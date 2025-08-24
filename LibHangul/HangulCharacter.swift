//
//  HangulCharacter.swift
//  LibHangul
//
//  Created by Sonic AI Assistant
//
//  한글 자모 관련 타입과 기본 연산을 정의하는 모듈
//

import Foundation

/// 한글 음절의 구성 요소를 나타내는 열거형
public enum HangulSyllableComponent: Sendable {
    case choseong  // 초성
    case jungseong // 중성
    case jongseong // 종성
}

/// 한글 자모의 결합 가능 여부를 나타내는 열거형
public enum HangulJamoConjoinability: Sendable {
    case conjoinable     // 결합 가능
    case nonConjoinable  // 결합 불가능
}

/// 한글 음절의 완성도를 나타내는 열거형
public enum HangulSyllableCompleteness: Sendable {
    case incomplete // 미완성 (자모만 있는 상태)
    case complete   // 완성 (음절 형태)
}

/// UCS-4 코드 단위의 글자 코드 값
/// libhangul의 ucschar 타입에 대응
public typealias UCSChar = UInt32

/// 한글 자모와 관련된 상수들
public enum HangulConstants: Sendable {
    // 음절 구성 관련
    @usableFromInline
    static let syllableBase: UCSChar = 0xAC00
    @usableFromInline
    static let choseongBase: UCSChar = 0x1100
    @usableFromInline
    static let jungseongBase: UCSChar = 0x1161
    @usableFromInline
    static let jongseongBase: UCSChar = 0x11A7

    @usableFromInline
    static let njungseong = 21
    @usableFromInline
    static let njongseong = 28

    // 필러 문자들
    @usableFromInline
    static let choseongFiller: UCSChar = 0x115F
    @usableFromInline
    static let jungseongFiller: UCSChar = 0x1160

    // 유니코드 범위
    @usableFromInline
    static let choseongRange: ClosedRange<UCSChar> = 0x1100...0x115F
    @usableFromInline
    static let jungseongRange: ClosedRange<UCSChar> = 0x1160...0x11A7
    @usableFromInline
    static let jongseongRange: ClosedRange<UCSChar> = 0x11A8...0x11FF
    @usableFromInline
    static let syllableRange: ClosedRange<UCSChar> = 0xAC00...0xD7A3
    @usableFromInline
    static let cjamoRange: ClosedRange<UCSChar> = 0x3131...0x318E

    // 확장 영역
    @usableFromInline
    static let choseongExtARange: ClosedRange<UCSChar> = 0xA960...0xA97C
    @usableFromInline
    static let jungseongExtBRange: ClosedRange<UCSChar> = 0xD7B0...0xD7C6
    @usableFromInline
    static let jongseongExtBRange: ClosedRange<UCSChar> = 0xD7CB...0xD7FB
}

/// 한글 음절을 구성하는 자모들을 담는 구조체
public struct HangulJamoCombination: Sendable {
    public var choseong: UCSChar = 0    // 초성
    public var jungseong: UCSChar = 0   // 중성
    public var jongseong: UCSChar = 0   // 종성

    public init(choseong: UCSChar = 0, jungseong: UCSChar = 0, jongseong: UCSChar = 0) {
        self.choseong = choseong
        self.jungseong = jungseong
        self.jongseong = jongseong
    }

    /// 모든 자모가 비어있는지 확인
    @inlinable
    public var isEmpty: Bool {
        choseong == 0 && jungseong == 0 && jongseong == 0
    }

    /// 유효한 조합인지 확인
    @inlinable
    public var isValid: Bool {
        (choseong == 0 || HangulCharacter.isChoseong(choseong)) &&
        (jungseong == 0 || HangulCharacter.isJungseong(jungseong)) &&
        (jongseong == 0 || HangulCharacter.isJongseong(jongseong))
    }
}

/// 한글 자모 관련 기능을 제공하는 클래스
public final class HangulCharacter: Sendable {

    // MARK: - Performance Optimizations

    /// 자모 유니코드 범위 캐시 (Int로 변환)
    @usableFromInline
    static let chosungRange = Int(0x1100)...Int(0x115F)
    @usableFromInline
    static let jungseongRange = Int(0x1160)...Int(0x11A7)
    @usableFromInline
    static let jongseongRange = Int(0x11A8)...Int(0x11FF)
    @usableFromInline
    static let syllableRange = Int(0xAC00)...Int(0xD7A3)
    @usableFromInline
    static let cjamoRange = Int(0x3131)...Int(0x318E)

