#!/usr/bin/env python3
"""Bounded recheck after the reviewed pre-observation local stop fix."""
import concurrent.futures
import json
import os
import pathlib
import run_checks as checks

PARENT = pathlib.Path(__file__).resolve().parent
OUTPUT = PARENT / 'attempt3-urgent-stop'


def main():
    OUTPUT.mkdir(exist_ok=False)
    previous = json.loads((PARENT / 'attempt2/sources-before.json').read_text())
    sources = [pathlib.Path(name) for name in previous]
    sources.append(pathlib.Path(__file__).resolve())
    dependencies = [pathlib.Path(name) for name in json.loads((PARENT / 'attempt2/dependencies-before.json').read_text())]
    links = [pathlib.Path(name) for name in json.loads((PARENT / 'attempt2/dependency-links-before.json').read_text())]
    before = checks.inventory(sources)
    dependency_before = checks.inventory(dependencies)
    links_before = {str(path): os.readlink(path) for path in links}
    checks.write(OUTPUT / 'sources-before.json', before)
    checks.write(OUTPUT / 'dependencies-before.json', dependency_before)
    checks.write(OUTPUT / 'dependency-links-before.json', links_before)
    checks.LEAF = OUTPUT
    commands = {
        'tsc': ([str(checks.NODE), str(checks.TOOLS / 'node_modules/typescript/bin/tsc'), '--noEmit'], 120),
        'node-controls': ([str(checks.NODE), '--experimental-strip-types', '--test', '--test-concurrency=1', '--test-timeout=30000',
                           'src/unattended_scheduler_control.test.ts'], 180),
    }
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        futures = {name: executor.submit(checks.execute, name, *value) for name, value in commands.items()}
        results = {name: future.result() for name, future in futures.items()}
    after = checks.inventory(sources)
    dependency_after = checks.inventory(dependencies)
    links_after = {str(path): os.readlink(path) for path in links}
    checks.write(OUTPUT / 'sources-after.json', after)
    checks.write(OUTPUT / 'dependencies-after.json', dependency_after)
    checks.write(OUTPUT / 'dependency-links-after.json', links_after)
    result = {'source_inputs': len(before), 'dependency_inputs': len(dependency_before),
              'source_unchanged': before == after, 'dependencies_unchanged': dependency_before == dependency_after,
              'dependency_links_unchanged': links_before == links_after,
              'changed_since_attempt2': [name for name in previous if previous[name] != before[name]],
              'commands': results, 'host_job_installed': False, 'host_job_started': False, 'hosted_calls': False,
              'keychain_calls': False, 'sender_actions': 0, 'full_history_regression_executed': False,
              'pass': before == after and dependency_before == dependency_after and links_before == links_after and
                      all(value['exit_code'] == 0 and not value['timed_out'] for value in results.values())}
    checks.write(OUTPUT / 'verification.json', result)
    print(json.dumps(result, indent=2))
    return 0 if result['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
