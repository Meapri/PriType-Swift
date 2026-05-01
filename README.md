# PriType

macOS용 한글 입력기. Swift와 InputMethodKit으로 만들었고, 한글 조합 엔진으로 [libhangul-swift](https://github.com/Meapri/libhangul-swift)를 사용한다.

## 기능

- **한글 조합**: 두벌식, 세벌식 390, 옛한글 자판 지원
- **한자 변환**: 한글 입력 중 한자키를 눌러 한자 후보 선택
- **자모 특수문자**: 자음(ㅁ, ㅎ 등) 입력 후 한자키를 누르면 ♥, ★ 등 390개 특수문자 입력
- **한/영 전환**: 우측 Command 기본, 설정에서 아무 키나 지정 가능
- **영문 편의 기능**: 문장 시작 자동 대문자, 더블스페이스 → 마침표
- **자동 업데이트 확인**: GitHub Releases 기반

## 설치 및 문제 해결 가이드

1. **PKG 설치**
   [Releases](https://github.com/Meapri/PriType-Swift/releases) 페이지에서 최신 PKG를 다운로드하여 설치합니다. Apple 공증을 완료하여 Gatekeeper 경고 없이 안전하게 설치됩니다.

2. **기본 설치 경로**
   PriType의 실제 앱 번들은 `/Library/Input Methods` (Finder > 컴퓨터 > Macintosh HD > 라이브러리 > Input Methods) 경로에 설치됩니다. 수동으로 시스템 권한을 부여하거나 바탕화면에 앱 단축키를 빼놓고 싶을 때 이 경로로 이동하시면 됩니다.

3. **기본 입력기 충돌 방지 (중요)**
   충돌 없이 완벽하게 작동하려면 macOS 기본 입력기(한글, ABC 등)를 모두 목록에서 제거하는 것을 권장합니다. PriType 설정 창의 "영어 입력기 비활성화" 버튼을 눌렀음에도 기본 입력기가 계속 남아있다면, **Mac을 재시동**한 후 다시 확인해 주세요. 최초 설치 시에도 로그아웃이나 재시동이 필요할 수 있습니다.

4. **우측 Command 한/영 전환 권한**
   오른쪽 Command 키로 한/영 전환이 먹히지 않는다면, `시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용`에서 PriType에 접근성 권한이 정상적으로 부여되었는지 확인하고, 권한을 토글한 뒤 **Mac을 재시동**해 보세요.

5. **다국어 입력기 호환성**
   PriType은 일본어, 중국어 등 타 언어의 Mac 기본 입력기와 함께 켜져 있어도 충돌 없이 정상 작동합니다. 단, 외부 키보드를 사용하여 세 개 이상의 언어를 오가며 타이핑할 경우, 입력 소스 전환을 위해 `지구본(Globe)` 키 등 별도의 시스템 단축키를 매핑하여 활용하시는 것이 편리합니다.

## 요구사항

- macOS 26.0+ (Tahoe)
- Swift 6.2+

## 빌드

```bash
# 개발 빌드
swift build

# 릴리즈 PKG 생성
./build_release.sh
```

## 문서

- [ARCHITECTURE.md](ARCHITECTURE.md) — 내부 구조, 모듈 설명, 테스트 구성
- [BENCHMARK.md](BENCHMARK.md) — 성능 측정 결과

## 라이선스

MIT License
