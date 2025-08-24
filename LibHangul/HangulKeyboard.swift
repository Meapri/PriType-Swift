//
//  HangulKeyboard.swift
//  LibHangul
//
//  Created by Sonic AI Assistant
//
//  한글 키보드 레이아웃 관리
//

import Foundation

/// 키보드 타입 열거형
public enum HangulKeyboardType: Int, Sendable {
    case jamo = 0      // 자모 단위 입력
    case jaso = 1      // 자소 단위 입력
    case romaja = 2    // 로마자 방식
    case jamoYet = 3   // 옛한글 자모
    case jasoYet = 4   // 옛한글 자소

    /// 키보드 타입 설명
    public var description: String {
        switch self {
        case .jamo:
            return "자모 단위"
        case .jaso:
            return "자소 단위"
        case .romaja:
            return "로마자"
        case .jamoYet:
            return "옛한글 자모"
        case .jasoYet:
            return "옛한글 자소"
        }
    }
}

/// 키보드 레이아웃을 정의하는 기본 클래스
public class HangulKeyboard {
    /// 키보드 식별자
    public let identifier: String
    /// 키보드 이름
    public let name: String
    /// 키보드 타입
    public private(set) var type: HangulKeyboardType

    /// 키 매핑 테이블 (ASCII -> 자모)
    internal var keyMap: [Int: UCSChar] = [:]

    public init(identifier: String, name: String, type: HangulKeyboardType = .jaso) {
        self.identifier = identifier
        self.name = name
        self.type = type
        setupDefaultMappings()
    }

    /// 키 코드를 자모로 변환
    /// - Parameter key: ASCII 키 코드
    /// - Returns: 변환된 자모 코드, 없으면 0
    public func mapKey(_ key: Int) -> UCSChar {
        return keyMap[key] ?? 0
    }

    /// 키보드 타입 설정
    /// - Parameter type: 새 키보드 타입
    public func setType(_ type: HangulKeyboardType) {
        self.type = type
    }

    /// 기본 키보드 매핑 설정 (두벌식 기준)
    internal func setupDefaultMappings() {
        // 자음 - 표준 두벌식
        keyMap[Int(Character("r").asciiValue!)] = 0x1100  // ㄱ
        keyMap[Int(Character("R").asciiValue!)] = 0x1101  // ㄲ
        // 's' 키는 초성(ㄷ)으로 매핑 (종성 매핑은 유지)
        keyMap[Int(Character("s").asciiValue!)] = 0x1102  // ㄷ
        keyMap[Int(Character("E").asciiValue!)] = 0x1104  // ㄺ
        keyMap[Int(Character("f").asciiValue!)] = 0x1105  // ㅁ
        keyMap[Int(Character("a").asciiValue!)] = 0x1106  // ㅂ
        keyMap[Int(Character("q").asciiValue!)] = 0x1107  // ㅃ
        keyMap[Int(Character("Q").asciiValue!)] = 0x1108  // ㅄ
        keyMap[Int(Character("t").asciiValue!)] = 0x1109  // ㅅ
        keyMap[Int(Character("d").asciiValue!)] = 0x110B  // ㅇ
        keyMap[Int(Character("w").asciiValue!)] = 0x110C  // ㅈ
        keyMap[Int(Character("W").asciiValue!)] = 0x110D  // ㅉ
        keyMap[Int(Character("c").asciiValue!)] = 0x110E  // ㅊ
        keyMap[Int(Character("z").asciiValue!)] = 0x110F  // ㅋ
        keyMap[Int(Character("x").asciiValue!)] = 0x1110  // ㅌ
        keyMap[Int(Character("v").asciiValue!)] = 0x1111  // ㅍ
        keyMap[Int(Character("g").asciiValue!)] = 0x1112  // ㅎ

        // 모음 - 두벌식 표준 매핑
        keyMap[Int(Character("k").asciiValue!)] = 0x1161  // ㅏ
        keyMap[Int(Character("o").asciiValue!)] = 0x1169  // ㅗ (초성 매핑보다 우선)
        keyMap[Int(Character("i").asciiValue!)] = 0x1163  // ㅑ
        keyMap[Int(Character("O").asciiValue!)] = 0x1164  // ㅒ
        keyMap[Int(Character("j").asciiValue!)] = 0x1165  // ㅓ
        keyMap[Int(Character("e").asciiValue!)] = 0x1166  // ㅔ
        keyMap[Int(Character("p").asciiValue!)] = 0x1166  // ㅔ (p도 동일하게 매핑)
        keyMap[Int(Character("u").asciiValue!)] = 0x1167  // ㅕ
        keyMap[Int(Character("P").asciiValue!)] = 0x1168  // ㅖ
        keyMap[Int(Character("h").asciiValue!)] = 0x1169  // ㅗ (초성 매핑보다 우선)
        keyMap[Int(Character("y").asciiValue!)] = 0x116D  // ㅛ
        keyMap[Int(Character("n").asciiValue!)] = 0x116E  // ㅜ
        keyMap[Int(Character("b").asciiValue!)] = 0x1172  // ㅠ
        keyMap[Int(Character("m").asciiValue!)] = 0x1173  // ㅡ
        keyMap[Int(Character("l").asciiValue!)] = 0x1175  // ㅣ (초성 매핑보다 우선)

        // 종성 위치
        keyMap[Int(Character("F").asciiValue!)] = 0x11A8  // ㄱ
        keyMap[Int(Character("R").asciiValue!)] = 0x11A9  // ㄲ
        keyMap[Int(Character("s").asciiValue!)] = 0x11AB  // ㄴ (초성 매핑보다 우선)
        keyMap[Int(Character("T").asciiValue!)] = 0x11AB  // ㄴ
        keyMap[Int(Character("C").asciiValue!)] = 0x11AE  // ㄹ
        keyMap[Int(Character("E").asciiValue!)] = 0x11B7  // ㅁ
        keyMap[Int(Character("7").asciiValue!)] = 0x11B8  // ㅂ
        keyMap[Int(Character("8").asciiValue!)] = 0x11BA  // ㅅ
        keyMap[Int(Character("D").asciiValue!)] = 0x11BB  // ㅆ
        keyMap[Int(Character("X").asciiValue!)] = 0x11BC  // ㅇ
        keyMap[Int(Character("4").asciiValue!)] = 0x11BD  // ㅈ
        keyMap[Int(Character("V").asciiValue!)] = 0x11BE  // ㅊ
        keyMap[Int(Character("5").asciiValue!)] = 0x11BF  // ㅋ
        keyMap[Int(Character("%").asciiValue!)] = 0x11C0  // ㅌ
        keyMap[Int(Character("^").asciiValue!)] = 0x11C1  // ㅍ
        keyMap[Int(Character("&").asciiValue!)] = 0x11C2  // ㅎ
    }
}

