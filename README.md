# PriType

macOS용 네이티브 한글 입력기. Swift 6 / InputMethodKit 기반이며, 한글 조합 엔진으로 자체 개발한 [libhangul-swift](https://github.com/Meapri/libhangul-swift)를 사용한다.

## 아키텍처

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

### 입력 처리 흐름

1. macOS가 키 이벤트를 `PriTypeInputController.handle()`에 전달한다.
2. `handle()`은 캐싱된 `ClientContext`를 참조해 Secure Input 여부, Finder 바탕화면 여부를 판정한다.
3. 판정을 통과하면 `ClientAdapter`로 감싸서 `HangulComposer.handle()`에 위임한다.
4. `HangulComposer`는 libhangul-swift의 `ThreadSafeHangulInputContext`를 통해 한글 조합을 수행하고, preedit(밑줄 표시)과 commit(확정 삽입)을 `ClientAdapter` 콜백으로 전달한다.
5. `ClientAdapter`는 `IMKTextInput` 프로토콜을 통해 최종 텍스트를 앱에 삽입한다.

### 한/영 전환 흐름

`RightCommandSuppressor`가 `CGEventTap`으로 시스템 레벨 키 이벤트를 가로채서 우측 Command(토글), 우측 Option(한자), Control+Space(토글)를 처리한다. CGEventTap이 시스템에 의해 반복 비활성화되면 `IOKitManager`(IOHIDManager 기반)로 자동 전환된다.

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
| **PriTypeInputController** | `IMKInputController` 서브클래스. `activateServer` → `handle()` → `deactivateServer` 수명 주기를 관리한다. 내부에 `ClientAdapter`(밑줄 표시 모드)와 `ImmediateModeAdapter`(Finder 바탕화면용, setMarkedText 생략) 두 가지 어댑터를 포함한다. |
| **ClientContextDetector** | 입력 클라이언트 분석기. 번들 ID, `validAttributesForMarkedText`, 좌표 휴리스틱을 조합해 `ClientContext` 구조체를 생성한다. Finder 바탕화면은 좌표 기반(`y < 50`)으로 판별한다. |
| **RightCommandSuppressor** | `CGEventTap` 기반 시스템 레벨 키 인터셉터. 우측 Command(한/영), 우측 Option(한자), Control+Space(한/영)를 처리한다. 이벤트 탭 비활성화 시 재활성화를 시도하며, 60초 내 3회 실패 시 IOKit 백업으로 자동 전환한다. |
| **IOKitManager** | `IOHIDManager` 기반 하드웨어 레벨 키 모니터. CGEventTap 실패 시 백업 핸들러로 동작한다. 우측 Command(한/영)와 우측 Option(한자)을 처리한다. |
| **HanjaCandidateWindow** | SwiftUI 기반 한자 후보 패널. `NSPanel`을 재사용하며, `screenSaver + 1` 윈도우 레벨로 Electron 앱 위에 표시된다. 1~9 숫자키 선택, 방향키/Tab 페이지 이동을 지원한다. |
| **HanjaManager** | 한자 사전 로더. `hanja.txt`(6.4MB, 약 80,000 항목)를 번들에서 읽어 libhangul의 `HanjaTable`에 적재한다. 검색 결과는 LRU 캐시(32개)로 재사용한다. |
| **ConfigurationManager** | `UserDefaults` 기반 설정 관리. 자판 배열, 토글 키, 자동 대문자, 더블스페이스 마침표, 자동 업데이트 확인 옵션을 저장한다. `ConfigurationProviding` 프로토콜로 테스트 시 목(mock) 주입이 가능하다. |
| **SettingsWindowController** | SwiftUI `NSHostingController` 기반 설정 창. 반투명 배경, 접근성 권한 확인/요청, ABC 입력소스 제거 안내 기능을 포함한다. |
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

## 빌드

### 요구사항
- macOS 26.0+ (Tahoe)
- Swift 6.2+

### 개발 빌드
```bash
swift build
```

### 릴리즈 PKG 생성
```bash
./build_release.sh
```

릴리즈 빌드 과정:
1. `swift build -c release`로 최적화 바이너리 생성
2. `.app` 번들 구조 조립 (Info.plist, 리소스, 아이콘, 한자 사전)
3. `codesign`으로 Developer ID Application 서명
4. `pkgbuild`로 PKG 생성 후 Developer ID Installer 서명
5. `xcrun notarytool`로 Apple 공증 후 `stapler`로 스테이플

### 설치
[Releases](https://github.com/Meapri/PriType-Swift/releases) 페이지에서 PKG를 다운로드하여 설치한다. Apple 공증 완료 상태이므로 Gatekeeper 경고 없이 설치된다.

설치 후 `시스템 설정 > 키보드 > 입력 소스 편집`에서 PriType을 추가한다. 최초 설치 시 로그아웃이 필요할 수 있다. 업데이트 시에는 PKG를 덮어 설치하면 실행 중인 프로세스가 자동 교체된다.

## 디렉토리 구조
```
PriType-Swift/
├── Sources/
│   ├── PriType/                    # 실행 타깃 (main.swift)
│   ├── PriTypeCore/                # 코어 라이브러리
│   │   ├── HangulComposer.swift        # 한글 조합 엔진 (715줄)
│   │   ├── PriTypeInputController.swift # IMK 컨트롤러 (278줄)
│   │   ├── RightCommandSuppressor.swift # CGEventTap 핸들러
│   │   ├── IOKitManager.swift           # IOKit 백업 핸들러
│   │   ├── HanjaCandidateWindow.swift   # 한자 후보창 (SwiftUI)
│   │   ├── HanjaManager.swift           # 한자 사전 로더 + LRU 캐시
│   │   ├── SettingsWindowController.swift# 설정 창 (SwiftUI, 679줄)
│   │   ├── ConfigurationManager.swift   # UserDefaults 설정
│   │   ├── ClientContextDetector.swift  # 클라이언트 분석기
│   │   ├── TextConvenienceHandler.swift # 자동 대문자, 더블스페이스
│   │   ├── StatusBarManager.swift       # 메뉴 바 "가/A" 표시
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
│   │       ├── ko.lproj/               # 한국어 문자열
│   │       └── en.lproj/               # 영어 문자열
│   └── PriTypeVerify/              # 빌드 검증 타깃
├── Tests/                          # 테스트
├── Packaging/
│   ├── Payload/                    # .app 번들 조립 경로
│   └── scripts/
│       └── postinstall             # 설치 후 스크립트
├── Info.plist                      # IMK 설정 (ConnectionName, ControllerClass)
├── PriType.entitlements            # com.apple.inputmethod.kit
├── build_release.sh                # 릴리즈 빌드+서명+패키징 스크립트
└── Package.swift                   # SPM 매니페스트
```

## 라이선스

MIT License
