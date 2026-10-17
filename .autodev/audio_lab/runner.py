"""Independent, real-process Godot audio lifetime experiments; no installation.

Every attempt is retained, including expected failing controls. A failing process,
wrong driver, ERROR or leaked-object warning is never classified as passing QA.
"""
from __future__ import annotations
import argparse
import collections
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / '.autodev'))
import auto

CASES = ('A', 'B', 'C', 'D', 'E', 'E_queue', 'F', 'E_drain', 'H_quit', 'H_free', 'H_drain', 'ORIGINAL_IMMEDIATE')
ERRORS = re.compile(r'(?im)^\s*(?:SCRIPT ERROR:|ERROR:|WARNING:.*(?:ObjectDB.*leak|resources? still in use))')

def save(path, data):
    temp = path.with_suffix('.' + uuid.uuid4().hex + '.tmp')
    temp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding='utf-8')
    os.replace(temp, path)

def parse_log(text, expected_driver, returncode, original=False):
    objects = collections.Counter(name.strip() or '<unknown>' for name in re.findall(r'Leaked instance:[ \t]*([^:\r\n]*):', text))
    resources = re.findall(r'Resource still in use:\s*(.+)', text)
    events = []
    for line in text.splitlines():
        if line.startswith(('LAB_BEGIN ', 'LAB_TRACE ', 'LAB_RESULT ')):
            try:
                events.append({'event': line.split(' ', 1)[0], **json.loads(line.split(' ', 1)[1])})
            except ValueError:
                pass
    result = next((e for e in reversed(events) if e['event'] == 'LAB_RESULT'), None)
    actual_driver = next((e.get('driver') for e in events if e['event'] == 'LAB_BEGIN'), None)
    if original and 'WASAPI: Activated output_device using' in text and 'falling back to the dummy driver' not in text:
        actual_driver = 'WASAPI'
    errors = [line for line in text.splitlines() if ERRORS.search(line)]
    return {'exit_code': returncode, 'driver_actual': actual_driver, 'events': events,
            'leaked_objects': dict(objects), 'leaked_object_count': sum(objects.values()),
            'resources_still_in_use': resources, 'error_lines': errors,
            'passed': returncode == 0 and actual_driver == expected_driver
                      and ((result is not None and result.get('completed') is True) if not original else 'RAPID_SFX_IMMEDIATE_EXIT' in text)
                      and not errors and not objects and not resources}

def environment(folder):
    env = os.environ.copy()
    for key, sub in [('APPDATA', 'roaming'), ('LOCALAPPDATA', 'local'), ('XDG_DATA_HOME', 'xdg')]:
        destination = folder / sub
        destination.mkdir(parents=True, exist_ok=True)
        env[key] = str(destination)
    return env

def command(godot, project, case, driver, log, env):
    # --audio-driver follows --headless deliberately: headless defaults to Dummy.
    original = case == 'ORIGINAL_IMMEDIATE'
    script = 'unchanged_immediate.gd' if original else 'audio_lifetime_probe.gd'
    args = [str(godot), '--headless', '--audio-driver', driver, '--verbose', '--path', str(project),
            '--script', 'res://' + script, '--', 'case=' + case]
    start = time.monotonic()
    with log.open('xb') as stream:
        try:
            process = subprocess.run(args, stdout=stream, stderr=subprocess.STDOUT, env=env, timeout=20)
            code = process.returncode
        except subprocess.TimeoutExpired:
            code = -1
            stream.write(b'\nERROR: LAB subprocess exceeded 20 second deadline\n')
    text = log.read_text(encoding='utf-8', errors='replace')
    return {**parse_log(text, driver, code, original), 'command': args, 'duration_s': round(time.monotonic() - start, 6),
            'log_sha256': auto.sha(log)}

def import_project(godot, project, run, name):
    log = run / (name + '-import.log')
    with log.open('xb') as output:
        process = subprocess.run([str(godot), '--headless', '--path', str(project), '--import'],
                                 stdout=output, stderr=subprocess.STDOUT, env=environment(run / 'import_userdata' / name), timeout=120)
    text = log.read_text(encoding='utf-8', errors='replace')
    if process.returncode or ERRORS.search(text):
        raise RuntimeError('Project import failed; preserved log: ' + log.name)

