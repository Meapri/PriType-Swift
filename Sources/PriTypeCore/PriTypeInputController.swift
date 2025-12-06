import Cocoa
import InputMethodKit
import LibHangul

@objc(PriTypeInputController)
public class PriTypeInputController: IMKInputController {
    
    private let composer = HangulComposer()
    // Strong reference to prevent client being released during rapid switching
    private var lastClient: IMKTextInput?
    
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
        // 반드시 조합 중인 내용을 커밋
        if let client = sender as? IMKTextInput ?? lastClient {
            let adapter = ClientAdapter(client: client)
            composer.forceCommit(delegate: adapter)
        }
        super.deactivateServer(sender)
        // 클라이언트 참조 해제
        lastClient = nil
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
