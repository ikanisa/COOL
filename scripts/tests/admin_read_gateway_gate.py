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
         'test/admin_declared_read_dispatch_test.dart',
         'test/admin_declared_route_states_test.dart', 'test/admin_route_access_test.dart',
         'test/admin_action_ui_session_test.dart', 'test/admin_platform_access_test.dart',
         'test/admin_reconciliation_repository_test.dart', 'test/admin_reconciliation_step_up_test.dart',
         'test/admin_reconciliation_ui_test.dart', 'test/admin_login_recovery_test.dart',
         'test/admin_logout_lifecycle_test.dart', 'test/admin_reason_dialog_focus_test.dart']
TESTS += ['test/admin_data_sync_test.dart', 'test/admin_realtime_stability_test.dart',
          'test/admin_list_paging_test.dart', 'test/admin_repository_paging_test.dart',
          'test/admin_list_models_test.dart', 'test/admin_error_redaction_test.dart',
          'test/admin_sms_queue_repository_test.dart', 'test/admin_automations_test.dart',
          'test/admin_queue_navigation_test.dart', 'test/admin_overview_totals_test.dart']
TESTS += ['test/admin_sensitive_permission_test.dart']
TESTS += ['test/admin_custom_action_ui_test.dart']
TESTS += ['test/admin_value_integrity_test.dart']
TESTS += ['test/admin_value_screen_integrity_test.dart']
TESTS += ['test/admin_operational_health_test.dart']
TESTS += ['test/admin_permission_refresh_test.dart', 'test/admin_bounded_loading_test.dart',
          'test/admin_header_accessibility_test.dart', 'test/admin_page_reflow_test.dart',
          'test/admin_filter_bar_responsive_test.dart',
          'test/admin_shadow_runs_repository_test.dart', 'test/admin_shadow_runs_test.dart']
TESTS += ['test/admin_roster_fresh_auth_test.dart',
          'test/admin_roster_transport_test.dart',
          'test/admin_roster_authority_scope_test.dart',
          'test/admin_roster_dialog_test.dart', 'test/admin_roster_file_parser_test.dart',
          'test/admin_roster_xlsx_preflight_test.dart',
          'test/admin_roster_fresh_auth_sql_receipts_test.dart',
          'test/admin_entrypoint_rebuild_test.dart',
          'test/admin_hybrid_member_directory_test.dart',
          'test/admin_operations_readability_test.dart',
          'test/admin_transaction_lifecycle_test.dart',
          'test/admin_reason_dialog_bounds_test.dart']
TESTS += ['test/admin_realtime_sdk_provider_test.dart']
TESTS += ['test/admin_roster_declared_read_dispatch_test.dart']
TESTS += ['test/admin_receipt_overview_test.dart']
TESTS += ['test/admin_utc_observation_timestamp_test.dart']
TESTS += ['test/admin_investigation_test.dart']
TESTS += ['test/admin_investigation_view_test.dart', 'test/admin_roster_calendar_test.dart']
TESTS += ['test/admin_email_login_test.dart', 'test/admin_email_transport_session_test.dart']
TESTS += ['test/admin_operator_approval_sdk_matrix_test.dart']
TESTS += ['test/admin_operator_approval_test.dart']
TESTS += ['test/admin_roster_upload_admission_test.dart']
TESTS += ['test/admin_email_submit_paint_test.dart']
TESTS += ['test/admin_gateway_contracts_test.dart', 'test/admin_gateway_models_test.dart',
          'test/admin_gateway_repository_test.dart', 'test/admin_gateway_page_test.dart',
          'test/admin_gateway_sdk_state_matrix_test.dart']
TESTS += ['test/admin_gateway_observed_test.dart']
TESTS += ['test/admin_gateway_action_ui_sdk_test.dart']
TESTS += ['test/admin_private_provider_authority_test.dart']
TESTS += ['test/admin_exception_sdk_provider_state_test.dart']
TESTS += ['test/admin_exception_models_test.dart',
          'test/admin_exception_repository_test.dart',
          'test/admin_exception_page_test.dart']
TESTS += ['test/admin_gateway_checkpoint_test.dart']
TESTS += ['test/admin_pwa_test.dart']
TESTS += ['test/admin_entity_audit_models_test.dart',
          'test/admin_entity_audit_repository_test.dart',
          'test/admin_entity_audit_authority_test.dart',
          'test/admin_entity_audit_page_test.dart']
