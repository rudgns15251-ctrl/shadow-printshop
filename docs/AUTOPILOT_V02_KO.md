# Game Harness v0.2 — 운영 설명서

이 버전은 **기존 v0.1을 변경하지 않고** `autopilot.py` 단일 실행 관리자를 추가합니다.
`PLAN-001`, `PLAN-002`, 상태 DB, 기존 Git 커밋과 worktree를 보존합니다.

## 실행

프로젝트 루트에서 PowerShell을 열고:

```powershell
.\.venv\Scripts\python.exe autopilot.py plan
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

`plan`은 실행 가능한 작업을 미리 보여줍니다. 현재 PLAN-002까지 승인됐다면 **아직 등록된 다음 작업이 없으므로** 실행 대상이 없을 수 있습니다.

신규 작업을 등록하고 커밋한 이후에만 실사용 예시:

```powershell
.\.venv\Scripts\python.exe autopilot.py run --live --max-tasks 2 --minutes 45 --max-retries 1
```

## 동작 및 안전장치

- 우선순위와 의존성을 고려해 pending 작업을 차례로 실행
- 하나의 워커만 허용하도록 잠금파일 사용
- 작업당 소프트 타임아웃 및 전역 작업 수·시간 제한. 이미 시작한 작업은 기존 하네스의 종료를 기다리며 강제로 분리하지 않음
- 로컬 로그 `logs/autopilot/` 기록과 30초 단위 진행 알림
- 프로세스가 정상 종료되고 변경 파일이 없는 일부 실패만 최대 1회 자동 재시도
- 의심스러운 작업·남은 running 상태는 **자동 복구하지 않고 중단**
- 기존 하네스의 파일 범위·필수 결과물 검사 유지
- 작업이 `review`에 도달해도 자동 승인하거나 Git에 합치지 않음
- 웹 시장 조사, 코드 리뷰, 완성 게임 자동 생성, 비용의 실제 금액 모니터링은 미구현

## 중단/오류 대응

- `running`: 먼저 관련 Python/Codex 프로세스와 작업 공간을 확인. 함부로 재실행·삭제하지 않음
- `review`: 사람이 결과 검토 후 `harness.py approve TASK-ID`로 반영
- `blocked`: `harness.py inspect TASK-ID`와 로그 확인. 변경물이 있을 수 있으므로 자동 삭제 금지
- 오래된 `.data/autopilot.lock`: 프로세스 ID가 더 이상 실행 중이지 않다는 사실을 확인하기 전까지 삭제 금지

## 제한 사항

기존 `harness.py`는 Codex JSON 출력을 900초까지 모았다가 파일에 기록합니다. `autopilot.py`는 실행 중 생존 확인 메시지와 래퍼 로그를 남기지만, **Codex 토큰 단위 실시간 이벤트 스트림을 아직 구현하지 않았습니다.**

기존 CLI의 `run --live` 명령은 항상 새 worktree 생성과 API 사용량을 동반할 수 있습니다. 작업 통과 여부는 자동 검증의 범위에 한정되며 상품성을 보장하지 않습니다.

v0.3 후보: 작업 자동 생성·승인 정책·독립 시장 조사·엔진 테스트·코드 및 그래픽 품질 게이트.
