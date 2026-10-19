# 음영 인쇄소 · 제작 및 자산 크레딧

기존 결말의 제작 정보와 감사 인사는 그대로 두었습니다. 캠페인의 마지막 퍼즐을 완성한 뒤 기존 ‘크레딧’ 버튼을 누르면 이 문서 전문과 실행 중인 Godot 엔진의 라이선스 원문, 내장 글꼴의 저작권·라이선스 고지가 이어집니다. 확대 글자에서도 기존 대화창의 세로 스크롤로 읽을 수 있습니다.

## 이번 원본 그림

원본 벡터 작성: OpenAI Codex, 2026-10-19. 실제 도구는 코드 편집 도구 apply_patch이며, SVG의 좌표·경로·도형을 직접 작성했습니다. 이미지 생성, 사진 변환, 다운로드, 외부 이미지·폰트·스크립트 삽입은 사용하지 않았습니다.

- assets/art/shop_background.svg: 나무 작업대, 종이 선반, 금속 인쇄 도구와 형광등을 직사각형·직선·곡선으로 구성했습니다. scripts/slice_main.gd의 _build_interface에서 캠페인과 기존 슬라이스 UI 뒤에 표시합니다.
- assets/art/portrait_baek.svg: 넓은 얼굴 윤곽, 옆머리, 작업 셔츠와 앞치마를 제한된 선과 면으로 그렸습니다. 백인호의 의뢰서와 기록함 다시보기에 표시합니다.
- assets/art/portrait_yoon.svg: 머리와 얼굴의 곡선, 셔츠, 접힌 종이 받침으로 기록 초상을 그렸습니다. 윤해린의 보관 문서 옆에 ‘기록 이미지’라고 표시하며 현재 현장에 나타난 인물로 취급하지 않습니다.
- assets/art/portrait_client.svg: 봉투·접힌 의뢰서·빈 서명 칸으로만 구성한 익명의 문서 표식입니다. 사람의 얼굴이나 정체를 나타내지 않습니다.

종이 #f4ebdd, 먹 #24211d, 목재 #d8c7ad, 녹색 #315d49, 인주색 #8a3f24를 공통으로 사용했습니다. 배경의 벽면에는 기존 패널색 #e4d5be를 사용했습니다. 이번 작업은 프로젝트용 원본 작성 기록이며, 별도의 공개 배포 라이선스나 제3자 권리 취득을 선언하지 않습니다. 자산 대장의 NOASSERTION은 허가가 기록되어 있지 않다는 뜻입니다.

## 이번 원본 배경음

assets/audio/shop_ambience.wav — OpenAI Codex가 이 프로젝트를 위해 2026-10-19에 새로 작성한 절차 합성 배경음입니다. Python 표준 라이브러리의 math, struct, io, wave만 사용하여 오프라인으로 만들었습니다. 녹음, 외부 샘플, 다운로드, 이미지 생성은 사용하지 않았습니다. 기존 효과음은 이번 합성의 재료로 사용하지 않았습니다.

형식은 모노 48,000 Hz, 부호 있는 리틀엔디언 PCM16이며 576,000프레임, 12초입니다. 110·165·220·330·440 Hz 사인파를 각각 0.42·0.27·0.16·0.10·0.05의 비중으로 더했습니다. t=i/48000, T=12에서 양끝 거리 d=min(t,T-t)에 따른 fade=0.5-0.5*cos(pi*min(d,1.0))로 앞뒤 1초를 부드럽게 감싸고, breath=0.84+0.16*cos(2*pi*t/T)로 천천히 음량을 바꿉니다. 모든 주파수는 12초 안에 정수 주기를 마치며 난수나 시드는 사용하지 않습니다. 원시 표본의 절댓값 최대치를 기준으로 목표 피크 0.06에 맞춘 뒤 round(value*32767)로 PCM16을 기록했습니다. 순방향 반복 범위는 0 이상 576,000 미만 프레임이며, 캠페인이 소유한 별도 AudioStreamPlayer에서 설정합니다.

최종 WAV를 다시 읽어 측정한 절댓값 피크는 1,966/32,768 = 0.05999755859375입니다. 첫 표본과 마지막 표본은 모두 0이며 반복 경계의 표본 차이는 0/32,768 = 0입니다. ASSET_LICENSES.json의 해당 행에는 전체 재현용 Python 코드, 파일 SHA-256과 계산 방법을 기록했습니다. wave로 최종 파일을 읽고 struct의 <h로 표본을 해석한 뒤 max(abs(s))/32768 및 abs(s[-1]-s[0])/32768을 계산하면 확인할 수 있습니다.

전체·효과음·BGM을 모두 1로 두는 표본 합산 검사에서, 기존 효과음 중 어느 두 개와 배경음의 임의 위상이 겹치는 상한은 0.9063720703125였습니다. 세 효과음을 동시에 시작한 경우의 표본 합에 배경음 최대치를 더한 상한은 0.852691650390625였습니다. 이는 명시한 합산 경우의 오프라인 근거입니다. 임의 시차의 세 효과음 중첩, 엔진의 실제 혼합·리샘플링과 WASAPI 실행 출력은 코디네이터의 오디오 검사 대상으로 남습니다. 위 수치는 반복 경계가 귀에 들리지 않는지, 음색이 온화한지, 오래 들어도 피로하지 않은지 또는 갑작스럽게 놀라게 하지 않는지에 대한 청취 판정을 대신하지 않습니다.

이 새 WAV와 합성 레시피에만 원제작 허가 LicenseRef-Shop-Ambience-Permissive를 부여합니다. 권리가 존재하고 부여 가능한 범위에서, 누구나 이 허가 고지를 유지하여 무료로 사용·복제·수정·공개·배포·재허가·판매할 수 있습니다. 자산과 레시피는 어떠한 보증도 없이 있는 그대로 제공됩니다. 영어 허가 원문은 ASSET_LICENSES.json에 있습니다. 기존 자산의 권리 상태는 바꾸지 않습니다. 합성 경위, 허가의 정확성 및 실제 청취는 사람의 검토가 필요합니다.

설정의 ‘BGM · 인쇄소 배경음’ 슬라이더는 키보드로도 조절할 수 있으며 기존 BGM 값과 함께 로컬에 저장됩니다. 캠페인 플레이 중 음량은 전체 음량×BGM이며 효과음 슬라이더와 독립적입니다. 새 게임이나 유효한 이어하기에서 시작하고, 음소거·전체 음량 0·BGM 0 또는 시작 화면 복귀에서 정지합니다. 이 동작과 종료 시 스트림 해제, 실제 오디오 드라이버 및 Windows 내보내기는 신뢰된 코디네이터의 실행 검증이 남아 있습니다.

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

ASSET_LICENSES.json은 게임 저장소 상대 경로를 기준으로 신규 네 SVG와 배경음 WAV, 보존한 두 SVG와 여섯 WAV, 엔진·글꼴 의존성의 사용 지점을 기록합니다. 임포터의 메타데이터는 별도 작품이 아니며 원본 자산의 기록을 따릅니다. 프로젝트 원본의 권리 처리, 기존 기록의 정확성, 배포 고지의 완전성은 사람의 검토 대상으로 남아 있습니다.
