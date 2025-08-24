import Foundation

private let MASLocalizationTableName = "Localizable"
private let MASPlaceholderLocalizationString = "XXX"

/**
 Reads a localized string from the framework's bundle.

 Normally you would use NSLocalizedString to read the localized
 strings, but that's just a shortcut for loading the strings from
 the main bundle. And once the framework ends up in an app, the
 main bundle will be the app's bundle and won't contain our strings.
 So we introduced this helper function that makes sure to load the
 strings from the framework's bundle. Please avoid using
 NSLocalizedString throughout the framework, it wouldn't work
 properly.
 */
public func MASLocalizedString(_ key: String, _ comment: String) -> String {
    struct StaticHolder {
        nonisolated(unsafe) static var bundle: Bundle?
        nonisolated(unsafe) static var onceToken: Int = 0
    }

    if StaticHolder.onceToken == 0 {
        StaticHolder.onceToken = 1

        #if SWIFT_PACKAGE
            StaticHolder.bundle = Bundle.module
        #else
            let frameworkBundle = Bundle(for: MASShortcut.self)
            // first we'll check if resources bundle was copied to MASShortcut framework bundle when !use_frameworks option is active
            if let cocoaPodsBundleURL = frameworkBundle.url(forResource: "MASShortcut", withExtension: "bundle") {
                StaticHolder.bundle = Bundle(url: cocoaPodsBundleURL)
            } else {
                // trying to fetch cocoapods bundle from main bundle
                if let cocoaPodsBundleURL = Bundle.main.url(forResource: "MASShortcut", withExtension: "bundle") {
                    StaticHolder.bundle = Bundle(url: cocoaPodsBundleURL)
                } else {
                    // fallback to framework bundle
                    StaticHolder.bundle = frameworkBundle
                }
            }
        #endif
    }

    return StaticHolder.bundle?.localizedString(forKey: key,
                                               value: MASPlaceholderLocalizationString,
                                               table: MASLocalizationTableName) ?? key
}
