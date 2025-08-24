//
//  HangulBuffer.swift
//  LibHangul
//
//  Created by Sonic AI Assistant
//
//  한글 입력 버퍼 관리
//

import Foundation

/// 한글 입력 버퍼의 상태를 관리하는 클래스
/// C 코드의 struct _HangulBuffer에 대응
/// ⚠️ DEPRECATED: 동시성 환경에서는 ThreadSafeHangulInputContext를 사용하세요
/// 참고: Swift 6 동시성 제한으로 인해 이 클래스는 Sendable이 아닙니다.
/// 내부 구현용으로만 사용하세요.
@available(*, deprecated, message: "동시성 환경에서는 ThreadSafeHangulInputContext를 사용하세요. 내부 구현용입니다.")
public final class HangulBuffer {
    /// 초성
    public private(set) var choseong: UCSChar = 0

    /// 중성
    public private(set) var jungseong: UCSChar = 0

    /// 종성
    public private(set) var jongseong: UCSChar = 0

    /// 자모 스택
    private var stack: [UCSChar] = []
    private let maxStackSize: Int

    /// 최대 스택 크기
    public var maxStackSizeValue: Int {
        maxStackSize
    }

    public init(maxStackSize: Int = 12) {
        self.maxStackSize = maxStackSize
    }

    /// 현재 스택 인덱스
    private var index: Int = 0

    /// 버퍼가 비어있는지 확인
    public var isEmpty: Bool {
        choseong == 0 && jungseong == 0 && jongseong == 0 && stack.isEmpty
    }

    /// 버퍼를 초기화
    public func clear() {
        choseong = 0
        jungseong = 0
        jongseong = 0
        stack.removeAll(keepingCapacity: true)
        index = 0
    }

    /// 자모를 버퍼에 추가
    /// - Parameter jamo: 추가할 자모
    /// - Returns: 성공 여부
    public func push(_ jamo: UCSChar) -> Bool {
        guard HangulCharacter.isJamo(jamo) else { return false }

        if HangulCharacter.isChoseong(jamo) {
            return pushChoseong(jamo)
        } else if HangulCharacter.isJungseong(jamo) {
            return pushJungseong(jamo)
        } else if HangulCharacter.isJongseong(jamo) {
            return pushJongseong(jamo)
        }

        return false
    }

    /// 마지막 자모를 제거하고 반환
    /// - Returns: 제거된 자모, 없으면 0
    public func pop() -> UCSChar {
        if !stack.isEmpty {
            return stack.removeLast()
        }

        // 스택이 비어있으면 현재 상태에서 제거
        if jongseong != 0 {
            let result = jongseong
            jongseong = 0
            return result
        } else if jungseong != 0 {
            let result = jungseong
            jungseong = 0
            return result
        } else if choseong != 0 {
            let result = choseong
            choseong = 0
            return result
        }

        return 0
    }

    /// 버퍼의 내용을 음절로 변환
    /// - Returns: 변환된 음절, 실패시 0
    public func buildSyllable() -> UCSChar {
        guard choseong != 0 || jungseong != 0 || jongseong != 0 else { return 0 }

        return HangulCharacter.jamoToSyllable(
            choseong: choseong,
            jungseong: jungseong,
            jongseong: jongseong
        )
    }

    /// 버퍼의 내용을 자모 배열로 반환
    /// - Returns: 자모 배열
    public func getJamoString() -> [UCSChar] {
        var result: [UCSChar] = []

        if choseong != 0 {
            result.append(choseong)
        }
        if jungseong != 0 {
            result.append(jungseong)
        }
        if jongseong != 0 {
            result.append(jongseong)
        }

        result.append(contentsOf: stack)
        return result
    }

    // MARK: - Private Methods

    private func pushChoseong(_ jamo: UCSChar) -> Bool {
        if choseong == 0 {
            choseong = jamo
            return true
        } else if jungseong == 0 {
            // 초성이 있고 중성이 없으면 초성 결합 시도
            if let combined = combineChoseong(choseong, jamo) {
                choseong = combined
                return true
            }
        } else if jongseong == 0 {
            // 초성, 중성이 있고 종성이 없으면 종성으로 변환 후 추가
            let jong = HangulCharacter.choseongToJongseong(jamo)
            if jong != 0 {
                jongseong = jong
                return true
            }
        }

        return false
    }

