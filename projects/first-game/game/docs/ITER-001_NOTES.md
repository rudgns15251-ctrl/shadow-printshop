# ITER-001 — 진행 경계 안내

작성일: 2026-10-12. 대상은 미승인 실험용 테스트 게임이다. 상용 콘셉트 승인, 사람의 플레이테스트, 시장성 검증을 의미하지 않는다.

## 변경 범위

- scripts/main.gd: _refresh()의 완료 상태 문자열 두 개만 변경했다.
- tests/progress_clarity_test.gd: 선택적으로 실행하는 집중 Godot UI 테스트를 추가했다.
- docs/ITER-001_NOTES.md: 이 작업 기록을 추가했다.
- 퍼즐 데이터, 상태 전이, 입력 연결, 인쇄·회전·취소·초기화 규칙, 다음 버튼 활성화 조건은 변경하지 않았다.
- 기존 나머지 14개 파일은 작업 전 바이트와 동일하다. 보호 파일 tests/smoke_test.gd, tests/regression_test.gd, docs/VALIDATION.json을 포함한다.

## 정확한 전후 동작

첫 퍼즐 완료 전 안내:

~~~text
MATCH! Press N for puzzle 2, or undo / reset to retry with fewer prints.
~~~

첫 퍼즐 완료 후 안내:

~~~text
MATCH! Next is manual: press N or click 'N: next puzzle' for puzzle 2.
U / Z: undo | R: reset to retry this puzzle.
~~~

첫 완료에서 자동 이동하지 않으며 N 키 또는 기존 다음 버튼으로 수동 진행한다는 점을 명시했다. 취소·초기화 키도 표시한다. 기존대로 첫 퍼즐 완료 시에만 다음 버튼이 활성화된다. 취소하면 미완료 상태 안내(Different cells: ...)로 돌아가 완료 안내가 사라지고 다음 버튼이 비활성화된다.

두 번째 퍼즐 완료 전 안내:

~~~text
Both puzzles complete. Prototype ends here. Undo / reset to retry this puzzle.
~~~

두 번째 퍼즐 완료 후 안내:

~~~text
Both puzzles complete. No next puzzle. Close the window to exit.
U / Z: undo | R: reset to retry this puzzle.
~~~

마지막 완료에는 다음 퍼즐이 없고 창을 닫아 종료할 수 있으며 U/Z로 취소, R로 현재 퍼즐 초기화가 가능함을 명시했다. 기존대로 다음 버튼은 비활성화된 채 유지된다. 취소·초기화는 두 번째 퍼즐에 머물러 재시도한다. 종료 버튼이나 새 입력 규칙은 추가하지 않았다.

## 선택적 집중 테스트

progress_clarity_test.gd는 실제 main.tscn을 인스턴스화하고 기존 키 입력 경로와 버튼 신호로 두 퍼즐을 해결한다. 비공개 상태 주입이나 모의 상태는 사용하지 않는다.

- 첫 완료 후 한 프레임을 기다려 수동 진행 안내와 활성화된 다음 버튼을 확인한다. 마우스 취소 후 안내 제거·다음 버튼 비활성화와 N 이동 거부를 확인하고 재해결 후 다음 버튼으로 진행한다.
- 두 번째 완료 후 종료·취소·초기화 안내와 다음 버튼 비활성화를 확인한다. N 입력이 완료 상태와 안내를 유지하는지, Z 취소 후 재해결과 R 초기화가 같은 퍼즐에서 가능한지도 확인한다.
- 비교 실패는 quit(1)로 종료한다. 모든 비교를 마친 뒤 실패가 없을 때만 ITER_001_PROGRESS_CLARITY_PASS를 출력하고 quit(0)으로 종료한다. 기존 테스트나 하네스에는 연결하거나 수정하지 않았다.

## 실제 수행한 검증

셸 명령과 Godot 실행 명령은 0회 실행했다. 네트워크·개인 파일·네이티브 코드에 접근하지 않았고, 의존성 설치·Git 명령·커밋·하네스 변경을 하지 않았다. Node REPL의 로컬 파일 API(fs.readdir/readFile/writeFile), node:assert/strict 및 node:crypto만 사용했다.

