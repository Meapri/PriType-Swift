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
        return Bundle.module
        #else
        // 3. Fallback to main bundle (localization files directly in Resources)
        return Bundle.main
        #endif
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
    
    // MARK: - Key Binding
    
    public enum keyBinding {
        public static var title: String { localized("keyBinding.title") }
        public static var toggleKey: String { localized("keyBinding.toggleKey") }
        public static var hanjaKey: String { localized("keyBinding.hanjaKey") }
        public static var recording: String { localized("keyBinding.recording") }
        public static var change: String { localized("keyBinding.change") }
        public static var conflict: String { localized("keyBinding.conflict") }
        public static var conflictRestored: String { localized("keyBinding.conflictRestored") }
        public static var reset: String { localized("keyBinding.reset") }
        public static var capsLockSummary: String { String(format: localized("keyBinding.capsLockSummary"), app.name) }
        public static var capsLockStatusTitle: String { localized("keyBinding.capsLockStatusTitle") }
        public static var capsLockStatusOn: String { localized("keyBinding.capsLockStatusOn") }
        public static var capsLockStatusOff: String { localized("keyBinding.capsLockStatusOff") }
        public static var capsLockOnDescription: String { String(format: localized("keyBinding.capsLockOnDescription"), app.name) }
        public static var capsLockOffDescription: String { String(format: localized("keyBinding.capsLockOffDescription"), app.name) }
        public static var disabledByCapsLock: String { localized("keyBinding.disabledByCapsLock") }
        public static var managedByMacOS: String { localized("keyBinding.managedByMacOS") }
        public static var capsLockBlockedTitle: String { localized("keyBinding.capsLockBlockedTitle") }
        public static var capsLockBlockedMessage: String { String(format: localized("keyBinding.capsLockBlockedMessage"), app.name) }
        public static var capsLockOpenSettings: String { localized("keyBinding.capsLockOpenSettings") }
    }
    
    // MARK: - About
    
    public enum about {
        public static var title: String { localized("about.title") }
        public static var description: String { localized("about.description") }
        public static var version: String { localized("about.version") }
        public static var patchNote: String { localized("about.patchNote") }
    }
    
    // MARK: - App
    
    public enum app {
        public static var name: String { Brand.displayName }
        public static var copyright: String { localized("app.copyright") }
        public static var quit: String { String(format: localized("app.quit"), name) }
        public static var settingsMenu: String { String(format: localized("app.settingsMenu"), name) }
        public static var aboutMenu: String { String(format: localized("app.aboutMenu"), name) }
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
        public static var notificationTitle: String { String(format: localized("update.notificationTitle"), app.name) }
        public static var notificationBody: String { localized("update.notificationBody") }
        public static var autoCheck: String { localized("update.autoCheck") }
        public static var localPatchDisabled: String { localized("update.localPatchDisabled") }
    }
    
    // MARK: - System
    
    public enum system {
        public static var title: String { localized("system.title") }
        public static var accessibility: String { localized("system.accessibility") }
        public static var accessibilityGranted: String { localized("system.accessibilityGranted") }
        public static var accessibilityRequest: String { localized("system.accessibilityRequest") }
        public static var accessibilitySubtitle: String { localized("system.accessibilitySubtitle") }
        public static var removeABC: String { localized("system.removeABC") }
        public static var removeABCSubtitle: String { String(format: localized("system.removeABCSubtitle"), app.name) }
        public static var removeABCButton: String { localized("system.removeABCButton") }
        public static var removeABCSuccess: String { localized("system.removeABCSuccess") }
        public static var removeABCFailed: String { localized("system.removeABCFailed") }
    }
}
