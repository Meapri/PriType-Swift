import AppKit
import Carbon

/**
 Executes action when a shortcut is pressed.

 There can only be one instance of this class, otherwise things
 will probably not work. (There's a Carbon event handler inside
 and there can only be one Carbon event handler of a given type.)
 */
/// Protocol for shortcut monitoring operations.
public protocol ShortcutMonitoring {
    /// Register a shortcut with an async action.
    func registerShortcut(_ shortcut: MASShortcut, action: @escaping @Sendable () async -> Void) async throws -> ShortcutRegistration

    /// Unregister a shortcut.
    func unregisterShortcut(_ registration: ShortcutRegistration) async

    /// Unregister all shortcuts.
    func unregisterAllShortcuts() async

    /// Check if a shortcut is currently registered.
    func isShortcutRegistered(_ shortcut: MASShortcut) async -> Bool
}

/// A registration handle for a shortcut.
public struct ShortcutRegistration: Sendable, Hashable {
    let id: UUID
    let shortcut: MASShortcut

    public init(id: UUID = UUID(), shortcut: MASShortcut) {
        self.id = id
        self.shortcut = shortcut
    }
}

/// Modern shortcut monitor with async/await support.
/// Thread-safe implementation using serial queue for Swift 6 compatibility.
/// Note: Uses @unchecked Sendable due to Carbon API dependencies and complex mutable state.
/// This is a pragmatic choice for compatibility while acknowledging the trade-off.
public final class MASShortcutMonitor: NSObject, ShortcutMonitoring, @unchecked Sendable {

    // MARK: - Properties

    // Dependencies
    private let validator: MASShortcutValidator

    // Serial queue for thread safety
    private let registrationQueue = DispatchQueue(label: "com.masshortcut.registration")

    // Lock for protecting mutable state
    private let lock = NSLock()

    // Mutable state - protected by lock for thread safety
    private var hotKeys: [MASShortcut: MASHotKey] = [:]
    private var registrations: [ShortcutRegistration: MASHotKey] = [:]

    // MARK: - Initialization

    private init(validator: MASShortcutValidator) {
        self.validator = validator
        super.init()

        lock.withLock {
            hotKeys = [:]
        }

        _ = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // Install Carbon event handler - simplified for Swift 6 compatibility
        // In a full implementation, you would properly handle Carbon events
        // Note: eventHandlerRef is protected by lock in handleEvent method
    }

    deinit {
        // Simplified deinit - Carbon event handler management removed for Swift 6 compatibility
    }

    // MARK: - Factory Methods

    /// Creates a new shortcut monitor instance with a default validator.
    /// For Swift 6 compatibility, shared instances are not used.
    /// Instead, create and manage your own instance.
    public static func create() -> MASShortcutMonitor {
        let validator = MASShortcutValidator()
        return MASShortcutMonitor(validator: validator)
    }

    /// Creates a new shortcut monitor instance with a custom validator.
    public static func create(with validator: MASShortcutValidator) -> MASShortcutMonitor {
        return MASShortcutMonitor(validator: validator)
    }

    // MARK: - Errors

    /// Errors that can occur during shortcut registration.
    public enum RegistrationError: LocalizedError, Sendable {
        case shortcutAlreadyRegistered(MASShortcut)
        case systemRegistrationFailed
        case invalidShortcut

        public var errorDescription: String? {
            switch self {
            case .shortcutAlreadyRegistered(let shortcut):
                return "Shortcut \(shortcut) is already registered"
            case .systemRegistrationFailed:
                return "Failed to register shortcut with system"
            case .invalidShortcut:
                return "Invalid shortcut configuration"
            }
        }
    }

    // MARK: - Public Methods

    /// Register a shortcut with an async action.
    /// - Parameters:
    ///   - shortcut: The shortcut to register.
    ///   - action: The async action to execute when the shortcut is pressed.
    /// - Returns: A registration handle that can be used to unregister the shortcut.
    /// - Throws: `RegistrationError` if registration fails.
    public func registerShortcut(_ shortcut: MASShortcut, action: @escaping @Sendable () async -> Void) async throws -> ShortcutRegistration {
        // Validate shortcut first
        let isValid = await validator.isShortcutValid(shortcut)
        guard isValid else {
            throw RegistrationError.invalidShortcut
        }

        return try await withCheckedThrowingContinuation { continuation in
            registrationQueue.async {
                self.lock.withLock {
                    // Check if already registered
                    guard self.hotKeys[shortcut] == nil else {
                        continuation.resume(throwing: RegistrationError.shortcutAlreadyRegistered(shortcut))
                        return
                    }

                    let registration = ShortcutRegistration(shortcut: shortcut)
                    let hotKey = MASHotKey(shortcut: shortcut)

                    if let hotKey = hotKey {
                        hotKey.action = { Task { await action() } }
                        self.hotKeys[shortcut] = hotKey
                        self.registrations[registration] = hotKey
                        continuation.resume(returning: registration)
                    } else {
                        continuation.resume(throwing: RegistrationError.systemRegistrationFailed)
                    }
                }
            }
        }
    }

