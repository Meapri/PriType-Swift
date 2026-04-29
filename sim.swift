import Cocoa
import InputMethodKit

let composer = PriTypeInputController.sharedComposer

class MockDelegate: HangulComposerDelegate {
    func insertText(_ text: String) { print("INSERT: \(text)") }
    func setMarkedText(_ text: String) { print("MARKED: \(text)") }
    func textBeforeCursor(length: Int) -> String? { return nil }
    func replaceTextBeforeCursor(length: Int, with text: String) {}
}

let delegate = MockDelegate()

func sendKey(_ char: String, keyCode: UInt16) {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: char, charactersIgnoringModifiers: char, isARepeat: false, keyCode: keyCode)!
    let handled = composer.handle(event, delegate: delegate)
    print("Char: \(char), Handled: \(handled)")
}

sendKey("d", keyCode: 2)
sendKey("k", keyCode: 40)
sendKey("s", keyCode: 1)

