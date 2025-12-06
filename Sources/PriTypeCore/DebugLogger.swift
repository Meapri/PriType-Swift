import Foundation

public class DebugLogger {
    public static func log(_ msg: String) {
        let logMsg = "\(Date()): \(msg)\n"
        guard let data = logMsg.data(using: .utf8) else { return }
        
        let url = URL(fileURLWithPath: PriTypeConfig.logPath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = FileHandle(forWritingAtPath: PriTypeConfig.logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try logMsg.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // Ignore log error
        }
    }
}
