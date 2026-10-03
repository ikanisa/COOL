#!/usr/bin/env python3
"""Bind prepared browser source to the final strict immutable candidate."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT = Path(__file__).resolve().parent
FINAL = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/collect-integrated-local-candidate-20261001-current2')
MANIFEST_SHA = '24b1719665694a2f09b18ee78e8cf6d4e33f416a5fd0c42edd747f0f22867a6a'
PEER = ROOT / 'docs/release/collect-codex-goal-2026-09-30/admin-exception-history-ui-20261001'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

prepared = json.loads((OUT / 'browser-stage-prepared.json').read_text())
build = Path(prepared['build_root'])
manifest_path = FINAL / '.collect-release-candidate.json'
assert sha(manifest_path) == MANIFEST_SHA
manifest = json.loads(manifest_path.read_text())
final_inputs = {n: v['sha256'] for n, v in manifest['source_files'].items()}
old_inputs = prepared['inputs_sha256']
assert final_inputs.keys() == old_inputs.keys()
changed = [n for n, d in final_inputs.items() if d != old_inputs[n]]
assert changed == ['test/admin_entity_audit_authority_test.dart'], changed
for n, digest in old_inputs.items():
    assert sha(build / n) in ({digest, final_inputs[n]} if n in changed else {digest}), n
for n, digest in final_inputs.items():
    assert sha(FINAL / n) == digest, n
for n in changed:
    shutil.copy2(FINAL / n, build / n)
assert all(sha(build / n) == d and sha(FINAL / n) == d for n, d in final_inputs.items())
assert all(sha(build / n) == d for n, d in prepared['supplemental_inputs'].items())
assert final_inputs[changed[0]] == prepared['required_authority_test_final_sha256']

export_receipt = OUT.parent / 'candidate-current2-export.json'
export = json.loads(export_receipt.read_text())
assert export['status'] == export['source_readback']['status'] == 'pass'
assert export['manifest_sha256'] == MANIFEST_SHA and not export['source_readback']['changes']
assert export['file_count'] == len(final_inputs) == 2175
peer_receipt = PEER / 'attempt3/verification.json'
peer = json.loads(peer_receipt.read_text())
assert peer['accepted'] and peer['terminal']['success'] and peer['all_requested_suites_executed']
assert peer['completed_visible_cases'] == peer['expected_cases'] == 657 and not peer['changed_inputs']
assert sha(PEER / 'MANIFEST.json') == 'c071f0e8d4f38467366de44e7dac34160dd8b67aabed6de2c6da3a094b3c86b3'
peer_sources = json.loads((PEER / 'attempt3/inputs-before.json').read_text())
peer_candidate = {str(Path(n).relative_to(ROOT)): d for n, d in peer_sources.items()
                  if str(n).startswith(str(ROOT) + '/') and str(Path(n).relative_to(ROOT)) in final_inputs}
peer_external = {n: d for n, d in peer_sources.items()
                 if not (str(n).startswith(str(ROOT) + '/') and str(Path(n).relative_to(ROOT)) in final_inputs)}
external_drift = sorted(n for n, d in peer_external.items() if not Path(n).is_file() or sha(Path(n)) != d)
missing_peer = sorted(n for n in peer_candidate if n not in final_inputs)
peer_drift = sorted(n for n, d in peer_candidate.items() if n in final_inputs and final_inputs[n] != d)
assert not missing_peer and not peer_drift, (missing_peer, peer_drift)
assert not external_drift, external_drift

prepared.update({
    'status': 'bound_final_current2_authorized_for_one_lifecycle_command',
    'source': str(FINAL), 'manifest_sha256': MANIFEST_SHA,
    'source_manifest_sha256': manifest['source_manifest_sha256'],
    'inputs_sha256': final_inputs, 'current2_changed_inputs': changed,
    'needs_final_current2_snapshot_binding': False,
    'strict_export_receipt': str(export_receipt), 'strict_export_receipt_sha256': sha(export_receipt),
    'peer_657_receipt': str(peer_receipt), 'peer_657_receipt_sha256': sha(peer_receipt),
    'peer_657_source_bindings': peer_candidate,
    'peer_657_external_proof_and_dependency_bindings': peer_external,
    'peer_657_external_drift': external_drift,
    'peer_source_mismatch': peer_drift, 'peer_missing_sources': missing_peer,
    'scope': 'Final immutable current2 source, strict readback and existing 657-case peer acceptance. Only a known test-only delta replaced in prepared isolated source. One fresh production Admin build plus existing browser/Public/PWA lifecycle; no additional VM or SQL execution.'})
(OUT / 'browser-inputs.json').write_text(json.dumps(prepared, indent=2, sort_keys=True) + '\n')
print('BOUND final current2', len(final_inputs), 'source inputs;', len(peer_candidate), 'peer consumed source bindings;', len(changed), 'test-only delta', flush=True)
