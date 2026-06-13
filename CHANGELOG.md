# Changelog

All notable changes to PriType-Swift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### 조사 (한글 조합 밑줄 — macOS 26에서는 marked text로 제거 불가)
- 조합 밑줄을 모든 앱에서 없애기 위해 marked text 속성을 엔진별로 조정했으나(`PreeditUnderline`: Blink는 `underlineStyle 1 + alpha 1/255`, 그 외는 `underlineStyle 0 + NSColor.clear`), **macOS 26에서는 효과가 없음을 실측으로 확인했습니다**. NSTextInputClient 프로브로 실제 IMK 전송 경로를 측정한 결과, IME가 보내는 모든 속성 조합 — underline 0+clear, alpha 1/255, `NSMarkedClauseSegment` 1~9(kNoHilite 포함 전체 TSM hilite 카테고리), 심지어 속성 없는 문자열까지 13종 전부 — 이 앱에는 동일한 `NSUnderline=2 + 액센트 블루`로 재생성되어 도착합니다. 수신 측 프레임워크가 IME 스타일을 폐기하고 시스템 표준 스타일을 합성하므로, **macOS 26에서는 어떤 IME도 marked text 밑줄을 숨길 수 없습니다**(애플 한글 IME도 동일한 밑줄). 엔진별 속성 튜닝은 속성이 통과되는 구버전 macOS에서만 유효하며 코드에 유지합니다(오분류·부작용 없음). 밑줄 없는 입력은 marked text를 쓰지 않는 직접 삽입 모드(`com.pritype.experimentalDirectInsertion`)로 제공됩니다. 측정 과정은 `PreeditUnderline` 주석에 기록했습니다.

### 구조 (end-to-end 입력 파이프라인 개편)
- 세션 스코프 상태(클라이언트, `ClientContext`, delivery 어댑터, 중복 keyDown 상태, 포커스 상실 안전망)를 단일 소유자 `InputSession`으로 통합했습니다. `PriTypeInputController`는 IMK 수명 주기만 담당하는 얇은 edge가 되었고, 흩어져 있던 `lastClient`/`lastKnownInputClient`/`cachedContext`/`currentAdapter`/옵저버 필드 간 drift 가능성이 사라졌습니다.
- 조합 종료를 `InputSession.finalize(reason:)` **단일 경로**로 통일했습니다. 앱 비활성, IMK `deactivateServer`, 마우스 클릭 commit, 사용자 한/영 전환키, macOS Caps Lock/메뉴 모드 전환(`setValue` ingress), 자판 배열 변경 — 여섯 가지 종료 이벤트가 전부 같은 멱등 1-op commit(`insertText` + `NSNotFound`)을 사용합니다. 과거 KakaoTalk에서 검증된 시퀀스를 모든 경로에 적용한 것으로, 번들 ID 하드코딩이 전혀 없습니다.
- 조합 출력 전달(어댑터 3종: marked text / 직접 삽입 / immediate)을 `TextDelivery.swift`로 분리하고, 모드 결정을 `TextDeliveryPolicy.mode(for:)` 한 곳으로 모았습니다.
- 한자 후보창 좌표 전략 체인(firstRect → attributes → 캐시 → AX → 마우스)을 `CursorRectResolver.swift`로 분리해 `HangulComposer`가 조합에만 집중하도록 했습니다(약 280줄 감소).

### 수정 (KakaoTalk 한글 커밋 문제, 하드코딩 없이)
- 한/영 전환·Caps Lock 전환·자판 변경 중 조합 종료가 기존에는 별도 2-op commit 경로(`forceCommit` + `setMarkedText("")`)를 사용해, KakaoTalk 등 일부 네이티브 호스트에서 마지막 글자 유실/stranded preedit/이모티콘 팝업 깜빡임이 재발할 수 있었습니다. 모든 종료 경로가 검증된 1-op commit으로 수렴하면서 이 잔여 표면이 제거되었습니다.
- 중복 keyDown 억제(동일 물리 키 이벤트를 2회 전달하는 호스트 — KakaoTalk에서 관찰, 예: 백스페이스 1회에 자모 2개 분해)를 실험적 직접 삽입 모드 전용에서 **모든 delivery 모드 공통**으로 일반화했습니다. 중복 전달은 호스트 이벤트 전달의 속성이지 렌더링 방식의 속성이 아니기 때문입니다.
- 포커스 상실 안전망(NSWorkspace 비활성 옵저버)을 세션 소유로 옮기고, `deactivateServer`에서 반드시 disarm하도록 했습니다. 이전 구조에서는 stale 옵저버가 늦게 발화하면 공유 composer의 새 조합을 이전 앱 클라이언트로 흘릴 수 있는 cross-app commit-leak 가능성이 있었습니다.
- `deactivateServer` 이후 같은 클라이언트 객체로 `handle()`이 먼저 도착하는 경우(컨텍스트 stale — 같은 앱의 다른 필드로 포커스 이동 가능) 컨텍스트를 재분석한 뒤 처리하도록 명시했습니다.

