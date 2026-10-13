# SLICE-001 — 음영 인쇄소 6퍼즐 통합본

작성: 2026-10-13 · 상태: **통합 소스 작성 완료 / Windows Godot 검증 및 사람 승인은 미실행**

## 작업 범위와 보존

- Godot 기본 실행(`project.godot`의 `run/main_scene`)을 신규 `integrated_main.tscn`에 연결했다.
- 이전 `main.tscn`, `mech_main.tscn`, `media_preview.tscn`과 기존의 `game_state.gd`, `mech_state.gd`, `main.gd`, `mech_main.gd`, `media_preview.gd`는 그대로 보존한다.
- 보호 파일 `tests/smoke_test.gd`, `tests/regression_test.gd`, `docs/VALIDATION.json` 및 기존 QA 기록은 변경하지 않았다.
- 6개 퍼즐 데이터 `data/mech_data.gd`와 원본 3개 WAV, 원본 도장 SVG도 그대로 유지한다.
- 이전에 `blocked` 상태였던 하네스 SLICE-001의 SQLite 상태/승인/기존 worktree를 수정하지 않았다. **ZIP은 별도 실행 가능한 소스 복사본**이다.

## 이번에 실제 추가한 것

| 영역 | 구현 내용 | 확인 상태 |
| --- | --- | --- |
| 기본 게임 | 시작 화면 → 6퍼즐 → 완료/수동 다음의 통합 UI | 소스 제작, 런타임 미확인 |
| 그래픽 | 종이/잉크 팔레트, 0/1 명시, 변경 셀 이중 테두리, MEDIA SVG, 도장 반응 | 소스 제작, GUI 미확인 |
| 입력 | 1/2, Q/E, Space/Enter, U/Z, R, N, Esc 및 버튼 포커스 분리 | 코드 반영, 실제 입력 미확인 |
| 화면 | 스크롤 레이아웃, 1280×720 기준, 폭·글자배율에 따른 보드 재배치 | 화면 캡처 미확인 |
| 효과음 | 인쇄, 되돌리기, 완료 SFX. 마지막 인쇄에서는 완료음만 재생 | 소스 연결, 실제 청취 미확인 |
| 오디오 규격 | 기존 44.1kHz 원본에서 48kHz 모노 16bit 파생 파일 3종 생성 | Python 파일 검증 완료 |
| 설정 | 전체/SFX 볼륨, 음소거, 100/125/150% 글자, 모션 축소 | 소스 제작, 재시작 확인 필요 |
| 도움말·힌트 | 규칙 안내와 퍼즐별 3단계 힌트(3단계는 BFS 첫 수) | 소스 제작, 실제 플레이 검토 필요 |
| 저장 | `user://` 로컬 1슬롯, 모든 undo 이력과 선택/회전/보드, 힌트, 설정 별도 저장 | 소스 제작, 파일 쓰기 복원 검사 필요 |
| 저장 검증 | JSON 숫자형 재해석, 데이터 버전/범위/전체 undo 이력 재생 검증 | 로직 작성, GDScript 런타임 미검증 |
| 추가 테스트 | `tests/slice_acceptance.gd` — SceneTree 기반 6퍼즐 해답, 저장 왕복, 구버전 보존, UI 기본 바인딩 | 작성 완료, **Godot 미실행** |

## 실제 수행한 검사

- `python tests/mech_offline.py`: **PASS**, 6퍼즐 BFS 및 Python 참조 모델 6,000 입력열. 이 검사는 기존 게임 데이터에 대한 Python 검사로 Godot 검사를 대신하지 않는다.
- `tools/convert_slice_sfx.py` 실행: 48,000Hz / 16bit / 모노 파생 WAV 생성, 각 파일을 Python wave로 다시 열어 규격·프레임 확인. 실제 청취/믹스 검증은 미실행.
- 입력 압축 ZIP에서 원본 보존 비교, 새 파일 경로/리소스 참조·문서 목록 검사, GDScript 기초 정적 점검을 수행. **Godot 실행 파일은 이 제작 환경에서 찾지 못해 런타임 컴파일/임포트/화면/오디오 및 Windows 빌드는 검증하지 못했다.**
- 실제 사용자 하네스의 Godot 독립 QA, 기존 smoke/regression은 이 환경에서 실행하지 않았다. 기존 기록을 새 통과 결과로 표시하지 않는다.

