import Cocoa

/// Centralized About information for PriType
///
/// This structure provides all application metadata and about dialog functionality
/// in a single location to prevent code duplication across different UI components.
///
/// All user-visible strings are now sourced from `L10n` for internationalization.
public struct AboutInfo: Sendable {
    
    // MARK: - App Metadata
    
    /// Application display name
    public static var appName: String { L10n.app.name }
    
    /// Current version string
    public static let version = "1.0"
    
    /// Copyright notice (localized)
    public static var copyright: String { L10n.app.copyright }
    
    /// Full description for about dialog (localized)
    public static var description: String { L10n.about.description }
    
    // MARK: - About Dialog
    
    /// Shows the standard About dialog
    ///
    /// Displays a localized about dialog with app name, description, version, and copyright.
    /// Must be called from main thread only.
    @MainActor
    public static func showAlert() {
        let alert = NSAlert()
        alert.messageText = appName
        alert.informativeText = "\(description)\n\n\(L10n.about.version): \(version)\n\(copyright)"
        alert.alertStyle = .informational
        alert.runModal()
    }
}