### 변경
- 한글 조합 중 표시되던 밑줄(preedit underline)을 제거하고 평문 marked text로 표시하도록 했습니다.
- 앱 포커스 상실 시 조합을 강제 커밋하던 호환성 로직(과거 KakaoTalk 대응에서 일반화한 NSWorkspace 비활성 옵저버)을 완전히 제거했습니다. 정상 포커스 전환 commit은 IMK `deactivateServer`가 담당합니다.
- libhangul-swift 최신(main)에 맞춰 통합을 점검했습니다. 새 기본값(`outputMode .syllable`, `combinationOnDoubleStroke` OFF, `fineGrainedBackspace` ON, NFC 정규화)이 표준 2벌식 동작과 일치하여 코드 변경은 없으며, 기본값이 바뀌어도 조합이 깨지지 않도록 회귀 테스트(ㄱㄱ↛ㄲ, 와→오 단계 백스페이스)를 추가했습니다.

### 수정
- 한글 입력이 전혀 되지 않던 회귀를 고쳤습니다. 통합 아키텍처 작업 중 `Info.plist`의 입력기 등록에 최상위 `TISInputSourceID`(자식 입력 모드와 동일 ID)와 모드별 `TISInputSourceID`/`tsInputModeDefaultStateKey` 등 불필요한 키가 추가되면서 TIS 등록이 깨져, 입력 소스를 선택해도 조합이 동작하지 않았습니다. 등록을 검증된 2.6.5의 최소 `ComponentInputModeDict` 구조로 복원했습니다(단일 모드 `com.pritype.inputmethod.v2`, `smKorean`). 조합 엔진 자체는 정상이었고(유닛 테스트 통과) 원인은 등록부였습니다.

### 구조
- 한/영 입력 구조를 `v2.6.5`의 단일 상태기계와 `v2.7.2`의 macOS 통합 장점을 결합한 **단일 소스 하이브리드**로 정식화했습니다. PriType 단일 입력 소스가 IMK 세션을 영구 소유하고, 한/영은 `HangulComposer.inputMode` 하나로 내부 전환합니다. 정식 명세를 [Docs/UnifiedInputArchitecture.md](Docs/UnifiedInputArchitecture.md)로 추가하고, 기존 RollbackPlan(가짜 모드 2개 등록 안)은 superseded 처리했습니다.

### 개선
- 영어 모드를 순수 pass-through로 정리했습니다. PriType가 영문 입력에서 로컬 버퍼를 추적하거나 텍스트를 직접 삽입하지 않으며, 더블스페이스 마침표 등 영문 텍스트 편의는 macOS가 담당합니다. 버퍼-커서 불일치로 인한 잠재 버그 경로를 제거했습니다.
- 사용되지 않던 입력 소스 헬퍼(`ensureDefaultEnglishInputSourceEnabled`, `ensurePriTypeInputModesEnabled`)를 제거하고, stale 정리는 `cleanupStaleInputSources` 한 곳으로 정리했습니다.
- 앱 포커스 상실 시 한글 조합을 강제 커밋하던 동작에서 KakaoTalk 번들 ID 하드코딩을 제거했습니다. 이제 특정 앱에 의존하지 않고 모든 앱에 대해 동작하는 멱등 안전망(이미 커밋된 호스트에서는 no-op)으로 일반화했습니다.
- 사용자 지정 한/영 전환키 경로를 `InputModeCoordinator → PriTypeInputController → HangulComposer` 한 줄로 일원화해, Caps Lock 정책·활성 컨트롤러 가드·전환 전 1회 commit을 한 곳에서 보장하도록 정리했습니다(전환 콜백은 검증된 2.6.5 기준선대로 메인 런루프에 올립니다).
- `HangulComposer.inputMode`의 write 경로를 토글 전환과 외부 입력소스 선택(ingress) 두 곳으로 한정한다는 계약을 코드 주석으로 명문화했습니다.

