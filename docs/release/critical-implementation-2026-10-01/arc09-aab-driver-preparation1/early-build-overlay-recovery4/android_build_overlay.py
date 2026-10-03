"""Exact reviewed two-file APP overlay; archived native evidence stays historical."""
import hashlib
import json
from pathlib import Path

PATCH_PACKET_SHA256 = 'cc7fbb3d71e7b1edcf37b398948ab022dadd6948c14b52abfb7dd57e65e27445'
ORIGINAL_PINS_SHA256 = '771c21bd0a44953a4010bffd0eb0b7583ae91f98469143d66ed23982c324401e'
EXPECTED_FILES = {'android/build.gradle.kts', 'android/app/build.gradle.kts'}


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


def source_rows(value):
    return {name: {key: row[key] for key in ('sha256', 'bytes', 'mode')}
            for name, row in value.items()}


def strict_manifest(value):
    if (value.get('kind') != 'unapproved_collect_source_export'
            or value.get('retain_source_drift') is not False
            or value.get('capture_classification') != 'strict_unapproved_source_export'
            or value.get('approvals') != {name: False for name in
                ('trusted_source_verified', 'reviewed', 'frozen', 'owner_approved', 'signed',
                 'production_release_accepted')}):
        raise ValueError('strict unapproved APP manifest required')
    files = value['source_files']
    if (value.get('file_count') != len(files)
            or hashlib.sha256(canonical(files)).hexdigest() != value['source_manifest_sha256']):
        raise ValueError('complete APP source count/canonical hash differs')
    return files


def validate_manifest_overlay(archived, current, original_actual, export, delta):
    old, new = strict_manifest(archived), strict_manifest(current)
    if (archived['source_manifest_sha256'] != export['source_manifest_sha256']
            or old != source_rows(original_actual['source_files_exact'])):
        raise ValueError('archived manifest does not equal actual native/export8 source')
    changes = delta['two_file_changes']
    if set(changes) != EXPECTED_FILES or set(new) != set(old):
        raise ValueError('reviewed two-file source membership differs')
    differences = {name for name in old if old[name] != new[name]}
    if differences != EXPECTED_FILES:
        raise ValueError('current APP changes exceed or omit reviewed Android overlay')
    for name, row in changes.items():
        if old[name] != row['archived_before'] or new[name] != row['proposed_after']:
            raise ValueError('reviewed Android old/new SHA/bytes/mode differ')
    return {'archived_source_manifest_sha256': archived['source_manifest_sha256'],
            'current_APP_source_manifest_sha256': current['source_manifest_sha256'],
            'source_file_count': len(old), 'unchanged_source_rows': len(old) - len(changes),
            'exact_reviewed_android_changes': changes,
            'old_whole_APP_unchanged_claimed_for_current_source': False,
            'current_native_JVM_execution_claimed': False,
            'archived_native_XML_classes_and_unchanged_source_scoped_reuse': True,
            'production_release_approval': False}


def validate_pin_delta(original, current, root, delta):
    expected = dict(original)
    name = str(root / 'android/app/build.gradle.kts')
    if name not in expected or len(expected) != 42:
        raise ValueError('original42 prepared pin set differs')
    if expected[name] != delta['two_file_changes']['android/app/build.gradle.kts']['archived_before']:
        raise ValueError('old affected prepared pin differs from reviewed original')
    expected[name] = delta['two_file_changes']['android/app/build.gradle.kts']['proposed_after']
    if current != expected:
        raise ValueError('prepared42 pins have changes beyond the one originally present Android row')


