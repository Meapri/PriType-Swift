import Testing
import Cocoa
@testable import PriTypeCore

// MARK: - TextDeliveryPolicy

/// The delivery-mode decision is the single point where a session picks how
/// composition output reaches the host (marked text / direct insertion / immediate).
@Suite("TextDeliveryPolicy")
struct TextDeliveryPolicyTests {
    private func context(
        bundleId: String,
        hasTextInputCapability: Bool = true,
        isLikelyDesktopArea: Bool = false,
        documentAccessSafe: Bool = false
    ) -> ClientContext {
        ClientContext(
            bundleId: bundleId,
            hasTextInputCapability: hasTextInputCapability,
            isLikelyDesktopArea: isLikelyDesktopArea,
            documentAccessSafe: documentAccessSafe
        )
    }

    @Test("Finder desktop context resolves to immediate mode")
    func finderDesktopIsImmediate() {
        let ctx = context(bundleId: "com.apple.finder", hasTextInputCapability: false, isLikelyDesktopArea: true)
        #expect(TextDeliveryPolicy.mode(for: ctx) == .immediate)
    }

    @Test("Default context resolves to canonical marked text")
    func defaultIsMarkedText() {
        let ctx = context(bundleId: "com.apple.TextEdit", documentAccessSafe: true)
        #expect(TextDeliveryPolicy.mode(for: ctx) == .markedText)
    }

    @Test("Direct-insertion-preferring host without document access stays on marked text")
    func directPreferenceRequiresDocumentAccess() {
        let ctx = context(bundleId: "com.nousresearch.hermes", documentAccessSafe: false)
        #expect(TextDeliveryPolicy.mode(for: ctx) == .markedText)
    }

    @Test("Direct-insertion-preferring host with document access gets direct insertion")
    func directPreferenceWithDocumentAccess() {
        let ctx = context(bundleId: "com.nousresearch.hermes", documentAccessSafe: true)
        #expect(TextDeliveryPolicy.mode(for: ctx) == .directInsertion)
    }

    @Test("Denylisted Electron/Chromium hosts never get direct insertion")
    func denylistedHostStaysMarked() {
        let ctx = context(bundleId: "com.google.Chrome", documentAccessSafe: true)
        #expect(TextDeliveryPolicy.mode(for: ctx) == .markedText)
    }
}

// MARK: - Composition renderer classification

@Suite("CompositionRenderer")
struct CompositionRendererTests {
    @Test("Known Blink/Electron hosts classify as blink")
    func knownBlinkHosts() {
        for id in [
            "com.google.Chrome",
            "com.anthropic.claudefordesktop",
            "com.microsoft.VSCode",
            "com.tinyspeck.slackmacgap",
            "com.naver.whale"
        ] {
            #expect(ClientCompatibilityPolicy.compositionRenderer(bundleId: id) == .blink, "\(id) should be blink")
        }
    }

    @Test("Keyword heuristic catches unlisted Chromium/Electron wrappers")
    func keywordHeuristic() {
        #expect(ClientCompatibilityPolicy.compositionRenderer(bundleId: "com.example.MyElectronApp") == .blink)
        #expect(ClientCompatibilityPolicy.compositionRenderer(bundleId: "org.chromium.Chromium") == .blink)
    }

    @Test("WebKit and native hosts classify as system — Safari must NOT be blink")
    func systemHosts() {
        for id in [
            "com.apple.Safari",                 // WebKit: needs exactly NSColor.clear
            "com.apple.SafariTechnologyPreview",
            "org.mozilla.firefox",              // Gecko
            "com.apple.TextEdit",
            "com.kakao.KakaoTalkMac",
            "com.apple.dt.Xcode"
        ] {
            #expect(ClientCompatibilityPolicy.compositionRenderer(bundleId: id) == .system, "\(id) should be system")
        }
    }
}

// MARK: - Preedit underline invisibility attributes

/// The underline must be invisible in every renderer, but each engine needs a
/// different trick (see `PreeditUnderline` doc): Blink repaints a fully transparent
/// underline in the text color, so it gets alpha 1/255; everything else gets
/// style 0 + NSColor.clear (AppKit honors the 0, WebKit special-cases clear).
@Suite("PreeditUnderline")
struct PreeditUnderlineTests {
    @Test("Blink hosts get a single underline with near-zero (but non-zero) alpha")
    func blinkAttributes() throws {
        let attrs = PreeditUnderline.attributes(forBundleId: "com.google.Chrome")
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        let color = try #require(attrs[.underlineColor] as? NSColor)
        let alpha = color.alphaComponent
        #expect(alpha > 0, "exactly-transparent triggers Blink's text-color substitution")
        #expect(alpha < 0.01, "must stay imperceptible")
    }

