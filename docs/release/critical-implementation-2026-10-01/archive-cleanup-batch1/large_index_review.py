#!/usr/bin/env python3
"""Stream the seven large metadata indexes skipped by concise report review."""
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
PREFIX = 'docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/'
first = json.loads((PACKET / 'first-batch-candidate-manifest.json').read_text())
candidate = {row['path']: {'sha256': row['sha256'], 'incoming': []} for row in first['files']}
bounded = json.loads((PACKET / 'bounded-link-review.json').read_text())
reports = []
errors = []
os.umask(0o077)
for row in bounded['skipped']:
    if row['reason'] != 'report_larger_than_5MiB':
        continue
    path = ROOT / row['path']
    try:
        if any((ROOT / Path(*Path(row['path']).parts[:count])).is_symlink() for count in range(1, len(Path(row['path']).parts) + 1)):
            raise ValueError('Aliased metadata index')
        before = path.stat()
        h = hashlib.sha256()
        count = 0
        with path.open('rb') as source:
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
        after = path.stat()
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError('Large metadata index changed during read')
        reports.append({'path': row['path'], 'sha256': h.hexdigest(), 'bytes_streamed': count})
    except (OSError, ValueError, UnicodeError) as error:
        errors.append({'path': row['path'], 'reason': type(error).__name__})
result = {'schema_version': 1, 'scope': 'Exactly the seven larger-than-5MiB metadata indexes skipped by bounded-link-review; streamed without copying bodies.',
          'index_files_selected': len(bounded['skipped']), 'index_files_read': len(reports), 'reports': reports,
          'candidates': [{'original_path': name, **item} for name, item in sorted(candidate.items())],
          'exact_path_or_digest_index_reference_count': sum(len(item['incoming']) for item in candidate.values()),
          'read_errors': errors, 'original_files_removed': 0}
(PACKET / 'large-index-consumers.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['index_files_selected', 'index_files_read', 'exact_path_or_digest_index_reference_count']}))
