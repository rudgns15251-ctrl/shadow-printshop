# Steam 인디게임 자율 개발 하네스 0.1 (Windows)

현재 C01용 확장 실행 방법과 검증·복구 정책은 [자율 개발 안내](docs/AUTONOMOUS_HARNESS_KO.md)를 참고하세요.
아래 내용은 초기 하네스의 호환 인터페이스 설명입니다.

이 패키지는 **게임 자체가 아닌 자동화 하네스의 첫 단계**입니다. 현재 구현: PC 진단, 작업 명세, Codex CLI 호출, Git 격리(worktree), 파일 범위 검증, 작업 상태 SQLite 기록, 사람 승인 후 Git 통합. 이후 단계: 자동 수정 재시도, 게임 엔진 테스트, 실제 플레이 평가, 비용 추적, 12주 개발 계획.

## 1. 사전 준비
- Python 3.11 이상, Git for Windows, Node.js LTS 설치
- PowerShell에서 `npm install -g @openai/codex@latest` 및 `codex login`
- 기존 Python/Git/Codex가 준비되어 있으면 재설치하지 않아도 됩니다.

## 2. PC 사양·설치 확인 (읽기 전용)
압축을 풀고 PowerShell에서 패키지 디렉터리로 이동해 실행:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\doctor.ps1
```
이 스크립트는 계정명·비밀값·개인 파일 경로를 표시하지 않습니다. 출력된 OS/CPU/RAM/GPU/설치 여부만 채팅으로 전달하세요.

## 3. 부트스트랩
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```
로컬 Python 테스트가 먼저 실행됩니다. 일부 Windows PC에서 Codex CLI가 PowerShell에서 실행되지 않으면 설치 상태를 먼저 확인하세요.

## 4. Git 최초 커밋 (필수)
프로젝트 루트에 PowerShell을 열고 Git 이름·이메일이 설정되어 있는지 확인한 다음:
```powershell
git add .
git commit -m "Initial game harness starter"
```
Git user.name/user.email이 없다는 오류가 나면 개인 환경에 맞게 `git config --global user.name "..."` 및 `git config --global user.email "..."`로 설정합니다. **개인 이메일 주소를 이 채팅에 붙여 넣을 필요는 없습니다.**

## 5. 첫 작업 시험
```powershell
.\.venv\Scripts\python.exe harness.py doctor
.\.venv\Scripts\python.exe harness.py status
.\.venv\Scripts\python.exe harness.py run PLAN-001
```
여기까지는 AI 사용량이 발생하지 않습니다.

Codex 로그인 후 실제 실행:
```powershell
codex login
.\.venv\Scripts\python.exe harness.py run PLAN-001 --live
```
이 마지막 명령은 Codex를 실제 호출하므로 사용량이 발생할 수 있습니다. Codex가 생성한 후보 기획서는 `.worktrees/PLAN-001/projects/first-game/design/concepts.md`에 남으며 자동 통합되지 않습니다.

검토하고 수용할 경우:
```powershell
.\.venv\Scripts\python.exe harness.py inspect PLAN-001
.\.venv\Scripts\python.exe harness.py approve PLAN-001
```
승인을 하면 작업 결과가 현재 Git 브랜치에 커밋됩니다.

## 제한과 주의
- **0.1 버전은 아직 24시간 자율 운영이나 자동 반복 수정 기능을 제공하지 않습니다.** 코드가 실행·검증된 기반을 만든 뒤 점진적으로 확장할 예정입니다.
- 최소 권한으로 실행하지만, 로컬 CLI 샌드박스만으로 절대적인 보안을 보장하지 않습니다. 별도 폴더·Git 저장소 사용을 권장합니다.
- `--live` 외에는 Codex를 호출하지 않습니다. 실행 시간 초과·오류 시 작업이 `blocked`로 남고 파일은 삭제하지 않습니다.
- 테스트를 통과한 기획서도 인간의 판단과 시장·플레이테스트를 대신하지 않습니다.
- Steam 등록비 납부·계정 생성·게임 출시 등 외부 행위는 자동으로 수행하지 않습니다.
