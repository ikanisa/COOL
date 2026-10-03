#!/usr/bin/python3
"""Prepare a hash-bound macOS scheduler job; never install, load or start it."""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import re
import shlex
import stat
import tempfile


def selected_path(value):
    path = pathlib.Path(value)
    if not path.is_absolute() or any(c in str(path) for c in '\n\r\0\\'):
        raise ValueError('SCHEDULER_PATH_INVALID')
    return path


def digest(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid()
                or before.st_nlink != 1 or before.st_mode & 0o022
                or before.st_size > 256 * 1024 * 1024):
            raise ValueError('SCHEDULER_INPUT_UNVERIFIED')
        checksum = hashlib.sha256()
        length = 0
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            length += len(block)
            if length > 256 * 1024 * 1024:
                raise ValueError('SCHEDULER_INPUT_LIMIT')
            checksum.update(block)
        for after in [os.fstat(stream.fileno()), path.lstat()]:
            if any(getattr(after, name) != getattr(before, name) for name in [
                    'st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_nlink', 'st_size',
                    'st_mtime_ns', 'st_ctime_ns']) or length != before.st_size:
                raise ValueError('SCHEDULER_INPUT_DRIFT')
    return checksum.hexdigest()


def no_links(path):
    for item in [path, *path.parents]:
        if item.is_symlink():
            raise ValueError('SCHEDULER_SOURCE_LINK_REFUSED')


def private_file(path, maximum=8192):
    no_links(path)
    info = path.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1
            or info.st_size > maximum):
        raise ValueError('SCHEDULER_PROFILE_NOT_PRIVATE')
    parent = path.parent.lstat()
    if parent.st_uid != os.getuid() or stat.S_IMODE(parent.st_mode) != 0o700:
        raise ValueError('SCHEDULER_PROFILE_NOT_PRIVATE')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as stream:
        current = os.fstat(stream.fileno())
        if any(getattr(current, name) != getattr(info, name) for name in [
                'st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_nlink', 'st_size',
                'st_mtime_ns', 'st_ctime_ns']):
            raise ValueError('SCHEDULER_PROFILE_DRIFT')
        data = stream.read(maximum + 1)
        if len(data) != info.st_size or len(data) > maximum:
            raise ValueError('SCHEDULER_PROFILE_DRIFT')
        for after in [os.fstat(stream.fileno()), path.lstat()]:
            if any(getattr(after, name) != getattr(info, name) for name in [
                    'st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_nlink', 'st_size',
                    'st_mtime_ns', 'st_ctime_ns']):
                raise ValueError('SCHEDULER_PROFILE_DRIFT')
        return data


def bound_profile(path):
    data = private_file(path)
    profile = json.loads(data)
    expected = {'contract_version', 'scope', 'identity', 'helper_path',
                'helper_sha256', 'journal_directory'}
    if 'key_tag_id' in profile:
        expected.add('key_tag_id')
    uuid = r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    if (set(profile) != expected or type(profile['contract_version']) is not int
            or profile['contract_version'] != 2 or profile['scope'] != 'rw_receipt_operations'
            or set(profile['identity']) != {'principalId', 'keySha256', 'expiresAt'}
            or not re.fullmatch(uuid, profile['identity']['principalId'])
            or not re.fullmatch(r'[0-9a-f]{64}', profile['identity']['keySha256'])
            or not re.fullmatch(r'[0-9a-f]{64}', profile['helper_sha256'])
            or not isinstance(profile['identity']['expiresAt'], str)
            or 'key_tag_id' in profile and not re.fullmatch(uuid, profile['key_tag_id'])
            or (json.dumps(profile, separators=(',', ':'), ensure_ascii=False) + '\n').encode() != data):
        raise ValueError('SCHEDULER_PROFILE_INVALID')
    helper = selected_path(profile['helper_path'])
    no_links(helper)
    info = helper.lstat()
    parent = helper.parent.lstat()
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_nlink != 1 or info.st_mode & 0o022 or not info.st_mode & 0o100
            or info.st_size < 1 or info.st_size > 16 * 1024 * 1024
            or parent.st_uid != os.getuid() or stat.S_IMODE(parent.st_mode) != 0o700
            or digest(helper) != profile['helper_sha256']):
        raise ValueError('SCHEDULER_HELPER_UNVERIFIED')
    journal = selected_path(profile['journal_directory'])
    no_links(journal)
    info = journal.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('SCHEDULER_JOURNAL_NOT_PRIVATE')
    return profile, helper, hashlib.sha256(data).hexdigest()


