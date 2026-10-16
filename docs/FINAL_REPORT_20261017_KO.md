# 자율 게임 개발 하네스 구현·QA 결과

작성일: 2026-10-17, Asia/Seoul. 최종 판정: **INCOMPLETE / AUTONOMOUS_HARNESS_READY 아님**.
하네스 코드는 구현하고 독립 검사를 통과했으나, 실제 게임의 강화 오디오 검사와
두 작업 연속 End-to-End 인증은 완료하지 못했습니다. **Windows 종료 명령은 실행하지 않았습니다.**

## 보존한 기준선

- 시작 브랜치: `c01-stable-slice-20261013`, HEAD `83294f2eb49d261bce020e45985eb40983ace229`.
- origin의 안정 브랜치도 같은 커밋임을 `git ls-remote`로 확인했습니다.
- 작업 브랜치: `codex/autonomous-harness-20261017`. 안정 브랜치 참조와 기존 게임 파일은 변경하지 않았습니다.
- 원래 미추적이던 `.autodev` 코드·작업 명세와 Taskfile을 검토해 버전 관리에 넣었습니다.
  기존 run, 빌드, 로그, worktree, SQLite, 가상환경, 사용자 저장 데이터는 삭제하지 않았습니다.
- 수정 전 하네스·설정 복사본: `.data/harness-upgrade-20261017/`.
- `ui_hierarchy_01`의 기존 run `20261014-013323-606cc`는 계속 `review`입니다. 자동 승인·폐기하지 않았습니다.
- 추가 안전 보강용 `.data/harness-safety-worktree`와 `codex/harness-safety-20261017`도 보존했습니다.

## 구현한 구조와 기능

기존 `.autodev/auto.py`를 진입점으로 유지하고 `.autodev/autonomous.py`를 추가했습니다.
Python 표준 라이브러리와 기존 `.venv`, Git, Godot, 현재 로그인된 Codex CLI를 사용하며
의존성을 설치하거나 인증·권한 설정을 변경하지 않았습니다.

1. 자연어 목표 등록, 읽기 전용 Codex 분석, 작업 자동 분해와 명세 생성.
2. 정확한 허용 파일 목록, 보호 경로, 의존성·순환 검사와 실행 가능한 다음 작업 선정.
3. 원본 게임의 해시를 기록한 복사본에서 실제 Codex 구현. 소스 변경과 모델 완료 이벤트를 별도 검사.
4. 설치된 CLI 도움말을 검사하고 JSON 이벤트, 마지막 응답, PID, 종료 코드와 로그를 기록.
   현재 버전은 구조화된 구현 결과에 미검증 수용 기준이 있으면 차단합니다.
5. 기본 최대 3회 수정, 동일 실패 반복 시 조기 차단, 환경 장애의 제한된 재검증.
   실제 발견한 IMPORT 접근 위반 종료 코드를 환경 오류로 분류하도록 보강했습니다.
6. 정적 검사, IMPORT, Smoke, Regression, SLICE, 오프라인 퍼즐 검사, 보충 품질 QA,
   Windows export와 실제 EXE 시작·종료 검사. exit=0이어도 ERROR·누수 로그가 있으면 실패합니다.
7. 등록된 기능 수용 probe(`context_tooltips`)와 독립 검사 차단 사유를 통합 전에 강제 검사.
8. 원본 HEAD·소스·검증된 스냅샷·빌드 해시 재확인, 파일별 백업, 지정 파일만 스테이징·커밋.
9. 복사/커밋 저널, 커밋 직후 중단 인식, 백업 실패 후 재커밋 없는 재개, 지정 개발 ref만 push 및 원격 HEAD 검증.
10. 원자적 JSON 체크포인트, 중복 실행 lock, 살아 있는 이전 자식 확인, 협조적 pause/resume,
    미완료 계획을 명시적으로 보관하는 목표 전환, 상태·보고서·QA 재실행 명령.

주요 파일: `.autodev/autonomous.py`, `auto.py`, `policy.json`, `config.example.json`,
`checks/quality_probe.gd`, `checks/context_tooltips.gd`, `tests/test_autonomous.py`,
`tests/test_transactions.py`, `autodev.ps1`, `Taskfile.autodev.yml`.
기존 `harness.py`의 Windows 콘솔 출력 인코딩 오류도 수정했습니다.
설정·로그·run·상태·빌드는 Git에서 제외하며, 개인 경로를 포함하는 기존 로컬 설정은 커밋하지 않았습니다.

