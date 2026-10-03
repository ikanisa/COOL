#!/usr/bin/env python3
"""Offline successor gateway checks with exact retained SQL observations.

Cached tools only. Synthetic AES/filesystem/HTTP fixtures; no Android device,
Keystore, SMS, provider, authenticated hosted endpoint or deployment acceptance.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HELPER = Path('scripts/tests/android_gateway_native_tools.py')
DEFAULT_FIXTURES = Path('scripts/tests/fixtures/android_gateway_successor_v1')
SUITE = 'GatewaySuccessorTest'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, help='Exact six SQL-produced observations and producer association; defaults to canonical fixture directory')
    parser.add_argument('--reuse-compiled', type=Path, help='Retained packet with source/tool/artifact bindings; all selected source, shim and runtime bytes must match before reuse')
    args = parser.parse_args()
    packet = args.packet.resolve()
    packet.mkdir(parents=True, exist_ok=False)
    commands = []
    report = {'status': 'fail', 'suite_names': [SUITE], 'commands': commands,
              'scope': __doc__, 'compile_reuse': None}
    try:
        helper_target = packet / 'source' / HELPER
        helper_target.parent.mkdir(parents=True, exist_ok=True)
        helper_sha = digest(ROOT / HELPER)
        shutil.copyfile(ROOT / HELPER, helper_target)
        if digest(helper_target) != helper_sha:
            raise RuntimeError('Native helper changed during capture')
        spec = importlib.util.spec_from_file_location('gateway_native_helper', helper_target)
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        products = helper.product_sources(ROOT)
        tests = helper.test_sources(ROOT, [SUITE])
        api_sources = helper.api_sources(ROOT)
        fixtures = (args.fixtures.resolve() if args.fixtures else ROOT / DEFAULT_FIXTURES)
        fixture_paths = helper.fixture_sources(fixtures)
        paths = list(dict.fromkeys(products + tests + api_sources + [HELPER,
                Path('android/app/src/internal_gateway/AndroidManifest.xml'),
                Path('android/app/src/main/AndroidManifest.xml'),
                Path('android/app/build.gradle.kts'), Path(__file__).resolve().relative_to(ROOT)]))
        hashes = {str(path): digest(ROOT / path) for path in paths}
        if hashes[str(HELPER)] != helper_sha:
            raise RuntimeError('Native helper changed after import')
        for path in paths:
            target = packet / 'source' / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / path, target)
            if digest(target) != hashes[str(path)]:
                raise RuntimeError('Captured source changed before execution: ' + str(path))
        fixture_hashes = {path.name: digest(path) for path in fixture_paths}
        for path in fixture_paths:
            target = packet / 'source' / DEFAULT_FIXTURES / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            if digest(target) != fixture_hashes[path.name]:
                raise RuntimeError('Fixture changed during capture')
        captured_fixtures = packet / 'source' / DEFAULT_FIXTURES
        helper.fixture_sources(captured_fixtures)
        dependencies = [helper.jar(*parts) for parts in helper.DEPENDENCIES]
        engine = helper.FLUTTER_ENGINE.read_text().strip()
        embedding = helper.jar('io.flutter', 'flutter_embedding_debug', '1.0.0-' + engine)
        lifecycle = helper.jar('androidx.lifecycle', 'lifecycle-common-jvm', '2.9.4')
        binary_inputs = sorted({path for path in helper.JBR.rglob('*') if path.is_file()} |
                               set(dependencies + [helper.ANDROID_API, helper.JBR / 'bin/java',
                                                   embedding, lifecycle, helper.FLUTTER_ENGINE]))
        binary_hashes = {str(path): digest(path) for path in binary_inputs}
        source_cp = os.pathsep.join(str(dependencies[index]) for index in (1, 4, 6, 7, 8))
        shim_hashes = {}
        for name, body in helper.SHIMS.items():
            target = packet / 'shims' / name
            target.parent.mkdir(exist_ok=True)
            target.write_text(body)
            shim_hashes[name] = digest(target)
        report.update({'source_sha256': hashes, 'fixture_sha256': fixture_hashes,
                       'binary_sha256': binary_hashes, 'shim_sha256': shim_hashes})

        def run(name, argv):
            try:
                result = subprocess.run(argv, capture_output=True, timeout=480)
            except subprocess.TimeoutExpired as error:
                result = subprocess.CompletedProcess(argv, 124, error.stdout or b'',
                            (error.stderr or b'') + b'\nBounded offline command timeout.\n')
            (packet / (name + '.stdout')).write_bytes(result.stdout)
            (packet / (name + '.stderr')).write_bytes(result.stderr)
            commands.append({'name': name, 'argv': argv, 'exit_code': result.returncode,
                             'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(),
                             'stderr_sha256': hashlib.sha256(result.stderr).hexdigest()})
            print(name + ' terminal ' + str(result.returncode), flush=True)
            return result.returncode

        with tempfile.TemporaryDirectory(prefix='collect-successor-jvm-') as temporary:
            temporary = Path(temporary)
            if args.reuse_compiled:
                retained = args.reuse_compiled.resolve()
                binding_path = retained / 'compiled-evidence-binding.json'
                validation_path = retained / 'validation.json'
                binding = json.loads(binding_path.read_text())
                previous = json.loads(validation_path.read_text())
                # A retained unrelated suite timeout is not a compiler failure.
                compile_names = {'compile-shim-product', 'compile-tests-0', 'compile-tests-1', 'compile-real-android-api'}
                compiled = {entry['name']: entry['exit_code'] for entry in previous['commands'] if entry['name'] in compile_names}
                if set(compiled) != compile_names or any(compiled.values()):
                    raise RuntimeError('Retained product/test/API compilation did not complete')
                selected = products + tests + api_sources + [Path('android/app/src/internal_gateway/AndroidManifest.xml'),
                           Path('android/app/src/main/AndroidManifest.xml'), Path('android/app/build.gradle.kts')]
                for path in selected:
                    if binding['source_sha256'].get(str(path)) != hashes[str(path)] or previous['source_sha256'].get(str(path)) != hashes[str(path)]:
                        raise RuntimeError('Retained source differs: ' + str(path))
                if previous['binary_sha256'] != binary_hashes or binding['binary_sha256'] != binary_hashes:
                    raise RuntimeError('Retained runtime binary closure differs')
                if previous['shim_sha256'] != shim_hashes:
                    raise RuntimeError('Retained filesystem/crypto shim closure differs')
                members = binding['members_sha256']
                observed = {str(path.relative_to(retained / 'compiled-evidence')) for path in (retained / 'compiled-evidence').rglob('*') if path.is_file()}
                if observed != set(members):
                    raise RuntimeError('Retained compiled artifact membership differs')
                for name, expected in members.items():
                    relative = Path(name)
                    if relative.is_absolute() or '..' in relative.parts or digest(retained / 'compiled-evidence' / relative) != expected:
                        raise RuntimeError('Retained compiled artifact differs: ' + name)
                classes = retained / 'compiled-evidence/classes'
                test_classes = [retained / 'compiled-evidence/test-classes-0', retained / 'compiled-evidence/test-classes-1']
                if not any((path / 'app/cool/mobile/gateway/GatewaySuccessorTest.class').is_file() for path in test_classes):
                    raise RuntimeError('Retained successor test class unavailable')
                report['compile_reuse'] = {'packet': str(retained), 'validation_sha256': digest(validation_path),
                    'binding_sha256': digest(binding_path), 'artifact_members': len(members),
                    'runtime_binary_members': len(binary_hashes), 'api_module_count': len(api_sources),
                    'selected_source_count': len(set(selected)), 'reused_compilers': compiled,
                    'scope': 'Exact equivalent product/test/API and runtime bytes; retained broad suite result is not a new run'}
                code = 0
            else:
                classes = temporary / 'classes'; classes.mkdir()
                compiler = [str(helper.JBR / 'bin/java'), '-Xms64m', '-Xmx1g', '-XX:ActiveProcessorCount=2',
                    '-cp', os.pathsep.join(map(str, dependencies)), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                    '-no-stdlib', '-no-reflect', '-jvm-target', '17']
                code = run('compile-shim-product', compiler + ['-module-name', 'gateway_product', '-classpath', source_cp,
                           '-d', str(classes)] + [str(packet / 'source' / path) for path in products] +
                           [str(path) for path in sorted((packet / 'shims').glob('*.kt'))])
                target = temporary / 'test-classes'; target.mkdir(); test_classes = [target]
                if not code:
                    code = run('compile-successor-test', compiler + ['-module-name', 'gateway_successor_tests',
                        '-Xfriend-paths=' + str(classes), '-classpath', os.pathsep.join([str(classes), source_cp]),
                        '-d', str(target)] + [str(packet / 'source' / path) for path in tests])
                if not code:
                    api_classes = temporary / 'api-classes'; api_classes.mkdir()
                    config = packet / 'api-generated/BuildConfig.kt'; config.parent.mkdir(exist_ok=True)
                    config.write_text('package app.cool.mobile\nobject BuildConfig { const val FLAVOR = "internal_gateway" }\n')
                    code = run('compile-real-android-api', compiler + ['-classpath',
                        os.pathsep.join([str(helper.ANDROID_API), str(embedding), str(lifecycle), source_cp]),
                        '-d', str(api_classes)] + [str(packet / 'source' / path) for path in api_sources] + [str(config)])
            if not code:
                code = run('tests-' + SUITE, [str(helper.JBR / 'bin/java'),
                    '-Dcollect.successor.fixtures=' + str(captured_fixtures), '-ea', '-Xmx512m', '-XX:ActiveProcessorCount=2',
                    '-cp', os.pathsep.join([str(classes), *map(str, test_classes), source_cp]),
                    'org.junit.runner.JUnitCore', 'app.cool.mobile.gateway.' + SUITE])
        source_drift = [str(path) for path in paths if digest(ROOT / path) != hashes[str(path)]]
        fixture_drift = [path.name for path in fixture_paths if digest(path) != fixture_hashes[path.name]]
        binary_drift = [str(path) for path in binary_inputs if digest(path) != binary_hashes[str(path)]]
        report.update({'source_changes': source_drift, 'fixture_changes': fixture_drift, 'binary_changes': binary_drift,
                       'status': 'pass' if not code and not source_drift and not fixture_drift and not binary_drift else 'fail'})
    except Exception as error:
        report['error'] = str(error)
    (packet / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'error': report.get('error')}))
    raise SystemExit(0 if report['status'] == 'pass' else 1)


if __name__ == '__main__':
    main()
