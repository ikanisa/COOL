#!/usr/bin/env python3
"""Build, inspect and execute isolated Android tests, with evidence for every phase.

plan is read-only. build never signs production or accepts SDK licences. instrument
requires --execute and a named device, and touches only new .nativeTest packages.
A successful host-side test of this script is NOT an executed native build.
"""
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
import zipfile

from build_preflight import inspect as preflight
from native_artifacts import (
    Artifact, OVERLAY, ROLES, ROOT, RUNNER, TYPES, VERSION_CODE, VERSION_NAME,
    artifacts, build_tasks, inspect_apk, inspect_xml, select_apk,
)
from native_instrumentation_contract import (
    RECEIVER_TEST_CLASSES, SAFE_PACKAGE, TEST_CLASSES, expected_tests,
    instrumentation_classes, parse_instrumentation, selected_device, test_contracts,
    validated_sandbox_package, wait_for_startup_ui,
)
from native_pipeline_io import (
    PipelineError, command, contained_file, fresh_dir, now, sdk_path, sdk_tool, sha, write_json,
)
from verify_native_boundary import A, SMS_NAMES, manifest_failures, source_checks

def plan() -> dict:
    return {'schema': 1, 'mode': 'plan', 'native_build_executed': False,
            'gradle_tasks': build_tasks(), 'artifacts': [dataclasses.asdict(a) | {'package': a.package} for a in artifacts()],
            'expected_instrumentation_tests_per_flavor': test_contracts(),
            'device_policy': 'Named emulator by default; physical device requires explicit opt-in. Never overwrite installed packages.',
            'production_signing': False, 'production_deployment': False, 'licence_acceptance': False}

def fingerprint_source_files(base: Path) -> list[Path]:
    files = []
    for parent, directories, names in os.walk(base):
        directories[:] = [name for name in directories if name not in ('build', '.gradle', '.kotlin', '__pycache__')]
        for name in names:
            path = Path(parent) / name
            if name != 'local.properties' and path.suffix != '.pyc' and path.is_file():
                files.append(path)
    return sorted(files)


def source_fingerprint() -> dict:
    rows = []
    for base in (ROOT, OVERLAY / 'upstream/collect'):
        for path in fingerprint_source_files(base):
            rows.append({'path': path.relative_to(OVERLAY).as_posix(), 'sha256': sha(path)})
    encoded = json.dumps(rows, sort_keys=True).encode()
    return {'sha256': hashlib.sha256(encoded).hexdigest(), 'files': rows}


