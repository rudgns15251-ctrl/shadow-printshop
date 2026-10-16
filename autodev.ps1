# Thin Windows entry point; preserves the existing Python CLI and exit code.
$ErrorActionPreference = 'Stop'
$runnerPython = Join-Path $PSScriptRoot '.venv/Scripts/python.exe'
$runnerScript = Join-Path $PSScriptRoot '.autodev/auto.py'
if (-not (Test-Path -LiteralPath $runnerPython -PathType Leaf)) {
    Write-Error 'Existing .venv Python is missing. No dependencies were installed.'
    exit 2
}
& $runnerPython $runnerScript @args
exit $LASTEXITCODE
