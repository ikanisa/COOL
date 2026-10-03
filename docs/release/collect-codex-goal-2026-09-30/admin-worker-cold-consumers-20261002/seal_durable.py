import datetime
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PRIVATE = ROOT / '.cache/admin-worker-cold-consumer-20261002'
ACCEPTED = PRIVATE / 'accepted-consumer6'
BOUNDARY = ROOT / '.cache/admin-worker-cold-consumer-root-integration-20261002'
DEST = ROOT / 'docs/release/collect-codex-goal-2026-09-30/admin-worker-cold-consumers-20261002'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_relative(value):
    p = Path(value)
    assert not p.is_absolute() and '..' not in p.parts
    return p


assert not DEST.exists(), 'Preserve any existing durable packet'
manifest_path = ACCEPTED / 'FILES_SHA256.json'
assert sha(manifest_path) == '9b2eb40fb90198718fe0b20ea2f6fb2ab0b04135f2667a2d57f0e0fbc5575d5d'
assert sha(ACCEPTED / 'SEAL.json') == 'a228e242a94667e12d8bc1f6ba0966da7a045787f1e8156f972cadc8979d1f68'
manifest = json.loads(manifest_path.read_text())
assert Path(manifest['root']) == PRIVATE
assert manifest['members'] == len(manifest['files']) == 528
assert sum(x['bytes'] for x in manifest['files']) == manifest['bytes'] == 33008037
association = json.loads((BOUNDARY / 'canonical-source-association.json').read_text())
assert association['status'] == 'current_accepted_new_test_and_fixture_bytes_integrated'
assert association['completed_consumer_checks'] == 16 and association['targeted_analysis_passed']
for rel, digest in association['promoted_files'].items():
    assert sha(ROOT / safe_relative(rel)) == digest, rel
seen = set()
for entry in manifest['files']:
    rel = safe_relative(entry['path'])
    assert str(rel) not in seen
    seen.add(str(rel))
    path = PRIVATE / rel
    assert path.is_file() and not path.is_symlink()
    assert path.stat().st_size == entry['bytes'] and sha(path) == entry['sha256'], str(rel)
DEST.mkdir(parents=True)
for entry in manifest['files']:
    rel = safe_relative(entry['path'])
    target = DEST / 'retained' / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PRIVATE / rel, target)
    assert sha(target) == entry['sha256'], str(rel)
for name in ('HANDOFF.md', 'PROMOTION_MAP.json', 'FILES_SHA256.json', 'CANONICAL_SOURCE_ASSOCIATIONS.json', 'FINAL_STATUS.json', 'SEAL.json'):
    target = DEST / 'original-accepted-metadata' / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ACCEPTED / name, target)
    assert sha(target) == sha(ACCEPTED / name)
for name in ('canonical-source-association.json', 'promote.py', 'seal_durable.py'):
    shutil.copy2(BOUNDARY / name, DEST / name)
(DEST / 'README.md').write_text('''# Current Admin worker cold-history consumers

Six new canonical test/fixture files were integrated by exact accepted hashes. No production source correction was necessary. The final run passed 16 SDK/provider/card checks with clean targeted analysis. Its 5,835 captured source, runtime, dependency and fixture inputs were unchanged; root verified the 528-member private packet and 466 current canonical/fixture associations before promotion. The original observed SQL fixtures retain their producer bytes.

Eight SDK checks exercise actual AdminRepository/provider/session behavior through synthetic HTTP/Auth adapters, including known cold-integrity SQLSTATE 55000, no automatic retry and pending response rejection after session departure. Eight card checks cover reconstructed evidence, initial integrity refusal, stale evidence removal during refresh, and original-session departure for health and detail. Fixture clocks use the captured producer timestamp. The checks do not replace the worker repository or identity layer.

Earlier source drift, binding, HTTP mock and async-timing failures remain retained. The final 16 cases are separate from the preceding 14 DTO checks and the storage migration's 60 SQL checks; these counts are not summed. Targeted analysis has its own terminal receipt. Tests use one 820px layout and synthetic Auth/HTTP: they do not establish authenticated hosted behavior, complete browser/reader/Revolut acceptance, physical Android testing or a full candidate regression.

`retained/` preserves every member of the accepted private manifest, including failed attempts, copied source closure, observed fixtures and actual final receipts. `original-accepted-metadata/` preserves the original manifest, seals and private source associations unchanged. Those original absolute paths describe their captured private boundary; `FILES_SHA256.json` is the relocatable durable packet inventory. External runtime/dependency hash inventories are retained as associations, not bundled binaries. Root's canonical integration receipt records exact readback. The original storage packet remains unchanged and its migration still requires dependency-ordered integration.
''')
files = {}
for path in sorted(DEST.rglob('*')):
    if path.is_file():
        files[str(path.relative_to(DEST))] = {'bytes': path.stat().st_size, 'sha256': sha(path)}
durable_manifest = {'contract_version': 1, 'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'files': files, 'members': len(files), 'bytes': sum(x['bytes'] for x in files.values()), 'self_excluded': True, 'scope': association['scope']}
(DEST / 'FILES_SHA256.json').write_text(json.dumps(durable_manifest, indent=2, sort_keys=True) + '\n')
for rel, entry in files.items():
    assert sha(DEST / rel) == entry['sha256'], rel
receipt = {'status': 'sealed_durable_exact_accepted_consumer_proof', 'path': str(DEST), 'members': len(files), 'bytes': durable_manifest['bytes'], 'manifest_sha256': sha(DEST / 'FILES_SHA256.json'), 'canonical_promotions_verified': len(association['promoted_files']), 'new_check_count': 16, 'product_fix_count': 0, 'whole_candidate_pass': False, 'hosted_verified': False}
(BOUNDARY / 'durable-packet.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt))
