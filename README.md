# PriType

macOS용 한글 입력기. InputMethodKit 기반, Swift로 작성.

## 기능

- **한글 입력**: [libhangul-swift](https://github.com/Meapri/libhangul-swift) 엔진 사용. 두벌식/세벌식 지원.
- **한/영 전환**: 우측 Command, Control+Space
- **한자 변환**: 우측 Option 키로 한자 후보창 호출
- **편의 기능**: 스페이스 두 번으로 마침표 입력
- **Finder 대응**: 바탕화면/파일 이름 변경 시 입력 간섭 없음
- **보안**: Secure Input(암호 입력) 감지 시 자동 비활성화

## 설치

[Releases](https://github.com/Meapri/PriType-Swift/releases)에서 `PriTypeV2_Release.pkg` 다운로드 후 설치.

Apple 공증(Notarization) 완료되어 있어 Gatekeeper 경고 없이 설치 가능.

### 설치 후

1. `시스템 설정 > 키보드 > 입력 소스 편집`에서 PriType 추가
2. 최초 설치 시 로그아웃 1회 필요할 수 있음
3. 업데이트 시에는 PKG 설치만 하면 재시작 없이 적용

### 직접 빌드

```bash
./build_release.sh
```

## 구조

```
Sources/
├── PriType/              # 앱 진입점 (main.swift)
└── PriTypeCore/          # 핵심 로직
    ├── HangulComposer    # 한글 조합 엔진 래퍼
    ├── PriTypeInputController  # IMKInputController 구현
    ├── RightCommandSuppressor  # CGEventTap 기반 키 처리
    ├── HanjaCandidateWindow    # 한자 후보창
    └── ConfigurationManager    # 설정 관리
```

## 요구사항

- macOS 14.0+
- Xcode 15+ / Swift 5.9+

## 라이선스

MIT License
