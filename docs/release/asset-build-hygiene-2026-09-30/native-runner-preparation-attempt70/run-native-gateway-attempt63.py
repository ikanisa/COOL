import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
BASE = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/local-source-acceptance-attempt51'
BOUND = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/export-attempt51')
EXPORT = BOUND.parent / 'export-attempt63-gateway'
P = ROOT / 'docs/release/asset-build-hygiene-2026-09-30/native-export-attempt63-gateway'
SDK = ROOT / '.cache/flutter-sdk-isolated-asset-attempt23'
ANDROID = Path('/Users/jeanbosco/Library/Android/sdk')
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()

assert json.loads((BASE / 'execution.json').read_text())['status'] == 'pass'
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
assert all((EXPORT / name).is_file() and sha(EXPORT / name) == digest for name, digest in source.items())
drift = {name: {'before': digest, 'after': sha(ROOT / name) if (ROOT / name).is_file() else None}
         for name, digest in source.items() if not (ROOT / name).is_file() or sha(ROOT / name) != digest}
verification = {'status': 'pass', 'kind': 'local_unsigned_gateway_qa_artifact', 'path': str(apk),
                'bytes': apk.stat().st_size, 'sha256': sha(apk), 'actual_unsigned_rejection_verified': True,
                'dart_target': 'lib/main_gateway.dart', 'flavor': 'internal_gateway',
                'source_file_count': len(source), 'declared_exported_sources_unchanged': True,
                'original_checkout_drift': drift, 'current_checkout_acceptance': not drift,
                'jvm_test_count': sum(int(row['tests']) for row in tests), 'lint_warning_count': len(issues),
                'scope': 'Actual unsigned internal Gateway target/flavor, merged manifest and JVM/lint checks; no physical SIM, dispatch, Android Keystore, provider, signed artifact or store acceptance'}
(P / 'apk-verification.json').write_text(json.dumps(verification, indent=2) + '\n')
(P / 'execution.json').write_text(json.dumps({'status': 'pass', 'commands': commands,
                                            'artifact_verification_sha256': sha(P / 'apk-verification.json')}, indent=2) + '\n')
print('GATEWAY BUILD PASS', flush=True)
