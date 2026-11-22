#!/usr/bin/env python3
"""Read-only Collect Gateway device/APK preflight. Never installs or sends SMS."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

PACKAGE = 'app.cool.mobile.gateway'
ACTIVITY = 'app.cool.mobile.gateway.GatewayActivity'
SERIAL = re.compile(r'^[A-Za-z0-9_.:\-]{1,160}$')
PERMISSIONS = ('SEND_SMS', 'READ_PHONE_STATE', 'ACCESS_NETWORK_STATE', 'INTERNET')
FORBIDDEN = ('RECEIVE_SMS', 'READ_SMS', 'CALL_PHONE', 'CAMERA')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def devices(text):
    rows = []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 2 or line.startswith(('List of devices', '*')):
            continue
        serial, state = parts[:2]
        if not SERIAL.fullmatch(serial) or state not in ('device', 'offline', 'unauthorized', 'recovery', 'sideload'):
            raise ValueError('adb_device_list_invalid')
        rows.append((serial, state))
    if len({r[0] for r in rows}) != len(rows):
        raise ValueError('adb_device_list_invalid')
    return rows


def select_device(rows, requested):
    if requested is not None:
        if not SERIAL.fullmatch(requested):
            raise ValueError('adb_target_invalid')
        matches = [r for r in rows if r[0] == requested]
        return matches[0] if len(matches) == 1 else None
    return rows[0] if len(rows) == 1 else None


def hardware_kind(serial, kernel_qemu, boot_qemu, hardware):
    if serial.startswith('emulator-') or kernel_qemu == '1' or boot_qemu == '1' or hardware in ('goldfish', 'ranchu', 'vbox86'):
        return 'emulator'
    # Absence of an emulator marker is insufficient to certify a real handset.
    if kernel_qemu == '0' and hardware and hardware not in ('unknown', 'generic'):
        return 'physical_candidate'
    return 'unverified'


def package_projection(text):
    version = re.search(r'\bversionName=([A-Za-z0-9._+\-]{1,80})', text)
    code = re.search(r'\bversionCode=(\d{1,10})\b', text)
    flags = re.search(r'\b(?:pkgFlags|flags)=\[([^\]]*)\]', text)
    permissions = {}
    for name in PERMISSIONS + FORBIDDEN:
        m = re.search(r'android\.permission\.' + name + r': granted=(true|false)\b', text)
        permissions[name] = None if m is None else m[1] == 'true'
    return {'version_name': version[1] if version else None,
            'version_code': int(code[1]) if code else None,
            'debuggable': None if flags is None else 'DEBUGGABLE' in flags[1].split(),
            'runtime_permissions': permissions}


def apk_projection(badging, permission_text, certificate_text):
    package = re.search(r"^package: name='([^']+)'", badging, re.M)
    activity = re.search(r"^launchable-activity: name='([^']+)'", badging, re.M)
    permissions = sorted(set(re.findall(r"uses-permission(?:-sdk-\d+)?: name='(android\.permission\.[A-Z_]+)'", permission_text)))
    certificates = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$', certificate_text, re.M)
    if package is None or package[1] != PACKAGE or activity is None or activity[1] != ACTIVITY:
        raise ValueError('gateway_apk_identity_invalid')
    if any('android.permission.' + p in permissions for p in FORBIDDEN):
        raise ValueError('gateway_apk_forbidden_permission')
    if any('android.permission.' + p not in permissions for p in PERMISSIONS):
        raise ValueError('gateway_apk_required_permission_missing')
    if len(certificates) != 1:
        raise ValueError('gateway_apk_signer_unavailable')
    return {'package': PACKAGE, 'launch_activity': ACTIVITY, 'permissions': permissions,
            'signing_certificate_sha256': certificates[0].lower(),
            'store_signing_accepted': False}


def run_preflight(adb, serial, apk, build_tools, execute):
    calls = []

    def run(argv):
        # Raw output may contain device identifiers or package metadata; only
        # strict projections below are retained. No logcat/data/telephony dump.
        result = execute(argv)
        calls.append({'tool': Path(argv[0]).name, 'operation': argv[1:2], 'exit_code': result.returncode})
        if result.returncode != 0:
            raise ValueError('gateway_read_command_unavailable')
        return result.stdout

    rows = devices(run([adb, 'devices', '-l']))
    report = {'kind': 'read_only_gateway_device_preflight',
              'observed_at_utc': datetime.now(timezone.utc).isoformat(),
              'target_count': len(rows),
              'targets': [{'serial_sha256': digest(s.encode()), 'adb_state': state} for s, state in rows],
              'physical_device_accepted': False, 'carrier_or_delivery_accepted': False,
              'enrollment_verified': False, 'production_ready': False,
              'device_mutations': 0, 'backend_calls': 0, 'sms_invocations': 0,
              'commands': calls}
    target = select_device(rows, serial)
    if target is None:
        report['status'] = 'blocked'
        report['reason'] = 'device_not_connected' if not rows else 'explicit_single_device_required'
    elif target[1] != 'device':
        report.update(status='blocked', reason='device_not_authorized_or_ready')
    else:
        target_serial = target[0]

        def shell(*args):
            return run([adb, '-s', target_serial, 'shell', *args]).strip()

        kind = hardware_kind(target_serial, shell('getprop', 'ro.kernel.qemu'), shell('getprop', 'ro.boot.qemu'), shell('getprop', 'ro.hardware'))
        sdk = shell('getprop', 'ro.build.version.sdk')
        report['device'] = {'serial_sha256': digest(target_serial.encode()), 'hardware_kind': kind,
                            'android_api': int(sdk) if re.fullmatch(r'\d{1,3}', sdk) else None}
        listed = shell('pm', 'list', 'packages', PACKAGE).splitlines()
        if 'package:' + PACKAGE not in listed:
            report.update(status='blocked', reason='gateway_package_not_installed')
        else:
            report['installed_package'] = package_projection(shell('dumpsys', 'package', PACKAGE))
            features = shell('pm', 'list', 'features').splitlines()
            report['device']['telephony_messaging_feature'] = 'feature:android.hardware.telephony.messaging' in features
            report.update(status='observed_requires_native_smoke', reason='app_native_observations_and_owner_acceptance_required')
        if kind == 'emulator':
            report.update(status='blocked', reason='emulator_is_not_physical_handset_evidence')
        elif kind != 'physical_candidate':
            report.update(status='blocked', reason='physical_handset_unverified')
    if apk is not None:
        if build_tools is None or not apk.is_file() or apk.is_symlink():
            raise ValueError('gateway_apk_tools_unavailable')
        aapt, signer = build_tools / 'aapt', build_tools / 'apksigner'
        if not aapt.is_file() or not signer.is_file():
            raise ValueError('gateway_apk_tools_unavailable')
        projection = apk_projection(run([str(aapt), 'dump', 'badging', str(apk)]),
                                    run([str(aapt), 'dump', 'permissions', str(apk)]),
                                    run([str(signer), 'verify', '--print-certs', str(apk)]))
        report['apk'] = {**projection, 'bytes': apk.stat().st_size, 'sha256': digest(apk.read_bytes()),
                         'installed_artifact_parity_verified': False}
    report['unobserved_dimensions'] = ['signed native app network/SIM/radio/subscription observations',
                                       'installed artifact signing/parity', 'approved enrollment and current server authority',
                                       'physical Keystore/process-death/power-loss acceptance', 'carrier/provider acceptance']
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default=shutil.which('adb'))
    parser.add_argument('--serial')
    parser.add_argument('--apk', type=Path)
    parser.add_argument('--build-tools', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Refusing to overwrite existing device evidence.')
    try:
        if args.adb is None:
            raise ValueError('adb_unavailable')

        def execute(argv):
            try:
                return subprocess.run(argv, capture_output=True, text=True, timeout=30, check=False)
            except subprocess.TimeoutExpired:
                raise ValueError('gateway_read_command_timeout') from None

        result = run_preflight(args.adb, args.serial, args.apk, args.build_tools, execute)
    except ValueError as error:
        result = {'status': 'blocked', 'reason': str(error), 'production_ready': False,
                  'device_mutations': 0, 'backend_calls': 0, 'sms_invocations': 0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'status': result['status'], 'reason': result['reason'], 'output': str(args.output)}))
    return 0 if result['status'] == 'observed_requires_native_smoke' else 2


if __name__ == '__main__':
    raise SystemExit(main())
