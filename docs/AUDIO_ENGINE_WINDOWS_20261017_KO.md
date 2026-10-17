# Godot 4.7.1 Windows 엔진 수정 검증 — 진행 기록

현재 상태: **검증 진행 중**. 원본 Windows 엔진 빌드는 성공했으며 패치 엔진 및
전용 export template의 검증이 남아 있습니다. 컴파일 성공을 누수 해결로 판단하지 않습니다.
PC 자동 종료는 수행하지 않습니다.

## 빌드 환경 조사와 승인

PATH 밖의 Visual Studio 설치 정보를 조사하니 Visual Studio Community 2022 17.13.5,
MSVC 19.43.34809 x64 및 Windows SDK 10.0.22621.0이 이미 설치되어 있었습니다.
Windows.h, UCRT 헤더·라이브러리, kernel32.lib, rc.exe, mt.exe를 확인했고,
실제 C++ 프로그램의 컴파일·링크·실행으로 `MSVC_WINDOWS_SDK_OK`를 확인했습니다.
이전 보고서의 PATH 조사만으로 전체 컴파일러 설치 여부를 판단할 수는 없었습니다.

기존 프로젝트 가상환경의 Python은 3.14.3 x64이며 SCons만 없었습니다.
사용자의 명시적 승인 후 다음 명령으로 **기존 .venv에만 SCons 4.11.1**을 설치했습니다.

```powershell
.\.venv\Scripts\python.exe -m pip install "SCons==4.11.1"
```

관리자 권한, 시스템 PATH, Visual Studio 설치, 보안 설정을 변경하지 않았습니다.
조사 당시 RAM은 약 31.6 GiB, C 드라이브 여유 공간은 약 165.2 GiB였습니다.

## 정확한 소스와 공식 PR 비교

공식 `4.7.1-stable` 태그의 전체 소스를 별도 checkout으로 확보했습니다.
커밋은 `a13da4feb8d8aefc283c3763d33a2f170a18d541`이며 기존 바이너리의 커밋과 일치합니다.
원본 `audio_server.cpp` SHA-256은
`d7641ef5852aa86f75c4d506759de2838a2c3886c29f7eb25fd9e9310d87c102`입니다.

