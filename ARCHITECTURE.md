# 아키텍처

## 구조

```
┌──────────────────────────────────────────────────────────┐
│  macOS                                                   │
│                                                          │
│  ┌─────────────┐    IMK 프로토콜     ┌────────────────┐  │
│  │ 앱 텍스트필드 │ ◄──────────────── │ IMKServer      │  │
│  └─────────────┘                    └───────┬────────┘  │
│                                             │            │
│  ┌──────────────────────────────────────────┼─────────┐  │
│  │ PriType.app                              │         │  │
│  │                                          ▼         │  │
│  │  ┌──────────────────────┐  위임    ┌───────────┐   │  │
│  │  │ PriTypeInputController│ ──────► │HangulComposer│ │  │
│  │  │ (IMKInputController) │  Client  │(libhangul)│   │  │
│  │  └──────────┬───────────┘  Adapter └─────┬─────┘   │  │
│  │             │                            │         │  │
│  │  ┌──────────▼───────────┐  ┌─────────────▼──────┐  │  │
│  │  │ClientContextDetector │  │HanjaCandidateWindow│  │  │
│  │  │(컨텍스트 분석/캐싱)    │  │(SwiftUI 후보 패널)  │  │  │
│  │  └──────────────────────┘  └────────────────────┘  │  │
│  │                                                    │  │
│  │  ┌──────────────────────┐  ┌────────────────────┐  │  │
│  │  │RightCommandSuppressor│  │IOKitManager        │  │  │
│  │  │(CGEventTap, 주 핸들러)│  │(IOHIDManager, 백업) │  │  │
│  │  └──────────────────────┘  └────────────────────┘  │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## 입력 처리 흐름

1. macOS가 키 이벤트를 `PriTypeInputController.handle()`에 전달한다.
2. `handle()`은 캐싱된 `ClientContext`를 참조해 Secure Input 여부, Finder 바탕화면 여부를 판정한다.
3. 한글 모드일 경우 `client.firstRect()` / `client.attributes()`로 커서 좌표를 proactive 캐시한다.
4. 판정을 통과하면 `ClientAdapter`로 감싸서 `HangulComposer.handle()`에 위임한다.
5. `HangulComposer`는 libhangul-swift의 `ThreadSafeHangulInputContext`를 통해 한글 조합을 수행하고, preedit(밑줄 표시)과 commit(확정 삽입)을 `ClientAdapter` 콜백으로 전달한다.
6. `ClientAdapter`는 `IMKTextInput` 프로토콜을 통해 최종 텍스트를 앱에 삽입한다.

## 한/영 전환 흐름

`RightCommandSuppressor`가 `CGEventTap`으로 시스템 레벨 키 이벤트를 가로채서 사용자가 설정한 전환키(기본: 우측 Command)와 한자키(기본: 우측 Option)를 처리한다. Key Recorder 방식으로 아무 키나 등록할 수 있다. CGEventTap이 시스템에 의해 반복 비활성화되면 `IOKitManager`(IOHIDManager 기반)로 자동 전환된다.

## 한자 후보창 좌표 결정

한자 후보창을 커서 근처에 표시하기 위해 앱으로부터 커서의 화면 좌표를 얻어야 한다. 네이티브 앱(TextEdit, Xcode 등)에서는 `IMKTextInput.firstRect(forCharacterRange:)` 하나로 충분하지만, Chromium 계열 앱(Chrome, Edge, VS Code 등)은 한자키 이벤트 처리 중에 좌표 API를 차단한다.

### 좌표 조회 전략

한자키가 눌렸을 때 다음 순서로 유효한 좌표를 탐색한다:

1. **firstRect**: `IMKTextInput.firstRect(forCharacterRange:)`로 marked range의 화면 좌표를 조회한다. 네이티브 앱에서는 대부분 여기서 성공한다.

2. **attributes**: `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)`로 문자 위치의 line height rectangle을 조회한다. `firstRect`가 쓰레기값을 반환할 때 대안으로 사용한다.

3. **캐시 (proactive)**: `handle()` 메서드에서 한글 입력 중 매 키스트로크마다 `firstRect`와 `attributes`를 호출하여 `lastKnownCursorRect`에 저장한다. Chromium은 일반 타이핑 중에는 좌표를 정상 반환하므로, 한자키를 누르기 전에 캐시가 채워져 있다. fcitx5-macos의 `setController` 접근법에서 착안했다.

4. **Accessibility API**: `AXUIElementCopyAttributeValue`로 포커스된 텍스트 필드의 `AXBounds`와 `AXSelectedTextRange`를 조회한다. 접근성 권한이 필요하며, Chromium의 내부 텍스트 필드에서는 `-25212 (kAXErrorCannotComplete)` 에러가 발생할 수 있다.

5. **마우스 위치**: 위 전략이 모두 실패하면 `NSEvent.mouseLocation`을 사용한다. 커서 근처에서 한자키를 누르는 일반적인 사용 패턴에서 대체로 수용 가능한 위치를 제공한다.

### 좌표 유효성 검증

`isValidCursorRect()`로 반환된 좌표가 실제로 사용 가능한지 검증한다. Chromium이 반환하는 대표적인 쓰레기값:

- 전체 0: `(0, 0, 0, 0)` — 좌표 조회 실패
- 비정규화 부동소수점: `(1.6e-314, 95886, 1.6e-314, -1)` — 초기화되지 않은 메모리
- 음수 height: `(x, y, w, -1)` — 비정상 응답

검증 기준: origin이 (0, 0)이 아닐 것, height > 0, origin.x/y > 1 (부동소수점 쓰레기값 배제), origin이 연결된 `NSScreen.frame` 내부에 있을 것.

## 한자 검색과 자모 특수문자

`HanjaManager`는 두 종류의 검색을 처리한다.

### 한자 사전 검색

`hanja.txt`(약 80,000항목)를 libhangul의 `HanjaTable`에 적재하여 Trie 기반 exact match 검색을 수행한다. `"가"` → `[價, 家, 加, ...]` 형태의 결과를 반환한다. LRU 캐시(최대 32개, NSLock 보호)로 재검색 시 사전 접근을 생략한다.

### 자모 특수문자 검색

자음 입력 후 한자키를 누르면 `jamo_symbols.json`(14개 자음, 390개 특수문자)에서 특수문자 후보를 로딩한다. `"ㅁ"` → `[♥, ♡, ★, ...]` 형태의 결과를 반환한다.

libhangul은 preedit 문자를 초성 자모(Choseong Jamo, U+1100~U+1112)로 반환하지만, JSON 키는 호환 자모(Compatibility Jamo, U+3131~U+314E)를 사용한다. `HanjaManager`에서 `Character.isChoseongJamo` 판별 후 `choseongToCompatibility`로 변환하여 검색한다.

```
libhangul preedit: ᄆ (U+1106)
  → isChoseongJamo: true
  → choseongToCompatibility: ㅁ (U+3141)
  → jamo_symbols.json["ㅁ"]: [♥, ♡, ★, ...]
