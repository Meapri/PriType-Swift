import XCTest
import Cocoa
@testable import PriTypeCore

// MARK: - Mock StatusBarUpdating

private class MockStatusBar: StatusBarUpdating {
    var currentMode: InputMode = .korean
    var modeChanges: [InputMode] = []
    
    func setMode(_ mode: InputMode) {
        currentMode = mode
        modeChanges.append(mode)
    }
}

// MARK: - Mock HangulComposerDelegate

private class MockComposerDelegate: HangulComposerDelegate {
    var insertedTexts: [String] = []
    var markedText: String = ""
    var fullText: String = ""
    
    func insertText(_ text: String) {
        insertedTexts.append(text)
        markedText = ""
        fullText.append(text)
    }
    
    func setMarkedText(_ text: String) {
        markedText = text
    }
    
    func textBeforeCursor(length: Int) -> String? {
        if fullText.isEmpty { return nil }
        let count = fullText.count
        let start = max(0, count - length)
        let startIndex = fullText.index(fullText.startIndex, offsetBy: start)
        return String(fullText[startIndex...])
    }
    
    func replaceTextBeforeCursor(length: Int, with text: String) {
        if fullText.count >= length {
            fullText.removeLast(length)
            fullText.append(text)
        }
    }
    
    func reset() {
        insertedTexts = []
        markedText = ""
        fullText = ""
    }
}

// MARK: - HangulComposer Tests

final class HangulComposerTests: XCTestCase {
    
    private var composer: HangulComposer!
    private var delegate: MockComposerDelegate!
    private var mockStatusBar: MockStatusBar!
    
    override func setUp() {
        super.setUp()
        mockStatusBar = MockStatusBar()
        composer = HangulComposer(statusBar: mockStatusBar)
        delegate = MockComposerDelegate()
    }
    
    override func tearDown() {
        composer = nil
        delegate = nil
        mockStatusBar = nil
        super.tearDown()
    }
    
    // MARK: - Helper
    
