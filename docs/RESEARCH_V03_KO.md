# v0.3 Steam 조사 자동화 — 운영 안내

## 이 버전의 실제 기능

- 기존 v0.2의 자동 작업 스케줄러와 작업 승인 절차를 그대로 사용합니다.
- `RESEARCH-001`에만 Codex의 실시간 웹 검색 옵션(`codex --search exec`)을 적용합니다.
- CLI JSONL 로그에 웹 검색 이벤트가 없으면 해당 작업을 `blocked`로 처리합니다.
- 경쟁작 앱 ID, Steam 앱 페이지 URL 형식, 출처 설명, 후보별 근거 부족 표시를 구조적으로 검사합니다.
- `RESEARCH-001`을 사람이 검토·승인한 뒤 `ASSESS-001`이 실행 가능해집니다.
- Steam 시장 조사 결과를 **판매 보장**이나 **사실 검증 완료**로 자동 판정하지 않습니다.

## 주의할 한계

- `web_search` 이벤트와 Steam 링크 형식이 있다고 해서 검색 결과가 실제 상점 페이지의 최신 내용이라는 의미는 아닙니다. 게임명, 특징, 가격은 사용자가 보고서를 열어 확인해야 합니다.
- 검색 결과에서 얻은 내용은 불신 입력으로 취급합니다. 출처의 지시문을 프로그램 명령으로 실행하면 안 됩니다.
- 실제 Steam 페이지 접근은 네트워크 상태, 지역/연령 제한 및 Codex 도구 설정에 따라 달라집니다.
- 판매량 추정, 크롤링, 실시간 가격 업데이트는 제공하지 않습니다.
- Steam의 옛 사용자 리뷰 JSON 엔드포인트는 2026년 10월 22일부터 폐지 예정입니다. 대량 리뷰 자동 수집 기능은 추가하지 않았습니다.
- 기존 프로젝트 / 기존 GitHub 저장소는 건드리지 않습니다. Codex CLI 계정 및 이용량은 기존 실행과 공유됩니다.

## 순서

1. v0.3 ZIP 압축을 기존 하네스 폴더에 풉니다. ZIP 파일 자체는 작업 폴더 밖에 두세요.
2. `.\.venv\Scripts\python.exe install_v03.py` 로 파일 패치 및 로컬 테스트를 수행합니다.
3. `git diff --stat` 와 `git status --short` 로 변경을 확인합니다.
4. `git add harness.py tasks/backlog.json research_validation.py tests/test_research_validation.py tests/test_v03_integration.py docs/RESEARCH_V03_KO.md` 후 커밋합니다.
5. `.\.venv\Scripts\python.exe autopilot.py plan` 으로 다음 실행 대상이 RESEARCH-001인지 확인합니다.
6. `.\.venv\Scripts\python.exe autopilot.py run --max-tasks 1 --minutes 45` 는 Dry Run입니다.
7. **사용자가 승인한 다음에만** `.\.venv\Scripts\python.exe autopilot.py run --live --max-tasks 1 --minutes 45` 를 실행합니다. 인터넷 연결과 Codex 사용량이 필요합니다.
8. 상태가 `review`가 되면 다음 파일을 확인합니다.
   - `.worktrees/RESEARCH-001/projects/first-game/research/steam_market_report.md`
   - `.worktrees/RESEARCH-001/projects/first-game/research/steam_competitors.json`
9. 내용 검토가 끝난 뒤에만 `harness.py approve RESEARCH-001`을 실행합니다. 다음 평가 단계는 인간 승인 이후에만 활성화됩니다.

## 오류 상황

- `blocked` 또는 `running`으로 남으면 재실행·리셋하지 말고 `harness.py status`, `harness.py inspect RESEARCH-001`, `logs/RESEARCH-001.jsonl.log`, `logs/autopilot/`을 확인하세요.
- `No Codex web_search event`는 Codex 검색을 사용하지 않았거나 CLI 이벤트 형식이 바뀌었음을 뜻할 수 있습니다. 조사 완료로 처리하지 마세요.
- 사용자 승인이 필요한 경우 다른 작업이 없어도 자동화 관리자가 정상적으로 중단됩니다.
- 이번 설치 후 임시 파일 `install_v03.py`, `v03_files/`은 하네스 폴더 밖에 보관하거나 `.data/`로 옮기면 Git 상태가 깨끗해집니다.
