import XCTest
@testable import PriTypeCore

// MARK: - Mock Delegate

private class MockTextDelegate: HangulComposerDelegate {
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

// MARK: - Tests

final class TextConvenienceHandlerTests: XCTestCase {
    
    private var handler: TextConvenienceHandler!
    private var delegate: MockTextDelegate!
    
    override func setUp() {
        super.setUp()
        handler = TextConvenienceHandler()
        delegate = MockTextDelegate()
    }
    
    override func tearDown() {
        handler = nil
        delegate = nil
        super.tearDown()
    }
    
    // MARK: - Double Space Period Tests
    
    func testDoubleSpacePeriodConversion() {
        // Setup: "Hello " already typed
        delegate.fullText = "Hello "
        
        // First space (already in fullText)
        _ = handler.handleDoubleSpacePeriod(delegate: delegate, checkHangul: false)
        
        // Immediately second space should convert to period
        let result = handler.handleDoubleSpacePeriod(delegate: delegate, checkHangul: false)
        
        XCTAssertEqual(result, .convertedToPeriod)
        XCTAssertTrue(delegate.fullText.hasSuffix(". "))
    }
    
    func testNormalSpaceDoesNotConvert() {
        delegate.fullText = "Hello"
        
        // First space
        let result = handler.handleDoubleSpacePeriod(delegate: delegate, checkHangul: false)
        
        XCTAssertEqual(result, .normalSpace)
    }
    
    func testResetSpaceState() {
        delegate.fullText = "Hello "
        _ = handler.handleDoubleSpacePeriod(delegate: delegate, checkHangul: false)
        
        // Reset state (simulates typing a character)
        handler.resetSpaceState()
        
        // Next space should not convert
        let result = handler.handleDoubleSpacePeriod(delegate: delegate, checkHangul: false)
        XCTAssertEqual(result, .normalSpace)
    }
    
    // MARK: - Auto Capitalize Tests
    
    func testShouldCapitalizeAtDocumentStart() {
        // Empty document
        XCTAssertTrue(handler.shouldAutoCapitalize(delegate: delegate))
    }
    
    func testShouldCapitalizeAfterPeriod() {
        delegate.fullText = "Hello. "
        XCTAssertTrue(handler.shouldAutoCapitalize(delegate: delegate))
    }
    
    func testShouldCapitalizeAfterExclamation() {
        delegate.fullText = "Wow! "
        XCTAssertTrue(handler.shouldAutoCapitalize(delegate: delegate))
    }
    
    func testShouldCapitalizeAfterQuestion() {
        delegate.fullText = "Really? "
        XCTAssertTrue(handler.shouldAutoCapitalize(delegate: delegate))
    }
    
    func testShouldCapitalizeAfterNewline() {
        delegate.fullText = "Line one\n"
        XCTAssertTrue(handler.shouldAutoCapitalize(delegate: delegate))
    }
    
    func testShouldNotCapitalizeMidSentence() {
        delegate.fullText = "Hello "
        XCTAssertFalse(handler.shouldAutoCapitalize(delegate: delegate))
    }
    
    func testShouldNotCapitalizeAfterComma() {
        delegate.fullText = "Hello, "
        XCTAssertFalse(handler.shouldAutoCapitalize(delegate: delegate))
    }
    
    // MARK: - Hangul Detection Tests
    
    func testIsHangulSyllable() {
        XCTAssertTrue(handler.isHangul("한"))
        XCTAssertTrue(handler.isHangul("글"))
        XCTAssertTrue(handler.isHangul("가"))
    }
    
    func testIsHangulJamo() {
        XCTAssertTrue(handler.isHangul("ㄱ"))
        XCTAssertTrue(handler.isHangul("ㅏ"))
        XCTAssertTrue(handler.isHangul("ㅎ"))
    }
    
    func testIsNotHangul() {
        XCTAssertFalse(handler.isHangul("A"))
        XCTAssertFalse(handler.isHangul("1"))
        XCTAssertFalse(handler.isHangul("!"))
    }
    
    // MARK: - English Mode Input Tests
    
    func testEnglishModeSpacePassthrough() {
        delegate.fullText = "Hello"
        let result = handler.handleEnglishModeInput(char: " ", delegate: delegate)
        XCTAssertEqual(result, .passThrough)
    }
    
    func testEnglishModeNonLetterPassthrough() {
        let result = handler.handleEnglishModeInput(char: "1", delegate: delegate)
        XCTAssertEqual(result, .passThrough)
    }
}
