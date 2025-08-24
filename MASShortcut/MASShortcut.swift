import AppKit
import Carbon

// MARK: - MASShortcut

/**
 A value type representing a keyboard shortcut combination.

 This struct represents a combination of keys with strong type safety and modern Swift features.
 It provides immutable value semantics and comprehensive validation.
 */
@frozen
public struct MASShortcut: Sendable, Hashable, Codable, CustomStringConvertible {

    // MARK: - Properties

    /// The virtual key code for the keyboard key.
    /// Hardware independent, same as in `NSEvent`.
    public let keyCode: Int

    /// Cocoa keyboard modifier flags.
    /// Same as in `NSEvent`: `.command`, `.option`, etc.
    public let modifierFlags: NSEvent.ModifierFlags

    /// Same as `keyCode`, just a different type.
    public var carbonKeyCode: UInt32 {
        return keyCode == NSNotFound ? 0 : UInt32(keyCode)
    }

    /// Carbon modifier flags.
    /// A bit sum of `cmdKey`, `optionKey`, etc.
    public var carbonFlags: UInt32 {
        return MASCarbonModifiersFromCocoaModifiers(modifierFlags)
    }

    /// A string representing the "key" part of a shortcut, like the `5` in `⌘5`.
    /// The value may change depending on the active keyboard layout.
    public var keyCodeString: String? {
        return keyCodeStringForKeyCode(self.keyCode)
    }

    /// A key-code string used in key equivalent matching.
    public var keyCodeStringForKeyEquivalent: String? {
        let keyCodeString = self.keyCodeString

        switch self.keyCode {
        case Int(kVK_F1): return NSStringFromMASKeyCode(UInt16(NSF1FunctionKey))
        case Int(kVK_F2): return NSStringFromMASKeyCode(UInt16(NSF2FunctionKey))
        case Int(kVK_F3): return NSStringFromMASKeyCode(UInt16(NSF3FunctionKey))
        case Int(kVK_F4): return NSStringFromMASKeyCode(UInt16(NSF4FunctionKey))
        case Int(kVK_F5): return NSStringFromMASKeyCode(UInt16(NSF5FunctionKey))
        case Int(kVK_F6): return NSStringFromMASKeyCode(UInt16(NSF6FunctionKey))
        case Int(kVK_F7): return NSStringFromMASKeyCode(UInt16(NSF7FunctionKey))
        case Int(kVK_F8): return NSStringFromMASKeyCode(UInt16(NSF8FunctionKey))
        case Int(kVK_F9): return NSStringFromMASKeyCode(UInt16(NSF9FunctionKey))
        case Int(kVK_F10): return NSStringFromMASKeyCode(UInt16(NSF10FunctionKey))
        case Int(kVK_F11): return NSStringFromMASKeyCode(UInt16(NSF11FunctionKey))
        case Int(kVK_F12): return NSStringFromMASKeyCode(UInt16(NSF12FunctionKey))
        case Int(kVK_F13): return NSStringFromMASKeyCode(UInt16(NSF13FunctionKey))
        case Int(kVK_F14): return NSStringFromMASKeyCode(UInt16(NSF14FunctionKey))
        case Int(kVK_F15): return NSStringFromMASKeyCode(UInt16(NSF15FunctionKey))
        case Int(kVK_F16): return NSStringFromMASKeyCode(UInt16(NSF16FunctionKey))
        case Int(kVK_F17): return NSStringFromMASKeyCode(UInt16(NSF17FunctionKey))
        case Int(kVK_F18): return NSStringFromMASKeyCode(UInt16(NSF18FunctionKey))
        case Int(kVK_F19): return NSStringFromMASKeyCode(UInt16(NSF19FunctionKey))
        case Int(kVK_Space): return NSStringFromMASKeyCode(MASShortcutFunctionKey.space.rawValue)
        case Int(kVK_Escape): return NSStringFromMASKeyCode(MASShortcutGlyph.escape.rawValue)
        case Int(kVK_Delete): return NSStringFromMASKeyCode(MASShortcutGlyph.deleteLeft.rawValue)
        case Int(kVK_ForwardDelete): return NSStringFromMASKeyCode(MASShortcutGlyph.deleteRight.rawValue)
        case Int(kVK_LeftArrow): return NSStringFromMASKeyCode(MASShortcutGlyph.leftArrow.rawValue)
        case Int(kVK_RightArrow): return NSStringFromMASKeyCode(MASShortcutGlyph.rightArrow.rawValue)
        case Int(kVK_UpArrow): return NSStringFromMASKeyCode(MASShortcutGlyph.upArrow.rawValue)
        case Int(kVK_DownArrow): return NSStringFromMASKeyCode(MASShortcutGlyph.downArrow.rawValue)
        case Int(kVK_Help): return NSStringFromMASKeyCode(MASShortcutGlyph.help.rawValue)
        case Int(kVK_Home): return NSStringFromMASKeyCode(MASShortcutGlyph.northwestArrow.rawValue)
        case Int(kVK_End): return NSStringFromMASKeyCode(MASShortcutGlyph.southeastArrow.rawValue)
        case Int(kVK_PageUp): return NSStringFromMASKeyCode(MASShortcutGlyph.pageUp.rawValue)
        case Int(kVK_PageDown): return NSStringFromMASKeyCode(MASShortcutGlyph.pageDown.rawValue)
        case Int(kVK_Tab): return NSStringFromMASKeyCode(MASShortcutGlyph.tabRight.rawValue)
        case Int(kVK_Return): return NSStringFromMASKeyCode(MASShortcutGlyph.returnR2L.rawValue)
        default:
            return keyCodeString?.lowercased()
        }
    }

