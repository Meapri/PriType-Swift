import Foundation

public struct PriTypeConfig {
    /// Path for debug logging
    public static let logPath = NSString(string: "~/Library/Logs/PriType/pritype_debug.log").expandingTildeInPath
    
    /// Default keyboard identifier (2-set)
    public static let defaultKeyboardId = "2"
}
