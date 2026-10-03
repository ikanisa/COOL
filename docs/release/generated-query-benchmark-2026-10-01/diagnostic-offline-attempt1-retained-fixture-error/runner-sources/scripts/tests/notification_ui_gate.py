#!/usr/bin/env python3
"""Record actual notification recovery UI tests against immutable source copies."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
TEST = 'test/features/notification_preferences_recovery_ui_test.dart'
SCREEN = 'lib/features/settings/settings_subscreens.dart'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    files = set(ROOT.glob('lib/**/*.dart'))
    files.update(ROOT / p for p in [TEST, 'pubspec.yaml', 'pubspec.lock',
                                   'scripts/tests/notification_ui_gate.py'])
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(files)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / 'docs/release'):
        parser.error('Fresh repository release directory required')
    output.mkdir(parents=True, exist_ok=False)
    flutter = Path(args.flutter).resolve(strict=True)
    dart = flutter.parent / 'cache/dart-sdk/bin/dart'
    before = sources()
    for relative in before:
        target = output / 'sources' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / relative).read_bytes())
    commands = [
        ('toolchain', [str(flutter), '--version', '--machine']),
        ('tests', [str(flutter), 'test', '--no-pub', '--concurrency=1',
                   TEST, '--reporter', 'expanded']),
        ('analysis', [str(dart), 'analyze', SCREEN, TEST]),
    ]
    results = []
    for name, command in commands:
        result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                text=True, timeout=90)
        for stream in ['stdout', 'stderr']:
            (output / (name + '.' + stream)).write_text(getattr(result, stream))
        results.append({'name': name, 'argv': command, 'exit_code': result.returncode,
                        'stdout_sha256': digest(output / (name + '.stdout')),
                        'stderr_sha256': digest(output / (name + '.stderr'))})
    after = sources()
    counts = re.findall(r'\+(\d+): All tests passed!',
                        (output / 'tests.stdout').read_text())
    version = json.loads((output / 'toolchain.stdout').read_text())
    passed = (before == after and all(x['exit_code'] == 0 for x in results)
              and bool(counts) and version.get('frameworkVersion') == '3.44.4'
              and 'No issues found!' in (output / 'analysis.stdout').read_text())
    report = {'status': 'pass' if passed else 'fail', 'commands': results,
              'test_count': int(counts[-1]) if counts else None,
              'source_before': before, 'source_after': after,
              'source_unchanged': before == after,
              'captured_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'scope': 'Actual SDK with synthetic recording HTTP and real widget interactions; compact320x568 and2x text',
              'database_called': False, 'provider_called': False,
              'actual_browser_verified': False, 'whole_goal_complete': False}
    (output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status', 'test_count', 'source_unchanged']}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
