import Foundation

/**
 Binds actions to user defaults keys.

 If you store shortcuts in user defaults (for example by binding
 a `MASShortcutView` to user defaults), you can use this class to
 connect an action directly to a user defaults key. If the shortcut
 stored under the key changes, the action will get automatically
 updated to the new one.

 This class is mostly a wrapper around a `MASShortcutMonitor`. It
 watches the changes in user defaults and updates the shortcut monitor
 accordingly with the new shortcuts.
 */
/// Thread-safe shortcut binder using serial queue for Swift 6 compatibility.
/// Note: Uses @unchecked Sendable due to UserDefaults dependencies and complex mutable state.
/// This is a pragmatic choice for compatibility while acknowledging the trade-off.
public final class MASShortcutBinder: NSObject, @unchecked Sendable {

    // MARK: - Properties

    /// The underlying shortcut monitor.
    private let shortcutMonitor: MASShortcutMonitor

    /// Binding options customizing the access to user defaults.
    public var bindingOptions: [String: Any] = [
        "NSValueTransformerNameBindingOption": NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
    ]

    // Lock for protecting mutable state
    private let lock = NSLock()

    // Protected mutable state
    private var actions: [String: () -> Void] = [:]
    private var shortcuts: [String: MASShortcut] = [:]

    // MARK: - Initialization

    public override init() {
        self.shortcutMonitor = MASShortcutMonitor.create()
        super.init()
        setupNotificationObserver()
    }

    /// Creates a new shortcut binder with a custom monitor.
    public init(shortcutMonitor: MASShortcutMonitor) {
        self.shortcutMonitor = shortcutMonitor
        super.init()
        setupNotificationObserver()
    }

    deinit {
        // Simplified deinit - just remove observers
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsChanged(_:)), name: UserDefaults.didChangeNotification, object: nil)
    }

    // MARK: - Factory Method

    /// Creates a new shortcut binder instance.
    /// For Swift 6 compatibility, shared instances are not used.
    /// Instead, create and manage your own instance.
    public static func create() -> MASShortcutBinder {
        return MASShortcutBinder()
    }

    // MARK: - Public Methods

    /**
     Binds given action to a shortcut stored under the given defaults key.

     In other words, no matter what shortcut you store under the given key,
     pressing it will always trigger the given action.
     */
    public func bindShortcut(withDefaultsKey defaultsKeyName: String, toAction action: @escaping () -> Void) {
        assert(!defaultsKeyName.contains("."), "Illegal character in binding name (\".\"), please see http://git.io/x5YS.")
        assert(!defaultsKeyName.contains(" "), "Illegal character in binding name (\" \"), please see http://git.io/x5YS.")

        lock.withLock {
            actions[defaultsKeyName] = action
        }

        // Note: Binding system simplified for Swift 6 compatibility
        // In a full implementation, you would implement proper KVO-based binding
        // Notification observer is set up in init
    }

    /**
     Disconnect the binding between user defaults and action.

     In other words, the shortcut stored under the given key will no longer trigger an action.
     */
    public func breakBinding(withDefaultsKey defaultsKeyName: String) {
        lock.withLock {
            if let shortcut = shortcuts[defaultsKeyName] {
                shortcutMonitor.unregisterShortcut(shortcut)
            }
            shortcuts.removeValue(forKey: defaultsKeyName)
            actions.removeValue(forKey: defaultsKeyName)
        }
        // Simplified unbinding - just remove from actions
        // (NotificationCenter observer is removed in deinit)
    }

    /**
     Register default shortcuts in user defaults.

     This is a convenience frontend to `UserDefaults.registerDefaults`.
     The dictionary should contain a map of user defaults' keys to appropriate
     keyboard shortcuts. The shortcuts will be transformed according to
     `bindingOptions` and registered using `registerDefaults`.
     */
    public func registerDefaultShortcuts(_ defaultShortcuts: [String: MASShortcut]) {
        var transformer: ValueTransformer?

        if let transformerName = bindingOptions["NSValueTransformerNameBindingOption"] as? String {
            transformer = ValueTransformer(forName: NSValueTransformerName(rawValue: transformerName))
        }

        assert(transformer != nil, "Can't register default shortcuts without a transformer.")

        let defaults = UserDefaults.standard
        for (key, shortcut) in defaultShortcuts {
            if let value = transformer?.reverseTransformedValue(shortcut) {
                defaults.register(defaults: [key: value])
            }
        }
    }

    // MARK: - User Defaults Observation

    @objc private func userDefaultsChanged(_ notification: Notification) {
        let defaults = UserDefaults.standard
        lock.withLock {
            for (key, action) in actions {
                if let shortcut = defaults.object(forKey: key) as? MASShortcut {
                    // Update shortcut registration
                    if let currentShortcut = shortcuts[key], currentShortcut != shortcut {
                        shortcutMonitor.unregisterShortcut(currentShortcut)
                    }
                    shortcuts[key] = shortcut
                    _ = shortcutMonitor.registerShortcut(shortcut, withAction: action)
                }
            }
        }
    }

    // MARK: - Bindings Support

    private func isRegisteredAction(_ name: String) -> Bool {
        return lock.withLock {
            return actions[name] != nil
        }
    }

    // Simplified binding support - removed for Swift 6 compatibility
    // In a full implementation, you would implement proper async binding support
    public override func value(forUndefinedKey key: String) -> Any? {
        return super.value(forUndefinedKey: key)
    }

    public override func setValue(_ value: Any?, forUndefinedKey key: String) {
        super.setValue(value, forUndefinedKey: key)
    }
}
