<!-- Generated via multi-agent design workflow (16 agents) on 2026-06-05. Resolves 44 critique issues incl. 15 blockers. -->

# PriType 통합 설계 계획서 (Final)

> 대상: PriType-Swift 유지보수자 · 기준: v2.6.5 단일‑IME 내부 한/영 토글 모델 유지·보완
> 검증 기준일: 2026-06-05 · 모든 코드 주장은 현행 소스(`HEAD`, commit `fd72334`)와 `git show v2.6.5:` 대조로 확인함.

---

## 0. 결정된 방향 (재론의 금지)

PriType는 **하나의 macOS 입력 소스**(`com.pritype.inputmethod.v2`, `smKorean`)로 등록되고, 한/영은 **내부 상태**(`HangulComposer.inputMode`)로만 전환한다. 영어는 **순수 패스‑스루**(PriType가 아무것도 삽입하지 않고 `handle()`이 `false` 반환) + **ABC/US 키보드 레이아웃 오버라이드**로 처리한다.

토글 핫패스에서 **`TISSelectInputSource()`를 절대 호출하지 않는다** — 이것이 2.7대 첫‑키 손실/모드 불일치의 근본 원인이었다. 등록(Info.plist)은 v2.6.5의 **최소 형태**를 절대 벗어나지 않는다. 이 두 가지는 협상 대상이 아니다.

이 문서의 목표는 위 모델을 **유지하면서 약점을 체계적으로 보상**하고, 비평(critique)의 **모든 blocker를 명시적으로 해소**하는 것이다.

---

## 1. v2.6.5 단일‑IME 약점 → 보상 설계 (1:1 매핑)

| # | 약점 | 보상 설계 | 검증 |
|---|------|-----------|------|
| W1 | 메뉴바 입력소스 아이콘이 영어 모드에서도 PriType 로고로 고정 (모드 식별 불가) | `StatusBarManager`의 `가`/`A` 커스텀 인디케이터를 **권위 있는 신호**로 격상. `setup()` 명시 호출 + 상태바 메뉴에 "현재 모드" 표시 + 토글 시 짧은 HUD(선택). 메뉴바 고정은 §6.3에 **공식 트레이드오프로 문서화**. | 단위(상태바 콜백) + 온‑디바이스(육안) |
| W2 | 영어 텍스트 편의(더블스페이스→마침표, 스마트따옴표)를 호스트에 위임 — 미검증 | 호스트(macOS Text Substitution) 책임으로 **확정**. 온‑디바이스 검증을 GA 게이트로 지정. 실패 앱 발견 시 §5.2의 **최소 영어 버퍼 폴백**(더블스페이스 한정)만 복원. | 온‑디바이스(필수, §10) |
| W3 | 비‑QWERTY 물리 레이아웃(Dvorak/AZERTY)에서 ABC 오버라이드가 사용자 레이아웃을 무시 | 기본은 ABC 오버라이드. 설정에 **"영어 모드에서 내 물리 키보드 레이아웃 존중"** 토글(기본 OFF). private selector 실패 시 명시적 로그 + 폴백. | 단위(폴백 분기) + 온‑디바이스 |
| W4 | 한자 좌표 폴백이 마우스 위치로 떨어질 때 한도/경고 없음 | `isValidCursorRect` 강화(NaN/Inf/subnormal/초대형 좌표 거부) + 폴백 사용 시 전략 로그. 동일 앱 3회 연속 마우스 폴백 시 WARN. | 단위(좌표 검증) + 온‑디바이스(Chromium) |
| W5 | 신규 설치 시 자동 활성화 안 됨 (사용자가 직접 입력소스 추가해야 함) | postinstall이 신규 설치에서만 입력소스 설정 열기 + (옵션) 안전 가드된 자동 등록(§7.4). | 온‑디바이스(설치 흐름) |
| W6 | 로그인/FileVault/복구 화면에서 한국어/영어 모두 불가 | **아키텍처 경계로 명시 문서화** (§6.4). IME는 유저스페이스, 시스템 UI에는 macOS ABC가 필수. 영어 모드는 "로그인 후 유저스페이스 폴백"으로 범위 한정. | 문서 |
| W7 | Apple 한글 등 중복 입력소스 공존으로 토글 충돌 | 옵트인 정리 워크플로(`InputSourceManager.detect/cleanupAppleKoreanInputModes`) + 설정 UI 안내. `TISSelectInputSource` 미사용. | 단위(sanitize) + 온‑디바이스 |
| W8 | Caps Lock을 PriType 토글로 쓸 수 없음 (유지보수자 최우선 불만) | §4에서 **조건부 허용**으로 전면 재설계. `TISRomanSwitchState=OFF`이면 PriType가 소유, ON이면 macOS가 소유. | 단위 + 온‑디바이스 |

---

## 2. 비평 Blocker 해소 결정 (요약 — 상세는 각 섹션)

