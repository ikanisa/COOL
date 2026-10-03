"""Tiny synthetic archive proofs only; no actual APP/SDK/build reads or writes."""
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import warnings
import zipfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('local_aab_reader', HERE / 'aab_readback.py')
READER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(READER)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ArchiveReadback(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.archive = self.root / 'synthetic.aab'
        self.input = self.root / 'source.json'
        self.input.write_text('{"synthetic_only":true}\n')
        self.font = self.root / 'synthetic-font.ttf'
        self.font.write_bytes(b'SYNTHETIC FONT PAYLOAD; NOT A REAL FONT')
        self.binding = self.root / 'bindings.json'
        self.binding.write_text(json.dumps({'schema_version': 1,
            'inputs': [{'label': 'synthetic_source', 'role': 'source',
                        'path': str(self.input), 'sha256': sha(self.input)}],
            'fonts': [{'label': 'synthetic_font', 'family': 'Synthetic',
                       'asset': 'assets/typefaces/synthetic.ttf',
                       'path': str(self.font), 'sha256': sha(self.font)}]}))

    def tearDown(self):
        self.temp.cleanup()

    def make(self, extra=(), marker=READER.EXPECTED_MARKER_BYTES):
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(self.archive, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:
                bundle.writestr(READER.MARKER, marker)
                bundle.writestr(READER.FLUTTER + 'assets/typefaces/synthetic.ttf', self.font.read_bytes())
                bundle.writestr(READER.FLUTTER + 'FontManifest.json', json.dumps([
                    {'family': 'Synthetic', 'fonts': [{'asset': 'assets/typefaces/synthetic.ttf'}]}]))
                bundle.writestr(READER.FLUTTER + 'NOTICES.Z', gzip.compress(b'SYNTHETIC NOTICE ONLY\n', mtime=0))
                bundle.writestr('base/lib/arm64-v8a/libapp.so', b'NOT AN ACTUAL NATIVE LIBRARY')
                for name, body in extra:
                    bundle.writestr(name, body)

    def inspect(self):
        return READER.inspect(self.archive, sha(self.archive), self.binding, sha(self.binding))

    def test_complete_readback_hashes_all_members_and_notice_bytes(self):
        self.make()
        result = self.inspect()
        self.assertEqual(result['member_count'], 5)
        self.assertEqual(result['aab']['sha256_before'], result['aab']['sha256_after'])
        self.assertEqual(result['compiled_notices'][0]['decoded_sha256'], hashlib.sha256(b'SYNTHETIC NOTICE ONLY\n').hexdigest())
        self.assertTrue(result['declared_font_source_comparisons'][0]['source_bytes_match'])
        self.assertEqual(len(result['flutter_libraries']), 1)
        for field in ['signature_verified', 'unsignedness_verified', 'package_level_SBOM_complete', 'license_or_font_rights_approval', 'ARC09_closed']:
            self.assertFalse(result[field])
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['bindings.json', 'source.json', 'synthetic-font.ttf', 'synthetic.aab'])

    def test_duplicate_member_is_refused(self):
        self.make([(READER.MARKER, READER.EXPECTED_MARKER_BYTES)])
        with self.assertRaisesRegex(READER.ReadbackError, 'duplicate_zip_member'):
            self.inspect()

    def test_traversal_backslash_dot_and_file_directory_collisions_are_refused(self):
        for name in ['../outside', 'base/../outside', 'base\\outside', './outside', '.', '/outside', 'C:/outside']:
            with self.subTest(name=name):
                self.make([(name, b'x')])
                with self.assertRaisesRegex(READER.ReadbackError, 'unsafe_zip_member_path'):
                    self.inspect()
        self.make([('base', b'x')])
        with self.assertRaisesRegex(READER.ReadbackError, 'file_used_as_zip_directory'):
            self.inspect()

    def test_symlink_member_is_refused_without_extraction(self):
        link = zipfile.ZipInfo('base/assets/link')
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.make([(link, b'../../outside')])
        with self.assertRaisesRegex(READER.ReadbackError, 'unsupported_zip_member_type'):
            self.inspect()

    def test_crc_corruption_is_refused(self):
        self.make()
        body = bytearray(self.archive.read_bytes())
        start = body.index(b'PK\x01\x02')
        actual_crc = struct.unpack_from('<L', body, start + 16)[0]
        struct.pack_into('<L', body, start + 16, actual_crc ^ 1)
        self.archive.write_bytes(body)
        with self.assertRaises(zipfile.BadZipFile):
            self.inspect()

    def test_wrong_input_digest_and_numeric_marker_flags_are_refused(self):
        self.make()
        self.input.write_text('changed')
        with self.assertRaisesRegex(READER.ReadbackError, 'bound_input_sha256_mismatch'):
            self.inspect()
        self.input.write_text('{"synthetic_only":true}\n')
        self.make(marker=READER.EXPECTED_MARKER_BYTES.replace(b'false', b'0'))
        with self.assertRaisesRegex(READER.ReadbackError, 'local_QA_marker_missing_or_wrong'):
            self.inspect()

    def test_archive_named_leaf_replacement_is_refused(self):
        self.make()
        original = READER.file_hash
        calls = 0
        def replace_after_final_hash(stream, until, retain=False, limit=READER.MAX_INPUT):
            nonlocal calls
            result = original(stream, until, retain, limit)
            if stream.name == str(self.archive) or stream.name == self.archive:
                calls += 1
            # os.fdopen exposes an integer descriptor; identify the archive
            # by the second hash call on this FD after the initial input reads.
            if not retain and hasattr(stream, 'fileno'):
                target = self.archive.stat()
                import os
                opened = os.fstat(stream.fileno())
                if opened.st_ino == target.st_ino and stream.tell() == target.st_size:
                    calls += 1
                    if calls == 2:
                        replacement = self.root / 'replacement.aab'
                        replacement.write_bytes(self.archive.read_bytes())
                        replacement.replace(self.archive)
            return result
        with patch.object(READER, 'file_hash', replace_after_final_hash):
            with self.assertRaisesRegex(READER.ReadbackError, 'aab_changed_during_readback'):
                self.inspect()

    def test_gzip_truncation_trailing_data_and_decoded_bound_are_refused(self):
        payload = gzip.compress(b'x' * 4096, mtime=0)
        with self.assertRaisesRegex(READER.ReadbackError, 'notices_gzip_incomplete'):
            READER.notice_digest(payload[:-4], True, time.monotonic() + 5)
        with self.assertRaisesRegex(READER.ReadbackError, 'notices_trailing'):
            READER.notice_digest(payload + b'extra', True, time.monotonic() + 5)
        with patch.object(READER, 'MAX_NOTICES', 1024):
            with self.assertRaisesRegex(READER.ReadbackError, 'decoded_notices_byte_bound'):
                READER.notice_digest(payload, True, time.monotonic() + 5)

    def test_actual_regular_stream_growth_is_bounded_before_retention(self):
        with self.assertRaisesRegex(READER.ReadbackError, 'actual_regular_input_byte_bound'):
            READER.file_hash(io.BytesIO(b'x' * 4096), time.monotonic() + 5, True, 1024)

    def test_central_directory_bound_is_checked_before_zip_parser_allocation(self):
        self.make()
        with patch.object(READER, 'MAX_CENTRAL', 1), patch.object(READER.zipfile, 'ZipFile', side_effect=AssertionError('ZIP parser should not be constructed')):
            with self.assertRaisesRegex(READER.ReadbackError, 'zip_envelope_unsupported_or_bound'):
                self.inspect()

    def test_real_CLI_creates_private_receipt_and_refuses_overwrite(self):
        self.make()
        output = self.root / 'readback.json'
        command = [sys.executable, '-I', '-B', str(HERE / 'aab_readback.py'),
                   '--aab', str(self.archive), '--aab-sha256', sha(self.archive),
                   '--bindings', str(self.binding), '--bindings-sha256', sha(self.binding),
                   '--output', str(output)]
        first = subprocess.run(command, capture_output=True, timeout=5)
        self.assertEqual(first.returncode, 0, first.stderr.decode())
        self.assertEqual(json.loads(output.read_text())['member_count'], 5)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        before = sha(output)
        second = subprocess.run(command, capture_output=True, timeout=5)
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual(sha(output), before)


if __name__ == '__main__':
    unittest.main(verbosity=2)
