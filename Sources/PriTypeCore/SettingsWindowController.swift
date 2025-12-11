import Cocoa
import SwiftUI

/// Manages the settings window for the input method
@MainActor
public class SettingsWindowController: NSObject {
    
    public static let shared = SettingsWindowController()
    
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
        newWindow.setContentSize(NSSize(width: PriTypeConfig.settingsWindowWidth, height: PriTypeConfig.settingsWindowHeight))
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

struct SettingsView: View {
    @State private var selectedKeyboard = ConfigurationManager.shared.keyboardId
    @State private var selectedToggleKey = ConfigurationManager.shared.toggleKey
    @State private var hoverZone: String? = nil
    @State private var autoCapitalizeEnabled = ConfigurationManager.shared.autoCapitalizeEnabled
    @State private var doubleSpacePeriodEnabled = ConfigurationManager.shared.doubleSpacePeriodEnabled
    
    private let keyboardOptions = [
        ("2", L10n.keyboard.twoSet),
        ("3", L10n.keyboard.threeSet390),
        ("2y", L10n.keyboard.twoSetOld),
        ("3y", L10n.keyboard.threeSetOld)
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
            
            VStack(alignment: .leading, spacing: 20) {
                // Liquid Header (Fixed)
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
                .padding(.top, 10)
                .padding(.horizontal, 5)
                
                // Scrollable Content Stack
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Keyboard Layout Tile
                        GlassTile(title: L10n.keyboard.title) {
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
                        .onChange(of: selectedKeyboard) { _, newValue in
                            ConfigurationManager.shared.keyboardId = newValue
                        }
                        
                        // Toggle Key Tile
                        GlassTile(title: L10n.toggle.title) {
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
                        .onChange(of: selectedToggleKey) { _, newValue in
                            ConfigurationManager.shared.toggleKey = newValue
                        }
                        
                        // Text Input Options Tile
                        GlassTile(title: L10n.textInput.title) {
                            VStack(spacing: 12) {
                                // Auto-Capitalize Toggle
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.textInput.autoCapitalize)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $autoCapitalizeEnabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .scaleEffect(0.8)
                                }
                                
                                Divider().background(Color.white.opacity(0.1))
                                
                                // Double-Space Period Toggle
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.textInput.doubleSpacePeriod)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $doubleSpacePeriodEnabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .onChange(of: autoCapitalizeEnabled) { _, newValue in
                            ConfigurationManager.shared.autoCapitalizeEnabled = newValue
                        }
                        .onChange(of: doubleSpacePeriodEnabled) { _, newValue in
                            ConfigurationManager.shared.doubleSpacePeriodEnabled = newValue
                        }
                    }
                    .padding(.bottom, 10) // Padding inside scrollview
                }
                
                // Footer (Fixed)
                HStack {
                    Image(systemName: "drop.fill") // Liquid icon
                        .font(.caption)
                    Text("Designed for macOS Sequoia")
                        .font(.caption2)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("v1.0 Liquid")
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 10)
                .padding(.bottom, 5)
            }
            .padding(30)
        }
        .frame(width: PriTypeConfig.settingsWindowWidth, height: PriTypeConfig.settingsWindowHeight)
        .preferredColorScheme(.dark)
        .onAppear {
            // Sync state with ConfigurationManager on appear
            // This handles cases where settings were changed externally
            selectedKeyboard = ConfigurationManager.shared.keyboardId
            selectedToggleKey = ConfigurationManager.shared.toggleKey
            autoCapitalizeEnabled = ConfigurationManager.shared.autoCapitalizeEnabled
            doubleSpacePeriodEnabled = ConfigurationManager.shared.doubleSpacePeriodEnabled
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(isSelected ? "현재 선택됨" : "선택하려면 탭하세요")
    }
}
