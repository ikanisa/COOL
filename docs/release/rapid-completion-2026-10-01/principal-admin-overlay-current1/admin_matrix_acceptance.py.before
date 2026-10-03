#!/usr/bin/env python3
"""Run Admin acceptance against a hash-verified immutable source export.

Only the exported project's generated cache/build directories are used. Shared
checkout drift is reported separately from the precisely tested export.
"""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
from urllib.parse import unquote, urlparse

ROOT = pathlib.Path(__file__).resolve().parents[2]
TREES = ('lib', 'test', 'integration_test', 'assets', 'third_party')
CONFIG = ('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.metadata',
          '.fvmrc', '.dvmrc', '.dart_tool/package_config.json',
          '.dart_tool/package_graph.json', '.dart_tool/version', '.flutter-plugins-dependencies',
          'scripts/tests/admin_read_gateway_gate.py',
          'contracts/collect-shadow-supervisor-v1.fixture.json',
          'contracts/collect-shadow-supervisor-v1.observed.fixture.json',
          'contracts/collect-admin-gateway-v1.fixture.json',
          'contracts/collect-admin-gateway-owner-request-v1.fixture.json',
          'docs/release/collect-codex-goal-2026-09-30/gateway-admin/backend-uat/result.json',
          *[f'docs/release/collect-codex-goal-2026-09-30/gateway-admin/backend-uat/observed-{name}.json'
            for name in ['empty', 'pending', 'active', 'revoked-callbacks', 'owner-request']],
          'docs/release/collect-codex-goal-2026-09-30/gateway-admin/backend-uat/captured-source/20261001000200_admin_gateway_reads.sql',
          'docs/release/collect-codex-goal-2026-09-30/gateway-admin/backend-uat/captured-source/collect-admin-gateway-v1.schema.json',
          'docs/release/collect-codex-goal-2026-09-30/exception-reads-v2/backend-uat/result.json',
          *[f'docs/release/collect-codex-goal-2026-09-30/exception-reads-v2/backend-uat/observed-{name}.json'
            for name in ['empty', 'populated', 'filtered', 'cleared', 'recorded-lookup',
                         'unknown-lookup', 'progress-lookup', 'action-receipt']],
          *[f'docs/release/collect-codex-goal-2026-09-30/exception-reads-v2/backend-uat/executed-migrations/{name}'
            for name in ['20260930213000_operator_email_auth.sql',
                         '20260930220527_operator_email_cutover_guard.sql',
                         '20260930230100_receipt_backlog_events.sql',
                         '20260930230200_admin_receipt_overview.sql',
                         '20260930230300_admin_transaction_lifecycle.sql',
                         '20260930211605_android_gateway_identity.sql',
                         '20261001000100_operational_exception_inbox.sql',
                         '20261001000300_admin_exception_reads.sql', 'schema.json']],
          'docs/release/collect-codex-goal-2026-09-30/investigation-backend/result.json',
          *[f'docs/release/collect-codex-goal-2026-09-30/investigation-backend/observed-{name}.json'
            for name in ['posted-transaction', 'posted-receipt', 'reversed-transaction', 'bounded-history', 'empty']],
          *[f'docs/release/collect-codex-goal-2026-09-30/investigation-backend/captured-source/{name}'
            for name in ['20260930213000_operator_email_auth.sql',
                         '20260930230100_receipt_backlog_events.sql',
                         '20260930230300_admin_transaction_lifecycle.sql',
                         '20260930230400_admin_investigation.sql']],
          'scripts/tests/admin_matrix_acceptance.py')
# Current Admin PWA source-contract checks read these exact local files. Copy
# source text only: none of these scripts or SQL definitions execute here.
CONFIG += ('scripts/admin_pwa_authenticated_render_smoke.sh',
           'scripts/admin_pwa_browser_qa.mjs',
           'scripts/admin_pwa_release_build.sh',
           'scripts/admin_pwa_runtime_smoke.mjs',
           'scripts/templates/admin_pwa_service_worker.js',
           'supabase/config.toml', 'supabase/seed.sql',
           'supabase/functions/_shared/openai_roster.ts',
           'supabase/functions/prepare-roster-import/handler.ts',
           'web/flutter_bootstrap.js',
           *[f'supabase/migrations/{name}' for name in
             ['20260612103000_disable_browser_admin_bootstrap.sql',
              '20260901183000_admin_operations_tables.sql',
              '20260901193000_admin_group_lifecycle.sql',
              '20260901194500_admin_users_and_members.sql',
              '20260901210000_admin_single_access_role.sql',
              '20260903085000_hybrid_roster_import_control_plane.sql',
              '20260903091500_hybrid_member_directory_views.sql']])


