# CLAUDE.md — 음영 인쇄소 (C01 Shadow Printshop) 제작 인수인계

Claude Code가 2026-10-21 Codex로부터 제작 책임을 인수했다. 새 세션은 이 문서와 `AGENTS.md`를 먼저 읽고,
실제 상태는 아래 명령으로 확인한다. 이 문서는 운영 규칙이며 게임 설계 기준은 9개 바이블이다.

## 위치와 기준

- 실제 제작 작업 공간: `C:\Users\newsj\Downloads\game-harness-starter-v0.1\.data\production-worktree-20261018`
  (브랜치 `codex/production-20261018`, 원격 `origin` = github.com/rudgns15251-ctrl/shadow-printshop).
  기본 폴더(`game-harness-starter-v0.1`, 브랜치 `codex/autonomous-harness-20261017`)에는 사용자 미커밋 수정이 있다. 건드리지 않는다.
- 안정 브랜치 `c01-stable-slice-20261013`(83294f2)은 디렉터가 고정 확인한다. 직접 통합·강제 푸시 금지.
- 게임: `projects/first-game/game` (Godot 4.7.1 패치 엔진 `.data/engine-build-20261017/binaries/patched/`, 고정 템플릿
  `.data/qualified-templates/`). 제품 시작 장면은 `campaign_main.tscn`.
- 설계 기준(우선): `GAME_VISION.md`, `GAME_DESIGN_BIBLE.md`, `NARRATIVE_BIBLE.md`, `CHARACTER_BIBLE.md`, `ART_STYLE_BIBLE.md`,
  `AUDIO_STYLE_BIBLE.md`, `CONTENT_ROADMAP.md`, `QUALITY_CRITERIA.md`, `RELEASE_CHECKLIST.md`. 다른 프로젝트 설정을 섞지 않는다.
- Python: 기본 폴더의 `.venv\Scripts\python.exe`만 사용한다(설치 금지).

## 상태 확인

```powershell
# 기본 폴더에서 (생산 작업 공간으로 자동 전달)
.\game-production.ps1 status
```
`.autodev/state/production/현황_KO.txt`, `report.json`, `.autodev/state/plan.json`, `.autodev/runs/<run>/autonomous.json`이 기준이다.
보고서와 코드가 다르면 Git·실행 증거·해시를 우선한다.

## 모델 실행기 (Codex → Claude)

- 모든 모델 호출(계획·작성·독립 검토)은 `autonomous.codex()` 한 곳을 지난다. `.autodev/config.json`(로컬, 비추적)의
  `"model_cli": "claude"`이면 `autonomous.claude()`가 Claude Code CLI를 비대화형으로 호출한다:
  `--print --output-format json --json-schema … --safe-mode --strict-mcp-config --no-session-persistence --max-budget-usd`.
  작성자는 `Read,Grep,Glob,Edit,Write` + `acceptEdits`(셸 없음 → Godot/커밋/푸시/설치 불가), 검토자/계획자는 읽기 전용 + `dontAsk`.
  범위는 여전히 스냅샷 검사로 강제된다. `"model_cli"`가 없으면 기존 Codex 경로 그대로다.
- **차단 조건**: 독립 Claude CLI는 로그인되어 있어야 한다. 사람이 한 번 실행:
  `& "$env:APPDATA\Claude\claude-code\2.1.299\f0584be0fbaf\claude.exe" auth login` (데스크톱 앱 업데이트로 경로가 바뀌면
  `config.json`의 `claude_executable`을 갱신). 미로그인이면 계획/실행 전에 `AUTH_OR_USAGE`로 멈추고 시도 횟수를 쓰지 않는다.
  인증 우회·자격 증명 파일 열람/복사는 금지.
- 사용량/인증/요금 한도 오류는 `AUTH_OR_USAGE`(치명)로 멈춘다. 호출당 예산은 `claude_max_budget_usd`(기본 3, 상한 20).

## 운영자 경로 (대화형 Claude Code가 작성자일 때)

백그라운드 디렉터가 모델을 못 부를 때(미로그인 등) 대화형 세션이 작성자 역할만 맡는다. 나머지는 동일한 신뢰 코드다.

