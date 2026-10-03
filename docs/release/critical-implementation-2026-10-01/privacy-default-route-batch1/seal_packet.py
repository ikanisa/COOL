#!/usr/bin/env python3
"""Seal only this new local regression packet, preserving all earlier attempts."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

PACKET = Path(__file__).resolve().parent
ROOT = PACKET.parents[3]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, value):
    (PACKET / name).write_text(json.dumps(value, indent=2) + '\n')


attempt_names = [f'attempt{i}' for i in range(1, 7)] + [
    'owner-switch-diagnostic-attempt1',
    'analyzer-attempt1', 'analyzer-attempt2', 'analyzer-attempt3',
    'consumers-attempt1', 'stale-home-attempt1', 'authority-attempt1',
    'affected-security-attempt1', 'analyzer-attempt4', 'authority-attempt2',
]
attempts = {}
for name in attempt_names:
    location = PACKET / name
    receipt = json.loads((location / 'receipt.json').read_text())
    before = json.loads((location / 'sources-before.json').read_text())
    after = json.loads((location / 'sources-after.json').read_text())
    assert before == after and receipt['source_before_after_equal'] is True
    assert not receipt['changed_inputs']
    log = location / ('actual-test.log' if name.startswith('attempt') or name.startswith('owner-') else 'actual.log')
    expected_log = receipt.get('actual_test_log_sha256', receipt.get('actual_log_sha256'))
    assert sha(log) == expected_log
    assert receipt.get('source_count', receipt.get('input_count')) == len(before)
    if (location / 'test-source.dart').exists():
        assert sha(location / 'test-source.dart') == receipt['test_source_sha256']
    attempts[name] = {
        'receipt': str((location / 'receipt.json').relative_to(PACKET)),
        'receipt_sha256': sha(location / 'receipt.json'),
        'log': str(log.relative_to(PACKET)),
        'log_sha256': expected_log,
        'exit_code': receipt['exit_code'],
        'bound_input_count': len(before),
        'inputs_unchanged': True,
    }

assert attempts['attempt6']['exit_code'] == 0
for name in ['affected-security-attempt1', 'analyzer-attempt4', 'authority-attempt2', 'stale-home-attempt1']:
    assert attempts[name]['exit_code'] == 0

original_test_sha = 'e769c56144e728c681afecebe90971df4e8c8d52a2f6fc12b12388909f056b6c'
for number in range(1, 7):
    assert sha(PACKET / f'attempt{number}/test-source.dart') == original_test_sha
assert sha(PACKET / 'original-maintained-test-before-diagnostic.dart') == original_test_sha
current_test = ROOT / 'test/features/privacy/privacy_default_route_integration_test.dart'
assert sha(current_test) == '9f4575aeb0bdde8c29d415a49423ef7ec177dd8ef23eb6a5ceed55e408fff2f2'
assert current_test.read_bytes() == (PACKET / 'maintained-test-after-lint-correction.dart').read_bytes()

final_inputs = json.loads((PACKET / 'authority-attempt2/sources-after.json').read_text())
for name in ['affected-security-attempt1', 'analyzer-attempt4']:
    assert json.loads((PACKET / name / 'sources-before.json').read_text()) == final_inputs
errors = []
for path, expected in final_inputs.items():
    try:
        if sha(Path(path)) != expected:
            errors.append({'path': path, 'error': 'current SHA differs'})
    except OSError as error:
        errors.append({'path': path, 'error': str(error)})
assert not errors, errors

production_paths = [
    'lib/app/router.dart',
    'lib/shared/repositories/collect_repository.dart',
    'lib/shared/widgets/screen_scaffold.dart',
    'lib/features/settings/security_hub_header.dart',
]
production = {}
for relative in production_paths:
    source = ROOT / relative
    saved = PACKET / 'final-production-source' / relative
    assert source.read_bytes() == saved.read_bytes()
    assert final_inputs[str(source)] == sha(saved)
    production[relative] = sha(source)
assert 'PRIVACY_ROUTE_DIAG' not in (ROOT / 'lib/app/router.dart').read_text()

old_index = json.loads((PACKET / 'old-attempt-integrity.json').read_text())
for row in old_index['files']:
    path = PACKET / row['path']
    assert path.stat().st_size == row['size'] and sha(path) == row['sha256']

write('final-source-readback.json', {
    'recorded_at': datetime.now(timezone.utc).isoformat(),
    'current_inputs_read': len(final_inputs),
    'read_errors': errors,
    'final_sources_equal_affected_tests_analyzer_authority_inputs': True,
    'production_edits_owner': 'root',
    'production_sources': production,
    'maintained_test_sha256': sha(current_test),
    'original_behavior_test_sha256': original_test_sha,
    'all_six_behavior_attempt_tests_byte_equal': True,
    'test_only_lint_delta': 'test-only-lint-correction.diff',
    'assertions_relaxed': False,
    'diagnostic_markers_in_final_production': False,
    'canonical_registry_sha256': sha(ROOT / 'content/product/collect_capabilities.json'),
    'current_public_content_contract_sha256': sha(ROOT / 'docs/release/public-website-current-content-contract.json'),
    'scope': 'Local synthetic consumer integration; not the broad release candidate.',
})

final_text = '''# Default privacy route integration — scoped local acceptance

The actual default repository and guarded router now retain a previously
profile-verified owner's deletion-request form while the same SDK owner renews
the Auth session and native/cache/member rereads are pending. Verified code and
selected reason survive the renewal; explicit confirmation produces the own
pending-review intake receipt. Logout, owner replacement and denied refreshed
member access remove the old form and prevent its submission. A deliberate
fresh entry for the new owner starts an unverified form without inherited reasons.

The original source genuinely failed: holding native synchronization after OTP
renewal sent the form to Auth and disposed it, then resumed to Home. Root reviewed
and corrected production router/repository behavior. Intermediate real failures
also exposed build-phase notification churn and stale encoded privacy requests
reopening for a replacement owner. The focused requested/settled URI diagnostic
preserves the causal sequence. All six behavior attempts use exactly the same
original assertion source; temporary diagnostic code is retained separately and
absent from final production. The final test differs only by braces, an explicit
diagnostic-print import and its lint-safe print call.

| Actual execution | Result | Bound inputs |
| --- | --- | --- |
| Old source, attempt 1 | 3 pass / 1 fail | 587, unchanged |
| Reviewed corrections, attempts 2–5 | Preserved failures; not acceptance | 587 each, unchanged |
| Focused owner-switch diagnostic | 1 intentional observed failure | 587, unchanged |
| Final causal correction, attempt 6 | 4 / 4 pass | 587, unchanged |
| Maintained ten-file consumers | 134 pass / 2 Security-heading failures | 1,344, unchanged |
| Exact real-cache Home stale-pill consumer | 1 / 1 pass | 1,344, unchanged |
| Post-heading affected chrome/header/default-route replay | 37 / 37 pass | 1,345, unchanged |
| Final focused analyzer | Exit 0, no issues | 1,345, unchanged |
| Actual post-heading design-authority hygiene | Exit 0, pass | 1,345, unchanged |

The two broader failures were the existing custom Security header missing heading
level 1. Root added only `headingLevel: 1` under its existing header semantics,
with no layout change. The affected replay includes all six maintained header
tests and the four default-route cases. The prior 134 passes remain evidence
of their executed source; this packet does not claim a fresh 136-case full run.
The pre-heading real-cache pass is retained with that exact source distinction.

The new test uses the actual default repository/provider, guarded app router,
autoDispose controller, locked Auth/PostgREST SDK and a genuine loopback WebSocket.
Native method replies, HTTP responses, environment keys, identities and receipt
records are synthetic. Financial repository, guard, subject authority and
controller are not replaced, manually set or artificially retained. Existing
assertions and framework errors were not filtered or suppressed.

Production changes belong to root. This subagent owns only the new test and
this evidence packet. See `post-header-source-delta.json` for the sole final
header amendment and the explicitly bound verifier/test-input extension;
`final-runtime-source-delta.json` covers the reviewed router/repository/scaffold
correction. `final-source-readback.json` re-reads every final bound input.

Acceptance is limited to these local default privacy-route consumers. Native
bridge/encryption/signing, hosted Auth/RLS, legal authority and retention,
actual erasure lifecycle, provider/device/store, rights, visual comparators and
full production/release acceptance remain open. Design-authority hygiene does
not establish visual fidelity. Prior public-media-batch3 remains a dated proof;
these production and registry-binding changes require a fresh final public
media/source/browser proof. No deployment or external service action occurred.

Original compiler typo, lint diagnostics, runtime failures, source copies,
complete logs and before/after maps remain in this packet. Byte reconstruction
used only for two earlier verifier/test snapshots is explicitly SHA-verified
and is not represented as a new execution.
'''
(PACKET / 'FINAL.md').write_text(final_text)
(PACKET / 'README.md').write_text(final_text)

excluded = {'evidence-files.json', 'batch.json', 'final-readback.json'}
rows = []
for file in sorted(PACKET.rglob('*')):
    if file.is_file() and file.relative_to(PACKET).as_posix() not in excluded:
        assert not file.is_symlink()
        rows.append({'path': file.relative_to(PACKET).as_posix(), 'size': file.stat().st_size, 'sha256': sha(file)})
write('evidence-files.json', {'files': rows, 'count': len(rows), 'excludes_self_and_seal_readback': sorted(excluded)})
write('batch.json', {
    'schema': 'collect.local-consumer-evidence.v1',
    'batch': 'privacy-default-route-batch1',
    'sealed_at': datetime.now(timezone.utc).isoformat(),
    'status': 'SCOPED LOCAL DEFAULT PRIVACY ROUTE INTEGRATION PASS',
    'original_failure_preserved': True,
    'behavior_acceptance': {'cases': 4, 'final_original_source_attempt': 'attempt6', 'post_header_replay': 'affected-security-attempt1'},
    'broader_consumers': {'actual_cases': 136, 'passes': 134, 'failures': 2, 'receipt': 'consumers-attempt1/receipt.json', 'fresh_final_full_136_claimed': False},
    'affected_final_replay': {'actual_cases': 37, 'passes': 37, 'failures': 0},
    'real_cache_home': {'passes': 1, 'source_scope': 'pre-header source; only final production amendment is heading semantics'},
    'final_analyzer_exit': 0,
    'post_header_authority_exit': 0,
    'all_executed_input_maps_unchanged': True,
    'attempts': attempts,
    'final_production_source_sha256': production,
    'test_source_sha256': sha(current_test),
    'current_source_readback': {'path': 'final-source-readback.json', 'sha256': sha(PACKET / 'final-source-readback.json')},
    'evidence_index': {'path': 'evidence-files.json', 'sha256': sha(PACKET / 'evidence-files.json'), 'file_count': len(rows)},
    'production_approval': False,
    'native_hosted_visual_legal_full_lifecycle_acceptance': False,
    'design_authority_hygiene_is_visual_acceptance': False,
    'prior_public_media_batch3_is_current_source_acceptance': False,
    'no_external_actions': True,
})
print(json.dumps({'batch_sha256': sha(PACKET / 'batch.json'), 'files': len(rows), 'final_source_inputs_read': len(final_inputs)}))
