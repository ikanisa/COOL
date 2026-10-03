#!/usr/bin/env python3
"""Private reviewed proposal. Execution populates only the pinned private Gradle cache."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import types

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
DRIVER = RELEASE / 'arc09-aab-driver-preparation1/argv-unavailable-recovery3/run_selected_aab.py'
DRIVER_SHA = '76f587c54d8cfcb91d0ce584f4ee69ac99905b1ad313402ac2c82ce2fa6ed4f8'
PREP = RELEASE / 'kotlin-sdk-native-native-stage-preparation1'
APP = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/app-source')
HOME = APP.parent / 'gradle-home'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-fences-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--metadata-only', action='store_true')
    args = parser.parse_args()
    raw = DRIVER.read_bytes()
    if digest(raw) != DRIVER_SHA:
        raise ValueError('Reviewed lifecycle driver changed')
    driver = types.ModuleType('lint_exact_reviewed_driver'); driver.__file__ = str(DRIVER)
    exec(compile(raw, str(DRIVER), 'exec'), driver.__dict__)
    fences = driver.document(HERE / 'source-fences.json', args.source_fences_sha256)
    rows = {row['path']: row for row in fences['inputs']}
    for name, row in rows.items():
        body = driver.plain_read(name, row['sha256'], 128 * 1024**2)
        if len(body) != row['bytes']:
            raise ValueError('Exact scoped input byte count changed')
    config = driver.document(PREP / 'proposed-commands.json', rows[str(PREP / 'proposed-commands.json')]['sha256'])
    if Path(sys.executable).resolve() != Path(config['Python_executable']).resolve():
        raise ValueError('Pinned Python runtime differs')
    def loaded(relative, name):
        path = PREP / relative
        return driver.module(path, rows[str(path)]['sha256'], name)
    reader = loaded('publisher_metadata.py', 'lint_exact_reader')
    guards = loaded('consumer_guards.py', 'lint_exact_guards')
    controller = loaded('run_native_consumer.py', 'lint_exact_controller')
    for label in ('Python', 'JDK_java', 'Node'):
        if reader.stable_read(Path(config[label + '_executable']))[0]['sha256'] != config[label + '_SHA256']:
            raise ValueError('Pinned runtime bytes changed: ' + label)
    controller.reader = lambda: reader
    guards.load_metadata = lambda: reader
    source_project = HERE / 'minimal-project'
    if (HOME / 'gradle.properties').exists() != fences['private_gradle_properties_present']:
        raise ValueError('Private-home Gradle properties presence changed')
    # An init script could add repositories or tasks outside this isolated project.
    for leaf in ('init.gradle', 'init.gradle.kts'):
        if (HOME / leaf).exists(): raise ValueError('Unreviewed private-home init script: ' + leaf)
    if (HOME / 'init.d').exists() and any((HOME / 'init.d').iterdir()):
        raise ValueError('Unreviewed private-home init.d content')
    driver.physical(source_project)
    output = args.output
    if not output.is_absolute() or output.resolve() != output:
        raise ValueError('Output must be a physical absolute path')
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    project = output / 'minimal-project'
    project.mkdir(mode=0o700)
    project_sources = {}
    for leaf in ('settings.gradle', 'build.gradle'):
        body = driver.plain_read(source_project / leaf, rows[str(source_project / leaf)]['sha256'])
        with (project / leaf).open('xb') as copied:
            os.fchmod(copied.fileno(), 0o600)
            copied.write(body); copied.flush(); os.fsync(copied.fileno())
        project_sources[leaf] = digest(body)
    label = 'exact-lint32-tooling-metadata' if args.metadata_only else 'exact-lint32-tooling-resolution'
    argv = ['/bin/bash', str(APP / 'android/gradlew'), '-p', str(project),
        '--no-daemon', '--no-build-cache', '--no-configuration-cache', '--console=plain',
        '--max-workers=1', '-Dorg.gradle.internal.http.connectionTimeout=30000',
        '-Dorg.gradle.internal.http.socketTimeout=30000',
        '-PcollectLintGraphOutput=' + str(output / 'selected-tooling-graph.json'),
        '-PcollectLintMetadataOnly=' + ('true' if args.metadata_only else 'false'), 'resolveExactLintTooling']
    wrapper_rows = {relative: rows[str(APP / relative)] for relative in
                    ('android/gradlew', 'android/gradle/wrapper/gradle-wrapper.jar')}
    ctx = types.SimpleNamespace(config=config, controller=controller, guards=guards,
        records={'APP_source': {'source_files_exact': wrapper_rows}},
        matrix={'commands': [{'label': label, 'argv': argv}]})
    # Deliberately do not call driver.context(): it binds the historical native epoch
    # and old maintained Android inputs. This scope binds current relevant inputs only.
    tracker = driver.DaemonTracker(ctx, output, label)
    for row in driver.process_table().values():
        if tracker.private_identity(row) is not None:
            raise ValueError('Existing private Gradle daemon; no stop attempted')
    original = controller.subprocess
    def popen(*call_args, **call_kwargs):
        child = subprocess.Popen(*call_args, **call_kwargs)
        try: tracker.register(child)
        except BaseException:
            controller.stop_group(child)
            raise
        return child
    controller.subprocess = types.SimpleNamespace(Popen=popen, TimeoutExpired=subprocess.TimeoutExpired)
    command = daemon = None
    errors = []
    try:
        command = controller.run_process(output, label, argv, 180, project, config['environment_exact'])
    except BaseException as error:
        errors.append({'type': type(error).__name__, 'error': str(error)})
    finally:
        controller.subprocess = original
        daemon = tracker.finish()
    for name, row in rows.items():
        try:
            body = driver.plain_read(name, row['sha256'], 128 * 1024**2)
            if len(body) != row['bytes']: raise ValueError('Scoped source byte count drift')
        except BaseException as error:
            errors.append({'path': name, 'type': type(error).__name__, 'error': str(error)})
    for leaf, expected in project_sources.items():
        try: driver.plain_read(project / leaf, expected)
        except BaseException as error:
            errors.append({'path': str(project / leaf), 'error': str(error)})
    if (HOME / 'gradle.properties').exists() != fences['private_gradle_properties_present']:
        errors.append({'error': 'Private-home Gradle properties presence changed during resolution'})
    try: guards.process_success(command or {})
    except BaseException as error: errors.append({'type': type(error).__name__, 'error': str(error)})
    if daemon['observer_error'] is not None or not daemon['owned_daemons_absent']:
        errors.append({'error': 'Daemon qualification incomplete; actual tracker result retained'})
    graph_path = output / 'selected-tooling-graph.json'
    graph_row = None
    if graph_path.exists():
        graph_raw = driver.plain_read(graph_path)
        graph = json.loads(graph_raw)
        graph_row = {'path': str(graph_path), 'sha256': digest(graph_raw), 'bytes': len(graph_raw),
                     'counts': graph.get('counts')}
        required_complete = 'complete_selected_tooling_metadata' if args.metadata_only else 'complete_selected_tooling_graph'
        if graph.get(required_complete) is not True or graph.get('metadata_only_requested') is not args.metadata_only or graph.get('errors'):
            errors.append({'error': 'Selected graph incomplete', 'actual_graph_errors': graph.get('errors')})
    else: errors.append({'error': 'No selected graph produced'})
    checkpoints = []
    checkpoint_paths = sorted(output.glob('selected-tooling-graph.json.checkpoint-*.json'))
    if len(checkpoint_paths) > 8:
        errors.append({'error': 'Checkpoint count exceeds reviewed bound'})
    else:
        for path in checkpoint_paths:
            checkpoint_raw = driver.plain_read(path)
            checkpoint = json.loads(checkpoint_raw)
            checkpoints.append({'path': str(path), 'sha256': digest(checkpoint_raw), 'bytes': len(checkpoint_raw),
                'phase': checkpoint.get('phase'), 'counts': checkpoint.get('counts'),
                'complete_selected_tooling_metadata': checkpoint.get('complete_selected_tooling_metadata'),
                'complete_selected_tooling_graph': checkpoint.get('complete_selected_tooling_graph')})
    driver.save(output / 'readback.json', {'schema_version': 1,
        'status': 'PASS' if not errors else 'FAIL_OR_INCOMPLETE',
        'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'root_requested': 'com.android.tools.lint:lint-gradle:32.0.1', 'argv': argv,
        'source_fences_sha256': args.source_fences_sha256, 'command': command,
        'daemon_readback': daemon, 'selected_graph': graph_row, 'checkpoints': checkpoints, 'errors': errors,
        'metadata_only_requested': args.metadata_only,
        'metadata_only_success_is_not_full_graph_or_publisher_admission': True,
        'cache_population_is_not_publisher_admission': True, 'publisher_admission_complete': False,
        'Gradle_transport_retry_policy_not_asserted': True,
        'historical_native_pass_not_relabelled_current': True,
        'full_APP_SDK_source_guard_is_root_owned_separate_scope': True,
        'AAB_built': False, 'lint_run': False, 'lint_suppressed': False,
        'production_release_approval': False})
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
