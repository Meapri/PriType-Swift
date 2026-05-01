import Foundation
import PriTypeCore

// No-op status bar for accurate benchmarking (excludes NSStatusItem overhead)
final class NoopStatusBar: StatusBarUpdating {
    func setMode(_ mode: InputMode) {}
}

// MARK: - Benchmark Utilities

@discardableResult
func measure(_ label: String, iterations: Int = 1, block: () -> Void) -> Double {
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
        block()
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    let perOp = (elapsed / Double(iterations)) * 1_000_000 // microseconds
    if iterations > 1 {
        print("  \(label): \(String(format: "%.2f", elapsed * 1000))ms total, \(String(format: "%.2f", perOp))μs/op (\(iterations) iterations)")
    } else {
        print("  \(label): \(String(format: "%.2f", elapsed * 1000))ms")
    }
    return elapsed
}

func memoryUsageMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return -1 }
    return Double(info.resident_size) / (1024 * 1024)
}

func separator(_ title: String, emoji: String = "─") {
    print("\n" + String(repeating: "─", count: 50))
    print(title)
    print(String(repeating: "─", count: 50))
}

print(String(repeating: "=", count: 60))
print("  PriType v2.6.1 성능/안전성 벤치마크")
print(String(repeating: "=", count: 60))
let baseMemory = memoryUsageMB()
print("\n📊 초기 메모리: \(String(format: "%.1f", baseMemory))MB")

// =============================================
// 1. 한자 사전 로딩 성능
// =============================================
separator("1️⃣  한자 사전 로딩 성능")

let manager = HanjaManager.shared

// Force cold load by accessing search
measure("한자 사전 최초 로딩 (Cold)") {
    _ = manager.search(key: "가")
}
let afterDictMemory = memoryUsageMB()
print("  메모리 증가: \(String(format: "+%.1f", afterDictMemory - baseMemory))MB")

// =============================================
// 2. 한자 검색 성능
// =============================================
separator("2️⃣  한자 검색 성능")

let testKeys = ["가", "나", "다", "라", "마", "바", "사", "아", "자", "차",
                "한", "국", "어", "입", "력", "기", "성", "능", "테", "스"]

// Cold search (first time, no cache)
measure("한자 검색 Cold (20키)") {
    for key in testKeys {
        _ = manager.search(key: key)
    }
}

// Warm search (cached)
measure("한자 검색 Cached (20키)") {
    for key in testKeys {
        _ = manager.search(key: key)
    }
}

// High-frequency burst - simulates rapid typing
measure("한자 검색 버스트 (10,000회)", iterations: 10000) {
    _ = manager.search(key: "가")
}

// Worst case: cache miss every time (32+ unique keys rotate cache)
let manyKeys = (0xAC00...0xAC00+40).compactMap { UnicodeScalar($0) }.map { String($0) }
measure("캐시 미스 버스트 (40키 순환, 100회)") {
    for _ in 0..<100 {
        for key in manyKeys {
            _ = manager.search(key: key)
        }
    }
}

// Result count verification
print("\n  검색 결과 수 검증:")
for key in testKeys.prefix(10) {
    let results = manager.search(key: key)
    print("    '\(key)': \(results.count)개")
}

// =============================================
// 3. 자모 특수문자 검색 성능
// =============================================
separator("3️⃣  자모 특수문자 검색 성능")

