# Read-only, local diagnostic. Does not include account names, paths or secret values.
$ErrorActionPreference = 'Continue'
Write-Host '== Windows game harness environment check ==' -ForegroundColor Cyan
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus = Get-CimInstance Win32_VideoController
Write-Host "OS: $($os.Caption) / build $($os.BuildNumber)"
Write-Host "CPU: $($cpu.Name)"
Write-Host "RAM(GB): $([math]::Round($os.TotalVisibleMemorySize / 1024 / 1024, 1))"
foreach ($gpu in $gpus) { Write-Host "GPU: $($gpu.Name)" }
foreach ($app in @('py','python','git','node','npm','codex')) {
  $c = Get-Command $app -ErrorAction SilentlyContinue
  if ($null -ne $c) { Write-Host "$($app): installed" }
  else { Write-Host "$($app): not found" }
}
Write-Host 'No passwords, tokens, account IDs or personal file paths are collected.'