### 안정성
- `activateServer`가 `deactivateServer` 없이 반복 호출(Electron/Chromium 계열에서 흔함)될 때 자판 변경 옵저버가 중복 등록돼 `handleLayoutChange`가 여러 번 실행될 수 있던 문제를 막았습니다(재등록 전 기존 등록 제거).
- `PriTypeInputController`에 `deinit`을 추가해 자판 변경 옵저버와 앱 비활성 옵저버(block 기반은 자동 제거되지 않음)를 정리하도록 했습니다.
- 손쉬운 사용 권한 요청 후 권한을 polling하던 타이머가 권한을 끝내 허용하지 않으면 무한정 돌거나, 버튼을 반복 누르면 중첩되던 문제를 수정했습니다. 타이머를 저장해 재요청 시 교체하고, 상한(약 2분) 후 자동 종료하며, 설정 창이 사라질 때 무효화합니다.

### UX
- 설정 창 제목을 로컬라이즈했습니다(`PriType 설정`/`PriType Settings`). 시각적으로는 숨겨져 있지만 Window 메뉴·Mission Control·VoiceOver가 사용하는 값이라 언어에 맞게 읽히도록 정리했습니다.

### 테스트
- 그동안 커버리지가 없던 순수 함수에 회귀 테스트를 추가했습니다(9개): 한자 후보창 좌표 유효성 검증(`isValidCursorRect` — Chromium 쓰레기 좌표 거부)과 초성↔호환 자모 변환(`isChoseongJamo`/`choseongToCompatibility`/`isJamoConsonant`).
- AX 좌표 경로의 유일한 강제 언랩(`AXValueCreate(...)!`)을 graceful fallback으로 바꿔 잠재 크래시 경로를 제거했습니다.

### 검증
- `swift build -c debug --product PriType`
- `swift test` (121개 통과)
- `swift run -c debug PriTypeVerify`
- `swift build -c release --product PriType`

## [2.7.4] - 2026-05-21 (Stable)

### 수정
- 시작 시 PriType이 자기 입력 소스를 다시 enable 하던 경로를 제거해, 부팅 후 macOS가 입력 소스 추가/허용 확인창을 띄울 수 있는 부작용을 줄였습니다.
- KakaoTalk에서 앱 포커스를 잃을 때 남은 한글 조합을 강제 커밋하도록 알려진 앱 호환성 정책을 추가했습니다.
- 업데이트 알림 권한 요청을 앱 시작 시점이 아니라 실제 업데이트 알림을 보낼 때로 늦춰, 시작 시 불필요한 권한 팝업이 뜰 수 있는 경로를 제거했습니다.
- 입력 hot path의 디버그 카운터를 DEBUG 빌드에만 포함되도록 정리했습니다.

### 개선
- 설정창 폭과 상태 표시를 조정해 Caps Lock 안내, 키 설정, 손쉬운 사용 권한 상태가 덜 잘리고 더 안정적으로 보이도록 정리했습니다.

### 검증
- `swift build -c debug --product PriType`
- `swift run -c debug PriTypeVerify`
- `swift build -c release --product PriType`
- `swift run -c release PriTypeVerify`
- `swift run -c release PriTypeBenchmark`
- Release PKG 서명, Apple 공증, 스테이플, Gatekeeper 검증

## [2.7.3] - 2026-05-20 (Stable)

### 수정
- KakaoTalk에서 한글 조합 중 다른 앱으로 포커스를 옮겼다가 돌아오면 마지막 조합 글자가 확정되지 않고 다음 입력으로 덮어써지던 문제를 보완했습니다.
- KakaoTalk이 앱 비활성화 후에도 IMK marked composition을 오래 붙잡는 경우를 처리하기 위해, KakaoTalk 비활성화 시 조합 중인 글자를 즉시 커밋하도록 호환성 정책을 추가했습니다.
- PriType 실행 시 자기 입력 소스를 다시 활성화하던 자동 입력 소스 제어 경로를 제거했습니다. 재부팅할 때마다 macOS가 PriType 입력 소스 추가 확인창을 반복 표시할 수 있던 원인을 줄였습니다.

### 검증
- `swift test`
- `swift run -c debug PriTypeVerify`
- `swift run -c release PriTypeBenchmark`

## [2.7.2] - 2026-05-18 (Stable)

