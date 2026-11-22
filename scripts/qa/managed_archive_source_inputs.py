"""Check the original v3 managed archive inputs after moving a checkout. Runs no archive code."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import sys

from release_tree_custody import CHUNK, output, source_digests


MANIFEST = 'scripts/supabase/managed-archive-operator/v3/SOURCE-PINS.json'
MANIFEST_SHA256 = '7cb8035606dd9a7e0e64ac0e6ae7f210eb6f8ffef83fb35f10f62cb861b9a5db'
SOURCE_REVISION = '8e12ee13d6487dd2a9489fb08f162f183ef4aa3d'
ORIGINAL = PurePosixPath('/Volumes/COLLECT-STAGING-20261109/main-source')
MODULES = ORIGINAL / 'scripts/supabase/node_modules'
MAX_FILE = 256 * 1024 * 1024
MAX_TOTAL = 512 * 1024 * 1024


def committed_entries(repository, commit, paths):
    records = output(repository, '--literal-pathspecs', 'ls-tree', '-lz', commit, '--', *paths)
    result = {}
    for record in records.split(b'\0'):
        if record:
            head, raw_name = record.split(b'\t', 1)
            mode, kind, blob, size = head.decode('ascii').split()
            name = os.fsdecode(raw_name)
            result[name] = (name, mode, blob, int(size)) if (
                kind == 'blob' and mode in ('100644', '100755') and int(size) <= MAX_FILE) else None
    return result


def file_identity(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


def physical_file(path):
    """Read one bounded regular file, rejecting links, substitutions and changes during the read."""
    try:
        if path.resolve(strict=True) != path:
            return 'not_physical', None, 0
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            before = os.fstat(fd)
            if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_FILE:
                return 'invalid_file', None, 0
            digest = hashlib.sha256()
            remaining = before.st_size
            while remaining:
                chunk = os.read(fd, min(remaining, CHUNK))
                if not chunk:
                    return 'changed_during_read', None, 0
                digest.update(chunk)
                remaining -= len(chunk)
            if (os.read(fd, 1) or file_identity(before) != file_identity(os.fstat(fd)) or
                    file_identity(before) != file_identity(path.lstat()) or path.resolve(strict=True) != path):
                return 'changed_during_read', None, 0
            return 'verified', digest.hexdigest(), before.st_size
        finally:
            os.close(fd)
    except FileNotFoundError:
        return 'missing', None, 0
    except (OSError, RuntimeError):
        return 'unreadable', None, 0


def inventory(repository, revision, modules, replacements, show_inputs=False):
    commit = output(repository, 'rev-parse', '--verify', '--end-of-options', revision + '^{commit}').decode().strip()
    manifest = output(repository, 'cat-file', 'blob', commit + ':' + MANIFEST)
    if hashlib.sha256(manifest).hexdigest() != MANIFEST_SHA256:
        raise ValueError('Historical v3 manifest digest differs')
    pins = json.loads(manifest)['inputs']
    paths = [PurePosixPath(row['path']) for row in pins]
    external = {str(path) for path in paths if not path.is_relative_to(ORIGINAL)}
    mapped = dict(replacements)
    if len(mapped) != len(replacements) or not mapped.keys() <= external:
        raise ValueError('Only a unique external path from the original manifest can be remapped')
    tracked = [str(path.relative_to(ORIGINAL)) for path in paths
               if path.is_relative_to(ORIGINAL) and not path.is_relative_to(MODULES)]
    entries = committed_entries(repository, commit, tracked)
    files = [entry for entry in entries.values() if entry]
    if sum(entry[3] for entry in files) > MAX_TOTAL:
        raise ValueError('Selected Git inputs exceed the archive size limit')
    hashes = source_digests(repository, files, None)
    counts, verified_bytes = defaultdict(Counter), 0
    unresolved, inputs = [], []
    for path, pin in zip(paths, pins):
        name = str(path)
        if path.is_relative_to(MODULES):
            group = 'npm'
            source = modules.absolute() / path.relative_to(MODULES)
            status, actual, size = physical_file(source)
        elif path.is_relative_to(ORIGINAL):
            group = 'git'
            source = str(path.relative_to(ORIGINAL))
            entry = entries.get(source)
            if entry:
                _, _, blob, size = entry
                status, actual = 'verified', hashes[blob]
            else:
                status, actual, size = ('invalid_file' if source in entries else 'missing'), None, 0
        else:
            group = 'external'
            source = Path(mapped.get(name, name)).absolute()
            status, actual, size = physical_file(source)
        if status == 'verified' and actual != pin['sha256']:
            status = 'digest_mismatch'
        counts[group][status] += 1
        row = {'original': name, 'source': str(source), 'kind': group,
               'expected_sha256': pin['sha256'], 'status': status}
        if status != 'verified':
            unresolved.append(row)
        else:
            verified_bytes += size
            if verified_bytes > MAX_TOTAL:
                raise ValueError('Original manifest verification size exceeds its limit')
        if show_inputs:
            inputs.append(row)
    report = {'format': 'collect.managed-archive.source-custody.v1', 'commit': commit,
              'manifest': MANIFEST, 'manifest_sha256': MANIFEST_SHA256,
              'status': 'incomplete' if unresolved else 'verified', 'scope': 'source_bytes_only',
              'input_count': len(pins), 'verified_inputs': len(pins) - len(unresolved),
              'verified_bytes': verified_bytes, 'counts': counts, 'unresolved': unresolved}
    if show_inputs:
        report['inputs'] = inputs
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', type=Path, help='Local Git checkout or bare object store')
    parser.add_argument('--revision', default=SOURCE_REVISION, help='Git revision with the original v3 manifest and files')
    parser.add_argument('--node-modules', type=Path, required=True, help='Physical directory of the original Node dependencies')
    parser.add_argument('--external-input', nargs=2, action='append', default=[], metavar=('ORIGINAL', 'RECOVERED'))
    parser.add_argument('--show-inputs', action='store_true', help='Include the mapping for every manifest entry')
    args = parser.parse_args()
    try:
        result = inventory(args.repository, args.revision, args.node_modules, args.external_input, args.show_inputs)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(2, f'Archive source check failed: {exc}\n')
    print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'verified' else 1


if __name__ == '__main__':
    sys.exit(main())
