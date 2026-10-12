# Harness v0.4 — Godot prototype execution gate

## 목적

- 기존 v0.3 시장 조사 및 평가 문서는 그대로 보존한다.
- PROTO-001에서 C01을 **검증용 프로토타입**으로만 제작한다. 최종 상업 게임으로 확정하지 않는다.
- 생성 코드가 있는지만 보지 않고 Godot 4.x를 사용해 실제 헤드리스 엔진 테스트를 수행한다.

## 필요한 것

- Windows용 공식 Godot Engine 4.x 표준 에디터 (GDScript 사용). 에디터 압축 해제 후 exe 경로 등록.
- Godot가 없거나 경로가 확인되지 않으면 실제 작업은 시작하지 않는다.
- 빌드 내보내기(export templates) 및 Steam 출시 기능은 이번 v0.4 범위 밖이다.

## 명령어

```powershell
.\.venv\Scripts\python.exe engine_adapter.py doctor
.\.venv\Scripts\python.exe engine_adapter.py configure "C:\full\path\to\Godot_v4.x-stable_win64.exe"
.\.venv\Scripts\python.exe autopilot.py plan
.\.venv\Scripts\python.exe autopilot.py run --max-tasks 1 --minutes 45
.\.venv\Scripts\python.exe autopilot.py run --live --max-tasks 1 --minutes 45
```

실제 Codex는 `--live`에서만 실행한다. 프로토타입은 worktree에서 생성되며 검사 통과 후에도 자동 Git 병합되지 않는다. `harness.py inspect PROTO-001` 및 직접 플레이 후 사람이 승인한다.

## 검증의 한계

`engine_adapter.py`는 Godot 버전, 필수 파일, 기본 위험 패턴 및 headless import/테스트/시작을 검사한다. 이는 **보안 샌드박스가 아니다**. Godot를 이용해 Codex가 만든 GDScript를 실행하면 해당 사용자 권한으로 코드가 수행될 수 있다. 중요한 데이터가 없는 비관리자 개발용 환경 또는 별도 VM에서 실행을 권장한다. 네트워크/파일 권한 통제가 필요한 경우 OS 수준의 격리가 필요하다.

Codex가 함께 만든 smoke_test.gd는 자기검증이다. 기능의 정확성·조작감·재미·상업성은 별도 테스트와 사용자 확인이 필요하다.
