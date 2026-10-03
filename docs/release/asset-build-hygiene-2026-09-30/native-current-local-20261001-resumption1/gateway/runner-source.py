#!/usr/bin/env python3
"""One source-bound unsigned native sequence per platform, without private credentials."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import time

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
CACHE = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930')
SOURCE = CACHE / 'export-native-current-local-20261001-resumption1'
MANIFEST = ROOT / 'docs/release/rapid-completion-2026-10-01/native-source-resumption1.json'
BASE = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/native-current-local-20261001-resumption1'
SDK_IDS = {'production': 23, 'gateway': 136, 'ios': 28}
OLD_EXPORT = {'production': 'export-attempt125-android', 'gateway': 'export-attempt126-gateway', 'ios': 'export-attempt127-ios'}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path, value):
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')

def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=SDK_IDS)
    mode = parser.parse_args().platform
    packet = BASE / mode
    packet.mkdir(parents=True, exist_ok=False)
    export = CACHE / ('export-native-current-local-20261001-resumption1-' + mode)
    assert not export.exists(), 'Never overwrite an existing build attempt'
    sdk = ROOT / ('.cache/flutter-sdk-isolated-asset-attempt' + str(SDK_IDS[mode]))
    env = {k: v for k, v in os.environ.items() if k in {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
    env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', PUB_CACHE=str(ROOT / '.cache/pub-cache-hygiene-20260930'),
               JAVA_HOME='/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home',
               DEVELOPER_DIR='/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer', COCOAPODS_DISABLE_STATS='true')
    env['PATH'] = str(sdk / 'bin') + ':/Users/jeanbosco/.local/bin:' + env['PATH']
    env['CP_HOME_DIR'] = str(CACHE / 'cocoapods-attempt127-home')
    env['CP_CACHE_DIR'] = str(CACHE / 'cocoapods-attempt127-cache')
    commands = []
    stage = 'source-copy'
    write(packet / 'execution.json', {'status': 'running', 'pid': os.getpid(), 'stage': stage, 'commands': commands})
    shutil.copy2(__file__, packet / 'runner-source.py')
    manifest = json.loads(MANIFEST.read_text())
    source = manifest['source_sha256']
    assert len(source) == manifest['source_file_count'] == 1103
    for name, digest in source.items():
        origin = SOURCE / name
        assert origin.is_file() and not origin.is_symlink() and sha(origin) == digest, name
        target = export / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, target)
        assert sha(target) == digest, name
    write(packet / 'source-export.json', {**manifest, 'destination': str(export), 'immutable_parent': str(SOURCE),
          'parent_manifest_sha256': sha(MANIFEST), 'parent_manifest': str(MANIFEST), 'working_copy_source_sha256': source})
    extras = {}
    def extra(name, proof=None):
        origin = ROOT / name
        if proof:
            p = ROOT / 'docs/release/asset-build-hygiene-2026-09-30' / proof / 'validation.json'
            accepted = json.loads(p.read_text())
            assert accepted['status'] == 'pass' and accepted['source_sha256'][name] == sha(origin), name
        target = export / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, target)
        extras[name] = sha(target)
        return target
    package_tool = extra('scripts/qa/resolved_native_package_inputs.py', 'resolved-native-inputs-attempt97')
    if mode == 'gateway':
        extra('scripts/tests/android_gateway_attempt_archive_jvm.py')
        extra('docs/release/collect-codex-goal-2026-09-30/android-gateway/run_native_checks.py')
    if mode == 'ios':
        generated_tool = extra('scripts/qa/swift_generated_plugin_inputs.py', 'swift-generated-inputs-attempt129')
        binary_tool = extra('scripts/qa/swift_cached_artifact_inputs.py', 'swift-cached-artifact-inputs-root177-workspace-order')
    write(packet / 'additional-tooling-inputs.json', {'source_sha256': extras, 'scope': 'Additional captured native verification helpers, separate from the immutable root1103 build candidate.'})
    write(packet / 'environment-scope.json', {'environment_names': sorted(env), 'private_provider_signing_environment_supplied': False,
          'sdk': str(sdk), 'pub_cache': env['PUB_CACHE'], 'java_home': env['JAVA_HOME'], 'developer_dir': env['DEVELOPER_DIR']})
    def run(name, argv, cwd=export, expected=0):
        nonlocal stage
        stage = name
        print('START', mode, name, flush=True)
        write(packet / 'execution.json', {'status': 'running', 'pid': os.getpid(), 'stage': name, 'commands': commands})
        started = time.monotonic()
        with (packet / (name + '.stdout')).open('wb') as out, (packet / (name + '.stderr')).open('wb') as err:
            result = subprocess.run(argv, cwd=cwd, env=env, stdout=out, stderr=err)
        commands.append({'name': name, 'command': argv, 'exit_code': result.returncode, 'elapsed_seconds': round(time.monotonic() - started, 2),
                         'stdout_sha256': sha(packet / (name + '.stdout')), 'stderr_sha256': sha(packet / (name + '.stderr'))})
        print('END', mode, name, result.returncode, flush=True)
        write(packet / 'execution.json', {'status': 'running' if result.returncode == expected else 'fail', 'pid': os.getpid(), 'stage': name, 'commands': commands})
        if result.returncode != expected:
            raise RuntimeError('Command failed: ' + name)
    try:
        run('git-init', ['git', 'init', '-q'])
        run('flutter-version', [str(sdk / 'bin/flutter'), '--version', '--machine'])
        version = json.loads((packet / 'flutter-version.stdout').read_text())
        assert version['frameworkRevision'] == 'ad70ec4617166f1c38e5d2bfd388af71fda14f06' and version['dartSdkVersion'] == '3.12.2'
        run('pub-enforce', [str(sdk / 'bin/flutter'), 'pub', 'get', '--offline', '--enforce-lockfile'])
        assert sha(export / 'pubspec.lock') == source['pubspec.lock']
        package = load_module(package_tool, 'resolved_package_' + mode)
        binding = package.bind(export, sdk, ROOT / '.cache/pub-cache-hygiene-20260930')
        write(packet / 'resolved-package-inputs-before.json', binding)
        if mode != 'ios':
            old = CACHE / OLD_EXPORT[mode]
            for rel in ['android/.gradle', 'build']:
                if (old / rel).exists():
                    dest = export / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    run('clone-cache-' + rel.replace('/', '-'), ['cp', '-cR', str(old / rel), str(dest)])
            for rel in ['build/app/outputs', 'build/app/reports', 'build/app/test-results']:
                if (export / rel).is_dir():
                    shutil.rmtree(export / rel)
            (export / 'android/local.properties').write_text('sdk.dir=/Users/jeanbosco/Library/Android/sdk\nflutter.sdk=' + str(sdk) + '\nflutter.buildMode=release\nflutter.versionName=1.2.4\nflutter.versionCode=23\n')
            write(packet / 'generated-inputs.json', {'sha256': {name: sha(export / name) for name in ['android/local.properties', '.dart_tool/package_config.json', '.flutter-plugins-dependencies']}})
            flavor = 'Production' if mode == 'production' else 'Internal_gateway'
            dart_target = 'lib/main.dart' if mode == 'production' else 'lib/main_gateway.dart'
            argv = ['./gradlew', '-I', str(export / 'scripts/supply_chain/gradle_runtime_inventory.init.gradle')]
            if mode == 'gateway':
                original = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/gateway-notification-exclusion-attempt175/json-runtime-proof.init.gradle'
                proof = packet / 'real-json-runtime.init.gradle'
                proof.write_text(original.read_text().replace(str(original.parent), str(packet)))
                argv += ['-I', str(proof)]
            argv += [':app:assemble' + flavor + 'Release', ':app:lint' + flavor + 'Release',
                     ':app:testDevDebugUnitTest' if mode == 'production' else ':app:testInternal_gatewayDebugUnitTest', ':app:collectRuntimeGraph',
                     '-Ptarget=' + dart_target, '-PcollectUnsignedLocalQa=true',
                     '-PcollectInventoryConfiguration=' + ('production' if mode == 'production' else 'internal_gateway') + 'ReleaseRuntimeClasspath',
                     '-x', ':app:compileFlutterBuild' + ('Dev' if mode == 'production' else 'Internal_gateway') + 'Debug',
                     '--offline', '--no-daemon', '--max-workers=2', '--console=plain']
            run('unsigned-native-build-lint-jvm-graph', argv, export / 'android')
            if mode == 'gateway':
                run('gateway-native-archive-dispatch-harness', ['python3', str(export / 'scripts/tests/android_gateway_attempt_archive_jvm.py'), '--packet', str(packet / 'gateway-standalone')])
        else:
            run('xcode-version', ['xcrun', 'xcodebuild', '-version'])
            old = CACHE / OLD_EXPORT[mode]
            if (old / 'ios/Pods').is_dir():
                run('clone-cached-pods', ['cp', '-cR', str(old / 'ios/Pods'), str(export / 'ios/Pods')])
            run('unsigned-ios-config', [str(sdk / 'bin/flutter'), 'build', 'ios', '--release', '--flavor', 'production', '--no-codesign', '--no-pub', '--config-only'])
            generated = load_module(generated_tool, 'generated_swift_inputs')
            generated_binding = generated.bind(export, binding, source)
            write(packet / 'generated-compiler-inputs-before.json', generated_binding)
            cache = export / 'build/ios/SourcePackages'
            cache.mkdir(parents=True, exist_ok=True)
            prior = old / 'build/ios/SourcePackages'
            for component in ['artifacts', 'checkouts', 'repositories', 'workspace-state.json']:
                assert not (cache / component).exists(), component
                run('clone-swift-' + component.replace('.', '-'), ['cp', '-cR', str(prior / component), str(cache / component)])
            # APFS copies can normalize symlink modes; restore only exact copied targets.
            fixed_modes = []
            for path in (prior / 'artifacts').rglob('*'):
                if path.is_symlink():
                    target = cache / 'artifacts' / path.relative_to(prior / 'artifacts')
                    assert target.is_symlink() and os.readlink(target) == os.readlink(path)
                    expected_mode = stat.S_IMODE(path.lstat().st_mode)
                    if stat.S_IMODE(target.lstat().st_mode) != expected_mode:
                        os.lchmod(target, expected_mode)
                        fixed_modes.append(str(target.relative_to(cache)))
            write(packet / 'copied-symlink-mode-reconciliation.json', {'paths': fixed_modes, 'scope': 'Exact copied targets only; historical cache untouched.'})
            pins = json.loads((export / 'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())['pins']
            observed = {}
            for pin in pins:
                revision = subprocess.check_output(['git', '-C', str(cache / 'checkouts' / pin['identity']), 'rev-parse', 'HEAD'], env=env, text=True).strip()
                assert revision == pin['state']['revision'], pin['identity']
                observed[pin['identity']] = revision
            write(packet / 'swift-checkouts.json', observed)
            binary = load_module(binary_tool, 'cached_swift_inputs')
            binary_binding = binary.bind(export, prior, generated_binding)
            write(packet / 'cached-binary-inputs-before.json', binary_binding)
            run('unsigned-ios-build', ['xcrun', 'xcodebuild', '-workspace', 'ios/Runner.xcworkspace', '-scheme', 'production', '-configuration', 'Release-production',
                 '-sdk', 'iphoneos', '-destination', 'generic/platform=iOS', '-derivedDataPath', str(export / 'build/ios/DerivedData'),
                 '-clonedSourcePackagesDirPath', str(cache), '-onlyUsePackageVersionsFromResolvedFile', '-disableAutomaticPackageResolution', '-skipPackageUpdates',
                 '-jobs', '2', 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGNING_IDENTITY=', 'DEVELOPMENT_TEAM=', 'build'])
            for name, result in [('generated-compiler-inputs-after', generated.verify(generated_binding, export)), ('cached-binary-inputs-after', binary.verify(binary_binding))]:
                write(packet / (name + '.json'), result)
                assert result['status'] == 'pass', name
        package_check = package.verify(binding, export)
        write(packet / 'resolved-package-inputs-after.json', package_check)
        assert package_check['status'] == 'pass'
        drift = {name: {'before': digest, 'after': sha(export / name) if (export / name).is_file() else None}
                 for name, digest in {**source, **extras}.items() if not (export / name).is_file() or sha(export / name) != digest}
        parent_drift = [name for name, digest in source.items() if not (SOURCE / name).is_file() or sha(SOURCE / name) != digest]
        write(packet / 'source-after.json', {'working_copy_drift': drift, 'immutable_parent_drift': parent_drift, 'checked_input_count': len(source) + len(extras)})
        assert not drift and not parent_drift
        write(packet / 'execution.json', {'status': 'pass', 'pid': os.getpid(), 'stage': 'native-sequence-terminal', 'commands': commands,
              'source_manifest_sha256': sha(MANIFEST), 'scope': 'Actual captured candidate build/lint/JVM as listed; artifact inspection and warning decisions recorded separately. No signing, provider, physical device, store or whole-live-repository acceptance.'})
        print('TERMINAL PASS', mode, flush=True)
    except BaseException as error:
        write(packet / 'execution.json', {'status': 'fail', 'pid': os.getpid(), 'stage': stage, 'error': str(error), 'commands': commands,
              'source_manifest_sha256': sha(MANIFEST)})
        print('TERMINAL FAIL', mode, stage, repr(error), flush=True)
        raise

if __name__ == '__main__':
    main()
