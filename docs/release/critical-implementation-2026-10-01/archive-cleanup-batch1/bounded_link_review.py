#!/usr/bin/env python3
"""Bounded reference inventory and source readback; never copy report bodies."""
import gzip
import hashlib
import json
import os
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
PREFIX = 'docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/'
MARKERS = ['prior-module-cache', 'current-module-cache', 'firebase-scene-compatibility-attempt21']
extensions = {'.json', '.jsonl', '.md', '.txt', '.stdout', '.stderr', '.d', '.resp', '.tsv'}
files = []
skipped = []
refs = []
errors = []
os.umask(0o077)
with gzip.open(PACKET / 'file-inventory.jsonl.gz', 'rt') as source:
    for line in source:
        row = json.loads(line)
        name = row['path']
        # Dated family, all concise reports in its parent cohort, root reports,
        # and original critical review. No other copied source/global discovery.
        relative = Path(name).relative_to('docs/release')
        inside = name.startswith('docs/release/asset-build-hygiene-2026-09-30/') or name.startswith('docs/release/critical-review-2026-10-01/') or len(relative.parts) == 1
        if not inside or Path(name).suffix.lower() not in extensions:
            continue
        if row['logical_bytes'] > 5 * 1048576:
            skipped.append({'path': name, 'reason': 'report_larger_than_5MiB'})
            continue
        path = ROOT / name
        try:
            if any((ROOT / Path(*Path(name).parts[:count])).is_symlink() for count in range(1, len(Path(name).parts) + 1)):
                raise ValueError('Aliased report path')
            before = path.stat()
            if not stat.S_ISREG(before.st_mode):
                raise ValueError('Regular report required')
            data = path.read_bytes()
            after = path.stat()
            if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
                raise ValueError('Report changed during bounded read')
            files.append({'path': name, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
            text = data.decode('utf-8')
            for number, body in enumerate(text.splitlines(), 1):
                hits = [marker for marker in MARKERS if marker in body]
                if hits:
                    refs.append({'path': name, 'line': number, 'matched_markers': hits,
                                 'role': 'compiler_dependency_path' if path.suffix == '.d' else 'historical_command_or_evidence_reference_needs_preserved_mapping'})
        except (OSError, ValueError, UnicodeError) as error:
            errors.append({'path': name, 'reason': type(error).__name__})

first = json.loads((PACKET / 'first-batch-candidate-manifest.json').read_text())
names = [row['path'] for row in first['files']]
ignored = subprocess.run(['git', 'check-ignore', '--stdin', '-z'], input=b'\0'.join(os.fsencode(name) for name in names) + b'\0', cwd=ROOT, capture_output=True, check=False)
if ignored.returncode not in (0, 1):
    raise ValueError('git check-ignore failed')
ignored_paths = sorted(os.fsdecode(name) for name in ignored.stdout.split(b'\0') if name)
tracked = subprocess.check_output(['git', 'ls-files', '-z', '--', PREFIX + 'ios-source-compile1/'], cwd=ROOT)
tracked_paths = sorted(os.fsdecode(name) for name in tracked.split(b'\0') if name)
candidate_tracked = sorted(set(names) & set(tracked_paths))

# Independent first-batch full readback with another implementation.
readback = []
for row in first['files']:
    path = ROOT / row['path']
    with path.open('rb') as handle:
        actual = hashlib.file_digest(handle, 'sha256').hexdigest()
    st = path.stat()
    ok = actual == row['sha256'] and st.st_size == row['logical_bytes'] and stat.S_IMODE(st.st_mode) == row['mode']
    readback.append({'path': row['path'], 'sha256': actual, 'bytes': st.st_size, 'mode': stat.S_IMODE(st.st_mode), 'matches_original_manifest': ok})
    if not ok:
        raise ValueError('First-batch source changed after original bounded hashing')

current = json.loads((ROOT / 'docs/release/public-website-current-content-contract.json').read_text())
contract_refs = []
for key in ['current_comparison_file']:
    if key in current:
        name = current[key]
        path = ROOT / name
        contract_refs.append({'origin': 'docs/release/public-website-current-content-contract.json', 'key': key, 'target': name,
                              'exists': path.is_file(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None})

result = {'schema_version': 1, 'finished_at_utc': datetime.now(timezone.utc).isoformat(),
          'scope': 'Metadata-selected concise root release reports, asset-build-hygiene report/text/metadata family and original critical-review reports only. Maintained consumers indexed separately.',
          'report_files_read': len(files), 'reports': files, 'references': refs, 'read_errors': errors, 'skipped': skipped,
          'first_batch_git_ignored_count': len(set(names) & set(ignored_paths)), 'first_batch_tracked_count': len(candidate_tracked),
          'first_batch_tracked_paths': candidate_tracked, 'first_batch_independent_full_source_hash_readback': readback,
          'current_public_comparison_reference': contract_refs,
          'limits': ['No arbitrary global incoming-link proof; other release families, binary/deep generated content and computed references remain outside this bounded review.',
                     'Ignored/untracked status does not authorize disposal. Historical paths must resolve through a durable original-path archive index after any future move.',
                     'This is a second source hash check, not restoration from an archive.'],
          'archive_created': False, 'independent_restore_verified': False, 'original_files_removed': 0}
(PACKET / 'bounded-link-review.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ['report_files_read', 'first_batch_git_ignored_count', 'first_batch_tracked_count', 'archive_created', 'original_files_removed']}))
