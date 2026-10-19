# 음영 인쇄소 · 제작 및 자산 크레딧

기존 결말의 제작 정보와 감사 인사는 그대로 두었습니다. 캠페인의 마지막 퍼즐을 완성한 뒤 기존 ‘크레딧’ 버튼을 누르면 이 문서 전문과 실행 중인 Godot 엔진의 라이선스 원문, 내장 글꼴의 저작권·라이선스 고지가 이어집니다. 확대 글자에서도 기존 대화창의 세로 스크롤로 읽을 수 있습니다.

## 이번 원본 그림

원본 벡터 작성: OpenAI Codex, 2026-10-19. 실제 도구는 코드 편집 도구 apply_patch이며, SVG의 좌표·경로·도형을 직접 작성했습니다. 이미지 생성, 사진 변환, 다운로드, 외부 이미지·폰트·스크립트 삽입은 사용하지 않았습니다.

- assets/art/shop_background.svg: 나무 작업대, 종이 선반, 금속 인쇄 도구와 형광등을 직사각형·직선·곡선으로 구성했습니다. scripts/slice_main.gd의 _build_interface에서 캠페인과 기존 슬라이스 UI 뒤에 표시합니다.
- assets/art/portrait_baek.svg: 넓은 얼굴 윤곽, 옆머리, 작업 셔츠와 앞치마를 제한된 선과 면으로 그렸습니다. 백인호의 의뢰서와 기록함 다시보기에 표시합니다.
- assets/art/portrait_yoon.svg: 머리와 얼굴의 곡선, 셔츠, 접힌 종이 받침으로 기록 초상을 그렸습니다. 윤해린의 보관 문서 옆에 ‘기록 이미지’라고 표시하며 현재 현장에 나타난 인물로 취급하지 않습니다.
- assets/art/portrait_client.svg: 봉투·접힌 의뢰서·빈 서명 칸으로만 구성한 익명의 문서 표식입니다. 사람의 얼굴이나 정체를 나타내지 않습니다.

종이 #f4ebdd, 먹 #24211d, 목재 #d8c7ad, 녹색 #315d49, 인주색 #8a3f24를 공통으로 사용했습니다. 배경의 벽면에는 기존 패널색 #e4d5be를 사용했습니다. 이번 작업은 프로젝트용 원본 작성 기록이며, 별도의 공개 배포 라이선스나 제3자 권리 취득을 선언하지 않습니다. 자산 대장의 NOASSERTION은 허가가 기록되어 있지 않다는 뜻입니다.

## 보존한 그림과 효과음

assets/art/press_wood.svg는 기존 목판 무늬입니다. docs/ART-001_NOTES.md는 외부 이미지·폰트 없이 곡선 24개를 배치했다고 기록합니다. scripts/slice_main.gd의 도장과 scripts/slice_board.gd의 보드에서 계속 사용합니다. 당시 제작자의 개인 이름이나 별도 라이선스 부여 기록은 이 스냅샷에 없습니다.

assets/art/stamp_preview.svg는 기존 종이·인주 도형입니다. docs/MEDIA_PROOF.md에 직접 작성한 SVG라는 기록이 있으며 scripts/media_preview.gd에서 사용합니다. 이 기록에 없는 역사적 제작 도구나 배포 허가는 추정하지 않았습니다.

assets/audio/print.wav, undo.wav, complete.wav는 tools/generate_sfx.py와 docs/MEDIA_PROOF.md에 기록된 원본 효과음입니다. Python 표준 라이브러리로 고정 시드 잡음, 감쇠 사인파, 페이드를 합성한 모노 44,100 Hz PCM입니다. scripts/media_preview.gd에서 사용합니다. 외부 녹음이나 샘플을 사용하지 않았다는 기존 기록을 근거로 삼았으며 별도의 권리 양도는 확인하지 않았습니다.

assets/audio/slice_print.wav, slice_undo.wav, slice_complete.wav는 위 세 파일을 tools/convert_slice_sfx.py의 선형 보간으로 48,000 Hz에 변환한 기존 파생본입니다. scripts/slice_main.gd에서 인쇄·되돌리기·완료에 사용합니다. 원본과 파생본 모두 보존했습니다. 이번 작업에서 효과음을 생성하거나 수정하지 않았습니다.

## Godot와 글꼴 의존성

Godot Engine 4 — MIT License. Copyright (c) 2014-present Godot Engine contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur. 저장소 사용 경로는 project.godot 및 campaign_main.tscn입니다. 엔진 실행 파일은 게임 저장소 안의 그림 자산이 아니며, 게임의 실행·렌더링·입력을 제공하는 외부 구성요소입니다. 기존 크레딧 동작은 Engine.get_license_text()로 해당 실행 엔진의 MIT 원문을 함께 표시합니다.

기본 UI 글꼴은 Godot의 Noto Sans 계열 기본 테마 글꼴을 사용합니다. Noto Sans font — Copyright 2012 Google Inc., SIL Open Font License 1.1 (OFL-1.1). 사용 경로는 scripts/slice_main.gd의 Theme/Label/Button 및 scripts/campaign_main.gd의 대화창입니다. scripts/slice_board.gd와 scripts/board_view.gd는 ThemeDB.fallback_font로 0/1 기호를 그립니다. 게임이 별도의 폰트 파일을 포함하거나 자체 폰트를 지정하지 않습니다. 크레딧 화면에 실행 중인 UI 기본 글꼴과 ThemeDB 대체 글꼴의 실제 가족명도 표시합니다.

Godot의 내장 글꼴 고지에는 DroidSans font (엔진 내부 thirdparty/fonts/DroidSans*.woff2, Copyright 2008 The Android Open Source Project, Apache License 2.0)도 있습니다. 기본 글꼴과 대체 글꼴의 포함 여부는 실행 엔진 빌드에 따르며, 실행 중인 엔진의 Engine.get_copyright_info()/get_license_info()에서 제공하는 모든 font 항목의 파일·저작권·라이선스 원문을 이 화면 아래에 표시합니다. Noto Sans와 DroidSans를 게임 제작자의 그림이나 독자 제작 폰트로 표시하지 않습니다.

한글 등 기본 글꼴에 없는 글리프는 Godot의 시스템 글꼴 대체 기능을 통해 운영체제에 설치된 글꼴을 사용할 수 있습니다. Windows의 맑은 고딕(Malgun Gothic)은 Microsoft Corporation의 운영체제 제공 글꼴이며 Microsoft의 독점 사용 조건을 따릅니다. 이 게임은 맑은 고딕이나 다른 시스템 글꼴 파일을 복제·재배포하지 않습니다. 실제 선택되는 시스템 대체 글꼴은 실행 환경에 따라 달라지므로 Windows 내보내기에서 확인해야 합니다. 사용 지점은 위 UI 경로와 scripts/slice_board.gd의 ThemeDB.fallback_font입니다.

ASSET_LICENSES.json은 게임 저장소 상대 경로를 기준으로 신규 네 SVG, 보존한 두 SVG와 여섯 WAV, 엔진·글꼴 의존성의 사용 지점을 기록합니다. 임포터의 메타데이터는 별도 작품이 아니며 원본 자산의 기록을 따릅니다. 프로젝트 원본의 권리 처리, 기존 기록의 정확성, 배포 고지의 완전성은 사람의 검토 대상으로 남아 있습니다.
