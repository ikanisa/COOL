#!/usr/bin/env python3
"""Real source/delta/license/FD mutation negatives; no SDK writes/execution."""
import hashlib
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('candidate2_exact_source_guard', HERE / 'verify_candidate2_source.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
spec = importlib.util.spec_from_file_location('candidate2_exact_source_patcher', HERE / 'apply_exact_cumulative8.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


class Candidate2PreparationNegatives(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module, cls.admission, cls.preview = m.anchors()
        cls.originals = {name: (m.PRISTINE / name).read_bytes() for name in cls.preview['files']}
        _, cls.prepared = p.prepare_ram_delta(m.PRISTINE)
        cls.license = (m.PRISTINE / 'LICENSE').read_bytes()

    def test_writer_and_observer_are_only_exact_candidate_root_change(self):
        old = HERE.parent / 'kotlin-sdk-candidate-preparation-batch1'
        for source, target in [('authenticated_candidate_expansion.py', 'authenticated_candidate2_expansion.py'), ('observe-candidate-runtime.init.gradle', 'observe-candidate2-runtime.init.gradle')]:
            with self.subTest(file=target):
                body = (old / source).read_bytes()
                self.assertEqual(body.count(str(m.FAILED_CANDIDATE).encode()), 1)
                self.assertEqual((HERE / target).read_bytes(), body.replace(str(m.FAILED_CANDIDATE).encode(), str(m.CANDIDATE).encode()))

    def test_all8_actual_upstream_bytes_pass_only_pristine_phase(self):
        self.assertEqual(len(self.originals), 8)
        for name, body in self.originals.items():
            with self.subTest(path=name):
                row = self.admission['members']['flutter/' + name]
                m.check_regular_bytes('flutter/' + name, body, row, self.preview, 'pristine')
                with self.assertRaises(ValueError):
                    m.check_regular_bytes('flutter/' + name, body, row, self.preview, 'patched')

    def test_all8_reviewed_RAM_afters_pass_only_patched_and_built(self):
        for name, row in self.prepared.items():
            with self.subTest(path=name):
                original = self.admission['members']['flutter/' + name]
                for phase in ('patched', 'built'):
                    m.check_regular_bytes('flutter/' + name, row['after_bytes'], original, self.preview, phase)
                with self.assertRaises(ValueError):
                    m.check_regular_bytes('flutter/' + name, row['after_bytes'], original, self.preview, 'pristine')

    def test_all8_real_after_byte_mutations_rejected(self):
        for name, row in self.prepared.items():
            with self.subTest(path=name):
                body = bytearray(row['after_bytes'])
                body[-2] ^= 1
                with self.assertRaises(ValueError):
                    m.check_regular_bytes('flutter/' + name, bytes(body), self.admission['members']['flutter/' + name], self.preview, 'built')

    def test_partial_original3_only_candidate_rejected_for_other5(self):
        for name, original in self.originals.items():
            if name.endswith(('BaseFlutterTask.kt', 'DeepLinkJsonFromManifestTask.kt', 'FlutterTask.kt', 'DeeplinkTest.kt', 'FlutterPluginUtilsTest.kt')):
                with self.subTest(path=name), self.assertRaises(ValueError):
                    m.check_regular_bytes('flutter/' + name, original, self.admission['members']['flutter/' + name], self.preview, 'built')

    def test_real_before_byte_drift_rejected_before_RAM_patch(self):
        with tempfile.TemporaryDirectory(prefix='collect-sdk8-source-negative-') as temporary:
            root = Path(temporary)
            for name, body in self.originals.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(body)
            target = root / 'packages/flutter_tools/gradle/src/main/kotlin/tasks/FlutterTask.kt'
            target.write_bytes(target.read_bytes() + b' ')
            with self.assertRaises(ValueError):
                p.prepare_ram_delta(root)

    def test_license_loss_or_unreviewed_normalization_rejected(self):
        row = self.admission['members']['flutter/LICENSE']
        for phase in ('pristine', 'patched', 'built'):
            for body in (self.license[:-1], self.license.replace(b'\n', b'\r\n')):
                with self.subTest(phase=phase), self.assertRaises(ValueError):
                    m.check_regular_bytes('flutter/LICENSE', body, row, self.preview, phase)

    def test_unreviewed_real_helper_source_delta_rejected(self):
        name = 'flutter/packages/flutter_tools/gradle/src/main/kotlin/tasks/FlutterTaskHelper.kt'
        body = (m.PRISTINE / name.removeprefix('flutter/')).read_bytes()
        for phase in ('pristine', 'patched', 'built'):
            with self.subTest(phase=phase), self.assertRaises(ValueError):
                m.check_regular_bytes(name, body + b' ', self.admission['members'][name], self.preview, phase)

    def test_real_reviewed_five_file_manifest_drift_rejected(self):
        body = (HERE.parent / 'kotlin-sdk-task-compatibility-plan2/proposed-five-file-delta.json').read_bytes()
        with tempfile.TemporaryDirectory(prefix='collect-sdk8-metadata-negative-') as temporary:
            changed = Path(temporary) / 'changed.json'
            changed.write_bytes(body + b' ')
            with self.assertRaises(ValueError):
                self.module.exact_json(changed, m.ADDITIONAL_PREVIEW_SHA)

    def test_writer_byte_drift_rejected_before_import(self):
        with tempfile.TemporaryDirectory(prefix='collect-sdk8-writer-negative-') as temporary:
            root = Path(temporary)
            (root / 'authenticated_candidate2_expansion.py').write_bytes((HERE / 'authenticated_candidate2_expansion.py').read_bytes() + b' ')
            with patch.object(m, 'HERE', root), self.assertRaisesRegex(ValueError, 'derivative writer drift'):
                m.anchors()

    def test_actual_in_place_FD_mutation_rejected_at_final_fence(self):
        with tempfile.TemporaryDirectory(prefix='collect-sdk8-fd-negative-') as temporary:
            path = Path(temporary) / 'source'
            path.write_bytes(b'exact public source\n')
            before = path.lstat()
            with path.open('rb') as reader:
                opened = os.fstat(reader.fileno())
                reader.read()
                with path.open('r+b') as mutation:
                    mutation.write(b'X')
                    mutation.flush()
                    os.fsync(mutation.fileno())
                with self.assertRaisesRegex(ValueError, 'FD/named identity'):
                    m.regular_read_fence(path, before, opened, os.fstat(reader.fileno()))

    def test_actual_named_leaf_swap_rejected_at_final_fence(self):
        with tempfile.TemporaryDirectory(prefix='collect-sdk8-leafswap-negative-') as temporary:
            path = Path(temporary) / 'source'
            path.write_bytes(b'exact public source\n')
            before = path.lstat()
            with path.open('rb') as reader:
                opened = os.fstat(reader.fileno())
                body = reader.read()
                replacement = path.with_name('replacement')
                replacement.write_bytes(body)
                os.replace(replacement, path)
                with self.assertRaisesRegex(ValueError, 'FD/named identity'):
                    m.regular_read_fence(path, before, opened, os.fstat(reader.fileno()))

    def test_actual_unchanged_FD_read_passes_fence(self):
        with tempfile.TemporaryDirectory(prefix='collect-sdk8-fence-positive-') as temporary:
            path = Path(temporary) / 'source'
            path.write_bytes(b'exact public source\n')
            before = path.lstat()
            with path.open('rb') as reader:
                opened = os.fstat(reader.fileno())
                reader.read()
                m.regular_read_fence(path, before, opened, os.fstat(reader.fileno()))

    def test_wrong_phase_or_unreviewed_generated_source_rejected(self):
        with self.assertRaises(ValueError):
            m.verify('silently_bless_changes')
        self.assertFalse(m.generated_path_allowed('flutter/packages/flutter_tools/gradle/src/main/kotlin/new.kt', 'built'))
        self.assertFalse(m.generated_path_allowed('flutter/packages/flutter_tools/gradle/build/new.class', 'patched'))

    def test_no_candidate2_or_new_execution_packet_created(self):
        self.assertFalse(m.CANDIDATE.exists())
        self.assertTrue(m.FAILED_CANDIDATE.exists())
        self.assertFalse((HERE.parent / 'kotlin-sdk-candidate2-execution-batch1').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
