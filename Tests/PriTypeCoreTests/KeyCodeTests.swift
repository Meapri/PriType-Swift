import Testing
@testable import PriTypeCore

// MARK: - KeyCode Tests

@Suite("KeyCode Constants & Helpers")
struct KeyCodeTests {
    
    @Test("Printable ASCII range (32-126)")
    func printableASCIIRange() {
        #expect(KeyCode.isPrintableASCII(32))   // Space
        #expect(KeyCode.isPrintableASCII(126))  // Tilde
        #expect(KeyCode.isPrintableASCII(65))   // 'A'
        #expect(KeyCode.isPrintableASCII(97))   // 'a'
        #expect(KeyCode.isPrintableASCII(48))   // '0'
        #expect(KeyCode.isPrintableASCII(33))   // '!'
    }
    
    @Test("Non-printable ASCII")
    func nonPrintableASCII() {
        #expect(!KeyCode.isPrintableASCII(0))   // NUL
        #expect(!KeyCode.isPrintableASCII(1))   // SOH
        #expect(!KeyCode.isPrintableASCII(31))  // Unit separator
        #expect(!KeyCode.isPrintableASCII(127)) // DEL
    }
    
    @Test("Function key detection >= 63000")
    func functionKeyDetection() {
        #expect(KeyCode.isFunctionKey(63000))
        #expect(KeyCode.isFunctionKey(65535))
        #expect(!KeyCode.isFunctionKey(62999))
        #expect(!KeyCode.isFunctionKey(126))
    }
    
    @Test("Ignorable control chars exclude tab/newline/CR")
    func ignorableControlChars() {
        // Should be ignorable
        #expect(KeyCode.isIgnorableControlChar(0))  // NUL
        #expect(KeyCode.isIgnorableControlChar(1))  // SOH
        #expect(KeyCode.isIgnorableControlChar(8))  // BS
        
        // Tab, newline, CR should NOT be ignorable
        #expect(!KeyCode.isIgnorableControlChar(9))  // Tab
        #expect(!KeyCode.isIgnorableControlChar(10)) // LF
        #expect(!KeyCode.isIgnorableControlChar(13)) // CR
        
        // Printable should NOT be ignorable
        #expect(!KeyCode.isIgnorableControlChar(32))
    }
    
    @Test("shouldPassThrough combines function + control char checks")
    func shouldPassThrough() {
        #expect(KeyCode.shouldPassThrough(63000))  // Function key
        #expect(KeyCode.shouldPassThrough(0))      // NUL
        #expect(!KeyCode.shouldPassThrough(65))    // 'A'
        #expect(!KeyCode.shouldPassThrough(32))    // Space
        #expect(!KeyCode.shouldPassThrough(9))     // Tab
    }
    
    @Test("Key code constant values are correct")
    func keyCodeConstants() {
        #expect(KeyCode.space == 49)
        #expect(KeyCode.backspace == 51)
        #expect(KeyCode.escape == 53)
        #expect(KeyCode.`return` == 36)
        #expect(KeyCode.numpadEnter == 76)
        #expect(KeyCode.tab == 48)
        #expect(KeyCode.leftArrow == 123)
        #expect(KeyCode.rightArrow == 124)
        #expect(KeyCode.downArrow == 125)
        #expect(KeyCode.upArrow == 126)
        #expect(KeyCode.rightCommand == 54)
        #expect(KeyCode.spaceInt64 == 49)
    }
}
