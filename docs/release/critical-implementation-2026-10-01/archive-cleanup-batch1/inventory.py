#!/usr/bin/env python3
"""Metadata-only release-tree census, with no symlink traversal or removals."""
import collections
import hashlib
import json
import os
import stat
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
TREE = ROOT / 'docs/release'


def classify(name):
    lower = '/' + name.lower() + '/'
    if any(marker in lower for marker in ['/.gradle/', '/vendor/bundle/', '/.dart_tool/', '/node_modules/', '/pods/', '/deriveddata/']) or '-module-cache/' in lower:
        return 'dependency_or_compiler_cache'
    if any(marker in lower for marker in ['/artifact/', '/admin-build/', '/public-build/', '/build/web/', '/build/ios/', '.app/', '.xcarchive/']):
        return 'compiled_or_packaged_artifact'
    if any(marker in lower for marker in ['/source/', '/candidate/', '/sources/', '/source-prepared/', '/source-original/', '/prepared-source/']):
        return 'copied_source_or_candidate_tree'
    suffix = Path(name).suffix.lower()
    if suffix in {'.png', '.jpg', '.jpeg', '.webp', '.gif'}:
        return 'image_or_visual_evidence'
    if suffix in {'.json', '.jsonl', '.ndjson', '.yaml', '.yml', '.csv', '.tsv', '.sha256'}:
        return 'structured_report_manifest_or_data'
    if suffix in {'.md', '.html', '.pdf'}:
        return 'report_document_or_page'
    if suffix in {'.log', '.stdout', '.stderr', '.txt'}:
        return 'execution_log_or_text_evidence'
    if suffix in {'.apk', '.aab', '.ipa', '.zip', '.tar', '.gz', '.tgz', '.wasm', '.o', '.a', '.class', '.jar', '.pcm', '.pch', '.so', '.dylib', '.ttf', '.woff', '.woff2'}:
        return 'binary_archive_or_generated_component'
    if suffix in {'.dart', '.rb', '.py', '.js', '.ts', '.mjs', '.cjs', '.sql', '.sh', '.swift', '.kt', '.java', '.c', '.h', '.cc', '.cpp'}:
        return 'authored_or_copied_code_unclassified'
    return 'other_unclassified'


os.umask(0o077)
started = datetime.now(timezone.utc).isoformat()
stack = [TREE]
classes = collections.defaultdict(lambda: {'files': 0, 'logical_bytes': 0, 'allocated_bytes': 0})
top = collections.defaultdict(lambda: {'files': 0, 'logical_bytes': 0})
depth3 = collections.defaultdict(lambda: {'files': 0, 'logical_bytes': 0})
largest = []
errors = []
symlinks = []
special = []
directories = 0
count = 0
inventory = PACKET / 'file-inventory.jsonl'
with inventory.open('w') as out:
    while stack:
        directory = stack.pop()
        try:
            entries = sorted(os.scandir(directory), key=lambda entry: entry.name)
        except OSError as error:
            errors.append({'path': str(directory.relative_to(ROOT)), 'operation': 'scandir', 'error_type': type(error).__name__, 'errno': error.errno})
            continue
        for entry in entries:
            path = Path(entry.path)
            if path == PACKET:
                continue
            relative = path.relative_to(ROOT).as_posix()
            try:
                info = entry.stat(follow_symlinks=False)
            except OSError as error:
                errors.append({'path': relative, 'operation': 'lstat', 'error_type': type(error).__name__, 'errno': error.errno})
                continue
            if stat.S_ISDIR(info.st_mode):
                directories += 1
                stack.append(path)
                continue
            if stat.S_ISLNK(info.st_mode):
                try:
                    target = os.readlink(path)
                    target_hash = hashlib.sha256(os.fsencode(target)).hexdigest()
                    exists = path.exists()
                    symlinks.append({'path': relative, 'target_text_sha256': target_hash, 'target_is_absolute': target.startswith('/'), 'target_exists_at_readback': exists, 'followed': False})
                except OSError as error:
                    errors.append({'path': relative, 'operation': 'readlink', 'error_type': type(error).__name__, 'errno': error.errno})
                continue
            if not stat.S_ISREG(info.st_mode):
                special.append({'path': relative, 'mode': info.st_mode})
                continue
            name = path.relative_to(TREE).as_posix()
            category = classify(name)
            blocks = getattr(info, 'st_blocks', 0) * 512
            row = {'path': relative, 'logical_bytes': info.st_size, 'allocated_bytes': blocks, 'mode': stat.S_IMODE(info.st_mode),
                   'mtime_ns': info.st_mtime_ns, 'device': str(info.st_dev), 'inode': str(info.st_ino), 'nlink': info.st_nlink,
                   'class': category, 'classification_method': 'path/extension heuristic; content, uniqueness and discardability not inferred'}
            out.write(json.dumps(row, separators=(',', ':')) + '\n')
            count += 1
            classes[category]['files'] += 1
            classes[category]['logical_bytes'] += info.st_size
            classes[category]['allocated_bytes'] += blocks
            for key, cohort in [(name.split('/')[0], top), ('/'.join(name.split('/')[:3]), depth3)]:
                cohort[key]['files'] += 1
                cohort[key]['logical_bytes'] += info.st_size
            largest.append((info.st_size, relative))
            if len(largest) > 1200:
                largest = sorted(largest, reverse=True)[:100]
largest = sorted(largest, reverse=True)[:100]
result = {'schema_version': 1, 'status': 'metadata_inventory_complete_with_explicit_limits', 'started_at_utc': started,
          'finished_at_utc': datetime.now(timezone.utc).isoformat(), 'root': str(TREE), 'regular_file_count': count,
          'directory_count': directories, 'logical_bytes': sum(item['logical_bytes'] for item in classes.values()),
          'allocated_bytes_sum_not_physical_unique': sum(item['allocated_bytes'] for item in classes.values()),
          'classes': dict(sorted(classes.items())), 'top_level_cohorts': dict(sorted(top.items())),
          'largest_depth3_cohorts': sorted([{'path': key, **value} for key, value in depth3.items()], key=lambda row: row['logical_bytes'], reverse=True)[:80],
          'largest_files': [{'path': name, 'logical_bytes': size} for size, name in largest],
          'symlink_count': len(symlinks), 'symlinks': symlinks, 'special_entries': special, 'read_errors': errors,
          'excluded_paths': [str(PACKET.relative_to(ROOT))],
          'limits': ['Single live metadata census; other workers can create/modify evidence during traversal.', 'Symlink targets inventoried by hash/existence but never traversed.', 'File bodies not opened; no blanket content hashes, customer/secret scan, ownership or retention classification inferred.', 'Allocated bytes can double count hardlinks/APFS clones; logical bytes do not equal space safely reclaimable.', 'Own packet excluded to avoid self-counting; Git ignored content included.'],
          'inventory_sha256': hashlib.sha256(inventory.read_bytes()).hexdigest(), 'removed_files': 0}
(PACKET / 'inventory-summary.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['regular_file_count', 'directory_count', 'logical_bytes', 'symlink_count', 'inventory_sha256']}))
