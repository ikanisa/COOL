#!/usr/bin/env python3
"""Read-only association of prior scoped MCP evidence with retained source06.

No MCP process, tool call, Auth/Keychain operation, installation or network.
Only this evidence leaf receives output; prior packets and source remain intact.
"""
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import math
import os
import subprocess
import tomllib

ROOT = Path(__file__).resolve().parents[6]
OUTPUT = Path(__file__).resolve().parent
GOAL = ROOT / 'docs/release/collect-codex-goal-2026-09-30'
JOURNAL = GOAL / 'receipt-supervisor-journal'
PRIOR = GOAL / 'release-tooling/checkpoint05'
NODE = Path('/Volumes/PRO-G40/Development/Node/bin/node')
BRIDGE = ROOT / 'tools/collect-notification-mcp'
READS = frozenset({
    'collect_list_pending_receipts', 'collect_notification_health',
    'get_collect_health', 'get_notification_status', 'list_notification_failures',
})


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def relative(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name or '\0' in name:
        raise ValueError('EVIDENCE_PATH_INVALID')
    return path


def regular(root, name):
    path = root
    for part in relative(name).parts:
        path = path / part
        if path.is_symlink():
            raise ValueError('EVIDENCE_SYMLINK_REFUSED')
    if not path.is_file():
        return None
    data = path.read_bytes()
    return {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}


def packet_integrity(path):
    manifest = json.loads((path / 'MANIFEST.json').read_text())
    differences = []
    for name, recorded in manifest['files'].items():
        observed = regular(path, name)
        if observed is None or any(observed.get(k) != recorded.get(k) for k in ('bytes', 'sha256')):
            differences.append(name)
    return {'manifest_sha256': sha(path / 'MANIFEST.json'),
            'file_count': len(manifest['files']), 'readback_matches': not differences,
            'different_or_missing_paths': differences}


def compare(candidate, manifest, expected):
    rows = {}
    for name, recorded in expected.items():
        observed = regular(candidate, name)
        captured = manifest['source_files'].get(name)
        rows[name] = {
            'recorded': {'sha256': recorded['sha256'], 'bytes': recorded['bytes']},
            'captured_manifest': None if captured is None else
                {'sha256': captured['sha256'], 'bytes': captured['bytes']},
            'captured_readback': observed,
            'matches_recorded_and_manifest': observed is not None and captured is not None
                and all(observed[k] == recorded[k] == captured[k] for k in ('sha256', 'bytes')),
        }
    return {'checked_files': len(rows), 'matching_files': sum(
        row['matches_recorded_and_manifest'] for row in rows.values()),
        'different_or_missing_paths': [name for name, row in rows.items()
                                       if not row['matches_recorded_and_manifest']],
        'files': rows}


def host_metadata(prior):
    # Parse locally; access only fixed metadata. Never copy/forward profile env.
    path = Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))) / 'config.toml'
    try:
        profile = tomllib.loads(path.read_text())['mcp_servers']['collect-notifications']
        names = profile.get('enabled_tools')
        exact = isinstance(names, list) and len(names) == 5 and all(
            isinstance(name, str) for name in names) and set(names) == READS
        command = Path(profile['command'])
        args = profile['args']
        fixed = (command.is_file() and command.resolve().name == 'node'
                 and Path(profile['cwd']).resolve() == BRIDGE.resolve()
                 and isinstance(args, list) and len(args) == 2
                 and args[0] == '--experimental-strip-types'
                 and Path(args[1]).resolve() == (BRIDGE / 'src/server.ts').resolve())
        deadlines = {}
        for key in ('startup_timeout_sec', 'tool_timeout_sec'):
            value = profile.get(key)
            deadlines[key] = value if isinstance(value, (int, float)) and not isinstance(
                value, bool) and math.isfinite(value) and 0 < value <= 300 else None
        result = {
            'readable': True, 'config_path': str(path),
            'exact_five_read_allowlist': exact,
            'enabled_read_tools': sorted(READS) if exact else [],
            'enabled': profile.get('enabled', True) is True,
            'fixed_local_bridge_invocation': fixed,
            'configured_node_sha256': sha(command) if fixed else None,
            'timeouts': deadlines,
            'same_read_allowlist_as_prior_discovery': exact and sorted(READS)
                == prior['host_enabled_tools'],
            'host_runtime_reload_verified': False,
            'config_environment_reported': False, 'config_environment_forwarded': False,
        }
        if fixed:
            result['configured_node_path'] = str(command)
            result['configured_node_version'] = subprocess.run(
                [str(command), '--version'], env={}, check=True, capture_output=True,
                text=True, timeout=10).stdout.strip()
            result['configured_node_version_matches_prior_discovery'] = (
                result['configured_node_version'] == prior['node_version'])
            result['configured_node_matches_regression_binary_hash'] = (
                result['configured_node_sha256'] == sha(NODE))
        result['historical_configured_node_binary_sha256_available'] = False
        result['historical_configured_node_binary_equality_attested'] = False
        result['same_deadlines_as_prior_discovery'] = deadlines == {
            'startup_timeout_sec': prior['host_startup_timeout_sec'],
            'tool_timeout_sec': prior['host_tool_timeout_sec'],
        }
        return result
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return {'readable': False, 'reason_code': 'HOST_METADATA_UNAVAILABLE',
                'config_environment_reported': False, 'config_environment_forwarded': False,
                'host_runtime_reload_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--manifest-sha256', required=True)
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    manifest_path = candidate / '.collect-release-candidate.json'
    if sha(manifest_path) != args.manifest_sha256:
        raise ValueError('SOURCE06_MANIFEST_MISMATCH')
    manifest = json.loads(manifest_path.read_text())
    journal = json.loads((JOURNAL / 'verification.json').read_text())
    dependency = json.loads((PRIOR / 'mcp-dependency-binding.json').read_text())
    discovery = json.loads((PRIOR / 'mcp-host-read-only-discovery.json').read_text())
    journal_compare = compare(candidate, manifest, journal['source_files'])
    discovery_compare = compare(candidate, manifest, dependency['bridge_source_files'])
    if journal_compare['checked_files'] != 58 or discovery_compare['checked_files'] != 42:
        raise ValueError('PRIOR_SCOPE_COUNT_CHANGED')
    compiler = BRIDGE / 'node_modules/.pnpm/typescript@7.0.2/node_modules/typescript/bin/tsc'
    version = subprocess.run([str(NODE), '--version'], env={}, check=True,
                             capture_output=True, text=True, timeout=10).stdout.strip()
    runtime = {'node_path': str(NODE), 'node_version': version, 'node_sha256': sha(NODE),
               'node_matches_prior': sha(NODE) == journal['node_sha256']
                   and version == journal['node_version'],
               'compiler_sha256': sha(compiler),
               'compiler_matches_prior': sha(compiler) == journal['compiler_sha256'],
               'installed_package_manifests': {}}
    for name, recorded in dependency['resolved_package_manifests'].items():
        file = BRIDGE / 'node_modules' / relative(name)
        observed = json.loads(file.read_text()) if file.is_file() else {}
        runtime['installed_package_manifests'][name] = {
            'name': recorded['name'], 'recorded_version': recorded['version'],
            'observed_version': observed.get('version'),
            'recorded_sha256': recorded['sha256'],
            'observed_sha256': sha(file) if file.is_file() else None,
            'matches': file.is_file() and sha(file) == recorded['sha256']
                and observed.get('version') == recorded['version'],
        }
    runtime['package_manifests_match_prior'] = all(
        row['matches'] for row in runtime['installed_package_manifests'].values())
    runtime['source06_recorded_node_metadata'] = manifest['toolchain']['node']
    runtime['source06_recorded_node_path_and_version_match'] = (
        manifest['toolchain']['node']['path'] == str(NODE)
        and manifest['toolchain']['node']['version'] == version)
    runtime['complete_installed_dependency_bytes_reread'] = False
    runtime['snapshot_contains_node_modules'] = False
    host = host_metadata(discovery)
    integrity = {'journal_packet': packet_integrity(JOURNAL),
                 'checkpoint05_packet': packet_integrity(PRIOR)}
    copied_integrity = all(row['readback_matches'] for row in integrity.values())
    journal_match = journal_compare['matching_files'] == 58
    discovery_match = discovery_compare['matching_files'] == 42
    runtime_match = runtime['node_matches_prior'] and runtime['compiler_matches_prior']
    schemas_hash = hashlib.sha256(canonical(discovery['enabled_read_schemas'])).hexdigest()
    report = {
        'kind': 'retained_source06_scoped_mcp_evidence_association',
        'status': 'scoped_input_association_pass' if journal_match and discovery_match
            and copied_integrity and runtime_match else 'differences_retained',
        'checked_at_utc': datetime.now(timezone.utc).isoformat(),
        'candidate_root': str(candidate), 'candidate_manifest_sha256': args.manifest_sha256,
        'candidate_classification': manifest['capture_classification'],
        'candidate_capture_interval': manifest['capture_interval'],
        'candidate_current_tree_accepted': manifest['source_current_tree_accepted'],
        'candidate_approvals': manifest['approvals'],
        'original_packets_integrity': integrity,
        'journal_input_comparison': journal_compare,
        'discovery_input_comparison': discovery_compare,
        'runtime_metadata': runtime, 'host_metadata': host,
        'association': {
            '139_test_scope_source_inputs_associated': copied_integrity and journal_match
                and runtime_match and runtime['package_manifests_match_prior'],
            'typescript_scope_source_inputs_associated': copied_integrity and journal_match
                and runtime_match and runtime['package_manifests_match_prior'],
            '16_registered_exact5_read_discovery_scope_source_inputs_associated':
                copied_integrity and discovery_match and runtime['node_matches_prior']
                and host.get('exact_five_read_allowlist', False)
                and host.get('fixed_local_bridge_invocation', False)
                and host.get('configured_node_version_matches_prior_discovery', False)
                and schemas_hash == discovery['read_schema_sha256'],
            'tests_rerun': False, 'typescript_rerun': False, 'discovery_rerun': False,
            'historical_139_tests': journal['combined_bridge_checks'],
            'historical_test_file_count': journal['combined_bridge_test_file_count'],
            'historical_typescript_check': journal['combined_typescript_check'],
            'historical_registered_tools': discovery['registered_tool_count'],
            'historical_protocol': discovery['protocol_version'],
            'historical_schema_sha256': discovery['read_schema_sha256'],
            'historical_discovery_checked_at_utc': discovery['checked_at_utc'],
        },
        'limitations': [
            'Association preserves historical scoped checks; no new run or hosted acceptance.',
            'Candidate lacks installed modules. Runtime compiler/package metadata is local, not a fresh frozen installation.',
            'Complete dependency file bytes are not re-attested by this association.',
            'Later SQL/migration behavior outside the listed58 inputs is not covered by the139 mock/stdio/unit scope.',
            'Host runtime reload, current-user auth, backend deployment and live RPCs remain unverified.',
            'Configured host and regression Node binaries differ in path/hash and both report v24.19.0. Prior discovery did not record its configured binary hash; no exact historical host-binary equality or new binary drift is attested.',
        ],
        'backend_reads': 0, 'mcp_processes_started': 0, 'mcp_tool_calls': 0,
        'keychain_or_auth_calls': 0, 'installation_mutations': 0,
        'credential_values_reported_or_forwarded': False,
        'config_or_host_allowlist_changed': False, 'production_accepted': False,
        'trusted_or_reviewed_production_freeze_claimed': False,
    }
    (OUTPUT / 'association.json').write_bytes(canonical(report))
    print(json.dumps({'candidate_manifest_sha256': args.manifest_sha256,
                      'journal_matching_files': journal_compare['matching_files'],
                      'discovery_matching_files': discovery_compare['matching_files'],
                      'journal_different_paths': journal_compare['different_or_missing_paths'],
                      'discovery_different_paths': discovery_compare['different_or_missing_paths'],
                      'node_matches': runtime['node_matches_prior'],
                      'compiler_matches': runtime['compiler_matches_prior'],
                      'exact_five_reads': host.get('exact_five_read_allowlist', False),
                      'association': report['association']}, sort_keys=True))


if __name__ == '__main__':
    main()
