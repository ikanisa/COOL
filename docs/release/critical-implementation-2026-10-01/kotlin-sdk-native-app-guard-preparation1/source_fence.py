#!/usr/bin/env python3
"""Bounded read-only source identity fences; no export, SDK or build execution."""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import stat
import subprocess
import time
import types
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
REPO = RELEASE.parents[2]
ORIGINAL = RELEASE / 'kotlin-sdk-native-consumer-preparation1'
EXPORTER_SHA256 = '1cf2c61c09099b6249895bd3887532cf1672a3f69c3eb4c23cb58c52d94aa690'
LIVE_FLOOR = 4 * 1024**3


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def metadata():
    return module(ORIGINAL / 'publisher_metadata.py', 'snapshot_metadata_reader')


def stable(path):
    path = Path(path)
    before = path.lstat()
    reader = metadata()
    row, _ = reader.stable_read(path)
    after = path.lstat()
    if reader.identity(before) != reader.identity(after) or before.st_uid != after.st_uid or before.st_gid != after.st_gid:
        raise ValueError('source identity changed during bounded read')
    row.update(ctime_ns=before.st_ctime_ns, uid=before.st_uid, gid=before.st_gid)
    return row


def physical_directory(path):
    path = Path(path)
    if path.absolute() != path or path.resolve() != path:
        raise ValueError('physical directory path or ancestor alias refused')
    row = path.lstat()
    if not stat.S_ISDIR(row.st_mode):
        raise ValueError('physical directory required')
    return {'device': row.st_dev, 'inode': row.st_ino, 'mode': stat.S_IMODE(row.st_mode),
            'uid': row.st_uid, 'gid': row.st_gid}


def private_destination(app, base):
    app, base = Path(app), Path(base)
    if app.parent != base or app == base or app.exists() or app.is_symlink():
        raise ValueError('new exclusive app destination must be absent in owned root')
    row = physical_directory(base)
    if row['uid'] != os.getuid() or row['mode'] != 0o700:
        raise ValueError('private owned native root must retain owner-only mode')
    return row


def private_candidate(app, base):
    app, base = Path(app), Path(base)
    if app.parent != base:
        raise ValueError('candidate must belong to reviewed private root')
    for root in (base, app):
        row = physical_directory(root)
        if row['uid'] != os.getuid() or row['mode'] != 0o700:
            raise ValueError('candidate and owner root must remain private')
    for parent, directories, names in os.walk(app, followlinks=False):
        for name in directories:
            row = physical_directory(Path(parent) / name)
            if row['uid'] != os.getuid():
                raise ValueError('candidate directory owner differs')
        for name in names:
            path = Path(parent) / name
            row = path.lstat()
            if (not stat.S_ISREG(row.st_mode) or row.st_nlink != 1
                    or row.st_uid != os.getuid() or row.st_mode & (stat.S_ISUID | stat.S_ISGID)):
                raise ValueError('candidate leaf is not independently owned safe regular source')
    return {'private_root_and_candidate_mode': 0o700, 'authored_leaves_single_link': True,
            'OS_immutable_flag_attested': False, 'production_freeze_attested': False}


