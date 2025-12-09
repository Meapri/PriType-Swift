import Cocoa
import LibHangul

// MARK: - Protocols

/// Protocol for receiving text composition events from `HangulComposer`
///
/// Implement this protocol to receive callbacks when the composer needs to
/// insert finalized text or update the in-progress composition (marked text).
///
/// ## Example Implementation
/// ```swift
/// class MyDelegate: HangulComposerDelegate {
///     func insertText(_ text: String) {
///         textView.insertText(text)
///     }
///     func setMarkedText(_ text: String) {
///         textView.setMarkedText(text)
///     }
/// }
/// ```
public protocol HangulComposerDelegate: AnyObject {
    /// Called when finalized text should be inserted
    /// - Parameter text: The text to insert (already composed Hangul syllables)
    func insertText(_ text: String)
    
    /// Called when the in-progress composition text should be displayed
    /// - Parameter text: The preedit text (incomplete Hangul being composed)
    func setMarkedText(_ text: String)
    
    /// Returns the text immediately before the current cursor position
    /// - Parameter length: Maximum length of text to retrieve
    /// - Returns: The text before cursor, or nil if unavailable
    func textBeforeCursor(length: Int) -> String?
}

// MARK: - Types

/// Input mode for the Hangul composer
///
/// The composer can operate in two modes:
/// - `korean`: Processes keystrokes as Hangul input
/// - `english`: Passes keystrokes through unchanged
public enum InputMode: Sendable {
    /// Korean input mode - keystrokes are processed as Hangul
    case korean
    /// English input mode - keystrokes pass through to system
    case english
}

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
    
    // MARK: - Private Properties
    
    /// Track last delegate for external toggle calls
    private weak var lastDelegate: (any HangulComposerDelegate)?
    
    /// The libhangul context for character composition
    @available(*, deprecated, message: "Intentionally using synchronous context")
    private var context: HangulInputContext = {
       let ctx = HangulInputContext(keyboard: PriTypeConfig.defaultKeyboardId)
       DebugLogger.log("Configured context with 2-set (id: '\(PriTypeConfig.defaultKeyboardId)')")
       return ctx
    }()
    
    // MARK: - Auto-Capitalize & Double-Space State (macOS-aligned)
    
    // MARK: - Auto-Capitalize & Double-Space State
    
    /// Track if last character was a space (for double-space detection & pending space)
    private var lastCharacterWasSpace: Bool = false
    
    // Note: Other state variables (sentenceEndedBeforeSpace, shouldCapitalizeNext, etc.) 
    // have been removed in favor of robust context-based detection.
    
    // MARK: - Helpers
    
    /// Determines if the next character should be auto-capitalized based on document context.
    /// Checks for: Start of document, Newline, or Sentence ending (. ! ?) followed by space.
    private func shouldAutoCapitalize(delegate: HangulComposerDelegate) -> Bool {
        // Read enough context (e.g. 5 chars) to detect patterns like ". " or "? "
        guard let text = delegate.textBeforeCursor(length: 5) else {
            return true  // Start of document -> Capitalize
        }
        
        if text.isEmpty { return true }
        
        // 1. Check for Newline (immediate capitalization)
        if let last = text.last {
            if last == "\n" || last == "\r" { return true }
        }
        
        // 2. Check for Sentence Ending Pattern
        // The pattern we look for is: [Punctuation] [Space(s)] [Cursor]
        // If the immediate preceding char is NOT a space, we are in the middle of a word -> No Cap.
        // Exception: If we are at the very start of a line/doc (already handled above).
        
        guard let lastChar = text.last, lastChar.isWhitespace else {
            return false // Cursor is right after a non-space char (e.g. "Hello." or "Word") -> No Cap
        }
        
        // Find the last non-whitespace character
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let lastNonSpace = trimmed.last {
            if lastNonSpace == "." || lastNonSpace == "!" || lastNonSpace == "?" {
                return true
            }
        }
        
        return false
    }
    
    /// Checks if a character is a Hangul syllable or Jamo
    private func isHangul(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let val = scalar.value
        // Hangul Syllables: AC00-D7A3
        // Hangul Compatibility Jamo: 3130-318F
        // Hangul Jamo: 1100-11FF
        return (val >= 0xAC00 && val <= 0xD7A3) ||
               (val >= 0x3130 && val <= 0x318F) ||
               (val >= 0x1100 && val <= 0x11FF)
    }
    
    // MARK: - Initialization
    
    /// Creates a new HangulComposer with default settings
    public init() {
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
        context = HangulInputContext(keyboard: id)
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
        
        inputMode = (inputMode == .korean) ? .english : .korean
        StatusBarManager.shared.setMode(inputMode)
        DebugLogger.log("Mode switched to: \(inputMode)")
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
            && ConfigurationManager.shared.controlSpaceAsToggle {
            DebugLogger.log("Control+Space -> Toggle mode")
            
            // Commit any composition before switching (preserve text)
            if !context.isEmpty() {
                commitComposition(delegate: delegate)
                DebugLogger.log("Composition committed before mode switch")
            }
            
            // Toggle mode
            inputMode = (inputMode == .korean) ? .english : .korean
            StatusBarManager.shared.setMode(inputMode)
            DebugLogger.log("Mode switched to: \(inputMode)")
            
            return true  // Consume the event
        }
        
        // English mode: handle auto-capitalize and double-space period (macOS-aligned)
        if inputMode == .english {
            DebugLogger.log("English mode")
            
            guard let chars = event.characters, chars.count == 1, let char = chars.first else {
                return false
            }
            
            // Handle space key
            if char == " " {
                // Double-space period: Only if enabled and we just typed a space
                // AND the character before that space was a word character (no punctuation)
                if ConfigurationManager.shared.doubleSpacePeriodEnabled && lastCharacterWasSpace {
                    // Check context to confirm valid double-space condition
                    // We need to look back: [WordChar] [Space] [Cursor]
                    if let context = delegate.textBeforeCursor(length: 2),
                       context.hasSuffix(" ") {
                        let preSpaceChar = context.dropLast().last
                        if let lastChar = preSpaceChar, (lastChar.isLetter || lastChar.isNumber) {
                            // Valid double-space condition!
                            // Replace previous space with ". "
                            delegate.setMarkedText("")   // Clear pending space
                            delegate.insertText(". ")    // Insert period + space
                            lastCharacterWasSpace = false
                            DebugLogger.log("Double-space -> period (Context validated)")
                            return true
                        }
                    }
                }
                
                // If double-space is enabled, hold the space as marked text
                if ConfigurationManager.shared.doubleSpacePeriodEnabled {
                    // Check if we should hold this space (only if following a word)
                    if let context = delegate.textBeforeCursor(length: 1),
                       let lastChar = context.last,
                       (lastChar.isLetter || lastChar.isNumber) {
                        delegate.setMarkedText(" ")  // Show space as pending
                        lastCharacterWasSpace = true
                        return true
                    }
                }
                
                // Normal space handling
                lastCharacterWasSpace = true
                return false
            }
            
            // Non-space character handling
            
            // Commit pending space if exists
            if lastCharacterWasSpace {
                delegate.setMarkedText("")
                delegate.insertText(" ")
            }
            lastCharacterWasSpace = false
            
            // Auto-capitalize: Only if enabled
            if ConfigurationManager.shared.autoCapitalizeEnabled && char.isLetter {
                if shouldAutoCapitalize(delegate: delegate) {
                    let uppercased = String(char).uppercased()
                    delegate.insertText(uppercased)
                    DebugLogger.log("Auto-capitalized: \(char) -> \(uppercased)")
                    return true
                }
            }
            
            return false  // Pass through to system
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

        
        // 1. Check for Special Keys
        // Return / Enter
        if keyCode == KeyCode.return || keyCode == KeyCode.numpadEnter {
             DebugLogger.log("Return key -> commit")
             commitComposition(delegate: delegate)
             // Return true to consume if we want to handle newline ourselves,
             // or return false to let system insert newline. 
             // Usually, committing is enough, and we let system do newline.
             return false 
        }
        
        // Escape
        if keyCode == KeyCode.escape {
             DebugLogger.log("Escape -> cancel")
             cancelComposition(delegate: delegate)
             return true
        }
        
        // Space
        if keyCode == KeyCode.space {
            // Double-space period: Only if enabled and we just typed a space
            if ConfigurationManager.shared.doubleSpacePeriodEnabled && lastCharacterWasSpace {
                // Check context to confirm valid double-space condition in Korean mode
                // Need to look back: [WordChar/Hangul] [Space] [Cursor]
                if let context = delegate.textBeforeCursor(length: 2),
                   context.hasSuffix(" ") {
                    let preSpaceChar = context.dropLast().last
                    if let lastChar = preSpaceChar,
                       (lastChar.isLetter || lastChar.isNumber || isHangul(lastChar)) {
                        // Valid double-space condition!
                        // Previous space was marked, now replace with ". "
                        delegate.setMarkedText("")    // Clear pending space
                        delegate.insertText(". ")     // Insert period + space
                        lastCharacterWasSpace = false
                        DebugLogger.log("Double-space -> period (Korean mode, Context validated)")
                        return true
                    }
                }
            }
            
            DebugLogger.log("Space -> flush and space")
            commitComposition(delegate: delegate)
            
            // If double-space is enabled, hold space as marked text
            // In Korean mode, we assume any committed hangul allows double-space
            if ConfigurationManager.shared.doubleSpacePeriodEnabled {
                // Check if we should hold this space (only if following a word)
                // Since we just committed (or context is there), check context
                // Note: commitComposition updates the client, so textBeforeCursor should see it.
                // However, IMKTextInput update might be async or delayed.
                // For simplicity/robustness, we can assume if we just committed Hangul, it's valid.
                // But safer to check context or just always pending-space in Korean mode?
                // Better to be consistent. Let's check context.
                if let context = delegate.textBeforeCursor(length: 1),
                   let lastChar = context.last,
                   (lastChar.isLetter || lastChar.isNumber || isHangul(lastChar)) {
                        delegate.setMarkedText(" ")
                        lastCharacterWasSpace = true
                        return true
                   }
            }
            
            lastCharacterWasSpace = true
            return false
        }
        
        // Non-space: commit pending space if exists
        if lastCharacterWasSpace {
            delegate.setMarkedText("")
            delegate.insertText(" ")
        }
        
        // Reset space tracking for non-space keys
        lastCharacterWasSpace = false
        
        // 방향키 - 조합 커밋 후 시스템에 전달
        if keyCode == KeyCode.leftArrow || keyCode == KeyCode.rightArrow ||
           keyCode == KeyCode.upArrow || keyCode == KeyCode.downArrow {
            DebugLogger.log("Arrow key -> commit and pass to system")
            commitComposition(delegate: delegate)
            return false // 시스템이 커서 이동 처리
        }
        
        // Tab 키 - 조합 커밋 후 시스템에 전달
        if keyCode == KeyCode.tab {
            DebugLogger.log("Tab key -> commit")
            commitComposition(delegate: delegate)
            return false
        }
        
        // Backspace
        if keyCode == KeyCode.backspace {
            DebugLogger.log("Backspace")
            // If composing, try to backspace within engine
            if !context.isEmpty() {
                 if context.backspace() {
                     DebugLogger.log("Engine backspace success")
                     updateComposition(delegate: delegate)
                     return true
                 } else {
                     // Empty context after backspace? reset UI
                     DebugLogger.log("Engine backspace caused empty")
                     updateComposition(delegate: delegate)
                     return true
                 }
            }
            // If not composing, return false to let system delete previous char
            return false
        }
        
        // 2. Alphanumeric Keys (Typing)
        // We define "typing keys" as Printable ASCII usually.
        // For simplicity, let's process everything that has characters.
        
        DebugLogger.log("Handle key: \(inputCharacters) code: \(keyCode)")
        
        // Filter: If input contains non-printable characters (e.g., function keys, arrows)
        // Return false to pass to system. Function keys often have charCode > 63000.
        // Printable ASCII is 32-126. We also allow extended for international.
        // However, we must NOT process function key codes at all.
        if let firstScalar = inputCharacters.unicodeScalars.first {
            let firstCharCode = Int(firstScalar.value)
            // Function keys and special keys have very high char codes (> 63000)
            // or are control characters (< 32, except for special handling)
            if firstCharCode >= 63000 || (firstCharCode < 32 && firstCharCode != 9 && firstCharCode != 10 && firstCharCode != 13) {
                DebugLogger.log("Non-printable key detected, passing to system")
                return false
            }
        }
        
        var handledAtLeastOnce = false
        
        for char in inputCharacters.unicodeScalars {
            let charCode = Int(char.value)
            
            // Skip non-printable characters in the loop as well
            if charCode >= 63000 || (charCode < 32 && charCode != 9 && charCode != 10 && charCode != 13) {
                continue
            }
            
            // Check if standard typing range (approx)
            // ASCII 33-126 are printable. 
            // In Hangul mode, we map mapped keys.
            // If it's a typing key, we MUST consume it (return true).
            // Fallback: If libhangul fails, we insert it manually.
            
            DebugLogger.log("Processing char code: \(charCode)")
            
            // Primary attempt
            if context.process(charCode) {
                DebugLogger.log("Process success")
                handledAtLeastOnce = true
                updateComposition(delegate: delegate)
            } else {
                // Failure case (e.g. invalid key for engine, or boundary)
                DebugLogger.log("Process failed")
                
                // If we have composition, commit it first (boundary case)
                if !context.isEmpty() {
                    commitComposition(delegate: delegate)
                }
                
                // Retry with clean context
                if context.process(charCode) {
                     DebugLogger.log("Retry success")
                     handledAtLeastOnce = true
                     updateComposition(delegate: delegate)
                } else {
                     // Still failed. It's an unprocessable char (e.g. maybe symbol not in map).
                     // ONLY insert if it's a printable character (32-126 or extended)
                     if charCode >= 32 && charCode < 127 {
                         DebugLogger.log("Retry failed, inserting printable char")
                         delegate.insertText(String(char))
                         handledAtLeastOnce = true
                     } else {
                         // Non-printable, skip insertion but still mark as handled
                         // to avoid leakage to system
                         DebugLogger.log("Retry failed, skipping non-printable char")
                     }
                }
            }
        }
        
        // If we processed anything, we return true to stop system from handling it duplicates.
        // We assume standard typing keys are processed.
        return handledAtLeastOnce
    }
    
    private func updateComposition(delegate: HangulComposerDelegate) {
        let preedit = context.getPreeditString()
        let commit = context.getCommitString()
        
        // If there is committed text, insert it first
        if !commit.isEmpty {
            let commitStr = String(commit.compactMap { UnicodeScalar($0) }.map { Character($0) })
            delegate.insertText(commitStr.precomposedStringWithCanonicalMapping)
        }
        
        // Update preedit text
        if !preedit.isEmpty {
            // Normalize: Map to Compatibility Jamo for better display (Windows-style)
            let scs = preedit.compactMap { UnicodeScalar($0) }
            let mapped = scs.map { scalar in
                 let val = scalar.value
                 // 1. Try standard helper (covers Choseong/Jungseong)
                 let stdMapped = HangulCharacter.jamoToCJamo(val)
                 if stdMapped != val { return UnicodeScalar(stdMapped) ?? scalar }
                 
                 // 2. Use unified JamoMapper for all Jamo types
                 if let compat = JamoMapper.toCompatibilityJamo(val) {
                     return UnicodeScalar(compat) ?? scalar
                 }
                 
                 return scalar
            }
            let preeditStr = String(mapped.map { Character($0) })
            delegate.setMarkedText(preeditStr)
        } else {
             delegate.setMarkedText("")
        }
    }
    
    private func commitComposition(delegate: HangulComposerDelegate) {
        // Flush context
        let flushed = context.flush()
        let commitStr = String(flushed.compactMap { UnicodeScalar($0) }.map { Character($0) })
        
        DebugLogger.log("commitComposition: flushed=\(flushed), str='\(commitStr)'")
        
        if !commitStr.isEmpty {
            // insertText replaces the marked text automatically
            delegate.insertText(commitStr.precomposedStringWithCanonicalMapping)
            DebugLogger.log("commitComposition: inserted '\(commitStr)'")
        }
    }

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
