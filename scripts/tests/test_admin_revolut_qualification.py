#!/usr/bin/env python3
"""No-network regression cases for truthful Collect Admin qualification reporting."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

TARGET = Path(__file__).resolve().parents[1] / 'admin_revolut_qualification.py'
spec = importlib.util.spec_from_file_location('admin_qualification', TARGET)
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)

class QualificationTests(unittest.TestCase):
    def test_incomplete_source_does_not_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            result = qualification.inspect(Path(folder))
            self.assertFalse(result['release_ready'])
            self.assertTrue(any(c['status'] == 'failed' for c in result['checks']))

    def test_absent_flutter_does_not_produce_a_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            result = qualification.inspect(Path(folder), sdk=False)
            cases = [c for c in result['checks'] if c['name'] == 'Flutter analyzer']
            self.assertEqual(cases[0]['status'], 'unverified')

    def test_no_automated_manual_gate_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            result = qualification.inspect(Path(folder))
            manual = [c for c in result['checks'] if c['status'] == 'requires_external_acceptance']
            self.assertEqual(len(manual), len(qualification.MANUAL_GATES))
            self.assertFalse(result['release_ready'])

if __name__ == '__main__':
    unittest.main()
