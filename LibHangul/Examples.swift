//
//  Examples.swift
//  LibHangul
//
//  Created by Sonic AI Assistant
//
//  LibHangul 사용 예제 모음
//

import Foundation

/// LibHangul 사용 예제들
public enum LibHangulExamples {

    /// 기본적인 한글 입력 예제
    public static func basicHangulInput() {
        print("=== 기본 한글 입력 예제 ===")

        // 입력 컨텍스트 생성 (두벌식 키보드)
        let context = LibHangul.createInputContextLegacy(keyboard: "2")

        // "안녕하세요" 입력 시뮬레이션
        let input = "dkssudgktpdy" // "안녕하세요"의 두벌식 자판 입력
        print("입력: \(input)")

        var result = ""
        for char in input {
            let key = Int(char.asciiValue!)
            if context.process(key) {
                let commit = context.getCommitString()
                if !commit.isEmpty {
                    let commitText = commit.compactMap { UnicodeScalar($0) }.map { Character($0) }
                    result += commitText
                }
            }
        }

        // 남은 조합중인 문자열 처리
        let remaining = context.flush()
        if !remaining.isEmpty {
            let remainingText = remaining.compactMap { UnicodeScalar($0) }.map { Character($0) }
            result += remainingText
        }

        print("결과: \(result)")
        print()
    }

    /// 키보드 타입별 입력 예제
    public static func keyboardTypeExample() {
        print("=== 키보드 타입별 예제 ===")

        // 두벌식
        let dubeolResult = LibHangul.createInputContextLegacy(keyboard: "2")
        let dubeolText = dubeolResult.processText("rk") // ㄱ + ㅏ
        print("두벌식 'rk' -> '\(dubeolText)'")

        // 세벌식 (간단한 매핑으로 테스트)
        let sebeolResult = LibHangul.createInputContextLegacy(keyboard: "3")
        let sebeolText = sebeolResult.processText("kf") // 세벌식 ㄱ + ㅏ
        print("세벌식 'kf' -> '\(sebeolText)'")

        print()
    }

    /// 한글 자모 분석 예제
    public static func hangulAnalysisExample() {
        print("=== 한글 자모 분석 예제 ===")

        let text = "한글"
        print("분석할 텍스트: \(text)")

        for char in text {
            let isSyllable = LibHangul.isHangulSyllable(String(char))
            print("\(char): \(isSyllable ? "음절" : "음절 아님")")

            if isSyllable {
                let decomposed = LibHangul.decomposeHangul(String(char))
                print("  분해된 결과: \(decomposed)")
            }
        }

        print()
    }

    /// 한글 결합 예제
    public static func hangulCompositionExample() {
        print("=== 한글 결합 예제 ===")

        // 기본 음절 결합
        let syllables: [(String, String, String, String)] = [
            ("ㄱ", "ㅏ", "가", "가"),
            ("ㄴ", "ㅏ", "나", "나"),
            ("ㄷ", "ㅏ", "다", "다"),
            ("ㄱ", "ㅏ", "ㄴ", "간"),
            ("ㄴ", "ㅏ", "ㅁ", "남")
        ]

        for syllable in syllables {
            if syllable.3 != "" { // 종성이 있는 경우
                let result = LibHangul.composeHangul(choseong: syllable.0, jungseong: syllable.1)
                print("\(syllable.0) + \(syllable.1) = \(result ?? "실패") (기대값: \(syllable.2))")
            } else {
                let result = LibHangul.composeHangul(choseong: syllable.0, jungseong: syllable.1, jongseong: syllable.2)
                print("\(syllable.0) + \(syllable.1) + \(syllable.2) = \(result ?? "실패") (기대값: \(syllable.3))")
            }
        }

        print()
    }

    /// 실시간 입력 시뮬레이션 예제
    public static func realtimeInputSimulation() {
        print("=== 실시간 입력 시뮬레이션 ===")

        let context = LibHangul.createInputContextLegacy(keyboard: "2")

        // "안녕하세요"의 자모 입력 시퀀스
        let inputSequence = [
            ("d", "ㄷ"),
            ("k", "ㅏ"),
            ("s", "ㄴ"),
            ("s", "ㄴ"),
            ("u", "ㅕ"),
            ("d", "ㄹ"),
            ("g", "ㅎ"),
            ("k", "ㅏ"),
            ("t", "ㅅ"),
            ("p", "ㅔ"),
            ("d", "ㄹ"),
            ("y", "ㅛ")
        ]

        print("입력 시퀀스:")
        for (key, jamo) in inputSequence {
            print("  키 '\(key)' (자모: \(jamo))")

            let keyCode = Int(Character(key).asciiValue!)
            let processed = context.process(keyCode)

            if processed {
                let commit = context.getCommitString()
                if !commit.isEmpty {
                    let commitText = commit.compactMap { UnicodeScalar($0) }.map { Character($0) }
                    print("    커밋됨: \(commitText)")
                }
            }

            let preedit = context.getPreeditString()
            if !preedit.isEmpty {
                let preeditText = preedit.compactMap { UnicodeScalar($0) }.map { Character($0) }
                print("    조합중: \(preeditText)")
            }
        }

        // 최종 플러시
        let final = context.flush()
        if !final.isEmpty {
            let finalText = final.compactMap { UnicodeScalar($0) }.map { Character($0) }
            print("최종 결과: \(finalText)")
        }

        print()
    }

    /// 옵션 사용 예제
    public static func optionsExample() {
        print("=== 옵션 사용 예제 ===")

        let context = LibHangul.createInputContextLegacy(keyboard: "2")

        // 옵션 설정
        context.setOption(.autoReorder, value: true)
        context.setOption(.combinationOnDoubleStroke, value: false)

        print("자동 재정렬 옵션: \(context.getOption(.autoReorder))")
        print("두 번 입력시 결합 옵션: \(context.getOption(.combinationOnDoubleStroke))")

        // 출력 모드 변경
        context.setOutputMode(.jamo)
        print("출력 모드: 자모 단위")

        let result = context.processText("rk") // ㄱ + ㅏ
        print("자모 모드 결과: \(result)")

        context.setOutputMode(.syllable)
        print("출력 모드: 음절 단위")

        let result2 = context.processText("rk") // ㄱ + ㅏ
        print("음절 모드 결과: \(result2)")

        print()
    }

    /// 키보드 정보 출력 예제
    public static func keyboardInfoExample() {
        print("=== 키보드 정보 ===")

        let keyboards = LibHangul.availableKeyboards()

        print("사용 가능한 키보드: \(keyboards.count)개")
        for keyboard in keyboards {
            print("  ID: \(keyboard.id), 이름: \(keyboard.name), 타입: \(keyboard.type)")
        }

        print()
    }

    /// 모든 예제 실행
    public static func runAllExamples() {
        print("LibHangul Swift 사용 예제")
        print("========================\n")

        basicHangulInput()
        keyboardTypeExample()
        hangulAnalysisExample()
        hangulCompositionExample()
        realtimeInputSimulation()
        optionsExample()
        keyboardInfoExample()

        print("모든 예제가 완료되었습니다.")
    }
}
