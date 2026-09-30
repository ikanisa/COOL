#!/usr/bin/env python3
"""Retain current health contract and widget acceptance with actual SQL provenance."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
MODULE = 'lib/admin/core/admin_operational_health.dart'
TEST = 'test/admin_operational_health_test.dart'
FIXTURE = 'test/fixtures/admin_operational_health148.json'
SQL = 'docs/release/admin-full-coverage-2026-09-30/sql-reads148-attempt3'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot():
    files = set(ROOT.glob('lib/**/*.dart'))
    for package in ['gotrue', 'file_saver']:
        files.update(ROOT.glob(f'third_party/{package}/lib/**/*.dart'))
        files.update(p for p in (ROOT / f'third_party/{package}').glob('*')
                     if p.is_file())
    files.update(ROOT / p for p in [TEST, FIXTURE, 'pubspec.yaml', 'pubspec.lock',
        '.dart_tool/package_config.json', 'scripts/tests/operational_health_ui_gate.py',
        'supabase/migrations/20260930160000_redacted_operational_health.sql'])
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
    fixture = json.loads((ROOT / FIXTURE).read_text())
    result = json.loads((ROOT / SQL / 'result.json').read_text())
    if not (result['status'] == 'pass' and result['unchanged'] and
            result['tables_before'] == result['tables_after'] == 146 and
            result['identity']['count'] == 148 and
            result['provider_calls'] is False and result['hosted_writes'] is False):
        raise RuntimeError('Exact restored actual local SQL proof required')
    provenance = fixture['provenance']
    for key, name in [('stdout_sha256', 'stdout'), ('result_sha256', 'result.json')]:
        if provenance[key] != digest(ROOT / SQL / name):
            raise RuntimeError('Actual SQL fixture provenance mismatch')
    if provenance['source_sql_sha256'] != result['reviewed_source_sha256']:
        raise RuntimeError('Fixture SQL source mismatch')
    prefix = 'ADMIN_READ_RECEIPT_JSON|'
    receipts = [json.loads(line[len(prefix):]) for line in (ROOT / SQL / 'stdout')
                .read_text().splitlines() if line.startswith(prefix)]
    actual = [r['value'] for r in receipts if r['rpc'] == 'admin_system_health']
    if len(receipts) != 15 or actual != [fixture['receipt']]:
        raise RuntimeError('Health fixture must equal actual captured SQL receipt')
    flutter = Path(args.flutter).resolve(strict=True)
    dart = flutter.parent / 'cache/dart-sdk/bin/dart'
    before = snapshot()
    for relative in before:
        dst = output / 'sources' / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes((ROOT / relative).read_bytes())
    commands = [
        ('toolchain', [str(flutter), '--version', '--machine']),
        ('tests', [str(flutter), 'test', '--no-pub', '--concurrency=1',
                   TEST, '--reporter', 'expanded']),
        ('analysis', [str(dart), 'analyze', MODULE, TEST]),
    ]
    results = []
    for name, command in commands:
        process = subprocess.run(command, cwd=ROOT, capture_output=True,
                                 text=True, timeout=90)
        for stream in ['stdout', 'stderr']:
            (output / f'{name}.{stream}').write_text(getattr(process, stream))
        results.append({'name': name, 'argv': command,
                        'exit_code': process.returncode,
                        'stdout_sha256': digest(output / f'{name}.stdout'),
                        'stderr_sha256': digest(output / f'{name}.stderr')})
    after = snapshot()
    counts = re.findall(r'\+(\d+): All tests passed!',
                        (output / 'tests.stdout').read_text())
    version = json.loads((output / 'toolchain.stdout').read_text())
    passed = (before == after and all(r['exit_code'] == 0 for r in results)
              and counts == ['39'] and version.get('frameworkVersion') == '3.44.4'
              and 'No issues found!' in (output / 'analysis.stdout').read_text())
    report = {'status': 'pass' if passed else 'fail', 'commands': results,
              'test_count': int(counts[-1]) if counts else None,
              'source_before': before, 'source_after': after,
              'source_unchanged': before == after, 'sql_provenance': provenance,
              'captured_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
              'scope': 'Actual installed148 SQL receipt plus current contract and compact320x568/2x widget mutations and interactions',
              'database_called_during_widget_tests': False, 'provider_called': False,
              'actual_browser_verified': False, 'whole_goal_complete': False}
    (output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status', 'test_count', 'source_unchanged']}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
