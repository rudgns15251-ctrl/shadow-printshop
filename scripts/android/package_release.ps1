# 음영 인쇄소 - Google Play 제출용 AAB 만들기 (사용자가 직접 실행)
#
# 커밋된 게임(기본 HEAD)을 사용자의 업로드 키로 서명한 AAB로 묶고 검증합니다.
# 암호는 화면에 보이지 않게 입력받아 이 실행의 환경 변수로만 넘기며 파일이나 로그에 남기지 않습니다.
# Play Console에 올릴 때마다 VersionCode를 1씩 올리세요(이전 업로드보다 커야 합니다).
param(
    [Parameter(Mandatory = $true)][int]$VersionCode,
    [Parameter(Mandatory = $true)][string]$VersionName,
    [string]$KeyStore = (Join-Path $env:USERPROFILE ".android-keys\shadowprintshop-upload.jks"),
    [string]$Alias = "upload",
    [string]$Ref = "HEAD",
    [string]$Out = ""
)
$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$python = Join-Path $repo "..\..\.venv\Scripts\python.exe"
if (-not (Test-Path $KeyStore)) { throw "업로드 키가 없습니다: $KeyStore (scripts\android\make_upload_key.ps1로 만드세요)" }
if (-not $Out) { $Out = Join-Path $repo (".data\android-release\" + $VersionName + "-" + $VersionCode) }
$secure = Read-Host "업로드 키 암호" -AsSecureString
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = (Resolve-Path $KeyStore).Path
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $Alias
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
try {
    & $python (Join-Path $PSScriptRoot "package_android.py") --mode release --format both --ref $Ref `
        --version-code $VersionCode --version-name $VersionName --out $Out
    if ($LASTEXITCODE -ne 0) { throw "패키징 또는 검증 실패 ($LASTEXITCODE). $Out\android-evidence.json을 확인하세요." }
} finally {
    Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH, Env:GODOT_ANDROID_KEYSTORE_RELEASE_USER, Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host "Play Console에 올릴 파일: $Out\shadowprintshop-$VersionName-release.aab"
