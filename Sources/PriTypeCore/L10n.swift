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
    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: SettingsWindowController.self)
        #endif
    }
    
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
    }
}
