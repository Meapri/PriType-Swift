import Cocoa
import SwiftUI

/// Manages the settings window for the input method
public class SettingsWindowController: NSObject, @unchecked Sendable {
    
    nonisolated(unsafe) public static let shared = SettingsWindowController()
    
    private var window: NSWindow?
    
    private override init() {
        super.init()
    }
    
    @MainActor
    public func showSettings() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create SwiftUI settings view
        let settingsView = SettingsView()
        
        // Create hosting controller
        let hostingController = NSHostingController(rootView: settingsView)
        
        // Create window with "liquid" style (full size content, transparent titlebar)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "PriType 설정"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.backgroundColor = .clear
        
        // Set proper size to avoid truncation
        newWindow.setContentSize(NSSize(width: 400, height: 450))
        newWindow.center()
        newWindow.delegate = self
        
        self.window = newWindow
        
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor
    public func closeSettings() {
        window?.close()
        window = nil
    }
}

extension SettingsWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - Visual Effect View (Glassmorphism)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - SwiftUI Settings View

// MARK: - SwiftUI Settings View

struct SettingsView: View {
    @State private var selectedKeyboard = ConfigurationManager.shared.keyboardId
    @State private var selectedToggleKey = ConfigurationManager.shared.toggleKey
    @State private var hoverZone: String? = nil
    @State private var isABCEnabled = InputSourceManager.shared.isABCEnabled() || InputSourceManager.shared.isUSEnabled()
    @State private var showDisableAlert = false
    
    private let keyboardOptions = [
        ("2", "두벌식 표준"),
        ("3", "세벌식 390"),
        ("2y", "두벌식 옛한글"),
        ("3y", "세벌식 옛한글")
    ]
    
    var body: some View {
        ZStack {
            // Base Layer: Deep Liquid Glass
            VisualEffectView(material: .headerView, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            // Chromatic Liquid Gradient (Subtle background shift)
            RadialGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.1), Color.clear]),
                center: .topLeading,
                startRadius: 0,
                endRadius: 600
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 30) {
                // Liquid Header
                HStack {
                    Text("PriType")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("Settings")
                        .font(.system(size: 34, weight: .thin, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.top, 25)
                .padding(.horizontal, 5)
                
                // Content Stack (Floating Glass Tiles)
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Keyboard Layout Tile
                    GlassTile(title: "자판 배열") {
                        VStack(spacing: 8) {
                            ForEach(keyboardOptions, id: \.0) { option in
                                LiquidSelectionRow(
                                    title: option.1,
                                    isSelected: selectedKeyboard == option.0,
                                    action: { selectedKeyboard = option.0 }
                                )
                            }
                        }
                    }
                    .onChange(of: selectedKeyboard) { newValue in
                        ConfigurationManager.shared.keyboardId = newValue
                    }
                    
                    // Toggle Key Tile
                    GlassTile(title: "한영 전환 키") {
                        VStack(spacing: 8) {
                            ForEach(ToggleKey.allCases, id: \.self) { key in
                                LiquidSelectionRow(
                                    title: key.displayName,
                                    isSelected: selectedToggleKey == key,
                                    action: { selectedToggleKey = key }
                                )
                            }
                        }
                    }
                    .onChange(of: selectedToggleKey) { newValue in
                        ConfigurationManager.shared.toggleKey = newValue
                    }
                    
                    // Input Source Management Tile
                    GlassTile(title: "입력 소스 관리") {
                        VStack(spacing: 12) {
                            // ABC Keyboard Toggle
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("기본 영어 입력기 (ABC)")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                    Text(isABCEnabled ? "활성화됨" : "비활성화됨")
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundColor(isABCEnabled ? .green.opacity(0.8) : .orange.opacity(0.8))
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $isABCEnabled)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                    .scaleEffect(0.8)
                            }
                            .padding(.vertical, 4)
                            
                            // Info Text
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                Text("비활성화하면 PriType만 사용됩니다")
                                    .font(.system(size: 11, design: .rounded))
                            }
                            .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .onChange(of: isABCEnabled) { newValue in
                        handleABCToggle(enabled: newValue)
                    }
                }
                
                Spacer()
                
                // Footer
                HStack {
                    Image(systemName: "drop.fill") // Liquid icon
                        .font(.caption)
                    Text("Designed for macOS 26")
                        .font(.caption2)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("v1.0 Liquid")
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
            .padding(30)
        }
        .frame(width: 420, height: 700)
        .preferredColorScheme(.dark)
        .alert("ABC 입력기 비활성화", isPresented: $showDisableAlert) {
            Button("취소", role: .cancel) {
                isABCEnabled = true
            }
            Button("비활성화", role: .destructive) {
                _ = InputSourceManager.shared.disableABC()
                // Also try to disable US
                _ = InputSourceManager.shared.disableUS()
            }
        } message: {
            Text("기본 영어 입력기를 비활성화하면 PriType 영어 모드만 사용됩니다.\n\n계속하시겠습니까?")
        }
    }
    
    // MARK: - Private Methods
    
    private func handleABCToggle(enabled: Bool) {
        if enabled {
            // Re-enable ABC
            _ = InputSourceManager.shared.enableABC()
        } else {
            // Show confirmation alert before disabling
            showDisableAlert = true
        }
    }
}

// MARK: - Liquid Design Components

struct GlassTile<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .padding(.leading, 5)
            
            VStack {
                content
            }
            .padding(12)
            .background(
                ZStack {
                    Color.white.opacity(0.03)
                    VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                        .opacity(0.3)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)) // Squircle
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
    }
}

struct LiquidSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded)) // Fixed weight to prevent flickering
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.5), radius: 5)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            ZStack {
                if isSelected {
                    // Selected: Liquid Blue Glow
                    Color.blue.opacity(0.3)
                    VisualEffectView(material: .selection, blendingMode: .withinWindow)
                } else if isHovering {
                    // Hover: Shallow Water
                    Color.white.opacity(0.05)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(isHovering && !isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                action()
            }
        }
        .onHover { hover in
            isHovering = hover
        }
    }
}