def validate_commands(config, original, proposal, repo, base, sdk, app, auth):
    original_config = json.loads((Path(original) / 'proposed-commands.json').read_text())
    keys = ('Python_executable', 'Python_SHA256', 'Node_executable', 'Node_SHA256',
            'JDK_java_executable', 'JDK_java_SHA256', 'environment_exact', 'commands',
            'minimum_free_bytes', 'live_free_floor_bytes', 'foundation_deadline_seconds',
            'source_readback_deadline_seconds', 'reviewed_exporter_SHA256',
            'raw_Gradle_ZIP_SHA256', 'raw_Gradle_ZIP_bytes',
            'raw_Gradle_ZIP_owned_relative_destination', 'raw_Gradle_seed_deadline_seconds',
            'raw_published_Gradle_ZIP_source', 'SDK', 'app', 'base',
            'separate_root_stage_authorization_required', 'later_stage_requires_root_pinned_predecessor_terminal',
            'app_lock_native_require_root_pinned_original_export_binding')
    if any(config.get(key) != original_config.get(key) for key in keys):
        raise ValueError('original exact tool/env/root/command/deadline/resource invariant changed')
    expected_config = dict(original_config)
    expected_config.update(immutable_root_stage_admission_directory=str(auth),
                           strict_current_source_hold_required_for_export=False,
                           strict_current_source_comparison_required_for_export=True,
                           source_scope_held_for_strict_export=False,
                           source_identity_index_membership_fixture_fences_required=True,
                           only_app_export_admitted_by_derivative=False,
                           only_app_export_and_app_lock_admitted_by_derivative=True)
    if config != expected_config:
        raise ValueError('only declared snapshot admission fields may differ from original full configuration')
    command = config['commands']['app-export']
    expected = [config['Python_executable'], '-I', '-B', str(Path(repo) / 'scripts/qa/collect_release_candidate.py'),
                '--root', str(repo), 'export', '--destination', str(app), '--flutter-sdk', str(sdk),
                '--report', str(Path(base) / '.control/app-export/source-export.json')]
    if (command != {'argv': expected, 'cwd': str(repo), 'deadline_seconds': 300}
            or config['reviewed_exporter_SHA256'] != EXPORTER_SHA256
            or config.get('strict_current_source_hold_required_for_export') is not False
            or config.get('strict_current_source_comparison_required_for_export') is not True
            or config.get('source_scope_held_for_strict_export') is not False
            or config.get('source_identity_index_membership_fixture_fences_required') is not True
            or config.get('only_app_export_admitted_by_derivative') is not False
            or config.get('only_app_export_and_app_lock_admitted_by_derivative') is not True
            or config.get('immutable_root_stage_admission_directory') != str(auth)
            or config.get('candidate_promoted') is not False or config.get('production_release_approval') is not False):
        raise ValueError('honest strict-only app snapshot command/admission contract differs')


