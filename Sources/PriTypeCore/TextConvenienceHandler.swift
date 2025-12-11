import Foundation

/// Handles text convenience features like auto-capitalize and double-space period
///
/// This class separates text convenience functionality from the core Hangul composition engine,
/// following the Single Responsibility Principle.
///
/// ## Features
/// - Auto-capitalize first letter of sentences (English mode)
/// - Double-space to period conversion (both Korean and English modes)
/// - English mode input handling with pass-through
///
/// ## Usage
/// ```swift
/// let handler = TextConvenienceHandler()
/// let result = handler.handleDoubleSpacePeriod(delegate: myDelegate)
/// ```
public final class TextConvenienceHandler: @unchecked Sendable {
    
    // MARK: - State
    
    /// Track if last character was a space (for double-space detection)
    private var lastWasSpace: Bool = false
    
    /// Timestamp of the last space key press (for double-space timing check)
    private var lastSpaceTime: CFAbsoluteTime = 0
    
    public init() {}
    
    // MARK: - Double-Space Period
    
    /// Result of double-space period handling
    public enum DoubleSpaceResult {
        /// Double-space was converted to period - event consumed
        case convertedToPeriod
        /// Normal space - event should be passed to system
        case normalSpace
    }
    
    /// Handle space key press for double-space period conversion
    ///
    /// - Parameters:
    ///   - delegate: The delegate to query/modify text
    ///   - checkHangul: If true, also checks for Hangul characters before space
    /// - Returns: Result indicating whether period conversion occurred
    public func handleDoubleSpacePeriod(delegate: HangulComposerDelegate, checkHangul: Bool = false) -> DoubleSpaceResult {
        let now = CFAbsoluteTimeGetCurrent()
        let isDoubleTap = (now - lastSpaceTime) < PriTypeConfig.doubleSpaceThreshold
        lastSpaceTime = now
        
        // Double-space period: Only if enabled, just typed space, AND fast enough
        if ConfigurationManager.shared.doubleSpacePeriodEnabled && lastWasSpace && isDoubleTap {
            // Check context to confirm valid double-space condition
            if let context = delegate.textBeforeCursor(length: 2),
               context.hasSuffix(" ") {
                let preSpaceChar = context.dropLast().last
                if let lastChar = preSpaceChar {
                    let isValidChar = lastChar.isLetter || lastChar.isNumber || (checkHangul && isHangul(lastChar))
                    if isValidChar {
                        // Valid double-space condition - replace space with period
                        delegate.replaceTextBeforeCursor(length: 1, with: ". ")
                        lastWasSpace = false
                        DebugLogger.log("Double-space -> period (Context validated)")
                        return .convertedToPeriod
                    }
                }
            }
        }
        
        // Normal space
        lastWasSpace = true
        return .normalSpace
    }
    
    /// Reset the space state (call when non-space character is typed)
    public func resetSpaceState() {
        lastWasSpace = false
    }
    
    // MARK: - English Mode Input
    
    /// Result of English mode input handling
    public enum EnglishInputResult {
        /// Input was handled (consumed) - auto-capitalized or double-space period
        case handled
        /// Input should pass through to system
        case passThrough
    }
    
    /// Handle English mode input
    ///
    /// - Parameters:
    ///   - char: The character being typed
    ///   - delegate: The delegate for text operations
    /// - Returns: Result indicating whether input was handled
    public func handleEnglishModeInput(char: Character, delegate: HangulComposerDelegate) -> EnglishInputResult {
        // Handle space key
        if char == " " {
            let result = handleDoubleSpacePeriod(delegate: delegate, checkHangul: false)
            return result == .convertedToPeriod ? .handled : .passThrough
        }
        
        // Non-space character
        resetSpaceState()
        
        // Auto-capitalize: Only if enabled
        if ConfigurationManager.shared.autoCapitalizeEnabled && char.isLetter {
            if shouldAutoCapitalize(delegate: delegate) {
                let uppercased = String(char).uppercased()
                delegate.insertText(uppercased)
                DebugLogger.log("Auto-capitalized: \(char) -> \(uppercased)")
                return .handled
            }
        }
        
        return .passThrough
    }
    
    // MARK: - Auto-Capitalize
    
    /// Determines if the next character should be auto-capitalized based on document context
    ///
    /// Checks for:
    /// - Start of document
    /// - After newline
    /// - Sentence ending (. ! ?) followed by space
    ///
    /// - Parameter delegate: The delegate to query for text context
    /// - Returns: `true` if the next character should be capitalized
    public func shouldAutoCapitalize(delegate: HangulComposerDelegate) -> Bool {
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
        guard let lastChar = text.last, lastChar.isWhitespace else {
            return false // Cursor is right after a non-space char
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
    
    // MARK: - Helpers
    
    /// Checks if a character is a Hangul syllable or Jamo
    public func isHangul(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let val = scalar.value
        // Hangul Syllables: AC00-D7A3
        // Hangul Compatibility Jamo: 3130-318F
        // Hangul Jamo: 1100-11FF
        return (val >= 0xAC00 && val <= 0xD7A3) ||
               (val >= 0x3130 && val <= 0x318F) ||
               (val >= 0x1100 && val <= 0x11FF)
    }
}
