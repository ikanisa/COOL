#!/usr/bin/env python3
"""Source-bound member data acceptance; synthetic local transports only.

This gate copies current source and dependency inputs. No database target,
provider credentials, deployment or native build is accepted or invoked.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import sys
import urllib.parse

from roster_fresh_auth_gate import ROOT, command, hashes, machine_summary, sha, source_files

TESTS = [
    'test/data_correctness_contract_test.dart',
    'test/admin_roster_calendar_test.dart',
    'test/shared/contribution_intent_binding_test.dart',
    'test/shared/member_data_authority_test.dart',
    'test/shared/member_read_integrity_test.dart',
    'test/shared/member_mutation_session_test.dart',
    'test/features/member_data_unknown_states_test.dart',
    'test/features/contribution_flow_session_test.dart',
    'test/core/momo_ussd_amount_boundary_test.dart',
    'test/core/momo_ussd_intent_guard_test.dart',
    'test/core/play_integrity_service_test.dart',
    'test/core/rwf_amount_input_formatter_test.dart',
    'test/core/money_format_test.dart',
    'test/shared/pending_shared_group_intent_store_test.dart',
    'test/payment_json_integrity_test.dart',
    'test/payment_intent_decoding_test.dart',
    'test/payment_event_decoding_test.dart',
    'test/payment_cache_integrity_test.dart',
    'test/payment_intent_cache_boundary_test.dart',
    'test/group_summary_integrity_test.dart',
    'test/group_summary_decoding_test.dart',
    'test/group_summary_cache_recovery_test.dart',
    'test/member_history_page_integrity_test.dart',
    'test/member_history_controller_integrity_test.dart',
    'test/shared/member_history_pagination_test.dart',
    'test/shared/rwanda_momo_history_test.dart',
    'test/shared/collect_offline_cache_test.dart',
    'test/shared/collect_repository_test.dart',
    'test/shared/collect_repository_live_reader_contract_test.dart',
    'test/shared/collect_profile_country_rules_test.dart',
    'test/group_list_summary_availability_test.dart',
    'test/hardening/editorial_summary_availability_test.dart',
]
WEB_TESTS = [
    'test/data_correctness_contract_test.dart',
    'test/admin_roster_calendar_test.dart',
    'test/payment_json_integrity_test.dart',
    'test/member_history_page_integrity_test.dart',
    'test/core/rwf_amount_input_formatter_test.dart',
    'test/core/money_format_test.dart',
]
STATIC_TEST_INPUTS = [
    'supabase/migrations/20260925190000_rwanda_momo_only.sql',
    'scripts/supabase_production_readiness.sh',
]
SQL_HISTORY_TEST = 'test/actual_member_history_sql_receipts_test.dart'


def bind_sql_history(source, packet, export, prior_unsafe=None):
    source = source.resolve(strict=True)
    if not source.is_relative_to(ROOT / 'docs/release/data-correctness-2026-09-30'):
        raise RuntimeError('A reviewed local data SQL release packet is required')
    result_path = source / 'result.json'
    result = json.loads(result_path.read_text())
    allowed_failed = {
        'review input plus genuine finalizer refuses nonexact money 9007199254740992',
        'review input plus genuine finalizer refuses nonexact money 9223372036854775807',
        'history server does not publish nonexact aggregate JSON',
    }
    failed = [row for row in result['cases'] if row['status'] != 'pass']
    if (result['kind'] != 'installed154_plus_exact234000_synthetic_positive_history_mechanics'
            or result.get('failure') or result['status'] not in ('failed', 'pass_scoped')
            or len(result['cases']) < 42
            or any(row['name'] not in allowed_failed for row in failed)
            or not result['source_inputs_unchanged'] or not result['recorder_sources_unchanged']
            or not result['all_source_tables_catalog_cron_preserved']
            or not result['isolated_database_removed'] or result['source_rows_copied']
            or result['hosted_called'] or result['provider_called'] or result['independent_provider_truth']
            or result['signed_jwt_tested'] or result['native_device_attestation_tested']
            or result['source_guard']['count'] != 154
            or result['source_guard']['latest'] != '20260930230000'):
        raise RuntimeError('Actual positive-history receipt provenance/scope failed')
    names = ['actual-member-history-pages.json', 'actual-member-balances.json',
             'synthetic-reconciliation-receipts.json', 'financial-after-fixture-before-reads.json',
             'actual-history-wrapper-plans.json']
    before = {name: sha(source / name) for name in names}
    if before != result['artifact_sha256']:
        raise RuntimeError('Actual SQL artifacts changed after execution')
    baseline = json.loads((source / names[3]).read_text())
    if baseline != result['financial_after']:
        raise RuntimeError('Actual SQL history/precision probes changed financial fingerprints')
    receipts = packet / 'actual-history-sql'
    receipts.mkdir()
    for name in names + ['result.json']:
        (receipts / name).write_bytes((source / name).read_bytes())
    if before != {name: sha(source / name) for name in names} or sha(result_path) != sha(receipts / 'result.json'):
        raise RuntimeError('Actual SQL packet changed during copy')
    fixture = {
        'pages': json.loads((receipts / names[0]).read_text()),
        'balances': json.loads((receipts / names[1]).read_text()),
        'precision_observations': result.get('precision_boundary_observations', []),
        'aggregate_observation': result.get('aggregate_boundary_observation', {}),
        'synthetic_mechanics_only': True,
    }
    prior_scope = None
    if prior_unsafe is not None:
        prior_unsafe = prior_unsafe.resolve(strict=True)
        if not prior_unsafe.is_relative_to(ROOT / 'docs/release/data-correctness-2026-09-30'):
            raise RuntimeError('A retained local unsafe SQL packet is required')
        prior_result_path = prior_unsafe / 'result.json'
        prior_sha = sha(prior_result_path)
        prior = json.loads(prior_result_path.read_text())
        # This exact retained packet includes39 passing genuine posting/read
        # controls, three real money failures, and one later-corrected zero-shape
        # harness assertion. Its failures remain failures; only its actual JSON
        # observations are consumed as negative decoder inputs.
        if (prior_sha != '36b17dfef5357a778e2a8bbd9b65aff18e3b3afaac775cd4d771e955530691d0'
                or prior.get('failure') or prior['status'] != 'failed'
                or prior['kind'] != result['kind']
                or sum(c['status']=='pass' for c in prior['cases']) != 39
                or sum(c['status']=='failed' for c in prior['cases']) != 4
                or not prior['all_source_tables_catalog_cron_preserved']
                or not prior['isolated_database_removed'] or not prior['recorder_sources_unchanged']
                or not prior['source_inputs_unchanged'] or prior['source_rows_copied']
                or prior['provider_called'] or prior['hosted_called'] or prior['independent_provider_truth']):
            raise RuntimeError('Retained unsafe SQL receipt provenance failed')
        unsafe = [observation for observation in prior['precision_boundary_observations']
                  if observation.get('actual_response') is not None]
        aggregate = prior['aggregate_boundary_observation']
        if (len(unsafe) != 1 or unsafe[0]['amount'] != 9007199254740992
                or aggregate.get('actual_response',{}).get('totals',{}).get('RWF') != 9007199254740992):
            raise RuntimeError('Expected genuine unsafe individual and aggregate receipts missing')
        fixture['precision_observations'] += unsafe
        fixture['aggregate_observation'] = aggregate
        fixture['historical_unsafe_observation_count'] = 2
        (receipts / 'retained-unsafe-result.json').write_bytes(prior_result_path.read_bytes())
        if prior_sha != sha(prior_result_path) or prior_sha != sha(receipts / 'retained-unsafe-result.json'):
            raise RuntimeError('Retained unsafe SQL receipt changed during copy')
        prior_scope = {'source_packet':str(prior_unsafe.relative_to(ROOT)), 'result_sha256':prior_sha,
            'server_result_status':'failed', 'passing_cases':39, 'failed_cases':4,
            'negative_decoder_observations':2, 'corrected_server_acceptance':False}
    defines = export / '.qa_actual_history_defines.json'
    defines.write_text(json.dumps({'MEMBER_HISTORY_SQL_RECEIPTS_BASE64':
        base64.b64encode(json.dumps(fixture).encode()).decode()}, separators=(',', ':')) + '\n')
    return defines, {
        'source_packet': str(source.relative_to(ROOT)), 'result_sha256': sha(receipts / 'result.json'),
        'artifact_sha256': before, 'define_file_sha256': sha(defines),
        'server_result_status': result['status'], 'server_failed_cases': failed,
        'receipt_candidate': result.get('receipt_candidate'), 'mode':result.get('mode'),
        'reviewed_stage_packet':result.get('reviewed_stage_packet'), 'retained_unsafe_scope':prior_scope,
        'current_server_acceptance': False, 'sql_executed_here': False,
        'scope': 'Genuine public reconciliation API synthetic mechanics, captured positive history and explicitly retained unsafe observations; decoder acceptance is separate from server failures and provider/device/settlement acceptance.',
    }


def copy_export(packet):
    export = packet / 'source-export'
    export.mkdir()
    files = sorted(set(source_files()) | {Path(__file__).resolve()} |
                   {ROOT / path for path in STATIC_TEST_INPUTS})
    before = hashes(files, ROOT)
    for path in files:
        target = export / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        content = path.read_bytes()
        if hashlib.sha256(content).hexdigest() != before[str(path.relative_to(ROOT))]:
            raise RuntimeError('Source changed during copy: ' + str(path.relative_to(ROOT)))
        target.write_bytes(content)
    if hashes(files, ROOT) != before:
        raise RuntimeError('Source changed during copy')
    config_path = export / '.dart_tool/package_config.json'
    config = json.loads(config_path.read_text())
    dependencies, sdk_roots, sdk_files = {}, {}, []
    for package in config['packages']:
        if not package['rootUri'].startswith('file:'):
            continue
        source = Path(urllib.parse.unquote(urllib.parse.urlparse(package['rootUri']).path))
        if package['name'] in ['flutter', 'flutter_test', 'flutter_localizations',
                               'integration_test', 'sky_engine', 'flutter_web_plugins']:
            sdk_roots[package['name']] = source
            sdk_files.extend(p for p in (source / 'lib').rglob('*') if p.is_file())
            sdk_files.append(source / 'pubspec.yaml')
            continue
        target = export / '.qa_dependencies' / package['name']
        target.mkdir(parents=True)
        copied = []
        for path in sorted(source.rglob('*')):
            if path.is_file() and not any(x in path.relative_to(source).parts
                    for x in ['example', 'test', 'doc', '.git', '.dart_tool',
                              'build', '.gradle', 'Pods']):
                dest = target / path.relative_to(source)
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(path.read_bytes())
                copied.append(path)
        if any(sha(p) != sha(target / p.relative_to(source)) for p in copied):
            raise RuntimeError('Dependency changed during copy: ' + package['name'])
        dependencies[package['name']] = {'source_root': str(source),
            'files': {str(p.relative_to(source)): sha(p) for p in copied}}
        package['rootUri'] = target.as_uri()
    config_path.write_text(json.dumps(config, indent=2) + '\n')
    plugins_path = export / '.flutter-plugins-dependencies'
    plugins = json.loads(plugins_path.read_text())
    for entries in plugins.get('plugins', {}).values():
        for plugin in entries:
            owned = export / 'third_party' / plugin['name']
            dependency = export / '.qa_dependencies' / plugin['name']
            if owned.exists():
                plugin['path'] = str(owned) + '/'
            elif dependency.exists():
                plugin['path'] = str(dependency) + '/'
            elif plugin['name'] in sdk_roots:
                plugin['path'] = str(sdk_roots[plugin['name']]) + '/'
            else:
                raise RuntimeError('Uncopied plugin input: ' + plugin['name'])
    plugins_path.write_text(json.dumps(plugins, indent=2) + '\n')
    return export, files, before, dependencies, sdk_files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--analysis-timeout', type=int, default=180,
                        help='Bounded full analysis observation window; timeout remains a failed attempt')
    parser.add_argument('--flutter', required=True, type=Path)
    parser.add_argument('--chrome', required=True, type=Path)
    parser.add_argument('--sql-history', type=Path,
                        help='Terminal genuine local positive-history packet to bind in VM and Chrome')
    parser.add_argument('--sql-history-prior', type=Path,
                        help='Exact retained unsafe SQL result used only for negative decoder observations')
    args = parser.parse_args()
    if not 1 <= args.analysis_timeout <= 900:
        parser.error('--analysis-timeout must be within 1..900 seconds')
    if args.sql_history_prior is not None and args.sql_history is None:
        parser.error('--sql-history-prior requires --sql-history')
    packet = args.output.resolve()
    if not packet.is_relative_to(ROOT / 'docs/release/data-correctness-2026-09-30'):
        parser.error('A fresh data correctness release packet is required')
    packet.mkdir(parents=True, exist_ok=False)
    result = {'status': 'fail', 'whole_system_acceptance': False,
              'sql_executed_here': False, 'provider_calls': False, 'commands': []}
    try:
        export, files, before, dependencies, sdk_files = copy_export(packet)
        tests, browser_tests, defines = list(TESTS), list(WEB_TESTS), []
        if args.sql_history:
            define_path, sql_scope = bind_sql_history(args.sql_history, packet, export, args.sql_history_prior)
            result['actual_sql_history_scope'] = sql_scope
            tests.append(SQL_HISTORY_TEST)
            browser_tests.append(SQL_HISTORY_TEST)
            defines = [f'--dart-define-from-file={define_path}']
        flutter = args.flutter.resolve(strict=True)
        dart = flutter.parent / 'cache/dart-sdk/bin/dart'
        chrome = args.chrome.resolve(strict=True)
        sdk_files += [flutter, dart, chrome, flutter.parent / 'cache/flutter_tools.snapshot']
        sdk_files += [flutter.parent / 'cache/artifacts/engine/darwin-x64/flutter_tester']
        sdk_files.extend(p for p in (flutter.parent / 'cache/dart-sdk/bin').rglob('*')
                         if p.is_file())
        tool_root = flutter.parent.parent / 'packages/flutter_tools'
        sdk_files.extend(p for p in (tool_root / 'lib').rglob('*') if p.is_file())
        for directory in ['dart-sdk/lib', 'artifacts/engine/common/flutter_web_sdk']:
            sdk_files.extend(p for p in (flutter.parent / 'cache' / directory).rglob('*')
                             if p.is_file())
        sdk_before = {str(p): sha(p) for p in sorted(set(sdk_files)) if p.is_file()}
        export_files = sorted(p for p in export.rglob('*') if p.is_file())
        export_before = hashes(export_files, export)
        (packet / 'inputs.json').write_text(json.dumps({
            'source': before, 'export': export_before, 'dependencies': dependencies,
            'sdk_and_browser': sdk_before, 'declared_vm_tests': tests,
            'declared_browser_tests': browser_tests,
            'actual_sql_history_scope': result.get('actual_sql_history_scope'),
            'declared_static_test_inputs': STATIC_TEST_INPUTS}, indent=2) + '\n')
        environment = os.environ.copy()
        environment['CHROME_EXECUTABLE'] = str(chrome)
        for name, argv, timeout in [
            ('toolchain', [str(flutter), '--version', '--machine'], 30),
            ('analysis', [str(dart), 'analyze', 'lib', *tests], args.analysis_timeout),
            ('vm', [str(flutter), 'test', '--no-pub', '--concurrency=1',
                    '--reporter=expanded',
                    f'--file-reporter=json:{packet / "vm.machine.jsonl"}', *defines, *tests], 900),
            ('browser', [str(flutter), 'test', '--no-pub', '--platform=chrome',
                    '--concurrency=1', '--reporter=expanded',
                    f'--file-reporter=json:{packet / "browser.machine.jsonl"}', *defines, *browser_tests], 600),
        ]:
            receipt = command(name, argv, export, packet,
                              environment=environment, timeout=timeout)
            result['commands'].append(receipt)
            if receipt['exit_code']:
                break
        result.update(vm=machine_summary(packet / 'vm.machine.jsonl'),
                      browser=machine_summary(packet / 'browser.machine.jsonl'))
        # Publication can legitimately remove or add source inputs while an
        # immutable acceptance runs. Record that drift without losing the
        # completed runner receipts to a missing-file exception.
        live_files = sorted(set(source_files()) | {Path(__file__).resolve()} |
                            {ROOT / path for path in STATIC_TEST_INPUTS})
        source_after = hashes([path for path in live_files if path.is_file()], ROOT)
        result['live_source_drift'] = sorted(
            k for k in set(before) | set(source_after)
            if before.get(k) != source_after.get(k))
        result['live_source_removed'] = sorted(set(before) - set(source_after))
        result['live_source_added'] = sorted(set(source_after) - set(before))
        result['export_unchanged'] = export_before == hashes([export / p for p in export_before], export)
        result['sdk_and_browser_unchanged'] = all(sha(Path(p)) == value for p, value in sdk_before.items())
        result['inputs_sha256'] = sha(packet / 'inputs.json')
        passed = len(result['commands']) == 4 and all(
            c['exit_code'] == 0 for c in result['commands'])
        for name in ['vm', 'browser']:
            summary = result[name]
            passed &= summary['runner_completed_successfully'] and summary['passed'] > 0
            passed &= not (summary['failed'] or summary['errors'] or summary['skipped'])
        passed &= result['export_unchanged'] and result['sdk_and_browser_unchanged']
        result['status'] = 'pass' if passed else 'fail'
        result['current_source_acceptance'] = bool(passed and not result['live_source_drift'])
    except Exception as error:
        result['error'] = type(error).__name__ + ': ' + str(error)
    (packet / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result.get(k) for k in [
        'status', 'current_source_acceptance', 'live_source_drift', 'error']}, indent=2))
    return 0 if result['status'] == 'pass' else 1


if __name__ == '__main__':
    sys.exit(main())
