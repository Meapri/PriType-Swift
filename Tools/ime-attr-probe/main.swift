import AppKit

// Self-advancing IME attribute probe v2.
// Shows instructions; each received setMarkedText records the result for the
// CURRENT experiment variant, then auto-advances PreeditStyleExperiment to the
// next one. No external timing/sync needed — the user just types one key
// repeatedly. Results: window + /tmp/ime_attr_probe/probe2.log

let logPath = "/tmp/ime_attr_probe/probe2.log"
let imeDomain = "com.pritype.inputmethod.v2" as CFString
let expKey = "PreeditStyleExperiment" as CFString
var logLines: [String] = []
let t0 = Date()
func plog(_ s: String) {
    let dt = String(format: "%6.1f", Date().timeIntervalSince(t0))
    logLines.append("[\(dt)] \(s)")
    try? logLines.joined(separator: "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
}

func setVariant(_ v: String?) {
    if let v = v {
        CFPreferencesSetValue(expKey, v as CFString, imeDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    } else {
        CFPreferencesSetValue(expKey, nil, imeDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    CFPreferencesSynchronize(imeDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
}

func describe(_ value: Any) -> String {
    if let color = value as? NSColor {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "rgba(%.2f,%.2f,%.2f,%.2f)", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }
    return "\(value)"
}

// Variants still unmeasured (clause2, clause9, u0clear already measured: U=2 blue).
let variants: [String] = ["clause1", "clause3", "clause4", "clause5", "clause6", "clause7", "clause8", "empty", "OFF(production)"]
var idx = 0
var results: [String] = []

final class ProbeView: NSView, NSTextInputClient {
    var currentMarked = NSRange(location: NSNotFound, length: 0)
    var onResult: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    func insertText(_ string: Any, replacementRange: NSRange) {
        currentMarked = NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        var summary = "?"
        if let attr = string as? NSAttributedString {
            var parts: [String] = []
            attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { attrs, range, _ in
                if attrs.isEmpty { parts.append("(no attrs)") }
                for (k, v) in attrs.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                    parts.append("\(k.rawValue)=\(describe(v))")
                }
            }
            summary = parts.joined(separator: " ")
            currentMarked = NSRange(location: 0, length: attr.length)
        } else {
            summary = "PLAIN STRING (no attrs)"
            currentMarked = NSRange(location: 0, length: (string as? String)?.utf16.count ?? 0)
        }
        onResult?(summary)
    }

    func unmarkText() { currentMarked = NSRange(location: NSNotFound, length: 0) }
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { currentMarked }
    func hasMarkedText() -> Bool { currentMarked.location != NSNotFound }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .underlineColor, .markedClauseSegment, .foregroundColor,
         .backgroundColor, .font, .glyphInfo, .textAlternatives, .attachment]
    }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        window?.convertToScreen(NSRect(x: 10, y: 10, width: 0, height: 20)) ?? .zero
    }
    func characterIndex(for point: NSPoint) -> Int { 0 }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }
    override func doCommand(by selector: Selector) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 560, height: 240),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.title = "PriType 밑줄 실험 (자동 진행)"
window.level = .floating

let instruction = NSTextField(labelWithString: "이 창에 한글 키(예: ㅎ = g)를 반복해서 눌러주세요.\n키를 누를 때마다 다음 실험값으로 자동으로 넘어갑니다.")
instruction.frame = NSRect(x: 16, y: 180, width: 528, height: 44)
instruction.font = .systemFont(ofSize: 13)

let status = NSTextField(labelWithString: "")
status.frame = NSRect(x: 16, y: 148, width: 528, height: 24)
status.font = .boldSystemFont(ofSize: 15)

let resultLabel = NSTextField(labelWithString: "")
resultLabel.frame = NSRect(x: 16, y: 12, width: 528, height: 130)
resultLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
resultLabel.maximumNumberOfLines = 12
resultLabel.cell?.truncatesLastVisibleLine = true

let view = ProbeView(frame: window.contentView!.bounds)
window.contentView?.addSubview(view)
window.contentView?.addSubview(instruction)
window.contentView?.addSubview(status)
window.contentView?.addSubview(resultLabel)

func refreshStatus() {
    if idx < variants.count {
        status.stringValue = "테스트 중 (\(idx + 1)/\(variants.count)): \(variants[idx]) — 키를 누르세요"
    } else {
        status.stringValue = "✅ 완료! 창을 닫아도 됩니다 (실험값은 원래대로 복구됨)"
    }
    resultLabel.stringValue = results.suffix(11).joined(separator: "\n")
}

view.onResult = { summary in
    guard idx < variants.count else { return }
    let v = variants[idx]
    let line = "\(v): \(summary)"
    results.append(line)
    plog("RESULT \(line)")
    idx += 1
    if idx < variants.count {
        let next = variants[idx]
        setVariant(next == "OFF(production)" ? nil : next)
        plog("SET \(next)")
    } else {
        setVariant(nil)
        plog("ALL DONE — experiment key removed")
    }
    DispatchQueue.main.async { refreshStatus() }
}

window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(view)
app.activate(ignoringOtherApps: true)

setVariant(variants[0])
plog("probe2 started; SET \(variants[0])")
refreshStatus()

DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
    setVariant(nil)
    plog("probe2 timeout — experiment key removed")
    app.terminate(nil)
}

app.run()
