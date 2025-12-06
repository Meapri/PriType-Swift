import XCTest
import Cocoa
@testable import PriTypeCore

class MockComposerDelegate: HangulComposerDelegate {
    var insertedText: String?
    var markedText: String?
    
    func insertText(_ text: String) {
        insertedText = text
    }
    
    func setMarkedText(_ text: String) {
        markedText = text
    }
}

final class PriTypeTests: XCTestCase {
    func testHangulComposition() {
        let composer = HangulComposer()
        let delegate = MockComposerDelegate()
        
        // Simulate typing 'g' -> 'ㅎ'
        let eventG = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "g", charactersIgnoringModifiers: "g", isARepeat: false, keyCode: 5)
        
        let handledG = composer.handle(eventG!, delegate: delegate)
        XCTAssertTrue(handledG)
        XCTAssertEqual(delegate.markedText, "ㅎ")
        
        // Simulate typing 'k' -> 'ㅏ'
        let eventK = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)
        
        let handledK = composer.handle(eventK!, delegate: delegate)
        XCTAssertTrue(handledK)
        XCTAssertEqual(delegate.markedText, "하")
        
        // Simulate typing 's' -> 'ㄴ'
        let eventS = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)
        
        let handledS = composer.handle(eventS!, delegate: delegate)
        XCTAssertTrue(handledS)
        XCTAssertEqual(delegate.markedText, "한")
    }
}
