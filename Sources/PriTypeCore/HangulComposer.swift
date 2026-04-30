import Cocoa
import LibHangul
import InputMethodKit

// Protocol and InputMode are now in HangulComposerTypes.swift
// Helper functions are now in CompositionHelpers.swift

// MARK: - HangulComposer

/// Core Hangul composition engine that wraps libhangul
///
/// `HangulComposer` handles the complete lifecycle of Hangul text input:
/// - Converting keystrokes to Hangul syllables
/// - Managing preedit (composition in progress) state
/// - Committing finalized text
/// - Switching between Korean and English modes
///
/// ## Overview
/// The composer uses `libhangul`'s `HangulInputContext` internally to perform
/// the actual character composition according to Korean keyboard layouts.
///
/// ## Usage
/// ```swift
/// let composer = HangulComposer()
/// let handled = composer.handle(keyEvent, delegate: myDelegate)
/// ```
///
/// ## Thread Safety
/// This class is not thread-safe. All calls should be made from the main thread.
public class HangulComposer {
    
    // MARK: - Public Properties
    
    /// The current input mode (Korean or English)
    ///
    /// When in `.english` mode, all keystrokes are passed through unchanged.
    public private(set) var inputMode: InputMode = .korean
    
    // MARK: - Dependencies
    
    /// Status bar updater (injected for testability)
    private let statusBar: StatusBarUpdating
    
    /// Configuration provider (injected for testability)
    private let configuration: ConfigurationProviding
    
    // MARK: - Private Properties
    
    /// Track last delegate for external toggle calls
    private weak var lastDelegate: (any HangulComposerDelegate)?
    
    /// Strong reference to the most recent adapter for Hanja lookup.
    /// Unlike lastDelegate (weak) and PriTypeInputController.currentAdapter,
    /// this survives IMK controller deallocation which happens frequently
    /// in Electron apps (Chrome, VS Code).
    /// Released with a 2-second delay when replaced, to allow async Hanja callbacks to finish.
    private var lastStrongDelegate: (any HangulComposerDelegate)?
    
    /// Pending release of previous strong delegate (delayed to allow async callbacks)
    private var pendingDelegateRelease: DispatchWorkItem?
    
    /// Whether Hanja candidate mode is currently active
    private var hanjaMode = false
    
    /// The Hangul key currently being looked up for Hanja conversion
    private var hanjaKey: String = ""
    
    /// Local cache of recently typed text (English mode primarily) to avoid IPC calls
    /// Maintains the last 15 characters to support auto-capitalization and double-space detection
    public private(set) var localTextBuffer: String = ""
    
    /// Maximum buffer size for local text tracking
    private let bufferMaxLength = 15
    
    /// Append text to the local buffer, trimming to max length
    private func appendToBuffer(_ text: String) {
        localTextBuffer.append(text)
        if localTextBuffer.count > bufferMaxLength {
            localTextBuffer = String(localTextBuffer.suffix(bufferMaxLength))
        }
    }
    
    // MARK: - libhangul Context
    // ThreadSafeHangulInputContext is thread-safe and supports synchronous calls.
    // It uses NSLock internally for synchronization.
    private var currentKeyboardId: String = PriTypeConfig.defaultKeyboardId
    private var context: ThreadSafeHangulInputContext = {
       let ctx = ThreadSafeHangulInputContext(keyboard: PriTypeConfig.defaultKeyboardId)
       DebugLogger.log("Configured context with 2-set (id: '\(PriTypeConfig.defaultKeyboardId)')")
       return ctx
    }()
    
    /// Text convenience handler (auto-capitalize, double-space period)
    /// Owns all state for text convenience features
    private let textConvenience = TextConvenienceHandler()
    
    // MARK: - Initialization
    
    /// Creates a new HangulComposer with default settings
    /// - Parameters:
    ///   - statusBar: Status bar updater (defaults to shared manager)
    ///   - configuration: Configuration provider (defaults to shared manager)
    public init(
        statusBar: StatusBarUpdating = StatusBarManager.shared,
        configuration: ConfigurationProviding = ConfigurationManager.shared
    ) {
        self.statusBar = statusBar
        self.configuration = configuration
        DebugLogger.log("HangulComposer init")
    }
    
    
    // MARK: - Public Methods
    