def prepare(run, godot):
    game = ROOT / auto.load_json(auto.CONFIG)['game_dir']
    minimal = run / 'minimal'
    (minimal / 'assets').mkdir(parents=True)
    (minimal / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="C01 Audio Lifetime Lab"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
    assets = {}
    for name in ('print', 'undo', 'complete'):
        source = game / 'assets/audio' / ('slice_' + name + '.wav')
        shutil.copy2(source, minimal / 'assets' / source.name)
        assets[source.name] = auto.sha(source)
    projects = {'minimal': minimal}
    sources = {'game-original': game,
               'game-previous-candidate': ROOT / '.autodev/runs/20261017-005228-b1610/game'}
    for name, source in sources.items():
        auto.copy_game(source, run / name)
        projects[name] = run / name
    for name, project in projects.items():
        shutil.copy2(HERE / 'probe.gd', project / 'audio_lifetime_probe.gd')
        import_project(godot, project, run, name)
    return projects, assets

def summary(results):
    groups = {}
    for result in results:
        key = '/'.join((result['project'], result['case'], result['driver_requested']))
        group = groups.setdefault(key, {'attempts': 0, 'passed': 0, 'failed': 0, 'leaked_objects': {}, 'duration_s': []})
        group['attempts'] += 1
        group['passed' if result['passed'] else 'failed'] += 1
        counts = collections.Counter(group['leaked_objects'])
        counts.update(result['leaked_objects'])
        group['leaked_objects'] = dict(counts)
        group['duration_s'].append(result['duration_s'])
    return groups

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repeats', type=int, choices=range(1, 101), default=5)
    parser.add_argument('--cases', nargs='+', choices=CASES, default=list(CASES[:-1]))
    parser.add_argument('--drivers', nargs='+', choices=['WASAPI', 'Dummy'], default=['WASAPI', 'Dummy'])
    parser.add_argument('--run-dir', type=Path, help='Append new attempts to a previously prepared lab run')
    args = parser.parse_args(argv)
    if 'ORIGINAL_IMMEDIATE' in args.cases and 'Dummy' in args.drivers:
        parser.error('The unchanged original probe identifies WASAPI via verbose driver activation; run it with --drivers WASAPI')
    config = auto.load_json(auto.CONFIG)
    godot = auto.resolve_godot(None, config)
    if args.run_dir:
        run = args.run_dir.resolve()
        if not run.is_relative_to(ROOT / '.data'):
            raise ValueError('Existing lab must stay inside workspace .data')
        report = json.loads((run / 'results.json').read_text(encoding='utf-8'))
        if report['godot_sha256'] != auto.sha(godot) or report['probe_sha256'] != auto.sha(HERE / 'probe.gd'):
            raise ValueError('Engine or probe changed: prepare a fresh lab, preserve earlier results')
        projects = {name: run / name for name in ('minimal', 'game-original', 'game-previous-candidate')}
    else:
        stamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6]
        run = ROOT / '.data' / ('audio-rootcause-' + stamp)
        run.mkdir()
        version = subprocess.run([str(godot), '--version'], capture_output=True, timeout=20).stdout.decode().strip()
        report = {'created_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
                  'baseline_commit': auto.git('rev-parse', 'HEAD'), 'godot': version,
                  'godot_sha256': auto.sha(godot), 'probe_sha256': auto.sha(HERE / 'probe.gd'),
                  'shutdown_executed': False, 'results': []}
        save(run / 'results.json', report)
        projects, assets = prepare(run, godot)
        report['assets_sha256'] = assets
    print('LAB_RUN=' + str(run), flush=True)
    if 'ORIGINAL_IMMEDIATE' in args.cases:
        original_sha = auto.sha(HERE / 'original_immediate.gd')
        if report.get('original_stress_sha256', original_sha) != original_sha:
            raise ValueError('Original stress probe changed')
        report['original_stress_sha256'] = original_sha
        for name in ('game-original', 'game-previous-candidate'):
            target = projects[name] / 'unchanged_immediate.gd'
            if target.exists() and auto.sha(target) != original_sha:
                raise ValueError('Existing original stress probe mismatch')
            if not target.exists():
                shutil.copy2(HERE / 'original_immediate.gd', target)
    for case in args.cases:
        names = ['game-original', 'game-previous-candidate'] if case.startswith('H_') or case == 'ORIGINAL_IMMEDIATE' else ['minimal']
        for name in names:
            for driver in args.drivers:
                for _ in range(args.repeats):
                    index = len(report['results']) + 1
                    log = run / ('%04d-%s-%s-%s.log' % (index, name, case, driver))
                    result = command(godot, projects[name], case, driver, log, environment(run / 'userdata' / str(index)))
                    result.update(project=name, case=case, driver_requested=driver, log=log.name, attempt=index)
                    report['results'].append(result)
                    report['groups'] = summary(report['results'])
                    save(run / 'results.json', report)
                    print('%s %s %s %s exit=%s leaks=%d %.3fs' % ('PASS' if result['passed'] else 'FAIL', name, case, driver,
                          result['exit_code'], result['leaked_object_count'], result['duration_s']), flush=True)
    return 0 if all(result['passed'] for result in report['results']) else 2

if __name__ == '__main__':
    raise SystemExit(main())
