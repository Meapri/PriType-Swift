import Cocoa
import InputMethodKit
import LibHangul
import Carbon.HIToolbox

@objc(PriTypeInputController)
public class PriTypeInputController: IMKInputController {
    
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
    nonisolated(unsafe) public static let sharedComposer = HangulComposer()
    private var composer: HangulComposer { Self.sharedComposer }
    
    /// Last active controller reference for external toggle access
    /// - Warning: Access from main thread only (guaranteed by IMK, not compiler-enforced)
    nonisolated(unsafe) public static weak var sharedController: PriTypeInputController?
    
    // Strong reference to prevent client being released during rapid switching
    private var lastClient: IMKTextInput?
    
    // Keep adapter alive for external toggle calls
    public private(set) var currentAdapter: (any HangulComposerDelegate)?
    
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
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
        
        func setMarkedText(_ text: String) {
            // Default: no-op, subclasses override
        }
        
        func textBeforeCursor(length: Int) -> String? {
            let selRange = client.selectedRange()
            guard selRange.location != NSNotFound else { return nil }
            
            let location = max(0, selRange.location - length)
            let actualLength = selRange.location - location
            guard actualLength > 0 else { return nil }
            
            let charRange = NSRange(location: location, length: actualLength)
            return client.attributedSubstring(from: charRange)?.string
        }
        
