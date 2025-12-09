import Foundation
import Carbon

// MARK: - InputSourceManager

/// Manages macOS input sources via HIToolbox.plist manipulation
///
/// The TIS API (TISDisableInputSource) doesn't work reliably on macOS Sonoma/Ventura.
/// This implementation modifies `~/Library/Preferences/com.apple.HIToolbox.plist` directly,
/// which is the same approach used by power users and various utilities.
///
/// ## Usage
/// ```swift
/// if InputSourceManager.shared.isABCEnabledInPlist() {
///     InputSourceManager.shared.removeABCFromPlist()
/// }
/// ```
///
/// ## Important
/// After modifying the plist, CFPreferences sync and a logout/restart may be required.
public final class InputSourceManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance
    nonisolated(unsafe) public static let shared = InputSourceManager()
    
    private init() {}
    
    // MARK: - Constants
    
    /// Path to the HIToolbox preferences plist
    private static let hiToolboxPlistPath = NSString(string: "~/Library/Preferences/com.apple.HIToolbox.plist").expandingTildeInPath
    
    /// Key for enabled input sources in the plist
    private static let enabledInputSourcesKey = "AppleEnabledInputSources"
    
    /// Key for selected input sources in the plist
    private static let selectedInputSourcesKey = "AppleSelectedInputSources"
    
    /// Input source ID for the standard ABC keyboard
    public static let abcInputSourceID = "com.apple.keylayout.ABC"
    
    /// Keyboard Layout ID for ABC (252)
    public static let abcKeyboardLayoutID = 252
    
    // MARK: - Plist-based Methods (Reliable)
    
    /// Check if ABC keyboard is in the enabled input sources plist
    /// - Returns: `true` if ABC is in the plist, `false` otherwise
    public func isABCEnabledInPlist() -> Bool {
        guard let plist = loadHIToolboxPlist(),
              let enabledSources = plist[Self.enabledInputSourcesKey] as? [[String: Any]] else {
            return false
        }
        
        return enabledSources.contains { source in
            if let name = source["KeyboardLayout Name"] as? String, name == "ABC" {
                return true
            }
            if let layoutID = source["KeyboardLayout ID"] as? Int, layoutID == Self.abcKeyboardLayoutID {
                return true
            }
            return false
        }
    }
    
    /// Remove ABC keyboard from the enabled input sources plist
    /// - Returns: `true` if successful, `false` otherwise
    @discardableResult
    public func removeABCFromPlist() -> Bool {
        guard var plist = loadHIToolboxPlist(),
              var enabledSources = plist[Self.enabledInputSourcesKey] as? [[String: Any]] else {
            #if DEBUG
            DebugLogger.log("InputSourceManager: Could not load HIToolbox.plist")
            #endif
            return false
        }
        
        let originalCount = enabledSources.count
        
        // Filter out ABC keyboard
        enabledSources.removeAll { source in
            if let name = source["KeyboardLayout Name"] as? String, name == "ABC" {
                return true
            }
            if let layoutID = source["KeyboardLayout ID"] as? Int, layoutID == Self.abcKeyboardLayoutID {
                return true
            }
            return false
        }
        
        // Check if anything was removed
        if enabledSources.count == originalCount {
            #if DEBUG
            DebugLogger.log("InputSourceManager: ABC not found in plist")
            #endif
            return false
        }
        
        // Update plist
        plist[Self.enabledInputSourcesKey] = enabledSources
        
        // Also clean up selected input sources
        if var selectedSources = plist[Self.selectedInputSourcesKey] as? [[String: Any]] {
            selectedSources.removeAll { source in
                if let name = source["KeyboardLayout Name"] as? String, name == "ABC" {
                    return true
                }
                return false
            }
            plist[Self.selectedInputSourcesKey] = selectedSources
        }
        
        // Save plist
        let success = saveHIToolboxPlist(plist)
        
        if success {
            // Sync preferences to ensure changes are written
            CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
            
            #if DEBUG
            DebugLogger.log("InputSourceManager: Removed ABC from plist successfully")
            #endif
        }
        
        return success
    }
    
    /// Add ABC keyboard back to the enabled input sources plist
    /// - Returns: `true` if successful, `false` otherwise
    @discardableResult
    public func addABCToPlist() -> Bool {
        guard var plist = loadHIToolboxPlist(),
              var enabledSources = plist[Self.enabledInputSourcesKey] as? [[String: Any]] else {
            #if DEBUG
            DebugLogger.log("InputSourceManager: Could not load HIToolbox.plist")
            #endif
            return false
        }
        
        // Check if already exists
        let alreadyExists = enabledSources.contains { source in
            if let name = source["KeyboardLayout Name"] as? String, name == "ABC" {
                return true
            }
            return false
        }
        
        if alreadyExists {
            #if DEBUG
            DebugLogger.log("InputSourceManager: ABC already in plist")
            #endif
            return true
        }
        
        // Add ABC keyboard
        let abcEntry: [String: Any] = [
            "InputSourceKind": "Keyboard Layout",
            "KeyboardLayout ID": Self.abcKeyboardLayoutID,
            "KeyboardLayout Name": "ABC"
        ]
        
        enabledSources.append(abcEntry)
        plist[Self.enabledInputSourcesKey] = enabledSources
        
        let success = saveHIToolboxPlist(plist)
        
        if success {
            CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
            
            #if DEBUG
            DebugLogger.log("InputSourceManager: Added ABC to plist successfully")
            #endif
        }
        
        return success
    }
    
    // MARK: - TIS API Methods (Legacy - may not work on modern macOS)
    
    /// Get a list of all enabled keyboard input sources using TIS API
    /// - Returns: Array of tuples containing (inputSourceID, localizedName)
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
        return sources.contains { $0.id == Self.abcInputSourceID || $0.name == "ABC" }
    }
    
    /// Check if US is enabled via TIS API
    public func isUSEnabled() -> Bool {
        let sources = getEnabledKeyboardInputSources()
        return sources.contains { $0.id.contains("US") || $0.name == "U.S." }
    }
    
    // MARK: - Convenience Methods
    
    /// Disable ABC (uses plist method)
    @discardableResult
    public func disableABC() -> Bool {
        return removeABCFromPlist()
    }
    
    /// Enable ABC (uses plist method)
    @discardableResult
    public func enableABC() -> Bool {
        return addABCToPlist()
    }
    
    /// Disable US (redirects to ABC for now)
    @discardableResult
    public func disableUS() -> Bool {
        return removeABCFromPlist()
    }
    
    /// Enable US (redirects to ABC for now)
    @discardableResult
    public func enableUS() -> Bool {
        return addABCToPlist()
    }
    
    // MARK: - Private Plist Methods
    
    private func loadHIToolboxPlist() -> [String: Any]? {
        let url = URL(fileURLWithPath: Self.hiToolboxPlistPath)
        
        guard let data = try? Data(contentsOf: url) else {
            #if DEBUG
            DebugLogger.log("InputSourceManager: Could not read HIToolbox.plist")
            #endif
            return nil
        }
        
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            #if DEBUG
            DebugLogger.log("InputSourceManager: Could not parse HIToolbox.plist")
            #endif
            return nil
        }
        
        return plist
    }
    
    private func saveHIToolboxPlist(_ plist: [String: Any]) -> Bool {
        let url = URL(fileURLWithPath: Self.hiToolboxPlistPath)
        
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else {
            #if DEBUG
            DebugLogger.log("InputSourceManager: Could not serialize plist")
            #endif
            return false
        }
        
        do {
            try data.write(to: url)
            return true
        } catch {
            #if DEBUG
            DebugLogger.logError(error, context: "InputSourceManager.saveHIToolboxPlist")
            #endif
            return false
        }
    }
}
