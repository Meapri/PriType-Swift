import Testing
import Cocoa
@testable import PriTypeCore

// MARK: - Direct Insertion (Phase 3, experimental) Tests
//
// Validates the Windows-style direct-insertion delivery logic without a live
// IMKTextInput: the pure DirectInsertionPlanner, the commit-before-mark ordering the
// model relies on, and an end-to-end simulation through a fake client that applies the
// same plan the real DirectInsertionAdapter would.

@Suite("DirectInsertionPlanner")
struct DirectInsertionPlannerTests {

    @Test("Preedit update replaces the live region and tracks new length")
    func preeditUpdate() {
        // cursor at 5, live preedit "가가" (2 utf16) -> replace {3,2} with new preedit "각" (1)
        let plan = DirectInsertionPlanner.plan(
            cursorLocation: 5, livePreeditLength: 2, textUTF16Count: 1, keepingLive: true)
        #expect(!plan.bailed)
        #expect(plan.replaceRange == NSRange(location: 3, length: 2))
        #expect(plan.newLivePreeditLength == 1)
    }

    @Test("Commit replaces the live region and resets tracked length to 0")
    func commitFinalizes() {
        let plan = DirectInsertionPlanner.plan(
            cursorLocation: 5, livePreeditLength: 2, textUTF16Count: 2, keepingLive: false)
        #expect(!plan.bailed)
        #expect(plan.replaceRange == NSRange(location: 3, length: 2))
        #expect(plan.newLivePreeditLength == 0, "Committed text is permanent, not live")
    }

    @Test("First keystroke (no live preedit) inserts at cursor")
    func firstKeystroke() {
        let plan = DirectInsertionPlanner.plan(
            cursorLocation: 0, livePreeditLength: 0, textUTF16Count: 1, keepingLive: true)
        #expect(!plan.bailed)
        #expect(plan.replaceRange == NSRange(location: 0, length: 0))
        #expect(plan.newLivePreeditLength == 1)
    }

    @Test("Bails on NSNotFound cursor (no document access)")
    func bailsOnNSNotFound() {
        let plan = DirectInsertionPlanner.plan(
            cursorLocation: NSNotFound, livePreeditLength: 1, textUTF16Count: 1, keepingLive: true)
        #expect(plan.bailed)
        #expect(plan.replaceRange.location == NSNotFound)
    }

    @Test("Bails on Chromium-garbage cursor location")
    func bailsOnGarbage() {
        let plan = DirectInsertionPlanner.plan(
            cursorLocation: 20_000_000, livePreeditLength: 1, textUTF16Count: 1, keepingLive: true)
        #expect(plan.bailed)
    }

    @Test("Bails when live length exceeds cursor (would delete real text)")
    func bailsWhenLiveExceedsCursor() {
        let plan = DirectInsertionPlanner.plan(
            cursorLocation: 0, livePreeditLength: 2, textUTF16Count: 1, keepingLive: true)
        #expect(plan.bailed, "Cannot delete 2 chars when caret is at 0")
    }
}

// MARK: - Caret-stability guard (prevents click/arrow corruption)

@Suite("DirectInsertion caret-stability guard")
struct DirectInsertionStabilityTests {

    @Test("No tracking ⇒ always safe")
    func nothingTracked() {
        #expect(DirectInsertionPlanner.liveRegionIsVerified(
            caret: 5, livePreeditLength: 0, actualSubstring: nil, expectedText: ""))
    }

    @Test("Read-back matches the tracked preedit ⇒ verified")
    func matchVerified() {
        // doc "...가", caret right after the live "가" (len 1), read-back == "가"
        #expect(DirectInsertionPlanner.liveRegionIsVerified(
            caret: 3, livePreeditLength: 1, actualSubstring: "가", expectedText: "가"))
    }

    @Test("Caret moved PAST the live region (read-back differs) ⇒ NOT verified")
    func forwardMoveRejected() {
        // bug #3: doc "AB가CD", live 가, user clicked caret to index 5; the bytes at
        // [4,1] are "D", not "가" → must abandon tracking, never delete "D".
        #expect(!DirectInsertionPlanner.liveRegionIsVerified(
            caret: 5, livePreeditLength: 1, actualSubstring: "D", expectedText: "가"))
    }

    @Test("Caret moved BEFORE the live region (cursor < len) ⇒ NOT verified")
    func backwardMoveRejected() {
        #expect(!DirectInsertionPlanner.liveRegionIsVerified(
            caret: 0, livePreeditLength: 1, actualSubstring: nil, expectedText: "가"))
    }

    @Test("Unreadable region (nil) ⇒ NOT verified")
    func unreadableRejected() {
        #expect(!DirectInsertionPlanner.liveRegionIsVerified(
            caret: 3, livePreeditLength: 1, actualSubstring: nil, expectedText: "가"))
    }

    @Test("NSNotFound / garbage caret ⇒ NOT verified")
    func garbageCaretRejected() {
        #expect(!DirectInsertionPlanner.liveRegionIsVerified(
            caret: NSNotFound, livePreeditLength: 1, actualSubstring: "가", expectedText: "가"))
        #expect(!DirectInsertionPlanner.liveRegionIsVerified(
            caret: 20_000_000, livePreeditLength: 1, actualSubstring: "가", expectedText: "가"))
    }
}

