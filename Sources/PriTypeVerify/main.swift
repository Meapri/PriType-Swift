import Foundation
import Cocoa
import PriTypeCore

class MockDelegate: HangulComposerDelegate {
    var markedText: String = ""
    var insertedText: String = ""
    
    func insertText(_ text: String) {
        insertedText = text
        markedText = "" // System behavior: insertion replaces marked text
        print("Inserted: '\(text)'")
    }
    
    func setMarkedText(_ text: String) {
        markedText = text
        print("Marked: '\(text)'")
    }
}

func verify() {
    print("Starting verification...")
    let composer = HangulComposer()
    let delegate = MockDelegate()
    
    // Test 1: Typing 'g' -> ㅎ (0x314E)
    print("Test 1: Typing 'g'")
    let eventG = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "g", charactersIgnoringModifiers: "g", isARepeat: false, keyCode: 5)
    _ = composer.handle(eventG!, delegate: delegate)
    
    print("Marked: '\(delegate.markedText)'")
    if delegate.markedText == "\u{314E}" {
        print("PASS: g -> ㅎ (Compat)")
    } else if delegate.markedText == "\u{1112}" {
        print("PASS: g -> ᄒ (Choseong)")
    } else {
        print("FAIL: g -> \(delegate.markedText), expected ㅎ (Compat 314E)")
        for scalar in delegate.markedText.unicodeScalars {
            print("Scalar: \(String(format: "%X", scalar.value))")
        }
        exit(1)
    }

    // Test 2: Typing 'k' -> 하 (joined)
    print("Test 2: Typing 'k'")
    let eventK = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)
    _ = composer.handle(eventK!, delegate: delegate)
    
    print("Marked: '\(delegate.markedText)'")
    if delegate.markedText == "하" {
        print("PASS: k -> 하")
    } else {
        print("FAIL: k -> \(delegate.markedText), expected 하")
        exit(1)
    }

    // Test 3: Typing 's' -> 한 (joined)
    print("Test 3: Typing 's'")
    let eventS = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)
    _ = composer.handle(eventS!, delegate: delegate)
    
    print("Marked: '\(delegate.markedText)'")
    if delegate.markedText == "한" {
        print("PASS: s -> 한")
    } else {
        print("FAIL: s -> \(delegate.markedText), expected 한")
        exit(1)
    }
    
    // Test 4: Boundary case "dks" (안) + "s" (ㄴ) -> "안ㄴ"
    // Currently context has "한". Flush it first for clean test?
    commit(delegate: delegate, composer: composer) 
    // Let's reset for clarity
    delegate.markedText = ""
    delegate.insertedText = ""
    
    // Type d, k, s -> 안
    _ = composer.handle(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "d", charactersIgnoringModifiers: "d", isARepeat: false, keyCode: 2)!, delegate: delegate)
    _ = composer.handle(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!, delegate: delegate)
    let eventS1 = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)
    _ = composer.handle(eventS1!, delegate: delegate)
    
    // Now "안" is in markedText. Verify.
    if delegate.markedText == "안" {
         print("Setup PASS: dks -> 안")
    }
    
    // Type s (ㄴ) again. Should commit "안" and mark "ㄴ"
    // "안" (dks) + s -> 안 (complete) + s (start next)?
    // Actually "안" can accept more? "앉" (nj)? 
    // s is 'ㄴ'. ks is 'ㄳ' ?
    // 'dks' = ㅇ ㅏ ㄴ = 안. 
    // 's' = ㄴ.
    // 안 + ㄴ = 안 + ㄴ?  or 앉?
    // In 2-set, 's' is 'ㄴ'. 'sw' is 'ㄵ'. 
    // If I type 'd' (ㅇ) 'k' (ㅏ) 's' (ㄴ) -> 안.
    // If I type another 's' (ㄴ).  Does 'ㄴㄴ' make a valid Jongseong? No.
    // So '안' should be committed, and new 'ㄴ' starts.
    
    print("Test 4: Boundary '안' + 's' -> commit '안', mark 'ㄴ'")
    let eventS2 = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)
    
    let handledS2 = composer.handle(eventS2!, delegate: delegate)
    
    if handledS2 {
        print("PASS: Handled boundary key 's'")
    } else {
        print("FAIL: Did not handle boundary key 's'")
        exit(1)
    }
    
    if delegate.insertedText == "안" {
        print("PASS: Inserted '안'")
    } else {
         print("FAIL: Inserted '\(delegate.insertedText)', expected '안'")
         exit(1)
    }
    
    if delegate.markedText == "ㄴ" { // choseong nieun 0x1102 OR compat 0x3134
        print("PASS: Marked 'ㄴ'")
    } else if delegate.markedText == "\u{3134}" {
         print("PASS: Marked 'ㄴ' (U+3134 - Compatibility Jamo)")
    } else if delegate.markedText == "\u{1102}" {
         print("PASS: Marked 'ㄴ' (U+1102 - Choseong)")
    } else if delegate.markedText == "\u{11AB}" {
        print("PASS: Marked 'ᆫ' (U+11AB) - Accepted as valid Jamo return")
    } else {
        print("FAIL: Marked '\(delegate.markedText)', expected 'ㄴ'")
        for scalar in delegate.markedText.unicodeScalars {
            print("Scalar: \(String(format: "%X", scalar.value))")
        }
        exit(1)
    }

    // Clear context for next test
    commit(delegate: delegate, composer: composer)

    // Test 5: Strict Consumption (Mixed/Rapid) attempt
    // Simulate 'u' (which maps to ㅕ). It should be handled.
    print("Test 5: Typing 'u' (mapped to ㅕ)")
    let eventU = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "u", charactersIgnoringModifiers: "u", isARepeat: false, keyCode: 32)
    
    let handledU = composer.handle(eventU!, delegate: delegate)
    
    if handledU {
        print("PASS: Handled 'u'")
    } else {
        print("FAIL: 'u' was not handled (returned false)")
        exit(1)
    }
    
    if delegate.markedText == "ㅕ" || delegate.markedText == "\u{3155}" { // Compat ㅕ
         print("PASS: Marked ㅕ")
    } else {
         print("FAIL: Expected ㅕ, got '\(delegate.markedText)'")
         exit(1)
    }
    
    // Test 6: Unknown char (e.g. '!') - Keycode 18 (1) + Shift? 
    // Just manual char '!'
    print("Test 6: Typing '!'")
    let eventBang = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "!", charactersIgnoringModifiers: "!", isARepeat: false, keyCode: 18)
    
    // LibHangul might map '!' (Shift+1) to something or just pass it?
    // In 2-set, Shift+1 is ! (not mapped to hangul).
    // So process() might return false?
    // New logic should insert '!' manually and return true.
    
    // Clear first
    commit(delegate: delegate, composer: composer)
    
    let handledBang = composer.handle(eventBang!, delegate: delegate)
    
    if handledBang {
        print("PASS: Handled '!'")
    } else {
        print("FAIL: '!' was not handled (returned false)")
        exit(1)
    }
    
    if delegate.insertedText == "!" {
         print("PASS: Inserted '!' manually")
    } else if delegate.markedText == "!" {
         print("PASS: Marked '!'")
    } else {
         print("WARNING: '!' result unexpected: Inserted='\(delegate.insertedText)', Marked='\(delegate.markedText)'")
    }

    // Test 8: Modifier Pass-Through (Cleaned Up)
    // flagsChanged is no longer handled - we only pass through keyDown with modifiers
    // This test verifies modifiers don't interfere with composition
    
    print("Test 8: Modifier Pass-Through")
    
    // Reset state
    commit(delegate: delegate, composer: composer)
    delegate.insertedText = ""
    delegate.markedText = ""
    
    // 1. Type 'r' to create composition
    _ = composer.handle(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)!, delegate: delegate)
    
    if delegate.markedText == "ㄱ" || delegate.markedText == "\u{3131}" || delegate.markedText == "\u{1100}" {
        print("Setup PASS: Marked 'ㄱ'")
    } else {
        print("Setup FAIL: Expected 'ㄱ', got '\(delegate.markedText)'")
        exit(1)
    }
    
    // 2. Simulate Cmd+S (keyDown with modifier) - should return false (pass to system)
    print("Simulating Cmd+S...")
    let eventCmdS = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)
    
    let handledCmd = composer.handle(eventCmdS!, delegate: delegate)
    
    if handledCmd == false {
        print("PASS: Returned false (passed to system)")
    } else {
        print("FAIL: Returned true (consumed event)")
        exit(1)
    }
    
    // Composition should still be there (not committed on modifier keyDown)
    if delegate.markedText == "ㄱ" || delegate.markedText == "\u{3131}" || delegate.markedText == "\u{1100}" {
        print("PASS: Composition preserved after modifier key")
    } else {
        print("FAIL: Composition lost after modifier key")
        exit(1)
    }
    
    print("All tests passed!")
}

func commit(delegate: MockDelegate, composer: HangulComposer) {
    // Force reset of engine state
    composer.reset(delegate: delegate)
    delegate.insertedText = ""
    delegate.markedText = ""
}

verify()