TESTS += ['test/admin_receipt_cancel_models_test.dart',
          'test/admin_receipt_cancel_repository_test.dart',
          'test/admin_receipt_cancel_card_test.dart']
TESTS += ['test/admin_receipt_cancel_sdk_authority_test.dart']
TESTS += ['test/shared/notification_preference_runtime_test.dart',
          'test/features/notification_preferences_recovery_ui_test.dart']
TESTS += ['test/admin_operating_policy_models_test.dart',
          'test/admin_operating_policy_runtime_test.dart']
# Enabled nested Automations/Exceptions consumers. Declarations select tests;
# only retained named executions establish their bounded acceptance.
TESTS += ['test/admin_entity_audit_links_test.dart',
          'test/admin_exception_workflow_test.dart',
          'test/admin_exception_workflow_sdk_test.dart',
          'test/admin_receipt_content_v2_test.dart',
          'test/admin_receipt_deferral_test.dart',
          'test/admin_receipt_worker_health_test.dart',
          'test/admin_receipt_operations_models_test.dart',
          'test/admin_receipt_operations_sdk_test.dart',
          'test/admin_receipt_operations_runtime_test.dart',
          'test/admin_receipt_operations_card_test.dart',
          'test/admin_receipt_operations_checkpoint_test.dart']
TESTS += ['test/admin_receipt_principal_models_test.dart',
          'test/admin_receipt_principal_recovery_test.dart',
          'test/admin_receipt_principal_integration_test.dart']
BROWSER_CHECKPOINT_CASES = {
    'test/admin_receipt_cancel_checkpoint_browser_test.dart':
        'actual same-tab storage persists exact original intent across adapter recreation and isolates owners',
    'test/admin_exception_checkpoint_browser_test.dart':
        'real browser sessionStorage retains only owner-bound same-tab reviewed references across adapter recreation',
    'test/admin_gateway_checkpoint_browser_test.dart':
        'real same-tab browser adapter retains reviewed fingerprints after recreation and isolates owners',
    'test/admin_roster_bookmark_browser_test.dart':
        'actual browser sessionStorage retains only bounded schema references across adapter recreation',
    'test/admin_receipt_operations_checkpoint_browser_test.dart':
        'actual browser localStorage adapter retains original across instances and isolates owners',
}

# This enabled principal browser cohort contains ten cases, unlike the five
# one-case checkpoint cohorts. Require every named execution explicitly.
BROWSER_PRINCIPAL_CASES = {
    'test/admin_receipt_principal_browser_test.dart': (
        'real store reload uses original lookup only and retains resolved bytes',
        'actual lock serializes exact-UUID concurrent publication and prevents overwrite',
        'actual lock refuses distinct pending revoke UUIDs for one target',
        'urgent different-target revoke can publish alongside original activation',
        'authority-lost queued publication acquires no permission to write',
        'five-second aborted lock acquisition never publishes after eventual release',
        'controller timeout closes queued publication before lock becomes available',
        'changed-original actual browser bytes fail closed on reload',
        'changed-marker actual browser bytes fail closed on reload',
        'orphan-marker actual browser bytes fail closed on reload',
    ),
}
BROWSER_TEST_FILES = (*BROWSER_CHECKPOINT_CASES, *BROWSER_PRINCIPAL_CASES)
BROWSER_REQUIRED_CASE_NAMES = (*BROWSER_CHECKPOINT_CASES.values(),
    *(name for names in BROWSER_PRINCIPAL_CASES.values() for name in names))



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
    termination_errors = []
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
            except OSError as error:
                termination_errors.append({'signal': 'SIGTERM', 'errno': error.errno})
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except OSError as error:
                    termination_errors.append({'signal': 'SIGKILL', 'errno': error.errno})
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    termination_errors.append({'signal': 'wait', 'error': 'parent_still_running'})
            # The parent can exit before a child that ignores SIGTERM.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except OSError as error:
                if error.errno != 3:  # A missing group is expected after exit.
                    termination_errors.append({'signal': 'SIGKILL', 'errno': error.errno})
    return {'argv': argv, 'exit_code': 124 if timed_out else process.returncode,
            'timed_out': timed_out, 'process_group': process.pid,
            'termination_errors': termination_errors,
            'parent_exit_confirmed': process.poll() is not None,
            'seconds': round(time.monotonic() - start, 3), 'sha256': digest(log)}


