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
    private var buffer: String!

    override func setUp() {
        super.setUp()
        handler = TextConvenienceHandler()
        delegate = MockTextDelegate()
        buffer = ""
    }

    override func tearDown() {
        handler = nil
        delegate = nil
        buffer = nil
        super.tearDown()
    }

    // MARK: - Double Space Period Tests

    func testDoubleSpacePeriodConversion() {
        // Setup: "Hello " already typed
        delegate.fullText = "Hello "
        buffer = "Hello "

        // First space (already in buffer)
        _ = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)

        // Immediately second space should convert to period
        let result = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)

        XCTAssertEqual(result, .convertedToPeriod)
        XCTAssertTrue(delegate.fullText.hasSuffix(". "))
    }

    func testNormalSpaceDoesNotConvert() {
        delegate.fullText = "Hello"
        buffer = "Hello"

        // First space
        let result = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)

        XCTAssertEqual(result, .normalSpace)
    }

    func testResetSpaceState() {
        delegate.fullText = "Hello "
        buffer = "Hello "
        _ = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)

        // Reset state (simulates typing a character)
        handler.resetSpaceState()

        // Next space should not convert
        let result = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)
        XCTAssertEqual(result, .normalSpace)
    }

    // MARK: - Auto Capitalize Tests

    func testShouldCapitalizeAtDocumentStart() {
        // Empty buffer
        XCTAssertTrue(handler.shouldAutoCapitalize(buffer: ""))
    }

    func testShouldCapitalizeAfterPeriod() {
        XCTAssertTrue(handler.shouldAutoCapitalize(buffer: "Hello. "))
    }

    func testShouldCapitalizeAfterExclamation() {
        XCTAssertTrue(handler.shouldAutoCapitalize(buffer: "Wow! "))
    }

    func testShouldCapitalizeAfterQuestion() {
        XCTAssertTrue(handler.shouldAutoCapitalize(buffer: "Really? "))
    }

    func testShouldCapitalizeAfterNewline() {
        XCTAssertTrue(handler.shouldAutoCapitalize(buffer: "Line one\n"))
    }

    func testShouldNotCapitalizeMidSentence() {
        XCTAssertFalse(handler.shouldAutoCapitalize(buffer: "Hello "))
    }

    func testShouldNotCapitalizeAfterComma() {
        XCTAssertFalse(handler.shouldAutoCapitalize(buffer: "Hello, "))
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
        buffer = "Hello"
        let result = handler.handleEnglishModeInput(char: " ", buffer: &buffer, delegate: delegate)
        XCTAssertEqual(result, .passThrough)
    }

    func testEnglishModeNonLetterPassthrough() {
        let result = handler.handleEnglishModeInput(char: "1", buffer: &buffer, delegate: delegate)
        XCTAssertEqual(result, .passThrough)
    }
}
