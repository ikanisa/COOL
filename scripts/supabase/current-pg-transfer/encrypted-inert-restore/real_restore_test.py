"""End-to-end tests of the reviewed launcher using only newly made fixtures."""
import hashlib
import importlib.util
import json
import os
import pathlib
import plistlib
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
LAUNCHER = HERE / 'real-restore.py'
PIN = hashlib.sha256((HERE / 'REAL-SOURCE-PINS.json').read_bytes()).hexdigest()
ENV = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LC_ALL': 'C', 'PYTHONDONTWRITEBYTECODE': '1'}
SPEC = importlib.util.spec_from_file_location('collect_real_restore', LAUNCHER)
REAL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REAL)


def command(*args):
    return ['/usr/bin/python3', str(LAUNCHER), '--source-manifest-sha256', PIN, *args]


def check_synthetic_failure_cleanup(test, result):
    """Discard only the test's own synthetic evidence, after verified detach."""
    test.assertEqual(result['status'], 'unconfirmed')
    test.assertTrue(result['owned_child_stopped'])
    test.assertTrue(result['owned_postgres_stopped'])
    test.assertTrue(result['owned_image_detached'])
    test.assertFalse(result['disk_operation_unconfirmed'])
    root = pathlib.Path(result['preserved_root'])
    test.assertRegex(str(root), r'^/private/tmp/collect-encrypted-archive-[a-z0-9_]+$')
    st = root.lstat()
    test.assertTrue(root.is_dir() and not root.is_symlink() and root.resolve() == root)
    test.assertEqual(st.st_uid, os.getuid())
    test.assertEqual(st.st_mode & 0o777, 0o700)
    evidence = root / 'RECOVERY.json'
    test.assertEqual(json.loads(evidence.read_text()), result)
    info = plistlib.loads(subprocess.check_output(['/usr/bin/hdiutil', 'info', '-plist'], env=ENV, timeout=15))
    test.assertFalse(any(i.get('image-path') == str(root / 'archive-restore.sparseimage') for i in info['images']))
    test.assertEqual(root.lstat().st_ino, st.st_ino)
    shutil.rmtree(root)


