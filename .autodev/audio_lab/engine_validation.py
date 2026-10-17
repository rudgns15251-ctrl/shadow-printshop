"""Run the unchanged audio experiments against an explicitly selected engine.

No config changes, probe edits, installations, or replacement of export templates.
Each engine has its own evidence directory. All failed attempts remain recorded.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import shutil
import subprocess

import runner

auto = runner.auto


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', required=True, type=Path)
    parser.add_argument('--run-dir', required=True, type=Path)
    parser.add_argument('--phase', required=True, choices=['control', 'stress', 'original'])
    parser.add_argument('--repeats', type=int, choices=range(1, 101), default=30)
    args = parser.parse_args()
    engine = args.engine.resolve(strict=True)
    run = args.run_dir.resolve()
    if not run.is_relative_to(runner.ROOT / '.data'):
        raise ValueError('Evidence must remain inside workspace .data')
    hashes = {'godot_sha256': auto.sha(engine), 'probe_sha256': auto.sha(runner.HERE / 'probe.gd'),
              'original_stress_sha256': auto.sha(runner.HERE / 'original_immediate.gd')}
    if hashes['original_stress_sha256'] != 'c2d324affd3f97c4e59eec50397ed35ba86c762b84d7c4b29854f9da8d49273d':
        raise ValueError('Original immediate-exit test changed')
    if (run / 'results.json').exists():
        report = json.loads((run / 'results.json').read_text(encoding='utf-8'))
        if any(report.get(key) != value for key, value in hashes.items()):
            raise ValueError('Engine/probe changed; preserve evidence and use a fresh directory')
    else:
        run.mkdir(parents=True, exist_ok=False)
        version = subprocess.run([str(engine), '--version'], capture_output=True, timeout=20, check=True)
        report = {'created_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                  'baseline_commit': auto.git('rev-parse', 'HEAD'),
                  'godot': version.stdout.decode('utf-8', 'replace').strip(),
                  **hashes, 'shutdown_executed': False, 'results': []}
        runner.save(run / 'results.json', report)
        projects, assets = runner.prepare(run, engine)
        report['assets_sha256'] = assets
        report['source_snapshots'] = {name: auto.source_files(project)
                                      for name, project in projects.items()}
        runner.save(run / 'results.json', report)
    projects = {name: run / name for name in ('minimal', 'game-original', 'game-previous-candidate')}
    if 'assets_sha256' not in report:
        raise ValueError('Preparation was incomplete; use a new directory and preserve import logs')
    cases = {'control': ['A', 'B', 'F'], 'stress': ['C', 'D', 'E', 'E_queue', 'H_quit', 'H_free'],
             'original': ['ORIGINAL_IMMEDIATE']}[args.phase]
    drivers = ['WASAPI'] if args.phase == 'original' else ['WASAPI', 'Dummy']
    if args.phase == 'original':
        for name in ('game-original', 'game-previous-candidate'):
            target = projects[name] / 'unchanged_immediate.gd'
            if target.exists() and auto.sha(target) != hashes['original_stress_sha256']:
                raise ValueError('Copied original probe differs')
            if not target.exists():
                shutil.copy2(runner.HERE / 'original_immediate.gd', target)
    print('LAB_RUN=' + str(run), flush=True)
    for case in cases:
        names = ['game-original', 'game-previous-candidate'] if case.startswith('H_') or case == 'ORIGINAL_IMMEDIATE' else ['minimal']
        for name in names:
            for driver in drivers:
                for _ in range(args.repeats):
                    index = len(report['results']) + 1
                    log = run / ('%04d-%s-%s-%s.log' % (index, name, case, driver))
                    result = runner.command(engine, projects[name], case, driver, log,
                                            runner.environment(run / 'userdata' / str(index)))
                    result.update(project=name, case=case, driver_requested=driver, log=log.name, attempt=index)
                    report['results'].append(result)
                    report['groups'] = runner.summary(report['results'])
                    runner.save(run / 'results.json', report)
                    print('%s %s %s %s exit=%s leaks=%d %.3fs' % (
                        'PASS' if result['passed'] else 'FAIL', name, case, driver,
                        result['exit_code'], result['leaked_object_count'], result['duration_s']), flush=True)
    for name, expected in report['source_snapshots'].items():
        actual = auto.source_files(projects[name])
        actual.pop('unchanged_immediate.gd', None)
        if actual != expected:
            raise ValueError('Project changed during validation: ' + name)
    return 0 if all(result['passed'] for result in report['results']) else 2


if __name__ == '__main__':
    raise SystemExit(main())
