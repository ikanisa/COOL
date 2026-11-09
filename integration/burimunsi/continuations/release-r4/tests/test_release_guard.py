"""Positive and adversarial policy tests. All release records are synthetic."""
import copy
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from fixtures import Fixture,g

class GuardTests(unittest.TestCase):
    def setUp(self):
        t=tempfile.TemporaryDirectory();self.addCleanup(t.cleanup);self.base=Path(t.name);self.f=Fixture(self.base)
    def blocked(self,code=None):
        r=self.f.check();self.assertFalse(r['gate_open'],r);self.assertEqual(r['status'],'blocked');self.assertFalse(r['production_authorized'])
        if code:self.assertIn(code,r['errors'])
    def test_valid_source(self):self.assertTrue(self.f.check()['gate_open']);self.assertFalse(self.f.check()['production_authorized'])
    def test_source_mutated(self):
        (self.f.source/'main.py').write_text('changed');self.blocked('SOURCE_INVENTORY_MISMATCH')
    def test_source_added(self):
        (self.f.source/'new.py').write_text('new');self.blocked('SOURCE_INVENTORY_MISMATCH')
    def test_source_deleted(self):
        (self.f.source/'main.py').unlink();self.blocked('SOURCE_INVENTORY_MISMATCH')
    def test_source_executable_changed(self):
        (self.f.source/'main.py').chmod(0o755);self.blocked('SOURCE_INVENTORY_MISMATCH')
    def test_source_case_collision(self):
        (self.f.source/'MAIN.py').write_text('collision');self.blocked('SOURCE_PATH_COLLISION')
    def test_source_symlink(self):
        (self.f.source/'alias').symlink_to(self.f.source/'main.py');self.blocked('SYMLINK_REFUSED')
    def test_symlink_even_in_excluded_directory(self):
        (self.f.source/'build').symlink_to(self.f.evidence);self.blocked('SYMLINK_REFUSED')
    def test_hardlink(self):
        os.link(self.f.source/'main.py',self.base/'hardlink');self.blocked('HARDLINK_REFUSED')
    def test_fifo(self):
        os.mkfifo(self.f.source/'fifo');self.blocked('NONREGULAR_FILE')
    def test_empty_tree(self):
        for p in self.f.source.iterdir():p.unlink()
        self.blocked('EMPTY_SOURCE')
    def test_private_filename(self):
        (self.f.source/'.env.production').write_text('synthetic');self.blocked('CREDENTIAL_LIKE_FILENAME')
    def test_token_in_source(self):
        (self.f.source/'config.txt').write_text('gh'+'p_'+'X'*30);self.blocked('CREDENTIAL_LIKE_CONTENT')
    def test_template_not_exempt_from_scan(self):
        (self.f.source/'.env.example').write_text('sb_'+'secret_'+'X'*30);self.blocked('CREDENTIAL_LIKE_CONTENT')
    def test_missing_result(self):
        (self.f.evidence/self.f.m['qualifications'][0]['result']['path']).unlink();self.blocked('FILE_UNAVAILABLE')
    def test_result_bytes_changed(self):
        (self.f.evidence/self.f.m['qualifications'][0]['result']['path']).write_text('{}');self.blocked('FILE_HASH_MISMATCH')
    def test_log_bytes_changed(self):
        (self.f.evidence/next(iter(self.f.results.values()))['log']['path']).write_text('changed');self.blocked('FILE_HASH_MISMATCH')
    def test_log_empty(self):
        ref=self.f.store('logs/empty.txt',b'  \n');self.f.change_result(lambda r:r.update(log=ref));self.blocked('EMPTY_TEST_LOG')
    def test_log_secret(self):
        ref=self.f.store('logs/secret.txt',('gh'+'p_'+'X'*30).encode());self.f.change_result(lambda r:r.update(log=ref));self.blocked('CREDENTIAL_LIKE_CONTENT')
    def test_missing_qualifications(self):self.f.m['qualifications']=[];self.blocked('MISSING_QUALIFICATION_RESULTS')
    def test_duplicate_qualifications(self):self.f.m['qualifications']*=2;self.blocked('DUPLICATE_QUALIFICATION')
    def test_extra_qualification(self):self.f.m['qualifications'][0]['id']='unknown';self.blocked('UNEXPECTED_QUALIFICATION')
    def test_extra_manifest_field(self):self.f.m['bypass']=True;self.blocked('INVALID_MANIFEST_FIELDS')
    def test_future_manifest(self):self.f.m['created_at']=self.f.t(1);self.blocked('FUTURE_EVIDENCE')
    def test_stale_manifest(self):self.f.m['created_at']=self.f.t(-g.MAX_AGE-1);self.blocked('STALE_EVIDENCE')
    def test_stale_result(self):
        self.f.change_result(lambda r:r.update(started_at=self.f.t(-g.MAX_AGE-1)));self.blocked('STALE_EVIDENCE')
    def test_future_result(self):
        self.f.change_result(lambda r:r.update(completed_at=self.f.t(1)));self.blocked('FUTURE_EVIDENCE')
    def test_result_before_capture(self):
        self.f.change_result(lambda r:r.update(started_at=self.f.t(-100)));self.blocked('TIME_ORDER_INVALID')
    def test_reversed_result_times(self):
        self.f.change_result(lambda r:r.update(started_at=self.f.t(-15)));self.blocked('TIME_ORDER_INVALID')
    def test_result_after_manifest(self):
        self.f.change_result(lambda r:r.update(completed_at=self.f.t(-5)));self.blocked('TIME_ORDER_INVALID')
    def test_exclusions_immutable(self):
        self.f.s['excluded_directories'].append('app');self.f.m['source_manifest']=self.f.store('source-manifest.json',self.f.s);self.blocked('SOURCE_EXCLUSIONS_CHANGED')
    def test_tree_hash_wrong(self):
        self.f.s['tree_sha256']='0'*64;self.f.m['source_manifest']=self.f.store('source-manifest.json',self.f.s);self.blocked('SOURCE_TREE_MISMATCH')
    def test_symlink_parent(self):
        target=self.base/'external';target.mkdir();(self.f.evidence/'source-manifest.json').rename(target/'source-manifest.json')
        (self.f.evidence/'alias').symlink_to(target);self.f.m['source_manifest']['path']='alias/source-manifest.json';self.blocked('SYMLINK_REFUSED')
    def test_dependency_source_mismatch(self):
        self.f.dep['source_tree_sha256']='0'*64;self.f.m['dependency_inventory']=self.f.store('dependencies.json',self.f.dep);self.blocked('DEPENDENCY_BINDING_MISMATCH')
    def test_dependency_declaration_removed(self):
        self.f.dep['declarations']=[];self.f.m['dependency_inventory']=self.f.store('dependencies.json',self.f.dep);self.blocked('DEPENDENCY_DECLARATIONS_MISMATCH')
    def test_boolean_file_size(self):self.f.m['source_manifest']['size']=True;self.blocked('INVALID_FILE_SIZE')
    def test_bad_file_hash(self):self.f.m['source_manifest']['sha256']='z'*64;self.blocked('INVALID_SHA256')
    def test_missing_file_hash(self):del self.f.m['source_manifest']['sha256'];self.blocked('INVALID_FILE_REFERENCE')
    def test_no_clobber(self):
        p=self.base/'out';p.write_bytes(b'old')
        with self.assertRaisesRegex(g.Rejected,'OUTPUT_EXISTS'):g.write_new(p,b'new')
        self.assertEqual(p.read_bytes(),b'old')
    def test_output_symlink(self):
        p=self.base/'out';p.symlink_to(self.f.source/'main.py')
        with self.assertRaisesRegex(g.Rejected,'SYMLINK_REFUSED'):g.write_new(p,b'new')
    def test_repeatable_package(self):
        a=self.base/'a.zip';b=self.base/'b.zip'
        for p in (a,b):g.package(self.f.source,self.f.evidence,self.f.m,self.f.product,self.f.version,p)
        self.assertEqual(a.read_bytes(),b.read_bytes());self.assertEqual(g.audit_package(a.read_bytes())['status'],'passed')
    def test_package_requires_evidence(self):
        self.f.m['qualifications']=[];p=self.base/'out.zip'
        with self.assertRaises(g.Rejected):g.package(self.f.source,self.f.evidence,self.f.m,self.f.product,self.f.version,p)
        self.assertFalse(p.exists())
    def test_package_production_forbidden(self):
        self.f.m['designation']='production'
        with self.assertRaises(g.Rejected):g.package(self.f.source,self.f.evidence,self.f.m,self.f.product,self.f.version,self.base/'out.zip')
    def test_package_output_inside_source(self):
        with self.assertRaisesRegex(g.Rejected,'OUTPUT_ALIASES_INPUT'):g.package(self.f.source,self.f.evidence,self.f.m,self.f.product,self.f.version,self.f.source/'out.zip')
    def test_package_extra_entry(self):
        p=self.base/'out.zip';g.package(self.f.source,self.f.evidence,self.f.m,self.f.product,self.f.version,p)
        entries=g.inspect_zip(p.read_bytes());entries['rogue.txt']=b'rogue'
        with self.assertRaisesRegex(g.Rejected,'PACKAGE_INVENTORY_MISMATCH'):g.audit_package(g.zip_bytes(entries))
    def test_package_mutated_entry(self):
        p=self.base/'out.zip';g.package(self.f.source,self.f.evidence,self.f.m,self.f.product,self.f.version,p)
        entries=g.inspect_zip(p.read_bytes());entries['source/main.py']=b'changed'
        with self.assertRaisesRegex(g.Rejected,'PACKAGE_INVENTORY_MISMATCH'):g.audit_package(g.zip_bytes(entries))
    def test_cli_absent_manifest(self):
        r=subprocess.run([sys.executable,g.__file__,'validate','--source',str(self.f.source),'--evidence-root',str(self.f.evidence),
            '--manifest',str(self.base/'absent.json'),'--product','BuriMunsi','--version',self.f.version,'--phase','build'],capture_output=True,text=True)
        self.assertEqual(r.returncode,2);self.assertFalse(json.loads(r.stdout)['gate_open'])
    def test_tooling_cannot_promote(self):
        r=g.validate(self.f.source,self.f.evidence,self.f.m,product='release-safeguards',version=self.f.version,phase='promotion')
        self.assertIn('TOOLING_CANNOT_BE_PRODUCTION',r['errors'])