    /// Update the keyboard layout dynamically
    ///
    /// This method commits any in-progress composition before switching layouts
    /// to prevent text corruption.
    ///
    /// - Parameter id: The keyboard layout identifier (e.g., "2" for 두벌식, "3" for 세벌식)
    public func updateKeyboardLayout(id: String) {
        // Only re-create context if layout actually changed.
        // Electron apps trigger activateServer frequently, and re-creating
        // the context every time resets the composition state, causing the
        // first character to appear in English.
        guard currentKeyboardId != id else {
            DebugLogger.log("HangulComposer: Layout '\(id)' unchanged, skipping")
            return
        }
        
        DebugLogger.log("HangulComposer: Updating keyboard layout '\(currentKeyboardId)' -> '\(id)'")
        // Commit existing text before switching to avoid corruption
        if let delegate = lastDelegate, !context.isEmpty() {
            commitComposition(delegate: delegate)
        }
        
        // Re-initialize context with new keyboard ID
        currentKeyboardId = id
        context = ThreadSafeHangulInputContext(keyboard: id)
        localTextBuffer = ""
    }
    
    /// Toggle between Korean and English input modes
    ///
    /// This method:
    /// 1. Commits any in-progress composition
    /// 2. Switches the mode
    /// 3. Updates the status bar indicator
    ///
    /// Called externally by `RightCommandSuppressor` or `IOKitManager`.
    public func toggleInputMode() {
        DebugLogger.log("toggleInputMode called externally")
        
        // Commit any composition before switching
        if let delegate = lastDelegate, !context.isEmpty() {
            commitComposition(delegate: delegate)
            DebugLogger.log("Composition committed before mode switch")
        }
        
        switchMode()
    }
    
    // MARK: - Private Helpers
    
    /// Switch between Korean and English modes
    /// Centralizes mode switching logic to avoid duplication
    private func switchMode() {
        inputMode = inputMode.toggled
        statusBar.setMode(inputMode)
        DebugLogger.log("Mode switched to: \(inputMode)")
    }
    
    /// Handle special keys (Return, Escape, Space, Arrow, Tab, Backspace)
    /// - Returns: `nil` if not a special key, otherwise the result to return from handle()
    private func handleSpecialKey(keyCode: UInt16, delegate: HangulComposerDelegate) -> Bool? {
        // Return / Enter
        if keyCode == KeyCode.return || keyCode == KeyCode.numpadEnter {
            DebugLogger.log("Return key -> commit")
            commitComposition(delegate: delegate)
            return false  // Let system insert newline
        }
        
        // Escape - only consume if there's an active composition to cancel
        if keyCode == KeyCode.escape {
            if !context.isEmpty() {
                DebugLogger.log("Escape -> cancel composition")
                cancelComposition(delegate: delegate)
                return true
            }
            return false  // No composition, pass to system (e.g. Finder close dialog)
        }
        
        // Space - handle double-space period
        if keyCode == KeyCode.space {
            commitComposition(delegate: delegate)
            let result = textConvenience.handleDoubleSpacePeriod(buffer: &localTextBuffer, delegate: delegate, checkHangul: true)
            if result == .convertedToPeriod {
                DebugLogger.log("Double-space -> period (Korean mode)")
                return true
            }
            DebugLogger.log("Space -> flush and space")
            appendToBuffer(" ")
            return false
        }
        
        // Non-space: reset space state
        textConvenience.resetSpaceState()
        
        // Arrow keys
        if keyCode == KeyCode.leftArrow || keyCode == KeyCode.rightArrow ||
           keyCode == KeyCode.upArrow || keyCode == KeyCode.downArrow {
            DebugLogger.log("Arrow key -> commit and pass to system")
            commitComposition(delegate: delegate)
            return false
        }
        
        // Tab
        if keyCode == KeyCode.tab {
            DebugLogger.log("Tab key -> commit")
            commitComposition(delegate: delegate)
            return false
        }
        
        // Backspace
        if keyCode == KeyCode.backspace {
            DebugLogger.log("Backspace")
            if !localTextBuffer.isEmpty {
                localTextBuffer.removeLast()
            }
            if !context.isEmpty() {
                if context.backspace() {
                    DebugLogger.log("Engine backspace success")
                    updateComposition(delegate: delegate)
                    return true
                } else {
                    DebugLogger.log("Engine backspace caused empty")
                    updateComposition(delegate: delegate)
                    return true
                }
            }
            return false
        }
        
        return nil  // Not a special key
    }
    
