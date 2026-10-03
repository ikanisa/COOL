#!/usr/bin/env python3
"""Associate unchanged successful scopes; copy/readback final input bytes.

This performs no tests, daemon IPC, credential access or backend requests.
"""
import hashlib
import json
import os
import pathlib
import re
import shutil

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def read(name):
    return json.loads((HERE / name).read_text())


def write(name, value):
    path = HERE / name
    with path.open('x') as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + '\n')


def relative_imports(entry):
    pending = [entry]
    selected = set()
    while pending:
        path = pending.pop().resolve()
        if path in selected:
            continue
        selected.add(path)
        for target in re.findall(r'(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s*)[\"\'](\.{1,2}/[^\"\']+)[\"\']', path.read_text()):
            imported = (path.parent / target).resolve()
            if not imported.is_relative_to(ROOT) or not imported.is_file():
                raise RuntimeError('Unexpected transitive source')
            pending.append(imported)
    return sorted(selected)


def main():
    final = read('attempt3-urgent-stop/sources-after.json')
    initial = read('sources-before.json')
    dependencies = read('attempt3-urgent-stop/dependencies-after.json')
    links = read('attempt3-urgent-stop/dependency-links-after.json')
    current = {name: digest(pathlib.Path(name)) for name in final}
    if current != final:
        raise RuntimeError('Source drift after final affected proof')
    current_dependencies = {name: digest(pathlib.Path(name)) for name in dependencies}
    if current_dependencies != dependencies or any(os.readlink(name) != target for name, target in links.items()):
        raise RuntimeError('Runtime drift after final affected proof')
    scheduler = relative_imports(ROOT / 'tools/collect-notification-mcp/src/unattended_scheduler.test.ts')
    python = [ROOT / 'scripts/tests/unattended_launchd_preparation_test.py', ROOT / 'tools/collect-notification-mcp/scripts/prepare_unattended_launchd.py']
    for path in scheduler + python:
        if initial.get(str(path)) != final.get(str(path)) or final.get(str(path)) != digest(path):
            raise RuntimeError('Associated scope changed; cannot reuse successful test')
    if read('dependencies-before.json') != dependencies or read('dependency-links-before.json') != links:
        raise RuntimeError('Associated dependency scope changed')
    bindings = {}
    for name, checksum in final.items():
        source = pathlib.Path(name)
        target = HERE / 'source' / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            stream.write(source.read_bytes())
        if digest(target) != checksum or digest(source) != checksum:
            raise RuntimeError('Source copy readback failed')
        bindings[str(target.relative_to(HERE))] = checksum
    write('source-bindings.json', {'inputs': len(bindings), 'copy_readback_pass': True, 'files': bindings})
    write('scope-association.json', {
        'current_affected': {'receipt': 'attempt3-urgent-stop/verification.json', 'controls_passed': 43,
                             'failed': 0, 'skipped': 0, 'cancelled': 0, 'tsc_exit_code': 0,
                             'source_inputs': len(final), 'dependencies_plus_node': len(dependencies)},
        'associated_existing_scheduler': {
            'receipt': 'verification.json', 'log': 'node-focused.log', 'tests_passed_in_own_file': 16,
            'containing_aggregate_pass': False, 'new_execution': False,
            'transitive_inputs': {str(path.relative_to(ROOT)): final[str(path)] for path in scheduler},
            'sources_and_pinned_node_dependencies_links_unchanged': True},
        'associated_python_preparation': {
            'receipt': 'verification.json', 'log': 'python-preparation.log', 'tests_passed': 12,
            'new_execution': False, 'source_inputs': {str(path.relative_to(ROOT)): final[str(path)] for path in python},
            'source_unchanged': True, 'python_binary_initial_hash_not_captured': True},
        'initial_to_current_source_changes': [name for name in initial if initial[name] != final.get(name)],
        'whole_suite_current_aggregate_claimed': False,
        'full_history_regression_executed': False, 'full_current_history_acceptance': 'open',
        'host_job_installed': False, 'host_job_started': False, 'hosted_calls': False,
        'keychain_calls': False, 'sender_actions': 0,
        'source_snapshot_is_reviewed_production_candidate': False,
        'scope': 'local scheduler operating controls only'})
    print(json.dumps({'copied_inputs': len(bindings), 'associated_scheduler_transitive_inputs': len(scheduler),
                      'python_source_inputs': len(python), 'readback_pass': True}))


if __name__ == '__main__':
    main()
