import Cocoa
import InputMethodKit

// MARK: - InputDeliveryMode

/// How composition output reaches the focused client.
enum InputDeliveryMode: Equatable {
    case immediate          // Finder desktop: defer, no marked window
    case directInsertion    // EXPERIMENTAL: real-text in-place rewrite
    case markedText         // Default: canonical marked-text composition
}

// MARK: - TextDeliveryPolicy

/// Single decision point for how composition is delivered to a client.
///
/// Default is canonical marked text. Direct insertion (experimental) is attempted in
/// EVERY app when the flag is ON — there is no per-app allowlist. The only gate is the
/// activation probe `documentAccessSafe`: apps that cannot report a usable selection
/// range (e.g. terminals) physically cannot do in-place rewrites, so they keep the
/// marked-text path. Apps that pass the probe but misbehave at runtime degrade to
/// marked text via the adapter's caret-stability guard / bail path — so enabling it
/// everywhere never corrupts text, it just falls back where it can't work.
enum TextDeliveryPolicy {
    static func mode(for context: ClientContext) -> InputDeliveryMode {
        if context.shouldUseImmediateMode {
            return .immediate
        }
        if (ConfigurationManager.shared.experimentalDirectInsertion ||
            ClientCompatibilityPolicy.prefersDirectInsertionForComposition(bundleId: context.bundleId)),
           context.documentAccessSafe,
           !ClientCompatibilityPolicy.directInsertionDenied(bundleId: context.bundleId) {
            return .directInsertion
        }
        return .markedText
    }

    static func makeAdapter(for client: IMKTextInput, context: ClientContext) -> BaseClientAdapter {
        switch mode(for: context) {
        case .immediate:
            return ImmediateModeAdapter(client: client, bundleId: context.bundleId)
        case .directInsertion:
            DebugLogger.log("TextDeliveryPolicy: DirectInsertionAdapter (experimental) for \(context.bundleId)")
            return DirectInsertionAdapter(client: client, bundleId: context.bundleId)
        case .markedText:
            return MarkedTextAdapter(client: client, bundleId: context.bundleId)
        }
    }
}

// MARK: - PreeditUnderline

/// Marked-text attributes chosen to make the composition underline invisible
/// WHERE THE OS STILL HONORS IME ATTRIBUTES (the underline is pure decoration;
/// the marked range and commit semantics are untouched either way).
///
/// ⚠️ TRANSPORT REALITY on macOS 26 (measured 2026-06 with an NSTextInputClient
/// probe on the live IMK path, enumerating every payload we can send): underline
/// style 0 + `.clear`, single + alpha-1/255, `NSMarkedClauseSegment` 1…9 (every
/// TSM hilite category incl. kNoHilite), and even an attribute-LESS string ALL
/// arrive at the client as the same regenerated pair `NSUnderline=2 + accent
/// blue`. The receiving framework discards IME-provided styling and synthesizes
/// the system marked-text style — distinct categories that carry distinct styles
/// in `IMKInputController.mark(forStyle:at:)` dictionaries (e.g. style 3 → gray
/// U=3, style 4 → gray U=1) arrive indistinguishable, so the channel is fully
/// dead, not merely quantized. On macOS 26 NO setMarkedText attributes can hide
/// the composition underline, for any IME (Apple's Korean IME draws the same
/// underline). The only underline-free composition is to not use marked text at
/// all — `DirectInsertionAdapter` via `experimentalDirectInsertion`.
///
/// On older macOS the attributes pass through, and there no single set hides the
/// underline in every renderer — verified against the engine sources (Chromium
/// `render_widget_host_view_cocoa.mm` + `styleable_marker_painter.cc`, WebKit
/// `WebViewImpl.mm` + `TextBoxPainter.cpp`):
///
///                          AppKit      WebKit(Safari)   Blink(Chromium/Electron)
///   style 0                hidden      VISIBLE¹         VISIBLE (thin black)
///   style 1 + .clear       hidden      hidden²          VISIBLE (text color)³
///   style 1 + alpha 1/255  hidden      VISIBLE¹         hidden (painted at 0.4%)
///
/// ¹ WebKit/Blink check only the attribute's PRESENCE; the 0 value is ignored, and a
///   non-clear color is repainted in the system accent color by modern WebKit.
/// ² WebKit special-cases exactly `NSColor.clear` at extraction, and an alpha-0 color
///   is also skipped at paint (`Color::isVisible()`), so clear is doubly safe there.
/// ³ Blink substitutes the TEXT color for a fully transparent underline
///   (`StyleableMarker::UseTextColor`) — clear makes the underline VISIBLE there;
///   alpha 1/255 fails the exact-transparent compare and paints imperceptibly.
///
/// Omitting the attribute entirely is worse everywhere it matters: AppKit applies
/// its default marked-text style (underline) and WebKit falls back to an opaque
/// yellow composition highlight. Hence: always send the attribute, engine-tuned.
enum PreeditUnderline {
    static func attributes(forBundleId bundleId: String) -> [NSAttributedString.Key: Any] {
        switch ClientCompatibilityPolicy.compositionRenderer(bundleId: bundleId) {
        case .blink:
            return [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1.0 / 255.0)
            ]
        case .system:
            return [
                .underlineStyle: 0,
                .underlineColor: NSColor.clear
            ]
        }
    }
}