    @Test("System hosts get style 0 with exactly NSColor.clear")
    func systemAttributes() throws {
        for bundleId in ["com.apple.TextEdit", "com.apple.Safari", "com.kakao.KakaoTalkMac"] {
            let attrs = PreeditUnderline.attributes(forBundleId: bundleId)
            #expect(attrs[.underlineStyle] as? Int == 0)
            let color = try #require(attrs[.underlineColor] as? NSColor)
            // WebKit's extraction fast path compares isEqual:NSColor.clearColor —
            // it must be the literal clear color, not a hand-built alpha-0 color.
            #expect(color == NSColor.clear)
        }
    }
}

// MARK: - Finalize reason coverage

/// Every composition-ending event must map to a finalize reason — the single path
/// contract. This is a compile-time-ish guard: adding a new reason here forces the
/// author to think about whether it routes through `InputSession.finalize`.
@Suite("CompositionFinalizeReason")
struct CompositionFinalizeReasonTests {
    @Test("All session-ending events have a distinct reason")
    func reasonsAreDistinct() {
        let reasons: [CompositionFinalizeReason] = [
            .appDeactivate, .deactivateServer, .mouseCommit,
            .modeTransition, .systemModeSwitch, .keyboardLayoutChange
        ]
        #expect(Set(reasons.map(\.rawValue)).count == reasons.count)
    }
}

// MARK: - Web-host first-mark replacement range

/// Confluence/ProseMirror empty list items often have a non-collapsed or
/// placeholder selection. Apple's setMarkedText docs: if there is no marked
/// text and replacementRange is NSNotFound, the **current selection is replaced**.
/// Replacing that selection with the first ㄱ looks like splitting a list item
/// (`- ㄱ` then `- 감사합니다.`). Native hosts must keep NSNotFound (KakaoTalk).
@Suite("MarkedTextReplacement")
struct MarkedTextReplacementTests {
    private let notFound = NSRange(location: NSNotFound, length: NSNotFound)
    private let placeholderSelection = NSRange(location: 0, length: 1)
    private let collapsedCaret = NSRange(location: 12, length: 0)

    @Test("Native hosts always use NSNotFound")
    func nativeAlwaysNotFound() {
        #expect(MarkedTextReplacement.range(
            isClearing: false,
            hasLiveMarkedText: false,
            selectedRange: placeholderSelection,
            prefersCollapsedStart: false
        ) == notFound)
    }

    @Test("Clearing marked text always uses NSNotFound")
    func clearingAlwaysNotFound() {
        #expect(MarkedTextReplacement.range(
            isClearing: true,
            hasLiveMarkedText: false,
            selectedRange: placeholderSelection,
            prefersCollapsedStart: true
        ) == notFound)
    }

    @Test("Subsequent preedit updates use NSNotFound so the host replaces its marked text")
    func liveMarkedUsesNotFound() {
        #expect(MarkedTextReplacement.range(
            isClearing: false,
            hasLiveMarkedText: true,
            selectedRange: placeholderSelection,
            prefersCollapsedStart: true
        ) == notFound)
    }

    @Test("First mark on a web host inserts at the caret without replacing host selection")
    func firstWebMarkInsertsCollapsed() {
        let range = MarkedTextReplacement.range(
            isClearing: false,
            hasLiveMarkedText: false,
            selectedRange: placeholderSelection,
            prefersCollapsedStart: true
        )
        #expect(range == NSRange(location: 0, length: 0),
                "Must not replace a non-collapsed list-item selection; got \(range)")
    }

    @Test("First mark on a web host with a collapsed caret still inserts at that caret")
    func firstWebMarkCollapsedCaret() {
        #expect(MarkedTextReplacement.range(
            isClearing: false,
            hasLiveMarkedText: false,
            selectedRange: collapsedCaret,
            prefersCollapsedStart: true
        ) == NSRange(location: 12, length: 0))
    }

    @Test("Invalid or Chromium-garbage selection falls back to NSNotFound")
    func garbageSelectionFallsBack() {
        #expect(MarkedTextReplacement.range(
            isClearing: false,
            hasLiveMarkedText: false,
            selectedRange: NSRange(location: NSNotFound, length: 0),
            prefersCollapsedStart: true
        ) == notFound)
        #expect(MarkedTextReplacement.range(
            isClearing: false,
            hasLiveMarkedText: false,
            selectedRange: NSRange(location: 20_000_000, length: 0),
            prefersCollapsedStart: true
        ) == notFound)
    }
}
