#!/usr/bin/env python3
"""Retain genuine foundation receipts; reads only SDK/old packets, never tools."""
import datetime
import hashlib
import importlib.util
import json
import os
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
PREPARATION = RELEASE / 'kotlin-sdk-native-consumer-preparation1'
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
SDK = BASE / 'flutter'
CONTROL = BASE / '.control/foundation'
ADMISSION = RELEASE / 'root-sdk-native-consumer-preparation-review1/foundation-admission.json'
ADMISSION_SHA = '6c0a5990146965548066dad38137a44c99d44d61f1b0971909713178de590e3f'
PREPARATION_SHA = '9f08883dc0db884cee715d30e1c0efda31f5285d614aae0acc69da7418dc73bc'


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, sort_keys=True, indent=2); stream.write('\n')
        stream.flush(); os.fsync(stream.fileno())


def main():
    metadata_path = PREPARATION / 'publisher_metadata.py'
    if hashlib.sha256(metadata_path.read_bytes()).hexdigest() != 'c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25':
        raise ValueError('frozen regular reader differs')
    metadata = load(metadata_path, 'retained_foundation_reader')
    row, _ = metadata.stable_read(PREPARATION / 'run_native_consumer.py')
    if row['sha256'] != '33788a5bb25509b02e555f5411216c0849fc2590a4b8f6c22176a97bf7afbd86':
        raise ValueError('frozen controller differs')
    controller = load(PREPARATION / 'run_native_consumer.py', 'read_only_foundation_controller')
    controller.packet(PREPARATION, PREPARATION_SHA)
    controller.packet(RELEASE / 'kotlin-sdk-native-consumer-plan1', controller.PLAN_MANIFEST)
    controller.packet(RELEASE / 'kotlin-sdk-candidate2-execution-batch1', controller.COMPLETED_MANIFEST)
    retained = {}
    for name in ('start.json', 'exclusive-expansion-and-exact8.json',
                 'exclusive-expansion-and-exact8.stdout', 'exclusive-expansion-and-exact8.stderr',
                 'full-source-and-metadata.json', 'terminal.json'):
        path = CONTROL / name; row, body = metadata.stable_read(path, True)
        copy = HERE / ('actual-' + name)
        with copy.open('xb') as stream:
            stream.write(body); stream.flush(); os.fsync(stream.fileno())
        copied, _ = metadata.stable_read(copy)
        if copied['sha256'] != row['sha256'] or (copied['device'], copied['inode']) == (row['device'], row['inode']):
            raise ValueError('immutable receipt physical copy drift')
        retained[name] = {'source_path': str(path), 'source': row, 'copy_name': copy.name,
                          'copy_sha256': copied['sha256'], 'distinct_inode': True}
    row, body = metadata.stable_read(ADMISSION, True)
    if row['sha256'] != ADMISSION_SHA: raise ValueError('immutable foundation admission differs')
    with (HERE / 'actual-root-foundation-admission.json').open('xb') as stream:
        stream.write(body); stream.flush(); os.fsync(stream.fileno())
    terminal = json.loads((HERE / 'actual-terminal.json').read_text())
    command = json.loads((HERE / 'actual-exclusive-expansion-and-exact8.json').read_text())
    full = json.loads((HERE / 'actual-full-source-and-metadata.json').read_text())
    outer = json.loads((HERE / 'controller-terminal.json').read_text())
    if terminal.get('stage') != 'foundation' or terminal.get('stage_pass') is not True:
        raise ValueError('actual foundation stage did not pass; no acceptance')
    if (outer['controller_exit_code'] != 0 or command['exit_code'] != 0 or command['timed_out']
            or command['headroom_failure'] or command['residual_process_group_required_stop']
            or command['owned_process_group_absent'] is not True or command['deadline_seconds'] != 600):
        raise ValueError('actual producing process terminal proof failed')
    if (full['SDK_executed'] is not False or full['exact_cumulative8']['source_files_changed'] != 8
            or any(full[phase]['retained_publisher_members'] != 22415
                   or full[phase]['source_entries'] != 15660 or full[phase]['generated_output_manifest']
                   for phase in ('pristine', 'patched'))
            or full['pristine']['allowed_source_deltas'] or len(full['patched']['allowed_source_deltas']) != 8):
        raise ValueError('actual full source/publisher/delta boundary differs')
    eight = {}
    for name, expected in full['exact_cumulative8']['files'].items():
        actual, _ = metadata.stable_read(SDK / name)
        if actual['sha256'] != expected['after_sha256'] or actual['mode'] != expected['mode']:
            raise ValueError('actual current exact reviewed eight-byte/mode drift')
        eight[name] = actual
    four = metadata.validate_four_bytes(SDK)
    for name, actual in four.items():
        if actual != full['patched']['four_publisher_bootstrap_leaf_observations'][name]:
            raise ValueError('current publisher four-byte/time/physical observation drift')
        if actual['mtime_ns'] != metadata.timestamp_ns(metadata.FILES[name][0]):
            raise ValueError('actual publisher UTC interpretation differs')
    license_row, _ = metadata.stable_read(SDK / 'LICENSE')
    if license_row['sha256'] != 'a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20':
        raise ValueError('actual unchanged foundation license bytes drift')
    if (SDK / 'packages/flutter_tools/.dart_tool').exists() or (SDK / 'packages/flutter_tools/gradle/build').exists():
        raise ValueError('unexpected SDK tool/generated execution output materialized')
    protected = controller.protected_metadata()
    if protected != terminal['protected_after'] or protected['protected_metadata_paths_unchanged'] != 68020:
        raise ValueError('protected originals differ after foundation copy')
    report = {
        'observed_UTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status': 'GENUINE_NATIVE_CONSUMER_FOUNDATION_PASS_NO_SDK_EXECUTION',
        'producing_controller_actual_seconds': outer['actual_seconds'],
        'producing_owned_child_actual_seconds': command['actual_seconds'],
        'actual_expansion_elapsed_seconds': full['expansion']['elapsed_seconds'],
        'fixed_owned_stage_deadline_seconds': command['deadline_seconds'],
        'actual_immutable_receipt_copies': retained,
        'root_admission_SHA256': ADMISSION_SHA, 'preparation_manifest_SHA256': PREPARATION_SHA,
        'publisher_archive_SHA256': full['expansion']['archive_sha256'],
        'publisher_members_all_read': 22415, 'source_entries_all_read': 15660,
        'license_notice_paths_all_read': len(full['expansion']['full_independent_readback']['license_notice_paths']),
        'current_exact_reviewed_eight': eight, 'current_exact_four_metadata_leaves': four,
        'current_unchanged_SDK_license': license_row, 'protected_originals_actual_readback': protected,
        'current_internal_free_bytes': shutil.disk_usage(BASE).free,
        'new_SDK_root': str(SDK), 'runtime_and_generated_SDK_changes': {},
        'SDK_or_Dart_pub_startup_Gradle_app_execution': False,
        'publisher_timezone_attested': False, 'exact_DOS_UTC_interpretation_only': True,
        'next_stage': 'sdk-lock', 'next_stage_executed': False,
        'candidate_promoted': False, 'ARC09_closed': False, 'production_release_approval': False,
    }
    save(HERE / 'actual-foundation-assessment.json', report)
    config = json.loads((PREPARATION / 'proposed-commands.json').read_text())
    save(HERE / 'sdk-lock-next-proposal.json', {
        'scope': 'Next SDK-only enforced locked resolution proposed; not authorized or executed by this foundation proof.',
        'required_new_immutable_root_receipt': str(controller.receipt_path('sdk-lock')),
        'required_predecessor_terminal_sha256': retained['terminal.json']['copy_sha256'],
        'preparation_manifest_sha256': PREPARATION_SHA,
        'locked_resolution_command_exact': config['commands']['sdk-lock'],
        'source_readback_deadline_seconds': 300, 'live_floor_bytes': 4294967296,
        'SDK_lock_original_SHA256': metadata.FILES['packages/flutter_tools/pubspec.lock'][2],
        'actual_required_source_bytes': 'All retained publisher bytes +exact8; no cache binary/JSON override.',
        'owned_resolved_package_roots': [str(SDK), str(BASE / 'pub-cache')],
        'source_and_lock_bytes_must_remain_exact': True,
        'post_pub_lock_mtime_may_change_only_from_actual_enforced_pub': True,
        'sdk_lock_executed': False, 'startup_app_export_Gradle_native_authorized': False,
        'candidate_promoted': False, 'ARC09_closed': False, 'production_release_approval': False,
    })
    print(json.dumps({key: report[key] for key in ('status', 'producing_controller_actual_seconds',
        'producing_owned_child_actual_seconds', 'actual_expansion_elapsed_seconds',
        'publisher_members_all_read', 'source_entries_all_read', 'license_notice_paths_all_read',
        'current_internal_free_bytes', 'SDK_or_Dart_pub_startup_Gradle_app_execution')}, indent=2))


if __name__ == '__main__':
    main()