// MARK: - BaseClientAdapter

/// Base adapter class with common IMKTextInput operations
/// Subclasses override setMarkedText for different behaviors
class BaseClientAdapter: NSObject, HangulComposerDelegate {
    let client: IMKTextInput

    /// Host bundle id, for engine-tuned preedit styling.
    let bundleId: String

    /// Engine-tuned attributes for the composition preedit (effective only on
    /// macOS versions that honor IME attributes — see `PreeditUnderline`).
    let preeditAttributes: [NSAttributedString.Key: Any]

    /// The delivery mode this adapter implements. Used by `InputSession` to detect
    /// when the resolved policy no longer matches the live adapter (e.g. the
    /// experimental flag flipped mid-session) and the adapter must be rebuilt.
    var deliveryMode: InputDeliveryMode { .markedText }

    init(client: IMKTextInput, bundleId: String) {
        self.client = client
        self.bundleId = bundleId
        self.preeditAttributes = PreeditUnderline.attributes(forBundleId: bundleId)
    }

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        // Canonical IMK commit: pass NSNotFound so the host replaces the current
        // marked text automatically. This matches Apple's own input methods and is
        // what native hosts (e.g. KakaoTalk) expect. Passing an explicit marked
        // range here desynced KakaoTalk's composition (stranded marked text +
        // missing commit on focus loss).
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    func setMarkedText(_ text: String) {
        // Default: no-op, subclasses override
    }

    func textBeforeCursor(length: Int) -> String? {
        let selRange = client.selectedRange()
        guard selRange.location != NSNotFound, selRange.location < 10000000 else { return nil } // Protect against Chromium garbage values

        let location = max(0, selRange.location - length)
        let actualLength = selRange.location - location
        guard actualLength > 0 else { return "" }

        let charRange = NSRange(location: location, length: actualLength)
        return client.attributedSubstring(from: charRange)?.string
    }

    func replaceTextBeforeCursor(length: Int, with text: String) {
        let selRange = client.selectedRange()
        guard selRange.location != NSNotFound, selRange.location < 10000000, selRange.location >= length else { return }

        let replacementRange = NSRange(location: selRange.location - length, length: length)
        client.insertText(text, replacementRange: replacementRange)
    }
}

// MARK: - MarkedTextAdapter

