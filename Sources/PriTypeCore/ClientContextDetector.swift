import Cocoa
import InputMethodKit

// MARK: - ClientContext

/// Represents the context of the current text input client
///
/// This struct encapsulates information about the client application and
/// its text input capabilities, enabling context-aware input handling.
public struct ClientContext: Sendable {
    
    /// Bundle identifier of the client application
    public let bundleId: String
    
    /// Whether the client has text input capability (based on validAttributesForMarkedText)
    public let hasTextInputCapability: Bool
    
    /// Whether the client appears to be in a desktop/non-text area (coordinate heuristic)
    public let isLikelyDesktopArea: Bool
    
    /// Whether secure input is currently enabled (password field)
    public let isSecureInputActive: Bool
    
    // MARK: - Derived Properties
    
    /// Whether the client is Finder
    public var isFinder: Bool {
        bundleId == "com.apple.finder"
    }
    
    /// Whether immediate mode should be used (skip marked text display)
    ///
    /// Returns `true` when:
    /// - Client is Finder AND (no text capability OR likely desktop area)
    public var shouldUseImmediateMode: Bool {
        isFinder && (!hasTextInputCapability || isLikelyDesktopArea)
    }
    
    /// Whether input should be passed through to the system
    ///
    /// Returns `true` when secure input is active (password fields)
    public var shouldPassThrough: Bool {
        isSecureInputActive
    }
}

// MARK: - ClientContextDetector

/// Detects and analyzes the context of text input clients
///
/// This utility class extracts the complex client detection logic from
/// `PriTypeInputController`, improving maintainability and testability.
///
/// ## Usage
/// ```swift
/// let context = ClientContextDetector.analyze(client: sender as! IMKTextInput)
/// if context.shouldPassThrough {
///     return false
/// }
/// if context.shouldUseImmediateMode {
///     // Use ImmediateModeAdapter
/// }
/// ```
public struct ClientContextDetector: Sendable {
    
    /// Analyzes an IMKTextInput client and returns its context
    ///
    /// - Parameter client: The text input client to analyze
    /// - Returns: A `ClientContext` containing the analysis results
    public static func analyze(client: IMKTextInput) -> ClientContext {
        // 1. FAST PATH: Check active application Bundle ID
        // Using NSWorkspace is generally faster and safer than generic IPC calls on the client
        var bundleId = client.bundleIdentifier() ?? ""
        if bundleId.isEmpty, let app = NSWorkspace.shared.frontmostApplication {
            bundleId = app.bundleIdentifier ?? ""
        }
        
        let isFinder = (bundleId == "com.apple.finder")
        
        // 2. Capabilities Check (Required for both Finder and standard apps)
        // Check text input capability via validAttributesForMarkedText
        let validAttrs = client.validAttributesForMarkedText() ?? []
        let hasTextInputCapability = validAttrs.count > 0
        
        // 3. SECURE INPUT CHECK (Fastest exit for password fields)
        let isSecureInputActive = IsSecureEventInputEnabled()
        if isSecureInputActive {
            return ClientContext(
                bundleId: bundleId,
                hasTextInputCapability: hasTextInputCapability,
                isLikelyDesktopArea: false, // Irrelevant in secure mode
                isSecureInputActive: true
            )
        }
        
        // 4. CONDITIONAL HEURISTIC: Coordinate check ONLY for Finder
        // This prevents false positives in other apps (e.g. Safari tabs at top of screen)
        var isLikelyDesktopArea = false
        if isFinder {
            // Coordinate-based heuristic for desktop detection
            let firstRect = client.firstRect(
                forCharacterRange: NSRange(location: 0, length: 0),
                actualRange: nil
            )
            // Check if input area is suspiciously close to top-left (typical for Finder's dummy window)
            isLikelyDesktopArea = firstRect.origin.x < PriTypeConfig.finderDesktopThreshold &&
                                   firstRect.origin.y < PriTypeConfig.finderDesktopThreshold
        }
        
        return ClientContext(
            bundleId: bundleId,
            hasTextInputCapability: hasTextInputCapability,
            isLikelyDesktopArea: isLikelyDesktopArea,
            isSecureInputActive: isSecureInputActive
        )
    }
}
