import Foundation
import InputMethodKit

// MARK: - PriType 입력기 메인 시작점
// macOS 입력기는 반드시 직접 IMKServer를 초기화해야 시스템에 등록됩니다.

/// 입력기 연결 이름 (Info.plist의 InputMethodConnectionName과 정확히 일치해야 함)
let connectionName = "Meapri_PriType_Swift_Connection"

/// 현재 앱의 번들 정보 가져오기
let mainBundle = Bundle.main
let bundleID = mainBundle.bundleIdentifier!

print("🚀 PriType 한글 입력기 시작")
print("📦 번들 ID: \(bundleID)")
print("🔗 연결 이름: \(connectionName)")
print("📁 번들 경로: \(mainBundle.bundlePath)")

do {
    // MARK: - IMKServer 초기화 (가장 중요!)
    // 이 과정이 바로 macOS에 "나를 입력기로 등록해줘"라고 요청하는 부분입니다.
    let server = try IMKServer(name: connectionName, bundleIdentifier: bundleID)

    print("✅ IMKServer 초기화 성공")
    print("🔄 입력기 서버 실행 중...")

    // MARK: - 서버 상태 모니터링
    // 디버깅을 위한 서버 상태 정보 출력
    print("📊 서버 정보:")
    print("   - 연결 이름: \(connectionName)")
    print("   - 번들 ID: \(bundleID)")
    print("   - 서버 인스턴스: \(String(describing: server))")

    // MARK: - 메인 이벤트 루프 실행
    // 입력기는 백그라운드에서 항상 실행되어야 합니다.
    // 이 루프가 종료되면 입력기가 시스템에서 사라집니다.
    print("🎯 입력기 준비 완료 - 시스템 이벤트 대기 중")
    print("💡 시스템 설정 → 키보드 → 입력 소스에서 확인해보세요")

    RunLoop.current.run()

} catch {
    // MARK: - 에러 처리
    print("❌ IMKServer 초기화 실패: \(error)")
    print("🔍 에러 원인:")
    print("   - Info.plist의 InputMethodConnectionName이 '\(connectionName)'과 일치하는지 확인")
    print("   - 번들 ID가 올바른지 확인: \(bundleID)")
    print("   - 코드 서명이 제대로 되어 있는지 확인")

    // 에러 발생 시 앱 종료
    exit(1)
}