| Blocker | 결정 |
|---------|------|
| B1 문자 레퍼토리 `[Hang]` 거짓말 논란 | **`[Hang]` 유지** (단일‑IME 모델 일관). Latin 미선언 트레이드오프를 §3·§6.4에 명시 문서화. `Latn` 추가는 거부(strict‑Latin 필드에서 원치 않는 활성화 + ABC 폴백 방해). |
| B2 Caps Lock 소유권 모순 | **조건부 소유로 진짜 상호배타 구현** (§4). `keyCode 57` 무조건 거부/패스‑스루 제거, `TISRomanSwitchState`에 따라 분기. |
| B3 영어 모드 범위 vs 시스템 컨텍스트 | 영어 모드는 **유저스페이스 한정**으로 범위 확정·문서화 (§5.4, §6.4). 시스템 UI는 macOS ABC 필수. |
| B4 메뉴바 아이콘 고정 vs 사용자 기대 | **의도된 트레이드오프로 투명 문서화** (§6.3). 듀얼모드 등록(2.7 시도)은 TIS 오작동으로 거부됨을 명기. |
| B5 Caps Lock LED 하드웨어 desync 불가피 | **consume‑without‑lock‑toggle 전략 채택** (§4.3) + 불가능 케이스 폴백. LED를 신뢰 인디케이터로 마케팅하지 않음. `가`/`A`가 진실. |
| B6 CGEventTap 비결정적 실패 → IOKit 인계 미보장 | **하드 전환**: 재시도 한도 도달 시 탭 완전 정지 후 IOKit 시작 (§4.4). |
| B7 단일‑모드 TIS 등록 취약 | **빌드 전·후 이중 검증** + 단위 테스트 + Xcode GUI 편집 금지 규약 (§3). |
| B8 `overrideKeyboardWithKeyboardNamed:` private selector | respondsToSelector 가드 + 실패 시 명시 로그 + 사용자 레이아웃 폴백 옵션 (§5.3). 온‑디바이스 다중 macOS 버전 검증. |
| B9 `TISRomanSwitchState` 실시간 미반영 | 분산 알림 리스너 등록 + 변경 시 UI 갱신/배너 (§4.5). |
| B10 신규 설치 자동 등록 안 됨 | postinstall 안전 가드 자동 등록 (옵트인) (§7.4). |
| B11 비‑ANSI 키보드(ISO/JIS) 키코드 가정 | 국제 사용자 기본 토글을 **Control+Space 권장**, Key Recorder가 물리 위치 표시 (§4.6). |
| B12 빠른 키 반복/연타 가드 없음 | 토글 디바운스 + 자모 반복 테스트 (§4.7). |
| B13 한자 윈도우 + Caps Lock 상호작용 | 모드 토글 시 한자 윈도우 강제 종료, 한자를 양 모드에서 허용 (§6.5). |
| B14 SecureInput 전역 플래그 stuck | 5초 주기 재확인 + 설정 인디케이터 (§8.4). |
| B15 이모지/문자 팔레트 미가드 | 문자 팔레트 포커스 감지 시 토글 스킵 (§8.5). |

> B5/B6/B10/B11/B13/B14/B15는 비평의 세 번째 묶음에서 blocker로 분류된 항목까지 포함해 모두 처리한다.

---

## 3. 등록 계약 (REGISTRATION CONTRACT)

### 3.1 현재 상태 (검증됨)

현행 `Info.plist`는 v2.6.5와 **버전 번호 2개**(`CFBundleShortVersionString` 2.6.5→2.7.4, `CFBundleVersion` 34→39)만 다르고 구조는 **완전 동일**하다. 즉 등록은 이미 올바르다. 이 섹션의 목표는 **재퇴행 방지 자동 가드**다.

### 3.2 필수 키 (이 외 추가 금지)

**최상위:**
`CFBundleDevelopmentRegion`, `CFBundleDisplayName`, `CFBundleExecutable`, `CFBundleIconFile`, `CFBundleIconName`, `CFBundleIdentifier`(=`com.pritype.inputmethod.v2`), `CFBundleInfoDictionaryVersion`, `CFBundleName`, `CFBundlePackageType`, `CFBundleShortVersionString`, `CFBundleVersion`, `PriTypeReleaseChannel`, `InputMethodConnectionName`(=`PriType_InputString_v2`), `InputMethodServerControllerClass`(=`PriTypeInputController`), `LSUIElement`(=true), `ComponentInputModeDict`, **`tsInputMethodCharacterRepertoireKey`**(최상위, `[Hang]`), `tsInputMethodIconFileKey`(=`icon.tiff`).

> **정정**: `tsInputMethodCharacterRepertoireKey`는 **최상위**에 있다(critique의 검증기 예시는 `ComponentInputModeDict` 내부로 잘못 가정함). 검증기는 최상위에서 읽어야 한다.

**`ComponentInputModeDict` 구조 (정확히 이것만):**
```
ComponentInputModeDict
  tsInputModeListKey
    com.pritype.inputmethod.v2        ← 유일 모드 (키 = 번들 ID)
      tsInputModePrimaryInScriptKey = true
      tsInputModeScriptKey = "smKorean"
  tsVisibleInputModeOrderedArrayKey = ["com.pritype.inputmethod.v2"]
```

### 3.3 금지 키 (commit `030a035` 퇴행 원인 — 절대 재추가 금지)

