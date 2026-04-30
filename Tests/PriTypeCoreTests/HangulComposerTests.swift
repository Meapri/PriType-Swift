import Testing
import Cocoa
@testable import PriTypeCore

// MARK: - HangulComposer Tests

@Suite("HangulComposer")
struct HangulComposerTests {
    
    // MARK: - Basic Composition Tests
    
    @Test("Single choseong input")
    func singleChoseong() {
        let (composer, delegate, _) = makeComposer()
        let event = TestEventFactory.keyEvent(char: "r", keyCode: 15)!
        let handled = composer.handle(event, delegate: delegate)
        
        #expect(handled, "Choseong should be handled")
        #expect(
            delegate.markedText == "ㄱ" || 
            delegate.markedText == "\u{3131}" || 
            delegate.markedText == "\u{1100}",
            "Expected ㄱ, got '\(delegate.markedText)'"
        )
    }
    
    @Test("Choseong + Jungseong = syllable")
    func choseongPlusJungseong() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        #expect(delegate.markedText == "가")
    }
    
    @Test("Full syllable with jongseong")
    func fullSyllable() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "d", keyCode: 2)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "s", keyCode: 1)!, delegate: delegate)
        
        #expect(delegate.markedText == "안")
    }
    
    // MARK: - Syllable Boundary Tests
    
    @Test("Syllable boundary commits previous and starts new")
    func syllableBoundary() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "d", keyCode: 2)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "s", keyCode: 1)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "s", keyCode: 1)!, delegate: delegate)
        
        #expect(delegate.insertedTexts.last == "안")
        #expect(
            delegate.markedText == "ㄴ" || 
            delegate.markedText == "\u{3134}" ||
            delegate.markedText == "\u{1102}" ||
            delegate.markedText == "\u{11AB}",
            "Expected ㄴ, got '\(delegate.markedText)'"
        )
    }
    
    // MARK: - Backspace Tests
    
    @Test("Backspace during composition removes last jamo")
    func backspaceInComposition() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        #expect(delegate.markedText == "가")
        
        let backspace = TestEventFactory.keyEvent(char: "\u{7F}", keyCode: KeyCode.backspace)!
        let handled = composer.handle(backspace, delegate: delegate)
        
        #expect(handled, "Backspace should be handled during composition")
        #expect(
            delegate.markedText == "ㄱ" || 
            delegate.markedText == "\u{3131}" ||
            delegate.markedText == "\u{1100}",
            "Expected ㄱ after backspace, got '\(delegate.markedText)'"
        )
    }
    
    @Test("Backspace on empty context passes through")
    func backspaceOnEmptyContext() {
        let (composer, delegate, _) = makeComposer()
        let backspace = TestEventFactory.keyEvent(char: "\u{7F}", keyCode: KeyCode.backspace)!
        let handled = composer.handle(backspace, delegate: delegate)
        
        #expect(!handled, "Backspace on empty context should pass through")
    }
    
    // MARK: - Mode Toggle Tests
    
    @Test("Toggle input mode")
    func toggleInputMode() {
        let (composer, _, mockStatusBar) = makeComposer()
        #expect(composer.inputMode == .korean)
        
        composer.toggleInputMode()
        #expect(composer.inputMode == .english)
        #expect(mockStatusBar.currentMode == .english)
        
        composer.toggleInputMode()
        #expect(composer.inputMode == .korean)
    }
    
    @Test("English mode passes through keys")
    func englishModePassthrough() {
        let (composer, delegate, _) = makeComposer()
        composer.toggleInputMode()
        #expect(composer.inputMode == .english)
        
        let event = TestEventFactory.keyEvent(char: "a", keyCode: 0)!
        let _ = composer.handle(event, delegate: delegate)
        // English mode uses TextConvenienceHandler which may handle or pass through
    }
    
    // MARK: - Modifier Key Tests
    
    @Test("Command+key passes through")
    func modifierKeyPassthrough() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        
        let cmdEvent = TestEventFactory.keyEvent(char: "s", keyCode: 1, modifiers: [.command])!
        let handled = composer.handle(cmdEvent, delegate: delegate)
        
        #expect(!handled, "Command+key should pass through")
    }
    
    // MARK: - Special Key Tests
    
    @Test("Return key commits composition")
    func returnKeyCommit() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        let returnEvent = TestEventFactory.keyEvent(char: "\r", keyCode: KeyCode.`return`)!
        let handled = composer.handle(returnEvent, delegate: delegate)
        
        #expect(!handled, "Return should not be consumed")
        #expect(delegate.insertedTexts.contains("가"))
    }
    
    @Test("Arrow key commits composition")
    func arrowKeyCommit() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        let arrowEvent = TestEventFactory.keyEvent(char: "\u{F702}", keyCode: KeyCode.leftArrow)!
        let handled = composer.handle(arrowEvent, delegate: delegate)
        
        #expect(!handled, "Arrow key should pass through")
        #expect(delegate.insertedTexts.contains("가"))
    }
    
    // MARK: - Composition Commit on Shortcut Tests (Regression)
    
    @Test("Cmd+Arrow commits composition before pass-through")
    func cmdArrowCommitsComposition() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        #expect(delegate.markedText == "가")
        #expect(delegate.insertedTexts.isEmpty)
        
        let cmdLeft = TestEventFactory.keyEvent(char: "\u{F702}", keyCode: KeyCode.leftArrow, modifiers: [.command])!
        let handled = composer.handle(cmdLeft, delegate: delegate)
        
        #expect(!handled, "Cmd+Arrow passes through")
        #expect(delegate.insertedTexts.contains("가"), "Composition should be committed")
        #expect(delegate.markedText == "")
    }
    
    @Test("Option+Arrow commits composition before pass-through")
    func optionArrowCommitsComposition() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        let optLeft = TestEventFactory.keyEvent(char: "\u{F702}", keyCode: KeyCode.leftArrow, modifiers: [.option])!
        let handled = composer.handle(optLeft, delegate: delegate)
        
        #expect(!handled)
        #expect(delegate.insertedTexts.contains("가"))
        #expect(delegate.markedText == "")
    }
    
    @Test("Home key commits composition before pass-through")
    func homeKeyCommitsComposition() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        let homeKey = TestEventFactory.keyEvent(char: "\u{F729}", keyCode: 115)!
        let handled = composer.handle(homeKey, delegate: delegate)
        
        #expect(!handled)
        #expect(delegate.insertedTexts.contains("가"))
        #expect(delegate.markedText == "")
    }
    
    @Test("Cmd shortcut without composition just passes through")
    func cmdShortcutWithoutComposition() {
        let (composer, delegate, _) = makeComposer()
        let cmdS = TestEventFactory.keyEvent(char: "s", keyCode: 1, modifiers: [.command])!
        let handled = composer.handle(cmdS, delegate: delegate)
        
        #expect(!handled)
        #expect(delegate.insertedTexts.isEmpty)
        #expect(delegate.markedText == "")
    }
    
    // MARK: - Keyboard Layout Tests
    
    @Test("Keyboard layout change commits composition")
    func keyboardLayoutChange() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        
        composer.updateKeyboardLayout(id: "3")
        
        #expect(delegate.markedText.isEmpty || delegate.insertedTexts.count > 0)
        
        composer.updateKeyboardLayout(id: "2")
    }
    
    // MARK: - Helper
    
    private func makeComposer() -> (HangulComposer, MockComposerDelegate, MockStatusBar) {
        let statusBar = MockStatusBar()
        let composer = HangulComposer(statusBar: statusBar)
        let delegate = MockComposerDelegate()
        return (composer, delegate, statusBar)
    }
}
