import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
BASE = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/local-source-acceptance-attempt83'
BOUND = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt83')
EXPORT = BOUND.parent / 'export-attempt63-gateway'
P = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt63-gateway'
SDK = ROOT / '.cache/flutter-sdk-isolated-asset-attempt23'
ANDROID = Path('/Users/jeanbosco/Library/Android/sdk')
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()

prior = json.loads((BASE / 'execution.json').read_text())
assert prior['status'] == 'pass'
assert all(any(row['name'] == name and row['exit_code'] == 0 for row in prior['commands'])
           for name in ['format-check', 'fatal-analyzer', 'public-copy-responsive-regressions'])
assert not EXPORT.exists()
P.mkdir(exist_ok=False)
(P / 'runner-source.py').write_bytes(Path(__file__).read_bytes())
manifest = json.loads((BASE / 'source-export.json').read_text())
source = manifest['source_sha256']
extras = json.loads((BASE / 'additional-public-tooling-source.json').read_text())['sha256']
inputs = {**source, **extras}
for name, digest in sorted(inputs.items()):
    origin = BOUND / name
    assert origin.is_file() and sha(origin) == digest, name
    target = EXPORT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(origin, target)
    assert sha(target) == digest
clone = {**manifest, 'kind': 'independent_clone_of_one_bound_application_source',
         'destination': str(EXPORT), 'parent_source_export_sha256': sha(BASE / 'source-export.json'),
         'clone_inputs_sha256': inputs}
