import Cocoa
import LibHangul

public protocol HangulComposerDelegate: AnyObject {
    func insertText(_ text: String)
    func setMarkedText(_ text: String)
}

/// Input mode for the composer
public enum InputMode: Sendable {
    case korean
    case english
}

public class HangulComposer {
    
    // Current input mode (Korean or English)
    public private(set) var inputMode: InputMode = .korean
    
    // Track last delegate for external toggle calls
    private weak var lastDelegate: (any HangulComposerDelegate)?
    
    // Initialize with direct HangulInputContext (synchronous)
    @available(*, deprecated, message: "Intentionally using synchronous context")
    private var context: HangulInputContext = {
       let ctx = HangulInputContext(keyboard: PriTypeConfig.defaultKeyboardId)
       DebugLogger.log("Configured context with 2-set (id: '\(PriTypeConfig.defaultKeyboardId)')")
       return ctx
    }()
    
    public init() {
        DebugLogger.log("HangulComposer init")
    }
    
    /// Update keyboard layout dynamically (e.g. from Settings)
    public func updateKeyboardLayout(id: String) {
        DebugLogger.log("HangulComposer: Updating keyboard layout to '\(id)'")
        // Commit existing text before switching to avoid corruption
        if let delegate = lastDelegate, !context.isEmpty() {
            commitComposition(delegate: delegate)
        }
        
        // Re-initialize context with new keyboard ID
        context = HangulInputContext(keyboard: id)
    }
    
    /// Toggle input mode externally (called by EventTapManager)
    public func toggleInputMode() {
        DebugLogger.log("toggleInputMode called externally")
        
        // Commit any composition before switching
        if let delegate = lastDelegate, !context.isEmpty() {
            commitComposition(delegate: delegate)
            DebugLogger.log("Composition committed before mode switch")
        }
        
        inputMode = (inputMode == .korean) ? .english : .korean
        StatusBarManager.shared.setMode(inputMode)
        DebugLogger.log("Mode switched to: \(inputMode)")
    }
    
    public func handle(_ event: NSEvent, delegate: HangulComposerDelegate) -> Bool {
        // Track delegate for external toggle calls
        self.lastDelegate = delegate
        
        // Only handle key down events
        if event.type != .keyDown {
            return false
        }
        
        // Control+Space: Language toggle (only if enabled in settings)
        if event.keyCode == KeyCode.space && event.modifierFlags.contains(.control) 
            && ConfigurationManager.shared.controlSpaceAsToggle {
            DebugLogger.log("Control+Space -> Toggle mode")
            
            // Commit any composition before switching (preserve text)
            if !context.isEmpty() {
                commitComposition(delegate: delegate)
                DebugLogger.log("Composition committed before mode switch")
            }
            
            // Toggle mode
            inputMode = (inputMode == .korean) ? .english : .korean
            StatusBarManager.shared.setMode(inputMode)
            DebugLogger.log("Mode switched to: \(inputMode)")
            
            return true  // Consume the event
        }
        
        // English mode: pass all keys to system
        if inputMode == .english {
            DebugLogger.log("English mode -> Pass through")
            return false
        }
        
        // Pass through if modifiers (Command, Control, Option) are present
        // This ensures system shortcuts work correctly without interference
        let significantModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(significantModifiers).isEmpty {
             return false
        }
        
        // Critical Fix: Caps Lock Passthrough
        // If Caps Lock is ON, we should NOT process input as Hangul.
        // Instead, commit any existing composition and let the system handle raw input (Uppercase English).
        if event.modifierFlags.contains(.capsLock) {
            if !context.isEmpty() {
                commitComposition(delegate: delegate)
            }
            return false
        }
        
        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }
        
        let inputCharacters = characters
        
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
        
        // Filter: If input contains non-printable characters (e.g., function keys, arrows)
        // Return false to pass to system. Function keys often have charCode > 63000.
        // Printable ASCII is 32-126. We also allow extended for international.
        // However, we must NOT process function key codes at all.
        if let firstScalar = inputCharacters.unicodeScalars.first {
            let firstCharCode = Int(firstScalar.value)
            // Function keys and special keys have very high char codes (> 63000)
            // or are control characters (< 32, except for special handling)
            if firstCharCode >= 63000 || (firstCharCode < 32 && firstCharCode != 9 && firstCharCode != 10 && firstCharCode != 13) {
                DebugLogger.log("Non-printable key detected, passing to system")
                return false
            }
        }
        
        var handledAtLeastOnce = false
        
        for char in inputCharacters.unicodeScalars {
            let charCode = Int(char.value)
            
            // Skip non-printable characters in the loop as well
            if charCode >= 63000 || (charCode < 32 && charCode != 9 && charCode != 10 && charCode != 13) {
                continue
            }
            
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
                     // ONLY insert if it's a printable character (32-126 or extended)
                     if charCode >= 32 && charCode < 127 {
                         DebugLogger.log("Retry failed, inserting printable char")
                         delegate.insertText(String(char))
                         handledAtLeastOnce = true
                     } else {
                         // Non-printable, skip insertion but still mark as handled
                         // to avoid leakage to system
                         DebugLogger.log("Retry failed, skipping non-printable char")
                     }
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
        
        DebugLogger.log("commitComposition: flushed=\(flushed), str='\(commitStr)'")
        
        if !commitStr.isEmpty {
            // insertText replaces the marked text automatically
            delegate.insertText(commitStr.precomposedStringWithCanonicalMapping)
            DebugLogger.log("commitComposition: inserted '\(commitStr)'")
        }
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
