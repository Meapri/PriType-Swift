# 한글-윈도우 입력 방식의 macOS 안정 구현 타당성 분석 및 구현 플랜

> 작성: 멀티에이전트 리서치 워크플로우 (`korean-windows-input-feasibility`) 종합
> 대상 브랜치: `experiment/dual-mode-capslock` (HEAD `6832226`, build 50)
> 판정: **feasible-with-caveats** · 신뢰도 **0.86**

---

## 0. 한 줄 결론

**"윈도우 한글 입력 느낌"은 macOS에서 안정적으로 구현 가능하다. 단, 그 정답은
`direct insertion`(매 키마다 글자를 실제 텍스트로 지우고 다시 삽입)이 아니라,
PriType가 *이미* 쓰고 있는 "마크드 텍스트 + 음절 단위 즉시 커밋" 모델을 정밀하게
다듬는 것이다.** 직접삽입은 한 번뿐인 포커스-상실 깜빡임을 *상시* 매-키 깜빡임으로
바꾸고, 흔한 앱(Chrome/VS Code/터미널/보안필드/카톡)에서 데이터 손상 또는 무동작이
되므로 기본 경로로는 **비권장**이다.

---

## 1. "한글 윈도우 방식"이 실제로 무엇인가

윈도우 한글 IME(MS-IME 두벌식)가 "깨끗하게" 느껴지는 진짜 이유는 *직접삽입*이 아니다:

1. **조합 중인 단 하나의 음절**만 transient composition region(IMM32/TSF composition
   string)에 둔다. 이건 디스플레이 전용이며 문서 스토리지를 건드리지 않는다 — 그래서
   `ㄱ→가→각`으로 자모가 바뀌어도 조합 *중* 깜빡임이 없다.
2. **다음 음절이 시작되는 순간**, 직전 음절을 완성형(NFC)으로 atomic하게 확정(commit)해
   실제 텍스트로 흘려보낸다. 그래서 "마크드 텍스트가 길게 끌리는" 느낌이 없다.
3. 포커스 상실/스페이스/엔터 시에도 같은 commit이 일어난다.

이 모델은 macOS의 **마크드 텍스트(setMarkedText) + 음절 단위 insertText 커밋**과 1:1로
대응된다. (Firefox/Gecko가 Windows IMM/TSF와 macOS NSTextInput을 *하나의* composition
모델로 통합한 것이 그 증거다.) 즉 윈도우의 깔끔함은 별도의 마법이 아니라 "조합창은 항상
≤1음절, 완성되면 즉시 확정"이라는 *정책*에서 나온다.

### PriType는 이미 이걸 한다

`HangulComposer.updateComposition` (`HangulComposer.swift:455-473`):

```swift
private func updateComposition(delegate: HangulComposerDelegate) {
    let preedit = context.getPreeditString()
    let commit  = context.getCommitString()

    // (A) 확정 문자열 먼저 — libhangul이 음절 경계에서 직전 음절을 내보냄
    if !commit.isEmpty {
        let finalStr = CompositionHelpers.convertAndNormalize(commit)   // NFC 완성형
        delegate.insertText(finalStr)
        appendToBuffer(finalStr)
    }
    // (B) 그 다음, 살아있는 음절만 마크드 텍스트로
    if !preedit.isEmpty {
        delegate.setMarkedText(CompositionHelpers.normalizeJamoForDisplay(preedit))
    } else {
        delegate.setMarkedText("")
    }
}
```

→ 이 **commit-before-mark 순서**가 핵심이며, 그 덕에 마크드 윈도우는 본질적으로 ≤1음절,
포커스 상실 시 stranded될 수 있는 양도 1음절뿐이다. `finalizeComposition`
(`PriTypeInputController.swift:195-210`)이 그 1음절을 canonical `NSNotFound`로 1-op
커밋하는 것이 build 50의 포커스-상실 처리다.

---

## 2. 왜 direct insertion이 정답이 아닌가 (결정적 근거)

