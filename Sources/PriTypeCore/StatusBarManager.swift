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
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.autosaveName = "PriTypeInputModeIndicator"
        statusItem?.isVisible = true
        
        if let button = statusItem?.button {
            let font = NSFont(name: "AppleSDGothicNeo-Medium", size: 14) ?? NSFont.systemFont(ofSize: 14)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .baselineOffset: -1
            ]
            button.attributedTitle = NSAttributedString(string: "가", attributes: attributes)
            button.imagePosition = .noImage
        }
        
        setupMenu()
        DebugLogger.log("StatusBarManager: Created status item with menu")
    }
    
    @MainActor
    private func setupMenu() {
        let menu = NSMenu()
        
        let settingsItem = NSMenuItem(title: L10n.settings.title + "...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: L10n.about.title, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: L10n.app.quit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
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
    
    /// Update the status bar to show current mode with subtle animation feedback
    public func setMode(_ mode: InputMode) {
        guard lastMode != mode else { return }
        lastMode = mode
        
        let modeValue = mode
        
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem?.button else { return }
            
            let isKorean = (modeValue == .korean)
            let text = isKorean ? "가" : "A"
            let font = NSFont(name: "AppleSDGothicNeo-Medium", size: 14) ?? NSFont.systemFont(ofSize: 14)
            
            // Subtle fade animation for mode change feedback
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                button.animator().alphaValue = 0.4
            } completionHandler: {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .baselineOffset: CGFloat(-1)
                ]
                button.attributedTitle = NSAttributedString(string: text, attributes: attributes)
                
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.08
                    button.animator().alphaValue = 1.0
                }
            }
            
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