## 실제 실행한 테스트

| 검사 | 실제 결과 | 증거 |
|---|---|---|
| 기존 하네스, Windows | 111건 실행, 100 통과·11 Linux 전용 skip | `.data/harness-upgrade-20261017/final-legacy-windows.log` |
| 기존 하네스, WSL | 111건 모두 통과 | `legacy-wsl.log` |
| 새 오케스트레이터 독립 검사 | 24건 실행, 23 통과·1 symlink 권한 skip | `final-autonomous-tests.log` |
| 추가 트랜잭션 장애 검사 | 6건 모두 통과, Windows junction 차단 포함 | `final-transaction-tests.log` |
| 기존 AutoDev 모의 pipeline, WSL | 2건 통과 | `final-pipeline-wsl.log` |
| 기존 모의 WSL worker | 1건 통과 | `final-worker-wsl.log` |
| Python 구문 검사 | 통과 | `py_compile` 실제 실행 |
| 기준선 Godot QA | IMPORT·Smoke·Regression·SLICE 통과 | `.autodev/runs/20261017-004302-8984b/logs/` |
| 기존 추가 게임 검사 | MECH 367,008 checks / 8,000 sequences, 실패 0; 진행 안내 74 checks 통과 | `.data/harness-upgrade-20261017/legacy-extra/` |
| 기준선 Windows 빌드 | export, EXE/PCK 해시, 실제 시작·정상 종료 통과 | 기준선 run의 `release/`, `logs/build-run.log` |
| 화면 캡처 | 2개 해상도 × 3개 글자 크기, PNG 6장 저장 | `.data/harness-upgrade-20261017/visual-before/` |

위 표에서 파일명만 적힌 로그는 `.data/harness-upgrade-20261017/` 아래에 있습니다.
모의 provider 검사는 실제 Godot나 실제 Codex 성공을 뜻하지 않습니다. 실제 임시 Git과
실제 하위 프로세스 검사도 포함하지만, 실제 PC 재부팅·네트워크 장애·프로세스 강제 종료를
모두 재현한 것은 아닙니다. 건너뛴 symlink 검사를 통과로 계산하지 않았습니다.

## 실제 End-to-End 시도와 실패

실제 Codex CLI `0.162.1`, Godot `4.7.1.stable.official.a13da4feb`를 확인했습니다.
실제 읽기 전용 계획 run은 `20261017-005027-815f9`이며 두 작업을 생성했습니다.

- `task_1`: 손상 JSON 처리와 빠른 SFX 재생·즉시 종료 시 누수 수정.
- `task_2`: task_1 이후 상태에 맞는 한국어 버튼 툴팁 추가.

`task_1`의 실제 Codex run은 `20261017-005228-b1610`입니다. Codex가
`scripts/slice_main.gd`를 실제 수정했으며, 변경은 이 run 안에만 보존했습니다.
최초 통합 QA의 IMPORT가 종료 코드 `3221225477`로 중단되었습니다. 같은 소스의 제한된
독립 재실행은 통과했고, 이후 전체 일반 QA도 통과했습니다.

일반 QA 재실행의 실제 결과는 STATIC, IMPORT, SMOKE, REGRESSION, SLICE(277 checks),
OFFLINE(8,000 cases), QUALITY(155 checks, 2×3 배치), EXPORT, BUILD_RUN 모두 통과입니다.
수정 후보의 Windows EXE/PCK도 생성해 실제 시작·정상 종료를 확인했습니다.
산출물은 해당 run의 `release/`에 있으며 **미승인 검토용 후보**입니다.

그러나 별도 독립 WASAPI 즉시 종료 검사는 **5회 중 3회 실패**했습니다.
모든 프로세스 종료 코드는 0이었지만 AudioStreamWAV/AudioStreamPlaybackWAV 누수가 있었습니다.
실패한 실행의 WAV/Playback 객체 수는 각각 3/33, 3/12, 3/9입니다.
증거는 run의 `logs/independent-immediate-0.log`부터 `-4.log`, `logs/result.json`입니다.
일반 QA 통과를 전체 수용 성공으로 바꾸지 않았고, `acceptance_blockers`에 이 실패를 기록했습니다.

