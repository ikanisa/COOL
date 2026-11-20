"""Overlay integrity and release-entrypoint contract checks, not Gradle execution."""
from pathlib import Path
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from fixtures import g
ROOT=Path(__file__).resolve().parents[1]

class OverlayTests(unittest.TestCase):
    def test_each_changed_file_matches_ledger(self):
        ledger=g.load(ROOT/'integration/merge-ledger.json')
        for product,entry in ledger['products'].items():
            for row in entry['changes']:
                raw=g.read_file(ROOT/'integration'/product/'files',row['path'])
                self.assertEqual(g.sha(raw),row['after_sha256']);g.scan(row['path'],raw)
    def test_shared_guards_identical_in_both_products(self):
        for product in ('M-Money','BuriMunsi'):
            for name in ('release_guard.py','release_guard_adapter.py','release_provenance.py','provenance_exchange.py'):
                self.assertEqual((ROOT/'src'/name).read_bytes(),(ROOT/'integration'/product/'files/scripts'/name).read_bytes())
    def test_release_workflow_gate_precedes_signing_step(self):
        s=(ROOT/'integration/M-Money/files/.github/workflows/release-candidate.yml').read_text()
        self.assertLess(s.index('scripts/release_guard_adapter.py --phase build'),s.index('Build configured publisher-signed candidate'))
    def test_gradle_release_dependency(self):
        s=(ROOT/'integration/M-Money/files/app/build.gradle.kts').read_text()
        self.assertIn('dependsOn(verifyReleaseEvidenceR2)',s);self.assertIn('verifyProductionPromotion',s)
    def test_mm_cli_enforces_guard_and_exact_artifact(self):
        s=(ROOT/'integration/M-Money/files/scripts/release_gate.py').read_text()
        self.assertIn('failures.extend(enforce(',s);self.assertIn('if args.artifact is None:',s);self.assertIn('review evidence is stale',s)
    def test_mm_packager_enforces_guard(self):
        s=(ROOT/'integration/M-Money/files/scripts/package_source.py').read_text()
        self.assertIn('failures = enforce(',s);self.assertIn('result=g.package(',s)
        self.assertNotIn("with zipfile.ZipFile(output, 'w'",s)
    def test_bm_cli_preserves_old_gate_and_enforces_new(self):
        s=(ROOT/'integration/BuriMunsi/files/native/burimunsi/scripts/release_readiness.py').read_text()
        self.assertIn('result=evaluate(load(a.status),load(a.evidence)',s);self.assertIn("result['errors'].extend(enforce(",s)
        self.assertIn("BUILD_TASK_IDS={f'T{i:03}' for i in range(1,59)}",s)
    def test_adapter_does_not_offer_promotion_bypass(self):
        s=(ROOT/'src/release_guard_adapter.py').read_text();self.assertIn("choices=['source','build']",s)
    def test_all_python_sources_compile(self):
        for path in ROOT.rglob('*.py'):
            if '__pycache__' not in path.parts:compile(path.read_text(),str(path),'exec')
    def test_missing_build_evidence_blocks_actual_adapter(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t);(root/'scripts').mkdir();(root/'app').mkdir()
            for name in ('release_guard.py','release_guard_adapter.py','release_provenance.py','provenance_exchange.py'):(root/'scripts'/name).write_bytes((ROOT/'src'/name).read_bytes())
            (root/'app/build.gradle.kts').write_text('versionName = "synthetic"\n')
            p=subprocess.run([sys.executable,'-B',str(root/'scripts/release_guard_adapter.py'),'--phase','build'],capture_output=True,text=True)
            self.assertEqual(p.returncode,2);self.assertFalse(json.loads(p.stdout)['gate_open'])
    def test_overlay_conflict_does_not_create_output(self):
        spec=importlib.util.spec_from_file_location('overlay',ROOT/'integration/apply_overlay.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
        with tempfile.TemporaryDirectory() as t:
            source=Path(t)/'source';source.mkdir();(source/'app').mkdir();(source/'app/build.gradle.kts').write_text('changed by another workstream')
            output=Path(t)/'out'
            with self.assertRaisesRegex(g.Rejected,'CHANGED_PATH_CONFLICT'):m.apply('M-Money',source,output)
            self.assertFalse(output.exists())
    def test_unknown_product_gate_blocks(self):
        with self.assertRaisesRegex(g.Rejected,'UNKNOWN_PRODUCT'):g.policy('unknown','source')
    def test_unknown_phase_gate_blocks(self):
        with self.assertRaisesRegex(g.Rejected,'UNKNOWN_PHASE'):g.policy('BuriMunsi','unknown')
    def test_no_credentials_in_tooling_source(self):
        self.assertGreater(len(g.source_entries(ROOT)),0)

if __name__=='__main__':unittest.main(verbosity=2)