def build(args: argparse.Namespace) -> int:
    out = fresh_dir(args.output)
    result = {'schema': 1, 'run_id': str(uuid.uuid4()), 'started_at': now(), 'status': 'BLOCKED',
              'native_build_executed': False, 'apk_inspection_passed': False, 'instrumentation_executed': False,
              'production_deployment': False, 'stage': 'preflight'}
    try:
        if args.download_gradle:
            command([sys.executable, str(ROOT / 'scripts/bootstrap_gradle.py'), '--download'], out / 'gradle-bootstrap.log', timeout=180)
        report = preflight(args.sdk)
        write_json(out / 'preflight.json', report)
        if not report['ready_for_build']:
            raise PipelineError('Build prerequisites unavailable: ' + ', '.join(c['name'] for c in report['checks'] if not c['ok']))
        sdk = sdk_path(args.sdk)
        failures = source_checks(ROOT)
        if failures:
            raise PipelineError('Source boundary: ' + '; '.join(failures))
        fingerprint = source_fingerprint()
        write_json(out / 'source-fingerprint.json', fingerprint)
        command([str(sdk_tool(sdk, 'sdkmanager')), '--sdk_root=' + str(sdk), '--list_installed'], out / 'sdk-packages.txt')
        command([str(sdk_tool(sdk, 'adb')), 'version'], out / 'adb-version.txt')
        java = str(Path(os.environ['JAVA_HOME']) / 'bin/java') if os.environ.get('JAVA_HOME') else 'java'
        command([java, '-version'], out / 'java-version.txt')
        result['stage'] = 'gradle-build'
        result['native_build_executed'] = True
        # Never permit locally configured endpoints in this evidence build. Optimized and
        # nativeTest variants also hard-override every endpoint and binding in their DSL.
        config = ['-P' + k + '=' for k in ('collectSupabaseOrigin', 'collectAdminOrigin', 'burimunsiApiOrigin', 'burimunsiApiPathPrefix', 'collectGatewayOrigin',
                  'collectPublishableKey')]
        env = os.environ.copy()
        env['ANDROID_HOME'] = str(sdk)
        env['ANDROID_SDK_ROOT'] = str(sdk)
        cmd = ['sh', str(ROOT / 'gradlew'), *build_tasks(), *config, '--no-daemon', '--stacktrace', '--console=plain']
        write_json(out / 'build-command.json', cmd)
        command(cmd, out / 'gradle-build.log', timeout=2400, env=env)
        result['stage'] = 'apk-inspection'
        records = []
        (out / 'apks').mkdir()
        for spec in artifacts():
            path = select_apk(spec.output_dir, spec.variant)
            record = inspect_apk(path, spec, sdk, out / 'inspection')
            dest = out / 'apks' / spec.filename
            shutil.copyfile(path, dest)
            if sha(dest) != record['sha256']:
                raise PipelineError('APK changed during copy')
            record['path'] = dest.relative_to(out).as_posix()
            records.append(record)
        for flavor in ROLES:
            pair = [r for r in records if r['spec']['flavor'] == flavor and r['spec']['kind'] == 'nativeTest']
            if len(pair) != 2 or pair[0]['certificate_sha256'] != pair[1]['certificate_sha256']:
                raise PipelineError('Application and instrumentation APK signer mismatch')
        write_json(out / 'artifacts.json', {'source_sha256': fingerprint['sha256'], 'artifacts': records,
                                         'expected_tests_per_flavor': test_contracts()})
        (out / 'APK_SHA256SUMS').write_text(''.join(r['sha256'] + '  ' + r['path'] + '\n' for r in records))
        for source, dest in ((ROOT / 'app/build/reports', out / 'reports'),
                             (ROOT / 'core/build/test-results', out / 'core-test-results'),
                             (ROOT / 'app/build/outputs/mapping', out / 'mapping')):
            if source.exists():
                shutil.copytree(source, dest)
        if source_fingerprint()['sha256'] != fingerprint['sha256']:
            raise PipelineError('Source changed during build')
        result.update(status='PASS', stage='complete', apk_inspection_passed=True, artifact_count=len(records))
    except (PipelineError, OSError, ValueError, zipfile.BadZipFile, ET.ParseError) as error:
        result.update(status='FAIL' if result['native_build_executed'] else 'BLOCKED', error=str(error))
    finally:
        result['finished_at'] = now()
        write_json(out / 'build-result.json', result)
        print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'PASS' else 2

