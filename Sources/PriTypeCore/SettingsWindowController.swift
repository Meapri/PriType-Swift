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

// MARK: - Animated Liquid Background

struct AnimatedLiquidBackground: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Base dark background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Moving liquid blobs
            Circle()
                .fill(Color(red: 0.2, green: 0.4, blue: 0.9).opacity(0.5))
                .frame(width: 350, height: 350)
                .offset(x: isAnimating ? -100 : 150, y: isAnimating ? -150 : 100)
                .blur(radius: 90)
            
            Circle()
                .fill(Color(red: 0.6, green: 0.2, blue: 0.8).opacity(0.5))
                .frame(width: 400, height: 400)
                .offset(x: isAnimating ? 150 : -100, y: isAnimating ? 150 : -50)
                .blur(radius: 100)
                
            Circle()
                .fill(Color(red: 0.1, green: 0.7, blue: 0.8).opacity(0.4))
                .frame(width: 300, height: 300)
                .offset(x: isAnimating ? 50 : -150, y: isAnimating ? 50 : 200)
                .blur(radius: 80)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - SwiftUI Settings View

struct SettingsView: View {
    @State private var selectedKeyboard = ConfigurationManager.shared.keyboardId
    @State private var selectedToggleKey = ConfigurationManager.shared.toggleKey
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
            // Background
            AnimatedLiquidBackground()
                .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 20) {
                // Liquid Header
                HStack {
                    Text("PriType")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .white.opacity(0.3), radius: 10, x: 0, y: 0)
                    
                    Text("Settings")
                        .font(.system(size: 36, weight: .ultraLight, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
                .padding(.top, 15)
                .padding(.horizontal, 10)
                
                // Scrollable Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        
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
                                LiquidToggleRow(title: L10n.textInput.autoCapitalize, isOn: $autoCapitalizeEnabled)
                                Divider().background(Color.white.opacity(0.2))
                                LiquidToggleRow(title: L10n.textInput.doubleSpacePeriod, isOn: $doubleSpacePeriodEnabled)
                            }
                        }
                        .onChange(of: autoCapitalizeEnabled) { _, newValue in
                            ConfigurationManager.shared.autoCapitalizeEnabled = newValue
                        }
                        .onChange(of: doubleSpacePeriodEnabled) { _, newValue in
                            ConfigurationManager.shared.doubleSpacePeriodEnabled = newValue
                        }
                    }
                    .padding(.bottom, 20)
                    .padding(.horizontal, 5)
                }
                
                // Footer
                HStack {
                    Image(systemName: "drop.fill")
                        .font(.caption)
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                        )
                    Text("Designed for macOS Sequoia")
                        .font(.caption2)
                        .fontWeight(.medium)
                    Spacer()
                    Text("v1.0 Liquid")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .padding(25)
        }
        .frame(width: PriTypeConfig.settingsWindowWidth, height: PriTypeConfig.settingsWindowHeight)
        .preferredColorScheme(.dark)
        .onAppear {
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
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .padding(.leading, 5)
            
            VStack {
                content
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.1), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 8)
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
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                action()
            }
        }) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .cyan.opacity(0.6), radius: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                        
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    } else if isHovering {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering && !isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { hover in
            isHovering = hover
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

struct LiquidToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.cyan)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
}
