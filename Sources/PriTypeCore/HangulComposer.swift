import Cocoa
import LibHangul

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
        
        // Escape
        if keyCode == KeyCode.escape {
            DebugLogger.log("Escape -> cancel")
            cancelComposition(delegate: delegate)
            return true
        }
        
        // Space - handle double-space period
        if keyCode == KeyCode.space {
            commitComposition(delegate: delegate)
            let result = textConvenience.handleDoubleSpacePeriod(delegate: delegate, checkHangul: true)
            if result == .convertedToPeriod {
                DebugLogger.log("Double-space -> period (Korean mode)")
                return true
            }
            DebugLogger.log("Space -> flush and space")
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
        
        DebugLogger.log("Processing char code: \(charCode)")
        
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
        
        // Only handle key down events
        if event.type != .keyDown {
            return false
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
            
            let result = textConvenience.handleEnglishModeInput(char: char, delegate: delegate)
            return result == .handled
        }
        
        // Pass through if modifiers (Command, Control, Option) are present
        // This ensures system shortcuts work correctly without interference
        let significantModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(significantModifiers).isEmpty {
             return false
        }
        
        // Critical Fix: Caps Lock Passthrough
        // If Caps Lock is ON, we should NOT process input as Hangul.

        // Instead, commit any existing composition and let the system handle raw input (Uppercase English).
        if event.modifierFlags.contains(.capsLock) {
            if !context.isEmpty() {
                commitComposition(delegate: delegate)
            }
            return false
        }
        
        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }
        
        let inputCharacters = characters
        
        let keyCode = event.keyCode

        
        // Handle special keys (Return, Escape, Space, Arrow, Tab, Backspace)
        if let result = handleSpecialKey(keyCode: keyCode, delegate: delegate) {
            return result
        }
        
        // 2. Alphanumeric Keys (Typing)
        // We define "typing keys" as Printable ASCII usually.
        // For simplicity, let's process everything that has characters.
        
        DebugLogger.log("Handle key: \(inputCharacters) code: \(keyCode)")
        
        // Filter: If input contains non-printable characters (e.g., function keys, arrows)
        // Return false to pass to system.
        if let firstScalar = inputCharacters.unicodeScalars.first {
            let firstCharCode = UInt32(firstScalar.value)
            if KeyCode.shouldPassThrough(firstCharCode) {
                DebugLogger.log("Non-printable key detected, passing to system")
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
            delegate.insertText(commitStr.precomposedStringWithCanonicalMapping)
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
        
        DebugLogger.log("commitComposition: flushed=\(flushed), str='\(commitStr)'")
        
        if !commitStr.isEmpty {
            // insertText replaces the marked text automatically
            delegate.insertText(commitStr.precomposedStringWithCanonicalMapping)
            DebugLogger.log("commitComposition: inserted '\(commitStr)'")
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
    }
    
    /// Force commit any in-progress composition
    ///
    /// Called when the input method is about to be deactivated or when
    /// text needs to be finalized immediately (e.g., before window switch).
    ///
    /// - Parameter delegate: The delegate to receive the committed text
    public func forceCommit(delegate: HangulComposerDelegate) {
        commitComposition(delegate: delegate)
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
    }
}