def instrument(args: argparse.Namespace) -> int:
    if not args.execute:
        print(json.dumps({'mode': 'plan', 'execute': False, 'serial': args.serial,
                          'packages': [a.package for a in artifacts() if a.kind == 'nativeTest'],
                          'expected_tests_per_flavor': test_contracts(),
                          'note': 'Add --execute to inspect, install and run on the named device.'}, indent=2))
        return 0
    out = fresh_dir(args.output)
    result = {'schema': 1, 'run_id': str(uuid.uuid4()), 'started_at': now(), 'status': 'BLOCKED',
              'installation_executed': False, 'instrumentation_executed': False, 'flavors': [],
              'production_deployment': False, 'cleanup': []}
    installed: list[str] = []
    adb: Path | None = None
    try:
        sdk = sdk_path(args.sdk)
        adb = sdk_tool(sdk, 'adb')
        serial = args.serial
        listed = command([str(adb), 'devices', '-l'], out / 'devices.txt')
        selected_device(listed, serial)
        def call(parts: list[str], name: str, timeout: int = 120) -> str:
            return command([str(adb), '-s', serial, *parts], out / name, timeout=timeout)
        qemu = call(['shell', 'getprop', 'ro.kernel.qemu'], 'device-kind.txt').strip()
        if qemu != '1' and not args.allow_physical_device:
            raise PipelineError('Physical device requires --allow-physical-device; use an emulator for synthetic tests')
        api = int(call(['shell', 'getprop', 'ro.build.version.sdk'], 'device-api.txt').strip())
        if api < 26:
            raise PipelineError('Device API below supported minimum 26')
        call(['shell', 'getprop', 'ro.build.fingerprint'], 'device-fingerprint.txt')
        if call(['shell', 'getprop', 'sys.boot_completed'], 'boot-state.txt').strip() != '1':
            raise PipelineError('Device has not completed boot')
        if call(['shell', 'am', 'get-current-user'], 'device-user.txt').strip() != '0':
            raise PipelineError('Use the primary device user (0); work-profile/secondary-user installation is refused')
        result.update(device_api=api, device_kind='emulator' if qemu == '1' else 'physical')
        evidence = args.build_evidence.expanduser().absolute()
        build_result = json.loads(contained_file(evidence, 'build-result.json').read_text())
        inventory = json.loads(contained_file(evidence, 'artifacts.json').read_text())
        if build_result.get('status') != 'PASS' or not build_result.get('apk_inspection_passed'):
            raise PipelineError('Build evidence is not a passing inspected build')
        contracts = test_contracts()
        if (inventory.get('source_sha256') != source_fingerprint()['sha256'] or
                inventory.get('expected_tests_per_flavor') != contracts):
            raise PipelineError('Current source does not match the built/tested source contract')
        rows = inventory.get('artifacts', [])
        prepared = {}
        for spec in [a for a in artifacts() if a.kind == 'nativeTest']:
            matches = [r for r in rows if r.get('spec') == dataclasses.asdict(spec)]
            if len(matches) != 1:
                raise PipelineError('Missing/ambiguous native-test artifact')
            row = matches[0]
            path = contained_file(evidence, row['path'])
            if sha(path) != row['sha256']:
                raise PipelineError('APK differs from build evidence')
            checked = inspect_apk(path, spec, sdk, out / 'inspection')
            if checked['certificate_sha256'] != row['certificate_sha256']:
                raise PipelineError('APK signer differs from build evidence')
            package = validated_sandbox_package(spec.package)
            # No -r, no pm clear, no uninstall of a pre-existing app, even a QA app.
            if call(['shell', 'pm', 'list', 'packages', '-u', package], spec.filename + '.existing.txt').strip():
                raise PipelineError('Sandbox package already installed; refusing to overwrite or erase it: ' + package)
            prepared[(spec.flavor, spec.test)] = (spec, path, checked)
        for flavor in ROLES:
            if prepared[(flavor, False)][2]['certificate_sha256'] != prepared[(flavor, True)][2]['certificate_sha256']:
                raise PipelineError('Test and target signer mismatch')
        # All four APKs and existing-package checks have passed before the first install.
        for flavor in ROLES:
            app_spec, app_path, _ = prepared[(flavor, False)]
            test_spec, test_path, _ = prepared[(flavor, True)]
            for spec, path in ((app_spec, app_path), (test_spec, test_path)):
                output = call(['install', '-t', str(path)], spec.filename + '.install.txt', timeout=180)
                if not re.search(r'^Success\s*$', output, re.MULTILINE):
                    raise PipelineError('Installation did not report success')
                installed.append(spec.package)
                result['installation_executed'] = True
                call(['shell', 'dumpsys', 'package', spec.package], spec.filename + '.installed.txt')
            result['instrumentation_executed'] = True
            names = ','.join(instrumentation_classes(flavor))
            text = call(['shell', 'am', 'instrument', '-w', '-r', '-e', 'class', names,
                         test_spec.package + '/' + RUNNER], flavor + '-instrumentation.txt', timeout=900)
            parsed = parse_instrumentation(text, set(contracts[flavor]))
            write_json(out / (flavor + '-instrumentation.json'), parsed)
            result['flavors'].append({'flavor': flavor, **parsed})
            if not parsed['passed']:
                raise PipelineError('Instrumentation failed contract for ' + flavor)
            if qemu == '1':
                # Exact offline nativeTest form, captured before any synthetic
                # credentials. Read only the UID installed by this invocation.
                image = subprocess.run([str(adb), '-s', serial, 'exec-out', 'run-as',
                    validated_sandbox_package(app_spec.package), 'cat', 'cache/prototype-sign-in.png'],
                    capture_output=True, timeout=30, check=True).stdout
                if not image.startswith(b'\x89PNG\r\n\x1a\n') or len(image) > 10_000_000:
                    raise PipelineError('Invalid native prototype sign-in screenshot')
                destination = out / (flavor + '-prototype-sign-in.png')
                destination.write_bytes(image)
                result.setdefault('ui_artifacts', []).append({'flavor': flavor, 'path': destination.name,
                    'sha256': sha(destination), 'scope': 'offline synthetic Compose root; no live identity or TLS proof'})
            # Evidence-only startup smoke: no SMS permissions, test account or financial action.
            launch = call(['shell', 'am', 'start', '-W', '-n', app_spec.package + '/rw.ikanisa.burimunsi.MainActivity'], flavor + '-launch.txt')
            if not re.search(r'^Status:\s*ok\s*$', launch, re.MULTILINE):
                raise PipelineError('Main activity failed to launch')
            if qemu == '1':
                wait_for_startup_ui(call, app_spec.package, flavor)
            focused = call(['shell', 'dumpsys', 'activity', 'activities'], flavor + '-activity.txt')
            if not any(app_spec.package in line and ('mResumedActivity' in line or 'topResumedActivity' in line) for line in focused.splitlines()):
                raise PipelineError('Sandbox activity is not foreground; screenshot refused')
            # Avoid collecting a personal physical-device screenshot by default.
            if qemu == '1':
                shot = subprocess.run([str(adb), '-s', serial, 'exec-out', 'screencap', '-p'], capture_output=True, timeout=30, check=True).stdout
                if not shot.startswith(b'\x89PNG\r\n\x1a\n'):
                    raise PipelineError('Invalid screenshot output')
                (out / (flavor + '-startup.png')).write_bytes(shot)
            call(['shell', 'am', 'force-stop', app_spec.package], flavor + '-stop.txt')
        result['status'] = 'PASS'
    except (PipelineError, OSError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError, subprocess.SubprocessError) as error:
        result.update(status='FAIL' if result['installation_executed'] else 'BLOCKED', error=str(error))
    finally:
        if adb:
            for package in reversed(installed):
                try:
                    # Only packages installed successfully by this invocation are owned here.
                    text = command([str(adb), '-s', args.serial, 'uninstall', validated_sandbox_package(package)],
                                   out / (package + '.cleanup.txt'))
                    ok = bool(re.search(r'^Success\s*$', text, re.MULTILINE))
                except (PipelineError, OSError):
                    ok = False
                result['cleanup'].append({'package': package, 'removed': ok})
                if not ok:
                    result.update(status='FAIL', cleanup_error='A sandbox installed by this run remains; inspect cleanup evidence.')
        result['finished_at'] = now()
        write_json(out / 'instrumentation-result.json', result)
        print(json.dumps(result, indent=2))
    return 0 if result['status'] == 'PASS' else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='mode', required=True)
    sub.add_parser('plan')
    p = sub.add_parser('build')
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--sdk')
    p.add_argument('--download-gradle', action='store_true')
    p = sub.add_parser('instrument')
    p.add_argument('--build-evidence', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--serial', required=True)
    p.add_argument('--sdk')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--allow-physical-device', action='store_true')
    args = parser.parse_args()
    if args.mode == 'plan':
        print(json.dumps(plan(), indent=2))
        return 0
    return build(args) if args.mode == 'build' else instrument(args)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (PipelineError, OSError, ValueError) as error:
        print(json.dumps({'status': 'BLOCKED', 'error': str(error), 'native_success_claimed': False}), file=sys.stderr)
        sys.exit(2)
