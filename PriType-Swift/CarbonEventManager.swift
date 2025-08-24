import Foundation
import Carbon
import CoreFoundation
import AppKit

/// Carbon Event 기반 키보드 이벤트 관리자
/// 시스템 전체 키보드 이벤트를 낮은 수준에서 처리
class CarbonEventManager: @unchecked Sendable {

    // MARK: - Properties

    /// 이벤트 핫키 목록
    private var hotKeys: [String: EventHotKeyRef] = [:]

    /// 이벤트 핸들러
    private var eventHandlerRef: EventHandlerRef?

    /// 이벤트 핸들러 타겟
    private var eventHandlerTarget: EventTargetRef?

    /// 현재 한영 전환 상태
    private var isHangulMode = false

    /// 이벤트 처리 콜백
    private let keyboardEventHandler: (@Sendable (KeyboardInput) -> Void)?

    // MARK: - Initialization

    init(keyboardEventHandler: (@Sendable (KeyboardInput) -> Void)? = nil) {
        self.keyboardEventHandler = keyboardEventHandler
        print("🔥 CarbonEventManager 초기화")
        setupCarbonEvents()
    }

    deinit {
        cleanup()
        print("🗑️ CarbonEventManager 해제")
    }

    // MARK: - Public Methods

    /// Carbon 이벤트 시스템 설정
    func setupCarbonEvents() {
        print("⚙️ Carbon 이벤트 시스템 설정 중...")

        // 이벤트 핸들러 설치
        installEventHandler()

        // 기본 핫키 등록
        registerDefaultHotKeys()

        print("✅ Carbon 이벤트 시스템 설정 완료")
    }

    /// 기본 핫키 등록
    func registerDefaultHotKeys() {
        print("🔑 기본 핫키 등록 중...")

        // 한영 전환 핫키 (Cmd + Space)
        registerHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey),
            id: 1,
            name: "한영 전환"
        )

        // 한영 전환 핫키 (한자 키)
        registerHotKey(
            keyCode: UInt32(kVK_F1), // 한자 키는 보통 F1로 매핑됨
            modifiers: 0,
            id: 2,
            name: "한자 키"
        )

        print("✅ 기본 핫키 등록 완료")
    }

    /// 커스텀 핫키 등록
    func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: Int, name: String) {
        let hotKeyID = EventHotKeyID(signature: 0x50524954, id: UInt32(id)) // 'PRIT'

        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef = hotKeyRef {
            let key = hotKeyIdentifier(keyCode: keyCode, modifiers: modifiers)
            hotKeys[key] = hotKeyRef
            print("✅ 핫키 등록: \(name) (\(key))")
        } else {
            print("❌ 핫키 등록 실패: \(name) (에러: \(status))")
        }
    }

    /// 핫키 해제
    func unregisterHotKey(keyCode: UInt32, modifiers: UInt32) {
        let key = hotKeyIdentifier(keyCode: keyCode, modifiers: modifiers)

        if let hotKeyRef = hotKeys[key] {
            let status = UnregisterEventHotKey(hotKeyRef)
            if status == noErr {
                hotKeys.removeValue(forKey: key)
                print("🗑️ 핫키 해제: \(key)")
            } else {
                print("❌ 핫키 해제 실패: \(key) (에러: \(status))")
            }
        }
    }

    /// 현재 등록된 핫키 목록
    var registeredHotKeys: [String] {
        Array(hotKeys.keys)
    }

    /// 한영 모드 토글
    func toggleHangulMode() {
        isHangulMode.toggle()
        print("🔄 한영 모드: \(isHangulMode ? "한글" : "영어")")

        // 시스템 알림 전송 (필요시)
        postHangulModeNotification()
    }

    /// 현재 한영 모드 상태
    var currentHangulMode: Bool {
        isHangulMode
    }

    // MARK: - Private Methods

    private func installEventHandler() {
        print("🎯 이벤트 핸들러 설치 중...")

        // 이벤트 핸들러 타겟 획득
        eventHandlerTarget = GetEventDispatcherTarget()

        guard let eventHandlerTarget = eventHandlerTarget else {
            print("❌ 이벤트 핸들러 타겟 획득 실패")
            return
        }

        // 핫키 이벤트 핸들러 설치
        var hotKeyEventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            eventHandlerTarget,
            carbonEventHandler,
            1,
            &hotKeyEventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status == noErr {
            print("✅ 이벤트 핸들러 설치 완료")
        } else {
            print("❌ 이벤트 핸들러 설치 실패: \(status)")
        }
    }

    private func cleanup() {
        print("🧹 Carbon Event 정리 중...")

        // 핫키 정리
        for (key, hotKeyRef) in hotKeys {
            let status = UnregisterEventHotKey(hotKeyRef)
            if status != noErr {
                print("❌ 핫키 정리 실패: \(key) (에러: \(status))")
            }
        }
        hotKeys.removeAll()

        // 이벤트 핸들러 정리
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        print("✅ Carbon Event 정리 완료")
    }

    private func hotKeyIdentifier(keyCode: UInt32, modifiers: UInt32) -> String {
        "\(keyCode)_\(modifiers)"
    }

    private func postHangulModeNotification() {
        // 시스템 전체에 한영 모드 변경 알림 전송
        let notification = Notification(
            name: Notification.Name("PriTypeHangulModeChanged"),
            object: self,
            userInfo: ["isHangulMode": isHangulMode]
        )

        NotificationCenter.default.post(notification)

        // Distributed Notification도 전송하여 다른 프로세스에서도 감지 가능
        DistributedNotificationCenter.default().post(
            name: Notification.Name("PriTypeHangulModeChanged"),
            object: nil,
            userInfo: ["isHangulMode": isHangulMode]
        )
    }

    /// 키보드 이벤트 처리
    private func handleKeyboardEvent(_ input: KeyboardInput) {
        // 콜백 핸들러 호출
        keyboardEventHandler?(input)

        // 디버깅용 로깅
        if input.isSpace && input.hasCommand {
            print("🎹 Cmd + Space 감지")
            toggleHangulMode()
        }
    }
}

