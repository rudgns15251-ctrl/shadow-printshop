"""Independent raw-log/binary auditor; does not import the primary verdict parser."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import sys


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--report', default='engine-regression.json')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    run = args.run_dir.resolve(strict=True)
    if not run.is_relative_to(root / '.data') or Path(args.report).name != args.report:
        raise ValueError('Workspace evidence and a report basename are required')
    label = Path(args.report).stem
    report = json.loads((run / args.report).read_text(encoding='utf-8'))
    output = run / ('audit-' + label + '.json')
    if output.exists():
        raise ValueError('Preserve the earlier independent audit')
    errors = []
    seen = set()
    independent = {}
    groups = {}
    leak_objects = collections.Counter()
    sys.path.insert(0, str(root))
    import engine_adapter
    for row in report['gates']:
        name = row['name']
        if name in independent:
            raise ValueError('Repeated gate name: ' + name)
        if 'log' in row:
            if Path(row['log']).name != row['log'] or row['log'] in seen:
                raise ValueError('Unsafe or repeated raw log')
            seen.add(row['log'])
            log = run / row['log']
            if not log.is_file() or sha(log) != row.get('log_sha256'):
                errors.append(name + ': missing raw log or hash mismatch')
                independent[name] = False
                continue
            text = log.read_text(encoding='utf-8', errors='replace')
            diagnostic = re.search(r'(?im)^\s*(?:ERROR:|SCRIPT ERROR:|WARNING:.*(?:leak|still in use))', text)
            objects = collections.Counter(item.strip() or '<unknown>' for item in re.findall(r'Leaked instance:[ \t]*([^:\r\n]*):', text))
            leak_objects.update(objects)
            diagnostic = diagnostic or bool(objects) or 'Resource still in use:' in text
            audio = '--audio-driver' in row['command']
            driver = 'WASAPI: Activated output_device using' in text and 'falling back to the dummy driver' not in text
            marker = row.get('marker')
            ok = row.get('exit_code') == 0 and not diagnostic and (not marker or marker in text) and (not audio or driver)
            if name.endswith('-GRAPHICAL_PLAYBACK') or name.endswith('-PLAYBACK'):
                payloads = [json.loads(line[len('PLAYBACK_RESULT '):]) for line in text.splitlines() if line.startswith('PLAYBACK_RESULT ')]
                grid = {(phase, sound) for phase in ('initial', 'after_unmute', 'after_zero_volume') for sound in ('print', 'undo', 'complete')}
                ok = ok and len(payloads) == 1
                if payloads:
                    payload = payloads[0]
                    measures = payload['measurements']
                    ok = ok and payload['passed'] is True and payload['driver'] == 'WASAPI'
                    ok = ok and len(measures) == 9 and {(m['phase'], m['sound']) for m in measures} == grid
                    ok = ok and all(m['passed'] is True and m['peak_db'] > -70.0 for m in measures)
                if name.endswith('-GRAPHICAL_PLAYBACK'):
                    ok = ok and 'OpenGL API' in text
            if '-PACK_IMMEDIATE-' in name:
                key = name.rsplit('-PACK_IMMEDIATE-', 1)[0]
                group = groups.setdefault(key, {'attempts': 0, 'passed': 0, 'failed': 0,
                                                 'leak_attempts': 0, 'leaked_objects': 0})
                group['attempts'] += 1
                group['passed' if ok else 'failed'] += 1
                group['leak_attempts'] += bool(objects or re.search(r'(?im)^.*(?:ObjectDB.*leak|resources still in use)', text))
                group['leaked_objects'] += sum(objects.values())
        elif name.endswith('-FILES'):
            tag = name[:-len('-FILES')]
            mode = re.search(r'-(debug|release)(?:-|$)', tag).group(1)
            folder = run / (label + '-export-' + tag)
            template_sha = report['templates'][mode]['sha256']
            template = Path(report['templates'][mode]['path'])
            ok = independent.get(tag + '-EXPORT', False) and template.is_file() and sha(template) == template_sha
            for filename in ('C01_Windows_Test.exe', 'C01_Windows_Test.pck'):
                file = folder / filename
                entry = row.get('files', {}).get(filename, {})
                ok = ok and file.is_file() and file.stat().st_size == entry.get('bytes') and sha(file) == entry.get('sha256')
            exe = folder / 'C01_Windows_Test.exe'
            ok = ok and sha(exe) == template_sha
        elif name.endswith('-STATIC'):
            project = name[:-len('-STATIC')]
            ok, _ = engine_adapter.check_sources(run / (label + '-source-' + project))
        else:
            errors.append(name + ': unsupported gate type')
            ok = False
        independent[name] = bool(ok)
        if bool(ok) != row['passed']:
            errors.append(name + ': primary/independent verdict mismatch')
    expected = {project + '-' + mode for project in ('game-original', 'game-previous-candidate') for mode in ('debug', 'release')}
    complete = set(groups) == expected and all(group['attempts'] == 30 for group in groups.values())
    result = {'evidence_consistent': not errors, 'errors': errors, 'raw_logs': len(seen),
              'gates': len(independent), 'independently_passed': sum(independent.values()),
              'independently_failed': sum(not value for value in independent.values()),
              'export_stress_groups': groups, 'export_30_groups_complete': complete,
              'export_stress_all_passed': complete and all(group['failed'] == 0 for group in groups.values()),
              'leaked_objects': dict(leak_objects), 'all_report_gates_passed': bool(independent) and all(independent.values()),
              'scope': 'Evidence and Windows export audit; full project/engine certification is separate.'}
    with output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
    print(json.dumps(result, indent=2))
    return 0 if not errors else 2


if __name__ == '__main__':
    raise SystemExit(main())