    /// Process a single character through the Hangul engine
    /// - Returns: `true` if the character was processed, `false` if skipped
    private func processCharacter(_ char: Unicode.Scalar, delegate: HangulComposerDelegate) -> Bool {
        let charCode = UInt32(char.value)
        
        // Skip non-printable characters
        if KeyCode.shouldPassThrough(charCode) {
            return false
        }
        
        DebugLogger.logSensitive("Processing char code", sensitiveContent: "\(charCode)")
        
        // Primary attempt
        if context.process(Character(char)) {
            DebugLogger.log("Process success")
            updateComposition(delegate: delegate)
            return true
        }
        
        // Failure case - try committing first then retry
        DebugLogger.log("Process failed")
        
        if !context.isEmpty() {
            commitComposition(delegate: delegate)
        }
        
        // Retry with clean context
        if context.process(Character(char)) {
            DebugLogger.log("Retry success")
            updateComposition(delegate: delegate)
            return true
        }
        
        // Still failed - insert printable ASCII directly
        if KeyCode.isPrintableASCII(charCode) {
            DebugLogger.log("Retry failed, inserting printable char")
            delegate.insertText(String(char))
            appendToBuffer(String(char))
            return true
        }
        
        DebugLogger.log("Retry failed, skipping non-printable char")
        return false
    }
    
    /// Handle a keyboard event
    ///
    /// This is the main entry point for processing keyboard input. The method
    /// determines whether to process the event as Hangul input, pass it through
    /// to the system, or handle it as a special key (Return, Space, etc.).
    ///
    /// - Parameters:
    ///   - event: The `NSEvent` to process (must be `.keyDown`)
    ///   - delegate: The delegate to receive composition callbacks
    /// - Returns: `true` if the event was consumed, `false` if it should be passed to the system
    public func handle(_ event: NSEvent, delegate: HangulComposerDelegate) -> Bool {
        // Track delegate for external toggle calls
        self.lastDelegate = delegate
        
        // Delayed release of previous strong delegate to prevent indefinite retention
        // while keeping it alive long enough for async Hanja callbacks (2s window).
        // HOW IT WORKS: `oldDelegate` is captured strongly by the DispatchWorkItem closure.
        // This keeps the old adapter alive for 2 seconds even after `lastStrongDelegate`
        // is replaced. When the work item executes (or is cancelled), the captured
        // reference is released, allowing the old adapter to be deallocated.
        if lastStrongDelegate !== (delegate as AnyObject) {
            pendingDelegateRelease?.cancel()
            let oldDelegate = lastStrongDelegate  // Strong capture keeps it alive for 2s
            let releaseWork = DispatchWorkItem {
                _ = oldDelegate  // prevent compiler from optimizing away the capture
            }
            pendingDelegateRelease = releaseWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: releaseWork)
            self.lastStrongDelegate = delegate
        }
        
        // Only handle key down events for actual typing
        if event.type != .keyDown {
            return false
        }
        
        // Global context invalidation:
        // Any navigation or confirmation key (Arrow, Tab, Return) invalidates our local text context
        // because the cursor has likely moved, changing the text before it.
        let keyCode = event.keyCode
        if keyCode == KeyCode.leftArrow || keyCode == KeyCode.rightArrow ||
           keyCode == KeyCode.upArrow || keyCode == KeyCode.downArrow ||
           keyCode == KeyCode.tab || keyCode == KeyCode.return || keyCode == KeyCode.numpadEnter {
            localTextBuffer = ""
        }
        
        // Control+Space: Language toggle (only if enabled in settings)
        if event.keyCode == KeyCode.space && event.modifierFlags.contains(.control) 
            && configuration.controlSpaceAsToggle {
            DebugLogger.log("Control+Space -> Toggle mode")
            
            // Commit any composition before switching (preserve text)
            if !context.isEmpty() {
                commitComposition(delegate: delegate)
                DebugLogger.log("Composition committed before mode switch")
            }
            
            switchMode()
            return true  // Consume the event
        }
        
