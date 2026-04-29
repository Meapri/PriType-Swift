import Cocoa
import SwiftUI

/// Custom floating candidate window for Hanja selection
///
/// Displays a list of Hanja candidates near the text cursor position.
/// Supports keyboard navigation (1-9, arrow keys, page up/down).
public final class HanjaCandidateWindow: @unchecked Sendable {
    
    nonisolated(unsafe) public static let shared = HanjaCandidateWindow()
    
    private var window: NSWindow?
    private var candidates: [HanjaEntry] = []
    private var currentPage = 0
    private let pageSize = 9
    private var onSelect: ((HanjaEntry) -> Void)?
    private var onDismiss: (() -> Void)?
    
    public var isVisible: Bool {
        window?.isVisible ?? false
    }
    
    private init() {}
    
    /// Show the candidate window with the given entries
    /// - Parameters:
    ///   - entries: Array of HanjaEntry to display
    ///   - cursorRect: The rect near the text cursor to position the window
    ///   - onSelect: Callback when a candidate is selected
    ///   - onDismiss: Callback when the window is dismissed
    public func show(
        entries: [HanjaEntry],
        cursorRect: NSRect,
        onSelect: @escaping (HanjaEntry) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.candidates = entries
        self.currentPage = 0
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        
        guard !entries.isEmpty else {
            dismiss()
            return
        }
        
        // Reuse existing panel or create a new one
        let panel: NSPanel
        if let existing = window as? NSPanel {
            panel = existing
        } else {
            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 0),
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isReleasedWhenClosed = false
            self.window = panel
        }
        
        updateContent()
        positionWindow(near: cursorRect)
        panel.orderFrontRegardless()
        
        DebugLogger.log("Hanja: Window shown at \(panel.frame), level=\(panel.level.rawValue)")
    }
    
    /// Dismiss the candidate window (hides without destroying)
    public func dismiss() {
        window?.orderOut(nil)
        candidates = []
        let dismissCallback = onDismiss
        onDismiss = nil
        onSelect = nil
        dismissCallback?()
    }
    
    /// Handle a key event while the candidate window is visible
    /// - Returns: true if the event was consumed
    public func handleKey(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        
        let keyCode = event.keyCode
        
        // ESC -> dismiss
        if keyCode == 53 { // Escape
            dismiss()
            return true
        }
        
        // Number keys 1-9 -> select
        if let chars = event.charactersIgnoringModifiers,
           let digit = chars.first?.wholeNumberValue,
           digit >= 1 && digit <= 9 {
            let index = (currentPage * pageSize) + (digit - 1)
            if index < candidates.count {
                selectCandidate(at: index)
                return true
            }
        }
        
        // Enter -> select first on current page
        if keyCode == 36 || keyCode == 76 { // Return / Numpad Enter
            let index = currentPage * pageSize
            if index < candidates.count {
                selectCandidate(at: index)
                return true
            }
        }
        
        // Arrow Down / Tab -> next page
        if keyCode == 125 || keyCode == 48 { // Down arrow / Tab
            if (currentPage + 1) * pageSize < candidates.count {
                currentPage += 1
                updateContent()
            }
            return true
        }
        
        // Arrow Up -> previous page
        if keyCode == 126 { // Up arrow
            if currentPage > 0 {
                currentPage -= 1
                updateContent()
            }
            return true
        }
        
        // ] -> next page
        if keyCode == 30 { // ]
            if (currentPage + 1) * pageSize < candidates.count {
                currentPage += 1
                updateContent()
            }
            return true
        }
        
        // [ -> previous page
        if keyCode == 33 { // [
            if currentPage > 0 {
                currentPage -= 1
                updateContent()
            }
            return true
        }
        
        // Any other key -> dismiss and don't consume
        dismiss()
        return false
    }
    
    // MARK: - Private
    
    private func selectCandidate(at index: Int) {
        guard index < candidates.count else { return }
        let entry = candidates[index]
        let callback = onSelect
        // Fire onSelect BEFORE dismiss to preserve hanjaKey state
        callback?(entry)
        // Dismiss without calling onDismiss (selection already handled cleanup)
        dismissWithoutCallback()
    }
    
    /// Hide the window without triggering onDismiss callback
    /// Used after selection, where the onSelect callback already handles state cleanup
    private func dismissWithoutCallback() {
        window?.orderOut(nil)
        candidates = []
        onSelect = nil
        onDismiss = nil
        currentPage = 0
    }
    
    private func updateContent() {
        guard let window = window else { return }
        
        let startIndex = currentPage * pageSize
        let endIndex = min(startIndex + pageSize, candidates.count)
        let pageEntries = Array(candidates[startIndex..<endIndex])
        let totalPages = (candidates.count + pageSize - 1) / pageSize
        
        let view = HanjaCandidateView(
            entries: pageEntries,
            startNumber: 1,
            currentPage: currentPage + 1,
            totalPages: totalPages,
            onSelect: { [weak self] index in
                let globalIndex = (self?.currentPage ?? 0) * (self?.pageSize ?? 9) + index
                self?.selectCandidate(at: globalIndex)
            }
        )
        
        let hostView = NSHostingView(rootView: view)
        hostView.frame.size = hostView.fittingSize
        
        window.contentView = hostView
        window.setContentSize(hostView.fittingSize)
    }
    
    private func positionWindow(near cursorRect: NSRect) {
        guard let window = window else { return }
        
        // Find the screen containing the cursor position (supports multi-monitor)
        let cursorPoint = NSPoint(x: cursorRect.origin.x, y: cursorRect.origin.y)
        let screen = NSScreen.screens.first { $0.frame.contains(cursorPoint) } ?? NSScreen.main
        guard let activeScreen = screen else { return }
        
        let windowSize = window.frame.size
        var origin = NSPoint(
            x: cursorRect.origin.x,
            y: cursorRect.origin.y - windowSize.height - 4
        )
        
        // Ensure window stays on screen
        let screenFrame = activeScreen.visibleFrame
        if origin.x + windowSize.width > screenFrame.maxX {
            origin.x = screenFrame.maxX - windowSize.width
        }
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX
        }
        if origin.y < screenFrame.minY {
            origin.y = cursorRect.maxY + 4
        }
        
        window.setFrameOrigin(origin)
    }
}

// MARK: - SwiftUI Candidate View

private struct HanjaCandidateView: View {
    let entries: [HanjaEntry]
    let startNumber: Int
    let currentPage: Int
    let totalPages: Int
    let onSelect: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                HanjaCandidateRow(
                    number: startNumber + index,
                    entry: entry,
                    onSelect: { onSelect(index) }
                )
                
                if index < entries.count - 1 {
                    Divider()
                        .opacity(0.15)
                        .padding(.horizontal, 8)
                }
            }
            
            if totalPages > 1 {
                Divider()
                    .opacity(0.2)
                
                HStack {
                    Spacer()
                    Text("\(currentPage) / \(totalPages)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Text("▲▼ 페이지 이동")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.quaternary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 4)
        .frame(minWidth: 240)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct HanjaCandidateRow: View {
    let number: Int
    let entry: HanjaEntry
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Number badge
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.primary.opacity(0.06)))
                
                // Hanja character
                Text(entry.hanja)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, alignment: .center)
                
                // Meaning
                Text(entry.meaning)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Hangul key
                Text(entry.hangul)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? AnyShapeStyle(.primary.opacity(0.06)) : AnyShapeStyle(Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