### (가) 깜빡임을 *줄이는 게 아니라 늘린다*
Apple Cocoa Text Architecture 문서: 마크드 텍스트는 **"display에만 영향, layout/storage
불변"**. 즉 `ㄱ→가→각` 변화가 `NSTextStorage`를 안 건드린다. 반면 `insertText`는 호출마다
스토리지 변경 + 레이아웃 강제 + `NSTextDidChange` + undo 엔트리를 만든다.
"이전 음절 지우고 새로 삽입"을 **매 키마다** 하는 direct insertion은 마크드 텍스트보다
구조적으로 더 많은 redraw를 일으킨다. → 한 번의 blur 깜빡임을 없애려고 *상시* 깜빡임을
들여오는 셈. **순손해.**

### (나) 많은 앱에서 아예 안 되거나 데이터를 깬다
- `IMKTextInput`에는 `deleteBackward`/atomic delete 프리미티브가 **없다**. 이전 preedit을
  지우는 유일한 길은 `insertText(_:replacementRange:)`.
- 그런데 **클라이언트가 legacy Carbon `TSMDocumentAccess`를 지원하지 않으면
  `replacementRange`는 조용히 무시**된다(Apple IMK 헤더). 그러면 delete+reinsert가 단순
  append로 붕괴 → `ㄱ가각간…` 누적 쓰레기.
- `selectedRange()`가 `NSNotFound`(터미널/Spotlight/보안필드) 또는 garbage(Chromium,
  코드가 이미 `< 10_000_000`으로 막는 그것)면 지울 범위 자체를 계산 못 한다. 잘못 센 delete는
  음절 옆의 *확정된 문서 텍스트*를 먹는다 — 마크드 텍스트엔 없는 **실제 데이터 손실**.

### (다) undo 오염 + 음절 중간 autocorrect
`replacementRange`가 다른 commit-then-replace가 강제되면(Firefox bug 875674) 매 키가
개별 undo 가능 + autocorrect 대상 편집이 된다 — 마크드 텍스트가 *억제하려고 존재하는* 바로
그것. Notes/Mail/Word에서 눈에 보이는 품질 저하.

### (라) 선례
유일한 실질 direct-insertion 성공작 OpenKey(베트남어)조차 IMK를 안 쓰고
`CGEventTap + synthesized backspace`로 동작하며, 그럼에도 Chrome/Brave/Apple/Sublime용
per-app 하드코딩 목록을 들고 다닌다. 출하 중인 한국어 macOS IME(Apple, 구름) 중 마크드
텍스트를 버린 것은 **없다**. Rime/Squirrel조차 마크드 세계에서 per-bundle 예외표를 유지한다.

---

## 3. 구현 플랜 (단계별)

