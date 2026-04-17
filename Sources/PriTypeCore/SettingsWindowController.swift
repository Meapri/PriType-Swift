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
        
        // Create window with Liquid Glass style
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "PriType 설정"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.backgroundColor = .clear
        
        // Set proper size
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

// MARK: - Visual Effect View (System Blur)

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

// MARK: - Liquid Glass Design System

/// Namespace for Liquid Glass design tokens
private enum LiquidGlass {
    // Corner radii
    static let tileRadius: CGFloat = 16
    static let rowRadius: CGFloat = 10
    static let badgeRadius: CGFloat = 8
    
    // Specular highlight colors
    static let specularTop = Color.white.opacity(0.35)
    static let specularBottom = Color.white.opacity(0.0)
    static let borderTop = Color.white.opacity(0.25)
    static let borderBottom = Color.white.opacity(0.06)
    
    // Glass fill
    static let glassFill = Color.white.opacity(0.04)
    static let glassHover = Color.white.opacity(0.07)
    static let glassSelected = Color.white.opacity(0.12)
    
    // Accent
    static let accent = Color(red: 0.35, green: 0.58, blue: 1.0)
    static let accentGlow = Color(red: 0.35, green: 0.58, blue: 1.0).opacity(0.25)
    
    // Text
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
    
    // Shadows
    static let dropShadow = Color.black.opacity(0.25)
    static let innerGlow = Color.white.opacity(0.05)
}

// MARK: - Specular Highlight Overlay

/// Simulates the Liquid Glass specular highlight — a soft light refraction at the top edge
private struct SpecularHighlight: View {
    let cornerRadius: CGFloat
    
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [LiquidGlass.specularTop, LiquidGlass.specularBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius
                )
            )
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Glass Tile Modifier

/// Applies the Liquid Glass material to any view — frosted blur, specular edge, border gradient
private struct GlassMaterialModifier: ViewModifier {
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Layer 1: System vibrancy blur
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .opacity(0.55)
                    
                    // Layer 2: Subtle tinted fill
                    LiquidGlass.glassFill
                    
                    // Layer 3: Specular highlight
                    SpecularHighlight(cornerRadius: cornerRadius)
                        .opacity(0.5)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                // Border gradient — bright top edge, fading to transparent
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [LiquidGlass.borderTop, LiquidGlass.borderBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: LiquidGlass.dropShadow, radius: 12, x: 0, y: 6)
    }
}

