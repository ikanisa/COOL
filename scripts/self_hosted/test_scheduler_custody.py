import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

from scripts.self_hosted import scheduler


class SchedulerTemporaryCustody(unittest.TestCase):
    def setUp(self):
        self.area = tempfile.TemporaryDirectory()
        self.addCleanup(self.area.cleanup)
        self.root = Path(self.area.name).resolve()
        private = self.root / 'private'
        (private / 'db-tls').mkdir(parents=True)
        (private / 'keys.json').write_text(json.dumps({'POSTGRES_PASSWORD': 'synthetic-password'}))
        (private / 'db-tls' / 'ca.crt').write_text('synthetic-ca')
        self.cache = private / 'operator-cache'
        (self.cache / 'node_modules' / 'pg').mkdir(parents=True)
        (self.cache / 'node_modules' / 'pg' / 'package.json').write_text('{}')
        lock = self.cache / 'package-lock.json'
        lock.write_text('{}')
        (self.cache / 'installed-lock.sha256').write_text(hashlib.sha256(lock.read_bytes()).hexdigest())
        self.op = unittest.mock.Mock()
        self.op.root = self.root
        self.op.docker = 'synthetic-docker'
        self.op.project = 'synthetic-project'
        self.op.docker_preflight.return_value = {'services': {'web': {'image': 'synthetic-image'}}}
        self.op.run.return_value = b'{"status":"synthetic"}\n'
        cache_patch = patch.object(scheduler, 'operator_cache', return_value=self.cache)
        env_patch = patch.object(scheduler, 'read_env', return_value={
            'COLLECT_DEPLOYMENT_PROFILE': 'synthetic-profile',
            'COLLECT_DEPLOYMENT_PROFILE_SHA256': 'a' * 64,
        })
        cache_patch.start(); env_patch.start()
        self.addCleanup(cache_patch.stop); self.addCleanup(env_patch.stop)

    def temporary_files(self):
        return list((self.root / 'private').glob('operator-*.json'))

    def test_invalid_readiness_removes_private_environment_before_run(self):
        readiness = self.root / 'readiness.json'
        readiness.write_text('{}')
        readiness.chmod(0o644)
        with self.assertRaises(ValueError):
            scheduler.execute(self.op, 'main', ['status'], readiness)
        self.op.run.assert_not_called()
        self.assertEqual(self.temporary_files(), [])

    def test_serialization_failure_removes_partially_written_environment(self):
        def partial_write(value, stream):
            stream.write('{"synthetic":"partial')
            raise OSError('synthetic failure')
        with patch.object(scheduler.json, 'dump', side_effect=partial_write):
            with self.assertRaises(OSError):
                scheduler.execute(self.op, 'main', ['status'])
        self.op.run.assert_not_called()
        self.assertEqual(self.temporary_files(), [])

    def test_operator_failure_cleans_environment(self):
        self.op.run.side_effect = RuntimeError('synthetic failure')
        with self.assertRaises(RuntimeError):
            scheduler.execute(self.op, 'main', ['status'])
        self.assertEqual(self.temporary_files(), [])

    def test_stream_open_failure_cleans_created_file_and_descriptor(self):
        opened = []
        real_open = scheduler.os.open
        def record_open(*args, **kwargs):
            fd = real_open(*args, **kwargs)
            opened.append(fd)
            return fd
        with patch.object(scheduler.os, 'open', side_effect=record_open), \
             patch.object(scheduler.os, 'fdopen', side_effect=OSError('synthetic failure')):
            with self.assertRaises(OSError):
                scheduler.execute(self.op, 'main', ['status'])
        self.assertEqual(len(opened), 1)
        with self.assertRaises(OSError):
            os.fstat(opened[0])
        self.op.run.assert_not_called()
        self.assertEqual(self.temporary_files(), [])

    def test_exclusive_collision_does_not_remove_existing_file(self):
        fixed = unittest.mock.Mock(hex='a' * 32)
        existing = self.root / 'private' / ('operator-' + fixed.hex + '.json')
        existing.write_text('preserved')
        with patch.object(scheduler.uuid, 'uuid4', return_value=fixed):
            with self.assertRaises(FileExistsError):
                scheduler.execute(self.op, 'main', ['status'])
        self.assertEqual(existing.read_text(), 'preserved')
        self.op.run.assert_not_called()

    def test_success_uses_private_file_and_then_removes_it(self):
        def run(command, timeout):
            files = self.temporary_files()
            self.assertEqual(len(files), 1)
            self.assertEqual(stat.S_IMODE(os.stat(files[0]).st_mode), 0o600)
            self.assertIn('synthetic-password', json.loads(files[0].read_text())['COLLECT_JOBS_DATABASE_URL'])
            return b'{"status":"synthetic"}\n'
        self.op.run.side_effect = run
        self.assertEqual(scheduler.execute(self.op, 'main', ['status']), [{'status': 'synthetic'}])
        self.assertEqual(self.temporary_files(), [])


if __name__ == '__main__':
    unittest.main()
