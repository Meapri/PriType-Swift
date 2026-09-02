import Cocoa
import InputMethodKit

// MARK: - SecureInputPolicy

/// Pure policy for deciding whether a secure-input-looking client should bypass IMK composition.
///
/// Password fields can still expose partial IMK capabilities. Avoid Accessibility
/// probing on the keystroke hot path; prefer raw passthrough whenever the client
/// selection is unavailable or macOS Secure Event Input is active.
struct SecureInputSignals: Sendable {
    let bundleId: String
    let hasTextInputCapability: Bool
    let hasInvalidSelection: Bool
    let hasGlobalSecureInput: Bool
    let hasMarkedTextSupport: Bool
}

struct SecureInputPolicy: Sendable {
    static func isSystemSecureClient(_ bundleId: String) -> Bool {
        bundleId == "com.apple.SecurityAgent" ||
            bundleId == "com.apple.loginwindow" ||
            bundleId == "com.apple.screencaptureui"
    }

    static func shouldPassThrough(_ signals: SecureInputSignals) -> Bool {
        if isSystemSecureClient(signals.bundleId) {
            return true
        }

        // Password-like fields: no marked-text capability, or a missing selection
        // *and* no text-input attributes. Invalid selection alone is not enough —
        // Chromium reports NSNotFound in ordinary web fields too, and treating
        // that as secure input made Korean type as ABC qwerty.
        let looksLikeSecureField = !signals.hasTextInputCapability || !signals.hasMarkedTextSupport
        if signals.hasInvalidSelection && looksLikeSecureField {
            return true
        }

        // Global Secure Event Input is process-wide. A password field in another
        // app must not disable Hangul in this client if this client looks like a
        // normal text field.
        if signals.hasGlobalSecureInput && (looksLikeSecureField || signals.hasInvalidSelection) {
            return true
        }

        return false
    }
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

    /// Whether this context intentionally skipped client IPC for activation speed.
    public let isLightweight: Bool

    /// Whether the client reports a usable selection range (proxy for legacy
    /// Carbon `TSMDocumentAccess` support). When false, `insertText`'s
    /// `replacementRange` is unreliable — direct insertion would corrupt text, so
    /// the experimental direct-insertion path is denied. Probed once at activation.
    public let documentAccessSafe: Bool

