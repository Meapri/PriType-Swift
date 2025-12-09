import Foundation

/// Global configuration constants for PriType
public struct PriTypeConfig: Sendable {
    
    #if DEBUG
    /// Path for debug logging (DEBUG builds only)
    /// - Note: This property does not exist in release builds for security.
    public static let logPath = NSString(string: "~/Library/Logs/PriType/pritype_debug.log").expandingTildeInPath
    #endif
    
    /// Default keyboard identifier (두벌식 표준)
    public static let defaultKeyboardId = "2"
}
