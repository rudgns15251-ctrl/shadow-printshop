param([ValidateSet('start','status','report','pause','resume','recover')][string]$Action='status')
$ErrorActionPreference = 'Stop'
$productionPython = Join-Path $PSScriptRoot '.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $productionPython)) {
    throw 'Existing project .venv Python is required. This launcher never installs dependencies.'
}
& $productionPython -X utf8 (Join-Path $PSScriptRoot '.autodev/director.py') $Action
exit $LASTEXITCODE
