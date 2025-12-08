import Foundation
import Cocoa
import ApplicationServices

/// CGEventTap to handle toggle keys for language switching
/// Supports: Right Command (instant + normal keys), Control+Space
public final class RightCommandSuppressor {
    
    // Singleton
    nonisolated(unsafe) public static let shared = RightCommandSuppressor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    /// Callback for toggle
    public var onToggle: (@Sendable () -> Void)?
    
    /// Track Right Command state
    private var rightCommandIsDown = false
    
    /// Right Command keyCode
    private let rightCommandKeyCode: Int64 = 54
    
    /// Control keyCode
    private let controlKeyCode: Int64 = 59
    private let rightControlKeyCode: Int64 = 62
    
    /// Space keyCode
    private let spaceKeyCode: Int64 = 49
    
    /// Track Control state for Control+Space
    private var controlIsDown = false
    
    private init() {}
    
    // MARK: - Start/Stop
    
    /// Start monitoring toggle keys
    public func start() {
        guard eventTap == nil else {
            DebugLogger.log("RightCommandSuppressor: Already running")
            return
        }
        
        guard IOKitManager.hasAccessibilityPermission() else {
            DebugLogger.log("RightCommandSuppressor: No Accessibility permission")
            return
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
            return
        }
        
        // Add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        DebugLogger.log("RightCommandSuppressor: Started (monitoring Right Command + Control+Space)")
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
            if keyCode == rightCommandKeyCode && config.rightCommandAsToggle {
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
            if keyCode == spaceKeyCode && controlIsDown && config.controlSpaceAsToggle {
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

