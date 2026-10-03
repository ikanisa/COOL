#!/usr/bin/env python3
"""Copy genuine completed receipts and read owned bytes; never invoke SDK tools."""
import datetime
import hashlib
import importlib.util
import json
import os
import re
import shutil
import stat
import time
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
PREPARATION = RELEASE / 'kotlin-sdk-native-consumer-preparation1'
BASE = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1')
SDK = BASE / 'flutter'
CONTROL = BASE / '.control/sdk-lock'
ADMISSION = RELEASE / 'root-sdk-native-consumer-preparation-review1/sdk-lock-admission.json'
ADMISSION_SHA = 'f27501095ec77a819b9835dd9b9ee48c9034e3219745105bd3247b5b6ef44ff3'
PREPARATION_SHA = '9f08883dc0db884cee715d30e1c0efda31f5285d614aae0acc69da7418dc73bc'
FOUNDATION_SHA = 'c76d92111dd1f167022245add0c5e2f3949137c1965abd4972ecbb2aabaeb2b5'
PREDECESSOR_SHA = 'cd987c5c877f3d3e6867dd0c84ef6531e9611c5e81288e763ac61ccb675da9cf'


def load(path, name, expected):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError('frozen read-only helper differs')
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
    with destination.open('xb') as stream:
        stream.write(body); stream.flush(); os.fsync(stream.fileno())
    after, _ = reader.stable_read(destination)
    if (after['sha256'] != before['sha256']
            or (after['device'], after['inode']) == (before['device'], before['inode'])):
        raise ValueError('actual receipt copy drift/shared inode')
    return {'source_path': str(source), 'source': before,
            'copy_name': name, 'copy_sha256': after['sha256'], 'distinct_inode': True}


def inventory_cache(reader):
    root = BASE / 'pub-cache'; tick = time.monotonic()
    if root.resolve() != root: raise ValueError('owned pub cache alias')
    rows = {}; aliases = set(); total = 0; legal = []
    for parent, directories, files in os.walk(root, followlinks=False):
        for item in directories + files:
            if time.monotonic() - tick >= 300: raise ValueError('read-only cache inventory deadline')
            path = Path(parent) / item; name = path.relative_to(root).as_posix()
            if '\\' in name or any(ord(char) < 32 for char in name): raise ValueError('unsafe cache path')
            alias = unicodedata.normalize('NFC', name).casefold()
            if alias in aliases: raise ValueError('cache case/Unicode alias')
            aliases.add(alias)
            if len(aliases) > 200000: raise ValueError('cache inventory entry bound')
            current = path.lstat()
            if stat.S_ISDIR(current.st_mode):
                rows[name] = {'kind': 'directory', 'mode': stat.S_IMODE(current.st_mode)}
            elif stat.S_ISREG(current.st_mode):
                row, _ = reader.stable_read(path)
                total += row['bytes']
                if total > 4 * 1024**3: raise ValueError('cache inventory byte bound')
                rows[name] = dict(row, kind='regular')
                if re.search(r'(?i)(^|/)(license[^/]*|notice[^/]*|copying[^/]*)$', name): legal.append(name)
                if item.lower() == 'skill.md': raise ValueError('unexpected skill materialized by SDK pub resolution')
            else: raise ValueError('cache link/special file cannot be an exact consumer input')
    return {'root': str(root), 'entries': rows, 'regular_file_count': sum(r['kind'] == 'regular' for r in rows.values()),
            'directory_count': sum(r['kind'] == 'directory' for r in rows.values()), 'total_regular_bytes': total,
            'legal_notice_paths_observed': sorted(legal), 'actual_seconds': round(time.monotonic() - tick, 3),
            'scope': 'Actual fresh owned resolved package/cache bytes only. Local hosted-hash metadata is not independent publisher authentication or advisory/license approval.'}


