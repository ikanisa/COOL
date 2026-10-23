#!/usr/bin/env python3
"""Export actual compiled mobile defaults without Flutter writing the output file.

Run only under the repository's native compiler ownership/headroom controls.
The output is public configuration, never an authentication/session export.
"""
import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import time
from urllib.parse import unquote, urljoin, urlsplit

PRODUCER = 'test/tools/public_configuration_defaults_export_test.dart'
MARKER = 'COLLECT_PUBLIC_DEFAULTS_EXPORT_BASE64:'
SOURCES = frozenset({
    'lib/core/data/exact_json_values.dart',
    'lib/shared/models/collect_model_json_helpers.dart',
    'lib/shared/models/collect_models.dart',
    'lib/shared/models/collect_payment_json.dart',
    'lib/shared/models/collect_payment_models.dart',
    'lib/shared/models/collect_profile_country_rules.dart',
    'lib/shared/models/collect_summary_json.dart',
    'lib/shared/repositories/collect_repository_providers.dart',
    'pubspec.lock', 'pubspec.yaml',
})
VALUE_KEYS = frozenset({'get_public_runtime_config', 'get_collection_type_catalog',
                        'list_account_request_reasons'})
MAX_LOG = 8 * 1024 * 1024
MAX_PAYLOAD = 128 * 1024


