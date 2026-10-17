# Godot 종료 정리 패치 — C01 Windows 검증 완료

`godot-4.7.1-drain-at-finish.patch`를 별도 4.7.1 소스에 적용해 Windows editor를 빌드했습니다.
기존 설치된 Godot 실행 파일과 export template은 교체하지 않았습니다.
Editor 570회와 전용 Windows template 즉시 종료 120회가 모두 누수 0건으로 통과했습니다.
최종 게임 QA·Windows export·실제 팝업·하네스 E2E도 통과했습니다.
인증은 보고서에 고정한 C01 커밋·바이너리·GL Compatibility 환경에 한정합니다.
최신 상태는 [Windows 검증 보고서](../../../docs/AUDIO_ENGINE_WINDOWS_20261017_KO.md)를 확인합니다.

대상은 Godot `4.7.1-stable` / 바이너리 커밋 접두사 `a13da4feb`의
`servers/audio/audio_server.cpp`이며 원본 SHA-256은
`d7641ef5852aa86f75c4d506759de2838a2c3886c29f7eb25fd9e9310d87c102`입니다.
해당 소스 복사본에 `git apply --check --unidiff-zero`가 통과했습니다.
패치 파일의 중첩 diff 공백 오탐을 피하도록 문맥 없는 형식으로 저장했으므로,
반드시 위 원본 SHA와 `--unidiff-zero` 옵션을 함께 확인해야 합니다.
원본/패치 editor·debug/release template의 MSVC 빌드와 실제 런타임 검사를 완료했습니다.

변경 범위는 `AudioServer::finish()` 한 곳입니다. 모든 오디오 드라이버가 정지한 뒤,
남은 playback 노드를 기존 삭제 함수로 제거하고 메인 스레드의 지연 삭제 목록을 정리합니다.
버스 삭제보다 먼저 실행하며 임의 대기나 오류 필터를 추가하지 않습니다.
방향은 [공식 미병합 PR #122742](https://github.com/godotengine/godot/pull/122742)와 같습니다.
원본 엔진 소스는 Godot Engine의 MIT 라이선스 대상입니다.

후속 조사에서 PATH 밖의 MSVC 19.43 및 Windows SDK 10.0.22621을 찾아 실제 컴파일을
확인했습니다. Python 3.14.3은 기존 .venv를 사용하며, 사용자 승인 후 SCons 4.11.1만
해당 .venv에 설치했습니다. 시스템 설치·PATH 변경·관리자 권한 변경은 하지 않았습니다.
정확한 소스 커밋과 공통 옵션은 [windows_build_recipe.json](windows_build_recipe.json)에 있습니다.

위험: 엔진 전체의 오디오 종료 순서가 바뀝니다. 플레이어·믹스 콜백·확장 기능의 수명,
오디오 장치 변경/실패 경로와 export template까지 별도 검증해야 합니다.
이번 C01 검사에서는 기존 안정 엔진을 보존하고 별도 실행 파일로 동일 조건 30회 및 전체 QA를
검증했습니다. 다른 프로젝트나 환경은 별도 검증이 필요합니다.
이 패치로 빌드하지 않은 기존 Windows export는 패치 검증이 아닙니다.
