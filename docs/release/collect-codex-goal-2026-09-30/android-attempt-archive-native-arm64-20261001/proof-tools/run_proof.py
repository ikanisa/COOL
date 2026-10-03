#!/usr/bin/env python3
"""Single serial full native archive proof on exact private APFS inputs."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time
from datetime import datetime, timezone

REPO = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
PRIVATE = Path('/Users/jeanbosco/.cache/collect-android-native-proof-20261001')
LEAF = REPO / 'docs/release/collect-codex-goal-2026-09-30/android-attempt-archive-native-arm64-20261001'
TOOLS = REPO / '.cache/android-attempt-archive-native-arm64-20261001'
SUITES = ['GatewayAttemptArchiveTest', 'GatewayAttemptArchiveBackendTest', 'GatewayJournalArchiveTest',
          'GatewayArchiveStorageTest', 'GatewaySafetyTest', 'GatewayDispatchBackendIntegrationTest',
          'GatewayArchiveBackendIntegrationTest', 'GatewayDispatchWireTest', 'GatewayBackgroundCoordinatorTest']
PRODUCTS = ['GatewayJournal', 'GatewayJournalArchive', 'GatewayEncryptedStore', 'GatewayCrypto',
            'GatewayAttemptArchive', 'GatewayAttemptArchiveWire', 'GatewayDispatch', 'GatewayDispatchWire',
            'GatewayBackgroundCoordinator', 'GatewayInstalledEnrollment', 'GatewayWire', 'GatewayTransport',
            'GatewayRadioObservation', 'GatewayDeviceIdentity', 'GatewaySignedBackend']
CURRENT_CHILD = None


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write(path, value):
    temp = path.with_suffix(path.suffix + '.new')
    with temp.open('x') as f:
        f.write(json.dumps(value, indent=2) + '\n')
        f.flush()
        os.fsync(f.fileno())
    os.replace(temp, path)


def check_runtime(root, expected):
    entries = {str(p.relative_to(root)): p for p in root.rglob('*')}
    if set(entries) != set(expected):
        raise RuntimeError('JDK runtime closure path changed')
    for name, entry in expected.items():
        p = entries[name]
        if entry['kind'] == 'symlink':
            if not p.is_symlink() or os.readlink(p) != entry['target'] or not p.resolve(strict=True).is_relative_to(root.resolve()):
                raise RuntimeError('JDK link changed')
        elif entry['kind'] == 'file':
            if p.is_symlink() or not p.is_file() or sha(p) != entry['sha256'] or oct(p.stat().st_mode & 0o777) != entry['mode']:
                raise RuntimeError('JDK runtime byte/mode changed')
        elif not p.is_dir() or p.is_symlink() or oct(p.stat().st_mode & 0o777) != entry['mode']:
            raise RuntimeError('JDK runtime directory changed')


def main():
    os.umask(0o077)
    lock = PRIVATE / 'single-attempt.lock'
    with lock.open('x') as f:
        f.write(json.dumps({'runner_pid': os.getpid(), 'created_at': now()}) + '\n')
        f.flush()
        os.fsync(f.fileno())
    stage = json.loads((PRIVATE / 'staging.json').read_text())
    if PRIVATE.resolve() != PRIVATE or stage['private_root'] != str(PRIVATE):
        raise RuntimeError('Private proof staging does not resolve to expected internal path')
    filesystem = subprocess.run(['/bin/df', '-h', str(PRIVATE)], capture_output=True, text=True, timeout=10, check=True).stdout
    if '/System/Volumes/Data' not in filesystem or '/Volumes/PRO-G40' in filesystem:
        raise RuntimeError('Proof staging is not on confirmed internal APFS data volume')
    (LEAF / 'internal-filesystem.txt').write_text(filesystem)
    source = Path(stage['source_root'])
    shims = Path(stage['shim_root'])
    java = Path(stage['java'])
    jdk = Path(stage['jdk_root'])
    original = json.loads((REPO / 'docs/release/collect-codex-goal-2026-09-30/android-attempt-archive/native-final-unverified/validation.json').read_text())
    if len(stage['source_sha256']) != 36 or len(stage['binary_sha256']) != 14 or len(stage['shim_sha256']) != 5:
        raise RuntimeError('Exact full source/dependency/shim count changed')
    if stage['source_sha256'] != original['source_sha256'] or stage['binary_sha256'] != original['binary_sha256'] or stage['shim_sha256'] != original['shim_sha256']:
        raise RuntimeError('Exact final native source/dependency contract changed')
    binaries = stage['staged_binaries']
    for p in (source, shims, java, jdk, *(Path(x['path']) for x in binaries.values())):
        if not p.resolve().is_relative_to(PRIVATE.resolve()):
            raise RuntimeError('Compiler input escaped internal staging')
    runtime_manifest = LEAF / 'jdk-runtime-closure.json'
    if sha(runtime_manifest) != stage['jdk_runtime_closure_sha256']:
        raise RuntimeError('Runtime manifest changed')
    runtime = json.loads(runtime_manifest.read_text())
    tools = {str(p.relative_to(REPO)): sha(p) for p in sorted(TOOLS.glob('*.py'))}
    for path in tools:
        dest = LEAF / 'proof-tools' / Path(path).name
        dest.parent.mkdir(mode=0o700, exist_ok=True)
        dest.write_bytes((REPO / path).read_bytes())
    def readback():
        changes = {'original_source': [], 'copied_source': [], 'original_binary': [], 'copied_binary': [], 'shims': [], 'tools': [],
                   'native_source_inventory': []}
        for p, expected in stage['source_sha256'].items():
            if sha(REPO / p) != expected:
                changes['original_source'].append(p)
            if sha(source / p) != expected:
                changes['copied_source'].append(p)
        for p, expected in stage['binary_sha256'].items():
            if sha(Path(p)) != expected:
                changes['original_binary'].append(p)
            if sha(Path(binaries[p]['path'])) != expected:
                changes['copied_binary'].append(p)
        for p, expected in stage['shim_sha256'].items():
            if sha(shims / p) != expected:
                changes['shims'].append(p)
        for p, expected in tools.items():
            if sha(REPO / p) != expected:
                changes['tools'].append(p)
        native_base = Path('android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway')
        expected_native = {p for p in stage['source_sha256'] if p.startswith(str(native_base) + '/') and p.endswith('.kt')}
        actual_native = {str(p.relative_to(REPO)) for p in (REPO / native_base).glob('*.kt')}
        changes['native_source_inventory'] = sorted(actual_native.symmetric_difference(expected_native))
        check_runtime(jdk, runtime)
        return changes
    before = readback()
    if any(before.values()):
        raise RuntimeError('Input changed before first compiler')
    write(LEAF / 'execution-inputs-before.json', {'at': now(), 'changes': before, 'tools_sha256': tools,
                                              'staging_sha256': sha(PRIVATE / 'staging.json'), 'jdk_manifest_sha256': sha(runtime_manifest)})
    work = PRIVATE / 'work'
    work.mkdir(mode=0o700)
    env = {'PATH': os.defpath, 'HOME': str(PRIVATE), 'TMPDIR': str(work), 'LANG': 'C.UTF-8'}
    binary_paths = [Path(x['path']) for x in binaries.values()]
    dependencies = binary_paths[:9]
    compiler_cp = os.pathsep.join(map(str, dependencies))
    source_cp = os.pathsep.join(str(dependencies[i]) for i in (1, 4, 6, 7, 8))
    compiler = [str(java), '-Xms64m', '-Xmx1g', '-XX:ActiveProcessorCount=2', '-cp', compiler_cp,
                'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler', '-no-stdlib', '-no-reflect', '-jvm-target', '17']
    base = Path('android/app/src/internal_gateway/kotlin/app/cool/mobile/gateway')
    product_sources = [source / base / (name + '.kt') for name in PRODUCTS]
    test_sources = [source / p for p in stage['source_sha256'] if '/src/testInternal_gateway' in p and Path(p).stem in SUITES]
    api_sources = [source / p for p in stage['source_sha256'] if p.startswith(str(base) + '/') and p.endswith('.kt')]
    if len(product_sources) != 15 or len(test_sources) != 9 or len(api_sources) != 22:
        raise RuntimeError('Full product/test/Android scope changed')
    started = now()
    aggregate_deadline = time.monotonic() + 1200
    commands = []
    status_path = LEAF / 'execution-status.json'
    def command(name, argv, maximum=480):
        global CURRENT_CHILD
        left = aggregate_deadline - time.monotonic()
        if left <= 0:
            commands.append({'name': name, 'status': 'not_started_aggregate_deadline', 'exit_code': 124})
            return 124
        maximum = min(maximum, left)
        started_mono = time.monotonic()
        limit = started_mono + maximum
        stdout_path = work / (name + '.stdout')
        stderr_path = work / (name + '.stderr')
        gc_path = work / (name + '.gc.log')
        # GC logs are diagnostic only; no assertions or selected source changes.
        if Path(argv[0]) == java:
            argv = argv[:1] + ['-Xlog:gc*:file=' + str(gc_path) + ':time,level,tags'] + argv[1:]
        with stdout_path.open('xb') as stdout, stderr_path.open('xb') as stderr:
            process = subprocess.Popen(argv, stdout=stdout, stderr=stderr, env=env, cwd=work, start_new_session=True)
            CURRENT_CHILD = process
            write(status_path, {'state': 'running', 'stage': name, 'runner_pid': os.getpid(), 'child_pid': process.pid,
                                'started_at': now(), 'stage_bound_seconds': maximum, 'aggregate_bound_seconds': 1200,
                                'java': str(java), 'source_scope': '15product/5shims/9suites/22native+BuildConfig/Android36'})
            print(json.dumps({'state': 'running', 'stage': name, 'pid': process.pid, 'bound_seconds': maximum}), flush=True)
            next_diagnostic = started_mono + 60
            timed_out = False
            usage = None
            while True:
                pid, wait_status, usage = os.wait4(process.pid, os.WNOHANG)
                if pid:
                    process.returncode = os.waitstatus_to_exitcode(wait_status)
                    break
                clock = time.monotonic()
                if clock >= limit:
                    timed_out = True
                    os.killpg(process.pid, signal.SIGTERM)
                    stop_deadline = time.monotonic() + 5
                    while time.monotonic() < stop_deadline:
                        pid, wait_status, usage = os.wait4(process.pid, os.WNOHANG)
                        if pid:
                            process.returncode = os.waitstatus_to_exitcode(wait_status)
                            break
                        time.sleep(0.1)
                    if not pid:
                        os.killpg(process.pid, signal.SIGKILL)
                        _, wait_status, usage = os.wait4(process.pid, 0)
                        process.returncode = os.waitstatus_to_exitcode(wait_status)
                    break
                if clock >= next_diagnostic:
                    elapsed = int(clock - started_mono)
                    try:
                        observation = subprocess.run(['/bin/ps', '-p', str(process.pid), '-o', 'pid,ppid,etime,state,%cpu,cputime,comm'],
                                                     capture_output=True, timeout=5, env=env)
                        (LEAF / (name + '.process-' + str(elapsed) + '.txt')).write_bytes(observation.stdout + observation.stderr)
                    except subprocess.TimeoutExpired:
                        (LEAF / (name + '.process-' + str(elapsed) + '.txt')).write_text('Bounded own-PID process observation timed out.\n')
                    # These inspect only the known child PID; attach tools have independent short bounds.
                    for action, suffix in [('Thread.print', 'threads'), ('GC.heap_info', 'heap')]:
                        try:
                            diag = subprocess.run([str(java.parent / 'jcmd'), str(process.pid), action], capture_output=True, timeout=8, env=env)
                            (LEAF / (name + '.' + suffix + '-' + str(elapsed) + '.txt')).write_bytes((diag.stdout + diag.stderr)[:512 * 1024])
                        except subprocess.TimeoutExpired:
                            (LEAF / (name + '.' + suffix + '-' + str(elapsed) + '.txt')).write_text('Bounded own-PID diagnostic timed out.\n')
                    next_diagnostic = time.monotonic() + 60
                time.sleep(0.2)
        CURRENT_CHILD = None
        code = 124 if timed_out else process.returncode
        elapsed = time.monotonic() - started_mono
        for p in (stdout_path, stderr_path, gc_path):
            if p.exists():
                shutil.copyfile(p, LEAF / p.name)
        receipt = {'name': name, 'argv': argv, 'exit_code': code, 'timed_out': timed_out, 'wall_seconds': elapsed,
                   'cpu_user_seconds': usage.ru_utime if usage else None, 'cpu_system_seconds': usage.ru_stime if usage else None,
                   'max_rss_platform_units': usage.ru_maxrss if usage else None, 'child_pid': process.pid,
                   'stdout_sha256': sha(stdout_path), 'stderr_sha256': sha(stderr_path), 'gc_sha256': sha(gc_path) if gc_path.exists() else None,
                   'own_child_reaped': process.returncode is not None}
        commands.append(receipt)
        write(status_path, {'state': 'stage_terminal', 'stage': name, 'at': now(), 'exit_code': code, 'receipt': receipt,
                            'runner_pid': os.getpid(), 'child_pid': None})
        print(json.dumps({'state': 'stage_terminal', 'stage': name, 'exit_code': code, 'wall_seconds': elapsed,
                          'cpu_seconds': (usage.ru_utime + usage.ru_stime) if usage else None}), flush=True)
        return code
    classes = work / 'classes'
    classes.mkdir(mode=0o700)
    code = command('compile-shim-product', compiler + ['-module-name', 'gateway_product', '-classpath', source_cp, '-d', str(classes)] +
                   list(map(str, product_sources)) + list(map(str, sorted(shims.glob('*.kt')))))
    batches = [[p for p in test_sources if p.stem in ('GatewayAttemptArchiveTest', 'GatewayAttemptArchiveBackendTest')],
               [p for p in test_sources if p.stem not in ('GatewayAttemptArchiveTest', 'GatewayAttemptArchiveBackendTest')]]
    test_classpaths = []
    for index, batch in enumerate(batches):
        if code:
            break
        target = work / ('test-classes-' + str(index))
        target.mkdir(mode=0o700)
        code = command('compile-tests-' + str(index), compiler + ['-module-name', 'gateway_tests_' + str(index),
            '-Xfriend-paths=' + str(classes), '-classpath', os.pathsep.join([str(classes), source_cp]), '-d', str(target)] + list(map(str, batch)))
        test_classpaths.append(str(target))
    if not code:
        code = command('tests', [str(java), '-ea', '-Xmx512m', '-cp', os.pathsep.join([str(classes), *test_classpaths, source_cp]),
                                'org.junit.runner.JUnitCore'] + ['app.cool.mobile.gateway.' + name for name in SUITES], 180)
    api_code = None
    if not code:
        api_classes = work / 'api-classes'
        api_classes.mkdir(mode=0o700)
        config = work / 'BuildConfig.kt'
        config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
        (LEAF / 'BuildConfig.kt').write_bytes(config.read_bytes())
        api_cp = os.pathsep.join([str(binary_paths[9]), str(binary_paths[11]), str(binary_paths[12]), source_cp])
        api_code = command('compile-real-android-api', compiler + ['-classpath', api_cp, '-d', str(api_classes)] +
                           list(map(str, api_sources)) + [str(config)])
    outputs = {}
    for directory in sorted(work.glob('*classes*')):
        if directory.is_dir():
            for p in sorted(directory.rglob('*')):
                if p.is_file() and not p.is_symlink():
                    outputs[str(p.relative_to(work))] = {'sha256': sha(p), 'bytes': p.stat().st_size}
                    p.chmod(0o400)
    write(LEAF / 'compiled-artifact-map.json', {'private_work_root': str(work), 'files': outputs, 'count': len(outputs)})
    tests_path = LEAF / 'tests.stdout'
    completed_tests = None
    if tests_path.exists():
        matches = re.findall(r'^OK \((\d+) tests\)$', tests_path.read_text(), re.MULTILINE)
        if len(matches) == 1:
            completed_tests = int(matches[0])
    after = readback()
    write(LEAF / 'execution-inputs-after.json', {'at': now(), 'changes': after, 'tools_sha256': tools,
                                             'staging_sha256': sha(PRIVATE / 'staging.json'), 'jdk_manifest_sha256': sha(runtime_manifest)})
    success = not code and api_code == 0 and completed_tests is not None and not any(after.values())
    result = {'status': 'pass' if success else 'fail', 'started_at': started, 'finished_at': now(), 'commands': commands,
              'source_sha256': stage['source_sha256'], 'binary_sha256': stage['binary_sha256'], 'tools_sha256': tools,
              'staged_binary_sha256': {x['path']: x['sha256'] for x in binaries.values()}, 'before_changes': before, 'after_changes': after,
              'jdk_runtime_closure_sha256': sha(runtime_manifest), 'java': str(java), 'suite_names': SUITES,
              'product_files': 15, 'shim_files': 5, 'full_android_native_files': 22, 'api_build_config_files': 1,
              'api': 'Android36 + matching retained Flutter embedding + lifecycle; JVM target17',
              'single_serial_attempt': True, 'all_owned_children_reaped': all(c.get('own_child_reaped', False) for c in commands),
              'junit_tests_passed': completed_tests, 'compiled_artifact_count': len(outputs),
              'compiled_artifact_map_sha256': sha(LEAF / 'compiled-artifact-map.json'),
              'aggregate_bound_seconds': 1200, 'each_compiler_bound_seconds': 480,
              'limits': ['Synthetic local AES/filesystem/backend seams; no physical Keystore/device/SMS/carrier/backend/host acceptance.',
                         'Direct native source/API compile; no Gradle/APK/merged-manifest/lint/signing proof.',
                         'New Temurin arm64 JDK21 vendor/patch plus internal staging is an explicitly different proof runtime, not a proven sole-cause fix.']}
    write(LEAF / 'validation.json', result)
    write(status_path, {'state': 'terminal', 'status': result['status'], 'at': now(), 'runner_pid': os.getpid(), 'child_pid': None,
                        'commands_completed': len(commands), 'all_owned_children_reaped': result['all_owned_children_reaped'],
                        'validation_sha256': sha(LEAF / 'validation.json')})
    print(json.dumps({'state': 'terminal', 'status': result['status'], 'commands': len(commands), 'changes': after}), flush=True)
    raise SystemExit(0 if success else 1)


def terminate_own_child():
    child = CURRENT_CHILD
    if child is None or child.returncode is not None:
        return
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        pid, status, _ = os.wait4(child.pid, os.WNOHANG)
        if pid:
            child.returncode = os.waitstatus_to_exitcode(status)
            return
        time.sleep(0.1)
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    _, status, _ = os.wait4(child.pid, 0)
    child.returncode = os.waitstatus_to_exitcode(status)


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        terminate_own_child()
        if not isinstance(error, SystemExit):
            write(LEAF / 'runner-failure.json', {'state': 'terminal_failed', 'at': now(), 'type': type(error).__name__, 'reason': str(error)})
        raise
