import Foundation
import InputMethodKit
import PriTypeCore

let kConnectionName = "PriType_InputString_v2"

class Application {
    static func main() {
        let server = IMKServer(name: kConnectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
        RunLoop.main.run()
    }
}

Application.main()
