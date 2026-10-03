import hashlib
import json
import pathlib
import tomllib

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent
MAP = ROOT / '.cache/receipt-successor-workflows-20261001/INTEGRATION_MAP_430_CURRENT1.json'
RUNNER = ROOT / '.cache/receipt-successor-native-runner-adaptation-20261002'
P700 = ROOT / '.cache/receipt-worker-history-storage-20261002/promote'
P800 = ROOT / '.cache/receipt-repeat-run-recovery-20261002'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def entry(source, target, expected, base=None):
    source = pathlib.Path(source)
    target = pathlib.Path(target)
    assert not target.is_absolute() and '..' not in target.parts
    assert sha(source) == expected, str(source)
    canonical = ROOT / target
    if base is None:
        assert not canonical.exists(), str(target)
    else:
        assert not canonical.is_symlink() and sha(canonical) == base, str(target)
    return {'source': str(source), 'target': str(target), 'sha256': expected,
            'base_sha256': base, 'mode': source.stat().st_mode & 0o777}

assert sha(MAP) == '0227f38f2b97b5486a467a5a04523199751a04275e2135abba39f6e63e7c1052'
mapping = json.loads(MAP.read_text())
entries = []
for item in mapping['product_entries']:
    if item['canonical_target'] and item['kind'] != 'new_successor_test_21':
        entries.append(entry(item['accepted_path'], item['canonical_target'],
                             item['accepted_sha256'], item['current_base_sha256']))
for target, expected in {
    'supabase/migrations/20261002070000_receipt_worker_history_storage.sql':
        'c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3',
    'docs/platform/RECEIPT_WORKER_HISTORY_STORAGE.md':
        'f1c72a3229a5e1c123bff5c080e6a5aef32676fc5182149d0a96050c65310279'
}.items():
    entries.append(entry(P700 / target, target, expected))
promotion = json.loads((P800 / 'PROMOTION.json').read_text())
for target, expected in promotion['files'].items():
    base = promotion['base_aware_model']['base_sha256'] if target.endswith('admin_receipt_operational_history_models.dart') else None
    entries.append(entry(P800 / 'promote' / target, target, expected, base))

config = ROOT / 'supabase/config.toml'
assert sha(config) == '7151b94ab19ded20073b741c373f6f95c3739405ebed01f7ea33bdd8b7f2cc67'
original = config.read_bytes()
suffix = b'\n# Device P-256 request authentication is checked by the successor handler.\n[functions.collect-receipt-successor-gateway]\nverify_jwt = false\n'
updated = original + suffix
before, after = tomllib.loads(original.decode()), tomllib.loads(updated.decode())
assert after['functions'].pop('collect-receipt-successor-gateway') == {'verify_jwt': False}
assert before == after
staged_config = OUT / 'supabase-config.toml'
staged_config.write_bytes(updated)
entries.append(entry(staged_config, 'supabase/config.toml', sha(staged_config), sha(config)))

versions = [p.name.split('_', 1)[0] for p in (ROOT / 'supabase/migrations').glob('*.sql')]
assert len(versions) == len(set(versions)) == 204
new_versions = [pathlib.Path(e['target']).name.split('_', 1)[0]
                for e in entries if e['target'].startswith('supabase/migrations/')]
assert new_versions == ['20261002043000', '20261002070000', '20261002080000']
assert not set(versions).intersection(new_versions)
plan = {'status': 'reviewed_product_plan_awaiting_sealed_runner_delta',
        'entries': entries, 'current_migrations': 204, 'planned_migrations': 207,
        'integration_order': ['430', '700', '800'], 'canonical_written': False,
        'runner_stage': str(RUNNER), 'map_sha256': sha(MAP)}
(OUT / 'product-plan.json').write_text(json.dumps(plan, indent=2) + '\n')
print(json.dumps({'status': plan['status'], 'files': len(entries),
                  'modifications': sum(e['base_sha256'] is not None for e in entries),
                  'planned_migrations': 207}))
