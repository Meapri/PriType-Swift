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
        newWindow.titlebarSeparatorStyle = .none
        
        // Translucent glass window — desktop shows through with blur
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        
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
            // Translucent glass window background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            GlassEffectContainer {
                VStack(spacing: 0) {
                    // ── Header ──
                    HStack(spacing: 12) {
                        // App icon badge
                        Text("ㅎ")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .glassEffect(.regular, in: .rect(cornerRadius: 16))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PriType")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(L10n.settings.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                    .padding(.horizontal, 28)
                    
                    // Thin separator
                    Divider()
                        .opacity(0.3)
                        .padding(.horizontal, 20)
                    
                    // ── Scrollable Content ──
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            
                            // Keyboard Layout Section
                            LiquidGlassSection(
                                title: L10n.keyboard.title,
                                icon: "keyboard"
                            ) {
                                VStack(spacing: 2) {
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
                            
                            // Toggle Key Section
                            LiquidGlassSection(
                                title: L10n.toggle.title,
                                icon: "globe"
                            ) {
                                VStack(spacing: 2) {
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
                            
                            // Text Input Options Section
                            LiquidGlassSection(
                                title: L10n.textInput.title,
                                icon: "text.cursor"
                            ) {
                                VStack(spacing: 0) {
                                    LiquidToggleRow(
                                        title: L10n.textInput.autoCapitalize,
                                        icon: "textformat.size.larger",
                                        isOn: $autoCapitalizeEnabled
                                    )
                                    Divider()
                                        .opacity(0.3)
                                        .padding(.horizontal, 12)
                                    LiquidToggleRow(
                                        title: L10n.textInput.doubleSpacePeriod,
                                        icon: "period",
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
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 24)
                    
                    // ── Footer ──
                    HStack {
                        Spacer()
                        Text("v\(AboutInfo.version)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(width: PriTypeConfig.settingsWindowWidth, height: PriTypeConfig.settingsWindowHeight)
        .onAppear {
            selectedKeyboard = ConfigurationManager.shared.keyboardId
            selectedToggleKey = ConfigurationManager.shared.toggleKey
            autoCapitalizeEnabled = ConfigurationManager.shared.autoCapitalizeEnabled
            doubleSpacePeriodEnabled = ConfigurationManager.shared.doubleSpacePeriodEnabled
        }
    }
}

// MARK: - Visual Effect View (Window Background)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Conditional Glass Modifier

/// Applies `.glassEffect()` only when `isActive` is true.
/// Works around the limitation that GlassEffect styles cannot be used in ternary expressions.
struct ConditionalGlass<S: InsettableShape>: ViewModifier {
    let isActive: Bool
    let shape: S
    
    func body(content: Content) -> some View {
        if isActive {
            content.glassEffect(.regular, in: shape)
        } else {
            content
        }
    }
}

// MARK: - Liquid Glass Components

/// A section card with an icon, title label, and native Liquid Glass content area
struct LiquidGlassSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header with icon
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            
            // Glass card
            VStack {
                content
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A selection row with polished hover and selected states
struct LiquidSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                action()
            }
        }) {
            HStack(spacing: 10) {
                // Selection indicator
                Circle()
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .frame(width: 7, height: 7)
                    .padding(6)
                    .modifier(ConditionalGlass(isActive: isSelected, shape: .circle))
                
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.cyan)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background {
                if isHovering && !isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.primary.opacity(0.04))
                }
            }
            .modifier(ConditionalGlass(isActive: isSelected, shape: .rect(cornerRadius: 10)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .onHover { hover in
            isHovering = hover
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A toggle row with an icon for on/off settings
struct LiquidToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .glassEffect(.regular, in: .circle)
            
            Text(title)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}
