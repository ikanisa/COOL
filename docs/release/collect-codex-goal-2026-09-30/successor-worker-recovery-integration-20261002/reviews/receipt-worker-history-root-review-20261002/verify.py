import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parent
canonical = root.parents[1]
packet = canonical / '.cache/receipt-worker-history-storage-20261002/accepted-final12'


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


assert sha(packet / 'SEAL.json') == 'bc447ab0e637a491216ddb9a556bdee8dafd2e661a1620179b2c457e5d92b297'
assert sha(packet / 'FILES_SHA256.json') == '39db631e919e0a7cd73cdb7ff8d06e9fb5c900f1251ef37b7431d48f6fe32d51'
manifest = json.loads((packet / 'FILES_SHA256.json').read_text())
base = Path(manifest['root'])
assert base.resolve() == packet.parent.resolve()
assert len(manifest['files']) == manifest['members'] == 14602
total = 0
for member in manifest['files']:
    path = base / member['path']
    path.resolve().relative_to(base.resolve())
    assert path.is_file(), str(path)
    assert path.stat().st_size == member['bytes'], str(path)
    assert sha(path) == member['sha256'], str(path)
    total += member['bytes']
assert total == manifest['bytes'] == 2326540160

result_path = base / 'sql-attempt12/result.json'
result = json.loads(result_path.read_text())
assert sha(result_path) == '2ecc0262297e8c96b85dc7c47356330c6f58166bb954abd86c9e928ce6ed5e0f'
assert result['status'] == 'passed' and len(result['checks']) == 60
assert all(case['passed'] for case in result['checks'])
assert len(result['source_bindings']) == 418
for name, digest in result['source_bindings'].items():
    assert sha(Path(name)) == digest, name

promotion = json.loads((packet / 'PROMOTION_MAP.json').read_text())
for entry in promotion['entries']:
    assert sha(Path(entry['staged'])) == entry['sha256'], entry['staged']
    assert not (canonical / entry['canonical']).exists(), entry['canonical']

receipt = {
    'checked_at': datetime.now(timezone.utc).isoformat(),
    'status': 'private_packet_and_current_inputs_verified',
    'member_count': len(manifest['files']),
    'member_bytes': total,
    'selected_source_tool_bindings': len(result['source_bindings']),
    'actual_sql_checks': len(result['checks']),
    'promotion_entries': promotion['entries'],
    'canonical_written': False,
    'prerequisite_limit': 'Exact private430, canonical500 and corrected600 over selected retained checkpoint; not full current candidate or hosted acceptance',
    'remaining': 'Verify actual SDK/card consumer packet, original target absence, private430 integration dependency, and unified snapshot/native/scheduler recovery',
}
(root / 'verification.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: value for key, value in receipt.items() if key != 'promotion_entries'}))
