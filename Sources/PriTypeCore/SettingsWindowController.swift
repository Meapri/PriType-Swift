import Cocoa
import SwiftUI
import Carbon

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
        
        // Liquid Glass window background
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        
        // Wrap content in NSGlassEffectView for proper Liquid Glass rendering
        let glassView = NSGlassEffectView()
        glassView.cornerRadius = 14
        glassView.contentView = hostingController.view
        newWindow.contentView = glassView
        
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
    @State private var toggleKeyBinding = ConfigurationManager.shared.toggleKeyBinding
    @State private var hanjaKeyBinding = ConfigurationManager.shared.hanjaKeyBinding
    @State private var autoCapitalizeEnabled = ConfigurationManager.shared.autoCapitalizeEnabled
    @State private var doubleSpacePeriodEnabled = ConfigurationManager.shared.doubleSpacePeriodEnabled
    @State private var autoUpdateCheckEnabled = ConfigurationManager.shared.autoUpdateCheckEnabled
    @State private var isAccessibilityGranted = false
    @State private var removeABCStatus: RemoveABCStatus = .idle
    @State private var hasKeyConflict = false
    
    // Update check state
    @State private var updateStatus: UpdateStatus = .idle
    
    private enum UpdateStatus: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)  // version string
        case error
    }
    
    private enum RemoveABCStatus: Equatable {
        case idle
        case success
        case error
    }
    
    private let keyboardOptions = [
        ("2", L10n.keyboard.twoSet),
        ("3", L10n.keyboard.threeSet390),
        ("2y", L10n.keyboard.twoSetOld),
        ("3y", L10n.keyboard.threeSetOld)
    ]
    
    var body: some View {
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
                        
                        // Key Binding Section (replaces legacy Toggle Key preset)
                        SettingsSection(
                            title: L10n.keyBinding.title,
                            icon: "command"
                        ) {
                            VStack(spacing: 0) {
                                KeyRecorderRow(
                                    label: L10n.keyBinding.toggleKey,
                                    icon: "globe",
                                    binding: $toggleKeyBinding,
                                    conflictBinding: hanjaKeyBinding,
                                    hasConflict: $hasKeyConflict
                                )
                                
                                Divider()
                                    .opacity(0.2)
                                    .padding(.horizontal, 12)
                                
                                KeyRecorderRow(
                                    label: L10n.keyBinding.hanjaKey,
                                    icon: "character.book.closed",
                                    binding: $hanjaKeyBinding,
                                    conflictBinding: toggleKeyBinding,
                                    hasConflict: $hasKeyConflict
                                )
                                
                                if hasKeyConflict {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange)
                                        Text(L10n.keyBinding.conflict)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .onChange(of: toggleKeyBinding) { _, newValue in
                            if newValue == hanjaKeyBinding {
                                withAnimation(.easeInOut(duration: 0.2)) { hasKeyConflict = true }
                                toggleKeyBinding = ConfigurationManager.shared.toggleKeyBinding
                                return
                            }
                            ConfigurationManager.shared.toggleKeyBinding = newValue
                            withAnimation(.easeInOut(duration: 0.2)) { hasKeyConflict = false }
                        }
                        .onChange(of: hanjaKeyBinding) { _, newValue in
                            if newValue == toggleKeyBinding {
                                withAnimation(.easeInOut(duration: 0.2)) { hasKeyConflict = true }
                                hanjaKeyBinding = ConfigurationManager.shared.hanjaKeyBinding
                                return
                            }
                            ConfigurationManager.shared.hanjaKeyBinding = newValue
                            withAnimation(.easeInOut(duration: 0.2)) { hasKeyConflict = false }
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
                                    icon: "ellipsis.rectangle",
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
                        
                        // System Section
                        SettingsSection(
                            title: L10n.system.title,
                            icon: "gearshape.2"
                        ) {
                            VStack(spacing: 0) {
                                // Accessibility
                                HStack(spacing: 10) {
                                    Image(systemName: "hand.raised")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(.primary.opacity(0.06)))
                                    
                                    Text(L10n.system.accessibility)
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                    
                                    if isAccessibilityGranted {
                                        Text(L10n.system.accessibilityGranted)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.green)
                                    } else {
                                        Button(action: { requestAccessibility() }) {
                                            Text(L10n.system.accessibilityRequest)
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Capsule().fill(.primary.opacity(0.1)))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                
                                Divider()
                                    .opacity(0.2)
                                    .padding(.horizontal, 12)
                                
                                // Remove ABC Keyboard
                                HStack(spacing: 10) {
                                    Image(systemName: "minus.square")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(.primary.opacity(0.06)))
                                    
                                    Text(L10n.system.removeABC)
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                    
                                    if removeABCStatus == .success {
                                        Text(L10n.system.removeABCSuccess)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.green)
                                    } else if removeABCStatus == .error {
                                        Text(L10n.system.removeABCFailed)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.orange)
                                    } else {
                                        Button(action: { removeABCKeyboard() }) {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                            }
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
        }
        .frame(width: PriTypeConfig.settingsWindowWidth, height: PriTypeConfig.settingsWindowHeight)
        .onAppear {
            selectedKeyboard = ConfigurationManager.shared.keyboardId
            selectedToggleKey = ConfigurationManager.shared.toggleKey
            toggleKeyBinding = ConfigurationManager.shared.toggleKeyBinding
            hanjaKeyBinding = ConfigurationManager.shared.hanjaKeyBinding
            autoCapitalizeEnabled = ConfigurationManager.shared.autoCapitalizeEnabled
            doubleSpacePeriodEnabled = ConfigurationManager.shared.doubleSpacePeriodEnabled
            autoUpdateCheckEnabled = ConfigurationManager.shared.autoUpdateCheckEnabled
            checkAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkAccessibility()
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
    
    // MARK: - System Settings Logic
    
    private func checkAccessibility() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }
    
    private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
        
        // Start a timer to poll for changes if user grants it while window is open
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let granted = AXIsProcessTrusted()
            if granted {
                DispatchQueue.main.async {
                    self.isAccessibilityGranted = true
                    
                    // Auto-start key monitoring that was skipped at launch
                    if !RightCommandSuppressor.shared.isRunning {
                        RightCommandSuppressor.shared.onToggle = {
                            PriTypeInputController.sharedComposer.toggleInputMode()
                        }
                        RightCommandSuppressor.shared.onHanjaLookup = {
                            PriTypeInputController.sharedComposer.triggerHanjaLookup()
                        }
                        let started = RightCommandSuppressor.shared.start()
                        DebugLogger.log("Accessibility granted: CGEventTap start = \(started)")
                    }
                }
                timer.invalidate()
            }
        }
    }
    
    private func removeABCKeyboard() {
        guard let defaults = UserDefaults(suiteName: "com.apple.HIToolbox"),
              var sources = defaults.array(forKey: "AppleEnabledInputSources") as? [[String: Any]] else {
            removeABCStatus = .error
            return
        }
        
        let originalCount = sources.count
        sources.removeAll { source in
            if let name = source["KeyboardLayout Name"] as? String, name == "ABC" {
                return true
            }
            return false
        }
        
        if sources.count < originalCount {
            defaults.set(sources, forKey: "AppleEnabledInputSources")
            let _ = CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
            
            // Restart TextInputMenuAgent to apply changes immediately
            let task = Process()
            task.launchPath = "/usr/bin/killall"
            task.arguments = ["TextInputMenuAgent"]
            try? task.run()
            
            withAnimation { removeABCStatus = .success }
        } else {
            // Already removed or not found
            withAnimation { removeABCStatus = .success }
        }
        
        // Auto-reset status message after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                self.removeABCStatus = .idle
            }
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

/// A selection row — animations scoped to checkmark and background only
struct SelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            // No withAnimation here — prevents text from re-rendering with animation
            action()
        }) {
            HStack(spacing: 10) {
                // Selection indicator — simple circle
                Circle()
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.primary.opacity(0.10)))
                    .frame(width: 7, height: 7)
                    .padding(6)
                    .animation(.easeOut(duration: 0.2), value: isSelected)
                
                // Text — NO animation to prevent Korean glyph flickering
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .animation(nil, value: isSelected) // Explicitly disable
                
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
                    .animation(.easeOut(duration: 0.15), value: isHovering)
                    .animation(.easeOut(duration: 0.2), value: isSelected)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// A key recorder row — press to record a new key binding