RESULTS={
'blocked':({'status':'blocked'},'QUALIFICATION_NOT_EXECUTED_OR_NOT_PASSED'),
'skipped':({'status':'skipped'},'QUALIFICATION_NOT_EXECUTED_OR_NOT_PASSED'),
'unexecuted':({'executed':False},'QUALIFICATION_NOT_EXECUTED_OR_NOT_PASSED'),
'int_executed':({'executed':1},'QUALIFICATION_NOT_EXECUTED_OR_NOT_PASSED'),
'bool_exit':({'exit_code':False},'QUALIFICATION_EXIT_CODE'),
'failed_exit':({'exit_code':1},'QUALIFICATION_EXIT_CODE'),
'wrong_run':({'run_id':'other-synthetic-run'},'RESULT_IDENTITY_MISMATCH'),
'wrong_product':({'product':'M-Money'},'RESULT_IDENTITY_MISMATCH'),
'wrong_version':({'source_version':'other'},'RESULT_IDENTITY_MISMATCH'),
'wrong_scope':({'scope':'source_only'},'QUALIFICATION_SCOPE_MISMATCH'),
'wrong_tree':({'source_tree_sha256':'0'*64},'RESULT_SOURCE_BINDING_MISMATCH'),
'wrong_source_manifest':({'source_manifest_sha256':'0'*64},'RESULT_SOURCE_BINDING_MISMATCH'),
'wrong_dependencies':({'dependency_inventory_sha256':'0'*64},'RESULT_SOURCE_BINDING_MISMATCH'),
'wrong_artifacts':({'artifact_sha256s':{'fake':'0'*64}},'RESULT_ARTIFACT_BINDING_MISMATCH'),
'wrong_policy':({'policy_sha256':'0'*64},'RESULT_IDENTITY_MISMATCH'),
'unknown_schema':({'schema_version':99},'UNSUPPORTED_SCHEMA'),
'bool_schema':({'schema_version':True},'UNSUPPORTED_SCHEMA'),
'no_command':({'command':[]},'RESULT_COMMAND_MISSING')}
for name,(changes,code) in RESULTS.items():
    def test(self,changes=changes,code=code):self.f.change_result(lambda r:r.update(changes));self.blocked(code)
    setattr(GuardTests,'test_result_'+name,test)