Node 정적 검사 최종 16항목 통과:

1. 원래 두 안내 문자열을 되돌리면 main.gd가 작업 전 전체 내용과 정확히 일치한다.
2. 첫 안내의 수동 진행·키·버튼·도착 퍼즐, 마지막 안내의 진행 경계·창 닫기 종료, 양쪽의 취소·초기화 키를 확인했다.
3. 안내를 각각 두 줄로 나눴으며 줄당 문자 수는 첫 안내 70/44자, 마지막 안내 64/44자다. 기존 한 줄은 각각 72자와 78자였다. 이는 문자 수 검사이며 픽셀 배치 검증이 아니다.
4. main.gd 이외의 기존 14개 파일을 Buffer.equals로 비교했고, 보호 파일 3개도 각각 바이트 비교와 SHA-256 비교를 수행했다.
5. 선택적 테스트의 실제 장면 preload와 대상 파일 존재, 키·버튼 입력 경로, 진행 안내 제거·마지막 종료 안내·비활성화 검사, 최종 취소·초기화 경로, 실패 종료와 단일 성공 표식, 외부 API 및 상태 직접 쓰기 부재를 소스에서 확인했다.

사용한 핵심 검증 식:

~~~javascript
assert.ok(currentMain.replace(newFirst, oldFirst).replace(newFinal, oldFinal) === mainBefore);
assert.ok((await fs.readFile(path.join(game, rel))).equals(beforeFiles.get(rel)));
crypto.createHash('sha256').update(bytes).digest('hex');
~~~

최초 정적 검사에서 첫 안내가 기존보다 긴 76자 한 줄임을 발견해 70자로 줄였다. 재실행 중 검증 스크립트의 변수 선언 오류와 REPL 집계 변수 문제를 수정했다. 최종 검사는 조건 16개를 배열에 모아 각각 assert.ok로 실행하고 길이를 집계했다. 위 오류들은 도구용 정적 검사 문제이며 Godot 실행 실패나 통과 기록이 아니다.

보호 파일 SHA-256(작업 전후 동일):

- tests/smoke_test.gd: 9080f787df2165315034c407c928163ff8f447279966fbb6e1072c89e58c9f68
- tests/regression_test.gd: 6d0590e898a6be0bb18c08371a18b6118111919c16238ea7f92dceed34e0d0dc
- docs/VALIDATION.json: 4cae614cfb8a75ceee6352b242dfe39ce9c8e96792b9716635e2182ac415bbd4

## 실행하지 못한 검증과 후속 확인

현재 노출된 도구에는 전용 Godot 실행기가 없다. 이번 작업은 셸 명령·네이티브 코드 접근을 금지하므로 엔진 탐색이나 별도 프로세스 실행을 시도하지 않았다. 기존 QA 문서의 이전 실행 결과를 이번 검증으로 재사용하지 않는다.

새 집중 테스트, 기존 smoke/regression, 독립 QA 모두 이번에 실행하지 않았다. GDScript 파싱·런타임, 실제 버튼 클릭 이벤트 전달, 실제 창 종료, 두 줄 안내의 화면 잘림·DPI·창 크기별 가독성은 미검증이다. 사람의 새 플레이테스트도 수행하지 않았다.

Godot 실행이 허용되고 엔진이 준비된 환경에서 사용할 실행 예시(문서상의 예시이며 미실행):

~~~text
godot --headless --path projects/first-game/game --script res://tests/progress_clarity_test.gd
godot --headless --path projects/first-game/game --script res://tests/smoke_test.gd
godot --headless --path projects/first-game/game --script res://tests/regression_test.gd
~~~

집중 테스트는 종료 코드 0, 성공 표식, 파싱/스크립트 오류 없음까지 실제 확인해야 한다. 기존 보호 테스트와 독립 QA 결과는 별도로 확인한다. 실제 창에서도 첫 완료→취소의 안내 제거·다음 버튼 잠금, 마지막 완료의 종료·취소·초기화 안내와 다음 버튼 잠금, 창 닫기 종료 및 화면 배치를 확인해야 한다. 이 노트의 정적 검사는 요청된 동작의 런타임 입증이나 최종 승인 판정을 대체하지 않는다.