- 최상위: `TISInputSourceID`, `TISIntendedLanguage`, `TISIconLabels`, `TISIconIsTemplate`, `TICapsLockLanguageSwitchCapable`, `InputMethodServerDataSourceClass`, `InputMethodServerDelegateClass`, `LSMinimumSystemVersion`, `tsInputMethodPaletteIconFileKey`, `TISUnifiedUIForInputMethodEnabling`
- 모드별: `TISInputSourceID`, `TISIntendedLanguage`, `TISIconLabels`, `TISIconIsTemplate`, `tsInputModeMenuIconFileKey`, `tsInputModeAlternateMenuIconFileKey`, `tsInputModePaletteIconFileKey`, `tsInputModeDefaultStateKey`, `tsInputModeIsVisibleKey`
- 레퍼토리: `[Hang]`만. `Latn`/`Numb`/`Punc` 추가 금지 (B1 결정).

### 3.4 자동 가드 (B7 해소)

기존 `Sources/PriTypeVerify` 타깃을 확장한다(새 `PriTypeInfoPlistValidator` 타깃 만들지 않음 — 이미 존재).

1. **`Sources/PriTypeVerify`에 `PlistContractVerifier`** 추가: 최상위 forbidden 키 0개, `ComponentInputModeDict.tsInputModeListKey`에 모드 정확히 1개(`com.pritype.inputmethod.v2`), 모드별 forbidden 0개, `tsInputModeScriptKey == "smKorean"`, `tsInputModePrimaryInScriptKey == true`, `tsVisibleInputModeOrderedArrayKey == ["com.pritype.inputmethod.v2"]`, 최상위 `tsInputMethodCharacterRepertoireKey == ["Hang"]`. 위반 시 `exit(1)`.
2. **빌드 전·후 이중 검증** (B7 핵심): `build_release.sh`/`build_debug.sh`에서
   - 빌드 직후·번들 복사 **전**: `swift run PriTypeVerify plist Info.plist || exit 1`
   - `cp Info.plist "$CONTENTS_DIR/"` **직후**: `swift run PriTypeVerify plist "$CONTENTS_DIR/Info.plist" || exit 1`
   - 추가로 `plutil -lint Info.plist` (XML 정합성).
3. **번들 ID 정합성 가드** (critique B "Info.plist Bundle ID Mismatch"): `plutil -extract CFBundleIdentifier raw Info.plist`가 코드 상수와 일치하는지 빌드 스크립트에서 확인, 불일치 시 `exit 1`.
4. **단위 테스트** `Tests/PriTypeCoreTests/RegistrationContractTests.swift`: 소스 트리의 `Info.plist`를 직접 로드(빌드 번들 의존 X), 위 계약을 `PropertyListSerialization`으로 검사.
5. **규약 문서** `Docs/RegistrationContract.md` + `CONTRIBUTING.md`에 **"Info.plist는 Xcode GUI로 편집 금지, raw XML만"** 명기.

---

## 4. 토글 + Caps Lock 설계 (유지보수자 최우선)

### 4.1 핵심 모델: 진짜 상호배타 (B2 해소)

현행 코드의 모순(검증됨):
- `ConfigurationManager.swift` getter: `binding = (decoded.keyCode == 63 || decoded.keyCode == 57) ? .defaultToggle : decoded` → Caps Lock **무조건** 거부.
- `RightCommandSuppressor.swift`: `if keyCode == 57 { return Unmanaged.passUnretained(event) }` → 동적 토글 검사 **이전**에 무조건 패스‑스루.
- `SettingsWindowController.swift`: Key Recorder가 `keyCode == 57`을 무조건 차단.

→ `TISRomanSwitchState` 상태와 무관하게 Caps Lock은 **결코** PriType 토글이 될 수 없다. 이를 **조건부**로 바꾼다:

| `TISRomanSwitchState` | Caps Lock 소유자 | PriType 커스텀 토글 | Caps Lock 바인딩 |
|---|---|---|---|
| ON | **macOS** | 비활성(`InputModeCoordinator` 가드) | 거부 (macOS 소유) |
| OFF | **PriType** (사용자가 바인딩 시) | 활성 | **허용** |

### 4.2 코드 변경 (조건부 허용)

**(a) `ConfigurationManager.toggleKeyBinding` getter** — Fn(63)만 무조건 거부, Caps Lock(57)은 `TISRomanSwitchState`에 따라:
```swift
let capsOwnedByMacOS = capsLockInputSourceSwitchEnabled
binding = (decoded.keyCode == 63
           || (decoded.keyCode == 57 && capsOwnedByMacOS)) ? .defaultToggle : decoded
```

**(b) `SettingsWindowController` Key Recorder** — `keyCode == 57`일 때:
- `capsLockInputSourceSwitchEnabled == true` → `onCapsLockBlocked()` (현행 알림, 단 문구를 "macOS Caps Lock 전환이 켜져 있습니다. 시스템 설정에서 끄면 PriType 토글로 사용할 수 있습니다"로 변경).
- `false` → 정상 바인딩 허용.

**(c) `RightCommandSuppressor.handleEvent`** — 무조건 패스‑스루 줄 삭제, 일반 modifier 토글 로직으로 흡수. 단 Caps Lock은 lock‑state 특성상 §4.3 처리 적용.

**(d) `IOKitManager`** — `usage 0x39`(Caps Lock) 이미 매핑됨(검증). 동일 디바운스/가드 적용.

### 4.3 consume‑without‑lock‑toggle 전략 (B5 해소 — 핵심 결정)

