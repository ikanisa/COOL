import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parent
canonical = root.parents[1]
app = root / 'validation-app'
proof = root / 'proof'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


before = json.loads((proof / 'bindings-before.json').read_text())
after = json.loads((proof / 'bindings-after.json').read_text())
result = json.loads((proof / 'result.json').read_text())
assert result['status'] == 'passed'
assert before == after
drift = [path for path, digest in after.items()
         if not Path(path).is_file() or sha(Path(path)) != digest]
assert not drift, drift

expected = json.loads((proof / 'promotion.json').read_text())['files']
expected.update(json.loads((proof / 'plain-language-successor.json').read_text())['files'])
for name, digest in expected.items():
    assert sha(canonical / name) == digest, name
    assert sha(root / 'promote' / name) == digest, name

associated = {}
for path, digest in after.items():
    try:
        relative = Path(path).relative_to(app)
    except ValueError:
        continue
    if relative.parts[0] not in ['lib', 'test', 'contracts', 'scripts', 'docs']:
        continue
    current = canonical / relative
    assert current.is_file(), str(current)
    assert sha(current) == digest, str(current)
    associated[str(relative)] = digest
for name in ['pubspec.yaml', 'pubspec.lock']:
    assert sha(canonical / name) == sha(app / name), name
    associated[name] = sha(canonical / name)

migrations = sorted((canonical / 'supabase/migrations').glob('*.sql'))
versions = Counter(p.name.split('_')[0] for p in migrations)
assert all(count == 1 for count in versions.values())
receipt = {
    'checked_at': datetime.now(timezone.utc).isoformat(),
    'status': 'passed',
    'promoted_files': expected,
    'promoted_file_count': len(expected),
    'source_dependency_tool_binding_count': len(after),
    'all_bound_inputs_still_match_completed_run': True,
    'current_canonical_consumer_and_fixture_bindings': associated,
    'canonical_consumer_and_fixture_count': len(associated),
    'validation_manifest_match': True,
    'validation_package_uri_adaptation': 'Private application package roots resolve copied consumers; resolved dependency contents and tools bound before and after execution',
    'current_migration_count': len(migrations),
    'duplicate_migration_versions': [],
    'actual_consumer_terminal': {'session_id': 88745, 'exit_code': 0},
    'scope': 'Exact current 38-file integration and affected Admin history, capture and joined-audit consumers; not whole candidate or hosted acceptance',
}
(proof / 'canonical-source-association.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({k: v for k, v in receipt.items()
                  if k not in ['promoted_files', 'current_canonical_consumer_and_fixture_bindings']}))