    /// 확장 범위 캐시
    @usableFromInline
    static let chosungExtARange = Int(0xA960)...Int(0xA97C)
    @usableFromInline
    static let jungseongExtBRange = Int(0xD7B0)...Int(0xD7C6)
    @usableFromInline
    static let jongseongExtBRange = Int(0xD7CB)...Int(0xD7FB)

    /// 결합 가능성 캐시 (성능 최적화)
    @usableFromInline
    static let chosungConjoinableRange = Int(0x1100)...Int(0x1112)
    @usableFromInline
    static let jungseongConjoinableRange = Int(0x1161)...Int(0x1175)
    @usableFromInline
    static let jongseongConjoinableRange = Int(0x11A7)...Int(0x11C2)

    // MARK: - 자모 판별 함수들

    /// 초성인지 확인
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 초성이면 true
    @inlinable
    public static func isChoseong(_ c: UCSChar) -> Bool {
        let intValue = Int(c)
        return chosungRange.contains(intValue) || chosungExtARange.contains(intValue)
    }

    /// 중성인지 확인
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 중성이면 true
    @inlinable
    public static func isJungseong(_ c: UCSChar) -> Bool {
        let intValue = Int(c)
        return jungseongRange.contains(intValue) || jungseongExtBRange.contains(intValue)
    }

    /// 종성인지 확인
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 종성이면 true
    @inlinable
    public static func isJongseong(_ c: UCSChar) -> Bool {
        let intValue = Int(c)
        return jongseongRange.contains(intValue) || jongseongExtBRange.contains(intValue)
    }

    /// 한글 음절인지 확인
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 한글 음절이면 true
    @inlinable
    public static func isSyllable(_ c: UCSChar) -> Bool {
        syllableRange.contains(Int(c))
    }

    /// 자모인지 확인 (초성, 중성, 종성 중 하나)
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 자모이면 true
    @inlinable
    public static func isJamo(_ c: UCSChar) -> Bool {
        isChoseong(c) || isJungseong(c) || isJongseong(c)
    }

    /// 호환 자모인지 확인
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 호환 자모이면 true
    @inlinable
    public static func isCJamo(_ c: UCSChar) -> Bool {
        cjamoRange.contains(Int(c))
    }

    /// 결합 가능한 초성인지 확인
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 결합 가능하면 true
    @inlinable
    public static func isChoseongConjoinable(_ c: UCSChar) -> Bool {
        chosungConjoinableRange.contains(Int(c))
    }

    /// 결합 가능한 중성인지 확인
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 결합 가능하면 true
    @inlinable
    public static func isJungseongConjoinable(_ c: UCSChar) -> Bool {
        jungseongConjoinableRange.contains(Int(c))
    }

    /// 결합 가능한 종성인지 확인
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 결합 가능하면 true
    @inlinable
    public static func isJongseongConjoinable(_ c: UCSChar) -> Bool {
        // 종성 필러(0x11A7)는 음절 결합 시 사용되므로 true로 처리
        jongseongConjoinableRange.contains(Int(c))
    }

    /// 결합 가능한 자모인지 확인
    /// - Parameter c: 검사할 UCS 코드
    /// - Returns: 결합 가능하면 true
    @inlinable
    public static func isJamoConjoinable(_ c: UCSChar) -> Bool {
        isChoseongConjoinable(c) || isJungseongConjoinable(c) || isJongseongConjoinable(c)
    }

    // MARK: - 음절 결합/분해

    /// 자모들을 음절로 결합
    /// - Parameters:
    ///   - choseong: 초성
    ///   - jungseong: 중성
    ///   - jongseong: 종성 (0이면 종성 없음)
    /// - Returns: 결합된 음절 코드, 실패시 0
    @inlinable
    public static func jamoToSyllable(choseong: UCSChar, jungseong: UCSChar, jongseong: UCSChar = 0) -> UCSChar {
        // 유효성 검증을 먼저 수행
        guard isChoseongConjoinable(choseong) && isJungseongConjoinable(jungseong) else {
            return 0
        }

        if jongseong != 0 && !isJongseongConjoinable(jongseong) {
            return 0
        }

        // 최적화된 계산
        let c = choseong - HangulConstants.choseongBase
        let j = jungseong - HangulConstants.jungseongBase
        let o = (jongseong == 0) ? 0 : (jongseong - HangulConstants.jongseongBase)

        return ((c * UInt32(HangulConstants.njungseong) + j) * UInt32(HangulConstants.njongseong) + o) + HangulConstants.syllableBase
    }

