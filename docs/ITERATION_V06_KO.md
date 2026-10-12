# Game Harness v0.6 — AI 후속 작업 제안 및 승인 게이트

이 버전은 **사전에 작업을 수동 입력하는 방식**에서 한 단계 나아가 Codex가 1~3개의 다음 개발 과제를 제안하고, 검증된 템플릿으로 변환해 사람 승인 후 `tasks/backlog.json`에 등록합니다.

## 범위 및 안전장치

- 이 단계의 C01 게임은 **판매용으로 선정된 게임이 아닌 자동 개발 실험용 프로토타입**입니다. Godot는 이 실험의 엔진일 뿐 추후 게임의 최종 엔진으로 확정되지 않았습니다.
- Codex 제안 시 별도로 생성한 임시 폴더에서 `read-only` 실행을 요청하며, 기존 프로젝트에서 **허용한 세 문서만 발췌해** 전달합니다. 설정 파일, `.data`, 인증 정보, 다른 프로젝트는 기획 입력에 포함하지 않습니다. 다만 OS 수준의 완전한 격리를 보장하지 않으므로 신뢰할 수 없는 명령은 별도 VM에서 실행하세요.
- 기획 결과는 `kind`, `title`, `goal`, `checks`만 받습니다. AI는 작업 ID, 파일 접근 권한, 테스트 보호 목록, 자동 재시도 횟수, Codex 도구 권한을 지정할 수 없습니다.
- **반드시 사용자가 출력된 SHA256 digest에 동의하고 `stage --digest ... --apply`를 실행해야 작업이 등록됩니다.** 제안만으로는 게임 수정이나 작업 등록이 일어나지 않습니다.
- 등록된 작업은 기존 `autopilot.py`가 실행합니다. `godot_validation`, `qa_validation`, `require_regression`과 수동 승인 검증은 모두 유지합니다.
- 작업은 선형 의존성으로 연결됩니다(`PROTO-002 → ITER-001 → ITER-002 ...`). 각 단계가 `review`가 되면 **자동 Git 병합하지 않으므로**, 사용자 승인 후 다음 단계가 진행됩니다. 이 버전은 아직 완전 무인/상업 출시용 파이프라인이 아닙니다.
- 통과한 회귀 테스트는 **실제 기능의 모든 정확성·재미·시장성**을 검증하지 않습니다. 자동 생성된 새 테스트는 독립 검증이 아닙니다.
- 동일 프로젝트에 대해 다른 Codex 세션이 동시 수정하지 않도록 하세요. 단일 워커 lock과 Git 상태 확인은 기본 보호장치이며 악성 프로세스 격리는 아닙니다.

## 설치

1. `PROTO-002 completed` 확인 및 작업 디렉터리 `git status --short`가 깨끗한지 확인
2. ZIP의 `install_v06.py`, `v06_files`를 기존 `harness.py` 옆에 압축 해제
3. 현재 PowerShell에서 `\.venv\Scripts\python.exe install_v06.py` 실행
4. 로컬 테스트 통과 확인 후 새 파일 3개만 `git add`와 `git commit`
5. 설치용 `install_v06.py`, `v06_files`를 `.data/` 아래로 이동하여 Git 상태를 깨끗하게 유지

## 사용

```powershell
.\.venv\Scripts\python.exe iteration_planner.py propose
# Dry run: Codex 사용 없음
.\.venv\Scripts\python.exe iteration_planner.py propose --live
# Codex 사용량이 발생할 수 있음. JSON 제안만 .data 안에 저장됨.
.\.venv\Scripts\python.exe iteration_planner.py review
# 출력된 계획·digest를 꼼꼼히 확인
.\.venv\Scripts\python.exe iteration_planner.py stage --digest <SHA256> --apply
# 승인 후 backlog.json에 작업 1~3개 등록

git add tasks/backlog.json
git commit -m "Stage reviewed iteration plan v0.6"
.\.venv\Scripts\python.exe autopilot.py plan
.\.venv\Scripts\python.exe autopilot.py run --live --max-tasks 1 --minutes 45
```

## 검증과 운영상의 한계

- AI가 응답한 JSON을 엄격하게 검증하지만 **의미적으로 좋은 작업이라는 보장은 없습니다.** 실행 전 내용을 사람이 확인해야 합니다.
- Codex CLI가 `--output-last-message` 또는 read-only 권한 관련 오류를 반환하면 Codex CLI 버전과 현재 옵션을 확인하세요. 제안 실패 시 작업 명세는 변경되지 않습니다.
- 현재 `game_harness v0.5.1`의 Godot 테스트는 전체 사람 경험을 대체할 수 없습니다. 특히 판매용 게임의 기획·엔진·시장성 승인과 Steam 공개는 별도 사용자 결정입니다.
- 계획 생성 결과를 수정하려면 `.data/iteration_planner/proposal.json`을 임의로 고치기보다 재검토 후 승인하지 않고 새 제안을 생성하세요. 원본 계획 파일을 폐기하기 전에 별도 백업이 필요합니다.
