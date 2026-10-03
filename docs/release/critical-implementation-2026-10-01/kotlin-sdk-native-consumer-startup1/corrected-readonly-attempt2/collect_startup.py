#!/usr/bin/env python3
"""Retain actual startup receipts and read source; no SDK/tool invocation."""
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
CONTROL = BASE / '.control/startup'
ADMISSION = RELEASE / 'root-sdk-native-consumer-preparation-review1/startup-admission.json'
ADMISSION_SHA = '062361abe65088d82a85581ca3fabfad14f7620d21093c81ebe4a43e6d4613b8'
PREPARATION_SHA = '9f08883dc0db884cee715d30e1c0efda31f5285d614aae0acc69da7418dc73bc'
SDK_LOCK_PACKET_SHA = '8c59acde48be61ff7bc98e28eb09565e13a4cddd10f4cdd96ea4a6ffb9ac8f44'
PREDECESSOR_SHA = '04a61fe35f8e836e5bd8ca483408350856786fc5bca58f085bf1580e4b6fc92e'


def load(path, name, expected):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected: raise ValueError('frozen helper differs')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def save(name, value):
    with (HERE / name).open('x') as stream:
        json.dump(value, stream, sort_keys=True, indent=2); stream.write('\n')
        stream.flush(); os.fsync(stream.fileno())


def copy(reader, source, name):
    before, body = reader.stable_read(source, True)
    destination = HERE / name
    # The failed read-only first collector retained actual receipt copies.
    # Reuse only their exact bytes after a fresh fenced read; never overwrite.
    if not destination.exists():
        with destination.open('xb') as stream:
            stream.write(body); stream.flush(); os.fsync(stream.fileno())
    after, _ = reader.stable_read(destination)
    if (after['sha256'] != before['sha256']
            or (after['device'], after['inode']) == (before['device'], before['inode'])):
        raise ValueError('actual receipt copy drift/shared inode')
    return {'source_path': str(source), 'source': before, 'copy_name': name,
            'copy_sha256': after['sha256'], 'distinct_inode': True}


