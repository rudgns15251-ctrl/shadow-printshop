# Godot 4.7.1 Windows 오디오 수정 및 자율 개발 최종 QA

2026-10-17 / Asia/Seoul. **기술 검증 완료. `AUDIO_LEAK_RESOLVED=true`, `AUTONOMOUS_HARNESS_READY=true`.**
인증 대상 게임 커밋은 `3b921c763b79b092db95fc251f7a76720f13f04c`입니다.
검증 범위는 현재 PC의 Windows x86_64, C01, GL Compatibility, 고정한 별도 엔진·template입니다.
사람의 플레이·청취·주관적 가독성 검수와 상용 출시 승인은 별도이며 수행했다고 주장하지 않습니다.
**PC 자동 종료는 하지 않았습니다.**

기계 판독 결과와 전체 SHA는 [검증 JSON](AUDIO_ENGINE_WINDOWS_20261017.json)에 있습니다.
개별 `verify_evidence.py`는 한 실험 조건만 감사하므로 전체 해결 플래그를 의도적으로 false로 유지합니다.
통합 JSON은 그 감사 결과에 template·최종 게임 QA·E2E·보존 조건까지 대조한 별도 인증입니다.
이 문서가 최신 결과입니다. `AUDIO_ROOT_CAUSE_20261017_KO.md` 등 이전 BLOCKED 보고서는
당시 실패를 보존한 기록이며, 기존 사용자 미커밋 수정도 그대로 유지했습니다.

## 실제 누수 발생 횟수

모든 시행을 분모에 포함했습니다. 종료 코드 0이어도 ERROR·ObjectDB 누수·잔류 리소스·
잘못된 드라이버·완료 표시 누락은 실패입니다. 성공 30회가 될 때까지 다시 세지 않았습니다.

| 고정된 실험 범위 | 전체 | 통과 | 실패 | 오디오 누수 발생 시행 |
|---|---:|---:|---:|---:|
| 원본 MSVC editor, WASAPI/Dummy 행렬 | 570 | 278 | 292 | 292 |
| 패치 MSVC editor, 동일 행렬 | 570 | 570 | 0 | 0 |
| 원본 MSVC debug/release export 대조 | 120 | 64 | 56 | 56 |
| 패치 MSVC debug/release export | 120 | 120 | 0 | 0 |
| 최종 코드의 editor 독립 오디오 검사 | 180 | 180 | 0 | 0 |
| 최종 코드의 Windows export 즉시 종료 | 120 | 120 | 0 | 0 |
| 현재 task_1/task_2 신뢰 QA의 독립 오디오 검사 | 120 | 120 | 0 | 0 |
| 제한된 native Codex 내부의 초기 검증 | 223 | 0 | 223 | 0 |

원본 editor는 누수 객체 진단이 누적 **34,268개**, 동일 MSVC template 대조는 **1,652개**
(WAV 168 + playback 1,484)였습니다. 이는 실행 간 고유 객체 수나 메모리 바이트가 아닌
로그의 `Leaked instance` 누적 진단 수입니다. 패치의 지정된 검증 범위에서는 모두 0개입니다.
원래 WASAPI 즉시 종료 스크립트도 두 게임 복사본에서 각각 원본 24/30, 패치 30/30입니다.

기존 공식 MinGW template의 추가 대조 120회는 100 통과·20 누수 실패(객체 진단 429개)였습니다.
이는 동일 MSVC 설정 대조와 구분합니다. 이전 최초 원인 분리 320회의 77 실패도 보존했습니다.
문구 보완 전 최종 검사(오디오 180회·export 120회), 최초 task_2 오디오 60회,
최초 팝업 51개 결과도 별도 보존했습니다. 팝업 표시 통과 후 발견한 원래 문구 조건 누락은
독립 실패 기록을 남기고 task_2만 보완했습니다. 과거 실패나 이전 검사 결과를 덮어쓰지 않았습니다.

## 근본 원인과 엔진 수정

플레이어가 stop/free돼도 AudioServer가 보유한 playback 참조는 비동기 회수 경로에 남습니다.
원본 `AudioServer::finish()`는 드라이버를 정지한 뒤 살아 있는 playback 목록을 비우지 않아,
이후 mix가 없는 즉시 종료에서 해당 참조가 남았습니다. 최소 프로젝트에서도 재현됐습니다.

