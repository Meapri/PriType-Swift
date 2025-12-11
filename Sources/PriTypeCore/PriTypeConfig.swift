import Foundation

/// Global configuration constants for PriType
public struct PriTypeConfig: Sendable {
    
    #if DEBUG
    /// Path for debug logging (DEBUG builds only)
    /// - Note: This property does not exist in release builds for security.
    public static let logPath = NSString(string: "~/Library/Logs/PriType/pritype_debug.log").expandingTildeInPath
    #endif
    
    /// Default keyboard identifier (두벌식 표준)
    public static let defaultKeyboardId = "2"
    
    // MARK: - Finder Detection
    
    /// Finder 데스크톱 감지를 위한 좌표 임계값 (Points)
    /// Finder의 숨겨진 더미 입력창은 (5, 20) 근처에 위치하며,
    /// 50 포인트 이하를 데스크톱으로 간주합니다.
    public static let finderDesktopThreshold: CGFloat = 50
    
    // MARK: - UI Constants
    
    /// 설정 창 너비
    public static let settingsWindowWidth: CGFloat = 420
    
    /// 설정 창 높이
    public static let settingsWindowHeight: CGFloat = 680
    
    // MARK: - Text Convenience
    
    /// 더블 스페이스 감지 시간 임계값 (초)
    public static let doubleSpaceThreshold: TimeInterval = 0.45
}
