#!/usr/bin/env python3
"""Seal actual failure scope and preservation; no SDK/repository mutations."""
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
REPO = RELEASE.parents[2]
CANDIDATE = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-collect-kotlin-2.4.20-candidate1')
SHARED = Path('/Volumes/PRO-G40/Development/Flutter/flutter')
PRISTINE = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-authenticated-foundation-batch1')
BUILD = CANDIDATE / 'packages/flutter_tools/gradle/build'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, value):
    with (HERE / name).open('x') as out:
        json.dump(value, out, indent=2, sort_keys=True)
        out.write('\n')
        out.flush()
        os.fsync(out.fileno())


def main():
    terminal = json.loads((HERE / 'sdk-compiler-runtime-attempt2.json').read_text())
    built = json.loads((HERE / 'built-source-attempt2.json').read_text())
    if terminal['exit_code'] != 1 or terminal['timed_out'] or terminal['headroom_failure'] or built['exit_code'] != 0:
        raise ValueError('exact actual terminal failure/readback differs')
    stdout = (HERE / 'sdk-compiler-runtime-attempt2.stdout').read_text()
    stderr = (HERE / 'sdk-compiler-runtime-attempt2.stderr').read_text()
    if digest(HERE / 'sdk-compiler-runtime-attempt2.stdout') != terminal['stdout_sha256'] or digest(HERE / 'sdk-compiler-runtime-attempt2.stderr') != terminal['stderr_sha256']:
        raise ValueError('actual terminal logs drift')
    classes = {}
    for path in sorted((BUILD / 'classes/kotlin/main').rglob('*.class')):
        data = path.read_bytes()
        if data[:4] != b'\xca\xfe\xba\xbe':
            raise ValueError('actual classfile magic differs')
        classes[path.relative_to(BUILD / 'classes/kotlin/main').as_posix()] = hashlib.sha256(data).hexdigest()
    jar = BUILD / 'libs/gradle-1.0.0.jar'
    with zipfile.ZipFile(jar) as archive:
        jar_classes = {name: hashlib.sha256(archive.read(name)).hexdigest() for name in archive.namelist() if name.endswith('.class')}
    if len(classes) != 83 or jar_classes != classes:
        raise ValueError('real main classes/JAR exact correspondence differs')
    junit = sorted((BUILD / 'test-results').rglob('TEST-*.xml')) if (BUILD / 'test-results').exists() else []
    test_classes = list((BUILD / 'classes/kotlin/test').rglob('*.class'))
    if junit or test_classes:
        raise ValueError('unexpected test execution output; failure scope requires review')
    ps = subprocess.run(['ps', '-p', str(terminal['pid']), '-o', 'pid=,command='], capture_output=True, text=True).stdout.strip()
    if ps:
        raise ValueError('terminal compiler PID remains')
    failures = [line.strip() for line in stderr.splitlines() if '- Error:' in line]
    compile_errors = [line for line in stderr.splitlines() if line.startswith('e:')]
    if len(failures) != 5 or not compile_errors:
        raise ValueError('actual failure categories differ')
    preserve = json.loads((RELEASE / 'kotlin-sdk-physical-foundation-batch1/preservation-readback.json').read_text())
    packet_anchors = {name: row['manifest_sha256'] for name, row in preserve['prior_sealed_packets'].items()}
    packet_anchors.update({'kotlin-sdk-physical-foundation-batch1': '15fbf2bdda4a5f69b77d9e5eb945217528e63edbef1c372366ceceb33a12e126', 'kotlin-sdk-candidate-preparation-batch1': '1a788b56e4c61299f1981bdc83dff5201f8d742880c987f0f8c49dd22c06f551'})
    packets = {}
    for name, expected in packet_anchors.items():
        directory = RELEASE / name
        manifest = directory / 'packet-files.json'
        if digest(manifest) != expected:
            raise ValueError('prior independently frozen packet manifest drift')
        files = json.loads(manifest.read_text())['files']
        if any(digest(directory / path) != value for path, value in files.items()):
            raise ValueError('prior frozen packet leaf drift')
        packets[name] = {'manifest_sha256': expected, 'unchanged_leaves': len(files)}
    owned = {}
    for name, expected in preserve['owned_repo_inputs'].items():
        if digest(REPO / name) != expected:
            raise ValueError('owned repository declaration/lock/provenance input changed')
        owned[name] = expected
    shared = {}
    for name, row in preserve['shared_installed_Gradle_source_selected_paths'].items():
        current = digest(SHARED / name)
        if current != row['current_sha256']:
            raise ValueError('selected shared SDK source changed')
        shared[name] = current
    if digest(SHARED / 'pubspec.lock') != preserve['shared_current_pubspec_lock_sha256']:
        raise ValueError('shared SDK previously observed lock changed')
    original_three = json.loads((RELEASE / 'kotlin-sdk-physical-foundation-batch1/three-file-physical-preview-binding.json').read_text())['files']
    pristine_three = {name: digest(PRISTINE / name) for name in original_three}
    if any(pristine_three[name] != row['actual_physical_original_sha256'] for name, row in original_three.items()):
        raise ValueError('actual pristine original three source files changed')
    save('terminal-native-failure-results.json', {
        'status': 'ACTUAL_COMPILER_RECIPE_FAILURE__SCOPED_MAIN_AND_ORIGIN_PROOF_ONLY',
        'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'actual_exit_code': terminal['exit_code'], 'actual_seconds': terminal['actual_seconds'],
        'actual_deadline_seconds': terminal['actual_deadline_seconds'], 'timed_out': False,
        'headroom_failure': False, 'main_compile_and_JAR_produced': True,
        'main_class_files': len(classes), 'main_output_regular_files': 84,
        'class_sha256': classes, 'JAR_path': str(jar), 'JAR_sha256': digest(jar),
        'actual_JAR_classes_match_main_compiled_classes': True,
        'test_class_files': 0, 'JUnit_XML_files': 0, 'JUnit_tests_executed': 0,
        'validatePlugins_actual_errors': failures, 'compileTestKotlin_actual_errors': compile_errors,
        'complete_after_failure_candidate_source_readback_pass': True,
        'runtime_compiler_actual_graphs_and_publisher_binding_pass': True,
        'actual_supported_Kotlin_DSL_warning': 'embedded-kotlin/kotlin-dsl rely on Kotlin 2.2.0; requested 2.4.20 may work differently',
        'compiler_PID_absent': True, 'source_delta_count': 3,
        'candidate_promoted': False, 'production_release_approval': False,
        'remaining': ['fix and review upstream task metadata and test imports', 'real complete SDK JUnit/validation acceptance', 'Kotlin DSL support warning remains', 'generic SDK template/maxKnown2.3.20 scope', 'app all-flavor/native/Dart/bootstrap consumers', 'current complete provenance/license/advisory/SBOM inventory', 'candidate selection and release authority'],
    })
    save('current-preservation-readback.json', {
        'prior_frozen_packets': packets, 'prior_unchanged_leaf_count': sum(v['unchanged_leaves'] for v in packets.values()),
        'owned_repo_inputs_unchanged': owned, 'selected_shared_SDK_source_unchanged': shared,
        'selected_shared_count': len(shared), 'shared_previously_modified_pubspec_lock_unchanged': True,
        'pristine_actual_original_three_unchanged': pristine_three,
        'whole_installed_SDK_clean_or_publisher_authentication_claimed': False,
        'actual_free_bytes': shutil.disk_usage(CANDIDATE.parent).free,
        'shared_pristine_repo_pin_lock_writes': False,
    })
    print(json.dumps({'actual_failure_retained': True, 'main_class_files': len(classes), 'main_regular_files': 84, 'JUnit_tests_executed': 0, 'prior_unchanged_leaves': sum(v['unchanged_leaves'] for v in packets.values())}))


if __name__ == '__main__':
    main()
