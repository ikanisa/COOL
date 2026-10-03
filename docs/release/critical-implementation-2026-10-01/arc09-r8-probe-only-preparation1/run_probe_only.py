#!/usr/bin/env python3
"""Root-selected exact configuration probe; no graph, compiler or package command."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess
import sys
import time
import types

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
DRIVER = RELEASE / 'arc09-r8-9.1.29-preparation1/driver/run_selected_aab.py'
DRIVER_SHA256 = '6aec0de17f91f3981d2def8be12cc7f0f10eba40fca6c17ffea6f11166a893fc'


def compiler_observation(stdout):
    prefix = 'COLLECT_DEFAULT_PROGUARD_READBACK='
    lines = [line[len(prefix):] for line in stdout.splitlines() if line.startswith(prefix)]
    if len(lines) != 1: raise ValueError('exactly one actual configuration observation required')
    row = json.loads(lines[0])
    if (row['kind'] != 'collect_default_proguard_directory_readback'
            or not isinstance(row['actual_R8_compiler_readback'], dict)):
        raise ValueError('actual compiler observation missing')
    return row


def capture_provider(ctx, row):
    compiler = row['actual_R8_compiler_readback']
    captured = {}
    for label in ('provider', 'resolved_artifact'):
        observed = compiler[label]
        actual = ctx.reader.stable_read(Path(observed['path']))[0]
        if (actual['sha256'], actual['bytes']) != (observed['sha256'], observed['bytes']):
            raise ValueError('actual compiler ' + label + ' changed after observation')
        captured[label] = actual
    return {'kind': 'actual_R8_classloader_provider_observation',
            'actual_compiler_readback': compiler,
            'source_artifact_sha256': compiler['resolved_artifact']['sha256'],
            'provider': compiler['provider'], 'stable_readback': captured,
            'root_transformed_provider_admission_claimed': False,
            'APP_compilation_or_AAB_acceptance': False, 'production_release_approval': False}


def run_probe(ctx, driver, output, args):
    """Always stop after readback/classification and required source/protected guards."""
    started = time.monotonic()
    whole_deadline = started + 1800
    env = ctx.config['environment_exact']; command = ctx.readback_command
    if (command['label'] != 'production-default-proguard-readback'
            or command['deadline_seconds'] != 300
            or command['argv'][-1] != ':app:collectVerifyDefaultProguardDirectory'):
        raise ValueError('existing exact300 configuration probe command required')
    results = {}; errors = []; classification = 'NO_VALID_OBSERVATION'

    def invoke(label, argv, seconds, cwd, gradle=False):
        if time.monotonic() + seconds + 30 > whole_deadline:
            raise ValueError('finite probe/guard envelope cannot admit next stage')
        tracker = driver.DaemonTracker(ctx, output, label) if gradle else None
        original = ctx.controller.subprocess
        if tracker:
            def popen(*call_args, **call_kwargs):
                child = subprocess.Popen(*call_args, **call_kwargs)
                try: tracker.register(child)
                except BaseException as registration_error:
                    try: ctx.controller.stop_group(child)
                    finally: tracker.error = {'spawned_pid': child.pid, 'registration_error': str(registration_error)}
                    raise
                return child
            ctx.controller.subprocess = types.SimpleNamespace(Popen=popen, TimeoutExpired=subprocess.TimeoutExpired)
        actual = None; daemon = None
        try:
            actual = ctx.controller.run_process(output, label, argv, seconds, cwd, env)
        finally:
            ctx.controller.subprocess = original
            if tracker:
                daemon = tracker.finish()
                driver.save(output / (label + '.owned-daemon-readback.json'), daemon)
        results[label] = {'command': actual, 'daemon': daemon}
        ctx.guards.process_success(actual or {})
        if tracker and (daemon.get('observer_error') is not None or not daemon['owned_daemons_absent']):
            raise ValueError('reviewed tracker did not prove owned private daemon absence')
        return actual

    def guards(phase):
        fence = ctx.current_app_export['current_repository_source_fence_pin']
        argv = [ctx.config['Python_executable'], '-I', '-B', str(driver.PREP / 'source_fence.py'), 'verify',
                '--root', str(driver.ROOT), '--binding', fence['path'], '--binding-sha256', fence['sha256'],
                '--output', str(output / ('source-fence-' + phase + '.json'))]
        guard_errors = []
        try: invoke('source-fence-' + phase + '-command', argv, 300, driver.PREP)
        except BaseException as error:
            guard_errors.append({'guard': 'maintained-source', 'type': type(error).__name__, 'error': str(error)})
        argv = [ctx.config['Python_executable'], '-I', '-B', str(HERE / 'run_probe_only.py'),
                '--controller-sha256', args.controller_sha256, '--admission', str(args.admission),
                '--admission-sha256', args.admission_sha256, '--output', str(output), '--guard-phase', phase]
        try: invoke('combined-guard-' + phase + '-command', argv, 300, HERE)
        except BaseException as error:
            guard_errors.append({'guard': 'APP-SDK-protected', 'type': type(error).__name__, 'error': str(error)})
        if guard_errors: raise ValueError(json.dumps(guard_errors, sort_keys=True))

    try:
        table = driver.process_table()
        for old in ctx.admission['native_observed_daemons']:
            if old['pid'] in table or not driver.group_absent(old['pgid']):
                raise ValueError('prior owned native daemon not absent')
        preflight = driver.DaemonTracker(ctx, output, 'preflight')
        for process in table.values():
            if preflight.private_identity(process) is not None:
                raise ValueError('existing private-home Gradle daemon; no stop attempted')
        guards('before')
        invoke(command['label'], command['argv'], 300, command['cwd'], True)
        stdout = (output / (command['label'] + '.stdout')).read_text()
        row = compiler_observation(stdout)
        # Persist actual evidence before provider admission can refuse an unknown JAR.
        driver.save(output / 'configuration-observation.json', row)
        driver.save(output / 'compiler-provider-observation.json', capture_provider(ctx, row))
        default_path = Path(row['default_proguard_file'])
        if not default_path.is_relative_to(driver.BASE / 'native-build/app'):
            raise ValueError('observed default rule is outside the controlled app build directory')
        actual_rule = ctx.reader.stable_read(default_path)[0]
        if (actual_rule['sha256'], actual_rule['bytes']) != (row['actual_default_file_sha256'], row['actual_default_file_bytes']):
            raise ValueError('actual default Proguard file changed after readback')
        driver.save(output / 'actual-default-rule-readback.json', actual_rule)
        try:
            ctx.overlay.validate_proguard_output(stdout, driver.BASE / 'native-build/app')
            classification = 'OBSERVED_ADMITTED_PROVIDER'
        except ValueError as error:
            if str(error) != 'actual R8 classloader uses an unknown or unadmitted compiler provider':
                raise
            classification = 'OBSERVED_UNADMITTED_PROVIDER'
            driver.save(output / 'provider-admission-refusal.json', {'actual_error': str(error),
                'actual_compiler_evidence_retained': True, 'root_review_required_before_full_driver': True,
                'production_release_approval': False})
    except BaseException as error:
        errors.append({'type': type(error).__name__, 'error': str(error)})
    finally:
        # Verify current maintained/APP/SDK/protected inputs even on unknown-provider observation.
        try: guards('after')
        except BaseException as error:
            errors.append({'phase': 'after', 'type': type(error).__name__, 'error': str(error)})
        try: driver.context(args)
        except BaseException as error:
            errors.append({'phase': 'final-admission', 'type': type(error).__name__, 'error': str(error)})
        driver.save(output / 'terminal.json', {'kind': 'actual_probe_only_terminal',
            'classification': classification, 'required_guards_complete': not errors,
            'commands': results, 'errors': errors, 'actual_seconds': time.monotonic() - started,
            'whole_finite_seconds': 1800, 'probe_deadline_seconds': 300,
            'fresh_runtime_compile_graphs_executed': False, 'APP_compiled': False, 'AAB_built': False,
            'transformed_provider_admission_claimed': False, 'ARC09_closed': False,
            'protected_original_PID_scope': 68020, 'signal_authority_for_protected_original_PID': False,
            'production_release_approval': False})
    return 1 if errors else (2 if classification == 'OBSERVED_UNADMITTED_PROVIDER' else 0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--controller-sha256', required=True)
    parser.add_argument('--admission', required=True, type=Path)
    parser.add_argument('--admission-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--guard-phase', choices=('before', 'after'))
    args = parser.parse_args()
    raw = DRIVER.read_bytes()
    import hashlib
    if hashlib.sha256(raw).hexdigest() != DRIVER_SHA256: raise ValueError('unchanged reviewed driver differs')
    driver = types.ModuleType('r8_probe_reviewed_driver'); driver.__file__ = str(DRIVER)
    exec(compile(raw, str(DRIVER), 'exec'), driver.__dict__)
    driver.plain_read(HERE / 'run_probe_only.py', args.controller_sha256)
    ctx = driver.context(args)  # Actual root-held source/manifest/fence/admission; no invented hashes.
    output = args.output
    if (not output.is_absolute() or output.resolve() != output or output.parent != RELEASE
            or not output.name.startswith('root-arc09-r8-probe-observation')):
        raise ValueError('fresh root-owned physical probe output required')
    if args.guard_phase:
        driver.physical(output)
        driver.guard_phase(ctx, output, args.guard_phase)
        return 0
    output.mkdir(mode=0o700, exist_ok=False)
    driver.save(output / 'root-admission-captured.json', ctx.admission)
    return run_probe(ctx, driver, output, args)


if __name__ == '__main__': raise SystemExit(main())
