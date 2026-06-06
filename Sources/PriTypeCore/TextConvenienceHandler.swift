import Cocoa

/// Handles text convenience features like double-space period
///
/// This class separates text convenience functionality from the core Hangul composition engine,
/// following the Single Responsibility Principle.
///
/// ## Features
/// - Double-space to period conversion for Korean composition (gated on the
///   macOS `NSAutomaticPeriodSubstitutionEnabled`-backed preference)
/// - English-mode fallback for macOS text conveniences when IMK pass-through
///   does not trigger host substitutions.
///
/// English fallback deliberately touches only the narrow keys that need help
/// (`space` and lowercase ASCII letters). Everything else stays pass-through.
///
/// ## Usage
/// ```swift
/// let handler = TextConvenienceHandler()
/// let result = handler.handleDoubleSpacePeriod(delegate: myDelegate)
/// ```
public final class TextConvenienceHandler: @unchecked Sendable {
    private let isDoubleSpacePeriodEnabled: @Sendable () -> Bool
    private let isAutoCapitalizationEnabled: @Sendable () -> Bool
    private let isSmartQuoteSubstitutionEnabled: @Sendable () -> Bool
    private let isSmartDashSubstitutionEnabled: @Sendable () -> Bool
    
    // MARK: - State
    
    /// Track if last character was a space (for double-space detection)
    private var lastWasSpace: Bool = false
    
    /// Timestamp of the last space key press (for double-space timing check)
    private var lastSpaceTime: CFAbsoluteTime = 0
    
