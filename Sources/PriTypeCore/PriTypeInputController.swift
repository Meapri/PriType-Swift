import Cocoa
import InputMethodKit
import LibHangul
import Carbon.HIToolbox

@objc(PriTypeInputController)
public class PriTypeInputController: IMKInputController, @unchecked Sendable {
    private static let priTypeInputSourceID = "com.pritype.inputmethod.v2"
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
    private var applicationDeactivateObserver: Any?

    // Keep adapter alive for external toggle calls
    public private(set) var currentAdapter: (any HangulComposerDelegate)?
    
    // MARK: - Adapter Classes
    
    /// Base adapter class with common IMKTextInput operations
    /// Subclasses override setMarkedText for different behaviors
    class BaseClientAdapter: NSObject, HangulComposerDelegate {
        let client: IMKTextInput
        
        init(client: IMKTextInput) {
            self.client = client
        }

        static func insertionReplacementRange(markedRange: NSRange) -> NSRange {
            if markedRange.location != NSNotFound, markedRange.length > 0 {
                return markedRange
            }
            return NSRange(location: NSNotFound, length: NSNotFound)
        }

        static func markedTextClearingReplacementRange(markedRange: NSRange) -> NSRange? {
            guard markedRange.location != NSNotFound, markedRange.length > 0 else {
                return nil
            }
            return markedRange
        }
        
        func insertText(_ text: String) {
            guard !text.isEmpty else { return }
            let replacementRange = Self.insertionReplacementRange(markedRange: client.markedRange())
            if replacementRange.location != NSNotFound {
                DebugLogger.log("ClientAdapter.insertText replacing marked range loc=\(replacementRange.location) len=\(replacementRange.length)")
            }
            client.insertText(text, replacementRange: replacementRange)
        }
        
        func setMarkedText(_ text: String) {
            // Default: no-op, subclasses override
        }
        
