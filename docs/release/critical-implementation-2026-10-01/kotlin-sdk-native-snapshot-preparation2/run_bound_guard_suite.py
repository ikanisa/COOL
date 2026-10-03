#!/usr/bin/env python3
"""Run unchanged guard suites in new private fixtures with retained source fences."""
import argparse
import hashlib
import importlib.util
import json
import os
import stat
import sys
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORIGINAL = HERE.parent / 'kotlin-sdk-native-consumer-preparation1'
ORIGINAL_MANIFEST = '9f08883dc0db884cee715d30e1c0efda31f5285d614aae0acc69da7418dc73bc'
SUITES = {'snapshot': ('test_snapshot_guards.py', 34), 'original': ('test_original_guards.py', 31)}


def identity(row):
    return (row.st_dev, row.st_ino, row.st_size, row.st_mode, row.st_nlink,
            row.st_mtime_ns, row.st_ctime_ns, row.st_uid, row.st_gid)


def fingerprint(path, system_git=False):
    path = Path(path)
    if path.resolve() != path:
        raise ValueError('suite source has aliased ancestor or leaf')
    before = path.lstat()
    system_git_allowed = system_git and path == Path('/usr/bin/git') and before.st_uid == 0
    if not stat.S_ISREG(before.st_mode) or (before.st_nlink != 1 and not system_git_allowed):
        raise ValueError('suite source must be independent regular file')
    digest = hashlib.sha256()
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as source:
        if identity(os.fstat(source.fileno())) != identity(before):
            raise ValueError('suite source raced during FD opening')
        for chunk in iter(lambda: source.read(1024**2), b''):
            digest.update(chunk)
        if identity(os.fstat(source.fileno())) != identity(before):
            raise ValueError('suite source mutated during reading')
    if identity(path.lstat()) != identity(before):
        raise ValueError('suite source named leaf replaced')
    return {'sha256': digest.hexdigest(), 'bytes': before.st_size, 'device': before.st_dev,
            'inode': before.st_ino, 'mode': stat.S_IMODE(before.st_mode), 'nlink': before.st_nlink,
            'mtime_ns': before.st_mtime_ns, 'ctime_ns': before.st_ctime_ns,
            'uid': before.st_uid, 'gid': before.st_gid}


def save(path, value):
    with Path(path).open('x') as output:
        json.dump(value, output, indent=2, sort_keys=True); output.write('\n')
        output.flush(); os.fsync(output.fileno())


def inputs():
    manifest = ORIGINAL / 'packet-files.json'
    if fingerprint(manifest)['sha256'] != ORIGINAL_MANIFEST:
        raise ValueError('original frozen preparation differs')
    entries = json.loads(manifest.read_text())['files']
    paths = [manifest, *(ORIGINAL / name for name in entries),
             *(HERE / name for name in ('run_native_consumer.py', 'source_fence.py', 'proposed-commands.json',
                                        'test_snapshot_guards.py', 'test_original_guards.py', 'run_bound_guard_suite.py'))]
    rows = {str(path): fingerprint(path) for path in paths}
    for name, expected in entries.items():
        if Path(name).is_absolute() or '..' in Path(name).parts or rows[str(ORIGINAL/name)]['sha256'] != expected:
            raise ValueError('original frozen guard dependency changed')
    config = json.loads((HERE/'proposed-commands.json').read_text())
    python = Path(config['Python_executable'])
    if str(Path(sys.executable).resolve()) != str(python.resolve()) or fingerprint(python)['sha256'] != config['Python_SHA256']:
        raise ValueError('exact reviewed Python runtime required')
    rows[str(python.resolve())] = fingerprint(python.resolve())
    # This read-only macOS system tool can have several signed-system links.
    # Preserve its actual nlink/hash/identity; never treat it as a copied source leaf.
    rows['/usr/bin/git'] = fingerprint(Path('/usr/bin/git'), system_git=True)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', required=True, choices=SUITES)
    parser.add_argument('--fixture-root', required=True, type=Path)
    args = parser.parse_args()
    fixture_root = args.fixture_root
    if (fixture_root.parent != HERE/'negative-fixtures' or fixture_root.exists() or fixture_root.is_symlink()
            or fixture_root.absolute() != fixture_root or fixture_root.parent.resolve() != fixture_root.parent):
        raise ValueError('new fixture root must be absent and private to this proposal')
    before = inputs()
    save(HERE/(args.suite+'-bound-before.json'), {'files': before, 'suite': args.suite,
         'fixture_root': str(fixture_root), 'previous_negative_fixtures_executed': False,
         'real_app_export_SDK_Gradle_native_executed': False})
    script, expected = SUITES[args.suite]
    spec = importlib.util.spec_from_file_location('source_bound_'+args.suite, HERE/script)
    suite_module = importlib.util.module_from_spec(spec); spec.loader.exec_module(suite_module)
    suite_module.FIXTURES = fixture_root
    suite = unittest.TestLoader().loadTestsFromModule(suite_module)
    if suite.countTestCases() != expected:
        raise ValueError('exact guard suite count differs before execution')
    started = time.monotonic()
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    after = inputs()
    unchanged = before == after
    receipt = {'suite': args.suite, 'expected_tests': expected, 'actual_tests_run': result.testsRun,
               'actual_seconds': round(time.monotonic()-started, 6), 'failures': len(result.failures),
               'errors': len(result.errors), 'skips': len(result.skipped),
               'source_inputs_unchanged': unchanged, 'files': after,
               'fixture_root': str(fixture_root), 'fixture_override_changes_output_path_only': True,
               'real_app_export_SDK_Gradle_native_executed': False,
               'previous_negative_fixtures_executed': False, 'production_ready': False}
    save(HERE/(args.suite+'-bound-after.json'), receipt)
    if not unchanged:
        raise ValueError('actual suite source/tool/identity changed during execution')
    return 0 if result.wasSuccessful() and not result.skipped and result.testsRun == expected else 1


if __name__ == '__main__':
    raise SystemExit(main())