/// Standard adapter with invisible-underline marked text for composition display
final class MarkedTextAdapter: BaseClientAdapter {
    override func setMarkedText(_ text: String) {
        // Canonical marked-text protocol, matching Apple's own input methods:
        // set the marked text directly with replacementRange = NSNotFound (an
        // empty string clears the composition). No visible underline on composing
        // Hangul (engine-tuned attributes — see `PreeditUnderline`). The previous
        // non-canonical path (clearing via insertText("") over an explicit marked
        // range) left native hosts like KakaoTalk in an inconsistent composition
        // state — a stranded/underlined preedit that never committed on focus loss.
        let attributed = NSAttributedString(string: text, attributes: preeditAttributes)
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }
}

// MARK: - ImmediateModeAdapter

/// Immediate mode adapter for non-text contexts (e.g., Finder desktop)
/// Skips setMarkedText to prevent floating composition window
final class ImmediateModeAdapter: BaseClientAdapter {
    override var deliveryMode: InputDeliveryMode { .immediate }
    // Inherits no-op setMarkedText from base class
}

// MARK: - DirectInsertionAdapter

/// EXPERIMENTAL (Phase 3): Windows-style direct insertion. There is no marked
/// text — the in-progress syllable is written as REAL text and rewritten in place
/// each keystroke. This isolates all direct-insertion state here so `HangulComposer`
/// stays unchanged: the composer keeps calling `insertText`/`setMarkedText` and this
/// adapter reinterprets them as in-place real-text rewrites.
///
/// Selected only when `experimentalDirectInsertion` is ON, the host is on the
/// `directInsertionAllowed` allowlist, AND the activation probe found
/// `documentAccessSafe`. OFF by default. See Docs/KoreanWindowsInputFeasibility.md.
final class DirectInsertionAdapter: BaseClientAdapter {
    override var deliveryMode: InputDeliveryMode { .directInsertion }

    /// UTF-16 length of the live (in-progress) syllable currently sitting in the
    /// document as real text. 0 when there is no live preedit.
    private var livePreeditLength: Int = 0
    /// The exact string we last wrote as the live preedit. Used to VERIFY the live
    /// region is still where we think before deleting it (caret-stability guard).
    private var livePreeditText: String = ""
    /// Caret position we expect (UTF-16 offset) right after our last edit. When the
    /// host reports the SAME caret on the next keystroke, the live region is provably
    /// intact and we can SKIP the expensive attributedSubstring read-back (perf).
    private var expectedCaret: Int = NSNotFound
    /// Once the client proves it lacks reliable document access mid-composition,
    /// degrade to marked text for the rest of the session rather than strand text.
    private var fellBackToMarked = false

    /// Clear live-preedit tracking. Called by the session whenever composition
    /// ends out-of-band (focus loss, mouse-click commit, secure passthrough). Also
    /// re-arms direct insertion: a clean finalize lets a host that momentarily
    /// returned a bad selectionRange try direct insertion again.
    func resetPreeditTracking() {
        livePreeditLength = 0
        livePreeditText = ""
        expectedCaret = NSNotFound
        fellBackToMarked = false
    }

