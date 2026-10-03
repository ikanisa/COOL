#!/usr/bin/env python3
"""Local SDK HTTP/contract/session acceptance; never selects a database target."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
TESTS = [
    'test/shared/notification_preference_runtime_test.dart',
    'test/admin_feature_flag_runtime_test.dart',
    'test/admin_action_contracts_test.dart',
    'test/admin_action_session_test.dart',
    'test/shared/repository_session_fencing_test.dart',
    'test/shared/realtime_invalidation_recovery_test.dart',
]
ANALYZE = [
    'lib/shared/repositories/runtime_control_contract.dart',
    'lib/shared/repositories/collect_repository.dart',
    'lib/shared/repositories/collect_repository_live_reader.dart',
    'lib/admin/core/admin_action_contracts.dart',
    'lib/admin/core/admin_runtime.dart',
    TESTS[0], TESTS[1], TESTS[2], TESTS[5],
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sources():
    files = set(ROOT.glob('lib/**/*.dart')) | set(ROOT.glob('test/**/*.dart'))
    files.update(ROOT / name for name in [
        'pubspec.yaml', 'pubspec.lock',
        'docs/release/runtime-controls-2026-09-30/contracts/client-contract-v2.json',
        'supabase/migrations/20260930150000_runtime_control_governance.sql',
        'scripts/tests/runtime_control_client_gate.py',
    ])
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(files)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    flutter = pathlib.Path(args.flutter).resolve(strict=True)
    dart = flutter.parent / 'cache/dart-sdk/bin/dart'
    output = pathlib.Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    commands = [
        ('toolchain', [str(flutter), '--version', '--machine'], 30),
        ('tests', [str(flutter), 'test', '--no-pub', *TESTS, '--reporter', 'expanded'], 180),
        ('analysis', [str(dart), 'analyze', *ANALYZE], 60),
    ]
    before = sources()
    (output / 'source-before.json').write_text(json.dumps(before, indent=2) + '\n')
    results = []
    for name, command, timeout in commands:
        started = time.time()
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
        log = result.stdout + result.stderr
        (output / f'{name}.log').write_text(log)
        results.append({'name': name, 'argv': command, 'exit_code': result.returncode,
                        'seconds': round(time.time() - started, 3),
                        'log_sha256': digest(output / f'{name}.log')})
    after = sources()
    (output / 'source-after.json').write_text(json.dumps(after, indent=2) + '\n')
    tests_log = (output / 'tests.log').read_text()
    counts = re.findall(r'\+(\d+): All tests passed!', tests_log)
    analysis_clean = 'No issues found!' in (output / 'analysis.log').read_text()
    passed = (before == after and all(r['exit_code'] == 0 for r in results)
              and bool(counts) and analysis_clean)
    report = {
        'passed': passed, 'scope': 'local_actual_Supabase_SDK_mock_HTTP_and_contract_regression',
        'test_count': int(counts[-1]) if counts else None,
        'analysis_clean': analysis_clean, 'source_files': len(before),
        'source_unchanged': before == after, 'commands': results,
        'source_before_sha256': digest(output / 'source-before.json'),
        'source_after_sha256': digest(output / 'source-after.json'),
        'database_called': False, 'provider_called': False, 'hosted_activation_verified': False,
        'limitation': 'HTTP payloads/Auth records are synthetic; real SQL acceptance is the independent root147 packet. Settings UI follow-up is separately verified.',
    }
    (output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