```

## 모듈 구성

프로젝트는 두 개의 타깃으로 구성된다.

### `PriType` (실행 타깃)

앱 진입점(`main.swift`). `IMKServer` 초기화, `RightCommandSuppressor` / `IOKitManager` 시작, 상태 바 생성, 한자 사전 비동기 로딩, 업데이트 확인을 수행한다.

### `PriTypeCore` (라이브러리 타깃)

전체 입력 로직이 포함된 코어 패키지. 외부 의존성은 `libhangul-swift` 하나뿐이다.

| 파일 | 역할 |
|---|---|
| **HangulComposer** | 한글 조합 엔진. libhangul 컨텍스트를 감싸고, 키 이벤트 → 초·중·종성 조합 → preedit/commit 변환을 담당한다. 영문 모드 처리, 자동 대문자, 더블스페이스 마침표 기능을 포함한다. |
| **HangulComposerTypes** | `HangulComposerDelegate` 프로토콜(insertText, setMarkedText, textBeforeCursor, replaceTextBeforeCursor)과 `InputMode` enum 정의. |
| **PriTypeInputController** | `IMKInputController` 서브클래스. `activateServer` → `handle()` → `deactivateServer` 수명 주기를 관리한다. 내부에 `ClientAdapter`(밑줄 표시 모드)와 `ImmediateModeAdapter`(Finder 바탕화면용, setMarkedText 생략) 두 가지 어댑터를 포함한다. 한글 모드에서 커서 좌표를 proactive 캐시한다. |
| **ClientContextDetector** | 입력 클라이언트 분석기. 번들 ID, `validAttributesForMarkedText`, 좌표 휴리스틱을 조합해 `ClientContext` 구조체를 생성한다. Finder 바탕화면은 좌표 기반(`y < 50`)으로 판별한다. |
| **RightCommandSuppressor** | `CGEventTap` 기반 시스템 레벨 키 인터셉터. `ConfigurationManager`의 `toggleKeyBinding`/`hanjaKeyBinding`을 읽어 사용자 지정 키를 동적으로 처리한다. Key Recorder 모드를 지원하여 설정 창에서 키 캡처가 가능하다. 이벤트 탭 비활성화 시 재활성화를 시도하며, 60초 내 3회 실패 시 IOKit 백업으로 자동 전환한다. |
| **IOKitManager** | `IOHIDManager` 기반 하드웨어 레벨 키 모니터. CGEventTap 실패 시 백업 핸들러로 동작한다. HID usage 매핑 테이블을 통해 사용자 지정 키를 동적으로 처리한다. |
| **HanjaCandidateWindow** | SwiftUI 기반 한자 후보 패널. `NSPanel`을 재사용하며, `screenSaver + 1` 윈도우 레벨로 Electron 앱 위에 표시된다. 1~9 숫자키 선택, 방향키/Tab 페이지 이동을 지원한다. |
| **HanjaManager** | 한자 사전 로더 + 자모 특수문자 검색. `hanja.txt`를 `HanjaTable`에 적재하고, `jamo_symbols.json`에서 자모 특수문자를 로딩한다. LRU 캐시(32개, NSLock 보호)로 재검색 시 사전 접근을 생략한다. 초성 자모(U+1100~) → 호환 자모(U+3131~) 변환을 포함한다. |
| **ConfigurationManager** | `UserDefaults` 기반 설정 관리. 자판 배열, `KeyBinding`(한/영 전환키·한자 입력키), 자동 대문자, 더블스페이스 마침표, 자동 업데이트 확인 옵션을 저장한다. 기존 `ToggleKey` enum에서 `KeyBinding` struct로의 자동 마이그레이션을 지원한다. `ConfigurationProviding` 프로토콜로 테스트 시 목(mock) 주입이 가능하다. |
| **SettingsWindowController** | SwiftUI `NSHostingController` 기반 설정 창. Liquid Glass 스타일, Key Recorder(키 녹음) UI, 접근성 권한 확인/요청, ABC 입력소스 제거 안내 기능을 포함한다. |
| **StatusBarManager** | `NSStatusItem` 기반 메뉴 바 표시기. 현재 모드를 "가" / "A"로 표시하며, 전환 시 0.08초 페이드 애니메이션을 적용한다. |
| **TextConvenienceHandler** | 영문 모드 부가 기능. 문장 시작 자동 대문자, 더블스페이스 → 마침표 변환을 처리한다. IPC 호출 없이 `localTextBuffer`(15자)를 참조한다. |
| **UpdateChecker** | GitHub Releases API를 통해 최신 버전을 확인한다. 24시간 스로틀, 실패 시 다음 실행 시 재시도, 시맨틱 버전 비교(`.numeric`)를 사용한다. |
| **UpdateNotifier** | `UNUserNotificationCenter`를 사용해 업데이트 알림을 표시한다. 알림 클릭 시 릴리즈 페이지를 연다. |
| **InputSourceManager** | TIS(Text Input Source) API를 사용해 시스템 입력 소스 목록 조회 및 ABC 활성화 여부를 확인한다. |
| **CompositionHelpers** | libhangul의 `[UInt32]`(UCSChar) 배열을 Swift `String`으로 변환하고 NFC 정규화(`precomposedStringWithCanonicalMapping`)를 수행하는 유틸리티. |
| **DebugLogger** | 조건 컴파일(`#if DEBUG`) 기반 로거. 디버그 빌드에서는 `~/Library/Logs/PriType/pritype_debug.log`에 기록하고, 릴리즈 빌드에서는 `@autoclosure`로 문자열 생성 자체를 생략하는 no-op이 된다. |
| **KeyCode** | macOS 키 코드 상수와 문자 판별 함수(`isPrintableASCII`, `shouldPassThrough` 등)를 집중 관리한다. |
| **L10n** | `Localizable.strings`(ko/en)에서 로컬라이즈된 문자열을 타입 안전하게 접근한다. 배포/개발 환경 모두 대응하는 번들 해석 로직을 포함한다. |
| **PriTypeConfig** | 전역 상수 정의. 기본 자판 ID(`"2"`, 두벌식), Finder 바탕화면 임계값(50pt), 설정 창 크기, 더블스페이스 임계값(0.45초). |
| **PriTypeError** | 구조화된 에러 타입. CGEventTap 생성 실패, 접근성 권한 거부, IOHIDManager 오류에 대해 복구 제안(`recoverySuggestion`)을 포함한다. |
| **AboutInfo** | 앱 메타데이터 및 정보 대화상자. 버전은 `Info.plist`의 `CFBundleShortVersionString`에서 읽는다. |

