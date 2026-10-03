"""Exact reviewed candidate3 APP overlay; archived native evidence stays historical."""
import hashlib
import json
from pathlib import Path
import re

PATCH_PACKET_SHA256 = '35347d9bda9447d2e9467d15962ce3efde8446c3748e5ddbdfa87bc1dae9e30c'
ORIGINAL_PINS_SHA256 = '771c21bd0a44953a4010bffd0eb0b7583ae91f98469143d66ed23982c324401e'
EXPECTED_FILES = {'android/build.gradle.kts', 'android/app/build.gradle.kts', 'android/settings.gradle.kts'}
_R8_EXPECTED = None
PUBLISHER_JAR_SHA256 = '9a7d1e9e4c2d3ee05482b9695df5f4d8f92c22ebb74603d6be4eab0505467f1a'
PUBLISHER_RECEIPT_SHA256 = '401f7a88d479e7c9014990b7a5c312bfc5cd4790aae2539a70bd34a592b49c9d'
ARTIFACT_URL = 'https://storage.googleapis.com/r8-releases/raw/com/android/tools/r8/9.1.29/r8-9.1.29.jar'

PROBE_RECOVERY_RELATIVE = 'arc09-r8-9.1.29-preparation1'
PROBE_RECOVERY_PLAN_SHA256 = '333d7480f7aa44cad4baf060551eec519058df4448e605f8ed891098b38da6d9'
PROBE_RECOVERY_INIT_SHA256 = '1e1074529e1d8ca993a1466c41daf6722dc9f2d0b810d3d38b286434022327fe'


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
    changes = delta['three_file_changes']
    if set(changes) != EXPECTED_FILES or set(new) != set(old):
        raise ValueError('reviewed candidate3 source membership differs')
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
    if expected[name] != delta['three_file_changes']['android/app/build.gradle.kts']['archived_before']:
        raise ValueError('old affected prepared pin differs from reviewed original')
    expected[name] = delta['three_file_changes']['android/app/build.gradle.kts']['proposed_after']
    if current != expected:
        raise ValueError('prepared42 pins have changes beyond the one originally present Android row')


def validate_probe_override(driver, supplied, original_plan):
    """Allow one root-selected pinned init correction; every other plan field stays exact."""
    if supplied is None:
        raise ValueError('candidate3 requires the exact root-selected R8 readback init')
    recovery = driver.RELEASE / PROBE_RECOVERY_RELATIVE
    expected = {
        'plan': {'path': str(recovery / 'reviewed-verification-plan.json'),
                 'sha256': PROBE_RECOVERY_PLAN_SHA256},
        'init_script': {'path': str(recovery / 'verify-default-proguard-and-r8.init.gradle'),
                        'sha256': PROBE_RECOVERY_INIT_SHA256},
    }
    if supplied != expected:
        raise ValueError('exact root-selected default ProGuard probe override pins differ')
    replacement = driver.document(expected['plan']['path'], expected['plan']['sha256'])
    driver.plain_read(expected['init_script']['path'], expected['init_script']['sha256'])
    old_argv = original_plan['argv']; new_argv = replacement['argv']
    if old_argv.count('--init-script') != 1 or new_argv.count('--init-script') != 1:
        raise ValueError('exactly one original/replacement init-script argument required')
    index = old_argv.index('--init-script') + 1
    if (index >= len(old_argv) or index >= len(new_argv)
            or old_argv[index] != str(driver.RELEASE / 'arc09-early-build-root-preparation1/verify-default-proguard.init.gradle')):
        raise ValueError('original reviewed default ProGuard init-script path differs')
    expected_argv = list(old_argv); expected_argv[index] = expected['init_script']['path']
    if new_argv != expected_argv:
        raise ValueError('probe override changes an argument beyond the pinned init-script path')
    if (replacement['deadline_seconds'] != 300 or replacement['cwd'] != str(driver.APP)
            or replacement['required_environment_values'] != original_plan['required_environment_values']
            or replacement['preserve_prior_controlled_environment'] is not True
            or replacement['expected_task_scope'] != original_plan['expected_task_scope']):
        raise ValueError('probe override changes original metadata, cwd or finite bound')
    return replacement


