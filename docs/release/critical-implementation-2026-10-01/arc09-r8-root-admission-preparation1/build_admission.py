#!/usr/bin/env python3
"""Assemble root admission from exact observed pins; source/cache/build writes forbidden."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import types

HERE = Path(__file__).resolve().parent
RELEASE = HERE.parent
ROOT = RELEASE.parents[2]
R8 = RELEASE / 'arc09-r8-9.1.29-preparation1'
INTEGRATION = RELEASE / 'root-arc09-r8-integration1'
APP = Path('/Users/jeanbosco/Library/Caches/COOL-ARC09/native-consumer1/app-source')
TEMPLATE_SHA256 = '6d9e476ff812b95d79c9248d76f8f7c7d1006b8078447eb4dc421d06d532bbd3'
DRIVER_SHA256 = '6aec0de17f91f3981d2def8be12cc7f0f10eba40fca6c17ffea6f11166a893fc'
HELPER_SHA256 = '00ce52587ca4d43a617e9960f5935e04323fd0d9f1ef1fc85c12d3d2ede6472d'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-fence-sha256', required=True)
    parser.add_argument('--APP-manifest-sha256', required=True)
    parser.add_argument('--settings-overlay-readback-sha256', required=True)
    parser.add_argument('--aggregate-readback-sha256', required=True)
    parser.add_argument('--r8-artifact-admission-sha256', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--aab-output', type=Path)
    args = parser.parse_args()
    path = R8 / 'driver/run_selected_aab.py'
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != DRIVER_SHA256: raise ValueError('unchanged reviewed driver differs')
    driver = types.ModuleType('root_admission_builder_driver'); driver.__file__ = str(path)
    exec(compile(raw, str(path), 'exec'), driver.__dict__)
    helper = driver.module(R8 / 'driver/android_build_overlay.py', HELPER_SHA256, 'root_admission_builder_helper')
    admission = driver.document(R8 / 'root-admission-template.json', TEMPLATE_SHA256)
    def pinned(path, expected):
        body = driver.plain_read(path, expected)
        return {'path':str(path), 'sha256':hashlib.sha256(body).hexdigest()}, json.loads(body)
    fence_pin, fence = pinned(INTEGRATION / 'final-current-source-fence.json', args.source_fence_sha256)
    manifest_pin, manifest = pinned(APP / '.collect-release-candidate.json', args.APP_manifest_sha256)
    settings_pin, settings = pinned(INTEGRATION / 'settings-overlay-readback.json', args.settings_overlay_readback_sha256)
    aggregate_pin, aggregate = pinned(INTEGRATION / 'aggregate-source-readback.json', args.aggregate_readback_sha256)
    artifact_pin, artifact = pinned(INTEGRATION / 'r8-artifact-admission.json', args.r8_artifact_admission_sha256)
    helper.validate_r8_artifact(artifact)  # Full held-JAR/provenance readback stays in root's existing driver context.
    packet = driver.document(R8 / 'candidate3-patch-packet.json', admission['android_build_overlay']['reviewed_patch_packet']['sha256'])
    delta = driver.document(R8 / 'source-binding-delta.json', packet['files']['source-binding-delta.json']['sha256'])
    old_pin = admission['android_build_overlay']['archived_manifest']
    archived = driver.document(old_pin['path'], old_pin['sha256'])
    native_pin = admission['native_evidence']['APP_source']
    actual_native = driver.document(native_pin['path'], native_pin['sha256'])
    helper.validate_manifest_overlay(archived, manifest, actual_native,
                                    {'source_manifest_sha256':actual_native['source_manifest_sha256']}, delta)
    original42 = driver.document(RELEASE / 'arc09-aab-driver-preparation1/argv-unavailable-recovery3/prepared-input-pins.json', helper.ORIGINAL_PINS_SHA256)
    current42 = driver.document(R8 / 'driver/prepared-input-pins.json', admission['prepared_input_pins_sha256'])
    helper.validate_pin_delta(original42, current42, ROOT, delta)
    before = {}
    for label in ('maintained', 'privateAPP'):
        path = INTEGRATION / 'before' / label / 'android/settings.gradle.kts'
        body = driver.plain_read(path, delta['three_file_changes']['android/settings.gradle.kts']['archived_before']['sha256'])
        if len(body) != 840: raise ValueError('actual preserved before-settings bytes differ')
        before[label] = {'path':str(path), 'sha256':hashlib.sha256(body).hexdigest(), 'bytes':len(body)}
    for name, change in delta['three_file_changes'].items():
        expected = change['proposed_after']
        for owner in (ROOT, APP):
            path = owner / name; body = driver.plain_read(path, expected['sha256'])
            if len(body) != expected['bytes'] or path.stat().st_mode & 0o777 != expected['mode']:
                raise ValueError('actual maintained/private candidate3 bytes/mode differ')
        if any(fence['source_files_identity'][name][key] != expected[key] for key in ('sha256','bytes','mode')):
            raise ValueError('actual maintained fence does not bind candidate3')
    if (fence['source_root'] != str(ROOT) or fence['kind'] != 'strict_current_source_identity_fence'
            or not driver.HEX.fullmatch(fence['source_manifest_sha256'])
            or settings['current_APP_manifest'] != manifest_pin
            or settings['changed_settings']['actual_after'] != delta['three_file_changes']['android/settings.gradle.kts']['proposed_after']
            or settings['changed_settings']['archived_before'] != delta['three_file_changes']['android/settings.gradle.kts']['archived_before']
            or aggregate['new_root_fence']['sha256'] != fence_pin['sha256']
            or aggregate['new_root_fence']['path'] != fence_pin['path']
            or aggregate['source_manifest_sha256'] != fence['source_manifest_sha256']
            or aggregate['source_files'] != len(fence['source_files_identity'])
            or aggregate['current_APP_manifest'] != manifest_pin
            or manifest['source_manifest_sha256'] != settings['current_APP_source_manifest_sha256']
            or any(value['production_release_approval'] is not False for value in (fence,settings,aggregate,artifact))):
        raise ValueError('actual root overlay/aggregate/source/APP record identities differ')
    if args.aab_output is not None:
        path = args.aab_output
        if (path.parent != RELEASE or not path.name.startswith('arc09-production-aab-observation')
                or path.resolve()!=path or path.exists()):
            raise ValueError('root-selected fresh physical full AAB output required')
    admission.pop('root_admission_executable', None)
    admission['android_build_overlay']['current_manifest'] = manifest_pin
    admission['android_build_overlay']['current_source_fence'] = fence_pin
    admission['r8_artifact_admission'] = artifact_pin
    admission['output'] = str(args.aab_output) if args.aab_output else None
    admission['root_preserved_before_settings'] = before
    admission['actual_settings_overlay_readback'] = settings_pin
    admission['actual_aggregate_source_readback'] = aggregate_pin
    admission['current_maintained_source_row_count'] = len(fence['source_files_identity'])
    admission['current_APP_source_row_count'] = len(manifest['source_files'])
    admission['AAB_output_root_selected'] = args.aab_output is not None
    output = args.output
    if not output.is_absolute() or output.resolve()!=output: raise ValueError('fresh physical admission output required')
    driver.physical(output.parent)
    driver.save(output, admission)  # Exclusive new JSON only; no existing source/cache/data overwrite.
    print(json.dumps({'admission_path':str(output),'admission_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
                      'current_APP_manifest':manifest_pin,'current_source_fence':fence_pin,
                      'full_AAB_output_selected':args.aab_output is not None,'production_release_approval':False}, sort_keys=True))


if __name__=='__main__': main()
