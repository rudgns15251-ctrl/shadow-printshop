# ART-001 작업 기록

2026-10-13. 실제 기본 C01 장면에 아트를 통합한 구현이며, 사람 시각 승인 또는 Steam 출시 준비 완료를 뜻하지 않는다.

## 구현

- `slice_main.gd`, `slice_board.gd`, `assets/art/press_wood.svg`, 이 문서만 수정/추가했다. 기존 사용자 파일은 삭제하지 않았다.
- 외부 이미지·폰트 없이 수식으로 24개 곡선을 배치한 독창적 목판 SVG를 제작했다. 세 보드의 테두리/칸 사이와 도장 미리보기 배경에서 실제 Godot Texture2D로 사용한다.
- 종이색, 검은 잉크, 적갈색 인쇄 강조, 녹색 목표를 통일했다. BEFORE / AFTER / TARGET과 한국어 설명을 병기하고 프레임 색도 구분한다. 숫자 0/1과 삼각형 표시는 유지하며 검은 칸 위 강조는 밝은 황토색으로 바꿨다.
- 도장 미리보기는 고정 그림 대신 현재 선택·회전을 반영한 3×3 마스크다. `1 = 반전할 칸`을 명시한다.
- 성공한 인쇄/되돌리기/해결마다 별도 텍스트·기호를 표시하고 기존 0.14초 축소 복원, 0.20초 색 복원 반응을 사용한다. 완료는 현재 보드의 녹색 테두리와 기존 완료 안내로 지속 표시한다. 실패한 입력에는 반응을 호출하지 않는다.
- 모션 축소에서는 애니메이션 없이 텍스트와 완료 테두리만 제공한다. 애니메이션 도중 설정을 켜도 즉시 기본 크기·색으로 복원한다.
- 1280×720의 공간을 위해 보드 최소 크기를 156으로, 세로 간격과 중복 설명을 줄였다. 기존 반응형 열 배치와 흐름형 버튼, 세로 스크롤을 유지한다. 하단 상태창은 스크롤 밖에 있고 컨트롤은 동일 콘텐츠 흐름 안에 있어 겹쳐 배치하지 않는다. 1920×1080도 같은 컨테이너 구성을 사용한다. 확대 글꼴에서는 세로 스크롤이 필요할 수 있다. 두 해상도에서의 실제 렌더링 적합성은 미검증이다.
- 기존 hover/disabled/focus 스타일과 한국어 텍스트를 유지했다. 규칙·6퍼즐 데이터·오디오 호출·저장/복원 API·장면·설정 파일·테스트는 변경하지 않았다. `user://` 상대 저장 작업을 보존했다. 다운로드, 설치, 네트워크, 커밋은 하지 않았다.

## 실제 검증 결과

- `python3 projects/first-game/game/tests/mech_offline.py`: 종료 코드 0. `PASS offline cases 6000 (Python reference only)`. 퍼즐별 최소 인쇄 수 2/2/1/3/3/4. Godot 실행 검증을 대신하지 않는다.
- Python XML 파싱: `SVG_XML_PASS: 24 procedural grain paths plus border; no external references`.
- Git HEAD와 메서드 본문 비교: `PRESERVATION_PASS: audio and save/restore methods unchanged; relative user:// APIs retained`. 오디오 생성/음량/재생 및 저장/복원 관련 11개 메서드가 동일함을 확인했다. 금지된 절대 삭제/이름 변경 호출이 없다.
- 기본 장면 연결 정적 확인: `DEFAULT_SCENE_STATIC_PASS: original default scene binds modified scripts and dynamic mask`.
- 기본 `git diff --check`는 기존 CRLF 형식을 새 줄의 trailing whitespace로 보고했다. CRLF를 유지했고 `git -c core.whitespace=cr-at-eol diff --check`로 실제 공백 오류를 검사했다.
- Godot 탐색: `command -v godot`, `command -v godot4` 및 저장소 내 실행 파일 검색에서 사용 가능한 엔진을 찾지 못했다.
- 아래 네 명령을 실제 시도했으나 모두 `/bin/bash: godot: command not found`, 종료 코드 127로 시작하지 못했다:

```sh
godot --headless --editor --path projects/first-game/game --quit
godot --headless --path projects/first-game/game --script res://tests/smoke_test.gd
godot --headless --path projects/first-game/game --script res://tests/regression_test.gd
godot --headless --path projects/first-game/game --script res://tests/slice_acceptance.gd
```

## 남은 확인

Godot 임포트/스크립트 컴파일, 실제 기본 장면의 1280×720·1920×1080 화면, 100/125/150% 글꼴의 스크롤·포커스, 빠른 인쇄/취소 및 모션 축소 전환, Windows 한국어 글꼴 렌더링은 엔진 실행 후 확인해야 한다. 런타임 통과, 사람 플레이테스트·시각 승인, Steam 준비 여부를 주장하지 않는다. 외부 접근이나 엔진 설치로 제약을 우회하지 않았다.
