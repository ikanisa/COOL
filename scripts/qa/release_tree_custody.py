#!/usr/bin/env python3
"""Capture and verify committed evidence in a self-contained Git packet."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import tempfile

CHUNK = 1024 * 1024
MANIFEST = 'paths.jsonl.gz'
RECEIPT = 'receipt.json'
STORE = 'objects.git'


def digest_file(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def git_environment():
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull, GIT_NO_LAZY_FETCH='1')
    return env


def git(repo, *args, **kwargs):
    env = git_environment()
    env.update(kwargs.pop('env', {}))
    return subprocess.run(['git', '-C', str(repo), *args], check=True, env=env, **kwargs)


def output(repo, *args):
    return git(repo, *args, stdout=subprocess.PIPE).stdout


def unit_path(value):
    path = PurePosixPath(value)
    if (path.parts[:2] != ('docs', 'release') or '..' in path.parts or
            '.git' in path.parts or str(path) != value):
        raise ValueError('Select docs/release or a named subdirectory')
    return path


def entries(repo, tree):
    items = []
    for raw in output(repo, 'ls-tree', '-rzl', tree).split(b'\0'):
        if not raw:
            continue
        header, name = raw.split(b'\t', 1)
        mode, kind, blob, size = header.decode('ascii').split()
        if kind != 'blob' or mode not in {'100644', '100755', '120000'}:
            raise ValueError('Unsupported Git entry')
        items.append((os.fsdecode(name), mode, blob, int(size)))
    if not items:
        raise ValueError('Empty evidence tree')
    return items


def source_digests(repo, files, scratch=None):
    blobs = {blob: size for _, _, blob, size in files}
    hashes = {}
    with tempfile.TemporaryFile(dir=scratch) as queries:
        for blob in blobs:
            queries.write(blob.encode('ascii') + b'\n')
        queries.seek(0)
        cmd = ['git', '-C', str(repo), 'cat-file', '--batch']
        with subprocess.Popen(cmd, env=git_environment(), stdin=queries,
                              stdout=subprocess.PIPE) as process:
            data = process.stdout
            for blob, size in blobs.items():
                if data.readline().split() != [blob.encode('ascii'), b'blob', str(size).encode()]:
                    raise ValueError('Unexpected source blob header')
                hasher = hashlib.sha256()
                remaining = size
                while remaining:
                    chunk = data.read(min(remaining, CHUNK))
                    if not chunk:
                        raise ValueError('Short source blob')
                    hasher.update(chunk)
                    remaining -= len(chunk)
                if data.read(1) != b'\n':
                    raise ValueError('Unexpected source blob terminator')
                hashes[blob] = hasher.hexdigest()
            if data.read(1):
                raise ValueError('Unconsumed source bytes')
            if (code := process.wait()) != 0:
                raise subprocess.CalledProcessError(code, cmd)
    return hashes


def inventory_line(unit, entry, digest):
    name, mode, blob, size = entry
    return (json.dumps([str(unit / name), mode, blob, size, digest],
                       ensure_ascii=True, separators=(',', ':')) + '\n').encode('ascii')


def check_store(store, tree):
    if (store / 'objects/info/alternates').exists():
        raise ValueError('Restore store has an alternate object directory')
    if output(store, 'remote').strip():
        raise ValueError('Restore store has a remote')
    git(store, 'fsck', '--full', '--strict', '--no-reflogs', tree, stdout=subprocess.DEVNULL)


def capture(repo, revision, unit, packet):
    commit = output(repo, 'rev-parse', '--verify', revision + '^{commit}').decode().strip()
    tree = output(repo, 'rev-parse', '--verify', commit + ':' + str(unit)).decode().strip()
    if output(repo, 'cat-file', '-t', tree).strip() != b'tree':
        raise ValueError('Evidence root must be a Git tree')
    files = entries(repo, tree)
    packet.mkdir(mode=0o700)
    store = packet / STORE
    git(packet, 'init', '--bare', '--quiet', STORE)
    with tempfile.TemporaryFile(dir=packet) as pack:
        git(repo, 'pack-objects', '--stdout', '--revs', '--window=0', '--threads=2',
            input=(tree + '\n').encode(), stdout=pack)
        pack.seek(0)
        git(store, 'index-pack', '--stdin', '--strict', stdin=pack, stdout=subprocess.DEVNULL)
    git(store, 'update-ref', 'refs/tags/evidence-tree', tree)
    check_store(store, tree)
    hashes = source_digests(repo, files, packet)
    with (packet / MANIFEST).open('xb') as raw, gzip.GzipFile(
            filename='', fileobj=raw, mode='wb', mtime=0) as archive:
        for entry in files:
            archive.write(inventory_line(unit, entry, hashes[entry[2]]))
    modes = dict(Counter(mode for _, mode, _, _ in files))
    packs = list((store / 'objects/pack').glob('*.pack'))
    if len(packs) != 1:
        raise ValueError('Expected a single complete pack')
    receipt = {'format': 'collect.release-tree-custody.v1', 'source_commit': commit,
               'unit': str(unit), 'tree': tree, 'paths': len(files),
               'bytes': sum(row[3] for row in files), 'distinct_blobs': len(hashes),
               'git_modes': modes, 'inventory_sha256': digest_file(packet / MANIFEST),
               'pack_sha256': digest_file(packs[0]), 'pack_bytes': packs[0].stat().st_size}
    (packet / RECEIPT).write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({**receipt, 'receipt_sha256': digest_file(packet / RECEIPT)}), flush=True)


def restored_sha(path, mode, size):
    details = path.lstat()
    if mode == '120000':
        if not stat.S_ISLNK(details.st_mode):
            raise ValueError('Missing restored symlink at ' + str(path))
        target = os.readlink(os.fsencode(path))
        if len(target) != size:
            raise ValueError('Restored symlink size differs at ' + str(path))
        return hashlib.sha256(target).hexdigest()
    if (not stat.S_ISREG(details.st_mode) or details.st_size != size or
            (stat.S_IMODE(details.st_mode) & 0o111) != (int(mode, 8) & 0o111)):
        raise ValueError('Restored file mode or size differs at ' + str(path))
    return digest_file(path)


def checked_packet(packet, expected):
    raw = (packet / RECEIPT).read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError('Unexpected custody receipt')
    receipt = json.loads(raw)
    if receipt['format'] != 'collect.release-tree-custody.v1':
        raise ValueError('Unknown custody format')
    unit = unit_path(receipt['unit'])
    store = packet / STORE
    packs = list((store / 'objects/pack').glob('*.pack'))
    if (digest_file(packet / MANIFEST) != receipt['inventory_sha256'] or len(packs) != 1 or
            packs[0].stat().st_size != receipt['pack_bytes'] or
            digest_file(packs[0]) != receipt['pack_sha256']):
        raise ValueError('Custody inventory or pack differs')
    tree = receipt['tree']
    check_store(store, tree)
    files = entries(store, tree)
    if (len(files) != receipt['paths'] or sum(row[3] for row in files) != receipt['bytes'] or
            len({row[2] for row in files}) != receipt['distinct_blobs'] or
            Counter(row[1] for row in files) != receipt['git_modes']):
        raise ValueError('Evidence tree counts, modes or size differ')
    return receipt, unit, store, files


def check_inventory(packet, unit, files, digest_entry):
    with gzip.open(packet / MANIFEST, 'rb') as archive:
        for entry in files:
            if archive.readline() != inventory_line(unit, entry, digest_entry(entry)):
                raise ValueError('Evidence differs at ' + entry[0])
        if archive.read(1):
            raise ValueError('Unexpected inventory entry')


def receipt_summary(receipt, expected):
    return {'verified': True, 'source_commit': receipt['source_commit'], 'tree': receipt['tree'],
            'unit': receipt['unit'], 'paths': receipt['paths'], 'bytes': receipt['bytes'],
            'git_modes': receipt['git_modes'], 'receipt_sha256': expected}


def verify_packet(packet, expected):
    receipt, unit, store, files = checked_packet(packet, expected)
    hashes = source_digests(store, files)
    check_inventory(packet, unit, files, lambda entry: hashes[entry[2]])
    print(json.dumps({**receipt_summary(receipt, expected), 'scope': 'packet'}), flush=True)


def restore(packet, expected, destination, verify_existing=False):
    receipt, unit, store, files = checked_packet(packet, expected)
    tree = receipt['tree']
    checkout = destination / unit
    if not verify_existing:
        destination.mkdir(mode=0o700)
        checkout.mkdir(parents=True)
        with tempfile.TemporaryDirectory() as temp:
            env = {'GIT_INDEX_FILE': str(Path(temp) / 'index')}
            git(store, 'read-tree', tree, env=env)
            # The destination is private. Inside it, reproduce Git executable bits
            # even when the caller's private umask would strip group/other execute.
            git(store, '--work-tree=' + str(checkout), '-c', 'core.symlinks=true',
                '-c', 'core.autocrlf=false', 'checkout-index', '--all',
                '--prefix=' + str(checkout) + os.sep, env=env, umask=0o022)
    if checkout.resolve() != checkout or not checkout.is_dir():
        raise ValueError('Restore unit is missing or traverses a symlink')
    names = set()
    for parent, directories, filenames in os.walk(checkout, followlinks=False):
        directory = Path(parent)
        links = [name for name in directories if (directory / name).is_symlink()]
        names.update((directory / name).relative_to(checkout).as_posix() for name in filenames + links)
    if names != {name for name, _, _, _ in files}:
        raise ValueError('Restored path set differs from the committed tree')
    check_inventory(packet, unit, files,
                    lambda entry: restored_sha(checkout / entry[0], entry[1], entry[3]))
    print(json.dumps(receipt_summary(receipt, expected)), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    create = sub.add_parser('capture')
    create.add_argument('repository', type=Path)
    create.add_argument('revision')
    create.add_argument('unit', type=unit_path)
    create.add_argument('packet', type=Path)
    for action in ('restore', 'verify'):
        verify = sub.add_parser(action)
        verify.add_argument('packet', type=Path)
        verify.add_argument('receipt_sha256')
        verify.add_argument('destination', type=Path)
    packet_check = sub.add_parser('verify-packet', help='Verify the pack and inventory without a checkout')
    packet_check.add_argument('packet', type=Path)
    packet_check.add_argument('receipt_sha256')
    args = parser.parse_args()
    if args.action == 'capture':
        capture(args.repository.resolve(), args.revision, args.unit, args.packet.resolve())
    elif args.action == 'verify-packet':
        verify_packet(args.packet.resolve(), args.receipt_sha256)
    else:
        restore(args.packet.resolve(), args.receipt_sha256, args.destination.resolve(), args.action == 'verify')


if __name__ == '__main__':
    main()