def publish(path, data):
    descriptor, temporary = tempfile.mkstemp(prefix='.prepare-', dir=str(path.parent))
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        # No replacement of an existing deployment or unknown earlier outcome.
        os.link(temporary, path)
        os.unlink(temporary)
        directory = os.open(str(path.parent), os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def prepare(profile_path, node_path, source_directory, output_directory,
            interval_seconds=60, max_events=5):
    if not 60 <= interval_seconds <= 3600 or not 1 <= max_events <= 10:
        raise ValueError('SCHEDULER_LIMIT_INVALID')
    profile = selected_path(profile_path)
    node = selected_path(node_path)
    source = selected_path(source_directory)
    no_links(node)
    no_links(source)
    node = node.resolve(strict=True)
    source = source.resolve(strict=True)
    output = selected_path(output_directory)
    if output.exists() or output.is_symlink():
        raise ValueError('SCHEDULER_OUTPUT_ALREADY_EXISTS')
    for ancestor in output.parents:
        if ancestor.is_symlink():
            raise ValueError('SCHEDULER_OUTPUT_LINK_REFUSED')
    if not source.is_dir() or not node.is_file() or not os.access(node, os.X_OK):
        raise ValueError('SCHEDULER_RUNTIME_UNAVAILABLE')
    profile_data, helper, profile_sha = bound_profile(profile)
    entrypoint = source / 'src' / 'unattended_host_tick.ts'
    if not entrypoint.is_file() or not (source / 'node_modules').is_dir():
        raise ValueError('SCHEDULER_SOURCE_UNAVAILABLE')
    # Bind every local module and installed runtime dependency byte. This is
    # an execution-drift guard, not a publisher/provenance approval or an SBOM.
    inputs = {node, profile, helper}
    dependency_links = {}
    for name in ['package.json', 'pnpm-lock.yaml']:
        file = source / name
        if not file.is_file():
            raise ValueError('SCHEDULER_DEPENDENCY_UNAVAILABLE')
        inputs.add(file.resolve())
    for root in [source / 'src', source / 'node_modules']:
        if root.is_symlink():
            raise ValueError('SCHEDULER_SOURCE_LINK_REFUSED')
        for file in root.rglob('*'):
            if root.name == 'node_modules' and '.bin' in file.relative_to(root).parts:
                continue  # Package-manager command links are never invoked.
            if file.is_symlink():
                # Normal pnpm package links are accepted only inside the
                # installed dependency tree and are pinned before Node loads.
                if root.name != 'node_modules':
                    raise ValueError('SCHEDULER_SOURCE_LINK_REFUSED')
                target = os.readlink(file)
                if os.path.isabs(target) or any(c in target for c in '\n\r\0\\'):
                    raise ValueError('SCHEDULER_SOURCE_LINK_REFUSED')
                try:
                    file.resolve(strict=True).relative_to(root)
                except (ValueError, OSError):
                    raise ValueError('SCHEDULER_SOURCE_LINK_REFUSED')
                dependency_links[str(file)] = target
                continue
            if file.is_file():
                inputs.add(file.resolve(strict=True))
                if len(inputs) > 20000:
                    raise ValueError('SCHEDULER_INPUT_LIMIT')
    if len(inputs) > 20000:
        raise ValueError('SCHEDULER_INPUT_LIMIT')
    if sum(file.lstat().st_size for file in inputs) > 512 * 1024 * 1024:
        raise ValueError('SCHEDULER_INPUT_LIMIT')
    hashes = {str(file): digest(file) for file in sorted(inputs)}
    if any(any(c in name for c in '\n\r\0\\') for name in hashes):
        raise ValueError('SCHEDULER_PATH_INVALID')
    output.mkdir(mode=0o700)
    if stat.S_IMODE(output.stat().st_mode) != 0o700 or output.stat().st_uid != os.getuid():
        raise ValueError('SCHEDULER_OUTPUT_NOT_PRIVATE')
    (output / 'control').mkdir(mode=0o700)
    (output / 'diagnostics').mkdir(mode=0o700)
    checks = output / 'runtime.sha256'
    wrapper = output / 'tick.sh'
    plist = output / 'com.ikanisa.collect.receipt-operations.plist'
    command = [str(node), '--experimental-strip-types', str(entrypoint), '--deployment', str(output)]
    shell = '#!/bin/sh\nset -eu\n/usr/bin/env -i PATH=/usr/bin:/bin LANG=C /usr/bin/shasum -a 256 -c ' + shlex.quote(str(checks)) + ' >/dev/null 2>&1 || exit 78\n'
    for name, target in sorted(dependency_links.items()):
        shell += '[ "$(/usr/bin/env -i PATH=/usr/bin:/bin LANG=C /usr/bin/readlink ' + shlex.quote(name) + ')" = ' + shlex.quote(target) + ' ] || exit 78\n'
    shell += 'exec /usr/bin/env -i PATH=/usr/bin:/bin LANG=C ' + ' '.join(shlex.quote(value) for value in command) + '\n'
    job = {'Label': 'com.ikanisa.collect.receipt-operations',
           'ProgramArguments': ['/bin/sh', str(wrapper)], 'StartInterval': interval_seconds,
           'RunAtLoad': False, 'KeepAlive': False, 'ProcessType': 'Background',
           'ThrottleInterval': interval_seconds, 'Umask': 63,
           'EnvironmentVariables': {'PATH': '/usr/bin:/bin', 'LANG': 'C'},
           'StandardOutPath': '/dev/null', 'StandardErrorPath': '/dev/null'}
    publish(checks, ''.join('{}  {}\n'.format(value, name) for name, value in hashes.items()).encode())
    publish(wrapper, shell.encode())
    publish(plist, plistlib.dumps(job, fmt=plistlib.FMT_XML, sort_keys=True))
    result = {'contract_version': 2, 'kind': 'prepared_launchd_job',
              'installed': False, 'started': False, 'credentials_created': False,
              'profile_verified': False, 'interval_seconds': interval_seconds,
              'max_events': max_events, 'uid': os.getuid(),
              'label': 'com.ikanisa.collect.receipt-operations',
              'origin': 'https://lhbowpbcpwoiparwnwgt.supabase.co',
              'scope': 'rw_receipt_operations', 'profile_path': str(profile),
              'profile_sha256': profile_sha, 'identity': profile_data['identity'],
              'helper_path': str(helper), 'helper_sha256': profile_data['helper_sha256'],
              'key_tag_id': profile_data.get('key_tag_id'),
              'journal_directory': profile_data['journal_directory'],
              'node_path': str(node), 'source_directory': str(source), 'runtime_inputs': hashes,
              'dependency_links': dependency_links,
              'artifacts': {file.name: digest(file) for file in [checks, wrapper, plist]}}
    encoded = (json.dumps(result, indent=2, sort_keys=True) + '\n').encode()
    if len(encoded) > 4 * 1024 * 1024:
        raise ValueError('SCHEDULER_INPUT_LIMIT')
    publish(output / 'PREPARATION.json', encoded)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['profile', 'node', 'source-directory', 'output-directory']:
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--interval-seconds', type=int, default=60)
    parser.add_argument('--max-events', type=int, default=5)
    arguments = parser.parse_args()
    try:
        result = prepare(arguments.profile, arguments.node, arguments.source_directory,
                         arguments.output_directory, arguments.interval_seconds, arguments.max_events)
    except Exception:
        print(json.dumps({'status': 'SCHEDULER_PREPARATION_REFUSED', 'installed': False,
                          'started': False, 'credentials_created': False}))
        return 2
    print(json.dumps({'status': 'SCHEDULER_PREPARED', 'installed': False, 'started': False,
                      'runtime_input_count': len(result['runtime_inputs'])}))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