비평 B5는 "CGEventTap이 LED를 못 막으니 desync 불가피"라 했으나, 이는 **부분적으로 회피 가능**하다. macOS에서 Caps Lock의 lock‑state 전환은 `flagsChanged` 이벤트가 시스템에 도달해 처리될 때 일어난다. CGEventTap이 **다운 엣지에서 이벤트를 소비(`return nil`)하면**, 시스템은 그 전환 이벤트를 보지 못하므로 **상당수 macOS 구성에서 LED lock‑state 토글이 억제된다**. (HID 드라이버가 독립적으로 토글하는지는 하드웨어/버전 의존적이므로 단정하지 않는다.)

**채택 전략:**
1. Caps Lock이 PriType 토글로 바인딩 + `TISRomanSwitchState=OFF`일 때, `flagsChanged`의 **lock‑on 엣지**(`.maskAlphaShift` 새로 set)에서 `triggerToggle()` 후 `return nil`로 **소비 시도**.
2. **LED를 신뢰 인디케이터로 사용하지 않음**: `가`/`A` 상태바가 진실. 설정 `CapsLockStatusCard`에 "일부 키보드/macOS 버전에서 Caps Lock LED가 실제 모드와 다를 수 있습니다. 메뉴바의 `가`/`A`가 정확한 표시입니다"라 명시.
3. **LED desync 감지 폴백** (critique 셋째 묶음 major): 500ms 주기로 IOKit(`IOHIDElement`)에서 Caps Lock lock‑state를 읽어 `inputMode`와 불일치 시 상태바에 경고 표식(아이콘 색/툴팁). 정정은 불가하므로 **알림만** 한다.
4. **완전 억제 불가 시 폴백**: 온‑디바이스에서 LED 억제가 안 되는 것이 확인되면, 설정에 "Caps Lock LED가 모드와 어긋남 — Right Command/Control+Space 권장" 배너를 띄우되 기능은 유지(사용자 선택). **Caps Lock 바인딩을 lock‑state 신뢰성 솔루션으로 광고하지 않는다.**

### 4.4 CGEventTap 실패 → IOKit 하드 전환 (B6 해소)

현행(검증): 재시도 한도 도달 시 `onTapFailed` 콜백을 async로 호출하되 **탭은 계속 재활성화 시도** → 좀비 탭 위험.

**변경:** `tapDisableCount >= maxTapDisableRetries`일 때:
```swift
CGEvent.tapEnable(tap: tap, enable: false)   // 완전 정지
CFRunLoopRemoveSource(...); eventTap = nil; runLoopSource = nil
DispatchQueue.main.async { onTapFailed?() }   // 그 다음에만 IOKit 시작
```
`main.swift`의 `onTapFailed`가 `IOKitManager.start()`를 호출하도록 보장. **단위 테스트:** 3회 disable 후 `isRunning == false`이고 IOKit 시작 콜백이 정확히 1회 호출.

### 4.5 `TISRomanSwitchState` 실시간 반영 (B9 해소)

현행(검증): 매 호출마다 `CFPreferencesCopyValue` 읽음(캐싱 없음) → 다음 키 입력에서 반영되지만, 변경 즉시 토글이 조용히 죽어 사용자 혼란.

**변경:**
1. `ConfigurationManager` 초기화 시 `CFNotificationCenterAddObserver`(Darwin notify) 또는 `NSDistributedNotificationCenter`로 `AppleKeyboardUIMode`/HIToolbox 변경 관찰. 변경 감지 시 로그 + `keyBindingChanged` 알림 발행 → UI 갱신.
2. `CapsLockStatusCard`에 변경 후 5초간 노란 배너: "토글 동작이 변경됨 — 완전 동기화하려면 PriType 재시작 권장."
3. 핫패스 성능: 매 키 입력마다 `CFPreferencesCopyValue` 호출은 유지하되(정확성 우선), 알림 기반 캐시를 도입해 IPC 빈도를 낮추는 것은 **후속 최적화**로 분류.

### 4.6 비‑ANSI 키보드 (B11 해소)

키코드(54=Right Command, 57=Caps Lock 등)는 ANSI 가정. ISO/JIS에서 물리 위치가 달라질 수 있다.

**MVP 결정:**
1. 국제 사용자 기본 권장 토글을 **Control+Space**(Space는 레이아웃 불변)로 안내. 기본값은 Right Command 유지(국내 다수).
2. Key Recorder가 녹화 시 키코드와 함께 **물리 위치 힌트**(가능하면 TIS로 현재 레이아웃 조회) 표시.
3. 설정 도움말에 "토글 키 바인딩은 ANSI 레이아웃 기준. ISO/JIS 사용자는 Control+Space 권장" 명시.

### 4.7 디바운스 + 연타/키반복 가드 (B12 해소)

1. **토글 디바운스**: `RightCommandSuppressor`/`IOKitManager`에 `lastToggleTime` + 임계값. **비평 권고 반영**: 단순 200ms 차단은 의도적 재토글을 막으므로, **첫 토글은 항상 발화**하고 같은 시퀀스 내 추가 발화만 억제하는 스마트 디바운스(예: 직전 토글 후 동일 키 재발화가 250ms 내면 1회만). 값은 온‑디바이스 튜닝 후 확정, 필요 시 설정 슬라이더(50–500ms).
2. **자모 반복**: 동일 키 홀드(키 반복 ~60ev/s) 시 libhangul이 조합을 처리하므로 `localTextBuffer` 누적만 주의. 단위 테스트 `ㄱㄱㄱ` → 합성 1자 검증.