for field,value,code in [('executed',0,'INCOMPLETE_QUALIFICATION'),('failed',1,'INCOMPLETE_QUALIFICATION'),('skipped',1,'INCOMPLETE_QUALIFICATION'),
                         ('blocked',1,'INCOMPLETE_QUALIFICATION'),('executed',True,'INVALID_RESULT_COUNTS'),('executed',-1,'INVALID_RESULT_COUNTS')]:
    def test(self,field=field,value=value,code=code):self.f.change_result(lambda r:r['counts'].update({field:value}));self.blocked(code)
    setattr(GuardTests,'test_count_'+field+'_'+str(value),test)
for field,value,code in [('product','M-Money','SOURCE_IDENTITY_MISMATCH'),('source_version','other','SOURCE_IDENTITY_MISMATCH'),
                         ('schema_version',2,'UNSUPPORTED_SCHEMA'),('schema_version',True,'UNSUPPORTED_SCHEMA'),
                         ('designation','production','DESIGNATION_NOT_AUTHORIZED'),('policy_sha256','0'*64,'POLICY_MISMATCH'),
                         ('created_at','2026-13-99T99:00:00Z','INVALID_TIMESTAMP'),('created_at','2026-11-09T12:00:00','UTC_TIMESTAMP_REQUIRED')]:
    def test(self,field=field,value=value,code=code):self.f.m[field]=value;self.blocked(code)
    setattr(GuardTests,'test_manifest_'+field+'_'+str(value).replace(':','_'),test)
