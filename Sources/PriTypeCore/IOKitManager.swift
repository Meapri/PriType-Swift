import Foundation
import IOKit
import IOKit.hid
import ApplicationServices

/// Manager for IOHIDManager to detect Right Command key at hardware level
/// Handles toggle directly without EventTapManager
public final class IOKitManager {
    
    // Singleton
    nonisolated(unsafe) public static let shared = IOKitManager()
    
    private var manager: IOHIDManager?
    
    /// Callback when Right Command is pressed alone
    public var onRightCommandToggle: (@Sendable () -> Void)?
    
    /// Track Right Command state
    private var rightCommandIsDown = false
    private var anyOtherKeyPressed = false
    
    /// Right Command usage constant (kHIDUsage_KeyboardRightGUI = 0xE7 = 231)
    private let rightCommandUsage: UInt32 = 0xE7  // kHIDUsage_KeyboardRightGUI
    
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
    
    // MARK: - Start/Stop
    
    /// Start monitoring keyboard events via IOHIDManager
    public func start() {
        guard manager == nil else {
            DebugLogger.log("IOKitManager: Already running")
            return
        }
        
        DebugLogger.log("IOKitManager: Starting IOKit-only toggle detection...")
        
        // Create HID Manager
        let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = hidManager
        
        // Match keyboard devices
        let matchingDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(hidManager, matchingDict as CFDictionary)
        
        // No input value matching - receive ALL keyboard events
        IOHIDManagerSetInputValueMatching(hidManager, nil)
        
        // Set input value callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(hidManager, { context, result, sender, value in
            guard let context = context else { return }
            let manager = Unmanaged<IOKitManager>.fromOpaque(context).takeUnretainedValue()
            manager.handleInputValue(value)
        }, context)
        
        // Schedule with current run loop (like Gureum)
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        
        // Open manager
        let result = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            DebugLogger.log("IOKitManager: Failed to open IOHIDManager: \(result)")
            manager = nil
            return
        }
        
        DebugLogger.log("IOKitManager: Started successfully (IOKit-only mode)")
    }
    
    /// Stop monitoring
    public func stop() {
        guard let hidManager = manager else { return }
        
        IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        
        DebugLogger.log("IOKitManager: Stopped")
    }
    
    // MARK: - Input Handling
    
    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        let pressed = intValue > 0
        
        // Only interested in keyboard page
        guard usagePage == kHIDPage_KeyboardOrKeypad else { return }
        
        // Log events for debugging (limit to modifiers to reduce noise)
        if usage >= 0xE0 && usage <= 0xE7 {
            DebugLogger.log("IOKitManager: Modifier key 0x\(String(usage, radix: 16)) \(pressed ? "DOWN" : "UP")")
        }
        
        // Note: Caps Lock toggle is handled by RightCommandSuppressor (CGEventTap)
        // IOKitManager no longer handles Caps Lock to avoid duplicate toggles
        
        // Check for Right Command (Right GUI) key - only if enabled
        if usage == rightCommandUsage && ConfigurationManager.shared.rightCommandAsToggle {
            if pressed {
                // Right Command pressed
                rightCommandIsDown = true
                anyOtherKeyPressed = false
                DebugLogger.log("IOKitManager: Right Command DOWN")
            } else {
                // Right Command released
                if rightCommandIsDown && !anyOtherKeyPressed {
                    // Toggle!
                    DebugLogger.log("IOKitManager: TOGGLE triggered!")
                    let callback = onRightCommandToggle
                    DispatchQueue.main.async {
                        callback?()
                    }
                } else if anyOtherKeyPressed {
                    DebugLogger.log("IOKitManager: Toggle skipped (used with other key)")
                }
                rightCommandIsDown = false
                anyOtherKeyPressed = false
            }
        } else if rightCommandIsDown && pressed && usage > 0 && usage < 0xE0 {
            // Non-modifier key pressed while Right Command is down
            anyOtherKeyPressed = true
            DebugLogger.log("IOKitManager: Key pressed while Right Command is down (combo)")
        }
    }
}