### 수정
- 조합 중 Return/Enter 처리 시 조합을 확정하고 marked text를 명시적으로 정리한 뒤 원래 Return 이벤트를 앱에 그대로 전달하도록 단순화했습니다. 추가 클라이언트 속성 조회나 synthetic key 재전달을 제거해 입력 지연 가능성을 줄였습니다.
- GoodNotes의 IMK Return 재진입 문제를 알려진 앱 호환성 정책으로 처리합니다. GoodNotes에서 조합 중 Return은 조합을 확정한 뒤 줄바꿈을 직접 삽입하고 원래 Return을 소비해 중복 줄바꿈을 막습니다.
- MapleStory/Wine 전용 입력 호환 실험 경로를 제거하고 일반 IMK 조합 처리로 되돌렸습니다.

## [2.7.1] - 2026-05-18 (Stable)

### 수정
- 한글 조합 중 Return/Enter를 눌렀을 때 일부 앱에서 줄바꿈이 두 번 입력되던 문제를 수정했습니다.
- 조합 중 Enter는 PriType이 조합을 확정하고 줄바꿈을 한 번만 삽입한 뒤 원래 Enter 이벤트를 소비합니다.
- 조합이 없는 상태의 Enter는 기존처럼 앱에 그대로 전달합니다.

### 호환성
- 최소 지원 버전을 macOS 14.0 Sonoma로 낮췄습니다.
- macOS 26 Tahoe 전용 Liquid Glass API는 Tahoe 이상에서만 사용하고, Sonoma/Sequoia에서는 기본 vibrancy fallback을 사용하도록 정리했습니다.

### 문서
- Release 빌드 기준으로 벤치마크를 다시 측정하고 `BENCHMARK.md`를 갱신했습니다.
- README를 현재 설치 방식, Caps Lock 전환 정책, Sonoma 지원 기준에 맞게 정리했습니다.

### 검증
- `swift build -c release`
- `swift run -c release PriTypeVerify`
- `swift build -c debug --product PriType`
- PriTypeBenchmark 실행 및 macOS 최소 버전 `14.0` 확인

## [2.7] - 2026-05-18 (Stable)

### 핵심 변경
- 영어 입력은 PriType 내부 영어 모드가 아니라 macOS 기본 `ABC` 입력 소스를 사용하도록 전환했습니다. PriType은 한글 입력 소스 역할에 집중합니다.
- Caps Lock 한/영 전환을 PriType 자체 키 가로채기 경로에서 제거하고 macOS 입력 소스 전환 설정을 따르도록 정리했습니다.
- PriType 입력 소스 등록을 단일 한글 입력 소스(`com.pritype.inputmethod.v2.korean`)로 정리해 메뉴 막대에 `한글`이 중복 표시되던 문제를 해결했습니다.
- 오래된 PriType 영어 입력 소스, component input mode, Apple Korean 입력 모드 잔여 등록을 정리하는 복구 로직을 추가했습니다.

### 개선
- 우측 Command/우측 Option 등 PriType 사용자 지정 전환키는 CGEventTap/IOKit 경로를 유지하면서 실제 macOS 입력 소스 선택과 동기화되도록 정리했습니다.
- 자동 문장 대문자 옵션을 제거했습니다. 영어 입력이 macOS `ABC`로 이동했기 때문에 해당 동작은 macOS 기본 입력기가 담당합니다.
- 스페이스 두 번으로 마침표를 입력하는 동작은 PriType 별도 설정 대신 macOS `NSAutomaticPeriodSubstitutionEnabled` 설정을 따르도록 변경했습니다.
- 앱 활성화, 창 전환, 키 입력 중 불필요한 Accessibility/컨텍스트 검사를 줄여 입력 지연이 발생할 수 있는 경로를 완화했습니다.
- 비밀번호/보안 입력 필드에서는 조합 상태를 정리하고 즉시 패스스루하도록 보강했습니다.

### 설정 및 UX
- 설정창을 macOS Liquid Glass 스타일에 맞게 정리하고, 기본 시스템 폰트와 새 PriType 앱 아이콘 헤더를 사용하도록 변경했습니다.
- Caps Lock은 PriType 전환키로 직접 지정하지 못하게 막고 macOS 입력 소스 설정 상태, 안내 문구, 설정 바로가기를 제공하도록 변경했습니다.
- 키 설정 충돌 시 기존 설정을 복원했다는 피드백을 표시하도록 했습니다.
- 더 이상 필요하지 않은 기본 영어 입력기 제거 기능, 자동 대문자 옵션, PriType 전용 더블스페이스 옵션을 제거했습니다.

