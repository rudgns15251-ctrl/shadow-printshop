# 음영 인쇄소 지속 제작 실행

프로젝트 루트에서 두 명령으로 사용한다. 기존 프로젝트 가상환경을 사용하며 설치·결제·인증 복사를 하지 않는다.

```powershell
.\game-production.ps1 start
.\game-production.ps1 status
```

`start`는 숨겨진 독립 Python 관리자를 실행한다. 실제 OS 잠금과 PID를 확인한 경우에만 `worker_running: true`로 표시한다. 이 대화/실행 명령이 끝나도 프로세스가 살아 있으면 다음 제작 묶음을 자동으로 선정한다. PC가 꺼지거나 프로세스가 끝나면 제작은 멈춘다. Windows 자동 시작/레지스트리/예약 작업을 설치하지 않는다.

```powershell
.\game-production.ps1 pause
.\game-production.ps1 resume
.\game-production.ps1 recover
.\game-production.ps1 report
```

pause는 현재 코드/QA/검토가 안전한 경계에 도착할 때까지 기다린다. 요청 직후 `pause_requested: true`와 `worker_running: true`가 함께 보일 수 있다. 실제로 멈춘 뒤에는 PAUSED와 false가 기록된다. 실행 중인 자식을 강제 종료하거나 미검증 코드를 통합하지 않는다. 재개는 완료된 QA/검토 체크포인트를 재사용한다. 비정상 종료 시에는 이전 자식이 살아 있는지 확인하고, 불확실하면 중복 실행을 거부한다.

생산 작업은 `.data/production-worktree-20261018`의 `codex/production-20261018` 개발 브랜치에서 수행한다. 기본 작업 폴더의 사용자 수정과 기존 안정/개발 기록은 보존한다. 최신 제품 코드는 생산 작업 환경에 있고, 기본 폴더의 코드가 백그라운드 커밋마다 자동 교체되는 것은 아니다. `status`의 workspace/latest_build/last_verified_commit을 기준으로 본다.

실제 상태/이벤트/로그는 생산 작업 환경의 `.autodev/state/production/`, 모델별 게임/QA/검토 로그는 `.autodev/runs/`, ZIP은 `.data/production-builds/`에 남는다. 사람이 읽을 요약은 `.autodev/state/production/현황_KO.txt`다. 이 자료는 로컬이며 자격 증명과 원시 모델 로그를 GitHub에 게시하지 않는다. 검증된 게임 커밋만 지정 개발 브랜치로 백업하고 원격 SHA를 확인한다.

디렉터는 고정된 9개 제작 기준 문서와 `.autodev/production.json`을 바탕으로 계획/구현/검증/독립 편집/수정/통합/다음 묶음을 연결한다. 모든 작업에 기존 필수 QA와 WASAPI/Dummy 각 30회의 원본 프로브가 유지된다. 새 파일의 메타데이터도 정확한 정책 허용 목록에서만 생성한다. 명시적인 새 검사가 없는 기능은 기존 검사 통과만으로 인증하지 않는다. 스토리 편집은 작성과 별도 read-only Codex 실행에서 이루어진다.

독립 실행은 기존 네이티브 Codex CLI의 인증을 그대로 사용한다. 비대화형 JSONL/구조화 응답/읽기 전용 검토는 [OpenAI 공식 문서](https://learn.chatgpt.com/docs/non-interactive-mode)를 참고했고, 설치된 CLI가 실제 지원하는 옵션을 확인한다. 자격 증명 파일을 읽거나 복사하지 않는다. 사용량/인증 제한은 우회하지 않으며 해당 경우 상태와 로그를 남기고 멈춘다. 논리적으로 독립인 작업의 일반 실패는 다른 준비된 작업을 계속할 수 있지만 Git 통합/백업 불확실성은 전체 작업을 멈춘다.

완료 표시는 실제 캠페인·리소스·QA·Windows 실행 증거를 요구한다. 큐가 비었다는 이유만으로 출시 후보를 선언하지 않는다. 사람의 재미·학습·플레이타임·청취·출시 승인은 자동 인증과 별도다. Steam 게시·공개 출시·PC 종료를 수행하지 않는다.
