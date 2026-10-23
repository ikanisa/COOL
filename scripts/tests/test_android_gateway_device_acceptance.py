"""Synthetic parser/command safety tests; no connected device or Android calls."""
import importlib.util
import json
import subprocess
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[1] / 'android_gateway_device_acceptance.py'
spec = importlib.util.spec_from_file_location('gateway_device_acceptance', MODULE)
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)


class DeviceAcceptanceTest(unittest.TestCase):
    def test_empty_device_list_stops_before_any_device_command(self):
        calls = []

        def execute(argv):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0, 'List of devices attached\n\n', '')

        report = gateway.run_preflight('/adb', None, None, None, execute)
        self.assertEqual('device_not_connected', report['reason'])
        self.assertEqual([['/adb', 'devices', '-l']], calls)
        self.assertFalse(report['physical_device_accepted'])

    def test_multiple_devices_never_choose_an_arbitrary_target(self):
        rows = gateway.devices('List of devices attached\nfirst device\nsecond device\n')
        self.assertIsNone(gateway.select_device(rows, None))
        self.assertEqual(('second', 'device'), gateway.select_device(rows, 'second'))

    def test_emulator_and_unknown_hardware_cannot_be_physical_proof(self):
        self.assertEqual('emulator', gateway.hardware_kind('emulator-5554', '0', '', 'qcom'))
        self.assertEqual('emulator', gateway.hardware_kind('device', '', '1', 'ranchu'))
        self.assertEqual('unverified', gateway.hardware_kind('device', '', '', 'qcom'))
        self.assertEqual('physical_candidate', gateway.hardware_kind('device', '0', '', 'qcom'))

    def test_device_identifiers_and_raw_errors_are_not_retained(self):
        report = gateway.run_preflight('/adb', None, None, None, lambda a: subprocess.CompletedProcess(a, 0, 'List of devices attached\nprivate-serial unauthorized\n', 'private token'))
        text = json.dumps(report)
        self.assertNotIn('private-serial', text)
        self.assertNotIn('private token', text)
        self.assertEqual('device_not_authorized_or_ready', report['reason'])

    def test_malformed_and_duplicate_device_records_fail_closed(self):
        for text in ('same device\nsame device', 'unsafe;target device', 'one unrecognized'):
            with self.assertRaises(ValueError):
                gateway.devices(text)

    def test_permission_projection_preserves_unknown_and_independent_denials(self):
        data = gateway.package_projection('versionCode=42 minSdk=24\nversionName=1.2.4\npkgFlags=[ DEBUGGABLE HAS_CODE ]\nandroid.permission.SEND_SMS: granted=false\nandroid.permission.READ_PHONE_STATE: granted=true\nprivate customer data')
        self.assertFalse(data['runtime_permissions']['SEND_SMS'])
        self.assertTrue(data['runtime_permissions']['READ_PHONE_STATE'])
        self.assertIsNone(data['runtime_permissions']['INTERNET'])
        self.assertNotIn('private customer data', json.dumps(data))

    def test_verified_apk_requires_gateway_entrypoint_permissions_and_one_signer(self):
        badging = "package: name='app.cool.mobile.gateway' versionCode='1'\nlaunchable-activity: name='app.cool.mobile.gateway.GatewayActivity'\n"
        permissions = '\n'.join("uses-permission: name='android.permission." + p + "'" for p in gateway.PERMISSIONS)
        certificate = 'Signer #1 certificate SHA-256 digest: ' + 'a' * 64
        result = gateway.apk_projection(badging, permissions, certificate)
        self.assertEqual('a' * 64, result['signing_certificate_sha256'])
        self.assertFalse(result['store_signing_accepted'])
        for b, p, c in ((badging.replace('.gateway', ''), permissions, certificate),
                        (badging, permissions + "\nuses-permission: name='android.permission.RECEIVE_SMS'", certificate),
                        (badging, permissions.replace('SEND_SMS', 'UNRELATED'), certificate),
                        (badging, permissions, '')):
            with self.assertRaises(ValueError):
                gateway.apk_projection(b, p, c)

    def test_failed_adb_command_is_unavailable_without_retaining_output(self):
        with self.assertRaisesRegex(ValueError, '^gateway_read_command_unavailable$'):
            gateway.run_preflight('/adb', None, None, None, lambda a: subprocess.CompletedProcess(a, 1, 'sensitive', 'sensitive'))

    def test_complete_emulator_and_unclassified_reads_still_refuse_physical_acceptance(self):
        for serial, qemu, expected in (('emulator-5554', '1', 'emulator_is_not_physical_handset_evidence'),
                                       ('private-handset', '', 'physical_handset_unverified')):
            calls = []

            def execute(argv):
                calls.append(argv)
                command = argv[-2:]
                responses = {
                    ('getprop', 'ro.kernel.qemu'): qemu,
                    ('getprop', 'ro.boot.qemu'): '',
                    ('getprop', 'ro.hardware'): 'qcom',
                    ('getprop', 'ro.build.version.sdk'): '36',
                    ('package', gateway.PACKAGE): 'versionCode=1\nversionName=1.0\n',
                    ('list', 'features'): 'feature:android.hardware.telephony.messaging',
                    ('packages', gateway.PACKAGE): 'package:' + gateway.PACKAGE,
                }
                output = 'List of devices attached\n' + serial + ' device\n' if argv[1] == 'devices' else responses.get(tuple(command), '')
                return subprocess.CompletedProcess(argv, 0, output, '')

            report = gateway.run_preflight('/adb', serial, None, None, execute)
            self.assertEqual('blocked', report['status'])
            self.assertEqual(expected, report['reason'])
            self.assertFalse(report['physical_device_accepted'])
            self.assertFalse(report['enrollment_verified'])
            self.assertTrue(all('install' not in a and 'grant' not in a and 'logcat' not in a for a in calls))


if __name__ == '__main__':
    unittest.main()