def main():
    metadata = load(PREPARATION / 'publisher_metadata.py', 'sdk_lock_exact_reader',
                    'c21a475eae55b78997dbd944e6c97de1bd8e1df92f4f8696ede8ece198140b25')
    controller = load(PREPARATION / 'run_native_consumer.py', 'sdk_lock_read_only_controller',
                      '33788a5bb25509b02e555f5411216c0849fc2590a4b8f6c22176a97bf7afbd86')
    guards = load(PREPARATION / 'consumer_guards.py', 'sdk_lock_read_only_guards',
                  'f8ab32c78b0b499f8822b62ba79a8491effc67fad810187a22ac38d5ea2023aa')
    controller.packet(PREPARATION, PREPARATION_SHA)
    controller.packet(RELEASE / 'kotlin-sdk-native-consumer-foundation1', FOUNDATION_SHA)
    controller.packet(RELEASE / 'kotlin-sdk-native-consumer-plan1', controller.PLAN_MANIFEST)
    controller.packet(RELEASE / 'kotlin-sdk-candidate2-execution-batch1', controller.COMPLETED_MANIFEST)
    predecessor, _ = metadata.stable_read(BASE / '.control/foundation/terminal.json')
    if predecessor['sha256'] != PREDECESSOR_SHA: raise ValueError('actual admitted predecessor differs')
    admitted, _ = metadata.stable_read(ADMISSION)
    if admitted['sha256'] != ADMISSION_SHA: raise ValueError('immutable stage root admission differs')
    retained = {}
    for source in sorted(CONTROL.iterdir()):
        retained[source.name] = copy(metadata, source, 'actual-' + source.name)
    copy(metadata, ADMISSION, 'actual-root-sdk-lock-admission.json')
    terminal = guards.read_json(CONTROL / 'terminal.json')
    outer = guards.read_json(HERE / 'controller-terminal.json')
    command = guards.read_json(CONTROL / 'actual-command.json')
    config = guards.read_json(PREPARATION / 'proposed-commands.json')
    if (outer['controller_exit_code'] != 0 or terminal.get('stage_pass') is not True
            or terminal.get('stage') != 'sdk-lock'):
        raise ValueError('actual SDK locked resolution failed; preserve failure rather than accepting')
    guards.process_success(command)
    if (command['argv'] != config['commands']['sdk-lock']['argv']
            or command['cwd'] != config['commands']['sdk-lock']['cwd'] or command['deadline_seconds'] != 1200):
        raise ValueError('actual enforced locked command scope differs')
    guards.forbid_upgrade_branch((CONTROL / 'actual-command.stdout').read_text(),
                                (CONTROL / 'actual-command.stderr').read_text())
    sources = {}
    for phase in ('patched', 'sdk-locked'):
        process = guards.read_json(CONTROL / ('SDK-readback-' + phase + '.json'))
        guards.process_success(process)
        if process['deadline_seconds'] != 300: raise ValueError('actual source readback deadline differs')
        source = guards.read_json(CONTROL / ('SDK-source-' + phase + '.json'))
        if (source['phase'] != phase or source['source_entries'] != 15660
                or source['retained_publisher_members'] != 22415
                or len(source['allowed_source_deltas']) != 8 or source['SDK_executed_by_verifier'] is not False):
            raise ValueError('actual full source/allowed8 readback differs')
        sources[phase] = source
    if sources['patched']['generated_output_manifest']: raise ValueError('before pub SDK already generated')
    allowed_generated = {'flutter/packages/flutter_tools/.dart_tool',
                         'flutter/packages/flutter_tools/.dart_tool/package_config.json',
                         'flutter/packages/flutter_tools/.dart_tool/package_graph.json'}
    generated = sources['sdk-locked']['generated_output_manifest']
    if set(generated) != allowed_generated: raise ValueError('actual SDK generated files differ from retained successful observation')
    for name, row in generated.items():
        path = SDK / name.removeprefix('flutter/')
        if row['kind'] == 'regular':
            current, _ = metadata.stable_read(path)
            if (current['sha256'], current['bytes'], current['mode']) != (row['sha256'], row['bytes'], row['mode']):
                raise ValueError('actual generated SDK metadata drift')
            copy(metadata, path, 'actual-generated-' + path.name)
    current_eight = {}
    for name in sources['sdk-locked']['allowed_source_deltas']:
        current, _ = metadata.stable_read(SDK / name)
        expected = sources['sdk-locked']['retained_physical_manifest']['flutter/' + name]
        if (current['sha256'], current['bytes'], current['mode']) != (expected['sha256'], expected['bytes'], expected['mode']):
            raise ValueError('actual current reviewed eight-byte/mode drift')
        current_eight[name] = current
    four = metadata.validate_four_bytes(SDK)
    if four != sources['sdk-locked']['four_publisher_bootstrap_leaf_observations']:
        raise ValueError('four source/lock/binary/stamp identities drift since actual readback')
    lock = guards.require_lock(SDK / 'packages/flutter_tools/pubspec.lock', guards.SDK_LOCK)
    copy(metadata, SDK / 'packages/flutter_tools/pubspec.lock', 'actual-SDK-pubspec.lock')
    resolved = guards.package_config(SDK / 'packages/flutter_tools/.dart_tool/package_config.json', (SDK, BASE / 'pub-cache'))
    if resolved != guards.read_json(CONTROL / 'resolved-SDK-packages.json'): raise ValueError('actual resolved SDK packages drift')
    license_row, _ = metadata.stable_read(SDK / 'LICENSE')
    if license_row['sha256'] != 'a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20':
        raise ValueError('SDK unchanged license drift')
    protected = controller.protected_metadata()
    if protected != terminal['protected_after'] or protected['protected_metadata_paths_unchanged'] != 68020:
        raise ValueError('actual protected originals drift')
    if any((BASE / '.control' / stage).exists() for stage in ('startup', 'app-export', 'app-lock', 'native')):
        raise ValueError('unexpected advancement beyond SDK lock stage')
    cache = inventory_cache(metadata)
    save('actual-owned-pub-cache-manifest.json', cache)
    report = {
        'observed_UTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'status': 'GENUINE_ENFORCED_SDK_LOCK_PASS_NO_STARTUP_APP_OR_NATIVE',
        'actual_controller_seconds': outer['actual_seconds'], 'actual_enforced_pub_seconds': command['actual_seconds'],
        'actual_process_deadline_seconds': 1200, 'actual_source_readback_deadline_seconds': 300,
        'actual_immutable_receipt_copies': retained, 'root_admission_SHA256': ADMISSION_SHA,
        'preparation_manifest_SHA256': PREPARATION_SHA, 'actual_predecessor_SHA256': PREDECESSOR_SHA,
        'actual_current_terminal_SHA256': retained['terminal.json']['copy_sha256'],
        'full_before_after_publisher_member_count': 22415, 'full_before_after_official_source_count': 15660,
        'current_reviewed_source_eight': current_eight, 'SDK_generated_changes_separate': generated,
        'current_exact_four_metadata_leaves': four, 'SDK_original_lock_exact': lock,
        'current_unchanged_SDK_license': license_row, 'current_resolved_packages_count': len(resolved['packages']),
        'resolved_only_exact_owned_roots': resolved['only_exact_owned_bindings'],
        'owned_pub_cache_regular_files': cache['regular_file_count'], 'owned_pub_cache_bytes': cache['total_regular_bytes'],
        'owned_pub_cache_legal_notice_paths': len(cache['legal_notice_paths_observed']),
        'local_pub_cache_is_independent_publisher_advisory_license_acceptance': False,
        'protected_originals_actual_readback': protected, 'current_internal_free_bytes': shutil.disk_usage(BASE).free,
        'Dart_pub_executed': True, 'Flutter_startup_app_export_app_resolution_Gradle_native_executed': False,
        'publisher_timezone_attested': False, 'exact_DOS_UTC_interpretation_only': True,
        'candidate_promoted': False, 'ARC09_closed': False, 'production_release_approval': False,
    }
    save('actual-sdk-lock-assessment.json', report)
    save('startup-next-proposal.json', {
        'scope': 'Next unchanged private SDK version startup only proposed; not executed by this locked-resolution proof.',
        'required_new_immutable_root_receipt': str(controller.receipt_path('startup')),
        'required_predecessor_terminal_sha256': retained['terminal.json']['copy_sha256'],
        'preparation_manifest_sha256': PREPARATION_SHA, 'exact_startup_command': config['commands']['startup'],
        'source_readback_deadline_seconds': 300, 'live_floor_bytes': 4294967296,
        'exact_original_SDK_lock_SHA256': guards.SDK_LOCK, 'forbid_upgrade_bootstrap_branch': True,
        'all_publisher_source_binary_JSON_and_exact8_bytes_must_remain_unchanged': True,
        'resolved_packages_only_owned_roots': [str(SDK), str(BASE / 'pub-cache')],
        'new_source_or_binary_cache_exceptions_admitted': False, 'startup_executed': False,
        'app_export_app_resolution_Gradle_native_authorized': False,
        'candidate_promoted': False, 'ARC09_closed': False, 'production_release_approval': False,
    })
    print(json.dumps({key: report[key] for key in ('status', 'actual_controller_seconds',
        'actual_enforced_pub_seconds', 'current_resolved_packages_count', 'owned_pub_cache_regular_files',
        'owned_pub_cache_bytes', 'owned_pub_cache_legal_notice_paths', 'actual_current_terminal_SHA256')}, indent=2))


if __name__ == '__main__':
    main()
