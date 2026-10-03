#!/usr/bin/env python3
"""Only six frozen peer archive corrections, current cached native compile/lint and affected harness."""
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

R = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
C = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930')
B = R / 'docs/release/asset-build-hygiene-2026-09-30/native-current-local-20261001-resumption1'
P = B / 'gateway-archive-final'
OLD = C / 'export-native-current-local-20261001-resumption1-gateway'
E = C / 'export-native-current-local-20261001-resumption1-gateway-archive-final'
SDK = R / '.cache/flutter-sdk-isolated-asset-attempt136'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
assert json.loads((B / 'gateway/execution-recorder-continuation1.json').read_text())['status'] == 'pass'
assert json.loads((B / 'gateway/artifact-verification.json').read_text())['status'] == 'pass'
assert not E.exists()
P.mkdir(exist_ok=False)
shutil.copy2(__file__, P / 'runner-source.py')
delta = json.loads((B / 'gateway-archive-delta/captured-archive-delta.json').read_text())
assert len(delta['source_sha256']) == 6
assert all(sha(R / name) == digest for name, digest in delta['source_sha256'].items()), 'Peer native correction has changed since freeze; do not overwrite newer source'
env = {k: v for k, v in os.environ.items() if k in {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', JAVA_HOME='/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home',
           PUB_CACHE=str(R / '.cache/pub-cache-hygiene-20260930'), PATH=str(SDK / 'bin') + ':/Users/jeanbosco/.local/bin:' + env['PATH'])
commands = []
def run(name, argv, cwd=E, expected=0):
    print('START', name, flush=True)
    write(P / 'execution.json', {'status': 'running', 'pid': os.getpid(), 'stage': name, 'commands': commands})
    started = time.monotonic()
    with (P / (name + '.stdout')).open('wb') as out, (P / (name + '.stderr')).open('wb') as err:
        result = subprocess.run([str(x) for x in argv], cwd=cwd, env=env, stdout=out, stderr=err)
    commands.append({'name': name, 'command': [str(x) for x in argv], 'exit_code': result.returncode, 'elapsed_seconds': round(time.monotonic() - started, 2),
                     'stdout_sha256': sha(P / (name + '.stdout')), 'stderr_sha256': sha(P / (name + '.stderr'))})
    write(P / 'execution.json', {'status': 'running' if result.returncode == expected else 'fail', 'commands': commands, 'stage': name})
    print('END', name, result.returncode, flush=True)
    assert result.returncode == expected, name
run('clone-accepted-native-working-cache', ['cp', '-cR', OLD, E], C)
original = json.loads((B / 'gateway/source-export.json').read_text())['source_sha256']
for name, digest in delta['source_sha256'].items():
    assert sha(E / name) == original[name]
    source = B / 'gateway-archive-delta/source' / name
    assert sha(source) == digest
    shutil.copy2(source, E / name)
expected = {**original, **delta['source_sha256']}
assert all(sha(E / name) == digest for name, digest in expected.items())
flutter = {file.relative_to(E).as_posix(): sha(file) for file in (E / 'build/app/intermediates/flutter').rglob('*') if file.is_file()}
assert flutter and any(name.endswith('app.so') for name in flutter)
write(P / 'reused-flutter-output-inputs.json', flutter)
write(P / 'final-native-source.json', {'source_sha256': expected, 'android_source_sha256': delta['final_android_candidate_sha256'],
      'parent_artifact_verification_sha256': sha(B / 'gateway/artifact-verification.json'),
      'six_peer_corrections': delta['source_sha256'], 'scope': 'Fresh derivative of completed current native working copy, exactly six frozen archive runtime/tests overlaid; no shared checkout/native source mutation.'})
write(P / 'final-flat-native-inputs.json', delta['final_android_candidate_sha256'])
run('affected-archive-recovery-jvm', ['python3', E / 'scripts/tests/android_gateway_attempt_archive_jvm.py', '--focus-recovery', '--packet', P / 'affected-archive-jvm'])
run('incremental-gateway-assemble-lint', ['./gradlew', ':app:assembleInternal_gatewayRelease', ':app:lintInternal_gatewayRelease',
    '-x', ':app:compileFlutterBuildInternal_gatewayRelease', '-Ptarget=lib/main_gateway.dart', '-PcollectUnsignedLocalQa=true',
    '--offline', '--no-daemon', '--max-workers=2', '--console=plain'], E / 'android')
assert all(sha(E / name) == digest for name, digest in expected.items())
assert all(sha(E / name) == digest for name, digest in flutter.items())
lint = E / 'build/app/reports/lint-results-internal_gatewayRelease.xml'
issues = [{**dict(item.attrib), 'locations': [dict(loc.attrib) for loc in item.findall('location')]} for item in ET.parse(lint).getroot().findall('issue')]
assert not any(item['severity'] in ['Error', 'Fatal'] for item in issues)
write(P / 'lint-warning-inventory.json', issues)
shutil.copy2(lint, P / lint.name)
apk = E / 'build/app/outputs/apk/internal_gateway/release/app-internal_gateway-release-unsigned.apk'
with zipfile.ZipFile(apk) as archive:
    assert archive.testzip() is None
    assert not any('aeonik' in name.lower() for name in archive.namelist())
    assert b'Inter' in archive.read('assets/flutter_assets/FontManifest.json') and b'Aeonik' not in archive.read('assets/flutter_assets/FontManifest.json')
    assert hashlib.sha256(archive.read('assets/flutter_assets/assets/typefaces/Inter-Variable.ttf')).hexdigest() == sha(E / 'assets/typefaces/Inter-Variable.ttf')
    marker = json.loads(archive.read('assets/collect-local-unsigned-qa.json'))
    assert marker['signing'] is False and marker['store_acceptance'] is False
    dex = [name for name in archive.namelist() if name.endswith('.dex')]
    assert dex and all(all(token not in archive.read(name) for token in [b'FlutterLocalNotificationsPlugin', b'FlutterFirebaseMessagingPlugin', b'com/dexterous/flutterlocalnotifications/', b'com/google/firebase/messaging/']) for name in dex)
tools = Path('/Users/jeanbosco/Library/Android/sdk/build-tools/37.0.0')
run('final-apk-manifest', [tools / 'aapt2', 'dump', 'badging', apk])
badging = (P / 'final-apk-manifest.stdout').read_text()
assert "name='app.cool.mobile.gateway'" in badging and 'GatewayActivity' in badging and 'android.permission.POST_NOTIFICATIONS' not in badging
run('final-apk-unsigned', [tools / 'apksigner', 'verify', '--verbose', apk], expected=1)
assert 'DOES NOT VERIFY' in ((P / 'final-apk-unsigned.stdout').read_text() + (P / 'final-apk-unsigned.stderr').read_text())
helper = B / 'generated-native-input-classification/resolved_native_package_inputs.py'
spec = importlib.util.spec_from_file_location('reused_closed_plugin_inputs', helper)
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
package_check = package.verify(json.loads((B / 'gateway/resolved-package-inputs-before.json').read_text()), OLD)
assert package_check['status'] == 'pass'
write(P / 'reused-package-inputs-after.json', package_check)
assert sha(E / '.dart_tool/package_config.json') == sha(OLD / '.dart_tool/package_config.json')
assert sha(E / '.flutter-plugins-dependencies') == sha(OLD / '.flutter-plugins-dependencies')
output = C / 'artifacts-native-current-local-20261001-resumption1-gateway-archive-final'
output.mkdir(exist_ok=False)
shutil.copy2(apk, output / apk.name)
receipt = json.loads((P / 'affected-archive-jvm/validation.json').read_text())
assert receipt['status'] == 'pass'
report = {'status': 'pass', 'artifact': str(output / apk.name), 'sha256': sha(apk), 'bytes': apk.stat().st_size,
          'unsigned_verified': True, 'qa_marker': marker, 'aeonik_absent': True, 'inter_font_sha256': sha(E / 'assets/typefaces/Inter-Variable.ttf'),
          'native_source_sha256': delta['final_android_candidate_sha256'], 'native_source_unchanged': True,
          'reused_flutter_outputs_unchanged': True, 'closed_dependency_inputs_unchanged': True,
          'lint_errors': 0, 'lint_warning_count': len(issues), 'affected_harness_validation_sha256': sha(P / 'affected-archive-jvm/validation.json'),
          'live_peer_correction_drift': [name for name, digest in delta['source_sha256'].items() if sha(R / name) != digest],
          'scope': 'Current native archive correction APK/compile/lint and affected realJSON synthetic encrypted-store/backend recovery harness; initial full JVM controls and unchanged Dart/dependencies retained separately. No duplicated Flutter/pub/graph/production/iOS build, physical/provider/signing/store or whole-repo currentness claim.'}
write(P / 'artifact-verification.json', report)
write(P / 'execution.json', {'status': 'pass', 'commands': commands, 'artifact_verification_sha256': sha(P / 'artifact-verification.json')})
print('FINAL GATEWAY ARCHIVE PASS', flush=True)