        func textBeforeCursor(length: Int) -> String? {
            let selRange = client.selectedRange()
            guard selRange.location != NSNotFound, selRange.location < 10000000 else { return nil } // Protect against Chromium garbage values
            
            let location = max(0, selRange.location - length)
            let actualLength = selRange.location - location
            guard actualLength > 0 else { return nil }
            
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
    
    /// Standard adapter with underlined marked text for composition display
    private class ClientAdapter: BaseClientAdapter {
        override func setMarkedText(_ text: String) {
            guard !text.isEmpty else {
                if let replacementRange = Self.markedTextClearingReplacementRange(markedRange: client.markedRange()) {
                    client.insertText("", replacementRange: replacementRange)
                    DebugLogger.log("ClientAdapter.setMarkedText cleared marked range loc=\(replacementRange.location) len=\(replacementRange.length)")
                }
                return
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor.textColor
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            client.setMarkedText(attributed, selectionRange: NSRange(location: text.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
    }

    /// Immediate mode adapter for non-text contexts (e.g., Finder desktop)
    /// Skips setMarkedText to prevent floating composition window
    private final class ImmediateModeAdapter: BaseClientAdapter {
        // Inherits no-op setMarkedText from base class
    }

    // MARK: - State Management
    
    /// Cached client context to avoid expensive IPC calls on every keystroke
    /// - Note: Calculated in `activateServer`, used in `handle`, cleared in `deactivateServer`
    private(set) var cachedContext: ClientContext?

    private func makeAdapter(for client: IMKTextInput, context: ClientContext) -> any HangulComposerDelegate {
        if context.shouldUseImmediateMode {
            return ImmediateModeAdapter(client: client)
        }
        return ClientAdapter(client: client)
    }

    private func adapterMatchesContext(_ adapter: (any HangulComposerDelegate)?, context: ClientContext) -> Bool {
        if context.shouldUseImmediateMode {
            return adapter is ImmediateModeAdapter
        }
        return adapter is ClientAdapter
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

    private func updateApplicationDeactivateObserver(for context: ClientContext) {
        removeApplicationDeactivateObserver()

        // Host-agnostic safety net: commit any in-progress composition when the
        // focused app loses focus. Well-behaved hosts get this for free via the
        // IMK `deactivateServer` callback, but some apps never call it on focus
        // loss and leave marked text stranded (historically KakaoTalk). Rather
        // than hardcoding those bundle IDs, observe app deactivation for every
        // session. This is safe because `forceCommitForApplicationDeactivate`
        // is idempotent — it bails when there is no active composition, so for
        // hosts that already committed via `deactivateServer` it does nothing.
        guard !context.bundleId.isEmpty else {
            return
        }

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

            self.forceCommitForApplicationDeactivate(bundleId: context.bundleId)
        }

        DebugLogger.log("PriTypeInputController: observing app deactivation for \(context.bundleId)")
    }

    private func removeApplicationDeactivateObserver() {
        if let observer = applicationDeactivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            applicationDeactivateObserver = nil
        }
    }

    private func forceCommitForApplicationDeactivate(bundleId: String) {
        guard cachedContext?.bundleId == bundleId else {
            removeApplicationDeactivateObserver()
            return
        }
        guard composer.hasActiveComposition else {
            removeApplicationDeactivateObserver()
            return
        }
        guard let client = lastClient ?? lastKnownInputClient else {
            DebugLogger.log("PriTypeInputController: no client for app deactivate commit (\(bundleId))")
            removeApplicationDeactivateObserver()
            return
        }

        let adapter = currentAdapter ?? ClientAdapter(client: client)
        composer.forceCommit(delegate: adapter)
        composer.localTextBuffer = ""
        removeApplicationDeactivateObserver()
        DebugLogger.log("PriTypeInputController: force committed composition on app deactivate (\(bundleId))")
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
        // modern macOS, but the block-based NSWorkspace deactivate observer is not,
        // so clean both up explicitly to avoid a dangling registration.
        NotificationCenter.default.removeObserver(self, name: .keyboardLayoutChanged, object: nil)
        removeApplicationDeactivateObserver()
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
        // 반드시 조합 중인 내용을 커밋
        // Use the existing currentAdapter if available (not a stale temp adapter)
        if let adapter = currentAdapter {
            composer.forceCommit(delegate: adapter)
        } else if let client = sender as? IMKTextInput ?? lastClient {
            let adapter = ClientAdapter(client: client)
            composer.forceCommit(delegate: adapter)
        }
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

            let isPriTypeMode = inputModeID == Self.priTypeInputSourceID
            DebugLogger.log("PriTypeInputController: setValue inputMode='\(inputModeID)' priType=\(isPriTypeMode) current=\(composer.inputMode)")
            guard isPriTypeMode else {
                super.setValue(value, forTag: tag, client: sender)
                return
            }

            if let client = sender as? IMKTextInput {
                syncRomanKeyboardLayout(for: client, force: true)
            }

            if composer.inputMode != .korean {
                DebugLogger.log("PriTypeInputController: TIS selected PriType source -> korean")
                composer.setInputMode(.korean)
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
            DebugLogger.log("PriTypeInputController: handle keyCode=\(event.keyCode) mode=\(composer.inputMode) chars='\(event.characters ?? "")' modifiers=\(event.modifierFlags.rawValue) bundle=\(context.bundleId) lightweight=\(context.isLightweight) immediate=\(context.shouldUseImmediateMode) clientChanged=\(lastClient !== client)")
        }
        #endif
        
        // 2. Mark keystroke with current app's bundleId for cross-app hanja validation
        composer.markKeystroke(bundleId: context.bundleId)

        // 3. DYNAMIC CHECK: Secure Input (password fields)
        if shouldPassThroughSecureInput(client: client, context: context) {
            composer.discardCompositionForPassThrough()
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
            return composer.handle(event, delegate: currentAdapter!)
        }
        
        // Reuse adapter from activateServer if client hasn't changed
        // This avoids ~20 heap allocations/second during fast typing
        if lastClient !== client || currentAdapter == nil || !adapterMatchesContext(currentAdapter, context: context) {
            lastClient = client
            syncRomanKeyboardLayout(for: client)
            currentAdapter = makeAdapter(for: client, context: context)
        }
        
        return composer.handle(event, delegate: currentAdapter!)
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
