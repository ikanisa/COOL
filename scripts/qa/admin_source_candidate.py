#!/usr/bin/env python3
"""Admit the sole React Admin into a local Git tree or materialize it for qualification."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from collect_release_candidate import ReleaseError, exclusion, regular_bytes, safe_relative, screen_credentials


ROOT = Path(__file__).resolve().parents[2]
INPUTS = 'admin-web/scripts/source-inputs.json'
REF_PREFIX = 'refs/collect/candidates/react-admin/'


def git(root, *args, data=None, index=None):
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env['GIT_OPTIONAL_LOCKS'] = '0'
    if index is not None:
        env['GIT_INDEX_FILE'] = str(index)
    return subprocess.check_output(['git', '--literal-pathspecs', *args], cwd=root, env=env, input=data)


def oid(root, *args, **kwargs):
    return git(root, *args, **kwargs).decode().strip()


def inventory(root):
    spec = json.loads(regular_bytes(root, INPUTS)[0])
    paths = [safe_relative(name) for name in spec['build'] + spec['qualification']]
    if any(exclusion(name) for name in paths):
        raise ReleaseError('ADMIN_SOURCE_SCOPE_INVALID')
    raw = git(root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', *paths)
    names = sorted({safe_relative(item.decode()) for item in raw.split(b'\0') if item})
    names = [name for name in names if not exclusion(name) and os.path.lexists(root / name)]
    missing = [path for path in paths if not any(name == path or name.startswith(path + '/') for name in names)]
    if missing:
        raise ReleaseError('ADMIN_SOURCE_INPUT_MISSING', missing)
    return names


def admit(root):
    base = oid(root, 'rev-parse', 'HEAD^{commit}')
    object_format = oid(root, 'rev-parse', '--show-object-format')
    names = inventory(root)
    blobs = []
    contents = {}
    total_bytes = 0
    for name in names:
        content, permissions = regular_bytes(root, name)
        screen_credentials(content, name)
        header = f'blob {len(content)}\0'.encode()
        blob = hashlib.new(object_format, header + content).hexdigest()
        blobs.append(('100755' if permissions & 0o111 else '100644', blob, name))
        contents[blob] = content
        total_bytes += len(content)

    # Write exactly the screened bytes. Never reread a mutable working file
    # directly into Git, even when a concurrent change would be detected later.
    known = git(root, 'cat-file', '--batch-check=%(objecttype)', data=''.join(blob + '\n' for blob in contents).encode())
    for (blob, content), state in zip(contents.items(), known.splitlines(), strict=True):
        if state != b'blob' and oid(root, 'hash-object', '-w', '--stdin', data=content) != blob:
            raise ReleaseError('ADMIN_SOURCE_OBJECT_MISMATCH')
    if inventory(root) != names:
        raise ReleaseError('ADMIN_SOURCE_CHANGED_DURING_ADMISSION')
    for mode, blob, name in blobs:
        latest, permissions = regular_bytes(root, name)
        if latest != contents[blob] or bool(permissions & 0o111) != (mode == '100755'):
            raise ReleaseError('ADMIN_SOURCE_CHANGED_DURING_ADMISSION', [name])
    entries = b''.join(f'{mode} {blob}\t{name}\0'.encode() for mode, blob, name in blobs)
    with tempfile.TemporaryDirectory(prefix='collect-admin-index-') as directory:
        index = Path(directory) / 'index'
        git(root, 'read-tree', '--empty', index=index)
        git(root, 'update-index', '-z', '--index-info', data=entries, index=index)
        tree = oid(root, 'write-tree', index=index)

    # A tree ref keeps these objects reachable through local Git maintenance. Its
    # name binds the predecessor commit as well as the exact product contents.
    ref = REF_PREFIX + base + '/' + tree
    git(root, 'update-ref', ref, tree, tree if git_ref_exists(root, ref) else '0' * len(tree))
    return {'base_commit': base, 'product_tree': tree, 'ref': ref, 'files': len(names), 'bytes': total_bytes}


def git_ref_exists(root, ref):
    return bool(git(root, 'for-each-ref', '--format=%(refname)', ref).strip())


def checkout(root, ref, destination):
    width = hashlib.new(oid(root, 'rev-parse', '--show-object-format')).digest_size * 2
    match = re.fullmatch(re.escape(REF_PREFIX) + rf'([0-9a-f]{{{width}}})/([0-9a-f]{{{width}}})', ref)
    if not match:
        raise ReleaseError('ADMIN_SOURCE_REF_INVALID')
    base, tree = match.groups()
    if oid(root, 'rev-parse', '--verify', ref) != tree or oid(root, 'cat-file', '-t', tree) != 'tree':
        raise ReleaseError('ADMIN_SOURCE_REF_MISMATCH')
    if oid(root, 'cat-file', '-t', base) != 'commit':
        raise ReleaseError('ADMIN_SOURCE_BASE_MISMATCH')
    objects = oid(root, 'rev-parse', '--path-format=absolute', '--git-path', 'objects')
    destination = destination.parent.resolve(strict=True) / destination.name
    if destination.is_relative_to(root):
        raise ReleaseError('ADMIN_CHECKOUT_MUST_BE_OUTSIDE_SOURCE')
    destination.mkdir(mode=0o700)  # refuses existing directories, files and links
    git(destination, 'init', '-q', '--template=', '--object-format=' + oid(root, 'rev-parse', '--show-object-format'))
    (destination / '.git/objects/info/alternates').write_text(objects + '\n')
    git(destination, 'update-ref', '--no-deref', 'HEAD', base)
    git(destination, 'read-tree', tree)
    git(destination, 'checkout-index', '-a', '-u')
    git(destination, 'diff-files', '--quiet')
    if oid(destination, 'write-tree') != tree:
        raise ReleaseError('ADMIN_CHECKOUT_TREE_MISMATCH')
    return {'base_commit': base, 'product_tree': tree, 'directory': str(destination), 'index_matches_tree': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('admit', help='retain the current declared product inputs in the local object database')
    restore = commands.add_parser('checkout', help='materialize only the admitted files in a new directory')
    restore.add_argument('ref')
    restore.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        result = admit(ROOT) if args.command == 'admit' else checkout(ROOT, args.ref, args.destination)
    except ReleaseError as error:
        print(json.dumps({'error': error.code, 'paths': error.paths}), file=sys.stderr)
        return 1
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
