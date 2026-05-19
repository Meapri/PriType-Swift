import Foundation
import Testing
@testable import PriTypeCore

// MARK: - TextConvenienceHandler Tests

@Suite("TextConvenienceHandler")
struct TextConvenienceHandlerTests {
    
    // MARK: - Double Space Period Tests
    
    @Test("Double space converts to period")
    func doubleSpacePeriodConversion() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "NSAutomaticPeriodSubstitutionEnabled")
        defaults.set(true, forKey: "NSAutomaticPeriodSubstitutionEnabled")
        defer {
            if let original {
                defaults.set(original, forKey: "NSAutomaticPeriodSubstitutionEnabled")
            } else {
                defaults.removeObject(forKey: "NSAutomaticPeriodSubstitutionEnabled")
            }
        }

        let handler = TextConvenienceHandler()
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
    
    // MARK: - English Mode Input Tests
    
    @Test("English mode space passes through")
    func englishModeSpacePassthrough() {
        let handler = TextConvenienceHandler()
        let delegate = MockComposerDelegate()
        delegate.fullText = "Hello"
        var buffer = "Hello"
        let result = handler.handleEnglishModeInput(char: " ", buffer: &buffer, delegate: delegate)
        #expect(result == .passThrough)
    }
    
    @Test("English mode non-letter passes through")
    func englishModeNonLetterPassthrough() {
        let handler = TextConvenienceHandler()
        let delegate = MockComposerDelegate()
        var buffer = ""
        let result = handler.handleEnglishModeInput(char: "1", buffer: &buffer, delegate: delegate)
        #expect(result == .passThrough)
    }
}
