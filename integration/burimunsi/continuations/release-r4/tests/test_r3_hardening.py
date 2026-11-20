"""Regression cases for R3; all credentials and release evidence are synthetic."""
import copy
import datetime as dt
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import zlib
from fixtures import Fixture, g
import triage_credentials as triage

class R3Tests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        self.base=Path(temp.name);self.f=Fixture(self.base)

    def make_package(self):
        out=self.base/'test.zip'
        g.package(self.f.source,self.f.evidence,self.f.m,self.f.product,self.f.version,out)
        return out.read_bytes()

    def reindex(self, entries, modes=None):
        modes=modes or {}
        manifest=g.strict_json(entries['PACKAGE-MANIFEST.json'])
        manifest['files']=[{**g.ref(name,value),'mode':modes.get(name,0o644)}
                           for name,value in sorted(entries.items()) if name!='PACKAGE-MANIFEST.json']
        entries['PACKAGE-MANIFEST.json']=g.pretty(manifest)
        return g.zip_bytes(entries,modes)

    def verify(self,raw,**kwargs):
        return g.verify_package(raw,product=self.f.product,version=self.f.version,
                                expected_sha256=g.sha(raw),**kwargs)

    def test_unreadable_directory_not_silently_ignored(self):
        hidden=self.f.source/'unreadable';hidden.mkdir();(hidden/'actual-source.py').write_text('important')
        original=os.scandir
        def scandir(path):
            if Path(path)==hidden: raise PermissionError('synthetic failure; no credential')
            return original(path)
        with patch.object(g.os,'scandir',side_effect=scandir):
            with self.assertRaisesRegex(g.Rejected,'SOURCE_WALK_FAILED'):g.source_entries(self.f.source)

    def test_unreadable_root_blocks(self):
        with patch.object(g.os,'scandir',side_effect=PermissionError('injected')):
            with self.assertRaisesRegex(g.Rejected,'SOURCE_WALK_FAILED'):g.source_entries(self.f.source)

    def test_directories_case_collision(self):
        for directory,name in [('Config','a.txt'),('config','b.txt')]:
            p=self.f.source/directory;p.mkdir();(p/name).write_text('source')
        with self.assertRaisesRegex(g.Rejected,'SOURCE_PATH_COLLISION'):g.source_entries(self.f.source)

    def test_empty_directory_case_collision(self):
        (self.f.source/'Config').mkdir();(self.f.source/'config').mkdir()
        with self.assertRaisesRegex(g.Rejected,'SOURCE_PATH_COLLISION'):g.source_entries(self.f.source)

    def test_boolean_executable_is_required(self):
        self.f.s['files'][0]['executable']=0
        self.f.m['source_manifest']=self.f.store('source-manifest.json',self.f.s)
        self.assertIn('INVALID_SOURCE_ROW_EXECUTABLE',self.f.check()['errors'])

    def test_boolean_source_size_is_rejected(self):
        rows=[{'path':'one','sha256':g.sha(b'x'),'size':True,'executable':False}]
        with self.assertRaisesRegex(g.Rejected,'INVALID_SOURCE_ROW_SIZE'):g.source_rows(rows)

    def test_duplicate_source_rows_rejected(self):
        rows=self.f.s['files']*2
        with self.assertRaisesRegex(g.Rejected,'DUPLICATE_SOURCE_ROW'):g.source_rows(rows)

    def test_source_rows_canonical_order(self):
        with self.assertRaisesRegex(g.Rejected,'NONCANONICAL_SOURCE_ROWS'):g.source_rows(self.f.s['files'][::-1])

    def test_dependency_row_type_confusion(self):
        self.f.dep['declarations'][0]['executable']=0
        self.f.m['dependency_inventory']=self.f.store('dependencies.json',self.f.dep)
        self.assertIn('DEPENDENCY_DECLARATIONS_MISMATCH',self.f.check()['errors'])

    def test_source_archive_budget_is_aggregate(self):
        for name in ('a.zip','b.zip'):(self.f.source/name).write_bytes(g.zip_bytes({'one':b'x','two':b'y'}))
        with patch.object(g,'MAX_ENTRIES',3):
            with self.assertRaisesRegex(g.Rejected,'ARCHIVE_ENTRY_LIMIT'):g.source_entries(self.f.source)

    def test_archive_path_component_case_collision(self):
        with self.assertRaisesRegex(g.Rejected,'ARCHIVE_PATH_CASE_COLLISION'):
            g.inspect_zip(g.zip_bytes({'Config/a':b'x','config/b':b'y'}))

    def test_privileged_archive_mode_rejected(self):
        with self.assertRaisesRegex(g.Rejected,'ARCHIVE_PRIVILEGED_MODE'):
            g.inspect_zip(g.zip_bytes({'x':b'x'},{'x':0o4755}))

    def test_archive_comment_scanned(self):
        output=io.BytesIO()
        with zipfile.ZipFile(output,'w') as archive:
            archive.writestr('main',b'x');archive.comment=('gh'+'p_'+'Q'*32).encode()
        with self.assertRaisesRegex(g.Rejected,'CREDENTIAL_LIKE_CONTENT'):g.inspect_zip(output.getvalue())

    def test_member_comment_scanned(self):
        output=io.BytesIO();info=zipfile.ZipInfo('main');info.comment=('gh'+'p_'+'Q'*32).encode()
        with zipfile.ZipFile(output,'w') as archive:archive.writestr(info,b'x')
        with self.assertRaisesRegex(g.Rejected,'CREDENTIAL_LIKE_CONTENT'):g.inspect_zip(output.getvalue())

    def test_deflate_error_is_stable_rejection(self):
        raw=g.zip_bytes({'x':b'x'})
        with patch.object(zipfile.ZipFile,'open',side_effect=zlib.error('injected')):
            with self.assertRaisesRegex(g.Rejected,'INVALID_ARCHIVE'):g.inspect_zip(raw)

    def test_valid_fresh_offline_package(self):
        result=self.verify(self.make_package());self.assertTrue(result['gate_open'],result)
        self.assertFalse(result['packaged_code_executed']);self.assertFalse(result['provenance_authenticated'])
        self.assertFalse(result['production_authorized'])

    def test_wrong_archive_digest(self):
        raw=self.make_package()
        with self.assertRaisesRegex(g.Rejected,'ARCHIVE_HASH_MISMATCH'):
            g.verify_package(raw,product=self.f.product,version=self.f.version,expected_sha256='0'*64)

    def test_offline_archive_wrong_product(self):
        raw=self.make_package()
        result=g.verify_package(raw,product='M-Money',version=self.f.version,expected_sha256=g.sha(raw))
        self.assertIn('SOURCE_IDENTITY_MISMATCH',result['errors'])

    def test_offline_archive_wrong_version(self):
        raw=self.make_package()
        result=g.verify_package(raw,product=self.f.product,version='wrong',expected_sha256=g.sha(raw))
        self.assertIn('SOURCE_IDENTITY_MISMATCH',result['errors'])

    def test_integrity_pass_does_not_bypass_freshness(self):
        raw=self.make_package();self.assertEqual(g.audit_package(raw)['status'],'passed')
        result=self.verify(raw,now=self.f.now+dt.timedelta(days=2))
        self.assertFalse(result['gate_open']);self.assertIn('STALE_EVIDENCE',result['errors'])

    def test_reindexed_unreferenced_payload_rejected(self):
        entries=g.inspect_zip(self.make_package());entries['evidence/unreferenced.txt']=b'extra'
        with self.assertRaisesRegex(g.Rejected,'PACKAGE_UNDECLARED_PAYLOAD'):g.audit_package(self.reindex(entries))

    def test_reindexed_missing_log_rejected(self):
        entries=g.inspect_zip(self.make_package());del entries['evidence/'+next(iter(self.f.results.values()))['log']['path']]
        with self.assertRaisesRegex(g.Rejected,'PACKAGE_EVIDENCE_MISSING'):g.audit_package(self.reindex(entries))

    def test_reindexed_log_tampering_rejected(self):
        entries=g.inspect_zip(self.make_package());entries['evidence/'+next(iter(self.f.results.values()))['log']['path']]=b'changed'
        with self.assertRaisesRegex(g.Rejected,'PACKAGE_EVIDENCE_HASH_MISMATCH'):g.audit_package(self.reindex(entries))

    def test_duplicate_role_path_blocks(self):
        self.f.m['artifacts']=[{'id':'log-as-artifact','kind':'report','file':next(iter(self.f.results.values()))['log']}]
        self.f.change_result(lambda r:r.update(artifact_sha256s={'log-as-artifact':r['log']['sha256']}))
        self.assertIn('EVIDENCE_PATH_REUSED',self.f.check()['errors'])

    def test_manifest_path_reserved(self):
        ref=self.f.store('release-manifest.json',b'synthetic log')
        self.f.change_result(lambda r:r.update(log=ref))
        self.assertIn('EVIDENCE_PATH_REUSED',self.f.check()['errors'])

    def test_log_case_alias_blocks(self):
        ref=self.f.store('Logs/guard_regression.txt',b'synthetic')
        artifact=self.f.store('logs/report.txt',b'report')
        self.f.m['artifacts']=[{'id':'report','kind':'report','file':artifact}]
        self.f.change_result(lambda r:r.update(log=ref,artifact_sha256s={'report':artifact['sha256']}))
        self.assertIn('EVIDENCE_PATH_CASE_COLLISION',self.f.check()['errors'])

    def test_offline_verifier_never_executes_packaged_python(self):
        # Build a valid fresh fixture after replacing source with an observable payload.
        marker=self.base/'must-not-exist'
        (self.f.source/'main.py').write_text('from pathlib import Path\nPath('+repr(str(marker))+').touch()\n')
        self.f.s['files']=g.source_entries(self.f.source);self.f.s['tree_sha256']=g.sha(g.canonical(self.f.s['files']))
        self.f.sref=self.f.store('source-manifest.json',self.f.s);self.f.m['source_manifest']=self.f.sref
        self.f.dep=g.dependencies(self.f.s);self.f.dref=self.f.store('dependencies.json',self.f.dep);self.f.m['dependency_inventory']=self.f.dref
        self.f.change_result(lambda r:r.update(source_tree_sha256=self.f.s['tree_sha256'],source_manifest_sha256=self.f.sref['sha256'],dependency_inventory_sha256=self.f.dref['sha256']))
        self.assertTrue(self.verify(self.make_package())['gate_open']);self.assertFalse(marker.exists())

    def test_cli_offline_verifier(self):
        raw=self.make_package()
        run=subprocess.run([sys.executable,'-B',g.__file__,'verify-package',str(self.base/'test.zip'),
            '--product',self.f.product,'--version',self.f.version,'--sha256',g.sha(raw)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout);self.assertTrue(json.loads(run.stdout)['gate_open'])

    def test_cli_wrong_archive_hash_blocks(self):
        self.make_package()
        run=subprocess.run([sys.executable,'-B',g.__file__,'verify-package',str(self.base/'test.zip'),
            '--product',self.f.product,'--version',self.f.version,'--sha256','0'*64],capture_output=True,text=True)
        self.assertEqual(run.returncode,2);self.assertIn('ARCHIVE_HASH_MISMATCH',json.loads(run.stdout)['errors'])

    def test_r2_policy_cannot_authorize_r3(self):
        old=g.policy(self.f.product,self.f.phase);old['validator_version']='2.0.0'
        self.f.m['policy_sha256']=g.sha(g.canonical(old))
        self.assertIn('POLICY_MISMATCH',self.f.check()['errors'])

    def test_triage_never_emits_matched_value(self):
        secret='gh'+'p_'+'Q'*32;(self.f.source/'test_config.txt').write_text(secret)
        result=triage.triage(self.f.source,self.f.product,self.f.version)
        self.assertNotIn(secret,json.dumps(result));self.assertNotIn(g.sha(secret.encode()),json.dumps(result['findings'][0]['locations']))
        self.assertFalse(result['gate_override_permitted']);self.assertFalse(result['production_authorized'])
        self.assertEqual(result['findings'][0]['disposition'],'unresolved');self.assertEqual(result['scan_status'],'blocked')
        self.assertIn('CREDENTIAL_LIKE_CONTENT',self.f.check()['errors'])

    def test_triage_preserves_bytes(self):
        secret=('gh'+'p_'+'Q'*32).encode();p=self.f.source/'test_config.txt';p.write_bytes(secret)
        before=g.source_entries(self.f.source,check_credentials=False)
        triage.triage(self.f.source,self.f.product,self.f.version)
        self.assertEqual(before,g.source_entries(self.f.source,check_credentials=False))

    def test_triage_no_matches_does_not_claim_security(self):
        result=triage.triage(self.f.source,self.f.product,self.f.version)
        self.assertEqual(result['scan_status'],'no_heuristic_matches');self.assertFalse(result['production_authorized'])

    def test_triage_decoded_location(self):
        raw=('prefix\n'+'gh'+'p_'+'Q'*32).encode('utf-16')
        rows=triage.finding_locations(raw);self.assertEqual(rows[0]['view'],'utf-16');self.assertEqual(rows[0]['line'],2)

    def test_triage_match_limit_blocks(self):
        raw=(('gh'+'p_'+'Q'*32)+'\n').encode()*3
        with patch.object(triage,'MAX_MATCHES_PER_FILE',2):
            with self.assertRaisesRegex(g.Rejected,'TRIAGE_MATCH_LIMIT'):triage.finding_locations(raw)

for encoding in ('utf-16','utf-16-le','utf-16-be','utf-32','utf-32-le','utf-32-be'):
    def test(self,encoding=encoding):
        raw=('gh'+'p_'+'Q'*32).encode(encoding)
        with self.assertRaisesRegex(g.Rejected,'CREDENTIAL_LIKE_CONTENT'):g.scan('config.txt',raw)
    setattr(R3Tests,'test_secret_'+encoding.replace('-','_'),test)
    def positive(self,encoding=encoding):g.scan('message.txt','No secrets here. Muraho.'.encode(encoding))
    setattr(R3Tests,'test_clean_'+encoding.replace('-','_'),positive)

for char in '<>"|?*':
    def test(self,char=char):
        with self.assertRaisesRegex(g.Rejected,'UNSAFE_PATH'):g.safe_name('part'+char+'name.txt')
    setattr(R3Tests,'test_nonportable_path_'+str(ord(char)),test)

if __name__=='__main__':unittest.main(verbosity=2)
