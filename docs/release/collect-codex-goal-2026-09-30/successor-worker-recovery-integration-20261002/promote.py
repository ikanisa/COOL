import hashlib
import json
import os
import pathlib
import shutil
import stat
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent
RUNNER = ROOT / '.cache/receipt-successor-native-runner-adaptation-20261002'
NATIVE = ROOT / '.cache/receipt-successor-workflows-20261001/accepted-successor-native-primary-delta-current1'

def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def read(path):
    return json.loads(path.read_text())

assert not (OUT / 'canonical-source-association.json').exists()
seal = read(RUNNER / 'SEAL.json')
assert sha(RUNNER / 'MANIFEST.json') == seal['manifest_sha256'] == 'ad22e8755431f00750ecf58647daef81d03153a504b78cfe9a2e4eed6b318777'
assert sha(RUNNER / 'PROMOTION.json') == seal['promotion_sha256'] == 'ae0aecb3fa347398d1ed64da32942cf3041aefe50b7d5c818625a81f7a625672'
assert sha(RUNNER / 'accepted-receipt.json') == seal['accepted_receipt_sha256']
manifest = read(RUNNER / 'MANIFEST.json')
assert len(manifest) == seal['member_count'] == 825
for name, expected in manifest.items():
    path = RUNNER / name
    assert not pathlib.Path(name).is_absolute() and '..' not in pathlib.Path(name).parts
    assert stat.S_ISREG(path.lstat().st_mode) and sha(path) == expected, name
reuse = read(RUNNER / 'REUSE_BINDINGS.json')
for name, expected in reuse['selected_native_fixture_old_test_members'].items():
    assert sha(NATIVE / name) == expected, name
assert sha(pathlib.Path(reuse['producer_result_path'])) == reuse['producer_result_sha256']
historical = ROOT / 'docs/release/collect-codex-goal-2026-09-30/android-gateway/run_native_checks.py'
assert sha(historical) == reuse['historical_helper_sha256']
invocation = read(RUNNER / 'successor-attempt2/validation.json')
assert invocation['status'] == 'pass'
for path, expected in invocation['binary_sha256'].items():
    assert sha(pathlib.Path(path)) == expected, path
for command in invocation['commands']:
    assert command['exit_code'] == 0
    for stream in ['stdout', 'stderr']:
        assert sha(RUNNER / 'successor-attempt2' / (command['name'] + '.' + stream)) == command[stream + '_sha256']
assert 'OK (21 tests)' in (RUNNER / 'successor-attempt2/tests-GatewaySuccessorTest.stdout').read_text()

plan = read(OUT / 'product-plan.json')
entries = plan['entries']
for item in read(RUNNER / 'PROMOTION.json')['entries']:
    entries.append({'source': item['proposed_path'], 'target': item['target'],
                    'sha256': item['sha256'], 'base_sha256': item['base_sha256'],
                    'mode': int(item['mode'], 8)})
assert len(entries) == 43 and len({e['target'] for e in entries}) == 43
for item in entries:
    target = pathlib.Path(item['target'])
    assert not target.is_absolute() and '..' not in target.parts
    source = pathlib.Path(item['source'])
    assert stat.S_ISREG(source.lstat().st_mode) and sha(source) == item['sha256']
    canonical = ROOT / target
    if item['base_sha256'] is None:
        assert not canonical.exists(), str(target)
    else:
        assert stat.S_ISREG(canonical.lstat().st_mode) and sha(canonical) == item['base_sha256'], str(target)
        backup = OUT / 'originals' / target
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(canonical, backup)
        assert sha(backup) == item['base_sha256']
        item['mode'] = canonical.stat().st_mode & 0o777
before_migrations = {p.name: sha(p) for p in (ROOT / 'supabase/migrations').glob('*.sql')}
assert len(before_migrations) == 204
(OUT / 'accepted-plan.json').write_text(json.dumps({'entries': entries,
    'before_migrations': before_migrations, 'runner_manifest': seal['manifest_sha256']}, indent=2) + '\n')
for item in entries:
    canonical = ROOT / item['target']
    if item['base_sha256'] is None:
        assert not canonical.exists()
    else:
        assert sha(canonical) == item['base_sha256']
    data = pathlib.Path(item['source']).read_bytes()
    assert hashlib.sha256(data).hexdigest() == item['sha256']
    canonical.parent.mkdir(parents=True, exist_ok=True)
    temporary = canonical.with_name(canonical.name + '.root-integration-tmp')
    with temporary.open('xb') as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    temporary.chmod(item['mode'])
    temporary.replace(canonical)
    assert sha(canonical) == item['sha256']
after_migrations = {p.name: sha(p) for p in (ROOT / 'supabase/migrations').glob('*.sql')}
assert len(after_migrations) == 207
assert all(after_migrations[name] == value for name, value in before_migrations.items())
assert len({name.split('_', 1)[0] for name in after_migrations}) == 207
assert sha(historical) == reuse['historical_helper_sha256']
result = {'status': 'integrated_exact_reviewed_sources', 'files': len(entries),
          'modifications_preserved': sum(e['base_sha256'] is not None for e in entries),
          'canonical_sha256': {e['target']: e['sha256'] for e in entries},
          'migrations_before': 204, 'migrations_after': 207,
          'unchanged_preexisting_migrations': 204,
          'runner_members_verified': 825, 'runtime_inputs_verified': len(invocation['binary_sha256']),
          'timestamp': datetime.now(timezone.utc).isoformat(),
          'hosted': False, 'device': False, 'SMS': False, 'whole_candidate_pass': False,
          'affected_current_consumer_checks': 'pending'}
(OUT / 'canonical-source-association.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k: v for k, v in result.items() if k != 'canonical_sha256'}, indent=2))