## Windows PC에서 검사하는 명령

먼저 다운로드한 별도 `C01_Integrated_Standalone` 폴더를 압축 해제한다. 사용자 기존 하네스·worktree에 덮어쓰지 않는다.

```powershell
$game = (Resolve-Path ".\C01_Integrated_Standalone").Path
$godot = "C:\Users\newsj\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
& $godot --headless --editor --path "$game" --quit
& $godot --headless --path "$game" --script "res://tests/slice_acceptance.gd"
& $godot --headless --path "$game" --script "res://tests/mech_cases.gd"
& $godot --headless --path "$game" --script "res://tests/smoke_test.gd"
& $godot --headless --path "$game" --script "res://tests/regression_test.gd"
& $godot --path "$game"
```

각 명령의 종료 코드 0뿐 아니라 `SLICE_ACCEPTANCE_PASS`, `HARNESS_SMOKE_PASS`, 회귀 고유 성공 메시지 등을 확인한다. 구문/스크립트 오류가 있거나 성공 표식이 없으면 승인하지 않는다.

## 수동 검토 시나리오

1. 처음 실행: 시작 화면에서 도움말/설정을 열고 뒤로 가기. 새로운 플레이로 퍼즐 1 시작. Space·Enter를 단일 누름/2초 누름/다시 누름으로 구분한다.
2. 퍼즐 1~6을 연속 완주하고 퍼즐 3·4는 B 도장만 허용되는지 검사. 완료 후 자동 진행하지 않으며 마지막에서는 다음 버튼이 비활성화되는지 확인.
3. 인쇄→되돌리기→재인쇄→완료, 실패 인쇄 시 무음. 완료 시 print+complete가 중첩되지 않고 complete만 들리는지 확인.
4. 소리 음소거/0~100%/재시작 유지, 모션 축소 켠 상태, 720p·1080p×100/125/150%에서 잘림·스크롤·포커스 확인.
5. 퍼즐 3에서 몇 회 인쇄한 뒤 수동 저장→프로세스 종료→이어하기. 보드·인쇄 횟수·도장·회전·undo 이력·힌트 재현, 여러 번 undo 정상.
6. 저장 파일 손상·스키마 불일치 시 진행을 조용히 초기화하지 않고 재시작/복원 선택이 가능한지 확인. 사용자 개인 저장 삭제 금지.
7. 새 설치·Windows Export/라이선스·폰트 글리프·다중 장치 청취·실사용 만족도 및 Steam 상품성 검증은 별도 미검증이다.

## 알려진 차이 / 후속 범위

- 오디오 원본은 44.1kHz 그대로 보존했다. 통합본만 파생 48kHz를 사용하며 원음과 변환음의 청취 비교가 필요하다.
- 독립 BGM은 아직 없으며 설정 화면에 명시했다. 유료 완제품·전체 아트 세트·Steam 배포 빌드가 아니다.
- 6퍼즐의 기술 해답은 검증했지만 재미, 난이도, 콘텐츠 다양성, 판매 가치는 사람 관찰 전까지 미검증이다.
- Godot 720p·고배율 GUI 및 한국어 폰트 표시, 프로그램 종료/재실행 저장 복원은 실제 Windows 환경에서 검사 전까지 미검증이다.
- C01은 최종 게임 선정이 아닌 제한된 수직 슬라이스 실험이다. 최종 승인은 `PENDING_HUMAN_APPROVAL`이다.
