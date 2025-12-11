import Foundation
import Cocoa
import ApplicationServices

/// Primary toggle key handler using CGEventTap.
///
/// ## Role
/// Intercepts Right Command and Control+Space key events at the system level
/// using CGEventTap to provide instant language mode switching.
///
/// ## Relationship with IOKitManager
/// - **Primary handler**: `RightCommandSuppressor` (this class)
/// - **Backup handler**: `IOKitManager`
///
/// This class uses `IOKitManager.hasAccessibilityPermission()` to check permissions.
/// If CGEventTap creation fails (e.g., permission issues), `IOKitManager` takes over.
///
/// ## Key Features
/// - **Instant toggle**: Switches on key press, not release
/// - **Modifier stripping**: When Right Command is held, removes Command modifier from other keys
/// - **Control+Space support**: Alternative toggle key combination
public final class RightCommandSuppressor: @unchecked Sendable {
    
    // Singleton - accessed from CGEventTap callback context
    public static let shared = RightCommandSuppressor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    /// Callback for toggle
    public var onToggle: (@Sendable () -> Void)?
    
    /// Track Right Command state
    private var rightCommandIsDown = false
    
    // Key codes are centralized in KeyCode enum
    
    /// Track Control state for Control+Space
    private var controlIsDown = false
    
    private init() {}
    
    // MARK: - Start/Stop
    
    /// Start monitoring toggle keys
    /// - Returns: `true` if CGEventTap was created successfully, `false` otherwise
    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else {
            DebugLogger.log("RightCommandSuppressor: Already running")
            return true
        }
        
        guard IOKitManager.hasAccessibilityPermission() else {
            DebugLogger.log("RightCommandSuppressor: No Accessibility permission")
            return false
        }
        
        // Monitor flagsChanged AND keyDown events
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        
        // Create event tap
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let suppressor = Unmanaged<RightCommandSuppressor>.fromOpaque(refcon).takeUnretainedValue()
                return suppressor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            DebugLogger.log("RightCommandSuppressor: Failed to create event tap")
            return false
        }
        
        // Add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        DebugLogger.log("RightCommandSuppressor: Started (monitoring Right Command + Control+Space)")
        return true
    }
    
    /// Stop monitoring
    public func stop() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        DebugLogger.log("RightCommandSuppressor: Stopped")
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if disabled by system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let config = ConfigurationManager.shared
        
        // Handle flagsChanged (modifier keys)
        if type == .flagsChanged {
            let flags = event.flags
            
            // Track Control key state
            controlIsDown = flags.contains(.maskControl)
            
            // Right Command toggle - INSTANT (toggle on press)
            if keyCode == KeyCode.rightCommand && config.rightCommandAsToggle {
                let commandPressed = flags.contains(.maskCommand)
                
                if commandPressed && !rightCommandIsDown {
                    // Right Command pressed - toggle immediately!
                    rightCommandIsDown = true
                    DebugLogger.log("RightCommandSuppressor: Right Command DOWN - TOGGLE (instant)")
                    triggerToggle()
                    return nil  // Suppress the modifier event
                } else if !commandPressed && rightCommandIsDown {
                    // Right Command released
                    rightCommandIsDown = false
                    DebugLogger.log("RightCommandSuppressor: Right Command UP")
                    return nil  // Suppress release
                }
            }
            
            return Unmanaged.passRetained(event)
        }
        
        // Handle keyDown
        if type == .keyDown {
            // Control+Space toggle
            if keyCode == KeyCode.spaceInt64 && controlIsDown && config.controlSpaceAsToggle {
                DebugLogger.log("RightCommandSuppressor: Control+Space - TOGGLE triggered")
                triggerToggle()
                return nil  // Suppress the space
            }
            
            // When Right Command is held, strip the Command modifier from key events
            // This makes keys act as regular character input, not shortcuts
            if rightCommandIsDown && config.rightCommandAsToggle {
                // Remove Command flag from the event
                var newFlags = event.flags
                newFlags.remove(.maskCommand)
                event.flags = newFlags
                DebugLogger.log("RightCommandSuppressor: Key with Right Command - stripped modifier (normal input)")
                // Let the modified event pass through
                return Unmanaged.passRetained(event)
            }
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func triggerToggle() {
        let callback = onToggle
        DispatchQueue.main.async {
            callback?()
        }
    }
}
