#!/usr/bin/env python3
"""Retain actual local SDK probes and bounded acceptance, without DB targets."""
import argparse
import hashlib
import json
import pathlib
import re
import os
import signal
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROBE = 'test/admin_full_coverage_gap_test.dart'
SUPPORT_PROBE = 'test/admin_runtime_control_gap_test.dart'
TESTS = [PROBE, 'test/admin_read_contracts_test.dart',
         'test/admin_roster_gateway_expiry_test.dart',
         'test/admin_action_session_test.dart', 'test/admin_session_scope_test.dart',
         'test/admin_roster_import_test.dart', 'test/admin_roster_reload_test.dart',
         'test/admin_action_contracts_test.dart', 'test/admin_feature_flag_runtime_test.dart',
         'test/admin_support_read_contracts_test.dart', 'test/admin_declared_action_dispatch_test.dart',
         'test/admin_declared_route_states_test.dart', 'test/admin_route_access_test.dart',
         'test/admin_action_ui_session_test.dart', 'test/admin_platform_access_test.dart',
         'test/admin_reconciliation_repository_test.dart', 'test/admin_reconciliation_step_up_test.dart',
         'test/admin_reconciliation_ui_test.dart', 'test/admin_login_recovery_test.dart',
         'test/admin_logout_lifecycle_test.dart', 'test/admin_reason_dialog_focus_test.dart']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot():
    files = set(ROOT.glob('lib/**/*.dart')) | set(ROOT.glob('test/**/*.dart'))
    files.update([ROOT / 'pubspec.yaml', ROOT / 'pubspec.lock',
                  ROOT / '.dart_tool/package_config.json', pathlib.Path(__file__)])
    files.update(ROOT.glob('supabase/migrations/*.sql'))
    files.update(ROOT.glob('third_party/gotrue/**/*.dart'))
    files.update([ROOT / 'third_party/gotrue/pubspec.yaml'])
    files.update(ROOT.glob('third_party/firebase_messaging/**/*.dart'))
    if (ROOT / 'third_party/firebase_messaging/pubspec.yaml').exists():
        files.add(ROOT / 'third_party/firebase_messaging/pubspec.yaml')
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(files)}


def run_command(argv, cwd, log, timeout):
    start = time.monotonic()
    timed_out = False
    with log.open('wb') as stream:
        process = subprocess.Popen(argv, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            # Only this runner's newly created process group is targeted.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
            # The parent can exit before a child that ignores SIGTERM.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    return {'argv': argv, 'exit_code': 124 if timed_out else process.returncode,
            'timed_out': timed_out, 'process_group': process.pid,
            'seconds': round(time.monotonic() - start, 3), 'sha256': digest(log)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--phase', choices=['prior-probes', 'acceptance'], required=True)
    parser.add_argument('--support-probes', action='store_true')
    parser.add_argument('--sql-receipts')
    parser.add_argument('--sql-actor')
    parser.add_argument('--test-file', action='append')
    args = parser.parse_args()
    flutter = pathlib.Path(args.flutter).resolve(strict=True)
    output = pathlib.Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    before = snapshot()
    (output / 'source-before.json').write_text(json.dumps(before, indent=2) + '\n')
    for name in ['lib/admin/core/admin_runtime.dart', 'lib/admin/core/admin_auth_guard.dart',
                 'lib/admin/core/admin_roster_import.dart', 'lib/admin/admin_shell.dart',
                 'lib/admin/core/admin_read_contracts.dart', 'lib/admin/core/admin_detail_specs.dart',
                 'lib/admin/core/admin_reconciliation_models.dart', 'lib/admin/core/admin_action_contracts.dart',
                 *TESTS, SUPPORT_PROBE, 'test/support/admin_read_fixture.dart']:
        dst = output / 'sources' / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes((ROOT / name).read_bytes())
    tests = [SUPPORT_PROBE if args.support_probes else PROBE] if args.phase == 'prior-probes' else [*TESTS, SUPPORT_PROBE]
    if args.test_file:
        if any(name not in [*TESTS, SUPPORT_PROBE] for name in args.test_file):
            parser.error('--test-file must name a reviewed test in the declared gate')
        tests = args.test_file
    defines = []
    if bool(args.sql_receipts) != bool(args.sql_actor):
        parser.error('--sql-receipts and --sql-actor must be supplied together')
    if args.sql_receipts:
        receipt_path = pathlib.Path(args.sql_receipts).resolve(strict=True)
        defines = [f'--dart-define=ADMIN_READ_SQL_RECEIPTS={receipt_path}',
                   f'--dart-define=ADMIN_READ_SQL_ACTOR={args.sql_actor}']
    machine_log = output / 'tests.machine.jsonl'
    commands = [('toolchain', [str(flutter), '--version', '--machine'], 30),
                ('tests', [str(flutter), 'test', '--no-pub', *defines, *tests,
                           '--reporter', 'expanded', f'--file-reporter=json:{machine_log}'], 180)]
    if args.phase == 'acceptance':
        dart = flutter.parent / 'cache/dart-sdk/bin/dart'
        commands.append(('analysis', [str(dart), 'analyze',
            'lib/admin/core/admin_runtime.dart', 'lib/admin/core/admin_read_contracts.dart',
            'lib/admin/admin_shell.dart', 'lib/admin/core/admin_detail_specs.dart',
            'lib/admin/core/admin_action_contracts.dart',
            'lib/admin/core/admin_reconciliation_models.dart',
            'lib/admin/core/admin_roster_import.dart', 'lib/admin/core/admin_auth_guard.dart',
            'test/support/admin_read_fixture.dart', *tests], 90))
    results = []
    for name, argv, timeout in commands:
        log = output / f'{name}.log'
        result = run_command(argv, ROOT, log, timeout)
        results.append({'name': name, **result})
    after = snapshot()
    (output / 'source-after.json').write_text(json.dumps(after, indent=2) + '\n')
    text = (output / 'tests.log').read_text()
    counts = re.findall(r'\+(\d+)(?:\s+~\d+)?: All tests passed!', text)
    skips = re.findall(r'\+\d+\s+~(\d+): All tests passed!', text)
    analysis_clean = args.phase != 'acceptance' or 'No issues found!' in (output / 'analysis.log').read_text()
    report = {'phase': args.phase, 'source_unchanged': before == after,
              'source_count': len(before), 'commands': results,
              'test_files': tests,
              'source_drift': [key for key in sorted(set(before) | set(after)) if before.get(key) != after.get(key)],
              'test_count': int(counts[-1]) if counts else None,
              'skipped_test_count': int(skips[-1]) if skips else 0,
              'analysis_clean': analysis_clean,
              'test_gate_passed': bool(counts) and analysis_clean and all(r['exit_code'] == 0 for r in results),
              'database_called': False, 'provider_called': False,
              'scope': 'actual locally installed Supabase SDK; synthetic MockClient HTTP and Auth records',
              'actual_sql_receipt_sha256': digest(receipt_path) if args.sql_receipts else None,
              'machine_test_log_sha256': digest(machine_log) if machine_log.exists() else None,
              'source_before_sha256': digest(output / 'source-before.json'),
              'source_after_sha256': digest(output / 'source-after.json')}
    (output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if before == after and report['test_gate_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
