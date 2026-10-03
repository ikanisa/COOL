#!/usr/bin/env python3
"""Fresh candidate2 only; fail closed on separate exact root review authorization."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXECUTION = HERE.parent / 'kotlin-sdk-candidate2-execution-batch1'
AUTH = HERE.parent / 'root-sdk-foundation-review-batch1/candidate2-preparation-readback.json'
CANDIDATE = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-collect-kotlin-2.4.20-candidate2')
FAILED = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-collect-kotlin-2.4.20-candidate1')
GRADLE_HOME = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/private-gradle/sdk-kotlin-2.4.20-candidate1')
FAILURE_PACKET = HERE.parent / 'kotlin-sdk-candidate-execution-batch1'
FAILURE_MANIFEST_SHA = '71be02949c0e2c303f8f3e1e1d014035f7ae3a6330cbd9ec05f707bef81aee95'
COMMAND_SHA = 'c3f280e329807ab4d20e968a7d1c6420cc71499b5941c942c6d73479cf2736af'
EXPANSION_BYTES = 4244148641
MINIMUM_FREE_BYTES = EXPANSION_BYTES + 2 * 1024 ** 3


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def save(name, value):
    with (EXECUTION / name).open('x') as out:
        json.dump(value, out, indent=2, sort_keys=True)
        out.write('\n')
        out.flush()
        os.fsync(out.fileno())


def check_packet(directory, expected):
    if sha(directory / 'packet-files.json') != expected:
        raise ValueError('reviewed packet manifest drift')
    manifest = json.loads((directory / 'packet-files.json').read_text())
    for name, digest in manifest['files'].items():
        path = directory / name
        if path.is_symlink() or path.resolve() != path or sha(path) != digest:
            raise ValueError('exact reviewed packet leaf drift')
    return manifest


def check_authorization(args):
    manifest = check_packet(HERE, args.prepared_manifest_sha256)
    if sha(AUTH) != args.root_review_sha256:
        raise ValueError('separate exact root review receipt drift')
    auth = json.loads(AUTH.read_text())
    if (auth.get('local_execution_admitted') is not True or auth.get('errors') != []
            or auth.get('checked_packet_leaves') != manifest['file_count']
            or auth.get('packet_manifest_sha256') != args.prepared_manifest_sha256):
        raise ValueError('separate root receipt does not admit this exact complete preparation')
    if sha(HERE / 'candidate2-next-command.json') != COMMAND_SHA:
        raise ValueError('exact reviewed next command drift')
    return manifest


def stable_artifact_sha(path):
    if path.is_symlink() or path.resolve() != path or not path.is_relative_to(GRADLE_HOME) or path.stat().st_nlink != 1:
        raise ValueError('critical owned cache artifact not independent regular path')
    before = path.stat()
    with path.open('rb') as inp:
        opened = os.fstat(inp.fileno())
        h = hashlib.sha256()
        for chunk in iter(lambda: inp.read(1024 * 1024), b''):
            h.update(chunk)
        completed = os.fstat(inp.fileno())
    identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_mode, s.st_nlink)
    if any(identity(row) != identity(before) for row in (opened, completed, path.lstat())):
        raise ValueError('critical cache artifact FD/named-path race')
    return h.hexdigest()


def check_same_owned_cache():
    check_packet(FAILURE_PACKET, FAILURE_MANIFEST_SHA)
    if not GRADLE_HOME.is_dir() or GRADLE_HOME.is_symlink() or GRADLE_HOME.resolve() != GRADLE_HOME:
        raise ValueError('same owned private Gradlehome identity differs')
    terminal = json.loads((FAILURE_PACKET / 'sdk-compiler-runtime-attempt2.json').read_text())
    if subprocess.run(['ps', '-p', str(terminal['pid']), '-o', 'pid='], capture_output=True, text=True).stdout.strip():
        raise ValueError('old compiler PID still active; no cache reuse')
    observed_daemons = []
    for log in sorted((GRADLE_HOME / 'daemon/9.1.0').glob('daemon-*.out.log')):
        pid = int(log.name.removeprefix('daemon-').removesuffix('.out.log'))
        output = subprocess.run(['ps', '-p', str(pid), '-o', 'pid=,command='], capture_output=True, text=True).stdout.strip()
        if output:
            raise ValueError('previous owned daemon PID active; no cache reuse')
        observed_daemons.append({'log': str(log), 'pid': pid, 'process_absent': True})
    origin = json.loads((FAILURE_PACKET / 'actual-critical-publisher-license-bindings.json').read_text())
    fingerprints = [origin['core_raw_artifact'], origin['compiler_actual_cache_artifact']]
    fingerprints.extend(row['actual'] for row in origin['POMs'].values())
    current = {}
    for row in fingerprints:
        path = Path(row['path'])
        actual = stable_artifact_sha(path)
        if actual != row['sha256'] or path.stat().st_size != row['bytes']:
            raise ValueError('publisher-bound critical cache artifact fingerprint drift')
        current[str(path)] = actual
    return {'same_owner_cache_idle': True, 'critical_artifact_fingerprints': current, 'previous_daemons': observed_daemons, 'global_shared_caches_or_source_outputs_copied': False}


def run_stage(name, argv, timeout, cwd=None, env=None):
    tick = time.monotonic()
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(json.dumps({'stage': name, 'status': 'started', 'actual_deadline_seconds': timeout}), flush=True)
    result = {'argv': argv, 'started_utc': started, 'actual_deadline_seconds': timeout, 'timed_out': False, 'headroom_failure': False}
    with (EXECUTION / (name + '.stdout')).open('xb') as stdout, (EXECUTION / (name + '.stderr')).open('xb') as stderr:
        process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
        result['pid'] = process.pid
        deadline = tick + timeout
        while process.poll() is None:
            if time.monotonic() >= deadline or shutil.disk_usage(CANDIDATE.parent).free < 2 * 1024 ** 3:
                result['timed_out'] = time.monotonic() >= deadline
                result['headroom_failure'] = not result['timed_out']
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=10)
                break
            time.sleep(min(1, max(.01, deadline - time.monotonic())))
        result['exit_code'] = process.wait()
    result.update({'terminal_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'actual_seconds': round(time.monotonic() - tick, 3), 'stdout_sha256': sha(EXECUTION / (name + '.stdout')), 'stderr_sha256': sha(EXECUTION / (name + '.stderr')), 'runner_sha256': sha(__file__)})
    save(name + '.json', result)
    print(json.dumps({key: result[key] for key in ('exit_code', 'timed_out', 'headroom_failure', 'actual_seconds')}), flush=True)
    return result


def require_pass(result):
    if result['exit_code'] != 0 or result['timed_out'] or result['headroom_failure']:
        raise RuntimeError('actual stage failure retained; no candidate reuse')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared-manifest-sha256', required=True)
    parser.add_argument('--root-review-sha256', required=True)
    parser.add_argument('--expand-child', action='store_true')
    args = parser.parse_args()
    manifest = check_authorization(args)
    if args.expand_child:
        writer = load(HERE / 'authenticated_candidate2_expansion.py', 'exact_candidate2_expansion')
        result = writer.expand_after_separate_authorization(HERE.parent / 'kotlin-sdk-expansion-admission-batch1/exact-archive-admission.json', '9d22ab7c56ffdeb8d0b3b9c64022bd481403f86ff449ff4c257e8124ffcc3749', lambda value: print(json.dumps(value), flush=True))
        save('candidate2-physical-expansion-result.json', result)
        return 0
    if CANDIDATE.exists() or CANDIDATE.is_symlink() or EXECUTION.exists() or EXECUTION.is_symlink():
        raise ValueError('candidate2 and new execution packet must be absent; no reuse')
    if shutil.disk_usage(CANDIDATE.parent).free < MINIMUM_FREE_BYTES:
        raise ValueError('new expansion actual disk headroom prerequisite unavailable')
    cache = check_same_owned_cache()
    physical_plan = json.loads((HERE.parent / 'kotlin-sdk-physical-foundation-batch1/independent-three-file-validation-plan.json').read_text())
    command = json.loads((HERE / 'candidate2-next-command.json').read_text())
    wrapper = Path(command['argv'][1])
    inputs = {Path(physical_plan['java_executable']): physical_plan['java_executable_sha256'], wrapper: physical_plan['gradle_wrapper_script_sha256'], wrapper.parent / 'gradle/wrapper/gradle-wrapper.jar': physical_plan['gradle_wrapper_jar_sha256'], wrapper.parent / 'gradle/wrapper/gradle-wrapper.properties': physical_plan['gradle_wrapper_properties_sha256']}
    if any(sha(path) != digest for path, digest in inputs.items()):
        raise ValueError('exact reviewed standard Java/wrapper inputs changed')
    EXECUTION.mkdir(mode=0o700)
    save('authorized-workflow-start.json', {'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'root_review_receipt_sha256': args.root_review_sha256, 'prepared_manifest_sha256': args.prepared_manifest_sha256, 'prepared_leaf_files': manifest['file_count'], 'actual_free_bytes': shutil.disk_usage(CANDIDATE.parent).free, 'minimum_free_bytes': MINIMUM_FREE_BYTES, 'candidate2': str(CANDIDATE), 'same_owned_Gradle_home': str(GRADLE_HOME), 'cache_reuse_readback': cache, 'runner_sha256': sha(__file__), 'exact_command_sha256': COMMAND_SHA, 'failed_candidate1_sources_or_outputs_transferred': False})
    try:
        child = [sys.executable, '-I', '-B', str(Path(__file__).resolve()), '--prepared-manifest-sha256', args.prepared_manifest_sha256, '--root-review-sha256', args.root_review_sha256, '--expand-child']
        require_pass(run_stage('fresh-expansion-attempt1', child, 600))
        require_pass(run_stage('pristine-readback-attempt1', [sys.executable, '-I', '-B', str(HERE / 'verify_candidate2_source.py'), 'pristine', '--output', str(EXECUTION / 'candidate2-pristine-readback.json')], 300))
        patcher = load(HERE / 'apply_exact_cumulative8.py', 'exact_reviewed_cumulative8_application')
        save('exact-cumulative8-application.json', patcher.apply_after_separate_authorization(CANDIDATE))
        require_pass(run_stage('patched-readback-attempt1', [sys.executable, '-I', '-B', str(HERE / 'verify_candidate2_source.py'), 'patched', '--output', str(EXECUTION / 'candidate2-patched-readback.json')], 300))
        environment = {key: os.environ[key] for key in ('PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL') if key in os.environ}
        environment.update(command['environment'])
        compiler = run_stage('sdk-compiler-runtime-attempt1', command['argv'], 2700, cwd=command['cwd'], env=environment)
        readback = run_stage('built-readback-attempt1', [sys.executable, '-I', '-B', str(HERE / 'verify_candidate2_source.py'), 'built', '--output', str(EXECUTION / 'candidate2-built-readback.json')], 300)
        actual_pass = compiler['exit_code'] == readback['exit_code'] == 0 and not any(row['timed_out'] or row['headroom_failure'] for row in (compiler, readback))
        save('workflow-terminal.json', {'status': 'ACTUAL_COMPLETE_SDK_RECIPE_PASS__JUNIT_PUBLISHER_REVIEW_PENDING' if actual_pass else 'ACTUAL_FAILURE_RETAINED__NO_ACCEPTANCE', 'compiler_exit_code': compiler['exit_code'], 'complete_source_readback_exit_code': readback['exit_code'], 'source_delta_count': 8, 'failed_candidate1_pristine_shared_SDK_and_repo_pins_locks_modified': False, 'Flutter_bootstrap_Dart_application_executed': False, 'candidate_promoted': False, 'production_release_approval': False})
        return 0 if actual_pass else 1
    except Exception as error:
        save('workflow-terminal.json', {'status': 'ACTUAL_WORKFLOW_EXCEPTION_RETAINED__NO_ACCEPTANCE_OR_REUSE', 'exception_type': type(error).__name__, 'public_error': str(error), 'partial_candidate_preserved': True, 'candidate_promoted': False, 'production_release_approval': False})
        raise


if __name__ == '__main__':
    raise SystemExit(main())