def machine_summary(path):
    started, finished, hidden = {}, {}, set()
    done = None
    errors = []
    if path.exists():
        for number, line in enumerate(path.read_text().splitlines(), 1):
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                errors.append(f'invalid_event_line_{number}')
                continue
            kind = event.get('type')
            if kind == 'testStart':
                test = event['test']
                started[test['id']] = {'name': test['name'], 'source': test.get('root_url') or test.get('url')}
            elif kind == 'testDone':
                identity = event['testID']
                if identity in finished:
                    errors.append(f'duplicate_test_completion_{identity}')
                finished[identity] = event
                if event.get('hidden'):
                    hidden.add(identity)
            elif kind == 'done':
                done = event.get('success')
    actual = {key: value for key, value in finished.items() if key not in hidden}
    return {'runner_completed_successfully': done is True,
            'passed': sum(v.get('result') == 'success' and not v.get('skipped') for v in actual.values()),
            'failed': sum(v.get('result') == 'failure' for v in actual.values()),
            'errors': sum(v.get('result') == 'error' for v in actual.values()),
            'skipped': sum(bool(v.get('skipped')) for v in actual.values()),
            'unfinished': [started[key] for key in sorted(set(started) - set(finished))],
            'failures': [started.get(key, {'name': str(key)}) for key, value in actual.items()
                         if value.get('result') in ('error', 'failure')],
            'event_errors': errors}


