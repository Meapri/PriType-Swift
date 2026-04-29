import Foundation
import InputMethodKit
import Cocoa
import PriTypeCore

let kConnectionName = "PriType_InputString_v2"

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var hasLaunchedBefore = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLogger.log("AppDelegate: applicationDidFinishLaunching")
        
        // Initialize IMK Server
        _ = IMKServer(name: kConnectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
        DebugLogger.log("IMKServer initialized")
        
        // Setup status bar indicator
        DispatchQueue.main.async {
            StatusBarManager.shared.setup()
        }
        
        // Setup Right Command toggle via IOKit
        setupIOKit()
        
        // Pre-load Hanja dictionary in background for instant lookup
        DispatchQueue.global(qos: .utility).async {
            HanjaManager.shared.loadIfNeeded()
        }
        
        // Setup update notifications
        UpdateNotifier.shared.setup()
        
        // Check for updates in background (respects user preference and 24h throttle)
        if ConfigurationManager.shared.autoUpdateCheckEnabled {
            Task.detached(priority: .utility) {
                let result = await UpdateChecker.shared.checkForUpdatesIfNeeded()
                if case .updateAvailable(let info) = result {
                    UpdateNotifier.shared.notifyUpdateAvailable(info)
                }
            }
        }
        
        // Mark as launched (don't show settings on first boot)
        hasLaunchedBefore = true
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DebugLogger.log("AppDelegate: applicationShouldHandleReopen")
        // Only show settings when explicitly launched from Launchpad/Finder (reopen)
        DispatchQueue.main.async {
            SettingsWindowController.shared.showSettings()
        }
        return true
    }
    
    private func setupIOKit() {
        // Check/request Accessibility permission
        if !IOKitManager.hasAccessibilityPermission() {
            DebugLogger.log("Requesting Accessibility permission...")
            IOKitManager.requestAccessibilityPermission()
            return
        }
        
        // Set callback for CGEventTap toggle handler (handles all toggle keys)
        RightCommandSuppressor.shared.onToggle = {
            PriTypeInputController.sharedComposer.toggleInputMode()
        }
        
        // Set callback for Right Option key → Hanja lookup
        RightCommandSuppressor.shared.onHanjaLookup = {
            PriTypeInputController.sharedComposer.triggerHanjaLookup()
        }
        
        // Track if CGEventTap started successfully
        let eventTapStarted = RightCommandSuppressor.shared.start()
        
        // IOKit backup: Only start and activate actual toggle if CGEventTap failed
        if eventTapStarted {
            DebugLogger.log("Primary: CGEventTap started successfully")
            // Register fallback: if CGEventTap dies repeatedly, switch to IOKit
            RightCommandSuppressor.shared.onTapFailed = {
                DebugLogger.log("CGEventTap failed repeatedly — activating IOKit fallback")
                IOKitManager.shared.onRightCommandToggle = {
                    PriTypeInputController.sharedComposer.toggleInputMode()
                }
                IOKitManager.shared.onRightOptionHanja = {
                    PriTypeInputController.sharedComposer.triggerHanjaLookup()
                }
                IOKitManager.shared.start()
            }
        } else {
            DebugLogger.log("Primary: CGEventTap FAILED - IOKit taking over as primary")
            // IOKit takes over as primary toggle handler
            IOKitManager.shared.onRightCommandToggle = {
                PriTypeInputController.sharedComposer.toggleInputMode()
            }
            IOKitManager.shared.onRightOptionHanja = {
                PriTypeInputController.sharedComposer.triggerHanjaLookup()
            }
            IOKitManager.shared.start()
        }
        
        DebugLogger.log("Toggle key monitoring initialized")
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