for name in ['../outside','/outside','C:/outside','a\\b','a//b','a/./b','NUL.txt','x.','e\u0301.txt']:
    def test(self,name=name):self.f.m['source_manifest']['path']=name;self.blocked()
    setattr(GuardTests,'test_unsafe_path_'+str(len(GuardTests.__dict__)),test)

class JsonTests(unittest.TestCase):pass
for raw in [b'{"a":1,"a":2}',b'{"a":{"b":1,"b":2}}',b'{"x":NaN}',b'{"x":Infinity}',b'{"x":-Infinity}',b'[]',b'null',b'true',b'1',b'{"x":"\xff"}',b'{']:
    def test(self,raw=raw):
        with self.assertRaises(g.Rejected):g.strict_json(raw)
    setattr(JsonTests,'test_invalid_'+str(len(JsonTests.__dict__)),test)

class PhaseTests(unittest.TestCase):
    def setUp(self):
        t=tempfile.TemporaryDirectory();self.addCleanup(t.cleanup);self.base=Path(t.name)
    def test_build_unresolved(self):
        f=Fixture(self.base,phase='build');f.dep['resolution_status']='unresolved';f.m['dependency_inventory']=f.store('dependencies.json',f.dep)
        self.assertIn('DEPENDENCIES_UNRESOLVED',f.check()['errors'])
    def test_promotion_missing_artifact(self):
        f=Fixture(self.base,phase='promotion');f.m['artifacts'].pop();self.assertIn('REQUIRED_ARTIFACT_MISSING',f.check()['errors'])
    def test_artifact_mutation(self):
        f=Fixture(self.base,phase='promotion');(f.evidence/f.m['artifacts'][0]['file']['path']).write_bytes(b'changed');self.assertIn('FILE_HASH_MISMATCH',f.check()['errors'])
    def test_duplicate_artifact(self):
        f=Fixture(self.base,phase='promotion');f.m['artifacts'].append(copy.deepcopy(f.m['artifacts'][0]));self.assertIn('DUPLICATE_ARTIFACT',f.check()['errors'])
    def test_dependency_bytes_changed(self):
        f=Fixture(self.base,phase='build');(f.evidence/'dependencies/component.txt').write_bytes(b'changed');self.assertIn('FILE_HASH_MISMATCH',f.check()['errors'])
    def test_log_reuse(self):
        f=Fixture(self.base,phase='build');ids=list(f.results);f.change_result(lambda r:r.update(log=f.results[ids[0]]['log']),ids[1]);self.assertIn('REUSED_QUALIFICATION_LOG',f.check()['errors'])
    def test_wrong_artifact_container(self):
        f=Fixture(self.base,phase='promotion');a=f.m['artifacts'][0];a['file']=f.store(a['file']['path'],g.zip_bytes({'not-manifest.txt':b'x'}))
        self.assertIn('ANDROID_CONTAINER_INVALID',f.check()['errors'])