패치는 **모든 드라이버 정지 후, 버스 삭제 전** 기존 삭제 함수로 playback 노드를 제거하고
`_cleanup_lists()`를 호출합니다. 게임의 종료 지연·고정 대기·오류 필터·음소거 우회는 추가하지 않았습니다.
기존 `_build_audio`, `_play_sound`, `_update_audio`, `_exit_tree`의 동작은 보존했습니다.

정확한 소스는 Godot `4.7.1-stable`, `a13da4feb8d8aefc283c3763d33a2f170a18d541`입니다.
원본 audio_server.cpp SHA는 `d7641ef5852aa86f75c4d506759de2838a2c3886c29f7eb25fd9e9310d87c102`,
패치 후 SHA는 `0c1a17182b54e141900b745ef92d798d028d64026adf0c7182c017b81cd40b98`입니다.
[공식 PR #122742](https://github.com/godotengine/godot/pull/122742)의 조회 당시 HEAD
`eb5f8e774b5ca29cfbec745829767f82a7e8ec98`와 추가 실행문 4개가 일치했습니다.
원본 PR은 조회 당시 미병합이었으며, macOS 보고만으로 Windows 해결을 가정하지 않았습니다.

원래 즉시 종료 probe의 SHA는
`c2d324affd3f97c4e59eec50397ed35ba86c762b84d7c4b29854f9da8d49273d`입니다.
기존 보존 스크립트와 바이트가 같고, 원인 분리 probe와 누수 판정기도 유지했습니다.
`.gitattributes`는 해당 두 probe와 엔진 patch의 LF만 고정해 Windows checkout 변환을 방지합니다.

## 실제 Windows 빌드와 template 호환성

MSVC 19.43.34809 x64, SDK 10.0.22621.0, 기존 Python 3.14.3 x64를 확인했습니다.
실제 C++ 컴파일·링크·실행도 통과했습니다. 사용자 승인으로 기존 `.venv`에만 SCons 4.11.1을 설치했습니다.
시스템 설치·관리자 권한·시스템 PATH·보안 설정·Windows 인증서 저장소는 변경하지 않았습니다.

공통 SCons 옵션은 `platform=windows arch=x86_64 msvc_version=14.3 mssdk_version=10.0.22621.0
d3d12=no angle=no accesskit=no debug_symbols=yes lto=none -j8`입니다.
정확한 명령은 [빌드 recipe](../.autodev/audio_lab/engine_patch/windows_build_recipe.json)에 있습니다.
현재 실험은 D3D12·ANGLE·AccessKit이나 모든 Godot 확장 기능을 인증한 것이 아닙니다.

| target | 원본 | 패치 |
|---|---|---|
| editor | 성공, 1,300.970초 | 성공, 1,336.601초 |
| template_debug | 성공, 41.931초(증분 대조) | 최초 실패 991.890초, 증분 재시도 성공 130.627초 |
| template_release | 성공, 45.288초(증분 대조) | 성공, 781.593초 |

최초 debug 빌드 실패는 두 오브젝트의 Error 1만 남겼으며 구체적 컴파일러 원인은
확정할 수 없습니다. 원본 로그를 보존하고 소스·옵션 변경 없이 필요한 target만 재시도했습니다.
완료됐던 editor 빌드나 570회 행렬은 처음부터 다시 실행하지 않았습니다.
원본 template은 패치 바이너리를 먼저 보관한 뒤 동일 캐시의 audio_server.cpp만 역적용해
다시 컴파일·링크했습니다. 이후 패치 소스와 출력도 복원했습니다.

고정 보관 엔진의 SHA는 `a0b0c9b8609914673ea003f4fe1a649edab3bd6f176ffb52ee2ff45be8475652`입니다.
일반 게임 EXE의 기본 장면 실행, 별도 QA pack, debug/release 각각 30회씩을 검사했습니다.
export된 EXE가 고정 template과 바이트로 일치하고 PCK가 실제로 실행됨을 독립 감사했습니다.
template의 CLI 경로 override 제한은 유지했습니다. QA pack은 바이트가 같은 원래 probe를 상속합니다.
기존 Godot 실행 파일과 Windows template을 합한 5개 파일의 전후 해시는 일치합니다.

프로젝트 로컬 `.autodev/config.json`은 검증된 별도 엔진과 해시 고정 template을 사용합니다.
기존 설치본에는 패치를 덮어쓰지 않았으므로, 재현·QA·export는 이 프로필을 사용해야 합니다.
엔진은 `.data/engine-build-20261017/binaries/patched/`, template 복사본은
보존한 `.data/audio-engine-e2e/.data/qualified-templates/`에 있습니다. 삭제하면 해시 검사가 중단합니다.

## 게임 회귀·그래픽·실제 오디오

게임 수정은 `scripts/slice_main.gd` 하나입니다. 기존 JSON helper와 세 호출부를 재사용했고,
한국어 tooltip을 기존 `_refresh()` 조건에서 갱신하도록 추가했습니다. 인쇄 설명에는
선택한 도장의 표시된 칸을 반전한다는 원래 조건을 포함했습니다. 퍼즐·데이터·단축키·
버튼 라벨·레이아웃·애니메이션·오디오 함수·기존 테스트는 변경하지 않았습니다.

최종 task_2와 검증된 task_1 복사본의 전체 QA는 **176게이트 모두 통과**했습니다.
이 최종 검사에서 `game-original`은 현재 task_2, `game-previous-candidate`는 현재 task_1이며,
과거에 차단된 005228 후보를 뜻하지 않습니다.

- 기존 SMOKE 149,083, REGRESSION 98,689, SLICE 277 확인 항목 통과.
- MECH 367,008 확인 항목·8,000 시퀀스, OFFLINE 8,000 참조 사례 통과.
- PROGRESS 74, QUALITY 155(화면 2종 × 폰트 3종), 설정·저장 보존 추가 67 확인 항목 통과.
- 기존 tooltip 상태 전이 184 확인 항목 통과. 실제 표시·문구·경계는 **51개 팝업**으로 확인.
- 1280×720·1920×1080, 100%·125%·150% 폰트, 활성·비활성·완료·되돌리기·로드·초기화 상태 확인.
- 실제 OpenGL 3.3 / AMD Radeon RX 6800와 WASAPI 활성화 확인.
- 인쇄·되돌리기·완료 SFX의 9개 믹서 측정(초기/음소거 해제/볼륨 0 복원) 통과.

이는 실제 장치와 비무음 믹서 출력을 검사한 결과입니다. 물리적인 스피커 청취,
주관적 클리핑·재미·학습 곡선·최종 한국어 가독성의 사람 검수는 미수행입니다.

## 실제 자율 개발 E2E와 재개 수정

실제 native Codex CLI의 JSON 이벤트·완료 응답·프로세스 종료·로그 SHA를 기록했습니다.
모형 fixture의 성공을 실제 E2E로 간주하지 않았습니다.

| 작업 | 현재 run | 시도 번호 | 현재 QA | 자동 커밋·원격 백업 |
|---|---|---:|---:|---|
| task_1 JSON/기존 오디오 보존 | `20261017-140743-d9663` | 2 | 71/71 | `d361c2acb554499b38c61f9f4cb39d4366d24418` VERIFIED |
| task_2 문맥 tooltip·문구 보완 | `20261017-144004-16537` | 2 | 72/72 | `3b921c763b79b092db95fc251f7a76720f13f04c` VERIFIED |

첫 task_2 커밋 `4f7d0f9098a394f1e6c7444249d99bdb6c24abef`와 run `20261017-142954-f8e79`도 보존했습니다.
독립 문구 검사에서 원래 반전 설명 누락을 발견해 task_2만 보완했습니다. task_1은 다시 구현하지 않았습니다.

해결한 하네스 재개 문제는 다음과 같습니다.

1. 제한된 구현 프로세스의 Godot 223회가 인증서 저장소 읽기 ERROR를 냈습니다.
   **223회 모두 실패로 유지**했고 독립 감사도 인증서 ERROR 223·다른 ERROR 0·오디오 누수 0을 확인했습니다.
   권한을 넓히거나 인증서 검사를 끄지 않았습니다. 모델은 `code_ready`와 검증 대기를 보고하고,
   기존 신뢰 QA 실행기가 실제 게임·Windows 검증을 수행하도록 역할을 명시했습니다.
2. 신뢰된 IMPORT가 재생성한 `.import`를 모델 범위 위반으로 잘못 취급하던 문제를 수정했습니다.
   생성 전후 해시와 실행 로그를 연결하고, 이후 모델의 메타데이터 변경은 계속 거부합니다.
   생성 메타데이터는 게임 원본에 복사하지 않습니다.
3. 검증되지 않은 모델 수용 조건은 표준 QA만으로 통합할 수 없도록 차단을 유지·보강했습니다.
   추가 설정·힌트 보존 검사와 WASAPI 30 + Dummy 30 독립 프로세스를 필수로 실행합니다.
4. 에디터 최초 IMPORT 종료에서 별도 singleton/Thread 오류가 나타난 이력도 보존했습니다.
   스크립트 오류와 구분해 같은 코드를 한 번만 재검증하며, 재실패하면 중단합니다.
   Godot의 모든 에디터 종료 경로를 수정했다고 주장하지 않습니다. 대기 시간이나 오류 필터를 늘리지 않았습니다.
5. 코드·정책·브랜치 보존을 확인하는 명시적 infrastructure 재조정 이력을 남겼습니다.
   게임 변경·임의 정책 변경·알 수 없는 파일 변경은 거부합니다. 이전 HEAD와 실패 기록을 유지합니다.

재개 관련 회귀는 autonomous 24(23 통과·1 symlink 권한 skip), transaction 6, engine profile 5,
Windows 자식 종료 1, 새 재개 안전성 8건 통과입니다. 새 fixture 작성 중 실패도 로그로 남겼습니다.
이전에 완료한 기존 하네스 111건은 Windows 100 통과·11 Linux 전용 skip, WSL 111 통과였습니다.
관련 없는 완료 검사를 불필요하게 다시 시작하지 않았습니다.

## 구조·실행·복구·백업

기존 `.autodev/auto.py`와 `autonomous.py`, `policy.json`, checks, state, runs 구조를 유지했습니다.
`audio_lab/`은 원인 분리·엔진 비교·독립 감사 도구이며 `engine_patch/`는 패치와 빌드 recipe입니다.
기존 게임, 이전 review run, SQLite, 실패 후보, Git 기록을 보존했습니다.

실제로 사용한 실행 계열은 다음과 같습니다. 새 계획 생성에는 깨끗한 승인 개발 브랜치가 필요합니다.
현재 원래 보고서의 사용자 미커밋 수정 1건은 보존돼 있으므로 임의로 커밋하거나 되돌리지 않습니다.

```powershell
..venvScriptspython.exe .autodev/autonomous.py status
..venvScriptspython.exe .autodev/autonomous.py goal "기존 C01의 작은 개선 목표"
..venvScriptspython.exe .autodev/autonomous.py plan
..venvScriptspython.exe .autodev/autonomous.py run --autonomous --push
..venvScriptspython.exe .autodev/autonomous.py pause
..venvScriptspython.exe .autodev/autonomous.py resume --autonomous --push
```

`qa --run-id RUN`은 기존 후보를 검증합니다. 모델·독립 수용 조건 차단이 남으면 통합하지 않습니다.
`reconcile-infrastructure --run-id RUN`은 이번에 허용한 제한적 인프라 변경과 동일 게임 스냅샷만
명시적으로 재조정합니다. 임의의 HEAD 이동·정책 변경을 승인하는 기능이 아닙니다.
작업별 `latest-report.json`의 보수적인 `ready=false`는 전체 인증을 자동 추정하지 않는 값입니다.
이번 전체 기술 인증은 이 문서와 해시·커밋이 고정된 검증 JSON을 기준으로 합니다.
다음 게임 변경 후에는 해당 변경에 필요한 QA를 새로 통과해야 합니다.

승인 원격은 `origin`의 `codex/autonomous-harness-20261017`이며 강제 push는 하지 않았습니다.
위 자동 개발 커밋은 각각 `ls-remote`의 동일 SHA까지 확인했습니다.
안정 브랜치 `c01-stable-slice-20261013`은 `83294f2eb49d261bce020e45985eb40983ace229`로 유지했습니다.
최종 문서 커밋의 동기화·자체 작업 종료 감사는 로컬 `.data/engine-build-20261017/finish-audit.json`에 저장합니다.

GitHub에는 검증된 코드·엔진 패치·recipe·보고서·검증 JSON을 저장합니다.
대용량 바이너리·전체 원본 로그·개인 경로가 포함된 자료는 `.data/engine-build-20261017/`에 보존하며
GitHub에 백업됐다고 주장하지 않습니다. 설치 Godot/template, 안정 브랜치, 사용자 미커밋 수정은 보존했습니다.
공개 출시·Steam 게시·유료 서비스 변경·PC 종료는 수행하지 않았습니다.