    public init(
        isDoubleSpacePeriodEnabled: @escaping @Sendable () -> Bool = {
            ConfigurationManager.shared.doubleSpacePeriodEnabled
        },
        isAutoCapitalizationEnabled: @escaping @Sendable () -> Bool = {
            ConfigurationManager.shared.autoCapitalizationEnabled
        },
        isSmartQuoteSubstitutionEnabled: @escaping @Sendable () -> Bool = {
            ConfigurationManager.shared.smartQuoteSubstitutionEnabled
        },
        isSmartDashSubstitutionEnabled: @escaping @Sendable () -> Bool = {
            ConfigurationManager.shared.smartDashSubstitutionEnabled
        }
    ) {
        self.isDoubleSpacePeriodEnabled = isDoubleSpacePeriodEnabled
        self.isAutoCapitalizationEnabled = isAutoCapitalizationEnabled
        self.isSmartQuoteSubstitutionEnabled = isSmartQuoteSubstitutionEnabled
        self.isSmartDashSubstitutionEnabled = isSmartDashSubstitutionEnabled
    }
    
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
    ///   - buffer: The local text buffer to query and modify
    ///   - delegate: The delegate to modify text
    ///   - checkHangul: If true, also checks for Hangul characters before space
    /// - Returns: Result indicating whether period conversion occurred
    public func handleDoubleSpacePeriod(buffer: inout String, delegate: HangulComposerDelegate, checkHangul: Bool = false) -> DoubleSpaceResult {
        let now = CFAbsoluteTimeGetCurrent()
        let isDoubleTap = (now - lastSpaceTime) < PriTypeConfig.doubleSpaceThreshold
        lastSpaceTime = now
        
        // Double-space period: Only if enabled, just typed space, AND fast enough
        if isDoubleSpacePeriodEnabled() && lastWasSpace && isDoubleTap {
            // Check context to confirm valid double-space condition
            if buffer.hasSuffix(" ") {
                let preSpaceChar = buffer.dropLast().last
                if let lastChar = preSpaceChar {
                    let isValidChar = lastChar.isLetter || lastChar.isNumber || (checkHangul && isHangul(lastChar))
                    if isValidChar {
                        // Valid double-space condition - replace space with period
                        delegate.replaceTextBeforeCursor(length: 1, with: ". ")
                        buffer.removeLast()
                        buffer.append(". ")
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

    // MARK: - English Fallback

    /// Handles macOS-like text conveniences in PriType English mode.
    ///
    /// The normal English path still passes through. This method consumes only
    /// when macOS would visibly transform the input and IMK pass-through does
    /// not do it for PriType's internal English mode.
    public func handleEnglishModeInput(_ event: NSEvent, delegate: HangulComposerDelegate) -> Bool {
        guard event.type == .keyDown, !event.isARepeat, shouldHandleTextConvenience(event) else {
            return false
        }

        if event.keyCode == KeyCode.space {
            return handleEnglishDoubleSpacePeriod(delegate: delegate)
        }

        resetSpaceState()
        if handleEnglishSmartDash(event, delegate: delegate) {
            return true
        }
        if handleEnglishSmartQuote(event, delegate: delegate) {
            return true
        }
        return handleEnglishAutoCapitalization(event, delegate: delegate)
    }

    private func handleEnglishDoubleSpacePeriod(delegate: HangulComposerDelegate) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let isDoubleTap = (now - lastSpaceTime) < PriTypeConfig.doubleSpaceThreshold
        lastSpaceTime = now
        lastWasSpace = true

        guard isDoubleSpacePeriodEnabled(), isDoubleTap else {
            return false
        }

        guard let beforeCursor = delegate.textBeforeCursor(length: 2),
              beforeCursor.hasSuffix(" "),
              let preSpaceChar = beforeCursor.dropLast().last,
              preSpaceChar.isLetter || preSpaceChar.isNumber else {
            return false
        }

        delegate.replaceTextBeforeCursor(length: 1, with: ". ")
        lastWasSpace = false
        DebugLogger.log("Double-space -> period (English fallback)")
        return true
    }

    private func handleEnglishAutoCapitalization(_ event: NSEvent, delegate: HangulComposerDelegate) -> Bool {
        guard isAutoCapitalizationEnabled(),
              let typed = event.characters,
              typed.count == 1,
              let scalar = typed.unicodeScalars.first,
              scalar.value >= 0x61,
              scalar.value <= 0x7A else {
            return false
        }

        guard let beforeCursor = delegate.textBeforeCursor(length: 3),
              shouldAutoCapitalize(after: beforeCursor) else {
            return false
        }

        delegate.insertText(String(typed).uppercased())
        DebugLogger.log("Auto-capitalize English fallback")
        return true
    }

    private func handleEnglishSmartDash(_ event: NSEvent, delegate: HangulComposerDelegate) -> Bool {
        guard isSmartDashSubstitutionEnabled(),
              event.characters == "-",
              delegate.textBeforeCursor(length: 1) == "-" else {
            return false
        }

        delegate.replaceTextBeforeCursor(length: 1, with: "—")
        DebugLogger.log("Smart dash English fallback")
        return true
    }

    private func handleEnglishSmartQuote(_ event: NSEvent, delegate: HangulComposerDelegate) -> Bool {
        guard isSmartQuoteSubstitutionEnabled(),
              let typed = event.characters,
              typed == "\"" || typed == "'" else {
            return false
        }

        let beforeCursor = delegate.textBeforeCursor(length: 1)
        guard let beforeCursor else {
            return false
        }

        let isOpening = shouldUseOpeningQuote(after: beforeCursor)
        switch typed {
        case "\"":
            delegate.insertText(isOpening ? "“" : "”")
        case "'":
            delegate.insertText(isOpening ? "‘" : "’")
        default:
            return false
        }

        DebugLogger.log("Smart quote English fallback")
        return true
    }

    private func shouldHandleTextConvenience(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        return modifiers.isEmpty
    }

    private func shouldAutoCapitalize(after beforeCursor: String) -> Bool {
        if beforeCursor.isEmpty {
            return true
        }

        let scalars = Array(beforeCursor.unicodeScalars)
        if scalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return true
        }

        guard let last = scalars.last,
              CharacterSet.whitespacesAndNewlines.contains(last) else {
            return false
        }

        return scalars
            .dropLast()
            .last(where: { !CharacterSet.whitespacesAndNewlines.contains($0) })
            .map { ".!?".unicodeScalars.contains($0) } ?? false
    }

    private func shouldUseOpeningQuote(after beforeCursor: String) -> Bool {
        guard let scalar = beforeCursor.unicodeScalars.last else {
            return true
        }

        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return true
        }

        return "([{<".unicodeScalars.contains(scalar)
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
