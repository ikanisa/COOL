"""Preserve the completed failed native cohort using verified same-volume renames."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import types
import uuid

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
ROOTS = {'app-source': BASE / 'app-source',
         'app-export-control': BASE / '.control/app-export',
         'app-lock-control': BASE / '.control/app-lock',
         'native-control': BASE / '.control/native',
         'native-build': BASE / 'native-build'}


def load(path, expected, name):
    raw = path.read_bytes()
    if path.resolve() != path or hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError('reviewed preservation module differs')
    value = types.ModuleType(name)
    value.__file__ = str(path)
    exec(compile(raw, str(path), 'exec'), value.__dict__)
    return value


metadata = load(RELEASE / 'kotlin-sdk-native-consumer-preparation1/publisher_metadata.py',
    'c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25', 'preserve_reader')
previous = load(RELEASE / 'root-sdk-native-app-guard-review1/preserve_failed_candidate.py',
    'bf5598ce69f48c1068a1cffd7eb467306da64b0620ed00d606a54752b896e80e', 'preserve_inventory')
previous.READER = metadata
previous.HERE = HERE
controller = load(RELEASE / 'kotlin-sdk-native-native-stage-preparation1/run_native_consumer.py',
    '167d48b4e756043a87621feffcabccb41aca108232cfb943914b69fc5b090fe7', 'preserve_controller')
controller.reader = lambda: metadata


def completed_cohort():
    terminals = {}
    expected = {'app-export': ('0972133ee11e44e831e1cbd229fae8680524b7fc056944b08c031c4f19f2a960', True),
                'app-lock': ('42519f99f1fc439f0a0c72039dc21977afeaaba920059b0259af62c0f45a8f6c', True),
                'native': ('9211f83842a2c521cd822165abf94ebb1266d0d81b2934d2070c8b7ac41af330', False)}
    for stage, (digest, passed) in expected.items():
        terminal, _ = previous.document(BASE / '.control' / stage / 'terminal.json', digest)
        previous.require(terminal['stage'] == stage and terminal['stage_pass'] is passed,
                         'completed terminal differs')
        terminals[stage] = digest
    command, _ = previous.document(BASE / '.control/native/actual-command.json')
    diagnostic = terminal['actual_failure_diagnostics']['actual_failure_source_process']
    decoder, _ = previous.document(RELEASE / 'root-arc02-decoder-compatibility-preparation1/execution1/actual-tests.json')
    for process in (command, diagnostic, decoder):
        previous.require(process['finished_utc'] is not None and process['owned_process_group_absent'] is True,
                         'previous owned process not terminal')
        try:
            os.killpg(process['pid'], 0)
        except ProcessLookupError:
            pass
        else:
            raise ValueError('previous process group still exists')
    return terminals


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=('plan', 'preserve'), required=True)
    parser.add_argument('--plan-sha256')
    args = parser.parse_args()
    if args.mode == 'preserve':
        previous.require(isinstance(args.plan_sha256, str) and len(args.plan_sha256) == 64
                         and all(c in '0123456789abcdef' for c in args.plan_sha256), 'exact reviewed plan hash required')
    previous.physical(HERE)
    terminals = completed_cohort()
    protected = controller.protected_metadata()
    if args.mode == 'plan':
        parent = previous.physical(BASE / '.failed-attempts')
        archive = parent / ('native-20261002-attempt1-' + uuid.uuid4().hex)
        trees = {name: previous.stable_inventory(path) for name, path in ROOTS.items()}
        links = previous.raw_links(trees['app-source'])
        previous.require(len(links) == 13 and all(name.startswith('ios/Flutter/ephemeral/Packages/.packages/')
                         for name in links), 'original raw link membership differs')
        previous.require(all(not previous.raw_links(trees[name]) for name in ROOTS if name != 'app-source'),
                         'unexpected control/build link')
        value = {'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                 'script_sha256': previous.safe_bytes(Path(__file__))[0]['sha256'],
                 'archive_root': str(archive), 'parent_identity': previous.identity(parent.lstat()),
                 'roots': {name: str(path) for name, path in ROOTS.items()}, 'trees': trees,
                 'terminal_bindings': terminals, 'protected_originals': protected,
                 'raw_symlink_count': len(links), 'raw_symlinks_followed': False,
                 'individual_same_volume_atomic_renames': True, 'multi_tree_atomic_transaction_claimed': False,
                 'SDK_and_warm_pub_Gradle_caches_moved': False, 'stage_admitted': False}
        digest = previous.save(HERE / 'native-preservation-plan.json', value)
        print(json.dumps({'plan_sha256': digest, 'archive': str(archive),
                          'nodes': {name: len(rows) for name, rows in trees.items()}}))
        return
    value, _ = previous.document(HERE / 'native-preservation-plan.json', args.plan_sha256)
    previous.require(value['script_sha256'] == previous.safe_bytes(Path(__file__))[0]['sha256']
                     and value['terminal_bindings'] == terminals and value['roots'] == {name: str(p) for name,p in ROOTS.items()},
                     'reviewed preservation plan differs')
    archive = Path(value['archive_root'])
    previous.require(archive.parent == BASE / '.failed-attempts'
                     and archive.name.startswith('native-20261002-attempt1-')
                     and not os.path.lexists(archive), 'exclusive preservation target differs')
    previous.require(previous.identity(archive.parent.lstat()) == value['parent_identity'], 'archive parent changed')
    for name, root in ROOTS.items():
        previous.require(previous.stable_inventory(root) == value['trees'][name], 'tree changed before preservation')
        previous.require(root.lstat().st_dev == archive.parent.lstat().st_dev, 'same-volume rename required')
    archive.mkdir(mode=0o700)
    previous.save(archive / '00-plan-binding.json', {'plan_sha256': args.plan_sha256, 'stage_admitted': False})
    results = {}
    for index, (name, root) in enumerate(ROOTS.items(), 1):
        previous.bounded()
        before = value['trees'][name]
        previous.require(previous.stable_inventory(root) == before, 'tree raced before rename')
        target = archive / name
        previous.save(archive / f'{index:02d}-{name}-intent.json', {'source': str(root), 'destination': str(target)})
        os.rename(root, target)
        after = previous.stable_inventory(target)
        comparable = {key: dict(row) for key,row in after.items()}
        comparable['.']['ctime_ns'] = before['.']['ctime_ns']
        previous.require(comparable == before and not os.path.lexists(root), 'post-rename bytes/identities differ')
        results[name] = {'nodes': len(after), 'all_bytes_and_other_identities_exact': True,
                         'renamed_root_ctime_before': before['.']['ctime_ns'], 'renamed_root_ctime_after': after['.']['ctime_ns']}
        previous.save(archive / f'{index:02d}-{name}-verified.json', results[name])
    previous.save(HERE / 'native-preservation-readback.json', {'archive': str(archive), 'results': results,
        'protected_originals': controller.protected_metadata(), 'stage_admitted': False,
        'raw_symlinks_followed': False, 'SDK_and_warm_pub_Gradle_caches_moved': False})
    print(json.dumps({'archive': str(archive), 'all_five_renames_verified': True}))


if __name__ == '__main__':
    main()
