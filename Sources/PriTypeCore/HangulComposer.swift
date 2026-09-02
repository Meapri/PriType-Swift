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
/// - Applying Korean or English mode selected by the IMK controller
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
public class HangulComposer: @unchecked Sendable {
    
    // MARK: - Public Properties
    
    /// The current input mode (Korean or English)
    ///
    /// When in `.english` mode, all keystrokes are passed through unchanged.
    public private(set) var inputMode: InputMode = .korean

    /// Whether the underlying Hangul engine currently has active composition.
    public var hasActiveComposition: Bool {
        !context.isEmpty()
    }
    
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
    
    /// Local cache of recently typed text to support double-space detection and Hanja lookup
    public var localTextBuffer: String = ""
    
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
    /// Active keyboard layout id ("2" 두벌식, "3" 세벌식, ...). Exposed so the
    /// controller can finalize through the session BEFORE a layout switch.
    public private(set) var keyboardLayoutId: String = PriTypeConfig.defaultKeyboardId
    private var context: ThreadSafeHangulInputContext = {
       let ctx = ThreadSafeHangulInputContext(keyboard: PriTypeConfig.defaultKeyboardId)
       DebugLogger.log("Configured context with 2-set (id: '\(PriTypeConfig.defaultKeyboardId)')")
       return ctx
    }()
    
    /// Text convenience handler (double-space period)
    /// Owns all state for text convenience features
    private let textConvenience: TextConvenienceHandler
    
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
        self.textConvenience = TextConvenienceHandler(
            isDoubleSpacePeriodEnabled: {
                configuration.doubleSpacePeriodEnabled
            },
            isAutoCapitalizationEnabled: {
                configuration.autoCapitalizationEnabled
            },
            isSmartQuoteSubstitutionEnabled: {
                configuration.smartQuoteSubstitutionEnabled
            },
            isSmartDashSubstitutionEnabled: {
                configuration.smartDashSubstitutionEnabled
            }
        )
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
        guard keyboardLayoutId != id else {
            return
        }
        
        DebugLogger.log("HangulComposer: Updating keyboard layout '\(keyboardLayoutId)' -> '\(id)'")
        // Commit existing text before switching to avoid corruption
        if let delegate = lastDelegate, !context.isEmpty() {
            commitComposition(delegate: delegate)
        }
        
