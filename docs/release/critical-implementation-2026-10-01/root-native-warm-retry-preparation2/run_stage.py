"""One separately reviewed stage using the preserved, authenticated private SDK."""
import argparse
import datetime
import hashlib
import json
import os
import sys
from pathlib import Path
import types

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
ROOT = RELEASE.parents[2]
PREP = RELEASE / 'kotlin-sdk-native-native-stage-preparation1'
REVIEW = RELEASE / 'root-native-warm-retry-review2'
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
APP = BASE / 'app-source'
SDK = BASE / 'flutter'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def load(path, expected, name):
    raw = path.read_bytes()
    if path.resolve() != path or digest(raw) != expected:
        raise ValueError('reviewed module identity differs')
    value = types.ModuleType(name)
    value.__file__ = str(path)
    exec(compile(raw, str(path), 'exec'), value.__dict__)
    return value


reader = load(PREP / 'publisher_metadata.py', 'c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25', 'warm_reader')
guards = load(PREP / 'consumer_guards.py', 'f38cbad5ab95c7aa9adfa0b9ddae5cf5902666c89aa6548525edb75be3465e4a', 'warm_guards')
controller = load(PREP / 'run_native_consumer.py', '167d48b4e756043a87621feffcabccb41aca108232cfb943914b69fc5b090fe7', 'warm_bounded_controller')
fence = load(PREP / 'source_fence.py', '5c70fe6e6f946846325df052a0ff42a2fadae53c22ed719faf6b1e7fd7f7b7ea', 'warm_source_fence')

# Reuse the verified module objects for in-process validation.
controller.reader = lambda: reader
controller.require_pass = guards.process_success
guards.load_metadata = lambda: reader
fence.metadata = lambda: reader


def read(path):
    return reader.stable_read(path, True)


def pinned_json(path, expected):
    row, raw = read(path)
    if row['sha256'] != expected:
        raise ValueError('root-pinned input differs')
    return json.loads(raw)


