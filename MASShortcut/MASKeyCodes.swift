import AppKit
import Carbon

// MARK: - Key Glyphs

public enum MASShortcutGlyph: UInt16 {
    case eject = 0x23CF
    case clear = 0x2715
    case deleteLeft = 0x232B
    case deleteRight = 0x2326
    case leftArrow = 0x2190
    case rightArrow = 0x2192
    case upArrow = 0x2191
    case downArrow = 0x2193
    case escape = 0x238B
    case help = 0x003F
    case pageDown = 0x21DF
    case pageUp = 0x21DE
    case tabRight = 0x21E5
    case `return` = 0x2305
    case returnR2L = 0x21A9
    case padClear = 0x2327
    case northwestArrow = 0x2196
    case southeastArrow = 0x2198
}

// MARK: - Function Keys

public enum MASShortcutFunctionKey: UInt16 {
    case escape = 0x001B
    case delete = 0x0008
    case space = 0x0020
    case `return` = 0x000D
    case tab = 0x0009
}

// MARK: - Utility Functions

public func NSStringFromMASKeyCode(_ ch: UInt16) -> String {
    return String(format: "%C", ch)
}

public func MASPickCocoaModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    return flags.intersection([.control, .shift, .option, .command])
}

public func MASPickModifiersIncludingFn(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    return flags.intersection([.control, .shift, .option, .command, .function])
}

public func MASCarbonModifiersFromCocoaModifiers(_ cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
    var carbonFlags: UInt32 = 0
    if cocoaFlags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
    if cocoaFlags.contains(.option) { carbonFlags |= UInt32(optionKey) }
    if cocoaFlags.contains(.control) { carbonFlags |= UInt32(controlKey) }
    if cocoaFlags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
    return carbonFlags
}