### Phase 0 — 베이스라인 잠금 & NFC/순서 감사 (동작 변경 없음) · 위험: 없음
- `git tag pre-direct-insertion-experiment` (HEAD `6832226`) — 안전 복귀점.
- `updateComposition`의 commit-before-mark 순서(:460-464 → :467-469)를 코드 주석으로 *고정*.
  (이 순서가 깨지면 kitty #4219류 stale-cursor preedit 재발.)
- `convertAndNormalize`(확정=NFC 완성형) / `normalizeJamoForDisplay`(조합 중) 경로에 NFD가
  새지 않는지 확인 — macOS vs Windows 자소분리 축.
- `finalizeComposition`이 ≤1음절 canonical `NSNotFound` 1-op 커밋임을 "측정상 양호" 상태로 확정
  (카톡 이모티콘-깜빡임 테스트의 기준선).

### Phase 1 — 기존 하이브리드 강화 ("윈도우 느낌"의 실질 이득) · 위험: 낮음
- commit-before-mark 불변식을 **테스트로 고정**: `ㄱ가각가`(받침 이동 `각+ㅏ→가` 확정,
  `가`가 새 마크드) 시 *완성 음절당 insertText 1회 → 그 다음 setMarkedText* 순서를 단언.
- 하드 경계에서 preedit을 지우는 모든 지점이 **살아있는 음절을 먼저 커밋**(strand 금지)하는지
  보장: `commitComposition`(:482), `forceCommit`(:514),
  `commitActiveCompositionBeforeModeTransition`(`PriTypeInputController.swift:273`),
  `handleSpecialKey`의 Return/Space/Tab/Arrow(:194-249). 이후 `context.isEmpty()==true` &
  마크드 클리어를 단언.
- `ImmediateModeAdapter`(Finder; `PriTypeInputController.swift:127`)는 **그대로 둔다** —
  deferred-batch가 데스크톱의 올바른 동작(floating preedit 회피 이유).
- NFC 정규화 end-to-end 확인 → 확정 한글은 항상 완성형(윈도우-클린), 클립보드/호스트 불일치
  자소분리 제거.

### Phase 2 — TSMDocumentAccess 런타임 프로브 + per-host 정책 (게이트만, 새 모델 없음) · 위험: 낮음
- `activateServer`에서 안전 프로브: `client.selectedRange()` 읽어 `location==NSNotFound`
  또는 `location>=10_000_000`이면 "document access unsafe"로 판정, `ClientContext`에 캐시
  (키 입력 핫패스에서 프로브 금지).
- (보조) `client.supportsProperty(kTSMDocumentSupportDocumentAccessPropertyTag)`는 advisory,
  권위 게이트는 위 range-sanity 프로브(Chromium은 그럴듯하지만 틀린 값 반환).
- `ClientCompatibilityPolicy.directInsertionAllowed(bundleId:)` 추가, **기본 false**
  (`needsDirectNewlineAfterReturnCommit`(`ClientContextDetector.swift:104`) 미러링).
  하드-deny: Chromium/Electron, 터미널, 카톡, Office, 보안 클라이언트.
- `ClientContext`에 파생 `inputDeliveryMode`(`markedText | immediate | directInsertion`)
  추가 → `makeAdapter`(`PriTypeInputController.swift:137`)가 정책+프로브로 분기. 기본은 여전히
  `ClientAdapter`(마크드 텍스트).

### Phase 3 — 실험적 `DirectInsertionAdapter` (피처 플래그 뒤, opt-in 전용) · 위험: 높음
- `ConfigurationManager.experimentalDirectInsertion` 플래그(**기본 OFF**). ON일 때만
  `makeAdapter`가 프로브 통과 + 화이트리스트된 네이티브 AppKit 번들에 한해 directInsertion 고려.
- `DirectInsertionAdapter`(`BaseClientAdapter` 서브클래스): `setMarkedText`는 no-op, preedit
  경로를 `replaceTextBeforeCursor`(`BaseClientAdapter.swift:97`)로 추적된
  `insertedPreeditLength` 위에 덮어쓰기. `HangulComposer`에 `insertedPreeditLength` 추가,
  commit/cancel/flush/reset/setInputMode/updateKeyboardLayout에서 리셋.
- **치명 가드**: `replaceTextBeforeCursor`가 (음절 중간 `selectedRange` 무효로) 실패하면
  반-자모를 strand하지 말고 **남은 조합을 마크드 텍스트로 폴백**.
- `commitComposition`/`forceCommit`/`finalizeComposition`을 direct-insertion-aware로:
  살아있는 음절은 이미 문서에 있으므로 하드 커밋은 `insertedPreeditLength` 0으로 + libhangul
  reset만 — **재삽입 금지**(Win11 TSF 중복문자 클래스 버그 회피).
- backspace(:252)/Esc-cancel(:502)도 direct 모드에선 이미 삽입된 preedit을 실제 삭제.
- 출하 빌드에선 매트릭스 통과 전까지 플래그 OFF 유지 — 이건 *연구 차량*이지 기본값이 아니다.

### Phase 4 — 결정 게이트 · 위험: 없음
- 네이티브-AppKit 화이트리스트에 대해 플래그 ON으로 전체 매트릭스 실행. Phase 1 하드닝
  하이브리드 기준선과 undo 입도/autocorrect 간섭/깜빡임/자소분리 비교.
- **예상 결과**: direct insertion이 안전 호스트에서도 이득이 미미하고 undo/autocorrect를
  퇴행시킨다 → **플래그 영구 OFF**, Phase 1+2만 출하, direct insertion은 "평가 후 기각"으로 문서화.
- 특정 호스트가 명백히 이득이고 매트릭스 전 행 통과 시에만 좁은 per-bundle opt-in 유지(전역 기본 금지).

---

## 4. 테스트 매트릭스

| 클라이언트 | 시나리오 | 기대 |
|---|---|---|
| **KakaoTalk** | 받침 음절 살아있는 채로 앱 전환(포커스 상실), 이모티콘 추천 팝업 관찰 | 하이브리드: `finalizeComposition` 1-op로 1음절 확정, **이모티콘 팝업 깜빡임 없음/stranded 밑줄 없음**. direct는 카톡 **강제 OFF**(lifecycle range 불안정). 주 회귀 가드. |
| **Chrome/VS Code/Slack** | `한글날` 빠르게 + 음절 중간 blur | 하이브리드: 마크드 렌더 + 음절 커밋 정확, run-on 쓰레기/strand 없음. direct는 `selectedRange` garbage(≥10M)로 **deny→마크드 폴백**. |
| **Terminal/iTerm2** | 셸 프롬프트 한글 + 음절 내 backspace | `selectedRange==NSNotFound`→direct deny. 마크드/음절-커밋 경로, blind-append/셸 텍스트 삭제 없음. |
| **Notes/TextEdit**(네이티브 NSTextView) | 문장 입력 후 Cmd-Z 반복, autocorrect/smart-sub | 하이브리드(기본): undo가 단어/조합 단위 coalesce, 조합 중 autocorrect 억제, 매-키 깜빡임 없음. direct ON은 여기서만 "동작"하나 undo가 음절당 1회로 퇴행 + 음절 중간 autocorrect 발화 → 플래그 OFF 유지 근거. |
| **보안 필드**(login/sudo/1Password) | 패스워드 필드 한글 시도 | `SecureInputPolicy.shouldPassThrough`→raw passthrough, insertText/setMarkedText 미시도, 포커스 wedge 없음. direct 시도 안 함(전역 `IsSecureEventInputEnabled` 게이트). |
| **Notes/KakaoTalk**(빠른 받침 이동) | `각+ㅏ→가` 확정+`가` 새 블록, 레이아웃보다 빠르게 타건 | 하이브리드: commit-before-mark 유지, 이동 음절당 insertText 정확히 1회→setMarkedText, stale-cursor preedit(kitty #4219)/자모 누락·중복 없음. direct는 stale `selectedRange` read-modify-write로 race 위험 高. |
| **Finder**(immediate 모드) | 데스크톱/아이콘 이름변경 한글 | `ImmediateModeAdapter` 불변: deferred-batch, floating preedit 없음. direct로 전환하지 않음. |
| **Spotlight/Raycast/Alfred** | 한글 쿼리 | 터미널처럼 TSMDocumentAccess 없음→direct deny. 마크드/즉시-커밋, 결과 갱신 시 조합 안 끊김. |

---

## 5. 리스크 요약

1. **(결정적)** 매-키 direct insertion = blur 1회 깜빡임을 *상시* `NSTextStorage` 변경+relayout
   +`NSTextDidChange` churn으로 교체 → 마크드 텍스트보다 redraw가 **더 많다**. 깜빡임 *개선이
   아니라 퇴행*.
2. `replacementRange`는 TSMDocumentAccess 없는 클라이언트에서 무시 → direct가 blind append로
   붕괴 → run-on 자모 쓰레기.
3. `selectedRange()` NSNotFound/garbage → delete 범위 계산 불가 → 인접 확정 텍스트 삭제(데이터 손실).
4. undo 오염 + 음절 중간 autocorrect (Notes/Mail/Word 품질 퇴행).
5. 이중 삽입 / Win11-TSF-류 중복문자 버그(하드 커밋이 이미 있는 음절 재삽입 시).
6. 카톡은 마크드 텍스트에서도 다수 타겟 수정이 필요했다(commit-to-sender, NSWorkspace
   deactivate net, 1-op finalize). direct는 lifecycle edge의 stranded 위험을 재도입 → 하드-deny 필수.
7. 번들-ID 화이트리스트는 썩는다(새 Electron 래퍼 상시 출시) → 런타임 NSNotFound/garbage 프로브가
   안전 바닥. 미지 클라이언트는 마크드 텍스트로 fail-safe.
8. 하드닝 하이브리드도 포커스-상실 처리를 *없애지는 못한다*: 1음절은 여전히 예기치 못한 blur에서
   strand 가능 → `finalizeComposition`/deactivate flush 유지, commit-before-mark 순서 보존 필수.

---

## 6. 롤백 전략

- 브랜치 `experiment/dual-mode-capslock`, HEAD `6832226` = canonical 마크드 텍스트 + 1-op
  finalize = 안전 베이스라인(전달 의미상 build 50 동등). 변경 전 `pre-direct-insertion-experiment`
  태깅.
- Phase 1-2는 additive/저위험 → 출하 안전.
- Phase 3(`DirectInsertionAdapter`)는 전부 `ConfigurationManager.experimentalDirectInsertion`
  (기본 OFF)+화이트리스트+프로브 게이트 뒤 → 기본 빌드는 실행조차 안 함. 플래그 끄면 코드 revert
  없이 완전 복귀.
- Phase 1-2가 카톡 이모티콘-깜빡임/Chrome strand 테스트를 퇴행시키면
  `git reset --hard pre-direct-insertion-experiment`.
- **2.7.3 explicit-marked-range commit 패턴 부활 금지**(commit `60be6c7` 카톡 stranding 근본
  원인). 기본 경로의 canonical `NSNotFound`는 비협상.

---

## 7. 권고

- **지금 할 것**: Phase 0 → 1 → 2 (저위험, 실질 "윈도우 느낌" 이득, 회귀 가드 강화).
- **direct insertion**: Phase 3 플래그로 *연구용*만. 사용자가 직접 체감/판단하고 싶을 때 켜서
  네이티브 AppKit(Notes 등)에서만 테스트. 매트릭스 통과 못 하면 영구 OFF(예상 결과).
- **포커스-상실 깜빡임의 진실**: 마크드 텍스트로 확정하는 한 완전 제거는 불가하며(이전 리서치에서
  입증: `unmarkText`는 앱측, IME 호출 불가; 구름도 동일; Apple은 호스트 특별취급), direct insertion은
  이를 더 악화시킨다. PriType는 이미 그 깜빡임을 ≤1음절로 최소화한 상태(build 50)다.

---

## 8. 구현 결과 (Phase 0–3 완료)

`pre-direct-insertion-experiment` 태그를 베이스라인으로, Phase 0–3을 모두 구현했다.

**채택한 구조 — Approach B(어댑터 격리, 합성안 대비 개선):**
합성안은 `insertedPreeditLength`를 `HangulComposer`에 두자고 제안했으나, 실제로는 모든
direct-insertion 상태를 **`DirectInsertionAdapter`** 한 곳에 격리했다. `HangulComposer`는 로직
무변경(주석만 추가) — 여전히 `insertText`(확정)→`setMarkedText`(조합) 순서로 호출하고, 어댑터가
이를 *제자리 실제텍스트 재기록*으로 재해석한다. 핵심 수학은 순수 함수 **`DirectInsertionPlanner`**
로 분리해 IMKTextInput 없이 단위 테스트한다. 이점: 롤백 = 플래그 OFF면 코드상 완전 비활성,
회귀 표면 최소.

**게이트:** `ConfigurationManager.experimentalDirectInsertion`(기본 OFF, Settings 토글) +
`ClientContext.documentAccessSafe`(activation 시 `selectedRange` 프로브; 플래그 OFF면 IPC 0) +
`!ClientCompatibilityPolicy.directInsertionDenied`(Electron/Chromium/브라우저 denylist + 키워드
휴리스틱).

처음엔 native 허용목록 → 사용자 요청으로 허용목록 제거(모든 앱 시도) → **온디바이스 로그 분석 후
Electron/Chromium denylist 도입.** 이유: Claude Desktop 등 Electron 앱에서 `selectedRange`/
`attributedSubstring`이 비동기·부정확이라 캐럿 안정성 read-back이 매 키마다 오발동해 조합이 깨졌다
(로그의 `abandoning stale preedit tracking` 폭주로 확인). 이는 정책이 아니라 **물리적 한계**(§2 예측
적중) — 그래서 web/Electron은 마크드로 자동 폴백(거기선 깜빡임 이슈도 없음), direct insertion은
모든 **네이티브** 앱(KakaoTalk·메모 등)에서 동작한다.

### 8.1 온디바이스 로그로 잡은 추가 버그 2건
- **조합 글자가 한 번에 지워짐 (KakaoTalk):** 일부 호스트가 동일 물리 keyDown을 **2회 전달** →
  백스페이스 1번에 `context.backspace()` 2회 → 자모 2개 삭제. → `KeyEventDedup`(동일 keyCode·
  비-repeat·50ms 이내 재전달을 중복으로 판정)으로 제거. **direct 모드 한정** 적용(마크드/출하 경로
  무영향). auto-repeat(`isARepeat=true`)·빠른 타이핑(다른 keyCode)·사람 더블탭(>50ms)은 안전.
- **Electron 조합 깨짐:** 위 denylist로 해결.

**적대적 멀티에이전트 리뷰에서 잡아 고친 버그 5건(모두 direct-insertion 특유의 커서 손상 계열):**
1. *(critical)* `commitComposition(_:)`(마우스 클릭 커밋)이 direct-aware가 아니라 살아있는 음절을
   **재삽입** → 중복/덮어쓰기 손상. → finalize와 동일하게 재삽입 없이 엔진만 flush하도록 수정.
2. *(high)* direct 모드엔 marked text가 없어 내부 클릭 시 IMK가 commit을 안 쏨 → 다음 타건이 새
   커서 위치의 무관 텍스트를 삭제. → **캐럿 안정성 가드** 도입.
3. *(high)* 플래너가 커서가 라이브 영역을 *앞질러* 이동한 경우를 못 잡음 → 동일 가드로 차단.
4. *(medium)* `discardCompositionForPassThrough`(보안 필드 전환)가 어댑터 추적을 안 지움 → 다음
   타건이 실제텍스트 삭제. → 호출부에서 `resetPreeditTracking()`.
5. *(medium)* `fellBackToMarked`가 영구 sticky → 일시적 나쁜 selectedRange가 세션 전체를 마크드로
   강등. → `resetPreeditTracking()`에서 재무장.

**캐럿 안정성 가드(2·3의 근본 수정):** 라이브 음절을 지우기 전에
`client.attributedSubstring`으로 **`[caret-len, len]`이 우리가 쓴 preedit과 실제로 일치하는지
읽어 검증**하고, 불일치(클릭/화살표로 커서 이동, 읽기 실패)면 추적을 버리고 현재 커서에 새로
삽입한다 — **검증 못 한 텍스트는 절대 삭제하지 않는다.** false-positive는 조합 연속성만 끊을 뿐
손상은 없다(안전한 실패).

**테스트:** `DirectInsertionTests.swift` — 플래너 수학, 허용목록, commit-before-mark 순서, 안정성
가드, 통합(가짜 클라이언트로 받침 이동/스페이스 중복 없음·Escape 삭제·백스페이스 분해). 전체 146 통과.

**남은 한계(설계상 불가피, 변하지 않음):** 가드는 *손상*을 막을 뿐, direct insertion이 매-키
재기록으로 마크드보다 redraw가 많고(§2-가) undo/autocorrect를 퇴행시키는 점은 그대로다. 따라서
이 경로는 **연구용(기본 OFF)**이며, Phase 4 결정 게이트의 예상 결론은 여전히 "기본 OFF 유지,
하드닝 하이브리드가 기본"이다.
