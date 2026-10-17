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
