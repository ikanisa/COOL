import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parent
canonical = root.parents[1]
packet = canonical / '.cache/admin-worker-cold-consumer-20261002/accepted-consumer6'


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


assert sha(packet / 'SEAL.json') == 'a228e242a94667e12d8bc1f6ba0966da7a045787f1e8156f972cadc8979d1f68'
assert sha(packet / 'FILES_SHA256.json') == '9b2eb40fb90198718fe0b20ea2f6fb2ab0b04135f2667a2d57f0e0fbc5575d5d'
manifest = json.loads((packet / 'FILES_SHA256.json').read_text())
base = Path(manifest['root'])
assert base.resolve() == packet.parent.resolve()
assert len(manifest['files']) == manifest['members'] == 528
for member in manifest['files']:
    path = base / member['path']
    path.resolve().relative_to(base.resolve())
    assert path.stat().st_size == member['bytes'] and sha(path) == member['sha256'], str(path)
assert sum(member['bytes'] for member in manifest['files']) == manifest['bytes'] == 33008037

results = {}
for attempt in ['consumer-attempt6', 'analysis-attempt1']:
    result = json.loads((base / attempt / 'result.json').read_text())
    assert result['status'] == 'passed' and result['exit_code'] == 0
    before = json.loads((base / attempt / 'inputs-before.json').read_text())
    after = json.loads((base / attempt / 'inputs-after.json').read_text())
    assert before == after and len(before) == 5835
    for name, digest in after.items():
        assert sha(Path(name)) == digest, name
    results[attempt] = result
assert len(results['consumer-attempt6']['cases']) == 16
assert all(case['result'] == 'success' for case in results['consumer-attempt6']['cases'])
assert results['consumer-attempt6']['terminal']['success'] is True
association = json.loads((packet / 'CANONICAL_SOURCE_ASSOCIATIONS.json').read_text())
assert len(association['source_bindings']) == 466
for name, digest in association['source_bindings'].items():
    assert sha(Path(name)) == digest, name

promotion = json.loads((packet / 'PROMOTION_MAP.json').read_text())
assert len(promotion['entries']) == 6 and not promotion['production_source_fixes']
for entry in promotion['entries']:
    assert entry['new'] is True
    assert not (canonical / entry['canonical']).exists(), entry['canonical']
    assert sha(Path(entry['staged'])) == entry['sha256'], entry['staged']

promoted = {}
for entry in promotion['entries']:
    path = canonical / entry['canonical']
    path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(entry['staged'], path)
    assert sha(path) == entry['sha256'], str(path)
    promoted[entry['canonical']] = entry['sha256']
receipt = {
    'checked_at': datetime.now(timezone.utc).isoformat(),
    'status': 'current_accepted_new_test_and_fixture_bytes_integrated',
    'private_packet_members_verified': len(manifest['files']),
    'completed_consumer_checks': len(results['consumer-attempt6']['cases']),
    'targeted_analysis_passed': True,
    'source_runtime_dependency_bindings': 5835,
    'current_canonical_and_fixture_associations': 466,
    'promoted_files': promoted,
    'product_fix_count': 0,
    'scope': 'Exact current Admin SDK/provider/card integrity/session seam over original observed SQL fixtures through synthetic HTTP/Auth; no hosted/comparator/full-candidate acceptance',
}
(root / 'canonical-source-association.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: value for key, value in receipt.items() if key != 'promoted_files'}))
