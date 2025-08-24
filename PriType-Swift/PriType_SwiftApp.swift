//
//  PriType_SwiftApp.swift
//  PriType-Swift
//
//  Created by 리지 on 8/24/25.
//

import Foundation
import InputMethodKit
import AppKit

/// PriType 입력 메소드 앱 델리게이트
/// 시스템이 자동으로 IMKServer를 생성하고 PriTypeInputController를 관리
/// @unchecked Sendable: NSApplicationDelegate는 메인 스레드에서만 사용되므로 안전
final class PriTypeInputMethodAppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎯 PriType 입력 메소드 앱 시작")

        // 번들 정보 확인
        print("📦 번들 정보 확인:")
        print("   - 번들 경로: \(Bundle.main.bundlePath)")
        print("   - 번들 ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        print("   - 실행 파일: \(Bundle.main.executablePath ?? "Unknown")")

        // Info.plist에서 InputMethodConnectionName 확인
        if let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String {
            print("🔗 연결 이름: \(connectionName)")
        } else {
            print("⚠️ 연결 이름을 찾을 수 없습니다")
        }

        print("✅ PriType 입력 메소드 초기화 완료")
        print("🔄 시스템이 자동으로 IMKServer를 생성하고 PriTypeInputController를 관리합니다")
        print("🚀 입력 메소드 준비 완료 - 시스템 이벤트 대기 중")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 PriType 입력 메소드 앱 종료")
    }
}

// 입력 메소드 앱의 메인 구조
// @main을 사용하여 Swift 6 동시성 문제를 해결
@main
struct PriTypeInputMethod {
    static func main() {
        // 메인 스레드에서 안전하게 앱 초기화
        let delegate = PriTypeInputMethodAppDelegate()
        let application = NSApplication.shared
        application.delegate = delegate

        // NSApplicationMain을 통한 메인 이벤트 루프 시작
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
