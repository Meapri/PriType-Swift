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
            // Use attributed string for better text centering
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .paragraphStyle: style
            ]
            
            button.attributedTitle = NSAttributedString(string: "가", attributes: attributes)
            button.imagePosition = .noImage
        }
        
        DebugLogger.log("StatusBarManager: Created status item")
    }
    
    // MARK: - Mode Update
    
    /// Update the status bar to show current mode
    public func setMode(_ mode: InputMode) {
        let modeValue = mode
        Task { @MainActor in
            guard let button = self.statusItem?.button else { return }
            
            let text = (modeValue == .korean) ? "가" : "A"
            
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .paragraphStyle: style
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
