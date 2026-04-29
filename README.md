# PriType

macOS 환경을 위한 네이티브 한글 입력기입니다. InputMethodKit을 기반으로 하며, 순수 Swift로 구현되어 메모리 안정성과 응답 속도를 개선하는 데 중점을 두었습니다.

## 핵심 기능 및 기술 구조

### 1. 입력 지연 최소화 (Zero-IPC Caching)
입력 처리 시 발생하는 프로세스 간 통신(IPC) 오버헤드를 줄이기 위해, 입력창이 활성화되는 시점(`activateServer`)에 컨텍스트를 1회 분석 및 캐싱합니다. 이후 타이핑 중 발생하는 빈번한 `handle()` 호출은 캐싱된 데이터를 기반으로 동기적으로 처리되어 반응 속도를 유지합니다.

### 2. 컨텍스트 감지 (Context Detector)
단순 앱 ID 검사를 넘어 좌표 기반 휴리스틱을 사용합니다. 예를 들어 Finder의 바탕화면(`y < 50`)과 실제 텍스트 입력창을 구분합니다. 텍스트 입력이 필요 없는 영역에서는 키 이벤트를 가로채지 않고 시스템으로 통과시켜(Pass-through), 파일 검색이나 시스템 단축키 사용 시 간섭이 발생하지 않도록 설계되었습니다.

### 3. 스레드 및 메모리 안정성
Swift 6의 엄격한 동시성(Strict Concurrency) 모델을 준수합니다. 기존 입력기에서 `CGEventTap` 사용 시 발생할 수 있는 포인터 순환 참조(Retain Cycle) 및 메모리 누수 문제를 Swift의 수명 주기(Lifecycle) 관리를 통해 해결했습니다.

### 4. 보안 입력(Secure Input) 처리
비밀번호 입력창이나 시스템 인증 창 등에서 Secure Input이 활성화된 경우, 키 이벤트를 즉시 시스템으로 통과시킵니다. 카카오톡 등 일부 앱이 Secure Input 플래그를 해제하지 않는 상황에 대응하기 위해, 활성화된 클라이언트의 번들 ID(예: `SecurityAgent`, `loginwindow`)를 교차 검증하여 보안 환경을 정확히 판단합니다.

### 5. 한자 변환 엔진
우측 Option 키를 통해 한자 후보창을 호출합니다. 자체 개발한 `libhangul-swift`의 Prefix Tree(Trie) 자료구조를 활용하여, 수만 개의 한자 데이터베이스에서 O(m)의 시간 복잡도로 후보군을 검색합니다. Electron 기반 앱(Chrome, VS Code 등)에서도 후보창이 정상 표시되도록 렌더링 레벨과 포커스 관리가 최적화되어 있습니다.

### 6. 시스템 통합 및 UI
설정 창은 macOS 네이티브 반투명(Translucent) UI를 채택했습니다. 설정 내에서 입력기 작동에 필요한 접근성 권한 상태를 확인하고 요청할 수 있으며, 기본 영어(ABC) 입력기를 제거하는 편의 기능을 제공합니다.

## 설치 및 업데이트

[Releases](https://github.com/Meapri/PriType-Swift/releases) 페이지에서 `PriTypeV2_Release.pkg`를 다운로드하여 설치할 수 있습니다. 패키지는 Apple 공증(Notarization)을 완료하여 Gatekeeper 경고 없이 설치 가능합니다.

1. 설치 후 `시스템 설정 > 키보드 > 입력 소스 편집`에서 PriType을 추가합니다. (초기 인식 시 로그아웃이 필요할 수 있습니다.)
2. 업데이트 시 PKG를 덮어씌워 설치하면, 백그라운드 프로세스가 자동 교체되므로 재시작 없이 즉시 적용됩니다.

### 직접 빌드
```bash
./build_release.sh
```

## 디렉토리 구조
```
Sources/
├── PriType/              # 메인 앱 진입점 (main.swift)
└── PriTypeCore/          # 코어 로직 패키지
    ├── HangulComposer          # 한글 조합 엔진 (libhangul-swift) 연동
    ├── PriTypeInputController  # IMKInputController 구현 및 수명 주기 관리
    ├── RightCommandSuppressor  # CGEventTap 기반 단축키 처리
    ├── HanjaCandidateWindow    # 한자 후보창 UI 및 렌더링
    └── ConfigurationManager    # 사용자 설정 관리
```

## 요구사항
- macOS 14.0+
- Xcode 15.0+ / Swift 5.9+

## 라이선스
MIT License
