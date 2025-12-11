# Getting Started with PriTypeCore

PriTypeCore를 사용하여 한글 입력을 처리하는 방법을 알아봅니다.

## Overview

PriTypeCore는 InputMethodKit 기반 입력기의 핵심 로직을 제공합니다. 
``HangulComposer``가 모든 키 이벤트를 처리하고, ``HangulComposerDelegate``를 통해 결과를 전달합니다.

## Basic Usage

### Step 1: Composer 생성

```swift
let composer = HangulComposer()
```

### Step 2: Delegate 구현

```swift
class MyDelegate: HangulComposerDelegate {
    func insertText(_ text: String) {
        // 확정된 텍스트 삽입
        textView.insertText(text)
    }
    
    func setMarkedText(_ text: String) {
        // 조합 중인 텍스트 표시
        textView.setMarkedText(text, selectedRange: NSRange())
    }
    
    func textBeforeCursor(length: Int) -> String? {
        // 커서 앞 텍스트 반환 (자동 마침표 등에 사용)
        return nil
    }
    
    func replaceTextBeforeCursor(length: Int, with text: String) {
        // 커서 앞 텍스트 교체
    }
}
```

### Step 3: 이벤트 처리

```swift
func handle(_ event: NSEvent) -> Bool {
    return composer.handle(event, delegate: myDelegate)
}
```

## Mode Switching

한영 전환은 ``HangulComposer/toggleInputMode()`` 메서드로 수행합니다:

```swift
composer.toggleInputMode()  // 가 ↔ A
```

## See Also

- ``HangulComposer``
- ``HangulComposerDelegate``
- ``InputMode``
