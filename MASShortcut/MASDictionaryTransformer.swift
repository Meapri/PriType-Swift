import Foundation
import AppKit

public let MASDictionaryTransformerName = "MASDictionaryTransformer"

private let MASKeyCodeKey = "keyCode"
private let MASModifierFlagsKey = "modifierFlags"

/**
 Converts shortcuts for storage in user defaults.

 User defaults can't stored custom types directly, they have to
 be serialized to `Data` or some other supported type like a
 `Dictionary`. In Cocoa Bindings, the conversion can be done
 using value transformers like this one.

 There's a built-in transformer that converts any `NSCoding` types
 to `Data`, but with shortcuts it makes sense to use a dictionary
 instead – the defaults look better when inspected with the `defaults`
 command-line utility and the format is compatible with an older
 shortcut library called Shortcut Recorder.
 */
public class MASDictionaryTransformer: ValueTransformer {

    public override class func allowsReverseTransformation() -> Bool {
        return true
    }

    // Storing nil values as an empty dictionary lets us differ between
    // "not available, use default value" and "explicitly set to none".
    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let shortcut = value as? MASShortcut else {
            return [:]
        }

        return [
            MASKeyCodeKey: shortcut.keyCode,
            MASModifierFlagsKey: shortcut.modifierFlags.rawValue
        ]
    }

    public override func transformedValue(_ value: Any?) -> Any? {
        // We have to be defensive here as the value may come from user defaults.
        guard let dictionary = value as? [String: Any] else {
            return nil
        }

        guard let keyCodeBox = dictionary[MASKeyCodeKey],
              let modifierFlagsBox = dictionary[MASModifierFlagsKey] else {
            return nil
        }

        // Check if the values can be converted to integers
        guard let keyCode = (keyCodeBox as? Int) ?? (keyCodeBox as? NSNumber)?.intValue,
              let modifierFlagsRaw = (modifierFlagsBox as? Int) ?? (modifierFlagsBox as? NSNumber)?.intValue else {
            return nil
        }

        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(modifierFlagsRaw))
        return MASShortcut(keyCode: keyCode, modifierFlags: modifierFlags)
    }
}
