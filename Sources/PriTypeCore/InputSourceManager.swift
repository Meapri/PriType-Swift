import Foundation
import Carbon

// MARK: - InputSourceManager

/// Manages macOS input-source queries and stale preference cleanup.
///
/// Custom PriType language toggles must not call `TISSelectInputSource`.
/// Runtime mode switching is coordinated by `InputModeCoordinator` and
/// `PriTypeInputController`; this type stays off the typing hot path.
///
/// ## Usage
/// ```swift
/// let sources = InputSourceManager.shared.getEnabledKeyboardInputSources()
/// let isABCEnabled = InputSourceManager.shared.isABCEnabled()
/// ```
public final class InputSourceManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance
    public static let shared = InputSourceManager()
    
    private init() {}
    
    // MARK: - Constants
    
    /// Keyboard Layout ID for ABC (252)
    public static let abcKeyboardLayoutID = 252

    /// Modes belonging to `activeBundleID`. cleanupStaleInputSources must NOT
    /// strip the English mode (it is a real registered mode, not a leftover).
    private static func currentInputModes(forBundleID bundleID: String) -> Set<String> {
        [
            Brand.koreanModeID(forBundleID: bundleID),
            Brand.englishModeID(forBundleID: bundleID)
        ]
    }

    /// Old Korean mode key was the bundle id itself. TIS then minted
    /// `<bundleID>.<last-component>` and Settings showed every row as the app name.
    private static func legacyKoreanModeIds(forBundleID bundleID: String) -> Set<String> {
        [
            bundleID,
            Brand.mintedCollisionModeID(forBundleID: bundleID)
        ]
    }
    
    // MARK: - TIS API Methods
    
    /// Get a list of all enabled keyboard input sources using TIS API
    public func getEnabledKeyboardInputSources() -> [(id: String, name: String)] {
        var result: [(id: String, name: String)] = []
        
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true
        ]
        
        guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return result
        }
        
        for source in sourceList {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
               let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                result.append((id: id, name: name))
            }
        }
        
        return result
    }
    
    /// Check if ABC is enabled via TIS API
    public func isABCEnabled() -> Bool {
        let sources = getEnabledKeyboardInputSources()
        return sources.contains { $0.name == "ABC" || $0.id.contains("ABC") }
    }
    
    /// Check if US is enabled via TIS API  
    public func isUSEnabled() -> Bool {
        let sources = getEnabledKeyboardInputSources()
        return sources.contains { $0.id.contains("US") || $0.name == "U.S." }
    }

    /// Enabled ABC or US keyboard layout ID, or nil if the user has neither on.
    ///
    /// Used before `overrideKeyboardWithKeyboardNamed`. Requesting a *disabled*
    /// layout is what re-inserts ABC into `AppleEnabledInputSources` after the
    /// user turned it off.
    public func enabledRomanKeyboardLayoutID() -> String? {
        let enabledIDs = Set(getEnabledKeyboardInputSources().map(\.id))
        let candidates = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        return candidates.first { enabledIDs.contains($0) }
    }

    /// Remove the default ABC keyboard layout from the enabled input-source list.
    ///
    /// Matches KeyboardLayout ID 252 and the name "ABC". Does not touch U.S.
    /// Already-absent is treated as success. Does not enable or select sources.
    @discardableResult
    public func disableDefaultABCInputSource() -> Bool {
        guard let defaults = UserDefaults(suiteName: "com.apple.HIToolbox"),
              var sources = defaults.array(forKey: "AppleEnabledInputSources") as? [[String: Any]] else {
            return false
        }

        let originalCount = sources.count
        sources.removeAll { Self.isDefaultABCSource($0) }
        guard sources.count < originalCount else {
            return true
        }

        defaults.set(sources, forKey: "AppleEnabledInputSources")
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        DebugLogger.log("InputSourceManager: disabled default ABC input source")
        return true
    }

    internal static func isDefaultABCSource(_ source: [String: Any]) -> Bool {
        if (source["KeyboardLayout ID"] as? Int) == abcKeyboardLayoutID {
            return true
        }
        if (source["KeyboardLayout Name"] as? String) == "ABC" {
            return true
        }
        if let bundleID = source["Bundle ID"] as? String,
           bundleID.contains("keylayout.ABC") {
            return true
        }
        return false
    }

    /// Remove stale legacy entries without enabling or selecting input sources.
    ///
    /// This intentionally does not enable PriType itself. Calling
    /// `TISEnableInputSource` for the running input method can make macOS show
    /// an "add input source" confirmation again on startup.
    public func cleanupStaleInputSources() {
        guard let defaults = UserDefaults(suiteName: "com.apple.HIToolbox") else {
            DebugLogger.log("InputSourceManager: failed to open HIToolbox defaults")
            return
        }

        var enabledSources = defaults.array(forKey: "AppleEnabledInputSources") as? [[String: Any]] ?? []
        let originalEnabledSources = enabledSources

        enabledSources = Self.sanitizedInputSources(
            enabledSources,
            removeAppleKoreanInputModes: false,
            allowsPriTypeParentEntry: true,
            activeBundleID: Brand.bundleID
        )

        var didChange = !Self.inputSourcesEqual(enabledSources, originalEnabledSources)
        if didChange {
            defaults.set(enabledSources, forKey: "AppleEnabledInputSources")
        }

        for key in ["AppleSelectedInputSources", "AppleInputSourceHistory"] {
            guard let originalSources = defaults.array(forKey: key) as? [[String: Any]] else {
                continue
            }
            let sanitizedSources = Self.sanitizedInputSources(
                originalSources,
                removeAppleKoreanInputModes: false,
                allowsPriTypeParentEntry: true,
                activeBundleID: Brand.bundleID
            )
            if !Self.inputSourcesEqual(sanitizedSources, originalSources) {
                defaults.set(sanitizedSources, forKey: key)
                didChange = true
            }
        }

        guard didChange else {
            DebugLogger.log("InputSourceManager: Apple ABC and legacy input-source cleanup already current")
            return
        }

        defaults.synchronize()
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        DebugLogger.log("InputSourceManager: cleaned stale PriType input-source entries")
    }

    private static func inputSourcesEqual(_ lhs: [[String: Any]], _ rhs: [[String: Any]]) -> Bool {
        (lhs as NSArray).isEqual(to: rhs)
    }

    internal static func sanitizedInputSources(
        _ sources: [[String: Any]],
        removeAppleKoreanInputModes: Bool,
        allowsPriTypeParentEntry: Bool,
        activeBundleID: String = Brand.bundleID
    ) -> [[String: Any]] {
        var seen = Set<String>()
        let currentModes = currentInputModes(forBundleID: activeBundleID)
        let legacyKorean = legacyKoreanModeIds(forBundleID: activeBundleID)

        return sources.compactMap { source in
            let source = migrateLegacyPriTypeMode(
                source,
                bundleID: activeBundleID,
                koreanModeID: Brand.koreanModeID(forBundleID: activeBundleID),
                legacyIds: legacyKorean
            )
            if shouldRemoveInputSource(
                source,
                removeAppleKoreanInputModes: removeAppleKoreanInputModes,
                allowsPriTypeParentEntry: allowsPriTypeParentEntry,
                activeBundleID: activeBundleID,
                currentModes: currentModes
            ) {
                return nil
            }

            let key = inputSourceIdentity(source)
            guard seen.insert(key).inserted else {
                return nil
            }

            return source
        }
    }

    /// Rewrite the Korean mode id that used to equal the bundle id so enabled /
    /// selected lists keep working after the Info.plist rename.
    private static func migrateLegacyPriTypeMode(
        _ source: [String: Any],
        bundleID: String,
        koreanModeID: String,
        legacyIds: Set<String>
    ) -> [String: Any] {
        guard (source["Bundle ID"] as? String) == bundleID,
              (source["InputSourceKind"] as? String) == "Input Mode",
              let inputMode = source["Input Mode"] as? String,
              legacyIds.contains(inputMode) else {
            return source
        }
        var migrated = source
        migrated["Input Mode"] = koreanModeID
        return migrated
    }

    private static func shouldRemoveInputSource(
        _ source: [String: Any],
        removeAppleKoreanInputModes: Bool,
        allowsPriTypeParentEntry: Bool,
        activeBundleID: String,
        currentModes: Set<String>
    ) -> Bool {
        if let bundleID = source["Bundle ID"] as? String,
           bundleID == Brand.officialBundleID,
           activeBundleID != Brand.officialBundleID {
            // PatchType must not leave official PriType rows in HIToolbox.
            return true
        }

        if (source["Bundle ID"] as? String) == activeBundleID {
            let inputMode = source["Input Mode"] as? String
            guard let inputMode else {
                return !allowsPriTypeParentEntry
            }
            if !currentModes.contains(inputMode) {
                return true
            }
            return false
        }

        if removeAppleKoreanInputModes,
           Self.appleKoreanInputMethodBundleIDs.contains(source["Bundle ID"] as? String ?? ""),
           source["InputSourceKind"] as? String == "Input Mode" {
            return true
        }

        return false
    }

    private static let appleKoreanInputMethodBundleIDs: Set<String> = [
        "com.apple.inputmethod.Korean",
        "com.apple.inputmethod.ironwood"
    ]

    private static func inputSourceIdentity(_ source: [String: Any]) -> String {
        [
            source["InputSourceKind"] as? String ?? "",
            source["Bundle ID"] as? String ?? "",
            source["Input Mode"] as? String ?? "",
            "\(source["KeyboardLayout ID"] as? Int ?? Int.min)",
            source["KeyboardLayout Name"] as? String ?? ""
        ].joined(separator: "\u{1F}")
    }
}
