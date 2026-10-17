"""Second process audits raw artifacts without using runner.parse_log's verdict."""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import sys

def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run-dir', required=True, type=Path)
    args = parser.parse_args()
    run = args.run_dir.resolve()
    root = Path(__file__).resolve().parents[2]
    if not run.is_relative_to(root / '.data'):
        raise ValueError('Evidence must be inside the workspace')
    data = json.loads((run / 'results.json').read_text(encoding='utf-8'))
    errors = []
    seen = set()
    totals = collections.Counter()
    for result in data['results']:
        name = result['log']
        if Path(name).name != name or name in seen:
            raise ValueError('Unsafe or repeated log path')
        seen.add(name)
        file = run / name
        text = file.read_text(encoding='utf-8', errors='replace')
        if digest(file) != result['log_sha256']:
            errors.append(name + ': raw log hash mismatch')
        diagnostic_failure = re.search(r'(?im)^\s*(?:ERROR:|SCRIPT ERROR:|WARNING:.*(?:leak|still in use))', text)
        diagnostic_failure = diagnostic_failure or 'Leaked instance:' in text or 'Resource still in use:' in text
        if result['case'] == 'ORIGINAL_IMMEDIATE':
            driver_ok = result['driver_requested'] == 'WASAPI' and 'WASAPI: Activated output_device using' in text
            completed = 'RAPID_SFX_IMMEDIATE_EXIT' in text
        else:
            begin = [json.loads(line[10:]) for line in text.splitlines() if line.startswith('LAB_BEGIN ')]
            end = [json.loads(line[11:]) for line in text.splitlines() if line.startswith('LAB_RESULT ')]
            driver_ok = len(begin) == 1 and begin[0]['driver'] == result['driver_requested']
            completed = len(end) == 1 and end[0]['completed'] is True
        driver_ok = driver_ok and 'falling back to the dummy driver' not in text
        independent_pass = result['exit_code'] == 0 and driver_ok and completed and not diagnostic_failure
        if bool(independent_pass) != result['passed']:
            errors.append(name + ': independent verdict disagrees')
        totals['passed' if independent_pass else 'failed'] += 1
    original = root / '.autodev/audio_lab/original_immediate.gd'
    if digest(original) != data['original_stress_sha256']:
        errors.append('Original stress source hash mismatch')
    if original.read_bytes() != (root / '.data/harness-upgrade-20261017/immediate_audio.gd').read_bytes():
        errors.append('Original test is not byte identical to the preserved earlier test')
    strict = {key: value for key, value in data['groups'].items() if '/ORIGINAL_IMMEDIATE/WASAPI' in key}
    strict_pass = len(strict) == 2 and all(value['attempts'] == 30 and value['failed'] == 0 for value in strict.values())
    audit = {'evidence_consistent': not errors, 'errors': errors, 'attempts': len(data['results']),
             'independently_passed': totals['passed'], 'independently_failed': totals['failed'],
             'unique_raw_logs': len(seen), 'strict_wasapi_30_all_pass': strict_pass,
             'AUDIO_LEAK_RESOLVED': False,
             'status': 'CONDITION_NOT_REPRODUCED' if strict_pass and not errors else 'BLOCKED',
             'reason': ('This condition passed; full regression and patched-engine certification remain separate.'
                        if strict_pass and not errors else
                        'Original immediate-exit acceptance failed or evidence is inconsistent; no resolution is certified.')}
    (run / 'independent-audit.json').write_text(json.dumps(audit, indent=2), encoding='utf-8')
    print(json.dumps(audit, indent=2))
    return 2 if not strict_pass or errors else 0

if __name__ == '__main__':
    raise SystemExit(main())