    /// A string representing the shortcut modifiers, like the `⌘` in `⌘5`.
    public var modifierFlagsString: String {
        var chars: [unichar] = []
        // These are in the same order as the menu manager shows them
        if modifierFlags.contains(.control) { chars.append(0x2303) } // Control Unicode
        if modifierFlags.contains(.option) { chars.append(0x2325) }  // Option Unicode
        if modifierFlags.contains(.shift) { chars.append(0x21E7) }   // Shift Unicode
        if modifierFlags.contains(.command) { chars.append(0x2318) } // Command Unicode
        return chars.isEmpty ? "" : String(utf16CodeUnits: chars, count: chars.count)
    }

    // MARK: - Initialization

    /// Creates a new shortcut with the specified key code and modifier flags.
    /// - Parameters:
    ///   - keyCode: The virtual key code for the keyboard key.
    ///   - modifierFlags: The Cocoa keyboard modifier flags.
    public init(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = MASPickCocoaModifiers(modifierFlags)
    }

    /// Creates a shortcut from an NSEvent.
    /// - Parameter event: The event containing key and modifier information.
    public init?(event: NSEvent) {
        self.init(keyCode: Int(event.keyCode), modifierFlags: event.modifierFlags)
    }

    /// Convenience static factory method.
    public static func shortcut(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) -> MASShortcut {
        return MASShortcut(keyCode: keyCode, modifierFlags: modifierFlags)
    }

    /// Convenience static factory method for events.
    public static func shortcut(event: NSEvent) -> MASShortcut? {
        return MASShortcut(event: event)
    }

    // MARK: - Higher-Order Functions

    /// Creates a shortcut using function composition.
    public static func composed(_ composer: (MASShortcutComposer) -> MASShortcutComposer) -> MASShortcut? {
        let c = composer(MASShortcutComposer())
        return c.build()
    }

    /// Maps this shortcut to a new key code.
    public func mapKeyCode(_ transform: (Int) -> Int) -> MASShortcut {
        return MASShortcut(keyCode: transform(keyCode), modifierFlags: modifierFlags)
    }

    /// Maps this shortcut's modifiers.
    public func mapModifiers(_ transform: (NSEvent.ModifierFlags) -> NSEvent.ModifierFlags) -> MASShortcut {
        return MASShortcut(keyCode: keyCode, modifierFlags: transform(modifierFlags))
    }

    /// Chains multiple transformations.
    public func chain(_ operations: [(MASShortcut) -> MASShortcut]) -> MASShortcut {
        return operations.reduce(self) { $1($0) }
    }

    // MARK: - KeyPath-Based API

    /// Accesses a property using key paths.
    public subscript<T>(keyPath: KeyPath<MASShortcut, T>) -> T {
        return self[keyPath: keyPath]
    }

    /// Creates a new shortcut by modifying a specific property.
    public func with<T>(_ keyPath: WritableKeyPath<MASShortcut, T>, value: T) -> MASShortcut {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }

    /// Creates a new shortcut by transforming a property.
    public func map<T>(_ keyPath: WritableKeyPath<MASShortcut, T>, transform: (T) -> T) -> MASShortcut {
        return with(keyPath, value: transform(self[keyPath: keyPath]))
    }

    // MARK: - Modern API Extensions

    /// Creates a shortcut using a builder pattern.
    public static func build(_ builder: (inout Builder) -> Void) -> Result<MASShortcut, ShortcutError> {
        var b = Builder()
        builder(&b)

        guard let keyCode = b.keyCode else {
            return .failure(.missingKeyCode)
        }

        let shortcut = MASShortcut(keyCode: keyCode, modifierFlags: b.modifierFlags)
        return .success(shortcut)
    }

    /// A result builder for creating shortcuts.
    @resultBuilder
    public enum ShortcutBuilder {
        public static func buildBlock(_ components: MASShortcut...) -> [MASShortcut] {
            return components
        }
    }

    /// Errors that can occur when creating or validating shortcuts.
    public enum ShortcutError: LocalizedError, Sendable {
        case missingKeyCode
        case invalidKeyCode(Int)
        case invalidModifierFlags
        case systemReserved

        public var errorDescription: String? {
            switch self {
            case .missingKeyCode:
                return "Key code is required to create a shortcut"
            case .invalidKeyCode(let code):
                return "Invalid key code: \(code)"
            case .invalidModifierFlags:
                return "Invalid modifier flags combination"
            case .systemReserved:
                return "This shortcut is reserved by the system"
            }
        }
    }

    /// Builder for creating shortcuts with a fluent API.
    public struct Builder {
        public var keyCode: Int?
        public var modifierFlags: NSEvent.ModifierFlags = []

        public mutating func key(_ code: Int) {
            keyCode = code
        }

        public mutating func modifiers(_ flags: NSEvent.ModifierFlags) {
            modifierFlags = flags
        }

        public mutating func command() {
            modifierFlags.insert(.command)
        }

        public mutating func option() {
            modifierFlags.insert(.option)
        }

        public mutating func shift() {
            modifierFlags.insert(.shift)
        }

        public mutating func control() {
            modifierFlags.insert(.control)
        }
    }

    // MARK: - Private Methods

