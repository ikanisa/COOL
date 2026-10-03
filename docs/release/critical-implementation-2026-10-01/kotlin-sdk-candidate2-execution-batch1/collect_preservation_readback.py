#!/usr/bin/env python3
"""Read frozen prior proofs and selected protected sources; write this new proof only."""
import datetime
import hashlib
import json
import os
import shutil
import stat
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
REPO = RELEASE.parents[2]
BASE = Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09')
PRISTINE = BASE / 'flutter-3.44.4-authenticated-foundation-batch1'
FAILED = BASE / 'flutter-3.44.4-collect-kotlin-2.4.20-candidate1'
SHARED = Path('/Volumes/PRO-G40/Development/Flutter/flutter')


def digest(path):
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode):
        raise ValueError('preserved input is not a regular leaf: ' + str(path))
    state = lambda value: (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns,
                           value.st_ctime_ns, value.st_mode, value.st_nlink)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as source:
        opened = os.fstat(source.fileno())
        if state(before) != state(opened):
            raise ValueError('preserved input replaced before open')
        result = hashlib.file_digest(source, 'sha256').hexdigest()
        if state(opened) != state(os.fstat(source.fileno())):
            raise ValueError('preserved input mutated during hash')
    if state(before) != state(path.lstat()):
        raise ValueError('preserved input named leaf changed after hash')
    return result


def require(path, expected):
    actual = digest(path)
    if actual != expected:
        raise ValueError('preserved digest differs: ' + str(path))
    return actual


def main():
    old = json.loads((RELEASE / 'kotlin-sdk-physical-foundation-batch1/preservation-readback.json').read_text())
    anchors = {name: row['manifest_sha256'] for name, row in old['prior_sealed_packets'].items()}
    anchors.update({
        'kotlin-sdk-physical-foundation-batch1': '15fbf2bdda4a5f69b77d9e5eb945217528e63edbef1c372366ceceb33a12e126',
        'kotlin-sdk-candidate-preparation-batch1': '1a788b56e4c61299f1981bdc83dff5201f8d742880c987f0f8c49dd22c06f551',
        'kotlin-sdk-candidate-execution-batch1': '71be02949c0e2c303f8f3e1e1d014035f7ae3a6330cbd9ec05f707bef81aee95',
        'kotlin-sdk-task-compatibility-plan2': '6ec617a0925bf719670e308f51d8ce19728f975500aaabf8fe1958cd29ac3fb3',
        'kotlin-sdk-candidate2-preparation-batch1': '433aa82ca5a79f5ced1a4129583b74ca737da470dcf2617cb8adbe6ca70ab5f6',
    })
    packets = {}
    for name, expected in anchors.items():
        directory = RELEASE / name
        manifest = directory / 'packet-files.json'
        require(manifest, expected)
        leaves = json.loads(manifest.read_text())['files']
        for relative, value in leaves.items():
            require(directory / relative, value)
        packets[name] = {'manifest_sha256': expected, 'unchanged_leaves': len(leaves)}
    owned = {name: require(REPO / name, expected) for name, expected in old['owned_repo_inputs'].items()}
    shared = {name: require(SHARED / name, row['current_sha256'])
              for name, row in old['shared_installed_Gradle_source_selected_paths'].items()}
    require(SHARED / 'pubspec.lock', old['shared_current_pubspec_lock_sha256'])
    originals = json.loads((RELEASE / 'kotlin-sdk-physical-foundation-batch1/three-file-physical-preview-binding.json').read_text())['files']
    pristine = {name: require(PRISTINE / name, row['actual_physical_original_sha256']) for name, row in originals.items()}
    five = json.loads((RELEASE / 'kotlin-sdk-task-compatibility-plan2/proposed-five-file-delta.json').read_text())['files']
    for name, row in five.items():
        pristine[name] = require(PRISTINE / name, row['before_SHA256'])
    failure = json.loads((RELEASE / 'kotlin-sdk-candidate-execution-batch1/terminal-native-failure-results.json').read_text())
    require(Path(failure['JAR_path']), failure['JAR_sha256'])
    failed_classes = {name: require(FAILED / 'packages/flutter_tools/gradle/build/classes/kotlin/main' / name, expected)
                      for name, expected in failure['class_sha256'].items()}
    failed_read = json.loads((HERE / 'preserved-failed-candidate1-full-source-readback.json').read_text())
    if failed_read['status'] != 'EXACT_CANDIDATE_SOURCE_DELTA_AND_PHYSICAL_READBACK_PASS' or failed_read['phase'] != 'built':
        raise ValueError('failed candidate full source preservation proof absent')
    result = {
        'status': 'FROZEN_PRIOR_EVIDENCE_AND_SELECTED_PROTECTED_INPUT_READBACK_PASS',
        'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'prior_frozen_packets': packets,
        'prior_unchanged_leaf_count': sum(row['unchanged_leaves'] for row in packets.values()),
        'owned_repo_inputs_unchanged': owned, 'selected_shared_SDK_source_unchanged': shared,
        'selected_shared_count': len(shared), 'shared_previous_pubspec_lock_unchanged': True,
        'pristine_actual_original_eight_unchanged': pristine,
        'failed_candidate1_full_source_readback': {
            'path': str(HERE / 'preserved-failed-candidate1-full-source-readback.json'),
            'sha256': digest(HERE / 'preserved-failed-candidate1-full-source-readback.json'),
            'status': failed_read['status'], 'phase': failed_read['phase']},
        'failed_candidate1_JAR_SHA256_unchanged': failure['JAR_sha256'],
        'failed_candidate1_actual_83_classes_unchanged': failed_classes,
        'actual_free_bytes': shutil.disk_usage(BASE).free,
        'this_task_shared_pristine_repo_pin_lock_or_failed_candidate_writes': False,
        'whole_installed_SDK_clean_or_publisher_authentication_claimed': False,
        'candidate_promoted': False, 'production_release_approval': False,
    }
    with (HERE / 'current-preservation-readback.json').open('x') as output:
        json.dump(result, output, indent=2, sort_keys=True)
        output.write('\n'); output.flush(); os.fsync(output.fileno())
    print(json.dumps({'preservation': result['status'], 'prior_unchanged_leaves': result['prior_unchanged_leaf_count'],
                      'owned_inputs': len(owned), 'selected_shared_sources': len(shared), 'pristine_originals': len(pristine)}))


if __name__ == '__main__':
    main()
