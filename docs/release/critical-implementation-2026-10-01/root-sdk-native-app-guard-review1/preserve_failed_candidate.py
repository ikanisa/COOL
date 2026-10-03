#!/usr/bin/env python3
"""Plan read-only; preserve only the exact reviewed failed candidate by renames."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
REPO = RELEASE.parents[2]
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
PREP = RELEASE / 'kotlin-sdk-native-app-guard-preparation1'
ORIGINAL = RELEASE / 'kotlin-sdk-native-consumer-preparation1'
AUTHORITY = RELEASE / 'root-tooling-source-integration1/current-source-after-drop-correction.json'
MANIFEST_SHA = '509a1d3cd394276dd39447893596edc7066acb76981df32ba4300af8fb7cb78f'
AUTHORITY_SHA = '3d2e02e3acafe61bc3d6a7f98858c0c4f0442e1f4f253dc594a341116bca07ae'
READER_SHA = 'c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25'
ROOTS = {'app-source': BASE / 'app-source', 'app-export-control': BASE / '.control/app-export',
         'app-lock-control': BASE / '.control/app-lock'}
FLOOR = 4 * 1024**3
MAX_NODES = 200000
MAX_BYTES = 8 * 1024**3
DEADLINE = time.monotonic() + 300


def require(condition, message):
    if not condition:
        raise ValueError(message)


def bounded():
    require(time.monotonic() < DEADLINE, '300 second preservation/readback bound exceeded')
    require(shutil.disk_usage(BASE).free >= FLOOR and shutil.disk_usage(HERE).free >= FLOOR,
            '4 GiB live floor absent')


def physical(path):
    require(path.is_absolute() and '..' not in path.parts, 'nonliteral path')
    for parent in reversed((path, *path.parents)):
        require(stat.S_ISDIR(parent.lstat().st_mode), 'physical directory ancestor required: ' + str(parent))
    return path


def identity(row):
    return {name: getattr(row, attribute) for name, attribute in (
        ('dev', 'st_dev'), ('ino', 'st_ino'), ('mode', 'st_mode'), ('nlink', 'st_nlink'),
        ('size', 'st_size'), ('mtime_ns', 'st_mtime_ns'), ('ctime_ns', 'st_ctime_ns'),
        ('uid', 'st_uid'), ('gid', 'st_gid'))}


def safe_bytes(path, retain=False):
    bounded()
    physical(path.parent)
    before = identity(path.lstat())
    require(stat.S_ISREG(before['mode']) and before['nlink'] == 1
            and not before['mode'] & (stat.S_ISUID | stat.S_ISGID), 'unsafe regular leaf: ' + str(path))
    result, body = READER.stable_read(path, retain)
    require(identity(path.lstat()) == before, 'regular leaf identity raced: ' + str(path))
    return {**before, 'sha256': result['sha256']}, body


def document(path, expected=None):
    row, body = safe_bytes(path, True)
    require(expected is None or row['sha256'] == expected, 'pinned document differs: ' + str(path))
    return json.loads(body), row['sha256']


def digest(value):
    return hashlib.sha256((json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()).hexdigest()


def save(path, value):
    physical(path.parent)
    with path.open('x', encoding='utf-8') as output:
        json.dump(value, output, indent=2, sort_keys=True)
        output.write('\n')
        output.flush()
        os.fsync(output.fileno())
    return safe_bytes(path)[0]['sha256']


def bindings():
    packet, _ = document(PREP / 'packet-files.json', MANIFEST_SHA)
    require(packet['leaf_count'] == 87 and len(packet['files']) == 87, 'final packet count differs')
    for name in ('actual-failed-candidate-app-readback.json', 'consumer_guards.py',
                 'run_native_consumer.py', 'source_fence.py'):
        require(safe_bytes(PREP / name)[0]['sha256'] == packet['files'][name], 'selected sealed leaf differs')
    proof, _ = document(PREP / 'actual-failed-candidate-app-readback.json',
                        packet['files']['actual-failed-candidate-app-readback.json'])
    links = proof['exact_generated_swiftpm_links']
    require(len(links) == 13 and all(row['link_not_traversed'] is True for row in links.values()),
            'sealed raw link proof differs')
    authority, _ = document(AUTHORITY, AUTHORITY_SHA)
    source_hashes = authority['after_sha256']
    require(len(source_hashes) == 12, 'current DROP source authority count differs')
    for name, expected in source_hashes.items():
        relative = Path(name)
        require(not relative.is_absolute() and '..' not in relative.parts, 'source authority path unsafe')
        require(safe_bytes(REPO / relative)[0]['sha256'] == expected, 'current DROP source differs: ' + name)
    return links


def inventory(root, content=True):
    physical(root)
    rows = {}
    total = 0
    pending = [(root, '.')]
    while pending:
        bounded()
        path, name = pending.pop()
        before = identity(path.lstat())
        require(not before['mode'] & (stat.S_ISUID | stat.S_ISGID), 'special mode: ' + name)
        if stat.S_ISDIR(before['mode']):
            rows[name] = {'kind': 'directory', **before}
            with os.scandir(path) as entries:
                children = sorted((entry.name for entry in entries), reverse=True)
            require(identity(path.lstat()) == before, 'directory raced: ' + name)
            pending.extend((path / child, child if name == '.' else name + '/' + child) for child in children)
        elif stat.S_ISLNK(before['mode']):
            require(before['nlink'] == 1, 'aliased link: ' + name)
            target = os.readlink(path)  # Never stat, resolve, open or traverse the target.
            require(identity(path.lstat()) == before, 'raw link raced: ' + name)
            rows[name] = {'kind': 'symlink', **before, 'literal_target': target}
        elif stat.S_ISREG(before['mode']):
            require(before['nlink'] == 1, 'aliased regular leaf: ' + name)
            total += before['size']
            require(total <= MAX_BYTES, '8 GiB inventory byte bound exceeded')
            record = safe_bytes(path)[0] if content else before
            rows[name] = {'kind': 'regular', **record}
        else:
            raise ValueError('special file refused: ' + name)
        require(len(rows) <= MAX_NODES, 'inventory node bound exceeded')
    return rows


def stable_inventory(root):
    rows = inventory(root)
    identity_only = {name: {key: value for key, value in row.items() if key != 'sha256'}
                     for name, row in rows.items()}
    require(inventory(root, False) == identity_only, 'inventory membership or node identity changed')
    return rows


def failed_pair():
    export, export_sha = document(ROOTS['app-export-control'] / 'terminal.json')
    lock, lock_sha = document(ROOTS['app-lock-control'] / 'terminal.json')
    require(export.get('stage') == 'app-export' and export.get('stage_pass') is True,
            'expected old app-export terminal absent')
    require(lock.get('stage') == 'app-lock' and lock.get('stage_pass') is False
            and lock.get('retry_or_next_stage_admitted') is False,
            'expected whole failed app-lock terminal absent')
    return {'app-export': export_sha, 'app-lock': lock_sha,
            'whole_app_lock_failed': True, 'old_export_not_admitted_for_retry': True}


def raw_links(rows):
    return {name: row for name, row in rows.items() if row['kind'] == 'symlink'}


def check_links(rows, expected):
    actual = raw_links(rows)
    require(set(actual) == set(expected), 'raw generated link membership differs from sealed evidence')
    for name, proof in expected.items():
        require(actual[name]['literal_target'] == proof['literal_target'], 'raw link target differs: ' + name)
        require(all(actual[name][key] == value for key, value in proof['link_identity'].items()),
                'raw link identity differs from sealed evidence: ' + name)


def plan():
    links = bindings()
    terminal = failed_pair()
    trees = {name: stable_inventory(root) for name, root in ROOTS.items()}
    check_links(trees['app-source'], links)
    require(all(not raw_links(trees[name]) for name in ROOTS if name != 'app-source'), 'control link refused')
    require(failed_pair() == terminal, 'failed terminals raced')
    archive_parent = physical(BASE / '.failed-attempts')
    archive = archive_parent / ('app-lock-20261002-attempt1-' + uuid.uuid4().hex)
    require(not os.path.lexists(archive), 'unique archive already exists')
    value = {'kind': 'review_only_failed_native_preservation_plan', 'schema': 1,
             'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'helper_sha256': safe_bytes(Path(__file__))[0]['sha256'],
             'prepared_manifest_sha256': MANIFEST_SHA, 'current12_authority_sha256': AUTHORITY_SHA,
             'archive_root': str(archive), 'archive_parent_identity': identity(archive_parent.lstat()),
             'terminal_binding': terminal, 'roots': {name: str(root) for name, root in ROOTS.items()},
             'trees': trees, 'tree_sha256': {name: digest(rows) for name, rows in trees.items()},
             'raw_symlink_count': 13, 'symlink_targets_followed': False,
             'root_directory_ctime_may_change_only_due_to_rename': True,
             'multi_tree_atomic_transaction_claimed': False, 'stage_admission': False,
             'source_scope_held_for_strict_export': False, 'source_lock_attested': False,
             'transient_write_and_restore_absence_attested': False}
    sha = save(HERE / 'preservation-plan.json', value)
    print(json.dumps({'plan_sha256': sha, 'archive_root': str(archive),
                      'nodes': {name: len(rows) for name, rows in trees.items()}, 'stage_admission': False}))


def preserve(expected):
    require(expected is not None and len(expected) == 64 and all(c in '0123456789abcdef' for c in expected),
            'root-reviewed plan SHA required')
    value, _ = document(HERE / 'preservation-plan.json', expected)
    require(value['helper_sha256'] == safe_bytes(Path(__file__))[0]['sha256']
            and value['prepared_manifest_sha256'] == MANIFEST_SHA
            and value['current12_authority_sha256'] == AUTHORITY_SHA
            and value['roots'] == {name: str(root) for name, root in ROOTS.items()}
            and value['stage_admission'] is False, 'reviewed plan scope differs')
    links = bindings()
    require(failed_pair() == value['terminal_binding'], 'failed terminals differ from plan')
    for name, root in ROOTS.items():
        rows = stable_inventory(root)
        require(rows == value['trees'][name] and digest(rows) == value['tree_sha256'][name],
                'reviewed tree bytes or identities differ: ' + name)
    check_links(value['trees']['app-source'], links)
    archive = Path(value['archive_root'])
    require(archive.parent == BASE / '.failed-attempts'
            and archive.name.startswith('app-lock-20261002-attempt1-')
            and len(archive.name.removeprefix('app-lock-20261002-attempt1-')) == 32,
            'archive destination differs')
    physical(archive.parent)
    require(identity(archive.parent.lstat()) == value['archive_parent_identity'], 'archive parent changed; new plan required')
    require(not os.path.lexists(archive), 'reviewed archive destination exists')
    require(all(root.lstat().st_dev == archive.parent.lstat().st_dev for root in ROOTS.values()),
            'same-volume rename required')
    archive.mkdir(mode=0o700)
    # Separate atomic renames; preserve partial progress without rollback or deletion.
    save(archive / '00-plan-binding.json', {'plan_sha256': expected, 'stage_admission': False})
    for index, (name, root) in enumerate(ROOTS.items(), 1):
        bounded()
        require(stable_inventory(root) == value['trees'][name], 'tree raced before rename: ' + name)
        target = archive / name
        require(not os.path.lexists(target), 'archive subtree already exists')
        save(archive / (str(index).zfill(2) + '-' + name + '-intent.json'), {
            'source': str(root), 'destination': str(target), 'plan_sha256': expected,
            'expected_tree_sha256': digest(value['trees'][name]), 'stage_admission': False})
        os.rename(root, target)
        before = value['trees'][name]
        after = stable_inventory(target)
        comparable = {path: dict(row) for path, row in after.items()}
        # Rename can change ctime of the renamed directory itself; preserve all other identities.
        comparable['.']['ctime_ns'] = before['.']['ctime_ns']
        require(comparable == before and not os.path.lexists(root), 'post-rename byte/identity verification failed: ' + name)
        save(archive / (str(index).zfill(2) + '-' + name + '-verified.json'), {
            'source': str(root), 'destination': str(target), 'plan_sha256': expected,
            'tree_sha256_before': digest(before), 'tree_sha256_after': digest(after),
            'renamed_root_ctime_before': before['.']['ctime_ns'],
            'renamed_root_ctime_after': after['.']['ctime_ns'],
            'all_other_bytes_and_identities_exact': True, 'raw_symlinks_not_followed': True,
            'node_count': len(after), 'stage_admission': False})
    print(json.dumps({'archive_root': str(archive), 'all_three_renames_verified': True, 'stage_admission': False}))


def main():
    global READER
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', required=True, choices=('plan', 'preserve'))
    parser.add_argument('--plan-sha256')
    args = parser.parse_args()
    physical(HERE)
    metadata = ORIGINAL / 'publisher_metadata.py'
    physical(metadata.parent)
    before = identity(metadata.lstat())
    require(stat.S_ISREG(before['mode']) and before['nlink'] == 1
            and not before['mode'] & (stat.S_ISUID | stat.S_ISGID), 'unsafe original reader')
    descriptor = os.open(metadata, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as stream:
        require(identity(os.fstat(stream.fileno())) == before, 'original reader open raced')
        body = stream.read(1024 * 1024)
        require(stream.read(1) == b'' and hashlib.sha256(body).hexdigest() == READER_SHA,
                'original exact reader differs')
        require(identity(os.fstat(stream.fileno())) == before and identity(metadata.lstat()) == before,
                'original reader identity raced')
    spec = importlib.util.spec_from_file_location('preservation_exact_reader', metadata)
    READER = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(READER)
    require(safe_bytes(metadata)[0]['sha256'] == READER_SHA, 'original reader raced')
    plan() if args.mode == 'plan' else preserve(args.plan_sha256)


if __name__ == '__main__':
    main()
