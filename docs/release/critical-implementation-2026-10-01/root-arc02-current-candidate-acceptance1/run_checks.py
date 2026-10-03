"""Original refactor criterion on one captured candidate; no release approval."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import types

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
APP = BASE / 'app-source'
SDK = BASE / 'flutter'


def load(path, digest, name):
    raw = path.read_bytes()
    if path.resolve() != path or hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError('reviewed module differs')
    module = types.ModuleType(name); module.__file__ = str(path)
    exec(compile(raw, str(path), 'exec'), module.__dict__)
    return module


metadata = load(RELEASE / 'kotlin-sdk-native-consumer-preparation1/publisher_metadata.py',
    'c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25', 'refactor_metadata')
guards = load(RELEASE / 'kotlin-sdk-native-app-guard-preparation2/consumer_guards.py',
    'f38cbad5ab95c7aa9adfa0b9ddae5cf5902666c89aa6548525edb75be3465e4a', 'refactor_guards')
controller = load(RELEASE / 'kotlin-sdk-native-native-stage-preparation1/run_native_consumer.py',
    '167d48b4e756043a87621feffcabccb41aca108232cfb943914b69fc5b090fe7', 'refactor_controller')
decoder = load(RELEASE / 'root-arc02-decoder-compatibility-preparation1/run_decoder_compatibility.py',
    '4d9ca29245a49dafb785e7d03e738eabba4842176524205d8e4c4ac2dc6b38c7', 'refactor_libraries')
controller.reader = lambda: metadata
controller.require_pass = guards.process_success
guards.load_metadata = lambda: metadata


def context(expected):
    row, raw = metadata.stable_read(HERE / 'packet-files.json', True)
    if row['sha256'] != expected: raise ValueError('prepared packet differs')
    for leaf in json.loads(raw)['files']:
        path = Path(leaf['path'])
        if path.is_absolute() or '..' in path.parts: raise ValueError('unsafe packet path')
        actual, _ = metadata.stable_read(HERE / path)
        if (actual['sha256'], actual['bytes']) != (leaf['sha256'], leaf['bytes']): raise ValueError('packet leaf differs')
    return json.loads(metadata.stable_read(HERE / 'plan.json', True)[1])


def observe(plan, label):
    source = guards.app_readback('built', plan['export_manifest_file_sha256'])
    if len(source['source_files_exact']) != 2513 or source['source_manifest_sha256'] != plan['source_manifest_sha256']:
        raise ValueError('captured authored source differs')
    libraries = decoder.pub_libraries({'source_root': str(APP), 'SDK': str(SDK), 'base': str(BASE)}, metadata, guards)
    controller.save(HERE / ('app-' + label + '.json'), {'app': source, 'libraries': libraries,
        'protected': controller.protected_metadata()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet-sha256', required=True)
    parser.add_argument('--observe', choices=('before', 'after'))
    args = parser.parse_args(); plan = context(args.packet_sha256)
    if args.observe:
        observe(plan, args.observe); return 0
    prior_row, prior_body = metadata.stable_read(BASE / '.control/app-lock/terminal.json', True)
    prior = json.loads(prior_body)
    if prior_row['sha256'] != plan['app_lock_terminal_sha256'] or prior['stage_pass'] is not True:
        raise ValueError('fresh whole app-lock predecessor differs')
    if (BASE / '.control/native').exists(): raise ValueError('another native owner was admitted')
    config = json.loads(metadata.stable_read(RELEASE / 'kotlin-sdk-native-native-stage-preparation1/proposed-commands.json', True)[1])
    if Path(sys.executable).resolve() != Path(config['Python_executable']).resolve(): raise ValueError('runtime differs')
    if metadata.stable_read(Path(config['Python_executable']))[0]['sha256'] != config['Python_SHA256']:
        raise ValueError('runtime checksum differs')
    env = config['environment_exact']; started = time.monotonic(); deadline = started + 900
    errors = []; processes = {}
    terminal = {'source_manifest_sha256': plan['source_manifest_sha256'], 'source_files': 2513,
        'production_release_approval': False, 'current209_SQL_producer_verified': False,
        'source_lock_attested': False, 'OS_immutable_flag_attested': False, 'ARC02_closed': False}
    def run(name, argv, seconds, cwd=APP):
        remaining = deadline - time.monotonic() - 30
        if remaining <= 0: raise TimeoutError('whole900/cleanup30 bound reached')
        result = controller.run_process(HERE, name, argv, min(seconds, remaining), cwd, env)
        processes[name] = result; controller.require_pass(result); return result
    def observation(label):
        for path, expected in plan['receipt_hashes'].items():
            if metadata.stable_read(Path(path))[0]['sha256'] != expected:
                raise ValueError('dated actual SQL receipt changed')
        run('APP-reader-' + label, [sys.executable, '-I', '-B', str(Path(__file__)), '--packet-sha256',
            args.packet_sha256, '--observe', label], 300, HERE)
        run('SDK-reader-' + label, [sys.executable, '-I', '-B',
            str(RELEASE / 'kotlin-sdk-native-consumer-preparation1/verify_native_consumer_source.py'),
            'built', '--output', str(HERE / ('SDK-' + label + '-output.json'))], 300, HERE)
    try:
        for define in plan['defines']:
            if define.startswith('--dart-define=') and not define.startswith('--dart-define=ADMIN_READ_SQL_ACTOR='):
                path = Path(define.split('=', 2)[2]); metadata.stable_read(path)
        observation('before')
        run('hard-size-gate', ['/bin/bash', str(HERE / 'exact-size-gate.sh')], 60)
        run('strict-analysis', [str(SDK / 'bin/flutter'), '--suppress-analytics', 'analyze',
            '--no-pub', '--fatal-infos', '--fatal-warnings'], 180)
        argv = [str(SDK / 'bin/flutter'), '--suppress-analytics', 'test', '--no-pub', '--concurrency=1',
            '--timeout=30s', *plan['defines'], '--reporter=expanded',
            '--file-reporter=json:' + str(HERE / 'tests.events.jsonl'), *plan['tests']]
        run('affected37-suites', argv, 600)
    except BaseException as error:
        errors.append({'phase': 'actual_checks', 'type': type(error).__name__, 'message': str(error)})
    try:
        observation('after')
        before = json.loads(metadata.stable_read(HERE / 'app-before.json', True)[1])
        after = json.loads(metadata.stable_read(HERE / 'app-after.json', True)[1])
        for key in ('source_files_exact', 'source_manifest_sha256', 'export_manifest_file_sha256'):
            if before['app'][key] != after['app'][key]: raise ValueError('authored source changed')
        if before['libraries'] != after['libraries']: raise ValueError('external package source changed')
        terminal['authored_and_external_package_source_before_after_equal'] = True
    except BaseException as error:
        errors.append({'phase': 'after', 'type': type(error).__name__, 'message': str(error)})
    try:
        events = [json.loads(line) for line in metadata.stable_read(HERE / 'tests.events.jsonl', True)[1].decode().splitlines()]
        starts = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
        dones = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
        failed = [e for e in dones if e.get('result') != 'success' or e.get('skipped')]
        final = [e for e in events if e.get('type') == 'done']
        errors_events = [e for e in events if e.get('type') == 'error']
        terminal['test_counts'] = {'unhidden': len(dones), 'successful_unskipped': len(dones)-len(failed),
                                  'failed_or_skipped': len(failed), 'error_events': len(errors_events)}
        terminal['actual_decoder_cases'] = []
        names = json.loads(metadata.stable_read(RELEASE / 'root-arc02-decoder-compatibility-preparation1/execution-plan.json', True)[1])['cases']
        for case in names:
            matches = [e for e in dones if starts[e['testID']]['name'] == case['name']]
            if len(matches) != 1 or matches[0] in failed: raise ValueError('named actual decoder case missing/failed/skipped')
            terminal['actual_decoder_cases'].append(case['name'])
        if not dones or failed or errors_events or len(final) != 1 or final[0].get('success') is not True:
            raise ValueError('actual full affected stream incomplete/failed/skipped')
    except BaseException as error:
        errors.append({'phase': 'actual_outcomes', 'type': type(error).__name__, 'message': str(error)})
    if time.monotonic() >= deadline:
        errors.append({'phase': 'whole_deadline', 'type': 'TimeoutError', 'message': 'whole900 bound exceeded'})
    terminal.update(status='pass' if not errors else 'failed', errors=errors, actual_processes=processes,
        whole_seconds=round(time.monotonic()-started, 3), finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    controller.save(HERE / 'terminal.json', terminal)
    print(json.dumps({'status': terminal['status'], 'counts': terminal.get('test_counts'), 'errors': errors}))
    return 0 if not errors else 1


if __name__ == '__main__':
    raise SystemExit(main())