### 아이콘 및 입력 소스 표시
- 앱 아이콘과 입력 소스 메뉴/팔레트 아이콘을 새 자산으로 교체했습니다.
- 한글 입력 소스 이름과 아이콘 리소스를 패키지와 로컬 설치 경로에 함께 포함하도록 정리했습니다.

### 패키징
- 릴리즈/디버그 패키징 스크립트가 임시 payload 디렉터리를 사용하도록 변경해 빌드 잔여물이 LaunchServices에 등록되지 않게 했습니다.
- 설치 후 Script Editor 알림을 띄우던 AppleScript 의존성을 제거하고 TextInput 관련 프로세스 재등록 범위를 보강했습니다.
- 버전을 `2.7`, 빌드를 `35`, 릴리즈 채널을 `stable`로 갱신했습니다.

### 검증
- `swift build -c release`
- `swift run -c release PriTypeVerify`
- Release/Debug PKG 서명, 공증, 스테이플, Gatekeeper 검증

## [2.6.5] - 2026-05-10 (Stable)

### 추가
- 앱 버전에 `stable`/`beta` 릴리즈 채널을 구분하는 메타데이터를 추가했습니다.
- 설정/정보 화면에서 현재 버전을 `v2.6.5 (Stable)`처럼 채널과 함께 표시합니다.
- GitHub Releases 목록에서 stable 후보만 고르는 업데이트 검증 테스트를 추가했습니다.
- SwiftPM 테스트와 검증 도구에서도 한자 사전 리소스가 실제로 로드되는지 확인하는 테스트를 추가했습니다.

### 개선
- 업데이트 확인 로직이 더 높은 beta 버전이 있어도 stable 릴리즈만 표시하도록 변경했습니다.
- `v3.0.0-beta.1`처럼 beta 표기가 붙은 태그는 GitHub의 prerelease 플래그가 빠져 있어도 stable 업데이트 후보에서 제외합니다.
- 릴리즈 워크플로우가 태그 버전과 `Info.plist`의 버전/채널을 함께 검증하도록 강화했습니다.
- 릴리즈 패키징 스크립트가 서명, 공증, 스테이플, Gatekeeper 검증을 필수 단계로 수행하도록 정리했습니다.
- 성능 벤치마크가 `Info.plist`의 실제 앱 버전을 기준으로 표시되도록 개선했습니다.

### 수정
- 비밀번호창에서 `selectedRange == NSNotFound`인 경우 Accessibility 검사 없이 즉시 패스스루하도록 단순화해, 한글 상태 비밀번호 입력 시 경고음과 렉이 발생할 수 있던 경로를 제거했습니다.
- 비밀번호/보안 입력창에서 macOS Secure Event Input은 켜져 있지만 Accessibility 포커스 판별이 `unknown`인 경우를 예전 안정 동작처럼 즉시 패스스루하도록 복원해, 한글 입력 시 경고음이 발생할 수 있던 경로를 수정했습니다.
- 일부 비밀번호 입력창에서 매 키 입력마다 Accessibility 포커스 검사를 타며 심한 렉이 발생할 수 있던 문제를 수정했습니다.
- 비밀번호/보안 입력 필드에서 불필요한 조합 입력으로 경고음이 발생할 수 있는 경로를 보강했습니다.
- Wine/게임 환경 감지와 입력 경로를 강화해 일부 게임 런타임에서 한글 조합이 깨지는 위험을 줄였습니다.
- 한자 후보창 위치 계산에서 Chromium 계열 앱과 Accessibility fallback 경로를 더 안정적으로 처리했습니다.
- SwiftPM 테스트/검증 환경에서 `hanja.txt`와 localization 리소스를 못 찾아 한자 사전 로딩 경고가 반복되던 문제를 수정했습니다.
- 오래된 실험용 `sim*.swift` 파일을 제거하고 재추적되지 않도록 정리했습니다.

### 검증
- Swift 테스트 121개 통과
- SwiftLint strict 0건
- PriTypeVerify 통과
- PriTypeBenchmark 통과
- 릴리즈 PKG 서명, Apple 공증, 스테이플, Gatekeeper 검증 통과

## [1.0.0] - 2025-12-11

### Added
- Initial release of PriType-Swift
- Hangul composition using libhangul-swift
- Korean/English toggle via Right Command or Control+Space
- SwiftUI-based settings window
- Auto-capitalize and double-space period features
- Finder desktop detection for floating window prevention
- Secure input field detection (password fields)
- Debug-only logging with complete release removal
