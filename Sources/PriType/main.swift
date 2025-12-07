import Foundation
import InputMethodKit
import PriTypeCore

let kConnectionName = "PriType_InputString_v2"

class Application {
    static func main() {
        DebugLogger.log("Application main() started")
        DebugLogger.log("Configuration: ConnectionName=\(kConnectionName)")
        
        let server = IMKServer(name: kConnectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
        DebugLogger.log("IMKServer initialized")
        
        // Setup Right Command toggle
        setupEventTap()
        
        RunLoop.main.run()
    }
    
    static func setupEventTap() {
        // Check/request Accessibility permission
        if !EventTapManager.hasAccessibilityPermission() {
            DebugLogger.log("Requesting Accessibility permission...")
            EventTapManager.requestAccessibilityPermission()
            // Don't start tap yet - user needs to grant permission
            return
        }
        
        // Set callback
        EventTapManager.shared.onRightCommandToggle = {
            PriTypeInputController.sharedComposer.toggleInputMode()
        }
        
        // Start monitoring
        EventTapManager.shared.start()
    }
}

Application.main()