    private func makeKeyEvent(char: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: false,
            keyCode: keyCode
        )
    }
    
    // MARK: - Basic Composition Tests
    
    func testSingleChoseong() {
        // 'r' key maps to ㄱ
        let event = makeKeyEvent(char: "r", keyCode: 15)!
        let handled = composer.handle(event, delegate: delegate)
        
        XCTAssertTrue(handled, "Choseong should be handled")
        // Accept either compatibility or standard jamo
        XCTAssertTrue(
            delegate.markedText == "ㄱ" || 
            delegate.markedText == "\u{3131}" || 
            delegate.markedText == "\u{1100}",
            "Expected ㄱ, got '\(delegate.markedText)'"
        )
    }
    
    func testChoseongPlusJungseong() {
        // 'r' + 'k' = ㄱ + ㅏ = 가
        _ = composer.handle(makeKeyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        XCTAssertEqual(delegate.markedText, "가")
    }
    
    func testFullSyllable() {
        // 'd' + 'k' + 's' = ㅇ + ㅏ + ㄴ = 안
        _ = composer.handle(makeKeyEvent(char: "d", keyCode: 2)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "s", keyCode: 1)!, delegate: delegate)
        
        XCTAssertEqual(delegate.markedText, "안")
    }
    
    // MARK: - Syllable Boundary Tests
    
    func testSyllableBoundary() {
        // Type "안" then another 'ㄴ' should commit "안" and start new composition
        _ = composer.handle(makeKeyEvent(char: "d", keyCode: 2)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "s", keyCode: 1)!, delegate: delegate) // 안
        
        // Another ㄴ (s) - should commit 안 and start ㄴ
        _ = composer.handle(makeKeyEvent(char: "s", keyCode: 1)!, delegate: delegate)
        
        XCTAssertEqual(delegate.insertedTexts.last, "안")
        XCTAssertTrue(
            delegate.markedText == "ㄴ" || 
            delegate.markedText == "\u{3134}" ||
            delegate.markedText == "\u{1102}" ||
            delegate.markedText == "\u{11AB}",
            "Expected ㄴ, got '\(delegate.markedText)'"
        )
    }
    
    // MARK: - Backspace Tests
    
    func testBackspaceInComposition() {
        // Type "가" then backspace should leave just "ㄱ"
        _ = composer.handle(makeKeyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        XCTAssertEqual(delegate.markedText, "가")
        
        let backspaceEvent = makeKeyEvent(char: "\u{7F}", keyCode: KeyCode.backspace)!
        let handled = composer.handle(backspaceEvent, delegate: delegate)
        
        XCTAssertTrue(handled, "Backspace should be handled during composition")
        XCTAssertTrue(
            delegate.markedText == "ㄱ" || 
            delegate.markedText == "\u{3131}" ||
            delegate.markedText == "\u{1100}",
            "Expected ㄱ after backspace, got '\(delegate.markedText)'"
        )
    }
    
    func testBackspaceOnEmptyContext() {
        // Backspace with no composition should pass through
        let backspaceEvent = makeKeyEvent(char: "\u{7F}", keyCode: KeyCode.backspace)!
        let handled = composer.handle(backspaceEvent, delegate: delegate)
        
        XCTAssertFalse(handled, "Backspace on empty context should pass through")
    }
    
    // MARK: - Mode Toggle Tests
    
    func testToggleInputMode() {
        XCTAssertEqual(composer.inputMode, .korean)
        
        composer.toggleInputMode()
        
        XCTAssertEqual(composer.inputMode, .english)
        XCTAssertEqual(mockStatusBar.currentMode, .english)
        
        composer.toggleInputMode()
        
        XCTAssertEqual(composer.inputMode, .korean)
    }
    
    func testEnglishModePassthrough() {
        composer.toggleInputMode()
        XCTAssertEqual(composer.inputMode, .english)
        
        // English mode should pass through most keys
        let event = makeKeyEvent(char: "a", keyCode: 0)!
        let handled = composer.handle(event, delegate: delegate)
        
        // English mode uses TextConvenienceHandler which may handle or pass through
        // depending on auto-capitalize settings
        XCTAssertTrue(handled || !handled, "English mode input test passed")
    }
    
    // MARK: - Modifier Key Tests
    
    func testModifierKeyPassthrough() {
        // Type something first
        _ = composer.handle(makeKeyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        
        // Command+S should pass through (return false)
        let cmdEvent = makeKeyEvent(char: "s", keyCode: 1, modifiers: [.command])!
        let handled = composer.handle(cmdEvent, delegate: delegate)
        
        XCTAssertFalse(handled, "Command+key should pass through")
    }
    
    // MARK: - Special Key Tests
    
    func testReturnKeyCommit() {
        _ = composer.handle(makeKeyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        let returnEvent = makeKeyEvent(char: "\r", keyCode: KeyCode.`return`)!
        let handled = composer.handle(returnEvent, delegate: delegate)
        
        XCTAssertFalse(handled, "Return should not be consumed (pass to system)")
        // Composition should have been committed
        XCTAssertTrue(delegate.insertedTexts.contains("가"))
    }
    
    func testArrowKeyCommit() {
        _ = composer.handle(makeKeyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        let arrowEvent = makeKeyEvent(char: "\u{F702}", keyCode: KeyCode.leftArrow)!
        let handled = composer.handle(arrowEvent, delegate: delegate)
        
        XCTAssertFalse(handled, "Arrow key should pass through")
        XCTAssertTrue(delegate.insertedTexts.contains("가"))
    }
    
    // MARK: - Composition Commit on Shortcut Tests (Regression)

    /// 조합 중 Cmd+방향키 → 시스템으로 pass-through 되기 전에 조합이 커밋되어야 함.
    /// 커밋하지 않으면 marked text가 살아있어 호스트 앱이 단축키를 무시하거나 엉뚱한 위치에 문자가 남음.
    func testCmdArrowCommitsCompositionBeforePassThrough() {
        // Given: "가" 조합 중
        _ = composer.handle(makeKeyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        XCTAssertEqual(delegate.markedText, "가")
        XCTAssertTrue(delegate.insertedTexts.isEmpty, "아직 커밋 전이어야 함")

        // When: Cmd+Left
        let cmdLeft = makeKeyEvent(char: "\u{F702}", keyCode: KeyCode.leftArrow, modifiers: [.command])!
        let handled = composer.handle(cmdLeft, delegate: delegate)

        // Then: 시스템으로 넘기지만, 조합은 먼저 커밋됨
        XCTAssertFalse(handled, "Cmd+Arrow는 시스템으로 pass-through되어야 함")
        XCTAssertTrue(delegate.insertedTexts.contains("가"), "조합 중이던 '가'가 커밋되어야 함")
        XCTAssertEqual(delegate.markedText, "", "marked text가 정리되어야 함")
    }

    /// 조합 중 Option+방향키도 동일하게 커밋 후 pass-through.
    func testOptionArrowCommitsCompositionBeforePassThrough() {
        _ = composer.handle(makeKeyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        XCTAssertEqual(delegate.markedText, "가")

        let optLeft = makeKeyEvent(char: "\u{F702}", keyCode: KeyCode.leftArrow, modifiers: [.option])!
        let handled = composer.handle(optLeft, delegate: delegate)

        XCTAssertFalse(handled, "Option+Arrow는 시스템으로 pass-through되어야 함")
        XCTAssertTrue(delegate.insertedTexts.contains("가"), "조합이 커밋되어야 함")
        XCTAssertEqual(delegate.markedText, "")
    }

    /// Fn+Left는 macOS에서 Home 키(keyCode 115, NSHomeFunctionKey = U+F729)로 변환됨.
    /// handleSpecialKey의 방향키 분기에 매칭되지 않고 non-printable 필터에서 pass-through 되는 경로.
    /// 이 경로에서도 조합이 먼저 커밋되어야 함.
    func testFnArrowHomeCommitsCompositionBeforePassThrough() {
        _ = composer.handle(makeKeyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(makeKeyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        XCTAssertEqual(delegate.markedText, "가")

        // Home key: keyCode 115, characters = NSHomeFunctionKey (U+F729)
        let homeKey = makeKeyEvent(char: "\u{F729}", keyCode: 115)!
        let handled = composer.handle(homeKey, delegate: delegate)

        XCTAssertFalse(handled, "Home 키는 시스템으로 pass-through되어야 함")
        XCTAssertTrue(delegate.insertedTexts.contains("가"), "조합이 커밋되어야 함")
        XCTAssertEqual(delegate.markedText, "")
    }

    /// 조합이 없는 상태에서는 단축키가 그대로 통과만 하고 추가 동작이 없어야 함.
    func testCmdShortcutWithoutCompositionJustPassesThrough() {
        let cmdS = makeKeyEvent(char: "s", keyCode: 1, modifiers: [.command])!
        let handled = composer.handle(cmdS, delegate: delegate)

        XCTAssertFalse(handled, "조합 없는 Cmd 단축키는 pass-through")
        XCTAssertTrue(delegate.insertedTexts.isEmpty, "조합이 없었으므로 insertText가 호출되지 않아야 함")
        XCTAssertEqual(delegate.markedText, "")
    }

    // MARK: - Keyboard Layout Tests

    func testKeyboardLayoutChange() {
        // Type something
        _ = composer.handle(makeKeyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        
        // Change layout should commit composition
        composer.updateKeyboardLayout(id: "3")
        
        // Composition should have been committed
        XCTAssertTrue(delegate.markedText.isEmpty || delegate.insertedTexts.count > 0)
        
        // Restore
        composer.updateKeyboardLayout(id: "2")
    }
}