    public init(
        bundleId: String,
        hasTextInputCapability: Bool,
        isLikelyDesktopArea: Bool,
        isLightweight: Bool = false,
        documentAccessSafe: Bool = false
    ) {
        self.bundleId = bundleId
        self.hasTextInputCapability = hasTextInputCapability
        self.isLikelyDesktopArea = isLikelyDesktopArea
        self.isLightweight = isLightweight
        self.documentAccessSafe = documentAccessSafe
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

// MARK: - ClientCompatibilityPolicy

public enum ClientCompatibilityPolicy {
    private static let goodNotesBundleId = "com.goodnotesapp.x"
    private static let hermesBundleIds: Set<String> = [
        "com.nousresearch.hermes",
        "com.nousresearch.hermes.setup"
    ]

    /// Apps where experimental direct insertion is known to be IMPOSSIBLE, not just
    /// risky: Electron/Chromium and browser web-content fields report `selectedRange`
    /// and `attributedSubstring` asynchronously / inaccurately, so the in-place
    /// rewrite cannot verify or target the live region — it desyncs the composition.
    /// (Confirmed in on-device logs: every keystroke tripped the caret-stability guard
    /// in Claude Desktop / Electron.) These keep the canonical marked-text path, which
    /// works fine there. This is graceful degradation, not a feature gate — direct
    /// insertion still runs in every NATIVE app (e.g. KakaoTalk, Notes). See
    /// Docs/KoreanWindowsInputFeasibility.md §2.
    private static let directInsertionDenylist: Set<String> = [
        "com.anthropic.claudefordesktop",
        "com.openai.codex",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "notion.id",
        "com.figma.Desktop",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",        // Arc
        "org.mozilla.firefox",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview"
    ]

    public static func needsDirectNewlineAfterReturnCommit(bundleId: String) -> Bool {
        bundleId == goodNotesBundleId
    }

    /// Some chat-style hosts send the message on Return before their text system has
    /// incorporated the IMK commit. When Hangul is still marked, the submitted text can
    /// miss the last composing syllable. For those hosts, consume the Return that only
    /// finalizes composition; the next Return remains a normal send/newline action.
    public static func needsReturnConsumedAfterCompositionCommit(bundleId: String) -> Bool {
        hermesBundleIds.contains(bundleId)
    }

    /// Hermes is an Electron chat host whose send action can read the DOM value before
    /// Chromium has incorporated IMK marked text, dropping only the final Hangul
    /// syllable. Prefer real-text composition there when document access is usable.
    public static func prefersDirectInsertionForComposition(bundleId: String) -> Bool {
        hermesBundleIds.contains(bundleId)
    }

    /// Whether `bundleId` is a browser / Electron / CEF / Atlassian web editor.
    /// These hosts run contenteditable (often ProseMirror), not AppKit text views.
    public static func isWebContentHost(bundleId: String) -> Bool {
        if directInsertionDenylist.contains(bundleId) { return true }
        if blinkRendererBundleIds.contains(bundleId) { return true }
        let lower = bundleId.lowercased()
        return lower.contains("electron")
            || lower.contains("chrome")
            || lower.contains("chromium")
            || lower.contains("atlassian")
            || lower.contains("confluence")
            || lower.contains("jira")
    }

    /// Whether direct insertion must be denied for `bundleId` because the host cannot
    /// reliably support in-place real-text rewrites (Electron/Chromium/browsers).
    /// Explicit list + a keyword heuristic for unlisted Electron/Chromium wrappers.
    public static func directInsertionDenied(bundleId: String) -> Bool {
        if directInsertionDenylist.contains(bundleId) { return true }
        let lower = bundleId.lowercased()
        return lower.contains("electron")
            || lower.contains("chrome")
            || lower.contains("chromium")
    }

    /// Web editors treat Hangul Compatibility Jamo (U+3131 ㄱ) as a finished letter
    /// and may fire compositionend after the first choseong. That commits `ㄱ` into
    /// its own Confluence/ProseMirror list item while libhangul continues composing
    /// the same syllable in the next item (`- ㄱ` / `- 감사합니다.`). Keep the
    /// engine's choseong jamo (U+1100) so the host leaves composition open.
    /// Native AppKit hosts keep compatibility jamo for display.
    public static func prefersRawJamoPreedit(bundleId: String) -> Bool {
        isWebContentHost(bundleId: bundleId)
    }

    /// Web editors' empty list items often have a non-collapsed / placeholder
    /// selection. `setMarkedText` with `replacementRange = NSNotFound` then
    /// **replaces that selection** (Apple NSTextInputClient). Collapsing the
    /// first mark to `{caret, 0}` inserts without eating the list structure.
    /// Native hosts (KakaoTalk) must keep NSNotFound.
    public static func prefersCollapsedCompositionReplacement(bundleId: String) -> Bool {
        isWebContentHost(bundleId: bundleId)
    }

    /// Hosts whose text fields are rendered by Blink (Chromium/Electron/CEF).
    /// ENGINE classification, not per-app behavior: it decides only which form of
    /// "invisible underline" attributes the preedit uses (see `PreeditUnderline`),
    /// because Blink is the one renderer that repaints a fully transparent
    /// composition-underline color in the TEXT color (Blink
    /// `StyleableMarker::UseTextColor`), so `NSColor.clear` cannot hide it there.
    /// Misclassification is benign: a Blink host left as `.system` just keeps a
    /// thin text-colored underline (the pre-existing behavior), and a native/WebKit
    /// host wrongly marked `.blink` gets an alpha-1/255 underline that AppKit and
    /// legacy WebKit paint invisibly anyway.
    private static let blinkRendererBundleIds: Set<String> = [
        "com.anthropic.claudefordesktop",
        "com.openai.codex",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "notion.id",
        "com.figma.Desktop",
        "com.spotify.client",              // CEF
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",      // Arc
        "com.naver.whale",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera"
    ]

    public static func compositionRenderer(bundleId: String) -> CompositionRenderer {
        if blinkRendererBundleIds.contains(bundleId) { return .blink }
        let lower = bundleId.lowercased()
        if lower.contains("electron") || lower.contains("chrome") || lower.contains("chromium") {
            return .blink
        }
        return .system
    }
}

/// Which engine renders the host's marked-text (composition) decoration.
/// `.system` covers AppKit/TextKit, Catalyst, WebKit (Safari) and everything else;
/// `.blink` is Chromium-derived hosts. Used only to pick preedit underline styling.
public enum CompositionRenderer: Sendable, Equatable {
    case system
    case blink
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
    /// Probe for legacy Carbon `TSMDocumentAccess` support. A client that returns a
    /// sane selection range honors `insertText(replacementRange:)`; NSNotFound
    /// (terminals/secure/launchers) or absurd values (Chromium garbage) mean the
    /// replacementRange is ignored, so direct insertion would corrupt text.
    /// One IPC call — done once per activation, never on the keystroke hot path.
    ///
    /// Gated on the experimental flag: when direct insertion is OFF (the default,
    /// shipping configuration) this returns false WITHOUT any IPC, so the marked-text
    /// path pays zero extra cost for a feature it never uses.
    static func probeDocumentAccessSafe(_ client: IMKTextInput, bundleId: String) -> Bool {
        guard ConfigurationManager.shared.experimentalDirectInsertion ||
              ClientCompatibilityPolicy.prefersDirectInsertionForComposition(bundleId: bundleId) else {
            return false
        }
        let sel = client.selectedRange()
        return sel.location != NSNotFound && sel.location < 10_000_000
    }

    public static func analyzeForActivation(client: IMKTextInput) -> ClientContext {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        var bundleId = frontmostApp?.bundleIdentifier ?? ""
        if bundleId.isEmpty {
            bundleId = client.bundleIdentifier() ?? ""
        }
        let isFinder = bundleId == "com.apple.finder"

        return ClientContext(
            bundleId: bundleId,
            hasTextInputCapability: !isFinder,
            isLikelyDesktopArea: isFinder,
            isLightweight: true,
            documentAccessSafe: probeDocumentAccessSafe(client, bundleId: bundleId)
        )
    }

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
        let hasTextInputCapability = !validAttrs.isEmpty
        
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
            documentAccessSafe: probeDocumentAccessSafe(client, bundleId: bundleId)
        )
    }
}
