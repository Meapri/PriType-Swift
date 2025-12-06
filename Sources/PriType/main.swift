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
        RunLoop.main.run()
    }
}

Application.main()
