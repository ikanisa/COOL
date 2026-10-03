#!/usr/bin/env python3
"""Immutable actual member WebSocket/session/cache acceptance; local only."""
import argparse
import json
from pathlib import Path
import sys

from data_correctness_gate import copy_export
from roster_fresh_auth_gate import ROOT, command, hashes, machine_summary, sha

TESTS = ['test/shared/member_realtime_sdk_session_test.dart',
         'test/shared/realtime_invalidation_recovery_test.dart']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--flutter', required=True, type=Path)
    args = parser.parse_args()
    packet = args.output.resolve()
    if not packet.is_relative_to(ROOT / 'docs/release'):
        parser.error('Fresh repository release packet required')
    packet.mkdir(parents=True, exist_ok=False)
    result = {'status': 'fail', 'whole_system_acceptance': False,
              'sql_executed': False, 'hosted_called': False, 'provider_called': False,
              'declared_tests': TESTS, 'commands': []}
    try:
        export, files, before, dependencies, sdk_files = copy_export(packet)
        script = Path(__file__).resolve()
        target = export / script.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(script.read_bytes())
        before[str(script.relative_to(ROOT))] = sha(script)
        files.append(script)
        flutter = args.flutter.resolve(strict=True)
        dart = flutter.parent / 'cache/dart-sdk/bin/dart'
        sdk_files += [flutter, dart, flutter.parent / 'cache/flutter_tools.snapshot',
                      flutter.parent / 'cache/artifacts/engine/darwin-x64/flutter_tester']
        for directory in ['dart-sdk/lib', 'dart-sdk/bin']:
            sdk_files.extend(p for p in (flutter.parent / 'cache' / directory).rglob('*') if p.is_file())
        sdk_files.extend(p for p in (flutter.parent.parent / 'packages/flutter_tools/lib').rglob('*') if p.is_file())
        sdk = {str(p): sha(p) for p in set(sdk_files) if p.is_file()}
        copied = hashes([p for p in export.rglob('*') if p.is_file()], export)
        inputs = {'source': before, 'export': copied, 'dependencies': dependencies,
                  'sdk': sdk, 'declared_tests': TESTS}
        (packet / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
        for name, argv, timeout in [
            ('tests', [str(flutter), 'test', '--no-pub', '--concurrency=1', '--reporter=expanded',
                       f'--file-reporter=json:{packet / "tests.machine.jsonl"}', *TESTS], 300),
            ('analysis', [str(dart), 'analyze', '--fatal-infos', 'lib/shared/repositories/collect_repository.dart',
                          'lib/core/supabase/realtime_invalidation.dart', *TESTS], 300),
        ]:
            result['commands'].append(command(name, argv, export, packet, timeout=timeout))
        result['machine'] = machine_summary(packet / 'tests.machine.jsonl')
        result['export_unchanged'] = copied == hashes([export / p for p in copied], export)
        result['sdk_unchanged'] = all(Path(p).is_file() and sha(Path(p)) == h for p, h in sdk.items())
        result['live_source_drift'] = sorted(p for p, h in before.items()
            if not (ROOT / p).is_file() or sha(ROOT / p) != h)
        result['inputs_sha256'] = sha(packet / 'inputs.json')
        summary = result['machine']
        passed = (all(c['exit_code'] == 0 for c in result['commands'])
                  and summary['runner_completed_successfully'] and summary['passed'] > 0
                  and not any(summary[k] for k in ['failed', 'errors', 'skipped'])
                  and result['export_unchanged'] and result['sdk_unchanged'])
        result['status'] = 'pass' if passed else 'fail'
        result['current_source_acceptance'] = bool(passed and not result['live_source_drift'])
    except Exception as error:
        result['error'] = type(error).__name__ + ': ' + str(error)
    (packet / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result.get(k) for k in ['status', 'error', 'live_source_drift', 'current_source_acceptance']}, indent=2))
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
