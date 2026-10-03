#!/usr/bin/env python3
"""Refine metadata hierarchy with caches/artifacts preceding copied-source class."""
import collections
import gzip
import json
from pathlib import Path

PACKET = Path(__file__).resolve().parent
summary = json.loads((PACKET / 'inventory-summary.json').read_text())
classes = collections.defaultdict(lambda: {'files': 0, 'logical_bytes': 0, 'allocated_bytes': 0})
count = 0
with gzip.open(PACKET / 'file-inventory.jsonl.gz', 'rt') as source:
    for line in source:
        row = json.loads(line)
        name = '/' + row['path'].lower() + '/'
        category = row['class']
        if category == 'dependency_or_compiler_cache' or any(marker in name for marker in ['/build/test_cache/', '/kernel_snapshot/', '/.cache.dill.track.dill/']):
            category = 'dependency_or_compiler_cache'
        elif category == 'compiled_or_packaged_artifact':
            pass
        elif any(marker in name for marker in ['/source-export/', '/source-snapshot/', '/sources-attempt', '/immutable-source/']):
            category = 'copied_source_or_candidate_tree'
        for field in ['logical_bytes', 'allocated_bytes']:
            classes[category][field] += row[field]
        classes[category]['files'] += 1
        count += 1
assert count == summary['regular_file_count']
assert sum(item['logical_bytes'] for item in classes.values()) == summary['logical_bytes']
(PACKET / 'class-refinement.json').write_text(json.dumps({
    'schema_version': 1, 'input_uncompressed_sha256': summary['inventory_sha256'], 'file_count': count,
    'logical_bytes': summary['logical_bytes'], 'classes': dict(sorted(classes.items())),
    'priority': 'Explicit dependency/compiler cache then compiled artifact then copied-source tree then extension heuristic.',
    'supersedes_only_preliminary_class_totals_in': 'inventory-representation.json',
    'reason': 'Keep dependency/cache descendants classified as cache even inside a copied-source tree; byte-equivalent original metadata inventory unchanged.',
    'method': 'Metadata-only path heuristic; content uniqueness, approval, reproducibility and discardability not inferred.'
}, indent=2) + '\n')
print(json.dumps(dict(sorted(classes.items()))))
