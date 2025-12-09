import Foundation

// MARK: - Types

/// Toggle key options for language switching
///
/// Defines the available modifier key combinations that can be used
/// to switch between Korean and English input modes.
public enum ToggleKey: String, CaseIterable, Sendable {
    /// Control + Space key combination
    case controlSpace = "controlSpace"
    /// Right Command key (single key toggle)
    case rightCommand = "rightCommand"
    
    /// Human-readable display name for the toggle key
    public var displayName: String {
        switch self {
        case .controlSpace: return "Control + Space"
        case .rightCommand: return "우측 Command"
        }
    }
}

// MARK: - ConfigurationManager

/// Manages persistent user configuration using UserDefaults
///
/// `ConfigurationManager` provides a centralized interface for accessing and
/// modifying user preferences. All settings are automatically persisted using
/// `UserDefaults` with the `com.pritype` prefix.
///
/// ## Usage
/// ```swift
/// // Read current keyboard layout
/// let layout = ConfigurationManager.shared.keyboardId
///
/// // Change keyboard layout (automatically persisted)
/// ConfigurationManager.shared.keyboardId = "3"  // Switch to Sebeolsik
/// ```
///
/// ## Notifications
/// When `keyboardId` changes, a `PriTypeKeyboardLayoutChanged` notification is posted
/// to notify observers (e.g., `PriTypeInputController`) to update the input engine.
///
/// ## Thread Safety
/// This class uses `@unchecked Sendable` and should be accessed carefully from
/// multiple threads. The underlying `UserDefaults` is thread-safe.
public class ConfigurationManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance for global access
    nonisolated(unsafe) public static let shared = ConfigurationManager()
    
    // MARK: - Private Properties
    
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Keys
    
    private enum Keys {
        static let keyboardId = "com.pritype.keyboardId"
        static let toggleKey = "com.pritype.toggleKey"
        static let autoCapitalizeEnglish = "com.pritype.autoCapitalizeEnglish"
    }
    
    // MARK: - Keyboard Layout
    
    /// The current keyboard layout identifier
    ///
    /// Supported values:
    /// - `"2"`: 두벌식 표준 (Dubeolsik Standard)
    /// - `"3"`: 세벌식 390 (Sebeolsik 390)
    /// - `"2y"`: 두벌식 옛한글 (Dubeolsik Old Hangul)
    /// - `"3y"`: 세벌식 옛한글 (Sebeolsik Old Hangul)
    ///
    /// When this value changes, a `PriTypeKeyboardLayoutChanged` notification is posted.
    public var keyboardId: String {
        get {
            defaults.string(forKey: Keys.keyboardId) ?? "2"
        }
        set {
            if keyboardId != newValue {
                defaults.set(newValue, forKey: Keys.keyboardId)
                // Notify observers (e.g. InputController) to update the engine
                NotificationCenter.default.post(name: Notification.Name("PriTypeKeyboardLayoutChanged"), object: nil)
            }
        }
    }
    
    // MARK: - Toggle Key
    
    /// The selected toggle key for switching between Korean and English
    ///
    /// Defaults to `.rightCommand` if no preference is set.
    public var toggleKey: ToggleKey {
        get {
            if let rawValue = defaults.string(forKey: Keys.toggleKey),
               let key = ToggleKey(rawValue: rawValue) {
                return key
            }
            return .rightCommand  // Default
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.toggleKey)
        }
    }
    
    // MARK: - Convenience Properties
    
    /// Whether Right Command key is configured as the toggle key
    ///
    /// Use this to conditionally enable Right Command monitoring.
    public var rightCommandAsToggle: Bool {
        return toggleKey == .rightCommand
    }
    
    /// Whether Control+Space is configured as the toggle key
    ///
    /// Use this to conditionally handle Control+Space in the composer.
    public var controlSpaceAsToggle: Bool {
        return toggleKey == .controlSpace
    }
    
    // MARK: - Auto-Capitalize
    
    /// Whether to auto-capitalize the first letter in English mode
    ///
    /// When enabled, the first letter typed after a period, question mark,
    /// exclamation mark, or at the start of input will be capitalized.
    public var autoCapitalizeEnglish: Bool {
        get {
            // Default to false (disabled)
            if defaults.object(forKey: Keys.autoCapitalizeEnglish) == nil {
                return false
            }
            return defaults.bool(forKey: Keys.autoCapitalizeEnglish)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoCapitalizeEnglish)
        }
    }
}
