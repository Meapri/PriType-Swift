import Foundation

// MARK: - PriType Errors

/// Errors that can occur in the PriType input method
///
/// These errors provide structured error handling for system-level operations
/// that may fail, such as event tap creation or permission requests.
public enum PriTypeError: LocalizedError, Sendable {
    
    // MARK: - Event Tap Errors
    
    /// CGEventTap creation failed
    case eventTapCreationFailed
    
    /// Event tap was disabled by the system
    case eventTapDisabled
    
    // MARK: - Permission Errors
    
    /// Accessibility permission not granted
    case accessibilityPermissionDenied
    
    // MARK: - IOKit Errors
    
    /// Failed to open IOHIDManager
    case hidManagerOpenFailed(code: Int32)
    
    // MARK: - LocalizedError
    
    public var errorDescription: String? {
        switch self {
        case .eventTapCreationFailed:
            return "CGEventTap 생성에 실패했습니다. 접근성 권한을 확인하세요."
        case .eventTapDisabled:
            return "CGEventTap이 시스템에 의해 비활성화되었습니다."
        case .accessibilityPermissionDenied:
            return "접근성 권한이 필요합니다. 시스템 설정에서 PriType에 권한을 부여하세요."
        case .hidManagerOpenFailed(let code):
            return "IOHIDManager 열기 실패 (코드: \(code))"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .eventTapCreationFailed, .accessibilityPermissionDenied:
            return "시스템 설정 > 개인정보 보호 및 보안 > 접근성에서 PriType을 활성화하세요."
        case .eventTapDisabled:
            return "입력기를 재시작하거나 시스템을 다시 시작하세요."
        case .hidManagerOpenFailed:
            return "시스템을 재시작하거나 접근성 권한을 확인하세요."
        }
    }
}
