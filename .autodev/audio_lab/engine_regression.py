"""Unchanged game suites and isolated custom Windows export-template QA."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

import runner

auto = runner.auto


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--template-debug', type=Path, required=True)
    parser.add_argument('--template-release', type=Path, required=True)
    parser.add_argument('--label', default='engine-regression')
    parser.add_argument('--export-repeats', type=int, choices=range(1, 101), default=30)
    args = parser.parse_args()
    engine = args.engine.resolve(strict=True)
    run = args.run_dir.resolve(strict=True)
    if not run.is_relative_to(runner.ROOT / '.data'):
        raise ValueError('Workspace evidence directory required')
    previous = json.loads((run / 'results.json').read_text(encoding='utf-8'))
    if previous['godot_sha256'] != auto.sha(engine):
        raise ValueError('Engine differs from audio experiment')
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.label):
        raise ValueError('Unsafe evidence label')
    report_file = run / (args.label + '.json')
    if report_file.exists():
        raise ValueError('Preserve earlier regression evidence; use a fresh validation run')
    templates = {name: path.resolve(strict=True) for name, path in (
        ('debug', args.template_debug), ('release', args.template_release))}
    audit = {'engine_sha256': auto.sha(engine), 'templates': {
        key: {'sha256': auto.sha(path), 'path': str(path)} for key, path in templates.items()}, 'gates': []}

    def gate(name, cmd, marker=None, timeout=240, expect_audio=True):
        index = len(audit['gates']) + 1
        log = run / ('%s-%03d-%s.log' % (args.label, index, name))
        started = time.monotonic()
        result = {'name': name, 'passed': False, 'status': 'RUNNING', 'marker': marker,
                  'command': [str(v) for v in cmd], 'log': log.name}
        audit['gates'].append(result)
        runner.save(report_file, audit)
        with log.open('xb') as output:
            try:
                process = subprocess.run([str(v) for v in cmd], stdout=output, stderr=subprocess.STDOUT,
                                         timeout=timeout, env=runner.environment(run / (args.label + '_userdata') / str(index)))
                code = process.returncode
            except subprocess.TimeoutExpired:
                code = -1
                output.write(b'\nERROR: regression deadline exceeded\n')
        text = log.read_text(encoding='utf-8', errors='replace')
        wasapi = 'WASAPI: Activated output_device using' in text and 'falling back to the dummy driver' not in text
        errors = [line for line in text.splitlines() if runner.ERRORS.search(line)
                  or 'Leaked instance:' in line or 'Resource still in use:' in line]
        ok = code == 0 and not errors and (marker is None or marker in text) and (not expect_audio or wasapi)
        rendering_lines = [line for line in text.splitlines() if 'OpenGL API' in line or 'Vulkan API' in line]
        if name.endswith('-GRAPHICAL_PLAYBACK'):
            ok = ok and any('OpenGL API' in line for line in rendering_lines)
        result.update({'name': name, 'passed': ok, 'status': 'FINISHED', 'exit_code': code, 'marker': marker,
                  'wasapi_activated': wasapi, 'command': [str(v) for v in cmd], 'log': log.name,
                  'log_sha256': auto.sha(log), 'duration_s': round(time.monotonic() - started, 3), 'errors': errors,
                  'rendering_lines': rendering_lines})
        runner.save(report_file, audit)
        print(('PASS ' if ok else 'FAIL ') + name, flush=True)
        return ok

    def export(stage, tag, mode, fixture=None):
        export_stage = run / (args.label + '-project-' + tag)
        auto.copy_game(stage, export_stage)
        if fixture:
            source_probe = runner.HERE / ('original_immediate.gd' if fixture == 'immediate' else 'playback_verification.gd')
            target_probe = export_stage / source_probe.name
            shutil.copy2(source_probe, target_probe)
            if auto.sha(source_probe) != auto.sha(target_probe):
                raise ValueError('Export probe copy differs')
            if fixture == 'immediate' and auto.sha(target_probe) != previous['original_stress_sha256']:
                raise ValueError('Unchanged immediate probe hash mismatch')
            # Default templates intentionally disable CLI script/path overrides.
            # A separate QA pack inherits the unchanged SceneTree probe as its
            # configured main loop. An empty Node satisfies main-scene validation.
            (export_stage / 'audio_pack_entry.gd').write_text(
                'class_name AudioPackProbe\nextends "res://' + source_probe.name + '"\n', encoding='utf-8')
            (export_stage / 'audio_pack_boot.tscn').write_text(
                '[gd_scene format=3]\n[node name="AudioPackBoot" type="Node"]\n', encoding='utf-8')
            project = export_stage / 'project.godot'
            text = project.read_text(encoding='utf-8')
            if text.count('[application]') != 1 or 'run/main_loop_type=' in text:
                raise ValueError('Unexpected fixture startup settings')
            text = text.replace('[application]', '[application]\nrun/main_loop_type="AudioPackProbe"')
            text = '\n'.join('run/main_scene="res://audio_pack_boot.tscn"' if row.startswith('run/main_scene=') else row
                             for row in text.splitlines()) + '\n'
            project.write_text(text, encoding='utf-8')
            audit.setdefault('fixtures', {})[tag] = {'kind': fixture, 'probe_sha256': auto.sha(target_probe),
                'entry_sha256': auto.sha(export_stage / 'audio_pack_entry.gd'), 'project_sha256': auto.sha(project),
                'description': 'Separate QA pack; unchanged inherited probe, empty boot Node, no path-override changes.'}
        preset = auto.PRESET
        for key, path in templates.items():
            preset = preset.replace('custom_template/' + key + '=""', 'custom_template/' + key + '="' + path.as_posix() + '"')
        (export_stage / 'export_presets.cfg').write_text(preset, encoding='utf-8')
        output_dir = run / (args.label + '-export-' + tag)
        output_dir.mkdir()
        exe = output_dir / 'C01_Windows_Test.exe'
        prefix = [engine, '--headless', '--audio-driver', 'WASAPI', '--verbose', '--path', export_stage]
        if not gate(tag + '-IMPORT', prefix + ['--import'], timeout=360):
            return None
        exported = gate(tag + '-EXPORT', prefix + ['--export-' + mode, 'Windows Desktop', exe], timeout=360)
        files = (exe, exe.with_suffix('.pck'))
        usable = exported and all(path.is_file() and path.stat().st_size > 0 for path in files)
        same_binary = exe.is_file() and auto.sha(exe) == auto.sha(templates[mode])
        audit['gates'].append({'name': tag + '-FILES', 'passed': usable and same_binary,
            'files': {path.name: {'sha256': auto.sha(path), 'bytes': path.stat().st_size}
                      for path in files if path.is_file()}, 'exported_exe_equals_template': same_binary})
        runner.save(report_file, audit)
        return exe if usable and same_binary else None

    config = auto.load_json(auto.CONFIG)
    sys.path.insert(0, str(runner.ROOT))
    import engine_adapter
    for name in ('game-original', 'game-previous-candidate'):
        stage = run / (args.label + '-source-' + name)
        auto.copy_game(run / name, stage)
        before = auto.source_files(stage)
        static_ok, static_message = engine_adapter.check_sources(stage)
        audit['gates'].append({'name': name + '-STATIC', 'passed': static_ok, 'detail': static_message})
        runner.save(report_file, audit)
        prefix = [engine, '--headless', '--audio-driver', 'WASAPI', '--verbose', '--path', stage]
        if not gate(name + '-IMPORT', prefix + ['--import'], timeout=360):
            continue
        before = auto.source_files(stage)
        for entry in config['tests']:
            gate(name + '-' + entry['name'], prefix + ['--script', 'res://' + entry['script']], entry['marker'])
        gate(name + '-MECH', prefix + ['--script', 'res://tests/mech_cases.gd'], 'MECH checks=367008 sequences=8000 failures=0')
        gate(name + '-PROGRESS', prefix + ['--script', 'res://tests/progress_clarity_test.gd'], 'ITER_001_PROGRESS_CLARITY_PASS')
        gate(name + '-OFFLINE', [sys.executable, stage / 'tests/mech_offline.py'], 'PASS offline cases 8000', expect_audio=False)
        gate(name + '-QUALITY', prefix + ['--script', runner.ROOT / '.autodev/checks/quality_probe.gd'], 'AUTODEV_QUALITY_PASS checks=155')
        gate(name + '-PLAYBACK', prefix + ['--script', runner.HERE / 'playback_verification.gd'], '"passed":true')
        for mode in ('debug', 'release'):
            tag = name + '-' + mode
            exe = export(stage, tag, mode)
            if exe:
                gate(tag + '-BUILD_RUN', [exe, '--headless', '--audio-driver', 'WASAPI', '--verbose', '--quit-after', '90'], 'Godot Engine')
            probe_exe = export(stage, tag + '-immediate', mode, 'immediate')
            if probe_exe:
                for attempt in range(1, args.export_repeats + 1):
                    gate(tag + '-PACK_IMMEDIATE-%02d' % attempt,
                         [probe_exe, '--headless', '--audio-driver', 'WASAPI', '--verbose', '--quit-after', '90'], 'RAPID_SFX_IMMEDIATE_EXIT')
            if mode == 'release':
                playback_exe = export(stage, tag + '-playback', mode, 'playback')
                if playback_exe:
                    gate(tag + '-GRAPHICAL_PLAYBACK', [playback_exe, '--audio-driver', 'WASAPI', '--verbose',
                         '--rendering-method', 'gl_compatibility', '--quit-after', '600'], '"passed":true')
        if before != auto.source_files(stage):
            raise ValueError('Regression mutated source project: ' + name)
    return 0 if all(row['passed'] for row in audit['gates']) else 2


if __name__ == '__main__':
    raise SystemExit(main())
