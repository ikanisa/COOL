#!/usr/bin/env python3
"""One bounded three-case decoder observation; never SQL, Pub or build."""
import argparse
import datetime
import hashlib
import json
import os
import signal
import stat
import sys
import time
import types
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
METADATA = RELEASE / 'kotlin-sdk-native-consumer-preparation1/publisher_metadata.py'
METADATA_SHA = 'c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25'
CONTROLLER = RELEASE / 'kotlin-sdk-native-native-stage-preparation1/run_native_consumer.py'
CONTROLLER_SHA = '167d48b4e756043a87621feffcabccb41aca108232cfb943914b69fc5b090fe7'
GUARD = RELEASE / 'kotlin-sdk-native-app-guard-preparation2/consumer_guards.py'
GUARD_SHA = 'f38cbad5ab95c7aa9adfa0b9ddae5cf5902666c89aa6548525edb75be3465e4a'


def bootstrap(path, expected, name):
    """Execute the exact read bytes, without reopening the verified module."""
    if path.resolve() != path:
        raise ValueError('bootstrap input alias')
    before = path.lstat()
    identity = lambda row: (row.st_dev, row.st_ino, row.st_size, row.st_mode,
                            row.st_nlink, row.st_mtime_ns, row.st_ctime_ns)
    if (not stat.S_ISREG(before.st_mode) or before.st_nlink != 1
            or before.st_size > 1024**2 or before.st_mode & (stat.S_ISUID | stat.S_ISGID)):
        raise ValueError('bootstrap input not an exclusive bounded regular file')
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as stream:
        if identity(os.fstat(stream.fileno())) != identity(before):
            raise ValueError('bootstrap opening race')
        body = stream.read()
        if identity(os.fstat(stream.fileno())) != identity(before):
            raise ValueError('bootstrap FD mutation')
    if identity(path.lstat()) != identity(before) or hashlib.sha256(body).hexdigest() != expected:
        raise ValueError('bootstrap hash or named identity differs')
    module = types.ModuleType(name)
    module.__file__ = str(path)
    exec(compile(body, str(path), 'exec'), module.__dict__)
    return module


def context(expected):
    metadata = bootstrap(METADATA, METADATA_SHA, 'decoder_metadata')
    controller = bootstrap(CONTROLLER, CONTROLLER_SHA, 'decoder_bounded_process')
    controller.packet(HERE, expected)
    plan = json.loads(metadata.stable_read(HERE / 'execution-plan.json', True)[1])
    for directory, digest in plan['dependency_packets'].items():
        controller.packet(Path(directory), digest)
    guard = bootstrap(GUARD, GUARD_SHA, 'decoder_source_guard2')
    return plan, metadata, controller, guard


def inputs(plan, metadata):
    rows = {}
    pins = dict(plan['pinned_inputs'])
    for receipt in plan['receipts'].values():
        pins[receipt['copy']] = receipt['sha256']
    for relative, digest in plan['maintained_Dart_closure']['files'].items():
        pins[str(Path(plan['maintained_repo']) / relative)] = digest
    for name, digest in pins.items():
        row, _ = metadata.stable_read(Path(name))
        if row['sha256'] != digest:
            raise ValueError('exact input changed: ' + name)
        rows[name] = row
    for receipt in plan['receipts'].values():
        _, body = metadata.stable_read(Path(receipt['copy']), True)
        lines = [line for line in body.decode().splitlines() if line.startswith(receipt['prefix'])]
        if len(lines) != receipt['entry_count']:
            raise ValueError('dated receipt entry count differs')
        for line in lines:
            if not isinstance(json.loads(line[len(receipt['prefix']):]), dict):
                raise ValueError('dated receipt entry is not an object')
    return rows


