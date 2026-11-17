"""One shared host operation lock and durable, non-replaying mutation marker.

The lock serializes cooperating retained deployment and startup entrypoints.
It does not purport to constrain direct Docker, root, or retired executors.
The directory must be provisioned explicitly before a lock-aware rollout.
"""
from __future__ import annotations

import contextlib
import fcntl
import hashlib
import json
import os
import re
import stat
import uuid
from pathlib import Path

DEFAULT_ROOT = Path('/Volumes/PRO-G40/Projects/COLLECT-Production/.collect-operation-lock-v1')
FORMAT = 'collect.host-operation.v1'


class OperationRefused(RuntimeError):
    pass


class OperationBusy(OperationRefused):
    pass


def _directory(path):
    path = Path(path)
    st = path.lstat()
    if (not path.is_absolute() or path.resolve() != path or not stat.S_ISDIR(st.st_mode)
        or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o700):
        raise OperationRefused('operation_directory_untrusted')
    return path


def _open_private(path, flags):
    before = path.lstat()
    if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid()
        or before.st_nlink != 1 or stat.S_IMODE(before.st_mode) != 0o600):
        raise OperationRefused('operation_file_untrusted')
    fd = os.open(path, flags | os.O_NOFOLLOW)
    actual = os.fstat(fd)
    if ((actual.st_dev, actual.st_ino) != (before.st_dev, before.st_ino)
        or not stat.S_ISREG(actual.st_mode) or actual.st_uid != os.getuid()
        or actual.st_nlink != 1 or stat.S_IMODE(actual.st_mode) != 0o600):
        os.close(fd)
        raise OperationRefused('operation_file_changed')
    return fd


def _sync_dir(root):
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def initialize(root=None):
    """Create a fresh private coordination directory; never adopt an existing one."""
    root = Path(DEFAULT_ROOT if root is None else root)
    parent = root.parent
    pst = parent.lstat()
    if (not root.is_absolute() or parent.resolve() != parent or not stat.S_ISDIR(pst.st_mode)
        or pst.st_uid != os.getuid() or stat.S_IMODE(pst.st_mode) & 0o022):
        raise OperationRefused('operation_parent_untrusted')
    root.mkdir(mode=0o700)
    fd = os.open(root/'operation.lock', os.O_CREAT | os.O_EXCL | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
    _sync_dir(root)
    _sync_dir(parent)


class Coordinator:
    def __init__(self, root=None):
        self.root = _directory(DEFAULT_ROOT if root is None else root)
        self.fd = _open_private(self.root/'operation.lock', os.O_RDWR)
        try:
            fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            os.close(self.fd)
            raise OperationBusy('another_operation_running') from None
        except BaseException:
            os.close(self.fd)
            raise

    def close(self):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def active(self):
        path = self.root/'active.private.json'
        if not os.path.lexists(path):
            return None
        fd = _open_private(path, os.O_RDONLY)
        with os.fdopen(fd, 'rb') as stream:
            raw = stream.read(4097)
        if len(raw) > 4096:
            raise OperationRefused('operation_marker_invalid')
        try:
            record = json.loads(raw)
            valid = (set(record) == {'format', 'operation', 'kind', 'binding_sha256'}
                     and record['format'] == FORMAT
                     and str(uuid.UUID(record['operation'])) == record['operation']
                     and re.fullmatch(r'[a-z][a-z0-9_]{0,47}', record['kind'])
                     and re.fullmatch(r'[a-f0-9]{64}', record['binding_sha256']))
        except (ValueError, TypeError, KeyError, AttributeError):
            valid = False
        if not valid:
            raise OperationRefused('operation_marker_invalid')
        return record

    def begin(self, operation, kind, binding_sha256):
        if self.active() is not None:
            raise OperationBusy('previous_operation_requires_reconciliation')
        try:
            valid = (str(uuid.UUID(operation)) == operation
                     and re.fullmatch(r'[a-z][a-z0-9_]{0,47}', kind)
                     and re.fullmatch(r'[a-f0-9]{64}', binding_sha256))
        except (ValueError, TypeError, AttributeError):
            valid = False
        if not valid:
            raise OperationRefused('operation_binding_invalid')
        value = {'format': FORMAT, 'operation': operation, 'kind': kind, 'binding_sha256': binding_sha256}
        raw = (json.dumps(value, sort_keys=True, separators=(',', ':'))+'\n').encode()
        fd = os.open(self.root/'active.private.json', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        _sync_dir(self.root)
        if self.active() != value:
            raise OperationRefused('operation_marker_unconfirmed')
        return value

    def require(self, expected):
        if self.active() != expected:
            raise OperationRefused('operation_owner_changed')

    def complete(self, expected):
        self.require(expected)
        path = self.root/'active.private.json'
        # No other supported operator can enter while this flock is held.
        os.unlink(path)
        _sync_dir(self.root)
        if os.path.lexists(path):
            raise OperationRefused('operation_completion_unconfirmed')


def binding(kind, target):
    return hashlib.sha256((kind+'\0'+str(target)).encode()).hexdigest()


@contextlib.contextmanager
def mutation(kind, target, *, root=None):
    """Keep the marker on any unknown/failed outcome; never auto-retry."""
    with Coordinator(root) as guard:
        marker = guard.begin(str(uuid.uuid4()), kind, binding(kind, target))
        try:
            yield
        except BaseException:
            raise
        else:
            guard.complete(marker)


class MutationPermit:
    def __init__(self, coordinator, kind, target):
        self.coordinator = coordinator
        self.kind = kind
        self.target = target
        self.marker = None

    def arm(self):
        if self.marker is None:
            self.marker = self.coordinator.begin(str(uuid.uuid4()), self.kind, binding(self.kind, self.target))


@contextlib.contextmanager
def coordinated(kind, target, *, root=None):
    """Hold the lock; persist intent only when an actual mutation may begin."""
    with Coordinator(root) as guard:
        if guard.active() is not None:
            raise OperationBusy('previous_operation_requires_reconciliation')
        permit = MutationPermit(guard, kind, target)
        try:
            yield permit
        except BaseException:
            raise
        else:
            if permit.marker is not None:
                guard.complete(permit.marker)


def monitor_cycle(callback, *, root=None):
    """Let a live monitor wait harmlessly while another operation owns the host."""
    try:
        guard = Coordinator(root)
    except OperationBusy:
        return False
    try:
        if guard.active() is not None:
            return False
        callback()
        return True
    finally:
        guard.close()
