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
        
        // Start CGEventTap (handles Control+Space, Right Command, Caps Lock)
        RightCommandSuppressor.shared.start()
        
        // Start IOKit monitoring as backup for hardware-level detection
        IOKitManager.shared.onRightCommandToggle = {
            // Only trigger if not handled by CGEventTap
            DebugLogger.log("IOKitManager toggle (backup)")
        }
        IOKitManager.shared.start()
        
        DebugLogger.log("Toggle key monitoring started (CGEventTap + IOKit backup)")
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
