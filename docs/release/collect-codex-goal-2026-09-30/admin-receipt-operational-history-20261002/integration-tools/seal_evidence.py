import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

integration = Path(__file__).resolve().parent
canonical = integration.parents[1]
original = canonical / '.cache/admin-operational-history-20261002'
corrected = canonical / '.cache/admin-operational-history-cost-correction-20261002'
destination = canonical / 'docs/release/collect-codex-goal-2026-09-30/admin-receipt-operational-history-20261002'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy_file(source, target):
    assert source.is_file(), str(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    assert sha(source) == sha(target), str(target)


assert not destination.exists(), 'Existing evidence must not be overwritten'
association = json.loads((integration / 'proof/canonical-source-association.json').read_text())
assert association['status'] == 'passed'
original_manifest = json.loads((original / 'manifest.json').read_text())
original_receipt = json.loads((original / 'proof/accepted-receipt.json').read_text())
assert sha(original / 'manifest.json') == original_receipt['manifest_sha256']
assert sha(original / 'HANDOFF.md') == original_receipt['handoff_sha256']
for member in original_manifest['files']:
    assert sha(original / 'promote' / member['path']) == member['proposed_sha256'], member['path']
corrected_manifest = json.loads((corrected / 'manifest.json').read_text())
for name, digest in corrected_manifest['members'].items():
    assert sha(corrected / name) == digest, name
sql_result = json.loads((corrected / 'sql-attempt6/result.json').read_text())
assert sql_result['status'] == 'passed' and len(sql_result['checks']) == 63
assert all(row['passed'] for row in sql_result['checks'])
for name, digest in sql_result['source_bindings'].items():
    assert sha(Path(name)) == digest, name

destination.mkdir(parents=True)
shutil.copytree(integration / 'proof', destination / 'integration')
for name in ['verify.py', 'associate_canonical.py', 'seal_evidence.py']:
    copy_file(integration / name, destination / 'integration-tools' / name)
for name, digest in association['promoted_files'].items():
    assert sha(canonical / name) == digest, name
    copy_file(canonical / name, destination / 'final-source' / name)
shutil.copytree(integration / 'root-originals', destination / 'preserved-originals')
for name in ['HANDOFF.md', 'manifest.json', 'proof/accepted-receipt.json']:
    copy_file(original / name, destination / 'original-packet' / name)
for name, digest in original_receipt['proof_sha256'].items():
    assert sha(original / name) == digest, name
    copy_file(original / name, destination / 'original-packet' / name)
for name in ['HANDOFF.md', 'manifest.json', 'accepted-receipt.json']:
    copy_file(corrected / name, destination / 'corrected-sql' / name)
for name in corrected_manifest['members']:
    copy_file(corrected / name, destination / 'corrected-sql' / name)
shutil.copytree(corrected / 'sql-attempt6', destination / 'corrected-sql/sql-attempt6', dirs_exist_ok=True)
copy_file(corrected / 'sql-attempt6.log', destination / 'corrected-sql/sql-attempt6.log')
failure_pointers = {
    'scope': 'Full predecessor and rejected SQL/consumer attempts remain unchanged at these local private packets; selected accepted proof and failure metadata are copied here. This is a scoped integration packet, not a self-contained complete candidate.',
    'original_packet': str(original),
    'corrected_packet': str(corrected),
    'prior_root_review_packet': str(canonical / '.cache/admin-operational-history-root-review-20261002'),
    'prior_root_final_view_packet': str(canonical / '.cache/admin-operational-history-final-view-20261002'),
    'original_sql_attempts': original_manifest['retained_sql_attempts'],
    'corrected_sql_attempts': corrected_manifest['targets'],
    'counting': 'Do not sum predecessor, failed-command completed prefixes or overlapping scopes into the current passing 70-case command or 63-case SQL command.',
}
(destination / 'PRIVATE_PACKET_POINTERS.json').write_text(json.dumps(failure_pointers, indent=2) + '\n')
print(json.dumps({'status': 'copied_and_verified', 'destination': str(destination),
                  'final_source_files': len(association['promoted_files']),
                  'sql_checks': len(sql_result['checks']),
                  'current_consumer_inputs': association['canonical_consumer_and_fixture_count']}))
