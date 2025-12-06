import Cocoa
import InputMethodKit
import LibHangul

@objc(PriTypeInputController)
public class PriTypeInputController: IMKInputController {
    
    private let composer = HangulComposer()
    private weak var lastClient: IMKTextInput?
    
    // Adapter class to bridge IMKTextInput calls to HangulComposerDelegate
    private class ClientAdapter: HangulComposerDelegate {
        let client: IMKTextInput
        
        init(client: IMKTextInput) {
            self.client = client
        }
        
        func insertText(_ text: String) {
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
    
    override public func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, let client = sender as? IMKTextInput else { return false }
        lastClient = client
        let adapter = ClientAdapter(client: client)
        return composer.handle(event, delegate: adapter)
    }
    
    // 입력기 전환 시 조합 중인 텍스트 커밋
    override public func deactivateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput ?? lastClient {
            let adapter = ClientAdapter(client: client)
            composer.forceCommit(delegate: adapter)
        }
        super.deactivateServer(sender)
    }
    
    // 마우스 클릭 등으로 조합 영역 외부 클릭 시 조합 커밋
    override public func commitComposition(_ sender: Any!) {
        if let client = sender as? IMKTextInput ?? lastClient {
            let adapter = ClientAdapter(client: client)
            composer.forceCommit(delegate: adapter)
        }
        super.commitComposition(sender)
    }
}
