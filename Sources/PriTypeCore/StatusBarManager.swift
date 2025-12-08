import Cocoa

/// Manages a status bar item to show current input mode (가/A)
public final class StatusBarManager: NSObject, @unchecked Sendable {
    
    // Singleton
    public static let shared = StatusBarManager()
    
    private var statusItem: NSStatusItem?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup
    
    /// Initialize the status bar item (must be called from main thread)
    @MainActor
    public func setup() {
        guard statusItem == nil else { return }
        
        // Use squareLength for consistent icon sizing
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // Enable position persistence
        statusItem?.autosaveName = "PriTypeInputModeIndicator"
        statusItem?.isVisible = true
        
        if let button = statusItem?.button {
            // Use AppleSDGothicNeo-Medium font
            let font = NSFont(name: "AppleSDGothicNeo-Medium", size: 14) ?? NSFont.systemFont(ofSize: 14)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .baselineOffset: -1  // Korean "가"
            ]
            button.attributedTitle = NSAttributedString(string: "가", attributes: attributes)
            button.imagePosition = .noImage
        }
        
        // Setup context menu
        setupMenu()
        
        DebugLogger.log("StatusBarManager: Created status item with menu")
    }
    
    @MainActor
    private func setupMenu() {
        let menu = NSMenu()
        
        // Settings
        let settingsItem = NSMenuItem(title: "PriType 설정...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // About
        let aboutItem = NSMenuItem(title: "PriType 정보", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "PriType 종료", action: #selector(quitApp), keyEquivalent: "q")
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
            let alert = NSAlert()
            alert.messageText = "PriType"
            alert.informativeText = "macOS용 한글 입력기\n\n버전: 2.0\n© 2025"
            alert.alertStyle = .informational
            alert.runModal()
        }
    }
    
    @objc private func quitApp() {
        DebugLogger.log("StatusBarManager: Quitting")
        NSApp.terminate(nil)
    }
    
    // MARK: - Mode Update
    
    /// Update the status bar to show current mode
    public func setMode(_ mode: InputMode) {
        let modeValue = mode
        Task { @MainActor in
            guard let button = self.statusItem?.button else { return }
            
            let isKorean = (modeValue == .korean)
            let text = isKorean ? "가" : "A"
            let font = NSFont(name: "AppleSDGothicNeo-Medium", size: 14) ?? NSFont.systemFont(ofSize: 14)
            // Different baseline offset for Korean vs English
            let baselineOffset: CGFloat = -1  // Same for both Korean and English
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .baselineOffset: baselineOffset
            ]
            button.attributedTitle = NSAttributedString(string: text, attributes: attributes)
            
            DebugLogger.log("StatusBarManager: Mode set to \(modeValue)")
        }
    }
    
    // MARK: - Cleanup
    
    /// Remove the status bar item
    @MainActor
    public func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
