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
        
        // Create window
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "PriType 설정"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 400, height: 300))
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
    
    private let keyboardOptions = [
        ("2", "두벌식 표준"),
        ("3", "세벌식 390"),
        ("2y", "두벌식 옛한글"),
        ("3y", "세벌식 옛한글")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("PriType 설정")
                .font(.title)
                .fontWeight(.bold)
            
            Divider()
            
            // Keyboard Layout
            VStack(alignment: .leading, spacing: 8) {
                Text("자판 배열")
                    .font(.headline)
                
                Picker("", selection: $selectedKeyboard) {
                    ForEach(keyboardOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedKeyboard) { newValue in
                    ConfigurationManager.shared.keyboardId = newValue
                }
            }
            
            Divider()
            
            // Toggle Key
            VStack(alignment: .leading, spacing: 8) {
                Text("한영 전환 키")
                    .font(.headline)
                
                Picker("", selection: $selectedToggleKey) {
                    ForEach(ToggleKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedToggleKey) { newValue in
                    ConfigurationManager.shared.toggleKey = newValue
                }
                
                Text("변경 후 입력기를 재시작하면 적용됩니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Version info
            HStack {
                Spacer()
                Text("PriType v2.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 350, minHeight: 350)
    }
}
