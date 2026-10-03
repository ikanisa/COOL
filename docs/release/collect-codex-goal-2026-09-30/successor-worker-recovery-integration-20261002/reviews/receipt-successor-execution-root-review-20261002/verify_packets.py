import datetime
import hashlib
import json
from pathlib import Path

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PRIVATE = ROOT / '.cache/receipt-successor-workflows-20261001'
DEST = ROOT / '.cache/receipt-successor-execution-root-review-20261002/packet-verification.json'
SPECS = [
    ('accepted-successor-first-job-execution-current1', 'd88c93d23e7f2f3c14a1bc0de7de837738fb9ecf842b3719c25fb2b58cf22fb7', '04114409eb766331870421032263b926bf25ccfc2140f4261b0c6047d5e8f0a3', 3941),
    ('accepted-successor-observations-archive-current1', 'b6f2e1f2c08d7cd3af071c85c8b1e5543b2cae2153ad24867a6d75b498a51885', 'df39ee12e0433323cf5ad3f94f149d6668be1f8d694e8e790cfe8ccb40635804', 1827),
    ('accepted-successor-full430-publication-current1', '34a085ce4b1023ffbaa99e9944e09fee29d341d2344cf216a64517b07641194d', '1261edab8273b821039fdda0465165452d8aa52e9b80b860e99106a76e5fe567', 2167),
    ('accepted-successor-owner-publication-current1', '60c9d6ffbbe88141cdf686ec051048b306fbd7df772b35349fbc61cfa07fd059', '8de17c2108b489ef3e7c4beeb674440fb37ec249ba6cfcceb805b8b2b872dae4', 1797),
    ('accepted-successor-edge-current1', '2b72b3f39941916dfaf6fbdfb6ed00744f862e2c45974c0a162a6c34ca68f41a', '591aa0d3d725f9a36a2a611e17c9dba8e81fc57ce9462b1e1e0833a2fba3897f', 71),
    ('accepted-successor-edge-index-current1', '9e87c6a73d63ec00708598c3974dfd5eb47eee282b705f6c96237cab492c28a7', 'b52efd4b202d48184d270ff3ebd07efafd0779df9d3821770058abd378ffcf3f', 73),
    ('accepted-successor-native-primary-delta-current1', 'eeeddadf78eedc0bc24639baeea1b69a79a0b606eba053d24401e157faafe13e', '9baf583457b7dc51421acf9b490ba97c82abe63bcad8f93bf01726be7e3ea97d', 510)
]


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


assert not DEST.exists()
packets = []
canonical = {}
for name, mh, vh, count in SPECS:
    p = PRIVATE / name
    assert sha(p / 'MANIFEST.json') == mh and sha(p / 'verification.json') == vh, name
    manifest = json.loads((p / 'MANIFEST.json').read_text())
    assert len(manifest) == count, name
    size = 0
    for rel, digest in manifest.items():
        r = Path(rel)
        assert not r.is_absolute() and '..' not in r.parts
        f = p / r
        assert f.is_file() and not f.is_symlink() and sha(f) == digest, f'{name}:{rel}'
        size += f.stat().st_size
    v = json.loads((p / 'verification.json').read_text())
    bound_result = None
    if v.get('result_sha256'):
        matches = [rel for rel, digest in manifest.items() if digest == v['result_sha256']]
        assert len(matches) == 1
        bound_result = matches[0]
        r = json.loads((p / bound_result).read_text())
        assert r['status'] == 'passed', name
        if 'checks' in r:
            assert len(r['checks']) == v['actual_cases'] and all(x['passed'] for x in r['checks'])
            assert r['source_unchanged']
        if isinstance(r.get('source_bindings'), dict):
            for rel, digest in r['source_bindings'].items():
                if (ROOT / rel).is_file() and not Path(rel).is_absolute():
                    assert sha(ROOT / rel) == digest, f'{name}:{rel}'
                    if rel in canonical:
                        assert canonical[rel] == digest
                    canonical[rel] = digest
    for key in ('canonical_prerequisites', 'shared_dependencies', 'current_unchanged20_old_test_bindings'):
        for rel, digest in v.get(key, {}).items():
            assert sha(ROOT / rel) == digest, f'{name}:{rel}'
            if rel in canonical:
                assert canonical[rel] == digest
            canonical[rel] = digest
    for path, digest in v.get('binary_bindings', {}).items():
        assert sha(Path(path)) == digest, path
    for path, record in v.get('remote_dependencies', {}).items():
        assert sha(Path(path)) == record['sha256']
        assert sha(p / record['packet_path']) == record['sha256']
    if v.get('deno_path'):
        assert sha(Path(v['deno_path'])) == v['deno_sha256']
    packets.append({'name': name, 'members': count, 'bytes': size, 'manifest_sha256': mh, 'verification_sha256': vh, 'actual_bound_result': bound_result, 'scope': v.get('scope', v.get('selected_scope', 'See immutable verification')), 'cases': v.get('actual_cases', v.get('actual_composed_cases', v.get('complete_actual_cases_composed'))), 'composed': name in ('accepted-successor-owner-publication-current1', 'accepted-successor-native-primary-delta-current1')})

owner = PRIVATE / 'accepted-successor-owner-publication-current1'
om = json.loads((owner / 'MANIFEST.json').read_text())
ov = json.loads((owner / 'verification.json').read_text())
for label, indices in [('unchanged_source_equivalent_prefix', range(25)), ('affected_tail', range(5))]:
    digest = ov['composition'][label]['result_sha256']
    matches = [rel for rel, h in om.items() if h == digest]
    assert len(matches) == 1
    r = json.loads((owner / matches[0]).read_text())
    assert r['source_unchanged'] and all(r['checks'][i]['passed'] for i in indices)
    for rel, h in r['source_bindings'].items():
        assert sha(ROOT / rel) == h, rel

native = PRIVATE / 'accepted-successor-native-primary-delta-current1'
nv = json.loads((native / 'verification.json').read_text())
for rel, pair in nv['modified_native_boundaries'].items():
    assert sha(ROOT / rel) == pair['canonical_sha256'] and sha(native / rel) == pair['staged_sha256']
for rel, h in nv['new_native_modules'].items():
    assert not (ROOT / rel).exists() and sha(native / rel) == h
assert nv['complete_actual_cases_composed'] == 272 and nv['new_successor_cases'] == 21 and nv['legacy_cases'] == 251

receipt = {'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'status': 'scoped_SQL_Edge_native_packets_and_current_prerequisites_verified', 'packets': packets, 'members_verified': sum(x['members'] for x in packets), 'bytes_verified': sum(x['bytes'] for x in packets), 'canonical_associations_verified': canonical, 'migration_sha256': '9793a5d5de2251e00d98221156b8c97e202ebb499f2f79da1f988a99a189001c', 'root_source_review': 'Complete1016-line combined SQL, all new200-line Edge handler/83-line wire/5-line index, all9 native diffs and both new native modules read.', 'integration_state': 'Not canonical; resolve root-found successor readRequests row/envelope identity coherence gap before native promotion; exact-artifact272 preceding composition remains immutable', 'whole_candidate_pass': False, 'hosted_verified': False, 'device_verified': False}
DEST.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({k: receipt[k] for k in ('status', 'members_verified', 'bytes_verified', 'migration_sha256', 'integration_state')}))