def refuse(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        refuse(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def parse_json(raw):
    return json.loads(raw.decode('utf-8', errors='strict'), object_pairs_hook=unique_object,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Nonfinite JSON')))


def describe(raw):
    return {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)}


def identity(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def physical(path, directory=False):
    path = Path(os.path.abspath(path))
    refuse(path.resolve(strict=True) == path, 'Physical path required: ' + str(path))
    info = path.lstat()
    refuse(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode),
           'Unexpected file type: ' + str(path))
    return path


def source_bytes(root, relative):
    refuse(relative in SOURCES | {PRODUCER, '.fvmrc'}, 'Unexpected public source role')
    path = physical(root / relative)
    before = path.lstat()
    refuse(0 < before.st_size <= 1024 * 1024, 'Unbounded public source')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        refuse(identity(os.fstat(stream.fileno())) == identity(before), 'Source changed before read')
        raw = stream.read(1024 * 1024 + 1)
        refuse(identity(os.fstat(stream.fileno())) == identity(before), 'Source changed during read')
    refuse(identity(path.lstat()) == identity(before), 'Source path changed during read')
    text = raw.decode('utf-8', errors='strict')
    refuse(not re.search(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', text), 'Public source has controls')
    return raw


def source_snapshot(project, custody):
    result = {}
    for relative in sorted(SOURCES | {PRODUCER, '.fvmrc'}):
        compiled = source_bytes(project, relative)
        retained = source_bytes(custody, relative)
        refuse(compiled == retained, 'Execution source differs from custody: ' + relative)
        result[relative] = describe(compiled)
    return result


def package_config_snapshot(project):
    """Pin the exact package map passed explicitly to the Flutter compiler."""
    path = physical(project / '.dart_tool/package_config.json')
    before = path.lstat()
    refuse(before.st_nlink == 1 and 0 < before.st_size <= 1024 * 1024,
           'Package configuration must be independent and bounded')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        refuse(identity(os.fstat(stream.fileno())) == identity(before), 'Package map changed before read')
        raw = stream.read(1024 * 1024 + 1)
        refuse(identity(os.fstat(stream.fileno())) == identity(before), 'Package map changed during read')
    refuse(identity(path.lstat()) == identity(before), 'Package map path changed during read')
    config = parse_json(raw)
    refuse(isinstance(config, dict) and type(config.get('configVersion')) is int and
           config['configVersion'] == 2 and isinstance(config.get('packages'), list),
           'A version-two compiler package map is required')
    names = []
    for package in config['packages']:
        refuse(isinstance(package, dict) and isinstance(package.get('name'), str) and
               package['name'], 'Invalid compiler package entry')
        names.append(package['name'])
    refuse(len(names) == len(set(names)) and names.count('collect_app') == 1,
           'One unambiguous collect_app package is required')
    package = config['packages'][names.index('collect_app')]
    refuse(isinstance(package.get('rootUri'), str) and package.get('packageUri') == 'lib/',
           'Unexpected collect_app source mapping')
    root_uri = urljoin(path.as_uri(), package['rootUri'])
    def mapped_directory(uri):
        parts = urlsplit(uri)
        refuse(parts.scheme == 'file' and not parts.netloc and not parts.query and not parts.fragment,
               'Compiler package sources must use local file URIs')
        return physical(Path(unquote(parts.path, errors='strict')), directory=True)
    refuse(mapped_directory(root_uri) == project and
           mapped_directory(urljoin(root_uri, package['packageUri'])) == project / 'lib',
           'Compiler collect_app mapping differs from the execution project')
    return {'path': str(path), **describe(raw), 'identity': list(identity(before)),
            'package_name': 'collect_app', 'root': str(project), 'package_uri': 'lib/'}


def parse_machine_log(raw, returncode):
    refuse(returncode == 0, 'Flutter test process failed')
    refuse(0 < len(raw) <= MAX_LOG, 'Machine log exceeds bound')
    events = []
    process_starts = 0
    process_start = [{'event': 'test.startedProcess', 'params': {'vmServiceUri': None}}]
    for line in raw.splitlines():
        if not line.strip():
            continue
        event = parse_json(line)
        if isinstance(event, list):
            # Flutter 3.44.4 emits this tool event while its VM loader starts.
            # It is not a test result and cannot carry arbitrary event arrays.
            loaders = [item for item in events if item.get('type') == 'testStart']
            refuse(event == process_start and process_starts == 0 and loaders and
                   all(isinstance(item.get('test', {}).get('name'), str) and
                       item['test']['name'].startswith('loading ') for item in loaders) and
                   not any(item.get('type') in {'testDone', 'print', 'error', 'done'}
                           for item in events), 'Unexpected Flutter process-start frame')
            process_starts += 1
            continue
        refuse(isinstance(event, dict), 'Machine events must be objects')
        events.append(event)
    refuse(events, 'Machine events must be objects')
    done = [event for event in events if event.get('type') == 'done']
    refuse(len(done) == 1 and events[-1] == done[0] and done[0].get('success') is True,
           'Missing successful final Flutter result')
    refuse(not any(event.get('type') == 'error' for event in events), 'Flutter reported an error')
    started = {}
    completed = {}
    frames = []
    for event in events:
        kind = event.get('type')
        if kind == 'testStart':
            test = event.get('test', {})
            test_id = test.get('id')
            refuse(type(test_id) is int and test_id not in started, 'Duplicate or invalid test identity')
            refuse(test.get('metadata', {}).get('skip') is not True, 'Skipped test is not evidence')
            started[test_id] = test
        elif kind == 'testDone':
            test_id = event.get('testID')
            refuse(type(test_id) is int and test_id in started and test_id not in completed,
                   'Unmatched or duplicate test result')
            refuse(event.get('result') == 'success' and event.get('skipped') is False,
                   'Failed/skipped test is not evidence')
            completed[test_id] = event
        elif kind == 'print' and isinstance(event.get('message'), str):
            message = event['message']
            if MARKER in message:
                refuse(message.startswith(MARKER) and event.get('messageType') == 'print',
                       'Malformed payload print frame')
                frames.append((event.get('testID'), message[len(MARKER):]))
    refuse(set(started) == set(completed), 'Unfinished Flutter tests')
    real = [test_id for test_id, event in completed.items() if event.get('hidden') is not True]
    refuse(len(real) == 1 and len(frames) == 1 and frames[0][0] == real[0],
           'Require exactly one completed producer test and one payload frame')
    encoded = frames[0][1]
    refuse(len(encoded) <= ((MAX_PAYLOAD + 2) // 3) * 4, 'Export frame exceeds bound')
    try:
        payload = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError('Invalid export base64') from error
    refuse(0 < len(payload) <= MAX_PAYLOAD, 'Export payload exceeds bound')
    document = parse_json(payload)
    refuse(isinstance(document, dict) and set(document) == {'schema_version', 'kind', 'source_inputs', 'values'},
           'Unexpected defaults export shape')
    refuse(type(document['schema_version']) is int and document['schema_version'] == 1 and
           document['kind'] == 'collect_mobile_public_configuration_defaults', 'Unexpected defaults export identity')
    refuse(isinstance(document['source_inputs'], dict) and set(document['source_inputs']) == SOURCES,
           'Unexpected defaults source roles')
    refuse(isinstance(document['values'], dict) and set(document['values']) == VALUE_KEYS,
           'Unexpected defaults operation scope')
    for row in document['source_inputs'].values():
        refuse(isinstance(row, dict) and set(row) == {'sha256', 'bytes'} and
               isinstance(row['sha256'], str) and re.fullmatch('[a-f0-9]{64}', row['sha256']) and
               type(row['bytes']) is int and 0 < row['bytes'] <= 1024 * 1024, 'Invalid source claim')
    return payload, document, {'actual_producer_tests': 1, 'hidden_loaders_excluded': len(completed)-1,
                               'payload_frames': 1, 'skipped': 0, 'failed': 0,
                               'flutter_process_start_frames': process_starts}


class PrivateOutput:
    """Hold an exclusive directory descriptor; never follow output aliases."""
    def __init__(self, path):
        self.path = Path(os.path.abspath(path))
        parent = physical(self.path.parent, directory=True)
        parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.mkdir(self.path.name, mode=0o700, dir_fd=parent_fd)
            self.fd = os.open(self.path.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
        finally:
            os.close(parent_fd)
        self.before = os.fstat(self.fd)

    def file(self, name):
        refuse(re.fullmatch('[a-z0-9_.-]+', name) is not None and name not in {'.','..'}, 'Unsafe output name')
        return os.fdopen(os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                0o600, dir_fd=self.fd), 'wb')

    def write(self, name, raw):
        with self.file(name) as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())

    def read(self, name):
        with os.fdopen(os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=self.fd), 'rb') as stream:
            raw = stream.read(MAX_LOG + 1)
        refuse(len(raw) <= MAX_LOG, 'Captured log exceeds bound')
        return raw

    def verify(self):
        info = self.path.lstat()
        refuse(stat.S_ISDIR(info.st_mode) and (info.st_dev,info.st_ino) ==
               (self.before.st_dev,self.before.st_ino), 'Owned output directory path changed')
        refuse(self.path.resolve(strict=True) == self.path, 'Owned output directory was aliased')

    def close(self):
        os.close(self.fd)


def capture(output, label, argv, project, env, timeout=180):
    with output.file(label+'.stdout.jsonl') as stdout, output.file(label+'.stderr.txt') as stderr:
        process = subprocess.Popen(argv, cwd=project, env=env, stdin=subprocess.DEVNULL,
                                   stdout=stdout, stderr=stderr, start_new_session=True)
        started = time.monotonic()
        try:
            while process.poll() is None:
                refuse(time.monotonic()-started <= timeout, 'Flutter command timeout')
                refuse(os.fstat(stdout.fileno()).st_size <= MAX_LOG and
                       os.fstat(stderr.fileno()).st_size <= MAX_LOG, 'Flutter output exceeds bound')
                time.sleep(0.1)
            refuse(os.fstat(stdout.fileno()).st_size <= MAX_LOG and
                   os.fstat(stderr.fileno()).st_size <= MAX_LOG, 'Flutter output exceeds bound')
            return process.returncode, round(time.monotonic()-started, 3)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=10)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--project-root', required=True)
    parser.add_argument('--custody-root', required=True)
    parser.add_argument('--out', required=True, help='New private directory; existing paths are refused')
    args = parser.parse_args(argv)
    project = physical(args.project_root, directory=True)
    custody = physical(args.custody_root, directory=True)
    flutter = physical(args.flutter)
    before = source_snapshot(project, custody)
    package_before = package_config_snapshot(project)
    pin = parse_json(source_bytes(project, '.fvmrc')).get('flutter')
    refuse(isinstance(pin, str) and re.fullmatch(r'\d+\.\d+\.\d+', pin), 'An exact Flutter pin is required')
    flutter_source = describe(flutter.read_bytes())
    output = PrivateOutput(args.out)
    result = {'all_pass': False, 'provider_calls': False, 'credential_or_session_export': False}
    try:
        env = dict(os.environ, COLLECT_PUBLIC_DEFAULTS_EXPORT_STDOUT='1',
                   COLLECT_PUBLIC_DEFAULTS_PACKAGE_CONFIG=package_before['path'],
                   COLLECT_PUBLIC_DEFAULTS_PACKAGE_CONFIG_SHA256=package_before['sha256'])
        version_argv = [str(flutter), '--version', '--machine']
        code, _ = capture(output, 'flutter-version', version_argv, project, env)
        refuse(code == 0, 'Flutter version check failed')
        version = parse_json(output.read('flutter-version.stdout.jsonl'))
        refuse(version.get('frameworkVersion') == pin, 'Flutter version differs from repository pin')
        test_argv = [str(flutter), '--packages='+package_before['path'],
                     'test', '--machine', '--no-pub', PRODUCER]
        code, seconds = capture(output, 'flutter-test', test_argv, project, env)
        payload, document, counts = parse_machine_log(output.read('flutter-test.stdout.jsonl'), code)
        refuse(before == source_snapshot(project, custody), 'Public sources changed during export')
        refuse(package_before == package_config_snapshot(project), 'Compiler package map changed during export')
        refuse(describe(flutter.read_bytes()) == flutter_source, 'Flutter launcher changed during export')
        refuse(document['source_inputs'] == {path: before[path] for path in SOURCES},
               'Actual compiled package source claims differ from execution/custody')
        output.verify()
        output.write('mobile-defaults.json', payload)
        result.update(all_pass=True, payload=describe(payload), sources=before,
                      flutter_version=version, flutter_launcher=flutter_source,
                      producer=PRODUCER, counts=counts, seconds=seconds,
                      compiler_package_config=package_before,
                      commands=[version_argv,test_argv], project_root=str(project), custody_root=str(custody),
                      wrapper=describe(Path(__file__).read_bytes()),
                      limits='Local typed defaults only; no provider, installed-device, legal or owner acceptance')
        return 0
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        result.update(error_type=type(error).__name__, error=str(error))
        return 1
    finally:
        try:
            output.verify()
            output.write('result.json', (json.dumps(result, indent=2)+'\n').encode())
        finally:
            output.close()
        print(json.dumps({'all_pass':result['all_pass'], 'out':str(output.path),
                          'error':result.get('error')}))


if __name__ == '__main__':
    raise SystemExit(main())
