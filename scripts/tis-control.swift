import Carbon
import Foundation

private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let ptr = TISGetInputSourceProperty(source, key) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
}

private func allSources(includeDisabled: Bool) -> [TISInputSource] {
    let list = TISCreateInputSourceList(nil, includeDisabled)
    return (list?.takeRetainedValue() as? [TISInputSource]) ?? []
}

private func findSource(id: String, includeDisabled: Bool) -> TISInputSource? {
    allSources(includeDisabled: includeDisabled).first { stringProperty($0, kTISPropertyInputSourceID) == id }
}

private func printSource(_ source: TISInputSource) {
    let id = stringProperty(source, kTISPropertyInputSourceID) ?? "?"
    let name = stringProperty(source, kTISPropertyLocalizedName) ?? "?"
    let enabled = boolProperty(source, kTISPropertyInputSourceIsEnabled)
    print("\(enabled ? "on " : "off")\t\(id)\t\(name)")
}

private func interesting(_ id: String) -> Bool {
    let keys = ["patchtype", "pritype", "Korean", "Hangul", "ABC", "US", "2Set"]
    return keys.contains { id.localizedCaseInsensitiveContains($0) }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let action = args.first else {
    fputs("usage: tis-control list|enable|select|find <id>\n", stderr)
    exit(2)
}

switch action {
case "list":
    print("ENABLED:")
    for source in allSources(includeDisabled: false) where interesting(stringProperty(source, kTISPropertyInputSourceID) ?? "") {
        printSource(source)
    }
    print("CURRENT:")
    if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
        printSource(current)
    }

case "find":
    guard args.count > 1 else {
        fputs("usage: tis-control find <id>\n", stderr)
        exit(2)
    }
    let id = args[1]
    if let source = findSource(id: id, includeDisabled: true) {
        printSource(source)
        exit(0)
    }
    fputs("not found: \(id)\n", stderr)
    exit(1)

case "enable":
    guard args.count > 1 else {
        fputs("usage: tis-control enable <id>\n", stderr)
        exit(2)
    }
    let id = args[1]
    guard let source = findSource(id: id, includeDisabled: true) else {
        fputs("not found: \(id)\n", stderr)
        exit(1)
    }
    let status = TISEnableInputSource(source)
    print("TISEnableInputSource(\(id)) -> \(status)")
    exit(status == noErr ? 0 : Int32(status == 0 ? 0 : 1))

case "select":
    guard args.count > 1 else {
        fputs("usage: tis-control select <id>\n", stderr)
        exit(2)
    }
    let id = args[1]
    guard let source = findSource(id: id, includeDisabled: true) else {
        fputs("not found: \(id)\n", stderr)
        exit(1)
    }
    if !boolProperty(source, kTISPropertyInputSourceIsEnabled) {
        let enableStatus = TISEnableInputSource(source)
        print("TISEnableInputSource(\(id)) -> \(enableStatus)")
        if enableStatus != noErr {
            exit(1)
        }
    }
    let status = TISSelectInputSource(source)
    print("TISSelectInputSource(\(id)) -> \(status)")
    exit(status == noErr ? 0 : 1)

default:
    fputs("unknown action: \(action)\n", stderr)
    exit(2)
}
