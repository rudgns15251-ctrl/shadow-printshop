# 음영 인쇄소 - Google Play 업로드 키 만들기 (사용자가 직접 한 번 실행)
#
# 업로드 키는 Play Console에 올리는 AAB에 서명하는 사용자의 키입니다. 이 스크립트는
# 키 파일을 저장소 밖(기본: %USERPROFILE%\.android-keys)에 만들고 SHA-256 지문을 보여 줍니다.
# 암호는 화면에 보이지 않게 입력받으며 어디에도 저장하지 않습니다.
# 키 파일과 암호를 잃으면 Play Console에서 업로드 키 재설정을 요청해야 하므로 따로 백업하세요.
param(
    [string]$KeyStore = (Join-Path $env:USERPROFILE ".android-keys\shadowprintshop-upload.jks"),
    [string]$Alias = "upload"
)
$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$jdk = Get-ChildItem (Join-Path $repo ".data\android-toolchain\jdk17") -Directory | Select-Object -First 1
$keytool = Join-Path $jdk.FullName "bin\keytool.exe"
if (-not (Test-Path $keytool)) { throw "keytool을 찾지 못했습니다: $keytool" }
$full = [System.IO.Path]::GetFullPath($KeyStore)
if ($full.StartsWith([string]$repo, [System.StringComparison]::OrdinalIgnoreCase)) { throw "키는 저장소 밖에 두세요: $full" }
if (Test-Path $full) { throw "이미 키 파일이 있습니다(덮어쓰지 않음): $full" }
New-Item -ItemType Directory -Force (Split-Path $full) | Out-Null

$first = Read-Host "새 키 암호(6자 이상)" -AsSecureString
$second = Read-Host "암호 확인" -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($first))
$check = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($second))
if ($plain -ne $check) { throw "두 암호가 다릅니다." }
if ($plain.Length -lt 6) { throw "암호는 6자 이상이어야 합니다." }
$name = Read-Host "인증서 이름(예: 개발자 또는 스튜디오 이름)"

# The password reaches keytool through an environment variable, not the command line.
$env:SP_UPLOAD_PASS = $plain
try {
    & $keytool -genkeypair -v -keystore $full -alias $Alias -keyalg RSA -keysize 4096 -validity 10000 `
        -storepass:env SP_UPLOAD_PASS -keypass:env SP_UPLOAD_PASS -dname "CN=$name"
    if ($LASTEXITCODE -ne 0) { throw "keytool 실패 ($LASTEXITCODE)" }
    & $keytool -list -v -keystore $full -alias $Alias -storepass:env SP_UPLOAD_PASS | Select-String "SHA256:"
} finally {
    Remove-Item Env:SP_UPLOAD_PASS -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host "업로드 키를 만들었습니다: $full (별칭 $Alias)"
Write-Host "키 파일과 암호를 안전한 곳에 따로 백업하세요. 저장소에는 넣지 마세요."
