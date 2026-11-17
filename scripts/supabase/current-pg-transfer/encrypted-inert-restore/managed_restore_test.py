"""Native end-to-end tests using generated Auth and Storage metadata only."""
import hashlib
import importlib.util
import json
import os
import pathlib
import plistlib
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
ENV = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}
SPEC = importlib.util.spec_from_file_location('collect_managed_supervisor', HERE / 'managed-supervisor.py')
SUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUP)


def command(component, *args):
    pin = hashlib.sha256((HERE / (component.upper() + '-SOURCE-PINS.json')).read_bytes()).hexdigest()
    return ['/usr/bin/python3', str(HERE / (component + '-managed-restore.py')), '--source-manifest-sha256', pin, *args]


def cleanup_synthetic_failure(test, value):
    for field in ('owned_child_stopped', 'owned_postgres_stopped', 'owned_image_detached'):
        test.assertTrue(value[field], value)
    test.assertFalse(value['disk_operation_unconfirmed'])
    root = pathlib.Path(value['preserved_root'])
    test.assertRegex(str(root), r'^/private/tmp/collect-encrypted-managed-[a-z0-9_]+$')
    st = root.lstat()
    test.assertTrue(root.is_dir() and not root.is_symlink() and root.resolve() == root)
    test.assertEqual(st.st_uid, os.getuid())
    test.assertEqual(st.st_mode & 0o777, 0o700)
    test.assertEqual(json.loads((root / 'RECOVERY.json').read_text()), value)
    info = plistlib.loads(subprocess.check_output(['/usr/bin/hdiutil', 'info', '-plist'], env=ENV, timeout=15))
    test.assertFalse(any(i.get('image-path') == str(root / 'archive-restore.sparseimage') for i in info['images']))
    test.assertEqual(root.lstat().st_ino, st.st_ino)
    shutil.rmtree(root)


