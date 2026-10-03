#!/usr/bin/env python3
"""Seal a read-only review packet and recheck candidate originals, never delete."""
import ast
import gzip
import hashlib
import json
import os
import platform
import stat
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
os.umask(0o077)
def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

summary = json.loads((PACKET / 'inventory-summary.json').read_text())
representation = json.loads((PACKET / 'inventory-representation.json').read_text())
classes = json.loads((PACKET / 'class-refinement.json').read_text())
compressed = PACKET / 'file-inventory.jsonl.gz'
assert digest(compressed) == representation['compressed_sha256']
rows, logical_bytes, metadata_bytes = 0, 0, 0
h = hashlib.sha256()
with gzip.open(compressed, 'rb') as source:
    for line in source:
        h.update(line)
        metadata_bytes += len(line)
        rows += 1
        logical_bytes += json.loads(line)['logical_bytes']
assert h.hexdigest() == summary['inventory_sha256'] == representation['input_sha256']
assert rows == summary['regular_file_count'] == representation['input_rows']
assert logical_bytes == summary['logical_bytes'] == classes['logical_bytes']
assert metadata_bytes == representation['input_bytes']
assert not (PACKET / 'file-inventory.jsonl').exists()

first = json.loads((PACKET / 'first-batch-candidate-manifest.json').read_text())
candidate_readback = []
for row in first['files']:
    path = ROOT
    for part in row['path'].split('/'):
        assert part not in ('', '.', '..')
        path /= part
        assert not stat.S_ISLNK(os.lstat(path).st_mode)
    before = os.lstat(path)
    assert stat.S_ISREG(before.st_mode)
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    try:
        opened = os.fstat(fd)
        keys = lambda st: (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, stat.S_IMODE(st.st_mode))
        assert keys(opened) == keys(before)
        with os.fdopen(fd, 'rb', closefd=False) as source:
            actual = hashlib.file_digest(source, 'sha256').hexdigest()
        after = os.lstat(path)
        assert keys(before) == keys(after)
        assert actual == row['sha256'] and after.st_size == row['logical_bytes'] and stat.S_IMODE(after.st_mode) == row['mode']
        candidate_readback.append({'path': row['path'], 'sha256': actual, 'bytes': after.st_size, 'mode': stat.S_IMODE(after.st_mode), 'regular_unaliased_stable_read': True, 'matches_first_manifest': True})
    finally:
        os.close(fd)
assert len(candidate_readback) == 98
assert sum(row['bytes'] for row in candidate_readback) == 73167256
assert len({row['sha256'] for row in candidate_readback}) == 98

index_checks = {}
for name in ['exact-index-consumers.json', 'compressed-index-consumers.json', 'large-index-consumers.json']:
    receipt = json.loads((PACKET / name).read_text())
    assert not receipt['read_errors']
    assert receipt['index_files_selected'] == receipt['index_files_read']
    assert len(receipt['candidates']) == 98
    index_checks[name] = {'index_files_read': receipt['index_files_read'], 'candidate_count': 98,
                         'exact_path_or_digest_index_reference_count': receipt['exact_path_or_digest_index_reference_count'], 'read_errors': 0}

plans = [json.loads((PACKET / name).read_text()) for name in ['first-batch-plan.json', 'object-store-proposal.json', 'consumer-repair-matrix.json']]
assert plans[0]['original_files_removed'] == plans[0]['archives_created'] == plans[0]['independent_archive_restores_run'] == 0
assert plans[0]['ARC10_full_acceptance_met'] is False and plans[0]['original_removal_authorized'] is False
assert plans[0]['candidate_manifest_sha256'] == digest(PACKET / plans[0]['candidate_manifest'])
assert plans[0]['original_report_sha256'] == digest(ROOT / plans[0]['original_report'])
assert plans[1]['status'] == 'proposal_only_not_created'
syntax = []
for path in sorted(PACKET.glob('*.py')):
    ast.parse(path.read_text(), filename=path.name)
    syntax.append(path.name)

readback = {'schema_version': 1, 'verified_at_utc': datetime.now(timezone.utc).isoformat(), 'python_version': platform.python_version(),
    'status': 'read_only_inventory_and_proposal_verification_pass',
    'inventory_decompressed_sha256': h.hexdigest(), 'inventory_rows': rows, 'inventory_logical_bytes': logical_bytes,
    'full_original_decompressed_byte_equality_previously_verified_before_own_raw_removal': True,
    'final_candidate_source_readback': candidate_readback, 'candidate_unique_objects': 98,
    'index_checks': index_checks, 'python_syntax_checked': syntax,
    'source_payloads_preserved': True, 'archives_created': 0, 'independent_archive_restores_run': 0,
    'original_files_removed': 0, 'ARC10_full_acceptance_met': False,
    'limits': ['Third source hash/regular-file/alias/stability readback only; no archive exists and no archive restore has been executed.',
               'Inventory/consumer epochs are explicit; root/other workers continue unrelated valid source/evidence writes.',
               'Per-path bounded index mapping does not certify arbitrary computed/unnamed/deep copied-source link closure.']}
(PACKET / 'final-readback.json').write_text(json.dumps(readback, indent=2) + '\n')

artifacts = []
for path in sorted(PACKET.iterdir()):
    if path.name == 'batch.json':
        continue
    assert path.is_file() and not path.is_symlink()
    artifacts.append({'path': path.name, 'sha256': digest(path), 'bytes': path.stat().st_size})
batch = {'schema_version': 1, 'finding': 'ARC-10', 'sealed_at_utc': datetime.now(timezone.utc).isoformat(),
         'status': 'verified_read_only_inventory_and_concrete_preservation_first_plan',
         'report': 'README.md', 'artifacts': artifacts,
         'inventory_files': rows, 'inventory_logical_bytes': logical_bytes,
         'maintained_consumer_files': 153, 'bounded_hashed_files': 110,
         'exact_first_batch_paths': 98, 'first_batch_logical_bytes': 73167256,
         'first_batch_source_hash_readback_pass': True,
         'original_files_removed': 0, 'archives_created': 0, 'independent_archive_restores_run': 0,
         'original_removal_authorized': False, 'ARC10_full_acceptance_met': False,
         'clean_checkout_without_archive_verified': False, 'secret_customer_classification_complete': False,
         'all_arbitrary_incoming_links_verified': False, 'production_release_approved': False,
         'required_next_action': 'Root reviews exact source/index/consumer scope and pending access/retention/engine/backup choices before assigning preservation/restore work; removal remains unassigned.'}
(PACKET / 'batch.json').write_text(json.dumps(batch, indent=2) + '\n')
print(json.dumps({'status': readback['status'], 'candidate_paths': 98, 'inventory_rows': rows,
                  'artifacts': len(artifacts), 'batch_sha256': digest(PACKET / 'batch.json'), 'original_files_removed': 0}))
