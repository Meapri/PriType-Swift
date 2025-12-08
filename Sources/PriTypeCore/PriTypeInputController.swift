import Cocoa
import InputMethodKit
import LibHangul

@objc(PriTypeInputController)
public class PriTypeInputController: IMKInputController {
    
    // Shared composer for EventTapManager access
    nonisolated(unsafe) public static let sharedComposer = HangulComposer()
    private var composer: HangulComposer { Self.sharedComposer }
    
    // Keep last active controller for toggle access
    nonisolated(unsafe) public static weak var sharedController: PriTypeInputController?
    
    // Strong reference to prevent client being released during rapid switching
    private var lastClient: IMKTextInput?
    
    // Keep adapter alive for external toggle calls
    private var lastAdapter: ClientAdapter?
    
    // Adapter class to bridge IMKTextInput calls to HangulComposerDelegate
    private class ClientAdapter: HangulComposerDelegate {
        let client: IMKTextInput
        
        init(client: IMKTextInput) {
            self.client = client
        }
        
        func insertText(_ text: String) {
            guard !text.isEmpty else { return }
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
        
        func setMarkedText(_ text: String) {
            // Use NSAttributedString with underline style for native cursor appearance
            let attributes: [NSAttributedString.Key: Any] = [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor.textColor
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            client.setMarkedText(attributed, selectionRange: NSRange(location: text.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleLayoutChange), name: Notification.Name("PriTypeKeyboardLayoutChanged"), object: nil)
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
        NotificationCenter.default.removeObserver(self, name: Notification.Name("PriTypeKeyboardLayoutChanged"), object: nil)
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
        
        // Efficient Secure Input Detection
        // If the client doesn't report a valid selection range (NSNotFound),
        // it likely means it's a password field or doesn't support IM text manipulation.
        // In this case, we pass the event through to let the system handle raw input.
        if client.selectedRange().location == NSNotFound {
            DebugLogger.log("Invalid selection range (Secure Input?), passing through")
            return false
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
        let alert = NSAlert()
        alert.messageText = "PriType"
        alert.informativeText = "macOS용 한글 입력기\n\n버전: 1.0\n© 2025"
        alert.alertStyle = .informational
        alert.runModal()
    }
}
