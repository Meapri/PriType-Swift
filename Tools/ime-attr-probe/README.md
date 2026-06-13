# ime-attr-probe

IMK 전송 계층이 IME의 marked-text 속성을 실제로 앱에 어떻게 전달하는지 측정하는
NSTextInputClient 프로브. macOS 업데이트 후 `PreeditUnderline`(TextDelivery.swift)의
전송 계층 가정이 여전히 유효한지 재측정할 때 사용한다.

## 측정 결과 (macOS 26, 2026-06)

PriType이 보내는 **모든** 속성 페이로드 — `underlineStyle 0 + .clear`,
`single + alpha 1/255`, `NSMarkedClauseSegment` 1~9(전체 TSM hilite 카테고리),
속성 없는 문자열 — 13종 전부가 앱에는 동일한 `NSUnderline=2 + 액센트 블루`로
재생성되어 도착했다. 즉 macOS 26에서는 어떤 IME도 marked text 밑줄을 숨길 수 없고,
밑줄 없는 입력은 직접 삽입 모드(`com.pritype.experimentalDirectInsertion`)가 유일하다.

## 사용법

PriType 디버그 빌드는 `PreeditStyleExperiment` UserDefaults 키를 읽지 않는다
(실험 스위치는 측정 완료 후 제거됨). 재측정하려면 `PreeditUnderline.attributes`에
임시로 실험 분기를 되살리거나, 이 프로브의 variants 배열이 거치는
`CFPreferencesSetValue` 키를 IME가 읽도록 다시 연결할 것.

```sh
mkdir -p /tmp/probe/Probe.app/Contents/MacOS
swiftc -O main.swift -o /tmp/probe/Probe.app/Contents/MacOS/Probe
# Info.plist(CFBundleIdentifier 등 최소 키) 작성 후 ad-hoc 서명
codesign --force -s - /tmp/probe/Probe.app
/tmp/probe/Probe.app/Contents/MacOS/Probe   # `open`은 ad-hoc 앱을 거부할 수 있음(-10825)
```

창 안내에 따라 한글 키를 반복 입력하면 키 입력마다 실험값이 자동으로 넘어가고,
도착한 속성이 `/tmp/ime_attr_probe/probe2.log`와 창에 기록된다.

주의: 합성 키 연타로 자동화하지 말 것 — 같은 키 50ms 이내 비반복 재도착은
`KeyEventDedup`이 호스트 중복 전달로 간주해 버린다(사람 입력은 불가능한 간격).