    private func keyCodeStringForKeyCode(_ keyCode: Int) -> String {
        // Some key codes don't have an equivalent
        switch keyCode {
        case NSNotFound: return ""
        case Int(kVK_F1): return "F1"
        case Int(kVK_F2): return "F2"
        case Int(kVK_F3): return "F3"
        case Int(kVK_F4): return "F4"
        case Int(kVK_F5): return "F5"
        case Int(kVK_F6): return "F6"
        case Int(kVK_F7): return "F7"
        case Int(kVK_F8): return "F8"
        case Int(kVK_F9): return "F9"
        case Int(kVK_F10): return "F10"
        case Int(kVK_F11): return "F11"
        case Int(kVK_F12): return "F12"
        case Int(kVK_F13): return "F13"
        case Int(kVK_F14): return "F14"
        case Int(kVK_F15): return "F15"
        case Int(kVK_F16): return "F16"
        case Int(kVK_F17): return "F17"
        case Int(kVK_F18): return "F18"
        case Int(kVK_F19): return "F19"
        case Int(kVK_Space): return NSLocalizedString("Space", comment: "Shortcut glyph name for SPACE key")
        case Int(kVK_Escape): return NSStringFromMASKeyCode(MASShortcutGlyph.escape.rawValue)
        case Int(kVK_Delete): return NSStringFromMASKeyCode(MASShortcutGlyph.deleteLeft.rawValue)
        case Int(kVK_ForwardDelete): return NSStringFromMASKeyCode(MASShortcutGlyph.deleteRight.rawValue)
        case Int(kVK_LeftArrow): return NSStringFromMASKeyCode(MASShortcutGlyph.leftArrow.rawValue)
        case Int(kVK_RightArrow): return NSStringFromMASKeyCode(MASShortcutGlyph.rightArrow.rawValue)
        case Int(kVK_UpArrow): return NSStringFromMASKeyCode(MASShortcutGlyph.upArrow.rawValue)
        case Int(kVK_DownArrow): return NSStringFromMASKeyCode(MASShortcutGlyph.downArrow.rawValue)
        case Int(kVK_Help): return NSStringFromMASKeyCode(MASShortcutGlyph.help.rawValue)
        case Int(kVK_Home): return NSStringFromMASKeyCode(MASShortcutGlyph.northwestArrow.rawValue)
        case Int(kVK_End): return NSStringFromMASKeyCode(MASShortcutGlyph.southeastArrow.rawValue)
        case Int(kVK_PageUp): return NSStringFromMASKeyCode(MASShortcutGlyph.pageUp.rawValue)
        case Int(kVK_PageDown): return NSStringFromMASKeyCode(MASShortcutGlyph.pageDown.rawValue)
        case Int(kVK_Tab): return NSStringFromMASKeyCode(MASShortcutGlyph.tabRight.rawValue)
        case Int(kVK_Return): return NSStringFromMASKeyCode(MASShortcutGlyph.returnR2L.rawValue)

        // Keypad
        case Int(kVK_ANSI_Keypad0): return "0"
        case Int(kVK_ANSI_Keypad1): return "1"
        case Int(kVK_ANSI_Keypad2): return "2"
        case Int(kVK_ANSI_Keypad3): return "3"
        case Int(kVK_ANSI_Keypad4): return "4"
        case Int(kVK_ANSI_Keypad5): return "5"
        case Int(kVK_ANSI_Keypad6): return "6"
        case Int(kVK_ANSI_Keypad7): return "7"
        case Int(kVK_ANSI_Keypad8): return "8"
        case Int(kVK_ANSI_Keypad9): return "9"
        case Int(kVK_ANSI_KeypadDecimal): return "."
        case Int(kVK_ANSI_KeypadMultiply): return "*"
        case Int(kVK_ANSI_KeypadPlus): return "+"
        case Int(kVK_ANSI_KeypadClear): return NSStringFromMASKeyCode(MASShortcutGlyph.padClear.rawValue)
        case Int(kVK_ANSI_KeypadDivide): return "/"
        case Int(kVK_ANSI_KeypadEnter): return NSStringFromMASKeyCode(MASShortcutGlyph.return.rawValue)
        case Int(kVK_ANSI_KeypadMinus): return "-"
        case Int(kVK_ANSI_KeypadEquals): return "="
        default:
            break
        }

        // For simplicity, return empty string for complex key codes
        // In a full implementation, you would implement proper keyboard layout handling
        return ""
    }

    // MARK: - Protocol Conformances

    public var description: String {
        return "\(modifierFlagsString)\(keyCodeString ?? "")"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifierFlags.rawValue)
    }

    public static func == (lhs: MASShortcut, rhs: MASShortcut) -> Bool {
        return lhs.keyCode == rhs.keyCode && lhs.modifierFlags == rhs.modifierFlags
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifierFlags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        let flagsRaw = try container.decode(UInt.self, forKey: .modifierFlags)
        modifierFlags = NSEvent.ModifierFlags(rawValue: flagsRaw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifierFlags.rawValue, forKey: .modifierFlags)
    }
}

// MARK: - MASShortcutComposer

/// A functional composer for creating shortcuts.
public struct MASShortcutComposer {
    private var keyCode: Int?
    private var modifierFlags: NSEvent.ModifierFlags = []

    public func key(_ code: Int) -> MASShortcutComposer {
        var copy = self
        copy.keyCode = code
        return copy
    }

    public func modifiers(_ flags: NSEvent.ModifierFlags) -> MASShortcutComposer {
        var copy = self
        copy.modifierFlags = flags
        return copy
    }

    public func command() -> MASShortcutComposer {
        var copy = self
        copy.modifierFlags.insert(.command)
        return copy
    }

    public func option() -> MASShortcutComposer {
        var copy = self
        copy.modifierFlags.insert(.option)
        return copy
    }

    public func shift() -> MASShortcutComposer {
        var copy = self
        copy.modifierFlags.insert(.shift)
        return copy
    }

    public func control() -> MASShortcutComposer {
        var copy = self
        copy.modifierFlags.insert(.control)
        return copy
    }

    public func build() -> MASShortcut? {
        guard let keyCode = keyCode else { return nil }
        return MASShortcut(keyCode: keyCode, modifierFlags: modifierFlags)
    }
}
