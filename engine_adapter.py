"""Godot 4.x execution gate for game-harness v0.4.

The engine is not installed or downloaded automatically. Running a generated
project executes game scripts with the user's operating-system permissions.
This is a technical smoke check, NOT a sandbox or a fun/quality certification.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CONFIG = ROOT / '.data' / 'godot_path.txt'
PROJECT_REL = 'projects/first-game/game'
VERSION_RE = re.compile(r'(^|[^0-9])4\.[0-9]+')
REQUIRED = ('project.godot', 'main.tscn', 'scripts/game_state.gd', 'tests/smoke_test.gd')
BANNED_CALLS = (
    re.compile(r'\bOS\s*\.\s*(execute|create_process|kill)\s*\('),
    re.compile(r'\bDirAccess\s*\.\s*(remove_absolute|rename_absolute)\s*\('),
)


def run_command(cmd, timeout=90, cwd=None):
    return subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          encoding='utf-8', errors='replace', timeout=timeout, check=False)


def version(path):
    try:
        out = run_command([str(path), '--version'], 20)
        if out.returncode != 0 or not VERSION_RE.search(out.stdout):
            return None
        return out.stdout.strip().splitlines()[0][:160]
    except (OSError, subprocess.TimeoutExpired):
        return None


def locate():
    candidates = []
    if os.environ.get('GODOT_BIN'):
        candidates.append(os.environ['GODOT_BIN'])
    if CONFIG.is_file():
        candidates.append(CONFIG.read_text(encoding='utf-8').strip())
    for exe in ('godot', 'godot4', 'godot.exe', 'Godot.exe'):
        located = shutil.which(exe)
        if located:
            candidates.append(located)
    for candidate in candidates:
        raw = Path(candidate).expanduser()
        if raw.is_file() and version(raw):
            return str(raw.resolve())
    return None


def configure(executable):
    file = Path(executable).expanduser()
    if not file.is_file():
        raise RuntimeError('Godot executable not found; provide full path to the .exe')
    actual = version(file)
    if not actual:
        raise RuntimeError('Godot 4.x executable not verified; refusing to save path')
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(str(file.resolve()), encoding='utf-8')
    return actual


def check_sources(folder):
    if folder.is_symlink() or not folder.is_dir():
        return False, 'Missing or linked game project directory'
    for item in REQUIRED:
        p = folder / item
        if not p.is_file() or p.is_symlink():
            return False, 'Missing or linked Godot artifact: ' + item
    if (folder / 'addons').exists() or (folder / 'bin').exists():
        return False, 'Third-party addons/binaries require separate human approval'
    for suffix in ('.gd', '.gdextension', '.dll', '.exe'):
        for path in folder.rglob('*'+suffix):
            if path.is_symlink():
                return False, 'Symlink found: ' + str(path)
            if suffix != '.gd':
                return False, 'Native executable/extension needs manual review: '+str(path)
            text = path.read_text(encoding='utf-8', errors='replace')
            if any(pattern.search(text) for pattern in BANNED_CALLS):
                return False, 'Blocked potentially destructive Godot call: ' + str(path)
    return True, 'Source preflight passed (not a security sandbox)'


def validate(workspace, task):
    """Technical smoke gate (only for tasks declaring godot_validation=true)."""
    folder = Path(workspace) / PROJECT_REL
    ok, reason = check_sources(folder)
    if not ok:
        return False, reason
    exe = locate()
    if not exe:
        return False, 'Godot 4.x not configured. Run engine_adapter.py configure <full-path-to-godot.exe>'
    # The Godot editor import and smoke script may run generated code. This
    # should be done on a non-privileged, dedicated development PC/VM.
    commands = [
        ('import', [exe, '--headless', '--path', str(folder), '--import'], 180),
        ('smoke', [exe, '--headless', '--path', str(folder), '--script', 'res://tests/smoke_test.gd'], 90),
        ('launch', [exe, '--headless', '--path', str(folder), '--quit-after', '5'], 90),
    ]
    log_dir = ROOT / 'logs' / 'godot'
    log_dir.mkdir(parents=True, exist_ok=True)
    lines = []
    for name, cmd, timeout in commands:
        try:
            result = run_command(cmd, timeout=timeout, cwd=folder)
            lines.append(f'[{name}] exit={result.returncode}\n{result.stdout}')
            text = result.stdout
            if result.returncode or re.search(r'(?im)^\s*(SCRIPT ERROR|ERROR|Parse Error):', text):
                (log_dir / (task['id']+'.log')).write_text('\n'.join(lines), encoding='utf-8')
                return False, f'Godot {name} check failed; inspect logs/godot/{task["id"]}.log'
            if name == 'smoke' and 'HARNESS_SMOKE_PASS' not in text:
                (log_dir / (task['id']+'.log')).write_text('\n'.join(lines), encoding='utf-8')
                return False, 'Godot smoke result marker missing; must check tests/smoke_test.gd'
        except (OSError, subprocess.TimeoutExpired) as exc:
            (log_dir / (task['id']+'.log')).write_text('\n'.join(lines)+f'\n{name} exception: {exc}', encoding='utf-8')
            return False, f'Godot {name} could not complete: {exc}'
    (log_dir / (task['id']+'.log')).write_text('\n'.join(lines), encoding='utf-8')
    return True, 'Godot headless import, generated smoke test, scene launch passed; human playtest still needed'


def main():
    parser = argparse.ArgumentParser(description='Godot engine check for game-harness v0.4')
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('doctor')
    cfg = sub.add_parser('configure')
    cfg.add_argument('executable')
    chk = sub.add_parser('check')
    chk.add_argument('project_dir', nargs='?', default=PROJECT_REL)
    args = parser.parse_args()
    try:
        if args.command == 'doctor':
            exe = locate()
            if not exe:
                print('GODOT_NOT_FOUND: no Godot 4.x editor detected.')
                print('Download the Windows standard editor, then configure full exe path.')
            else:
                print('GODOT_OK:', exe, version(exe))
        elif args.command == 'configure':
            print('GODOT_CONFIGURED:', configure(args.executable))
        else:
            exe = locate()
            if not exe:
                raise RuntimeError('Configure Godot first with engine_adapter.py configure <exe>')
            folder = (ROOT / args.project_dir).resolve()
            if not folder.is_relative_to(ROOT.resolve()):
                raise RuntimeError('Project directory outside harness repository')
            ok, detail = validate(ROOT, {'id': 'MANUAL-CHECK'}) if folder == (ROOT / PROJECT_REL).resolve() else (False, 'Only the configured game project can be checked')
            print('PASS:' if ok else 'FAIL:', detail)
            return 0 if ok else 1
    except (OSError, RuntimeError, ValueError) as exc:
        print('ERROR:', exc, file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