def packet(directory, expected):
    document = pinned_json(directory / 'packet-files.json', expected)
    for leaf in document['files']:
        relative = Path(leaf['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('unsafe frozen packet path')
        row, _ = read(directory / relative)
        if (row['sha256'], row['bytes']) != (leaf['sha256'], leaf['bytes']):
            raise ValueError('frozen packet leaf changed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', required=True, choices=('app-export', 'app-lock', 'native'))
    parser.add_argument('--review-sha256', required=True)
    args = parser.parse_args()
    controller.packet(PREP, 'a9345a6c699794117e6e3a9bb6e06d4c3e34f1db7fb680a79c7b09f45bcf3452')
    controller.packet(RELEASE / 'kotlin-sdk-native-consumer-preparation1', '9f08883dc0db884cee715d30e1c0efda31f5285d614aae0acc69da7418dc73bc')
    review = pinned_json(REVIEW / (args.stage + '-review.json'), args.review_sha256)
    if (set(review) != {'stage', 'script_sha256', 'source_fence_sha256', 'predecessor_terminal_sha256', 'export_binding_sha256', 'production_release_approval'}
            or review['stage'] != args.stage or review['production_release_approval'] is not False
            or read(Path(__file__).resolve())[0]['sha256'] != review['script_sha256']):
        raise ValueError('separate root stage review differs')
    packet(RELEASE / 'root-native-failure-readback1', 'a1f281aeb715153cc3d043212b1fb5046b351409e970028dd22cbdb2c00ec814')
    old = pinned_json(RELEASE / 'root-native-failure-readback1/readback.json', '4a87ce1fde1444209234b674a718826bdad78b4c339c3448c3e4e8624b40f064')
    if not old['actual_sdk_source_diagnostic_pass'] or old['stages']['native']['stage_pass'] is not False:
        raise ValueError('preserved failed attempt/SDK diagnostic differs')
    config = pinned_json(PREP / 'proposed-commands.json', '696a87e401485c5a86205e752aec934a29ede3ae0c3b86beee7ff7cd97501353')
    if reader.stable_read(Path(config['Python_executable']))[0]['sha256'] != config['Python_SHA256']:
        raise ValueError('Python executable differs')
    if Path(sys.executable).resolve() != Path(config['Python_executable']).resolve():
        raise ValueError('actual Python runtime differs')
    predecessor = {'app-export': 'startup', 'app-lock': 'app-export', 'native': 'app-lock'}[args.stage]
    prior = pinned_json(BASE / '.control' / predecessor / 'terminal.json', review['predecessor_terminal_sha256'])
    if prior['stage'] != predecessor or prior['stage_pass'] is not True:
        raise ValueError('whole predecessor did not pass')
    if args.stage != 'app-export' and prior.get('warm_retry_script_sha256') != review['script_sha256']:
        raise ValueError('prior stage belongs to a different retry')
    binding = None
    if args.stage != 'app-export':
        binding = pinned_json(BASE / '.control/app-export/export-source-binding.json', review['export_binding_sha256'])
        if binding['source_fence_sha256'] != review['source_fence_sha256'] or binding['production_release_approval'] is not False:
            raise ValueError('fresh strict export binding differs')
        guards.app_readback('built' if args.stage == 'native' else 'app-export', binding['export_manifest_file_sha256'])
    directory = BASE / '.control' / args.stage
    directory.mkdir(mode=0o700)
    env = config['environment_exact']
    try:
        controller.save(directory / 'start.json', {'stage': args.stage, 'review_sha256': args.review_sha256,
            'warm_retry_script_sha256': review['script_sha256'], 'protected_before': controller.protected_metadata(),
            'source_lock_attested': False, 'production_release_approval': False})
        controller.source_readback(directory, 'built', env, 'before')
        if args.stage == 'app-export':
            fence.private_destination(APP, BASE)
            if reader.stable_read(Path(config['Node_executable']))[0]['sha256'] != config['Node_SHA256']:
                raise ValueError('Node executable differs')
            fence_command = [config['Python_executable'], '-I', '-B', str(PREP / 'source_fence.py'), 'verify',
                '--root', str(ROOT), '--binding', str(REVIEW / 'source-fence.json'), '--binding-sha256', review['source_fence_sha256'],
                '--output', str(directory / 'source-fence-before.json')]
            controller.require_pass(controller.run_process(directory, 'source-fence-before', fence_command, 300, PREP, env))
        if args.stage == 'app-lock':
            with (APP / 'android/local.properties').open('x') as output:
                os.fchmod(output.fileno(), 0o600)
                output.write('sdk.dir=' + env['ANDROID_SDK_ROOT'] + '\nflutter.sdk=' + str(SDK) + '\n')
                output.flush(); os.fsync(output.fileno())
        if args.stage == 'native':
            if reader.stable_read(Path(config['JDK_java_executable']))[0]['sha256'] != config['JDK_java_SHA256']:
                raise ValueError('Java executable differs')
            for relative in ('platforms/android-36/android.jar', 'ndk/28.2.13676358/source.properties', 'build-tools/36.0.0/source.properties'):
                if not (Path(env['ANDROID_SDK_ROOT']) / relative).is_file():
                    raise ValueError('installed Android prerequisite absent; download disabled')
            source = Path(config['raw_published_Gradle_ZIP_source'])
            destination = BASE / 'gradle-home' / config['raw_Gradle_ZIP_owned_relative_destination']
            observed = [reader.stable_read(path)[0] for path in (source, destination)]
            if any((row['sha256'], row['bytes']) != (config['raw_Gradle_ZIP_SHA256'], config['raw_Gradle_ZIP_bytes']) for row in observed) or (observed[0]['device'], observed[0]['inode']) == (observed[1]['device'], observed[1]['inode']):
                raise ValueError('owned published Gradle ZIP provenance differs')
            controller.save(directory / 'raw-Gradle-owned-reuse.json', {'source': observed[0], 'destination': observed[1],
                'extracted_global_caches_copied': False, 'standard_wrapper_authentication_required': True})
        command = config['commands'][args.stage]
        process = controller.run_process(directory, 'actual-command', command['argv'], command['deadline_seconds'], command['cwd'], env)
        controller.require_pass(process)
        guards.forbid_upgrade_branch((directory / 'actual-command.stdout').read_text(), (directory / 'actual-command.stderr').read_text())
        guards.require_lock(SDK / 'packages/flutter_tools/pubspec.lock', guards.SDK_LOCK)
        if args.stage == 'app-export':
            fence_command[-1] = str(directory / 'source-fence-after.json')
            controller.require_pass(controller.run_process(directory, 'source-fence-after', fence_command, 300, PREP, env))
            fence.private_candidate(APP, BASE)
            exported = guards.app_readback('app-export')
            controller.save(directory / 'actual-app-source.json', exported)
            binding = {'source_fence_sha256': review['source_fence_sha256'],
                'export_manifest_file_sha256': exported['export_manifest_file_sha256'],
                'source_manifest_sha256': exported['source_manifest_sha256'],
                'original_app_lock_sha256': exported['source_files_exact']['pubspec.lock']['sha256'],
                'production_release_approval': False, 'source_lock_attested': False}
        else:
            guards.require_lock(APP / 'pubspec.lock', binding['original_app_lock_sha256'])
            controller.save(directory / 'actual-app-source.json', guards.app_readback('built' if args.stage == 'native' else 'app-locked', binding['export_manifest_file_sha256']))
            controller.save(directory / 'actual-app-packages.json', guards.package_config(APP / '.dart_tool/package_config.json', (SDK, APP, BASE / 'pub-cache')))
            controller.save(directory / 'actual-plugin-bindings.json', guards.plugin_metadata(APP / '.flutter-plugins-dependencies'))
        controller.source_readback(directory, 'built', env, 'after')
        if args.stage == 'native':
            controller.save(directory / 'actual-production-JVM-and-classes.json', controller.junit_and_classes())
        protected = controller.protected_metadata()
        if args.stage == 'app-export':
            controller.save(directory / 'export-source-binding.json', binding)
        controller.save(directory / 'terminal.json', {'stage': args.stage, 'stage_pass': True,
            'warm_retry_script_sha256': review['script_sha256'], 'protected_after': protected,
            'native_packages_built': False, 'ARC09_closed': False, 'production_release_approval': False})
    except BaseException as error:
        diagnostics = {}
        try:
            output = directory / 'actual-failure-SDK-source.json'
            argv = [config['Python_executable'], '-I', '-B', str(RELEASE / 'kotlin-sdk-native-consumer-preparation1/verify_native_consumer_source.py'),
                'built', '--output', str(output)]
            diagnostics['actual_failure_source_process'] = controller.run_process(directory, 'failure-source-readback', argv, 300,
                RELEASE / 'kotlin-sdk-native-consumer-preparation1', env)
        except BaseException as diagnostic_error:
            diagnostics['source_diagnostic_error'] = str(diagnostic_error)
        try:
            diagnostics['protected_after_failure'] = controller.protected_metadata()
        except BaseException as protected_error:
            diagnostics['protected_metadata_error'] = str(protected_error)
        controller.save(directory / 'terminal.json', {'stage': args.stage, 'stage_pass': False,
            'actual_error_type': type(error).__name__, 'public_error': str(error), 'partial_failure_preserved': True,
            'actual_failure_diagnostics': diagnostics, 'retry_or_next_stage_admitted': False, 'production_release_approval': False})
        raise


if __name__ == '__main__':
    main()
