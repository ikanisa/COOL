#!/usr/bin/env python3
"""Bind completed member SDK evidence to the reviewed current runtime correction.

This is a read-only source/evidence review. No SQL, SDK, browser or test runs.
"""
import datetime
import difflib
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
PACKET = OUT / 'member-realtime-attempt4-current-fatal-analysis'
DATA = ROOT / 'docs/release/data-correctness-2026-09-30/immutable-attempt22-current167-sql-bridge'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


validation = json.loads((PACKET / 'validation.json').read_text())
inputs = json.loads((PACKET / 'inputs.json').read_text())
require(validation['status'] == 'pass' and validation['export_unchanged']
        and validation['sdk_unchanged'], 'Accepted immutable SDK packet required')
require(validation['inputs_sha256'] == digest(PACKET / 'inputs.json'), 'SDK manifest drift')
require(validation['machine']['passed'] == 18
        and not any(validation['machine'][k] for k in ('failed', 'errors', 'skipped')),
        'All declared eighteen member cases must pass')
require(len(validation['commands']) == 2, 'Both actual runner receipts required')
for command in validation['commands']:
    require(command['exit_code'] == 0 and not command['timed_out']
            and command['parent_exit_confirmed'], 'Nonterminal runner')
    for stream in ('stdout', 'stderr'):
        require(digest(PACKET / f"{command['name']}.{stream}") == command[f'{stream}_sha256'],
                'Runner log drift')
analysis = next(c for c in validation['commands'] if c['name'] == 'analysis')
require('--fatal-infos' in analysis['argv']
        and 'No issues found!' in (PACKET / 'analysis.stdout').read_text(), 'Fatal clean analysis required')

files = ['lib/shared/repositories/collect_repository.dart',
         'lib/core/supabase/realtime_invalidation.dart',
         'test/shared/member_realtime_sdk_session_test.dart',
         'test/shared/realtime_invalidation_recovery_test.dart']
bindings = {}
for name in files:
    exported = PACKET / 'source-export' / name
    require(digest(exported) == inputs['source'][name], 'Copied source drift: ' + name)
    require(digest(ROOT / name) == digest(exported), 'Current source drift: ' + name)
    bindings[name] = digest(exported)

repository = files[0]
previous = (DATA / 'source-export' / repository).read_text()
current = (ROOT / repository).read_text()
replacements = [
    ('    _realtimeOwnerId = userId;\n    _realtimeSync = RealtimeInvalidationSubscription(',
     '    _realtimeOwnerId = userId;\n    final session = _captureSession();\n    _realtimeSync = RealtimeInvalidationSubscription('),
    ("      topic: 'collect:mobile:invalidation',",
     "      // The locked SDK matches channel messages by topic. A departed join's\n"
     "      // frame must not be routed into a replacement Auth scope's callback.\n"
     "      topic: 'collect:mobile:invalidation:${const Uuid().v4()}',"),
    ('        if (mounted && supabase.auth.currentUser?.id == userId) {',
     '        if (_isCurrentSession(session) &&\n            supabase.auth.currentUser?.id == userId) {'),
]
expected = previous
for old, new in replacements:
    require(expected.count(old) == 1, 'Reviewed replacement is not unique')
    expected = expected.replace(old, new, 1)
require(expected == current, 'Changes beyond the reviewed Realtime scope')
require(digest(DATA / 'source-export' / files[1]) == bindings[files[1]],
        'Shared coordinator changed since Data22')
diff_path = OUT / 'member-realtime-reviewed-data22.diff'
diff_path.write_text(''.join(difflib.unified_diff(previous.splitlines(True), current.splitlines(True),
                                              fromfile='accepted-data22/' + repository,
                                              tofile='current/' + repository)))

prior = {}
for directory in ('member-realtime-attempt1-prior', 'member-realtime-attempt2-prior-valid-fixture',
                  'member-realtime-attempt3-current-unique-topic'):
    path = OUT / directory / 'validation.json'
    item = json.loads(path.read_text())
    prior[directory] = {'validation_sha256': digest(path), 'recorded_status': item['status'],
                        'machine': {k: item['machine'][k] for k in ('passed', 'failed', 'errors', 'skipped')}}

