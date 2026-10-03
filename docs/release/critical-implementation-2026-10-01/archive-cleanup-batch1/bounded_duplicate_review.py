#!/usr/bin/env python3
"""Hash only explicit bounded candidate cohorts; never relocate or remove files."""
import collections
import gzip
import hashlib
import json
import os
import stat
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
MODULE_PREFIX = 'docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/ios-source-compile1/'
NATIVE_PREFIX = 'docs/release/native-gateway-observation-2026-10-01/root197-correction/'
COPIES = [
    'docs/release/data-correctness-2026-09-30/immutable-attempt21-current-calendar/source-export/',
    'docs/release/data-correctness-2026-09-30/immutable-attempt22-current167-sql-bridge/source-export/',
]
rows = []
inventory = PACKET / 'file-inventory.jsonl'
metadata = inventory.open() if inventory.exists() else gzip.open(PACKET / 'file-inventory.jsonl.gz', 'rt')
for line in metadata:
    row = json.loads(line)
    name = row['path']
    if name.startswith(MODULE_PREFIX) and '-module-cache/' in name:
        row['bounded_set'] = 'historical_compiler_module_caches_first_batch'
    elif name.startswith(NATIVE_PREFIX) and Path(name).name in {'prior-app-production-release.apk', 'prior-app-production-release-unsigned.apk'}:
        row['bounded_set'] = 'active_native_prior_artifact_duplicates_defer'
    elif any(name.startswith(prefix) for prefix in COPIES) and name.split('/source-export/', 1)[-1] in {'pubspec.lock', 'assets/typefaces/Inter-Variable.ttf', 'lib/core/theme/collect_theme.dart'}:
        row['bounded_set'] = 'two_dated_source_exports_selected_common_inputs_preserve'
    else:
        continue
    rows.append(row)
metadata.close()


def digest(name):
    path = ROOT
    for part in name.split('/'):
        path /= part
        if path.is_symlink():
            raise ValueError('Aliased candidate path')
    before = path.stat()
    if not stat.S_ISREG(before.st_mode):
        raise ValueError('Regular candidate required')
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    try:
        opened = os.fstat(fd)
        if (opened.st_ino, opened.st_size, opened.st_mtime_ns) != (before.st_ino, before.st_size, before.st_mtime_ns):
            raise ValueError('Candidate changed before hashing')
        h = hashlib.sha256()
        with os.fdopen(fd, 'rb', closefd=False) as handle:
            for block in iter(lambda: handle.read(1048576), b''):
                h.update(block)
        after = path.stat()
        if (after.st_ino, after.st_size, after.st_mtime_ns) != (before.st_ino, before.st_size, before.st_mtime_ns):
            raise ValueError('Candidate changed during hashing')
        return h.hexdigest()
    finally:
        os.close(fd)


errors = []
hashed = []
for row in sorted(rows, key=lambda item: item['path']):
    try:
        row['sha256'] = digest(row['path'])
        row['logical_size_readback_matches_inventory'] = (ROOT / row['path']).stat().st_size == row['logical_bytes']
        if not row['logical_size_readback_matches_inventory']:
            raise ValueError('Size changed since inventory')
        hashed.append(row)
    except (OSError, ValueError) as error:
        errors.append({'path': row['path'], 'error_type': type(error).__name__, 'reason': str(error) if isinstance(error, ValueError) else 'OS read error'})
by_hash = collections.defaultdict(list)
by_name = collections.defaultdict(list)
for row in hashed:
    by_hash[(row['sha256'], row['logical_bytes'])].append(row)
    by_name[(row['bounded_set'], Path(row['path']).name)].append(row)
duplicates = [{'sha256': key[0], 'logical_bytes_each': key[1], 'paths': [row['path'] for row in group],
               'redundant_copy_logical_bytes': (len(group) - 1) * key[1],
               'interpretation': 'Exact byte duplicates only; distinct path/epoch/provenance and restore obligations remain.'}
              for key, group in sorted(by_hash.items()) if len(group) > 1]
different_same_names = [{'set': key[0], 'basename': key[1], 'paths': [row['path'] for row in group], 'unique_sha256': len({row['sha256'] for row in group})}
                        for key, group in sorted(by_name.items()) if len({row['sha256'] for row in group}) > 1]
first = [row for row in hashed if row['bounded_set'] == 'historical_compiler_module_caches_first_batch']
result = {'schema_version': 1, 'scope': 'Exactly two historical compiler-module cache trees, prior APKs under one active native cohort (deferred), and three named inputs in two dated source exports (preserved). No broad source/global/archive hashing.',
          'hashed_file_count': len(hashed), 'hashed_logical_bytes': sum(row['logical_bytes'] for row in hashed), 'files': hashed,
          'exact_duplicate_groups': duplicates, 'different_content_same_basename_groups': different_same_names, 'read_errors': errors,
          'first_batch_candidate_count': len(first), 'first_batch_logical_bytes': sum(row['logical_bytes'] for row in first),
          'first_batch_unique_objects': len({row['sha256'] for row in first}),
          'first_batch_unique_object_logical_bytes': sum(key[1] for key, group in by_hash.items() if any(row in first for row in group)),
          'removed_files': 0, 'archive_objects_created': 0, 'restore_verified': False,
          'limits': ['Candidates retain unique bytes and original path/source/toolchain provenance.', 'APK equality does not verify signing, legitimacy or release approval.', 'No archive implementation or deletion authority granted by this review.']}
(PACKET / 'bounded-duplicates.json').write_text(json.dumps(result, indent=2) + '\n')
(PACKET / 'first-batch-candidate-manifest.json').write_text(json.dumps({'status': 'proposed_preserve_then_verify_then_reassign_removal', 'prefix': MODULE_PREFIX,
    'files': first, 'file_count': len(first), 'logical_bytes': sum(row['logical_bytes'] for row in first), 'archive_created': False, 'restoration_verified': False, 'removal_authorized': False}, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['hashed_file_count', 'hashed_logical_bytes', 'first_batch_candidate_count', 'first_batch_logical_bytes', 'first_batch_unique_objects']}))
