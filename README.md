# PriType

<p align="center">
  <strong>macOS 기본 입력 흐름에 맞춘 빠른 한글 입력기</strong><br>
  한글은 PriType, 영어는 macOS ABC. 입력 소스 전환은 더 자연스럽게, 한글 조합은 더 가볍게.
</p>

<p align="center">
  <a href="https://github.com/Meapri/PriType-Swift/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Meapri/PriType-Swift?label=release"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-14.0%2B-111111">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-F05138">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

PriType은 Swift와 InputMethodKit으로 만든 macOS용 한글 입력기입니다. 한글 조합 엔진은 [libhangul-swift](https://github.com/Meapri/libhangul-swift)를 사용합니다.

## 특징

- **macOS다운 한/영 전환**
  PriType은 한글 입력을 담당하고, 영어는 macOS 기본 `ABC` 입력 소스를 사용합니다. Caps Lock 전환, 메뉴 막대 입력 소스 표시, 시스템 입력 소스 UI가 macOS 방식과 자연스럽게 맞물립니다.

- **빠른 한글 조합**
  두벌식 표준, 세벌식 390, 두벌식 옛한글, 세벌식 옛한글을 지원합니다.

- **한자와 자모 특수문자**
  한글 입력 중 한자키를 눌러 한자 후보를 고를 수 있습니다. 자음 입력 후 한자키를 누르면 `♥`, `★` 같은 자모 특수문자도 입력할 수 있습니다.

- **선택 가능한 전환키**
  macOS Caps Lock 입력 소스 전환을 쓰지 않는 경우, 우측 Command 등 원하는 키를 PriType 한/영 전환키로 지정할 수 있습니다. Caps Lock 전환이 켜져 있으면 PriType 전환키는 자동으로 비활성화됩니다.

- **macOS 설정 연동**
  스페이스 두 번으로 마침표 입력은 PriType 별도 설정이 아니라 macOS 텍스트 입력 설정을 따릅니다.

- **공증된 설치 패키지**
  릴리즈 PKG는 Developer ID 서명, Apple 공증, Gatekeeper 검증을 거쳐 배포합니다.

## 설치

1. [최신 릴리즈](https://github.com/Meapri/PriType-Swift/releases/latest)에서 `PriTypeV2_Release.pkg`를 다운로드합니다.
2. PKG를 실행해 설치합니다.
3. `시스템 설정 > 키보드 > 텍스트 입력 > 입력 소스`에서 `한글` PriType 입력 소스를 추가합니다.
4. 영어 입력은 macOS 기본 `ABC` 입력 소스를 함께 사용합니다.

PriType 앱 번들은 기본적으로 `/Library/Input Methods/PriTypeV2.app`에 설치됩니다.

## 한/영 전환 설정

### Caps Lock으로 전환

macOS 설정에서 `Caps Lock 키로 ABC 입력 소스 전환`을 켜면, Caps Lock으로 `ABC`와 PriType 한글 입력 소스를 전환할 수 있습니다.

이 모드에서는 PriType 설정의 별도 한/영 전환키가 비활성화됩니다. 전환 경로가 둘로 갈라지지 않도록 macOS 입력 소스 전환을 단일 기준으로 사용합니다.

### 우측 Command 등으로 전환

Caps Lock 입력 소스 전환을 쓰지 않는다면 PriType 설정에서 한/영 전환키를 지정할 수 있습니다. 기본값은 우측 Command입니다.

우측 Command 전환이 동작하지 않으면 `시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용`에서 PriType 권한을 확인한 뒤, 필요하면 권한을 껐다 켜고 Mac을 재시동해 주세요.

## 지원 기능

| 영역 | 내용 |
| --- | --- |
| 자판 배열 | 두벌식 표준, 세벌식 390, 두벌식 옛한글, 세벌식 옛한글 |
| 입력 소스 | PriType 한글 + macOS 기본 ABC |
| 전환 | macOS Caps Lock 입력 소스 전환 또는 PriType 사용자 지정 전환키 |
| 한자 | 한자 후보창, 자모 특수문자 입력 |
| 텍스트 편의 기능 | macOS 더블스페이스 마침표 설정 연동 |
| 업데이트 | GitHub Releases 기반 자동 업데이트 확인 |

## 요구사항

- macOS 14.0 Sonoma 이상
- Swift 6.2 이상

## 빌드

```bash
# 개발 빌드
swift build

# 릴리즈 PKG 생성, 서명, 공증, Gatekeeper 검증
./build_release.sh
```

## 문제 해결

- **입력 소스가 중복으로 보일 때**
  최신 버전 설치 후 로그아웃/로그인하거나 재시동해 macOS 입력 소스 캐시를 새로 고쳐 주세요.

- **Caps Lock 전환이 안 될 때**
  macOS 입력 소스 설정에서 Caps Lock 전환 옵션이 켜져 있는지 확인해 주세요. PriType 설정에서 Caps Lock을 직접 전환키로 지정하는 방식은 사용하지 않습니다.

- **우측 Command 전환이 안 될 때**
  손쉬운 사용 권한이 필요합니다. 권한을 부여한 뒤에도 동작하지 않으면 PriType을 재실행하거나 Mac을 재시동해 주세요.

## 문서

- [ARCHITECTURE.md](ARCHITECTURE.md): 내부 구조, 입력 처리 흐름, 주요 모듈
- [BENCHMARK.md](BENCHMARK.md): 성능 측정 결과
- [CHANGELOG.md](CHANGELOG.md): 버전별 변경 사항

## 라이선스

MIT License
