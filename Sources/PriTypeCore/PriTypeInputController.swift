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
    // This is safe because ALL access is guaranteed to occur on the main thread:
    //
    // 1. `sharedComposer`: Created once at startup, accessed only via:
    //    - IMK callbacks (handle, commitComposition, etc.) - main thread only
    //    - RightCommandSuppressor.onToggle - dispatches to main thread
    //
    // 2. `sharedController`: Read/written only in:
    //    - activateServer() - IMK callback, main thread
    //    - deactivateServer() - IMK callback, main thread
    //
    // These invariants are enforced by InputMethodKit's design and our callback dispatch.
    // If you add new access patterns, ensure they maintain main-thread-only access.
    
    /// Shared composer instance for toggle key handler access
    /// - Warning: Access from main thread only. See THREAD SAFETY INVARIANTS above.
    nonisolated(unsafe) public static let sharedComposer = HangulComposer()
    private var composer: HangulComposer { Self.sharedComposer }
    
    /// Last active controller reference for external toggle access
    /// - Warning: Access from main thread only. See THREAD SAFETY INVARIANTS above.
    nonisolated(unsafe) public static weak var sharedController: PriTypeInputController?
    
    // Strong reference to prevent client being released during rapid switching
    private var lastClient: IMKTextInput?
    
    // Keep adapter alive for external toggle calls
    private var lastAdapter: (any HangulComposerDelegate)?
    
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
            client.setMarkedText(attributed, selectionRange: NSRange(location: text.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
    }
    
    /// Immediate mode adapter for non-text contexts (e.g., Finder desktop)
    /// Skips setMarkedText to prevent floating composition window
    private final class ImmediateModeAdapter: BaseClientAdapter {
        // Inherits no-op setMarkedText from base class
    }
    
    // 입력기가 활성화될 때 호출 - 새 세션 시작
    override public func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // 클라이언트 저장
        if let client = sender as? IMKTextInput {
            lastClient = client
            lastAdapter = ClientAdapter(client: client)
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
        // 반드시 조합 중인 내용을 커밋
        if let client = sender as? IMKTextInput ?? lastClient {
            let adapter = ClientAdapter(client: client)
            composer.forceCommit(delegate: adapter)
        }
        super.deactivateServer(sender)
        // 클라이언트 참조 해제
        lastClient = nil
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
        guard let event = event, let client = sender as? IMKTextInput else { return false }
        
        // Debug: Log all incoming events to diagnose Caps Lock issue
        DebugLogger.log("InputController.handle() event type: \(event.type.rawValue) keyCode: \(event.keyCode)")
        
        // Analyze client context using dedicated detector
        let context = ClientContextDetector.analyze(client: client)
        
        // Secure Input Detection (password fields)
        if context.shouldPassThrough {
            DebugLogger.log("Secure Input Mode active (password field), passing through")
            return false
        }
        
        // Finder-specific handling
        if context.shouldUseImmediateMode {
            DebugLogger.log("Finder: ImmediateMode (context=\(context))")
            lastClient = client
            lastAdapter = ImmediateModeAdapter(client: client)
            return composer.handle(event, delegate: lastAdapter!)
        }
        
        lastClient = client
        lastAdapter = ClientAdapter(client: client)
        
        return composer.handle(event, delegate: lastAdapter!)
    }
    
    // 마우스 클릭 등으로 조합 영역 외부 클릭 시 조합 커밋
    override public func commitComposition(_ sender: Any!) {
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