    private func pushJungseong(_ jamo: UCSChar) -> Bool {
        if jungseong == 0 {
            jungseong = jamo
            return true
        } else {
            // 중성이 있으면 결합 시도
            if let combined = combineJungseong(jungseong, jamo) {
                jungseong = combined
                return true
            }
        }

        return false
    }

    private func pushJongseong(_ jamo: UCSChar) -> Bool {
        if jongseong == 0 {
            jongseong = jamo
            return true
        } else {
            // 종성이 있으면 결합 시도
            if let combined = combineJongseong(jongseong, jamo) {
                jongseong = combined
                return true
            }
        }

        return false
    }

    private func combineChoseong(_ a: UCSChar, _ b: UCSChar) -> UCSChar? {
        // 초성 결합 규칙 (간단한 버전)
        let combinations: [UCSChar: [UCSChar: UCSChar]] = [
            0x1100: [0x1100: 0x1101], // ㄱ + ㄱ = ㄲ
            0x1102: [0x1102: 0x1103], // ㄷ + ㄷ = ㄸ
            0x1107: [0x1107: 0x1108], // ㅂ + ㅂ = ㅃ
            0x1109: [0x1109: 0x110A], // ㅅ + ㅅ = ㅆ
            0x110C: [0x110C: 0x110D]  // ㅈ + ㅈ = ㅉ
        ]

        return combinations[a]?[b]
    }

    private func combineJungseong(_ a: UCSChar, _ b: UCSChar) -> UCSChar? {
        // 중성 결합 규칙 (간단한 버전)
        let combinations: [UCSChar: [UCSChar: UCSChar]] = [
            0x1169: [
                0x1161: 0x116A, 0x1162: 0x116B, 0x1175: 0x116C
            ],
            0x116E: [
                0x1165: 0x116F, 0x1166: 0x1170, 0x1175: 0x1171
            ],
            0x1173: [0x1175: 0x1174],
            0x1161: [0x1175: 0x1162],
            0x1163: [0x1175: 0x1164],
            0x1165: [0x1175: 0x1166],
            0x1167: [0x1175: 0x1168]
        ]

        return combinations[a]?[b]
    }

    private func combineJongseong(_ a: UCSChar, _ b: UCSChar) -> UCSChar? {
        // 종성 결합 규칙 (간단한 버전)
        let combinations: [UCSChar: [UCSChar: UCSChar]] = [
            0x11A8: [0x11A8: 0x11A9], // ㄱ + ㄱ = ㄲ
            0x11AB: [0x11C2: 0x11AD], // ㄴ + ㅎ = ㄶ
            0x11AF: [0x11A8: 0x11B0], // ㄹ + ㄱ = ㄺ
            0x11B8: [0x11BA: 0x11B9], // ㅂ + ㅅ = ㅄ
            0x11BA: [0x11BA: 0x11BB]  // ㅅ + ㅅ = ㅆ
        ]

        return combinations[a]?[b]
    }
}

// MARK: - HangulCharacter Extension

extension HangulCharacter {
    /// 초성을 종성으로 변환
    /// - Parameter choseong: 변환할 초성
    /// - Returns: 대응되는 종성, 없으면 0
    public static func choseongToJongseong(_ choseong: UCSChar) -> UCSChar {
        let table: [UCSChar: UCSChar] = [
            0x1100: 0x11A8, 0x1101: 0x11A9, 0x1102: 0x11AB, 0x1103: 0x11AE,
            0x1104: 0x11AF, 0x1105: 0x11B7, 0x1106: 0x11B8, 0x1107: 0x11BA,
            0x1108: 0x11BB, 0x1109: 0x11BC, 0x110A: 0x11BD, 0x110B: 0x11BE,
            0x110C: 0x11BF, 0x110D: 0x11C0, 0x110E: 0x11C1, 0x110F: 0x11C2,
            0x1110: 0x11C5, 0x1111: 0x11C6, 0x1112: 0x11C2  // 0x1112 (ㅎ) -> 0x11C2 (ㅎ)
        ]

        return table[choseong] ?? 0
    }
}