def previous_owner_finished(plan, metadata):
    base = Path(plan['base']) / '.control/native'
    terminal = json.loads(metadata.stable_read(base / 'terminal.json', True)[1])
    command = json.loads(metadata.stable_read(base / 'actual-command.json', True)[1])
    diagnostic = terminal['actual_failure_diagnostics']['actual_failure_source_process']
    if (terminal.get('stage') != 'native' or terminal.get('stage_pass') is not False
            or command.get('exit_code') != 1 or command.get('finished_utc') is None
            or diagnostic.get('finished_utc') is None
            or command.get('owned_process_group_absent') is not True
            or diagnostic.get('owned_process_group_absent') is not True):
        raise ValueError('pinned failed native stage is not terminal')
    for process in (command, diagnostic):
        try:
            os.killpg(process['pid'], 0)
        except ProcessLookupError:
            pass
        else:
            raise ValueError('previous native or diagnostic process group present')
    return {'previous_native_stage_pass': False, 'previous_native_exit_code': 1,
            'previous_owned_groups_absent': True, 'previous_failure_reclassified': False}


def pub_libraries(plan, metadata, guard):
    """Bind the actual external package libraries; do not resolve dependencies."""
    app, sdk = Path(plan['source_root']), Path(plan['SDK'])
    pub = Path(plan['base']) / 'pub-cache'
    configured = guard.package_config(app / '.dart_tool/package_config.json', (app, pub, sdk))
    result = {}; nodes = 0; total = 0
    for package in configured['packages']:
        root = Path(package['exact_root'])
        if not root.is_relative_to(pub):
            continue
        library = Path(os.path.normpath(str(root / urllib.parse.unquote(package['package_uri']))))
        row, _ = metadata.stable_read(root / 'pubspec.yaml')
        result[str(root / 'pubspec.yaml')] = row
        if not library.exists():
            continue
        guard.safe_directory(library, (root,))
        for parent, directories, files in os.walk(library, followlinks=False):
            for name in directories + files:
                path = Path(parent) / name; observed = path.lstat(); nodes += 1
                if nodes > 100000:
                    raise ValueError('external package source node bound')
                if stat.S_ISDIR(observed.st_mode):
                    guard.safe_directory(path, (root,))
                elif stat.S_ISREG(observed.st_mode):
                    row, _ = metadata.stable_read(path); total += row['bytes']
                    if total > 2 * 1024**3:
                        raise ValueError('external package source byte bound')
                    result[str(path)] = row
                else:
                    raise ValueError('external package library alias or special file')
    return {'configured_packages': configured, 'external_package_files': result,
            'source_nodes': nodes, 'source_bytes': total, 'resolution_performed': False}


def observe_app(plan, metadata, controller, guard, label):
    out = Path(plan['output'])
    before = inputs(plan, metadata)
    source = guard.app_readback('built', plan['original_export_manifest_sha256'])
    if (len(source['source_files_exact']) != plan['original_authored_file_count']
            or source['source_manifest_sha256'] != plan['original_source_manifest_sha256']):
        raise ValueError('frozen authored source membership differs')
    libraries = pub_libraries(plan, metadata, guard)
    protected = controller.protected_metadata()
    after = inputs(plan, metadata)
    if after != before:
        raise ValueError('input identity changed during app observation')
    controller.save(out / ('APP-' + label + '.json'),
                    {'app': source, 'libraries': libraries, 'protected_originals': protected,
                     'pinned_inputs': after, 'label': label})


