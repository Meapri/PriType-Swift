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
    @State private var autoUpdateCheckEnabled = ConfigurationManager.shared.autoUpdateCheckEnabled
    @State private var isAccessibilityGranted = false
    @State private var hasKeyConflict = false
    @State private var showKeyConflictRestored = false
    @State private var isRestoringKeyBinding = false
    @State private var showCapsLockBlockedAlert = false
    @State private var capsLockSwitchEnabled = false

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
        VStack(spacing: 0) {
            settingsHeader
                .zIndex(1)

            ScrollView(.vertical, showsIndicators: false) {
                GlassEffectContainer(spacing: 16) {
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

                        SettingsNoticeRow(
                            icon: "capslock",
                            text: L10n.keyBinding.capsLockSummary
                        )

                        CapsLockStatusRow(
                            isEnabled: capsLockSwitchEnabled,
                            openSettings: openInputSourceSettings
                        )

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
                                    hasConflict: $hasKeyConflict,
                                    isDisabled: capsLockSwitchEnabled,
                                    onCapsLockBlocked: { showCapsLockBlockedAlert = true }
                                )

                                Divider()
                                    .opacity(0.2)
                                    .padding(.horizontal, 12)

                                KeyRecorderRow(
                                    label: L10n.keyBinding.hanjaKey,
                                    icon: "character.book.closed",
                                    binding: $hanjaKeyBinding,
                                    conflictBinding: toggleKeyBinding,
                                    hasConflict: $hasKeyConflict,
                                    isDisabled: false,
                                    onCapsLockBlocked: { showCapsLockBlockedAlert = true }
                                )

                                if hasKeyConflict {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange)
                                        Text(showKeyConflictRestored ? L10n.keyBinding.conflictRestored : L10n.keyBinding.conflict)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }

                            }
                        }
                        .onChange(of: toggleKeyBinding) { _, newValue in
                            if isRestoringKeyBinding {
                                isRestoringKeyBinding = false
                                return
                            }
                            if newValue == hanjaKeyBinding {
                                showRestoredConflict()
                                isRestoringKeyBinding = true
                                toggleKeyBinding = ConfigurationManager.shared.toggleKeyBinding
                                return
                            }
                            ConfigurationManager.shared.toggleKeyBinding = newValue
                            clearKeyConflict()
                        }
                        .onChange(of: hanjaKeyBinding) { _, newValue in
                            if isRestoringKeyBinding {
                                isRestoringKeyBinding = false
                                return
                            }
                            if newValue == toggleKeyBinding {
                                showRestoredConflict()
                                isRestoringKeyBinding = true
                                hanjaKeyBinding = ConfigurationManager.shared.hanjaKeyBinding
                                return
                            }
                            ConfigurationManager.shared.hanjaKeyBinding = newValue
                            clearKeyConflict()
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
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.roundedRectangle(radius: 7))
                                    .controlSize(.small)
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
                                    SettingsRowIcon(systemName: "hand.raised")

                                    Text(L10n.system.accessibility)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if isAccessibilityGranted {
                                        Text(L10n.system.accessibilityGranted)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.green)
                                    } else {
                                        Button(action: { requestAccessibility() }) {
                                            Text(L10n.system.accessibilityRequest)
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.roundedRectangle(radius: 7))
                                        .controlSize(.small)
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
            }
            .clipped()

            settingsFooter
        }
        .frame(width: PriTypeConfig.settingsWindowWidth, height: PriTypeConfig.settingsWindowHeight)
        .onAppear {
            selectedKeyboard = ConfigurationManager.shared.keyboardId
            selectedToggleKey = ConfigurationManager.shared.toggleKey
            toggleKeyBinding = ConfigurationManager.shared.toggleKeyBinding
            hanjaKeyBinding = ConfigurationManager.shared.hanjaKeyBinding
            autoUpdateCheckEnabled = ConfigurationManager.shared.autoUpdateCheckEnabled
            refreshCapsLockSwitchState()
            checkAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshCapsLockSwitchState()
            checkAccessibility()
        }
        .alert(L10n.keyBinding.capsLockBlockedTitle, isPresented: $showCapsLockBlockedAlert) {
            Button(L10n.keyBinding.capsLockOpenSettings) {
                openInputSourceSettings()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(L10n.keyBinding.capsLockBlockedMessage)
        }
    }

    private var settingsHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SettingsHeaderIcon()

                VStack(alignment: .leading, spacing: 3) {
                    Text("PriType")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(L10n.settings.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
            .padding(.horizontal, 28)

            Divider()
                .opacity(0.22)
                .padding(.horizontal, 20)
        }
    }

    private var settingsFooter: some View {
        HStack {
            Spacer()
            Text("v\(AboutInfo.displayVersion)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 7)
            Spacer()
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text(L10n.update.upToDate)
                    .font(.system(size: 12, weight: .medium))
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
                        .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 12, weight: .medium))
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

    private func openInputSourceSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?InputSources") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func refreshCapsLockSwitchState() {
        capsLockSwitchEnabled = ConfigurationManager.shared.capsLockInputSourceSwitchEnabled
    }

    private func showRestoredConflict() {
        withAnimation(.easeInOut(duration: 0.2)) {
            hasKeyConflict = true
            showKeyConflictRestored = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                hasKeyConflict = false
                showKeyConflictRestored = false
            }
        }
    }

    private func clearKeyConflict() {
        guard hasKeyConflict || showKeyConflictRestored else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            hasKeyConflict = false
            showKeyConflictRestored = false
        }
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
                            if let nextMode = InputSourceManager.shared.toggledInputMode(
                                fallbackMode: PriTypeInputController.sharedComposer.inputMode
                            ) {
                                PriTypeInputController.sharedController?.selectInputModeForCurrentClient(nextMode)
                                PriTypeInputController.sharedComposer.setInputMode(nextMode)
                            }
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
}

