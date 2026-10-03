#!/usr/bin/env python3
"""Check bounded compressed metadata indexes without extracting evidence."""
import gzip
import hashlib
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
PREFIX = 'docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/'
first = json.loads((PACKET / 'first-batch-candidate-manifest.json').read_text())
candidate = {row['path']: {'sha256': row['sha256'], 'incoming': []} for row in first['files']}
selected = []
with gzip.open(PACKET / 'file-inventory.jsonl.gz', 'rt') as metadata:
    for line in metadata:
        row = json.loads(line)
        name = row['path']
        if not name.endswith(('.json.gz', '.jsonl.gz', '.tsv.gz', '.csv.gz', '.sha256.gz')):
            continue
        if any(marker in name for marker in ['/source-export/', '/source-snapshot/', '/source/', '/sources/', '/candidate/', '/prepared-source/', '/artifact/', '/build/', '/node_modules/', '/.dart_tool/']):
            continue
        if re.search(r'manifest|inventory|index|sha256|hash|verification|integrity|source|file[-_]?(list|table|catalog)|tree[-_]?(list|index)', Path(name).name.lower()):
            selected.append(row)
os.umask(0o077)
reports = []
errors = []
for row in selected:
    path = ROOT / row['path']
    try:
        if any((ROOT / Path(*Path(row['path']).parts[:count])).is_symlink() for count in range(1, len(Path(row['path']).parts) + 1)):
            raise ValueError('Aliased compressed index')
        before = path.stat()
        h = hashlib.sha256()
        count = 0
        with gzip.open(path, 'rb') as source:
            for number, line in enumerate(source, 1):
                h.update(line)
                count += len(line)
                text = line.decode('utf-8')
                if 'module-cache' not in text and not any(item['sha256'] in text for item in candidate.values()):
                    continue
                for name, item in candidate.items():
                    relative = name[len(PREFIX):]
                    exact = name in text
                    context_relative = row['path'].startswith(PREFIX) and (relative in text or relative.removeprefix('ios-source-compile1/') in text)
                    digest = item['sha256'] in text
                    if exact or context_relative or digest:
                        item['incoming'].append({'consumer': row['path'], 'line': number,
                            'match': 'exact_original_path' if exact else 'contextual_family_relative_path' if context_relative else 'exact_candidate_content_digest'})
        with path.open('rb') as stored:
            stored_hash = hashlib.file_digest(stored, 'sha256').hexdigest()
        after = path.stat()
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError('Compressed index changed during read')
        reports.append({'path': row['path'], 'stored_sha256': stored_hash, 'stored_bytes': before.st_size,
                        'decompressed_sha256': h.hexdigest(), 'decompressed_bytes_streamed': count})
    except (OSError, ValueError, UnicodeError) as error:
        errors.append({'path': row['path'], 'reason': type(error).__name__})
result = {'schema_version': 1, 'scope': 'Compressed text metadata manifest/index/inventory filenames in recorded docs/release census, excluding copied source/generated/dependency subtrees; no filesystem extraction.',
    'index_files_selected': len(selected), 'index_files_read': len(reports), 'reports': reports,
    'candidates': [{'original_path': name, **item} for name, item in sorted(candidate.items())],
    'exact_path_or_digest_index_reference_count': sum(len(item['incoming']) for item in candidate.values()),
    'read_errors': errors, 'extracted_files': 0, 'original_files_removed': 0,
    'limits': ['Every future removed path still needs immutable original-path relocation/restore mapping; these compressed indexes must retain their original stored and decompressed hashes.',
               'Not a claim of arbitrary computed/unnamed/deep copied-source index completeness.']}
(PACKET / 'compressed-index-consumers.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['index_files_selected', 'index_files_read', 'exact_path_or_digest_index_reference_count']}))
