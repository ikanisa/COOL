#!/usr/bin/env python3
"""Package one executed lifecycle proof; no test, build or browser execution."""
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT = Path(__file__).resolve().parent
META = json.loads((OUT / 'browser-inputs.json').read_text())
BUILD = Path(META['build_root'])
FINAL = Path(META['source'])
SDK = Path(META['sdk_root'])
LIFECYCLE = BUILD / '.cache/lifecycle-integration-current3'
REPORT_PATH = LIFECYCLE / 'report.json'
REPORT = json.loads(REPORT_PATH.read_text())

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def mismatch(base, values):
    return sorted(n for n, d in values.items() if not (base / n).is_file() or sha(base / n) != d)

def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

candidate_drift = mismatch(FINAL, META['inputs_sha256'])
build_drift = mismatch(BUILD, META['inputs_sha256'])
executed_drift = mismatch(BUILD, REPORT['sources_before'])
supplemental_drift = mismatch(BUILD, META['supplemental_inputs'])
harness_drift = mismatch(Path(META['harness_root']), META['executing_harness_inputs'])
sdk_drift = mismatch(SDK, json.loads((OUT / 'browser-sdk-prepared.json').read_text()))
private_sdk_drift = mismatch(Path(META['corrected_sdk_root']), json.loads((OUT / 'browser-private-sdk-inputs.json').read_text()))
drain_logs = {p.name: json.loads(p.read_text()) for p in sorted((OUT / 'font-subset-drain-logs').glob('*.json'))}
drain_valid = bool(drain_logs) and all(row['stdout_fully_drained'] and not row['drain_errors']
    and row['engine_exit_code'] == 0 for row in drain_logs.values())
tools = json.loads((OUT / 'browser-tool-inputs.json').read_text())
browser_tool_drift = [n for n, d in tools['inputs_sha256'].items() if not Path(n).is_file() or sha(Path(n)) != d]
wrapper_runtime = json.loads((OUT / 'wrapper-runtime-inputs.json').read_text())
wrapper_runtime_drift = [n for n, row in wrapper_runtime['executables'].items() if sha(Path(row['path'])) != row['sha256']]
fresh_build = json.loads(Path(META['retained_build_report']).read_text())
fresh_build_receipts_valid = all(next(c['exit_code'] for c in fresh_build['commands'] if c['name'] == name) == 0
                               for name in ['admin-build', 'public-build'])
retained_artifacts_exact = fresh_build['artifacts'] == REPORT['artifacts']
package_drift = {name: mismatch(Path(row['root']), row['files'])
                 for name, row in json.loads((OUT / 'browser-packages-prepared.json').read_text()).items()}
package_drift = {n: d for n, d in package_drift.items() if d}
config_drift = sha(BUILD / '.dart_tool/package_config.json') != META['package_config_sha256']
graph_drift = sha(BUILD / '.dart_tool/package_graph.json') != META['package_graph_sha256']
artifact_drift = {label: mismatch(LIFECYCLE / (label + '-build'), values)
                  for label, values in REPORT['artifacts'].items()}
command_log_drift = [command['name'] + '.' + stream
                     for command in REPORT['commands'] for stream in ['stdout', 'stderr']
                     if sha(Path(command['reused_from']).parent / (command['name'] + '.' + stream)
                            if command.get('reused_from') else LIFECYCLE / (command['name'] + '.' + stream))
                     != command[stream + '_sha256']]
route_counts = {authority: sum(row['authority'] == authority for row in REPORT['route_states'])
                for authority in ['signed-out', 'authenticated-email-owner']}
manifest_current_sha = sha(FINAL / '.collect-release-candidate.json')
peer = json.loads(Path(META['peer_657_receipt']).read_text())
peer_receipt_unchanged = sha(Path(META['peer_657_receipt'])) == META['peer_657_receipt_sha256']
source_names = set()
for tree in ['lib', 'web', 'assets', 'third_party', 'content/legal']:
    for p in (ROOT / tree).rglob('*'):
        if p.is_file():
            n = p.relative_to(ROOT).as_posix()
            if not re.match(r'^third_party/[^/]+/(?:test|tests|example|examples|benchmark|benchmarks|doc|docs)/', n):
                source_names.add(n)
expected_names = {n for n in REPORT['sources_before'] if n.startswith(('lib/', 'web/', 'assets/', 'third_party/', 'content/legal/'))}
live_readback = {
    'changed_or_missing_executed_inputs': mismatch(ROOT, REPORT['sources_before']),
    'added_executed_directory_files': sorted(source_names - expected_names),
    'removed_executed_directory_files': sorted(expected_names - source_names),
    'scope': 'Separate readback of live source; acceptance is bound to immutable final current2, not untested subsequent live edits.'}
