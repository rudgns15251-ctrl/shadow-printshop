$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
Write-Host '=== Game Harness 0.1 Bootstrap ===' -ForegroundColor Cyan
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw 'Python is missing. Install Python 3.11+.' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is missing. Install Git for Windows.' }
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { throw 'Codex CLI is missing. npm install -g @openai/codex@latest' }
if (-not (Test-Path '.git')) { git init }
if (-not (Test-Path '.venv')) { python -m venv .venv }
& .\.venv\Scripts\python.exe -m unittest discover -s tests -v
if ($LASTEXITCODE -ne 0) { throw 'Local tests failed.' }
& .\.venv\Scripts\python.exe harness.py init
Write-Host 'Bootstrap passed. Next: create the first Git commit, login to Codex, then run dry-run.' -ForegroundColor Green
