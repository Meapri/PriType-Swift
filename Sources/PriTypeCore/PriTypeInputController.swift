import Cocoa
import InputMethodKit
import LibHangul
import Carbon.HIToolbox

@objc(PriTypeInputController)
public class PriTypeInputController: IMKInputController, @unchecked Sendable {
    // Two PriType input modes registered in Info.plist ComponentInputModeDict.
    // Korean composes; English is a pure pass-through (ABC layout override).
    // macOS Caps Lock / input-source switching moves between these two modes.
    private static let priTypeInputSourceID = "com.pritype.inputmethod.v2"          // Korean mode (== bundle id)
    private static let priTypeEnglishInputModeID = "com.pritype.inputmethod.v2.english"
    private static let romanKeyboardLayoutID = resolveRomanKeyboardLayoutID()
    private static let romanKeyboardLayoutCandidates = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US"
    ]
    
    // MARK: - Shared State
    //
    // THREAD SAFETY INVARIANTS:
    // These static properties use `nonisolated(unsafe)` for Swift 6 strict concurrency compliance.
    //
    // WHY NOT @MainActor?
    // IMKInputController callbacks (handle, activateServer, etc.) are NOT @MainActor-isolated.
    // Swift 6 compiler would reject @MainActor property access from these callbacks.
    //
    // IMK guarantees main thread execution by design:
    // 1. `sharedComposer`: Created once at startup, accessed only via IMK callbacks
    // 2. `sharedController`: Read/written only in activateServer/deactivateServer
    //
    // This is a documented limitation of integrating Swift 6 strict concurrency with
    // legacy Objective-C frameworks like InputMethodKit.
    
    /// Shared composer instance for toggle key handler access
    /// - Warning: Access from main thread only (guaranteed by IMK, not compiler-enforced)
    public static let sharedComposer = HangulComposer()
    private var composer: HangulComposer { Self.sharedComposer }
    
    /// Last active controller reference for external toggle access
    /// - Warning: Access from main thread only (guaranteed by IMK, not compiler-enforced)
    nonisolated(unsafe) public static weak var sharedController: PriTypeInputController?
    
    // Strong reference to prevent client being released during rapid switching
    private var lastClient: IMKTextInput?
    private var lastKnownInputClient: IMKTextInput?

    #if DEBUG
    private var debugHandleLogCount = 0
    #endif
    private var lastKeyboardOverrideClientID: ObjectIdentifier?
    private var lastKeyboardOverrideTime: CFAbsoluteTime = 0

    // Commits the composition early on app-focus-loss (see updateApplicationDeactivateObserver).
    private var applicationDeactivateObserver: Any?

    // Keep adapter alive for external toggle calls
    public private(set) var currentAdapter: (any HangulComposerDelegate)?

    // Duplicate-keyDown suppression (some hosts, e.g. KakaoTalk, deliver the same
    // physical keyDown twice). Only acted on in experimental direct-insertion mode.
    private var lastKeyDown: KeyDownSnapshot?
    private var lastHandleReturn = false
    
    // MARK: - Adapter Classes
    
    /// Base adapter class with common IMKTextInput operations
    /// Subclasses override setMarkedText for different behaviors
    private class BaseClientAdapter: NSObject, HangulComposerDelegate {
        let client: IMKTextInput
        
        init(client: IMKTextInput) {
            self.client = client
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
    
    /// Standard adapter with plain (no underline) marked text for composition display
    private class ClientAdapter: BaseClientAdapter {
        override func setMarkedText(_ text: String) {
            // Canonical marked-text protocol, matching Apple's own input methods:
            // set the marked text directly with replacementRange = NSNotFound (an
            // empty string clears the composition). No underline on composing Hangul
            // (underline style 0). The previous non-canonical path (clearing via
            // insertText("") over an explicit marked range) left native hosts like
            // KakaoTalk in an inconsistent composition state — a stranded/underlined
            // preedit that never committed on focus loss.
            let attributed = NSAttributedString(string: text, attributes: [.underlineStyle: 0])
            client.setMarkedText(
                attributed,
                selectionRange: NSRange(location: text.utf16.count, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        }
    }

    /// Immediate mode adapter for non-text contexts (e.g., Finder desktop)
    /// Skips setMarkedText to prevent floating composition window
    private final class ImmediateModeAdapter: BaseClientAdapter {
        // Inherits no-op setMarkedText from base class
    }

    /// EXPERIMENTAL (Phase 3): Windows-style direct insertion. There is no marked
    /// text — the in-progress syllable is written as REAL text and rewritten in place
    /// each keystroke. This isolates all direct-insertion state here so `HangulComposer`
    /// stays unchanged: the composer keeps calling `insertText`/`setMarkedText` and this
    /// adapter reinterprets them as in-place real-text rewrites.
    ///
    /// Selected only when `experimentalDirectInsertion` is ON, the host is on the
    /// `directInsertionAllowed` allowlist, AND the activation probe found
    /// `documentAccessSafe`. OFF by default. See Docs/KoreanWindowsInputFeasibility.md.
    private final class DirectInsertionAdapter: BaseClientAdapter {
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

        /// Clear live-preedit tracking. Called by the controller whenever composition
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
            let attributed = NSAttributedString(string: text, attributes: [.underlineStyle: 0])
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

    private enum InputDeliveryMode {
        case immediate          // Finder desktop: defer, no marked window
        case directInsertion    // EXPERIMENTAL: real-text in-place rewrite
        case markedText         // Default: canonical marked-text composition
    }

    // MARK: - State Management
    
    /// Cached client context to avoid expensive IPC calls on every keystroke
    /// - Note: Calculated in `activateServer`, used in `handle`, cleared in `deactivateServer`
    private(set) var cachedContext: ClientContext?

    /// Decide how composition is delivered to this client. Default is canonical
    /// marked text. Direct insertion (experimental) is attempted in EVERY app when the
    /// flag is ON — there is no per-app allowlist. The only gate is the activation
    /// probe `documentAccessSafe`: apps that cannot report a usable selection range
    /// (e.g. terminals) physically cannot do in-place rewrites, so they keep the
    /// marked-text path. Apps that pass the probe but misbehave at runtime degrade to
    /// marked text via the adapter's caret-stability guard / bail path — so enabling
    /// it everywhere never corrupts text, it just falls back where it can't work.
    private func deliveryMode(for context: ClientContext) -> InputDeliveryMode {
        if context.shouldUseImmediateMode {
            return .immediate
        }
        if ConfigurationManager.shared.experimentalDirectInsertion,
           context.documentAccessSafe,
           !ClientCompatibilityPolicy.directInsertionDenied(bundleId: context.bundleId) {
            return .directInsertion
        }
        return .markedText
    }

    private func makeAdapter(for client: IMKTextInput, context: ClientContext) -> any HangulComposerDelegate {
        switch deliveryMode(for: context) {
        case .immediate:
            return ImmediateModeAdapter(client: client)
        case .directInsertion:
            DebugLogger.log("PriTypeInputController: DirectInsertionAdapter (experimental) for \(context.bundleId)")
            return DirectInsertionAdapter(client: client)
        case .markedText:
            return ClientAdapter(client: client)
        }
    }

    private func adapterMatchesContext(_ adapter: (any HangulComposerDelegate)?, context: ClientContext) -> Bool {
        switch deliveryMode(for: context) {
        case .immediate:
            return adapter is ImmediateModeAdapter
        case .directInsertion:
            return adapter is DirectInsertionAdapter
        case .markedText:
            // ClientAdapter only — DirectInsertionAdapter is a sibling BaseClientAdapter
            // subclass, not a ClientAdapter, so this correctly forces recreation when
            // the flag flips off mid-session.
            return adapter is ClientAdapter
        }
    }

    private func syncRomanKeyboardLayout(for client: IMKTextInput, force: Bool = false) {
        let clientID = ObjectIdentifier(client as AnyObject)
        let now = CFAbsoluteTimeGetCurrent()
        guard force || lastKeyboardOverrideClientID != clientID || now - lastKeyboardOverrideTime > 0.5 else {
            return
        }

        let selector = NSSelectorFromString("overrideKeyboardWithKeyboardNamed:")
        let object = client as AnyObject
        guard object.responds(to: selector) else {
            DebugLogger.log("PriTypeInputController: client does not support keyboard override")
            return
        }

        _ = object.perform(selector, with: Self.romanKeyboardLayoutID)
        lastKeyboardOverrideClientID = clientID
        lastKeyboardOverrideTime = now
        DebugLogger.log("PriTypeInputController: override keyboard layout -> \(Self.romanKeyboardLayoutID)")
    }

    private static func resolveRomanKeyboardLayoutID() -> String {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String
        ]

        guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, true)?.takeRetainedValue() as? [TISInputSource] else {
            return romanKeyboardLayoutCandidates[0]
        }

        let availableIDs = Set(sourceList.compactMap { source -> String? in
            guard let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                return nil
            }
            return Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
        })

        return romanKeyboardLayoutCandidates.first { availableIDs.contains($0) } ?? romanKeyboardLayoutCandidates[0]
    }


    /// Finalize the in-progress composition into `client` in a SINGLE operation:
    /// replace the marked-text range with the committed string. One op (not commit +
    /// separate clear) avoids the focus-loss flicker. Idempotent — no-op when there is
    /// no active composition, so the observer and deactivateServer can both call it.
    private func finalizeComposition(to client: IMKTextInput?, reason: String) {
        guard composer.hasActiveComposition else { return }

        // EXPERIMENTAL direct insertion: the in-progress syllable is ALREADY real text
        // in the document. Re-inserting it here would duplicate the character. Just end
        // the engine's composition and clear the adapter's live-preedit tracking.
        if let direct = currentAdapter as? DirectInsertionAdapter {
            _ = composer.flushCommitString()   // flush engine + update buffer; do NOT insert
            direct.resetPreeditTracking()
            DebugLogger.log("PriTypeInputController: finalizeComposition[\(reason)] direct-insertion (already in document, no re-insert)")
            return
        }

        guard let client else { return }
        let markedRange = client.markedRange()
        let committed = composer.flushCommitString()
        DebugLogger.log("PriTypeInputController: finalizeComposition[\(reason)] client=\(client.bundleIdentifier() ?? "?") marked=(\(markedRange.location),\(markedRange.length)) len=\(committed.count)")
        if !committed.isEmpty {
            // Canonical finalize: NSNotFound asks the host to convert its OWN marked text to
            // committed (composition-end), rather than an explicit marked-range edit. The
            // explicit edit makes hosts re-run text detection — e.g. KakaoTalk re-fires its
            // emoticon-recommendation popup (a visible flicker). The composition-end path
            // avoids that. (Done at app-deactivate-observer timing, the host still accepts it.)
            client.insertText(committed, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        } else if markedRange.location != NSNotFound, markedRange.length > 0 {
            client.insertText("", replacementRange: markedRange)
        }
    }

    /// Observe the focused app's deactivation and finalize the composition THEN — early
    /// enough that the host (e.g. KakaoTalk) still accepts the insertText. By the time
    /// IMK's deactivateServer runs, native hosts have already resigned and drop it,
    /// leaving a stranded/underlined preedit. Host-agnostic; no bundle-ID hardcoding.
    private func updateApplicationDeactivateObserver(for context: ClientContext) {
        removeApplicationDeactivateObserver()
        guard !context.bundleId.isEmpty else { return }
        applicationDeactivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == context.bundleId else {
                return
            }
            self.finalizeComposition(to: self.lastClient ?? self.lastKnownInputClient, reason: "appDeactivate")
        }
    }

    private func removeApplicationDeactivateObserver() {
        if let observer = applicationDeactivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            applicationDeactivateObserver = nil
        }
    }

    public func performPriTypeModeTransition(source: InputModeCoordinator.ToggleSource) {
        guard let client = lastClient ?? lastKnownInputClient else {
            DebugLogger.log("PriTypeInputController: no current client for mode transition (\(source))")
            return
        }

        let nextMode = composer.inputMode.toggled
        DebugLogger.log("PriTypeInputController: mode transition \(composer.inputMode) -> \(nextMode) source=\(source)")

        commitActiveCompositionBeforeModeTransition()
        syncRomanKeyboardLayout(for: client, force: true)
        composer.setInputMode(nextMode)
        syncSelectedInputModeForMenuBar(client: client, mode: nextMode)
    }

    /// Best-effort: tell macOS which PriType mode is active so the menu-bar input
    /// source indicator (and Caps Lock's notion of the current mode) matches a
    /// custom-key toggle. Cosmetic + consistency only — `composer.inputMode` is
    /// already the authoritative composition state, so even if this is delayed or
    /// unsupported, typing is unaffected (no first-key race). Without it, a
    /// custom-key toggle and macOS's selected mode could drift apart.
    private func syncSelectedInputModeForMenuBar(client: IMKTextInput, mode: InputMode) {
        let modeID = mode == .english ? Self.priTypeEnglishInputModeID : Self.priTypeInputSourceID
        let selector = NSSelectorFromString("selectInputMode:")
        let object = client as AnyObject
        guard object.responds(to: selector) else {
            DebugLogger.log("PriTypeInputController: client does not support selectInputMode:")
            return
        }
        _ = object.perform(selector, with: modeID)
        DebugLogger.log("PriTypeInputController: selectInputMode -> \(modeID)")
    }

    private func commitActiveCompositionBeforeModeTransition() {
        guard composer.hasActiveComposition else {
            composer.clearLocalBuffer()
            return
        }

        if let adapter = currentAdapter {
            composer.forceCommit(delegate: adapter)
            adapter.setMarkedText("")
        } else if let client = lastClient ?? lastKnownInputClient {
            let adapter = ClientAdapter(client: client)
            composer.forceCommit(delegate: adapter)
            adapter.setMarkedText("")
        }
    }

    deinit {
        // The selector-based `.keyboardLayoutChanged` observer is auto-removed on
        // modern macOS, but remove it explicitly to be safe. The block-based
        // NSWorkspace deactivate observer is NOT auto-removed, so clean it up too.
        removeApplicationDeactivateObserver()
        NotificationCenter.default.removeObserver(self, name: .keyboardLayoutChanged, object: nil)
    }

    // 입력기가 활성화될 때 호출 - 새 세션 시작
    override public func activateServer(_ sender: Any!) {
        #if DEBUG
        assert(Thread.isMainThread, "IMK activateServer must run on main thread")
        #endif
        super.activateServer(sender)
        // NOTE: Focus changes never reset `composer.inputMode`. The Korean/English
        // state is owned solely by the toggle path and the `setValue` ingress, so
        // switching apps preserves whatever mode the user last chose.
        // 클라이언트 저장
        if let client = sender as? IMKTextInput {
            lastClient = client
            lastKnownInputClient = client
            syncRomanKeyboardLayout(for: client, force: true)
            
            // PERFORMANCE: Analyze context ONCE per session and cache it.
            // This avoids heavy IPC calls (bundleId check, coordinate calculation) on every keystroke.
            let context = ClientContextDetector.analyzeForActivation(client: client)
            self.cachedContext = context
            currentAdapter = makeAdapter(for: client, context: context)
            updateApplicationDeactivateObserver(for: context)
            DebugLogger.log("Activated for client: \(self.cachedContext?.bundleId ?? "unknown") (Lightweight Context)")
        } else {
            // Fallback if sender is not IMKTextInput (rare)
            self.cachedContext = nil
            removeApplicationDeactivateObserver()
        }
        
        // Set as active controller for toggle access
        Self.sharedController = self
        
        // Ensure composer has correct layout (in case it changed while inactive)
        let currentLayoutId = ConfigurationManager.shared.keyboardId
        composer.updateKeyboardLayout(id: currentLayoutId)
        
        // Observe layout changes. IMK can call activateServer again without an
        // intervening deactivateServer (common in Electron/Chromium hosts), and
        // NotificationCenter allows duplicate (observer, selector, name)
        // registrations that would each fire handleLayoutChange. Remove any prior
        // registration first so this stays idempotent.
        NotificationCenter.default.removeObserver(self, name: .keyboardLayoutChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLayoutChange), name: .keyboardLayoutChanged, object: nil)
    }
    
    override public func deactivateServer(_ sender: Any!) {
        #if DEBUG
        assert(Thread.isMainThread, "IMK deactivateServer must run on main thread")
        #endif
        // Fallback finalize. The primary path is the app-deactivate observer (it fires
        // earlier, while the host still accepts input); by the time deactivateServer
        // runs, native hosts like KakaoTalk have already resigned and ignore insertText.
        // If the observer already committed, this is a no-op.
        finalizeComposition(to: (sender as? IMKTextInput) ?? lastClient, reason: "deactivateServer")
        // NOTE: Do NOT clear localTextBuffer here.
        // Cross-app hanja leaking is prevented by bundleId matching in handleHanjaLookup(),
        // not by clearing the buffer. Clearing would make same-app hanja lookup impossible.
        super.deactivateServer(sender)
        // Do NOT clear currentAdapter here.
        // CGEventTap triggerHanjaLookup() is dispatched async and needs a valid adapter.
        // The next activateServer() will replace it with the new client's adapter.
        lastClient = nil
        // Keep cachedContext alive — activateServer() will replace it with the new client's context.
        // Clearing it here causes unnecessary slow path if handle() arrives before activateServer().
        removeApplicationDeactivateObserver()
        NotificationCenter.default.removeObserver(self, name: .keyboardLayoutChanged, object: nil)
    }
    
    @objc private func handleLayoutChange() {
        let newId = ConfigurationManager.shared.keyboardId
        DebugLogger.log("PriTypeInputController: Layout changed to \(newId), updating composer")
        composer.updateKeyboardLayout(id: newId)
    }
    
    // Match the native IMK path used by DINKIssTyle: ask IMK for flagsChanged
    // so TIS can drive Caps Lock language switching, then pass modifier events
    // through without doing any work in handle().
    override public func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override public func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        if tag == Int(kTextServiceInputModePropertyTag) {
            guard let inputModeID = value as? String, !inputModeID.isEmpty else {
                DebugLogger.log("PriTypeInputController: ignored empty input mode property")
                return
            }

            // Route the two PriType modes to the single composer source of truth.
            // This is how macOS Caps Lock / input-source switching between the
            // Korean and English modes reaches the composer — synchronously, so the
            // next keyDown already sees the new mode (no first-key race).
            let targetMode: InputMode?
            switch inputModeID {
            case Self.priTypeEnglishInputModeID: targetMode = .english
            case Self.priTypeInputSourceID:      targetMode = .korean
            default:                             targetMode = nil
            }
            DebugLogger.log("PriTypeInputController: setValue inputMode='\(inputModeID)' target=\(String(describing: targetMode)) current=\(composer.inputMode)")
            guard let targetMode else {
                super.setValue(value, forTag: tag, client: sender)
                return
            }

            if let client = sender as? IMKTextInput {
                syncRomanKeyboardLayout(for: client, force: true)
            }

            if composer.inputMode != targetMode {
                DebugLogger.log("PriTypeInputController: macOS selected PriType \(targetMode) mode")
                composer.setInputMode(targetMode)
            }
            return
        }

        super.setValue(value, forTag: tag, client: sender)
    }
    
    override public func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        #if DEBUG
        assert(Thread.isMainThread, "IMK handle must run on main thread")
        #endif
        guard let event = event, let client = sender as? IMKTextInput else { return false }

        guard event.type == .keyDown else {
            return false
        }

        // 0. Duplicate-keyDown suppression (direct-insertion mode only). Some hosts
        // (observed: KakaoTalk) deliver the same physical keyDown to the IME twice. That
        // double-processes input — notably one backspace decomposing TWO jamo, i.e. a
        // composing syllable "deleted all at once". Drop the exact re-delivery and replay
        // the original result. Gated to the direct adapter so the shipping marked-text
        // path is completely untouched.
        let keyDownSnapshot = KeyDownSnapshot(timestamp: event.timestamp, keyCode: event.keyCode, isARepeat: event.isARepeat)
        if currentAdapter is DirectInsertionAdapter,
           KeyEventDedup.isDuplicate(keyDownSnapshot, previous: lastKeyDown) {
            DebugLogger.log("PriTypeInputController: dropped duplicate keyDown keyCode=\(event.keyCode) (direct mode)")
            lastKeyDown = keyDownSnapshot
            return lastHandleReturn
        }
        lastKeyDown = keyDownSnapshot

        // 1. Resolve context FIRST — all subsequent logic must use fresh bundleId.
        // Context is invalidated when the client object changes (app switch without activateServer).
        // When lastClient is nil (after deactivateServer), always re-analyze to avoid
        // using stale context from a previous app/field.
        var context: ClientContext
        if let cached = self.cachedContext, let last = lastClient, last === client {
            if cached.isLightweight && cached.isFinder {
                context = ClientContextDetector.analyze(client: client)
                self.cachedContext = context
            } else {
                context = cached
            }
        } else {
            DebugLogger.log("cachedContext miss: client changed or nil, analyzing (Slow Path)")
            context = ClientContextDetector.analyze(client: client)
            self.cachedContext = context
            updateApplicationDeactivateObserver(for: context)
            // Do not update self.lastClient here. It must be updated alongside currentAdapter
            // below to ensure the adapter is correctly recreated when the client changes.
        }

        #if DEBUG
        if debugHandleLogCount < 200 {
            debugHandleLogCount += 1
            DebugLogger.log("PriTypeInputController: handle keyCode=\(event.keyCode) repeat=\(event.isARepeat) mode=\(composer.inputMode) chars='\(event.characters ?? "")' modifiers=\(event.modifierFlags.rawValue) bundle=\(context.bundleId) lightweight=\(context.isLightweight) immediate=\(context.shouldUseImmediateMode) clientChanged=\(lastClient !== client)")
        }
        #endif
        
        // 2. Mark keystroke with current app's bundleId for cross-app hanja validation
        composer.markKeystroke(bundleId: context.bundleId)

        // 3. DYNAMIC CHECK: Secure Input (password fields)
        if shouldPassThroughSecureInput(client: client, context: context) {
            composer.discardCompositionForPassThrough()
            // In direct insertion the syllable was written as real text; discarding the
            // engine without clearing adapter tracking would leave a stale livePreedit
            // length that the next keystroke would use to delete real text. Re-arm it.
            (currentAdapter as? DirectInsertionAdapter)?.resetPreeditTracking()
            return false
        }

        // Finder-specific handling
        if context.shouldUseImmediateMode {
            DebugLogger.log("Finder: ImmediateMode (context=\(context))")
            // Only recreate adapter if client changed or type mismatch
            if lastClient !== client || !adapterMatchesContext(currentAdapter, context: context) {
                lastClient = client
                syncRomanKeyboardLayout(for: client)
                currentAdapter = makeAdapter(for: client, context: context)
            }
            lastHandleReturn = composer.handle(event, delegate: currentAdapter!)
            return lastHandleReturn
        }

        // Reuse adapter from activateServer if client hasn't changed
        // This avoids ~20 heap allocations/second during fast typing
        if lastClient !== client || currentAdapter == nil || !adapterMatchesContext(currentAdapter, context: context) {
            lastClient = client
            syncRomanKeyboardLayout(for: client)
            currentAdapter = makeAdapter(for: client, context: context)
        }

        lastHandleReturn = composer.handle(event, delegate: currentAdapter!)
        return lastHandleReturn
    }

    private func shouldPassThroughSecureInput(client: IMKTextInput, context: ClientContext) -> Bool {
        let bundleId = context.bundleId

        if SecureInputPolicy.isSystemSecureClient(bundleId) {
            DebugLogger.log("Secure Input: System secure client (\(bundleId)), passing through")
            return true
        }

        let hasGlobalSecureInput = IsSecureEventInputEnabled()

        if hasGlobalSecureInput {
            DebugLogger.log("Secure Input: global secure input active in '\(bundleId)', passing through")
            return true
        }

        guard !context.hasTextInputCapability else {
            return false
        }

        let selectionRange = client.selectedRange()
        let hasInvalidSelection = selectionRange.location == NSNotFound

        if hasInvalidSelection {
            DebugLogger.log("Secure Input: invalid selection in '\(bundleId)', passing through")
            return true
        }

        return false
    }

    // 마우스 클릭 등으로 조합 영역 외부 클릭 시 조합 커밋
    override public func commitComposition(_ sender: Any!) {
        #if DEBUG
        assert(Thread.isMainThread, "IMK commitComposition must run on main thread")
        #endif

        // EXPERIMENTAL direct insertion: the live syllable is ALREADY real text in the
        // document. A mouse-click commit must NOT re-insert it (that would duplicate the
        // syllable and, if the caret moved, overwrite unrelated text). End the engine's
        // composition and clear adapter tracking instead — mirrors finalizeComposition.
        if let direct = currentAdapter as? DirectInsertionAdapter {
            if composer.hasActiveComposition { _ = composer.flushCommitString() }
            direct.resetPreeditTracking()
            composer.localTextBuffer = ""
            super.commitComposition(sender)
            return
        }

        if let client = sender as? IMKTextInput ?? lastClient {
            let adapter = currentAdapter ?? ClientAdapter(client: client)
            composer.forceCommit(delegate: adapter)
        }
        composer.localTextBuffer = "" // Clear buffer when focus changes or user clicks elsewhere
        super.commitComposition(sender)
    }

    private func currentContext(for sender: Any?) -> ClientContext? {
        if let client = sender as? IMKTextInput {
            if let cachedContext, lastClient === client {
                return cachedContext
            }
            return nil
        }
        return cachedContext
    }
    
    // MARK: - Input Method Menu
    
    /// Returns custom menu for the input method (shown in system input source menu)
    override public func menu() -> NSMenu! {
        let menu = NSMenu()
        
        // Settings
        let settingsItem = NSMenuItem(title: "PriType 설정...", action: #selector(openSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // About
        let aboutItem = NSMenuItem(title: "PriType 정보", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        return menu
    }
    
    @objc private func openSettings(_ sender: Any?) {
        DebugLogger.log("Opening settings")
        DispatchQueue.main.async {
            SettingsWindowController.shared.showSettings()
        }
    }
    
    @MainActor
    @objc private func showAbout(_ sender: Any?) {
        DebugLogger.log("Showing about")
        AboutInfo.showAlert()
    }
}
