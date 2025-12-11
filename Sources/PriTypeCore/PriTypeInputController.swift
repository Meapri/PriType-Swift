import Cocoa
import InputMethodKit
import LibHangul

@objc(PriTypeInputController)
public class PriTypeInputController: IMKInputController {
    
    // MARK: - Shared State
    // These static properties are accessed only from the main thread via IMK callbacks.
    // nonisolated(unsafe) is required for Swift 6 strict concurrency, but is safe because:
    // 1. IMKInputController lifecycle is managed by InputMethodKit on main thread
    // 2. All access happens through IMK callbacks which are main-thread-only
    
    /// Shared composer for EventTapManager access
    nonisolated(unsafe) public static let sharedComposer = HangulComposer()
    private var composer: HangulComposer { Self.sharedComposer }
    
    /// Keep last active controller for toggle access
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
        
        // Efficient Secure Input Detection
        // If the client doesn't report a valid selection range (NSNotFound),
        // it likely means it's a password field or doesn't support IM text manipulation.
        // In this case, we pass the event through to let the system handle raw input.
        if client.selectedRange().location == NSNotFound {
            DebugLogger.log("Invalid selection range (Secure Input?), passing through")
            return false
        }      
        
        // MARK: - Finder-specific Detection
        let bundleId = client.bundleIdentifier() ?? ""
        
        if bundleId == "com.apple.finder" {
            // Improved Finder Detection:
            // Primary: validAttributesForMarkedText - empty means no text input capability
            // Secondary: Coordinate heuristic as fallback
            
            let validAttrs = client.validAttributesForMarkedText() ?? []
            let hasTextInputCapability = validAttrs.count > 0
            
            // Fallback: Coordinate-based heuristic (for edge cases)
            let firstRect = client.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
            let isLikelyDesktop = firstRect.origin.x < PriTypeConfig.finderDesktopThreshold && firstRect.origin.y < PriTypeConfig.finderDesktopThreshold
            
            // Use immediate mode if: no text input capability OR likely desktop area
            if !hasTextInputCapability || isLikelyDesktop {
                DebugLogger.log("Finder: ImmediateMode (validAttrs=\(validAttrs.count), firstRect=\(firstRect.origin))")
                lastClient = client
                lastAdapter = ImmediateModeAdapter(client: client)
                return composer.handle(event, delegate: lastAdapter!)
            }
            
            // Search Bar/Rename: Use ClientAdapter
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
