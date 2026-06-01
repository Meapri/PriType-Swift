# PriType 통합 입력 아키텍처 (Unified Input Architecture)

작성일: 2026-06-01
상태: **canonical** — 이 문서가 한/영 입력 구조의 정식 명세다.

이 문서는 `v2.6.5`(내부 모드 통합)와 `v2.7.2`(macOS 입력 소스 통합)의 장점을 결합한
현재 아키텍처를 기술한다. 과거의 [InputArchitectureHybridRollbackPlan.md](InputArchitectureHybridRollbackPlan.md)는
"영어 가짜 모드 2개 등록" 안을 제안했으나, 실제 구현은 더 단순한 **단일 소스 하이브리드**로
수렴했다. 그 차이와 근거는 아래 §2.1에 정리한다.

---

## 1. 결합 원리

두 버전이 각각 다른 것을 잘했고, 동시에 못 가지는 근본 충돌이 있었다.

| | 2.6.5 (내부 모드) | 2.7.2 (실 ABC 소스) |
| --- | --- | --- |
| 한/영 상태 진리 | `HangulComposer.inputMode` 단일 | TIS source + IMK mode + composer (분산) |
| 전환 경로 | 프로세스 내부, 동기 | `TISSelectInputSource(ABC)` 비동기 |
| 첫 글자 안정성 | 안정 (race 거의 없음) | "전환 직후 첫 키 씹힘" |
| 모드/입력 일치 | 일관 | "한글인데 영어 쳐짐" |
| 영어 = 진짜 macOS ABC | 아님 (내부 처리) | 맞음 |
| 메뉴바/입력소스 UI 통합 | 덜 자연스러움 | 자연스러움 |
| Caps Lock = macOS 소유 | 아님 (PriType가 가로챔) | 맞음 |

**근본 충돌:** 실제 ABC source가 선택되는 순간 PriType는 현재 IMK 입력 세션 소유권을 잃는다.
그래서 "진짜 ABC + 무지연 내부 전환"은 양립 불가능하다. 전환 race(2.7.2의 씹힘/불일치)는
*실제 입력 소스 선택*과 *PriType 내부 composer mode*가 서로 다른 비동기 시스템이라는 데서 온다.

**결합안:** PriType 단일 입력 소스가 IMK 세션을 **영구 소유**하고, 한/영은 `HangulComposer.inputMode`
하나로 내부 전환한다(2.6.5의 무지연·일관성). 영어는 조합하지 않고 raw key를 pass-through하며,
`overrideKeyboardWithKeyboardNamed`로 로마자 레이아웃을 입혀 ABC를 *체감*으로 재현한다(2.7대의 통합 일부).
Caps Lock 기반 전환은 그대로 macOS가 소유하고, 이때 PriType custom toggle은 비활성화한다.

---

## 2. 권장 구조

```
CGEventTap / IOKit  ──(키 감지만)──►  InputModeCoordinator   (정책: Caps Lock·controller 유무)
                                            │ requestToggle
                                            ▼
                              PriTypeInputController          (IMK 세션 imperative edge)
                                  │ performPriTypeModeTransition
        ┌─────────────────────────┼──────────────────────────┐
        ▼                         ▼                          ▼
  commit 1회             overrideKeyboard(ABC/US)      composer.setInputMode
  (조합 정리)             (영어 레이아웃 보정)          (★ 단일 진리)
                                            │
                          ┌─────────────────┴─────────────────┐
                     .korean                                .english
              libhangul 조합 + marked text          순수 pass-through (return false)
                                                    StatusBar "A", macOS가 영문 처리
```

### 2.1 단일 소스 등록 (영어 가짜 모드 미등록)

`Info.plist`는 `ComponentInputModeDict` 아래 **단일 모드** `com.pritype.inputmethod.v2`만 등록한다
(`tsInputModeScriptKey = smKorean`). 별도의 `...english` 가짜 모드는 등록하지 않는다.

과거 RollbackPlan은 Korean/English 두 가짜 모드 등록을 제안했지만 채택하지 않는다. 이유:

- 메뉴바 모드 표시는 [StatusBarManager](../Sources/PriTypeCore/StatusBarManager.swift)의 `가`/`A`가 이미 담당한다.
  가짜 영어 모드의 유일한 명분(메뉴 표시)이 불필요하다.
