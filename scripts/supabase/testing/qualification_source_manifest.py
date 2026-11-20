"""Capture source identity for synthetic SQL qualification; opens no services."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import stat

ROOT = Path(__file__).resolve().parents[3]
ROOTS = (
    'supabase/functions', 'supabase/migrations', 'supabase/jobs',
    'supabase/retention-inventory.json', 'deploy/collect-sms',
    'supabase/managed-migration-history/source-migrations.lock.json', 'scripts/supabase',
    'lib/shared/models', 'lib/core/data/exact_json_values.dart',
    'lib/shared/repositories/collect_repository_live_reader.dart',
    '.github/workflows/supabase.yml', '.fvmrc', 'pubspec.yaml', 'pubspec.lock',
)
SKIP = {'node_modules', '.git', '.temp', '.dart_tool', '__pycache__', '.DS_Store'}


def source_manifest(root=ROOT):
    root = Path(root)
    if not root.is_absolute() or root.resolve(strict=True) != root:
        raise ValueError('Physical source root required')
    files = []
    def visit(relative):
        path = root / relative
        before = path.lstat()
        if stat.S_ISLNK(before.st_mode):
            raise ValueError('Synthetic qualification refuses source links')
        if stat.S_ISDIR(before.st_mode):
            for entry in sorted(os.scandir(path), key=lambda entry: entry.name):
                if entry.name not in SKIP and not entry.name.startswith('._'):
                    visit(relative / entry.name)
            return
        if not stat.S_ISREG(before.st_mode) or before.st_size > 16 * 1024 * 1024:
            raise ValueError('Bounded regular source files required')
        data = path.read_bytes()
        after = path.lstat()
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError('Source changed during synthetic qualification')
        files.append({'path': relative.as_posix(), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
        if len(files) > 10000:
            raise ValueError('Source inventory is too large')
    for name in ROOTS:
        visit(Path(name))
    files.sort(key=lambda item: item['path'])
    raw = json.dumps(files, sort_keys=True, separators=(',', ':')).encode()
    return {'format': 'collect.supabase-cloud.qualification-source.v1', 'files': files, 'sha256': hashlib.sha256(raw).hexdigest()}


if __name__ == '__main__':
    print(json.dumps(source_manifest(), sort_keys=True, separators=(',', ':')))