def case_outcomes(plan, metadata):
    path = Path(plan['output']) / 'tests.events.jsonl'
    row, body = metadata.stable_read(path, True)
    expected = {case['name']: case['file'] for case in plan['cases']}
    starts = {}; dones = {}; errors = []; finished = []
    for line in body.decode().splitlines():
        event = json.loads(line); kind = event.get('type')
        if kind == 'testStart':
            case = event['test']; identity = case['id']
            if identity in starts:
                raise ValueError('duplicate actual test start')
            starts[identity] = case
        elif kind == 'testDone':
            identity = event['testID']
            if identity in dones:
                raise ValueError('duplicate actual test outcome')
            dones[identity] = event
        elif kind == 'error':
            errors.append(event)
        elif kind == 'done':
            finished.append(event)
    actual = []; issues = []
    for name, relative in expected.items():
        matching = [(identity, case) for identity, case in starts.items() if case['name'] == name]
        if len(matching) != 1:
            actual.append({'name': name, 'file': relative, 'actual_outcome': 'missing_or_duplicate',
                           'matching_starts': len(matching)})
            issues.append('named test missing or repeated: ' + name)
            continue
        identity, case = matching[0]; done = dones.get(identity)
        passed = (case.get('url') == (Path(plan['source_root']) / relative).as_uri()
                  and case.get('metadata', {}).get('skip') is False and done is not None
                  and done.get('result') == 'success' and done.get('skipped') is False
                  and done.get('hidden') is False)
        actual.append({'name': name, 'file': relative, 'testID': identity,
                       'actual_start': case, 'actual_done': done,
                       'actual_decoder_case_pass': passed})
        if not passed:
            issues.append('actual named decoder case failed, skipped or mismatched: ' + name)
    for identity, case in starts.items():
        if case['name'] not in expected:
            done = dones.get(identity, {})
            if not (case['name'].startswith('loading ') and done.get('hidden') is True
                    and done.get('result') == 'success' and done.get('skipped') is False):
                issues.append('unexpected actual test: ' + case['name'])
    if set(starts) != set(dones) or errors or len(finished) != 1 or finished[0].get('success') is not True:
        issues.append('actual runner stream failed or incomplete')
    return {'actual_cases': actual, 'errors': errors, 'issues': issues,
            'actual_runner_done': finished, 'machine_stream': row,
            'historic_aggregate_PASS_imported': False}


def test_argv(plan):
    command = [str(Path(plan['SDK']) / 'bin/flutter'), '--suppress-analytics', 'test',
               '--no-pub', '--concurrency=1', '--timeout=30s', '--name', plan['exact_test_regex']]
    command.extend('--dart-define=' + name + '=' + receipt['copy'] for name, receipt in plan['receipts'].items())
    command += ['--dart-define=ADMIN_READ_SQL_ACTOR=' + plan['admin_actor'], '--reporter=expanded',
                '--file-reporter=json:' + str(Path(plan['output']) / 'tests.events.jsonl')]
    return command + [case['file'] for case in plan['cases']]


