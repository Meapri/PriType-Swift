# PriType

macOS에 최적화된 Swift 6 기반의 빠르고 안전한 한글 입력기입니다.
InputMethodKit을 활용하여 시스템과 네이티브로 연동되며, 엄격한 동시성 모델과 현대적인 UI를 제공합니다.

## 주요 특징

### 1. 최신 기술 스택과 안정성
- **Swift 6 & Strict Concurrency**: 완전한 동시성 검사를 통과한 안전한 메모리 관리
- **테스트 커버리지 보장**: Swift Testing 프레임워크를 기반으로 핵심 비즈니스 로직(컨텍스트 감지, 키 처리, 문자열 조합 등) 검증 완료
- **메모리 최적화**: 이벤트 후킹(CGEventTap) 시 발생하는 포인터 유지(retain) 오류를 제거하여 장시간 사용 시의 메모리 누수 원천 차단

### 2. 정밀한 컨텍스트 감지와 성능
- **Zero-IPC 캐싱 구조**: 입력창 활성화 시 컨텍스트를 1회 분석 후 캐시하여 매 키 입력마다 발생하는 무거운 프로세스 간 통신(IPC) 제거
- **Finder 예외 처리**: Finder 바탕화면의 더미 입력창을 좌표 기반 휴리스틱으로 정확하게 판별하여, 비활성 영역에서의 단축키 충돌 방지
- **어댑터 패턴(Adapter Pattern) 적용**: 표준 입력창과 Finder 바탕화면 등의 특수 컨텍스트를 어댑터 패턴으로 분리하여 유연하게 대응

### 3. 강화된 보안과 프라이버시
- **Secure Input 감지**: 암호 입력창 등 보호된 환경에서 자동으로 로깅 및 키 후킹 비활성화
- **민감 정보 보호**: 디버그 로그에서 실제 사용자의 키 입력(Key Code) 및 조합 텍스트를 기본적으로 `[REDACTED]` 처리하여 개인정보 유출 방지
- **시스템 권한 관리**: Apple 공식 TIS API를 활용하여 입력 소스를 안전하게 조회

### 4. 현대화된 사용자 인터페이스
- **Liquid Glass 디자인**: macOS 네이티브 API를 활용한 반투명 유리 효과(Translucent) 설정 창 제공
- **상태 표시줄 피드백**: 상태 표시줄(가/A) 변경 시 부드러운 애니메이션 효과를 주어 시각적 피드백 강화

### 5. 신뢰할 수 있는 배포 파이프라인
- **PKG 자동화**: `pkgbuild`를 활용한 시스템 전역 설치(`.pkg`) 지원 및 패키지 충돌/재배치(Relocation) 방지 로직 적용
- **공증(Notarization) 자동화**: `xcrun notarytool` 연동으로 Gatekeeper 보안 검증 완비
- **안전한 업그레이드**: 설치 전 `preinstall` 스크립트로 꼬여있는 권한의 구버전을 깔끔하게 정리 후 설치

---

## 아키텍처

- **PriTypeInputController**: IMKInputController 서브클래스. 캐싱된 ClientContext를 기반으로 이벤트를 효율적으로 분배합니다.
- **HangulComposer**: 조합 엔진. `libhangul-swift`의 Trie 기반 사전 검색을 활용하여 고성능 한자 및 한글 조합을 수행합니다.
- **ClientContextDetector**: 번들 ID 체크와 좌표 휴리스틱을 결합한 하이브리드 입력 상태 감지 모듈입니다.
- **RightCommandSuppressor**: 로우 레벨 이벤트 탭을 통해 Right Command 키를 한영 전환 전용으로 매핑합니다.

---

## 지원 자판

| ID | 이름 | 설명 |
| :--- | :--- | :--- |
| `2` | **두벌식 표준** | 표준 두벌식 (QWERTY 기반) |
| `3` | **세벌식 390** | 기호 입력이 강화된 세벌식 |
| `2y` | **두벌식 옛한글** | 제주어/고어 입력 지원 |
| `3y` | **세벌식 옛한글** | 세벌식 기반 옛한글 |

---

## 설치 및 빌드

### 요구 사항
- macOS 15.0 이상 (Target: macOS 26 Tahoe API 사용)
- Xcode 16.0 이상 (Swift 6.2)

### 패키지 빌드 (PKG)
배포용 설치 파일을 생성하려면 프로젝트 루트에서 다음 스크립트를 실행합니다. 기존 설치본을 안전하게 제거한 뒤 `/Library/Input Methods`에 설치되는 릴리스 패키지가 생성됩니다.

```bash
./build_release.sh
```

생성된 `PriTypeV2_Release.pkg`를 실행하여 설치한 뒤, 시스템 설정 > 키보드 > 입력 소스 편집에서 `PriType`을 추가하세요. (최초 설치 시 로그아웃 또는 재시동이 필요할 수 있습니다.)

### 로컬 테스트
```bash
./install.sh
```
개발용으로 사용자 디렉토리(`~/Library/Input Methods`)에 빠르게 빌드하고 덮어씁니다.

---

## 라이선스

**MIT License**
Copyright © 2026 PriType Team.
내부적으로 사용된 `libhangul-swift` 라이브러리는 해당 라이선스를 따릅니다.
