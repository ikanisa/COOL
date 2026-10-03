import datetime
import hashlib
import json
import pathlib
import shutil
import sys

root = pathlib.Path.cwd()
cache = root / '.cache/admin-exception-history-ui-20261001'
packet = root / 'docs/release/collect-codex-goal-2026-09-30/admin-exception-history-ui-20261001'
attempt = sys.argv[1]
accepted = json.loads((cache / attempt / 'verification.json').read_text())
assert accepted['accepted'] and accepted['all_requested_suites_executed']
assert accepted['changed_inputs'] == []
assert len(accepted['case_counts']) == 19
assert '[revolut-design-authority] pass' in (cache / 'authority.log').read_text()
backend = root / 'docs/release/collect-codex-goal-2026-09-30/exception-inbox-audit-v2-20261001'
backend_manifest = backend / 'packet-manifest.json'
assert backend_manifest.is_file()
bindings = json.loads((cache / attempt / 'inputs-before.json').read_text())
for name, digest in bindings.items():
    assert hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest() == digest, name
assert not packet.exists()
packet.mkdir()
shutil.copytree(cache / attempt, packet / attempt)
for preceding in sorted(cache.glob('attempt*')):
    if preceding.is_dir() and preceding.name != attempt:
        shutil.copytree(preceding, packet / ('rejected-' + preceding.name))
shutil.copy2(cache / 'authority.log', packet / 'authority.log')
shutil.copy2(pathlib.Path(__file__), packet / 'seal.py')
rows = []
copies = 0
for name, digest in sorted(bindings.items()):
    source = pathlib.Path(name)
    row = {'path': name, 'sha256': digest, 'current_readback': True}
    try:
        relative = source.relative_to(root)
    except ValueError:
        relative = None
    if relative is not None:
        destination = packet / 'sources' / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        assert hashlib.sha256(destination.read_bytes()).hexdigest() == digest
        row['copy'] = destination.relative_to(packet).as_posix()
        copies += 1
    rows.append(row)
counts = {pathlib.Path(path).name: count for path, count in accepted['case_counts'].items()}
new_names = [
    'admin_exception_history_v2_models_test.dart',
    'admin_exception_escalation_inbox_v2_models_test.dart',
    'admin_exception_history_v2_sdk_test.dart',
    'admin_exception_history_v2_page_test.dart',
    'admin_exception_escalation_inbox_v2_test.dart',
]
new_cases = sum(counts[name] for name in new_names)
readme = f'''# Joined exception history and recipient inbox — scoped Admin evidence

The existing exception action-history route now joins immutable review, assignment/deadline and escalation transitions. Other entity routes retain their v1 readers. Separate source-derived event IDs keep equal original UUIDs distinguishable across review and workflow records. Original request, actor, source/workflow revision, assignee, historical deadline and escalation IDs are presented from strict closed v2 records. Historical coverage remains explicitly incomplete; retained transitions with unknown actors are not attributed to the current operator.

The actual SDK uses three additive v2 RPCs for exception history, current-recipient inbox pagination and opening acknowledgement. Reads use one HTTP attempt with a15-second bound. Owner/domain/audit permissions, current identity, session and repository scope are rechecked; departed or expired evidence is hidden. The inbox uses paired20-row delivery cursors, separate escalation and exception identities, and no contact/address disclosure. Opening acknowledges the immutable delivery only, and a repeated opening retains its original acknowledgement. A direct action-history link does not acknowledge opening or resolve the source.

The follow-up dialog closes and settles before pushing the existing canonical history route. Its opening session and independent audit permission still govern navigation. A departed scope cannot close a different route or reopen history. Cursor history resets when identity, session, repository or entity changes; expired rows and paging are hidden until a manual refresh.

Accepted affected integration: {accepted['visible_cases']}/{accepted['completed_visible_cases']} visible cases across all19 requested suites, successful terminal event, analysis0 and all{accepted['inputs']:,} captured source/dependency/fixture/toolchain inputs unchanged. The new five-file scope contains{new_cases} cases; the other14 files retain v1 audit, assignment/deadline and exception regressions. Per-file counts are in verification.json. Actual SQL fixture bytes and producer associations are preserved separately for the100-case precursor and37-case affected query-bound proof; those SQL counts are not added to the Flutter tally. The current branch-bounded migration is included in the captured inputs.

Shared Collect semantic colours, typography, quiet Business cards/dialogs and named controls adapt the owner-selected revolut-design authority. Narrow layout, enlarged text, keyboard and semantics cases supply automated behavior evidence. The required sole-authority hygiene check passed; it does not certify exact visual fidelity or unaided screen-reader speech. No new screenshot acceptance is supplied; an inherited optional capture remains environment-disabled.

This packet copies the actual affected Dart import/export/part closure and local fixtures. Dependency sources inside the checkout are bound evidence inputs rather than authored product changes. Rejected attempts, if present, retain their raw logs and hash-only input maps; their failed-source copies are not reconstructed.

The complete187-migration sequence, whole candidate build/regression, hosted Auth/operator authority/RLS installation, actual gateway/device/carrier behavior, reader/comparator acceptance and production release remain open. No hosted mutation, credentials, enrollment, deployment or business message occurred in this scope. The active21-item implementation goal is unchanged.
'''
(packet / 'README.md').write_text(readme)
verification = {
    'scope': accepted['scope'],
    'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'vm': accepted,
    'new_cases': new_cases,
    'source_copies': copies,
    'current_source_bindings': rows,
    'backend_association': {
        'packet': str(backend),
        'manifest_sha256': hashlib.sha256(backend_manifest.read_bytes()).hexdigest(),
        'preceding_sql_cases': 100,
        'affected_current_sql_cases': 37,
        'not_added_to_vm_cases': True,
    },
    'hygiene': {'command': ['make', 'revolut-design-authority'], 'exit_code': 0, 'log': 'authority.log', 'visual_acceptance': 'unverified'},
    'full_candidate_regression': False,
    'production_accepted': False,
    'current_migration_count': 187,
    'hosted_calls': 0,
    'live_sends': 0,
    'deployments': 0,
    'remaining_goal08': ['complete candidate composition', 'authenticated hosted lifecycle acceptance', 'full comparator and actual reader acceptance'],
}
(packet / 'verification.json').write_text(json.dumps(verification, indent=2) + '\n')
manifest = []
for file in sorted(packet.rglob('*')):
    if file.is_file():
        manifest.append({'path': file.relative_to(packet).as_posix(), 'sha256': hashlib.sha256(file.read_bytes()).hexdigest(), 'bytes': file.stat().st_size})
(packet / 'MANIFEST.json').write_text(json.dumps({'files': manifest}, indent=2) + '\n')
for row in manifest:
    assert hashlib.sha256((packet / row['path']).read_bytes()).hexdigest() == row['sha256']
print(json.dumps({'packet': str(packet), 'visible_cases': accepted['visible_cases'], 'new_cases': new_cases, 'source_copies': copies, 'bound_inputs': len(bindings), 'manifest_files': len(manifest), 'manifest_sha256': hashlib.sha256((packet / 'MANIFEST.json').read_bytes()).hexdigest(), 'readback_failures': 0}))
