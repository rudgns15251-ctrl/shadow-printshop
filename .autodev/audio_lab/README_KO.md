# C01 오디오 수명 원인 분리 실험

기존 게임과 저장 파일을 건드리지 않고 `.data/audio-rootcause-*`에 최소 프로젝트,
원본/이전 수정 후보 복사본, 각 프로세스의 독립 user:// 환경과 원본 로그를 생성합니다.
의존성이나 엔진을 설치하지 않습니다. 현재 로컬 `.autodev/config.json`과 기존 실패 run이 필요합니다.

```powershell
.\.venv\Scripts\python.exe .autodev/audio_lab/runner.py --repeats 5
.\.venv\Scripts\python.exe .autodev/audio_lab/runner.py --run-dir .data/audio-rootcause-RUN --cases ORIGINAL_IMMEDIATE E E_drain H_drain --drivers WASAPI --repeats 30
.\.venv\Scripts\python.exe .autodev/audio_lab/regression.py --run-dir .data/audio-rootcause-RUN
.\.venv\Scripts\python.exe .autodev/audio_lab/verify_evidence.py --run-dir .data/audio-rootcause-RUN
.\.venv\Scripts\python.exe -m unittest discover -s .autodev/tests -p test_audio_lab.py -v
```

`RUN`은 첫 명령이 출력하는 실제 run 디렉터리 이름으로 바꿉니다.
case A는 오디오 없음, B는 로드만, C는 한 WAV 재생 직후 종료,
D는 세 WAV 각 100회 재생 직후 종료, E는 같은 반복 후 stop/null/free,
E_queue는 queue_free 완료 후 종료, F는 자연 재생 완료 후 종료입니다.
두 드라이버를 비교하는 것이 CASE G에 해당합니다. H_quit/H_free는 실제 게임 종료 경로,
H_drain은 게임 복사본에서 참조 소멸을 관찰하는 별도 완화 실험입니다.

E_drain/H_drain은 정해진 시간만 기다리지 않습니다. 생성 시점에 각 playback의 WeakRef만
기록하고, 플레이어 정지·스트림 제거·노드 해제 후 그 참조가 실제 소멸할 때 종료합니다.
2초는 실패 판정을 위한 상한이며 성공 조건은 참조 소멸입니다. 이 경로가 통과하더라도
같은 프레임의 즉시 종료 조건 C/D/E/ORIGINAL_IMMEDIATE가 해결된 것으로 보지 않습니다.
자연 재생 완료나 한 프레임 대기도 원래 즉시 종료 검사의 대체물이 아닙니다.

`original_immediate.gd`는 이전 실패 스크립트와 바이트가 같습니다.
이 스크립트의 판정은 `--verbose`의 실제 WASAPI 장치 활성화 로그를 요구합니다.
다른 probe는 AudioServer가 보고하는 드라이버 이름까지 기록합니다.
`--headless`의 기본 오디오는 Dummy이므로 실제 검사에서는 그 뒤에 WASAPI를 명시합니다.

실패한 시도도 빠짐없이 분모와 결과에 포함합니다. exit=0과 성공 마커가 있어도
ERROR·ObjectDB 누수·리소스 잔류 또는 잘못된 드라이버가 있으면 실패입니다.
실패가 하나라도 있으면 runner는 종료 코드 2를 반환합니다. 이는 통제 실험에서 실패가
예상됐다는 이유로 QA 성공으로 바뀌지 않습니다. 로그는 배타적으로 생성하며 덮어쓰지 않습니다.

독립 감사기는 runner의 판정 함수를 사용하지 않고 원본 로그 해시, 드라이버, 완료 마커,
오류·누수 진단을 다시 검사합니다. 감사 자료의 일관성이 통과해도 오디오 문제가 해결됐다는
뜻이 아닙니다. 전체 완료는 수정된 엔진/게임의 동일 조건 재검증이 필요합니다.

검토용 엔진 패치와 미검증 범위는 [engine_patch/README_KO.md](engine_patch/README_KO.md)에 있습니다.

## 별도 Windows 엔진 비교

`engine_validation.py --engine ENGINE --run-dir .data/NEW_RUN --phase control --repeats 5`로
명시한 엔진의 새 증거 디렉터리를 준비합니다. 같은 경로에 `--phase stress --repeats 30`,
`--phase original --repeats 30`을 실행하면 기존 probe를 수정하지 않고 570회 전체를 기록합니다.
엔진이나 probe 해시가 바뀌면 이전 증거에 덧붙이지 않습니다.
독립 감사는 기존 `verify_evidence.py`를 그대로 사용합니다.

`engine_regression.py`는 `--engine`, `--run-dir`, `--template-debug`, `--template-release`를
명시해 기존 게임 QA와 export를 수행합니다. `--label`은 이전 실패를 보존하는 별도 실행 이름이며
이미 있는 보고서나 빌드 디렉터리를 덮어쓰지 않습니다. 기본값은 export당 독립 프로세스 30회입니다.
일반 게임 EXE의 기본 장면 실행과 별도 QA pack의 즉시 종료·그래픽 재생을 구분합니다.
기본 template의 CLI 경로 제한을 유지하기 위해 QA pack의 main loop만 원본 probe를 상속합니다.
원본 probe의 바이트·누수 판정 기준·게임 원본·기존 acceptance 테스트는 변경하지 않습니다.
추가 `playback_verification.gd`는 실제 WASAPI와 9개 SFX 믹서 peak를 측정합니다.
물리적인 스피커 청취나 주관적 클리핑 평가는 별도입니다.

실제 시행 결과와 중간 실패 원인은 [Windows 검증 보고서](../../docs/AUDIO_ENGINE_WINDOWS_20261017_KO.md)에 기록합니다.

## 최종 인증과 실제 팝업 검사

C01의 지정 Windows 엔진·template·최종 게임 QA·두 작업 E2E 인증은 완료됐습니다.
결과·고정 SHA·제한 환경의 223회 실패·에디터 IMPORT 실패·문구 보완 이력을
[최종 검증 JSON](../../docs/AUDIO_ENGINE_WINDOWS_20261017.json)에 함께 보존합니다.
개별 감사기의 제한된 범위 결과와 전체 통합 인증은 구분합니다.

`tooltip_visibility.gd`는 검증 복사본의 실제 팝업을 viewport 입력으로 확인합니다.
운영체제 마우스 포인터는 이동하지 않습니다. 그래픽 모드, WASAPI, 격리된 user:// 환경,
기존 이미지 출력 폴더를 준비한 뒤 `--script`의 절대 경로와 `-- output=절대폴더`를 사용합니다.
51개 팝업·화면 2종·폰트 3종의 실제 Label·경계·PNG를 기록합니다.
최종 별도 감사는 초기 인쇄 문구의 도장·반전 설명도 확인했습니다.
물리 청취·재미·주관적 가독성은 사람 검수이며 자동 통과로 기록하지 않습니다.

Windows worktree에서도 원래 두 probe와 엔진 patch의 바이트를 유지하도록 LF를 고정했습니다.
기존 `.autodev/config.json`은 검증된 별도 엔진과 SHA가 고정된 `.data` template만 사용합니다.
설치 Godot/template을 교체하지 않았으므로 원래 설치본으로 실행한 결과와 혼동하지 않습니다.