for product in ('BuriMunsi','M-Money'):
    for phase in ('build','promotion'):
        def test(self,product=product,phase=phase):
            f=Fixture(self.base,product,phase);r=f.check();self.assertTrue(r['gate_open'],r);self.assertFalse(r['production_authorized'])
        setattr(PhaseTests,'test_complete_synthetic_'+product.replace('-','')+'_'+phase,test)

class ArchiveTests(unittest.TestCase):
    def test_valid(self):self.assertEqual(g.inspect_zip(g.zip_bytes({'a/b.txt':b'x'})),{'a/b.txt':b'x'})
    def test_duplicate_path(self):
        out=io.BytesIO()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            with zipfile.ZipFile(out,'w') as z:z.writestr('x',b'a');z.writestr('x',b'b')
        with self.assertRaisesRegex(g.Rejected,'DUPLICATE_ARCHIVE_PATH'):g.inspect_zip(out.getvalue())
    def test_symlink(self):
        out=io.BytesIO()
        with zipfile.ZipFile(out,'w') as z:
            i=zipfile.ZipInfo('alias');i.create_system=3;i.external_attr=(stat.S_IFLNK|0o777)<<16;z.writestr(i,b'target')
        with self.assertRaisesRegex(g.Rejected,'ARCHIVE_SPECIAL_FILE'):g.inspect_zip(out.getvalue())
    def test_nested_secret(self):
        raw=g.zip_bytes({'nested.zip':g.zip_bytes({'config.txt':('gh'+'p_'+'X'*30).encode()})})
        with self.assertRaisesRegex(g.Rejected,'CREDENTIAL_LIKE_CONTENT'):g.inspect_zip(raw)
    def test_depth(self):
        raw=g.zip_bytes({'x':b'x'})
        for _ in range(5):raw=g.zip_bytes({'nested.zip':raw})
        with self.assertRaisesRegex(g.Rejected,'ARCHIVE_NESTING_LIMIT'):g.inspect_zip(raw)
    def test_size_budget(self):
        with self.assertRaisesRegex(g.Rejected,'ARCHIVE_SIZE_LIMIT'):g.inspect_zip(g.zip_bytes({'x':b'xxxxx'}),budget=[2,10])
    def test_entry_budget(self):
        with self.assertRaisesRegex(g.Rejected,'ARCHIVE_ENTRY_LIMIT'):g.inspect_zip(g.zip_bytes({'x':b'x'}),budget=[100,0])
    def test_unknown_compression(self):
        with self.assertRaisesRegex(g.Rejected,'UNSUPPORTED_ARCHIVE'):g.scan('x.gz',b'unknown')
    def test_malformed_zip(self):
        with self.assertRaisesRegex(g.Rejected,'INVALID_ARCHIVE'):g.scan('x.zip',b'unknown')
for name,entries,code in [('case_collision',{'X':b'a','x':b'b'},'DUPLICATE_ARCHIVE_PATH'),
    ('file_parent',{'a':b'x','a/b':b'x'},'ARCHIVE_FILE_DIRECTORY_COLLISION'),
    ('traversal',{'../x':b'x'},'UNSAFE_PATH'),('absolute',{'/x':b'x'},'UNSAFE_PATH'),
    ('env',{'.env':b'synthetic'},'CREDENTIAL_LIKE_FILENAME'),('key',{'secret.key':b'synthetic'},'CREDENTIAL_LIKE_FILENAME'),
    ('nested_key',{'z.zip':g.zip_bytes({'secret.key':b'synthetic'})},'CREDENTIAL_LIKE_FILENAME')]:
    def test(self,entries=entries,code=code):
        with self.assertRaisesRegex(g.Rejected,code):g.inspect_zip(g.zip_bytes(entries))
    setattr(ArchiveTests,'test_'+name,test)

if __name__=='__main__':unittest.main(verbosity=2)
