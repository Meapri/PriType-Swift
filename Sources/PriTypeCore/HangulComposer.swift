import Cocoa
import LibHangul

public protocol HangulComposerDelegate: AnyObject {
    func insertText(_ text: String)
    func setMarkedText(_ text: String)
}

public class HangulComposer {
    
    // Initialize with direct HangulInputContext (synchronous)
    @available(*, deprecated, message: "Intentionally using synchronous context")
    private lazy var context: HangulInputContext = {
       let ctx = HangulInputContext(keyboard: PriTypeConfig.defaultKeyboardId)
       DebugLogger.log("Configured context with 2-set (id: '\(PriTypeConfig.defaultKeyboardId)')")
       return ctx
    }()
    
    public init() {
        DebugLogger.log("HangulComposer init")
    }
    
    public func handle(_ event: NSEvent, delegate: HangulComposerDelegate) -> Bool {
        // Only handle key down events
        if event.type != .keyDown {
            return false
        }
        
        // Handle modifiers (Command, Control, Option)
        // If these are pressed, we generally want to let the system handle shortcuts.
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) {
             return false
        }
        
        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }
        
        // Caps Lock 처리: Caps Lock이 켜져 있고 Shift를 안 눌렀으면 소문자로 변환
        // 이렇게 해야 한글 모드에서 Caps Lock이 쌍자음으로 잘못 인식되는 것을 방지
        let isCapsLockOn = event.modifierFlags.contains(.capsLock)
        let isShiftPressed = event.modifierFlags.contains(.shift)
        
        let inputCharacters: String
        if isCapsLockOn && !isShiftPressed {
            // Caps Lock만 켜진 경우: 소문자로 변환하여 일반 자음으로 처리
            inputCharacters = characters.lowercased()
        } else {
            // Shift 키가 눌렸거나 Caps Lock이 꺼진 경우: 원본 사용
            inputCharacters = characters
        }
        
        let keyCode = event.keyCode
        
        // 1. Check for Special Keys
        // Return / Enter
        if keyCode == KeyCode.return || keyCode == KeyCode.numpadEnter {
             DebugLogger.log("Return key -> commit")
             commitComposition(delegate: delegate)
             // Return true to consume if we want to handle newline ourselves,
             // or return false to let system insert newline. 
             // Usually, committing is enough, and we let system do newline.
             return false 
        }
        
        // Escape
        if keyCode == KeyCode.escape {
             DebugLogger.log("Escape -> cancel")
             cancelComposition(delegate: delegate)
             return true
        }
        
        // Space
        if keyCode == KeyCode.space {
            DebugLogger.log("Space -> flush and space")
            commitComposition(delegate: delegate)
            // Let system handle space insertion? Or strict consumption?
            // "Windows-style": Space commits, then inserts space.
            // If we return false, system inserts space. This is usually fine.
            return false
        }
        
        // 방향키 - 조합 커밋 후 시스템에 전달
        if keyCode == KeyCode.leftArrow || keyCode == KeyCode.rightArrow ||
           keyCode == KeyCode.upArrow || keyCode == KeyCode.downArrow {
            DebugLogger.log("Arrow key -> commit and pass to system")
            commitComposition(delegate: delegate)
            return false // 시스템이 커서 이동 처리
        }
        
        // Tab 키 - 조합 커밋 후 시스템에 전달
        if keyCode == KeyCode.tab {
            DebugLogger.log("Tab key -> commit")
            commitComposition(delegate: delegate)
            return false
        }
        
        // Backspace
        if keyCode == KeyCode.backspace {
            DebugLogger.log("Backspace")
            // If composing, try to backspace within engine
            if !context.isEmpty() {
                 if context.backspace() {
                     DebugLogger.log("Engine backspace success")
                     updateComposition(delegate: delegate)
                     return true
                 } else {
                     // Empty context after backspace? reset UI
                     DebugLogger.log("Engine backspace caused empty")
                     updateComposition(delegate: delegate)
                     return true
                 }
            }
            // If not composing, return false to let system delete previous char
            return false
        }
        
        // 2. Alphanumeric Keys (Typing)
        // We define "typing keys" as Printable ASCII usually.
        // For simplicity, let's process everything that has characters.
        
        DebugLogger.log("Handle key: \(inputCharacters) code: \(keyCode)")
        
        var handledAtLeastOnce = false
        
        for char in inputCharacters.unicodeScalars {
            let charCode = Int(char.value)
            
            // Check if standard typing range (approx)
            // ASCII 33-126 are printable. 
            // In Hangul mode, we map mapped keys.
            // If it's a typing key, we MUST consume it (return true).
            // Fallback: If libhangul fails, we insert it manually.
            
            DebugLogger.log("Processing char code: \(charCode)")
            
            // Primary attempt
            if context.process(charCode) {
                DebugLogger.log("Process success")
                handledAtLeastOnce = true
                updateComposition(delegate: delegate)
            } else {
                // Failure case (e.g. invalid key for engine, or boundary)
                DebugLogger.log("Process failed")
                
                // If we have composition, commit it first (boundary case)
                if !context.isEmpty() {
                    commitComposition(delegate: delegate)
                }
                
                // Retry with clean context
                if context.process(charCode) {
                     DebugLogger.log("Retry success")
                     handledAtLeastOnce = true
                     updateComposition(delegate: delegate)
                } else {
                     // Still failed. It's an unprocessable char (e.g. maybe symbol not in map).
                     // CONSUME IT ANYWAY and insert raw char to avoid "leakage" reordering.
                     DebugLogger.log("Retry failed, inserting raw char")
                     delegate.insertText(String(char))
                     handledAtLeastOnce = true
                }
            }
        }
        
        // If we processed anything, we return true to stop system from handling it duplicates.
        // We assume standard typing keys are processed.
        return handledAtLeastOnce
    }
    
    private func updateComposition(delegate: HangulComposerDelegate) {
        let preedit = context.getPreeditString()
        let commit = context.getCommitString()
        
        // If there is committed text, insert it first
        if !commit.isEmpty {
            let commitStr = String(commit.compactMap { UnicodeScalar($0) }.map { Character($0) })
            delegate.insertText(commitStr.precomposedStringWithCanonicalMapping)
        }
        
        // Update preedit text
        if !preedit.isEmpty {
            // Normalize: Map to Compatibility Jamo for better display (Windows-style)
            let scs = preedit.compactMap { UnicodeScalar($0) }
            let mapped = scs.map { scalar in
                 let val = scalar.value
                 // 1. Try standard helper (covers Choseong/Jungseong)
                 let stdMapped = HangulCharacter.jamoToCJamo(val)
                 if stdMapped != val { return UnicodeScalar(stdMapped) ?? scalar }
                 
                 // 2. Custom helper for Jongseong (U+11A8 ~ U+11C2)
                 if let compat = JamoMapper.mapJongseongToCompat(val) {
                     return UnicodeScalar(compat) ?? scalar
                 }
                 
                 return scalar
            }
            let preeditStr = String(mapped.map { Character($0) })
            delegate.setMarkedText(preeditStr)
        } else {
             delegate.setMarkedText("")
        }
    }
    
    private func commitComposition(delegate: HangulComposerDelegate) {
        // Flush context
        let flushed = context.flush()
        let commitStr = String(flushed.compactMap { UnicodeScalar($0) }.map { Character($0) })
        
        if !commitStr.isEmpty {
             delegate.insertText(commitStr.precomposedStringWithCanonicalMapping)
        }
        // Clear mark
        delegate.setMarkedText("")
    }

    private func cancelComposition(delegate: HangulComposerDelegate) {
        context.reset()
        delegate.setMarkedText("")
    }
    
    /// 입력기 전환 등의 상황에서 조합 중인 내용을 강제로 커밋
    public func forceCommit(delegate: HangulComposerDelegate) {
        commitComposition(delegate: delegate)
    }
    
    public func reset(delegate: HangulComposerDelegate) {
        context.reset()
        delegate.setMarkedText("")
        delegate.insertText("") 
    }
}