// MARK: - Electron/Chromium denylist (direct insertion physically impossible)

@Suite("DirectInsertion denylist")
struct DirectInsertionDenylistTests {

    @Test("Electron / browser hosts are denied")
    func electronDenied() {
        for id in [
            "com.anthropic.claudefordesktop",
            "com.microsoft.VSCode",
            "com.tinyspeck.slackmacgap",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.apple.Safari"
        ] {
            #expect(ClientCompatibilityPolicy.directInsertionDenied(bundleId: id), "should deny \(id)")
        }
    }

    @Test("Keyword heuristic catches unlisted Electron/Chromium wrappers")
    func keywordHeuristic() {
        #expect(ClientCompatibilityPolicy.directInsertionDenied(bundleId: "com.example.MyElectronApp"))
        #expect(ClientCompatibilityPolicy.directInsertionDenied(bundleId: "org.chromium.Chromium"))
        #expect(ClientCompatibilityPolicy.directInsertionDenied(bundleId: "com.vendor.someChromeThing"))
    }

    @Test("Native AppKit hosts are NOT denied")
    func nativeAllowed() {
        for id in [
            "com.kakao.KakaoTalkMac",
            "com.apple.Notes",
            "com.apple.TextEdit",
            "com.apple.dt.Xcode"
        ] {
            #expect(!ClientCompatibilityPolicy.directInsertionDenied(bundleId: id), "should allow \(id)")
        }
    }
}

// MARK: - Duplicate keyDown suppression

@Suite("KeyEventDedup")
struct KeyEventDedupTests {
    private func snap(_ t: TimeInterval, _ code: UInt16, _ repeat_: Bool = false) -> KeyDownSnapshot {
        KeyDownSnapshot(timestamp: t, keyCode: code, isARepeat: repeat_)
    }

    @Test("Exact re-delivery (same timestamp, same key) is a duplicate")
    func exactDuplicate() {
        #expect(KeyEventDedup.isDuplicate(snap(100.0, 51), previous: snap(100.0, 51)))
    }

    @Test("Re-delivery within the window is a duplicate")
    func withinWindow() {
        #expect(KeyEventDedup.isDuplicate(snap(100.02, 51), previous: snap(100.0, 51)))
    }

    @Test("Outside the window is NOT a duplicate (human double-tap)")
    func outsideWindow() {
        #expect(!KeyEventDedup.isDuplicate(snap(100.2, 51), previous: snap(100.0, 51)))
    }

    @Test("Different keyCode is never a duplicate (fast typing)")
    func differentKey() {
        #expect(!KeyEventDedup.isDuplicate(snap(100.01, 40), previous: snap(100.0, 51)))
    }

    @Test("Auto-repeat events are never treated as duplicates")
    func autoRepeatExempt() {
        // new is a repeat
        #expect(!KeyEventDedup.isDuplicate(snap(100.01, 51, true), previous: snap(100.0, 51, false)))
        // previous was a repeat (held key)
        #expect(!KeyEventDedup.isDuplicate(snap(100.01, 51, false), previous: snap(100.0, 51, true)))
    }

    @Test("No previous event ⇒ not a duplicate")
    func noPrevious() {
        #expect(!KeyEventDedup.isDuplicate(snap(100.0, 51), previous: nil))
    }
}

// MARK: - Commit-before-mark ordering invariant (marked-text mode)

@Suite("Commit-before-mark ordering")
struct CommitBeforeMarkOrderingTests {

    /// On a syllable boundary (받침 migration), the previous syllable must be
    /// committed via insertText BEFORE the new syllable is shown via setMarkedText.
    /// This is the load-bearing invariant for both the Windows-feel marked path and
    /// the experimental direct-insertion path.
    @Test("받침 migration commits previous syllable before marking the new one")
    func migrationOrdering() {
        let statusBar = MockStatusBar()
        let composer = HangulComposer(statusBar: statusBar, configuration: MockConfiguration())
        let delegate = MockComposerDelegate()

        // Type 안 (ㅇ ㅏ ㄴ)
        _ = composer.handle(TestEventFactory.keyEvent(char: "d", keyCode: 2)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "s", keyCode: 1)!, delegate: delegate)

