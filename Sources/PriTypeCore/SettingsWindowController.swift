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
    @State private var autoUpdateCheckEnabled = ConfigurationManager.shared.autoUpdateCheckEnabled
    
    // Update check state
    @State private var updateStatus: UpdateStatus = .idle
    
    private enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)  // version string
        case error
    }
    
    private let keyboardOptions = [
        ("2", L10n.keyboard.twoSet),
        ("3", L10n.keyboard.threeSet390),
        ("2y", L10n.keyboard.twoSetOld),
        ("3y", L10n.keyboard.threeSetOld)
    ]
    
    var body: some View {
        ZStack {
            // Single translucent background — no additional GlassEffectContainer
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // ── Header (fixed, not scrollable) ──
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // App icon badge — only glass element in header
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
                    .padding(.bottom, 16)
                    .padding(.horizontal, 28)
                    
                    // Thin separator
                    Divider()
                        .opacity(0.3)
                        .padding(.horizontal, 20)
                }
                .zIndex(1) // Header stays above scroll content
                
                // ── Scrollable Content (clipped to prevent bleed-through) ──
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // Keyboard Layout Section
                        SettingsSection(
                            title: L10n.keyboard.title,
                            icon: "keyboard"
                        ) {
                            VStack(spacing: 2) {
                                ForEach(keyboardOptions, id: \.0) { option in
                                    SelectionRow(
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
                        SettingsSection(
                            title: L10n.toggle.title,
                            icon: "globe"
                        ) {
                            VStack(spacing: 2) {
                                ForEach(ToggleKey.allCases, id: \.self) { key in
                                    SelectionRow(
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
                        SettingsSection(
                            title: L10n.textInput.title,
                            icon: "text.cursor"
                        ) {
                            VStack(spacing: 0) {
                                SettingsToggleRow(
                                    title: L10n.textInput.autoCapitalize,
                                    icon: "textformat.size.larger",
                                    isOn: $autoCapitalizeEnabled
                                )
                                Divider()
                                    .opacity(0.2)
                                    .padding(.horizontal, 12)
                                SettingsToggleRow(
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
                        
                        // Update Section
                        SettingsSection(
                            title: L10n.update.title,
                            icon: "arrow.triangle.2.circlepath"
                        ) {
                            VStack(spacing: 0) {
                                SettingsToggleRow(
                                    title: L10n.update.autoCheck,
                                    icon: "clock.arrow.2.circlepath",
                                    isOn: $autoUpdateCheckEnabled
                                )
                                
                                Divider()
                                    .opacity(0.2)
                                    .padding(.horizontal, 12)
                                
                                // Manual check button + status
                                HStack(spacing: 10) {
                                    Button(action: { checkForUpdates() }) {
                                        HStack(spacing: 6) {
                                            if updateStatus == .checking {
                                                ProgressView()
                                                    .controlSize(.small)
                                            } else {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                            Text(L10n.update.checkButton)
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(.primary.opacity(0.06))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(updateStatus == .checking)
                                    
                                    Spacer()
                                    
                                    // Status indicator
                                    updateStatusView
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                            }
                        }
                        .onChange(of: autoUpdateCheckEnabled) { _, newValue in
                            ConfigurationManager.shared.autoUpdateCheckEnabled = newValue
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 28)
                }
                .clipped() // Prevent content from bleeding into header
                
                // ── Footer ──
                HStack {
                    Spacer()
                    Text("v\(AboutInfo.version)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: PriTypeConfig.settingsWindowWidth, height: PriTypeConfig.settingsWindowHeight)
        .onAppear {
            selectedKeyboard = ConfigurationManager.shared.keyboardId
            selectedToggleKey = ConfigurationManager.shared.toggleKey
            autoCapitalizeEnabled = ConfigurationManager.shared.autoCapitalizeEnabled
            doubleSpacePeriodEnabled = ConfigurationManager.shared.doubleSpacePeriodEnabled
            autoUpdateCheckEnabled = ConfigurationManager.shared.autoUpdateCheckEnabled
        }
    }
    
    // MARK: - Update Status View
    
    @ViewBuilder
    private var updateStatusView: some View {
        switch updateStatus {
        case .idle:
            EmptyView()
        case .checking:
            Text(L10n.update.checking)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text(L10n.update.upToDate)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        case .available(let version):
            Button(action: { openLatestRelease() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.cyan)
                    Text(String(format: L10n.update.available, version))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan)
                }
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        case .error:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text(L10n.update.error)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
    }
    
    // MARK: - Actions
    
    private func checkForUpdates() {
        withAnimation { updateStatus = .checking }
        
        Task {
            let result = await UpdateChecker.shared.checkForUpdates()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    switch result {
                    case .updateAvailable(let info):
                        updateStatus = .available(info.version)
                    case .upToDate:
                        updateStatus = .upToDate
                    case .skipped:
                        updateStatus = .upToDate
                    case .error:
                        updateStatus = .error
                    }
                }
                
                // Auto-dismiss success/error after 8 seconds
                if updateStatus == .upToDate || updateStatus == .error {
                    Task {
                        try? await Task.sleep(for: .seconds(8))
                        await MainActor.run {
                            withAnimation { updateStatus = .idle }
                        }
                    }
                }
            }
        }
    }
    
    private func openLatestRelease() {
        let url = URL(string: "https://github.com/Meapri/PriType-Swift/releases/latest")!
        NSWorkspace.shared.open(url)
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

// MARK: - Settings Components (Minimal Glass)

/// A section with a label and a single glass card for its content.
/// Only ONE `.glassEffect` per section — on the card itself.
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header — plain text, no glass
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            
            // Glass card — single glass layer for the entire section content
            VStack {
                content
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A selection row — uses solid fill instead of nested glass
struct SelectionRow: View {
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
                // Selection indicator — simple circle, no glass
                Circle()
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.primary.opacity(0.10)))
                    .frame(width: 7, height: 7)
                    .padding(6)
                
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
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? Color.primary.opacity(0.06)
                          : isHovering ? Color.primary.opacity(0.03) : Color.clear)
            )
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

/// A toggle row — icon uses plain background instead of glass
struct SettingsToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.primary.opacity(0.06))
                )
            
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
