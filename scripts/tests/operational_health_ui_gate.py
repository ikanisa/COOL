#!/usr/bin/env python3
"""Verify health guidance from an immutable export and actual installed150 SQL.

The existing Admin exporter supplies the same owned-package isolation as the
route matrix. Live checkout drift is recorded separately from tested bytes.
"""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
MODULE = 'lib/admin/core/admin_operational_health.dart'
TEST = 'test/admin_operational_health_test.dart'
FIXTURE = 'test/fixtures/admin_operational_health150.json'
EXPORTER = 'scripts/tests/admin_matrix_acceptance.py'
RUNNER = 'scripts/tests/admin_read_gateway_gate.py'
SELF = 'scripts/tests/operational_health_ui_gate.py'
SQL_SOURCE = 'scripts/tests/operational_health_receipt_uat.sql'
MIGRATIONS = [
    'supabase/migrations/20260930160000_redacted_operational_health.sql',
    'supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql',
    'supabase/migrations/20260930180000_operational_health_authority.sql',
]
RESPONSES = [
    'receipt_parse_backlog', 'receipt_parse_age', 'receipt_parse_failure',
    'receipt_parser_lease_expired', 'payment_unmatched', 'payment_review_age',
    'reconciliation_exception', 'push_queue_age', 'push_expired_lease',
    'push_missing_lease', 'push_attempt_failure', 'receipt_telemetry_stale',
    'push_scheduler_stale',
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n')


def inventory(exporter, base):
    values = exporter.inventory(base)
    for name in [SELF, SQL_SOURCE, RUNNER, EXPORTER, *MIGRATIONS]:
        values[name] = digest(base / name)
    return values


def actual_sql_provenance():
    fixture = json.loads((ROOT / FIXTURE).read_text())
    provenance = fixture['provenance']
    packet = (ROOT / provenance['packet']).resolve(strict=True)
    if not packet.is_relative_to(ROOT / 'docs/release'):
        raise ValueError('Actual local release packet required')
    result = json.loads((packet / 'result.json').read_text())
    if not (result['status'] == 'pass' and result['unchanged']
            and result['tables_before'] == result['tables_after'] == 149
            and result['identity']['count'] == 150
            and result['identity']['latest'] == '20260930180000'
            and result['sql_role'] == 'postgres' and result['sql_return_code'] == 0
            and result['provider_calls'] is False and result['hosted_writes'] is False):
        raise ValueError('Exact restored actual ordinary-owner150 SQL proof required')
    for key, name in [('stdout_sha256', 'stdout'), ('stderr_sha256', 'stderr'),
                      ('result_sha256', 'result.json')]:
        if provenance[key] != digest(packet / name):
            raise ValueError('Actual receipt provenance bytes changed')
    if (provenance['source_sql_sha256'] != result['reviewed_source_sha256']
            or provenance['source_sql_sha256'] != digest(ROOT / SQL_SOURCE)):
        raise ValueError('Actual reviewed SQL source mismatch')
    prefix = 'HEALTH_RECEIPT_JSON|'
    receipts = [json.loads(line.split(prefix, 1)[1])
                for line in (packet / 'stderr').read_text().splitlines()
                if prefix in line]
    if receipts != [fixture['receipt']]:
        raise ValueError('Fixture must equal the single real API receipt')
    return provenance, packet


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True, type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / 'docs/release'):
        parser.error('Fresh repository release directory required')
    output.mkdir(parents=True, exist_ok=False)
    provenance, sql_packet = actual_sql_provenance()
    exporter = load_module('health_exporter', ROOT / EXPORTER)
    before = inventory(exporter, ROOT)
    deps_before = exporter.transport_dependencies()
    write_json(output / 'original-before.json', before)
    write_json(output / 'transport-dependencies-before.json', deps_before)
    export = output / 'source-export'
    export.mkdir()
    for name in before:
        target = export / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, target)
    after_copy = inventory(exporter, ROOT)
    copied = inventory(exporter, export)
    if not before == after_copy == copied:
        write_json(output / 'validation.json', {
            'status': 'fail', 'phase': 'copy', 'source_before': before,
            'source_after_copy': after_copy, 'copied_source': copied})
        return 1
    write_json(output / 'package-binding-adaptation.json', exporter.bind_packages(export))
    exported_before = inventory(exporter, export)
    write_json(output / 'export-before.json', exported_before)
    retained = output / 'actual-sql'
    retained.mkdir()
    for name in ['result.json', 'stdout', 'stderr', 'before.json', 'after.json', 'reviewed-source.sql']:
        shutil.copyfile(sql_packet / name, retained / name)
        if digest(retained / name) != digest(sql_packet / name):
            raise ValueError('SQL evidence changed while copied')
    runner = load_module('health_runner', export / RUNNER)
    flutter = args.flutter.resolve(strict=True)
    dart = flutter.parent / 'cache/dart-sdk/bin/dart'
    machine = output / 'tests.machine.jsonl'
    commands = [
        ('toolchain', [str(flutter), '--version', '--machine'], 30),
        ('tests', [str(flutter), 'test', '--no-pub', '--concurrency=1', TEST,
                   '--reporter', 'expanded', '--file-reporter=json:' + str(machine)], 180),
        ('format', [str(dart), 'format', '--output=none', '--set-exit-if-changed', MODULE, TEST], 30),
        ('analysis', [str(dart), 'analyze', MODULE, TEST], 90),
    ]
    results = []
    for name, argv, timeout in commands:
        results.append({'name': name, **runner.run_command(argv, export, output / (name + '.log'), timeout)})
    summary = runner.machine_summary(machine)
    events = [json.loads(line) for line in machine.read_text().splitlines()] if machine.exists() else []
    starts = {event['test']['id']: event['test']['name'] for event in events if event.get('type') == 'testStart'}
    successful_names = [starts.get(event['testID']) for event in events
                        if event.get('type') == 'testDone' and event.get('result') == 'success'
                        and not event.get('skipped') and not event.get('hidden')]
    missing_responses = [code for code in RESPONSES
                         if successful_names.count(code + ' response is read-only, reachable at2x and expires') != 1]
    event_errors = [event for event in events if event.get('type') == 'error']
    original_after = inventory(exporter, ROOT)
    exported_after = inventory(exporter, export)
    deps_after = exporter.transport_dependencies()
    write_json(output / 'original-after.json', original_after)
    write_json(output / 'export-after.json', exported_after)
    write_json(output / 'transport-dependencies-after.json', deps_after)
    version = json.loads((output / 'toolchain.log').read_text())
    passed = (summary['runner_completed_successfully'] and summary['passed'] == 55
              and not any(summary[k] for k in ['failed', 'errors', 'skipped', 'unfinished', 'event_errors'])
              and not missing_responses and not event_errors
              and all(r['exit_code'] == 0 and r['parent_exit_confirmed'] for r in results)
              and version.get('frameworkVersion') == '3.44.4'
              and 'No issues found!' in (output / 'analysis.log').read_text()
              and exported_before == exported_after and deps_before == deps_after)
    report = {
        'status': 'pass' if passed else 'fail', 'commands': results,
        'machine_summary': summary, 'missing_response_cases': missing_responses,
        'event_errors': event_errors, 'test_count': summary['passed'],
        'response_cases': len(RESPONSES) - len(missing_responses),
        'copied_source_exact_and_stable': True,
        'export_source_unchanged': exported_before == exported_after,
        'live_source_unchanged': before == original_after,
        'live_source_drift': [k for k in sorted(set(before) | set(original_after)) if before.get(k) != original_after.get(k)],
        'transport_dependencies_unchanged': deps_before == deps_after,
        'export_before_sha256': digest(output / 'export-before.json'),
        'export_after_sha256': digest(output / 'export-after.json'),
        'sql_provenance': provenance, 'machine_log_sha256': digest(machine) if machine.exists() else None,
        'captured_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
        'scope': 'Actual installed150 SQL receipt; immutable current contract and all13 read-only response guidance/compact320x568/2x expiry interactions',
        'database_called_during_widget_tests': False, 'provider_called': False,
        'actual_browser_verified': False, 'operator_actions_rehearsed': False,
        'whole_goal_complete': False,
    }
    write_json(output / 'validation.json', report)
    print(json.dumps({k: report[k] for k in ['status', 'test_count', 'response_cases', 'export_source_unchanged', 'live_source_unchanged']}))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
