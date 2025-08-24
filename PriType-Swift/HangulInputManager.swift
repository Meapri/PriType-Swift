// 공통 타입 정의 - 다른 파일들이 사용할 수 있도록 public
import Foundation
import LibHangul
import AppKit

/// 키보드 입력 정보를 나타내는 구조체
public struct KeyboardInput: Sendable {
    public let keyCode: UInt16
    public let characters: String?
    public let modifierFlags: NSEvent.ModifierFlags
    public let timestamp: TimeInterval

    public var isBackspace: Bool { keyCode == 0x33 }
    public var isSpace: Bool { keyCode == 0x31 }
    public var isReturn: Bool { keyCode == 0x24 }
    public var isEscape: Bool { keyCode == 0x35 }

    public var hasCommand: Bool {
        modifierFlags.contains(.command)
    }

    public var hasControl: Bool {
        modifierFlags.contains(.control)
    }

    public var hasOption: Bool {
        modifierFlags.contains(.option)
    }

    public var hasShift: Bool {
        modifierFlags.contains(.shift)
    }

    public init(keyCode: UInt16, characters: String?, modifierFlags: NSEvent.ModifierFlags, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.keyCode = keyCode
        self.characters = characters
        self.modifierFlags = modifierFlags
        self.timestamp = timestamp
    }
}

/// 한글 입력 상태를 나타내는 열거형
public enum HangulInputState: Sendable {
    case idle
    case composing(String)
    case committed(String)
    case error(String)
}

/// 한글 입력 모드를 나타내는 열거형
public enum HangulInputMode: String, Sendable {
    case hangul = "한글"
    case english = "영어"

    public var displayName: String { rawValue }
    public var isHangul: Bool { self == .hangul }
}

/// 한글 입력 결과를 나타내는 타입
public enum HangulInputResult: Sendable {
    case processed(String)
    case committed(String)
    case deleted
    case noChange
    case modeChanged(HangulInputMode)
}

// MARK: - 에러 정의

/// 한글 입력 처리 중 발생할 수 있는 에러
enum HangulInputError: LocalizedError, Sendable {
    case processingFailed(String)
    case backspaceFailed(String)
    case commitFailed(String)
    case initializationFailed(String)
    case invalidKeyCode(String)
    case unsupportedCharacter(String)

    var errorDescription: String? {
        switch self {
        case .processingFailed(let detail):
            return "한글 입력 처리 실패: \(detail)"
        case .backspaceFailed(let detail):
            return "백스페이스 처리 실패: \(detail)"
        case .commitFailed(let detail):
            return "커밋 처리 실패: \(detail)"
        case .initializationFailed(let detail):
            return "한글 입력 초기화 실패: \(detail)"
        case .invalidKeyCode(let detail):
            return "잘못된 키코드: \(detail)"
        case .unsupportedCharacter(let detail):
            return "지원하지 않는 문자: \(detail)"
        }
    }
}

// MARK: - 통계 구조체

/// 한글 입력 통계를 나타내는 구조체
struct HangulInputStatistics: Sendable {
    var totalCharacters: Int = 0
    var backspaces: Int = 0
    var spaces: Int = 0
    var returns: Int = 0
    var committedCompositions: Int = 0
    var errors: Int = 0

    mutating func recordKeyEvent() {
        totalCharacters += 1
    }

    mutating func recordBackspace() {
        backspaces += 1
    }

    mutating func recordSpace() {
        spaces += 1
    }

    mutating func recordReturn() {
        returns += 1
    }

    mutating func recordCommittedComposition() {
        committedCompositions += 1
    }

    mutating func recordError() {
        errors += 1
    }
}

// MARK: - 한글 입력 관리자