def capture(root, seconds=300, floor=LIVE_FLOOR):
    """Two identity/index/name reads fence one selected byte/fixture capture."""
    root = Path(root)
    started = time.monotonic()
    deadline = started + seconds

    def bound():
        if time.monotonic() >= deadline:
            raise ValueError('read-only source fence deadline exceeded')
        if shutil.disk_usage(root).free < floor:
            raise ValueError('read-only source fence headroom floor breached')

    bound()
    root_row = physical_directory(root)
    exporter_path = root / 'scripts/qa/collect_release_candidate.py'
    exporter_row = stable(exporter_path)
    if exporter_row['sha256'] != EXPORTER_SHA256:
        raise ValueError('reviewed strict exporter bytes changed')
    verified_row, exporter_bytes = metadata().stable_read(exporter_path, True)
    if verified_row['sha256'] != EXPORTER_SHA256 or stable(exporter_path) != exporter_row:
        raise ValueError('reviewed exporter raced before byte-bound module loading')
    exporter = types.ModuleType('snapshot_reviewed_exporter')
    exporter.__file__ = str(exporter_path)
    exec(compile(exporter_bytes, str(exporter_path), 'exec'), exporter.__dict__)
    env = {'PATH': '/usr/bin:/bin', 'GIT_OPTIONAL_LOCKS': '0', 'LC_ALL': 'C'}

    def git(*args):
        bound()
        return subprocess.check_output(['/usr/bin/git', *args], cwd=root, env=env,
                                       stderr=subprocess.DEVNULL, timeout=min(20, max(.01, deadline-time.monotonic())))

    def selection():
        names = sorted({exporter.safe_relative(value.decode('utf-8'))
                        for value in git('ls-files', '--cached', '--others', '--exclude-standard', '-z').split(b'\0') if value})
        return [name for name in names if exporter.exclusion(name) in (None, 'upstream_qa_fixture_source')]

    head = git('rev-parse', 'HEAD').decode('ascii').strip()
    if not re.fullmatch('[0-9a-f]{40,64}', head):
        raise ValueError('actual indexed repository HEAD malformed')
    index = Path(git('rev-parse', '--git-path', 'index').decode('utf-8').strip())
    if not index.is_absolute():
        index = root / index
    index_row = stable(index)
    names = selection()
    files, fixtures, absent, directories = {}, {}, [], {}
    for name in names:
        bound()
        path = root / name
        for parent in path.parents:
            if parent == root:
                break
            if parent.exists() or parent.is_symlink():
                directories[parent.relative_to(root).as_posix()] = physical_directory(parent)
        reason = exporter.exclusion(name)
        if not path.exists() and not path.is_symlink():
            if reason == 'upstream_qa_fixture_source':
                fixtures[name] = {'reason': reason, 'absent': True}
            else:
                absent.append(name)
            continue
        row = stable(path)
        if reason == 'upstream_qa_fixture_source':
            fixtures[name] = dict(row, reason=reason)
        else:
            files[name] = row
    if not exporter.REQUIRED <= files.keys():
        raise ValueError('selected source lacks exact exporter prerequisites')
    exporter.migration_versions(files)
    bound()
    if (selection() != names or git('rev-parse', 'HEAD').decode('ascii').strip() != head
            or stable(index) != index_row or physical_directory(root) != root_row):
        raise ValueError('source index/head/membership/root changed during capture')
    for name, expected in directories.items():
        if physical_directory(root / name) != expected:
            raise ValueError('source directory identity changed during capture')
    for name, expected in {**files, **fixtures}.items():
        bound()
        if expected.get('absent'):
            if (root / name).exists() or (root / name).is_symlink():
                raise ValueError('excluded indexed absence changed during capture')
        elif stable(root / name) != {key: value for key, value in expected.items() if key != 'reason'}:
            raise ValueError('selected/excluded fixture identity changed during capture')
    for name in absent:
        if (root / name).exists() or (root / name).is_symlink():
            raise ValueError('selected indexed absence changed during capture')
    selected = {name: {key: row[key] for key in ('sha256', 'bytes', 'mode')} for name, row in files.items()}
    excluded = {name: ({'reason': row['reason'], 'absent': True} if row.get('absent') else
                      {key: row[key] for key in ('reason', 'sha256', 'bytes', 'mode')}) for name, row in fixtures.items()}
    return {'schema_version': 1, 'kind': 'strict_current_source_identity_fence', 'source_root': str(root),
            'root_identity': root_row, 'HEAD': head, 'index_path': str(index), 'index_identity': index_row,
            'selection_names': names, 'source_files_identity': files, 'source_directories_identity': directories,
            'excluded_upstream_fixture_identity': fixtures, 'absent_indexed_source_paths': absent,
            'source_manifest_sha256': hashlib.sha256(exporter.canonical(selected)).hexdigest(),
            'excluded_upstream_qa_sha256': hashlib.sha256(exporter.canonical(excluded)).hexdigest(),
            'source_scope_held_for_strict_export': False, 'source_lock_attested': False,
            'transient_write_and_restore_absence_attested': False, 'production_release_approval': False}


def compare(expected, actual):
    if expected != actual:
        changed = sorted(key for key in expected.keys() | actual.keys() if expected.get(key) != actual.get(key))
        raise ValueError('root-pinned source identity/index/membership/fixture drift: ' + ', '.join(changed))


def save(path, value):
    with Path(path).open('xb') as output:
        output.write(canonical(value)); output.flush(); os.fsync(output.fileno())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('capture', 'verify'))
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--binding', type=Path)
    parser.add_argument('--binding-sha256')
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise ValueError('new retained source-fence output must be absent')
    actual = capture(args.root)
    if args.mode == 'verify':
        if not args.binding or not re.fullmatch('[0-9a-f]{64}', args.binding_sha256 or ''):
            raise ValueError('verify requires exact root-pinned source fence')
        row = stable(args.binding)
        if row['sha256'] != args.binding_sha256:
            raise ValueError('root-pinned source fence file changed')
        expected = json.loads(args.binding.read_text())
        compare(expected, actual)
        if stable(args.binding) != row:
            raise ValueError('root source-fence binding raced during verification')
    save(args.output, actual)
    print(json.dumps({'source_identity_fence': 'pass', 'selected_files': len(actual['source_files_identity']),
                      'excluded_fixture_paths': len(actual['excluded_upstream_fixture_identity']),
                      'source_manifest_sha256': actual['source_manifest_sha256'], 'source_lock_attested': False,
                      'production_release_approval': False}, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