def admit(driver, admission, records, export, pins):
    supplied = admission['android_build_overlay']
    if (set(supplied) != {'reviewed_patch_packet', 'archived_manifest', 'current_manifest',
                         'current_source_fence'}
            or admission.get('fresh_canonical_graphs_required') is not True
            or admission.get('native_whole_pass_applies_to_archived_export8_only') is not True
            or admission.get('current_native_whole_pass_claimed') is not False):
        raise ValueError('explicit reviewed overlay/current source and fresh graph admission required')
    patch = driver.RELEASE / 'arc09-r8-9.1.29-preparation1'
    pin = supplied['reviewed_patch_packet']
    if pin != {'path': str(patch / 'candidate3-patch-packet.json'), 'sha256': PATCH_PACKET_SHA256}:
        raise ValueError('exact reviewed Android patch packet differs')
    packet = driver.document(pin['path'], pin['sha256'])
    if len(packet['files']) != 5: raise ValueError('reviewed Android patch leaf count differs')
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
    for name, row in delta['three_file_changes'].items():
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
    original_patch = driver.RELEASE / 'arc09-early-build-root-preparation1'
    original_packet = driver.document(original_patch / 'packet-files.json', 'cc7fbb3d71e7b1edcf37b398948ab022dadd6948c14b52abfb7dd57e65e27445')
    plan = driver.document(original_patch / 'verification-plan.json', original_packet['files']['verification-plan.json']['sha256'])
    if plan['deadline_seconds'] != 300 or plan['cwd'] != str(driver.APP):
        raise ValueError('original bounded configuration readback plan differs')
    plan = validate_probe_override(driver, admission.get('default_proguard_probe_override'), plan)
    global _R8_EXPECTED
    _R8_EXPECTED = admit_r8_artifact(driver, admission['r8_artifact_admission'])
    result.update(r8_artifact_admission=admission['r8_artifact_admission'], current_APP_manifest_pin=new, archived_APP_manifest_pin=old,
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
    if _R8_EXPECTED is None: raise ValueError('root R8 artifact admission was not established')
    validate_r8_readback(row['actual_R8_compiler_readback'], _R8_EXPECTED, expected_app.parent.parent / 'gradle-home')
    return row


def validate_r8_artifact(value):
    """Admit acquired immutable bytes, never the unfilled preparation template."""
    jar = value['jar']; acquisition = value['actual_acquisition']
    if (value['kind'] != 'root_selected_exact_r8_artifact_admission'
            or value['coordinate'] != 'com.android.tools:r8:9.1.29'
            or value['version'] != '9.1.29' or value['publisher_url'] != ARTIFACT_URL
            or value['publisher_content_length'] != 56139715
            or value['publisher_generation'] != '1770813549786388'
            or value['publisher_md5_hex'] != '60e153b8c1dba4d97e9b1ef2d75c2e61'
            or value['publisher_crc32c_base64'] != 'wwtxyA=='
            or not isinstance(jar['path'], str) or not Path(jar['path']).is_absolute()
            or jar['sha256'] != PUBLISHER_JAR_SHA256
            or jar['bytes'] != 56139715 or jar['md5_hex'] != value['publisher_md5_hex']
            or acquisition['observed'] is not True or acquisition['HTTP_code'] != 200
            or acquisition['TLS_verify_result'] != 0 or acquisition['effective_url'] != ARTIFACT_URL
            or acquisition['deadline_seconds'] != 120 or acquisition['maximum_bytes'] != 60000000
            or value['production_release_approval'] is not False):
        raise ValueError('exact acquired official R8 9.1.29 artifact admission differs')
    if not isinstance(value['root_pinned_transformed_providers'], list):
        raise ValueError('explicit root-pinned transformed provider list required')
    for provider in value['root_pinned_transformed_providers']:
        if (set(provider) != {'path', 'sha256', 'bytes', 'source_artifact_sha256', 'provenance_receipt'}
                or provider['source_artifact_sha256'] != jar['sha256']
                or not re.fullmatch('[0-9a-f]{64}', provider['sha256'])
                or provider['bytes'] <= 0 or not Path(provider['path']).is_absolute()):
            raise ValueError('transformed compiler provider lacks exact source/artifact binding')
    return value


def admit_r8_artifact(driver, pin):
    expected_path = driver.RELEASE / 'root-arc09-r8-integration1/r8-artifact-admission.json'
    if (set(pin) != {'path', 'sha256'} or pin['path'] != str(expected_path)
            or not driver.HEX.fullmatch(pin['sha256'])):
        raise ValueError('exact root-held R8 artifact admission pin required')
    value = validate_r8_artifact(driver.document(pin['path'], pin['sha256']))
    publisher_pin = value['publisher_acquisition_readback']
    publisher_path = driver.RELEASE / 'root-r8-9.1.29-publisher-acquisition1/readback.json'
    if publisher_pin != {'path': str(publisher_path), 'sha256': PUBLISHER_RECEIPT_SHA256}:
        raise ValueError('actual root publisher acquisition readback pin differs')
    publisher = driver.document(publisher_pin['path'], publisher_pin['sha256'])
    if (publisher['status'] != 'PASS' or publisher['sha256'] != PUBLISHER_JAR_SHA256
            or publisher['path'] != value['jar']['path'] or publisher['bytes'] != value['jar']['bytes']
            or publisher['HTTP_code'] != 200 or publisher['TLS_verify_result'] != 0
            or publisher['effective_URL'] != ARTIFACT_URL or publisher['publisher_md5'] != value['jar']['md5_hex']):
        raise ValueError('actual root publisher artifact receipt differs')
    raw = driver.plain_read(value['jar']['path'], value['jar']['sha256'], 60000000)
    if len(raw) != value['jar']['bytes'] or hashlib.md5(raw).hexdigest() != value['jar']['md5_hex']:
        raise ValueError('actual admitted R8 JAR differs from publisher size/MD5')
    for provider in value['root_pinned_transformed_providers']:
        body = driver.plain_read(provider['path'], provider['sha256'], 128 * 1024**2)
        if len(body) != provider['bytes']: raise ValueError('transformed R8 provider byte count differs')
        receipt = provider['provenance_receipt']
        if not Path(receipt['path']).is_relative_to(driver.RELEASE):
            raise ValueError('root-held actual compiler provider provenance required')
        observed = driver.document(receipt['path'], receipt['sha256'])
        if (observed.get('kind') != 'actual_gradle_r8_instrumentation_provider'
                or observed.get('observed') is not True
                or observed.get('source_artifact_sha256') != value['jar']['sha256']
                or observed.get('provider') != {k: provider[k] for k in ('path', 'sha256', 'bytes')}):
            raise ValueError('actual transformed R8 provider provenance differs')
    return value


def validate_r8_readback(row, admitted, gradle_home):
    value = validate_r8_artifact(admitted)
    artifact = row['resolved_artifact']; provider = row['provider']
    if (row['coordinate'] != value['coordinate'] or row['version'] != '9.1.29'
            or row['tool_class'] != 'com.android.builder.dexing.R8Tool'
            or row['R8_class'] != 'com.android.tools.r8.R8'
            or row['invoked_declaring_class'] != 'com.android.tools.r8.R8'
            or row['invoked_method_name'] != 'main' or row['invoked_modifiers'] != 9
            or row['invoked_return_type'] != 'void' or row['invoked_parameter_types'] != ['[Ljava.lang.String;']
            or row['invoked_arguments'] != ['--version'] or row['version_method_invoked'] is not True
            or row['R8_selected_from_AGP_tool_classloader'] is not True
            or not all(row.get(k) for k in ('tool_classloader', 'tool_classloader_identity', 'R8_classloader', 'R8_classloader_identity'))
            or len(re.findall(r'(?m)^R8 9\.1\.29(?:\s|$)', row['version_stdout'])) != 1
            or row['app_compilation_executed_by_this_task'] is not False
            or not Path(artifact['path']).is_relative_to(gradle_home)
            or artifact['sha256'] != value['jar']['sha256'] or artifact['bytes'] != value['jar']['bytes']
            or artifact['md5_hex'] != value['jar']['md5_hex']
            or not Path(provider['path']).is_relative_to(gradle_home)):
        raise ValueError('actual AGP R8 classloader/version/invocation/artifact readback differs')
    raw = provider['sha256'] == value['jar']['sha256'] and provider['bytes'] == value['jar']['bytes']
    transformed = any(provider == {k: p[k] for k in ('path', 'sha256', 'bytes')}
                      for p in value['root_pinned_transformed_providers'])
    if not raw and not transformed:
        raise ValueError('actual R8 classloader uses an unknown or unadmitted compiler provider')
    return row