---

## 5. 영어 패스‑스루 완전성

### 5.1 계약 (검증됨)

`HangulComposer.handle()`에서 `inputMode == .english`이면 진행 중 조합 커밋 후 `localTextBuffer = ""`, **`return false`**. 로컬 버퍼/마크드 텍스트 없음 → 커서‑버퍼 desync 원천 차단. Roman 글자는 컨트롤러의 `overrideKeyboardWithKeyboardNamed(ABC/US)`에서 나온다.

### 5.2 텍스트 편의 = 호스트 책임 (B2/W2)

더블스페이스→마침표, 스마트따옴표, 자동수정은 **macOS Text Substitution**이 패스‑스루 키에 적용. PriType는 영어 모드에서 재구현하지 않음. **GA 게이트 검증** 후, 특정 앱(Slack/Electron 등)에서 더블스페이스가 안 되면 `TextConvenienceHandler.handleEnglishModeInput`을 **더블스페이스 한정**으로만 복원(전체 영어 버퍼는 복원 금지 — design debt 회귀 방지).

### 5.3 키보드 레이아웃 오버라이드 (B8/W3)

`overrideKeyboardWithKeyboardNamed:`는 private selector(검증). 보강:
1. `responds(to:)` 가드 + 호출 전후 로그(런타임 실패 감지).
2. 실패 시 조용한 폴백 대신 **명시 로그** + (옵션) 설정 "내 물리 키보드 레이아웃 존중"(기본 OFF=ABC 강제, ON=오버라이드 생략).
3. **다중 macOS 버전 온‑디바이스 검증 필수**(14/15/16) — selector 가용성·동작 확인.

### 5.4 시스템 컨텍스트 경계 (B3)

영어 모드는 **유저스페이스 한정**. 로그인/FileVault/복구/펌웨어 화면에서는 PriTypeInputController 자체가 인스턴스화되지 않으므로 영어 모드도 동작하지 않는다. 이는 PriType 결함이 아니라 IME 아키텍처 경계다. → §6.4 문서화. Shift/Option/Command 조합은 호스트가 `NSEvent.characters`로 이미 계산하므로 패스‑스루로 충분(현행 modifier 가드 검증됨).

---

## 6. 한/영 상태 머신 + 표시

### 6.1 단일 진실원 (검증됨)

`HangulComposer.inputMode`는 `public private(set)`, 초기 `.korean`. **쓰기 경로 2개만**: `PriTypeInputController.performPriTypeModeTransition`(커스텀 토글), `setValue(_:forTag:)`(TIS 재선택). `activateServer`/`handle()`/`deactivateServer`는 절대 쓰지 않음. 토글은 `InputModeCoordinator.requestToggle` → 컨트롤러로 async 디스패치(검증). 문서 주석으로 불변식 고정.

### 6.2 첫‑키 안정성 (critique major)