def admit(driver, admission, records, export, pins):
    supplied = admission['android_build_overlay']
    if (set(supplied) != {'reviewed_patch_packet', 'archived_manifest', 'current_manifest',
                         'current_source_fence'}
            or admission.get('fresh_canonical_graphs_required') is not True
            or admission.get('native_whole_pass_applies_to_archived_export8_only') is not True
            or admission.get('current_native_whole_pass_claimed') is not False):
        raise ValueError('explicit reviewed overlay/current source and fresh graph admission required')
    patch = driver.RELEASE / 'arc09-early-build-root-preparation1'
    pin = supplied['reviewed_patch_packet']
    if pin != {'path': str(patch / 'packet-files.json'), 'sha256': PATCH_PACKET_SHA256}:
        raise ValueError('exact reviewed Android patch packet differs')
    packet = driver.document(pin['path'], pin['sha256'])
    if len(packet['files']) != 11: raise ValueError('reviewed Android patch leaf count differs')
    for name, row in packet['files'].items():
        if Path(name).is_absolute() or '..' in Path(name).parts:
            raise ValueError('unsafe reviewed patch leaf')
        body = driver.plain_read(patch / name, row['sha256'])
        if len(body) != row['bytes']: raise ValueError('reviewed patch byte count differs')
    delta = driver.document(patch / 'source-binding-delta.json', packet['files']['source-binding-delta.json']['sha256'])
    previous_pins = driver.document(driver.RELEASE / 'arc09-aab-driver-preparation1/argv-unavailable-recovery3/prepared-input-pins.json', ORIGINAL_PINS_SHA256)
    validate_pin_delta(previous_pins, pins, driver.ROOT, delta)
    old = supplied['archived_manifest']; new = supplied['current_manifest']
    if (new['path'] != str(driver.APP / '.collect-release-candidate.json')
            or old['sha256'] != export['export_manifest_file_sha256']
            or not Path(old['path']).is_relative_to(driver.RELEASE)):
        raise ValueError('preserved original/current APP manifest paths or historical hash differ')
    archived = driver.document(old['path'], old['sha256'])
    current = driver.document(new['path'], new['sha256'])
    result = validate_manifest_overlay(archived, current, records['APP_source'], export, delta)
    for name, row in delta['two_file_changes'].items():
        for root in (driver.ROOT, driver.APP):
            path = root / name; body = driver.plain_read(path, row['proposed_after']['sha256'])
            if len(body) != row['proposed_after']['bytes'] or path.stat().st_mode & 0o777 != row['proposed_after']['mode']:
                raise ValueError('current maintained/private reviewed Android bytes/mode differ')
    fence_pin = supplied['current_source_fence']
    if not Path(fence_pin['path']).is_relative_to(driver.RELEASE):
        raise ValueError('root-held current source fence required')
    fence = driver.document(fence_pin['path'], fence_pin['sha256'])
    if not driver.HEX.fullmatch(fence['source_manifest_sha256']):
        raise ValueError('current source fence manifest identity missing')
    plan = driver.document(patch / 'verification-plan.json', packet['files']['verification-plan.json']['sha256'])
    if plan['deadline_seconds'] != 300 or plan['cwd'] != str(driver.APP):
        raise ValueError('original bounded configuration readback plan differs')
    result.update(current_APP_manifest_pin=new, archived_APP_manifest_pin=old,
                  current_repository_source_fence_pin=fence_pin,
                  current_repository_source_manifest_sha256=fence['source_manifest_sha256'],
                  current_repository_source_count=len(fence['source_files_identity']),
                  reviewed_patch_packet=pin, native_evidence=admission['native_evidence'],
                  original_export8_binding_sha256='0bad50e24b58427074045c8db05dd1e0536bccf34fccf35d4939f5ff1610070c')
    return result, {'label': 'production-default-proguard-readback', 'argv': plan['argv'],
                    'cwd': plan['cwd'], 'deadline_seconds': plan['deadline_seconds']}


def validate_proguard_output(stdout, expected_app):
    prefix = 'COLLECT_DEFAULT_PROGUARD_READBACK='
    lines = [line[len(prefix):] for line in stdout.splitlines() if line.startswith(prefix)]
    if len(lines) != 1: raise ValueError('exactly one actual default Proguard readback required')
    row = json.loads(lines[0]); build = str(expected_app)
    if (row['kind'] != 'collect_default_proguard_directory_readback'
            or row['app_build_directory'] != build or row['configured_app_build_directory'] != build
            or row['producer_task'] != ':app:extractProguardFiles'
            or not all(row[k] is True for k in ('minify_enabled', 'shrink_resources', 'default_paths_and_producer_verified'))
            or row['r8_execution_verified'] is not False or row['package_or_release_acceptance'] is not False
            or not Path(row['default_proguard_file']).is_relative_to(expected_app)
            or not row['release_default_proguard_paths']
            or any(path != row['default_proguard_file'] for path in row['release_default_proguard_paths'])):
        raise ValueError('actual default Proguard path/producer/shrinking readback differs')
    return row
