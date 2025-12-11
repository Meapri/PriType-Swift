# ``PriTypeCore``

macOS용 한글 입력기 핵심 라이브러리

## Overview

PriTypeCore는 libhangul 기반의 현대적인 macOS 한글 입력기 엔진입니다. InputMethodKit(IMK)과 통합되어 모든 macOS 앱에서 한글 입력을 지원합니다.

### 주요 기능

- **한글 조합**: libhangul 기반 정확한 조합 처리
- **모드 전환**: 우측 Command 또는 Control+Space로 즉시 전환
- **Finder 지원**: 데스크톱 환경에서도 안정적인 입력
- **보안**: 릴리즈 빌드에서 로깅 완전 제거

## Topics

### 핵심 컴포넌트

- ``HangulComposer``
- ``HangulComposerDelegate``
- ``InputMode``

### 키 이벤트 처리

- ``RightCommandSuppressor``
- ``IOKitManager``
- ``KeyCode``

### 사용자 설정

- ``ConfigurationManager``
- ``ToggleKey``
- ``SettingsWindowController``

### 유틸리티

- ``CompositionHelpers``
- ``JamoMapper``
- ``TextConvenienceHandler``
- ``DebugLogger``

### 시스템 통합

- ``StatusBarManager``
- ``InputSourceManager``
- ``PriTypeInputController``