///
/// Shows the current key binding and enters recording mode on click.
/// In recording mode, the next key press is captured and saved.
struct KeyRecorderRow: View {
    let label: String
    let icon: String
    @Binding var binding: KeyBinding
    let conflictBinding: KeyBinding
    @Binding var hasConflict: Bool
    
    @State private var isRecording = false
    @State private var isHovering = false
    @State private var monitor: Any?
    @State private var pulseAnimation = false
    
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
            
            Text(label)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulseAnimation ? 1.3 : 0.8)
                            .opacity(pulseAnimation ? 0.6 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)
                        
                        Text(L10n.keyBinding.recording)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.cyan)
                    } else {
                        Text(binding.displayName)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isRecording
                              ? Color.cyan.opacity(0.12)
                              : isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
            .onHover { hover in
                isHovering = hover
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .onDisappear {
            stopRecording()
        }
    }
    
    @State private var previousFlags: NSEvent.ModifierFlags = []
    
    private func startRecording() {
        isRecording = true
        pulseAnimation = true
        previousFlags = NSEvent.ModifierFlags(rawValue: 0)
        
        // Use local event monitor to capture key events in the settings window
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                let keyCode = Int64(event.keyCode)
                let currentFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                
                // Detect key DOWN: current flags have MORE modifiers than previous
                // This prevents capturing on modifier release
                let isNewModifier = !currentFlags.isSubset(of: previousFlags) && !currentFlags.isEmpty
                previousFlags = currentFlags
                
                if isNewModifier {
                    // Fn key (63) is not supported in CGEventTap — ignore it
                    guard keyCode != 63 else { return event }
                    let newBinding = KeyBinding(
                        keyCode: keyCode,
                        modifiers: 0,  // modifier-only binding
                        displayName: KeyBinding.generateDisplayName(keyCode: keyCode, modifiers: 0)
                    )
                    binding = newBinding
                    stopRecording()
                    return nil  // Consume event
                }
            } else if event.type == .keyDown {
                // Escape cancels recording
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }
                
                // Regular key + optional modifiers
                let keyCode = Int64(event.keyCode)
                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
                let newBinding = KeyBinding(
                    keyCode: keyCode,
                    modifiers: UInt64(modifiers),
                    displayName: KeyBinding.generateDisplayName(keyCode: keyCode, modifiers: UInt64(modifiers))
                )
                binding = newBinding
                stopRecording()
                return nil  // Consume event
            }
            return event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        pulseAnimation = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
