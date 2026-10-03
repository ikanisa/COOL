#!/usr/bin/env python3
"""Capture this additive fixture's real command result and changing inputs."""
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = pathlib.Path(__file__).resolve().parent / sys.argv[1]
OUT.mkdir(exist_ok=False)
FLUTTER = '/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter'
TEST = 'test/features/privacy/privacy_request_screen_test.dart'


def inventory():
    paths = list(ROOT.glob('lib/**/*.dart'))
    paths += list(ROOT.glob('test/features/privacy/*.dart'))
    paths += list(ROOT.glob('third_party/gotrue/lib/**/*.dart'))
    paths += [ROOT / p for p in [
        'pubspec.yaml', 'pubspec.lock', '.dart_tool/package_config.json',
        'assets/typefaces/Inter-Variable.ttf',
    ]]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(set(paths))}


def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


started = datetime.datetime.now(datetime.timezone.utc).isoformat()
before = inventory()
write('inputs-before.json', before)
commands = [
    [FLUTTER, '--version', '--machine'],
    [FLUTTER, 'analyze', '--no-pub', TEST],
    [FLUTTER, 'test', '--no-pub', '--timeout', '45s', '--reporter', 'json', TEST],
]
if len(sys.argv) > 2:
    commands[-1] += ['--plain-name', sys.argv[2]]
results = []
for index, command in enumerate(commands):
    log = OUT / f'command-{index}.log'
    with log.open('wb') as output:
        try:
            result = subprocess.run(command, cwd=ROOT, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=900)
            exit_code = result.returncode
        except subprocess.TimeoutExpired:
            exit_code = 'timeout'
    results.append({'argv': command, 'exit_code': exit_code,
                    'log': log.name,
                    'sha256': hashlib.sha256(log.read_bytes()).hexdigest()})
after = inventory()
write('inputs-after.json', after)
drift = {key: {'before': before.get(key), 'after': after.get(key)}
         for key in sorted(set(before) | set(after)) if before.get(key) != after.get(key)}
events = []
for line in (OUT / 'command-2.log').read_text(errors='replace').splitlines():
    try:
        event = json.loads(line)
        if isinstance(event, dict):
            events.append(event)
    except ValueError:
        pass
done = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
summary = {'started_at_utc': started,
           'completed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
           'commands': results, 'inputs': len(before), 'drift': drift,
           'visible_tests': len(done),
           'passed': sum(e.get('result') == 'success' and not e.get('skipped') for e in done),
           'failed': sum(e.get('result') in ('failure', 'error') for e in done),
           'skipped': sum(bool(e.get('skipped')) for e in done),
           'runner_done': [e for e in events if e.get('type') == 'done'],
           'scope': 'Synthetic actual-route widget fixture only; no hosted/provider/erasure or visual-fidelity claim.'}
write('result.json', summary)
print(json.dumps(summary, indent=2))
sys.exit(0 if all(r['exit_code'] == 0 for r in results) and not drift
         and done and summary['failed'] == 0 and summary['skipped'] == 0
         and len(summary['runner_done']) == 1
         and summary['runner_done'][0].get('success') is True
         else 1)
