import importlib.util
from pathlib import Path
import hashlib
import os
import stat
import subprocess
import tempfile
import time
import unittest

HERE = Path(__file__).absolute().parent
spec = importlib.util.spec_from_file_location('cache_preservation', HERE / 'preserve_exact_caches.py')
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class Refusals(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=HERE)
        self.root = Path(self.temp.name)
        self.file = self.root / 'hook.dill'
        self.file.write_bytes(bytes.fromhex('90abcdef') + b'private fixture')
        s = self.file.stat()
        self.row = {'path': 'hook.dill', 'bytes': s.st_size, 'mode': stat.S_IMODE(s.st_mode),
                    'mtime_ns': s.st_mtime_ns, 'ctime_ns': s.st_ctime_ns,
                    'dev': s.st_dev, 'ino': s.st_ino, 'nlink': 1,
                    'sha256': hashlib.sha256(self.file.read_bytes()).hexdigest()}

    def tearDown(self):
        self.temp.cleanup()

    def test_known_exact_file(self):
        fd = stage.open_verified(self.file, self.row, time.monotonic() + 5)
        os.close(fd)

    def test_identity_drift_refused(self):
        self.file.write_bytes(b'changed size')
        with self.assertRaises(ValueError):
            stage.open_verified(self.file, self.row, time.monotonic() + 5)

    def test_wrong_hash_refused(self):
        self.row['sha256'] = '0' * 64
        with self.assertRaises(ValueError):
            stage.open_verified(self.file, self.row, time.monotonic() + 5)

    def test_symlink_refused(self):
        link = self.root / 'symlink.dill'
        link.symlink_to(self.file)
        with self.assertRaises(OSError):
            stage.open_verified(link, self.row, time.monotonic() + 5)

    def test_hardlink_refused(self):
        os.link(self.file, self.root / 'another.dill')
        with self.assertRaises(ValueError):
            stage.open_verified(self.file, self.row, time.monotonic() + 5)

    def test_no_overwrite(self):
        path = self.root / 'receipt.json'
        stage.write_json(path, {'kept': True})
        with self.assertRaises(FileExistsError):
            stage.write_json(path, {'kept': False})

    def test_lsof_absence_only(self):
        stage.assert_no_open(subprocess.CompletedProcess(['fixture'], 1, b'', b''))
        for code, stdout, stderr in [(0, b'', b''), (0, b'open file', b''), (1, b'', b'warning'), (2, b'', b'')]:
            with self.subTest(code=code, stdout=stdout, stderr=stderr):
                with self.assertRaises(ValueError):
                    stage.assert_no_open(subprocess.CompletedProcess(['fixture'], code, stdout, stderr))


if __name__ == '__main__':
    unittest.main()