proof = {
    'status': 'pass_scoped_current_member_realtime',
    'generated_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'packet': str(PACKET.relative_to(ROOT)),
    'validation_sha256': digest(PACKET / 'validation.json'),
    'inputs_sha256': digest(PACKET / 'inputs.json'),
    'source_count': len(inputs['source']), 'export_count': len(inputs['export']),
    'machine': {k: validation['machine'][k] for k in ('passed', 'failed', 'errors', 'skipped')},
    'fatal_analysis_clean': True, 'scoped_current_bindings': bindings,
    'reviewed_prior_packets': prior,
    'data22_reuse': {
        'packet': str(DATA.relative_to(ROOT)),
        'old_repository_sha256': digest(DATA / 'source-export' / repository),
        'new_repository_sha256': bindings[repository],
        'reviewed_substitution_count': 3,
        'all_non_realtime_repository_bytes_unchanged': True,
        'shared_coordinator_unchanged': True,
        'raw_diff': str(diff_path.relative_to(ROOT)), 'raw_diff_sha256': digest(diff_path),
        'scope': 'Reuse Data22 only for unchanged repository bodies; current SDK18 separately accepts the changed topic/session/callback path.',
    },
    'database_calls_here': 0, 'tests_or_browser_reexecuted_here': False,
    'hosted_or_provider_acceptance': False, 'whole_L16_or_system_closed': False,
    'scope': 'Actual locked Auth/PostgREST and Phoenix loopback plus production repository/cache/coordinator. Synthetic JWT/HTTP rows are local mechanical fixtures, not signed-token, server RLS, provider or physical-device evidence.',
}
(OUT / 'accepted-current-proof.json').write_text(json.dumps(proof, indent=2) + '\n')
(OUT / 'critical-review.md').write_text('''# Member Realtime and cache authority review

## Demonstrated defect and correction

The prior valid-fixture run passed thirteen cases and retained four assertion failures plus one fixture error. Three failures were actual production behavior: a frame belonging to a departed topic caused an extra profile read after same-user session replacement, A to B to A, or account replacement. The locked SDK routes messages by topic, so reusing the static topic attached the departed frame to the new callback. This did not establish a private-row publication leak.

The repository now gives every authority scope a unique topic, captures its existing sticky session before subscribing, and requires that session to remain current before a callback refresh. The shared coordinator and valid same-session token refresh remain intact. The two other prior issues were fixture timing and a teardown helper reading disposed repository state; they remain distinct from the runtime defect.

## Accepted evidence

Strict current attempt4 passed **18 cases, zero failures/errors/skips**, with **fatal analysis clean**. Its 849 source inputs, 6,191 exported inputs and locked SDK remained unchanged. The completed packet recorded no live-source drift. The acceptance includes legitimate active joins, duplicate and irrelevant frames, failed-binding rejoin and missed membership reduction, same-user replacement, A to B to A, account replacement, supported token refresh, an old in-flight profile response, permission denial/private-cache cleanup, deliberate recovery, logout and disposal.

The current source readback in `accepted-current-proof.json` binds the repository, unchanged shared coordinator and both fixtures exactly. A full-byte comparison against the accepted Data22 repository permits only three reviewed substitutions inside `_ensureRealtimeSync`; all other repository bodies match. Data22's VM/Chrome data, mutation and staged-read results can therefore be retained for those unchanged bodies, while this SDK packet accepts the new Realtime behavior. The raw diff is preserved separately.

## Retained failures and limits

Attempt1 failed at fixture setup before the intended behavior; attempt2 reproduced the real static-topic issue. Attempt3 passed behavior but retained an analyzer information finding because its original gate did not fail on infos. Attempt4 adds the brace repair and a fatal-infos gate. Every original packet remains unchanged.

This is a scoped client acceptance. It does not certify signed JWTs, deployed RLS, provider delivery, every Admin/Gateway consumer, a physical device, or whole-system closure. Current generated-query performance and full application source integration remain separate local acceptance. No SQL, tests, browser or provider runs are executed by this review.
''')
print(json.dumps({'accepted_proof_sha256': digest(OUT / 'accepted-current-proof.json'),
                  'critical_review_sha256': digest(OUT / 'critical-review.md'),
                  'current_repository_sha256': bindings[repository]}, indent=2))
