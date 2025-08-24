# PriType 한글 입력기

macOS용 Swift 기반 한글 입력기 프로젝트입니다.

## 프로젝트 개요

PriType은 macOS Input Method Kit(IMK)를 기반으로 한 한글 입력기입니다. Swift 6의 Strict Concurrency를 준수하며, macOS 시스템에 완전히 통합됩니다.

## 개발 과정

### 1. 기본 프로젝트 설정 (완료)
- ✅ Xcode 프로젝트 생성
- ✅ Swift 6 설정
- ✅ Input Method Kit 연동

### 2. 입력기 구현 (진행 중)
- ✅ IMKInputController 상속
- ✅ 기본 입력 처리 로직
- ✅ 한글 입력 상태 관리
- ✅ HangulInputManager 연동

### 3. 시스템 통합 (진행 중)
- ✅ Info.plist 설정
- ✅ 입력기 아이콘 생성
- ✅ 코드 서명
- 🔄 **한국어 카테고리 등록** (진행 중)

### 4. 오픈소스 입력기 조사 (완료)
다음 오픈소스 프로젝트들을 조사하여 공통점과 해결 방법을 찾았습니다:

#### 조사한 프로젝트들:
- **SokIM**: 빠르고 가벼운 macOS 한글 입력기
- **Gureum**: 방대한 한국어 입력기 (두벌식, 세벌식 등 지원)
- **azooKey**: 일본어 입력기
- **OpenVanilla**: 다국어 입력기

#### 핵심 발견사항:
1. **TISIntendedLanguage = "ko"** - 한국어 카테고리에 표시되도록
2. **@objc(ClassName)** - Objective-C 런타임 호환성
3. **ComponentInputModeDict 구조** - 입력 모드 설정
4. **tsInputModeScriptKey = "smKorean"** - 한국어 스크립트 지정

## 빌드 및 설치

### 요구사항
- macOS 13.0+
- Xcode 15.0+
- Swift 6.0+

### 빌드 방법
```bash
# 클린 빌드
xcodebuild -scheme PriType-Swift -configuration Debug clean build

# 또는 Xcode에서 직접 빌드 (Command + B)
```

### 설치 방법
```bash
# 시스템에 설치
sudo cp -r build/Debug/PriType-Swift.app /Library/Input\ Methods/

# 시스템 재시작
sudo killall -HUP loginwindow
```

### 입력 소스 추가
시스템 설정 → 키보드 → 입력 소스 → 한국어 카테고리에서 "PriType 한글 입력기" 선택

## 프로젝트 구조

```
PriType-Swift/
├── PriType-Swift/
│   ├── Info.plist                    # 입력기 설정
│   ├── PriTypeInputController.swift  # 메인 컨트롤러
│   ├── PriTypeInputServer.swift      # 서버 관리
│   ├── HangulInputManager.swift      # 한글 입력 로직
│   ├── ContentView.swift            # SwiftUI 뷰
│   ├── Assets.xcassets/             # 아이콘 및 에셋
│   └── Resources/                   # 추가 리소스
├── PriType-SwiftTests/
├── PriType-SwiftUITests/
├── PriType-Swift.xcodeproj/
├── Package.resolved
└── README.md
```

## 주요 기술

- **Input Method Kit (IMK)**: macOS 입력기 프레임워크
- **Swift 6 Strict Concurrency**: 동시성 안전성 보장
- **SwiftUI**: 현대적인 UI 프레임워크
- **LibHangul**: 한글 입력 엔진

## 해결된 문제들

### 1. 입력기 등록 문제
- ✅ TISIntendedLanguage = "ko" 설정
- ✅ ComponentInputModeDict 구조 개선
- ✅ @objc 클래스 이름 지정

### 2. 빌드 문제
- ✅ Xcode Copy Bundle Resources 설정
- ✅ Info.plist와 아이콘 파일 포함

### 3. 코드 서명
- ✅ Apple Developer ID로 서명
- ✅ 권한 설정 (entitlements)

## 진행 상황

- [x] 기본 프로젝트 구조
- [x] 입력 컨트롤러 구현
- [x] 한글 입력 로직
- [x] 시스템 통합 설정
- [ ] **한국어 카테고리 등록** (진행 중)
- [ ] 사용자 인터페이스 개선
- [ ] 추가 입력 방식 지원

## 참고 자료

- [Input Method Kit Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/InputManager/InputManager.html)
- [SokIM](https://github.com/kiding/SokIM) - macOS 한글 입력기
- [Gureum](https://github.com/gureum/gureum) - 종합 한글 입력기

## 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다.
