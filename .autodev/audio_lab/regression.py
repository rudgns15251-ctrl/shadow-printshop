"""Run preserved game suites against the lab copies using actual Windows audio."""
import argparse
import json
from pathlib import Path
import sys
import time
import subprocess

import runner
auto = runner.auto

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run-dir', required=True, type=Path)
    args = parser.parse_args()
    run = args.run_dir.resolve()
    if not run.is_relative_to(runner.ROOT / '.data'):
        raise ValueError('Lab must remain in workspace .data')
    config = auto.load_json(auto.CONFIG)
    godot = auto.resolve_godot(None, config)
    audit = {'engine': subprocess.run([str(godot), '--version'], capture_output=True).stdout.decode().strip(),
             'engine_sha256': auto.sha(godot), 'driver': 'WASAPI', 'gates': []}
    def gate(name, cmd, marker=None):
        index = len(audit['gates']) + 1
        log = run / ('regression-%02d-%s.log' % (index, name))
        if log.exists():
            raise ValueError('Earlier regression evidence exists; do not overwrite')
        started = time.monotonic()
        rc, text = auto.run_process([str(v) for v in cmd], log, 240,
                                    env=runner.environment(run / 'regression_userdata' / str(index)))
        audio = '--audio-driver' in cmd
        actual_wasapi = 'WASAPI: Activated output_device using' in text
        ok = rc == 0 and not runner.ERRORS.search(text) and (marker is None or marker in text)
        if audio:
            ok = ok and actual_wasapi and 'falling back to the dummy driver' not in text
        record = {'name': name, 'passed': ok, 'exit_code': rc, 'command': [str(v) for v in cmd],
                  'wasapi_activated': actual_wasapi, 'duration_s': round(time.monotonic() - started, 6),
                  'log': log.name, 'sha256': auto.sha(log), 'marker': marker,
                  'error_lines': [line for line in text.splitlines() if runner.ERRORS.search(line)]}
        audit['gates'].append(record)
        runner.save(run / 'regression.json', audit)
        print(('PASS ' if ok else 'FAIL ') + name, flush=True)
        return ok
    for project in ('game-original', 'game-previous-candidate'):
        stage = run / project
        prefix = [str(godot), '--headless', '--audio-driver', 'WASAPI', '--verbose', '--path', str(stage)]
        for entry in config['tests']:
            gate(project + '-' + entry['name'], prefix + ['--script', 'res://' + entry['script']], entry['marker'])
        gate(project + '-OFFLINE', [sys.executable, str(stage / 'tests/mech_offline.py')], 'PASS offline cases 8000')
        gate(project + '-QUALITY', prefix + ['--script', str(runner.ROOT / '.autodev/checks/quality_probe.gd')], 'AUTODEV_QUALITY_PASS checks=155')
        export_root = run / ('export-' + project)
        export_root.mkdir()
        (export_root / 'logs').mkdir()
        try:
            archive = auto.make_release(godot, stage, export_root, config)
            audit['gates'].append({'name': project + '-EXPORT', 'passed': True, 'archive': str(archive.relative_to(run))})
            exe = export_root / 'release' / config['exe_name']
            audit.setdefault('builds', {})[project] = {
                p.name: {'bytes': p.stat().st_size, 'sha256': auto.sha(p)}
                for p in (exe, exe.with_suffix('.pck'))}
            gate(project + '-BUILD_RUN', [str(exe), '--headless', '--audio-driver', 'WASAPI', '--verbose', '--quit-after', '90'], 'Godot Engine')
        except Exception as exc:
            audit['gates'].append({'name': project + '-EXPORT', 'passed': False, 'error': str(exc)})
            runner.save(run / 'regression.json', audit)
    runner.save(run / 'regression.json', audit)
    return 0 if all(g['passed'] for g in audit['gates']) else 2

if __name__ == '__main__':
    raise SystemExit(main())
