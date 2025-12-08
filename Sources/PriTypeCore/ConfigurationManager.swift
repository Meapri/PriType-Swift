import Foundation

/// Toggle key options for language switching
public enum ToggleKey: String, CaseIterable, Sendable {
    case controlSpace = "controlSpace"
    case rightCommand = "rightCommand"
    
    public var displayName: String {
        switch self {
        case .controlSpace: return "Control + Space"
        case .rightCommand: return "우측 Command"
        }
    }
}

/// Manages user configuration using UserDefaults
public class ConfigurationManager: @unchecked Sendable {
    
    nonisolated(unsafe) public static let shared = ConfigurationManager()
    
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Keys
    
    private enum Keys {
        static let keyboardId = "com.pritype.keyboardId"
        static let toggleKey = "com.pritype.toggleKey"
    }
    
    // MARK: - Properties
    
    /// Keyboard layout ID: "2" (dubeolsik), "390", "3final"
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
    
    /// Selected toggle key for language switching
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
    
    /// Convenience: Check if Right Command is used as toggle
    public var rightCommandAsToggle: Bool {
        return toggleKey == .rightCommand
    }
    
    /// Convenience: Check if Control+Space is used as toggle
    public var controlSpaceAsToggle: Bool {
        return toggleKey == .controlSpace
    }
}

