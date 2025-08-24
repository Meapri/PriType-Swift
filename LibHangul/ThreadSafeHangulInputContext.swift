//
//  ThreadSafeHangulInputContext.swift
//  LibHangul
//
//  Swift 6 동시성 제한에 대응하는 스레드 안전한 한글 입력 컨텍스트 래퍼
//

import Foundation

/// 스레드 안전한 한글 입력 컨텍스트 액터
/// Swift 6의 엄격한 동시성 제한을 준수하기 위한 래퍼
public actor ThreadSafeHangulInputContext {

    // MARK: - Properties

    /// 내부적으로 사용하는 실제 컨텍스트 (actor에 의해 보호됨)
    private var context: HangulInputContext
    private let configuration: HangulInputConfiguration

    // MARK: - Initialization

    /// 기본 생성자
    public init(keyboard: String? = nil, configuration: HangulInputConfiguration = .default) {
        self.configuration = configuration
        self.context = HangulInputContext(keyboard: keyboard, configuration: configuration)
    }

    /// 키보드 지정 생성자
    public init(keyboard: HangulKeyboard, configuration: HangulInputConfiguration = .default) {
        self.configuration = configuration
        self.context = HangulInputContext(keyboard: keyboard, configuration: configuration)
    }

    /// 설정으로만 초기화
    public init(configuration: HangulInputConfiguration = .default) {
        self.configuration = configuration
        self.context = HangulInputContext(configuration: configuration)
    }

    // MARK: - Public Methods

    /// 키 입력 처리 (스레드 안전)
    /// - Parameter key: ASCII 키 코드
    /// - Returns: 키가 처리되었으면 true
    public func process(_ key: Int) -> Bool {
        return context.process(key)
    }



    /// 백스페이스 처리
    /// - Returns: 처리되었으면 true
    public func backspace() -> Bool {
        return context.backspace()
    }

    /// 버퍼 초기화
    public func reset() {
        context.reset()
    }

    /// 현재 사전 편집 문자열 반환
    /// - Returns: 사전 편집 문자열
    public func getPreeditString() -> [UCSChar] {
        return context.getPreeditString()
    }

    /// 커밋된 문자열 반환 및 초기화
    /// - Returns: 커밋된 문자열
    public func getCommitString() -> [UCSChar] {
        return context.getCommitString()
    }

    /// 모든 내용을 커밋
    /// - Returns: 커밋된 문자열
    public func flush() -> [UCSChar] {
        return context.flush()
    }

    /// 키보드 설정
    /// - Parameter keyboard: 키보드 식별자
    public func setKeyboard(with identifier: String) {
        context.setKeyboard(with: identifier)
    }

    /// 키보드 설정
    /// - Parameter keyboard: 키보드 객체
    public func setKeyboard(_ keyboard: HangulKeyboard) {
        context.setKeyboard(keyboard)
    }

    /// 출력 모드 설정
    /// - Parameter mode: 출력 모드
    public func setOutputMode(_ mode: HangulOutputMode) {
        context.setOutputMode(mode)
    }

    /// 옵션 설정
    /// - Parameters:
    ///   - option: 옵션
    ///   - value: 설정값
    public func setOption(_ option: HangulInputContextOption, value: Bool) {
        context.setOption(option, value: value)
    }

    /// 옵션 확인
    /// - Parameter option: 확인할 옵션
    /// - Returns: 옵션이 설정되어 있으면 true
    public func getOption(_ option: HangulInputContextOption) -> Bool {
        return context.getOption(option)
    }

    /// 버퍼가 비어있는지 확인
    /// - Returns: 비어있으면 true
    public func isEmpty() -> Bool {
        return context.isEmpty()
    }

    /// 현재 상태를 문자열로 반환
    /// - Returns: 현재 상태를 나타내는 문자열
    public func currentStateDescription() -> String {
        return context.currentStateDescription()
    }

    // MARK: - Configuration Access

    /// 최대 버퍼 크기
    public var maxBufferSize: Int {
        get { context.maxBufferSize }
        set { context.maxBufferSize = newValue }
    }

    /// NFC 정규화 강제 사용
    public var forceNFCNormalization: Bool {
        get { context.forceNFCNormalization }
        set { context.forceNFCNormalization = newValue }
    }

    /// 관용 입력 모드 활성화 여부
    public var enableIdiomaticInput: Bool {
        get { context.enableIdiomaticInput }
        set { context.enableIdiomaticInput = newValue }
    }

    /// 버퍼 상태 모니터링 활성화
    public var enableBufferMonitoring: Bool {
        get { context.enableBufferMonitoring }
        set { context.enableBufferMonitoring = newValue }
    }

    /// 자동 오류 복구
    public var autoErrorRecovery: Bool {
        get { context.autoErrorRecovery }
        set { context.autoErrorRecovery = newValue }
    }

    /// 파일명 호환성 모드
    public var filenameCompatibilityMode: Bool {
        get { context.filenameCompatibilityMode }
        set { context.filenameCompatibilityMode = newValue }
    }

    // MARK: - State Checks

    /// 초성이 있는지 확인
    /// - Returns: 초성이 있으면 true
    public func hasChoseong() -> Bool {
        return context.hasChoseong()
    }

    /// 중성이 있는지 확인
    /// - Returns: 중성이 있으면 true
    public func hasJungseong() -> Bool {
        return context.hasJungseong()
    }

    /// 종성이 있는지 확인
    /// - Returns: 종성이 있으면 true
    public func hasJongseong() -> Bool {
        return context.hasJongseong()
    }

    // MARK: - Utility Methods

    /// 유니코드 정규화된 문자열 반환
    /// - Parameter text: 정규화할 텍스트
    /// - Returns: NFC 정규화된 문자열
    public func normalizeUnicode(_ text: [UCSChar]) -> [UCSChar] {
        return context.normalizeUnicode(text)
    }

    /// 파일명용 정규화
    /// - Parameter text: 정규화할 텍스트
    /// - Returns: 파일명 호환성을 위한 정규화된 텍스트
    public func normalizeForFilename(_ text: [UCSChar]) -> [UCSChar] {
        return context.normalizeForFilename(text)
    }

    /// 크로스플랫폼 호환성을 위한 변환
    /// - Parameter text: 변환할 텍스트
    /// - Returns: 플랫폼 호환성을 보장한 텍스트
    public func ensureCrossPlatformCompatibility(_ text: [UCSChar]) -> [UCSChar] {
        return context.ensureCrossPlatformCompatibility(text)
    }
}

