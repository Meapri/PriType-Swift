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
        #expect(CompositionHelpers.convertToString([0xAC00]) == "가")
    }
    
    @Test("Convert multiple Hangul code points")
    func convertMultipleCodePoints() {
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

// MARK: - Jamo Conversion Tests

@Suite("Jamo Conversion")
struct JamoConversionTests {

    @Test("Choseong jamo detection covers U+1100...U+1112 only")
    func choseongDetection() {
        #expect(Character("\u{1100}").isChoseongJamo)   // ᄀ first choseong
        #expect(Character("\u{1112}").isChoseongJamo)   // ᄒ last choseong
        #expect(!Character("\u{10FF}").isChoseongJamo)  // just below range
        #expect(!Character("\u{1113}").isChoseongJamo)  // just above range
        #expect(!Character("\u{3131}").isChoseongJamo)  // ㄱ compatibility jamo, not choseong
        #expect(!Character("가").isChoseongJamo)         // precomposed syllable
        #expect(!Character("A").isChoseongJamo)
    }

    @Test("Choseong jamo maps to the matching compatibility jamo")
    func choseongToCompatibilityMapping() {
        // libhangul emits choseong jamo; jamo_symbols.json is keyed by compatibility jamo.
        #expect(Character("\u{1100}").choseongToCompatibility == "\u{3131}")  // ᄀ → ㄱ
        #expect(Character("\u{1102}").choseongToCompatibility == "\u{3134}")  // ᄂ → ㄴ
        #expect(Character("\u{1106}").choseongToCompatibility == "\u{3141}")  // ᄆ → ㅁ
        #expect(Character("\u{110B}").choseongToCompatibility == "\u{3147}")  // ᄋ → ㅇ
        #expect(Character("\u{1112}").choseongToCompatibility == "\u{314E}")  // ᄒ → ㅎ
    }

    @Test("Non-choseong characters are returned unchanged")
    func nonChoseongUnchanged() {
        #expect(Character("가").choseongToCompatibility == "가")
        #expect(Character("A").choseongToCompatibility == "A")
        #expect(Character("\u{3131}").choseongToCompatibility == "\u{3131}")  // already compatibility
    }

    @Test("Compatibility jamo consonant detection covers U+3131...U+314E")
    func jamoConsonantDetection() {
        #expect(Character("\u{3131}").isJamoConsonant)  // ㄱ
        #expect(Character("\u{314E}").isJamoConsonant)  // ㅎ
        #expect(!Character("\u{314F}").isJamoConsonant) // ㅏ (vowel, just above range)
        #expect(!Character("가").isJamoConsonant)
    }
}
