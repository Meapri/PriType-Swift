import Foundation
import Carbon

// MARK: - InputSourceManager

/// Manages macOS input sources using the Text Input Source (TIS) API
///
/// This implementation uses only Apple's official TIS API for querying
/// input source status. Note: TIS API cannot disable system input sources
/// like ABC - users must manage these through System Settings.
///
/// ## Usage
/// ```swift
/// let sources = InputSourceManager.shared.getEnabledKeyboardInputSources()
/// let isABCEnabled = InputSourceManager.shared.isABCEnabled()
/// ```
public final class InputSourceManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance
    public static let shared = InputSourceManager()
    
    private init() {}
    
    // MARK: - Constants
    
    /// Keyboard Layout ID for ABC (252)
    public static let abcKeyboardLayoutID = 252
    
    // MARK: - TIS API Methods
    
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
}