따라서 task_1은 BLOCKED, task_2는 PENDING이며 **실제 연속 두 작업의 통합·커밋·push 인증은 미완료**입니다.
실패한 게임 변경을 개발 브랜치에 넣지 않았습니다. 오디오 누수의 엔진 내부 원인은 확정하지
않았습니다. 비슷한 종료 누수의 [Godot 공식 이슈](https://github.com/godotengine/godot/issues/95484)가
있지만 현재 버전의 원인 증명을 대신하지 않습니다. 엔진 설치·교체·패치나 검사 완화는 하지 않았습니다.

최종 하네스의 구조화된 모델 결과 계약과 추가 안전 보강은 독립 모의 검사로 검증했습니다.
이 최종 버전으로 실제 연속 개발 성공을 다시 인증한 것은 아닙니다.

## 증거 보존 과정에서 수정한 문제

명시적 QA 재실행이 동일한 `attempt-1-IMPORT.log` 이름을 재사용하는 문제를 발견했습니다.
이번에 생성한 최초 IMPORT 원본 로그는 덮어써졌습니다. 원래 종료 코드·기록된 해시·실패 내용은
`autonomous.json`의 process/failure 기록에 남아 있습니다. 그 내용에서 복원한 발췌는
`logs/recovered-initial-import-failure.txt`이며 원본 raw 로그로 가장하지 않았습니다.
현재 코드는 매 실행마다 고유한 로그 경로를 선택하고 배타적으로 파일을 생성합니다.
이전 로그가 유지되는 회귀 검사를 추가해 통과했습니다. 기존 사용자 run 로그는 수정하지 않았습니다.

## Git 커밋과 원격 백업

주요 구현 커밋은 `b877825`, 재개·빌드 무결성 보강 `7b668c6`, 수용 probe `1f9e34d`,
구조화된 결과 `59047fb`, 계획 보존·엔진 종료 코드 분류 `f10ee30`, 독립 실패 통합 차단
`e0c69f0`, QA 상태/저널 보강 `0d0ecf2`, 로그 보존 수정 `75d3750`입니다.
보고서 저장 후 현재 개발 브랜치의 최종 HEAD를 정책상 origin에 일반 push하고
`ls-remote`의 정확한 SHA 일치를 확인합니다. 최종 커밋과 실제 백업 결과는
`.data/harness-upgrade-20261017/finalization.json`에 기록합니다.
로컬 run·로그·빌드와 SQLite는 GitHub 백업 대상에서 제외됩니다.

## 실행·복구 방법

기본 명령은 [실행 안내](AUTONOMOUS_HARNESS_KO.md)에 있습니다.

```powershell
.\autodev.ps1 status
.\autodev.ps1 report
.\autodev.ps1 qa --run-id 20261017-005228-b1610
.\autodev.ps1 pause
.\autodev.ps1 resume --push
```

현재 run에는 독립 수용 실패가 남아 있어 QA 재실행만으로 통합 승인이 되지 않습니다.
하네스 보강으로 HEAD도 바뀌었으므로 과거 run의 직접 통합은 원본 커밋 검사를 통과하지 못합니다.
기준 커밋 검사를 우회하지 말고 원인을 해결한 뒤 새 기준선으로 다시 계획·검증해야 합니다.
비활성 계획을 보존하고 다른 목표로 전환할 때는 다음 명령을 사용합니다.

```powershell
.\autodev.ps1 goal "검토한 새 목표" --replace-incomplete
.\autodev.ps1 plan
.\autodev.ps1 run --autonomous --push
```

현재 실패 후보와 기존 계획은 보존합니다. 안정 브랜치 병합이나 게임 방향 변경 승인은 포함되지 않습니다.

## 남은 작업과 PC 종료 판단

- 실제 Windows 오디오 즉시 종료 누수 해결과 반복 재검증.
- 최종 하네스로 두 개 이상 실제 게임 작업의 연속 통합·커밋·GitHub 백업 인증.
- 일반 자연어 수용 기준 전체를 자동 판정하는 기능은 없음. 등록된 probe 밖의 기준은 사람 검수 필요.
- 전체 텍스트 겹침, 스크롤 사용감, 실제 효과음 청취·클리핑, 재미·학습 곡선은 검증 완료가 아님.
- 최종 검사에서 worker lock과 run 자식 PID는 없었고, 프로젝트 경로가 포함된 개발 프로세스가
  WMI 조회에 남아 있지 않았습니다. 전역 앱의 미저장 사용자 작업은 확인할 수 없습니다.
- 실제 E2E 미완료, 알려진 QA 실패, 미저장 작업 확인 불가 때문에 `shutdown.exe /s /t 0`은 실행하지 않았습니다.

결제·설치·출시·공개 배포·강제 push·기존 데이터 삭제는 하지 않았습니다.