def main():
    metadata = load(PREPARATION / 'publisher_metadata.py', 'startup_exact_reader',
                    'c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25')
    controller = load(PREPARATION / 'run_native_consumer.py', 'startup_read_only_controller',
                      '33788a5bb25509b02e555f5411216c0849fc2590a4b8f6c22176a97bf7afbd86')
    guards = load(PREPARATION / 'consumer_guards.py', 'startup_read_only_guards',
                  'f8ab32c78b0b499f8822b62ba79a8491effc67fad810187a22ac38d5ea2023aa')
    controller.packet(PREPARATION, PREPARATION_SHA)
    controller.packet(RELEASE / 'kotlin-sdk-native-consumer-sdk-lock1', SDK_LOCK_PACKET_SHA)
    controller.packet(RELEASE / 'kotlin-sdk-native-consumer-plan1', controller.PLAN_MANIFEST)
    controller.packet(RELEASE / 'kotlin-sdk-candidate2-execution-batch1', controller.COMPLETED_MANIFEST)
    predecessor, _ = metadata.stable_read(BASE / '.control/sdk-lock/terminal.json')
    if predecessor['sha256'] != PREDECESSOR_SHA: raise ValueError('actual reviewed predecessor differs')
    admitted, _ = metadata.stable_read(ADMISSION)
    if admitted['sha256'] != ADMISSION_SHA: raise ValueError('immutable stage admission differs')
    retained = {source.name: copy(metadata, source, 'actual-' + source.name)
                for source in sorted(CONTROL.iterdir())}
    copy(metadata, ADMISSION, 'actual-root-startup-admission.json')
    terminal = guards.read_json(CONTROL / 'terminal.json')
    outer = guards.read_json(HERE / 'controller-terminal.json')
    command = guards.read_json(CONTROL / 'actual-command.json')
    config = guards.read_json(PREPARATION / 'proposed-commands.json')
    if (outer['controller_exit_code'] != 0 or terminal.get('stage_pass') is not True
            or terminal.get('stage') != 'startup'):
        raise ValueError('actual startup failed; no success acceptance')
    guards.process_success(command)
    if (command['argv'] != config['commands']['startup']['argv']
            or command['cwd'] != config['commands']['startup']['cwd'] or command['deadline_seconds'] != 300):
        raise ValueError('actual unchanged startup command differs')
    version = guards.startup_version((CONTROL / 'actual-command.stdout').read_text(),
                                    (CONTROL / 'actual-command.stderr').read_text())
    if version != guards.read_json(CONTROL / 'actual-version.json'): raise ValueError('actual parsed version receipt differs')
    sources = {}
    for phase in ('sdk-locked', 'startup'):
        process = guards.read_json(CONTROL / ('SDK-readback-' + phase + '.json'))
        guards.process_success(process)
        if process['deadline_seconds'] != 300: raise ValueError('source readback deadline differs')
        source = guards.read_json(CONTROL / ('SDK-source-' + phase + '.json'))
        if (source['phase'] != phase or source['source_entries'] != 15660
                or source['retained_publisher_members'] != 22415
                or len(source['allowed_source_deltas']) != 8 or source['SDK_executed_by_verifier'] is not False):
            raise ValueError('actual full source/allowed8 readback differs')
        sources[phase] = source
    before = sources['sdk-locked']['retained_physical_manifest']
    after = sources['startup']['retained_physical_manifest']
    differences = {name: {'before': before.get(name), 'after': after.get(name)}
                   for name in sorted(set(before) | set(after)) if before.get(name) != after.get(name)}
    # The unchanged publisher updater atomically replaces engine.stamp on startup.
    # This is an observed inode replacement, never a source/binary byte exception.
    stamp = 'flutter/bin/cache/engine.stamp'
    if set(differences) != {stamp}: raise ValueError('unexpected startup physical identity change')
    stamp_before = dict(differences[stamp]['before']); stamp_after = dict(differences[stamp]['after'])
    if (stamp_before.pop('inode') != 58771407 or stamp_after.pop('inode') != 58897783
            or stamp_before != stamp_after or stamp_after['bytes'] != 41
            or stamp_after['sha256'] != '244f6cdbfc0fbba9c7a913c5cfcba4ffd92dfae5f57d3aee527461775cec2066'
            or stamp_after['mode'] != 420 or stamp_after['nlink'] != 1):
        raise ValueError('actual updater stamp replacement has source/byte/mode/link drift')
    updater = SDK / 'bin/internal/update_engine_version.sh'
    updater_row, updater_body = metadata.stable_read(updater, True)
    if updater_row['sha256'] != after['flutter/bin/internal/update_engine_version.sh']['sha256']:
        raise ValueError('publisher updater source differs from actual complete source proof')
    expected_statement = b'echo "$ENGINE_VERSION" >"$es_tmp" && mv "$es_tmp" "$FLUTTER_ROOT/bin/cache/engine.stamp"'
    if expected_statement not in updater_body: raise ValueError('actual publisher atomic-stamp statement differs')
    current_stamp, _ = metadata.stable_read(SDK / 'bin/cache/engine.stamp')
    if (current_stamp['sha256'], current_stamp['inode']) != (stamp_after['sha256'], 58897783):
        raise ValueError('observed current stamp replacement drift')
    save('actual-publisher-stamp-inode-replacement.json', {
        'scope': 'Actual one named owned inode replacement only; no source/binary byte or mode exception.',
        'before_after_difference': differences, 'current_stable_stamp': current_stamp,
        'exact_publisher_updater_source': updater_row,
        'authenticated_commit': 'ad70ec4617166f1c38e5d2bfd388af71fda14f06',
        'publisher_updater_source_lines': [67, 69, 71],
        'unchanged_source_statement': expected_statement.decode(),
        'core_source_validator_or_execution_authorization_changed': False,
    })
    if sources['startup']['generated_output_manifest'] != sources['sdk-locked']['generated_output_manifest']:
        raise ValueError('SDK generated files changed during version startup')
    eight = {}
    for name in sources['startup']['allowed_source_deltas']:
        current, _ = metadata.stable_read(SDK / name)
        expected = sources['startup']['retained_physical_manifest']['flutter/' + name]
        if (current['sha256'], current['bytes'], current['mode']) != (expected['sha256'], expected['bytes'], expected['mode']):
            raise ValueError('current reviewed eight source bytes/modes drift')
        eight[name] = current
    four = metadata.validate_four_bytes(SDK)
    if four != sources['startup']['four_publisher_bootstrap_leaf_observations']:
        raise ValueError('current four source/lock/binary/stamp observations differ')
    lock = guards.require_lock(SDK / 'packages/flutter_tools/pubspec.lock', guards.SDK_LOCK)
    packages = guards.package_config(SDK / 'packages/flutter_tools/.dart_tool/package_config.json', (SDK, BASE / 'pub-cache'))
    if packages != guards.read_json(BASE / '.control/sdk-lock/resolved-SDK-packages.json'):
        raise ValueError('current owned package roots differ from actual locked resolution')
    save('actual-current-SDK-packages.json', packages)
    license_row, _ = metadata.stable_read(SDK / 'LICENSE')
    if license_row['sha256'] != 'a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20':
        raise ValueError('unchanged SDK license differs')
    protected = controller.protected_metadata()
    if protected != terminal['protected_after'] or protected['protected_metadata_paths_unchanged'] != 68020:
        raise ValueError('protected original metadata differs')
    if any((BASE / '.control' / stage).exists() for stage in ('app-export', 'app-lock', 'native')):
        raise ValueError('unexpected app/export/native advancement')
    report = {
        'observed_UTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status': 'GENUINE_UNCHANGED_PRIVATE_SDK_VERSION_STARTUP_PASS_NO_APP_OR_NATIVE',
        'actual_controller_seconds': outer['actual_seconds'], 'actual_startup_seconds': command['actual_seconds'],
        'runtime_source_readback_deadlines_seconds': 300, 'actual_immutable_receipt_copies': retained,
        'root_admission_SHA256': ADMISSION_SHA, 'preparation_manifest_SHA256': PREPARATION_SHA,
        'actual_predecessor_SHA256': PREDECESSOR_SHA,
        'actual_current_terminal_SHA256': retained['terminal.json']['copy_sha256'],
        'actual_stdout_version': version, 'actual_before_after_publisher_member_count': 22415,
        'actual_before_after_official_source_count': 15660, 'retained_publisher_bytes_modes_exact': True,
        'owned_engine_stamp_same_bytes_inode_replacement': differences,
        'current_reviewed_source_eight': eight, 'before_after_generated_manifest_unchanged': True,
        'generated_SDK_manifest_separate': sources['startup']['generated_output_manifest'],
        'current_exact_four_metadata_leaves': four, 'current_original_SDK_lock_exact': lock,
        'current_resolved_packages_count': len(packages['packages']), 'resolved_only_exact_owned_roots': True,
        'current_unchanged_SDK_license': license_row, 'protected_originals_actual_readback': protected,
        'current_internal_free_bytes': shutil.disk_usage(BASE).free,
        'Flutter_version_startup_executed': True, 'SDK_upgrade_bootstrap_branch_observed': False,
        'app_export_resolution_Gradle_native_executed': False,
        'current_app_source_hold_or_export_authorization_established_by_this_stage': False,
        'candidate_promoted': False, 'ARC09_closed': False, 'production_release_approval': False,
    }
    save('actual-startup-assessment.json', report)
    save('app-export-next-proposal.json', {
        'scope': 'Next strict source export only proposed; requires separately coordinated current source and independent immutable root receipt.',
        'required_new_immutable_root_receipt': str(controller.receipt_path('app-export')),
        'required_predecessor_terminal_sha256': retained['terminal.json']['copy_sha256'],
        'preparation_manifest_sha256': PREPARATION_SHA, 'exact_export_command': config['commands']['app-export'],
        'reviewed_exporter_SHA256': config['reviewed_exporter_SHA256'],
        'source_readback_deadline_seconds': 300, 'live_floor_bytes': 4294967296,
        'current_source_export_authorized': False, 'source_scope_held_for_strict_export': False,
        'strict_export_only_no_retain_drift': True, 'no_dated_discovery_hashes_substitute_for_actual_export': True,
        'exporter_must_not_execute_Flutter_and_must_retain_unapproved_source_binding': True,
        'SDK_or_shared_selection_app_resolution_Gradle_native_authorized': False,
        'candidate_promoted': False, 'ARC09_closed': False, 'production_release_approval': False,
    })
    print(json.dumps({key: report[key] for key in ('status', 'actual_controller_seconds',
        'actual_startup_seconds', 'actual_stdout_version', 'current_resolved_packages_count',
        'actual_current_terminal_SHA256')}, indent=2))


if __name__ == '__main__':
    main()