- 두 모드는 전환마다 `selectInputMode:`라는 **또 다른 비동기 IMK 호출을 hot path에 추가**한다.
  이는 `composer.inputMode`와 desync 가능 → 우리가 제거하려던 race를 재도입한다.
- 2.7대에서 고생한 입력 소스 중복, `tsVisibleInputModeOrderedArrayKey` 튜닝, stale ID 정리가 다시 필요해진다.

**트레이드오프(수용):** 영어 모드일 때도 macOS 메뉴바의 입력 소스 아이콘은 PriType(한글)로 남는다.
이는 2.6.5와 동일한 화면상 사소함이며, 사용자에겐 PriType 자체 `가`/`A` 표시가 실질 지표다.

### 2.2 상태 소유권

| 상태 | 소유자 | 비고 |
| --- | --- | --- |
| 한/영 진리 | `HangulComposer.inputMode` | 단일 source of truth |
| 전환 정책(Caps Lock·fallback) | `InputModeCoordinator` | 한 곳에서만 판단 |
| IMK 세션 edge(commit·override·layout) | `PriTypeInputController` | imperative 경계 |
| 실제 TIS source 선택 | **macOS만** | Caps Lock 경로 한정 |
| 사용자 표시(가/A) | `StatusBarManager` | |
| TIS 조회·stale 정리 | `InputSourceManager` | hot path 제외 |

---

## 3. 불변식 (회귀 가드)

1. custom toggle hot path에서 `TISSelectInputSource`를 호출하지 않는다.
2. `composer.inputMode`를 바꾸는 writer는 **정확히 둘**뿐이다:
   - `PriTypeInputController.performPriTypeModeTransition` (사용자 토글)
   - `PriTypeInputController.setValue(_:forTag:)` ingress (macOS가 PriType source 재선택 → 항상 `.korean` 복귀)
   `activateServer`(포커스 변경) 등 다른 경로는 모드를 건드리지 않는다.
3. 모드 전환 전 active composition은 정확히 1회 commit한다.
4. 전환 직후 keyDown을 막거나 replay하지 않는다. 전환이 즉시 완료되므로 불필요하다.
5. 영어 모드에서 PriType는 printable key를 consume하지 않는다(`return false`).
6. 일반 typing hot path에 TIS/AX 조회·UserDefaults JSON decode·로그 문자열 생성이 없다.
7. Caps Lock on이면 custom toggle을 비활성화한다. 둘이 같은 키 이벤트에서 동시 동작하지 않는다.

---

## 4. 적용된 정제 (2026-06-01)

이 결합안을 정식화하면서 구현에 반영한 4가지.

### ① 단일 소스 유지
`Info.plist`의 단일 모드 등록을 정식 구조로 고정. RollbackPlan의 2-가짜-모드 안은 폐기(§2.1).

### ② 영어 모드 = 순수 pass-through
[HangulComposer.handle()](../Sources/PriTypeCore/HangulComposer.swift)의 영어 분기는 조합 정리 후
`return false`만 수행한다. `localTextBuffer`와 `TextConvenienceHandler.handleEnglishModeInput`을
영어 hot path에서 제거했다(후자는 dead code로 삭제). 영어의 더블스페이스 마침표 등 텍스트 편의는
macOS가 소유한다(2.7 결정과 일치). 이로써 "PriType 영어 버퍼 ↔ 실제 커서" desync 버그 표면이 사라진다.

- 한글 모드의 더블스페이스 마침표는 기존대로 `NSAutomaticPeriodSubstitutionEnabled` 연동 정책을 유지한다.
- 검증 의존: pass-through 키에 host가 더블스페이스 치환을 적용하는지는 실기기 확인 항목(§6).
  만약 미동작이고 영어 더블스페이스가 꼭 필요하면, 그 한 기능만을 위한 최소 버퍼를 영어 분기에 재도입한다.

### ③ custom toggle 경로 단일화 (전환 정책을 coordinator로)
2.6.5는 `onToggle`이 `sharedComposer.toggleInputMode()`를 **직접** 호출했다. 현재 구조는
`RightCommandSuppressor/IOKit → InputModeCoordinator → PriTypeInputController → composer`로 일원화해,
Caps Lock 정책·active controller 가드·전환 전 1회 commit을 한 곳(coordinator/controller)에서 보장한다.

