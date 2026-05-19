import Testing
import Cocoa
@testable import PriTypeCore

// MARK: - Shared Test Helpers

/// Mock implementation of StatusBarUpdating for tests
final class MockStatusBar: StatusBarUpdating {
    var currentMode: InputMode = .korean
    var modeChanges: [InputMode] = []
    
    func setMode(_ mode: InputMode) {
        currentMode = mode
        modeChanges.append(mode)
    }
}

/// Mock implementation of ConfigurationProviding for tests
final class MockConfiguration: ConfigurationProviding, @unchecked Sendable {
    var keyboardId: String = PriTypeConfig.defaultKeyboardId
    var toggleKey: ToggleKey = .rightCommand
    var rightCommandAsToggle: Bool { true }
    var controlSpaceAsToggle: Bool { false }
    var capsLockInputSourceSwitchEnabled: Bool { false }
    var doubleSpacePeriodEnabled: Bool { true }
}

/// Mock implementation of HangulComposerDelegate for tests
final class MockComposerDelegate: HangulComposerDelegate {
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

/// Factory for creating NSEvent instances in tests
enum TestEventFactory {
    static func keyEvent(
        char: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        type: NSEvent.EventType = .keyDown,
        timestamp: TimeInterval = 0,
        isARepeat: Bool = false
    ) -> NSEvent? {
        return NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: isARepeat,
            keyCode: keyCode
        )
    }
}
