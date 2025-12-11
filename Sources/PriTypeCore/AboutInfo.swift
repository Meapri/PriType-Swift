import Cocoa

/// Centralized About information for PriType
///
/// This structure provides all application metadata and about dialog functionality
/// in a single location to prevent code duplication across different UI components.
public struct AboutInfo: Sendable {
    
    // MARK: - App Metadata
    
    /// Application display name
    public static let appName = "PriType"
    
    /// Current version string
    public static let version = "1.0"
    
    /// Copyright notice
    public static let copyright = "© 2025"
    
    /// Full description for about dialog
    public static let description = "macOS용 한글 입력기"
    
    // MARK: - About Dialog
    
    /// Shows the standard About dialog
    /// Call from main thread only
    @MainActor
    public static func showAlert() {
        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = "\(description)\n\n버전: \(version)\n\(copyright)"
        alert.alertStyle = .informational
        alert.runModal()
    }
}
