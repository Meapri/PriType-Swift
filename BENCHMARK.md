# 벤치마크

`swift run PriTypeBenchmark`으로 측정. Apple M4 Pro, macOS 26.4, Swift 6.2, Debug 빌드 기준.

벤치마크 소스: `Sources/PriTypeBenchmark/main.swift`

## 한자 검색

`HanjaManager.search(key:)`의 성능. hanja.txt(6.4MB, 약 80,000항목)를 libhangul의 `HanjaTable`에 적재한 뒤 Trie 기반으로 exact match 검색한다. 검색 결과는 LRU 캐시(최대 32개)에 저장하여 동일 키 재검색 시 사전 접근을 생략한다.

| 항목 | 수치 | 설명 |
|------|------|------|
| 사전 로딩 (Cold) | 1,251ms | hanja.txt 파싱 + Trie 구축. 최초 한자키 입력 시 1회만 발생 |
| 검색 20키 (Cold) | 0.42ms | 캐시 비어있는 상태에서 20개 키 검색 (21μs/키) |
| 검색 20키 (Cached) | 0.01ms | 캐시 히트. 딕셔너리 룩업만 수행 (0.5μs/키) |
| 검색 버스트 10,000회 | 0.98μs/op | 단일 키 반복 검색. 캐시 히트 경로의 최대 처리량 |
| 캐시 미스 순환 (40키 × 100회) | 2.92ms | LRU 캐시 크기(32)를 초과하는 40개 키를 순환하여 매번 캐시 미스 유발 |

사전은 첫 한자키 입력 시 lazy 로딩되며, 이후 메모리에 상주한다. 키 이벤트 처리 예산(10ms) 대비 검색은 0.98μs로 약 0.01%를 사용한다.

검색 결과 수 참고:

| 키 | 결과 수 | 키 | 결과 수 |
|---|---|---|---|
| 가 | 125 | 바 | 0 |
| 나 | 45 | 사 | 299 |
| 다 | 13 | 아 | 108 |
| 라 | 73 | 자 | 191 |
| 마 | 76 | 차 | 112 |

## 자모 특수문자 검색

자음 입력 후 한자키를 누르면 특수문자 후보를 표시하는 기능. `jamo_symbols.json`(14개 자음, 390개 특수문자)에서 로딩한다.

libhangul은 preedit 문자를 초성 자모(Choseong Jamo, U+1100~U+1112)로 반환하지만, JSON 키는 호환 자모(Compatibility Jamo, U+3131~U+314E)를 사용한다. `HanjaManager`가 초성 자모를 호환 자모로 변환한 뒤 검색한다.

| 항목 | 수치 | 설명 |
|------|------|------|
| JSON 최초 로딩 | 0.49ms | 14키 × 평균 28개 항목 파싱. 최초 자모 한자키 시 1회 |
| 전체 14키 검색 | 0.02ms | 14개 자음 전체 순회 (1.4μs/키) |
| 버스트 10,000회 (ㅁ) | 1.74μs/op | 호환 자모 직접 검색 |
| 초성 변환+검색 10,000회 (ᄆ→ㅁ) | 1.73μs/op | U+1106 → U+3141 변환 후 검색 |

변환 오버헤드(1.74 vs 1.73μs)는 측정 오차 범위이며 실질적으로 0이다.

자모별 특수문자 수:

| 자음 | 수 | 자음 | 수 | 자음 | 수 | 자음 | 수 |
|---|---|---|---|---|---|---|---|
| ㄱ | 32 | ㄹ | 21 | ㅅ | 15 | ㅊ | 14 |
| ㄴ | 18 | ㅁ | 58 | ㅇ | 15 | ㅋ | 14 |
| ㄷ | 42 | ㅂ | 28 | ㅈ | 20 | ㅌ | 48 |
|   |    |   |    |   |    | ㅍ | 29 |
|   |    |   |    |   |    | ㅎ | 36 |

14개 호환 자모와 14개 초성 자모 간 결과 수가 모두 일치함을 확인했다.

## 동시성

`HanjaManager`의 검색 캐시(`searchCache`, `cacheOrder`)에 대한 Thread Safety 검증.

| 항목 | 수치 | 설명 |
|------|------|------|
| 순차 5,000회 | 45.82ms, 에러 0건 | 단일 스레드에서 한자+자모+초성 키 혼합 검색 |
| 동시 5,000회 × 8스레드 | 166.20ms, 에러 0건 | 8개 스레드에서 동시에 40,000회 검색 |

캐시는 `NSLock`으로 보호된다. `cacheGet()`과 `cachePut()` 진입 시 락을 획득하고 반환 시 해제한다. IMK는 메인 스레드에서만 `search()`를 호출하므로 실제 경합은 발생하지 않으나, 방어적으로 동기화를 적용했다.

