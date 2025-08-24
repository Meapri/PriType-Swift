import Foundation
import InputMethodKit
import AppKit
import Carbon
import LibHangul

/// PriType 한글 입력 컨트롤러 - Input Method Kit 기반
/// macOS 시스템과 완벽하게 통합되는 입력 메소드
/// Swift 6 Strict Concurrency 완전 준수
@objc(PriTypeInputController)
final class PriTypeInputController: IMKInputController, @unchecked Sendable {

    // MARK: - Type Definitions
    // HangulInputManager에서 정의된 공통 타입들을 사용

    // MARK: - Properties

    /// 한글 입력 관리자 - Swift 6 Sendable 준수
    private let inputManager: HangulInputManager

    /// 현재 입력 중인 클라이언트
    private weak var currentClient: (any IMKTextInput)?

    /// 현재 입력 상태 - Sendable 타입으로 관리
    private var currentState: HangulInputState = .idle {
        didSet {
            // 상태 변경 시 처리 (간단하게 로그만)
            print("📊 상태 변경: \(oldValue) -> \(currentState)")
        }
    }

    /// 현재 한글 입력 모드 - Sendable 타입으로 관리
    private var currentInputMode: HangulInputMode = .english {
        didSet {
            // 모드 변경 시 처리 (간단하게 로그만)
            print("🔄 모드 변경: \(oldValue) -> \(currentInputMode)")
        }
    }

    /// 입력 통계 - Sendable 구조체로 관리
    private var inputStatistics = InputStatistics()

    /// 마지막 입력 시간 - 동시성 안전하게 관리
    private var lastInputTime: TimeInterval = 0

    /// 입력 세션 ID - 각 입력 세션 추적
    private var sessionID: UUID = UUID()

    // 메뉴 바 통합 제거됨 - 불필요한 기능

    // MARK: - Nested Types

    /// 입력 통계를 나타내는 Sendable 구조체
    struct InputStatistics: Sendable {
        private(set) var totalKeyEvents: Int = 0
        private(set) var composedCharacters: Int = 0
        private(set) var committedCharacters: Int = 0
        private(set) var backspaceCount: Int = 0
        private(set) var modeChanges: Int = 0

        mutating func recordKeyEvent() {
            totalKeyEvents += 1
        }

        mutating func recordComposition(_ text: String) {
            composedCharacters += text.count
        }

        mutating func recordCommit(_ text: String) {
            committedCharacters += text.count
        }

        mutating func recordBackspace() {
            backspaceCount += 1
        }

        mutating func recordModeChange() {
            modeChanges += 1
        }

        var description: String {
            "키입력:\(totalKeyEvents) 조합:\(composedCharacters) 커밋:\(committedCharacters) 백스페이스:\(backspaceCount)"
        }
    }

    /// IMK 서버 연결
    private weak var server: IMKServer?

    // MARK: - Initialization

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        print("🇰🇷 PriTypeInputController 초기화 시작")

        // 한글 입력 관리자 초기화 - 간단하게
        self.inputManager = HangulInputManager()

        // 부모 클래스 초기화
        super.init(server: server, delegate: delegate, client: inputClient)

        // 서버와 클라이언트 설정
        self.currentClient = inputClient as? IMKTextInput

        // 기본 모드 설정 (메뉴 바 아이콘은 activateServer에서 초기화)
        self.currentInputMode = .hangul

        // 입력 관리자 핸들러 설정
        setupInputManagerHandlers()