    /// 음절을 자모로 분해
    /// - Parameter syllable: 분해할 음절
    /// - Returns: 분해된 자모 조합
    @inlinable
    public static func syllableToJamo(_ syllable: UCSChar) -> HangulJamoCombination {
        guard isSyllable(syllable) else {
            return HangulJamoCombination()
        }

        let s = syllable - HangulConstants.syllableBase
        let jongseongIndex = s % UInt32(HangulConstants.njongseong)

        return HangulJamoCombination(
            choseong: HangulConstants.choseongBase + (s / UInt32(HangulConstants.njungseong * HangulConstants.njongseong)),
            jungseong: HangulConstants.jungseongBase + ((s / UInt32(HangulConstants.njongseong)) % UInt32(HangulConstants.njungseong)),
            jongseong: jongseongIndex == 0 ? 0 : (HangulConstants.jongseongBase + jongseongIndex)
        )
    }

    // MARK: - 자모 변환

    /// 자모를 호환 자모로 변환
    /// - Parameter jamo: 변환할 자모
    /// - Returns: 대응되는 호환 자모, 없으면 원본 반환
    public static func jamoToCJamo(_ jamo: UCSChar) -> UCSChar {
        // 자모 변환 테이블 (간략 버전)
        let jamoTable: [UCSChar: UCSChar] = [
            0x1100: 0x3131, 0x1101: 0x3132, 0x1102: 0x3134, 0x1103: 0x3137,
            0x1104: 0x3138, 0x1105: 0x3139, 0x1106: 0x3141, 0x1107: 0x3142,
            0x1108: 0x3143, 0x1109: 0x3145, 0x110A: 0x3146, 0x110B: 0x3147,
            0x110C: 0x3148, 0x110D: 0x3149, 0x110E: 0x314A, 0x110F: 0x314B,
            0x1110: 0x314C, 0x1111: 0x314D, 0x1112: 0x314E,
            0x1160: 0x3164,
            0x1161: 0x314F, 0x1162: 0x3150, 0x1163: 0x3151, 0x1164: 0x3152,
            0x1165: 0x3153, 0x1166: 0x3154, 0x1167: 0x3155, 0x1168: 0x3156,
            0x1169: 0x3157, 0x116A: 0x3158, 0x116B: 0x3159, 0x116C: 0x315A,
            0x116D: 0x315B, 0x116E: 0x315C, 0x116F: 0x315D, 0x1170: 0x315E,
            0x1171: 0x315F, 0x1172: 0x3160, 0x1173: 0x3161, 0x1174: 0x3162,
            0x1175: 0x3163
        ]

        return jamoTable[jamo] ?? jamo
    }

    // MARK: - 호환 자모 변환

