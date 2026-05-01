# PriType

macOS용 한글 입력기. Swift와 InputMethodKit으로 만들었고, 한글 조합 엔진으로 [libhangul-swift](https://github.com/Meapri/libhangul-swift)를 사용한다.

## 기능

- **한글 조합**: 두벌식, 세벌식 390, 옛한글 자판 지원
- **한자 변환**: 한글 입력 중 한자키를 눌러 한자 후보 선택
- **자모 특수문자**: 자음(ㅁ, ㅎ 등) 입력 후 한자키를 누르면 ♥, ★ 등 390개 특수문자 입력
- **한/영 전환**: 우측 Command 기본, 설정에서 아무 키나 지정 가능
- **영문 편의 기능**: 문장 시작 자동 대문자, 더블스페이스 → 마침표
- **자동 업데이트 확인**: GitHub Releases 기반

## 설치

[Releases](https://github.com/Meapri/PriType-Swift/releases) 페이지에서 PKG를 다운로드하여 설치한다. Apple 공증 완료 상태이므로 Gatekeeper 경고 없이 설치된다.

설치 후 `시스템 설정 > 키보드 > 입력 소스 편집`에서 PriType을 추가한다. 최초 설치 시 로그아웃이 필요할 수 있다.

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