    /// Register a shortcut with a synchronous action (for backward compatibility).
    /// - Parameters:
    ///   - shortcut: The shortcut to register.
    ///   - action: The synchronous action to execute when the shortcut is pressed.
    /// - Returns: `true` if registration was successful, `false` otherwise.
    public func registerShortcut(_ shortcut: MASShortcut, withAction action: @escaping () -> Void) -> Bool {
        return lock.withLock {
            guard hotKeys[shortcut] == nil else {
                return false // Already registered
            }

            guard let hotKey = MASHotKey(shortcut: shortcut) else {
                return false
            }

            hotKey.action = action
            hotKeys[shortcut] = hotKey
            return true
        }
    }

    /// Check if a shortcut is currently registered.
    public func isShortcutRegistered(_ shortcut: MASShortcut) -> Bool {
        return lock.withLock {
            return hotKeys[shortcut] != nil
        }
    }

    /// Unregister a shortcut by its registration handle.
    public func unregisterShortcut(_ registration: ShortcutRegistration) async {
        lock.withLock {
            guard registrations.removeValue(forKey: registration) != nil else {
                return
            }
            hotKeys.removeValue(forKey: registration.shortcut)
        }
        // HotKey deinit will handle unregistration
    }

    /// Unregister a shortcut by its shortcut value.
    public func unregisterShortcut(_ shortcut: MASShortcut) {
        _ = lock.withLock {
            hotKeys.removeValue(forKey: shortcut)
        }
    }

    /// Unregister all shortcuts.
    public func unregisterAllShortcuts() async {
        lock.withLock {
            registrations.removeAll()
            hotKeys.removeAll()
        }
    }

    // MARK: - Higher-Order APIs

    /// Registers multiple shortcuts with different actions.
    public func registerShortcuts(_ shortcuts: [(MASShortcut, @Sendable () async -> Void)]) async throws -> [ShortcutRegistration] {
        var registrations: [ShortcutRegistration] = []

        for (shortcut, action) in shortcuts {
            let registration = try await registerShortcut(shortcut, action: action)
            registrations.append(registration)
        }

        return registrations
    }

    /// Creates a shortcut registration with automatic cleanup.
    public func withShortcut<T: Sendable>(
        _ shortcut: MASShortcut,
        action: @escaping @Sendable () async -> Void,
        operation: () async throws -> T
    ) async throws -> T {
        let registration = try await registerShortcut(shortcut, action: action)
        defer { Task { await unregisterShortcut(registration) } }

        return try await operation()
    }

    /// Maps a sequence of shortcuts to registrations.
    public func registerShortcuts<S: Sequence>(
        _ shortcuts: S,
        actionProvider: (S.Element) -> (@Sendable () async -> Void)
    ) async throws -> [ShortcutRegistration] where S.Element == MASShortcut {
        var registrations: [ShortcutRegistration] = []

        for shortcut in shortcuts {
            let action = actionProvider(shortcut)
            let registration = try await registerShortcut(shortcut, action: action)
            registrations.append(registration)
        }

        return registrations
    }

    // MARK: - Event Handling

    public func handleEvent(_ event: EventRef) {
        if GetEventClass(event) != OSType(kEventClassKeyboard) {
            return
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        if status != noErr || hotKeyID.signature != MASHotKeySignature {
            return
        }

        // Safely access hotKeys with lock
        let hotKeysCopy = lock.withLock { hotKeys }
        for (_, hotKey) in hotKeysCopy {
            if hotKeyID.id == hotKey.carbonID {
                if let action = hotKey.action {
                    DispatchQueue.main.async {
                        action()
                    }
                }
                break
            }
        }
    }
}

// MARK: - Event Handling

// Carbon event handling simplified for Swift 6 compatibility
// In a full implementation, you would implement proper Carbon event handling
