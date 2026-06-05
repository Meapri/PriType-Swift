import Cocoa

// MARK: - StatusBarUpdating Protocol

/// Protocol for updating the status bar mode indicator
/// Enables dependency injection and testability
public protocol StatusBarUpdating: AnyObject {
    /// Update the status bar to show current input mode
    func setMode(_ mode: InputMode)
}

// MARK: - StatusBarManager

/// Manages a status bar item to show current input mode (가/A)
///
/// This class handles all UI updates on the main thread for thread safety.
public final class StatusBarManager: NSObject, StatusBarUpdating, @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = StatusBarManager()
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private var lastMode: InputMode?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup
    
    /// Initialize the status bar item
    @MainActor
    public func setup() {
        guard statusItem == nil else { return }

        // variableLength hugs the glyph like the system input-source indicator.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = "PriTypeInputModeIndicator"
        statusItem?.isVisible = true

        if let button = statusItem?.button {
            applyMode(lastMode ?? .korean, to: button)
        }

        setupMenu()
        DebugLogger.log("StatusBarManager: Created status item with menu")
    }

    /// Render the menu-bar indicator natively: a PLAIN title (so the system applies
    /// menu-bar vibrancy — white on a dark bar, and an inverted highlight while the menu
    /// is open) in the system font. The Korean label is "한", matching macOS's own 2-Set
    /// Korean indicator; English mirrors ABC's "A".
    private func applyMode(_ mode: InputMode, to button: NSStatusBarButton) {
        let isKorean = (mode == .korean)
        button.image = nil
        button.imagePosition = .noImage
        button.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        button.title = isKorean ? "한" : "A"
        button.toolTip = isKorean ? "한국어" : "English"
        button.setAccessibilityLabel(isKorean ? "한국어 입력" : "영문 입력")
    }

    @MainActor
    private func menuImage(_ symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true   // tint to the native menu text color (light/dark/highlight)
        return image
    }

    @MainActor
    private func setupMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: L10n.settings.title + "...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = menuImage("gearshape")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: L10n.about.title, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = menuImage("info.circle")
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.app.quit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = menuImage("power")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }
    
    // MARK: - Menu Actions
    
    @objc private func openSettings() {
        DebugLogger.log("StatusBarManager: Opening settings")
        DispatchQueue.main.async {
            SettingsWindowController.shared.showSettings()
        }
    }
    
    @objc private func showAbout() {
        DebugLogger.log("StatusBarManager: Showing about")
        DispatchQueue.main.async {
            AboutInfo.showAlert()
        }
    }
    
    @MainActor
    @objc private func quitApp() {
        DebugLogger.log("StatusBarManager: Quitting")
        NSApp.terminate(nil)
    }
    
    // MARK: - Mode Update with Animation
    
    /// Update the menu-bar indicator to the current mode. The swap is instant, matching
    /// the system input-source indicator (no fade), and uses the native plain-title
    /// rendering set up in `applyMode`.
    public func setMode(_ mode: InputMode) {
        guard lastMode != mode else { return }
        lastMode = mode

        let modeValue = mode

        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem?.button else { return }
            self.applyMode(modeValue, to: button)
            DebugLogger.log("StatusBarManager: Mode set to \(modeValue)")
        }
    }
    
    // MARK: - Cleanup
    
    @MainActor
    public func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
