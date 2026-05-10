import Cocoa
import InputMethodKit
import ApplicationServices

// MARK: - SecureTextFocusState

/// Focused text field security state detected through Accessibility.
public enum SecureTextFocusState: Sendable {
    case secureTextField
    case nonSecureTextInput
    case unknown
}

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

    /// Whether the client needs conservative marked-text handling for game/Wine runtimes.
    public let usesGameCompatibilityMode: Bool

    public init(
        bundleId: String,
        hasTextInputCapability: Bool,
        isLikelyDesktopArea: Bool,
        usesGameCompatibilityMode: Bool = false
    ) {
        self.bundleId = bundleId
        self.hasTextInputCapability = hasTextInputCapability
        self.isLikelyDesktopArea = isLikelyDesktopArea
        self.usesGameCompatibilityMode = usesGameCompatibilityMode
    }
    
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
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        var bundleId = client.bundleIdentifier() ?? ""
        if bundleId.isEmpty, let app = frontmostApp {
            bundleId = app.bundleIdentifier ?? ""
        }
        
        let isFinder = (bundleId == "com.apple.finder")
        
        // 2. Capabilities Check (Required for both Finder and standard apps)
        // Check text input capability via validAttributesForMarkedText
        let validAttrs = client.validAttributesForMarkedText() ?? []
        let hasTextInputCapability = validAttrs.count > 0
        
        // 3. SECURE INPUT CHECK is no longer cached here.
        // It is checked dynamically in PriTypeInputController.handle() for better accuracy.
        
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
            isLikelyDesktopArea = firstRect.origin.x >= 0 && firstRect.origin.y >= 0 &&
                                   firstRect.origin.x < PriTypeConfig.finderDesktopThreshold &&
                                   firstRect.origin.y < PriTypeConfig.finderDesktopThreshold
        }
        
        return ClientContext(
            bundleId: bundleId,
            hasTextInputCapability: hasTextInputCapability,
            isLikelyDesktopArea: isLikelyDesktopArea,
            usesGameCompatibilityMode: usesGameCompatibilityMode(
                bundleId: bundleId,
                app: frontmostApp
            )
        )
    }

    private static func usesGameCompatibilityMode(
        bundleId: String,
        app: NSRunningApplication?
    ) -> Bool {
        usesGameCompatibilityMode(
            bundleId: bundleId,
            localizedName: app?.localizedName,
            bundlePath: app?.bundleURL?.path,
            executablePath: app?.executableURL?.path
        )
    }

    static func usesGameCompatibilityMode(
        bundleId: String,
        localizedName: String?,
        bundlePath: String?,
        executablePath: String?
    ) -> Bool {
        let hints = [
            bundleId,
            localizedName ?? "",
            bundlePath ?? "",
            executablePath ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        let compatibilityMarkers = [
            "maplestory",
            "nexon",
            "wine",
            "crossover",
            "whisky"
        ]

        return compatibilityMarkers.contains { hints.contains($0) }
    }

    /// Detects whether the frontmost focused accessibility element is a secure text field.
    ///
    /// `IsSecureEventInputEnabled()` is a process-global signal and can be stale, while
    /// some password fields still report enough IMK text capability to tempt us into
    /// composing text. The focused AX element gives the field-level answer when available.
    public static func focusedSecureTextState() -> SecureTextFocusState {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .unknown
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedError == .success, let focusedValue else {
            DebugLogger.log("Secure Input: AX focused element unavailable error=\(focusedError.rawValue)")
            return .unknown
        }

        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            DebugLogger.log("Secure Input: AX focused value is not an element")
            return .unknown
        }

        let focusedElement = (focusedValue as! AXUIElement)
        let role = stringAttribute(kAXRoleAttribute as CFString, from: focusedElement)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: focusedElement)

        if subrole == (kAXSecureTextFieldSubrole as String) {
            return .secureTextField
        }

        if role == (kAXTextFieldRole as String) ||
            role == (kAXTextAreaRole as String) ||
            role == (kAXComboBoxRole as String) {
            return .nonSecureTextInput
        }

        return .unknown
    }

    private static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            return nil
        }
        return value as? String
    }
}
