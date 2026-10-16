# C01 자율 개발 실행 안내

기존 `.autodev/auto.py`에 디스크 상태 기반 오케스트레이터를 추가했습니다.
기존 `doctor`, `run --task`, `accept`는 호환용으로 유지합니다. 새 자율 실행은
원본 게임을 복사한 스냅샷에서 작업하고, 전체 QA 후 개발 브랜치에 명시한 파일만 커밋합니다.

## 실행

프로젝트 루트 PowerShell에서 실행합니다. 기존 `.venv`를 사용하며 설치는 하지 않습니다.
짧은 진입점 `./autodev.ps1 plan`, `./autodev.ps1 run --autonomous --push`도 제공합니다.
로컬 `.autodev/config.json`은 유지하고 Git에서는 제외합니다. 다른 PC에서는
`config.example.json`을 참고해 Godot 실행 경로를 지정합니다. 자율 경로는 Windows의
네이티브 Codex CLI를 사용합니다. 기존 단일 작업의 WSL 경로는 유지합니다.

```powershell
.\.venv\Scripts\python.exe .autodev/auto.py goal "기존 게임을 보존하면서 작고 검증 가능한 개선 목표"
.\.venv\Scripts\python.exe .autodev/auto.py plan
.\.venv\Scripts\python.exe .autodev/auto.py run --autonomous --push
.\.venv\Scripts\python.exe .autodev/auto.py status
.\.venv\Scripts\python.exe .autodev/auto.py pause
.\.venv\Scripts\python.exe .autodev/auto.py resume --push
.\.venv\Scripts\python.exe .autodev/auto.py report
.\.venv\Scripts\python.exe .autodev/auto.py qa --run-id RUN_ID
.\.venv\Scripts\python.exe .autodev/auto.py backup
```

`plan`과 실제 구현은 현재 인증된 CLI를 호출합니다. 무한 반복하지 않으며 정책의 최대
작업 수와 수정 수를 적용합니다. `--push`는 정책에 지정된 origin의 현재 `codex/`
브랜치 하나만 백업합니다. 안정 브랜치 병합, 배포, 설치, 결제, 강제 push는 하지 않습니다.

## 정책과 검증

`.autodev/policy.json`의 정확한 파일 목록이 작업 범위의 상한입니다. 모델이 생성한
작업은 이 상한을 넓힐 수 없습니다. 현재는 기존 UI 스크립트 두 개만 허용합니다.
목표가 이를 벗어나면 정책을 사람이 검토해야 합니다. 테스트와 퍼즐 데이터는 보호합니다.

순서: 정적 범위/위험 호출 검사 → IMPORT → Smoke → Regression → SLICE → Python
오프라인 검증 → 추가 UI/입력/저장/오디오 검사 → Windows export → 실제 EXE 시작·종료.
종료 코드, 필수 성공 마커와 오류/누수 로그를 함께 검사합니다. 통합 시 전체 소스 해시와
HEAD를 재확인합니다. 엔진 코드 실행은 OS 보안 샌드박스를 대신하지 않습니다.
계획기는 등록된 기능 수용 probe를 선택할 수 있습니다. `context_tooltips`는 버튼 툴팁의
초기/인쇄/완료/되돌림/초기화/불러오기/마지막 퍼즐 상태를 검사하며, 지정된 probe가
통과하지 않으면 통합을 거부합니다. 등록된 검사로 관찰할 수 없는 수용 기준은 사람 검수가
필요하다고 명시해야 합니다. 모델의 설명만으로 기능 수용을 증명하지 않습니다.

레이아웃 검사는 1280×720/1920×1080과 글자 크기 100/125/150%를 포함합니다.
스크롤로 접근하는 세로 콘텐츠는 화면 밖에 있다는 이유만으로 실패시키지 않습니다.
자동 검사는 재미, 미적 품질, 실제 청취와 클리핑, 전체 텍스트 겹침에 대한 사람의 검수를
대신하지 않습니다. 작업 고유 수용 기준은 실행 결과와 별도로 검토해야 합니다.

## 중단과 복구

`.autodev/state/plan.json`에 작업/의존성/진행을 저장하고 각 run의 `autonomous.json`에
원본 HEAD, 단계, 시도 횟수, 소스 해시, 프로세스 PID/종료 코드, QA 결과, 실패 원인을
저장합니다. 로그와 마지막 Codex 메시지도 같은 run에 남습니다. 이 자료는 로컬 전용입니다.

`pause`는 현재 자식 프로세스가 끝난 후 안전 지점에서 멈추는 협조적 중단입니다.
강제 종료로 사용하지 마세요. `resume`은 죽은 작업자의 lock을 보존 이름으로 이동하며,
살아 있는 이전 자식이 있으면 거부합니다. 통합 도중 중단되면 복사 전 저널과 검증 해시로
동일 변경만 마저 처리하거나 이미 만들어진 커밋을 인식합니다. 상태가 불명확하면 보존 후
BLOCKED입니다. 원격 백업 실패 후에는 동일 커밋만 다시 push하며 구현을 반복하지 않습니다.

실패한 run, 기존 worktree, SQLite, 사용자 저장 데이터는 자동 정리하지 않습니다.
다른 목표로 전환할 때는 `goal "새 목표" --replace-incomplete`로 비활성 미완료 계획을
명시적으로 보관한 뒤 `plan`을 실행할 수 있습니다. 살아 있는 자식이나 미완료 통합·백업이
있으면 이 전환도 거부합니다. 이전 계획과 run은 보존합니다.
원본 게임이 더러워졌거나 HEAD가 바뀌면 강제 복원하지 말고 결과를 검토하세요.
기존 `ui_hierarchy_01` 검토 대기 결과는 별개로 보존되며 자동 승인하지 않습니다.

## 독립 검사

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\python.exe -m unittest discover -s .autodev/tests -p test_autonomous.py -v
```

기존 Linux 전용 모의 worker/pipeline 검사는 WSL에서 실행합니다. 모의 provider 검사와
실제 Codex/Godot 인증은 별개이며 최종 보고서에 각각 기록합니다. 하네스 자체가 전체
완료를 선언하는 기능은 없습니다. PC 종료도 하네스의 자동 동작에 포함하지 않습니다.