        print("✅ PriTypeInputController 초기화 완료")
        print("🔗 서버 연결: \(String(describing: server))")
        print("👤 클라이언트: \(String(describing: inputClient))")
    }

    /// 입력 관리자 핸들러 설정
    private func setupInputManagerHandlers() {
        print("🔧 입력 관리자 핸들러 설정 중...")

        // 한글 입력 상태 변경 핸들러 - Task로 감싸서 실행
        Task {
            await inputManager.setStateChangedHandler { [weak self] state in
                Task { @MainActor in
                    self?.handleStateChange(state)
                }
            }
        }

        // 입력 모드 변경 핸들러 - Task로 감싸서 실행
        Task {
            await inputManager.setModeChangedHandler { [weak self] mode in
                Task { @MainActor in
                    self?.handleModeChange(mode)
                }
            }
        }

        print("✅ 입력 관리자 핸들러 설정 완료")
    }

    // 메뉴 바 관련 메소드들 제거됨



    deinit {
        print("🗑️ PriTypeInputController 해제")
    }

    // MARK: - IMKInputController Overrides

    /// 텍스트 입력 처리 - 입력기의 핵심 메소드
    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        guard let string = string, !string.isEmpty else { return false }

        print("📝 inputText called with: '\(string)'")

        // 현재 입력 모드 확인 (동기적으로)
        let isHangulMode = currentInputMode == .hangul

        if isHangulMode {
            // 한글 모드에서는 한글 입력 처리
            Task {
                _ = await handleHangulInput(string)
            }
            return true
        } else {
            // 영어 모드에서는 직접 입력
            insertText(string)
            return true
        }
    }

    /// 조합 텍스트 확정
    override func commitComposition(_ sender: Any!) {
        print("✅ commitComposition called")

        Task { @MainActor in
            commitComposedText()
        }
    }

    /// 입력 활성화 시 호출
    override func activateServer(_ sender: Any!) {
        // Objective-C super call
        super.activateServer(sender)

        print("🎯 PriType 입력 메소드 활성화")

        // Main actor에서 속성 접근 - 타입 안전한 방식으로 처리
        Task { @MainActor in
            // 한글 모드 기본 설정
            self.currentInputMode = HangulInputMode.hangul

            // 통계 기록
            self.inputStatistics.recordKeyEvent()
        }

        print("✅ PriType 입력 메소드 활성화 완료")
    }

    /// 입력 비활성화 시 호출
    override func deactivateServer(_ sender: Any!) {
        super.deactivateServer(sender)
        print("💤 PriType 입력 메소드 비활성화")

        // 메뉴 바 기능 제거됨

        // 현재 조합 중인 텍스트 처리
        Task { @MainActor in
            self.commitComposedText()
        }

        print("✅ PriType 입력 메소드 비활성화 완료")
    }

    /// 키보드 이벤트 처리
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event else {
            return false
        }

        // Main actor에서 속성 접근 - 타입 안전한 방식으로 처리
        if sender is IMKTextInput {
            Task { @MainActor in
                // 입력 통계 기록
                self.inputStatistics.recordKeyEvent()
            }
        }

        // 키보드 이벤트 변환 - synchronous 메소드
        let keyboardInput = convertNSEventToKeyboardInput(event)

        // 이벤트 처리 - background에서 async 메소드 실행
        Task {
            _ = await handleKeyboardInput(keyboardInput)
        }
        return true // 이벤트 처리됨
    }

    /// 메뉴 생성
    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "PriType 한글 입력기")

        // 입력 모드 토글 메뉴 아이템
        let toggleItem = NSMenuItem(
            title: currentInputMode == .hangul ? "영어 모드로 전환" : "한글 모드로 전환",
            action: #selector(toggleInputMode),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // 현재 상태 표시
        let statusItem = NSMenuItem(
            title: "현재 모드: \(currentInputMode.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if case .composing(let text) = currentState, !text.isEmpty {
            let composeItem = NSMenuItem(
                title: "조합 중: '\(text)'",
                action: nil,
                keyEquivalent: ""
            )
            composeItem.isEnabled = false
            menu.addItem(composeItem)
        }

        menu.addItem(.separator())

        // 버전 정보
        let versionItem = NSMenuItem(
            title: "PriType 한글 v1.0.0",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        return menu
    }

    /// 후보 단어 선택 처리
    override func candidateSelected(_ candidateString: NSAttributedString!) {
        print("🎯 candidateSelected called")

        if let candidate = candidateString?.string {
            Task { @MainActor in
                // 선택된 후보를 입력
                insertText(candidate)
                currentState = .idle
            }
        }
    }

    // MARK: - Private Methods

    // MARK: - Private Event Handling Methods

    /// NSEvent를 KeyboardInput으로 변환
    private func convertNSEventToKeyboardInput(_ event: NSEvent) -> KeyboardInput {
        KeyboardInput(
            keyCode: UInt16(event.keyCode),
            characters: event.characters,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp
        )
    }

    /// 키보드 이벤트 처리
    private func handleKeyboardInput(_ input: KeyboardInput) async -> Bool {
        // 마지막 입력 시간 업데이트 - Main actor에서
        await MainActor.run {
            lastInputTime = input.timestamp
        }

        // 특수 키 처리
        if input.isBackspace {
            return await handleBackspace()
        }

        if input.isSpace {
            return await handleSpace()
        }

        if input.isReturn {
            return await handleReturn()
        }

        if input.isEscape {
            return await handleEscape()
        }

        // 한글 입력 모드에서만 문자 처리
        let isHangulMode = await MainActor.run {
            return currentInputMode == .hangul
        }
        guard isHangulMode else {
            return false // 다른 입력 메소드가 처리하도록
        }

        // 일반 문자 입력 처리
        guard let characters = input.characters, !characters.isEmpty else {
            return false
        }

        return await handleHangulInput(characters)
    }

    /// 특수 키 처리
    private func handleBackspace() async -> Bool {
        let currentStateValue = await MainActor.run {
            return currentState
        }

        if case .composing(let text) = currentStateValue, !text.isEmpty {
            // 조합 중인 텍스트에서 삭제
            let keyboardInput = KeyboardInput(
                keyCode: UInt16(kVK_Delete),
                characters: "\u{08}",
                modifierFlags: []
            )
            let result = await inputManager.processKeyboardInput(keyboardInput)
            await MainActor.run {
                if case .deleted = result {
                    inputStatistics.recordBackspace()
                    // updateComposedTextFromState() 제거 - HangulInputManager에서 직접 처리
                }
            }
            return true
        }

        return false // 기본 백스페이스 동작 허용
    }

    /// 스페이스 키 처리
    private func handleSpace() async -> Bool {
        let currentStateValue = await MainActor.run {
            return currentState
        }

        if case .composing = currentStateValue {
            // 조합 중인 텍스트 커밋
            await MainActor.run {
                commitComposedText()
            }
            return true
        }

        return false // 기본 스페이스 동작 허용
    }

    /// 리턴 키 처리
    private func handleReturn() async -> Bool {
        let currentStateValue = await MainActor.run {
            return currentState
        }

        if case .composing = currentStateValue {
            await MainActor.run {
                commitComposedText()
            }
            return true
        }

        return false // 기본 리턴 동작 허용
    }

    /// ESC 키 처리
    private func handleEscape() async -> Bool {
        let currentStateValue = await MainActor.run {
            return currentState
        }

        if case .composing = currentStateValue {
            // 조합 취소
            await MainActor.run {
                currentState = .idle
                // currentComposition 초기화 제거 - HangulInputManager에서 관리
            }
            return true
        }

        return false
    }

    /// 문자 입력 처리
    private func handleCharacterInput(_ characters: String) async -> Bool {
        // 한글 입력 모드에서만 처리
        let isHangulMode = await MainActor.run {
            return currentInputMode == .hangul
        }
        guard isHangulMode else {
            return false // 영어 모드에서는 다른 입력 메소드가 처리
        }

        return await handleHangulInput(characters)
    }

    /// 한글 입력 처리
    @MainActor
    private func handleHangulInput(_ characters: String) async -> Bool {
        do {
            // 한글 입력 처리
            let keyboardInput = KeyboardInput(
                keyCode: UInt16(characters.first?.asciiValue ?? 0),
                characters: characters,
                modifierFlags: []
            )
            let result = await inputManager.processKeyboardInput(keyboardInput)

                        // Main actor에서 속성 접근
            switch result {
            case .processed(let text):
                // 조합 중인 텍스트 업데이트
                currentState = .composing(text)
                inputStatistics.recordComposition(text)

            case .committed(let text):
                // 커밋된 텍스트 처리
                currentState = .committed(text)
                inputStatistics.recordCommit(text)
                await MainActor.run {
                    insertCommittedText()
                }

            case .deleted:
                // 삭제 처리
                inputStatistics.recordBackspace()

            case .noChange, .modeChanged:
                break
            }
        }

        await MainActor.run {
            currentState = .idle
            // updateComposedTextFromState() 제거 - 메소드 없음
        }

        return true
    }

    /// 영어 입력 처리
    @MainActor
    private func handleEnglishInput(_ characters: String) -> Bool {
        // 영어 모드에서는 그대로 통과
        insertText(characters)
        return false // 다른 입력 메소드가 처리하도록
    }



    private func handleSpecialKeys(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 0x33: // Backspace
            Task { await handleBackspace() }
            return true
        case 0x24: // Return
            Task { await handleReturn() }
            return true
        case 0x35: // Escape
            Task { await handleEscape() }
            return true
        case 0x31: // Space
            Task { await handleSpace() }
            return true
        default:
            return false
        }
    }



    @MainActor
    private func updateComposedText() {
        guard let client = currentClient else { return }

        if case .composing(let text) = currentState, !text.isEmpty {
            // 조합 텍스트 설정
            client.setMarkedText(text, selectionRange: NSRange(location: text.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            // 조합 텍스트 제거
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    @MainActor
    private func commitComposedText() {
        guard let client = currentClient else { return }

        if case .composing(let text) = currentState, !text.isEmpty {
            // 조합 텍스트를 일반 텍스트로 변환
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            currentState = .idle
        }
    }

    @MainActor
    private func insertCommittedText() {
        guard let client = currentClient else { return }

        if case .committed(let text) = currentState, !text.isEmpty {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            currentState = .idle
        }
    }

    private func insertText(_ text: String) {
        guard let client = currentClient else { return }

        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func handleStateChange(_ state: HangulInputState) {
        // 상태 변경 처리
        currentState = state

        // 조합 텍스트 업데이트
        Task { @MainActor in
            updateComposedText()
        }

        // 커밋된 텍스트 처리
        if case .committed(let text) = state, !text.isEmpty {
            Task { @MainActor in
                insertCommittedText()
            }
        }
    }

    private func handleModeChange(_ mode: HangulInputMode) {
        currentInputMode = mode
        updateInputMode()

        print("🔄 입력 모드 변경: \(mode.displayName)")
    }

    private func updateInputMode() {
        // 입력 모드에 따른 시스템 설정 업데이트
        // IMK의 입력 모드 설정 (필요시 구현)
    }

    // MARK: - Actions

    @objc private func toggleInputMode() {
        if currentInputMode == .hangul {
            currentInputMode = .english
        } else {
            currentInputMode = .hangul
        }

        updateInputMode()
        handleModeChange(currentInputMode)
    }
}
