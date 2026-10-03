#!/usr/bin/env python3
"""Map exact original cache paths/digests in bounded metadata indexes only."""
import gzip
import hashlib
import json
import os
import re
import stat
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
PREFIX = 'docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/'
first = json.loads((PACKET / 'first-batch-candidate-manifest.json').read_text())
candidate = {row['path']: {'sha256': row['sha256'], 'incoming': []} for row in first['files']}
selected = []
excluded_count = 0
extensions = {'.json', '.jsonl', '.tsv', '.csv', '.sha256', '.md'}
name_filter = re.compile(r'manifest|inventory|index|sha256|hash|verification|integrity|batch|receipt|source.*(before|after)|before.*source|after.*source|file[-_]?(list|table|catalog)|tree[-_]?(list|index)')
with gzip.open(PACKET / 'file-inventory.jsonl.gz', 'rt') as metadata:
    for line in metadata:
        row = json.loads(line)
        name = row['path']
        if Path(name).suffix.lower() not in extensions or not name_filter.search(Path(name).name.lower()):
            continue
        if any(marker in name for marker in ['/source-export/', '/source-snapshot/', '/source/', '/sources/', '/candidate/', '/prepared-source/', '/artifact/', '/build/', '/node_modules/', '/.dart_tool/']):
            excluded_count += 1
            continue
        selected.append(row)

reports = []
errors = []
directory_refs = []
os.umask(0o077)
for row in selected:
    path = ROOT / row['path']
    try:
        if any((ROOT / Path(*Path(row['path']).parts[:count])).is_symlink() for count in range(1, len(Path(row['path']).parts) + 1)):
            raise ValueError('Aliased metadata index path')
        before = path.stat()
        if not stat.S_ISREG(before.st_mode):
            raise ValueError('Regular index required')
        h = hashlib.sha256()
        with path.open('rb') as source:
            for number, line in enumerate(source, 1):
                h.update(line)
                text = line.decode('utf-8')
                if 'module-cache' not in text and not any(item['sha256'] in text for item in candidate.values()):
                    continue
                for name, item in candidate.items():
                    relative = name[len(PREFIX):]
                    local = relative.removeprefix('ios-source-compile1/')
                    exact = name in text
                    context_relative = row['path'].startswith(PREFIX) and (relative in text or local in text)
                    digest = item['sha256'] in text
                    if exact or context_relative or digest:
                        item['incoming'].append({'consumer': row['path'], 'line': number,
                            'match': 'exact_original_path' if exact else 'contextual_family_relative_path' if context_relative else 'exact_candidate_content_digest'})
                for tree in ['prior-module-cache', 'current-module-cache']:
                    if tree in text:
                        directory_refs.append({'consumer': row['path'], 'line': number, 'tree': tree,
                            'match': 'historical_tree_or_command_reference', 'applies_to': 'All manifest-listed descendants of this tree; retained command records remain immutable.'})
        after = path.stat()
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError('Metadata index changed during read')
        reports.append({'path': row['path'], 'sha256': h.hexdigest(), 'bytes': before.st_size})
    except (OSError, ValueError, UnicodeError) as error:
        errors.append({'path': row['path'], 'reason': type(error).__name__})

for name, item in candidate.items():
    tree = 'prior-module-cache' if '/prior-module-cache/' in name else 'current-module-cache'
    item['incoming_tree_consumers'] = [ref for ref in directory_refs if ref['tree'] == tree]
    item['new_exact_original_path_indexes'] = [
        'file-inventory.jsonl.gz (original metadata row)', 'bounded-duplicates.json',
        'first-batch-candidate-manifest.json', 'bounded-link-review.json (second source readback)',
        'exact-index-consumers.json (this path mapping)']
    item['required_future_resolution'] = 'Retain original report/index bytes; append immutable relocation mapping from this exact original path+SHA+size to exact encrypted repository+snapshot+snapshot-path. Verify every incoming indexed path/digest resolves through that mapping before any original removal.'

result = {'schema_version': 1, 'finished_at_utc': datetime.now(timezone.utc).isoformat(),
          'scope': 'Census-selected release report/index/manifest/hash/inventory/verification filenames, streamed without copying bodies; copied-source, generated-build and dependency subtrees excluded.',
          'index_files_selected': len(selected), 'index_files_read': len(reports), 'index_files_read_bytes': sum(row['bytes'] for row in reports),
          'excluded_copied_source_or_generated_index_count': excluded_count,
          'reports': reports, 'read_errors': errors,
          'candidate_count': len(candidate), 'candidates': [{'original_path': name, **item} for name, item in sorted(candidate.items())],
          'exact_path_or_digest_index_reference_count': sum(len(item['incoming']) for item in candidate.values()),
          'historical_directory_references': directory_refs,
          'all_arbitrary_incoming_links_verified': False,
          'unresolved_limits': ['Computed paths and differently named indexes, excluded deep copied/generated manifests and newly written evidence after the census are outside this bounded scan.',
              'Do not rewrite original indexed evidence or allow a hash-only mapping to erase the original path/epoch semantics.',
              'Future removal needs root review plus complete relevant incoming-index resolution test against the selected frozen evidence cohort; no filesystem symlink/stub may pretend to be original bytes.'],
          'original_removal_authorized': False, 'archive_created': False, 'restore_verified': False}
(PACKET / 'exact-index-consumers.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['index_files_selected', 'index_files_read', 'index_files_read_bytes', 'candidate_count', 'exact_path_or_digest_index_reference_count']}))
