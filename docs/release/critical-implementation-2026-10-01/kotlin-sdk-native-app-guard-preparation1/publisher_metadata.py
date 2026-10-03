#!/usr/bin/env python3
"""Only four authenticated publisher DOS timestamps; no runtime/stamp bypass."""
import datetime
import hashlib
import os
import stat
import zipfile
from pathlib import Path

ROOT = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/flutter')
POLICY = 'Interpret exact ZIP DOS tuples as UTC for deterministic local restoration; publisher timezone is unspecified.'
FILES = {
    'packages/flutter_tools/pubspec.yaml': ((2026, 6, 24, 16, 17, 32), 2818, '7924b6c341dc618b4cbedcdc893b87279d317b38dfc83d3b19bd70cec27eb4ee'),
    'packages/flutter_tools/pubspec.lock': ((2026, 6, 24, 16, 20, 32), 23993, '1aa193fc5df798338a2ca97d1737450f9c2cc1984ec0095b2efbaa0f4dcad340'),
    'bin/cache/flutter_tools.snapshot': ((2026, 6, 24, 16, 20, 42), 45150928, 'b5044d15beb40be40af8d8d52c9df7ffb19a2e8dc26a70b95872c9bd2e8f0c70'),
    'bin/cache/flutter_tools.stamp': ((2026, 6, 24, 16, 20, 42), 42, 'ec8f93820205b3e7053c47457ffc28a7c7579631a74d7ebffab8e05106863329'),
}


def identity(row):
    return (row.st_dev, row.st_ino, row.st_size, row.st_mode, row.st_nlink, row.st_mtime_ns, row.st_ctime_ns)


def timestamp_ns(value):
    return int(datetime.datetime(*value, tzinfo=datetime.timezone.utc).timestamp()) * 1000000000


def stable_read(path, retain=False):
    path = Path(path)
    if path.resolve() != path:
        raise ValueError('no link ancestor or named leaf allowed')
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_mode & (stat.S_ISUID | stat.S_ISGID):
        raise ValueError('not exclusive safe regular input')
    if before.st_size > (64 * 1024**2 if retain else 1024**3):
        raise ValueError('regular reader byte bound')
    digest = hashlib.sha256(); body = bytearray() if retain else None
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as source:
        opened = os.fstat(source.fileno())
        if identity(opened) != identity(before):
            raise ValueError('regular input changed before open')
        for chunk in iter(lambda: source.read(1024**2), b''):
            digest.update(chunk)
            if body is not None: body.extend(chunk)
        if identity(os.fstat(source.fileno())) != identity(before):
            raise ValueError('regular FD mutated during read')
    if identity(path.lstat()) != identity(before):
        raise ValueError('regular named leaf replaced during read')
    return {'sha256': digest.hexdigest(), 'bytes': before.st_size, 'mode': stat.S_IMODE(before.st_mode),
            'mtime_ns': before.st_mtime_ns, 'device': before.st_dev, 'inode': before.st_ino, 'nlink': before.st_nlink}, bytes(body) if body is not None else None


def exact_archive_timestamp_policy(archive):
    with zipfile.ZipFile(archive) as bundle:
        infos = bundle.infolist()
        for relative, (date, length, _) in FILES.items():
            names = [row for row in infos if row.filename == 'flutter/' + relative]
            if len(names) != 1 or names[0].date_time != date or names[0].file_size != length:
                raise ValueError('four exact publisher time/member identities differ')
    return {'policy': POLICY, 'publisher_timezone_attested': False,
            'publisher_relative_YAML_before_lock_seconds': 180,
            'restored_paths_exact': {name: timestamp_ns(row[0]) for name, row in FILES.items()}}


def validate_four_bytes(root):
    observed = {}
    for relative, (_, length, digest) in FILES.items():
        row, _ = stable_read(root / relative)
        if (row['bytes'], row['sha256']) != (length, digest):
            raise ValueError('exact publisher YAML/lock/snapshot/stamp bytes drift')
        observed[relative] = row
    return observed


def restore_after_separate_authorization(root, archive):
    if root != ROOT or root.resolve() != root or root.is_symlink():
        raise ValueError('timestamp writer restricted to fresh independent consumer')
    policy = exact_archive_timestamp_policy(archive)
    before = validate_four_bytes(root)
    for relative, (date, _, _) in FILES.items():
        path = root / relative
        current = path.lstat()
        if (current.st_dev, current.st_ino, current.st_mtime_ns) != (
                before[relative]['device'], before[relative]['inode'], before[relative]['mtime_ns']):
            raise ValueError('metadata leaf changed before FD restoration')
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            if identity(os.fstat(fd)) != identity(current):
                raise ValueError('metadata opened identity differs')
            os.utime(fd, ns=(current.st_atime_ns, timestamp_ns(date)))
            os.fsync(fd)
            after = os.fstat(fd)
            if ((after.st_dev, after.st_ino, after.st_size, after.st_mode, after.st_nlink)
                    != (current.st_dev, current.st_ino, current.st_size, current.st_mode, current.st_nlink)
                    or after.st_mtime_ns != timestamp_ns(date)
                    or identity(path.lstat()) != identity(after)):
                raise ValueError('metadata restoration replaced/raced/changed regular input')
        finally:
            os.close(fd)
    after = validate_four_bytes(root)
    if any(after[name]['mtime_ns'] != timestamp_ns(FILES[name][0]) for name in FILES):
        raise ValueError('exact deterministic publisher timestamps not restored')
    return {'policy': policy, 'before': before, 'after': after, 'authored_bytes_changed': False,
            'SDK_executed': False, 'stamp_bytes_invented': False}


if __name__ == '__main__':
    raise SystemExit('Separate root/controller authorization required; standalone metadata writes refused.')