struct SettingsHeaderIcon: View {
    private var image: NSImage {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .accessibilityHidden(true)
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

struct SettingsNoticeRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct CapsLockStatusRow: View {
    let isEnabled: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SettingsRowIcon(systemName: "capslock")

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L10n.keyBinding.capsLockStatusTitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Spacer(minLength: 8)

                    Text(isEnabled ? L10n.keyBinding.capsLockStatusOn : L10n.keyBinding.capsLockStatusOff)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isEnabled ? .green : .secondary)
                        .fixedSize()
                }

                Button(action: openSettings) {
                    Text(L10n.keyBinding.capsLockOpenSettings)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 7))
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct SettingsRowIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
            .frame(width: 22, height: 22)
    }
}

/// A section with a label and a single readable glass surface for its content.
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            )
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
                // Text — NO animation to prevent Korean glyph flickering
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .animation(nil, value: isSelected) // Explicitly disable

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(minHeight: 34)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? Color.primary.opacity(0.075)
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
            SettingsRowIcon(systemName: icon)

            Text(title)
                .font(.system(size: 14, weight: .regular))
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
    let isDisabled: Bool
    let onCapsLockBlocked: () -> Void

    @State private var isRecording = false
    @State private var isHovering = false
    @State private var monitor: Any?
    @State private var pulseAnimation = false

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowIcon(systemName: icon)

            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: {
                guard !isDisabled else { return }
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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.blue)
                    } else {
                        Text(binding.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(isDisabled)
            .tint(isRecording ? Color.blue : nil)
            .onHover { hover in
                isHovering = hover
            }
        }
        .opacity(isDisabled ? 0.45 : 1)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .onChange(of: isDisabled) { _, disabled in
            if disabled {
                stopRecording()
            }
        }
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
                let currentFlags = event.modifierFlags.intersection([.command, .option, .control, .shift, .capsLock])

                // Detect key DOWN: current flags have MORE modifiers than previous
                // This prevents capturing on modifier release. Caps Lock is a lock
                // state, so capture its keyCode directly even when the flag toggles off.
                let isNewModifier = (!currentFlags.isSubset(of: previousFlags) && !currentFlags.isEmpty) || keyCode == 57
                previousFlags = currentFlags

                if isNewModifier {
                    // Fn key (63) is not supported in CGEventTap — ignore it
                    guard keyCode != 63 else { return event }
                    guard keyCode != 57 else {
                        stopRecording()
                        onCapsLockBlocked()
                        return nil
                    }
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
