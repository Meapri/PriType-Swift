import AppKit

public let MASShortcutBinding = "shortcutValue"

public enum MASShortcutViewStyle: Int {
    case `default` = 0  // Height = 19 px
    case texturedRect   // Height = 25 px
    case rounded        // Height = 43 px
    case flat
    case regularSquare
}

public class MASShortcutView: NSView {

    // MARK: - Properties

    public var shortcutValue: MASShortcut? {
        didSet {
            updateDisplay()
            shortcutValueChange?(self)
        }
    }

    public var shortcutValidator: MASShortcutValidator = .create()

    public private(set) var isRecording: Bool = false

    public var isEnabled: Bool = true {
        didSet {
            updateTrackingAreas()
            if !isEnabled {
                isRecording = false
            }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    public var shortcutValueChange: ((MASShortcutView) -> Void)?

    public var style: MASShortcutViewStyle = .default {
        didSet {
            if oldValue != style {
                resetShortcutCellStyle()
                invalidateIntrinsicContentSize()
                needsDisplay = true
            }
        }
    }

    // MARK: - Private Properties

    private var shortcutCell: MASShortcutViewButtonCell
    private var isHinting: Bool = false
    private var shortcutPlaceholder: String?
    private var showsDeleteButton: Bool = true
    private var acceptsFirstResponderValue: Bool = false

    // MARK: - Initialization

    public override init(frame frameRect: NSRect) {
        self.shortcutCell = MASShortcutView.shortcutCellClass.init()
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        self.shortcutCell = MASShortcutView.shortcutCellClass.init()
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        shortcutCell.font = NSFontManager.shared.convert(shortcutCell.font ?? NSFont.systemFont(ofSize: 11), toSize: 11)
        isEnabled = true
        showsDeleteButton = true
        acceptsFirstResponderValue = false
        resetShortcutCellStyle()
    }

    // MARK: - Public Methods

    public static var shortcutCellClass: MASShortcutViewButtonCell.Type {
        return MASShortcutViewButtonCell.self
    }

    public func setAcceptsFirstResponder(_ value: Bool) {
        acceptsFirstResponderValue = value
    }

    // MARK: - Private Methods

    private func resetShortcutCellStyle() {
        switch style {
        case .default:
            shortcutCell.bezelStyle = .regularSquare
        case .texturedRect:
            shortcutCell.bezelStyle = .texturedRounded
        case .rounded:
            shortcutCell.bezelStyle = .rounded
        case .flat:
            shortcutCell.bezelStyle = .inline
        case .regularSquare:
            shortcutCell.bezelStyle = .regularSquare
        }
    }

    private func updateDisplay() {
        if let shortcut = shortcutValue {
            shortcutCell.title = shortcut.modifierFlagsString + (shortcut.keyCodeString ?? "")
        } else {
            shortcutCell.title = shortcutPlaceholder ?? MASLocalizedString("Click to record shortcut", "")
        }
    }

    // MARK: - Event Handling

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled && !isRecording else { return }

        isRecording = true
        updateDisplay()
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if let shortcut = MASShortcut(event: event) {
            if shortcutValidator.isShortcutValid(shortcut) {
                shortcutValue = shortcut
                isRecording = false
                updateDisplay()
                needsDisplay = true
            }
        }
    }

    // MARK: - Layout

    public override var intrinsicContentSize: NSSize {
        let height: CGFloat
        switch style {
        case .default:
            height = 19
        case .texturedRect:
            height = 25
        case .rounded:
            height = 43
        case .flat, .regularSquare:
            height = 21
        }

        return NSSize(width: 120, height: height)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isRecording {
            NSColor.selectedControlColor.set()
            bounds.fill()
            shortcutCell.title = MASLocalizedString("Type shortcut", "")
        } else {
            updateDisplay()
        }

        shortcutCell.drawInterior(withFrame: bounds, in: self)
    }

    // MARK: - Accessibility

    public override var acceptsFirstResponder: Bool {
        return acceptsFirstResponderValue && isEnabled
    }

    public override var focusRingType: NSFocusRingType {
        get { return .exterior }
        set { super.focusRingType = newValue }
    }
}