    /// 호환 자모를 조합형 자모로 변환 (용도별)
    /// - Parameters:
    ///   - c: 변환할 호환 자모
    ///   - as: 변환 목적 (초성, 중성, 종성)
    /// - Returns: 조합형 자모 코드 (변환 실패 시 원본 반환)
    @inlinable
    public static func compatibilityJamoToJamo(_ c: UCSChar, as usage: JamoUsage = .choseong) -> UCSChar {
        // 호환 초성/중성 (0x3131-0x314E) -> 조합형 초성 (0x1100-0x1112)
        if c >= 0x3131 && c <= 0x314E {
            switch usage {
            case .choseong:
                // 초성 매핑: 각 호환 초성을 올바른 조합형 초성으로 매핑
                let choseongMap: [UCSChar: UCSChar] = [
                    0x3131: 0x1100, // ㄱ -> ㄱ
                    0x3132: 0x1101, // ㄲ -> ㄲ
                    0x3134: 0x1102, // ㄴ -> ㄴ
                    0x3137: 0x1103, // ㄷ -> ㄷ
                    0x3138: 0x1104, // ㄸ -> ㄸ
                    0x3139: 0x1105, // ㄹ -> ㄹ
                    0x3141: 0x1106, // ㅁ -> ㅁ
                    0x3142: 0x1107, // ㅂ -> ㅂ
                    0x3143: 0x1108, // ㅃ -> ㅃ
                    0x3145: 0x1109, // ㅅ -> ㅅ
                    0x3146: 0x110A, // ㅆ -> ㅆ
                    0x3147: 0x110B, // ㅇ -> ㅇ
                    0x3148: 0x110C, // ㅈ -> ㅈ
                    0x3149: 0x110D, // ㅉ -> ㅉ
                    0x314A: 0x110E, // ㅊ -> ㅊ
                    0x314B: 0x110F, // ㅋ -> ㅋ
                    0x314C: 0x1110, // ㅌ -> ㅌ
                    0x314D: 0x1111, // ㅍ -> ㅍ
                    0x314E: 0x1112, // ㅎ -> ㅎ
                ]
                return choseongMap[c] ?? c
            case .jungseong:
                return c - 0x3131 + 0x1161
            case .jongseong:
                // 종성 매핑: ㄱ(0x3131) -> ㄱ(0x11A8), ㄲ(0x3132) -> ㄲ(0x11A9), ...
                let jongseongMap: [UCSChar: UCSChar] = [
                    0x3131: 0x11A8, // ㄱ -> ᆨ
                    0x3132: 0x11A9, // ㄲ -> ᆩ
                    0x3133: 0x11AA, // ㄳ -> ᆪ
                    0x3134: 0x11AB, // ㄴ -> ᆫ
                    0x3135: 0x11AC, // ㄵ -> ᆬ
                    0x3136: 0x11AD, // ㄶ -> ᆭ
                    0x3137: 0x11AE, // ㄷ -> ᆮ
                    0x3138: 0x11AF, // ㄸ -> ᆯ
                    0x3139: 0x11AF, // ㄹ -> ᆯ
                    0x313A: 0x11B0, // ㄺ -> ᆰ
                    0x313B: 0x11B1, // ㄻ -> ᆱ
                    0x313C: 0x11B2, // ㄼ -> ᆲ
                    0x313D: 0x11B3, // ㄽ -> ᆳ
                    0x313E: 0x11B4, // ㄾ -> ᆴ
                    0x313F: 0x11B5, // ㄿ -> ᆵ
//                    0x3140: 0x11B6, // ㅀ -> ᆶ (ㄸ이 이미 0x3138에 매핑됨)
                    0x3141: 0x11B7, // ㅁ -> ᆷ
                    0x3142: 0x11B8, // ㅂ -> ᆸ
                    0x3143: 0x11B9, // ㅃ -> ᆹ
//                    0x3144: 0x11B9, // ㅄ -> ᆹ (ㅃ이 이미 0x3143에 매핑됨)
                    0x3145: 0x11BA, // ㅅ -> ᆺ
                    0x3146: 0x11BB, // ㅆ -> ᆻ
                    0x3147: 0x11BC, // ㅇ -> ᆼ
                    0x3148: 0x11BD, // ㅈ -> ᆽ
//                    0x3149: 0x11BE, // ㅉ -> ᆾ (중복)
                    0x314A: 0x11BE, // ㅊ -> ᆾ
                    0x314B: 0x11BF, // ㅋ -> ᆿ
                    0x314C: 0x11C0, // ㅌ -> ᇀ
                    0x314D: 0x11C1, // ㅍ -> ᇁ
                    0x314E: 0x11C2  // ㅎ -> ᇂ
                ]
                return jongseongMap[c] ?? c
            }
        }
        // 호환 중성 (0x314F-0x3163) -> 조합형 중성 (0x1161-0x1175)
        else if c >= 0x314F && c <= 0x3163 {
            return c - 0x314F + 0x1161
        }
        // 변환할 필요 없음
        return c
    }

    /// 자모 용도 열거형
    public enum JamoUsage: Sendable {
        case choseong
        case jungseong
        case jongseong
    }

    /// 호환 자모를 조합형 자모로 변환 (String 버전)
    /// - Parameter string: 변환할 문자열
    /// - Returns: 변환된 문자열
    public static func compatibilityJamoToJamo(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            let converted = compatibilityJamoToJamo(UCSChar(scalar.value))
            if let convertedScalar = UnicodeScalar(converted) {
                result.append(String(convertedScalar))
            }
        }
        return result
    }

    /// 결합 가능한 자모로 변환 (호환 자모인 경우 조합형으로 변환)
    /// - Parameter c: 검사할 자모
    /// - Returns: 결합 가능한 자모 코드
    @inlinable
    public static func toConjoinableJamo(_ c: UCSChar) -> UCSChar {
        compatibilityJamoToJamo(c)
    }


}
