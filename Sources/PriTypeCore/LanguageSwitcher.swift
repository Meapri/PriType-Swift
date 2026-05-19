import Foundation

/// Owns PriType's custom language-toggle path.
///
/// Caps Lock input-source switching is macOS-owned. Keeping the guard here
/// prevents app startup, settings permission recovery, and fallback handlers
/// from drifting into different behavior.
public enum LanguageSwitcher {
    public static func toggleLanguageInputSource() {
        if ConfigurationManager.shared.capsLockInputSourceSwitchEnabled {
            DebugLogger.log("PriType toggle ignored because macOS Caps Lock input-source switching is enabled")
            return
        }

        if let nextMode = InputSourceManager.shared.toggledInputMode(
            fallbackMode: PriTypeInputController.sharedComposer.inputMode
        ) {
            PriTypeInputController.sharedController?.selectInputModeForCurrentClient(nextMode)
            PriTypeInputController.sharedComposer.setInputMode(nextMode)
        }
    }
}