def execute(plan, metadata, controller, guard, expected):
    started = time.monotonic(); deadline = started + plan['whole_deadline_seconds']
    out = Path(plan['output']); out.mkdir(mode=0o700)
    terminal = {'scope': plan['kind'], 'prepared_manifest_sha256': expected,
                'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'current209_SQL_producer_verified': False, 'ARC02_closed': False,
                'native_stage_pass': False, 'production_ready': False,
                'whole37_suite_executed': False, 'SQL_or_Pub_or_build_command_executed': False,
                'source_lock_attested': False, 'transient_write_and_restore_absence_attested': False,
                'decoder_compatibility_pass': False, 'errors': []}

    def run(name, argv, maximum, cwd):
        seconds = min(maximum, deadline - time.monotonic() - plan['cleanup_reserve_seconds'])
        if seconds <= 0:
            raise TimeoutError('whole decoder observation deadline exhausted')
        return controller.run_process(out, name, argv, seconds, cwd, plan['environment_exact'])

    def observation(label):
        sdk_out = out / ('SDK-' + label + '.json')
        argv = [plan['Python'], '-I', '-B', str(Path(plan['source_preparation']) / 'verify_native_consumer_source.py'),
                'built', '--output', str(sdk_out)]
        controller.require_pass(run('SDK-reader-' + label, argv, plan['reader_deadline_seconds'],
                                    Path(plan['source_preparation'])))
        argv = [plan['Python'], '-I', '-B', str(HERE / 'run_decoder_compatibility.py'),
                '--prepared-manifest-sha256', expected, '--observe-app', label]
        controller.require_pass(run('APP-reader-' + label, argv, plan['reader_deadline_seconds'], HERE))

    pre = None; test_record = None; interrupted = False
    try:
        pre = inputs(plan, metadata)
        terminal['previous_owner'] = previous_owner_finished(plan, metadata)
        controller.save(out / 'input-guards-before.json', pre)
        observation('before')
        controller.save(out / 'planned-test-command.json', {'argv': test_argv(plan), 'cwd': plan['source_root']})
        test_record = run('actual-tests', test_argv(plan), plan['test_deadline_seconds'], Path(plan['source_root']))
    except BaseException as error:
        interrupted = isinstance(error, (KeyboardInterrupt, InterruptedError))
        terminal['errors'].append({'phase': 'before_or_actual_tests', 'type': type(error).__name__, 'message': str(error)})
    # A failed test command keeps its actual failure and still receives post-readback.
    try:
        if interrupted:
            raise InterruptedError('external stop retained; no further reader child spawned')
        observation('after')
        post = inputs(plan, metadata)
        controller.save(out / 'input-guards-after.json', post)
        if pre is None or pre != post:
            raise ValueError('pre/post pinned input bytes or identity differs')
        before = json.loads(metadata.stable_read(out / 'APP-before.json', True)[1])
        after = json.loads(metadata.stable_read(out / 'APP-after.json', True)[1])
        for key in ('source_files_exact', 'source_manifest_sha256', 'export_manifest_file_sha256'):
            if before['app'][key] != after['app'][key]:
                raise ValueError('pre/post frozen authored source differs')
        if before['libraries'] != after['libraries']:
            raise ValueError('pre/post configured external package source differs')
        terminal['source_lock_runtime_and_receipt_pre_post_exact'] = True
    except BaseException as error:
        terminal['errors'].append({'phase': 'after', 'type': type(error).__name__, 'message': str(error)})
    try:
        cases = case_outcomes(plan, metadata)
        controller.save(out / 'actual-case-outcomes.json', cases)
        terminal['actual_cases'] = cases['actual_cases']
        if cases['issues']:
            raise ValueError('; '.join(cases['issues']))
        if test_record is None:
            raise ValueError('actual test command did not return a terminal record')
        controller.require_pass(test_record)
    except BaseException as error:
        terminal['errors'].append({'phase': 'actual_outcomes', 'type': type(error).__name__, 'message': str(error)})
    terminal['actual_seconds'] = round(time.monotonic() - started, 3)
    if time.monotonic() >= deadline:
        terminal['errors'].append({'phase': 'whole_deadline', 'type': 'TimeoutError', 'message': 'whole deadline reached'})
    terminal['decoder_compatibility_pass'] = not terminal['errors']
    terminal['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    controller.save(out / 'terminal.json', terminal)
    print(json.dumps({'decoder_compatibility_pass': terminal['decoder_compatibility_pass'],
                      'terminal': str(out / 'terminal.json'), 'actual_case_count': len(terminal.get('actual_cases', []))}))
    return 0 if terminal['decoder_compatibility_pass'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared-manifest-sha256', required=True)
    parser.add_argument('--observe-app', choices=('before', 'after'))
    args = parser.parse_args()
    plan, metadata, controller, guard = context(args.prepared_manifest_sha256)
    if args.observe_app:
        observe_app(plan, metadata, controller, guard, args.observe_app)
        return 0
    def stopped(signum, frame):
        raise InterruptedError('external stop signal ' + str(signum))
    signal.signal(signal.SIGTERM, stopped)
    signal.signal(signal.SIGINT, stopped)
    return execute(plan, metadata, controller, guard, args.prepared_manifest_sha256)


if __name__ == '__main__':
    sys.exit(main())
