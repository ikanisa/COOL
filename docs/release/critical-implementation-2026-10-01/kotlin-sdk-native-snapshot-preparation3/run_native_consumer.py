#!/usr/bin/env python3
"""Separate reviewed stages only; never auto-advance, promote or reuse failure."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PROPOSAL = Path(__file__).resolve().parent
RELEASE = PROPOSAL.parent
HERE = RELEASE / 'kotlin-sdk-native-consumer-preparation1'
REPO = RELEASE.parents[2]
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
SDK = BASE / 'flutter'
APP = BASE / 'app-source'
AUTH_DIR = RELEASE / 'root-sdk-native-snapshot-review3'
ORIGINAL_PREPARATION_MANIFEST = '9f08883dc0db884cee715d30e1c0efda31f5285d614aae0acc69da7418dc73bc'
SOURCE_FENCE = AUTH_DIR / 'source-fence.json'
STAGES = ('foundation', 'sdk-lock', 'startup', 'app-export', 'app-lock', 'native')
MIN_FREE = 20350276001
LIVE_FLOOR = 4 * 1024**3
PLAN_MANIFEST = 'ff279d8dbeb0686e89407430dbcc60f6293694989fe8ff2e43b56d0b159fcb44'
COMPLETED_MANIFEST = 'e39ca4e70450d8f5b7bbb5926e9df043ba69377b49ef38119f09fb8dfbfbdf1e'


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


def reader():
    return load(HERE / 'publisher_metadata.py', 'controller_exact_reader')


def sha(path):
    return reader().stable_read(Path(path))[0]['sha256']


def save(path, value):
    with path.open('x') as output:
        json.dump(value, output, indent=2, sort_keys=True); output.write('\n')
        output.flush(); os.fsync(output.fileno())


def packet(directory, expected):
    row, body = reader().stable_read(directory / 'packet-files.json', True)
    if row['sha256'] != expected: raise ValueError('frozen manifest changed')
    document = json.loads(body)
    for name, digest in document['files'].items():
        path = directory / name
        if Path(name).is_absolute() or '..' in Path(name).parts or sha(path) != digest:
            raise ValueError('frozen packet leaf changed')
    return document


def receipt_path(stage):
    if stage not in STAGES: raise ValueError('unreviewed stage receipt path')
    return AUTH_DIR / (stage + '-admission.json')


def authorization(args):
    if args.stage != 'app-export' or getattr(args, 'foundation_child', False):
        raise ValueError('this separately reviewed derivative admits only app-export')
    manifest = packet(PROPOSAL, args.prepared_manifest_sha256)
    packet(HERE, ORIGINAL_PREPARATION_MANIFEST)
    row, body = reader().stable_read(receipt_path(args.stage), True)
    if row['sha256'] != args.root_review_sha256: raise ValueError('separate root authorization receipt differs')
    document = json.loads(body)
    if (document.get('errors') != [] or document.get('packet_manifest_sha256') != args.prepared_manifest_sha256
            or document.get('checked_packet_leaves') != len(manifest['files'])
            or document.get('execution_stage_admissions', {}).get(args.stage) is not True):
        raise ValueError('exact stage/full preparation not separately authorized')
    if (document.get('current_source_export_authorized') is not True
            or document.get('strict_current_source_comparison_required') is not True
            or document.get('private_snapshot_exclusive') is not True
            or document.get('source_scope_held_for_strict_export') is not False
            or document.get('source_lock_attested') is not False
            or document.get('transient_write_and_restore_absence_attested') is not False):
        raise ValueError('strict snapshot admission must require comparisons and disclose absence of a source lock')
    expected_fence = document.get('required_source_fence_sha256')
    if not isinstance(expected_fence, str) or not re.fullmatch('[0-9a-f]{64}', expected_fence) or sha(SOURCE_FENCE) != expected_fence:
        raise ValueError('root-pinned source identity/index/membership/fixture fence differs')
    index = STAGES.index(args.stage)
    if index:
        prior = BASE / '.control' / STAGES[index - 1] / 'terminal.json'
        row, body = reader().stable_read(prior, True)
        expected = document.get('required_predecessor_terminal_sha256')
        terminal = json.loads(body)
        if (not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected) or row['sha256'] != expected
                or terminal.get('stage_pass') is not True or terminal.get('stage') != STAGES[index - 1]):
            raise ValueError('actual predecessor terminal lacks separate exact root readback admission')
    if args.stage in ('app-lock', 'native'):
        export_binding(args)
    packet(RELEASE / 'kotlin-sdk-native-consumer-plan1', PLAN_MANIFEST)
    packet(RELEASE / 'kotlin-sdk-candidate2-execution-batch1', COMPLETED_MANIFEST)
    return manifest


def export_binding(args):
    auth_row, auth_body = reader().stable_read(receipt_path(args.stage), True)
    if auth_row['sha256'] != args.root_review_sha256: raise ValueError('separate root receipt raced before export binding')
    expected = json.loads(auth_body).get('required_app_export_binding_sha256')
    if not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected):
        raise ValueError('later app stage lacks separately root-pinned original strict export binding')
    path = BASE / '.control/app-export/export-source-binding.json'
    row, body = reader().stable_read(path, True)
    if row['sha256'] != expected: raise ValueError('original export source/manifest/lock binding changed')
    binding = json.loads(body)
    if (binding.get('kind') != 'actual_strict_unapproved_export_binding' or binding.get('export_stage_actual_pass') is not True
            or binding.get('source_root') != str(APP) or binding.get('production_release_approval') is not False
            or any(not isinstance(binding.get(key), str) or not re.fullmatch('[0-9a-f]{64}', binding[key])
                   for key in ('export_manifest_file_sha256', 'source_manifest_sha256', 'original_app_lock_sha256'))):
        raise ValueError('actual original strict app export binding malformed')
    return binding


def protected_metadata():
    rows = json.loads((HERE / 'protected-original-metadata.json').read_text())['paths']
    actual = {}
    for name, expected in rows.items():
        path = Path(name); row = path.lstat()
        current = {'device': row.st_dev, 'inode': row.st_ino, 'size': row.st_size,
                   'mode': row.st_mode, 'nlink': row.st_nlink, 'mtime_ns': row.st_mtime_ns, 'ctime_ns': row.st_ctime_ns}
        if stat.S_ISLNK(row.st_mode): current['target'] = os.readlink(path)
        if current != expected: raise ValueError('protected original mode/time/identity changed: ' + name)
        actual[name] = current
    return {'protected_metadata_paths_unchanged': len(actual), 'no_original_metadata_restoration_performed': True}


def existing_volume(path):
    path = Path(path)
    while not path.exists(): path = path.parent
    if path.resolve() != path: raise ValueError('physical volume ancestor alias')
    return path


def stop_group(process):
    for sig, grace in ((signal.SIGTERM, 5), (signal.SIGKILL, 5)):
        try: os.killpg(process.pid, sig)
        except ProcessLookupError: break
        try: process.wait(timeout=grace)
        except subprocess.TimeoutExpired: continue
    return process.wait(timeout=5)


def run_process(directory, name, argv, seconds, cwd, env, floor=LIVE_FLOOR):
    started = time.monotonic(); deadline = started + seconds
    record = {'argv': argv, 'cwd': str(cwd), 'deadline_seconds': seconds,
              'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'timed_out': False, 'headroom_failure': False, 'spawned': False, 'owned_process_group_absent': True, 'residual_process_group_required_stop': False}
    stdout_path = directory / (name + '.stdout'); stderr_path = directory / (name + '.stderr')
    process = None; caught_error = None
    with stdout_path.open('xb') as stdout, stderr_path.open('xb') as stderr:
        try:
            record['timed_out'] = time.monotonic() >= deadline
            record['headroom_failure'] = shutil.disk_usage(directory).free < floor
            if not record['timed_out'] and not record['headroom_failure']:
                process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
                record['pid'] = process.pid; record['spawned'] = True
                while process.poll() is None:
                    record['timed_out'] = record['timed_out'] or time.monotonic() >= deadline
                    record['headroom_failure'] = record['headroom_failure'] or shutil.disk_usage(directory).free < floor
                    if record['timed_out'] or record['headroom_failure']:
                        stop_group(process); break
                    time.sleep(min(1, max(.01, deadline - time.monotonic())))
                record['exit_code'] = process.wait()
            else: record['exit_code'] = None
            # Terminal observation is also bounded: a fast/reaped child cannot bypass guards.
            record['timed_out'] = record['timed_out'] or time.monotonic() >= deadline
            record['headroom_failure'] = record['headroom_failure'] or shutil.disk_usage(directory).free < floor
        except BaseException as error:
            caught_error = error
            record['actual_controller_error'] = {'type': type(error).__name__, 'public_error': str(error)}
            if process is not None:
                try: stop_group(process)
                except BaseException as stop_error:
                    record['owned_group_stop_error'] = {'type': type(stop_error).__name__, 'public_error': str(stop_error)}
                record['exit_code'] = process.poll()
            else: record['exit_code'] = None
        finally:
            if process is not None:
                try:
                    try: os.killpg(process.pid, 0)
                    except ProcessLookupError: record['owned_process_group_absent'] = True
                    else:
                        record['residual_process_group_required_stop'] = True
                        stop_group(process)
                        for _ in range(50):
                            try: os.killpg(process.pid, 0)
                            except ProcessLookupError: break
                            time.sleep(.1)
                        try: os.killpg(process.pid, 0)
                        except ProcessLookupError: record['owned_process_group_absent'] = True
                        else: record['owned_process_group_absent'] = False
                except OSError as error:
                    # EPERM cannot establish absence. Retain the actual probe failure;
                    # do not lose its receipt or accept an exit-zero leader as success.
                    record['owned_process_group_absent'] = False
                    record['residual_process_group_required_stop'] = True
                    record['actual_group_probe_error'] = {'type': type(error).__name__, 'errno': error.errno,
                                                         'public_error': str(error)}
    record.update({'actual_seconds': round(time.monotonic() - started, 3),
                   'finished_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   'stdout_sha256': sha(stdout_path), 'stderr_sha256': sha(stderr_path)})
    save(directory / (name + '.json'), record)
    if caught_error is not None: raise caught_error
    if record.get('owned_process_group_absent') is not True:
        raise RuntimeError('owned process group remains; no source acceptance')
    return record


def require_pass(record):
    load(HERE / 'consumer_guards.py', 'controller_guards').process_success(record)


def source_readback(directory, phase, environment, observation):
    if observation not in ('before', 'after'):
        raise ValueError('unreviewed SDK source observation')
    output = directory / ('SDK-source-' + observation + '-' + phase + '.json')
    command = [sys.executable, '-I', '-B', str(HERE / 'verify_native_consumer_source.py'), phase, '--output', str(output)]
    record = run_process(directory, 'SDK-readback-' + observation + '-' + phase, command, 300, HERE, environment)
    require_pass(record)
    return {'output_sha256': sha(output), 'process': record}


def seed_raw_gradle(directory, config):
    source = Path(config['raw_published_Gradle_ZIP_source'])
    row, _ = reader().stable_read(source)
    if (row['sha256'], row['bytes']) != (config['raw_Gradle_ZIP_SHA256'], config['raw_Gradle_ZIP_bytes']):
        raise ValueError('public Gradle ZIP differs from independent published checksum')
    destination = BASE / 'gradle-home' / config['raw_Gradle_ZIP_owned_relative_destination']
    if destination.exists(): raise ValueError('owned raw ZIP must be absent')
    destination.parent.mkdir(parents=True, exist_ok=True)
    tick = time.monotonic()
    before = source.lstat()
    identity = reader().identity
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as incoming, destination.open('xb') as output:
        if identity(os.fstat(incoming.fileno())) != identity(before): raise ValueError('raw ZIP input FD opening race')
        for chunk in iter(lambda: incoming.read(1024**2), b''):
            if time.monotonic() - tick >= 300 or shutil.disk_usage(BASE).free < LIVE_FLOOR:
                raise RuntimeError('owned raw ZIP copy deadline/headroom failure retained')
            output.write(chunk)
        output.flush(); os.fsync(output.fileno())
        if identity(os.fstat(incoming.fileno())) != identity(before): raise ValueError('raw ZIP input FD mutation during copy')
    if identity(source.lstat()) != identity(before): raise ValueError('raw ZIP input named leaf replacement during copy')
    copied, _ = reader().stable_read(destination)
    reread, _ = reader().stable_read(source)
    if ((copied['sha256'], copied['bytes']) != (row['sha256'], row['bytes']) or reread != row
            or (copied['device'], copied['inode']) == (row['device'], row['inode'])):
        raise ValueError('raw public ZIP physical copy/readback drift')
    save(directory / 'raw-Gradle-exclusive-copy.json', {'source': row, 'destination': copied,
         'source_path': str(source), 'destination_path': str(destination), 'distinct_inode': True,
         'standard_unchanged_wrapper_authentication_still_required': True,
         'global_extracted_or_module_caches_copied': False})


def junit_and_classes():
    build = BASE / 'native-build/app'; reports = sorted((build / 'test-results/testProductionDebugUnitTest').glob('TEST-*.xml'))
    if not reports: raise ValueError('actual Production JVM XML absent; zero tests not accepted')
    totals = dict(tests=0, failures=0, errors=0, skipped=0); suites = []
    for report in reports:
        row, body = reader().stable_read(report, True)
        if b'<!DOCTYPE' in body or b'<!ENTITY' in body: raise ValueError('unsafe actual XML')
        suite = ET.fromstring(body); cases = suite.findall('testcase')
        counts = {key: int(suite.get(key, '-1')) for key in totals}
        if (suite.tag != 'testsuite' or counts['tests'] != len(cases) or not cases
                or any(counts[key] for key in ('failures', 'errors', 'skipped'))
                or any(case.find('failure') is not None or case.find('error') is not None or case.find('skipped') is not None for case in cases)):
            raise ValueError('actual JVM failures/skip/report count drift')
        for key in totals: totals[key] += counts[key]
        suites.append({'suite': suite.get('name'), 'counts': counts, 'file': row,
                       'actual_case_names': [case.get('name') for case in cases]})
    classes = {}
    for root in (build / 'tmp/kotlin-classes/productionRelease', build / 'intermediates/javac/productionRelease'):
        for path in sorted(root.rglob('*.class')):
            row, body = reader().stable_read(path, True)
            if body[:4] != b'\xca\xfe\xba\xbe': raise ValueError('native class magic drift')
            classes[path.relative_to(build).as_posix()] = row
    if not classes: raise ValueError('actual Production release compiled class files absent')
    return {'actual_JVM_totals': totals, 'actual_XML_suites': suites, 'actual_release_classes': classes,
            'all_flavor_ABI_artifact_clearance': False, 'ARC09_closed': False, 'production_release_approval': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', required=True, choices=('app-export',))
    parser.add_argument('--prepared-manifest-sha256', required=True)
    parser.add_argument('--root-review-sha256', required=True)
    parser.add_argument('--foundation-child', action='store_true')
    args = parser.parse_args(); authorization(args)
    config = json.loads((PROPOSAL / 'proposed-commands.json').read_text())
    snapshot_guard = load(PROPOSAL / 'source_fence.py', 'strict_snapshot_guard')
    snapshot_guard.validate_commands(config, HERE, PROPOSAL, REPO, BASE, SDK, APP, AUTH_DIR)
    if (str(Path(sys.executable).resolve()) != config['Python_executable']
            or sha(Path(config['Python_executable'])) != config['Python_SHA256']):
        raise ValueError('reviewed Python actual runtime differs')
    if args.foundation_child:
        if args.stage != 'foundation': raise ValueError('writer child allowed only exact foundation stage')
        writer = load(HERE / 'authenticated_native_consumer_expansion.py', 'authorized_consumer_writer')
        expanded = writer.expand_after_separate_authorization(RELEASE / 'kotlin-sdk-expansion-admission-batch1/exact-archive-admission.json',
            '9d22ab7c56ffdeb8d0b3b9c64022bd481403f86ff449ff4c257e8124ffcc3749')
        validator = load(HERE / 'verify_native_consumer_source.py', 'consumer_source_validator')
        pristine = validator.verify('pristine')
        applied = load(HERE / 'apply_native_consumer_cumulative8.py', 'consumer_exact_patch').apply_after_separate_authorization(SDK)
        patched = validator.verify('patched')
        save(BASE / '.control/foundation/full-source-and-metadata.json', {'expansion': expanded, 'pristine': pristine,
              'exact_cumulative8': applied, 'patched': patched, 'SDK_executed': False})
        return 0
    if args.stage == 'foundation':
        if BASE.exists() or BASE.is_symlink() or BASE.parent.resolve() != BASE.parent:
            raise ValueError('fresh physical consumer root must be absent and unaliased')
        if shutil.disk_usage(existing_volume(BASE.parent)).free < MIN_FREE: raise ValueError('actual independent headroom prerequisite missing')
        BASE.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        BASE.mkdir(mode=0o700)
        for name in ('.control', 'home', 'tmp', 'pub-cache', 'gradle-home', 'native-build'):
            (BASE / name).mkdir(mode=0o700)
    elif BASE.resolve() != BASE or not BASE.is_dir():
        raise ValueError('exact previously successful owned physical root required')
    index = STAGES.index(args.stage)
    if index:
        previous = BASE / '.control' / STAGES[index - 1] / 'terminal.json'
        if load(HERE / 'consumer_guards.py', 'prior_terminal_reader').read_json(previous).get('stage_pass') is not True:
            raise ValueError('actual predecessor did not pass; no advancing or failure reuse')
    directory = BASE / '.control' / args.stage
    directory.mkdir(mode=0o700)
    env = config['environment_exact']
    guards = load(HERE / 'consumer_guards.py', 'native_stage_guards')
    pending_export_binding = None
    try:
        save(directory / 'start.json', {'stage': args.stage, 'prepared_manifest_sha256': args.prepared_manifest_sha256,
              'separate_root_receipt_sha256': args.root_review_sha256, 'actual_free_bytes': shutil.disk_usage(BASE).free,
              'protected_before': protected_metadata(), 'argv_configuration_sha256': sha(PROPOSAL / 'proposed-commands.json'),
              'private_environment_exact': env, 'no_provider_or_signing_variables_inherited': True})
        if args.stage == 'foundation':
            argv = [sys.executable, '-I', '-B', str(Path(__file__).resolve()), '--stage', 'foundation',
                '--prepared-manifest-sha256', args.prepared_manifest_sha256, '--root-review-sha256', args.root_review_sha256, '--foundation-child']
            require_pass(run_process(directory, 'exclusive-expansion-and-exact8', argv, 600, HERE, env))
        else:
            source_readback(directory, 'patched' if args.stage == 'sdk-lock' else 'sdk-locked' if args.stage == 'startup' else 'startup' if args.stage == 'app-export' else 'app-locked' if args.stage == 'native' else 'startup', env, 'before')
            if args.stage == 'app-export':
                snapshot_guard.private_destination(APP, BASE)
                if APP.exists() or APP.is_symlink() or sha(REPO / 'scripts/qa/collect_release_candidate.py') != config['reviewed_exporter_SHA256']:
                    raise ValueError('strict export destination/caller identity differs')
                if sha(Path(config['Node_executable'])) != config['Node_SHA256']: raise ValueError('reviewed Node identity differs')
                fence_command = [sys.executable, '-I', '-B', str(PROPOSAL / 'source_fence.py'), 'verify',
                    '--root', str(REPO), '--binding', str(SOURCE_FENCE), '--binding-sha256',
                    guards.read_json(receipt_path(args.stage), args.root_review_sha256)['required_source_fence_sha256'],
                    '--output', str(directory / 'source-fence-before-capture.json')]
                require_pass(run_process(directory, 'source-fence-before', fence_command, 300, PROPOSAL, env))
            if args.stage in ('app-lock', 'native'):
                original_export = export_binding(args)
                source = guards.app_readback('app-export' if args.stage == 'app-lock' else 'app-locked', original_export['export_manifest_file_sha256'])
                app_lock = original_export['original_app_lock_sha256']
                if source['source_manifest_sha256'] != original_export['source_manifest_sha256']:
                    raise ValueError('original strict app export source digest changed')
                guards.require_lock(APP / 'pubspec.lock', app_lock)
                if args.stage == 'app-lock':
                    with (APP / 'android/local.properties').open('x') as output:
                        os.fchmod(output.fileno(), 0o600)
                        output.write('sdk.dir=' + env['ANDROID_SDK_ROOT'] + '\nflutter.sdk=' + str(SDK) + '\n')
                        output.flush(); os.fsync(output.fileno())
                else:
                    if sha(Path(config['JDK_java_executable'])) != config['JDK_java_SHA256']: raise ValueError('reviewed Java bytes changed')
                    for relative in ('platforms/android-36/android.jar', 'ndk/28.2.13676358/source.properties', 'build-tools/36.0.0/source.properties'):
                        if not (Path(env['ANDROID_SDK_ROOT']) / relative).is_file(): raise ValueError('installed Android prerequisite absent; auto-download disabled')
                    seed_raw_gradle(directory, config)
            command = config['commands'][args.stage]
            process = run_process(directory, 'actual-command', command['argv'], command['deadline_seconds'], command['cwd'], env)
            require_pass(process)
            stdout = (directory / 'actual-command.stdout').read_text(); stderr = (directory / 'actual-command.stderr').read_text()
            guards.forbid_upgrade_branch(stdout, stderr)
            guards.require_lock(SDK / 'packages/flutter_tools/pubspec.lock', guards.SDK_LOCK)
            if args.stage == 'startup': save(directory / 'actual-version.json', guards.startup_version(stdout, stderr))
            if args.stage == 'sdk-lock': save(directory / 'resolved-SDK-packages.json', guards.package_config(SDK / 'packages/flutter_tools/.dart_tool/package_config.json', (SDK, BASE / 'pub-cache')))
            if args.stage == 'app-export':
                after_command = list(fence_command)
                after_command[-1] = str(directory / 'source-fence-after-capture.json')
                require_pass(run_process(directory, 'source-fence-after', after_command, 300, PROPOSAL, env))
                snapshot_guard.private_candidate(APP, BASE)
                exported = guards.app_readback('app-export')
                save(directory / 'exact-app-export-readback.json', exported)
                pending_export_binding = {
                    'kind': 'actual_strict_unapproved_export_binding', 'export_stage_actual_pass': True, 'source_root': str(APP),
                    'export_manifest_file_sha256': exported['export_manifest_file_sha256'],
                    'source_manifest_sha256': exported['source_manifest_sha256'],
                    'original_app_lock_sha256': exported['source_files_exact']['pubspec.lock']['sha256'],
                    'production_release_approval': False, 'candidate_promoted': False,
                    'source_scope_held_for_strict_export': False, 'source_lock_attested': False,
                    'transient_write_and_restore_absence_attested': False,
                    'source_identity_index_membership_fixture_fences_passed': True,
                    'source_fence_before_sha256': sha(directory / 'source-fence-before-capture.json'),
                    'source_fence_after_sha256': sha(directory / 'source-fence-after-capture.json'),
                    'root_pinned_source_fence_sha256': sha(SOURCE_FENCE),
                    'private_snapshot_exclusive': True,
                    'authored_snapshot_immutability': 'exact hash/mode/source manifest binding; no OS immutable flag or production freeze attested'}
            if args.stage in ('app-lock', 'native'):
                guards.require_lock(APP / 'pubspec.lock', app_lock)
                save(directory / 'actual-app-source-readback.json', guards.app_readback('built' if args.stage == 'native' else 'app-locked', original_export['export_manifest_file_sha256']))
                save(directory / 'actual-app-packages.json', guards.package_config(APP / '.dart_tool/package_config.json', (SDK, APP, BASE / 'pub-cache')))
                save(directory / 'actual-plugin-bindings.json', guards.plugin_metadata(APP / '.flutter-plugins-dependencies'))
            source_readback(directory, 'sdk-locked' if args.stage == 'sdk-lock' else 'built' if args.stage == 'native' else 'app-locked' if args.stage == 'app-lock' else 'startup', env, 'after')
            if args.stage == 'native': save(directory / 'actual-production-JVM-and-classes.json', junit_and_classes())
        protected_after = protected_metadata()
        if pending_export_binding is not None: save(directory / 'export-source-binding.json', pending_export_binding)
        save(directory / 'terminal.json', {'stage_pass': True, 'stage': args.stage, 'protected_after': protected_after,
             'all_flavor_ABI_complete': False, 'candidate_promoted': False, 'ARC09_closed': False,
             'actual_export_binding_sha256': sha(directory / 'export-source-binding.json') if args.stage == 'app-export' else None, 'production_release_approval': False})
        return 0
    except BaseException as error:
        diagnostics = {}
        if SDK.is_dir():
            try:
                phase = 'built' if args.stage == 'native' else 'pristine' if args.stage == 'foundation' else 'sdk-locked'
                diagnostic_output = directory / 'actual-failure-SDK-source.json'
                command = [sys.executable, '-I', '-B', str(HERE / 'verify_native_consumer_source.py'), phase, '--output', str(diagnostic_output)]
                diagnostics['actual_failure_source_process'] = run_process(directory, 'failure-source-readback', command, 300, HERE, env)
            except BaseException as diagnostic_error:
                diagnostics['source_diagnostic_error_type'] = type(diagnostic_error).__name__
        try: diagnostics['protected_after_failure'] = protected_metadata()
        except BaseException as protected_error: diagnostics['protected_readback_error'] = str(protected_error)
        if not (directory / 'terminal.json').exists():
            save(directory / 'terminal.json', {'stage_pass': False, 'stage': args.stage, 'actual_error_type': type(error).__name__,
                 'public_error': str(error), 'partial_failure_preserved': True, 'retry_or_next_stage_admitted': False,
                 'actual_failure_diagnostics': diagnostics,
                 'candidate_promoted': False, 'production_release_approval': False})
        raise


if __name__ == '__main__':
    raise SystemExit(main())
