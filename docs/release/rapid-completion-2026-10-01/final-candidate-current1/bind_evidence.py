#!/usr/bin/env python3
"""Verify the declared source/evidence composition; do not rerun product suites."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
RAPID = HERE.parent
CANDIDATE = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-final-local-candidate-20261001-current1')
NATIVE = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/native-current-local-20261001-resumption1'


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def emit(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def regular(path):
    path = Path(path)
    return path.is_file() and not path.is_symlink()


def source_map(name, expected, manifest, supplement):
    rows = {}
    problems = []
    for relative, value in sorted(expected.items()):
        sha = value['sha256'] if isinstance(value, dict) else value
        live = ROOT / relative
        candidate = CANDIDATE / relative
        supplementary = HERE / 'supplement' / relative
        if relative in manifest:
            captured = candidate
            classification = 'strict_source_export'
        elif relative in supplement:
            captured = supplementary
            classification = 'explicit_reproduction_supplement'
        else:
            captured = None
            classification = 'not_packaged'
        row = {'accepted_sha256': sha, 'classification': classification,
               'current_sha256': digest(live) if regular(live) else None,
               'packaged_sha256': digest(captured) if captured and regular(captured) else None}
        row['matches'] = row['accepted_sha256'] == row['packaged_sha256']
        row['current_matches'] = row['accepted_sha256'] == row['current_sha256']
        if not row['matches']:
            problems.append(relative)
        rows[relative] = row
    return {'status': 'pass' if not problems else 'fail', 'count': len(rows),
            'mismatches': problems, 'live_source_drift': [key for key, row in rows.items() if not row['current_matches']],
            'inputs': rows, 'scope': name}


def main():
    manifest = read(CANDIDATE / '.collect-release-candidate.json')
    assert digest(CANDIDATE / '.collect-release-candidate.json') == 'dba11a4a0deb5822c528c92d770c79d50fa705037f5f23fbd8aed08bcc907fdd'
    supplemental = read(HERE / 'supplement-manifest.json') if (HERE / 'supplement-manifest.json').exists() else {}
    supplement = supplemental.get('files', {})
    ledger = read(RAPID / 'requested-task-evidence-ledger1/ledger.json')
    proofs = {}
    for key, row in ledger['proofs'].items():
        path = ROOT / row['path']
        actual = digest(path) if regular(path) else None
        proofs[key] = {**row, 'current_receipt_sha256': actual,
                       'receipt_bytes_match_ledger': actual == row.get('sha256')}
    added = {
        'final_flutter': RAPID / 'full-flutter-accepted-union1/validation.json',
        'final_admin_browser': RAPID / 'current-admin-browser-current2/browser-acceptance.json',
        'final_admin_build_inputs': RAPID / 'current-admin-browser-current2/copied-inputs.json',
        'current_edge': RAPID / 'current-edge-http-terminal1/current-source-rebind.json',
        'current_mcp': RAPID / 'current-mcp-all-modules-terminal1/validation.json',
        'compatibility': RAPID / 'requested-task-evidence-ledger1/L23-COMPATIBILITY.md',
        'ordinary_platform': RAPID / 'ordinary-transport-owner-review1/validation.json',
        'source_export': HERE / 'export.json',
        'source_supplement': HERE / 'supplement-manifest.json',
        'native_terminal': NATIVE / 'final-native-acceptance.json',
        'live_source_readback': HERE / 'final-source-readback.json',
        'immutable_candidate_readback': HERE / 'accepted-candidate-readback.json',
        'source_archive': HERE / 'source-archive-readback.json',
        'current_admin_inventory': HERE / 'admin-inventory/validation.json',
        'current_admin_route_action_acceptance': HERE / 'admin-inventory/route-action-acceptance.json',
        'final_gateway_full_tests': NATIVE / 'final-native-current2-acceptance.json',
        'current_generic_action_audits': HERE / 'generic-action-audits/attempt4-json-scalar-contract/result.json',
    }
    for key, path in added.items():
        proofs[key] = {'path': str(path.relative_to(ROOT)), 'available': regular(path),
                       'sha256': digest(path) if regular(path) else None}
    flutter = read(added['final_flutter'])
    edge = read(added['current_edge'])
    mcp = read(added['current_mcp'])
    ordinary = read(RAPID / 'ordinary-installer-current-resumption3-private-platform/result.json')
    browser = read(added['final_admin_browser'])
    lifecycle = read(Path(browser['report']))
    assert digest(browser['report']) == browser['report_sha256']
    assert lifecycle['sources_before'] == lifecycle['sources_after']
    maps = {
        'Flutter runtime': flutter['current_lib_source_sha256'],
        'Flutter selected VM test sources': {k: v['test_source_sha256'] for k, v in flutter['cohorts'].items()},
        'Edge HTTP inputs': edge['source_inputs']['http'],
        'Edge unit inputs': edge['source_inputs']['units'],
        'MCP runtime, decoder and dependency inputs': mcp['current_runtime_decoder_dependency_inputs'],
        'Ordinary installer current185 migration bodies': {r['path']: r['sha256'] for r in ordinary['source_inventory']},
        'Platform receipt transport prerequisites': ordinary['platform_prerequisite_sha256'],
        'Executed production Admin and Public source consumers': lifecycle['sources_before'],
        'Selected source lockfiles': manifest['toolchain']['lock_sha256'],
        'Explicit reproduction supplement': supplement,
    }
    if added['current_generic_action_audits'].exists():
        audits = read(added['current_generic_action_audits'])
        maps['Current generic Admin actual audit harness sources'] = audits['source_inputs']
        maps['Current generic Admin appended31 migration bodies'] = audits['actual_appended_stage_sha256']
    native = read(added['native_terminal']) if added['native_terminal'].exists() else None
    native_artifacts = {}
    if native:
        assert native['status'] == 'pass'
        assert native['captured_final_manifest_sha256'] == digest(CANDIDATE / '.collect-release-candidate.json')
        maps['Android production executed consumer inputs'] = read(NATIVE / 'production/current-compiler-input-readback.json')['source_sha256']
        maps['Android Gateway final89 native source inputs'] = read(NATIVE / 'gateway-archive-final/final-flat-native-inputs.json')
        for relative, expected in native['evidence_sha256'].items():
            path = NATIVE / relative
            actual = digest(path) if regular(path) else None
            proofs['native/' + relative] = {'path': str(path.relative_to(ROOT)), 'sha256': expected,
                                           'current_receipt_sha256': actual, 'receipt_bytes_match_ledger': expected == actual}
        for family in ['production', 'gateway']:
            row = native[family]
            actual = digest(row['artifact']) if regular(row['artifact']) else None
            native_artifacts[family] = {**row, 'readback_sha256': actual, 'status': 'pass' if row['sha256'] == actual else 'fail'}
        ios_files = read(NATIVE / 'ios/bundle-manifest.json')
        assert digest(NATIVE / 'ios/bundle-manifest.json') == native['ios']['bundle_manifest_sha256']
        ios_root = Path(native['ios']['artifact'])
        ios_drift = []
        for relative, row in ios_files['files'].items():
            path = ios_root / relative
            if not regular(path) or digest(path) != row['sha256']:
                ios_drift.append(relative)
        for relative, target in ios_files['symlinks'].items():
            path = ios_root / relative
            if not path.is_symlink() or str(path.readlink()) != target:
                ios_drift.append(relative)
        native_artifacts['ios'] = {**native['ios'], 'bundle_drift': ios_drift,
                                   'status': 'pass' if not ios_drift else 'fail'}
    bindings = {name: source_map(name, rows, manifest['source_files'], supplement) for name, rows in maps.items()}
    failures = {name: row['mismatches'] for name, row in bindings.items() if row['status'] != 'pass'}
    receipt_drift = [key for key, row in proofs.items() if row.get('receipt_bytes_match_ledger') is False]
    missing = [key for key, row in proofs.items() if row.get('available') is False]
    command_and_log_receipts = {}
    for relative, expected in flutter['receipt_sha256'].items():
        path = RAPID / relative
        actual = digest(path) if regular(path) else None
        command_and_log_receipts[str(path.relative_to(ROOT))] = {'accepted_sha256': expected, 'current_sha256': actual, 'matches': expected == actual}
    artifact_rows = {}
    served_artifact_root = Path(browser['report']).parent
    for family, directory in [('admin', served_artifact_root / 'admin-build'), ('public', served_artifact_root / 'public-build')]:
        rows = {}
        for relative, expected in browser['artifact_hashes'][family].items():
            path = directory / relative
            actual = digest(path) if regular(path) else None
            rows[relative] = {'accepted_sha256': expected, 'current_sha256': actual, 'matches': expected == actual}
        artifact_rows[family] = {'path': str(directory), 'files': rows, 'status': 'pass' if all(v['matches'] for v in rows.values()) else 'fail'}
    log_drift = [key for key, row in command_and_log_receipts.items() if not row['matches']]
    artifact_drift = [key for key, row in artifact_rows.items() if row['status'] != 'pass']
    native_artifact_drift = [key for key, row in native_artifacts.items() if row['status'] != 'pass']
    archive = read(added['source_archive']) if added['source_archive'].exists() else None
    archive_ok = archive is not None and archive['status'] == 'pass' and digest(archive['archive']) == archive['archive_sha256']
    required_acceptance_status = {key: read(path).get('status') if path.exists() else 'missing' for key, path in added.items()
                                  if key in ['final_flutter', 'final_admin_browser', 'current_edge', 'current_mcp',
                                             'native_terminal', 'immutable_candidate_readback', 'source_archive',
                                             'current_admin_inventory', 'current_admin_route_action_acceptance', 'final_gateway_full_tests',
                                             'current_generic_action_audits']}
    route_acceptance = read(added['current_admin_route_action_acceptance']) if added['current_admin_route_action_acceptance'].exists() else None
    route_criterion_met = bool(route_acceptance and route_acceptance['status'] == 'pass_scoped'
                              and route_acceptance['all_applicable_declared_route_states_have_named_executed_cases']
                              and route_acceptance['all_declared_actions_have_practical_current_candidate_evidence']
                              and not route_acceptance['meaningful_unmet_enabled_action_audit_criteria'])
    unsuccessful_acceptance = {key: value for key, value in required_acceptance_status.items()
                               if value != 'pass' and not (key == 'current_admin_route_action_acceptance' and route_criterion_met)}
    packet = {
        'schema_version': 1,
        'kind': 'final_local_source_and_acceptance_composition',
        'captured_at_utc': datetime.now(timezone.utc).isoformat(),
        'status': 'pass' if not failures and not receipt_drift and not missing and not log_drift and not artifact_drift and not native_artifact_drift and archive_ok and not unsuccessful_acceptance else 'incomplete',
        'source_export': str(CANDIDATE),
        'source_manifest_sha256': manifest['source_manifest_sha256'],
        'candidate_manifest_sha256': digest(CANDIDATE / '.collect-release-candidate.json'),
        'source_files': manifest['file_count'],
        'source_bytes': manifest['total_bytes'],
        'source_migrations': len(manifest['migration_versions']),
        'source_approvals': manifest['approvals'],
        'toolchain_and_locks': manifest['toolchain'],
        'evidence': proofs,
        'receipt_drift': receipt_drift,
        'missing_receipts': missing,
        'source_bindings': bindings,
        'source_binding_failures': failures,
        'later_live_source_drift': {name: row['live_source_drift'] for name, row in bindings.items() if row['live_source_drift']},
        'live_source_readback': read(added['live_source_readback']) if added['live_source_readback'].exists() else None,
        'accepted_candidate_readback': read(added['immutable_candidate_readback']) if added['immutable_candidate_readback'].exists() else None,
        'executed_commands_and_logs': command_and_log_receipts,
        'log_drift': log_drift,
        'browser_artifacts': artifact_rows,
        'browser_artifact_drift': artifact_drift,
        'native_artifacts': native_artifacts,
        'native_artifact_drift': native_artifact_drift,
        'source_archive': archive,
        'source_archive_readback_hash_matches': archive_ok,
        'required_terminal_acceptance': required_acceptance_status,
        'unsuccessful_acceptance': unsuccessful_acceptance,
        'current_Admin_route_action_criterion_met_in_declared_local_scope': route_criterion_met,
        'acceptance_counts': {'Flutter_registered_VM_passes': flutter['registered_vm_cases_passed'],
                              'Flutter_VM_cohorts': flutter['vm_cohorts'],
                              'Chrome_component_cases': flutter['chrome_cases'],
                              'production_browser_checks': flutter['production_browser_checks'],
                              'Edge_unit_cases': edge['unit_cases'], 'Edge_HTTP_checks': edge['http_checks'],
                              'MCP_unique_cases': mcp['unique_successful_cases'], 'MCP_modules': len(mcp['modules']),
                              'ordinary_migration_applications': 2 * len(ordinary['source_inventory']),
                              'ordinary_named_checks': len(ordinary['cases']),
                              'production_native_JVM_cases': 12, 'final_Gateway_Gradle_JVM_cases': 141,
                              'final_Gateway_standalone_cases_separate_suite': 190,
                              'iOS_bundle_files': 197, 'source_SBOM_components': 686,
                              'observed_production_components': 200, 'observed_Gateway_components': 187,
                              'generic_Admin_actual_audit_checks': 59, 'generic_Admin_mutations_audited': 12},
        'scope': 'Actual local suites and builds are reused only within their declared executed consumer input maps and the exact immutable2117-file candidate plus371-file reproduction supplement. Original timeout/failure receipts are retained; successful bounded corrections are explicitly composed. Later concurrent live-checkout edits are separately recorded and are not accepted by this packet. This command hashes evidence and inputs; it does not rerun tests or certify deployment.',
        'limits': ['No signed or store-ready artifacts', 'No hosted/provider/device acceptance',
                   'No owner release approval or source provenance attestation',
                   'No 100 percent Revolut comparator certification',
                   'No ongoing whole mutable-checkout parity claim'],
    }
    emit(HERE / 'evidence-binding.json', packet)
    print(json.dumps({'status': packet['status'], 'source_binding_failures': failures,
                      'receipt_drift': receipt_drift, 'missing_receipts': missing,
                      'log_drift': log_drift, 'browser_artifact_drift': artifact_drift,
                      'native_artifact_drift': native_artifact_drift,
                      'later_live_source_drift': packet['later_live_source_drift'],
                      'binding_counts': {key: value['count'] for key, value in bindings.items()}}))


if __name__ == '__main__':
    main()