/// 기본 키보드 레이아웃 구현체
public final class HangulKeyboardDefault: HangulKeyboard {
    public override init(identifier: String, name: String, type: HangulKeyboardType = .jaso) {
        super.init(identifier: identifier, name: name, type: type)
        // 추가적인 키 매핑 설정
        setupAdditionalMappings()
    }

    /// 추가적인 키 매핑 설정
    private func setupAdditionalMappings() {
        // 1 키를 종성 ㄴ으로 매핑 (두벌식용)
        keyMap[Int(Character("1").asciiValue!)] = 0x11AB  // ㄴ (종성용)
        // 불필요한 매핑 제거를 하지 않음 - 모든 키가 한글 입력에 사용되도록 함
    }

    public override func mapKey(_ key: Int) -> UCSChar {
        return keyMap[key] ?? 0
    }
}

/// 세벌식 키보드 구현체
public final class HangulKeyboard3Set: HangulKeyboard {
    public override init(identifier: String, name: String, type: HangulKeyboardType = .jaso) {
        super.init(identifier: identifier, name: name, type: type)
        setup3SetMappings()
    }

    /// 세벌식 자판 매핑 설정
    private func setup3SetMappings() {
        // 세벌식 자판 매핑 (간략 버전)
        // 실제 세벌식 구현은 더 복잡하지만 여기서는 기본적인 매핑만 구현

        // 초성 위치
        keyMap[Int(Character("k").asciiValue!)] = 0x1100  // ㄱ
        keyMap[Int(Character("h").asciiValue!)] = 0x1101  // ㄲ
        keyMap[Int(Character("u").asciiValue!)] = 0x1102  // ㄷ
        keyMap[Int(Character("y").asciiValue!)] = 0x1103  // ㄹ
        keyMap[Int(Character("i").asciiValue!)] = 0x1105  // ㅁ
        keyMap[Int(Character("n").asciiValue!)] = 0x1106  // ㅂ
        keyMap[Int(Character("j").asciiValue!)] = 0x1107  // ㅃ
        keyMap[Int(Character("l").asciiValue!)] = 0x1109  // ㅅ
        keyMap[Int(Character(";").asciiValue!)] = 0x110A  // ㅆ
        keyMap[Int(Character("o").asciiValue!)] = 0x110B  // ㅇ
        keyMap[Int(Character("0").asciiValue!)] = 0x110C  // ㅈ
        keyMap[Int(Character("p").asciiValue!)] = 0x110E  // ㅊ
        keyMap[Int(Character("m").asciiValue!)] = 0x110F  // ㅋ
        keyMap[Int(Character(",").asciiValue!)] = 0x1110  // ㅌ
        keyMap[Int(Character(".").asciiValue!)] = 0x1111  // ㅍ
        keyMap[Int(Character("/").asciiValue!)] = 0x1112  // ㅎ

        // 중성 위치
        // 'f' 키는 초성(ㅁ)으로 이미 매핑되어 있으므로 중성 매핑에서 제외
        // 'r' 키는 초성(ㄱ)으로 이미 매핑되어 있으므로 중성 매핑에서 제외
        keyMap[Int(Character("k").asciiValue!)] = 0x1161  // ㅏ
        keyMap[Int(Character("6").asciiValue!)] = 0x1163  // ㅑ
        keyMap[Int(Character("c").asciiValue!)] = 0x1165  // ㅓ
        keyMap[Int(Character("e").asciiValue!)] = 0x1166  // ㅔ
        keyMap[Int(Character("7").asciiValue!)] = 0x1167  // ㅕ
        keyMap[Int(Character("v").asciiValue!)] = 0x1169  // ㅗ
        keyMap[Int(Character("4").asciiValue!)] = 0x116D  // ㅛ
        keyMap[Int(Character("b").asciiValue!)] = 0x116E  // ㅜ
        keyMap[Int(Character("5").asciiValue!)] = 0x1172  // ㅠ
        keyMap[Int(Character("t").asciiValue!)] = 0x1173  // ㅡ
        keyMap[Int(Character("g").asciiValue!)] = 0x1175  // ㅣ

        // 종성 위치
        keyMap[Int(Character("d").asciiValue!)] = 0x11A8  // ㄱ
        keyMap[Int(Character("s").asciiValue!)] = 0x11A9  // ㄲ
        keyMap[Int(Character("w").asciiValue!)] = 0x11AB  // ㄷ
        keyMap[Int(Character("3").asciiValue!)] = 0x11AE  // ㄹ
        keyMap[Int(Character("a").asciiValue!)] = 0x11B7  // ㅁ
        keyMap[Int(Character("z").asciiValue!)] = 0x11B8  // ㅂ
        keyMap[Int(Character("x").asciiValue!)] = 0x11BA  // ㅅ
        keyMap[Int(Character("2").asciiValue!)] = 0x11BB  // ㅆ
        keyMap[Int(Character("q").asciiValue!)] = 0x11BC  // ㅇ
        keyMap[Int(Character("1").asciiValue!)] = 0x11BD  // ㅈ
        keyMap[Int(Character("9").asciiValue!)] = 0x11BE  // ㅊ
        keyMap[Int(Character("8").asciiValue!)] = 0x11BF  // ㅋ
        keyMap[Int(Character("-").asciiValue!)] = 0x11C0  // ㅌ
        keyMap[Int(Character("=").asciiValue!)] = 0x11C1  // ㅍ
        keyMap[Int(Character("]").asciiValue!)] = 0x11C2  // ㅎ
    }

