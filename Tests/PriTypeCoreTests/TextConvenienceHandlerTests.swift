import Foundation
import Testing
@testable import PriTypeCore

// MARK: - TextConvenienceHandler Tests

@Suite("TextConvenienceHandler")
struct TextConvenienceHandlerTests {
    
    // MARK: - Double Space Period Tests
    
    @Test("Double space converts to period")
    func doubleSpacePeriodConversion() {
        let handler = TextConvenienceHandler(isDoubleSpacePeriodEnabled: { true })
        let delegate = MockComposerDelegate()
        delegate.fullText = "Hello "
        var buffer = "Hello "
        
        _ = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)
        let result = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)
        
        #expect(result == .convertedToPeriod)
        #expect(delegate.fullText.hasSuffix(". "))
    }
    
    @Test("Normal space does not convert")
    func normalSpaceDoesNotConvert() {
        let handler = TextConvenienceHandler()
        let delegate = MockComposerDelegate()
        delegate.fullText = "Hello"
        var buffer = "Hello"
        
        let result = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)
        
        #expect(result == .normalSpace)
    }
    
    @Test("Reset space state prevents conversion")
    func resetSpaceState() {
        let handler = TextConvenienceHandler()
        let delegate = MockComposerDelegate()
        delegate.fullText = "Hello "
        var buffer = "Hello "
        _ = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)
        
        handler.resetSpaceState()
        
        let result = handler.handleDoubleSpacePeriod(buffer: &buffer, delegate: delegate, checkHangul: false)
        #expect(result == .normalSpace)
    }
    
    // MARK: - Hangul Detection Tests
    
    @Test("Hangul syllable detection")
    func isHangulSyllable() {
        let handler = TextConvenienceHandler()
        #expect(handler.isHangul("한"))
        #expect(handler.isHangul("글"))
        #expect(handler.isHangul("가"))
    }
    
    @Test("Hangul jamo detection")
    func isHangulJamo() {
        let handler = TextConvenienceHandler()
        #expect(handler.isHangul("ㄱ"))
        #expect(handler.isHangul("ㅏ"))
        #expect(handler.isHangul("ㅎ"))
    }
    
    @Test("Non-Hangul detection")
    func isNotHangul() {
        let handler = TextConvenienceHandler()
        #expect(!handler.isHangul("A"))
        #expect(!handler.isHangul("1"))
        #expect(!handler.isHangul("!"))
    }
    
    // English auto-capitalization: empty cursor context must pass through.
    // Sentence-end fallback is covered by HangulComposerTests.
}
