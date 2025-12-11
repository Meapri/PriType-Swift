import Foundation

// MARK: - HangulComposerDelegate Protocol

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
    
    /// Replaces text before the cursor with new text
    /// Used for features like double-space period where we modify existing text
    /// - Parameters:
    ///   - length: Number of characters to replace (counting backwards from cursor)
    ///   - text: The new text to insert
    func replaceTextBeforeCursor(length: Int, with text: String)
}

// MARK: - InputMode Enum

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
    
    /// Returns the opposite mode (korean ↔ english)
    public var toggled: InputMode {
        switch self {
        case .korean: return .english
        case .english: return .korean
        }
    }
}
