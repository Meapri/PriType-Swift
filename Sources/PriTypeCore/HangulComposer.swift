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
    
    /// Whether Hanja candidate mode is currently active
    private var hanjaMode = false
    
    /// The Hangul key currently being looked up for Hanja conversion
    private var hanjaKey: String = ""
    
    /// Local cache of recently typed text (English mode primarily) to avoid IPC calls
    /// Maintains the last 15 characters to support auto-capitalization and double-space detection
    public private(set) var localTextBuffer: String = ""
    
    // MARK: - libhangul Context
    // ThreadSafeHangulInputContext is thread-safe and supports synchronous calls.
    // It uses NSLock internally for synchronization.
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
        DebugLogger.log("HangulComposer: Updating keyboard layout to '\(id)'")
        // Commit existing text before switching to avoid corruption
        if let delegate = lastDelegate, !context.isEmpty() {
            commitComposition(delegate: delegate)
        }
        
        // Re-initialize context with new keyboard ID
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
            localTextBuffer.append(" ")
            if localTextBuffer.count > 15 { localTextBuffer = String(localTextBuffer.suffix(15)) }
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
            localTextBuffer.append(Character(char))
            if localTextBuffer.count > 15 { localTextBuffer = String(localTextBuffer.suffix(15)) }
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
                localTextBuffer.append(char)
                if localTextBuffer.count > 15 { localTextBuffer = String(localTextBuffer.suffix(15)) }
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
            let commitStr = CompositionHelpers.convertToString(commit)
            let finalStr = commitStr.precomposedStringWithCanonicalMapping
            delegate.insertText(finalStr)
            localTextBuffer.append(finalStr)
            if localTextBuffer.count > 15 { localTextBuffer = String(localTextBuffer.suffix(15)) }
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
            let finalStr = commitStr.precomposedStringWithCanonicalMapping
            delegate.insertText(finalStr)
            localTextBuffer.append(finalStr)
            if localTextBuffer.count > 15 { localTextBuffer = String(localTextBuffer.suffix(15)) }
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
        localTextBuffer = "" // External commit implies focus change or click, invalidate context
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
        
        guard let delegate = lastDelegate else {
            DebugLogger.log("Hanja: No delegate available")
            return
        }
        _ = handleHanjaLookup(delegate: delegate)
    }
    
    /// Handle Option key to trigger Hanja candidate lookup
    /// Searches based on the current preedit (composing) text, or the last committed Hangul character
    private func handleHanjaLookup(delegate: HangulComposerDelegate) -> Bool {
        guard inputMode == .korean else { return false }
        
        // Get the search key: prefer current preedit, fallback to last character in buffer
        var searchKey = ""
        var hadPreedit = false
        
        let preedit = context.getPreeditString()
        let preeditStr = CompositionHelpers.convertToString(preedit).precomposedStringWithCanonicalMapping
        
        if !preeditStr.isEmpty {
            searchKey = preeditStr
            hadPreedit = true
        } else if let lastChar = localTextBuffer.last, lastChar.isHangulChar {
            searchKey = String(lastChar)
        } else {
            // Try to read from the text field
            if let textBefore = delegate.textBeforeCursor(length: 1), !textBefore.isEmpty,
               let lastChar = textBefore.last, lastChar.isHangulChar {
                searchKey = String(lastChar)
            }
        }
        
        guard !searchKey.isEmpty else {
            DebugLogger.log("Hanja: No Hangul text to look up")
            return true // Consume the Option key
        }
        
        let entries = HanjaManager.shared.search(key: searchKey)
        guard !entries.isEmpty else {
            DebugLogger.log("Hanja: No results for '\(searchKey)'")
            return true
        }
        
        DebugLogger.log("Hanja: Found \(entries.count) entries for '\(searchKey)'")
        
        hanjaMode = true
        hanjaKey = searchKey
        
        // Commit preedit if it exists (so we can replace the committed character later)
        if hadPreedit {
            commitComposition(delegate: delegate)
        }
        
        // Get cursor position for window placement
        var cursorRect = NSRect(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y, width: 0, height: 20)
        
        if let controller = PriTypeInputController.sharedController,
           let client = controller.client() as? IMKTextInput {
            var actualRange = NSRange()
            let rect = client.firstRect(forCharacterRange: client.selectedRange(), actualRange: &actualRange)
            if rect.origin.x != 0 || rect.origin.y != 0 {
                cursorRect = rect
            }
        }
        
        // Capture the hanjaKey length for use in the callback
        let replacementLength = searchKey.utf16.count
        
        HanjaCandidateWindow.shared.show(
            entries: entries,
            cursorRect: cursorRect,
            onSelect: { [weak self] entry in
                guard let self = self else { return }
                
                // Use the current active client directly for reliable text replacement
                if let controller = PriTypeInputController.sharedController,
                   let client = controller.client() as? IMKTextInput {
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
