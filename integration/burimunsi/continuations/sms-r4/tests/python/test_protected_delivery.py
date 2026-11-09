"""R4 remains additive: shared application sources and the R3 plaintext test port stay unchanged."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('r4_install',ROOT/'scripts/install_overlay.py')
installer=importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
NEW={'EncryptedJournal.kt','TrustedCheckpoint.kt','ProtectedJournalPort.kt'}

class ProtectedDeliveryTests(unittest.TestCase):
    def test_r3_sources_adapters_host_dependencies_and_fixtures_unchanged(self):
        baseline=json.loads((ROOT/'provenance/R3_BASELINE.json').read_text())['files']
        selected={p:h for p,h in baseline.items() if p.split('/')[0] in ('src','host','vendor','fixtures')}
        self.assertGreater(len(selected),50)
        for p,h in selected.items():
            self.assertEqual(hashlib.sha256((ROOT/p).read_bytes()).hexdigest(),h,p)

    def test_additive_r3_to_r4_install_both_apps_and_repeat(self):
        baseline=json.loads((ROOT/'provenance/R3_BASELINE.json').read_text())['files']
        for app in ('burimunsi','mmoney'):
            with self.subTest(application=app), tempfile.TemporaryDirectory() as tmp:
                target=Path(tmp); core=target/'core/src/main/kotlin'
                prefix='rw/ikanisa/burimunsi/core' if app=='burimunsi' else 'com/ikanisa/mmoney/core'
                vendor='buri' if app=='burimunsi' else 'mmoney'
                (core/prefix).mkdir(parents=True)
                for p in (ROOT/f'vendor/{vendor}/core').glob('*.kt'):
                    shutil.copy2(p,core/prefix/p.name)
                for rel in baseline:
                    if rel.startswith('src/main/kotlin/'):
                        dst=core/rel.removeprefix('src/main/kotlin/')
                    elif rel.startswith(f'src/adapters/{app}/'):
                        dst=core/f'rw/ikanisa/sms/adapters/{app}'/Path(rel).name
                    else:
                        continue
                    dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(ROOT/rel,dst)
                before={p.relative_to(target):p.read_bytes() for p in target.rglob('*') if p.is_file()}
                creates={Path(x['path']).name for x in installer.install(target,app)['files'] if x['action']=='create'}
                self.assertEqual(creates,NEW)
                installer.install(target,app,True)
                self.assertTrue(all((target/p).read_bytes()==b for p,b in before.items()))
                self.assertTrue(all(x['action']=='already_present' for x in installer.install(target,app,True)['files']))

    def test_runner_binds_security_source_and_tests(self):
        spec=importlib.util.spec_from_file_location('r4_verify',ROOT/'scripts/verify.py')
        verifier=importlib.util.module_from_spec(spec);spec.loader.exec_module(verifier)
        inputs=verifier.input_hashes()
        for name in NEW:
            self.assertIn('src/main/kotlin/rw/ikanisa/sms/policy/'+name,inputs)
        self.assertIn('tests/protected/ProtectedChecks.kt',inputs)
        self.assertIn('provenance/R3_BASELINE.json',inputs)

    def test_existing_android_key_lookup_has_no_key_creation_or_export(self):
        text=(ROOT/'src/main/kotlin/rw/ikanisa/sms/policy/EncryptedJournal.kt').read_text()
        self.assertIn('class ExistingAndroidKeystoreKey',text)
        self.assertIn('store.getKey(alias,null)',text)
        self.assertNotIn('generateKey(',text)
        self.assertNotIn('.encoded',text)
        self.assertNotIn('setEntry(',text)

if __name__=='__main__':
    unittest.main()