save('live-executed-source-readback.json', live_readback)
valid = (
    REPORT['status'] == 'pass' and REPORT['source_inputs_stable'] and not REPORT['errors']
    and all(check['status'] == 'pass' for check in REPORT['checks'])
    and all(REPORT['coverage'].values())
    and route_counts == {'signed-out': 28, 'authenticated-email-owner': 28}
    and all(command['exit_code'] == 0 for command in REPORT['commands'])
    and not any([candidate_drift, build_drift, executed_drift, supplemental_drift, harness_drift,
                 sdk_drift, private_sdk_drift, package_drift, config_drift, graph_drift, command_log_drift,
                 browser_tool_drift, wrapper_runtime_drift])
    and not any(artifact_drift.values())
    and manifest_current_sha == META['manifest_sha256']
    and REPORT['executing_harness_sha256'] == META['executing_harness_inputs']['scripts/qa/current_browser_lifecycle.mjs']
    and REPORT['executing_fixture_sha256'] == META['executing_harness_inputs']['scripts/qa/local_browser_api_fixture.mjs']
    and peer_receipt_unchanged and peer['accepted'] and not peer['changed_inputs']
    and 'retained_admin_bundle' in REPORT and 'retained_public_bundle' in REPORT
    and fresh_build_receipts_valid and retained_artifacts_exact and drain_valid)

# Portable executed report, logs and captures; compiled bundles get exact maps.
evidence = OUT / 'browser-evidence'
evidence.mkdir(exist_ok=False)
for p in sorted(LIFECYCLE.iterdir()):
    if p.is_file() and p.suffix in {'.json', '.stdout', '.stderr', '.png', '.html', '.rb'}:
        shutil.copy2(p, evidence / p.name)
for command in REPORT['commands']:
    origin = Path(command['reused_from']).parent if command.get('reused_from') else LIFECYCLE
    for stream in ['stdout', 'stderr']:
        name = command['name'] + '.' + stream
        shutil.copy2(origin / name, evidence / name)
        assert sha(evidence / name) == command[stream + '_sha256'], name
artifact_paths = {}
artifact_copy_drift = {}
for label, values in REPORT['artifacts'].items():
    destination = OUT / 'artifacts' / (label + '-build')
    shutil.copytree(LIFECYCLE / (label + '-build'), destination)
    artifact_paths[label] = str(destination)
    artifact_copy_drift[label] = mismatch(destination, values)
valid = valid and not any(artifact_copy_drift.values())
save('executed-consumers.json', {'sources_before': REPORT['sources_before'], 'sources_after': REPORT['sources_after'],
    'count': len(REPORT['sources_before']), 'source_inputs_stable': REPORT['source_inputs_stable'],
    'scope': REPORT['source_scope'], 'harness': META['executing_harness_inputs']})
save('artifact-manifest.json', {'artifacts': REPORT['artifacts'], 'portable_artifact_paths': artifact_paths,
    'cache_artifact_paths': {label: str(LIFECYCLE / (label + '-build')) for label in REPORT['artifacts']},
    'copy_drift': artifact_copy_drift})
