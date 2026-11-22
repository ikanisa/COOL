"""Product packaging, diagnostic runner and explicit-upgrade contract tests."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from fixtures import Fixture,g

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'integration'))
import verify_baselines as runner
import apply_overlay as installer

spec=importlib.util.spec_from_file_location('candidate_packager',ROOT/'integration/M-Money/files/scripts/package_source.py')
packager=importlib.util.module_from_spec(spec);spec.loader.exec_module(packager)

class DeliveryTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup);self.base=Path(temp.name)
        self.f=Fixture(self.base,product='M-Money');self.f.store('release-manifest.json',self.f.m)

    def package(self):
        return packager.package_candidate(self.f.source,self.f.evidence/'release-manifest.json',self.f.version,self.base/'app.zip')

    def test_product_package_has_exact_bound_source_and_evidence(self):
        result=self.package();self.assertEqual(result['status'],'passed')
        entries=g.inspect_zip((self.base/'app.zip').read_bytes())
        self.assertEqual({n[7:] for n in entries if n.startswith('source/')},{r['path'] for r in self.f.s['files']})
        self.assertIn('evidence/results/guard_regression.json',entries)
        self.assertIn('evidence/logs/guard_regression.txt',entries)
        self.assertTrue((self.base/'app.zip.sha256').read_text().startswith(result['sha256']))

    def test_product_packager_does_not_call_legacy_subset_selector(self):
        with patch.object(packager,'source_files',side_effect=AssertionError('legacy subset called')):self.package()

    def test_product_existing_archive_retained(self):
        out=self.base/'app.zip';out.write_bytes(b'old retained evidence')
        with self.assertRaisesRegex(g.Rejected,'OUTPUT_EXISTS'):self.package()
        self.assertEqual(out.read_bytes(),b'old retained evidence')

    def test_product_existing_checksum_blocks_before_archive(self):
        out=self.base/'app.zip.sha256';out.write_bytes(b'old retained checksum')
        with self.assertRaisesRegex(g.Rejected,'OUTPUT_EXISTS'):self.package()
        self.assertFalse((self.base/'app.zip').exists());self.assertEqual(out.read_bytes(),b'old retained checksum')

    def test_product_output_symlink_rejected(self):
        (self.base/'app.zip').symlink_to(self.f.source/'main.py')
        with self.assertRaisesRegex(g.Rejected,'SYMLINK_REFUSED'):self.package()

    def test_product_changed_source_no_archive(self):
        (self.f.source/'added.txt').write_text('unqualified change')
        with self.assertRaises(g.Rejected):self.package()
        self.assertFalse((self.base/'app.zip').exists())

    def test_product_missing_qualification_no_archive(self):
        self.f.m['qualifications']=[];self.f.store('release-manifest.json',self.f.m)
        with self.assertRaises(g.Rejected):self.package()
        self.assertFalse((self.base/'app.zip').exists())

    def test_product_package_repeat_is_refused(self):
        self.package();first=(self.base/'app.zip').read_bytes()
        with self.assertRaisesRegex(g.Rejected,'OUTPUT_EXISTS'):self.package()
        self.assertEqual(first,(self.base/'app.zip').read_bytes())

    def test_missing_interpreter_is_blocked_not_negative_pass(self):
        with patch.object(runner.subprocess,'run',side_effect=FileNotFoundError('injected')):
            result=runner.execute(['no-such-executable'],self.base)
        self.assertFalse(result['executed']);self.assertIsNone(result['exit_code'])
        self.assertFalse(runner.expected_block('guard-json',result['exit_code'],result['raw']))

    def test_timeout_is_blocked_not_negative_pass(self):
        with patch.object(runner.subprocess,'run',side_effect=subprocess.TimeoutExpired(['synthetic'],1)):
            result=runner.execute(['synthetic'],self.base)
        self.assertFalse(result['executed']);self.assertIsNone(result['exit_code'])

    def test_crash_is_not_passing_negative_test(self):
        self.assertFalse(runner.expected_block('guard-json',2,b'Traceback (most recent call last)\n'))
        self.assertFalse(runner.expected_block('mm-release-text',1,b'Traceback (most recent call last)\n'))

    def test_nonzero_without_expected_contract_not_passed(self):
        self.assertFalse(runner.expected_block('guard-json',2,b'unrelated failure'))
        self.assertFalse(runner.expected_block('mm-release-text',1,b'RELEASE GATE NOT MET: RuntimeError'))

    def test_exact_guard_block_contract(self):
        raw=g.pretty({'status':'blocked','gate_open':False,'errors':['FILE_UNAVAILABLE'],'production_authorized':False})
        self.assertTrue(runner.expected_block('guard-json',2,raw))
        self.assertFalse(runner.expected_block('guard-json',1,raw))
        self.assertFalse(runner.expected_block('guard-json',0,raw))

    def test_exact_bm_block_contract(self):
        raw=g.pretty({'ready':False,'errors':['ROOT_NOT_DIRECTORY'],'production_authorized':False})
        self.assertTrue(runner.expected_block('bm-ready-json',2,raw))

    def test_exact_mm_block_contract(self):
        self.assertTrue(runner.expected_block('mm-release-text',1,b'RELEASE GATE NOT MET\nROOT_NOT_DIRECTORY\n'))

    def test_nominal_block_without_required_failure_not_passed(self):
        raw=g.pretty({'status':'blocked','gate_open':False,'errors':['unrelated'],'production_authorized':False})
        self.assertFalse(runner.expected_block('guard-json',2,raw))

    def test_allow_flag_does_not_pass_negative_contract(self):
        raw=g.pretty({'status':'blocked','gate_open':True,'errors':['FILE_UNAVAILABLE'],'production_authorized':False})
        self.assertFalse(runner.expected_block('guard-json',2,raw))

    def test_upgrade_requires_explicit_known_baseline(self):
        with self.assertRaisesRegex(g.Rejected,'UNKNOWN_BASELINE'):
            installer.apply('M-Money',self.f.source,self.base/'target','automatic')
        self.assertFalse((self.base/'target').exists())

    def test_upgrade_does_not_accept_original_or_conflicting_tree(self):
        with self.assertRaisesRegex(g.Rejected,'CHANGED_PATH_CONFLICT'):
            installer.apply('M-Money',self.f.source,self.base/'target','r2')
        self.assertFalse((self.base/'target').exists())

    def test_upgrade_preimages_are_recorded_for_all_paths(self):
        ledger=g.load(ROOT/'integration/merge-ledger.json')
        for entry in ledger['products'].values():
            for row in entry['changes']:
                if row['r2_sha256'] is not None:g.digest(row['r2_sha256'])
                else:self.assertIsNone(row['before_sha256'])

if __name__=='__main__':unittest.main(verbosity=2)