## 의존 라이브러리

### [libhangul-swift](https://github.com/Meapri/libhangul-swift)

C 기반 libhangul을 순수 Swift로 재구현한 한글 조합 엔진. PriType이 사용하는 API:

- **`ThreadSafeHangulInputContext`**: `OSAllocatedUnfairLock`으로 동기화된 입력 컨텍스트. `process()`, `getPreeditString()`, `getCommitString()`, `flush()`, `reset()` 호출.
- **`HanjaTable`**: Trie 기반 한자 사전. `matchExact(key:)`로 한글 키에 대응하는 한자 목록 검색.
- **`HangulCharacter`**: 초·중·종성 결합/분리 및 호환 자모(Compatibility Jamo) 변환.
- **`KeyInput`**: 키보드 입력을 `.character("r")` / `.keyCode(51)` 형태로 표현하는 타입 안전 열거형.

두벌식(`"2"`), 세벌식 390(`"3"`), 옛한글(`"2y"`, `"3y"`) 자판을 지원한다.

## Secure Input 처리

macOS의 `IsSecureEventInputEnabled()`는 프로세스 단위가 아닌 **시스템 전역 플래그**다. 카카오톡 등 일부 앱이 비밀번호 필드에서 이 플래그를 설정한 뒤 해제하지 않으면, 다른 모든 앱에서 입력기가 영문 모드로 고정되는 문제가 발생한다.

