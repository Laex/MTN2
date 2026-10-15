# Modern Terminal Navigator 2 (MTN2)

[English](README.en.md) | [Deutsch](README.de.md) | [Русский](README.md) | [中文](README.zh.md) | **한국어**

**Necromancer's DOS Navigator** 및 **Far Manager** 스타일의 듀얼 패널 파일 관리자로, 내장 콘솔,
터미널, 파일 뷰어 및 텍스트 에디터를 탑재하고 있습니다. 인터페이스는 텍스트 기반(TUI)이지만 일반 GUI 창에서 렌더링됩니다.
TrueType 폰트, 유니코드 및 32비트 트루컬러를 지원하는 Delphi FireMonkey 캔버스(Skia 렌더링, `--no-skia` 옵션으로 표준 캔버스 폴백 지원) 기반의
가상 문자 그리드로 구동됩니다. 한중일(CJK) 한자, 히라가나, 가타카나, 한글 및 전각 문자는
다른 터미널과 마찬가지로 2열 너비(더블 와이드)를 차지합니다.

[![CI](https://github.com/Laex/MTN2/actions/workflows/ci.yml/badge.svg)](https://github.com/Laex/MTN2/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/license-MPL--2.0-blue.svg)](LICENSE)

![MTN2: 탭이 있는 듀얼 패널](docs/images/mtn2-panels.png)

[프로젝트 웹사이트](https://laex.github.io/MTN2/en/)(영어) ·
[최신 버전 다운로드](https://github.com/Laex/MTN2/releases/latest) ·
[변경 사항](CHANGELOG.md) · [FAQ](docs/FAQ.md)(러시아어) · [기여 안내](CONTRIBUTING.md)(러시아어) ·
[토론](https://github.com/Laex/MTN2/discussions) ·
[Habr 기사](https://habr.com/ru/articles/1087174/)(러시아어)

MTN2는 DOS Navigator와 Far Manager와 함께 자랐고 키보드로 작업하는 사람들을 위한 프로그램입니다: 시스템·네트워크 엔지니어, 개발자, 관리자. Far Manager를 대체하지 않으며 Total Commander와 경쟁하지도 않습니다. 나름의 습관을 가진 또 하나의 듀얼 패널 관리자일 뿐입니다.

## 원칙

- **텔레메트리와 클라우드 기능 없음.** 유일한 네트워크 접근은 GitHub에서 새 버전을 확인하는 것입니다(시작 시 하루 한 번). **≡ → 업데이트 확인...**에서 끌 수 있습니다("시작 시 업데이트 확인").
- **휴대성.** 폴더 하나, 설치 프로그램 없음, 레지스트리 기록 없음. 포터블 버전은 설정을 `MTN2.exe` 옆에, 일반 버전은 `%APPDATA%\MTN2`에 저장합니다. 설정, 테마, 단축키 매핑은 일반 JSON 파일입니다.
- **키보드 우선.** 단축키 배치는 Far Manager와 비슷하며 자유롭게 바꿀 수 있습니다. 탭과 터미널은 ConEmu처럼 동작합니다.
- **진짜 터미널.** 콘솔은 흉내가 아니라 ConPTY(cmd, PowerShell, WSL, SSH) 위에서 동작합니다.
- **확장성.** 네이티브 및 WebAssembly 플러그인: 사용자 파일 시스템, 패널, 명령, 대화 상자, 텍스트 색상 강조.

> Habr 기사에서는 이름을 Modern Turbo Navigator로 풀이했습니다. 현재 이름은 **Modern Terminal Navigator**입니다.


## 스크린샷

| | |
|---|---|
| ![탭이 있는 듀얼 패널](docs/images/mtn2-panels.png) | ![폴더로 열린 압축 파일](docs/images/mtn2-archive.png) |
| 탭이 있는 패널, Far Classic 테마 | 압축 파일이 폴더처럼 열립니다 |
| ![Markdown 뷰어](docs/images/mtn2-markdown.png) | ![JSON 강조가 있는 에디터](docs/images/mtn2-editor.png) |
| 표를 지원하는 Markdown 뷰어 | 에디터. 강조는 플러그인이 제공합니다 |
| ![내장 콘솔](docs/images/mtn2-console.png) | ![Dracula 테마](docs/images/mtn2-dracula.png) |
| 내장 콘솔(Ctrl+O) | Dracula 테마 |

## 주요 기능

- **패널:** 탭을 지원하는 듀얼 패널, 간략(Brief)/상세(Full)/다중 열 보기 모드, 정렬, 빠른 검색 및 실시간 필터,
  와일드카드 마스크 선택, 디렉터리 비교, 히스토리 및 폴더 바로가기(즐겨찾기), 긴 경로 지원(> MAX_PATH).
- **파일 작업:** 백그라운드 작업 및 진행률 표시를 통한 복사, 이동, 삭제, 파일 속성 및 타임스탬프 수정,
  심볼릭/하드 링크, 휴지통, 체크섬 확인, 디렉터리 동기화.
- **콘솔 및 터미널:** 패널 하단 명령줄, 실제 ConPTY 연동(cmd, PowerShell, pwsh, Git Bash, WSL,
  SSH), ANSI/VT 이스케이프 시퀀스 파싱, TUI 프로그램을 위한 대체 화면 버퍼, 터미널 작업 공간.
  패널이나 명령줄에서 실행된 콘솔 프로그램은 내장 콘솔에서 동작하며 출력 결과가 화면에 유지됩니다(`Ctrl+O`).
- **보기 및 편집:** 내장 뷰어(텍스트, 16진수 hex, 대용량 파일 스트리밍 로딩), 에디터,
  빠른 보기(`Ctrl+Q`), Markdown 미리보기, 외부 뷰어/에디터 연동.
- **가상 파일 시스템(VFS):** 압축 파일을 폴더처럼 탐색(zip, `7z.dll`을 통한 7z), SSH 기반 SFTP, 플러그인 VFS.
- **사용자 정의 설정:** 재정의 가능한 키 매핑(`keymap.json`), 파일 기반 테마(Far Classic, Total Commander, Dracula, Nord, Solarized, High Contrast 등; 내장 테마 에디터를 통한 커스텀 테마 생성),
  사용자 메뉴(F2), 파일 연결 설정, F1 컨텍스트 도움말.
- **다국어 지원:** UI 및 도움말이 영어, 러시아어, 독일어, 중국어 간체로 제공됩니다. 언어는 **옵션 → 글꼴 / 화면...** (Options → Font / Display...)에서 선택할 수 있으며
  재시작 없이 즉시 적용됩니다. `MTN2.exe` 파일 옆에 `resource\<언어코드>\` 폴더(`locale.json`, `strings.json`, `help\`의 도움말)를 추가하여 사용자 언어를 확장할 수 있으며 다시 컴파일할 필요가 없습니다. 프로그램에는 영어만 내장되어 있습니다.
- **유니코드:** CJK 한자(기본 다국어 평면 BMP), 히라가나, 가타카나, 한글 및 전각 문자가
  콘솔, 패널, 탭, 제목 표시줄에서 2열 너비로 표시되며, 누락된 글꼴은 시스템 폰트로 대체 렌더링됩니다.
- **플러그인:** 네이티브 DLL 및 WebAssembly(Wasmtime 기반) – 커스텀 VFS 스키마 및 전용 패널, 메뉴 항목,
  단축키 바인딩, 메시지 버스 지원. 대화 상자, 오버레이 및 상태 표시줄 플러그인 프로토콜이 정의되어 있으나
  현재는 메인 프로그램 내부용으로 제공됩니다 – [PLUGIN_BOUNDARIES](docs/PLUGIN_BOUNDARIES.md) 참조.
- **업데이트:** GitHub 새 릴리스 매일 확인; 다운로드(SHA-256 검증 포함), 설치 및
  재시작은 사용자 확인 후에만 진행됩니다. 메뉴 **≡ → 업데이트 확인...**.

Windows x64(GUI 애플리케이션) 및 Linux x86-64를 지원합니다: `mtn2-tui`는 전체 텍스트 터미널에서 실행되며,
동일한 패널, 뷰어, 에디터, 콘솔 및 플러그인을 제공하고 SSH 및 `tmux` 환경에서도 작동합니다([docs/LINUX.md](docs/LINUX.md) 참조).
실험적인 Linux GUI 버전 `mtn2-sdl`은 같은 창을 일반 SDL2 창에서 보여 줍니다: 시스템 글꼴, 마우스와 휠, 모든 키보드 배열 입력, 데스크톱 클립보드, 빠른 보기의 이미지. X11 및 Wayland(Windows에서는 WSLg)에서 실행되고 `tar.gz` 및 `.deb` 패키지에 포함되며 `libSDL2`와 `libfreetype`이 필요합니다(PNG와 JPEG는 `libSDL2_image` 추가): 의존성과 옵션은 [docs/LINUX.md](docs/LINUX.md)(러시아어)를 참조하십시오. macOS 빌드는 향후 지원 예정입니다.

## 설치

빌드된 패키지는 [Releases](https://github.com/Laex/MTN2/releases) 페이지에서 다운로드할 수 있습니다:

- `MTN2-<버전>-win64.zip` – 설정 및 히스토리가 `%APPDATA%\MTN2`에 저장됩니다.
- `MTN2-<버전>-win64-portable.zip` – 포터블 버전: 모든 데이터가 `MTN2.exe`와 같은 폴더에 저장됩니다;
- `MTN2-<버전>-linux-x64.tar.gz` 및 `MTN2-<버전>-linux-x64.deb` – Linux 버전: `mtn2-tui`(터미널 창 안에서 실행, SSH 지원)와
  실험적인 GUI 버전 `mtn2-sdl`(SDL2 창, `libSDL2`와 `libfreetype` 필요):
  설치 방법, 의존성 및 옵션은 [docs/LINUX.md](docs/LINUX.md)를 참조하십시오.

**Windows:** 압축을 임의의 폴더에 풀고 `MTN2.exe`를 실행하기만 하면 됩니다. 이후에는 프로그램이 자체적으로 업데이트됩니다
(메뉴 **≡ → 업데이트 확인...**). 7z 및 기타 7-Zip 포맷 지원을 위해 [7-Zip](https://www.7-zip.org)의 `7z.dll`이 번들로 포함되어 있습니다(GNU LGPL 라이선스; 라이선스 전문은 `plugins\mtn.7z\license.txt`, 상세 내용은 [THIRD-PARTY.md](THIRD-PARTY.md) 참조). 필요한 경우 `plugins\mtn.7z\`의 DLL을 사용자의 x64 버전으로 교체할 수 있으며, zip 파일은 이 DLL 없이도 열 수 있습니다.

**Linux:** `tar xzf MTN2-*-linux-x64.tar.gz && ./mtn2/install.sh`(모든 사용자용은 `sudo`) 또는
`sudo apt install ./MTN2-*-linux-x64.deb`. 설치 후 `mtn2`는 터미널 버전을, `mtn2-sdl`은 SDL2 창을 실행합니다.
압축을 푼 폴더는 설치 없이도 실행됩니다: `mtn2/mtn2-tui`와 `mtn2/mtn2-sdl`을 그 자리에서 실행하면 됩니다.

### 개발 빌드 (Dev Builds)

프리릴리스(dev) 빌드는 `main` 브랜치에 변경 사항이 커밋될 때마다 별도 저장소인
[Laex/MTN2-dev](https://github.com/Laex/MTN2-dev/releases)에 자동으로 게시됩니다. 개발 빌드를 자동으로 수신하려면
**≡ → 업데이트 확인...**을 열고 dev 채널 옵션을 활성화하십시오. 언제든지 체크를 해제하여 안정 릴리스로 돌아갈 수 있습니다.
개발 빌드에는 최신 변경 사항이 포함되어 있어 다소 불안정할 수 있습니다.

## 빌드 방법

RAD Studio 13(Delphi, `Studio\37.0`) 및 Windows x64가 필요합니다. WASM 플러그인 `mtn.ws` 빌드에는 Rust가 필요합니다.
Linux 버전은 Windows에서 `dcclinux64` 컴파일러로 크로스 컴파일되며, 테스트는 WSL에서 실행됩니다.

```powershell
./src/build.ps1 -Config Release -Platform Win64   # bin\win64\MTN2.exe + bin\win64\plugins\
./src/tests/run-tests.ps1                          # DUnitX 회귀 테스트
./src/build-linux.ps1                              # bin\linux64\mtn2-tui
./src/tests/run-tests-linux.ps1                    # WSL에서 동일한 테스트 실행
```

실행: `bin\win64\MTN2.exe [--no-skia] [--fps] [경로]`. 상세 내용은 [docs/BUILDING.md](docs/BUILDING.md)를 참조하십시오.

## 저장소 구조

| 경로 | 내용 |
|---|---|
| `src/Core` | 핵심: 패널, VFS, 콘솔, 에디터, 대화 상자, 플러그인 호스트 |
| `src/Platform` | 플랫폼 추상화 계층: `Windows` 및 `Posix` 모듈 |
| `src/Hosts` | 셸 호스트: `Ansi` – 텍스트 터미널 버전 |
| `src/Forms`, `src/dialogs`, `src/Assets/themes` | 메인 폼, JSON 대화 상자, 기본 내장 테마 |
| `src/plugins` | 내장 플러그인 (`mtn.7z`, `mtn.tmp`, `mtn.ws`, WASM 데모) |
| `src/tests` | 그룹별 DUnitX 회귀 테스트 및 실행 스크립트 `run-tests.ps1` |
| `src/tools` | DialogDesigner, ExportDialogJson, `Group.groupproj` 프로젝트 그룹, 유틸리티 스크립트 |
| `bin/win64`, `bin/linux64` | 플랫폼별 빌드 결과물 |
| `bin/win64/resource` | 언어 팩: 인터페이스 문자열과 F1 도움말(en/ru/de/zh), 프로그램과 함께 배포 |
| `docs` | 개발자 문서, 스크린샷 (`docs/images`) |

## 문서

- [SDS.md](docs/SDS.md) – 상세 사양서: 설계 개념, 데이터 구조, API, 로드맵.
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) – 아키텍처 계층, 데이터 흐름 및 불변식.
- [BUILDING.md](docs/BUILDING.md) – 빌드 가이드, 테스트, CI/CD.
- [LINUX.md](docs/LINUX.md) – Linux 터미널 버전: 설치, 실행 옵션, 의존성.
- [THEMES.md](docs/THEMES.md) – 테마 파일 형식 및 색상 역할 정의.
- [HELP.md](docs/HELP.md) – 단일 파일 형태의 사용자 도움말 전문.
- 플러그인 규약: [PLUGIN_BOUNDARIES](docs/PLUGIN_BOUNDARIES.md), [PANEL](docs/PANEL_PLUGIN.md),
  [DIALOG](docs/DIALOG_PLUGIN.md), [INPUT](docs/INPUT_PLUGIN.md), [OVERLAY](docs/OVERLAY_PLUGIN.md),
  [STATUS](docs/STATUS_PLUGIN.md), [TEXTAREA](docs/TEXTAREA_PLUGIN.md), [TOOLBAR](docs/TOOLBAR_PLUGIN.md),
  [UI_PRIMITIVES](docs/UI_PRIMITIVES.md).

## 프로젝트 개발 배경

MTN2 개발에는 자체 개발 도구를 포함한 AI 어시스턴트가 적극적으로 활용되었습니다:

- 사전 프로젝트 문서화: 사양서([SDS.md](docs/SDS.md)), 아키텍처 개요, `docs/`의 플러그인 프로토콜 명세 작성;
- 로드맵 추적 및 작업 계획 수립;
- 대부분의 소스 코드 주석 작성;
- DUnitX 기반 회귀 테스트 슈트 개발(`src/tests`);
- 사용자 문서 작성: F1 도움말(`bin/win64/resource/<언어코드>/help`), [CHANGELOG.md](CHANGELOG.md), 릴리스 노트.

## 라이선스

[Mozilla Public License 2.0](LICENSE).