def named_case_passed(path, expected):
    starts, results = {}, {}
    for line in path.read_text().splitlines():
        event = json.loads(line)
        if event.get('type') == 'testStart':
            starts[event['test']['id']] = event['test']['name']
        elif event.get('type') == 'testDone' and not event.get('hidden'):
            results[event['testID']] = event
    matches = [results[key] for key, name in starts.items()
               if name == expected and key in results]
    return (len(matches) == 1 and matches[0].get('result') == 'success'
            and not matches[0].get('skipped'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--phase', choices=['prior-probes', 'acceptance'], required=True)
    parser.add_argument('--support-probes', action='store_true')
    parser.add_argument('--sql-receipts')
    parser.add_argument('--sql-actor')
    parser.add_argument('--roster-sql-receipts')
    parser.add_argument('--capture-operations', action='store_true')
    parser.add_argument('--browser-checkpoint', action='store_true')
    parser.add_argument('--test-file', action='append')
    parser.add_argument('--test-name')
    parser.add_argument('--test-timeout', type=int, default=180)
    parser.add_argument('--test-concurrency', type=int, default=2)
    args = parser.parse_args()
    if not 1 <= args.test_timeout <= 1800:
        parser.error('--test-timeout must be within 1..1800 seconds')
    if not 1 <= args.test_concurrency <= 8:
        parser.error('--test-concurrency must be within 1..8')
    flutter = pathlib.Path(args.flutter).resolve(strict=True)
    output = pathlib.Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    before = snapshot()
    (output / 'source-before.json').write_text(json.dumps(before, indent=2) + '\n')
    for name in ['lib/admin/core/admin_runtime.dart', 'lib/admin/core/admin_auth_guard.dart',
                 'lib/admin/core/admin_receipt_repository.dart', 'lib/admin/core/admin_exception_repository.dart',
                 'lib/admin/core/admin_roster_gateway.dart', 'lib/admin/core/admin_roster_upload.dart',
                 'lib/admin/admin_shell_navigation.dart',
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
    if args.roster_sql_receipts:
        roster_receipt_path = pathlib.Path(args.roster_sql_receipts).resolve(strict=True)
        defines.append(f'--dart-define=ROSTER_FRESH_SQL_RECEIPTS={roster_receipt_path}')
    if args.capture_operations:
        defines.append('--dart-define=COLLECT_CAPTURE_OPERATIONS=true')
    machine_log = output / 'tests.machine.jsonl'
    commands = [('toolchain', [str(flutter), '--version', '--machine'], 30),
                ('tests', [str(flutter), 'test', '--no-pub', *defines, *tests,
                           *(['--plain-name', args.test_name] if args.test_name else []),
                           f'--concurrency={args.test_concurrency}', '--reporter', 'expanded', f'--file-reporter=json:{machine_log}'], args.test_timeout)]
    browser_machine_log = output / 'browser-checkpoint.machine.jsonl'
    if args.browser_checkpoint:
        commands.append(('browser-checkpoint', [str(flutter), 'test', '--no-pub',
            '--platform=chrome', *BROWSER_TEST_FILES,
            '--reporter=expanded', f'--file-reporter=json:{browser_machine_log}'], args.test_timeout))
    if args.phase == 'acceptance':
        dart = flutter.parent / 'cache/dart-sdk/bin/dart'
        commands.append(('analysis', [str(dart), 'analyze',
            'lib/admin/core/admin_runtime.dart', 'lib/admin/core/admin_read_contracts.dart',
            'lib/admin/admin_shell.dart', 'lib/admin/core/admin_detail_specs.dart',
            'lib/admin/core/admin_action_contracts.dart',
            'lib/admin/core/admin_reconciliation_models.dart',
            'lib/admin/core/admin_roster_import.dart', 'lib/admin/core/admin_auth_guard.dart',
            'test/support/admin_read_fixture.dart', *tests], 300))
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
    machine = machine_summary(machine_log)
    machine_passed = (machine['runner_completed_successfully'] and machine['passed'] > 0
                      and not any(machine[key] for key in ['failed', 'errors', 'unfinished', 'event_errors'])
                      and bool(counts) and machine['passed'] == int(counts[-1]))
    browser_machine = machine_summary(browser_machine_log) if args.browser_checkpoint else None
    browser_passed = (browser_machine['runner_completed_successfully']
        and browser_machine['passed'] == len(BROWSER_REQUIRED_CASE_NAMES)
        and not any(browser_machine[key] for key in ['failed', 'errors', 'unfinished', 'event_errors'])
        and all(named_case_passed(browser_machine_log, title)
                for title in BROWSER_REQUIRED_CASE_NAMES)
        ) if args.browser_checkpoint else None
    roster_receipt_required = bool(args.roster_sql_receipts) and 'test/admin_roster_fresh_auth_sql_receipts_test.dart' in tests
    roster_receipt_passed = (named_case_passed(machine_log,
        'actual149 fresh recovery receipts agree with every client decoder')
        if roster_receipt_required else None)
    report = {'phase': args.phase, 'source_unchanged': before == after,
              'source_count': len(before), 'commands': results,
              'test_files': tests,
              'source_drift': [key for key in sorted(set(before) | set(after)) if before.get(key) != after.get(key)],
              'test_count': int(counts[-1]) if counts else None,
              'skipped_test_count': int(skips[-1]) if skips else 0,
              'analysis_clean': analysis_clean,
              'machine_summary': machine,
              'test_gate_passed': machine_passed and analysis_clean and all(r['exit_code'] == 0 for r in results)
                  and (not roster_receipt_required or roster_receipt_passed)
                  and (not args.browser_checkpoint or browser_passed),
              'browser_checkpoint_passed': browser_passed,
              'required_browser_checkpoint_cases': BROWSER_CHECKPOINT_CASES if args.browser_checkpoint else {},
              'required_browser_principal_cases': BROWSER_PRINCIPAL_CASES if args.browser_checkpoint else {},
              'browser_checkpoint_machine_summary': browser_machine,
              'browser_checkpoint_machine_sha256': digest(browser_machine_log) if args.browser_checkpoint else None,
              'actual_roster_sql149_decoder_required': roster_receipt_required,
              'actual_roster_sql149_decoder_passed': roster_receipt_passed,
              'database_called': False, 'provider_called': False,
              'synthetic_visual_capture_requested': args.capture_operations,
              'scope': 'actual locked Supabase SDK with synthetic MockClient and localhost HTTP/WebSocket transport; synthetic Auth records; actual locked PlatformFile interface with instrumented bounded streams',
              'actual_sql_receipt_sha256': digest(receipt_path) if args.sql_receipts else None,
              'actual_roster_sql149_receipt_sha256': digest(roster_receipt_path) if args.roster_sql_receipts else None,
              'machine_test_log_sha256': digest(machine_log) if machine_log.exists() else None,
              'source_before_sha256': digest(output / 'source-before.json'),
              'source_after_sha256': digest(output / 'source-after.json')}
    (output / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if before == after and report['test_gate_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