        // English mode: delegate to TextConvenienceHandler
        if inputMode == .english {
            DebugLogger.log("English mode")
            
            guard let chars = event.characters, chars.count == 1, let char = chars.first else {
                return false
            }
            
            // Do not process or append non-printable characters (e.g., arrow keys) in English mode
            if let firstScalar = chars.unicodeScalars.first, KeyCode.shouldPassThrough(UInt32(firstScalar.value)) {
                return false
            }
            
            let result = textConvenience.handleEnglishModeInput(char: char, buffer: &localTextBuffer, delegate: delegate)
            
            // If passThrough, we still need to track it in our buffer
            if result == .passThrough {
                appendToBuffer(String(char))
            }
            return result == .handled
        }
        
        // If Hanja candidate window is visible, forward keys to it
        if hanjaMode {
            let consumed = HanjaCandidateWindow.shared.handleKey(event)
            if !HanjaCandidateWindow.shared.isVisible {
                hanjaMode = false
                hanjaKey = ""
            }
            return consumed
        }
        
        // Option key: no longer intercepted here.
        // Right Option key is handled via CGEventTap in RightCommandSuppressor.
        // Pass through if modifiers (Command, Control, Option) are present
        // This ensures system shortcuts work correctly without interference
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
             // Commit any in-progress composition first. Otherwise marked text stays
             // live and the host app ignores or misapplies the shortcut (e.g. Cmd+←).
             if !context.isEmpty() {
                 commitComposition(delegate: delegate)
                 delegate.setMarkedText("")
             }
             localTextBuffer = "" // Any system shortcut (Cmd+V, Cmd+Z, etc.) invalidates local context
             return false
        }
        
        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }
        
        let inputCharacters = characters
        
        // Handle special keys (Return, Escape, Space, Arrow, Tab, Backspace)
        if let result = handleSpecialKey(keyCode: keyCode, delegate: delegate) {
            return result
        }
        
        // 2. Alphanumeric Keys (Typing)
        DebugLogger.logSensitive("Handle key code \(keyCode)", sensitiveContent: inputCharacters)
        
        // Filter: If input contains non-printable characters (e.g., function keys, arrows)
        // This catches Fn+Arrow (Home/End/PageUp/PageDown) and other navigation keys
        // that don't match the KeyCode enum in handleSpecialKey.
        if let firstScalar = inputCharacters.unicodeScalars.first {
            let firstCharCode = UInt32(firstScalar.value)
            if KeyCode.shouldPassThrough(firstCharCode) {
                DebugLogger.log("Non-printable key detected, passing to system")
                if !context.isEmpty() {
                    commitComposition(delegate: delegate)
                    delegate.setMarkedText("")
                }
                localTextBuffer = ""
                return false
            }
        }
        
        var handledAtLeastOnce = false
        
        for char in inputCharacters.unicodeScalars {
            if processCharacter(char, delegate: delegate) {
                handledAtLeastOnce = true
            }
        }
        
        // If we processed anything, we return true to stop system from handling duplicates.
        return handledAtLeastOnce
    }
    
    /// Updates the marked text and commits any finalized text
    ///
    /// This method retrieves the current preedit (composition in progress) and commit
    /// strings from libhangul, then updates the delegate accordingly:
    /// - Committed text is inserted immediately
    /// - Preedit text replaces the current marked text
    ///
    /// - Parameter delegate: The delegate to receive composition updates
    private func updateComposition(delegate: HangulComposerDelegate) {
        let preedit = context.getPreeditString()
        let commit = context.getCommitString()
        
        // If there is committed text, insert it first
        if !commit.isEmpty {
            let finalStr = CompositionHelpers.convertAndNormalize(commit)
            delegate.insertText(finalStr)
            appendToBuffer(finalStr)
        }
        
        // Update preedit text
        if !preedit.isEmpty {
            let preeditStr = CompositionHelpers.normalizeJamoForDisplay(preedit)
            delegate.setMarkedText(preeditStr)
        } else {
             delegate.setMarkedText("")
        }
    }
    
    /// Commits the current composition by flushing the libhangul context
    ///
    /// Flushes all pending text from the context and inserts it as finalized text.
    /// The committed string is normalized using precomposed canonical mapping to
    /// ensure proper Unicode representation.
    ///
    /// - Parameter delegate: The delegate to receive the committed text
    private func commitComposition(delegate: HangulComposerDelegate) {
        // Flush context
        let flushed = context.flush()
        let commitStr = CompositionHelpers.convertToString(flushed)
        
        DebugLogger.logSensitive("commitComposition flushed=\(flushed)", sensitiveContent: "'\(commitStr)'")
        
        if !commitStr.isEmpty {
            // insertText replaces the marked text automatically
            let finalStr = CompositionHelpers.convertAndNormalize(flushed)
            delegate.insertText(finalStr)
            appendToBuffer(finalStr)
            DebugLogger.logSensitive("commitComposition inserted", sensitiveContent: "'\(commitStr)'")
        }
    }

    /// Cancels the current composition without committing
    ///
    /// Resets the libhangul context and clears the marked text display.
    /// Use this when the user explicitly cancels input (e.g., pressing Escape).
    ///
    /// - Parameter delegate: The delegate to receive the cleared state
    private func cancelComposition(delegate: HangulComposerDelegate) {
        context.reset()
        delegate.setMarkedText("")
        // Do NOT clear localTextBuffer on cancel, as previously committed text is still valid context
    }
    
    /// Force commit any in-progress composition
    ///
    /// Called when the input method is about to be deactivated or when
    /// text needs to be finalized immediately (e.g., before window switch).
    ///
    /// - Parameter delegate: The delegate to receive the committed text
    public func forceCommit(delegate: HangulComposerDelegate) {
        commitComposition(delegate: delegate)
        // Preserve the last Hangul character for Hanja lookup.
        // Electron apps (Chrome, VS Code) trigger frequent deactivateServer calls
        // which call forceCommit. Clearing the entire buffer makes Hanja lookup impossible.
        if let lastChar = localTextBuffer.last, lastChar.isHangulChar {
            localTextBuffer = String(lastChar)
        } else {
            localTextBuffer = ""
        }
    }
    
    /// Reset the composition state
    ///
    /// Clears any in-progress composition without committing it.
    /// Use this when composition should be discarded (e.g., after Escape key).
    ///
    /// - Parameter delegate: The delegate to receive the cleared marked text
    public func reset(delegate: HangulComposerDelegate) {
        context.reset()
        delegate.setMarkedText("")
        delegate.insertText("") 
        localTextBuffer = ""
    }
    
    /// Clear the local text buffer without affecting composition state.
    public func clearLocalBuffer() {
        localTextBuffer = ""
    }
    
    /// Bundle ID of the app where the last keystroke was processed.
    /// Used to prevent cross-app hanja leaking: if the current app differs from
    /// the app that populated localTextBuffer, the buffer is considered stale.
    private var lastInputBundleId: String = ""
    
    /// Record which app the current keystroke is from (called from handle via controller)
    public func markKeystroke(bundleId: String) {
        lastInputBundleId = bundleId
    }
    
    /// Check if the buffer belongs to the given app
    public func isBufferFromApp(_ bundleId: String) -> Bool {
        return !lastInputBundleId.isEmpty && lastInputBundleId == bundleId
    }
    
    // MARK: - Hanja Lookup
    
    /// Trigger Hanja lookup externally (called by RightCommandSuppressor via CGEventTap)
    ///
    /// This is the public entry point for Hanja conversion.
    /// Acts as a toggle: dismisses if already visible, opens if not.
    public func triggerHanjaLookup() {
        // Toggle behavior: if already showing, dismiss
        if HanjaCandidateWindow.shared.isVisible {
            HanjaCandidateWindow.shared.dismiss()
            hanjaMode = false
            hanjaKey = ""
            DebugLogger.log("Hanja: Toggled off")
            return
        }
        
        // Use the active controller's current adapter, fallback to strong delegate on composer
        let activeDelegate = PriTypeInputController.sharedController?.currentAdapter
            ?? lastStrongDelegate
            ?? lastDelegate
        guard let delegate = activeDelegate else {
            DebugLogger.log("Hanja: No delegate available")
            return
        }
        _ = handleHanjaLookup(delegate: delegate)
    }
    
    /// Handle Option key to trigger Hanja candidate lookup
    /// Searches based on the current preedit (composing) text, or the last committed Hangul character
    private func handleHanjaLookup(delegate: HangulComposerDelegate) -> Bool {
        guard inputMode == .korean else {
            DebugLogger.log("Hanja: Not in Korean mode, skipping")
            return false
        }
        
        // Search key: only use OWNED state (preedit or localTextBuffer).
        // Previously we had fallback strategies using textBeforeCursor/attributedSubstring,
        // but those pick up existing text in the field that wasn't just typed,
        // causing false-positive hanja windows in Chromium/Electron apps.
        var searchKey = ""
        var hadPreedit = false
        
        // Strategy 1: Current preedit (composing text) — most reliable
        let preedit = context.getPreeditString()
        let preeditStr = CompositionHelpers.convertAndNormalize(preedit)
        
        if !preeditStr.isEmpty {
            searchKey = preeditStr
            hadPreedit = true
            DebugLogger.log("Hanja: searchKey from preedit: '\(searchKey)'")
        }
        
        // Strategy 2: localTextBuffer (last typed character) — only if from the same app
        // Cross-app check: if the current focused app differs from the app that populated
        // the buffer, the buffer content is stale and should not trigger hanja.
        if searchKey.isEmpty {
            let currentBundleId = PriTypeInputController.sharedController?.cachedContext?.bundleId
                ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            if isBufferFromApp(currentBundleId),
               let lastChar = localTextBuffer.last, lastChar.isHangulChar {
                searchKey = String(lastChar)
                DebugLogger.log("Hanja: searchKey from localTextBuffer: '\(searchKey)'")
            }
        }
        
        guard !searchKey.isEmpty else {
            DebugLogger.log("Hanja: No Hangul text to look up (buffer='\(localTextBuffer)', preedit='\(preeditStr)')")
            return true // Consume the key but don't open the window
        }
        
        let entries = HanjaManager.shared.search(key: searchKey)
        guard !entries.isEmpty else {
            DebugLogger.log("Hanja: No results for '\(searchKey)'")
            return true
        }
        
        DebugLogger.log("Hanja: Found \(entries.count) entries for '\(searchKey)'")
        
        hanjaMode = true
        hanjaKey = searchKey
        
        // IMPORTANT: Capture cursor position BEFORE commit.
        // Chromium/Electron apps update cursor position asynchronously after commit,
        // so firstRect() returns garbage values if called after commitComposition().
        // While preedit is active, the cursor is at the marked text position → valid coordinates.
        var cursorRect = NSRect(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y - 20, width: 0, height: 20)
        
        if let controller = PriTypeInputController.sharedController,
           let client = controller.client() as? IMKTextInput {
            var actualRange = NSRange()
            let rect = client.firstRect(forCharacterRange: client.selectedRange(), actualRange: &actualRange)
            
            if Self.isValidCursorRect(rect) {
                cursorRect = rect
                DebugLogger.log("Hanja: cursor from firstRect (pre-commit): \(rect)")
            } else {
                // Fallback: Use Accessibility API to get caret position
                // Chromium/Electron apps have broken IMK firstRect but support AX well
                if let axRect = Self.getCursorRectViaAccessibility() {
                    cursorRect = axRect
                    DebugLogger.log("Hanja: cursor from Accessibility API: \(axRect)")
                } else {
                    DebugLogger.log("Hanja: firstRect invalid (\(rect)), AX unavailable, using mouse location")
                }
            }
        }
        
        // Commit preedit AFTER capturing cursor position
        if hadPreedit {
            commitComposition(delegate: delegate)
        }
        
        // Capture the hanjaKey length for use in the callback
        let replacementLength = searchKey.utf16.count
        
        // Snapshot: Capture client identity at show time for validation at select time.
        // If focus changes while the candidate window is open, the snapshot client
        // will differ from the current active client, preventing incorrect text insertion.
        weak var snapshotClient = (PriTypeInputController.sharedController?.client() as? IMKTextInput)
        
        HanjaCandidateWindow.shared.show(
            entries: entries,
            cursorRect: cursorRect,
            onSelect: { [weak self] entry in
                guard let self = self else { return }
                
                // Validate: Ensure the client hasn't changed since the candidate window was shown
                if let controller = PriTypeInputController.sharedController,
                   let client = controller.client() as? IMKTextInput {
                    
                    // Safety check: if the client object changed (focus switched), dismiss silently
                    if let originalClient = snapshotClient,
                       originalClient !== (client as AnyObject) {
                        DebugLogger.log("Hanja: Client changed since show — aborting selection")
                        self.hanjaMode = false
                        self.hanjaKey = ""
                        return
                    }
                    
                    let selRange = client.selectedRange()
                    if selRange.location != NSNotFound && selRange.location >= replacementLength {
                        let replaceRange = NSRange(location: selRange.location - replacementLength, length: replacementLength)
                        client.insertText(entry.hanja, replacementRange: replaceRange)
                    } else {
                        // Fallback: just insert
                        client.insertText(entry.hanja, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                    }
                }
                
                self.localTextBuffer = String(self.localTextBuffer.dropLast(self.hanjaKey.count)) + entry.hanja
                self.hanjaMode = false
                self.hanjaKey = ""
                DebugLogger.log("Hanja: Selected '\(entry.hanja)' (\(entry.meaning))")
            },
            onDismiss: { [weak self] in
                self?.hanjaMode = false
                self?.hanjaKey = ""
                DebugLogger.log("Hanja: Dismissed")
            }
        )
        
        return true
    }
    
    // MARK: - Cursor Position Validation
    
    /// Validate that a rect from firstRect is a usable cursor position
    /// Electron/Chromium apps can return garbage values (e.g. x=1.6e-314, y=19896)
    private static func isValidCursorRect(_ rect: NSRect) -> Bool {
        // Reject zero origin (uninitialized)
        guard rect.origin.x != 0 || rect.origin.y != 0 else { return false }
        // Reject negative or zero height (malformed)
        guard rect.size.height > 0 else { return false }
        // Reject absurdly small coordinates (floating point garbage like 1.6e-314)
        guard rect.origin.x > 1 && rect.origin.y > 1 else { return false }
        // Check that the point is on any connected screen
        return NSScreen.screens.contains { screen in
            screen.frame.contains(NSPoint(x: rect.origin.x, y: rect.origin.y))
        }
    }
    
    // MARK: - Accessibility API Cursor Position
    
    /// Get cursor position via macOS Accessibility API
    /// Chromium/Electron apps have broken IMK firstRect but properly implement AX text attributes.
    /// Uses AXSelectedTextRange → AXBoundsForRange to get the caret's screen coordinates.
    ///
    /// - Returns: NSRect of the caret position in screen coordinates (bottom-left origin), or nil if unavailable
    private static func getCursorRectViaAccessibility() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()
        
        // Get the currently focused UI element
        var focusedElement: AnyObject?
        var focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        // Fallback: If system-wide focused element fails (common in Chromium intermittently),
        // try going through the focused application instead
        if focusResult != .success || focusedElement == nil {
            DebugLogger.log("Hanja AX: systemWide focusedElement failed (\(focusResult.rawValue)), trying app path")
            
            var focusedApp: AnyObject?
            if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
               let app = focusedApp {
                let appElement = app as! AXUIElement
                focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
                if focusResult != .success {
                    DebugLogger.log("Hanja AX: app focusedElement also failed (\(focusResult.rawValue))")
                    return nil
                }
            } else {
                DebugLogger.log("Hanja AX: focusedApplication also failed")
                return nil
            }
        }
        
        guard let element = focusedElement else { return nil }
        let axElement = element as! AXUIElement
        
        // Strategy 1: AXSelectedTextRange → AXBoundsForRange
        if let rect = getBoundsForSelectedText(axElement) {
            return rect
        }
        
        // Strategy 2: Use element's AXPosition + AXSize as approximation
        // The focused element itself (e.g. text area) gives us a reasonable position
        if let rect = getElementCaretPosition(axElement) {
            return rect
        }
        
        DebugLogger.log("Hanja AX: all strategies failed")
        return nil
    }
    
    /// Try to get caret bounds via AXBoundsForRange
    private static func getBoundsForSelectedText(_ axElement: AXUIElement) -> NSRect? {
        // Get the selected text range (caret position)
        var selectedRangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        guard rangeResult == .success, let rangeVal = selectedRangeValue else {
            DebugLogger.log("Hanja AX: selectedTextRange failed (\(rangeResult.rawValue))")
            return nil
        }
        
        // Extract the CFRange to check if we have a zero-length selection (caret)
        var cfRange = CFRange(location: 0, length: 0)
        AXValueGetValue(rangeVal as! AXValue, .cfRange, &cfRange)
        
        // If caret is at position > 0, try bounds for the character BEFORE caret
        // This often works better than bounds for a zero-length range
        let queryRange: AnyObject
        if cfRange.length == 0 && cfRange.location > 0 {
            var charRange = CFRange(location: cfRange.location - 1, length: 1)
            queryRange = AXValueCreate(.cfRange, &charRange)! as AnyObject
        } else {
            queryRange = rangeVal
        }
        
        // Get the bounds for this text range
        var boundsValue: AnyObject?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            axElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            queryRange,
            &boundsValue
        )
        guard boundsResult == .success, let boundsVal = boundsValue else {
            DebugLogger.log("Hanja AX: boundsForRange failed (\(boundsResult.rawValue))")
            return nil
        }
        
        // Convert AXValue to CGRect
        var bounds = CGRect.zero
        guard AXValueGetValue(boundsVal as! AXValue, .cgRect, &bounds) else {
            DebugLogger.log("Hanja AX: AXValueGetValue failed")
            return nil
        }
        
        DebugLogger.log("Hanja AX: raw bounds = \(bounds)")
        
        // Chrome returns (0, y, 0, 0) — only y is valid, in AX top-left coordinates
        // If we have a valid y but x/width/height are zero, supplement from element position
        if bounds.size.width == 0 && bounds.size.height == 0 && bounds.origin.y > 0 {
            // Get the element's position to supplement x coordinate
            var posValue: AnyObject?
            if AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &posValue) == .success,
               let pv = posValue {
                var pos = CGPoint.zero
                AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
                
                // bounds.origin.y is AX coord (top-left origin), convert to screen (bottom-left)
                let defaultHeight: CGFloat = 18
                guard let screenHeight = NSScreen.main?.frame.height else { return nil }
                let flippedY = screenHeight - bounds.origin.y - defaultHeight
                
                // If flippedY is valid (on-screen), use it; otherwise try element-based fallback
                if flippedY >= 0 {
                    let result = NSRect(x: pos.x, y: flippedY, width: 0, height: defaultHeight)
                    DebugLogger.log("Hanja AX: Chrome partial → (x=element, y=AXBounds): \(result)")
                    if isValidCursorRect(result) { return result }
                }
                
                // Chrome's y may reference the text field's internal y, not screen y.
                // Try: use element position's y and offset by (bounds.y - element y) if within element
                let elementBottomAX = pos.y + 20  // approximate line height from element top
                let altFlippedY = screenHeight - elementBottomAX
                if altFlippedY >= 0 {
                    let result = NSRect(x: pos.x, y: altFlippedY, width: 0, height: defaultHeight)
                    DebugLogger.log("Hanja AX: Chrome partial → element-offset fallback: \(result)")
                    if isValidCursorRect(result) { return result }
                }
                
                DebugLogger.log("Hanja AX: Chrome partial failed (flippedY=\(flippedY))")
            }
        }
        
        // Normal case: full bounds available
        guard let screenHeight = NSScreen.main?.frame.height else { return nil }
        let flippedY = screenHeight - bounds.origin.y - bounds.size.height
        let result = NSRect(x: bounds.origin.x, y: flippedY, width: bounds.size.width, height: bounds.size.height)
        
        guard isValidCursorRect(result) else {
            DebugLogger.log("Hanja AX: converted rect invalid: \(result)")
            return nil
        }
        
        return result
    }
    
    /// Fallback: use element's AXPosition to approximate caret location
    private static func getElementCaretPosition(_ axElement: AXUIElement) -> NSRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        
        guard AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let pv = posValue, let sv = sizeValue else {
            DebugLogger.log("Hanja AX: element position/size unavailable")
            return nil
        }
        
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        
        // Use the bottom-left of the element as a rough caret position
        guard let screenHeight = NSScreen.main?.frame.height else { return nil }
        let defaultHeight: CGFloat = 18
        // Place at element's x, and bottom of element (y + height in AX coords)
        let axBottom = pos.y + size.height
        let flippedY = screenHeight - axBottom
        let result = NSRect(x: pos.x, y: flippedY, width: 0, height: defaultHeight)
        
        DebugLogger.log("Hanja AX: element position fallback: \(result)")
        guard isValidCursorRect(result) else { return nil }
        return result
    }
}

// MARK: - Character Extension for Hangul detection
extension Character {
    var isHangulChar: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        // Hangul Syllables: U+AC00 - U+D7A3
        // Hangul Jamo: U+1100 - U+11FF
        // Hangul Compatibility Jamo: U+3130 - U+318F
        let v = scalar.value
        return (v >= 0xAC00 && v <= 0xD7A3) ||
               (v >= 0x1100 && v <= 0x11FF) ||
               (v >= 0x3130 && v <= 0x318F)
    }
}
