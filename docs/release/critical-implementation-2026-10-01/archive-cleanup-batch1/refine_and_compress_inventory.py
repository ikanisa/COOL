#!/usr/bin/env python3
"""Refine new metadata output; retain exactly equivalent deterministic gzip."""
import collections
import gzip
import hashlib
import json
import os
from pathlib import Path

PACKET = Path(__file__).resolve().parent
os.umask(0o077)
raw = PACKET / 'file-inventory.jsonl'
compressed = PACKET / 'file-inventory.jsonl.gz'
summary = json.loads((PACKET / 'inventory-summary.json').read_text())
classes = collections.defaultdict(lambda: {'files': 0, 'logical_bytes': 0, 'allocated_bytes': 0})
transitions = collections.Counter()
hash_before = hashlib.sha256()
rows = 0
bytes_before = 0
with raw.open('rb') as source, compressed.open('xb') as target:
    with gzip.GzipFile(fileobj=target, mode='wb', filename='', mtime=0, compresslevel=9) as gz:
        for line in source:
            hash_before.update(line)
            bytes_before += len(line)
            rows += 1
            gz.write(line)
            row = json.loads(line)
            name = '/' + row['path'].lower() + '/'
            category = row['class']
            # Only refine metadata categories; no discardability is inferred.
            if any(marker in name for marker in ['/source-export/', '/source-snapshot/', '/sources-attempt', '/immutable-source/']):
                category = 'copied_source_or_candidate_tree'
            if any(marker in name for marker in ['/build/test_cache/', '/kernel_snapshot/', '/.cache.dill.track.dill/']):
                category = 'dependency_or_compiler_cache'
            transitions[(row['class'], category)] += 1
            for field in ['logical_bytes', 'allocated_bytes']:
                classes[category][field] += row[field]
            classes[category]['files'] += 1
hash_restored = hashlib.sha256()
restored_bytes = 0
restored_rows = 0
with raw.open('rb') as original, gzip.open(compressed, 'rb') as restored:
    for original_line in original:
        restored_line = restored.readline()
        if restored_line != original_line:
            raise ValueError('Decompressed byte mismatch; retain original')
        restored_bytes += len(restored_line)
        restored_rows += 1
        hash_restored.update(restored_line)
    if restored.read(1):
        raise ValueError('Unexpected decompressed trailing bytes; retain original')
assert rows == restored_rows == summary['regular_file_count']
assert bytes_before == restored_bytes
assert hash_before.hexdigest() == hash_restored.hexdigest() == summary['inventory_sha256']
assert sum(row['logical_bytes'] for row in classes.values()) == summary['logical_bytes']
result = {'schema_version': 1, 'status': 'new_metadata_output_compressed_with_full_byte_equality',
          'input_sha256': hash_before.hexdigest(), 'input_bytes': bytes_before, 'input_rows': rows,
          'compressed_path': compressed.name, 'compressed_bytes': compressed.stat().st_size,
          'compressed_sha256': hashlib.sha256(compressed.read_bytes()).hexdigest(),
          'decompressed_sha256': hash_restored.hexdigest(), 'decompressed_rows': restored_rows,
          'full_original_decompressed_byte_equality': True,
          'refined_classes': dict(sorted(classes.items())),
          'class_transitions': [{'from': old, 'to': new, 'files': count} for (old, new), count in sorted(transitions.items()) if old != new],
          'classification_method': 'Refined path/extension metadata heuristic only; class does not determine uniqueness, approval or discardability.',
          'root_authorized_own_raw_output_replacement': True,
          'original_release_files_removed': 0,
          'raw_new_output_removed_after_equality_proof': False}
(PACKET / 'inventory-representation.json').write_text(json.dumps(result, indent=2) + '\n')
# Parent explicitly approved removal only of our new raw metadata output.
raw.unlink()
result['raw_new_output_removed_after_equality_proof'] = True
(PACKET / 'inventory-representation.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['input_rows', 'input_bytes', 'compressed_bytes', 'input_sha256', 'full_original_decompressed_byte_equality']}))