        func replaceTextBeforeCursor(length: Int, with text: String) {
            let selRange = client.selectedRange()
            guard selRange.location != NSNotFound && selRange.location >= length else { return }
            
            let replacementRange = NSRange(location: selRange.location - length, length: length)
            client.insertText(text, replacementRange: replacementRange)
        }
    }
    
    /// Standard adapter with underlined marked text for composition display
    private final class ClientAdapter: BaseClientAdapter {
        override func setMarkedText(_ text: String) {
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
    private var cachedContext: ClientContext?
    
    // 입력기가 활성화될 때 호출 - 새 세션 시작
    override public func activateServer(_ sender: Any!) {
        #if DEBUG
        assert(Thread.isMainThread, "IMK activateServer must run on main thread")
        #endif
        super.activateServer(sender)
        // 클라이언트 저장
        if let client = sender as? IMKTextInput {
            lastClient = client
            currentAdapter = ClientAdapter(client: client)
            
            // PERFORMANCE: Analyze context ONCE per session and cache it.
            // This avoids heavy IPC calls (bundleId check, coordinate calculation) on every keystroke.
            self.cachedContext = ClientContextDetector.analyze(client: client)
            DebugLogger.log("Activated for client: \(self.cachedContext?.bundleId ?? "unknown") (Cached Context)")
        } else {
            // Fallback if sender is not IMKTextInput (rare)
            self.cachedContext = nil
        }
        
        // Set as active controller for toggle access
        Self.sharedController = self
        
        // Ensure composer has correct layout (in case it changed while inactive)
        let currentLayoutId = ConfigurationManager.shared.keyboardId
        composer.updateKeyboardLayout(id: currentLayoutId)
        
        // Observe layout changes
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
        // Reset keystroke timestamp to prevent cross-app hanja leaking.
        // The buffer data is preserved (so hanja works when returning to this app),
        // but the timestamp is invalidated so a different app can't use the stale buffer.
        // When the user returns and types again, markKeystroke() refreshes the timestamp.
        composer.resetKeystrokeTime()
        super.deactivateServer(sender)
        // Do NOT clear currentAdapter here.
        // CGEventTap triggerHanjaLookup() is dispatched async and needs a valid adapter.
        // The next activateServer() will replace it with the new client's adapter.
        lastClient = nil
        // Keep cachedContext alive — activateServer() will replace it with the new client's context.
        // Clearing it here causes unnecessary slow path if handle() arrives before activateServer().
        NotificationCenter.default.removeObserver(self, name: .keyboardLayoutChanged, object: nil)
    }
    
    @objc private func handleLayoutChange() {
        let newId = ConfigurationManager.shared.keyboardId
        DebugLogger.log("PriTypeInputController: Layout changed to \(newId), updating composer")
        composer.updateKeyboardLayout(id: newId)
    }
    
    // Tell IMK which events we want to receive in handle()
    // By default, only keyDown events are delivered. We need flagsChanged for Caps Lock detection.
    override public func recognizedEvents(_ sender: Any!) -> Int {
        let keyDown = NSEvent.EventTypeMask.keyDown.rawValue
        let flagsChanged = NSEvent.EventTypeMask.flagsChanged.rawValue
        return Int(keyDown | flagsChanged)
    }
    
    override public func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        #if DEBUG
        assert(Thread.isMainThread, "IMK handle must run on main thread")
        #endif
        guard let event = event, let client = sender as? IMKTextInput else { return false }
        
        // Mark keystroke time for hanja buffer freshness check
        composer.markKeystroke()
        
        // Debug: Log all incoming events to diagnose Caps Lock issue
        DebugLogger.log("InputController.handle() event type: \(event.type.rawValue) keyCode: \(event.keyCode)")
        
        // DYNAMIC CHECK: Secure Input (password fields)
        // IsSecureEventInputEnabled() is a GLOBAL flag - other apps (KakaoTalk, browsers)
        // may enable it for password fields and forget to disable it, affecting ALL apps.
        // Two-tier validation:
        // 1. System security clients (SecurityAgent, loginwindow) → always pass through
        // 2. Other apps with global flag on → check if current field supports marked text
        //    (password fields typically don't support marked text attributes)
        if IsSecureEventInputEnabled() {
            let bundleId = cachedContext?.bundleId ?? ""
            let isSystemSecureClient = bundleId == "com.apple.SecurityAgent" ||
                                       bundleId == "com.apple.loginwindow" ||
                                       bundleId == "com.apple.screencaptureui"
            if isSystemSecureClient {
                DebugLogger.log("Secure Input: System secure client (\(bundleId)), passing through")
                return false
            }
            
            // Secondary check: if the field doesn't support marked text, treat as secure
            let validAttrs = client.validAttributesForMarkedText() ?? []
            if validAttrs.isEmpty {
                DebugLogger.log("Secure Input: Global flag + no markedText support in '\(bundleId)' → likely password field, passing through")
                return false
            }
            
            DebugLogger.log("Secure Input: Global flag set but '\(bundleId)' supports markedText — ignoring stale flag")
        }
        
        // PERFORMANCE: Use cached context if available and still valid, otherwise analyze.
        // Context is invalidated when the client object changes (app switch without activateServer).
        var context: ClientContext
        if let cached = self.cachedContext, lastClient === client || lastClient == nil {
            context = cached
        } else {
            // Client changed or no cache — re-analyze
            DebugLogger.log("cachedContext miss: client changed or nil, analyzing (Slow Path)")
            context = ClientContextDetector.analyze(client: client)
            self.cachedContext = context
        }
        
        // Finder-specific handling
        if context.shouldUseImmediateMode {
            DebugLogger.log("Finder: ImmediateMode (context=\(context))")
            // Only recreate adapter if client changed or type mismatch
            if lastClient !== client || !(currentAdapter is ImmediateModeAdapter) {
                lastClient = client
                currentAdapter = ImmediateModeAdapter(client: client)
            }
            return composer.handle(event, delegate: currentAdapter!)
        }
        
        // Reuse adapter from activateServer if client hasn't changed
        // This avoids ~20 heap allocations/second during fast typing
        if lastClient !== client || currentAdapter == nil {
            lastClient = client
            currentAdapter = ClientAdapter(client: client)
        }
        
        return composer.handle(event, delegate: currentAdapter!)
    }
    
    // 마우스 클릭 등으로 조합 영역 외부 클릭 시 조합 커밋
    override public func commitComposition(_ sender: Any!) {
        #if DEBUG
        assert(Thread.isMainThread, "IMK commitComposition must run on main thread")
        #endif
        if let client = sender as? IMKTextInput ?? lastClient {
            let adapter = ClientAdapter(client: client)
            composer.forceCommit(delegate: adapter)
        }
        super.commitComposition(sender)
    }
    
    // MARK: - Input Method Menu
    
    /// Returns custom menu for the input method (shown in system input source menu)
    override public func menu() -> NSMenu! {
        let menu = NSMenu()
        
        // Settings
        let settingsItem = NSMenuItem(title: "PriType 설정...", action: #selector(openSettings(_:)), keyEquivalent: ",")
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
