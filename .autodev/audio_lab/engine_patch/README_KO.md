# 검토용 Godot 종료 정리 패치 — 미빌드·미적용

`godot-4.7.1-drain-at-finish.patch`는 현재 엔진 바이너리에 적용하지 않았습니다.
이 파일이 있다는 이유로 누수가 해결된 것으로 판단하면 안 됩니다.

대상은 Godot `4.7.1-stable` / 바이너리 커밋 접두사 `a13da4feb`의
`servers/audio/audio_server.cpp`이며 원본 SHA-256은
`d7641ef5852aa86f75c4d506759de2838a2c3886c29f7eb25fd9e9310d87c102`입니다.
해당 소스 복사본에 `git apply --check`가 통과했습니다. C++ 컴파일·링크·실행 검증은 하지 못했습니다.

변경 범위는 `AudioServer::finish()` 한 곳입니다. 모든 오디오 드라이버가 정지한 뒤,
남은 playback 노드를 기존 삭제 함수로 제거하고 메인 스레드의 지연 삭제 목록을 정리합니다.
버스 삭제보다 먼저 실행하며 임의 대기나 오류 필터를 추가하지 않습니다.
방향은 [공식 미병합 PR #122742](https://github.com/godotengine/godot/pull/122742)와 같습니다.
원본 엔진 소스는 Godot Engine의 MIT 라이선스 대상입니다.

실제 적용에는 별도의 엔진 소스 checkout과 Windows 빌드 도구가 필요합니다.
현재 사용할 수 있는 PATH에서 Windows C++ 컴파일러/SCons 및 WSL C++ 컴파일러/SCons를
확인하지 못했습니다. 의존성을 설치하거나 기존 Godot 실행 파일을 교체하지 않았습니다.

위험: 엔진 전체의 오디오 종료 순서가 바뀝니다. 플레이어·믹스 콜백·확장 기능의 수명,
오디오 장치 변경/실패 경로와 export template까지 별도 검증해야 합니다.
빌드가 가능해져도 기존 안정 엔진은 보존하고 별도 실행 파일로 동일 조건 30회 및 전체 QA를
재수행해야 합니다. 이 패치로 빌드하지 않은 기존 Windows export는 패치 검증이 아닙니다.
