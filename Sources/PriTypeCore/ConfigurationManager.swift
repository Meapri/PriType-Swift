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

// MARK: - Notification Names

/// Notification names used by PriType
public extension Notification.Name {
    /// Posted when the keyboard layout changes
    static let keyboardLayoutChanged = Notification.Name("PriTypeKeyboardLayoutChanged")
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
/// This class uses `UserDefaults` which is thread-safe for reading/writing.
/// The class is marked `@unchecked Sendable` as UserDefaults provides the synchronization.
public final class ConfigurationManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance for global access
    public static let shared = ConfigurationManager()
    
    // MARK: - Private Properties
    
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Keys
    
    private enum Keys {
        static let keyboardId = "com.pritype.keyboardId"
        static let toggleKey = "com.pritype.toggleKey"
        static let autoCapitalize = "com.pritype.autoCapitalize"
        static let doubleSpacePeriod = "com.pritype.doubleSpacePeriod"
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
                NotificationCenter.default.post(name: .keyboardLayoutChanged, object: nil)
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
    
    // MARK: - Text Input Features
    
    /// Whether to auto-capitalize first letter of sentences in English mode
    /// Default: enabled
    public var autoCapitalizeEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.autoCapitalize) == nil {
                return true  // Default enabled
            }
            return defaults.bool(forKey: Keys.autoCapitalize)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoCapitalize)
        }
    }
    
    /// Whether double-space inserts a period
    /// Default: enabled
    public var doubleSpacePeriodEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.doubleSpacePeriod) == nil {
                return true  // Default enabled
            }
            return defaults.bool(forKey: Keys.doubleSpacePeriod)
        }
        set {
            defaults.set(newValue, forKey: Keys.doubleSpacePeriod)
        }
    }
}
