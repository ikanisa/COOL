"""Root-selected, exclusive preservation of eight observed Dart compiler caches.

Preparation only. No Gradle, compilation, network, arbitrary deletion or signals.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import time

HERE = Path(__file__).absolute().parent
ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
DESTINATION = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/external-headroom-preservation2')
OBSERVATION_SHA = '79c1432ec4021285b0ffb50fea2d911ba79abcf591ada537dd43f6e1327ac1f8'
EXACT_PATHS = {
    '.dart_tool/hooks_runner/objective_c/1f2474df3a/hook.dill',
    '.dart_tool/hooks_runner/objective_c/337ce265dc/hook.dill',
    '.dart_tool/hooks_runner/objective_c/407c785a7d/hook.dill',
    '.dart_tool/hooks_runner/objective_c/6782ff62a0/hook.dill',
    '.dart_tool/hooks_runner/objective_c/aeb97ac750/hook.dill',
    '.dart_tool/hooks_runner/objective_c/b8c2d55d59/hook.dill',
    '.dart_tool/hooks_runner/objective_c/cd662d2432/hook.dill',
    'build/1e57b4283dd269ba75191ea2755bf355.cache.dill.track.dill',
}
GUARDS = {
    ROOT / 'docs/release/critical-implementation-2026-10-01/root-arc09-r8-integration1/final-current-source-fence.json': 'f5448ce9a3e70623493035eaf37eb600d78c924d977e191e452ab9073b630333',
    Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/app-source/.collect-release-candidate.json'): '7f896d80db4f79c8b5f75743ff1dfeb30dd6cc51951f2ac6214ad3eb3c2f8df1',
    ROOT / 'docs/release/critical-implementation-2026-10-01/root-arc09-r8-integration1/r8-artifact-admission.json': 'd3b8ba4f728952752f55bfeafe230ef62fc253dc47b40692a4b249e74efd7651',
}


def check_deadline(deadline):
    if time.monotonic() > deadline:
        raise TimeoutError('exact cache preservation exceeded its 300-second bound')


def hash_fd(fd, deadline):
    os.lseek(fd, 0, os.SEEK_SET)
    result = hashlib.sha256()
    while True:
        check_deadline(deadline)
        block = os.read(fd, 1024 * 1024)
        if not block:
            return result.hexdigest()
        result.update(block)


def physical_parents(path):
    for parent in (path.parent, *path.parent.parents):
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError('nonphysical parent: ' + str(parent))


def match_identity(info, row):
    actual = {'bytes': info.st_size, 'mode': stat.S_IMODE(info.st_mode),
              'mtime_ns': info.st_mtime_ns, 'ctime_ns': info.st_ctime_ns,
              'dev': info.st_dev, 'ino': info.st_ino, 'nlink': info.st_nlink}
    if not stat.S_ISREG(info.st_mode) or any(actual[k] != row[k] for k in actual):
        raise ValueError('source cache identity drift: ' + row['path'])


def open_verified(path, row, deadline):
    physical_parents(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        match_identity(os.fstat(fd), row)
        if hash_fd(fd, deadline) != row['sha256']:
            raise ValueError('source cache hash drift: ' + row['path'])
        match_identity(os.fstat(fd), row)
        return fd
    except BaseException:
        os.close(fd)
        raise


def assert_no_open(result):
    # lsof's absence result is exit 1 and completely empty stdout/stderr.
    # Any open handle, warning, ambiguous success or execution error refuses.
    if result.returncode != 1 or result.stdout or result.stderr:
        raise ValueError('lsof did not establish a clean no-open-files observation')


def write_json(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')
    path.chmod(0o400)


def run_readonly(argv, deadline, bound=15, input_bytes=None):
    check_deadline(deadline)
    remaining = min(bound, deadline - time.monotonic())
    return subprocess.run(argv, cwd=ROOT, input=input_bytes, capture_output=True, timeout=remaining)


def verify_guards(deadline):
    for path, wanted in GUARDS.items():
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            if hash_fd(fd, deadline) != wanted:
                raise ValueError('held source/admission guard changed: ' + str(path))
        finally:
            os.close(fd)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--controller-sha256', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--remove-preserved-caches', action='store_true')
    args = parser.parse_args()
    if hashlib.sha256(Path(__file__).read_bytes()).hexdigest() != args.controller_sha256:
        raise ValueError('controller pin mismatch')
    if Path(args.output) != DESTINATION or str(Path(args.output)) != args.output:
        raise ValueError('only the root-reviewed exact fresh internal destination is allowed')
    physical_parents(DESTINATION)
    if ROOT.resolve() != ROOT or DESTINATION.parent.resolve() != DESTINATION.parent:
        raise ValueError('nonphysical root/destination')
    raw = (HERE / 'observation.json').read_bytes()
    if hashlib.sha256(raw).hexdigest() != OBSERVATION_SHA:
        raise ValueError('observation pin mismatch')
    observation = json.loads(raw)
    rows = observation['files']
    if len(rows) != 8 or {r['path'] for r in rows} != EXACT_PATHS or sum(r['bytes'] for r in rows) != 121842984:
        raise ValueError('exact eight-cache selection changed')
    source_paths = [ROOT / r['path'] for r in rows]
    start = time.monotonic()
    deadline = start + 300
    verify_guards(deadline)
    for row, path in zip(rows, source_paths):
        fd = open_verified(path, row, deadline)
        os.close(fd)
    tracked = run_readonly(['/usr/bin/git', 'ls-files', '-z', '--', *[r['path'] for r in rows]], deadline)
    ignored = run_readonly(['/usr/bin/git', 'check-ignore', '--stdin', '-z'], deadline, input_bytes=(''.join(r['path'] + '\0' for r in rows)).encode('utf-8'))
    if tracked.returncode or tracked.stdout or tracked.stderr or ignored.returncode or ignored.stderr or ignored.stdout.count(b'\0') != 8 or set(ignored.stdout.decode().split('\0')) != EXACT_PATHS | {''}:
        raise ValueError('cache must remain untracked and ignored')
    if os.statvfs(DESTINATION.parent).f_bavail * os.statvfs(DESTINATION.parent).f_frsize < 1024 ** 3:
        raise ValueError('insufficient internal preservation headroom')
    DESTINATION.mkdir(mode=0o700)  # No overwrite or resumption of another output.
    receipt = {'kind': 'root_exact_cache_preservation', 'removed_paths': [],
               'copied_paths': [], 'lsof': [], 'cache_removal_requested': args.remove_preserved_caches,
               'source': str(ROOT), 'destination': str(DESTINATION),
               'external_floor_bytes_unchanged': 4 * 1024 ** 3,
               'protected_original_PID_scope': 68020, 'protected_PID_signal_authority': False,
               'APP_SDK_source_evidence_artifact_paths_deleted': False,
               'production_release_approval': False}
    usage = os.statvfs(ROOT)
    receipt['external_free_before_bytes'] = usage.f_bavail * usage.f_frsize
    try:
        result = run_readonly(['/usr/sbin/lsof', '-nP', *map(str, source_paths)], deadline)
        receipt['lsof'].append({'argv': result.args, 'exit_code': result.returncode,
                                'stdout': result.stdout.decode(), 'stderr': result.stderr.decode(), 'phase': 'before-copy'})
        assert_no_open(result)
        for row, path in zip(rows, source_paths):
            fd = open_verified(path, row, deadline)
            copied = DESTINATION / row['path']
            copied.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            try:
                os.lseek(fd, 0, os.SEEK_SET)
                with copied.open('xb') as stream:
                    while True:
                        check_deadline(deadline)
                        block = os.read(fd, 1024 * 1024)
                        if not block:
                            break
                        stream.write(block)
                    stream.flush()
                    os.fsync(stream.fileno())
                copied.chmod(row['mode'])
                os.utime(copied, ns=(row['mtime_ns'], row['mtime_ns']), follow_symlinks=False)
                match_identity(os.fstat(fd), row)
            finally:
                os.close(fd)
            cfd = os.open(copied, os.O_RDONLY | os.O_NOFOLLOW)
            try:
                cs = os.fstat(cfd)
                if cs.st_size != row['bytes'] or stat.S_IMODE(cs.st_mode) != row['mode'] or cs.st_mtime_ns != row['mtime_ns'] or hash_fd(cfd, deadline) != row['sha256']:
                    raise ValueError('preserved copy verification failed: ' + row['path'])
            finally:
                os.close(cfd)
            receipt['copied_paths'].append(row['path'])
        for row, path in zip(rows, source_paths):
            fd = open_verified(path, row, deadline)
            os.close(fd)
        verify_guards(deadline)
        result = run_readonly(['/usr/sbin/lsof', '-nP', *map(str, source_paths)], deadline)
        receipt['lsof'].append({'argv': result.args, 'exit_code': result.returncode,
                                'stdout': result.stdout.decode(), 'stderr': result.stderr.decode(), 'phase': 'before-removal'})
        assert_no_open(result)
        write_json(DESTINATION / 'verified-before-removal.json', {'observation_sha256': OBSERVATION_SHA, 'files': rows, 'receipt': receipt})
        if args.remove_preserved_caches:
            # Do not remove directories, logs, manifests, object files or dylibs.
            # Root must keep cache producers quiescent through this short stage;
            # lsof and identity observations do not attest a global process lock.
            for row, path in zip(rows, source_paths):
                check_deadline(deadline)
                physical_parents(path)
                match_identity(path.lstat(), row)
                path.unlink()
                receipt['removed_paths'].append(row['path'])
        verify_guards(deadline)
        usage = os.statvfs(ROOT)
        receipt['external_free_after_bytes'] = usage.f_bavail * usage.f_frsize
        receipt['external_floor_met_after'] = receipt['external_free_after_bytes'] >= 4 * 1024 ** 3
        receipt['preserved_bytes'] = sum(row['bytes'] for row in rows)
        receipt['all_eight_preserved_bytes_hashes_modes_mtimes_verified'] = True
        receipt['actual_seconds'] = time.monotonic() - start
        receipt['status'] = 'REMOVED_AFTER_VERIFIED_PRESERVATION' if args.remove_preserved_caches else 'PRESERVED_ONLY'
        write_json(DESTINATION / 'readback.json', receipt)
        print(json.dumps(receipt, sort_keys=True))
    except BaseException as error:
        receipt['status'] = 'FAILED_NO_FURTHER_REMOVALS'
        receipt['error'] = {'type': type(error).__name__, 'message': str(error)}
        receipt['actual_seconds'] = time.monotonic() - start
        write_json(DESTINATION / 'failure.json', receipt)
        raise


if __name__ == '__main__':
    main()