        // Reset the call log, then trigger migration with ㅏ: 안 + ㅏ -> 아 + 나
        delegate.orderedCalls = []
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)

        #expect(delegate.orderedCalls == ["insert:아", "mark:나"],
                "Expected commit(아) before mark(나), got \(delegate.orderedCalls)")
    }
}

// MARK: - End-to-end direct insertion simulation

/// Models a text field under direct insertion: maintains real document text + the
/// live-preedit length, applying the SAME DirectInsertionPlanner the real
/// DirectInsertionAdapter uses, with the caret pinned at end-of-document.
final class FakeDirectInsertionClient: HangulComposerDelegate {
    private(set) var document = ""
    private var livePreeditLength = 0

    private func rewrite(_ text: String, keepingLive: Bool) {
        let cursor = document.utf16.count
        let plan = DirectInsertionPlanner.plan(
            cursorLocation: cursor,
            livePreeditLength: livePreeditLength,
            textUTF16Count: text.utf16.count,
            keepingLive: keepingLive)
        guard !plan.bailed else { return }
        var units = Array(document.utf16)
        let start = plan.replaceRange.location
        let end = start + plan.replaceRange.length
        units.replaceSubrange(start..<end, with: Array(text.utf16))
        document = String(decoding: units, as: UTF16.self)
        livePreeditLength = plan.newLivePreeditLength
    }

    func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        rewrite(text, keepingLive: false)
    }
    func setMarkedText(_ text: String) {
        rewrite(text, keepingLive: true)
    }
    func textBeforeCursor(length: Int) -> String? { nil }
    func replaceTextBeforeCursor(length: Int, with text: String) {
        livePreeditLength = 0
        var units = Array(document.utf16)
        guard units.count >= length else { return }
        units.removeLast(length)
        units.append(contentsOf: Array(text.utf16))
        document = String(decoding: units, as: UTF16.self)
    }
}

@Suite("Direct insertion end-to-end")
struct DirectInsertionEndToEndTests {

    private func makeComposer() -> (HangulComposer, FakeDirectInsertionClient) {
        let composer = HangulComposer(statusBar: MockStatusBar(), configuration: MockConfiguration())
        return (composer, FakeDirectInsertionClient())
    }

    @Test("받침 migration + space produces clean real text with no duplication")
    func migrationThenSpace() {
        let (composer, client) = makeComposer()
        // 안 + ㅏ -> 아 나, then space commits the live 나
        for (char, code): (String, UInt16) in [("d", 2), ("k", 40), ("s", 1), ("k", 40)] {
            _ = composer.handle(TestEventFactory.keyEvent(char: char, keyCode: code)!, delegate: client)
        }
        #expect(client.document == "아나", "Got '\(client.document)'")

        _ = composer.handle(TestEventFactory.keyEvent(char: " ", keyCode: KeyCode.space)!, delegate: client)
        #expect(client.document == "아나 ", "Space must not duplicate the live syllable; got '\(client.document)'")
    }

    @Test("Escape removes the in-progress syllable that was written as real text")
    func escapeRemovesLivePreedit() {
        let (composer, client) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: client) // ㄱ
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: client) // 가
        #expect(client.document == "가")

        _ = composer.handle(TestEventFactory.keyEvent(char: "\u{1B}", keyCode: KeyCode.escape)!, delegate: client)
        #expect(client.document == "", "Escape must delete the live preedit; got '\(client.document)'")
    }

    @Test("Backspace decomposes the live syllable in place")
    func backspaceDecomposes() {
        let (composer, client) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: client) // ㄱ
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: client) // 가
        #expect(client.document == "가")

        _ = composer.handle(TestEventFactory.keyEvent(char: "\u{7F}", keyCode: KeyCode.backspace)!, delegate: client)
        #expect(client.document == "ㄱ", "Backspace should leave ㄱ in place; got '\(client.document)'")
    }

    @Test("Two committed syllables accumulate correctly")
    func twoSyllables() {
        let (composer, client) = makeComposer()
        // 가 (r,k) space 나 (s,k)  -> "가 나"
        for (char, code): (String, UInt16) in [("r", 15), ("k", 40)] {
            _ = composer.handle(TestEventFactory.keyEvent(char: char, keyCode: code)!, delegate: client)
        }
        _ = composer.handle(TestEventFactory.keyEvent(char: " ", keyCode: KeyCode.space)!, delegate: client)
        for (char, code): (String, UInt16) in [("s", 1), ("k", 40)] {
            _ = composer.handle(TestEventFactory.keyEvent(char: char, keyCode: code)!, delegate: client)
        }
        #expect(client.document == "가 나", "Got '\(client.document)'")
    }
}
