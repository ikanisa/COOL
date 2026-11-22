#!/usr/bin/env python3
"""Verify the imported storage-policy subset on synthetic host fixtures only.

No Android build, network, application adoption, live data, or source rewriting.
The retained original two-product runner requires obsolete complete application
trees; this runner deliberately compiles only the imported shared policy and
BuriMunsi command-store baseline against their exact supplied tests.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory() -> dict[str, str]:
    result = {}
    for folder in ('policy', 'adapters', 'burimunsi', 'tests', 'tools'):
        for path in sorted((ROOT / folder).rglob('*')):
            if '__pycache__' in path.parts or path.suffix == '.pyc':
                continue
            if path.is_symlink():
                raise ValueError('Source link refused')
            if path.is_file():
                result[path.relative_to(ROOT).as_posix()] = sha(path)
    return result


def probe(log: Path) -> dict:
    value = json.loads(log.read_text())
    if not isinstance(value, dict):
        raise ValueError('Probe did not report a result object')
    names, count = value.get('names'), value.get('checks')
    if (value.get('status') != 'passed' or type(count) is not int or count <= 0 or
            not isinstance(names, list) or len(names) != count or
            any(not isinstance(name, str) or not name for name in names) or
            len(set(names)) != count):
        raise ValueError('Probe did not report a complete nonempty set of unique passing checks')
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--kotlinc', default=shutil.which('kotlinc') or '')
    parser.add_argument('--java', default=shutil.which('java') or '')
    args = parser.parse_args()
    out = args.output.resolve()
    if out == ROOT or ROOT in out.parents:
        parser.error('Use a new evidence directory outside the imported source subset')
    out.mkdir(parents=True, exist_ok=False)
    before = inventory()
    report = {
        'scope': 'imported_storage_r3_shared_and_burimunsi_host_subset',
        'started_at': dt.datetime.now(dt.timezone.utc).isoformat(),
        'source_files': before,
        'checks': [],
        'native_build_executed': False,
        'production_adopted': False,
        'external_acceptance': 'not_executed',
    }
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    # Python-created process fixtures and Java-created host fixtures both use
    # canonical paths; this avoids macOS's /var alias without relaxing the
    # production journal's prohibition on traversing symbolic links.
    temporary_root = out / 'temporary'
    temporary_root.mkdir()
    env['TMPDIR'] = str(temporary_root)
    if args.java:
        env['PATH'] = str(Path(args.java).absolute().parent) + os.pathsep + env.get('PATH', '')

    def run(name: str, command: list[str], timeout: int = 180, inspect_probe: bool = False) -> bool:
        row = {'name': name, 'command': command, 'status': 'failed'}
        report['checks'].append(row)
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                                    capture_output=True, timeout=timeout)
            stdout, stderr = out / (name + '.stdout.log'), out / (name + '.stderr.log')
            stdout.write_text(result.stdout)
            stderr.write_text(result.stderr)
            row.update(exit_code=result.returncode, stdout_sha256=sha(stdout), stderr_sha256=sha(stderr))
            if result.returncode == 0:
                if inspect_probe:
                    row['result'] = probe(stdout)
                row['status'] = 'passed'
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            row['error'] = type(error).__name__
        print(name + ': ' + row['status'], flush=True)
        return row['status'] == 'passed'

    try:
        copies = []
        product = ROOT / 'burimunsi/core/src/main/kotlin/rw/ikanisa/storagepolicy'
        for source in sorted((ROOT / 'policy').glob('*.kt')):
            copies.append((source, product / source.name))
        for folder, destination in (('jvm', 'jvm'), ('android', 'android')):
            for source in sorted((ROOT / ('adapters/' + folder)).glob('*.kt')):
                copies.append((source, product / destination / source.name))
        valid = bool(copies) and all(copy.is_file() and sha(source) == sha(copy) for source, copy in copies)
        report['checks'].append({'name': 'exact_shared_product_copy_identity',
                                 'status': 'passed' if valid else 'failed', 'copies': len(copies)})
        missing = [name for name, value in (('kotlinc', args.kotlinc), ('java', args.java)) if not value]
        if missing:
            report['checks'].append({'name': 'host_tools', 'status': 'blocked', 'missing': missing})
        elif valid:
            tools_ready = run('kotlinc-version', [args.kotlinc, '-version'], 30)
            tools_ready = run('java-version', [args.java, '-version'], 30) and tools_ready
            if tools_ready:
                policy = sorted((ROOT / 'policy').glob('*.kt'))
                jvm = sorted((ROOT / 'adapters/jvm').glob('*.kt'))
                android = sorted((ROOT / 'adapters/android').glob('*.kt'))
                core = ROOT / 'burimunsi/core/src/main/kotlin/rw/ikanisa/burimunsi/core'
                specs = [
                    ('storage_policy', policy + [core / (name + '.kt') for name in
                      ('Values', 'OperationJournal', 'DurableOperationStore')] + [ROOT / 'tests/StoragePolicyChecks.kt'], None),
                    ('authenticated_migration', policy + jvm + android +
                     [product / 'android/BuriMunsiLifecycleStorage.kt'] +
                     sorted((ROOT / 'tests/authenticated').glob('*.kt')), 'test_authenticated_restart.py'),
                    ('durable_lifecycle', policy + jvm + sorted((ROOT / 'tests/durable').glob('*.kt')),
                     'test_process_restart.py'),
                ]
                for name, sources, restart in specs:
                    jar = temporary_root / (name + '.jar')
                    if not run(name + '-compile', [args.kotlinc, *map(str, sources), '-jvm-target', '17',
                                                   '-include-runtime', '-d', str(jar)]):
                        continue
                    if run(name, [args.java, '-Djava.io.tmpdir=' + str(temporary_root), '-jar', str(jar)],
                           inspect_probe=True) and restart:
                        run(name + '-process-restart', [sys.executable, str(ROOT / 'tests' / restart),
                                                        '--jar', str(jar)], inspect_probe=True)
    finally:
        report['source_unchanged'] = inventory() == before
        statuses = {row['status'] for row in report['checks']}
        report['local_status'] = ('failed' if 'failed' in statuses or not report['source_unchanged'] else
                                  'blocked' if 'blocked' in statuses else 'passed')
        report['finished_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
        # The disposable jars/fixtures are never delivery application artifacts.
        shutil.rmtree(temporary_root)
        (out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'local_status': report['local_status'], 'summary': str(out / 'summary.json'),
                      'production_adopted': False, 'native_build_executed': False}))
    return {'passed': 0, 'failed': 1, 'blocked': 2}[report['local_status']]


if __name__ == '__main__':
    raise SystemExit(main())
