import Testing
@testable import PriTypeCore

// MARK: - CompositionHelpers Tests

@Suite("CompositionHelpers")
struct CompositionHelpersTests {
    
    @Test("Convert empty array returns empty string")
    func convertEmptyArray() {
        #expect(CompositionHelpers.convertToString([]) == "")
    }
    
    @Test("Convert single Hangul syllable code point")
    func convertSingleCodePoint() {
        // "가" = U+AC00
        #expect(CompositionHelpers.convertToString([0xAC00]) == "가")
    }
    
    @Test("Convert multiple Hangul code points")
    func convertMultipleCodePoints() {
        // "한글" = U+D55C U+AE00
        #expect(CompositionHelpers.convertToString([0xD55C, 0xAE00]) == "한글")
    }
    
    @Test("Convert ASCII code points")
    func convertASCIICodePoints() {
        #expect(CompositionHelpers.convertToString([0x41, 0x42, 0x43]) == "ABC")
    }
    
    @Test("Invalid surrogate code points are filtered out")
    func convertInvalidCodePointsFiltered() {
        #expect(CompositionHelpers.convertToString([0xD800]) == "")
    }
    
    @Test("Normalize empty Jamo array")
    func normalizeEmptyArray() {
        #expect(CompositionHelpers.normalizeJamoForDisplay([]) == "")
    }
    
    @Test("Normalize full syllable preserves it")
    func normalizeSyllable() {
        let result = CompositionHelpers.normalizeJamoForDisplay([0xAC00])
        #expect(!result.isEmpty)
    }
    
    @Test("Normalize Choseong Jamo produces non-empty result")
    func normalizeChoseongJamo() {
        // Choseong ㄱ (U+1100)
        let result = CompositionHelpers.normalizeJamoForDisplay([0x1100])
        #expect(!result.isEmpty)
    }
}

// MARK: - InputMode Tests

@Suite("InputMode")
struct InputModeTests {
    
    @Test("Toggle switches between korean and english")
    func toggled() {
        #expect(InputMode.korean.toggled == .english)
        #expect(InputMode.english.toggled == .korean)
    }
    
    @Test("Double toggle returns to original")
    func doubleToggleReturnsOriginal() {
        #expect(InputMode.korean.toggled.toggled == .korean)
        #expect(InputMode.english.toggled.toggled == .english)
    }
}

// MARK: - PriTypeConfig Tests

@Suite("PriTypeConfig Constants")
struct PriTypeConfigTests {
    
    @Test("Default values are sensible")
    func defaultValues() {
        #expect(PriTypeConfig.defaultKeyboardId == "2")
        #expect(PriTypeConfig.finderDesktopThreshold == 50)
        #expect(PriTypeConfig.doubleSpaceThreshold > 0)
        #expect(PriTypeConfig.doubleSpaceThreshold < 1.0)
        #expect(PriTypeConfig.settingsWindowWidth > 0)
        #expect(PriTypeConfig.settingsWindowHeight > 0)
    }
}

// MARK: - PriTypeError Tests

@Suite("PriTypeError")
struct PriTypeErrorTests {
    
    @Test("All errors have descriptions")
    func errorDescriptions() {
        #expect(PriTypeError.eventTapCreationFailed.errorDescription != nil)
        #expect(PriTypeError.eventTapDisabled.errorDescription != nil)
        #expect(PriTypeError.accessibilityPermissionDenied.errorDescription != nil)
        #expect(PriTypeError.hidManagerOpenFailed(code: -1).errorDescription != nil)
    }
    
    @Test("All errors have recovery suggestions")
    func recoverySuggestions() {
        #expect(PriTypeError.eventTapCreationFailed.recoverySuggestion != nil)
        #expect(PriTypeError.eventTapDisabled.recoverySuggestion != nil)
        #expect(PriTypeError.accessibilityPermissionDenied.recoverySuggestion != nil)
        #expect(PriTypeError.hidManagerOpenFailed(code: 0).recoverySuggestion != nil)
    }
    
    @Test("HID manager error includes error code")
    func hidManagerErrorIncludesCode() {
        let error = PriTypeError.hidManagerOpenFailed(code: 42)
        #expect(error.errorDescription!.contains("42"))
    }
}
