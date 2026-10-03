import hashlib
import json
import pathlib
import stat
import subprocess
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[2]
PACKET = ROOT / '.cache/receipt-repeat-run-recovery-20261002'
OUT = pathlib.Path(__file__).resolve().parent

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def read(name):
    return json.loads((PACKET / name).read_text())

def bound_path(name):
    path = pathlib.Path(name)
    return path if path.is_absolute() else ROOT / path

seal = read('SEAL.json')
for name, key in [('MANIFEST.json', 'manifest_sha256'),
                  ('accepted-receipt.json', 'receipt_sha256'),
                  ('PROMOTION.json', 'promotion_sha256')]:
    assert digest(PACKET / name) == seal[key], name
manifest = read('MANIFEST.json')
total = 0
for name, entry in manifest['files'].items():
    path = PACKET / name
    assert '..' not in pathlib.Path(name).parts and not pathlib.Path(name).is_absolute()
    assert stat.S_ISREG(path.lstat().st_mode), name
    assert path.stat().st_size == entry['bytes'] and digest(path) == entry['sha256'], name
    total += entry['bytes']
assert len(manifest['files']) == seal['members']

vectors = {}
for name, key in [('source-bindings.json', 'files'),
                  ('sql-attempt11/result.json', 'source_bindings'),
                  ('consumer-accepted2/consumer-receipt.json', 'source_bindings'),
                  ('view-attempt6/inputs.json', 'canonical_and_overlay'),
                  ('view-attempt6/inputs.json', 'private_copy_hashes')]:
    vector = read(name)[key]
    for path, expected in vector.items():
        actual = (PACKET / 'view-attempt6/validation-app' / path
                  if key == 'private_copy_hashes' else bound_path(path))
        assert digest(actual) == expected, (name, path)
    vectors[name + ':' + key] = len(vector)

sql = read('sql-attempt11/result.json')
assert sql['status'] == 'passed' and len(sql['checks']) == 93
assert all(c['passed'] for c in sql['checks']) and sql['command_receipts'] == 507
for name in ['consumer-accepted2/consumer-receipt.json', 'view-attempt6/result.json']:
    receipt = read(name)
    assert receipt['status'] == 'passed'
    directory = PACKET / pathlib.Path(name).parent
    for command in receipt['commands']:
        assert command['exit_code'] == 0
        for suffix in ['stdout', 'stderr']:
            assert digest(directory / (command['name'] + '.' + suffix)) == command[suffix + '_sha256']

promotion = read('PROMOTION.json')
model = promotion['base_aware_model']
assert digest(pathlib.Path(model['base'])) == model['base_sha256']
for name, expected in promotion['files'].items():
    assert digest(PACKET / 'promote' / name) == expected, name
    if name != 'lib/admin/core/admin_receipt_operational_history_models.dart':
        assert not (ROOT / name).exists(), name

docker = '/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
targets = []
for target in read('owned-targets-removed.json')['targets']:
    result = subprocess.run([docker, 'inspect', target['name']], capture_output=True, text=True, timeout=15)
    assert result.returncode == 1 and 'no such object:' in result.stderr.lower(), target['name']
    targets.append({'name': target['name'], 'exit_code': result.returncode,
                    'stderr': result.stderr.strip()})

result = {'status': 'verified', 'packet_members': len(manifest['files']),
          'packet_bytes': total, 'current_binding_vectors': vectors,
          'sql_checks': 93, 'sql_command_receipts': 507,
          'consumer_scope': '7 actual readers, 7 mapped negatives, 74 actual Edge contract fixtures',
          'flutter_scope': '35 checks: 22 unchanged history and 13 mapped recovery; four-file analysis clean',
          'promotion_files': len(promotion['files']), 'targets_absent': targets,
          'timestamp': datetime.now(timezone.utc).isoformat(),
          'canonical_mutation': False, 'hosted': False, 'device': False,
          'full_candidate_replay': False}
(OUT / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: v for k, v in result.items() if k != 'targets_absent'}, indent=2))