`triggerToggle()`은 main으로 async 디스패치(검증, v2.6.5 동일). 첫‑키 손실은 실제 ABC 소스 선택이 없으므로 구조적으로 제거됨. **다만** Electron류 async 클라이언트 콜백 경계 race를 온‑디바이스로 검증(§10 #1). 손실 관측 시 **pending‑mode 패턴** 도입: 토글 시 `pendingMode`만 세팅, 다음 `handle()` 진입에서 키 처리 전 원자적으로 적용.

### 6.3 메뉴바 트레이드오프 (B4)

macOS 입력소스 아이콘은 양 모드에서 PriType로 **고정**(단일‑IME 설계로 의도). 듀얼모드 등록(2.7 시도)은 TIS 오작동(한국어 조합 실패)으로 거부됨. **보상:** `StatusBarManager.setup()`을 `applicationDidFinishLaunching`에서 **명시 호출**(현행 미호출 검증됨 — lazy 의존 제거), 상태바 메뉴에 "현재 모드" 추가. 릴리스 노트·설정에 트레이드오프 투명 기재.

### 6.4 시스템 UI 경계 문서 (W6/B3)

`Docs/UnifiedInputArchitecture.md §7`에 명기: "PriType는 유저스페이스 IME로 로그인/FileVault/복구/펌웨어 화면에서 동작 불가. 이들 컨텍스트는 macOS ABC가 필수이며 항상 사용 가능. 영어 모드는 로그인 후 유저스페이스 폴백일 뿐 시스템 전역 폴백이 아님."

### 6.5 한자 + Caps Lock 상호작용 (B13)

1. 한자 트리거를 **양 모드 허용**: 한국어 모드는 당연, 영어 모드도 `localTextBuffer`에 한글이 있으면 그 마지막 글자로 조회(코드‑스위칭 워크플로 지원).
2. 모드 토글(어떤 경로든 Caps Lock 포함) 시 한자 윈도우 **강제 종료**(`hanjaMode = false`, 윈도우 닫기). 단위 테스트로 검증.

---

## 7. 자기충족성 & 공존 (다중 소스 혼란 제거)

### 7.1 정책

PriType 단독으로 일상 타이핑 충족(한국어 조합 + 영어 패스‑스루). ABC는 macOS 내장 **읽기 전용 폴백**(로그인/보안 필드용)으로, 사용자가 굳이 입력소스 목록에 추가할 필요 없음.

### 7.2 옵트인 정리 (W7)

`InputSourceManager`에 추가:
- `detectAppleKoreanInputModes() -> Bool`: `AppleEnabledInputSources`에서 `com.apple.inputmethod.Korean`/`ironwood` 탐지.
- `cleanupAppleKoreanInputModes() -> Int`: 3개 HIToolbox 키에서 제거, `CFPreferencesAppSynchronize`, 캐시 에이전트 kill. **`TISSelectInputSource` 미사용**(핫패스 race 없음). 설정 UI 버튼에서만 호출(유틸 스레드).

### 7.3 설정 UI

새 "입력 소스" 섹션: 권장 구성 안내, PriType(녹색 체크)·ABC(회색 내장) 상태, Apple 한글 감지 시에만 "제거" 버튼(확인 다이얼로그 포함). L10n(en/ko) 추가.

### 7.4 신규 설치 자동 등록 (B10/W5)

`Packaging/scripts/postinstall`:
1. `IS_UPDATE` 판정을 **정확한 번들 ID**로 강화: `grep 'com.pritype.inputmethod.v2'`(현행 느슨한 `pritype` 매치 위험 — critique 반영). 모호하면 `IS_UPDATE=true` 기본(설정 중복 오픈 방지).
2. **신규 설치만**: 안전 가드 자동 등록 — `AppleEnabledInputSources`에 PriType가 **없을 때만** `TISEnableInputSource` 시도(번들 누락/손상 시 시스템 로그 경고). 실패해도 입력소스 설정 열기로 폴백.
3. 셸 견고화(critique major): `#!/bin/sh`(POSIX), `killall -KILL -w <agent>` 타임아웃, 중요 단계 실패 시 `exit 1` + stderr 로그.

---

## 8. 앱 호환성 (번들‑ID 하드코딩 없이)

### 8.1 GoodNotes Return 중복 (검증됨)

현행 `HangulComposer.swift:198`이 `ClientCompatibilityPolicy.needsDirectNewlineAfterReturnCommit(bundleId:)`로 `com.goodnotesapp.x` 하드코딩(검증). **행동 기반 탐지로 대체:** 새 `IMKClientReturnDuplicationDetector`가 Return 콜백 재진입 타이밍(<50ms, 동일 클라이언트)으로 버그를 식별, `ObjectIdentifier`별 캐시. `ClientCompatibilityPolicy`는 deprecation 주석 후 v2.8 제거 예정. 단위 테스트(합성 타임스탬프)로 결정성 확보.

### 8.2 한자 좌표 (검증됨, 자동 폴백)

`isValidCursorRect` 강화: NaN/Inf/subnormal(|v|<0.1)/초대형(>10000) 거부 + 모든 연결 화면(NSScreen, 음수 좌표 포함) 포함 검사. 앱별 코드 없음. 멀티모니터/Chromium은 온‑디바이스 검증(§10).

### 8.3 Finder 데스크톱 (정당한 예외, 격리)

Finder의 더미 IMK 윈도우 좌표 휴리스틱은 유일하게 정당한 좌표 기반 예외. `finderDesktopThreshold` → `finderDummyWindowCoordinateThreshold` 개명 + 정당성 주석. Finder 번들‑ID 체크는 시스템 엔티티로 허용(SecureInputPolicy와 동급 근거).

### 8.4 SecureInput 전역 stuck (B14)

`IsSecureEventInputEnabled()`는 전역 플래그. 버그 앱이 안 끄면 PriType 토글이 영구 정지 위험. **보강:** 결과 캐시 + **5초 주기 재확인**(매 키 입력 X), OFF로 바뀌면 정상 복귀 + 로그. 설정에 "보안 입력 전역 활성(비밀번호 필드 등)" 인디케이터.

### 8.5 문자 팔레트/이모지 (B15)

이모지 피커/문자 팔레트는 IMK 외부. 포커스된 윈도우 감지(AXUIElement/NSWindow 스캔)로 팔레트 포커스 시 **토글 처리 스킵**, 키 패스‑스루. 온‑디바이스 검증.

### 8.6 정책 문서

`Docs/AppCompatibilityPolicy.md`: 번들‑ID 허용 예외는 (1) 시스템 클라이언트(보안), (2) Finder 더미 윈도우(유일 IMK 구현), (3) 행동 탐지된 IMK 버그(목록 아님)뿐. 개방형 번들‑ID 목록 금지. 각 탐지기는 단위 테스트 필수.

---

## 9. 횡단 불변식 (INVARIANTS)

1. 토글 핫패스에서 `TISSelectInputSource()` 호출 금지.
2. `Info.plist`는 §3.2/3.3 계약 준수 — 모드 정확히 1개, `smKorean`, `[Hang]`, forbidden 0개. 모든 빌드가 검증 통과해야 함.
3. `HangulComposer.inputMode` 쓰기 경로는 `performPriTypeModeTransition`·`setValue` 2개뿐.
4. 영어 모드 = 순수 패스‑스루(`return false`, 로컬 버퍼/마크드 텍스트 없음).
5. Caps Lock 소유는 `TISRomanSwitchState`로 **진짜 상호배타**: ON=macOS, OFF=PriType(바인딩 시).
6. `가`/`A` 상태바가 권위 인디케이터. LED/메뉴바 아이콘은 신뢰 대상 아님.
7. CGEventTap/IOKit 중 **한 번에 하나만** 활성(하드 전환).
8. 행동 기반 호환성 탐지만 허용(시스템 클라이언트·Finder 예외 제외).
9. 정리(cleanup)는 데이터 레이어(prefs)만, 핫패스·`handle()` 비관여.
10. RELEASE 빌드에서 DebugLogger 비활성, 키 입력 데이터 미유출.

---

## 10. 리스크 & 온‑디바이스 필수 검증

**단위로 검증 불가 — 반드시 온‑디바이스:**
1. (GA 게이트) **영어 더블스페이스→마침표**: TextEdit/Safari/Chrome/VS Code/Slack 전수. 실패 앱 발견 시 §5.2 폴백.
2. **첫‑키 안정성**: 토글 직후 즉시 타이핑(Chromium/Electron 포함) — 손실/중복 없음.
3. **Caps Lock LED 억제 여부**: 다양한 키보드(Magic/USB/게이밍)에서 consume 시 LED 토글 억제되는지 — B5 전략 유효성.
4. **`overrideKeyboardWithKeyboardNamed:` 가용성**: macOS 14/15/16 영어 출력 확인 (B8).
5. **`TISRomanSwitchState` 런타임 변경**: 설정 토글 시 PriType 토글 즉시 활성/비활성 + 배너.
6. **한자 좌표**: Chromium 조합 중 트리거 — 윈도우 위치 합리성.
7. **멀티모니터(음수 좌표)** 한자 위치.
8. **신규 설치 흐름**: postinstall 자동 등록/설정 열기, 업데이트는 미오픈.
9. **v2.6.5 롤백**: 언인스톨 후 v2.6.5 설치 — 조합/토글 정상.
10. **디바운스 체감**: 의도적 재토글이 막히지 않는지(§4.7 스마트 디바운스 튜닝).

**리스크:** DebugLogger 핫패스 비용(RELEASE 비활성으로 무해, DEBUG는 상태 변화·마일스톤만 로깅, 200 이벤트 캡 — critique 반영); 롤백 시 stale prefs 누적(v2.6.6 패치 또는 롤백 전 정리 안내 권장); private selector 장기 호환성.

---

## 11. 순차 구현 계획 (단계별 파일 변경 + 수용 기준)

### Phase 0 — 등록 가드 (퇴행 방지, 위험도 최저)
**파일:** `Sources/PriTypeVerify/*`(PlistContractVerifier 추가), `build_release.sh`, `build_debug.sh`, `Tests/PriTypeCoreTests/RegistrationContractTests.swift`, `Docs/RegistrationContract.md`, `CONTRIBUTING.md`.
**수용:** 정상 plist는 빌드 통과; forbidden 키 1개라도 주입 시 빌드 실패(전·후 이중); 번들 ID 불일치 시 실패; 단위 테스트 녹색.

### Phase 1 — 토글/IOKit 하드 전환 + 첫‑키 가드 (B6)
**파일:** `RightCommandSuppressor.swift`(탭 완전 정지 후 인계), `main.swift`(`onTapFailed`→IOKit), `InputModeCoordinator.swift`(주석/가드 정리), `Tests/.../ToggleHandoffTests.swift`.
**수용:** 3회 disable 후 `isRunning==false` + IOKit 1회 시작(단위); 토글 디스패치 race 단위 테스트.

### Phase 2 — Caps Lock 조건부 소유 (B2/B5/유지보수자 최우선)
**파일:** `ConfigurationManager.swift`(조건부 거부), `RightCommandSuppressor.swift`(무조건 패스‑스루 제거 + consume 엣지 + 디바운스), `IOKitManager.swift`(디바운스), `SettingsWindowController.swift`(Key Recorder 조건부 + CapsLockStatusCard 갱신), `L10n.swift`, `en/ko Localizable.strings`, `Tests/.../ToggleCapsLockTests.swift`.
**수용:** `TISRomanSwitchState=OFF`에서 Caps Lock 바인딩 직렬화/역직렬화 통과(단위); ON에서 거부(단위); 온‑디바이스 #3/#5/#10.

### Phase 3 — TISRomanSwitchState 실시간 + LED 감지 (B9/B5)
**파일:** `ConfigurationManager.swift`(알림 리스너), `StatusBarManager.swift`(desync 표식 + `setup()` 명시 호출), `SettingsWindowController.swift`(배너), `main.swift`(setup 호출).
**수용:** 설정 변경 시 UI/배너 갱신(온‑디바이스 #5); 상태바 launch 시 즉시 표시.

### Phase 4 — 영어 완전성 + 레이아웃 폴백 (B8/W3/B3)
**파일:** `PriTypeInputController.swift`(responds(to:) 가드 + 로그 + 레이아웃 옵션), `SettingsWindowController.swift`(레이아웃 존중 토글), `TextConvenienceHandler.swift`(폴백 훅 — 더블스페이스 한정, 기본 비활성), `Docs/UnifiedInputArchitecture.md §4.x/§7`.
**수용:** 온‑디바이스 #1(GA 게이트)/#4; selector 실패 분기 단위.

### Phase 5 — 자기충족성/공존 + 설치 (W7/B10)
**파일:** `InputSourceManager.swift`(detect/cleanup), `SettingsWindowController.swift`(입력소스 섹션), `Packaging/scripts/postinstall`(POSIX 견고화 + 정확 ID + 자동 등록 가드), `L10n.swift`, `en/ko Localizable.strings`, `Tests/.../InputSourceManagerTests.swift`.
**수용:** sanitize/detect 단위; 온‑디바이스 #8.

### Phase 6 — 앱 호환성 행동 탐지 (GoodNotes/SecureInput/팔레트/한자)
**파일:** `IMKClientReturnDuplicationDetector.swift`(신규), `HangulComposer.swift`(탐지기 연동 + `isValidCursorRect` 강화 + 한자 양모드/토글시 종료), `ClientContextDetector.swift`(Finder 주석/개명 + Policy deprecate), SecureInput 5초 재확인, 문자 팔레트 감지, `Docs/AppCompatibilityPolicy.md`, `Tests/.../ClientContextTests.swift`·`HangulComposerTests.swift`.
**수용:** 탐지기/좌표/한자 단위; 온‑디바이스 #2/#6/#7.

### Phase 7 — 표시/접근성 마감 + 문서
**파일:** `StatusBarManager.swift`(메뉴 "현재 모드", 접근성 announcement), 릴리스 노트, `Docs` 트레이드오프 정리.
**수용:** VoiceOver 모드 안내 온‑디바이스; 문서 리뷰.

> 의존성: Phase 0은 즉시·독립. Phase 1→2→3 순차(Caps Lock이 토글 인프라 의존). Phase 4/5/6은 Phase 2 이후 병렬 가능. Phase 7 최종.

---

## 12. 검증 & 롤아웃

- **단위 테스트 확장:** 등록 계약, 토글/IOKit 인계, Caps Lock 직렬화·상호배타, `isValidCursorRect`, Return 중복 탐지기, 한자 양모드/토글 종료. `ConfigurationProviding`(기존)·신규 `ToggleKeyProviding`로 주입해 Caps Lock ON/OFF 모킹.
- **DEBUG 로깅:** `~/Library/Logs/PriType/pritype_debug.log`. 핫패스는 **상태 변화·마일스톤만**(토글, 모드 전환, Caps Lock 탐지, 탭 실패, 첫‑키 진입) — 매 키 입력 로깅 금지(critique 반영). RELEASE 비활성.
- **빌드 타임:** Phase 0의 plist 전·후 이중 검증 + `plutil -lint` + 번들 ID 정합성. CI가 실패 시 릴리스 차단.
- **단계적 롤아웃:** (1) 유지보수자 DEBUG 자체 검증(§10 전수) → (2) `2.7.5-beta` 베타(로그 수집) → (3) `2.7.5` 안정. GA 전 **#1(영어 더블스페이스)** 통과 필수.
- **v2.6.5 폴백:** 번들 ID·모드 ID·Info.plist 구조 동일(버전 번호만 차이, 검증됨)이라 안전. 롤백 절차: `sudo rm -rf "/Library/Input Methods/PriTypeV2.app"` 후 v2.6.5 pkg 설치(양 버전 postinstall이 TIS 에이전트 kill·재등록). stale prefs 누적 우려 시 롤백 전 설정의 입력소스 정리 실행 권장, 또는 정리 로직 포함 **v2.6.6**을 공식 폴백으로 발행.

---

**핵심 요약:** 단일‑IME 내부 토글 모델을 유지하되, (1) 등록을 자동 가드로 잠그고, (2) Caps Lock을 `TISRomanSwitchState` 기반 진짜 상호배타로 1급 내부 토글화하며(LED 억제 시도 + desync 감지 폴백), (3) CGEventTap→IOKit 하드 전환으로 비결정성을 제거하고, (4) 영어 편의·시스템 경계·메뉴바 트레이드오프를 투명 문서화하며, (5) 번들‑ID 하드코딩을 행동 기반 탐지로 대체한다. 모든 blocker는 위에서 구체적 코드 변경·파일·수용 기준과 함께 해소했다.

**관련 파일(절대 경로):**
- `/Users/naen/Git/PriType-Swift/Info.plist`
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeCore/ConfigurationManager.swift` (토글 getter L370‑371, `capsLockInputSourceSwitchEnabled` L443‑460)
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeCore/RightCommandSuppressor.swift` (`keyCode==57` 무조건 패스‑스루, 탭 실패 인계, `triggerToggle` async)
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeCore/IOKitManager.swift` (Caps Lock usage `0x39` L65)
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeCore/InputModeCoordinator.swift`
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeCore/HangulComposer.swift` (영어 패스‑스루 L368‑374, Return/GoodNotes L198, `isValidCursorRect`)
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeCore/ClientContextDetector.swift` (`ClientCompatibilityPolicy` L101‑106)
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeCore/SettingsWindowController.swift` (Key Recorder Caps Lock 차단 L939‑944)
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeCore/StatusBarManager.swift` (`setup()` 미호출)
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeCore/InputSourceManager.swift`
- `/Users/naen/Git/PriType-Swift/Sources/PriType/main.swift` (`onTapFailed`/IOKit 선택)
- `/Users/naen/Git/PriType-Swift/Sources/PriTypeVerify/` (검증기 확장 위치 — 이미 존재)
- `/Users/naen/Git/PriType-Swift/build_release.sh`, `/Users/naen/Git/PriType-Swift/build_debug.sh` (Info.plist 복사 지점)
- `/Users/naen/Git/PriType-Swift/Packaging/scripts/postinstall`