    public override func mapKey(_ key: Int) -> UCSChar {
        return keyMap[key] ?? 0
    }
}

/// 키보드 관리자
public final class HangulKeyboardManager {
    /// 등록된 키보드들
    private var keyboards: [String: HangulKeyboard] = [:]

    /// 기본 키보드들 등록
    public init() {
        registerDefaultKeyboards()
    }

    /// 키보드 등록
    /// - Parameter keyboard: 등록할 키보드
    public func registerKeyboard(_ keyboard: HangulKeyboard) {
        keyboards[keyboard.identifier] = keyboard
    }

    /// 키보드 조회
    /// - Parameter identifier: 키보드 식별자
    /// - Returns: 키보드 객체, 없으면 nil
    public func keyboard(for identifier: String) -> HangulKeyboard? {
        keyboards[identifier]
    }

    /// 등록된 모든 키보드의 식별자 목록
    /// - Returns: 키보드 식별자 배열
    public func keyboardIdentifiers() -> [String] {
        Array(keyboards.keys).sorted()
    }

    /// 등록된 모든 키보드 목록
    /// - Returns: 키보드 객체 배열
    public func allKeyboards() -> [HangulKeyboard] {
        Array(keyboards.values)
    }

    /// 기본 키보드들 등록
    private func registerDefaultKeyboards() {
        // 두벌식 키보드
        let dubeol = HangulKeyboardDefault(
            identifier: "2",
            name: "두벌식",
            type: .jaso
        )
        registerKeyboard(dubeol)

        // 세벌식 키보드
        let sebeol = HangulKeyboard3Set(
            identifier: "3",
            name: "세벌식"
        )
        registerKeyboard(sebeol)

        // 두벌식 옛한글
        let dubeolYet = HangulKeyboardDefault(
            identifier: "2y",
            name: "두벌식 옛한글",
            type: .jasoYet
        )
        registerKeyboard(dubeolYet)

        // 세벌식 옛한글
        let sebeolYet = HangulKeyboard3Set(
            identifier: "3y",
            name: "세벌식 옛한글"
        )
        registerKeyboard(sebeolYet)
    }
}