class RealLauncherSyntheticTests(unittest.TestCase):
    def run_synthetic(self, **setting):
        result = subprocess.run(command('--synthetic'), env={**ENV, **setting},
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=130)
        return result, json.loads(result.stdout)

    def test_full_roundtrip(self):
        p, value = self.run_synthetic()
        self.assertEqual(p.returncode, 0, value)
        self.assertEqual(p.stderr, b'')
        self.assertEqual(value['status'], 'passed')
        for name in ('aes256_image_verified', 'owned_child_stopped', 'owned_postgres_stopped',
                     'owned_image_detached', 'owned_scratch_removed', 'native_cells_verified'):
            self.assertTrue(value[name], name)
        self.assertFalse(value['production_restore_authority'])
        self.assertFalse(value['whole_system_recovery'])
        self.assertEqual((value['tables'], value['rows']), (1, 1))
        self.assertRegex(value['capture_result_sha256'], r'^[a-f0-9]{64}$')
        for cell in (b'9007199254740993', b'12345678901234567890.123456789012', b'2026-10-21 00:00:00.123456+00'):
            self.assertNotIn(cell, p.stdout + p.stderr)

    def test_tamper_refused_before_restore(self):
        for tamper, expected in [('result', 'capture'), ('receipt', 'capture'),
                                 ('ciphertext', 'ciphertext'), ('key', 'authentication'),
                                 ('snapshot', 'authentication')]:
            with self.subTest(tamper=tamper):
                p, value = self.run_synthetic(COLLECT_ENCRYPTED_CAPTURE_TEST_TAMPER=tamper)
                self.assertNotEqual(p.returncode, 0)
                self.assertEqual(p.stderr, b'')
                self.assertEqual(value['code'], 'capture_restore_refused')
                self.assertEqual(value.get('synthetic_child_stage'), expected, value)
                check_synthetic_failure_cleanup(self, value)

    def assert_controlled_sigterm(self, pause, marker):
        env = {**ENV, 'COLLECT_ENCRYPTED_CAPTURE_TEST_PAUSE': pause}
        p = subprocess.Popen(command('--synthetic'), env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            ready, _, _ = select.select([p.stderr], [], [], 90)
            self.assertTrue(ready, 'synthetic restore did not reach requested pause')
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
        self.assertTrue(value['owned_child_stopped'])
        self.assertTrue(value['owned_postgres_stopped'])
        self.assertTrue(value['owned_image_detached'])
        self.assertTrue(value['owned_scratch_removed'])
        self.assertFalse(value['native_cells_verified'])

    def test_sigterm_after_decryption_stops_child_and_postgres(self):
        self.assert_controlled_sigterm('after_snapshot', b'COLLECT_SYNTHETIC_ARCHIVE_AUTHENTICATED\n')

    def test_sigterm_deferred_across_child_spawn(self):
        self.assert_controlled_sigterm('before_node_spawn', b'COLLECT_SYNTHETIC_ARCHIVE_SPAWN_READY\n')

    def test_wrong_source_pin_refused_before_creating_scratch(self):
        p = subprocess.run(['/usr/bin/python3', str(LAUNCHER), '--synthetic', '--source-manifest-sha256', '0' * 64],
                           env=ENV, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(json.loads(p.stdout), {'status': 'refused', 'code': 'source_manifest_changed'})

    def test_tampered_postgres_never_executes_before_pin_check(self):
        # A fake PostgreSQL executable would leave a marker if launched. Make
        # a test-owned manifest pin its physical location but not its bytes, so
        # this exercises binary integrity rather than just a path mismatch.
        with tempfile.TemporaryDirectory(prefix='collect-binary-pin-', dir='/private/tmp') as d:
            root = pathlib.Path(d)
            pg = root / 'bin'
            pg.mkdir(mode=0o700)
            marker = root / 'executed'
            for name in ('initdb', 'postgres', 'pg_ctl', 'pg_isready'):
                path = pg / name
                if name == 'postgres':
                    script = "#!/bin/sh\n/usr/bin/touch '" + str(marker) + "'\nprintf 'postgres (PostgreSQL) 17.0\\n'\n"
                else:
                    script = '#!/bin/sh\nexit 0\n'
                path.write_text(script)
                path.chmod(0o700)
            manifest = json.loads((HERE / 'REAL-SOURCE-PINS.json').read_text())
            manifest['binaries'] = {REAL.NODE: manifest['binaries'][REAL.NODE],
                                    **{str(pg / n): REAL.file_sha(pg / n)
                                       for n in ('initdb', 'postgres', 'pg_ctl', 'pg_isready')}}
            manifest['binaries'][str(pg / 'postgres')] = '0' * 64
            manifest_path = root / 'pins.json'
            manifest_path.write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
            pin = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
            argv = [str(LAUNCHER), '--synthetic', '--source-manifest-sha256', pin]
            env = {**ENV, 'COLLECT_SYNTHETIC_PG_BIN': str(pg)}
            with mock.patch.object(REAL, 'PINS', manifest_path), mock.patch.object(sys, 'argv', argv), \
                 mock.patch.dict(os.environ, env, clear=True):
                with self.assertRaises(REAL.Refused) as error:
                    REAL.main()
            self.assertEqual(str(error.exception), 'binary_pin_changed')
            self.assertFalse(marker.exists(), 'untrusted PostgreSQL executed before its digest was checked')

    def test_postgres_version_probe_rechecks_binary_after_execution(self):
        with tempfile.TemporaryDirectory(prefix='collect-version-pin-', dir='/private/tmp') as d:
            pg = pathlib.Path(d)
            postgres = pg / 'postgres'
            postgres.write_text("#!/bin/sh\nprintf '#changed\\n' >> \"$0\"\nprintf 'postgres (PostgreSQL) 17.0\\n'\n")
            postgres.chmod(0o700)
            pins = {str(postgres): REAL.file_sha(postgres)}
            with self.assertRaises(REAL.Refused) as error:
                REAL.check_pg_version(pg, pins)
            self.assertEqual(str(error.exception), 'binary_pin_changed')

    def test_test_injection_not_allowed_in_real_mode(self):
        # These paths deliberately do not exist. Rejection must happen before any archive access.
        p = subprocess.run(command('--real-capture', '--capture-result', '/does-not-exist/RESULT.json',
                                   '--capture-result-sha256', '0' * 64, '--ciphertext-copy', '/does-not-exist/archive'),
                           env={**ENV, 'COLLECT_ENCRYPTED_CAPTURE_TEST_TAMPER': 'ciphertext'},
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(json.loads(p.stdout), {'status': 'refused', 'code': 'invalid_test_setting'})

    def test_device_and_process_identity_require_exact_owned_bindings(self):
        root = pathlib.Path('/private/tmp/collect-encrypted-archive-test')
        image, mount = root / 'archive-restore.sparseimage', root / 'mount'
        entry = {'dev-entry': '/dev/disk24s1', 'mount-point': str(mount)}
        good = {'images': [{'image-path': str(image), 'system-entities': [entry]}]}
        self.assertEqual(REAL.attached_device(good, image, mount), '/dev/disk24s1')
        bad = [
            {'images': []},
            {'images': [{'image-path': str(image) + '.other', 'system-entities': [entry]}]},
            {'images': [{'image-path': str(image), 'system-entities': [entry, entry]}]},
            {'images': [{'image-path': str(image), 'system-entities': [{'dev-entry': '/dev/disk24', 'mount-point': str(mount)}]}]},
        ]
        for candidate in bad:
            with self.subTest(candidate=candidate), self.assertRaises(REAL.Refused):
                REAL.attached_device(candidate, image, mount)
        self.assertFalse(REAL.is_detached(good, image))
        self.assertTrue(REAL.is_detached({'images': []}, image))
        with tempfile.TemporaryDirectory(prefix='collect-test-pid-', dir='/private/tmp') as d:
            base = pathlib.Path(d)
            pidfile, data, sock = base / 'pid', base / 'data', base / 'sock'
            pidfile.write_text('42\n' + str(data) + '\n1234\n55001\n' + str(sock) + '\n')
            self.assertTrue(REAL.pid_matches(pidfile, 42, data, 55001, sock))
            self.assertFalse(REAL.pid_matches(pidfile, 43, data, 55001, sock))
            self.assertFalse(REAL.pid_matches(pidfile, 42, data, 55002, sock))
            self.assertFalse(REAL.pid_matches(pidfile, 42, data / 'other', 55001, sock))
            self.assertFalse(REAL.pid_matches(pidfile, 42, data, 55001, sock / 'other'))


if __name__ == '__main__':
    unittest.main()
