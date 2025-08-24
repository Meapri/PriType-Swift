import AppKit
import Carbon
import Foundation

public let MASHotKeySignature: FourCharCode = {
    if let code = FourCharCode("MASS") {
        return code
    } else {
        // Fallback value
        return FourCharCode(0x4D415353) // "MASS" in hex
    }
}()

/**
 MASHotKey represents a registered global hotkey that can trigger actions.
 */
public class MASHotKey: NSObject {

    // MARK: - Properties

    public private(set) var carbonID: UInt32
    public var action: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?

    // MARK: - Initialization

    public init?(shortcut: MASShortcut) {
        self.carbonID = 0
        super.init()

        // Generate unique Carbon ID using simple increment
        struct StaticHolder {
            nonisolated(unsafe) static var carbonHotKeyID: UInt32 = 0
        }
        StaticHolder.carbonHotKeyID += 1
        self.carbonID = StaticHolder.carbonHotKeyID

        let hotKeyID = EventHotKeyID(signature: MASHotKeySignature, id: carbonID)

        let status = RegisterEventHotKey(
            shortcut.carbonKeyCode,
            shortcut.carbonFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            return nil
        }
    }

    public class func registeredHotKey(with shortcut: MASShortcut) -> MASHotKey? {
        return MASHotKey(shortcut: shortcut)
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}