let jamoKeys = ["ㄱ", "ㄴ", "ㄷ", "ㄹ", "ㅁ", "ㅂ", "ㅅ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

// Cold search (triggers JSON loading)
measure("자모 특수문자 최초 검색 (JSON 로딩 포함)") {
    _ = manager.search(key: "ㅁ")
}

let afterJamoMemory = memoryUsageMB()
print("  자모 테이블 메모리 증가: \(String(format: "+%.1f", afterJamoMemory - afterDictMemory))MB")

// All jamo search
measure("자모 전체 검색 (14키)") {
    for key in jamoKeys {
        _ = manager.search(key: key)
    }
}

// Cached burst
measure("자모 검색 버스트 (ㅁ, 10,000회)", iterations: 10000) {
    _ = manager.search(key: "ㅁ")
}

// Choseong jamo (U+1100~) - simulating actual libhangul preedit
let choseongKeys = ["\u{1100}", "\u{1102}", "\u{1103}", "\u{1105}", "\u{1106}", "\u{1107}",
                     "\u{1109}", "\u{110B}", "\u{110C}", "\u{110E}", "\u{110F}", "\u{1110}",
                     "\u{1111}", "\u{1112}"]

measure("초성 자모 변환+검색 (14키)") {
    for key in choseongKeys {
        _ = manager.search(key: key)
    }
}

measure("초성 자모 버스트 (ᄆ→ㅁ, 10,000회)", iterations: 10000) {
    _ = manager.search(key: "\u{1106}")
}

// Verify counts match between compat and choseong
print("\n  호환자모 vs 초성자모 결과 일치 검증:")
var allMatch = true
for (compat, choseong) in zip(jamoKeys, choseongKeys) {
    let compatResults = manager.search(key: compat)
    let choseongResults = manager.search(key: choseong)
    let match = compatResults.count == choseongResults.count
    if !match { allMatch = false }
    let compatHex = String(compat.unicodeScalars.first!.value, radix: 16, uppercase: true)
    let choseongHex = String(choseong.unicodeScalars.first!.value, radix: 16, uppercase: true)
    print("    \(compat)(U+\(compatHex)) = \(compatResults.count)개, 초성(U+\(choseongHex)) = \(choseongResults.count)개 \(match ? "✅" : "❌")")
}
print("  전체 일치: \(allMatch ? "✅ PASS" : "❌ FAIL")")

// Total symbol count
let totalSymbols = jamoKeys.reduce(0) { $0 + manager.search(key: $1).count }
print("  총 특수문자: \(totalSymbols)개 (14키)")

// =============================================
// 4. 동시성 안전성 테스트
// =============================================
separator("4️⃣  동시성 안전성 테스트 (Thread Safety)")

let concurrentQueue = DispatchQueue(label: "benchmark.concurrent", attributes: .concurrent)
let group = DispatchGroup()
let threadCount = 8
let opsPerThread = 5000
nonisolated(unsafe) var concurrentErrors = 0
let errorLock = NSLock()

let allSearchKeys = testKeys + jamoKeys + choseongKeys

// Test 1: Sequential safety first
measure("순차 검색 \(opsPerThread)회") {
    for i in 0..<opsPerThread {
        let key = allSearchKeys[i % allSearchKeys.count]
        let results = manager.search(key: key)
        // Only jamo keys are guaranteed to have results
        if results.isEmpty && jamoKeys.contains(key) {
            concurrentErrors += 1
        }
    }
}
print("  순차 에러: \(concurrentErrors)건 \(concurrentErrors == 0 ? "✅ PASS" : "❌ FAIL")")

// Test 2: Concurrent safety
let concGroup = DispatchGroup()
nonisolated(unsafe) var concErrors2 = 0
measure("동시 검색 \(opsPerThread)회 × \(threadCount)스레드") {
    for _ in 0..<threadCount {
        concGroup.enter()
        concurrentQueue.async {
            for i in 0..<opsPerThread {
                let key = allSearchKeys[i % allSearchKeys.count]
                let results = manager.search(key: key)
                if results.isEmpty && jamoKeys.contains(key) {
                    errorLock.lock()
                    concErrors2 += 1
                    errorLock.unlock()
                }
            }
            concGroup.leave()
        }
    }
    concGroup.wait()
}
let totalOps = threadCount * opsPerThread
print("  총 작업: \(totalOps)회")
print("  동시성 에러: \(concErrors2)건 \(concErrors2 == 0 ? "✅ PASS (⚠️ 레이스 비발현)" : "❌ FAIL (Thread Safety 문제 확인)")")

// =============================================
// 5. isValidCursorRect 검증
// =============================================
separator("5️⃣  isValidCursorRect 검증")

let rectTests: [(NSRect, Bool, String)] = [
    (NSRect(x: 607, y: 637, width: 1, height: 19), true, "정상 커서"),
    (NSRect(x: 458, y: 978, width: 0, height: 18), true, "AX fallback (w=0)"),
    (NSRect(x: 100, y: 300, width: 10, height: 20), true, "일반 좌표"),
    (NSRect(x: 0, y: 0, width: 0, height: 0), false, "크롬 실패 (전체 0)"),
    (NSRect(x: 1.6e-314, y: 95886, width: 1.6e-314, height: -1), false, "크롬 쓰레기값"),
    (NSRect(x: -100, y: 500, width: 10, height: 20), false, "음수 x"),
    (NSRect(x: 500, y: 500, width: 10, height: -5), false, "음수 height"),
    (NSRect(x: 100000, y: 500, width: 10, height: 20), false, "비현실적 x (>50000)"),
    (NSRect(x: 500, y: 100000, width: 10, height: 20), false, "비현실적 y (>50000)"),
]

var rectPass = true
for (rect, expected, desc) in rectTests {
    let result = HangulComposer.isValidCursorRect(rect)
    let match = result == expected
    if !match { rectPass = false }
    print("  \(match ? "✅" : "❌") \(desc): (\(String(format: "%.1f", rect.origin.x)), \(String(format: "%.1f", rect.origin.y))) → \(result ? "valid" : "invalid")\(match ? "" : " (expected \(expected))")")
}
print("  Rect 검증: \(rectPass ? "✅ PASS" : "❌ FAIL")")

measure("isValidCursorRect 버스트 (100,000회)", iterations: 100000) {
    _ = HangulComposer.isValidCursorRect(NSRect(x: 607, y: 637, width: 1, height: 19))
}

// =============================================
// 6. HangulComposer 기본 동작
// =============================================
separator("6️⃣  HangulComposer 인스턴스 성능")

measure("HangulComposer 생성") {
    _ = HangulComposer(statusBar: NoopStatusBar())
}

let composer = HangulComposer(statusBar: NoopStatusBar())
measure("입력모드 전환 (10,000회)", iterations: 10000) {
    composer.toggleInputMode()
}
// Reset to known state
if composer.inputMode != .korean {
    composer.toggleInputMode()
}

// =============================================
// 7. 최종 메모리 보고
// =============================================
separator("7️⃣  최종 메모리 보고")
let finalMemory = memoryUsageMB()
print("  초기:       \(String(format: "%6.1f", baseMemory))MB")
print("  사전 로딩:  \(String(format: "%6.1f", afterDictMemory))MB (\(String(format: "+%.1f", afterDictMemory - baseMemory))MB)")
print("  자모 추가:  \(String(format: "%6.1f", afterJamoMemory))MB (\(String(format: "+%.1f", afterJamoMemory - afterDictMemory))MB)")
print("  벤치마크 후: \(String(format: "%6.1f", finalMemory))MB (\(String(format: "+%.1f", finalMemory - baseMemory))MB total)")

// =============================================
// Summary
// =============================================
print("\n" + String(repeating: "=", count: 60))
print("  📋 벤치마크 결과 요약")
print(String(repeating: "=", count: 60))
let allPassed = allMatch && concurrentErrors == 0 && concErrors2 == 0 && rectPass
print("  자모 매핑 일치:  \(allMatch ? "✅ PASS" : "❌ FAIL")")
print("  순차 안전성:    \(concurrentErrors == 0 ? "✅ PASS" : "❌ FAIL")")
print("  Thread Safety:  \(concErrors2 == 0 ? "✅ PASS" : "❌ FAIL") (\(totalOps)회 동시 검색)")
print("  Rect 검증:      \(rectPass ? "✅ PASS" : "❌ FAIL") (\(rectTests.count)개 테스트 케이스)")
print("  메모리 증가:     \(String(format: "+%.1f", finalMemory - baseMemory))MB")
print(String(repeating: "─", count: 60))
print("  종합 결과: \(allPassed ? "✅ ALL TESTS PASSED" : "❌ SOME TESTS FAILED")")
print(String(repeating: "=", count: 60))
