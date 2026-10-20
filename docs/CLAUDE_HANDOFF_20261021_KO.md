# Claude Code 인수인계 및 S07 출시 후보 보고 (2026-10-21)

## 결론

- 디렉터 상태 **RELEASE_CANDIDATE_READY** (출시 승인 아님). 마지막 검증 커밋 `593fa854c80c`, 원격 `codex/production-20261018` SHA 일치.
- 출시 후보 ZIP: `.data/production-builds/s07_release-593fa854c80c.zip`
  SHA-256 `7b1d7e4a019895d6e144f53b3c35386477e531ca979a50f269e306aaff63a707` (EXE + PCK + build_manifest).
- 증거: `.autodev/state/production/release-evidence.json` — Debug/Release × WASAPI/Dummy 각 30회, 새 사용자 데이터로 120/120 통과,
  ZIP을 새 폴더에 풀어 그래픽(OpenGL)·실제 WASAPI 실행 통과. `human_playtest`/`human_listening`: not_performed.

## 인수 시점 조사 결과

- Codex 관리자: 소유 PID 10564 종료, 실행 중 자식 없음(Codex 데스크톱 앱 자체만 실행 중). 이력·실행 기록은 모두 보존.
- S02~S06 DONE. S07 Codex 계획은 rc_01이 4회 `blocked` 후 예산 소진. 원인은 코드가 아니라 계획: 수용 기준이 보호된 테스트로만
  덮을 수 있는 실행 검증을 요구해 작성자가 정직하게 blocked를 보고했다.
- 기본 폴더의 미커밋 `.autodev` 수정은 생산 브랜치에 커밋된 것보다 오래된 초안이다. 손대지 않았다.

## 실행 주체 이전

- `autonomous.codex()` 단일 모델 경계에 Claude Code CLI 어댑터 추가(`model_cli: claude`, 로컬 config). 실제 설치 CLI 2.1.299의
  옵션 계약을 실제 호출로 확인했다(인증 전 단계까지). 작성자: 파일 도구만(셸 없음), 검토/계획: 읽기 전용.
- 인증·사용량·예산 오류 → AUTH_OR_USAGE 치명 중단. 미로그인 시 계획/실행 전에 거부(시도 횟수 미소모).
- **남은 차단**: 독립 Claude CLI가 로그인되어 있지 않다(`loggedIn: false`). 사람이 한 번 `claude auth login`을 실행해야
  백그라운드 디렉터가 모델 단계를 스스로 수행한다. 그때까지 대화형 Claude Code가 운영자 경로로 작성자 역할을 했다.
- 운영자 경로: operator-plan/stage/verify/review/integrate. 작성자만 바뀌고 범위 스냅샷, 전체 게이트, 별도 읽기 전용 검토
  기록, 저널 통합, 원격 백업 검증은 기존 신뢰 코드 그대로다. 검토자는 작성 맥락이 없는 별도 Claude 서브에이전트였다.

## 하네스 결함 수정 (게임 진행을 실제로 막은 것만)

1. 통합 전 가드 거절(예: 추적되지 않는 파일)이 BLOCKED/UNKNOWN으로 남아 재개 불가 → 검증·승인된 원본 그대로일 때만 재시도 허용.
2. 수용 프로브 실패 메시지에 종료 코드가 없어 엔진 종료 시 접근 위반(0xC0000005, 무관한 간헐 현상: 변경/기준 각 10회 재현 실패)이
   UNKNOWN(복구 불가)으로 분류 → 핵심 게이트처럼 `exit=`를 포함해 ENVIRONMENT로 분류.
- 하네스 테스트: 신규 17개 포함 116개, 기존 환경 의존 실패 2개(WSL 작업자, POSIX 모의 파이프라인)는 인수 전과 동일.

## S07 게임 작업 (렌더링 검토에서 찾은 실제 결함)

| 작업 | 내용 | 신뢰 게이트 | 독립 검토 |
|---|---|---|---|
| rc_01_modal_motion | 대화창·설정을 열면 인쇄/되돌리기 연출 즉시 정지 | 78/78 | accept |
| rc_02_korean_titles | 1장 원본 8개 퍼즐의 영어 제목 → 한국어 표시 제목(데이터 원본 불변) | 79/79 (1회 엔진 종료 크래시 재검증) | accept |
| rc_03_chapter_transition_sfx | 2·3장 진입 시 지난 장 기록+새 장 시작 대화창, 종이·장 전환 효과음 2종(표준 라이브러리 합성, 결정적, 피크 0.20/0.34) | 80/80 | accept |
| rc_04_asset_license_reader | 크레딧 → 자산 출처·라이선스 열람, 크레딧의 Markdown 표식 제거 | 81/81 (검토 지적: 의존성 라이선스가 프로젝트 파일 것처럼 보임 → 수정 후 재검증) | revise → accept |

신규 신뢰 프로브(먼저 작성해 실패 확인): `modal_motion`, `campaign_titles`, `chapter_transition`, `asset_licenses`.
모든 작업에 기존 STATIC/IMPORT/SMOKE/REGRESSION/SLICE/OFFLINE/QUALITY/EXPORT/BUILD_RUN, 캠페인·저장·힌트·사운드·출시 프로브,
WASAPI/Dummy 60회 오디오 누수 검사를 그대로 적용했다. 기준 완화·테스트 삭제 없음.

## 사람 검토 필요 (자동 통과로 대체하지 않음)

- 실제 플레이: 재미, 난이도 곡선, 초보자 학습, 60~90분, 장 전환 대화창의 흐름(자동 표시 vs 선택 읽기).
- 실제 청취: 새 효과음 2종의 크기·놀람·피로, 장 전환음의 C5/G5 잔향이 "건조한 소리" 기준에 맞는지, 배경음과의 조화.
- 한국어: 1장 표시 제목 8개(예: '엇갈린 상쇄'), 마침+시작 기록을 이어 읽을 때의 문장, '원래 교정판' 반복.
- 시각: 해상도 2종 × 글자 크기 3종에서 긴 대화창(장 전환·자산 열람)의 가독성과 섹션 구분.
- 권리: NOASSERTION 자산(Codex 작성 SVG 4종, 기존 자산, Claude 합성 효과음 2종), shop_ambience 허가 범위, 맑은 고딕 대체 글꼴.
- 출시 표기: 실행 파일명 `C01_Windows_Test.exe`, 프로젝트명 "C01 - Shadow Printshop Slice"(저장 폴더 키를 겸함)는
  공개 판매용 이름으로 정리할지 결정이 필요하다. 저장 호환성 때문에 프로젝트명 변경은 이전 경로 처리와 함께 해야 한다.
- 최종 출시 승인, Steam 업로드, 공개 배포는 사람의 결정이다.

## 다음 세션

`CLAUDE.md`를 읽고 `.\game-production.ps1 status`로 시작한다. 모든 마일스톤이 끝났으므로 새 작업은 사람 검토 결과나
출시 표기 결정 같은 새 요청에서 시작한다. Claude CLI 로그인 후에는 백그라운드 디렉터가 모델 단계를 직접 수행할 수 있다.