# These are archived synthetic DTO inputs for strict receipt-cancellation
# decoder/widget tests. They are never executed and imply no current SQL status.
CONFIG += ('docs/release/collect-codex-goal-2026-09-30/safe-receipt-actions/backend-uat/result.json',
           *[f'docs/release/collect-codex-goal-2026-09-30/safe-receipt-actions/backend-uat/observed-{name}.json'
             for name in ['linked-rwanda-inspection', 'revision-exhausted-inspection',
                          'unavailable-inspection', 'prior-attempt-inspection',
                          'unclassified-inspection', 'cancelled-inspection',
                          'preexisting-eligible-inspection', 'recorded-lookup',
                          'in-progress-lookup', 'reauthenticated-original-lookup',
                          'not-recorded-lookup', 'cancelled-action']],
           *[f'docs/release/collect-codex-goal-2026-09-30/safe-receipt-actions/backend-uat/executed-migrations/{name}'
             for name in ['20260930213000_operator_email_auth.sql',
                          '20260930220527_operator_email_cutover_guard.sql',
                          '20260930211605_android_gateway_identity.sql',
                          '20260930230100_receipt_backlog_events.sql',
                          '20260930230200_admin_receipt_overview.sql',
                          '20260930230300_admin_transaction_lifecycle.sql',
                          '20261001000100_operational_exception_inbox.sql',
                          '20261001000300_admin_exception_reads.sql',
                          '20261001000519_safe_unstarted_receipt_cancel.sql',
                          'collect-safe-receipt-action-v1.schema.json']])

# Exact dated JSON inputs read by the enabled workflow/receipt cohorts. These
# are decoder fixtures, never execution or current server-installation proof.
CURRENT_ADMIN_DECODER_INPUTS = (
    'contracts/collect-receipt-content-v2/observed-investigation-v2.json',
    *[f'docs/release/collect-codex-goal-2026-09-30/exception-lifecycle-20261001/attempt6/observed-{name}.json'
      for name in ['workflow', 'inbox', 'unassigned', 'unassigned-resolved']],
    *[f'docs/release/collect-codex-goal-2026-09-30/receipt-operational-authority-20261001/accepted-sql-attempt7/observed-{name}.json'
      for name in ['owner-configure', 'owner-stop', 'owner-lookup-recorded', 'policy-default']],
    *[f'docs/release/collect-codex-goal-2026-09-30/receipt-exception-worker-20261001/accepted-sql-attempt8/observed-worker-{name}.json'
      for name in ['health', 'unknown-health', 'quota-health', 'unobserved-health']],
    *[f'docs/release/collect-codex-goal-2026-09-30/receipt-deferral-exceptions-20261001/accepted-sql-attempt5/observed-{name}.json'
      for name in ['detail-deferred', 'detail-source-cleared', 'detail-handled',
                   'detail-superseded', 'detail-backlog-deferred', 'detail-backlog-handled',
                   'event-inbox', 'backlog-inbox']],
)
CONFIG += CURRENT_ADMIN_DECODER_INPUTS


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root):
    missing = [name for name in CURRENT_ADMIN_DECODER_INPUTS
               if not (root / name).is_file()]
    if missing:
        raise FileNotFoundError('Required Admin decoder inputs missing: ' + ', '.join(missing))
    paths = set()
    for name in TREES:
        paths.update(p for p in (root / name).rglob('*') if p.is_file()
                     and not str(p.relative_to(root)).startswith('test/goldens/failures/'))
    paths.update(root / name for name in CONFIG if (root / name).is_file())
    return {str(p.relative_to(root)): sha(p) for p in sorted(paths)}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def transport_dependencies():
    """Fingerprint actual locked SDK transport source, including shared caches."""
    config = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    manifest = {}
    for package in config['packages']:
        if package['name'] not in {'postgrest', 'supabase', 'supabase_common',
                                   'functions_client', 'http', 'retry',
                                   'realtime_client', 'web_socket_channel',
                                   'file_picker', 'file_picker_platform_interface',
                                   'file_picker_darwin', 'file_picker_web',
                                   'file_picker_linux', 'file_picker_windows',
                                   'android_file_picker', 'cross_file'}:
            continue
        uri = urlparse(package['rootUri'])
        directory = (pathlib.Path(unquote(uri.path)) if uri.scheme == 'file'
                     else ROOT / '.dart_tool' / unquote(uri.path)).resolve(strict=True)
        paths = list((directory / 'lib').rglob('*.dart')) + [directory / 'pubspec.yaml']
        manifest[package['name']] = {
            'root': str(directory),
            'files': {str(p.relative_to(directory)): sha(p) for p in sorted(paths)
                      if p.is_file()},
        }
    return manifest


