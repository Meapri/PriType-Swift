import Foundation
import Cocoa
import ApplicationServices

/// Manager for CGEventTap to detect Right Command key for language toggle
public final class EventTapManager {
    
    // Singleton - nonisolated(unsafe) for Swift 6 concurrency
    nonisolated(unsafe) public static let shared = EventTapManager()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    /// Callback when Right Command is pressed alone (no other keys)
    public var onRightCommandToggle: (@Sendable () -> Void)?
    
    /// Track state
    private var rightCommandIsDown = false
    private var rightCommandUsedWithOtherKey = false
    
    /// Right Command keyCode
    private let rightCommandKeyCode: Int64 = 54
    
    private init() {}
    
    // MARK: - Accessibility Permission
    
    /// Check if Accessibility permission is granted
    public static func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /// Request Accessibility permission (shows system dialog)
    public static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Event Tap
    
    /// Start monitoring for Right Command key
    public func start() {
        guard eventTap == nil else {
            DebugLogger.log("EventTapManager: Already running")
            return
        }
        
        guard EventTapManager.hasAccessibilityPermission() else {
            DebugLogger.log("EventTapManager: No Accessibility permission")
            return
        }
        
        // Monitor flagsChanged and keyDown events
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        
        // Create event tap
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            DebugLogger.log("EventTapManager: Failed to create event tap")
            return
        }
        
        // Add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        DebugLogger.log("EventTapManager: Started monitoring Right Command")
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
        DebugLogger.log("EventTapManager: Stopped")
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
        
        // Handle flagsChanged (modifier key press/release)
        if type == .flagsChanged {
            let flags = event.flags
            let commandPressed = flags.contains(.maskCommand)
            
            if keyCode == rightCommandKeyCode {
                if commandPressed {
                    // Right Command pressed down
                    rightCommandIsDown = true
                    rightCommandUsedWithOtherKey = false
                    DebugLogger.log("EventTapManager: Right Command DOWN")
                } else if rightCommandIsDown {
                    // Right Command released
                    DebugLogger.log("EventTapManager: Right Command UP, usedWithOther=\(rightCommandUsedWithOtherKey)")
                    
                    if !rightCommandUsedWithOtherKey {
                        // Toggle!
                        DebugLogger.log("EventTapManager: TOGGLE triggered")
                        let callback = onRightCommandToggle
                        DispatchQueue.main.async {
                            callback?()
                        }
                    }
                    
                    rightCommandIsDown = false
                    rightCommandUsedWithOtherKey = false
                    
                    // Consume the event
                    return nil
                }
            }
        }
        
        // Handle keyDown (mark as used with other key)
        if type == .keyDown && rightCommandIsDown {
            rightCommandUsedWithOtherKey = true
            DebugLogger.log("EventTapManager: Right Command used with key \(keyCode)")
        }
        
        return Unmanaged.passRetained(event)
    }
}