벤치마크 작성 과정에서 락 없이 8스레드 동시 접근 시 `cacheOrder` 배열의 Index out of range 크래시가 발생하는 것을 확인하여 수정했다.

## 커서 좌표 검증

`HangulComposer.isValidCursorRect()`는 한자 후보창 위치 결정 시 앱이 반환한 좌표가 유효한지 판별한다. Chromium 계열 앱은 `firstRect(forCharacterRange:)`에서 쓰레기값(예: x=1.6e-314)이나 영점(0, 0, 0, 0)을 반환하는 경우가 있어, 이를 걸러내야 한다.

| 입력 | 기대 | 결과 | 설명 |
|------|------|------|------|
| (607, 637, w=1, h=19) | valid | pass | 정상 커서 좌표 |
| (458, 978, w=0, h=18) | valid | pass | Accessibility API fallback (width 0은 허용) |
| (100, 300, w=10, h=20) | valid | pass | 일반 좌표 |
| (0, 0, w=0, h=0) | invalid | pass | Chromium: 좌표 조회 실패 시 전체 0 반환 |
| (1.6e-314, 95886, ..., h=-1) | invalid | pass | Chromium: 초기화되지 않은 메모리값 |
| (-100, 500, w=10, h=20) | invalid | pass | 음수 x 좌표 |
| (500, 500, w=10, h=-5) | invalid | pass | 음수 height |
| (100000, 500, w=10, h=20) | invalid | pass | x > 50,000 (비현실적) |
| (500, 100000, w=10, h=20) | invalid | pass | y > 50,000 (비현실적) |

9개 케이스 전체 통과. 버스트 100,000회에서 0.24μs/op.

## HangulComposer 인스턴스

| 항목 | 수치 | 설명 |
|------|------|------|
| 인스턴스 생성 | 0.18ms | libhangul 컨텍스트 초기화 포함 |
| 입력모드 전환 10,000회 | 3.17μs/op | `toggleInputMode()` 호출. 상태 바 업데이트 제외 |

## 메모리

| 단계 | 사용량 | 증가 |
|------|--------|------|
| 프로세스 시작 | 8.6MB | — |
| 한자 사전 로딩 후 | 79.7MB | +71.1MB |
| 자모 테이블 추가 후 | 80.2MB | +0.5MB |

한자 사전(hanja.txt)의 Trie 구조가 71.1MB로 메모리의 대부분을 차지한다. 자모 특수문자 테이블(390개)은 0.5MB이다. 두 자원 모두 lazy 로딩되며 한 번 적재되면 프로세스 수명 동안 유지된다.

## 유닛 테스트

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`로 실행. Swift Testing 기반. 109개 테스트, 13개 Suite 전체 통과 (0.007초).

| Suite | 테스트 수 | 검증 범위 |
|---|---|---|
| HangulComposer | 16 | 초·중·종성 조합, 백스페이스, 모드 전환, 방향키/Return/단축키 커밋, Caps Lock 처리 |
| Composition Edge Cases | 13 | 쌍자음(ㄲㄸㅃㅆㅉ), 복합 받침(ㄺ) 분리, 연속 백스페이스, 문장 타이핑(안녕·한글), Space/Tab/ESC 커밋 |
| TextConvenienceHandler | 14 | 더블스페이스→마침표, 자동 대문자, 한글 판별, 영문 모드 입력, 비활성화 시 동작 확인 |
| ConfigurationManager | 14 | 자판 배열·토글 키·한자 키 기본값 및 영속성, KeyBinding Codable/Equatable, 레거시 마이그레이션 |
| ClientContext | 8 | Finder 판별, 바탕화면 즉시 모드, 멀티모니터 좌표, 5K 해상도 |
| CompositionHelpers | 8 | UCSChar→String 변환, NFC 정규화, 서로게이트 필터링, 빈 배열/null 종단 처리 |
| UpdateChecker | 7 | 시맨틱 버전 비교 (major/minor/patch/two-part), 동일 버전, 역순 비교 |
| HanjaManager | 6 | 한자 검색 정확성, 캐싱 일관성, 없는 키 검색, HanjaEntry 구조체 |
| KeyCode | 6 | 키 코드 상수 값, printable ASCII 범위, 기능키/제어문자 판별, shouldPassThrough |
| AboutInfo | 5 | 버전 형식(x.y.z), 앱 이름/저작권/설명 유효성, nil 아님 확인 |
| PriTypeError | 3 | 에러 설명·복구 제안 존재 여부, HID 에러 코드 포함 |
| InputMode | 2 | korean ↔ english 토글, 이중 토글 복원 |
| PriTypeConfig | 1 | 전역 상수 범위 검증 (바탕화면 임계값, 더블스페이스 임계값) |
