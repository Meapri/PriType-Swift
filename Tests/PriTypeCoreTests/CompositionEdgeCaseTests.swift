import Testing
import Cocoa
@testable import PriTypeCore

// MARK: - Composition Edge Case Tests

@Suite("Composition Edge Cases")
struct CompositionEdgeCaseTests {
    
    // MARK: - Double Consonant (쌍자음) Tests
    
    @Test("Double consonant ㄲ (Shift+r → R)")
    func doubleConsonantGG() {
        let (composer, delegate, _) = makeComposer()
        // Shift+R = ㄲ
        _ = composer.handle(TestEventFactory.keyEvent(char: "R", keyCode: 15, modifiers: [.shift])!, delegate: delegate)
        
        #expect(!delegate.markedText.isEmpty, "ㄲ should produce marked text")
    }
    
    @Test("Double consonant ㄸ (Shift+e → E)")
    func doubleConsonantDD() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "E", keyCode: 14, modifiers: [.shift])!, delegate: delegate)
        
        #expect(!delegate.markedText.isEmpty, "ㄸ should produce marked text")
    }
    
    @Test("Double consonant ㅃ (Shift+q → Q)")
    func doubleConsonantBB() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "Q", keyCode: 12, modifiers: [.shift])!, delegate: delegate)
        
        #expect(!delegate.markedText.isEmpty, "ㅃ should produce marked text")
    }
    
    @Test("Double consonant ㅆ (Shift+t → T)")
    func doubleConsonantSS() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "T", keyCode: 17, modifiers: [.shift])!, delegate: delegate)
        
        #expect(!delegate.markedText.isEmpty, "ㅆ should produce marked text")
    }
    
    @Test("Double consonant ㅉ (Shift+w → W)")
    func doubleConsonantJJ() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "W", keyCode: 13, modifiers: [.shift])!, delegate: delegate)
        
        #expect(!delegate.markedText.isEmpty, "ㅉ should produce marked text")
    }
    
    // MARK: - Complex Jongseong (복합 받침) Tests
    
    @Test("Complex jongseong ㄳ (ㄱ+ㅅ)")
    func complexJongseongGS() {
        let (composer, delegate, _) = makeComposer()
        // 가 + ㄱ + ㅅ → 갃? No: 각 → need vowel first
        // ㅁ+ㅏ+ㄹ+ㄱ = 막 (ㄹㄱ = ㄺ)
        // Actually: 가 = r+k, then ㄹ = f, ㄱ = r → 갈ㄱ? 
        // Let's do: 달 = e+k+f → 달, then r → 닭? No.
        // More precisely: d+k+r+t = ㅇ+ㅏ+ㄱ+ㅅ = 앆 (if ㄱㅅ forms ㄳ)
        _ = composer.handle(TestEventFactory.keyEvent(char: "d", keyCode: 2)!, delegate: delegate)  // ㅇ
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate) // ㅏ → 아
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate) // ㄱ → 악
        _ = composer.handle(TestEventFactory.keyEvent(char: "t", keyCode: 17)!, delegate: delegate) // ㅅ → 앆 (ㄳ)
        
        #expect(!delegate.markedText.isEmpty, "Complex jongseong ㄳ should be composing")
    }
    
    @Test("Complex jongseong splits on next vowel")
    func complexJongseongSplitsOnVowel() {
        let (composer, delegate, _) = makeComposer()
        // Type: 닭 = ㄷ+ㅏ+ㄹ+ㄱ
        _ = composer.handle(TestEventFactory.keyEvent(char: "e", keyCode: 14)!, delegate: delegate)  // ㄷ
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)  // ㅏ → 다
        _ = composer.handle(TestEventFactory.keyEvent(char: "f", keyCode: 3)!, delegate: delegate)   // ㄹ → 달
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)  // ㄱ → 닭 (ㄺ)
        
        // Now type a vowel ㅏ → should split: 달 + 가
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)  // ㅏ → 달 committed, 가 composing
        
        #expect(delegate.insertedTexts.contains("달"), "달 should be committed when jongseong splits")
        #expect(delegate.markedText == "가", "New syllable 가 should be composing")
    }
    
    // MARK: - Consecutive Backspace Tests
    
    @Test("Consecutive backspaces decompose fully")
    func consecutiveBackspaces() {
        let (composer, delegate, _) = makeComposer()
        // Type 안 = ㅇ+ㅏ+ㄴ
        _ = composer.handle(TestEventFactory.keyEvent(char: "d", keyCode: 2)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "s", keyCode: 1)!, delegate: delegate)
        #expect(delegate.markedText == "안")
        
        // First backspace → 아
        _ = composer.handle(TestEventFactory.keyEvent(char: "\u{7F}", keyCode: KeyCode.backspace)!, delegate: delegate)
        #expect(delegate.markedText == "아", "Should be 아 after removing ㄴ")
        
        // Second backspace → ㅇ
        _ = composer.handle(TestEventFactory.keyEvent(char: "\u{7F}", keyCode: KeyCode.backspace)!, delegate: delegate)
        #expect(!delegate.markedText.isEmpty, "Should still have ㅇ composing")
        
        // Third backspace → empty
        _ = composer.handle(TestEventFactory.keyEvent(char: "\u{7F}", keyCode: KeyCode.backspace)!, delegate: delegate)
        #expect(delegate.markedText.isEmpty, "Composition should be fully cleared")
    }
    
    // MARK: - Sentence Typing Simulation
    
    @Test("Full sentence typing: 안녕하세요")
    func fullSentenceTyping() {
        let (composer, delegate, _) = makeComposer()
        
        // 안 = d+k+s
        _ = composer.handle(TestEventFactory.keyEvent(char: "d", keyCode: 2)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "s", keyCode: 1)!, delegate: delegate)
        
        // 녕 = s+u+d → ㄴ+ㅕ+ㅇ
        // Actually, 녕 splits: 안+ㄴ → ㄴ takes jongseong from 안 if next is vowel
        // s → 안's ㄴ is jongseong, next s = ㄴ → this would be 안ㄴ
        // Actually: 안 is composing. Then type 's' → ㄴ jongseong already exists.
        // Next ㄴ can't combine, so 안 commits, ㄴ starts.
        // Wait, 안 has jongseong ㄴ, next 's' = ㄴ → commits 안, starts ㄴ
        // Then u(ㅕ) → 녀, then d(ㅇ) → 녕
        
        _ = composer.handle(TestEventFactory.keyEvent(char: "s", keyCode: 1)!, delegate: delegate) // commits 안, starts ㄴ
        _ = composer.handle(TestEventFactory.keyEvent(char: "u", keyCode: 32)!, delegate: delegate) // 녀
        _ = composer.handle(TestEventFactory.keyEvent(char: "d", keyCode: 2)!, delegate: delegate)  // 녕
        
        #expect(delegate.insertedTexts.contains("안"), "안 should have been committed")
        #expect(delegate.markedText == "녕", "녕 should be composing")
    }
    
    @Test("Full word typing: 한글")
    func fullWordHangul() {
        let (composer, delegate, _) = makeComposer()
        
        // 한 = g+k+s (ㅎ+ㅏ+ㄴ)
        _ = composer.handle(TestEventFactory.keyEvent(char: "g", keyCode: 5)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "s", keyCode: 1)!, delegate: delegate)
        
        // 글 = r+m+f (ㄱ+ㅡ+ㄹ)
        // s(ㄴ) jongseong in 한, then r(ㄱ) → can't combine → 한 commits, ㄱ starts
        // Wait, actually typing r after 한: 한 has ㄴ jongseong, r=ㄱ doesn't combine with ㄴ
        // So 한 commits, ㄱ starts
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate) // commits 한, starts ㄱ
        _ = composer.handle(TestEventFactory.keyEvent(char: "m", keyCode: 46)!, delegate: delegate) // 그
        _ = composer.handle(TestEventFactory.keyEvent(char: "f", keyCode: 3)!, delegate: delegate)  // 글
        
        #expect(delegate.insertedTexts.contains("한"))
        #expect(delegate.markedText == "글")
    }
    
    // MARK: - Space Commits Composition
    
    @Test("Space commits composition and passes through")
    func spaceCommitsComposition() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        #expect(delegate.markedText == "가")
        
        let spaceEvent = TestEventFactory.keyEvent(char: " ", keyCode: KeyCode.space)!
        _ = composer.handle(spaceEvent, delegate: delegate)
        
        #expect(delegate.insertedTexts.contains("가"), "Space should commit composition")
    }
    
    // MARK: - Tab Commits Composition
    
    @Test("Tab commits composition and passes through")
    func tabCommitsComposition() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        
        let tabEvent = TestEventFactory.keyEvent(char: "\t", keyCode: KeyCode.tab)!
        let handled = composer.handle(tabEvent, delegate: delegate)
        
        #expect(!handled, "Tab should pass through")
        #expect(delegate.insertedTexts.contains("가"), "Tab should commit composition")
    }
    
    // MARK: - Escape Commits Composition
    
    @Test("Escape clears or commits composition")
    func escapeHandlesComposition() {
        let (composer, delegate, _) = makeComposer()
        _ = composer.handle(TestEventFactory.keyEvent(char: "r", keyCode: 15)!, delegate: delegate)
        _ = composer.handle(TestEventFactory.keyEvent(char: "k", keyCode: 40)!, delegate: delegate)
        #expect(delegate.markedText == "가")
        
        let escEvent = TestEventFactory.keyEvent(char: "\u{1B}", keyCode: KeyCode.escape)!
        _ = composer.handle(escEvent, delegate: delegate)
        
        // After ESC, composition should be cleared (either committed or cancelled)
        #expect(delegate.markedText.isEmpty, "Escape should clear marked text")
    }
    
    // MARK: - Helper
    
    private func makeComposer() -> (HangulComposer, MockComposerDelegate, MockStatusBar) {
        let statusBar = MockStatusBar()
        let composer = HangulComposer(statusBar: statusBar)
        let delegate = MockComposerDelegate()
        return (composer, delegate, statusBar)
    }
}
