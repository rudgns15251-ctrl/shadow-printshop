# 음영 인쇄소 · Android 출시 준비 안내

Claude가 준비한 범위는 "Play 스토어 제출 직전"까지다. Google 계정, Play Console 개발자 등록(유료),
업로드 키, 업로드와 게시는 사용자가 직접 한다. RELEASE_CANDIDATE_READY는 출시 승인이 아니다.

## 준비된 것

| 항목 | 위치 |
| --- | --- |
| Android 템플릿(패치 엔진 4.7.1과 같은 소스로 빌드) | `.data/qualified-templates-android-20261021/` (SHA256SUMS.txt) |
| 도구 모음(JDK 17, SDK 36, NDK, 빌드 도구) | `.data/android-toolchain/` (저장소에 포함되지 않음) |
| 패키징·검증 스크립트 | `scripts/android/package_android.py` |
| 업로드 키 만들기 | `scripts/android/make_upload_key.ps1` |
| 제출용 AAB 만들기 | `scripts/android/package_release.ps1` |
| 스토어 그래픽 다시 만들기 | `scripts/android/store_graphics.gd` |
| 등록정보·개인정보·데이터 보안·등급 초안 | `docs/play-store/*.md` |
| 아이콘·그래픽 이미지·스크린샷 | `docs/play-store/graphics/` |

게임 설정: 패키지 `com.shadowprintshop.game`, 가로(센서에 따라 180° 회전, 회전 잠금은 존중),
최소 Android 7.0(API 24), 대상 API 36, 64비트 ARM(arm64-v8a), 권한 없음, 인터넷 없음, 백업 끔.

스토어 그래픽은 게임을 바꾼 뒤 창 모드로 다시 만든다(헤드리스 불가, 글꼴 렌더링 필요):
`godot.windows.editor.x86_64.exe --path <게임 폴더> --script scripts\android\store_graphics.gd -- output=<출력 폴더>`
(게임 폴더는 한 번 `--import` 한 사본을 쓰는 것이 안전하다).

## 1. 테스트 설치용 APK (선택)

```powershell
..\..\.venv\Scripts\python.exe scripts\android\package_android.py --out .data\android-test --mode debug --format apk
```
Android 디버그 키로 서명된 APK가 만들어진다. 실제 휴대전화에 설치해 보려면 기기의
"알 수 없는 앱 설치"를 허용하고 `adb install`을 쓴다. 이 APK는 Play에 올릴 수 없다.

## 2. 업로드 키 만들기 (한 번)

```powershell
.\scripts\android\make_upload_key.ps1
```
키는 `%USERPROFILE%\.android-keys\shadowprintshop-upload.jks`에 생긴다. 키 파일과 암호를 따로 백업한다.
Play Console에서 "Play 앱 서명"(기본값)을 쓰면 Google이 실제 배포 키를 보관하고, 이 키는 업로드에만 쓰인다.

## 3. 제출용 AAB 만들기

```powershell
.\scripts\android\package_release.ps1 -VersionCode 1 -VersionName 1.0.0
```
`.data\android-release\1.0.0-1\shadowprintshop-1.0.0-release.aab`과 검증 기록 `android-evidence.json`이 생긴다.
검증 항목: 서명, 패키지·버전, SDK 24/36, arm64 전용, 권한 없음, 가로, 런처 진입점, 적응형·단색 아이콘,
bundletool validate, AAB에서 만든 범용 APK 세트. 다시 올릴 때마다 `-VersionCode`를 1씩 올린다.

## 4. Play Console에서 (사용자)

1. 앱 만들기: 이름 "음영 인쇄소", 기본 언어 한국어, 게임, 무료/유료 선택.
2. 앱 콘텐츠: 개인정보처리방침 URL(`PRIVACY_POLICY_KO.md`를 웹에 게시), 광고 없음,
   데이터 보안(`DATA_SAFETY_KO.md`), 콘텐츠 등급 설문(`CONTENT_RATING_KO.md`), 대상 연령층(13세 이상 권장).
3. 스토어 등록정보: `STORE_LISTING_KO.md`의 문구와 `graphics/`의 이미지.
4. 테스트: 먼저 내부 테스트 트랙에 AAB를 올려 실제 기기에서 확인한다.
   2023년 11월 이후 만든 개인 개발자 계정은 프로덕션 출시 전에 일정 인원·기간의 비공개 테스트를 거쳐야 한다
   (작성 시점 기준 테스터 12명 이상·14일 이상으로 알려져 있으나, 현재 요건은 Play Console 안내로 확인한다).
5. 프로덕션 출시 검토 제출은 사용자의 판단으로 한다.

## 사람이 확인해야 하는 것

- 실제 휴대전화에서의 플레이: 손가락 닿는 범위, 글자 크기, 노치·둥근 모서리, 180° 회전, 뒤로 가기, 앱 전환 후 복귀, 소리.
- 60~90분 플레이 시간, 난이도, 한국어 문장, 아이콘·그래픽의 미적 판단, 권리 검토.
- 에뮬레이터 실행은 Google API x86_64 이미지에서 ARM 번역으로 확인한 것이며 실제 기기 검증을 대신하지 않는다.