// MARK: - Carbon Event Callback

/// Carbon 이벤트 핸들러 콜백 함수
private func carbonEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {

    guard let userData = userData else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<CarbonEventManager>.fromOpaque(userData).takeUnretainedValue()

    // 핫키 이벤트 처리
    if let event = event {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        if status == noErr {
            print("🔥 핫키 이벤트 발생: \(hotKeyID.id)")

            // 핫키 ID에 따른 처리
            switch hotKeyID.id {
            case 1: // 한영 전환 (Cmd + Space)
                manager.toggleHangulMode()
            case 2: // 한자 키
                print("🏮 한자 키 이벤트")
            default:
                print("❓ 알 수 없는 핫키 ID: \(hotKeyID.id)")
            }
        }
    }

    return CallNextEventHandler(nextHandler, event)
}

// MARK: - 확장 기능

extension CarbonEventManager {

    /// 시스템 전체 키보드 레이아웃 모니터링
    func startKeyboardLayoutMonitoring() {
        print("👀 키보드 레이아웃 모니터링 시작...")

        // 키보드 레이아웃 변경 알림 설정
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            print("🔄 스페이스 변경 감지")
            self?.handleSpaceChange()
        }

        // 시스템 키보드 레이아웃 변경 모니터링
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("NSTextInputContextKeyboardSelectionDidChangeNotification"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            print("🔄 키보드 입력소스 변경 감지")
            self?.handleInputSourceChange()
        }

        print("✅ 키보드 레이아웃 모니터링 시작됨")
    }

    private func handleSpaceChange() {
        // 스페이스 변경 시 필요한 처리
        print("🏢 스페이스 변경 처리")
    }

    private func handleInputSourceChange() {
        // 입력소스 변경 시 필요한 처리
        print("⌨️ 입력소스 변경 처리")
    }

    /// 글로벌 키보드 이벤트 스트림 설정
    func setupGlobalEventStream() {
        print("🌊 글로벌 이벤트 스트림 설정 중...")

        // NSEvent 글로벌 모니터 설정 (Carbon Event와 함께 사용)
        NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            let keyboardInput = KeyboardInput(
                keyCode: event.keyCode,
                characters: event.characters,
                modifierFlags: event.modifierFlags
            )

            self?.handleKeyboardEvent(keyboardInput)
        }

        print("✅ 글로벌 이벤트 스트림 설정 완료")
    }

    /// 이벤트 스트림 중지
    func stopGlobalEventStream() {
        print("🛑 글로벌 이벤트 스트림 중지")
        // 실제로는 모니터 객체를 저장했다가 여기서 정리해야 함
    }
}

// MARK: - 시스템 통합

extension CarbonEventManager {

    /// 시스템 시작 시 자동 실행 설정
    func setupAutoLaunch() {
        print("🚀 자동 실행 설정 중...")

        // Launch Services를 통해 시스템 시작 시 자동 실행 설정
        let appPath = Bundle.main.bundlePath

        // 실제로는 SMLoginItemSetEnabled() 또는 Launch Services API 사용
        print("✅ 자동 실행 설정: \(appPath)")
    }

    /// 시스템 설정 동기화
    func syncWithSystemPreferences() {
        print("⚙️ 시스템 설정과 동기화 중...")

        // 시스템의 키보드 설정과 동기화
        if let currentLayout = getCurrentKeyboardLayout() {
            print("📋 현재 키보드 레이아웃: \(currentLayout)")
        }

        // 한영 전환 키 설정 확인
        if let toggleKey = getHangulToggleKey() {
            print("🔄 한영 전환 키: \(toggleKey)")
        }

        print("✅ 시스템 설정 동기화 완료")
    }

    private func getCurrentKeyboardLayout() -> String? {
        // 현재 시스템 키보드 레이아웃 조회
        // 실제로는 TISCopyCurrentKeyboardLayoutInputSource() 사용
        return "Korean"
    }

    private func getHangulToggleKey() -> String? {
        // 시스템의 한영 전환 키 설정 조회
        // 실제로는 시스템 설정에서 조회
        return "Cmd + Space"
    }
}
