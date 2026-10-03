#!/usr/bin/env python3
"""Seal only independent safe top-level leaves once; fixtures live outside packet."""
import hashlib
import json
import os
import stat
from pathlib import Path

HERE = Path(__file__).resolve().parent


def body(path):
    if path.resolve() != path:
        raise ValueError('safe packet leaf alias refused')
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError('safe packet leaf must be independent regular file')
    data = path.read_bytes()
    after = path.lstat()
    attrs = ('st_dev', 'st_ino', 'st_size', 'st_mode', 'st_nlink', 'st_mtime_ns', 'st_ctime_ns')
    if any(getattr(before, attr) != getattr(after, attr) for attr in attrs):
        raise ValueError('safe packet input changed during seal')
    return data


def write(path, data):
    with path.open('xb') as output:
        output.write(data); output.flush(); os.fsync(output.fileno())


def main():
    if any((HERE/name).exists() or (HERE/name).is_symlink() for name in ('packet-files.json', 'sha256sums.txt')):
        raise ValueError('new seal outputs must be absent; no replacement')
    paths = []
    for path in sorted(HERE.iterdir()):
        if not path.is_file() or path.is_symlink():
            raise ValueError('unexpected unsafe/unlisted proposal entry')
        paths.append(path)
    digests = {path.name: hashlib.sha256(body(path)).hexdigest() for path in paths}
    manifest = {'kind': 'private_native_snapshot_controller_phase_artifact_preparation', 'files': digests,
                'synthetic_test_fixtures_internal_temp_and_removed': True,
                'real_app_export_pub_Gradle_native_executed_by_this_preparation': False,
                'prior_actual_export_attempt1_remains_failed': True,
                'root_review_or_actual_export_admission_issued': False, 'production_ready': False}
    manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True)+'\n').encode()
    write(HERE/'packet-files.json', manifest_bytes)
    all_digests = dict(digests, **{'packet-files.json': hashlib.sha256(manifest_bytes).hexdigest()})
    write(HERE/'sha256sums.txt', ''.join(digest+'  '+name+'\n' for name,digest in sorted(all_digests.items())).encode())
    for name, digest in all_digests.items():
        if hashlib.sha256(body(HERE/name)).hexdigest() != digest:
            raise ValueError('actual sealed leaf changed at final readback')
    print(json.dumps({'checked_safe_leaves': len(digests), 'checksum_rows': len(all_digests),
                      'packet_manifest_sha256': all_digests['packet-files.json'],
                      'proposed_controller_sha256': digests['run_native_consumer.py'],
                      'internal_test_fixtures_removed': True, 'real_app_export_or_build_executed_by_this_preparation': False}))


if __name__ == '__main__':
    raise SystemExit(main())
