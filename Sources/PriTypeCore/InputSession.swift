import Cocoa
import InputMethodKit

// MARK: - CompositionFinalizeReason

/// Why a composition is being finalized. Diagnostics only — every reason takes the
/// SAME single code path (`InputSession.finalize`), which is the whole point: the
/// KakaoTalk stranded-preedit class of bugs came from different session-ending events
/// each having their own slightly different commit sequence.
enum CompositionFinalizeReason: String {
    case appDeactivate          // NSWorkspace deactivation (earliest, host still accepts insertText)
    case deactivateServer       // IMK deactivateServer (fallback; native hosts may already ignore)
    case mouseCommit            // IMK commitComposition (click outside the composition)
    case modeTransition         // PriType custom toggle key (한/영)
    case systemModeSwitch       // macOS selected the other PriType mode (Caps Lock / menu)
    case keyboardLayoutChange   // 두벌식/세벌식 layout switch mid-composition
}

// MARK: - InputSession

/// One live text-input session: a client, its analyzed context, the delivery adapter,
/// duplicate-keyDown state, and the focus-loss safety net — owned together so they can
/// never drift apart.
///
/// Lifecycle: created in `activateServer` (or on a client change observed in
/// `handle()`), kept across `deactivateServer` (async Hanja callbacks and early
/// `handle()` need the adapter/context), replaced when a different client appears.
///
/// INVARIANT: `finalize(reason:)` is the ONLY way an in-progress composition ends
/// against this session's client. It is idempotent (no-op without active composition)
/// and host-agnostic — no bundle-ID special cases.
final class InputSession: @unchecked Sendable {
    let client: IMKTextInput
    private(set) var context: ClientContext
    private(set) var adapter: BaseClientAdapter
    private let composer: HangulComposer

    /// Set in `deactivateServer`. The next `handle()` must re-analyze the context
    /// before trusting it: the same client object can come back focused on a
    /// different field (e.g. a password field) of the same app.
    private(set) var contextNeedsRefresh = false

    /// Commits the composition early on app-focus-loss (see `armFocusLossFinalizer`).
    private var focusLossObserver: Any?

    // Duplicate-keyDown suppression (some hosts, e.g. KakaoTalk, deliver the same
    // physical keyDown twice — double-processing input, notably one backspace
    // decomposing TWO jamo). Applies to every delivery mode; the duplicate is a
    // property of the host's event delivery, not of how we render composition.
    private var lastKeyDown: KeyDownSnapshot?
    private(set) var lastHandleResult = false

    init(client: IMKTextInput, context: ClientContext, composer: HangulComposer) {
        self.client = client
        self.context = context
        self.composer = composer
        self.adapter = TextDeliveryPolicy.makeAdapter(for: client, context: context)
    }

    deinit {
        disarmFocusLossFinalizer()
    }

    func matches(_ candidate: IMKTextInput) -> Bool {
        client === candidate
    }

    // MARK: Context lifecycle

    /// Replace the analyzed context (same client). Rebuilds the adapter when the
    /// resolved delivery mode changed, and re-arms the focus-loss finalizer when the
    /// owning app changed.
    func refreshContext(_ newContext: ClientContext) {
        let oldBundleId = context.bundleId
        context = newContext
        contextNeedsRefresh = false
        ensureAdapterMatchesPolicy()
        if focusLossObserver != nil, newContext.bundleId != oldBundleId {
            armFocusLossFinalizer()
        }
    }

    func markContextStale() {
        contextNeedsRefresh = true
    }

    /// Rebuild the adapter if the delivery policy no longer matches it (e.g. the
    /// experimental direct-insertion flag flipped mid-session). Cheap — two enum
    /// compares on the hot path.
    func ensureAdapterMatchesPolicy() {
        let resolved = TextDeliveryPolicy.mode(for: context)
        guard adapter.deliveryMode != resolved else { return }
        adapter = TextDeliveryPolicy.makeAdapter(for: client, context: context)
    }

    // MARK: Duplicate keyDown suppression

    /// Record the keyDown and report whether it is a machine re-delivery of the
    /// previous one (same physical event delivered twice). The caller should replay
    /// `lastHandleResult` for duplicates instead of processing the event again.
    func registerKeyDown(_ snapshot: KeyDownSnapshot) -> Bool {
        let duplicate = KeyEventDedup.isDuplicate(snapshot, previous: lastKeyDown)
        lastKeyDown = snapshot
        return duplicate
    }

