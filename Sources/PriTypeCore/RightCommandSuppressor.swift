import Foundation
import Cocoa
import ApplicationServices

/// Primary toggle key handler using CGEventTap.
///
/// ## Role
/// Intercepts user-configured toggle and hanja key events at the system level
/// using CGEventTap to provide instant language mode switching.
///
/// ## Dynamic Key Binding
/// Instead of hardcoded keys, this class reads `ConfigurationManager.toggleKeyBinding`
/// and `ConfigurationManager.hanjaKeyBinding` to determine which keys to intercept.
/// Users can configure any modifier key or key combination via the Settings UI.
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
/// - **Modifier stripping**: When toggle modifier is held, removes its modifier from other keys
/// - **Dynamic binding**: Supports any key via KeyBinding struct
public final class RightCommandSuppressor: @unchecked Sendable {
    
    // Singleton - accessed from CGEventTap callback context
    public static let shared = RightCommandSuppressor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    /// Callback for toggle
    public var onToggle: (@Sendable () -> Void)?
    
    /// Callback for Hanja lookup
    public var onHanjaLookup: (@Sendable () -> Void)?
    
    /// Track toggle modifier state
    private var toggleModifierIsDown = false
    
    /// Track hanja modifier state
    private var hanjaModifierIsDown = false
    
    /// Debounce timer for Hanja trigger to prevent double-fire
    private var lastHanjaTriggerTime: DispatchTime = .init(uptimeNanoseconds: 0)
    
    /// Track Control state for Control+Space
    private var controlIsDown = false
    
    /// Track CGEventTap disable events for auto-recovery
    private var tapDisableCount = 0
    private var lastTapDisableTime: CFAbsoluteTime = 0
    private let maxTapDisableRetries = 3
    private let tapDisableResetInterval: CFAbsoluteTime = 60  // Reset counter after 60s of stability
    
    /// Callback for when CGEventTap permanently fails and IOKit should take over
    public var onTapFailed: (@Sendable () -> Void)?
    
    /// Whether recording mode is active (for Key Recorder in settings)
    public var isRecordingKey = false
    
    /// Callback for key recording (settings UI)
    public var onKeyRecorded: ((_ keyCode: Int64, _ modifiers: UInt64) -> Void)?
    
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
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
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
        
        let config = ConfigurationManager.shared
        DebugLogger.log("RightCommandSuppressor: Started (toggle=\(config.toggleKeyBinding.displayName), hanja=\(config.hanjaKeyBinding.displayName))")
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
            let now = CFAbsoluteTimeGetCurrent()
            
            // Reset counter if stable for 60+ seconds
            if now - lastTapDisableTime > tapDisableResetInterval {
                tapDisableCount = 0
            }
            lastTapDisableTime = now
            tapDisableCount += 1
            
            if tapDisableCount >= maxTapDisableRetries {
                // CGEventTap is repeatedly failing — switch to IOKit backup
                DebugLogger.log("RightCommandSuppressor: Tap disabled \(tapDisableCount) times, switching to IOKit fallback")
                let callback = onTapFailed
                DispatchQueue.main.async {
                    callback?()
                }
                // Still try to re-enable in case IOKit also needs it
            } else {
                DebugLogger.log("RightCommandSuppressor: Tap disabled (\(tapDisableCount)/\(maxTapDisableRetries)), re-enabling")
            }
            
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let config = ConfigurationManager.shared
        let toggleBinding = config.toggleKeyBinding
        let hanjaBinding = config.hanjaKeyBinding
        
