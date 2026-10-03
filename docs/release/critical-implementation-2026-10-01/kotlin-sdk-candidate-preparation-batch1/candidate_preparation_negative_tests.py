#!/usr/bin/env python3
"""Actual publisher/reviewed byte negatives. No candidate writer/SDK execution."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('candidate_source_guard',HERE/'verify_candidate_source.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class CandidatePreparationNegatives(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module,cls.admission,cls.preview=m.anchors()
        cls.public_source={name:(m.PRISTINE/name).read_bytes() for name in cls.preview['files']}
        cls.license=(m.PRISTINE/'LICENSE').read_bytes()

    def test_derivative_is_only_exact_destination_change(self):
        original=(HERE.parent/'kotlin-sdk-expansion-admission-batch1/authenticated_sdk_expansion.py').read_bytes()
        derived=(HERE/'authenticated_candidate_expansion.py').read_bytes()
        changed=original.replace(str(m.PRISTINE).encode(),str(m.CANDIDATE).encode())
        self.assertEqual(derived,changed)
        self.assertNotEqual(m.CANDIDATE,m.PRISTINE)

    def test_all3_actual_upstream_before_bytes_pass_only_pristine_phase(self):
        for name,body in self.public_source.items():
            with self.subTest(path=name):
                row=self.admission['members']['flutter/'+name]
                m.check_regular_bytes('flutter/'+name,body,row,self.preview,'pristine')
                with self.assertRaisesRegex(ValueError,'allowed-byte delta drift'):
                    m.check_regular_bytes('flutter/'+name,body,row,self.preview,'patched')

    def test_all3_actual_before_one_byte_changes_rejected(self):
        for name,body in self.public_source.items():
            with self.subTest(path=name):
                changed=bytearray(body);changed[0]^=1
                with self.assertRaises(ValueError):
                    m.check_regular_bytes('flutter/'+name,bytes(changed),self.admission['members']['flutter/'+name],self.preview,'pristine')

    def test_license_byte_loss_rejected_in_every_phase(self):
        row=self.admission['members']['flutter/LICENSE']
        for phase in ('pristine','patched','built'):
            with self.subTest(phase=phase):
                m.check_regular_bytes('flutter/LICENSE',self.license,row,self.preview,phase)
                with self.assertRaises(ValueError):
                    m.check_regular_bytes('flutter/LICENSE',self.license[:-1],row,self.preview,phase)

    def test_unreviewed_license_CRLF_normalization_rejected(self):
        body=self.license.replace(b'\n',b'\r\n')
        self.assertNotEqual(self.license,body)
        with self.assertRaises(ValueError):
            m.check_regular_bytes('flutter/LICENSE',body,self.admission['members']['flutter/LICENSE'],self.preview,'built')

    def test_reviewed_source_preview_metadata_byte_drift_rejected(self):
        body=(HERE.parent/'kotlin-sdk-physical-foundation-batch1/three-file-physical-preview-binding.json').read_bytes()
        with tempfile.TemporaryDirectory(prefix='collect-sdk-candidate-negative-') as temporary:
            changed=Path(temporary)/'changed-reviewed-preview.json';changed.write_bytes(body+b' ')
            with self.assertRaisesRegex(ValueError,'reviewed metadata drift'):
                self.module.exact_json(changed,m.PREVIEW_SHA)

    def test_writer_byte_drift_rejected_before_import_or_materialization(self):
        body=(HERE/'authenticated_candidate_expansion.py').read_bytes()
        with tempfile.TemporaryDirectory(prefix='collect-sdk-candidate-negative-') as temporary:
            root=Path(temporary);(root/'authenticated_candidate_expansion.py').write_bytes(body+b' ')
            with patch.object(m,'HERE',root):
                with self.assertRaisesRegex(ValueError,'derivative writer drift'):
                    m.anchors()

    def test_unreviewed_source_phase_rejected_before_any_root_access(self):
        with self.assertRaisesRegex(ValueError,'source phase'):
            m.verify('silently_bless_changes')

    def test_prepared_code_creates_no_candidate_or_gradle_home(self):
        self.assertFalse(m.CANDIDATE.exists())
        home=Path('/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/private-gradle/sdk-kotlin-2.4.20-candidate1')
        self.assertFalse(home.exists())

if __name__=='__main__':
    unittest.main(verbosity=2)
