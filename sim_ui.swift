import Cocoa
import InputMethodKit
import PriTypeCore

let app = NSApplication.shared

class AppDelegate: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
        
        let view = MyView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(view)
        window.makeFirstResponder(view)
        
        print("Ready. Type something in the window. Close window to exit.")
        
        // Auto-type some keys for testing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            view.simulateKey("g", keyCode: 5) // ㅎ
            view.simulateKey("k", keyCode: 40) // ㅏ
            view.simulateKey("s", keyCode: 1) // ㄴ
            
            // Shift + G
            view.simulateKey("G", keyCode: 5, flags: .shift) // ㅉ? no wait, Shift + g is not a valid Jamo, let's try Shift + r
            view.simulateKey("R", keyCode: 15, flags: .shift) // ㄲ
            
            // Test with ONLY numericPad flag (which many standard keys have)
            view.simulateKey("d", keyCode: 2, flags: .numericPad) // ㅇ
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                app.terminate(nil)
            }
        }
    }
}

class MockDelegate: HangulComposerDelegate {
    func insertText(_ text: String) { print("INSERT: \(text)") }
    func setMarkedText(_ text: String) { print("MARKED: \(text)") }
    func textBeforeCursor(length: Int) -> String? { return nil }
    func replaceTextBeforeCursor(length: Int, with text: String) {}
}

class MyView: NSView {
    override var acceptsFirstResponder: Bool { true }
    
    let composer = HangulComposer()
    let del = MockDelegate()
    
    func simulateKey(_ char: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: char, charactersIgnoringModifiers: char, isARepeat: false, keyCode: keyCode)!
        print("\n--- Key Down: '\(char)', flags: \(flags.rawValue)")
        let handled = composer.handle(event, delegate: del)
        print("Handled: \(handled)")
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
