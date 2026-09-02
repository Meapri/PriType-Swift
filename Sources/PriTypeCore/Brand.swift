import Foundation

/// Runtime identity of the installed input method.
///
/// The source-tree `Info.plist` keeps the official PriType identity so upstream
/// PRs stay a PriType patch. `./install.sh --as-patchtype` rewrites the
/// *installed* bundle (name, bundle id, version, connection name). These
/// accessors follow `Bundle.main` in that installed process and fall back to
/// the official IDs in tests and unpackaged tools.
public enum Brand: Sendable {
    public static let officialDisplayName = "PriType"
    public static let officialBundleID = "com.pritype.inputmethod.v2"
    public static let officialKoreanModeID = "com.pritype.inputmethod.v2.korean"
    public static let officialEnglishModeID = "com.pritype.inputmethod.v2.english"
    public static let officialConnectionName = "PriType_InputString_v2"

    public static let patchDisplayName = "PatchType"
    public static let patchBundleID = "com.calvinjkim.patchtype"
    public static let patchKoreanModeID = "com.calvinjkim.patchtype.korean"
    public static let patchEnglishModeID = "com.calvinjkim.patchtype.english"
    public static let patchConnectionName = "PatchType_InputString"
    public static let patchVersion = "2.7.4-patch.1"
    public static let patchBuild = "51"

    /// Bundle id of the running IME, or the official id outside an IME process.
    public static var bundleID: String {
        let id = Bundle.main.bundleIdentifier ?? ""
        if id == patchBundleID || id == officialBundleID {
            return id
        }
        return officialBundleID
    }

    /// Localized display name from the running IME, otherwise "PriType".
    public static var displayName: String {
        let runningID = Bundle.main.bundleIdentifier ?? ""
        guard runningID == bundleID,
              let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
              !name.isEmpty else {
            return officialDisplayName
        }
        return name
    }

    public static var koreanModeID: String { "\(bundleID).korean" }
    public static var englishModeID: String { "\(bundleID).english" }

    public static var connectionName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
           !name.isEmpty,
           Bundle.main.bundleIdentifier == bundleID {
            return name
        }
        return officialConnectionName
    }

    /// PatchType builds must not offer official PriType GitHub updates.
    public static var tracksUpstreamUpdates: Bool {
        bundleID == officialBundleID
    }

    public static func koreanModeID(forBundleID bundleID: String) -> String {
        "\(bundleID).korean"
    }

    public static func englishModeID(forBundleID bundleID: String) -> String {
        "\(bundleID).english"
    }

    /// TIS mints `<bundleID>.<last-component>` when the Korean mode key equals the bundle id.
    public static func mintedCollisionModeID(forBundleID bundleID: String) -> String {
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return "\(bundleID).\(last)"
    }
}