PriType은 2단계 검증으로 이를 처리한다:
1. **번들 ID 확인**: `SecurityAgent`, `loginwindow`, `screencaptureui`이면 즉시 pass-through.
2. **필드 속성 확인**: 위 목록에 없으면 `validAttributesForMarkedText()`가 빈 배열인지 검사. 빈 배열이면 비밀번호 필드로 간주하여 pass-through. 그 외에는 오래된(stale) 플래그로 판단하고 정상 입력 처리.

## 테스트

Swift Testing 기반 109개 유닛 테스트, 13개 Suite 구성. 실행 방법과 상세 결과는 [BENCHMARK.md](BENCHMARK.md#유닛-테스트)를 참고한다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

> **참고**: Command Line Tools SDK에는 Testing 모듈이 포함되어 있지 않으므로 `DEVELOPER_DIR`로 Xcode SDK를 지정해야 한다.

## 디렉토리 구조

```
PriType-Swift/
├── Sources/
│   ├── PriType/                    # 실행 타깃 (main.swift)
│   ├── PriTypeCore/                # 코어 라이브러리
│   │   ├── HangulComposer.swift        # 한글 조합 엔진
│   │   ├── PriTypeInputController.swift # IMK 컨트롤러
│   │   ├── RightCommandSuppressor.swift # CGEventTap 핸들러
│   │   ├── IOKitManager.swift           # IOKit 백업 핸들러
│   │   ├── HanjaCandidateWindow.swift   # 한자 후보창 (SwiftUI)
│   │   ├── HanjaManager.swift           # 한자/자모 검색 + LRU 캐시
│   │   ├── SettingsWindowController.swift# 설정 창 (SwiftUI)
│   │   ├── ConfigurationManager.swift   # UserDefaults 설정
│   │   ├── ClientContextDetector.swift  # 클라이언트 분석기
│   │   ├── TextConvenienceHandler.swift # 자동 대문자, 더블스페이스
│   │   ├── StatusBarManager.swift       # 메뉴 바 표시
│   │   ├── UpdateChecker.swift          # GitHub 업데이트 확인
│   │   ├── UpdateNotifier.swift         # macOS 알림 전송
│   │   ├── InputSourceManager.swift     # TIS API 래퍼
│   │   ├── DebugLogger.swift            # 조건 컴파일 로거
│   │   ├── CompositionHelpers.swift     # UCSChar→String 변환
│   │   ├── HangulComposerTypes.swift    # 프로토콜/enum 정의
│   │   ├── KeyCode.swift                # 키 코드 상수
│   │   ├── L10n.swift                   # 로컬라이제이션
│   │   ├── PriTypeConfig.swift          # 전역 상수
│   │   ├── PriTypeError.swift           # 에러 타입
│   │   ├── AboutInfo.swift              # 앱 메타데이터
│   │   └── Resources/
│   │       ├── hanja.txt                # 한자 사전 (6.4MB, ~80,000항목)
│   │       ├── jamo_symbols.json        # 자모 특수문자 (14키, 390개)
│   │       ├── ko.lproj/               # 한국어 문자열
│   │       └── en.lproj/               # 영어 문자열
│   ├── PriTypeBenchmark/           # 성능 벤치마크 타깃
│   └── PriTypeVerify/              # 빌드 검증 타깃
├── Tests/
│   └── PriTypeCoreTests/           # 109개 유닛 테스트
├── Packaging/
│   ├── Payload/                    # .app 번들 조립 경로
│   └── scripts/
│       └── postinstall             # 설치 후 스크립트
├── Info.plist                      # IMK 설정
├── PriType.entitlements            # com.apple.inputmethod.kit
├── build_release.sh                # 릴리즈 빌드+서명+패키징 스크립트
└── Package.swift                   # SPM 매니페스트
```
