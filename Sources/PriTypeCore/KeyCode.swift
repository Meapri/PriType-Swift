import Foundation

/// Centralized key code constants for macOS keyboard events
///
/// ## Usage
/// ```swift
/// if keyCode == KeyCode.space { ... }
/// if KeyCode.isPrintable(charCode) { ... }
/// ```
public enum KeyCode {
    
    // MARK: - Navigation Keys
    
    /// Space key (49)
    public static let space: UInt16 = 49
    
    /// Backspace/Delete key (51)
    public static let backspace: UInt16 = 51
    
    /// Escape key (53)
    public static let escape: UInt16 = 53
    
    /// Return/Enter key (36)
    public static let `return`: UInt16 = 36
    
    /// Numpad Enter key (76)
    public static let numpadEnter: UInt16 = 76
    
    /// Tab key (48)
    public static let tab: UInt16 = 48
    
    // MARK: - Arrow Keys
    
    /// Left arrow (123)
    public static let leftArrow: UInt16 = 123
    
    /// Right arrow (124)
    public static let rightArrow: UInt16 = 124
    
    /// Down arrow (125)
    public static let downArrow: UInt16 = 125
    
    /// Up arrow (126)
    public static let upArrow: UInt16 = 126
    
    // MARK: - Modifier Keys (for CGEventTap)
    // These use Int64 type for compatibility with CGEvent.getIntegerValueField()
    
    /// Right Command key (54)
    public static let rightCommand: Int64 = 54
    
    /// Left Control key (59)
    public static let leftControl: Int64 = 59
    
    /// Right Control key (62)
    public static let rightControl: Int64 = 62
    
    /// Space key in Int64 context for CGEventTap (49)
    public static let spaceInt64: Int64 = 49
    
    // MARK: - Character Code Ranges
    
    /// Minimum printable ASCII character code (space)
    public static let printableMin: UInt32 = 32
    
    /// Maximum printable ASCII character code (tilde)
    public static let printableMax: UInt32 = 126
    
    /// Threshold for function/special keys (F1, etc.)
    public static let functionKeyThreshold: UInt32 = 63000
    
    /// Tab character code
    public static let tabCharCode: UInt32 = 9
    
    /// Newline (LF) character code
    public static let newlineCharCode: UInt32 = 10
    
    /// Carriage return (CR) character code
    public static let carriageReturnCharCode: UInt32 = 13
    
    // MARK: - Helper Methods
    
    /// Checks if a character code represents a printable ASCII character
    /// - Parameter charCode: Unicode scalar value
    /// - Returns: `true` if printable (32-126)
    public static func isPrintableASCII(_ charCode: UInt32) -> Bool {
        return charCode >= printableMin && charCode <= printableMax
    }
    
    /// Checks if a character code represents a function or special key
    /// - Parameter charCode: Unicode scalar value
    /// - Returns: `true` if function key (>= 63000)
    public static func isFunctionKey(_ charCode: UInt32) -> Bool {
        return charCode >= functionKeyThreshold
    }
    
    /// Checks if a character code is a control character (except tab/newline/CR)
    /// - Parameter charCode: Unicode scalar value
    /// - Returns: `true` if control character that should be ignored
    public static func isIgnorableControlChar(_ charCode: UInt32) -> Bool {
        return charCode < printableMin &&
               charCode != tabCharCode &&
               charCode != newlineCharCode &&
               charCode != carriageReturnCharCode
    }
    
    /// Checks if a character should be passed through to the system
    /// - Parameter charCode: Unicode scalar value
    /// - Returns: `true` if the character should not be handled by the input method
    public static func shouldPassThrough(_ charCode: UInt32) -> Bool {
        return isFunctionKey(charCode) || isIgnorableControlChar(charCode)
    }
}