/// 실제 LibHangul API를 사용하는 한글 입력 관리자
public actor HangulInputManager {

    // MARK: - Properties

    /// 한글 입력 컨텍스트 - 실제 libhangul-swift 라이브러리의 ThreadSafeHangulInputContext
    private let inputContext: ThreadSafeHangulInputContext

    /// 현재 입력 모드
    public private(set) var inputMode: HangulInputMode = .english

    /// 현재 입력 상태
    public private(set) var currentState: HangulInputState = .idle

    /// 입력 통계
    private var inputStats = HangulInputStatistics()

    /// 상태 변경 핸들러
    private var onStateChanged: (@Sendable (HangulInputState) -> Void)?

    /// 모드 변경 핸들러
    private var onModeChanged: (@Sendable (HangulInputMode) -> Void)?

    // MARK: - Initialization

    /// 기본 생성자 (실제 libhangul-swift 라이브러리 사용)
    public init() {
        print("🇰🇷 HangulInputManager 실제 LibHangul API로 초기화")

        // 실제 API: createThreadSafeInputContext 함수로 생성
        // HangulInputConfiguration.default 사용
        self.inputContext = LibHangul.createThreadSafeInputContext(configuration: .default)

        print("✅ HangulInputManager 초기화 완료 - 실제 ThreadSafeHangulInputContext 사용")
    }

    // MARK: - Public Methods

    /// 키보드 입력 처리 (실제 LibHangul API 사용)
    public func processKeyboardInput(_ input: KeyboardInput) async -> HangulInputResult {
        inputStats.recordKeyEvent()

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

        // 일반 문자 입력 처리
        guard let characters = input.characters, !characters.isEmpty else {
            return .noChange
        }

        let firstChar = characters.first!
        let keyCode = Int(firstChar.asciiValue ?? 0)

        // 한글 모드에서만 LibHangul 처리
        if inputMode == .hangul && keyCode > 0 {
            // 실제 API: ThreadSafeHangulInputContext는 동기적 메소드지만 actor이므로 await 사용
            let processed = await inputContext.process(keyCode)
            if processed {
                let preeditChars = await inputContext.getPreeditString()
                let committedChars = await inputContext.getCommitString()

                // 커밋된 텍스트가 있으면 우선 처리
                if !committedChars.isEmpty {
                    let committedText = committedChars.map { Character(UnicodeScalar($0)!) }.reduce("", { $0 + String($1) })
                    currentState = .committed(committedText)
                    onStateChanged?(currentState)
                    return .committed(committedText)
                }

                // 조합 중인 텍스트 처리
                if !preeditChars.isEmpty {
                    let preeditText = preeditChars.map { Character(UnicodeScalar($0)!) }.reduce("", { $0 + String($1) })
                    currentState = .composing(preeditText)
                    onStateChanged?(currentState)
                    return .processed(preeditText)
                }
            }
        }

        return .noChange
    }

    /// 백스페이스 처리
    public func handleBackspace() async -> HangulInputResult {
        inputStats.recordBackspace()

        // 실제 API: ThreadSafeHangulInputContext는 동기적 메소드지만 actor이므로 await 사용
        let backspaced = await inputContext.backspace()

        if backspaced {
            let preeditChars = await inputContext.getPreeditString()
            if !preeditChars.isEmpty {
                let preeditText = preeditChars.map { Character(UnicodeScalar($0)!) }.reduce("", { $0 + String($1) })
                currentState = .composing(preeditText)
                onStateChanged?(currentState)
                return .processed(preeditText)
            } else {
                currentState = .idle
                onStateChanged?(currentState)
                return .deleted
            }
        }

        return .noChange
    }

    /// 스페이스 처리
    public func handleSpace() async -> HangulInputResult {
        inputStats.recordSpace()

        if case .composing = currentState {
            // 조합 중인 텍스트 커밋
            let committedChars = await inputContext.flush()
            if !committedChars.isEmpty {
                let committedText = committedChars.map { Character(UnicodeScalar($0)!) }.reduce("", { $0 + String($1) })
                currentState = .committed(committedText)
                onStateChanged?(currentState)
                return .committed(committedText)
            }
        }

        return .noChange
    }

    /// 리턴 처리
    public func handleReturn() async -> HangulInputResult {
        inputStats.recordReturn()

        if case .composing = currentState {
            // 조합 중인 텍스트 커밋
            let committedChars = await inputContext.flush()
            if !committedChars.isEmpty {
                let committedText = committedChars.map { Character(UnicodeScalar($0)!) }.reduce("", { $0 + String($1) })
                currentState = .committed(committedText)
                onStateChanged?(currentState)
                return .committed(committedText)
            }
        }

        return .noChange
    }

    /// ESC 처리
    public func handleEscape() async -> HangulInputResult {
        if case .composing = currentState {
            await inputContext.reset()
            currentState = .idle
            onStateChanged?(currentState)
            return .deleted
        }

        return .noChange
    }

    /// 입력 모드 토글
    public func toggleInputMode() async {
        inputMode = (inputMode == .hangul) ? .english : .hangul
        await inputContext.reset()
        currentState = .idle
        onModeChanged?(inputMode)
        print("🔄 입력 모드 변경: \(inputMode.displayName)")
    }

    /// 입력 모드 설정
    public func setInputMode(_ mode: HangulInputMode) async {
        if inputMode != mode {
            inputMode = mode
            await inputContext.reset()
            currentState = .idle
            onModeChanged?(inputMode)
            print("🔄 입력 모드 설정: \(inputMode.displayName)")
        }
    }

    /// 입력 초기화
    public func resetComposition() async {
        await inputContext.reset()
        currentState = .idle
        onStateChanged?(currentState)
    }

    /// 현재 조합 상태 반환
    public func getCurrentComposition() async -> String {
        let preeditChars = await inputContext.getPreeditString()
        return preeditChars.map { Character(UnicodeScalar($0)!) }.reduce("", { $0 + String($1) })
    }

    /// 현재 커밋된 텍스트 반환
    public func getCommittedText() async -> String {
        let committedChars = await inputContext.getCommitString()
        return committedChars.map { Character(UnicodeScalar($0)!) }.reduce("", { $0 + String($1) })
    }

    /// 상태 변경 핸들러 설정
    public func setStateChangedHandler(_ handler: @escaping @Sendable (HangulInputState) -> Void) {
        onStateChanged = handler
    }

    /// 모드 변경 핸들러 설정
    public func setModeChangedHandler(_ handler: @escaping @Sendable (HangulInputMode) -> Void) {
        onModeChanged = handler
    }

    // MARK: - Private Methods

    /// UCSChar 배열을 String으로 변환
    private func convertUCSCharArrayToString(_ ucsChars: [UCSChar]) -> String {
        return String(ucsChars.map { Character(UnicodeScalar($0)!) })
    }
}
