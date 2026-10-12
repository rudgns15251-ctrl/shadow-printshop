#!/usr/bin/env python3
"""v0.7-D explicitly invoked fault-injection and regression audit.

No real Godot, WSL, Codex, Git mutation or user SQLite operations are made by the
new fault suite. The optional full suite includes pre-existing project tests.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent


def audit(full=False, report=False):
    env = os.environ.copy()
    env.update(PYTHONUTF8='1', PYTHONIOENCODING='utf-8', PYTHONDONTWRITEBYTECODE='1')
    pattern = 'test_*.py' if full else 'test_v07d_faults.py'
    cmd = [sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', pattern, '-v']
    proc = subprocess.run(cmd, cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace',
                          timeout=300 if full else 120, env=env)
    output = proc.stdout or ''
    print(output, end='' if output.endswith('\n') else '\n')
    count = re.search(r'Ran (\d+) tests? in ', output)
    success = proc.returncode == 0 and count is not None and re.search(r'(?m)^OK\s*$',output) is not None
    print(f'v0.7-D: {"PASS" if success else "FAIL"}; mode={"full" if full else "faults"}; tests={count.group(1) if count else "?"}')
    if report:
        dest = ROOT/'.data'/'v07d-reports'
        dest.mkdir(parents=True, exist_ok=True)
        name = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        payload = {'version':'0.7-D', 'mode':'full' if full else 'faults',
                   'status':'PASS' if success else 'FAIL', 'number_of_tests':int(count.group(1)) if count else None,
                   'exit_code':proc.returncode, 'utc':dt.datetime.now(dt.timezone.utc).isoformat(),
                   'warning':'Mocked fault-injection does not certify real failure recovery on host machine'}
        path = dest / (name+'.json')
        path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding='utf-8')
        print('REPORT:',path)
    return 0 if success else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description='v0.7-D isolated fault audit (no live execution)')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='Run isolated fault cases (default)')
    mode.add_argument('--full', action='store_true', help='Also execute all existing tests')
    parser.add_argument('--report', action='store_true', help='Save a small local JSON report under .data')
    args = parser.parse_args(argv)
    try:
        return audit(full=args.full, report=args.report)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print('v0.7-D: ERROR:',exc,file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