class ManagedSyntheticTests(unittest.TestCase):
    def synthetic(self, component, **settings):
        p = subprocess.run(command(component, '--synthetic'), env={**ENV, **settings},
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=130)
        return p, json.loads(p.stdout)

    def test_native_roundtrips_for_both_components(self):
        for component, table_count in [('auth', 27), ('storage', 10)]:
            with self.subTest(component=component):
                p, value = self.synthetic(component)
                self.assertEqual(p.returncode, 0, value)
                self.assertEqual(p.stderr, b'')
                self.assertEqual((value['status'], value['component'], value['tables'], value['rows']),
                                 ('passed', component, table_count, 1))
                for field in ('aes256_image_verified', 'owned_child_stopped', 'owned_postgres_stopped',
                              'owned_image_detached', 'owned_scratch_removed', 'native_cells_verified'):
                    self.assertTrue(value[field], field)
                self.assertFalse(value['production_restore_authority'])
                self.assertFalse(value['whole_system_recovery'])
                self.assertNotIn(b'synthetic quote', p.stdout + p.stderr)

    def test_result_receipt_ciphertext_key_and_snapshot_tampering(self):
        for component in ('auth', 'storage'):
            for tamper, stage in [('result', 'capture'), ('receipt', 'capture'), ('ciphertext', 'ciphertext'),
                                  ('key', 'authentication'), ('snapshot', 'authentication')]:
                with self.subTest(component=component, tamper=tamper):
                    p, value = self.synthetic(component, COLLECT_ENCRYPTED_CAPTURE_TEST_TAMPER=tamper)
                    self.assertNotEqual(p.returncode, 0)
                    self.assertEqual(p.stderr, b'')
                    self.assertEqual(value['code'], 'capture_restore_refused')
                    self.assertEqual(value.get('synthetic_child_stage'), stage, value)
                    cleanup_synthetic_failure(self, value)

    def interrupt(self, component, pause, marker):
        p = subprocess.Popen(command(component, '--synthetic'),
                             env={**ENV, 'COLLECT_ENCRYPTED_CAPTURE_TEST_PAUSE': pause},
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            ready, _, _ = select.select([p.stderr], [], [], 90)
            self.assertTrue(ready, 'managed synthetic restore did not reach requested pause')
            self.assertEqual(p.stderr.readline(), marker)
            p.send_signal(signal.SIGTERM)
            out, err = p.communicate(timeout=40)
        finally:
            if p.poll() is None:
                p.kill()
                p.wait(timeout=10)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(err, b'')
        value = json.loads(out)
        self.assertEqual(value['status'], 'interrupted')
        for field in ('owned_child_stopped', 'owned_postgres_stopped', 'owned_image_detached', 'owned_scratch_removed'):
            self.assertTrue(value[field], value)
        self.assertFalse(value['native_cells_verified'])

    def test_controlled_sigterm_during_spawn_and_after_decryption(self):
        for component in ('auth', 'storage'):
            for pause, marker in [('before_node_spawn', b'COLLECT_SYNTHETIC_ARCHIVE_SPAWN_READY\n'),
                                  ('after_snapshot', b'COLLECT_SYNTHETIC_ARCHIVE_AUTHENTICATED\n')]:
                with self.subTest(component=component, pause=pause):
                    self.interrupt(component, pause, marker)

    def test_bad_real_pins_refused_before_reading_paths(self):
        for component in ('auth', 'storage'):
            with self.subTest(component=component):
                p = subprocess.run(command(component, '--real-capture', '--capture-result', '/does-not-exist/RESULT.json',
                                           '--capture-result-sha256', '0' * 64, '--ciphertext-copy', '/does-not-exist/archive',
                                           '--ciphertext-sha256', '0' * 64, '--snapshot-sha256', '0' * 64),
                                   env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
                self.assertNotEqual(p.returncode, 0)
                self.assertEqual(json.loads(p.stdout), {'status': 'refused', 'code': 'capture_pin_mismatch'})

    def test_wrong_manifest_pin_and_real_test_injection_refused(self):
        for component in ('auth', 'storage'):
            wrapper = HERE / (component + '-managed-restore.py')
            p = subprocess.run(['/usr/bin/python3', str(wrapper), '--synthetic', '--source-manifest-sha256', '0' * 64],
                               env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            self.assertNotEqual(p.returncode, 0)
            self.assertEqual(json.loads(p.stdout), {'status': 'refused', 'code': 'source_manifest_changed'})
            expected = SUP.EXPECTED[component]
            # The real path string is never opened: the injected test setting is
            # rejected in main before source checks, subprocesses or archive I/O.
            p = subprocess.run(command(component, '--real-capture', '--capture-result', expected['result_path'],
                                       '--capture-result-sha256', expected['result'], '--ciphertext-copy', expected['copy'],
                                       '--ciphertext-sha256', expected['ciphertext'], '--snapshot-sha256', expected['snapshot']),
                               env={**ENV, 'COLLECT_ENCRYPTED_CAPTURE_TEST_TAMPER': 'ciphertext'},
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            self.assertNotEqual(p.returncode, 0)
            self.assertEqual(json.loads(p.stdout), {'status': 'refused', 'code': 'invalid_test_setting'})

    def test_unpinned_postgres_does_not_execute(self):
        # Test a correct manifest schema whose selected fake binary has wrong
        # contents. Its marker would reveal execution before the pin check.
        with tempfile.TemporaryDirectory(prefix='collect-managed-binary-', dir='/private/tmp') as d:
            root = pathlib.Path(d)
            pg = root / 'bin'
            pg.mkdir(mode=0o700)
            marker = root / 'executed'
            for name in ('initdb', 'postgres', 'pg_ctl', 'pg_isready'):
                path = pg / name
                script = ("#!/bin/sh\n/usr/bin/touch '" + str(marker) + "'\nprintf 'postgres (PostgreSQL) 17.0\\n'\n"
                          if name == 'postgres' else '#!/bin/sh\nexit 0\n')
                path.write_text(script)
                path.chmod(0o700)
            manifest = json.loads((HERE / 'AUTH-SOURCE-PINS.json').read_text())
            manifest['binaries'] = {SUP.NODE: manifest['binaries'][SUP.NODE],
                                    **{str(pg / n): SUP.file_sha(pg / n)
                                       for n in ('initdb', 'postgres', 'pg_ctl', 'pg_isready')}}
            manifest['binaries'][str(pg / 'postgres')] = '0' * 64
            path = root / 'pins.json'
            path.write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
            pin = hashlib.sha256(path.read_bytes()).hexdigest()
            configure = SUP.configure
            def test_configure(component):
                configure(component)
                SUP.PINS = path
            argv = ['auth-managed-restore.py', '--synthetic', '--source-manifest-sha256', pin]
            with mock.patch.object(SUP, 'configure', side_effect=test_configure), mock.patch.object(sys, 'argv', argv), \
                 mock.patch.dict(os.environ, {**ENV, 'COLLECT_SYNTHETIC_PG_BIN': str(pg)}, clear=True):
                with self.assertRaises(SUP.Refused) as error:
                    SUP.main('auth')
            self.assertEqual(str(error.exception), 'binary_pin_changed')
            self.assertFalse(marker.exists())

    def test_version_probe_rechecks_postgres_bytes(self):
        with tempfile.TemporaryDirectory(prefix='collect-managed-version-', dir='/private/tmp') as d:
            pg = pathlib.Path(d)
            postgres = pg / 'postgres'
            postgres.write_text("#!/bin/sh\nprintf '#changed\\n' >> \"$0\"\nprintf 'postgres (PostgreSQL) 17.0\\n'\n")
            postgres.chmod(0o700)
            pins = {str(postgres): SUP.file_sha(postgres)}
            with self.assertRaises(SUP.Refused) as error:
                SUP.check_pg_version(pg, pins)
            self.assertEqual(str(error.exception), 'binary_pin_changed')

    def test_owned_device_and_pid_bindings(self):
        root = pathlib.Path('/private/tmp/collect-encrypted-managed-test')
        image, mount = root / 'archive-restore.sparseimage', root / 'mount'
        entry = {'dev-entry': '/dev/disk24s1', 'mount-point': str(mount)}
        good = {'images': [{'image-path': str(image), 'system-entities': [entry]}]}
        self.assertEqual(SUP.attached_device(good, image, mount), '/dev/disk24s1')
        for bad in ({'images': []},
                    {'images': [{'image-path': str(image) + '.other', 'system-entities': [entry]}]},
                    {'images': [{'image-path': str(image), 'system-entities': [entry, entry]}]},
                    {'images': [{'image-path': str(image), 'system-entities': [{'dev-entry': '/dev/disk24', 'mount-point': str(mount)}]}]}):
            with self.subTest(bad=bad), self.assertRaises(SUP.Refused):
                SUP.attached_device(bad, image, mount)
        self.assertFalse(SUP.is_detached(good, image))
        self.assertTrue(SUP.is_detached({'images': []}, image))
        with tempfile.TemporaryDirectory(prefix='collect-managed-pid-', dir='/private/tmp') as d:
            base = pathlib.Path(d)
            pidfile, data, sock = base / 'pid', base / 'data', base / 'sock'
            pidfile.write_text('42\n' + str(data) + '\n1234\n55001\n' + str(sock) + '\n')
            self.assertTrue(SUP.pid_matches(pidfile, 42, data, 55001, sock))
            self.assertFalse(SUP.pid_matches(pidfile, 43, data, 55001, sock))
            self.assertFalse(SUP.pid_matches(pidfile, 42, data, 55002, sock))
            self.assertFalse(SUP.pid_matches(pidfile, 42, data / 'other', 55001, sock))
            self.assertFalse(SUP.pid_matches(pidfile, 42, data, 55001, sock / 'other'))


if __name__ == '__main__':
    unittest.main()