    func recordHandleResult(_ result: Bool) {
        lastHandleResult = result
    }

    // MARK: Focus-loss safety net

    /// Observe the focused app's deactivation and finalize the composition THEN — early
    /// enough that the host (e.g. KakaoTalk) still accepts the insertText. By the time
    /// IMK's deactivateServer runs, native hosts have already resigned and drop it,
    /// leaving a stranded/underlined preedit. Host-agnostic; the bundle ID compared is
    /// the session's own, never a hardcoded list.
    func armFocusLossFinalizer() {
        disarmFocusLossFinalizer()
        let bundleId = context.bundleId
        guard !bundleId.isEmpty else { return }
        focusLossObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == bundleId else {
                return
            }
            self.finalize(reason: .appDeactivate)
        }
    }

    /// Stop watching for focus loss. MUST be called when this session stops being the
    /// active one (deactivateServer): the composer is shared, so a stale observer
    /// firing later would flush a NEWER session's composition into THIS client.
    func disarmFocusLossFinalizer() {
        if let observer = focusLossObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            focusLossObserver = nil
        }
    }

    // MARK: Finalize (the single composition-ending path)

    /// Finalize the in-progress composition into this session's client in a SINGLE
    /// operation: insert the committed string with `replacementRange = NSNotFound`, so
    /// the host converts its OWN marked text to committed text (composition-end).
    ///
    /// One op — not commit + separate clear — is load-bearing: an explicit marked-range
    /// edit makes hosts re-run text detection (KakaoTalk re-fires its emoticon popup, a
    /// visible flicker) and a separate `setMarkedText("")` after the host resigned
    /// strands the preedit. Idempotent — no-op when there is no active composition, so
    /// every session-ending event can call it unconditionally.
    @discardableResult
    func finalize(reason: CompositionFinalizeReason) -> Bool {
        guard composer.hasActiveComposition else {
            // Nothing to commit, but the session-ending event (e.g. a mouse click)
            // likely moved the caret — stale direct-insertion tracking must never
            // survive it, or the next keystroke could rewrite unrelated text.
            (adapter as? DirectInsertionAdapter)?.resetPreeditTracking()
            return false
        }

        // EXPERIMENTAL direct insertion: the in-progress syllable is ALREADY real text
        // in the document. Re-inserting it here would duplicate the character. Just end
        // the engine's composition and clear the adapter's live-preedit tracking.
        if let direct = adapter as? DirectInsertionAdapter {
            _ = composer.flushCommitString()   // flush engine + update buffer; do NOT insert
            direct.resetPreeditTracking()
            DebugLogger.log("InputSession: finalize[\(reason.rawValue)] direct-insertion (already in document, no re-insert)")
            return true
        }

        Self.finalizeMarkedComposition(composer: composer, client: client, reason: reason)
        return true
    }

    /// The marked-text finalize, callable against any client. `PriTypeInputController`
    /// uses this directly when IMK hands it a sender that is not this session's client.
    static func finalizeMarkedComposition(
        composer: HangulComposer,
        client: IMKTextInput,
        reason: CompositionFinalizeReason
    ) {
        let markedRange = client.markedRange()
        let committed = composer.flushCommitString()
        DebugLogger.log("InputSession: finalize[\(reason.rawValue)] client=\(client.bundleIdentifier() ?? "?") marked=(\(markedRange.location),\(markedRange.length)) len=\(committed.count)")
        if !committed.isEmpty {
            // Canonical finalize: NSNotFound asks the host to convert its OWN marked
            // text to committed (composition-end), rather than an explicit marked-range
            // edit. (Done at app-deactivate-observer timing, the host still accepts it.)
            client.insertText(committed, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        } else if markedRange.location != NSNotFound, markedRange.length > 0 {
            client.insertText("", replacementRange: markedRange)
        }
    }

    /// Secure text fields must receive raw key events. Drop the engine's composition
    /// WITHOUT touching the client (no insertText/setMarkedText — those can trigger
    /// host warning beeps in password fields), and clear direct-insertion tracking so
    /// a stale live-preedit length can never delete real text on the next keystroke.
    func discardForSecureInput() {
        composer.discardCompositionForPassThrough()
        (adapter as? DirectInsertionAdapter)?.resetPreeditTracking()
    }
}
