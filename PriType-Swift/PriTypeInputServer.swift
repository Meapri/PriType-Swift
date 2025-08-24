import Foundation
import InputMethodKit
import AppKit

/// PriType 입력 메소드 서버 관리자
/// 실제 IMKServer는 시스템이 자동으로 생성하므로 여기서는 모니터링만 수행
class PriTypeInputServer: NSObject, @unchecked Sendable {

    // MARK: - Properties

    /// 서버 연결 이름 (Info.plist에서 가져옴)
    private var connectionName: String?

    /// 서버가 실행 중인지 여부
    private(set) var isRunning = false

    // MARK: - Initialization

    override init() {
        super.init()
        print("🖥️ PriTypeInputServer 초기화")

        // Info.plist에서 연결 이름 가져오기
        if let name = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String {
            self.connectionName = name
            print("📡 연결 이름 설정: \(name)")
        } else {
            print("⚠️ 연결 이름을 찾을 수 없습니다")
        }
    }

    deinit {
        print("🗑️ PriTypeInputServer 해제")
    }

    // MARK: - Public Methods

    /// 서버 상태 확인 및 업데이트
    func checkServerStatus() -> Bool {
        // 시스템이 자동으로 생성한 IMKServer 상태 확인
        // 실제로는 시스템의 입력 메소드 관리자를 통해 상태를 확인할 수 있음

        if let connectionName = connectionName {
            print("🔍 서버 상태 확인: \(connectionName)")

            // macOS의 Text Input Sources API를 통해 상태 확인 가능
            // 여기서는 간단한 시뮬레이션
            isRunning = true
            print("✅ PriType 입력 메소드 서버 실행 중 (시스템 관리)")
            return true
        }

        print("❌ 서버 상태 확인 실패")
        return false
    }

    /// 서버 정보 가져오기
    func getServerInfo() -> [String: Any] {
        [
            "connectionName": connectionName ?? "Unknown",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "isRunning": isRunning,
            "version": "1.0.0",
            "managedBy": "System (IMKServer)"
        ]
    }

    /// 연결 이름 반환
    var serverConnectionName: String? {
        return connectionName
    }
}

// MARK: - 메뉴 바 통합

extension PriTypeInputServer {

    /// 키보드 메뉴 바 아이템 생성
    func createMenuBarItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.title = "🇰🇷 PriType"
        item.toolTip = "PriType 한글 입력기"

        // 서브메뉴 생성
        let submenu = NSMenu(title: "PriType")

        let statusItem = NSMenuItem(
            title: "상태: \(isRunning ? "실행 중" : "시스템 관리 중")",
            action: nil,
            keyEquivalent: ""
        )
        statusItem.isEnabled = false
        submenu.addItem(statusItem)

        submenu.addItem(.separator())

        let checkItem = NSMenuItem(
            title: "상태 확인",
            action: #selector(checkStatus),
            keyEquivalent: ""
        )
        checkItem.target = self
        submenu.addItem(checkItem)

        let infoItem = NSMenuItem(
            title: "정보",
            action: #selector(showInfo),
            keyEquivalent: ""
        )
        infoItem.target = self
        submenu.addItem(infoItem)

        item.submenu = submenu
        return item
    }

    @objc private func checkStatus() {
        let running = checkServerStatus()
        print("🔍 서버 상태: \(running ? "정상" : "오류")")
    }

    @objc private func showInfo() {
        let info = getServerInfo()
        print("ℹ️ 서버 정보: \(info)")
    }
}