토글 콜백은 [RightCommandSuppressor.triggerToggle](../Sources/PriTypeCore/RightCommandSuppressor.swift)에서
`DispatchQueue.main.async`로 메인 런루프에 올린다. 이는 **검증된 2.6.5 기준선과 동일**하다.

> 설계 노트: "전환 직후 첫 글자 씹힘"의 구조적 원인은 async hop이 아니라 2.7.2의 *비동기 TIS source 선택*이었다.
> 현재 구조는 실제 ABC source를 선택하지 않고 `HangulComposer.inputMode`(메인 스레드 단일 상태)만 뒤집으므로
> race가 사라진다. 한때 토글을 탭 콜백 안에서 동기 실행하는 안을 검토했으나, 2.6.5/2.7.2 어디에도 없던 신규
> 동작(탭 콜백 내 IMK IPC)이라 `kCGEventTapDisabledByTimeout` 위험만 추가하고 이득이 불확실해 채택하지 않았다.

### ④ inputMode write-path 단일화
불변식 2를 코드 주석으로 명문화(`setInputMode`, `activateServer`). 외부 선택(Caps Lock)에서 PriType로
돌아오면 `setValue` ingress가 항상 `.korean`으로 복귀시킨다 — 영어는 "ABC"이지 "PriType-영어"가 아니므로.

---

## 5. 전환 트랜잭션 (원자 순서)

```
Tap/IOKit  ──requestToggle(source)──►  InputModeCoordinator
   InputModeCoordinator: Caps Lock 소유면 거부, active controller 없으면 거부
   InputModeCoordinator ──performModeTransition──►  PriTypeInputController
      Controller: commit active composition (1회)
      Controller: overrideKeyboardWithKeyboardNamed(ABC/US)
      Controller: composer.setInputMode(next)   ← 단일 진리 갱신
```

실패 처리:

- active controller가 없으면 composer mode만 단독으로 바꾸지 않는다(다음 activate에서 stale state로 첫 글자 엉킴 방지).
- `lastClient`/`lastKnownInputClient`가 모두 없으면 no-op.
- Caps Lock 소유 상태면 custom toggle은 진입 자체가 거부된다.

---

## 6. 회귀 검증

빌드/유닛:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c debug --product PriType
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run -c debug PriTypeVerify
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product PriType
```

실기기 시나리오(대상 앱: TextEdit · Safari/Chrome · Electron(ChatGPT) · KakaoTalk · Finder · Terminal/iTerm · GoodNotes):

- 한↔영 빠른 연타 중 입력 — 한글 모드에 영어가 섞여 나오는 사례 0
- 전환키와 다음 문자 거의 동시 입력 — 첫 keydown 씹힘 0 (정제 ③)
- 한글 조합 중 전환 — 전환 전 1회 commit
- 한글 조합 중 앱 포커스 이동 — 앱 비활성 시 조합을 강제 commit(host-무관 멱등 안전망). 정상 호스트는 IMK `deactivateServer`로, 그렇지 않은 호스트(과거 KakaoTalk 사례)는 `NSWorkspace` 비활성 알림으로 처리
- Backspace 길게 — release build 체감 딜레이 없음
- Return/Enter 1회 — GoodNotes 중복 줄바꿈 없음
- Hanja 후보창 호출 및 좌표 — Chromium fallback 포함
- 영어 모드 더블스페이스 — host(macOS)가 처리하는지 확인 (정제 ② 검증 의존)
- Caps Lock 전환 on — custom toggle 비활성, macOS만 ABC↔PriType 전환

---

## 7. 보존 확정 (이미 검증된 개선)

- 최신 설정창 UI/UX (Liquid Glass)
- Caps Lock은 macOS 입력 소스 설정이 소유한다는 정책
- GoodNotes Return 중복/누락 보정
- 앱 비활성 시 조합 강제 commit — host-무관 멱등 안전망(과거 KakaoTalk 하드코딩을 일반화: `PriTypeInputController`의 `NSWorkspace` 비활성 옵저버 + `forceCommitForApplicationDeactivate`)
- 설치/시작 시 PriType 자신을 `TISEnableInputSource` 하지 않는 보수화
