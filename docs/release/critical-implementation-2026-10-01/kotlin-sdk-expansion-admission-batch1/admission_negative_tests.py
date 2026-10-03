#!/usr/bin/env python3
"""Meaningful byte/receipt/link negatives. Never calls the SDK expansion writer."""
import copy
import hashlib
import importlib.util
import json
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('exact_sdk_admission', HERE / 'authenticated_sdk_expansion.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ExactAdmissionNegatives(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper, cls.nodes, cls.checkout, cls.source_links, cls.framework_links, cls.all_links = m.bindings()
        cls.admission = json.loads((HERE / 'exact-archive-admission.json').read_text())
        cls.raw_pairs = {}
        with zipfile.ZipFile(m.ARCHIVE) as archive:
            for name in cls.checkout:
                info = archive.getinfo(name)
                cls.raw_pairs[name] = (archive.read(info), info.external_attr >> 16)
            info = archive.getinfo('flutter/LICENSE')
            cls.license = (archive.read(info), info.external_attr >> 16)
            cls.infos = archive.infolist()

    def identity(self, name, body, mode):
        return m.source_identity(name, body, mode, self.nodes, self.checkout, self.helper)

    def assertReceiptRejects(self, mutator):
        changed = copy.deepcopy(self.admission)
        mutator(changed)
        with self.assertRaises(ValueError):
            m.validate_exact_admission(changed)

    def test_actual_full_admission_receipt_has_consistent_publisher_bindings(self):
        m.validate_exact_admission(self.admission)
        self.assertEqual(22415, len(self.admission['members']))
        self.assertEqual(15660, self.admission['source_entries'])

    def test_all_exact33_actual_raw_pairs_reject_one_byte_changes_before_conversion(self):
        self.assertEqual(33, len(self.raw_pairs))
        for name, (raw, mode) in self.raw_pairs.items():
            with self.subTest(path=name):
                self.assertTrue(self.identity(name, raw, mode)['exact_reviewed_CRLF_checkout'])
                changed = bytearray(raw); changed[0] ^= 1
                with self.assertRaisesRegex(ValueError, 'raw-byte drift'):
                    self.identity(name, bytes(changed), mode)

    def test_canonical_only_git_bytes_do_not_replace_exact_reviewed_publisher_CRLF(self):
        for name, (raw, mode) in self.raw_pairs.items():
            with self.subTest(path=name):
                self.assertNotEqual(raw, raw.replace(b'\r\n', b'\n'))
                with self.assertRaisesRegex(ValueError, 'raw-byte drift'):
                    self.identity(name, raw.replace(b'\r\n', b'\n'), mode)

    def test_unlisted_source_cannot_be_admitted_by_blanket_CRLF_normalization(self):
        raw, mode = self.license
        self.identity('flutter/LICENSE', raw, mode)
        self.assertNotEqual(raw, raw.replace(b'\n', b'\r\n'))
        with self.assertRaisesRegex(ValueError, 'blob identity drift'):
            self.identity('flutter/LICENSE', raw.replace(b'\n', b'\r\n'), mode)

    def test_actual_license_byte_loss_rejected(self):
        raw, mode = self.license
        with self.assertRaisesRegex(ValueError, 'blob identity drift'):
            self.identity('flutter/LICENSE', raw[:-1], mode)

    def test_actual_source_executable_mode_drift_rejected(self):
        raw, mode = self.license
        with self.assertRaisesRegex(ValueError, 'executable distinction'):
            self.identity('flutter/LICENSE', raw, mode | 0o111)

    def test_actual_source_type_drift_rejected(self):
        raw, mode = self.license
        with self.assertRaisesRegex(ValueError, 'type drift'):
            self.identity('flutter/LICENSE', raw, stat.S_IFLNK | 0o777)

    def test_license_omitted_from_actual_receipt_rejected(self):
        self.assertReceiptRejects(lambda r: r['members'].pop('flutter/LICENSE'))

    def test_source_checkout_pair_raw_SHA_drift_in_actual_receipt_rejected(self):
        name = next(iter(self.checkout))
        self.assertReceiptRejects(lambda r: r['members'][name].__setitem__('sha256', '0' * 64))

    def test_source_git_identity_drift_in_actual_receipt_rejected(self):
        self.assertReceiptRejects(lambda r: r['members']['flutter/LICENSE']['source'].__setitem__('official_git_blob_sha1', '0' * 40))

    def test_exact_framework_link_target_drift_even_if_contained_rejected(self):
        name = next(iter(self.framework_links))
        self.assertReceiptRejects(lambda r: r['members'][name].__setitem__('target', 'Versions/A/Resources'))

    def test_recursive_link_resolution_receipt_drift_rejected(self):
        name = next(iter(self.framework_links))
        self.assertReceiptRejects(lambda r: r['members'][name].__setitem__('resolved_archive_target', 'flutter/LICENSE'))

    def test_publisher_source_link_omission_rejected(self):
        name = next(iter(self.source_links))
        self.assertReceiptRejects(lambda r: r['members'].pop(name))

    def test_source_safe_materialized_permission_drift_rejected(self):
        self.assertReceiptRejects(lambda r: r['members']['flutter/LICENSE'].__setitem__('safe_materialized_mode', 0o666))

    def test_total_expanded_size_drift_rejected(self):
        self.assertReceiptRejects(lambda r: r.__setitem__('expanded_bytes', r['expanded_bytes'] + 1))

    def test_reviewed_delta_manifest_actual_byte_drift_rejected(self):
        body = (m.FOUNDATION / 'publisher-checkout-eol-deltas.json').read_bytes()
        changed = bytearray(body); changed[10] ^= 1
        with tempfile.TemporaryDirectory(prefix='collect-sdk-admission-negative-') as temporary:
            path = Path(temporary) / 'changed-reviewed-delta.json'; path.write_bytes(changed)
            with self.assertRaisesRegex(ValueError, 'reviewed metadata drift'):
                m.exact_json(path, m.EOL_MANIFEST_SHA)

    def test_root_review_actual_byte_drift_rejected(self):
        body = m.ROOT_REVIEW.read_bytes()
        with tempfile.TemporaryDirectory(prefix='collect-sdk-admission-negative-') as temporary:
            path = Path(temporary) / 'changed-root-review.json'; path.write_bytes(body + b' ')
            with self.assertRaisesRegex(ValueError, 'reviewed metadata drift'):
                m.exact_json(path, m.ROOT_REVIEW_SHA)

    def test_actual_archive_prefix_truncation_and_byte_drift_reject_before_sdk_writes(self):
        with m.ARCHIVE.open('rb') as stream:
            actual_prefix = stream.read(4096)
        changed = bytearray(actual_prefix); changed[32] ^= 1
        with tempfile.TemporaryDirectory(prefix='collect-sdk-admission-negative-') as temporary:
            path = Path(temporary) / 'changed-truncated-publisher-archive.zip'; path.write_bytes(changed)
            with patch.object(m, 'ARCHIVE', path):
                with self.assertRaisesRegex(ValueError, 'archive raw-byte/type/link drift'):
                    m.admit_readonly()
        self.assertFalse(m.DESTINATION.exists())

    def test_duplicate_actual_archive_identity_rejected(self):
        info = next(i for i in self.infos if i.filename == 'flutter/LICENSE')
        result = self.helper.check_metadata(self.infos + [copy.copy(info)], self.all_links,
                                           self.source_links, self.framework_links)
        self.assertFalse(result['admitted'])
        self.assertTrue(any('duplicate' in r.get('error', '') for r in result['issues']))

    def test_actual_member_path_traversal_rejected(self):
        infos = list(self.infos)
        index = next(i for i, info in enumerate(infos) if info.filename == 'flutter/LICENSE')
        changed = copy.copy(infos[index]); changed.filename = 'flutter/../outside/LICENSE'; infos[index] = changed
        result = self.helper.check_metadata(infos, self.all_links, self.source_links, self.framework_links)
        self.assertFalse(result['admitted'])
        self.assertTrue(any('unsafe archive path' in r.get('error', '') for r in result['issues']))

    def test_same_framework_extra_alias_not_in_exact17_rejected(self):
        name = next(iter(self.framework_links)); changed = copy.copy(next(i for i in self.infos if i.filename == name))
        extra_name = name.rsplit('/', 1)[0] + '/ExtraAlias'; changed.filename = extra_name
        targets = dict(self.all_links); targets[extra_name] = targets[name]
        result = self.helper.check_metadata(self.infos + [changed], targets, self.source_links, self.framework_links)
        self.assertFalse(result['admitted'])
        self.assertTrue(any(r.get('kind') == 'unreviewed_extra_link' for r in result['issues']))

    def test_external_git_object_pointer_rejected(self):
        with self.assertRaisesRegex(ValueError, 'external Git'):
            m.reject_external_git_pointers('flutter/.git/objects/info/alternates', b'/existing/sdk/.git/objects')

    def test_git_executable_hook_configuration_rejected(self):
        with self.assertRaisesRegex(ValueError, 'executable/external Git config'):
            m.reject_external_git_pointers('flutter/.git/config', b'[core]\n\thooksPath = /outside/hooks\n')


if __name__ == '__main__':
    unittest.main(verbosity=2)
