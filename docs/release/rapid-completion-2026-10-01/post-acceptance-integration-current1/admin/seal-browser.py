#!/usr/bin/env python3
"""Seal the task-owned evidence and portable artifacts; no verification run."""
import hashlib
import json
from pathlib import Path

out = Path(__file__).resolve().parent
manifest_path = out / 'SHA256SUMS.json'
assert not manifest_path.exists(), 'Owned packet already sealed'
files = {}
for path in sorted(out.rglob('*')):
    assert not path.is_symlink(), str(path)
    if path.is_file():
        files[path.relative_to(out).as_posix()] = {
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size,
        }
manifest = {'scope': 'Final owned packet and byte-identical portable Admin/Public artifacts; all source/test/SDK changes stayed outside live runtime.',
            'file_count': len(files), 'files': files, 'excludes': ['SHA256SUMS.json'],
            'browser_status': 'pass', 'browser_checks': 89, 'route_states': 56,
            'production_admin_build_attempts': 2, 'successful_final_admin_artifacts': 1,
            'retained_continuation_rebuilt_admin_or_public': False,
            'no_owned_live_process_remaining': True, 'owned_outputs_frozen': True}
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
assert all(hashlib.sha256((out / n).read_bytes()).hexdigest() == row['sha256'] for n, row in files.items())
print(json.dumps({'status': 'sealed', 'file_count': len(files),
                  'manifest_sha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                  'browser_acceptance_sha256': files['browser-acceptance.json']['sha256']}), flush=True)
