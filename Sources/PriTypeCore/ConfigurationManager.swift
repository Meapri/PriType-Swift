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
    
    /// Whether the bound key is a modifier key (Command, Option, Control, Shift, CapsLock)
    /// Modifier keys generate `flagsChanged` events; regular keys generate `keyDown` events.
    public var isModifierKey: Bool {
        switch keyCode {
        case 54, 55: return true  // Right/Left Command
        case 61, 58: return true  // Right/Left Option
        case 62, 59: return true  // Right/Left Control
        case 56, 60: return true  // Left/Right Shift
        case 57:     return true  // Caps Lock
        case 63:     return true  // Fn
        default:     return false
        }
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
        
        // Key name from keyCode — comprehensive macOS virtual key code mapping
        let keyName: String
        switch keyCode {
        // Modifier keys
        case 54: keyName = "우측 Command"
        case 55: keyName = "좌측 Command"
        case 61: keyName = "우측 Option"
        case 58: keyName = "좌측 Option"
        case 62: keyName = "우측 Control"
        case 59: keyName = "좌측 Control"
        case 56: keyName = "좌측 Shift"
        case 60: keyName = "우측 Shift"
        case 57: keyName = "Caps Lock"
        case 63: keyName = "Fn"
        // Special keys
        case 49: keyName = "Space"
        case 36: keyName = "Return"
        case 48: keyName = "Tab"
        case 53: keyName = "Escape"
        case 51: keyName = "Delete"
        case 117: keyName = "Forward Delete"
        // Arrow keys
        case 123: keyName = "←"
        case 124: keyName = "→"
        case 125: keyName = "↓"
        case 126: keyName = "↑"
        // Navigation
        case 115: keyName = "Home"
        case 119: keyName = "End"
        case 116: keyName = "Page Up"
        case 121: keyName = "Page Down"
        // F-keys
        case 122: keyName = "F1"
        case 120: keyName = "F2"
        case 99:  keyName = "F3"
        case 118: keyName = "F4"
        case 96:  keyName = "F5"
        case 97:  keyName = "F6"
        case 98:  keyName = "F7"
        case 100: keyName = "F8"
        case 101: keyName = "F9"
        case 109: keyName = "F10"
        case 103: keyName = "F11"
        case 111: keyName = "F12"
        case 105: keyName = "F13"
        case 107: keyName = "F14"
        case 113: keyName = "F15"
        // Letter keys (QWERTY layout)
        case 0:  keyName = "A"
        case 11: keyName = "B"
        case 8:  keyName = "C"
        case 2:  keyName = "D"
        case 14: keyName = "E"
        case 3:  keyName = "F"
        case 5:  keyName = "G"
        case 4:  keyName = "H"
        case 34: keyName = "I"
        case 38: keyName = "J"
        case 40: keyName = "K"
        case 37: keyName = "L"
        case 46: keyName = "M"
        case 45: keyName = "N"
        case 31: keyName = "O"
        case 35: keyName = "P"
        case 12: keyName = "Q"
        case 15: keyName = "R"
        case 1:  keyName = "S"
        case 17: keyName = "T"
        case 32: keyName = "U"
        case 9:  keyName = "V"
        case 13: keyName = "W"
        case 7:  keyName = "X"
        case 16: keyName = "Y"
        case 6:  keyName = "Z"
        // Number keys
        case 29: keyName = "0"
        case 18: keyName = "1"
        case 19: keyName = "2"
        case 20: keyName = "3"
        case 21: keyName = "4"
        case 23: keyName = "5"
        case 22: keyName = "6"
        case 26: keyName = "7"
        case 28: keyName = "8"
        case 25: keyName = "9"
        // Punctuation
        case 27: keyName = "-"
        case 24: keyName = "="
        case 33: keyName = "["
        case 30: keyName = "]"
        case 42: keyName = "\\"
        case 41: keyName = ";"
        case 39: keyName = "'"
        case 43: keyName = ","
        case 47: keyName = "."
        case 44: keyName = "/"
        case 50: keyName = "`"
        default:
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
    
    // MARK: - Key Binding Cache
    // CGEventTap callbacks read these on EVERY key event (100+ times/sec during typing).
    // JSON decoding on every access is wasteful; cache in memory and invalidate on write.
    // Lock protects in-memory cache from races between CGEventTap thread and settings UI.
    
    private var _cachedToggleBinding: KeyBinding?
    private var _cachedHanjaBinding: KeyBinding?
    private let keyBindingLock = NSLock()
    
    /// The user-configured toggle key binding
    ///
    /// Supports any key or key combination registered via the Key Recorder UI.
    /// On first access, migrates from legacy `toggleKey` if present.
    /// Result is cached in memory to avoid JSON decoding on every CGEventTap callback.
    public var toggleKeyBinding: KeyBinding {
        get {
            keyBindingLock.lock()
            defer { keyBindingLock.unlock() }
            if let cached = _cachedToggleBinding {
                return cached
            }
            let binding: KeyBinding
            if let data = defaults.data(forKey: Keys.toggleKeyBinding),
               let decoded = try? JSONDecoder().decode(KeyBinding.self, from: data) {
                // Sanitize: Fn key (63) is not supported in CGEventTap
                binding = decoded.keyCode == 63 ? .defaultToggle : decoded
            } else {
                // Migrate from legacy toggleKey
                binding = toggleKey.asKeyBinding
            }
            _cachedToggleBinding = binding
            return binding
        }
        set {
            keyBindingLock.lock()
            _cachedToggleBinding = newValue
            keyBindingLock.unlock()
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.toggleKeyBinding)
            }
            NotificationCenter.default.post(name: .keyBindingChanged, object: nil)
        }
    }
    
    /// The user-configured hanja input key binding
    ///
    /// Defaults to Right Option if no preference is set.
    /// Result is cached in memory to avoid JSON decoding on every CGEventTap callback.
    public var hanjaKeyBinding: KeyBinding {
        get {
            keyBindingLock.lock()
            defer { keyBindingLock.unlock() }
            if let cached = _cachedHanjaBinding {
                return cached
            }
            let binding: KeyBinding
            if let data = defaults.data(forKey: Keys.hanjaKeyBinding),
               let decoded = try? JSONDecoder().decode(KeyBinding.self, from: data) {
                // Sanitize: Fn key (63) is not supported in CGEventTap
                binding = decoded.keyCode == 63 ? .defaultHanja : decoded
            } else {
                binding = .defaultHanja
            }
            _cachedHanjaBinding = binding
            return binding
        }
        set {
            keyBindingLock.lock()
            _cachedHanjaBinding = newValue
            keyBindingLock.unlock()
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