1. 계획: `python .autodev/director.py operator-plan --milestone <id> --tasks <json> --reason "..."`
   (이전 계획은 `plan-history-*.json`으로 보존, 동일 검증기, 마일스톤은 PENDING으로만 바뀜)
2. `python .autodev/autonomous.py operator-stage --task-id <id>` → 출력된 `runs/<run>/game`(일회용 스테이지)만 편집
3. 결과 JSON(구현 스키마)을 `runs/<run>/` 아래(비추적)에 쓰고 `operator-verify --run-id <run> --outcome <file>`
   → 전체 게이트(STATIC/IMPORT/SMOKE/REGRESSION/SLICE/OFFLINE/QUALITY/프로브/WASAPI·Dummy 60회/EXPORT/BUILD_RUN)
4. 작성 맥락이 없는 별도 읽기 전용 검토자(서브에이전트)의 검토 JSON → `operator-review --run-id … --review … --reviewer …`
5. `operator-integrate --run-id …` → 저널 통합, 커밋, 원격 백업 SHA 확인
6. 마일스톤 계획이 모두 DONE이면 `game-production.ps1 start`가 모델 없이 패키징·최종 출시 인증(release-evidence.json)을 수행한다.

시도 예산(최대 4회), 반복 실패 중단, 범위·보호 파일 규칙은 모델 작성자와 같다. 테스트/기준을 약화하지 않는다.
새 신뢰 프로브는 `.autodev/checks/`에 먼저 작성하고(실패 확인) `ACCEPTANCE_PROBES`에 등록한다.

## 반드시 지킬 것

- 기존 8개 퍼즐 데이터·정답, 18개 퍼즐 ID/장 구조, v1 저장·캠페인 저장 호환, 오디오 수명 처리(누수 0)를 보존한다.
  `campaign_puzzles.json`의 원본 8행은 `mech_puzzles.json`과 바이트 의미가 같아야 한다(제목 포함). 표시용 문구는 `campaign_story.json`.
- `git reset --hard`, `git clean`, 강제 푸시, 기록 삭제, 기존 실행/로그 삭제 금지. 승인된 개발 브랜치에 비강제 푸시만.
- Steam 업로드·공개 배포·구매·계정 변경은 사람 승인 사항. RELEASE_CANDIDATE_READY는 출시 승인이 아니다.
- 사람 평가(재미, 난이도 체감, 60~90분, 한국어 문학성, 미적 판단, 실제 청취, 권리 검토, 출시 승인)는
  human_review_pending으로 남기고 자동 결과로 대체하지 않는다. 이미지 생성 도구를 쓰지 않았으면 썼다고 쓰지 않는다.
- 하네스 확장보다 게임 완성이 우선이다. 인프라 변경은 실제 차단 문제를 푸는 최소 범위로 한다.

## 인수인계 시점 기록 (2026-10-21)

- S02~S06 DONE(디렉터 기록). S07 Codex 계획은 rc_01이 "실행 가능한 검증이 없는 수용 기준"으로 4회 막혀 예산 소진.
  원인은 계획 결함(보호된 테스트로만 덮을 수 있는 기준). Claude 운영자가 S07을 4개 작업으로 재계획하고
  신뢰 프로브 4개(`modal_motion`, `campaign_titles`, `chapter_transition`, `asset_licenses`)를 먼저 추가했다.
- 진행 기록과 남은 일은 `docs/CLAUDE_HANDOFF_20261021_KO.md`에 갱신한다.
- 2026-10-21 오후: Claude CLI 로그인 완료(claude.ai Max). 백그라운드 디렉터가 Claude로 작성·검토·통합·인증을 무인 수행함을 확인했다.
  엔진은 GDScript 종료 해제 후 사용 결함을 고친 `binaries/patched-gdscript-fix-20261021` 프로필을 쓴다(이전 프로필은 config의
  `engine_profile_history`와 원래 폴더에 보존). S08 완료, RELEASE_CANDIDATE_READY (`f990602`).
- 인증은 마지막 작업 커밋 == 원격 브랜치 끝을 요구한다. 문서·인프라 커밋은 인증이 끝난 뒤에 한다.