    private func renderMarkedFallback(_ text: String) {
        let attributed = NSAttributedString(string: text, attributes: preeditAttributes)
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: text.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    /// Replace the live-preedit region (if any) with `text` as REAL text.
    /// `keepingLive` = true means `text` is the new live preedit; false means it is
    /// a finalized commit that becomes permanent (tracked length resets to 0).
    private func rewriteLivePreedit(with text: String, keepingLive: Bool) {
        if fellBackToMarked {
            renderMarkedFallback(text)
            return
        }

        let tStart = CFAbsoluteTimeGetCurrent()
        let caret = client.selectedRange().location
        let tAfterSel = CFAbsoluteTimeGetCurrent()
        var readbackMs = 0.0

        // CARET-STABILITY GUARD — prevents the direct-insertion corruption class.
        // The live preedit is REAL text the user can click or arrow away from, and
        // because there is no marked range IMK does NOT notify us when the caret moves.
        //
        // FAST PATH: if the host reports the caret exactly where our last edit left it
        // (`caret == expectedCaret`), the live region is provably intact — skip the
        // expensive attributedSubstring read-back (one synchronous IPC per keystroke,
        // a real latency source in some native hosts). Only when the caret differs do
        // we pay for the read-back to verify before deleting; on any mismatch we
        // abandon tracking and insert fresh — never deleting text we cannot verify.
        if livePreeditLength > 0 && caret != expectedCaret {
            let tReadStart = CFAbsoluteTimeGetCurrent()
            let actual: String?
            if caret != NSNotFound, caret >= livePreeditLength,
               caret < DirectInsertionPlanner.maxReasonableLocation {
                let region = NSRange(location: caret - livePreeditLength, length: livePreeditLength)
                actual = client.attributedSubstring(from: region)?.string
            } else {
                actual = nil
            }
            readbackMs = (CFAbsoluteTimeGetCurrent() - tReadStart) * 1000
            let verified = DirectInsertionPlanner.liveRegionIsVerified(
                caret: caret,
                livePreeditLength: livePreeditLength,
                actualSubstring: actual,
                expectedText: livePreeditText
            )
            if !verified {
                livePreeditLength = 0
                livePreeditText = ""
                DebugLogger.log("DirectInsertionAdapter: caret moved (\(caret) != expected \(expectedCaret)), abandoning stale preedit tracking")
            }
        }

        let plan = DirectInsertionPlanner.plan(
            cursorLocation: caret,
            livePreeditLength: livePreeditLength,
            textUTF16Count: text.utf16.count,
            keepingLive: keepingLive
        )
        if plan.bailed {
            // Document access unreliable: degrade to marked text to avoid stranding
            // a half-jamo. (Should be rare — probe + denylist gate this.)
            fellBackToMarked = true
            livePreeditLength = 0
            livePreeditText = ""
            expectedCaret = NSNotFound
            renderMarkedFallback(text)
            DebugLogger.log("DirectInsertionAdapter: invalid selectedRange, falling back to marked text")
            return
        }

        let tBeforeInsert = CFAbsoluteTimeGetCurrent()
        client.insertText(text, replacementRange: plan.replaceRange)
        let tEnd = CFAbsoluteTimeGetCurrent()

        livePreeditLength = plan.newLivePreeditLength
        livePreeditText = keepingLive ? text : ""
        expectedCaret = plan.replaceRange.location + text.utf16.count

        // Instrumentation: surface a slow rewrite with a per-IPC breakdown so latency
        // ("렉") can be pinpointed. Only logs the slow ones to avoid spam.
        let totalMs = (tEnd - tStart) * 1000
        if totalMs > 8 {
            DebugLogger.log(String(
                format: "DirectInsert SLOW total=%.1fms selRange=%.1fms readback=%.1fms insert=%.1fms len=%d",
                totalMs, (tAfterSel - tStart) * 1000, readbackMs, (tEnd - tBeforeInsert) * 1000, livePreeditLength))
        }
    }

    override func insertText(_ text: String) {
        if fellBackToMarked {
            super.insertText(text)   // base: NSNotFound auto-replaces marked text
            return
        }
        guard !text.isEmpty else { return }
        // A finalized insert replaces the live preedit (if any) and becomes permanent.
        // This is also why a hard commit cannot double-insert: committing the live
        // syllable rewrites the same region it already occupies.
        rewriteLivePreedit(with: text, keepingLive: false)
    }

    override func setMarkedText(_ text: String) {
        // No marked text in direct insertion: render the preedit as real text in place.
        rewriteLivePreedit(with: text, keepingLive: true)
    }

    override func replaceTextBeforeCursor(length: Int, with text: String) {
        // Committed-text edit (e.g. double-space period); no live preedit involved.
        livePreeditLength = 0
        super.replaceTextBeforeCursor(length: length, with: text)
    }
}
