import Foundation
import Carbon

// MARK: - InputSourceManager

/// Manages macOS input sources using the Text Input Source (TIS) API
///
/// This implementation uses Apple's official TIS API for querying and selecting
/// input sources. PriType does not rewrite macOS's enabled input-source
/// preferences at runtime; users keep ownership of the list in System Settings.
///
/// ## Usage
/// ```swift
/// let sources = InputSourceManager.shared.getEnabledKeyboardInputSources()
/// let selected = InputSourceManager.shared.selectedLanguageInputMode()
/// ```
public final class InputSourceManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance
    public static let shared = InputSourceManager()
    
    private init() {}
    
    // MARK: - Constants
    
    private static let priTypeBundleID = "com.pritype.inputmethod.v2"
    private static let priTypeKoreanInputSourceID = "com.pritype.inputmethod.v2.korean"
    private static let priTypeEnglishInputMode = "com.pritype.inputmethod.v2.english"
    private static let appleABCInputSourceID = "com.apple.keylayout.ABC"
    private static let abcKeyboardLayoutName = "ABC"
    
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

    public func toggledInputMode(fallbackMode: InputMode) -> InputMode? {
        let currentMode = selectedLanguageInputMode() ?? fallbackMode
        let nextMode = currentMode.toggled
        DebugLogger.log("InputSourceManager: toggling input source \(currentMode) -> \(nextMode)")
        guard selectInputMode(nextMode) else {
            return nil
        }
        return nextMode
    }

    @discardableResult
    public func selectPriTypeInputMode(_ mode: InputMode) -> Bool {
        selectInputMode(mode)
    }

    @discardableResult
    public func selectInputMode(_ mode: InputMode) -> Bool {
        let inputModeID: String
        switch mode {
        case .korean:
            inputModeID = Self.priTypeKoreanInputSourceID
        case .english:
            inputModeID = Self.appleABCInputSourceID
        }

        guard let source = inputSource(id: inputModeID) else {
            DebugLogger.log("InputSourceManager: input source not found: \(inputModeID)")
            return false
        }

        let status = TISSelectInputSource(source)
        guard status == noErr else {
            DebugLogger.log("InputSourceManager: failed to select \(inputModeID), status=\(status)")
            return false
        }

        DebugLogger.log("InputSourceManager: selected input source \(inputModeID)")
        return true
    }

    public func selectedPriTypeInputMode() -> InputMode? {
        selectedLanguageInputMode()
    }

    public func selectedLanguageInputMode() -> InputMode? {
        let filter = [kTISPropertyInputSourceIsSelected as String: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        for source in list {
            guard let id = Self.stringProperty(kTISPropertyInputSourceID, from: source) else {
                continue
            }

            switch id {
            case Self.priTypeBundleID, Self.priTypeKoreanInputSourceID:
                return .korean
            case Self.appleABCInputSourceID, Self.priTypeEnglishInputMode:
                return .english
            default:
                continue
            }
        }

        return nil
    }

    private func inputSource(id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        if let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
           let source = list.first {
            return source
        }

        guard id == Self.appleABCInputSourceID,
              let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        return list.first { source in
            Self.stringProperty(kTISPropertyLocalizedName, from: source) == Self.abcKeyboardLayoutName
        }
    }

    private static func stringProperty(_ key: CFString, from source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

}
