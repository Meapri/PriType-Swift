import Foundation
import CoreGraphics

// MARK: - Types

/// Toggle key options for language switching (legacy enum, kept for migration)
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
    
    /// Convert legacy ToggleKey to KeyBinding
    public var asKeyBinding: KeyBinding {
        switch self {
        case .rightCommand:
            return .defaultToggle
        case .controlSpace:
            return KeyBinding(keyCode: 49, modifiers: CGEventFlags.maskControl.rawValue, displayName: "Control + Space")
        }
    }
}

// MARK: - KeyBinding

/// Represents a user-configured key binding (raw keyCode + modifiers)
///
/// Unlike the legacy `ToggleKey` enum which only supports preset options,
/// `KeyBinding` stores the actual raw key code and modifier flags,
/// allowing users to bind any key combination.
///
/// ## Usage
/// ```swift
/// let binding = KeyBinding(keyCode: 54, modifiers: 0, displayName: "우측 Command")
/// if event.keyCode == binding.keyCode { ... }
/// ```
public struct KeyBinding: Codable, Equatable, Sendable {
    /// macOS virtual key code (e.g., 54 = Right Command, 61 = Right Option)
    public let keyCode: Int64
    
    /// CGEventFlags raw value. 0 means single modifier key (no additional modifiers).
    public let modifiers: UInt64
    
    /// Human-readable display name (e.g., "우측 Command", "Control + Space")
    public let displayName: String
    
    /// Whether this is a modifier-only binding (no additional modifiers required)
    public var isModifierOnly: Bool {
        modifiers == 0
    }
    
    /// Default toggle key: Right Command
    public static let defaultToggle = KeyBinding(keyCode: 54, modifiers: 0, displayName: "우측 Command")
    
    /// Default hanja key: Right Option
    public static let defaultHanja = KeyBinding(keyCode: 61, modifiers: 0, displayName: "우측 Option")
    
    /// Generate a display name from raw keyCode and modifiers
    public static func generateDisplayName(keyCode: Int64, modifiers: UInt64) -> String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        
        if flags.contains(.maskControl) { parts.append("Control") }
        if flags.contains(.maskAlternate) { parts.append("Option") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        if flags.contains(.maskCommand) { parts.append("Command") }
        
        // Key name from keyCode
        let keyName: String
        switch keyCode {
        case 54: keyName = "우측 Command"
        case 55: keyName = "좌측 Command"
        case 61: keyName = "우측 Option"
        case 58: keyName = "좌측 Option"
        case 62: keyName = "우측 Control"
        case 59: keyName = "좌측 Control"
        case 49: keyName = "Space"
        case 57: keyName = "Caps Lock"
        case 36: keyName = "Return"
        case 48: keyName = "Tab"
        case 53: keyName = "Escape"
        default:
            // Try to get character from keyCode
            keyName = "Key(\(keyCode))"
        }
        
        // For modifier-only bindings, don't duplicate modifier name
        if modifiers == 0 {
            return keyName
        }
        
        parts.append(keyName)
        return parts.joined(separator: " + ")
    }
}

// MARK: - Notification Names

/// Notification names used by PriType
public extension Notification.Name {
    /// Posted when the keyboard layout changes
    static let keyboardLayoutChanged = Notification.Name("PriTypeKeyboardLayoutChanged")
    /// Posted when a key binding changes
    static let keyBindingChanged = Notification.Name("PriTypeKeyBindingChanged")
}

// MARK: - ConfigurationProviding Protocol

/// Protocol for accessing configuration settings
///
/// This protocol enables dependency injection for configuration access,
/// improving testability by allowing mock implementations in tests.
///
/// ## Usage
/// ```swift
/// class MyClass {
///     private let config: ConfigurationProviding
///     
///     init(config: ConfigurationProviding = ConfigurationManager.shared) {
///         self.config = config
///     }
/// }
/// ```
public protocol ConfigurationProviding: AnyObject, Sendable {
    /// The current keyboard layout identifier
    var keyboardId: String { get set }
    
    /// The selected toggle key for switching between Korean and English
    var toggleKey: ToggleKey { get set }
    
