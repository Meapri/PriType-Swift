import Foundation

#if DEBUG
import os.log
#endif

// MARK: - DebugLogger

/// Debug-only logger that is completely disabled in release builds
///
/// This logger uses conditional compilation to ensure that:
/// - In DEBUG builds: Full logging to file and console
/// - In RELEASE builds: All logging functions are no-ops (empty functions)
///
/// ## Security
/// For input methods, logging user keystrokes could be a security risk.
/// This implementation guarantees that **no logging code exists** in release builds,
/// not just disabled - the code is literally not compiled.
///
/// ## Usage
/// ```swift
/// DebugLogger.log("User pressed key")  // Only logs in DEBUG builds
/// ```
public final class DebugLogger: @unchecked Sendable {
    
    #if DEBUG
    
    // =========================================================================
    // MARK: - Debug Build (Full implementation)
    // =========================================================================
    
    // MARK: - Private Properties
    
    /// System logger for console output (fallback)
    private static let osLog = OSLog(subsystem: "com.pritype.inputmethod", category: "Debug")
    
    /// Serial queue for thread-safe file operations
    private static let logQueue = DispatchQueue(label: "com.pritype.logger", qos: .utility)
    
    /// Cached file handle for performance
    /// - Note: Protected by logQueue serial dispatch
    nonisolated(unsafe) private static var cachedHandle: FileHandle?
    
    /// Flag to prevent infinite recursion on logging errors
    /// - Note: Protected by logQueue serial dispatch
    nonisolated(unsafe) private static var isLoggingError = false
    
    // MARK: - Public API
    
    /// Cached date formatter for performance (avoid repeated allocations)
    /// - Note: Access is serialized via logQueue, so nonisolated(unsafe) is safe here.
    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    /// Log a debug message to file with console fallback
    /// - Parameter msg: The message to log
    /// - Note: Thread-safe. Falls back to system console if file logging fails.
    /// - Important: This function is only available in DEBUG builds.
    public static func log(_ msg: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logMsg = "[\(timestamp)] \(msg)\n"
        
        logQueue.async {
            guard let data = logMsg.data(using: .utf8) else {
                logToConsole("Failed to encode log message: \(msg)", isError: true)
                return
            }
            
            do {
                try writeToFile(data: data)
            } catch {
                // Fallback to console on file error (avoid infinite recursion)
                if !isLoggingError {
                    isLoggingError = true
                    logToConsole("File logging failed: \(error.localizedDescription)", isError: true)
                    logToConsole(msg, isError: false)
                    isLoggingError = false
                }
            }
        }
    }
    
    /// Log an error with context
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - context: Additional context about where the error occurred
    /// - Important: This function is only available in DEBUG builds.
    public static func logError(_ error: Error, context: String) {
        log("ERROR [\(context)]: \(error.localizedDescription)")
    }
    
    // MARK: - Private Methods
    
    private static func writeToFile(data: Data) throws {
        let url = URL(fileURLWithPath: PriTypeConfig.logPath)
        let directory = url.deletingLastPathComponent()
        
        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: PriTypeConfig.logPath) {
            FileManager.default.createFile(atPath: PriTypeConfig.logPath, contents: nil)
            cachedHandle = nil // Invalidate cache
        }
        
        // Get or create file handle
        if cachedHandle == nil {
            cachedHandle = FileHandle(forWritingAtPath: PriTypeConfig.logPath)
        }
        
        guard let handle = cachedHandle else {
            throw LoggingError.failedToOpenFile
        }
        
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
    
    private static func logToConsole(_ msg: String, isError: Bool) {
        if isError {
            os_log(.error, log: osLog, "%{public}@", msg)
        } else {
            os_log(.debug, log: osLog, "%{public}@", msg)
        }
    }
    
    // MARK: - Error Types
    
    private enum LoggingError: Error, LocalizedError {
        case failedToOpenFile
        
        var errorDescription: String? {
            switch self {
            case .failedToOpenFile:
                return "Failed to open log file for writing"
            }
        }
    }
    
    #else
    
    // =========================================================================
    // MARK: - Release Build (No-op implementations)
    // =========================================================================
    
    /// No-op in release builds - does nothing
    /// - Parameter msg: Ignored in release builds
    @inlinable
    public static func log(_ msg: String) {
        // Intentionally empty - no logging in release builds for security
    }
    
    /// No-op in release builds - does nothing
    @inlinable
    public static func logError(_ error: Error, context: String) {
        // Intentionally empty - no logging in release builds for security
    }
    
    #endif
}