[공식 PR #122742](https://github.com/godotengine/godot/pull/122742)의 조회 시점 HEAD는
`eb5f8e774b5ca29cfbec745829767f82a7e8ec98`이며 아직 미병합입니다.
PR의 추가 실행문과 기존 패치의 실행문을 프로그램으로 비교해 일치함을 확인했습니다.
차이는 4.7.1의 삽입 위치와 설명 주석 두 줄입니다.
모든 드라이버의 `finish()` 이후 기존 playback 삭제 함수를 호출하고 `_cleanup_lists()`를
실행하며, 버스 삭제 이전에 완료합니다. 대기 시간이나 로그 필터를 추가하지 않습니다.
WASAPI와 Dummy의 종료 구현은 자신의 믹서 스레드를 join하는 것을 소스에서 확인했습니다.

원본과 패치 소스는 `.data/engine-build-20261017/source-original`, `source-patched`에
분리했습니다. 기존 Godot 실행 파일과 설치된 Windows template은 덮어쓰지 않았습니다.
공통 빌드 옵션과 정확한 버전은
[windows_build_recipe.json](../.autodev/audio_lab/engine_patch/windows_build_recipe.json)에 있습니다.
D3D12·ANGLE·AccessKit은 추가 SDK 설치 없이 C01의 GL Compatibility를 검사하도록 양쪽에서
동일하게 비활성화했습니다. 이 설정은 모든 Godot 기능·환경의 인증을 의미하지 않습니다.

## 현재까지 실제 결과

직접 빌드한 원본 editor는 1,300.97초, 패치 editor는 1,336.601초에 컴파일·링크를 완료했습니다.
기존 `probe.gd`, `original_immediate.gd`와 누수 판정기는 변경하지 않았습니다.
각 실행은 실제 Windows 독립 프로세스이며 사용자 저장 데이터도 격리했습니다.

| 원본 엔진 검사 | 전체 시행 | 통과 | 누수 발생 시행 |
|---|---:|---:|---:|
| 전체 사전 지정 행렬 | 570 | 278 | 292 |
| 원본 게임의 기존 즉시 종료, WASAPI | 30 | 24 | 6 |
| 이전 후보의 기존 즉시 종료, WASAPI | 30 | 24 | 6 |

570회 전체에서 보고된 누수 객체 진단은 합계 34,268개입니다.
종료 코드가 0인 누수 시행도 모두 실패로 계산했습니다.
독립 감사 결과 570개 원본 로그의 해시·드라이버·완료 표시·판정이 모두 일치했습니다.
원본 엔진의 오디오 해결 판정은 `false`입니다.

기존 공식 Windows template을 사용하는 별도 export 대조에서는 debug/release 각각
게임 복사본당 30회, 합계 120회 중 20회에서 누수가 발생했습니다. 이 대조의 template은
기존 공식 MinGW 바이너리이므로 새 MSVC template의 동일 설정 비교와 구분합니다.
실제 OpenGL 3.3/AMD Radeon RX 6800 그래픽 실행과 WASAPI 재생 측정도 통과했습니다.
원본 게임 QUALITY의 JSON 오류는 계속 실패로 기록했으며 이전 후보의 QUALITY는 통과했습니다.
패치 editor의 동일 행렬은 **570/570 통과, 누수 시행 0건·누수 객체 0개**입니다.
원래 WASAPI 즉시 종료 스크립트도 두 게임 복사본에서 각각 30/30 통과했습니다.
독립 감사가 570개 원본 로그의 해시·드라이버·완료 표시·판정을 모두 확인했습니다.
이 결과는 editor 범위이며 export template과 최종 게임·E2E 인증은 별도입니다.

패치 editor의 게임 QA 20게이트는 19 통과·1 실패입니다. 실패는 현재 원본 게임의
손상 JSON 오류(기존 task_1 대상)이며, 이전 수정 후보의 모든 QA는 통과했습니다.
독립 감사에서도 18개 실행 로그와 20게이트의 판정이 일치했고 누수 객체는 0개입니다.
원본 게임의 실패를 최종 완료에서 제외하지 않습니다.

## 검증 도구의 수정과 보존한 실패

추가 재생 검사는 WASAPI 활성화와 인쇄·되돌리기·완료 SFX의 믹서 peak를 측정합니다.
음소거·볼륨 0 이후의 복원도 검사합니다. 최초 작성 때 타입 추론 오류가 발생했고
명시적 bool 타입으로 고친 재실행은 9개 재생 측정을 통과했습니다. 최초 오류 로그도 보존했습니다.
이는 실제 사람의 청취·클리핑 평가를 대신하지 않습니다.

기본 export template은 CLI의 `--script` 경로 override를 비활성화합니다.
첫 export 검사에서 이를 확인하여 해당 프로세스를 중단하고 원본 로그를 남겼습니다.
검사 도구를 수정해 별도 QA pack의 main loop가 **바이트가 같은 기존 probe를 상속**하게 했습니다.
부팅 요구를 만족하는 빈 Node 외에 오디오나 대기 처리를 추가하지 않습니다.
실제 게임의 기본 장면을 실행하는 Windows 빌드는 별도로 검사합니다.
template의 경로 override 설정이나 게임 원본은 변경하지 않습니다.
첫 QA pack의 빈 main scene이 거부된 실패도 보존했고, 오디오가 없는 빈 Node 장면을
지정하여 해결했습니다. 별도 게임 QA 복사본의 import 누락으로 발생한 실패도 보존했으며,
각 복사본에서 IMPORT 게이트를 먼저 실행하도록 수정했습니다.

Windows 하네스 회귀 검사에서는 timeout 후 자식 종료가 비동기로 끝나 로그가 잠기는
문제를 재현했습니다. 자식 프로세스 핸들의 종료 신호와 로그의 실제 독점 열기 가능 상태를
확인하도록 수정했습니다. 고정 시간 경과로 성공 처리하지 않으며 상한 초과는 실패입니다.
이 수정은 오디오 엔진 수정과 독립적입니다. 관련 최초 실패·중간 재검증 실패도 남겼습니다.
수정 후 Windows 대상 46건은 45 통과·1 symlink 권한 skip, 기존 하네스 111건은
Windows 100 통과·11 Linux 전용 skip, WSL에서는 111건 모두 통과했습니다.
Linux 실행 파일을 사용하는 추가 fixture 3건도 WSL에서 모두 통과했습니다.
해시 고정 `engine_profile` 기능은 .data 안의 template 복사본과 원본 엔진을 사용한
실제 Windows export, EXE와 template의 바이트 일치, WASAPI 시작·종료까지 통과했습니다.
이 검사는 profile 연결 기능의 검증이며 원본 엔진 누수 해결 판정은 아닙니다.

## 증거 위치와 남은 작업

중단 후 재개 시 patched template_debug 빌드가 종료 코드 2로 끝난 것을 확인했습니다.
최초 로그는 variant_call 및 gdextension_special_compat_hashes 오브젝트의 Error 1만
기록하고 컴파일러의 구체적 원인 진단은 남기지 않았습니다. 원인을 단정하지 않습니다.
첫 실패 로그·JSON을 보존하고 동일 옵션·소스·기존 오브젝트 캐시로 해당 target만
증분 재시도합니다. 완료된 editor 빌드나 570회 행렬을 다시 실행하지 않습니다.
뒤 단계만 기다리던 자체 archive worker는 신원을 확인한 뒤 종료했고, 실제 template
성공을 확인한 후 이어갈 예정입니다. 사용자 프로세스는 종료하지 않았습니다.

원본 증거는 `.data/engine-build-20261017/`에 보존합니다.
`preparation-audit.json`, 빌드별 JSON/로그, `validation-original/results.json`,
`validation-original/independent-audit.json`이 현재 완료된 주요 자료입니다.
중단한 초기 export 검사와 후속 검사도 서로 다른 이름으로 보존합니다.
대용량 바이너리·원본 로그·개인 경로가 담긴 자료는 Git에 넣지 않습니다.

패치 엔진의 전체 반복 검사, patched debug/release template, 모든 게임 QA,
실제 Windows 그래픽·오디오 재생, task_1 → task_2 E2E와 승인된 개발 브랜치 백업을
검증한 뒤 최종 결과를 이 보고서에 반영합니다. 현재 게임 원본과 기존 실패 run은 보존했습니다.
