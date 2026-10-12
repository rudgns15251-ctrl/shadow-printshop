"""Harness-owned independent scene/input smoke gate for Godot 4 projects.

This is NOT gameplay-proof or a secure sandbox: it runs generated GDScript.
It stages the project in a temporary directory so agent worktrees stay intact.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import engine_adapter

ROOT = Path(__file__).resolve().parent
TRUSTED_SCRIPT = ROOT / 'qa' / 'scene_probe.gd'
REPORTS = ROOT / 'logs' / 'qa'
MARKER = 'HARNESS_QA_SCENE_PASS'


def safety_scan(project: Path) -> tuple[bool, str]:
    if not project.is_dir() or project.is_symlink():
        return False, 'Missing / symlink game directory'
    for item in project.rglob('*'):
        if item.is_symlink():
            return False, f'Symlink not permitted in staged game: {item.relative_to(project)}'
    return True, 'safe to stage (not a security sandbox)'


def run_engine(cmd: list[str], cwd: Path, timeout: int):
    return subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          encoding='utf-8', errors='replace', timeout=timeout, check=False)


def validate(workspace: Path, task: dict) -> tuple[bool, str]:
    """Independent harness-owned diagnostic script plus Godot import.

    Deliberately not a complete input/goal assertion: needs an approved game
    state adapter to certify gameplay semantics in a later milestone.
    """
    project = (Path(workspace) / engine_adapter.PROJECT_REL).resolve()
    workspace_root = Path(workspace).resolve()
    if not project.is_relative_to(workspace_root):
        return False, 'QA project outside workspace'
    ok, note = safety_scan(project)
    if not ok:
        return False, note
    if not TRUSTED_SCRIPT.is_file():
        return False, 'Harness-owned QA script is missing'
    regression = project / 'tests' / 'regression_test.gd'
    if task.get('require_regression') and not regression.is_file():
        return False, 'Missing regression_test.gd'
    exe = engine_adapter.locate()
    if not exe:
        return False, 'Godot not configured'
    REPORTS.mkdir(parents=True, exist_ok=True)
    report_path = REPORTS / f"{task['id']}.json"
    output = []
    try:
        with tempfile.TemporaryDirectory(prefix='harness-qa-') as tmp:
            stage = Path(tmp) / 'game'
            shutil.copytree(project, stage,
                            ignore=shutil.ignore_patterns('.godot', '.git', '*.tmp', '*.log'))
            (stage / 'tests').mkdir(parents=True, exist_ok=True)
            shutil.copyfile(TRUSTED_SCRIPT, stage / 'tests' / '__harness_probe.gd')
            stages = [('import', [exe, '--headless', '--path', str(stage), '--import'], 180)]
            if task.get('require_regression'):
                stages.append(('regression', [exe, '--headless', '--path', str(stage), '--script',
                                              'res://tests/regression_test.gd'], 90))
            stages.append(('probe', [exe, '--headless', '--path', str(stage), '--script',
                                    'res://tests/__harness_probe.gd'], 90))
            for phase, args, timeout in stages:
                result = run_engine(args, stage, timeout)
                text = result.stdout
                output.append({'phase': phase, 'exit': result.returncode,
                               'last_output': text[-6000:]})
                if result.returncode != 0 or re.search(r'(?im)^\s*(?:SCRIPT ERROR|ERROR|Parse Error):', text):
                    report_path.write_text(json.dumps({'passed': False, 'phases': output},
                                         ensure_ascii=False, indent=2), encoding='utf-8')
                    return False, f'Harness QA {phase} failed: {report_path}'
                if phase == 'regression' and 'HARNESS_REGRESSION_PASS' not in text:
                    report_path.write_text(json.dumps({'passed': False, 'phases': output},
                                         ensure_ascii=False, indent=2), encoding='utf-8')
                    return False, f'Godot regression marker missing: {report_path}'
                if phase == 'probe' and MARKER not in text:
                    report_path.write_text(json.dumps({'passed': False, 'phases': output},
                                         ensure_ascii=False, indent=2), encoding='utf-8')
                    return False, f'Harness QA marker missing: {report_path}'
    except (OSError, subprocess.TimeoutExpired, shutil.Error) as exc:
        output.append({'exception': str(exc)})
        report_path.write_text(json.dumps({'passed': False, 'phases': output},
                             ensure_ascii=False, indent=2), encoding='utf-8')
        return False, f'Harness QA could not run: {exc}'
    report_path.write_text(json.dumps({'passed': True, 'phases': output},
                         ensure_ascii=False, indent=2), encoding='utf-8')
    return True, f'Harness-owned scene/input smoke passed; report: {report_path}; manual gameplay review still required'
