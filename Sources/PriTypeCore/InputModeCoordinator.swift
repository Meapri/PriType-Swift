import Foundation

/// Coordinates PriType-owned language toggles.
///
/// Custom toggle keys must not select the real macOS ABC input source. Doing so
/// hands the active text session to another input source and reintroduces
/// first-key races. This coordinator keeps the custom toggle path inside
/// PriType: key monitor -> controller -> composer.
public final class InputModeCoordinator: @unchecked Sendable {
    public static let shared = InputModeCoordinator()

    public enum ToggleSource: Sendable {
        case customKey
        case iokitFallback
    }

    private init() {}

    public func requestToggle(source: ToggleSource) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.requestToggle(source: source)
            }
            return
        }

        guard !ConfigurationManager.shared.capsLockInputSourceSwitchEnabled else {
            DebugLogger.log("InputModeCoordinator: ignored custom toggle because Caps Lock owns switching")
            return
        }

        guard let controller = PriTypeInputController.sharedController else {
            DebugLogger.log("InputModeCoordinator: ignored custom toggle because no active controller exists")
            return
        }

        controller.performPriTypeModeTransition(source: source)
    }
}