(P / 'source-export.json').write_text(json.dumps(clone, indent=2, sort_keys=True) + '\n')
env = {k: v for k, v in os.environ.items()
       if k in {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
env.update({'CI': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
            'JAVA_HOME': '/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home',
            'PUB_CACHE': str(ROOT / '.cache/pub-cache-hygiene-20260930'),
            'PATH': str(SDK / 'bin') + ':/Users/jeanbosco/.local/bin:' + env['PATH']})
commands = []

def run(name, argv, cwd=EXPORT / 'android', expected=0):
    print('START', name, flush=True)
    started = time.monotonic()
    with (P / (name + '.stdout')).open('wb') as out, (P / (name + '.stderr')).open('wb') as err:
        result = subprocess.run(argv, cwd=cwd, env=env, stdout=out, stderr=err)
    commands.append({'name': name, 'command': argv, 'exit_code': result.returncode,
                     'elapsed_seconds': round(time.monotonic() - started, 2),
                     'stdout_sha256': sha(P / (name + '.stdout')),
                     'stderr_sha256': sha(P / (name + '.stderr'))})
    (P / 'execution.json').write_text(json.dumps({'status': 'running' if result.returncode == expected else 'fail',
                                                'commands': commands}, indent=2) + '\n')
    print('END', name, result.returncode, flush=True)
    assert result.returncode == expected, name

run('export-git-init', ['git', 'init', '-q'], EXPORT)
run('pub-enforce-offline', [str(SDK / 'bin/flutter'), 'pub', 'get', '--offline', '--enforce-lockfile'], EXPORT)
assert sha(EXPORT / 'pubspec.lock') == source['pubspec.lock']
# Additional native compiler/package source binding has its own accepted pure proof.
import importlib.util
PACKAGE_TOOL = 'scripts/qa/resolved_native_package_inputs.py'
package_proof_path = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/resolved-native-inputs-attempt87/validation.json'
package_proof = json.loads(package_proof_path.read_text())
assert package_proof['status'] == 'pass' and sha(ROOT / PACKAGE_TOOL) == package_proof['source_sha256'][PACKAGE_TOOL]
shutil.copy2(ROOT / PACKAGE_TOOL, P / 'resolved_native_package_inputs.py')
package_spec = importlib.util.spec_from_file_location('native_package_inputs', P / 'resolved_native_package_inputs.py')
package_module = importlib.util.module_from_spec(package_spec); package_spec.loader.exec_module(package_module)
package_binding = package_module.bind(EXPORT, SDK, ROOT / '.cache/pub-cache-hygiene-20260930')
(P / 'resolved-package-inputs-before.json').write_text(json.dumps(package_binding, indent=2, sort_keys=True) + '\n')
(P / 'resolved-package-tool-binding.json').write_text(json.dumps({'tool_sha256': sha(P / 'resolved_native_package_inputs.py'), 'accepted_test_packet_sha256': sha(package_proof_path), 'scope': 'Actual additional helper source, accepted12 pure regressions and immutable native package bindings; no application source change'}, indent=2) + '\n')
print('RESOLVED PACKAGE INPUTS BOUND', len(package_binding['packages']), sum(len(row['files']) for row in package_binding['packages'].values()), flush=True)
(EXPORT / 'android/local.properties').write_text('sdk.dir=' + str(ANDROID) + '\nflutter.sdk=' + str(SDK) +
                                               '\nflutter.buildMode=release\nflutter.versionName=1.2.4\nflutter.versionCode=23\n')
(P / 'generated-inputs.json').write_text(json.dumps({
    'android/local.properties': sha(EXPORT / 'android/local.properties'),
    'package_binding_sha256': sha(EXPORT / '.dart_tool/package_config.json'),
    'plugin_binding_sha256': sha(EXPORT / '.flutter-plugins-dependencies'),
    'dart_target': 'lib/main_gateway.dart', 'flavor': 'internal_gateway',
    'private_provider_signing_environment_supplied': False,
}, indent=2) + '\n')
target = '-Ptarget=lib/main_gateway.dart'
run('unsigned-gateway-build', ['./gradlew', ':app:assembleInternal_gatewayRelease', target,
                               '-PcollectUnsignedLocalQa=true', '--offline', '--no-daemon'])
run('gateway-native-lint', ['./gradlew', ':app:lintInternal_gatewayRelease', target, '--offline', '--no-daemon'])
run('gateway-native-jvm', ['./gradlew', ':app:testInternal_gatewayDebugUnitTest', target, '--offline', '--no-daemon'])
apk = EXPORT / 'build/app/outputs/apk/internal_gateway/release/app-internal_gateway-release-unsigned.apk'
if not apk.is_file():
    candidates = list((EXPORT / 'build/app/outputs').rglob('*internal_gateway*release*.apk'))
    assert len(candidates) == 1, candidates
    apk = candidates[0]
with zipfile.ZipFile(apk) as archive:
    assert archive.testzip() is None
tools = ANDROID / 'build-tools/37.0.0'
run('gateway-signature', [str(tools / 'apksigner'), 'verify', '--verbose', str(apk)], EXPORT, expected=1)
signature_output = (P / 'gateway-signature.stdout').read_text() + (P / 'gateway-signature.stderr').read_text()
assert 'DOES NOT VERIFY' in signature_output and 'Missing META-INF/MANIFEST.MF' in signature_output, 'Expected unsigned APK rejection was absent'
run('gateway-manifest', [str(tools / 'aapt2'), 'dump', 'badging', str(apk)], EXPORT)
badging = (P / 'gateway-manifest.stdout').read_text()
assert "name='app.cool.mobile.gateway'" in badging
assert "launchable-activity: name='app.cool.mobile.gateway.GatewayActivity'" in badging
for permission in ['SEND_SMS', 'READ_PHONE_STATE', 'ACCESS_NETWORK_STATE']:
    assert 'android.permission.' + permission in badging
for permission in ['RECEIVE_SMS', 'CALL_PHONE', 'CAMERA', 'POST_NOTIFICATIONS', 'WRITE_EXTERNAL_STORAGE', 'READ_EXTERNAL_STORAGE']:
    assert 'android.permission.' + permission not in badging
assert "launchable-activity: name='app.cool.mobile.MainActivity'" not in badging
lint = EXPORT / 'build/app/reports/lint-results-internal_gatewayRelease.xml'
issues = [{'id': issue.get('id'), 'severity': issue.get('severity'), 'message': issue.get('message'),
           'locations': [dict(location.attrib) for location in issue.findall('location')]}
          for issue in ET.parse(lint).getroot().findall('issue')]
assert not any(issue['severity'] in {'Error', 'Fatal'} for issue in issues)
shutil.copy2(lint, P / lint.name)
(P / 'lint-warning-inventory.json').write_text(json.dumps(issues, indent=2) + '\n')
testfiles = list((EXPORT / 'build/app/test-results/testInternal_gatewayDebugUnitTest').glob('TEST-*.xml'))
tests = [{key: ET.parse(file).getroot().get(key) for key in ['name', 'tests', 'failures', 'errors', 'skipped']}
         for file in testfiles]
assert testfiles and all(row['failures'] == row['errors'] == row['skipped'] == '0' for row in tests)
(P / 'jvm-test-results').mkdir()
for file in testfiles:
    shutil.copy2(file, P / 'jvm-test-results' / file.name)
(P / 'jvm-tests.json').write_text(json.dumps(tests, indent=2) + '\n')
package_check = package_module.verify(package_binding, EXPORT)
(P / 'resolved-package-inputs-after.json').write_text(json.dumps(package_check, indent=2, sort_keys=True) + '\n')
assert package_check['status'] == 'pass', 'Actual resolved compiler/plugin package input drift'
assert all((EXPORT / name).is_file() and sha(EXPORT / name) == digest for name, digest in inputs.items())
spec = importlib.util.spec_from_file_location('bound_export_scope', EXPORT / 'scripts/qa/native_source_export.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
current_names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
current = {name: sha(ROOT / name) for name in sorted(set(current_names))
           if name and (module.selected(name) or name.startswith('scripts/') or name in {'Makefile', '.gitignore'})
           and (ROOT / name).is_file() and not (ROOT / name).is_symlink()}
drift = {name: {'before': inputs.get(name), 'after': current.get(name)}
         for name in sorted(inputs.keys() | current.keys()) if inputs.get(name) != current.get(name)}
verification = {'status': 'pass', 'kind': 'local_unsigned_gateway_qa_artifact', 'path': str(apk),
                'bytes': apk.stat().st_size, 'sha256': sha(apk), 'actual_unsigned_rejection_verified': True,
                'dart_target': 'lib/main_gateway.dart', 'flavor': 'internal_gateway',
                'source_file_count': len(source), 'total_bound_input_count': len(inputs),
                'declared_exported_sources_and_tooling_unchanged': True,
                'scope_drift_includes_additions_and_deletions': True,
                'original_checkout_drift': drift, 'current_checkout_acceptance': not drift,
                'jvm_test_count': sum(int(row['tests']) for row in tests), 'lint_warning_count': len(issues),
                'scope': 'Actual unsigned internal Gateway target/flavor, merged manifest and JVM/lint checks; no physical SIM, dispatch, Android Keystore, provider, signed artifact or store acceptance'}
runtime_roots = ('lib/', 'assets/', 'licenses/', 'android/', 'ios/', 'third_party/', 'web/')
runtime_files = {'pubspec.yaml', 'pubspec.lock', '.metadata', '.fvmrc', '.dvmrc',
                 'scripts/android_play_store_build.sh', 'scripts/android_release_signing_preflight.sh',
                 'scripts/ios_app_store_build.sh', 'scripts/qa/native_build_provenance.rb'}
runtime_drift = {name: value for name, value in drift.items()
                 if name.startswith(runtime_roots) or name in runtime_files}
verification.update({'application_and_native_input_checkout_drift': runtime_drift,
                     'application_and_native_inputs_current': not runtime_drift,
                     'other_declared_input_drift': {name: value for name, value in drift.items() if name not in runtime_drift},
                     'currentness_scope': 'All drift is retained. SQL/QA/test scripts are separate from application/native/build-caller inputs; no whole-repository currentness claim.'})
(P / 'apk-verification.json').write_text(json.dumps(verification, indent=2) + '\n')
(P / 'execution.json').write_text(json.dumps({'status': 'pass', 'commands': commands,
                                            'artifact_verification_sha256': sha(P / 'apk-verification.json')}, indent=2) + '\n')
print('GATEWAY BUILD PASS', flush=True)