        // Key recording mode — capture the next key press for settings UI
        if isRecordingKey {
            if type == .flagsChanged {
                let flags = event.flags
                // Only fire on key DOWN (when a new modifier appears)
                let isModifierDown = flags.rawValue & 0xFFFF0000 != 0
                if isModifierDown {
                    let recordCallback = onKeyRecorded
                    DispatchQueue.main.async {
                        recordCallback?(keyCode, 0)  // modifier-only binding
                    }
                    return nil  // Suppress
                }
            } else if type == .keyDown {
                let modifiers = event.flags.rawValue & 0xFFFF0000  // Keep only modifier flags
                let recordCallback = onKeyRecorded
                DispatchQueue.main.async {
                    recordCallback?(keyCode, modifiers)
                }
                return nil  // Suppress
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Handle flagsChanged (modifier keys)
        if type == .flagsChanged {
            let flags = event.flags
            
            // Track Control key state (for Control+Space combo)
            controlIsDown = flags.contains(.maskControl)
            
            // Dynamic toggle key — modifier key, single-key binding
            if toggleBinding.isModifierKey && toggleBinding.isModifierOnly && keyCode == toggleBinding.keyCode {
                let modifierMask = Self.modifierMask(for: keyCode)
                let isPressed = flags.contains(modifierMask)
                
                if isPressed && !toggleModifierIsDown {
                    // Toggle modifier pressed - toggle immediately!
                    toggleModifierIsDown = true
                    DebugLogger.log("RightCommandSuppressor: Toggle key DOWN (\(toggleBinding.displayName)) - TOGGLE (instant)")
                    triggerToggle()
                    return nil  // Suppress the modifier event
                } else if !isPressed && toggleModifierIsDown {
                    // Toggle modifier released
                    toggleModifierIsDown = false
                    DebugLogger.log("RightCommandSuppressor: Toggle key UP (\(toggleBinding.displayName))")
                    return nil  // Suppress release
                }
            }
            
            // Dynamic hanja key — modifier key, single-key binding (only if different from toggle key)
            if hanjaBinding.isModifierKey && hanjaBinding.isModifierOnly && keyCode == hanjaBinding.keyCode && keyCode != toggleBinding.keyCode {
                let modifierMask = Self.modifierMask(for: keyCode)
                let isPressed = flags.contains(modifierMask)
                
                if isPressed && !hanjaModifierIsDown {
                    hanjaModifierIsDown = true
                    
                    // Debounce: ignore if last trigger was within 500ms
                    let now = DispatchTime.now()
                    let elapsed = now.uptimeNanoseconds - lastHanjaTriggerTime.uptimeNanoseconds
                    let elapsedMs = elapsed / 1_000_000
                    if elapsedMs < 500 {
                        DebugLogger.log("RightCommandSuppressor: Hanja key DEBOUNCED (\(elapsedMs)ms)")
                        return nil
                    }
                    lastHanjaTriggerTime = now
                    
                    DebugLogger.log("RightCommandSuppressor: Hanja key DOWN (\(hanjaBinding.displayName)) - HANJA")
                    triggerHanjaLookup()
                    return nil  // Suppress
                } else if !isPressed && hanjaModifierIsDown {
                    hanjaModifierIsDown = false
                    DebugLogger.log("RightCommandSuppressor: Hanja key UP (\(hanjaBinding.displayName))")
                    return nil  // Suppress release
                }
            }
            
            return Unmanaged.passUnretained(event)
        }
        
        // Handle keyDown
        if type == .keyDown {
            // Regular key (non-modifier) as toggle — single key or combo
            if keyCode == toggleBinding.keyCode && !toggleBinding.isModifierKey {
                if toggleBinding.isModifierOnly {
                    // Single regular key as toggle (e.g., F13, Caps Lock via keyDown)
                    DebugLogger.log("RightCommandSuppressor: Regular key toggle (\(toggleBinding.displayName)) - TOGGLE")
                    triggerToggle()
                    return nil
                } else {
                    // Combo toggle (e.g., Control+Space, Option+G)
                    let requiredFlags = CGEventFlags(rawValue: toggleBinding.modifiers)
                    if Self.hasRequiredModifiers(flags: event.flags, required: requiredFlags) {
                        DebugLogger.log("RightCommandSuppressor: Combo toggle (\(toggleBinding.displayName)) - TOGGLE triggered")
                        triggerToggle()
                        return nil
                    }
                }
            }
            
            // Regular key (non-modifier) as hanja — single key or combo
            if keyCode == hanjaBinding.keyCode && !hanjaBinding.isModifierKey && keyCode != toggleBinding.keyCode {
                if hanjaBinding.isModifierOnly || Self.hasRequiredModifiers(flags: event.flags, required: CGEventFlags(rawValue: hanjaBinding.modifiers)) {
                    DebugLogger.log("RightCommandSuppressor: Regular key hanja (\(hanjaBinding.displayName)) - HANJA")
                    triggerHanjaLookup()
                    return nil
                }
            }
            
            
            // When toggle modifier is held, strip its modifier from key events
            // This makes keys act as regular character input, not shortcuts
            if toggleModifierIsDown && toggleBinding.isModifierKey {
                let modifierMask = Self.modifierMask(for: toggleBinding.keyCode)
                var newFlags = event.flags
                newFlags.remove(modifierMask)
                event.flags = newFlags
                DebugLogger.log("RightCommandSuppressor: Key with toggle modifier - stripped modifier (normal input)")
                return Unmanaged.passUnretained(event)
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    // MARK: - Helpers
    
    /// Get the CGEventFlags modifier mask for a given keyCode
    private static func modifierMask(for keyCode: Int64) -> CGEventFlags {
        switch keyCode {
        case 54, 55: return .maskCommand       // Right/Left Command
        case 61, 58: return .maskAlternate      // Right/Left Option
        case 62, 59: return .maskControl        // Right/Left Control
        case 56, 60: return .maskShift          // Left/Right Shift
        case 57:     return .maskAlphaShift     // Caps Lock
        default:     return CGEventFlags(rawValue: 0)
        }
    }
    
    /// Check if event flags contain required modifier flags
    private static func hasRequiredModifiers(flags: CGEventFlags, required: CGEventFlags) -> Bool {
        return flags.intersection(required) == required
    }
    
    private func triggerToggle() {
        let callback = onToggle
        DispatchQueue.main.async {
            callback?()
        }
    }
    
    private func triggerHanjaLookup() {
        let callback = onHanjaLookup
        DispatchQueue.main.async {
            callback?()
        }
    }
}
