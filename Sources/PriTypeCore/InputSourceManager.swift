import Foundation
import Carbon

// MARK: - InputSourceManager

/// Manages macOS input sources using the Text Input Services (TIS) API
///
/// This manager provides functionality to:
/// - List enabled keyboard input sources
/// - Check if specific input sources (like ABC) are enabled
/// - Enable/disable input sources programmatically
///
/// ## Usage
/// ```swift
/// if InputSourceManager.shared.isABCEnabled() {
///     InputSourceManager.shared.disableABC()
/// }
/// ```
///
/// ## Security Note
/// Modifying input sources may require accessibility permissions on some macOS versions.
public final class InputSourceManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance
    nonisolated(unsafe) public static let shared = InputSourceManager()
    
    private init() {}
    
    // MARK: - Constants
    
    /// Input source ID for the standard ABC keyboard
    public static let abcInputSourceID = "com.apple.keylayout.ABC"
    
    /// Input source ID for US keyboard
    public static let usInputSourceID = "com.apple.keylayout.US"
    
    // MARK: - Public API
    
    /// Get a list of all enabled keyboard input sources
    /// - Returns: Array of tuples containing (inputSourceID, localizedName)
    public func getEnabledKeyboardInputSources() -> [(id: String, name: String)] {
        var result: [(id: String, name: String)] = []
        
        // Create filter for keyboard input sources only
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
    
    /// Check if the ABC keyboard input source is currently enabled
    /// - Returns: `true` if ABC is enabled, `false` otherwise
    public func isABCEnabled() -> Bool {
        return isInputSourceEnabled(id: Self.abcInputSourceID)
    }
    
    /// Check if the US keyboard input source is currently enabled
    /// - Returns: `true` if US is enabled, `false` otherwise
    public func isUSEnabled() -> Bool {
        return isInputSourceEnabled(id: Self.usInputSourceID)
    }
    
    /// Check if a specific input source is enabled
    /// - Parameter id: The input source ID to check
    /// - Returns: `true` if enabled, `false` otherwise
    public func isInputSourceEnabled(id: String) -> Bool {
        let sources = getEnabledKeyboardInputSources()
        return sources.contains { $0.id == id }
    }
    
    /// Disable the ABC keyboard input source
    /// - Returns: `true` if successful, `false` otherwise
    @discardableResult
    public func disableABC() -> Bool {
        return disableInputSource(id: Self.abcInputSourceID)
    }
    
    /// Disable the US keyboard input source
    /// - Returns: `true` if successful, `false` otherwise
    @discardableResult
    public func disableUS() -> Bool {
        return disableInputSource(id: Self.usInputSourceID)
    }
    
    /// Enable the ABC keyboard input source
    /// - Returns: `true` if successful, `false` otherwise
    @discardableResult
    public func enableABC() -> Bool {
        return enableInputSource(id: Self.abcInputSourceID)
    }
    
    /// Enable the US keyboard input source
    /// - Returns: `true` if successful, `false` otherwise
    @discardableResult
    public func enableUS() -> Bool {
        return enableInputSource(id: Self.usInputSourceID)
    }
    
    /// Disable a specific input source
    /// - Parameter id: The input source ID to disable
    /// - Returns: `true` if successful, `false` otherwise
    @discardableResult
    public func disableInputSource(id: String) -> Bool {
        guard let source = findInputSource(id: id) else {
            #if DEBUG
            DebugLogger.log("InputSourceManager: Could not find input source '\(id)'")
            #endif
            return false
        }
        
        let result = TISDisableInputSource(source)
        
        #if DEBUG
        if result == noErr {
            DebugLogger.log("InputSourceManager: Disabled '\(id)'")
        } else {
            DebugLogger.log("InputSourceManager: Failed to disable '\(id)', error: \(result)")
        }
        #endif
        
        return result == noErr
    }
    
    /// Enable a specific input source
    /// - Parameter id: The input source ID to enable
    /// - Returns: `true` if successful, `false` otherwise
    @discardableResult
    public func enableInputSource(id: String) -> Bool {
        guard let source = findInputSource(id: id) else {
            #if DEBUG
            DebugLogger.log("InputSourceManager: Could not find input source '\(id)'")
            #endif
            return false
        }
        
        let result = TISEnableInputSource(source)
        
        #if DEBUG
        if result == noErr {
            DebugLogger.log("InputSourceManager: Enabled '\(id)'")
        } else {
            DebugLogger.log("InputSourceManager: Failed to enable '\(id)', error: \(result)")
        }
        #endif
        
        return result == noErr
    }
    
    /// Check if PriType is currently enabled as an input source
    /// - Returns: `true` if PriType is in the enabled input sources list
    public func isPriTypeEnabled() -> Bool {
        let sources = getEnabledKeyboardInputSources()
        return sources.contains { $0.id.contains("pritype") || $0.id.contains("PriType") }
    }
    
    /// Get a list of all English-like input sources (ABC, US, etc.)
    /// - Returns: Array of English keyboard input source IDs
    public func getEnglishInputSources() -> [(id: String, name: String)] {
        let sources = getEnabledKeyboardInputSources()
        return sources.filter { source in
            source.id.contains("com.apple.keylayout.ABC") ||
            source.id.contains("com.apple.keylayout.US") ||
            source.id.contains("com.apple.keylayout.British") ||
            source.id.contains("com.apple.keylayout.Australian")
        }
    }
    
    // MARK: - Private Methods
    
    /// Find an input source by ID (including disabled ones)
    private func findInputSource(id: String) -> TISInputSource? {
        // Search in all input sources (including disabled)
        let filter: [String: Any] = [
            kTISPropertyInputSourceID as String: id
        ]
        
        guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sourceList.first else {
            return nil
        }
        
        return source
    }
}
