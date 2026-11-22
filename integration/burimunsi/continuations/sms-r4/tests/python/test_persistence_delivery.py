"""R3 is additive over R2: no existing policy or pinned dependency is silently replaced."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('r3_install',ROOT/'scripts/install_overlay.py')
installer=importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class PersistenceDeliveryTests(unittest.TestCase):
    def test_r2_sources_dependencies_and_fixtures_unchanged(self):
        baseline=json.loads((ROOT/'provenance/R2_BASELINE.json').read_text())['files']
        checked=0
        for rel,sha in baseline.items():
            if rel.split('/')[0] not in ('src','vendor','fixtures'):
                continue
            self.assertEqual(hashlib.sha256((ROOT/rel).read_bytes()).hexdigest(),sha,rel)
            checked+=1
        self.assertGreater(checked,40)

    def test_existing_r2_sources_accept_additive_install_for_both_apps(self):
        baseline=json.loads((ROOT/'provenance/R2_BASELINE.json').read_text())['files']
        for app in ('burimunsi','mmoney'):
            with self.subTest(application=app), tempfile.TemporaryDirectory() as tmp:
                target=Path(tmp)
                prefix='rw/ikanisa/burimunsi/core' if app=='burimunsi' else 'com/ikanisa/mmoney/core'
                vendor='buri' if app=='burimunsi' else 'mmoney'
                core=target/'core/src/main/kotlin'
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
                    dst.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copy2(ROOT/rel,dst)
                plan=installer.install(target,app)
                creates=[x for x in plan['files'] if x['action']=='create']
                self.assertEqual({Path(x['path']).name for x in creates},
                    {'SnapshotCodec.kt','JournalFormat.kt','JournalQueueStore.kt',
                     'EncryptedJournal.kt','TrustedCheckpoint.kt','ProtectedJournalPort.kt'})
                before={p.relative_to(target):p.read_bytes() for p in target.rglob('*') if p.is_file()}
                installer.install(target,app,True)
                self.assertTrue(all((target/p).read_bytes()==content for p,content in before.items()))
                self.assertNotIn('HostFileJournal.kt',{p.name for p in target.rglob('*')})
                self.assertTrue(all(x['action']=='already_present' for x in installer.install(target,app,True)['files']))

    def test_host_reference_not_inside_mobile_source_overlay(self):
        self.assertTrue((ROOT/'host/kotlin/rw/ikanisa/sms/host/HostFileJournal.kt').is_file())
        self.assertFalse(any('HostFileJournal' in p.name for p in (ROOT/'src').rglob('*')))

    def test_runner_hashes_new_host_and_persistence_inputs(self):
        spec=importlib.util.spec_from_file_location('r3_verify',ROOT/'scripts/verify.py')
        verifier=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(verifier)
        inputs=verifier.input_hashes()
        self.assertIn('host/kotlin/rw/ikanisa/sms/host/HostFileJournal.kt',inputs)
        self.assertIn('tests/persistence/PersistenceChecks.kt',inputs)
        self.assertIn('provenance/R2_BASELINE.json',inputs)
        self.assertIn('scripts/verify.py',inputs)

if __name__=='__main__':
    unittest.main()