extension View {
    fileprivate func liquidGlass(cornerRadius: CGFloat = LiquidGlass.tileRadius) -> some View {
        modifier(GlassMaterialModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - SwiftUI Settings View

struct SettingsView: View {
    @State private var selectedKeyboard = ConfigurationManager.shared.keyboardId
    @State private var selectedToggleKey = ConfigurationManager.shared.toggleKey
    @State private var autoCapitalizeEnabled = ConfigurationManager.shared.autoCapitalizeEnabled
    @State private var doubleSpacePeriodEnabled = ConfigurationManager.shared.doubleSpacePeriodEnabled
    @State private var appearAnimation = false
    
    private let keyboardOptions = [
        ("2", L10n.keyboard.twoSet),
        ("3", L10n.keyboard.threeSet390),
        ("2y", L10n.keyboard.twoSetOld),
        ("3y", L10n.keyboard.threeSetOld)
    ]
    
    var body: some View {
        ZStack {
            // Base: Deep system blur
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            // Ambient gradient layer — subtle chromatic warmth
            ZStack {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.25, green: 0.45, blue: 0.85).opacity(0.12),
                        Color.clear
                    ]),
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 400
                )
                
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.6, green: 0.3, blue: 0.8).opacity(0.06),
                        Color.clear
                    ]),
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 350
                )
            }
            .edgesIgnoringSafeArea(.all)
            
            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Header
                headerView
                    .padding(.top, 12)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                
                // Scrollable tiles
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Keyboard Layout
                        keyboardTile
                            .offset(y: appearAnimation ? 0 : 12)
                            .opacity(appearAnimation ? 1 : 0)
                        
                        // Toggle Key
                        toggleKeyTile
                            .offset(y: appearAnimation ? 0 : 12)
                            .opacity(appearAnimation ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05), value: appearAnimation)
                        
                        // Text Input Options
                        textInputTile
                            .offset(y: appearAnimation ? 0 : 12)
                            .opacity(appearAnimation ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.10), value: appearAnimation)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)
                }
                
                // Footer
                footerView
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: PriTypeConfig.settingsWindowWidth, height: PriTypeConfig.settingsWindowHeight)
        .preferredColorScheme(.dark)
        .onAppear {
            selectedKeyboard = ConfigurationManager.shared.keyboardId
            selectedToggleKey = ConfigurationManager.shared.toggleKey
            autoCapitalizeEnabled = ConfigurationManager.shared.autoCapitalizeEnabled
            doubleSpacePeriodEnabled = ConfigurationManager.shared.doubleSpacePeriodEnabled
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                appearAnimation = true
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // App icon glyph
            Image(systemName: "character.ko")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [LiquidGlass.accent, LiquidGlass.accent.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: LiquidGlass.accentGlow, radius: 8, x: 0, y: 2)
            
            Text("PriType")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(LiquidGlass.primaryText)
            
            Text("Settings")
                .font(.system(size: 26, weight: .light, design: .rounded))
                .foregroundColor(LiquidGlass.secondaryText)
            
            Spacer()
        }
    }
    
    // MARK: - Keyboard Layout Tile
    
    private var keyboardTile: some View {
        LiquidGlassTile(
            icon: "keyboard",
            title: L10n.keyboard.title
        ) {
            VStack(spacing: 4) {
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
    }
    
    // MARK: - Toggle Key Tile
    
    private var toggleKeyTile: some View {
        LiquidGlassTile(
            icon: "command",
            title: L10n.toggle.title
        ) {
            VStack(spacing: 4) {
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
    }
    
    // MARK: - Text Input Options Tile
    
    private var textInputTile: some View {
        LiquidGlassTile(
            icon: "textformat",
            title: L10n.textInput.title
        ) {
            VStack(spacing: 0) {
                LiquidToggleRow(
                    title: L10n.textInput.autoCapitalize,
                    subtitle: "영문 입력 시 문장 첫 글자 자동 대문자",
                    isOn: $autoCapitalizeEnabled
                )
                
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.horizontal, 4)
                
                LiquidToggleRow(
                    title: L10n.textInput.doubleSpacePeriod,
                    subtitle: "스페이스바 두 번 탭으로 마침표 입력",
                    isOn: $doubleSpacePeriodEnabled
                )
            }
        }
        .onChange(of: autoCapitalizeEnabled) { _, newValue in
            ConfigurationManager.shared.autoCapitalizeEnabled = newValue
        }
        .onChange(of: doubleSpacePeriodEnabled) { _, newValue in
            ConfigurationManager.shared.doubleSpacePeriodEnabled = newValue
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.fill")
                .font(.system(size: 9))
                .foregroundStyle(
                    LinearGradient(
                        colors: [LiquidGlass.accent.opacity(0.5), LiquidGlass.accent.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Text("Liquid Glass")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(LiquidGlass.tertiaryText)
            
            Spacer()
            
            Text("v1.0")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(LiquidGlass.tertiaryText)
        }
    }
}

// MARK: - Liquid Glass Tile

/// A section tile with Liquid Glass material, icon, and title
struct LiquidGlassTile<Content: View>: View {
    let icon: String
    let title: String
    let content: Content
    
    init(icon: String, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with icon
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LiquidGlass.accent)
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(LiquidGlass.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.leading, 4)
            
            // Glass content card
            VStack {
                content
            }
            .padding(6)
            .liquidGlass()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Liquid Selection Row

struct LiquidSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            ZStack {
                Circle()
                    .fill(isSelected ? LiquidGlass.accent : Color.white.opacity(0.06))
                    .frame(width: 20, height: 20)
                
                if isSelected {
                    Circle()
                        .fill(LiquidGlass.accent)
                        .frame(width: 20, height: 20)
                        .shadow(color: LiquidGlass.accentGlow, radius: 6, x: 0, y: 0)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 20, height: 20)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundColor(isSelected ? LiquidGlass.primaryText : LiquidGlass.secondaryText)
            
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: LiquidGlass.rowRadius, style: .continuous)
                .fill(
                    isSelected
                        ? LiquidGlass.glassSelected
                        : (isHovering ? LiquidGlass.glassHover : Color.clear)
                )
        )
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: LiquidGlass.rowRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [LiquidGlass.accent.opacity(0.4), LiquidGlass.accent.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                }
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: LiquidGlass.rowRadius, style: .continuous))
        .scaleEffect(isHovering && !isSelected ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovering)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
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

// MARK: - Liquid Toggle Row

struct LiquidToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(LiquidGlass.primaryText)
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(LiquidGlass.tertiaryText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(LiquidGlass.accent)
                .scaleEffect(0.85)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: LiquidGlass.rowRadius, style: .continuous)
                .fill(isHovering ? LiquidGlass.glassHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hover
            }
        }
    }
}
