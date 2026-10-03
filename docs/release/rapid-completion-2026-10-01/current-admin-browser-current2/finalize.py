from pathlib import Path
import hashlib
import json
import re

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT = ROOT / 'docs/release/rapid-completion-2026-10-01/current-admin-browser-current2'
META = json.loads((OUT / 'copied-inputs.json').read_text())
CANDIDATE = Path(META['build_root'])
LIFECYCLE = CANDIDATE / '.cache/lifecycle-production-current2'
REPORT = json.loads((LIFECYCLE / 'report.json').read_text())
ACCEPTANCE = Path(META['affected_acceptance_receipt'])
INTEGRATION = json.loads(ACCEPTANCE.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mismatch(base, values):
    return [name for name, digest in values.items()
            if not (base / name).is_file() or sha(base / name) != digest]


def compiled(name):
    return name.startswith(('lib/', 'web/', 'assets/', 'third_party/')) or name in {
        'pubspec.yaml', 'pubspec.lock', '.fvmrc'
    }


compiler_inputs = {name: digest for name, digest in META['copied_inputs'].items()
                   if compiled(name)}
candidate_drift = mismatch(CANDIDATE, META['copied_inputs'])
current_compiler_drift = mismatch(ROOT, compiler_inputs)
sdk_drift = mismatch(Path(META['sdk_root']), META['sdk_before'])
supplemental_drift = mismatch(ROOT, META['supplemental_inputs'])

# Read back the executed source set, including newly arriving reachable files.
# These are the same explicit package QA exclusions used by the lifecycle.
source_names = set()
for directory in ['lib', 'web', 'assets', 'third_party', 'content/legal']:
    for path in (ROOT / directory).rglob('*'):
        if path.is_file():
            name = path.relative_to(ROOT).as_posix()
            if not re.match(r'^third_party/[^/]+/(?:test|tests|example|examples|benchmark|benchmarks|doc|docs)/', name):
                source_names.add(name)
expected_directory_names = {name for name in REPORT['sources_before']
                            if name.startswith(('lib/', 'web/', 'assets/', 'third_party/', 'content/legal/'))}
current_source_added = sorted(source_names - expected_directory_names)
current_source_removed = sorted(expected_directory_names - source_names)
current_executed_source_drift = mismatch(ROOT, REPORT['sources_before'])

artifact_drift = {}
for label, directory in [('admin', 'admin-build'), ('public', 'public-build')]:
    artifact_drift[label] = mismatch(LIFECYCLE / directory, REPORT['artifacts'][label])
command_log_drift = []
for command in REPORT['commands']:
    for stream in ['stdout', 'stderr']:
        path = LIFECYCLE / (command['name'] + '.' + stream)
        if sha(path) != command[stream + '_sha256']:
            command_log_drift.append(path.name)

route_counts = {authority: sum(row['authority'] == authority for row in REPORT['route_states'])
                for authority in ['signed-out', 'authenticated-email-owner']}
valid = (
    REPORT['status'] == 'pass'
    and REPORT['source_inputs_stable'] is True
    and not REPORT['errors']
    and all(check['status'] == 'pass' for check in REPORT['checks'])
    and all(REPORT['coverage'].values())
    and route_counts == {'signed-out': 28, 'authenticated-email-owner': 28}
    and all(command['exit_code'] == 0 for command in REPORT['commands'])
    and INTEGRATION['status'] == 'pass'
    and INTEGRATION['current_changed_inputs_match'] is True
    and INTEGRATION['sdk_unchanged'] is True
    and not INTEGRATION['export_drift']
    and all(INTEGRATION['prior_chrome_named_cases_passed'].values())
    and not any([candidate_drift, current_compiler_drift, sdk_drift,
                 supplemental_drift, current_source_added, current_source_removed,
                 current_executed_source_drift, command_log_drift])
    and not any(artifact_drift.values())
    and REPORT['executing_harness_sha256'] == META['executed_harness_sha256']
)
result = {
    'status': 'pass' if valid else 'fail',
    'report': str(LIFECYCLE / 'report.json'),
    'report_sha256': sha(LIFECYCLE / 'report.json'),
    'copied_inputs_receipt': str(OUT / 'copied-inputs.json'),
    'copied_inputs_sha256': sha(OUT / 'copied-inputs.json'),
    'integration_receipt': str(ACCEPTANCE),
    'integration_receipt_sha256': sha(ACCEPTANCE),
    'executed_integration_cases': INTEGRATION['count'],
    'unchanged_affected_vm_cases_reused': INTEGRATION['prior_remaining_cases_reused'],
    'affected_vm_cases_total': INTEGRATION['count'] + INTEGRATION['prior_remaining_cases_reused'],
    'named_checkpoint_chrome_cases_reused': INTEGRATION['prior_chrome_named_cases_passed'],
    'production_admin_build_executed_once': True,
    'retained_admin_bundle_used': 'retained_admin_bundle' in REPORT,
    'named_browser_checks': REPORT['checks'],
    'browser_check_count': len(REPORT['checks']),
    'route_authority_counts': route_counts,
    'route_states': REPORT['route_states'],
    'coverage': REPORT['coverage'],
    'sdk_critical_hashes': META['sdk_before'],
    'sdk_drift': sdk_drift,
    'candidate_input_count': len(META['copied_inputs']),
    'candidate_drift': candidate_drift,
    'current_compiler_drift': current_compiler_drift,
    'current_executed_source_drift': current_executed_source_drift,
    'current_source_added': current_source_added,
    'current_source_removed': current_source_removed,
    'supplemental_drift': supplemental_drift,
    'artifact_hashes': REPORT['artifacts'],
    'artifact_drift': artifact_drift,
    'command_log_drift': command_log_drift,
    'commands': REPORT['commands'],
    'blocked_outbound_requests': REPORT['blocked_outbound_requests'],
    'database_calls': REPORT['database_calls'],
    'hosted_calls': REPORT['hosted_calls'],
    'provider_calls': REPORT['provider_calls'],
    'design_fidelity_certified': False,
    'scope': 'Current immutable Admin production build with the principal family and guarded whitespace-only repository format. One fresh-build lifecycle command executes route, tab-session and service-worker behavior using synthetic loopback transport. Original failures remain preserved; 436 unaffected VM cases and 15 real Chrome checkpoint cases are reused by explicit unchanged source and SDK bindings.',
    'limits': 'Route records are synthetic empty, unavailable or permission-denied states. Seven external Roboto font requests were blocked by the fixture. No real email delivery, hosted/provider operations, physical device, native current-principal build or Revolut visual fidelity is certified.',
    'check_count_explanation': 'Fresh build has one pinned-runtime check. The prior 89-check retained-build continuation had two retained-input/bundle checks instead, hence this complete fresh-build lifecycle contains 88 checks.',
}
(OUT / 'browser-acceptance.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['status', 'executed_integration_cases',
      'unchanged_affected_vm_cases_reused', 'affected_vm_cases_total', 'browser_check_count',
      'route_authority_counts', 'candidate_input_count', 'sdk_drift', 'current_compiler_drift',
      'current_executed_source_drift', 'current_source_added', 'current_source_removed']}))
raise SystemExit(0 if valid else 1)
