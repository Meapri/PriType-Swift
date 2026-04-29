import Foundation

/// Localization strings accessor for PriType
///
/// Provides type-safe access to localized strings from Localizable.strings.
///
/// ## Usage
/// ```swift
/// Text(L10n.keyboard.title)
/// Text(L10n.toggle.rightCommand)
/// ```
public enum L10n {
    
    /// Returns the bundle containing localized resources
    /// Uses robust fallback logic for both development and distribution environments
    private static let bundle: Bundle = {
        // 1. Try to find the SPM resource bundle in app's Resources directory (distribution)
        if let resourceURL = Bundle.main.resourceURL,
           let resourceBundle = Bundle(url: resourceURL.appendingPathComponent("PriType_PriTypeCore.bundle")) {
            return resourceBundle
        }
        
        // 2. Try Bundle.module for SPM development environment
        #if SWIFT_PACKAGE
        // This is safe in dev environment, but we use lazy fallback logic for robustness
        #endif
        
        // 3. Fallback to main bundle (localization files directly in Resources)
        return Bundle.main
    }()
    
    /// Helper to get localized string
    private static func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
    
    // MARK: - Settings
    
    public enum settings {
        public static var title: String { localized("settings.title") }
        public static var footer: String { localized("settings.footer") }
    }
    
    // MARK: - Keyboard Layout
    
    public enum keyboard {
        public static var title: String { localized("keyboard.title") }
        public static var twoSet: String { localized("keyboard.2set") }
        public static var threeSet390: String { localized("keyboard.3set390") }
        public static var twoSetOld: String { localized("keyboard.2setOld") }
        public static var threeSetOld: String { localized("keyboard.3setOld") }
    }
    
    // MARK: - Toggle Key
    
    public enum toggle {
        public static var title: String { localized("toggle.title") }
        public static var rightCommand: String { localized("toggle.rightCmd") }
        public static var controlSpace: String { localized("toggle.ctrlSpace") }
        public static var description: String { localized("toggle.description") }
    }
    
    // MARK: - Text Input
    
    public enum textInput {
        public static var title: String { localized("textInput.title") }
        public static var autoCapitalize: String { localized("textInput.autoCapitalize") }
        public static var doubleSpacePeriod: String { localized("textInput.doubleSpacePeriod") }
    }
    
    // MARK: - About
    
    public enum about {
        public static var title: String { localized("about.title") }
        public static var description: String { localized("about.description") }
        public static var version: String { localized("about.version") }
    }
    
    // MARK: - App
    
    public enum app {
        public static var name: String { "PriType" }
        public static var copyright: String { localized("app.copyright") }
        public static var quit: String { localized("app.quit") }
    }
    
    // MARK: - Update
    
    public enum update {
        public static var title: String { localized("update.title") }
        public static var checkButton: String { localized("update.checkButton") }
        public static var checking: String { localized("update.checking") }
        public static var upToDate: String { localized("update.upToDate") }
        public static var available: String { localized("update.available") }
        public static var download: String { localized("update.download") }
        public static var error: String { localized("update.error") }
        public static var notificationTitle: String { localized("update.notificationTitle") }
        public static var notificationBody: String { localized("update.notificationBody") }
        public static var autoCheck: String { localized("update.autoCheck") }
    }
    
    // MARK: - System
    
    public enum system {
        public static var title: String { localized("system.title") }
        public static var accessibility: String { localized("system.accessibility") }
        public static var accessibilityGranted: String { localized("system.accessibilityGranted") }
        public static var accessibilityRequest: String { localized("system.accessibilityRequest") }
        public static var removeABC: String { localized("system.removeABC") }
        public static var removeABCSuccess: String { localized("system.removeABCSuccess") }
        public static var removeABCFailed: String { localized("system.removeABCFailed") }
    }
}