def bind_packages(export):
    path = export / '.dart_tool/package_config.json'
    config = json.loads(path.read_text())
    rewrites = []
    original_base = ROOT / '.dart_tool'
    for package in config['packages']:
        original = package['rootUri']
        uri = urlparse(original)
        if uri.scheme == 'file':
            resolved = pathlib.Path(unquote(uri.path)).resolve()
        elif not uri.scheme:
            resolved = (original_base / unquote(uri.path)).resolve()
        else:
            raise ValueError('Package root must be a local file path')
        try:
            relative = resolved.relative_to(ROOT)
        except ValueError:
            replacement = resolved
        else:
            # Local pub cache remains a dependency input, while app and forks
            # must resolve solely inside this export.
            replacement = export / relative if not relative.parts or relative.parts[0] != '.cache' else resolved
        if not replacement.is_dir():
            raise ValueError(f'Missing package directory: {package["name"]}')
        package['rootUri'] = replacement.as_uri()
        if package['rootUri'] != original:
            rewrites.append({'package': package['name'], 'original': original,
                             'resolved': str(resolved), 'export': package['rootUri']})
    write_json(path, config)
    required = {'collect_app': export, 'gotrue': export / 'third_party/gotrue',
                'file_saver': export / 'third_party/file_saver',
                'firebase_messaging': export / 'third_party/firebase_messaging'}
    actual = {p['name']: p['rootUri'] for p in config['packages']}
    for name, target in required.items():
        if actual.get(name) != target.as_uri():
            raise ValueError(f'Owned package was not isolated: {name}')
    plugins_path = export / '.flutter-plugins-dependencies'
    if plugins_path.is_file():
        plugins = json.loads(plugins_path.read_text())
        for platform in plugins.get('plugins', {}).values():
            for plugin in platform:
                resolved = pathlib.Path(plugin['path']).resolve()
                try:
                    relative = resolved.relative_to(ROOT / 'third_party')
                except ValueError:
                    continue
                plugin['path'] = str(export / 'third_party' / relative) + '/'
        write_json(plugins_path, plugins)
    return rewrites


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True, type=pathlib.Path)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    parser.add_argument('--sql-receipts', required=True, type=pathlib.Path)
    parser.add_argument('--sql-actor', required=True)
    parser.add_argument('--roster-sql-receipts', type=pathlib.Path)
    parser.add_argument('--capture-operations', action='store_true')
    parser.add_argument('--browser-checkpoint', action='store_true')
    parser.add_argument('--test-file', action='append')
    parser.add_argument('--test-name')
    parser.add_argument('--test-timeout', type=int, default=1200)
    parser.add_argument('--test-concurrency', type=int, default=2)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    export = output / 'source-export'
    export.mkdir()
    before = inventory(ROOT)
    dependencies_before = transport_dependencies()
    write_json(output / 'transport-dependencies-before.json', dependencies_before)
    write_json(output / 'original-before.json', before)
    for name in before:
        destination = export / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, destination)
    copied = inventory(export)
    after_copy = inventory(ROOT)
    copy_valid = before == copied == after_copy
    write_json(output / 'original-after-copy.json', after_copy)
    write_json(output / 'copied-inputs.json', copied)
    if not copy_valid:
        write_json(output / 'validation.json', {'passed': False, 'reason': 'source_changed_during_copy',
            'original_before': before, 'original_after': after_copy, 'copied': copied})
        return 1
    binding_changes = bind_packages(export)
    write_json(output / 'package-binding-adaptation.json', binding_changes)
    exported_before = inventory(export)
    write_json(output / 'export-before.json', exported_before)
    receipt = args.sql_receipts.resolve(strict=True)
    receipt_copy = output / 'actual-read-receipts.stdout'
    shutil.copyfile(receipt, receipt_copy)
    if sha(receipt_copy) != sha(receipt):
        raise ValueError('Actual SQL receipt changed during preservation')
    # Separately dated, isolated synthetic SQL documents are decoder inputs.
    # Their archived source is bound without claiming current installation.
    gateway_path = pathlib.Path('docs/release/collect-codex-goal-2026-09-30/gateway-admin/backend-uat')
    gateway_result = json.loads((export / gateway_path / 'result.json').read_text())
    if (gateway_result.get('status') != 'pass'
            or any(case.get('status') != 'pass' for case in gateway_result.get('cases', []))
            or gateway_result.get('production_written') is not False
            or gateway_result.get('provider_called') is not False
            or gateway_result.get('selected_source_sha256') != gateway_result.get('selected_source_after_sha256')):
        raise ValueError('Dated isolated Gateway receipt provenance failed')
    archived_gateway_source = {}
    for original, expected in gateway_result['selected_source_sha256'].items():
        archived = gateway_path / 'captured-source' / pathlib.Path(original).name
        if sha(export / archived) != expected:
            raise ValueError('Dated Gateway source capture hash mismatch')
        archived_gateway_source[str(archived)] = expected
    gateway_receipts = {
        'result_sha256': sha(export / gateway_path / 'result.json'),
        'archived_source_sha256': archived_gateway_source,
        'observed_document_sha256': {name: sha(export / gateway_path / f'observed-{name}.json')
            for name in ['empty', 'pending', 'active', 'revoked-callbacks', 'owner-request']},
        'sql_executed_here': False, 'current_server_state_verified_here': False,
        'scope': 'Decoder compatibility with archived isolated synthetic-UAT documents; no ordinary-owner installation acceptance.',
    }
    exception_path = pathlib.Path('docs/release/collect-codex-goal-2026-09-30/exception-reads-v2/backend-uat')
    exception_result = json.loads((export / exception_path / 'result.json').read_text())
    if (exception_result.get('status') != 'pass'
            or any(case.get('status') != 'pass' for case in exception_result.get('cases', []))
            or exception_result.get('production_written') is not False
            or exception_result.get('shared_database_written') is not False
            or exception_result.get('provider_called') is not False
            or exception_result.get('source_rows_copied') is not False
            or exception_result.get('draft_preparation_only') is not True
            or exception_result.get('source_sha256') != exception_result.get('source_after_sha256')):
        raise ValueError('Dated isolated Exceptions decoder provenance failed')
    archived_exception_source = {}
    for original, expected in exception_result['source_sha256'].items():
        archived = exception_path / 'executed-migrations' / pathlib.Path(original).name
        if sha(export / archived) != expected:
            raise ValueError('Dated Exceptions source capture hash mismatch')
        archived_exception_source[str(archived)] = expected
    exception_schema = exception_path / 'executed-migrations/schema.json'
    if sha(export / exception_schema) != exception_result['schema_sha256']:
        raise ValueError('Dated Exceptions schema capture hash mismatch')
    exception_receipts = {
        'result_sha256': sha(export / exception_path / 'result.json'),
        'archived_source_sha256': archived_exception_source,
        'archived_schema_sha256': sha(export / exception_schema),
        'observed_document_sha256': {name: sha(export / exception_path / f'observed-{name}.json')
            for name in ['empty', 'populated', 'filtered', 'cleared', 'recorded-lookup',
                         'unknown-lookup', 'progress-lookup', 'action-receipt']},
        'sql_executed_here': False, 'current_server_state_verified_here': False,
        'scope': 'Decoder compatibility with dated isolated synthetic Exceptions documents and their archived sources; no current ordinary-owner installation, hosted Auth or persisted audit acceptance.',
    }
    investigation_path = pathlib.Path('docs/release/collect-codex-goal-2026-09-30/investigation-backend')
    investigation_result = json.loads((export / investigation_path / 'result.json').read_text())
    if (investigation_result.get('status') != 'pass'
            or any(case.get('status') != 'pass' for case in investigation_result.get('cases', []))
            or investigation_result.get('production_written') is not False
            or investigation_result.get('shared_source_written') is not False
            or investigation_result.get('provider_called') is not False
            or investigation_result.get('source_rows_copied') is not False
            or investigation_result.get('source_sha256') != investigation_result.get('source_after_sha256')):
        raise ValueError('Dated isolated investigation decoder provenance failed')
    archived_investigation_source = {}
    for original, expected in investigation_result['source_sha256'].items():
        archived = investigation_path / 'captured-source' / pathlib.Path(original).name
        if sha(export / archived) != expected:
            raise ValueError('Dated investigation source capture hash mismatch')
        archived_investigation_source[str(archived)] = expected
    investigation_receipts = {
        'result_sha256': sha(export / investigation_path / 'result.json'),
        'archived_source_sha256': archived_investigation_source,
        'observed_document_sha256': {name: sha(export / investigation_path / f'observed-{name}.json')
            for name in ['posted-transaction', 'posted-receipt', 'reversed-transaction', 'bounded-history', 'empty']},
        'sql_executed_here': False, 'current_server_state_verified_here': False,
        'scope': 'Dated isolated synthetic investigation DTO compatibility; no current ordinary-owner installation, hosted Auth or persisted audit acceptance.',
    }
    roster_receipt = None
    if args.roster_sql_receipts:
        roster_input = args.roster_sql_receipts.resolve(strict=True)
        roster_result_path = roster_input.parent / 'result.json'
        roster_result = json.loads(roster_result_path.read_text())
        reviewed_sql = ROOT / 'scripts/tests/roster_fresh_auth_recovery_uat.sql'
        if (roster_result.get('status') != 'pass' or not roster_result.get('unchanged')
                or roster_result.get('sql_return_code') != 0 or roster_result.get('failures')
                or roster_result.get('stdout_sha256') != sha(roster_input)
                or roster_result.get('reviewed_source_sha256') != sha(reviewed_sql)
                or roster_result.get('identity', {}).get('latest') != '20260930170000'):
            raise ValueError('Dated actual149 roster receipt provenance failed')
        roster_copy = output / 'actual-roster149-receipts.stdout'
        roster_result_copy = output / 'actual-roster149-receipts.result.json'
        shutil.copyfile(roster_input, roster_copy)
        shutil.copyfile(roster_result_path, roster_result_copy)
        if sha(roster_copy) != sha(roster_input) or sha(roster_result_copy) != sha(roster_result_path):
            raise ValueError('Actual149 roster evidence changed during preservation')
        roster_receipt = {'stdout': str(roster_copy), 'stdout_sha256': sha(roster_copy),
                          'result_sha256': sha(roster_result_copy),
                          'reviewed_sql_source_sha256': sha(reviewed_sql),
                          'installed_identity': roster_result['identity'],
                          'sql_executed_here': False,
                          'current_server_state_verified_here': False}
    command = ['python3', str(export / 'scripts/tests/admin_read_gateway_gate.py'),
               '--flutter', str(args.flutter.resolve(strict=True)),
               '--output', str(output / 'acceptance'), '--phase', 'acceptance',
               '--sql-receipts', str(receipt_copy), '--sql-actor', args.sql_actor,
               '--test-timeout', str(args.test_timeout),
               '--test-concurrency', str(args.test_concurrency)]
    if roster_receipt:
        command.extend(['--roster-sql-receipts', roster_receipt['stdout']])
    if args.capture_operations:
        for name in ('collect-codex-2026-09-30', 'collect-codex-shadow-2026-09-30',
                     'collect-codex-goal-2026-09-30/admin-overview',
                     'collect-codex-goal-2026-09-30/admin-investigation',
                     'collect-codex-goal-2026-09-30/admin-gateway',
                     'collect-codex-goal-2026-09-30/admin-exceptions',
                     'collect-codex-goal-2026-09-30/admin-receipt-cancellation',
                     'collect-codex-goal-2026-09-30/admin-entity-audit',
                     'collect-codex-goal-2026-09-30/admin-operating-policy',
                     'collect-codex-goal-2026-09-30/email-operator'):
            (export / 'docs/release' / name).mkdir(parents=True, exist_ok=True)
        command.append('--capture-operations')
    if args.browser_checkpoint:
        command.append('--browser-checkpoint')
    for test in args.test_file or []:
        command.extend(['--test-file', test])
    if args.test_name:
        command.extend(['--test-name', args.test_name])
    run_env = dict(os.environ)
    if args.capture_operations:
        # Always direct capture-only output into the immutable export's evidence
        # directories, never an inherited path pointing into the shared checkout.
        run_env['COLLECT_ENTITY_AUDIT_CAPTURE'] = str(export / 'docs/release/collect-codex-goal-2026-09-30/admin-entity-audit')
        run_env['COLLECT_POLICY_CAPTURE_DIR'] = str(export / 'docs/release/collect-codex-goal-2026-09-30/admin-operating-policy')
        run_env['COLLECT_CAPTURE_RECEIPT_CANCEL'] = 'true'
    with (output / 'runner.stdout').open('wb') as stream:
        completed = subprocess.run(command, cwd=export, env=run_env, stdout=stream, stderr=subprocess.STDOUT)
    original_after = inventory(ROOT)
    dependencies_after = transport_dependencies()
    write_json(output / 'transport-dependencies-after.json', dependencies_after)
    exported_after = inventory(export)
    write_json(output / 'original-after-run.json', original_after)
    write_json(output / 'export-after.json', exported_after)
    acceptance_path = output / 'acceptance/validation.json'
    acceptance = json.loads(acceptance_path.read_text()) if acceptance_path.exists() else None
    passed = (completed.returncode == 0 and exported_before == exported_after
              and dependencies_before == dependencies_after
              and acceptance is not None and acceptance['test_gate_passed'])
    report = {'passed': passed, 'exit_code': completed.returncode, 'argv': command,
              'source_export': str(export), 'copied_source_exact_and_stable': copy_valid,
              'export_source_unchanged': exported_before == exported_after,
              'transport_dependencies_unchanged': dependencies_before == dependencies_after,
              'transport_dependencies_sha256': sha(output / 'transport-dependencies-before.json'),
              'original_source_unchanged_during_tests': before == original_after,
              'original_source_drift': [n for n in sorted(set(before) | set(original_after))
                                        if before.get(n) != original_after.get(n)],
              'input_count': len(before), 'acceptance_sha256': sha(acceptance_path) if acceptance_path.exists() else None,
              'test_count': acceptance.get('test_count') if acceptance else None,
              'analysis_clean': acceptance.get('analysis_clean') if acceptance else False,
              'browser_checkpoint_passed': acceptance.get('browser_checkpoint_passed') if acceptance else None,
              'receipt_sha256': sha(receipt_copy), 'database_called': False, 'provider_called': False,
              'dated_roster_sql149_receipt': roster_receipt,
              'dated_gateway_decoder_inputs': gateway_receipts,
              'dated_exception_decoder_inputs': exception_receipts,
              'dated_investigation_decoder_inputs': investigation_receipts,
              'synthetic_visual_captures': {str(path.relative_to(export)): sha(path)
                  for path in sorted((export / 'docs/release').rglob('*.png'))}
                  if args.capture_operations else {},
              'gateway_visual_capture_requested': os.environ.get('COLLECT_CAPTURE_GATEWAY_ADMIN') == 'true',
              'scope': 'Exported Flutter runtime, tests, assets and owned forks; actual148 SQL read receipts are immutable read inputs, and SQL is not executed or covered by the Flutter source inventory. Original drift is separately reported; no hosted, visual fidelity or persisted audit claim'}
    write_json(output / 'validation.json', report)
    print(json.dumps(report, indent=2), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
