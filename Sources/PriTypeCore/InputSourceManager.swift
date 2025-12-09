import Foundation
import Carbon

// MARK: - InputSourceManager

/// Manages macOS input sources via shell commands and defaults
///
/// Direct plist file modification is ignored by cfprefsd daemon.
/// This implementation uses shell commands (defaults, PlistBuddy) which properly
/// interact with the preference system.
///
/// ## Usage
/// ```swift
/// InputSourceManager.shared.removeABCInputSource { success in
///     if success { print("ABC removed, please restart") }
/// }
/// ```
public final class InputSourceManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance
    nonisolated(unsafe) public static let shared = InputSourceManager()
    
    private init() {}
    
    // MARK: - Constants
    
    /// Path to the HIToolbox preferences plist
    private static let hiToolboxPlist = "~/Library/Preferences/com.apple.HIToolbox.plist"
    
    /// Keyboard Layout ID for ABC (252)
    public static let abcKeyboardLayoutID = 252
    
    // MARK: - Public API
    
    /// Check if ABC keyboard is in the enabled input sources
    /// - Returns: `true` if ABC is enabled, `false` otherwise
    public func isABCEnabledInPlist() -> Bool {
        // Use shell to check
        let result = runShellCommand("/usr/libexec/PlistBuddy -c 'Print :AppleEnabledInputSources' \(Self.hiToolboxPlist) 2>/dev/null | grep -q 'ABC'")
        return result == 0
    }
    
    /// Remove ABC keyboard from input sources using shell commands
    /// This properly interacts with cfprefsd
    /// - Returns: `true` if successful
    @discardableResult
    public func removeABCFromPlist() -> Bool {
        // Find the index of ABC in AppleEnabledInputSources
        guard let abcIndex = findABCIndex() else {
            #if DEBUG
            DebugLogger.log("InputSourceManager: ABC not found in plist")
            #endif
            return false
        }
        
        // Delete the entry using PlistBuddy
        let deleteCmd = "/usr/libexec/PlistBuddy -c 'Delete :AppleEnabledInputSources:\(abcIndex)' \(Self.hiToolboxPlist)"
        let result = runShellCommand(deleteCmd)
        
        if result == 0 {
            // Kill cfprefsd to force reload preferences
            _ = runShellCommand("killall cfprefsd 2>/dev/null || true")
            
            #if DEBUG
            DebugLogger.log("InputSourceManager: Removed ABC at index \(abcIndex)")
            #endif
            return true
        }
        
        #if DEBUG
        DebugLogger.log("InputSourceManager: Failed to remove ABC, exit code: \(result)")
        #endif
        return false
    }
    
    /// Add ABC keyboard back to input sources
    /// - Returns: `true` if successful
    @discardableResult
    public func addABCToPlist() -> Bool {
        // Check if already exists
        if isABCEnabledInPlist() {
            #if DEBUG
            DebugLogger.log("InputSourceManager: ABC already exists")
            #endif
            return true
        }
        
        // First, count current entries to get the next index
        let countCmd = "/usr/libexec/PlistBuddy -c 'Print :AppleEnabledInputSources' \(Self.hiToolboxPlist) 2>/dev/null | grep -c 'Dict'"
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", countCmd]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        var nextIndex = 0
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let count = Int(output) {
                nextIndex = count
            }
        } catch {
            // Default to appending at index 0 if count fails
        }
        
        // Add ABC entry using PlistBuddy - add dict first, then set its properties
        let plistPath = Self.hiToolboxPlist
        
        // Use a single compound command to ensure atomicity
        let addCmd = """
            /usr/libexec/PlistBuddy \
            -c 'Add :AppleEnabledInputSources:\(nextIndex) dict' \
            -c 'Set :AppleEnabledInputSources:\(nextIndex):InputSourceKind "Keyboard Layout"' \
            -c 'Set :AppleEnabledInputSources:\(nextIndex):KeyboardLayout\\ ID 252' \
            -c 'Set :AppleEnabledInputSources:\(nextIndex):KeyboardLayout\\ Name ABC' \
            \(plistPath)
            """
        
        let result = runShellCommand(addCmd)
        
        if result != 0 {
            #if DEBUG
            DebugLogger.log("InputSourceManager: Failed to add ABC with compound command, trying alternative")
            #endif
            
            // Try alternative: use individual commands
            _ = runShellCommand("/usr/libexec/PlistBuddy -c 'Add :AppleEnabledInputSources:\(nextIndex) dict' \(plistPath)")
            _ = runShellCommand("/usr/libexec/PlistBuddy -c 'Add :AppleEnabledInputSources:\(nextIndex):InputSourceKind string \"Keyboard Layout\"' \(plistPath)")
            _ = runShellCommand("/usr/libexec/PlistBuddy -c 'Add :AppleEnabledInputSources:\(nextIndex):KeyboardLayout\\ ID integer 252' \(plistPath)")
            _ = runShellCommand("/usr/libexec/PlistBuddy -c 'Add :AppleEnabledInputSources:\(nextIndex):KeyboardLayout\\ Name string ABC' \(plistPath)")
        }
        
        // Kill cfprefsd to force reload
        _ = runShellCommand("killall cfprefsd 2>/dev/null || true")
        
        // Verify it was added
        let success = isABCEnabledInPlist()
        
        #if DEBUG
        if success {
            DebugLogger.log("InputSourceManager: Added ABC at index \(nextIndex) successfully")
        } else {
            DebugLogger.log("InputSourceManager: Failed to verify ABC was added")
        }
        #endif
        
        return success
    }
    
    // MARK: - Convenience Methods
    
    /// Disable ABC (alias for removeABCFromPlist)
    @discardableResult
    public func disableABC() -> Bool {
        return removeABCFromPlist()
    }
    
    /// Enable ABC (alias for addABCToPlist)
    @discardableResult
    public func enableABC() -> Bool {
        return addABCToPlist()
    }
    
    // MARK: - TIS API Methods (for listing)
    
    /// Get a list of all enabled keyboard input sources using TIS API
    public func getEnabledKeyboardInputSources() -> [(id: String, name: String)] {
        var result: [(id: String, name: String)] = []
        
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true
        ]
        
        guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return result
        }
        
        for source in sourceList {
            if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
               let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
                let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
                result.append((id: id, name: name))
            }
        }
        
        return result
    }
    
    /// Check if ABC is enabled via TIS API
    public func isABCEnabled() -> Bool {
        let sources = getEnabledKeyboardInputSources()
        return sources.contains { $0.name == "ABC" || $0.id.contains("ABC") }
    }
    
    /// Check if US is enabled via TIS API  
    public func isUSEnabled() -> Bool {
        let sources = getEnabledKeyboardInputSources()
        return sources.contains { $0.id.contains("US") || $0.name == "U.S." }
    }
    
    /// Disable US (redirects to ABC)
    @discardableResult
    public func disableUS() -> Bool {
        return removeABCFromPlist()
    }
    
    /// Enable US (redirects to ABC)
    @discardableResult
    public func enableUS() -> Bool {
        return addABCToPlist()
    }
    
    // MARK: - Private Methods
    
    /// Find the index of ABC in AppleEnabledInputSources
    private func findABCIndex() -> Int? {
        // Get the plist content as text
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "plutil -p \(Self.hiToolboxPlist) 2>/dev/null"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            // Parse the output to find ABC index
            // Looking for pattern like:
            //   3 => {
            //     "KeyboardLayout Name" => "ABC"
            let lines = output.components(separatedBy: "\n")
            var currentIndex: Int?
            
            for line in lines {
                // Match index line like "    3 => {"
                if let match = line.range(of: #"^\s+(\d+)\s+=>\s+\{"#, options: .regularExpression) {
                    let indexStr = line[match].trimmingCharacters(in: .whitespaces)
                    if let idx = Int(indexStr.components(separatedBy: " ").first ?? "") {
                        currentIndex = idx
                    }
                }
                
                // Check for ABC in this entry
                if line.contains("\"KeyboardLayout Name\"") && line.contains("\"ABC\"") {
                    if let idx = currentIndex {
                        return idx
                    }
                }
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    /// Run a shell command and return exit code
    @discardableResult
    private func runShellCommand(_ command: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
