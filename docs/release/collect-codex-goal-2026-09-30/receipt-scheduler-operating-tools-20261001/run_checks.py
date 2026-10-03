#!/usr/bin/env python3
"""Scoped local proof. No daemon, credentials, hosted API or Keychain calls."""
import concurrent.futures
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[4]
LEAF = pathlib.Path(__file__).resolve().parent
TOOLS = ROOT / 'tools/collect-notification-mcp'
NODE = pathlib.Path('/Volumes/PRO-G40/Development/Node/bin/node').resolve()


def digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def inventory(paths):
    return {str(path): digest(path) for path in sorted(set(paths))}


def execute(name, command, limit):
    started = time.time()
    log = LEAF / (name + '.log')
    try:
        with log.open('wb') as output:
            child = subprocess.run(command, cwd=TOOLS, env={
                'PATH': '/usr/bin:/bin', 'LANG': 'C', 'PYTHONUTF8': '1',
                'PYTHONDONTWRITEBYTECODE': '1'}, stdout=output, stderr=subprocess.STDOUT,
                timeout=limit)
        return {'command': command, 'exit_code': child.returncode,
                'elapsed_seconds': round(time.time() - started, 3), 'timed_out': False}
    except subprocess.TimeoutExpired:
        return {'command': command, 'exit_code': None, 'timed_out': True,
                'elapsed_seconds': round(time.time() - started, 3)}


def main():
    if (LEAF / 'verification.json').exists():
        raise RuntimeError('Existing evidence is immutable; use a distinct attempt leaf')
    sources = list((TOOLS / 'src').rglob('*.ts')) + list((TOOLS / 'src').rglob('*.swift'))
    sources += [TOOLS / name for name in ['package.json', 'pnpm-lock.yaml', 'tsconfig.json']]
    sources += [TOOLS / 'scripts/prepare_unattended_launchd.py', ROOT / 'scripts/tests/unattended_launchd_preparation_test.py', pathlib.Path(__file__).resolve()]
    # The existing signed synthetic Edge test fixture imports these modules.
    sources += list((ROOT / 'supabase/functions/collect-receipt-supervisor').rglob('*.ts'))
    before = inventory(sources)
    dependencies = [path for path in (TOOLS / 'node_modules').rglob('*')
                    if path.is_file() and not path.is_symlink() and '.bin' not in path.parts]
    dependency_before = inventory(dependencies + [NODE])
    links = [path for path in (TOOLS / 'node_modules').rglob('*') if path.is_symlink() and '.bin' not in path.parts]
    links_before = {str(path): os.readlink(path) for path in links}
    write(LEAF / 'sources-before.json', before)
    write(LEAF / 'dependencies-before.json', dependency_before)
    write(LEAF / 'dependency-links-before.json', links_before)
    commands = {
        'tsc': ([str(NODE), str(TOOLS / 'node_modules/typescript/bin/tsc'), '--noEmit'], 120),
        'node-focused': ([str(NODE), '--experimental-strip-types', '--test', '--test-concurrency=1', '--test-timeout=30000',
                          'src/unattended_scheduler_control.test.ts', 'src/unattended_scheduler.test.ts'], 180),
        'python-preparation': (['/usr/bin/python3', str(ROOT / 'scripts/tests/unattended_launchd_preparation_test.py')], 60),
    }
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = {name: executor.submit(execute, name, *args) for name, args in commands.items()}
        results = {name: future.result() for name, future in futures.items()}
    after = inventory(sources)
    dependency_after = inventory(dependencies + [NODE])
    links_after = {str(path): os.readlink(path) for path in links}
    write(LEAF / 'sources-after.json', after)
    write(LEAF / 'dependencies-after.json', dependency_after)
    write(LEAF / 'dependency-links-after.json', links_after)
    result = {'source_inputs': len(before), 'dependency_inputs': len(dependency_before),
              'source_unchanged': before == after, 'dependencies_unchanged': dependency_before == dependency_after,
              'dependency_links_unchanged': links_before == links_after,
              'commands': results, 'host_job_installed': False, 'host_job_started': False,
              'hosted_calls': False, 'keychain_calls': False, 'sender_actions': 0,
              'full_history_regression_executed': False,
              'pass': before == after and dependency_before == dependency_after and links_before == links_after and
                      all(value['exit_code'] == 0 and not value['timed_out'] for value in results.values())}
    write(LEAF / 'verification.json', result)
    print(json.dumps(result, indent=2))
    return 0 if result['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
