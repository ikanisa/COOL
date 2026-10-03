#!/usr/bin/env python3
"""Package completed evidence and its limits; never execute another test/build."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
BASE = ROOT / 'docs/release/native-gateway-observation-2026-10-01/root197-correction/actual-native4'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


artifact = json.loads((BASE / 'production-artifact.json').read_text())
apk = Path(artifact['path'])
assert sha(apk) == artifact['sha256']
with zipfile.ZipFile(apk) as archive:
    assert archive.testzip() is None
execution = json.loads((BASE / 'execution.json').read_text())
commands = {row['name']: row for row in execution['commands']}
for name in ['corrected-production-native-lint', 'production-unsigned-assemble',
             'production-jvm', 'production-manifest']:
    assert commands[name]['exit_code'] == 0
assert commands['production-signature']['exit_code'] == 1
assert 'DOES NOT VERIFY' in (BASE / 'production-signature.stderr').read_text()
badging = (BASE / 'production-manifest.stdout').read_text()
assert "name='app.cool.mobile'" in badging
for permission in ['SEND_SMS', 'READ_PHONE_STATE', 'READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']:
    assert 'android.permission.' + permission not in badging

before = json.loads((BASE / 'source-before.json').read_text())
drift = {}
for name, captured in before.items():
    path = ROOT / name
    current = sha(path) if path.is_file() else None
    if current != captured:
        drift[name] = {'captured_sha256': captured, 'current_sha256': current}


def production_guard(name):
    if re.match(r'third_party/[^/]+/(test|tests|example|examples|benchmark|benchmarks|doc|docs)/', name):
        return False
    if name.startswith(('android/app/src/internal_gateway/', 'android/app/src/testInternal_gateway/')):
        return False
    return name.startswith(('lib/', 'assets/', 'licenses/', 'android/', 'third_party/')) or name in {
        'pubspec.yaml', 'pubspec.lock', '.metadata', '.fvmrc', '.dvmrc'}


guard = {name: value for name, value in before.items() if production_guard(name)}
runtime_drift = {name: value for name, value in drift.items() if production_guard(name)}
save('production-guarded-inputs.json', guard)
save('production-artifact-handover.json', {
    'status': 'pass_at_captured_source_current_binding_incomplete',
    'artifact': artifact, 'completed_commands': list(commands.values()),
    'recorded_source_input_count': len(before), 'production_guarded_input_count': len(guard),
    'production_guarded_input_manifest_sha256': sha(OUT / 'production-guarded-inputs.json'),
    'production_input_drift': runtime_drift,
    'all_captured_input_drift': drift,
    'parent_runner_stopped_during_duplicate_gateway_assemble': True,
    'native_lint_errors': 0, 'native_lint_warning_count': artifact['lint_warnings'],
    'production_jvm_pass_count': artifact['jvm_test_count'],
    'unsigned_rejection_and_package_permissions_verified': True,
    'current_complete_source_or_dependency_acceptance_claimed': False,
    'signed_store_or_physical_device_acceptance_claimed': False,
    'scope': 'Existing production artifact and recorded lint/JVM/manifest commands. '
             'Authored source comparison detects later changes. No rebuild, ignored credential '
             'read, dependency graph generation or test invocation is performed.'})
save('initial-current-production-bind-failure.json', {
    'status': 'failed_current_source_binding', 'runtime_drift': runtime_drift,
    'resolution': 'Keep the captured build; report current acceptance unverified; do not repeat the build.'})

prior = ROOT / 'docs/release/local-progress-2026-09-30/current177-root-checkpoint3/proof-index.json'
save('prior-proof-index.json', json.loads(prior.read_text()))
paths = [
    'docs/release/gateway-reduced-motion-2026-10-01/root216-current-regressions/validation.json',
    'docs/release/gateway-reduced-motion-2026-10-01/root224-current-format/validation.json',
    'docs/release/admin-full-coverage-2026-09-30/current-browser-adapters-root227/validation.json',
    'docs/release/rapid-completion-2026-10-01/production-artifact-handover.json',
    'docs/release/rapid-completion-2026-10-01/stopped-optional-runners.json']
merge = OUT / 'gateway-manifest-verification.json'
if merge.is_file():
    paths.append(str(merge.relative_to(ROOT)))
bindings = []
for name in paths:
    path = ROOT / name
    value = json.loads(path.read_text())
    bindings.append({'path': name, 'sha256': sha(path), 'observed_status': value.get('status'),
                     'scope': 'This packet retains its own source, execution and acceptance limits.'})

local_path = ROOT / 'docs/release/local-implementation-register-2026-09-30.json'
prod_path = ROOT / 'docs/release/production-remaining-tasks-2026-09-30.validation.json'
local = json.loads(local_path.read_text())
prod = json.loads(prod_path.read_text())
closed = [row['id'] for row in local['items'] if row['status'] == 'complete']
open_ids = [row['id'] for row in local['items'] if row['status'] != 'complete']
assert len(closed) == 7 and len(open_ids) == 17 and prod['closed_ids'] == ['G06']
save('handover-evidence-index.json', {
    'status': 'packaged_scoped_evidence', 'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'bindings': bindings, 'prior_proof_index_sha256': sha(OUT / 'prior-proof-index.json'),
    'original_local_register_sha256': sha(local_path), 'production_validation_sha256': sha(prod_path),
    'original_local_closed_ids': closed, 'original_local_open_ids': open_ids,
    'original_production_open_count': 101, 'release_decision': 'NO-GO',
    'full_original_goal_completed': False,
    'nonessential_active_work_cancelled': True,
    'goal_status_at_replan': 'usageLimited',
    'remaining_work': 'Only the essential gates in REPLAN.md remain active; original criteria are preserved.'})
print(json.dumps({'handover': 'packaged', 'production_build_source_drift_count': len(runtime_drift),
                  'production_jvm_pass': artifact['jvm_test_count'], 'local_closed': len(closed),
                  'local_open': len(open_ids), 'release': 'NO-GO'}))