        // Re-initialize context with new keyboard ID
        keyboardLayoutId = id
        context = ThreadSafeHangulInputContext(keyboard: id)
        localTextBuffer = ""
    }
    
    /// Set Korean or English mode from the PriType controller.
    ///
    /// Custom toggle keys are coordinated by `InputModeCoordinator` and
    /// `PriTypeInputController` before reaching this method. Caps Lock language
    /// switching also arrives through the controller as an IMK input-mode value
    /// change.
    /// - Important: `inputMode` is the single source of truth for the Korean/
    ///   English state. The only sanctioned writers are
    ///   `PriTypeInputController.performPriTypeModeTransition` (custom toggle) and
    ///   `PriTypeInputController.setValue(_:forTag:)` (macOS selecting a PriType
    ///   mode, including the English child mode). No other path — including
    ///   `activateServer` focus changes — may mutate the mode.
    public func setInputMode(_ mode: InputMode) {
        guard inputMode != mode else {
            return
        }

        DebugLogger.log("setInputMode called externally: \(mode)")

        hanjaMode = false
        hanjaKey = ""
        if Thread.isMainThread, HanjaCandidateWindow.shared.isVisible {
            HanjaCandidateWindow.shared.dismiss()
        }

        if let delegate = lastDelegate, !context.isEmpty() {
            commitComposition(delegate: delegate)
            DebugLogger.log("Composition committed before explicit mode switch")
        }

        inputMode = mode
        localTextBuffer = ""
        textConvenience.resetSpaceState()
        statusBar.setMode(inputMode)
        DebugLogger.log("Mode set to: \(inputMode)")
    }

    // MARK: - Private Helpers
    
    /// Handle special keys (Return, Escape, Space, Arrow, Tab, Backspace)
    /// - Returns: `nil` if not a special key, otherwise the result to return from handle()
    private func handleSpecialKey(keyCode: UInt16, delegate: HangulComposerDelegate) -> Bool? {
        // Return / Enter
        if keyCode == KeyCode.return || keyCode == KeyCode.numpadEnter {
            let hadComposition = !context.isEmpty()
            commitComposition(delegate: delegate)
            if hadComposition {
                delegate.setMarkedText("")
            }
            localTextBuffer = ""

            if hadComposition && ClientCompatibilityPolicy.needsDirectNewlineAfterReturnCommit(bundleId: lastInputBundleId) {
                delegate.insertText("\n")
                DebugLogger.log("Return -> GoodNotes compatibility: inserted newline and consumed original Return")
                return true
            }

            if hadComposition && ClientCompatibilityPolicy.needsReturnConsumedAfterCompositionCommit(bundleId: lastInputBundleId) {
                DebugLogger.log("Return -> committed composition and consumed original Return for host compatibility")
                return true
            }

            DebugLogger.log("Return -> committed composition and passed original Return to app (hadComposition=\(hadComposition))")
            return false
        }
        
        // Escape - only consume if there's an active composition to cancel
        if keyCode == KeyCode.escape {
            if !context.isEmpty() {
                DebugLogger.log("Escape -> cancel composition")
                cancelComposition(delegate: delegate)
                localTextBuffer = ""
                return true
            }
            localTextBuffer = ""
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
            delegate.insertText(" ")
            appendToBuffer(" ")
            return true
        }
        
        // Non-space: reset space state
        textConvenience.resetSpaceState()
        
        // Arrow keys
        if keyCode == KeyCode.leftArrow || keyCode == KeyCode.rightArrow ||
           keyCode == KeyCode.upArrow || keyCode == KeyCode.downArrow {
            commitComposition(delegate: delegate)
            localTextBuffer = ""
            return false
        }
        
        // Tab
        if keyCode == KeyCode.tab {
            commitComposition(delegate: delegate)
            localTextBuffer = ""
            return false
        }
        
        // Backspace
        if keyCode == KeyCode.backspace {
            if !localTextBuffer.isEmpty {
                localTextBuffer.removeLast()
            }
            if !context.isEmpty() {
                if context.backspace() {
                    updateComposition(delegate: delegate)
                    return true
                } else {
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
        
        // Primary attempt
        if context.process(Character(char)) {
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
        
        // English mode stays inside the PriType input source but performs no
        // composition. Most keys pass through to the host app unchanged.
        // - Roman characters come from the keyboard layout that the controller
        //   installs via `overrideKeyboardWithKeyboardNamed(ABC/US)`.
        // - Some macOS text conveniences do not fire for this internal English
        //   mode in every host, so PriType supplies a narrow fallback for only
        //   the transformed cases (double-space period, and auto-capitalization
        //   after an explicit sentence end — never for empty/unknown cursor context).
        // Keeping this path mostly pass-through avoids the classic buffer-vs-
        // cursor desync that a PriType-side English buffer invites.
        if inputMode == .english {
            if !context.isEmpty() {
                commitComposition(delegate: delegate)
                delegate.setMarkedText("")
            }
            localTextBuffer = ""
            if textConvenience.handleEnglishModeInput(event, delegate: delegate) {
                return true
            }
            return false
        }
        
        // If Hanja candidate window is visible, forward keys to it
        if hanjaMode {
            let consumed = HanjaCandidateWindow.shared.handleKey(event)
            if !HanjaCandidateWindow.shared.isVisible {
                hanjaMode = false
                hanjaKey = ""
            }
            if consumed {
                return true
            }
            // If not consumed (regular key dismissed the window),
            // fall through to normal key processing below so the
            // keystroke is handled by the Hangul composer instead
            // of being passed raw to the app (which would produce English).
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

        // ORDERING INVARIANT (load-bearing — do not reorder):
        // commit (insertText) MUST happen BEFORE the preedit update (setMarkedText).
        // This is the macOS equivalent of the Windows Korean IME model — only the
        // single in-progress syllable is ever "marked", and the previous syllable is
        // committed the instant libhangul emits it on a syllable boundary. Reordering
        // (mark-before-commit) reintroduces stale-cursor preedit (cf. kitty #4219) and
        // breaks the experimental DirectInsertionAdapter, which relies on insertText
        // arriving first to finalize the live preedit before the new one is rendered.
        // See Docs/KoreanWindowsInputFeasibility.md (Phase 0/1).
        if !commit.isEmpty {
            let finalStr = CompositionHelpers.convertAndNormalize(commit)
            delegate.insertText(finalStr)
            appendToBuffer(finalStr)
        }

        // Update preedit text (the single live syllable).
        if !preedit.isEmpty {
            let preeditStr: String
            if ClientCompatibilityPolicy.prefersRawJamoPreedit(bundleId: lastInputBundleId) {
                // Keep U+1100 choseong so web hosts do not compositionend after the
                // first jamo (compatibility U+3131 looks like a finished letter).
                preeditStr = CompositionHelpers.convertToString(preedit)
            } else {
                preeditStr = CompositionHelpers.normalizeJamoForDisplay(preedit)
            }
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

    /// Flush any in-progress composition and return its committed NFC string ("" if none).
    ///
    /// Unlike `forceCommit`, this does NOT insert via a delegate — the caller inserts the
    /// returned text itself. `deactivateServer` uses this to commit straight to the
    /// deactivating client with an explicit `replacementRange` over the marked text, which
    /// reliably clears a stranded preedit during a focus transition (some hosts, e.g.
    /// KakaoTalk, do not honor insertText's automatic marked-text replacement at that moment).
    public func flushCommitString() -> String {
        guard !context.isEmpty() else { return "" }
        let flushed = context.flush()
        let committed = CompositionHelpers.convertAndNormalize(flushed)
        if let lastChar = committed.last, lastChar.isHangulChar {
            localTextBuffer = String(lastChar)
        } else {
            localTextBuffer = ""
        }
        return committed
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

    /// Drops in-progress composition without touching the current client.
    ///
    /// Secure text fields must receive raw key events from the system. Calling
    /// `setMarkedText` or `insertText` while focus is inside a password field can
    /// trigger host-app warning beeps, so this reset intentionally has no delegate.
    public func discardCompositionForPassThrough() {
        context.reset()
        localTextBuffer = ""
        textConvenience.resetSpaceState()
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
            // Use NSWorkspace as the primary source of truth for frontmost app, because
            // cachedContext might be stale if the user clicked a non-text area in a new app.
            let currentBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                ?? PriTypeInputController.sharedController?.cachedContext?.bundleId ?? ""
            if isBufferFromApp(currentBundleId),
               let lastChar = localTextBuffer.last, lastChar.isHangulChar {
                searchKey = String(lastChar)
                DebugLogger.log("Hanja: searchKey from localTextBuffer: '\(searchKey)'")
            }
        }
        
        // Strategy 3: Read text before cursor if buffer is empty and no preedit
        // This handles cases where the user used arrow keys to move the cursor
        if searchKey.isEmpty {
            if let text = delegate.textBeforeCursor(length: 1), let lastChar = text.last, lastChar.isHangulChar {
                searchKey = String(lastChar)
                DebugLogger.log("Hanja: searchKey from textBeforeCursor: '\(searchKey)'")
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
        // While preedit is active, the cursor is at the marked text position → valid
        // coordinates. The strategy chain lives in CursorRectResolver.
        let cursorRect = CursorRectResolver.resolve(client: PriTypeInputController.sharedController?.client())

        // Commit preedit AFTER capturing cursor position
        if hadPreedit {
            commitComposition(delegate: delegate)
        }
        
        // Capture the hanjaKey length for use in the callback
        let replacementLength = searchKey.utf16.count
        
        // Snapshot: Capture client identity at show time for validation at select time.
        // Use ObjectIdentifier instead of weak reference: if the weak ref is deallocated,
        // validation would be skipped and hanja could be inserted into a wrong client.
        let snapshotClientID: ObjectIdentifier? = {
            if let client = PriTypeInputController.sharedController?.client() as? IMKTextInput {
                return ObjectIdentifier(client as AnyObject)
            }
            return nil
        }()
        
        HanjaCandidateWindow.shared.show(
            entries: entries,
            cursorRect: cursorRect,
            onSelect: { [weak self] entry in
                guard let self = self else { return }
                
                // Validate: Ensure the client hasn't changed since the candidate window was shown
                if let controller = PriTypeInputController.sharedController,
                   let client = controller.client() {
                    
                    // Safety check: if the client object changed (focus switched), dismiss silently
                    guard let originalID = snapshotClientID,
                          ObjectIdentifier(client as AnyObject) == originalID else {
                        DebugLogger.log("Hanja: Client changed since show — aborting selection")
                        self.hanjaMode = false
                        self.hanjaKey = ""
                        return
                    }
                    
                    let selRange = client.selectedRange()
                    if selRange.location != NSNotFound && selRange.location < 10000000 && selRange.location >= replacementLength {
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

    /// Forwarder kept for API stability (tests/benchmark). The implementation and
    /// the full coordinate strategy chain live in `CursorRectResolver`.
    public static func isValidCursorRect(_ rect: NSRect) -> Bool {
        CursorRectResolver.isValidCursorRect(rect)
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