// MARK: - Convenience Extensions

extension ThreadSafeHangulInputContext {
    /// 문자열을 한글 입력 컨텍스트에 입력
    /// - Parameter string: 입력할 문자열
    /// - Returns: 처리 결과
    public func process(_ string: String) -> Bool {
        var success = false
        for char in string.unicodeScalars {
            let key = Int(char.value)
            if process(key) {
                success = true
            }
        }
        return success
    }
}

// MARK: - Sendable Result Types

/// 스레드 안전한 입력 처리 결과
public struct HangulInputResult: Sendable {
    public let processed: Bool
    public let preedit: [UCSChar]
    public let committed: [UCSChar]

    public init(processed: Bool, preedit: [UCSChar], committed: [UCSChar]) {
        self.processed = processed
        self.preedit = preedit
        self.committed = committed
    }
}

/// 스레드 안전한 배치 처리
extension ThreadSafeHangulInputContext {

    /// 여러 키를 한 번에 처리 (배치 작업용)
    /// - Parameter keys: 처리할 키들의 배열
    /// - Returns: 각 키 처리 결과
    public func processBatch(_ keys: [Int]) -> [HangulInputResult] {
        var results: [HangulInputResult] = []

        for key in keys {
            let processed = process(key)
            let preedit = getPreeditString()
            let committed = getCommitString()

            results.append(HangulInputResult(
                processed: processed,
                preedit: preedit,
                committed: committed
            ))
        }

        return results
    }

    /// 텍스트를 완전히 처리하고 결과를 반환
    /// - Parameter text: 처리할 텍스트
    /// - Returns: 최종 처리 결과
    public func processText(_ text: String) -> HangulInputResult {
        let keys = text.unicodeScalars.map { Int($0.value) }
        let batchResults = processBatch(keys)

        // 마지막 결과만 반환
        return batchResults.last ?? HangulInputResult(processed: false, preedit: [], committed: [])
    }
}