    /// Whether Right Command key is configured as the toggle key
    var rightCommandAsToggle: Bool { get }
    
    /// Whether Control+Space is configured as the toggle key
    var controlSpaceAsToggle: Bool { get }
    
    /// Whether to auto-capitalize first letter of sentences in English mode
    var autoCapitalizeEnabled: Bool { get set }
    
    /// Whether double-space inserts a period
    var doubleSpacePeriodEnabled: Bool { get set }
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
public final class ConfigurationManager: ConfigurationProviding, @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance for global access
    public static let shared = ConfigurationManager()
    
    // MARK: - Private Properties
    
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Keys
    
    private enum Keys {
        static let keyboardId = "com.pritype.keyboardId"
        static let toggleKey = "com.pritype.toggleKey"  // Legacy
        static let toggleKeyBinding = "com.pritype.toggleKeyBinding"
        static let hanjaKeyBinding = "com.pritype.hanjaKeyBinding"
        static let autoCapitalize = "com.pritype.autoCapitalize"
        static let doubleSpacePeriod = "com.pritype.doubleSpacePeriod"
        static let lastUpdateCheck = "com.pritype.lastUpdateCheck"
        static let autoUpdateCheck = "com.pritype.autoUpdateCheck"
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
    
    // MARK: - Toggle Key (Legacy)
    
    /// The selected toggle key for switching between Korean and English
    ///
    /// Defaults to `.rightCommand` if no preference is set.
    /// - Note: Legacy property kept for backward compatibility. Prefer `toggleKeyBinding`.
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
    
    // MARK: - Key Bindings (New)
    
    /// The user-configured toggle key binding
    ///
    /// Supports any key or key combination registered via the Key Recorder UI.
    /// On first access, migrates from legacy `toggleKey` if present.
    public var toggleKeyBinding: KeyBinding {
        get {
            if let data = defaults.data(forKey: Keys.toggleKeyBinding),
               let binding = try? JSONDecoder().decode(KeyBinding.self, from: data) {
                return binding
            }
            // Migrate from legacy toggleKey
            return toggleKey.asKeyBinding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.toggleKeyBinding)
            }
            NotificationCenter.default.post(name: .keyBindingChanged, object: nil)
        }
    }
    
    /// The user-configured hanja input key binding
    ///
    /// Defaults to Right Option if no preference is set.
    public var hanjaKeyBinding: KeyBinding {
        get {
            if let data = defaults.data(forKey: Keys.hanjaKeyBinding),
               let binding = try? JSONDecoder().decode(KeyBinding.self, from: data) {
                return binding
            }
            return .defaultHanja
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.hanjaKeyBinding)
            }
            NotificationCenter.default.post(name: .keyBindingChanged, object: nil)
        }
    }
    
    // MARK: - Convenience Properties
    
    /// Whether Right Command key is configured as the toggle key
    ///
    /// Use this to conditionally enable Right Command monitoring.
    public var rightCommandAsToggle: Bool {
        return toggleKeyBinding.keyCode == 54 && toggleKeyBinding.isModifierOnly
    }
    
    /// Whether Control+Space is configured as the toggle key
    ///
    /// Use this to conditionally handle Control+Space in the composer.
    public var controlSpaceAsToggle: Bool {
        return toggleKeyBinding.keyCode == 49 && toggleKeyBinding.modifiers == CGEventFlags.maskControl.rawValue
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
    
    // MARK: - Update Settings
    
    /// Timestamp of the last successful update check
    /// Used by `UpdateChecker` to throttle API calls (24-hour interval)
    public var lastUpdateCheck: Date? {
        get {
            defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        }
        set {
            defaults.set(newValue, forKey: Keys.lastUpdateCheck)
        }
    }
    
    /// Whether automatic update checking is enabled
    /// Default: enabled
    public var autoUpdateCheckEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.autoUpdateCheck) == nil {
                return true  // Default enabled
            }
            return defaults.bool(forKey: Keys.autoUpdateCheck)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoUpdateCheck)
        }
    }
}
