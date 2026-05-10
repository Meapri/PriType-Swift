# Changelog

All notable changes to PriType-Swift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- 비밀번호/보안 입력 필드에서 불필요한 조합 입력으로 경고음이 발생할 수 있는 경로를 보강했습니다.
- Wine/게임 환경 감지와 입력 경로를 강화해 일부 게임 런타임에서 한글 조합이 깨지는 위험을 줄였습니다.
- 한자 후보창 위치 계산에서 Chromium 계열 앱과 Accessibility fallback 경로를 더 안정적으로 처리했습니다.
- SwiftPM 테스트/검증 환경에서 `hanja.txt`와 localization 리소스를 못 찾아 한자 사전 로딩 경고가 반복되던 문제를 수정했습니다.
- 오래된 실험용 `sim*.swift` 파일을 제거하고 재추적되지 않도록 정리했습니다.

### 검증
- Swift 테스트 118개 통과
- SwiftLint strict 0건
- PriTypeVerify 통과
- PriTypeBenchmark 통과
- 릴리즈 PKG 서명, Apple 공증, 스테이플, Gatekeeper 검증 통과

### Added
- Localization support with L10n.swift for type-safe string access
- Korean (ko) and English (en) Localizable.strings
- Multi-monitor Finder heuristic tests
- SwiftLint configuration (.swiftlint.yml)
- Extended KeyCode constants with helper methods

### Changed
- InputSourceManager refactored to TIS API only (removed shell commands)
- HangulComposer separated TextConvenience logic to dedicated handler
- Adapter classes refactored with BaseClientAdapter inheritance
- Finder detection improved with validAttributesForMarkedText

### Fixed
- Cmd/Ctrl/Option+Arrow and Fn+Arrow (Home/End/PageUp/PageDown) shortcuts now work correctly during Hangul composition. The in-progress preedit is committed and marked text is cleared before the event is passed to the host application, preventing the shortcut from being ignored or misapplied.

### Security
- Removed all shell command execution (PlistBuddy, killall cfprefsd)
- Added -strict-concurrency=complete Swift flag

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