result = {
    'status': 'pass' if valid else 'fail',
    'scope': 'One successful final production Admin build and separate Public build after preserved engine-I/O failure; hash-identical bundles reused for a private focus-corrected browser/PWA continuation. Actual current email/tab-session lifecycle against final immutable current2, synthetic loopback API. Existing 657 affected VM cases bound and reused, not rerun.',
    'candidate': str(FINAL), 'candidate_manifest_sha256': META['manifest_sha256'],
    'candidate_source_manifest_sha256': META['source_manifest_sha256'],
    'candidate_file_count': len(META['inputs_sha256']),
    'report': str(evidence / 'report.json'), 'report_sha256': sha(REPORT_PATH),
    'inputs_receipt': str(OUT / 'browser-inputs.json'), 'inputs_receipt_sha256': sha(OUT / 'browser-inputs.json'),
    'executed_consumers': str(OUT / 'executed-consumers.json'), 'executed_consumer_count': len(REPORT['sources_before']),
    'executed_consumers_sha256': sha(OUT / 'executed-consumers.json'),
    'package_map': str(OUT / 'browser-packages-prepared.json'), 'package_map_sha256': sha(OUT / 'browser-packages-prepared.json'),
    'sdk_map': str(OUT / 'browser-sdk-prepared.json'), 'sdk_map_sha256': sha(OUT / 'browser-sdk-prepared.json'),
    'artifact_manifest': str(OUT / 'artifact-manifest.json'), 'artifact_manifest_sha256': sha(OUT / 'artifact-manifest.json'),
    'artifact_paths': artifact_paths, 'artifact_counts': {label: len(values) for label, values in REPORT['artifacts'].items()},
    'fresh_build_report': META['retained_build_report'], 'fresh_build_report_sha256': sha(Path(META['retained_build_report'])),
    'fresh_build_commands_passed': fresh_build_receipts_valid, 'retained_artifacts_exact': retained_artifacts_exact,
    'private_harness_admission': str(OUT / 'private-harness-admission.json'),
    'private_harness_admission_sha256': sha(OUT / 'private-harness-admission.json'),
    'browser_tool_map': str(OUT / 'browser-tool-inputs.json'), 'browser_tool_map_sha256': sha(OUT / 'browser-tool-inputs.json'),
    'browser_tool_drift': browser_tool_drift, 'wrapper_runtime_drift': wrapper_runtime_drift,
    'commands': REPORT['commands'], 'browser_check_count': len(REPORT['checks']), 'named_browser_checks': REPORT['checks'],
    'route_authority_counts': route_counts, 'route_states': REPORT['route_states'], 'coverage': REPORT['coverage'],
    'production_admin_build_executed_once': True, 'retained_admin_bundle_used': 'retained_admin_bundle' in REPORT,
    'attempted_builds': 2, 'successful_final_admin_builds': 1,
    'original_failed_build_receipt': str(OUT / 'original-command-terminal.json'),
    'original_failed_build_receipt_sha256': sha(OUT / 'original-command-terminal.json'),
    'causal_recovery': 'Original font-subset stdout-pipe deadlock; private identical engine binary now has full concurrent stdout drain with bounded proof prefix and total digest. Application/compiler options unchanged.',
    'private_sdk_admission': str(OUT / 'private-sdk-admission.json'),
    'private_sdk_admission_sha256': sha(OUT / 'private-sdk-admission.json'),
    'private_sdk_map': str(OUT / 'browser-private-sdk-inputs.json'),
    'private_sdk_map_sha256': sha(OUT / 'browser-private-sdk-inputs.json'),
    'private_sdk_drift': private_sdk_drift, 'engine_stdout_drain_accepted': drain_valid,
    'engine_stdout_drain_receipt_count': len(drain_logs),
    'source_inputs_stable': REPORT['source_inputs_stable'], 'candidate_drift': candidate_drift, 'build_drift': build_drift,
    'executed_drift': executed_drift, 'supplemental_drift': supplemental_drift, 'harness_drift': harness_drift,
    'sdk_drift': sdk_drift, 'package_drift': package_drift, 'package_config_drift': config_drift, 'package_graph_drift': graph_drift,
    'artifact_drift': artifact_drift, 'artifact_copy_drift': artifact_copy_drift, 'command_log_drift': command_log_drift,
    'peer_657_receipt': META['peer_657_receipt'], 'peer_657_receipt_sha256': META['peer_657_receipt_sha256'],
    'peer_657_reused_cases': peer['completed_visible_cases'], 'peer_657_receipt_unchanged': peer_receipt_unchanged,
    'peer_657_candidate_source_bound_count': len(META['peer_657_source_bindings']),
    'live_source_readback': str(OUT / 'live-executed-source-readback.json'),
    'blocked_outbound_requests': REPORT['blocked_outbound_requests'],
    'database_calls': REPORT['database_calls'], 'hosted_calls': REPORT['hosted_calls'], 'provider_calls': REPORT['provider_calls'],
    'errors': REPORT['errors'], 'design_fidelity_certified': False,
    'limits': 'All 28 routes use signed-out or synthetic approved email-owner empty, unavailable or permission-denied records. This run does not certify positive joined-history/inbox-v2 browser scenarios; their existing affected widget/SDK and SQL receipts remain separate. No real email delivery, hosted/provider actions, physical devices, new native build, or Revolut visual fidelity claim.'}
save('browser-acceptance.json', result)
print(json.dumps({k: result[k] for k in ['status', 'browser_check_count', 'route_authority_counts', 'executed_consumer_count', 'artifact_counts', 'sdk_drift', 'package_drift', 'errors']}), flush=True)
raise SystemExit(0 if valid else 1)
