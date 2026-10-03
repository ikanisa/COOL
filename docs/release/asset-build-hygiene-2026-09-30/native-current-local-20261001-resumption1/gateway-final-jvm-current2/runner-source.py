#!/usr/bin/env python3
"""Only full final-source Gateway JVM suites; no package, Release, lint or graph task."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET

R = Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
C = Path('/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930')
B = R / 'docs/release/asset-build-hygiene-2026-09-30/native-current-local-20261001-resumption1'
E = C / 'export-native-current-local-20261001-resumption1-gateway-archive-final'
P = B / 'gateway-final-jvm-current2'
SDK = R / '.cache/flutter-sdk-isolated-asset-attempt136'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def write(p, value):
    p.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

assert not P.exists(), 'Preserve prior packets; do not restart'
P.mkdir()
shutil.copy2(__file__, P / 'runner-source.py')
original_receipt = B / 'final-native-acceptance.json'
original_receipt_sha = sha(original_receipt)
expected = json.loads((B / 'gateway-archive-final/final-native-source.json').read_text())['source_sha256']
flat = json.loads((B / 'gateway-archive-final/final-flat-native-inputs.json').read_text())
flutter = json.loads((B / 'gateway-archive-final/reused-flutter-output-inputs.json').read_text())
assert len(flat) == 89
assert all(sha(E / n) == h for n, h in expected.items())
assert all(sha(E / n) == h for n, h in flat.items())
assert all(sha(E / n) == h for n, h in flutter.items())
artifact = json.loads((B / 'gateway-archive-final/artifact-verification.json').read_text())
assert artifact['status'] == 'pass'
apk = Path(artifact['artifact'])
apk_before = sha(apk)
assert apk_before == artifact['sha256']
export_apk = E / 'build/app/outputs/apk/internal_gateway/release/app-internal_gateway-release-unsigned.apk'
assert sha(export_apk) == apk_before
initial = B / 'gateway/real-json-runtime.init.gradle'
init = P / 'real-json-runtime.init.gradle'
init.write_text(initial.read_text().replace(str(B / 'gateway'), str(P)))
write(P / 'inputs.json', {'final_native_source_sha256': sha(B / 'gateway-archive-final/final-native-source.json'),
    'final_flat_native_inputs_sha256': sha(B / 'gateway-archive-final/final-flat-native-inputs.json'),
    'original_final_native_acceptance_sha256': original_receipt_sha,
    'source_inputs': len(expected), 'native_inputs': len(flat), 'release_apk_sha256': apk_before,
    'real_json_init_parent_sha256': sha(initial), 'real_json_init_sha256': sha(init),
    'scope': 'Exactly accepted final six-file derivative; full Gateway JVM verification only.'})
env = {k: v for k, v in os.environ.items() if k in {'HOME', 'USER', 'LOGNAME', 'SHELL', 'PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE'}}
env.update(CI='true', FLUTTER_SUPPRESS_ANALYTICS='true', JAVA_HOME='/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home',
    PUB_CACHE=str(R / '.cache/pub-cache-hygiene-20260930'), PATH=str(SDK / 'bin') + ':/Users/jeanbosco/.local/bin:' + env['PATH'])
jobs = [
    ('full-gateway-debug-jvm', ['./gradlew', '-I', str(init), ':app:testInternal_gatewayDebugUnitTest',
      '-x', ':app:compileFlutterBuildInternal_gatewayDebug', '-Ptarget=lib/main_gateway.dart', '-PcollectUnsignedLocalQa=true',
      '--offline', '--no-daemon', '--max-workers=2', '--console=plain'], E / 'android'),
    ('full-standalone-jvm', ['python3', str(E / 'scripts/tests/android_gateway_attempt_archive_jvm.py'), '--packet', str(P / 'standalone')], E),
]
started = time.time()
processes = []
for name, argv, cwd in jobs:
    out = (P / (name + '.stdout')).open('wb')
    err = (P / (name + '.stderr')).open('wb')
    proc = subprocess.Popen(argv, cwd=cwd, env=env, stdout=out, stderr=err)
    processes.append((name, argv, proc, out, err, time.monotonic()))
write(P / 'execution.json', {'status': 'running', 'pid': os.getpid(), 'stage': 'full Gateway Debug JVM and full standalone JVM',
    'processes': [{'name': n, 'pid': p.pid, 'argv': a} for n, a, p, *_ in processes]})
print(json.dumps({'status': 'running', 'pid': os.getpid(), 'processes': [{'name': n, 'pid': p.pid} for n, _, p, *_ in processes]}), flush=True)
commands = []
for name, argv, proc, out, err, began in processes:
    try:
        code = proc.wait(timeout=max(1, 600 - (time.monotonic() - began)))
    except subprocess.TimeoutExpired:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        code = 124
    out.close()
    err.close()
    commands.append({'name': name, 'argv': argv, 'exit_code': code, 'elapsed_seconds': round(time.monotonic() - began, 2),
        'stdout_sha256': sha(P / (name + '.stdout')), 'stderr_sha256': sha(P / (name + '.stderr'))})
    write(P / 'execution.json', {'status': 'running', 'pid': os.getpid(), 'completed_commands': commands})
    print('END', name, code, flush=True)
assert all(x['exit_code'] == 0 for x in commands), 'Preserved actual command failure; no automatic restart'
gradle_output = (P / 'full-gateway-debug-jvm.stdout').read_text()
assert '> Task :app:testInternal_gatewayDebugUnitTest\n' in gradle_output, 'Full test task did not execute against changed current inputs'
assert 'BUILD SUCCESSFUL' in gradle_output
xml_dir = E / 'build/app/test-results/testInternal_gatewayDebugUnitTest'
xmls = sorted(xml_dir.glob('TEST-*.xml'))
assert xmls and all(x.stat().st_mtime >= started for x in xmls), 'Old XML receipt cannot satisfy current execution'
counts = {n: 0 for n in ('tests', 'errors', 'failures', 'skipped')}
for path in xmls:
    tree = ET.parse(path).getroot()
    for key in counts:
        counts[key] += int(tree.get(key, '0'))
    shutil.copy2(path, P / path.name)
assert counts['tests'] >= 141 and not any(counts[n] for n in ('errors', 'failures', 'skipped'))
standalone = json.loads((P / 'standalone/validation.json').read_text())
assert standalone['status'] == 'pass' and standalone['focus_recovery'] is False
test_output = (P / 'standalone/tests.stdout').read_text()
match = re.search(r'OK \((\d+) tests\)', test_output)
assert match
standalone_count = int(match.group(1))
assert standalone_count >= 186
classpath = json.loads((P / 'actual-json-test-classpath.json').read_text())
assert classpath['sha256'] == '3ea61b2a06e31edf1c91134fe9106b0ebb16628be169f3db75bc7a2b06b45796'
json_classes = [line for p in P.glob('jvm-class-load-*.log') for line in p.read_text().splitlines() if 'org.json.JSONObject source:' in line]
assert json_classes and all('json-20250517.jar' in x for x in json_classes)
assert all(sha(E / n) == h for n, h in expected.items())
assert all(sha(E / n) == h for n, h in flat.items())
assert all(sha(E / n) == h for n, h in flutter.items())
assert sha(apk) == apk_before and sha(export_apk) == apk_before
assert sha(original_receipt) == original_receipt_sha
receipt = {'status': 'pass', 'kind': 'additive_final_native_current_jvm_acceptance', 'commands': commands,
    'gradle_full_debug_jvm': counts, 'gradle_xml_suites': len(xmls), 'standalone_full_jvm_cases': standalone_count,
    'standalone_validation_sha256': sha(P / 'standalone/validation.json'), 'actual_real_json_class_load': json_classes,
    'actual_json_test_classpath_sha256': sha(P / 'actual-json-test-classpath.json'),
    'final_flat_native_inputs': str(B / 'gateway-archive-final/final-flat-native-inputs.json'),
    'final_flat_native_inputs_sha256': sha(B / 'gateway-archive-final/final-flat-native-inputs.json'),
    'native_input_count': len(flat), 'source_input_count': len(expected), 'all_frozen_inputs_unchanged': True,
    'cached_flutter_outputs_unchanged': True, 'release_apk': str(apk), 'release_apk_sha256': apk_before,
    'release_apk_unchanged': True, 'parent_final_native_acceptance': str(original_receipt),
    'parent_final_native_acceptance_sha256': original_receipt_sha, 'parent_receipt_unchanged': True,
    'both_full_suites_executed_against_final_six_file_derivative': True,
    'separate_suites_no_unique_union_sum_claim': True,
    'scope': 'Current frozen native derivative full Gradle Debug JVM and full existing standalone real-JSON/synthetic-encrypted-filesystem harness. Reuses already accepted exact Release APK/lint/Flutter/dependency graphs. No mutable whole-repository, signing, device, provider, store or publication claim.'}
write(B / 'final-native-current2-acceptance.json', receipt)
write(P / 'execution.json', {'status': 'pass', 'commands': commands, 'acceptance': str(B / 'final-native-current2-acceptance.json'),
    'acceptance_sha256': sha(B / 'final-native-current2-acceptance.json')})
print(json.dumps({'status': 'pass', 'gradle_jvm': counts, 'standalone_jvm_cases': standalone_count,
    'acceptance': str(B / 'final-native-current2-acceptance.json')}), flush=True)
