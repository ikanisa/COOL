#!/usr/bin/env python3
"""Separate actual attempt; unchanged frozen compiler command and owned inputs."""
import datetime
import hashlib
import importlib.util
import json
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXPECTED_RUNNER = '7e2cefbaaed856764e893d715984a7c1b0089e13eb878a366855f800b352b349'
EXPECTED_ZIP = 'b84e04fa845fecba48551f425957641074fcc00a88a84d2aae5808743b35fc85'


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    runner_path = HERE / 'run_candidate_workflow.py'
    if digest(runner_path) != EXPECTED_RUNNER:
        raise ValueError('original stage runner drift')
    spec = importlib.util.spec_from_file_location('unchanged_owned_stage_runner', runner_path)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    runner.checked_prep()
    cancellation = json.loads((HERE / 'sdk-compiler-runtime-attempt1-cancelled.json').read_text())
    if cancellation['remaining_process_group_members'] or cancellation['timed_out'] or cancellation['compile_failure_claimed']:
        raise ValueError('previous attempt is not explicitly terminated cancellation')
    copy = json.loads((HERE / 'raw-gradle-distribution-copy.json').read_text())
    raw = Path(copy['target_path'])
    if raw.is_symlink() or raw.stat().st_nlink != 1 or digest(raw) != EXPECTED_ZIP:
        raise ValueError('owned exclusive authenticated raw distribution drift')
    if shutil.disk_usage(runner.CANDIDATE.parent).free < 2 * 1024 ** 3:
        raise ValueError('actual headroom prerequisite unavailable')
    command = json.loads((runner.PREP / 'candidate-next-command.json').read_text())
    original = json.loads((runner.PHYSICAL / 'independent-three-file-validation-plan.json').read_text())
    wrapper = Path(command['argv'][1])
    identities = {
        Path(original['java_executable']): original['java_executable_sha256'],
        wrapper: original['gradle_wrapper_script_sha256'],
        wrapper.parent / 'gradle/wrapper/gradle-wrapper.jar': original['gradle_wrapper_jar_sha256'],
        wrapper.parent / 'gradle/wrapper/gradle-wrapper.properties': original['gradle_wrapper_properties_sha256'],
    }
    if any(digest(path) != expected for path, expected in identities.items()):
        raise ValueError('reviewed Java or standard wrapper identity drift')
    environment = {key: os.environ[key] for key in ('PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL') if key in os.environ}
    environment.update(command['environment'])
    runner.save('compiler-attempt2-start.json', {
        'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'runner_sha256': digest(__file__), 'unchanged_stage_runner_sha256': EXPECTED_RUNNER,
        'exact_frozen_command_sha256': runner.COMMAND_SHA,
        'previous_explicit_cancellation_sha256': digest(HERE / 'sdk-compiler-runtime-attempt1-cancelled.json'),
        'raw_publisher_zip_copy_receipt_sha256': digest(HERE / 'raw-gradle-distribution-copy.json'),
        'actual_deadline_seconds': 2700, 'argv': command['argv'], 'cwd': command['cwd'],
        'environment_overrides': command['environment'],
        'shared_extracted_or_module_caches_copied': False,
        'new_source_dependency_or_argv_deltas': False,
    })
    compiler_error = None
    readback_error = None
    try:
        runner.run_stage('sdk-compiler-runtime-attempt2', command['argv'], 2700, cwd=command['cwd'], env=environment)
    except Exception as error:
        compiler_error = {'type': type(error).__name__, 'public_error': str(error)}
    try:
        runner.run_stage('built-source-attempt2', [sys.executable, '-I', '-B', str(runner.PREP / 'verify_candidate_source.py'), 'built', '--output', str(HERE / 'candidate-built-source-attempt2-readback.json')], 300)
    except Exception as error:
        readback_error = {'type': type(error).__name__, 'public_error': str(error)}
    runner.save('compiler-attempt2-terminal.json', {
        'status': 'ACTUAL_COMPILER_PASS__JUNIT_PUBLISHER_REVIEW_PENDING' if not compiler_error and not readback_error else 'ACTUAL_FAILURE_RETAINED__NO_ACCEPTANCE',
        'compiler_error': compiler_error, 'complete_source_readback_error': readback_error,
        'candidate_promoted': False, 'production_release_approval': False,
        'Flutter_script_bootstrap_Dart_app_build_executed': False,
    })
    return 1 if compiler_error or readback_error else 0


if __name__ == '__main__':
    raise SystemExit(main())
