"""Genuine synthetic processes/stdio only; no PostgreSQL, Docker or providers."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
from urllib.parse import urlunsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'qa'))
import pg_archive_admission as archive


class ArchiveAdmissionTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='collect-archive-admission-')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.control = self.root / 'control.json'
        self.calls = self.root / 'calls.jsonl'
        self.output = self.root / 'output'; self.output.mkdir(mode=0o700)
        self.source = self.root / 'synthetic-source-binding.json'
        self.source.write_text('{"synthetic_only":"not_live_approved"}\n')
        self.service = self.root / 'service'; self.password = self.root / 'password'
        self.password.write_text('*:*:*:*:synthetic-secret\n'); self.password.chmod(0o600)
        self.state = {'server': '170006', 'bytes': 196613}
        self.write_state()
        program = f'''#!{sys.executable}
import hashlib,json,os,subprocess,sys,time
from pathlib import Path
name=Path(sys.argv[0]).name
control=Path({str(self.control)!r});state=json.loads(control.read_text())
args=sys.argv[1:]
stage='version' if args==['--version'] else ('server' if any('server_version_num' in x for x in args) else ('list' if args==['--list'] else 'operation'))
row={{'tool':name,'stage':stage,'argv':args,'secret_env_names':[k for k in os.environ if k in ('PGPASSWORD','DATABASE_URL','SUPABASE_ACCESS_TOKEN','COLLECT_PSQL_URL','PYTHONPATH','BASH_ENV','LD_PRELOAD') or k.startswith('DYLD_')],'pgoptions':os.environ.get('PGOPTIONS')}}
if stage=='version':
    time.sleep(state.get('version_sleep_'+name,0))
    if state.get('first_version_detached_'+name):
        marker=Path(state['first_version_detached_'+name])
        if not marker.exists():
            child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(20)'],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            marker.write_text(json.dumps(dict(parent_pgid=os.getpgrp(),descendant_pid=child.pid)))
    row['credential_paths_present']=any(k in os.environ for k in ('PGSERVICEFILE','PGPASSFILE'))
    out=state.get('version_'+name,'17.6')
    with Path({str(self.calls)!r}).open('a') as f:f.write(json.dumps(row)+'\\n')
    print(name+' (PostgreSQL) '+out);sys.exit(0)
if stage=='server':
    if state.get('change_dump_version_on_server'):
        state['version_pg_dump']='17.7';control.write_text(json.dumps(state))
    if state.get('change_service_on_server'):Path({str(self.service)!r}).write_text('changed')
    if state.get('change_source_on_server'):Path({str(self.source)!r}).write_text('changed')
    if state.get('replace_archive_on_server'):
        p=Path(state['replace_archive_on_server']);q=p.with_suffix('.replacement');q.write_bytes(p.read_bytes());q.replace(p)
    time.sleep(state.get('server_sleep',0))
    out=(state['server']+'\\n').encode()
elif name=='pg_dump':
    if state.get('descendant'):
        child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(20)'])
        Path(state['descendant']).write_text(str(child.pid))
    time.sleep(state.get('dump_sleep',0))
    out=(b'PGDMP' if '--format=custom' in args else b'-- partial public export\\n')+b'x'*state['bytes']
else:
    data=sys.stdin.buffer.read();row['stdin_bytes']=len(data);row['stdin_sha256']=hashlib.sha256(data).hexdigest()
    out=b'1; 0 0 SCHEMA - public synthetic\\n' if stage=='list' else b'LOCAL_SYNTHETIC_RESTORE_CLIENT_DONE\\n'
with Path({str(self.calls)!r}).open('a') as f:f.write(json.dumps(row)+'\\n')
sys.stdout.buffer.write(out);sys.stdout.buffer.flush()
if state.get('stderr_'+name):sys.stderr.write('synthetic-secret: private fake diagnostic')
sys.exit(state.get('exit_'+name,0))
'''
        self.tools = {}
        for name in ('psql', 'pg_dump', 'pg_restore'):
            path = self.root / name; path.write_text(program); path.chmod(0o700); self.tools[name] = path
        self.targets = [{'kind':'local_rehearsal','project_ref':None,'host':'127.0.0.1','port':port,'user':'postgres','database':'postgres'} for port in (54321,54322)]
        self.set_service(self.targets[0])
        self.base_path = self.root / 'base-admission.json'
        self.base_value = {'schema_version':1,'kind':'collect_postgres_admission','review_reference':'synthetic-only/not-human-reviewed',
            'client':dict(self.ref(self.tools['psql']),version='17.6'),
            'server_matrix':[{'client_version':'17.6','server_version_num_min':170006,'server_version_num_max':170006,'operations':['query','migration']}],
            'targets':self.targets,'timeouts':{'version_seconds':1,'server_seconds':1,'operation_seconds':1}}
        self.base_path.write_text(json.dumps(self.base_value))
        self.manifest = self.root / 'archive-admission.json'
        self.value = {'schema_version':1,'kind':'collect_postgres_archive_admission','review_reference':'synthetic-only/not-human-reviewed',
            'adapter_sha256':self.sha(Path(archive.__file__)),'base_admission':self.ref(self.base_path),
            'clients':{n:dict(self.ref(self.tools[n]),version='17.6') for n in ('pg_dump','pg_restore')},
            'profiles':list(archive.PROFILES),'server_version_num':170006,'artifact_limit_bytes':1024**2,'tls_rootcert':None}
        self.job_path = self.root / 'operation-binding.json'
        now = dt.datetime.now(dt.timezone.utc)
        self.job = {'schema_version':1,'kind':'collect_postgres_archive_operation_binding','review_reference':'synthetic-only/not-human-reviewed',
            'approved_at_utc':(now-dt.timedelta(minutes=1)).isoformat(),'expires_at_utc':(now+dt.timedelta(hours=1)).isoformat(),
            'manifest_sha256':None,'operation':'dump','profiles':['full_custom'],'target':self.targets[0],
            'source_binding':self.ref(self.source),'output_directory':str(self.output),'input':None}
        self.env = dict(os.environ,PSQL_BIN=str(self.tools['psql']),PGSERVICEFILE=str(self.service),PGPASSFILE=str(self.password))
        self.bind()
        self.addCleanup(self.retain_safe_trace)

    def retain_safe_trace(self):
        directory=os.environ.get('COLLECT_ARCHIVE_TEST_TRACE_DIR')
        if not directory:return
        destination=Path(directory)/self._testMethodName;destination.mkdir(parents=True,exist_ok=False)
        for name,path in [('calls.jsonl',self.calls),('synthetic-manifest.json',self.manifest),('synthetic-operation-binding.json',self.job_path)]:
            if path.exists():(destination/name).write_bytes(path.read_bytes())
        receipts={}
        for path in sorted(self.root.rglob('*.admission.json')):
            receipts[str(path.relative_to(self.root))]=json.loads(path.read_text())
        (destination/'synthetic-receipts.json').write_text(json.dumps({'scope':'synthetic engineering fixtures; no live approval, customer/Auth/SQL/provider execution','receipts':receipts},indent=2)+'\n')

    def sha(self, path):return hashlib.sha256(path.read_bytes()).hexdigest()
    def ref(self, path):return {'path':str(path),'sha256':self.sha(path)}
    def write_state(self):self.control.write_text(json.dumps(self.state))
    def set_service(self, target):
        self.service.write_text('[collect_readiness]\n'+f"host={target['host']}\nport={target['port']}\nuser={target['user']}\ndbname={target['database']}\nsslmode=disable\n")
        self.service.chmod(0o600)
    def bind(self):
        self.manifest.write_text(json.dumps(self.value,sort_keys=True))
        self.job['manifest_sha256']=self.sha(self.manifest);self.job_path.write_text(json.dumps(self.job,sort_keys=True))
        self.env.update(COLLECT_POSTGRES_ARCHIVE_ADMISSION=str(self.manifest),COLLECT_POSTGRES_ARCHIVE_ADMISSION_SHA256=self.sha(self.manifest),
                        COLLECT_POSTGRES_ARCHIVE_OPERATION=str(self.job_path),COLLECT_POSTGRES_ARCHIVE_OPERATION_SHA256=self.sha(self.job_path))
    def admit(self):return archive.ArchiveAdmission.from_environment(self.env)
    def rows(self):return [json.loads(x) for x in self.calls.read_text().splitlines()] if self.calls.exists() else []
    def requests(self):return [r for r in self.rows() if r['stage']!='version']
    def args(self, profile='full_custom'):
        name, flags=archive.PROFILES[profile]
        return ['service=collect_readiness',*flags,'--file='+str(self.output/name)]
    def dump(self):return self.admit().execute(self.args(),self.env)
    def restore_job(self):
        receipt=self.output/'database.dump.admission.json';artifact=self.output/'database.dump'
        destination=self.root/'restore-output';destination.mkdir(mode=0o700)
        self.job.update(operation='restore',profiles=['restore_custom'],target=self.targets[1],output_directory=str(destination),
                        input={'archive':self.ref(artifact),'bytes':artifact.stat().st_size,'capture_receipt':self.ref(receipt)})
        self.set_service(self.targets[1]);self.bind()
        self.calls.unlink(missing_ok=True)
        return ['service=collect_readiness','--exit-on-error','--single-transaction',str(artifact)]

    def test_constructor_first_version_only_detached_child_refuses_before_request(self):
        marker=self.root/'first-version-group.json'
        self.state['first_version_detached_psql']=str(marker);self.write_state()
        started=time.monotonic()
        with self.assertRaisesRegex(archive.Refused,'RESIDUAL_PROCESS_GROUP'):
            self.admit()
        observed=json.loads(marker.read_text())
        with self.assertRaises(ProcessLookupError):os.killpg(observed['parent_pgid'],0)
        self.assertEqual([(r['tool'],r['stage']) for r in self.rows()],[('psql','version')])
        self.assertEqual(self.requests(),[]);self.assertEqual(list(self.output.iterdir()),[])
        self.assertLess(time.monotonic()-started,6)
        # The same unchanged executable is clean on its next version invocation.
        admitted=self.admit();self.assertEqual(admitted.base.operation,'query')
        self.assertEqual(self.requests(),[]);self.assertEqual(list(self.output.iterdir()),[])
        with self.calls.open('a') as stream:
            stream.write(json.dumps(dict(tool='constructor-first-version-observer',stage='version',**observed,
                                         owned_group_absent=True,no_database_request_or_artifact=True,
                                         unchanged_executable_second_constructor_pass=True))+'\n')

    def test_clean_constructor_keeps_base_version_and_target_validation(self):
        admitted=self.admit()
        self.assertEqual(admitted.base.operation,'query')
        self.assertEqual(admitted.job['target'],self.targets[0])
        self.assertEqual([(r['tool'],r['stage']) for r in self.rows()],
                         [('psql','version'),('psql','version'),('pg_dump','version'),('pg_restore','version')])
        self.assertEqual(self.requests(),[]);self.assertEqual(list(self.output.iterdir()),[])
        self.state['version_psql']='17.7';self.write_state()
        with self.assertRaisesRegex(archive.Refused,'PG_CLIENT_VERSION_UNKNOWN_OR_WRONG'):
            self.admit()
        self.assertEqual(self.requests(),[]);self.assertEqual(list(self.output.iterdir()),[])

    def test_base_probe_bridge_returns_code_stdout_and_refuses_inherited_stdin(self):
        sentinel=self.root/'unsupported-stdin-executed'
        with self.assertRaisesRegex(archive.Refused,'BASE_STDIN_UNSUPPORTED'):
            archive.pg.bounded(['/bin/sh','-c','touch '+str(sentinel)],archive.pg.local_environment(),1,1024,inherit_stdin=True)
        self.assertFalse(sentinel.exists())
        code,stdout=archive.pg.bounded(['/bin/sh','-c','printf clean'],archive.pg.local_environment(),1,1024)
        self.assertEqual((code,stdout),(0,b'clean'))
        with self.assertRaisesRegex(archive.Refused,'COMMAND_FAILED'):
            archive.pg.bounded(['/bin/sh','-c','exit 7'],archive.pg.local_environment(),1,1024)
        self.assertEqual(self.requests(),[]);self.assertEqual(list(self.output.iterdir()),[])

    def test_custom_dump_stream_and_receipt_then_local_restore_exact_input_and_order(self):
        receipt=self.dump();body=(self.output/'database.dump').read_bytes()
        self.assertEqual(len(body),196618);self.assertEqual(receipt['artifact']['sha256'],hashlib.sha256(body).hexdigest())
        self.assertEqual(receipt['client_version_num'],170006);self.assertFalse(receipt['production_ready'])
        self.assertFalse(receipt['full_catalog_ACL_projection_recovery_accepted'])
        self.assertEqual(stat.S_IMODE((self.output/'database.dump').stat().st_mode),0o600)
        self.assertEqual([r['stage'] for r in self.requests()],['server','operation'])
        args=self.restore_job();restored=self.admit().execute(args,self.env)
        rows=self.requests();self.assertEqual([(r['tool'],r['stage']) for r in rows],[('pg_restore','list'),('psql','server'),('pg_restore','operation')])
        self.assertEqual(rows[-1]['stdin_sha256'],receipt['artifact']['sha256']);self.assertEqual(rows[-1]['stdin_bytes'],196618)
        self.assertEqual(rows[-1]['argv'],['--dbname=service=collect_readiness','-w','--exit-on-error','--single-transaction'])
        self.assertFalse(restored['full_catalog_ACL_projection_recovery_accepted'])

    def test_partial_profiles_keep_exact_scope_and_reject_mixed_full_capture(self):
        self.job['profiles']=['public_schema','public_data'];self.bind();a=self.admit()
        for p in self.job['profiles']:
            result=a.execute(self.args(p),self.env);self.assertEqual(result['profile'],p)
            self.assertTrue((self.output/archive.PROFILES[p][0]).read_bytes().startswith(b'-- partial public export'))
        with self.assertRaisesRegex(archive.Refused,'ARGUMENT_SCOPE'):a.execute(self.args(),self.env)

    def test_dump_argument_bypasses_refuse_before_server_or_dump(self):
        a=self.admit()
        for args in [['postgresql://synthetic-secret@other/db'],self.args()+['--host=evil'],self.args()+['--dbname=evil'],self.args()+['--no-privileges'],
                     self.args()+['--snapshot=unbound'],self.args()+['--file=/tmp/escape'],['service=collect_readiness','--format=custom','--file='+str(self.output/'other')]]:
            with self.subTest(args=args),self.assertRaises(archive.Refused):a.execute(args,self.env)
        self.assertEqual(self.requests(),[])

    def test_restore_argument_bypasses_refuse_before_list_server_or_write(self):
        self.dump();args=self.restore_job();a=self.admit()
        for flag in ['--create','--clean','--role=postgres','--disable-triggers','--no-privileges','--use-list=other','--dbname=evil','--schema=public','--jobs=8']:
            with self.subTest(flag=flag),self.assertRaisesRegex(archive.Refused,'ARGUMENT_SCOPE'):a.execute(args+[flag],self.env)
        self.assertEqual(self.requests(),[])

    def test_forged_same_version_client_bytes_and_path_override_refuse_before_request(self):
        a=self.admit();self.tools['pg_dump'].write_bytes(self.tools['pg_dump'].read_bytes()+b'\n# forged same banner\n')
        with self.assertRaises(archive.Refused):a.execute(self.args(),self.env)
        self.assertEqual(self.requests(),[])

    def test_wrong_actual_version_even_when_tool_bytes_are_bound(self):
        self.state['version_pg_dump']='15.12';self.write_state()
        with self.assertRaisesRegex(archive.Refused,'VERSION_UNKNOWN'):self.admit()
        self.assertEqual(self.requests(),[])

    def test_version_state_drift_before_first_remote_observation_is_refused(self):
        a=self.admit();self.state['version_pg_restore']='17.7';self.write_state()
        with self.assertRaisesRegex(archive.Refused,'VERSION_UNKNOWN'):a.execute(self.args(),self.env)
        self.assertEqual(self.requests(),[])

    def test_version_state_drift_after_server_observation_refuses_before_operation(self):
        self.state['change_dump_version_on_server']=True;self.write_state()
        with self.assertRaisesRegex(archive.Refused,'VERSION_UNKNOWN'):self.dump()
        self.assertEqual([r['stage'] for r in self.requests()],['server'])

    def test_incompatible_or_forged_numeric_server_is_never_written(self):
        for number in ['170007','180001','170006 forged','unknown']:
            with self.subTest(number=number):
                self.calls.unlink(missing_ok=True);self.state['server']=number;self.write_state()
                with self.assertRaises(archive.Refused):self.dump()
                self.assertEqual([r['stage'] for r in self.requests()],['server'])

    def test_path_substitute_never_selected_and_explicit_overrides_refuse(self):
        evil=self.root/'evil';evil.mkdir();sentinel=self.root/'evil-ran'
        for name in ('psql','pg_dump','pg_restore'):
            p=evil/name;p.write_text('#!/bin/sh\n/bin/touch '+str(sentinel)+'\n');p.chmod(0o700)
        self.env['PATH']=str(evil);self.admit();self.assertFalse(sentinel.exists())
        for variable in ('PG_DUMP_BIN','PG_RESTORE_BIN'):
            self.env[variable]=str(evil/'pg_dump')
            with self.assertRaisesRegex(archive.Refused,'OVERRIDE_UNBOUND'):self.admit()
            self.env.pop(variable)
        self.assertEqual(self.requests(),[])

    def test_manifest_job_and_source_drift_refuse_before_first_request(self):
        for path in (self.manifest,self.job_path,self.source):
            original=path.read_bytes();a=self.admit();path.write_bytes(original+b' ')
            with self.assertRaises(archive.Refused):a.execute(self.args(),self.env)
            path.write_bytes(original)
        self.assertEqual(self.requests(),[])

    def test_same_byte_client_inode_substitution_and_symlink_refuse(self):
        a=self.admit();path=self.tools['pg_dump'];replacement=self.root/'replacement';replacement.write_bytes(path.read_bytes());replacement.chmod(0o700);replacement.replace(path)
        with self.assertRaisesRegex(archive.Refused,'IDENTITY_CHANGED'):a.execute(self.args(),self.env)
        original=self.root/'original';path.rename(original);path.symlink_to(original)
        with self.assertRaisesRegex(archive.Refused,'SYMLINK'):self.admit()
        self.assertEqual(self.requests(),[])

    def test_unsupported_cohort_and_operation_are_not_manifest_expandable(self):
        self.value['server_version_num']=180001;self.bind()
        with self.assertRaisesRegex(archive.Refused,'OUTSIDE_PROPOSED_COHORT'):self.admit()
        self.value['server_version_num']=170006;self.value['clients']['pg_dump']['version']='latest';self.bind()
        with self.assertRaisesRegex(archive.Refused,'OUTSIDE_PROPOSED_COHORT'):self.admit()
        self.assertEqual(self.requests(),[])

    def test_wrong_service_target_options_or_permissions_refuse_before_request(self):
        a=self.admit();self.set_service(self.targets[1])
        with self.assertRaisesRegex(archive.Refused,'TARGET_MISMATCH'):a.execute(self.args(),self.env)
        self.set_service(self.targets[0]);self.service.chmod(0o644)
        with self.assertRaisesRegex(archive.Refused,'PERMISSIONS'):a.execute(self.args(),self.env)
        self.service.chmod(0o600);self.service.write_text(self.service.read_text()+'hostaddr=evil\n')
        with self.assertRaises(archive.Refused):a.execute(self.args(),self.env)
        self.assertEqual(self.requests(),[])

    def test_service_source_changes_during_read_never_reach_dump(self):
        for setting in ('change_service_on_server','change_source_on_server'):
            with self.subTest(setting=setting):
                self.calls.unlink(missing_ok=True);self.state={setting:True,'server':'170006','bytes':100};self.write_state();self.set_service(self.targets[0]);self.source.write_text('{"synthetic_only":"not_live_approved"}\n')
                with self.assertRaises(archive.Refused):self.dump()
                self.assertEqual([r['stage'] for r in self.requests()],['server'])

    def test_credentials_and_loader_environment_are_absent_from_versions_and_operations(self):
        self.env.update(PGPASSWORD='synthetic-secret',DATABASE_URL='synthetic-secret',SUPABASE_ACCESS_TOKEN='synthetic-secret',COLLECT_PSQL_URL='synthetic-secret',
                        PYTHONPATH='synthetic-secret',BASH_ENV='synthetic-secret',DYLD_INSERT_LIBRARIES='synthetic-secret',PGOPTIONS='-c search_path=evil')
        self.dump()
        for row in self.rows():
            self.assertEqual(row['secret_env_names'],[])
            if row['stage']=='version':self.assertFalse(row['credential_paths_present'])
        self.assertEqual(self.requests()[-1]['pgoptions'],'-c default_transaction_read_only=on -c statement_timeout=120000')

    def test_hosted_restore_without_a_shipping_adapter_refuses_before_any_tool(self):
        self.job.update(operation='restore',profiles=['restore_custom'],target={'kind':'supabase','project_ref':'a'*20},input={});self.bind()
        with self.assertRaisesRegex(archive.Refused,'HOSTED_RESTORE_ADAPTER_ABSENT'):self.admit()
        self.assertEqual(self.rows(),[])

    def test_expired_operation_and_unbound_hash_refuse_before_tools(self):
        self.job['expires_at_utc']=(dt.datetime.now(dt.timezone.utc)-dt.timedelta(seconds=1)).isoformat();self.bind()
        with self.assertRaisesRegex(archive.Refused,'EXPIRED'):self.admit()
        self.env.pop('COLLECT_POSTGRES_ARCHIVE_OPERATION_SHA256')
        with self.assertRaises(archive.Refused):self.admit()
        self.assertEqual(self.rows(),[])

    def test_restore_archive_and_receipt_drift_are_not_rebound_by_caller(self):
        self.dump();args=self.restore_job();a=self.admit();path=Path(self.job['input']['archive']['path']);old=path.read_bytes();path.write_bytes(old+b'changed')
        with self.assertRaises(archive.Refused):a.execute(args,self.env)
        self.assertEqual(self.requests(),[])

    def test_restore_same_bytes_inode_swap_after_server_read_stops_before_write(self):
        self.dump();args=self.restore_job();self.state['replace_archive_on_server']=self.job['input']['archive']['path'];self.write_state()
        with self.assertRaisesRegex(archive.Refused,'RESTORE_INPUT_CHANGED'):self.admit().execute(args,self.env)
        self.assertEqual([r['stage'] for r in self.requests()],['list','server'])

    def test_restore_capture_binding_must_match_full_profile_and_source(self):
        self.dump();self.restore_job();p=Path(self.job['input']['capture_receipt']['path']);v=json.loads(p.read_text());v['profile']='public_schema';p.write_text(json.dumps(v));self.job['input']['capture_receipt']=self.ref(p);self.bind()
        with self.assertRaisesRegex(archive.Refused,'CAPTURE_RECEIPT_MISMATCH'):self.admit()
        self.assertEqual(self.requests(),[])

    def test_real_stdout_overflow_and_stderr_warning_leave_no_artifact_or_receipt(self):
        self.value['artifact_limit_bytes']=1024;self.bind()
        with self.assertRaisesRegex(archive.Refused,'STDOUT_LIMIT'):self.dump()
        self.assertEqual(list(self.output.iterdir()),[])
        self.value['artifact_limit_bytes']=1024**2;self.bind();self.state['stderr_pg_dump']=True;self.write_state()
        with self.assertRaisesRegex(archive.Refused,'WARNINGS_REFUSED') as caught:self.dump()
        self.assertNotIn('synthetic-secret',str(caught.exception));self.assertEqual(list(self.output.iterdir()),[])

    def test_real_operation_timeout_and_early_exit_are_bounded_without_receipt(self):
        self.base_value['timeouts']['operation_seconds']=0.1;self.base_path.write_text(json.dumps(self.base_value));self.value['base_admission']=self.ref(self.base_path);self.bind()
        self.state['dump_sleep']=20;self.write_state();started=time.monotonic()
        with self.assertRaisesRegex(archive.Refused,'TIMEOUT'):self.dump()
        self.assertLess(time.monotonic()-started,3);self.assertEqual(list(self.output.iterdir()),[])
        self.state.pop('dump_sleep');self.state['exit_pg_dump']=7;self.write_state()
        with self.assertRaisesRegex(archive.Refused,'COMMAND_FAILED'):self.dump()
        self.assertEqual(list(self.output.iterdir()),[])

    def test_real_descendant_holding_stdio_is_killed_with_its_owned_group(self):
        pidfile=self.root/'descendant.pid';self.state['descendant']=str(pidfile);self.write_state()
        self.base_value['timeouts']['operation_seconds']=0.2;self.base_path.write_text(json.dumps(self.base_value));self.value['base_admission']=self.ref(self.base_path);self.bind()
        with self.assertRaisesRegex(archive.Refused,'TIMEOUT'):self.dump()
        result=subprocess.run(['/bin/ps','-o','stat=','-p',pidfile.read_text()],capture_output=True,timeout=2)
        state=result.stdout.decode().strip();self.assertTrue(not state or state.startswith('Z'),state)
        self.assertEqual(list(self.output.iterdir()),[])

    def test_existing_artifact_and_output_directory_escape_refuse_without_request(self):
        a=self.admit();path=self.output/'database.dump';path.write_text('human-owned-existing')
        with self.assertRaisesRegex(archive.Refused,'OUTPUT_EXISTS'):a.execute(self.args(),self.env)
        self.assertEqual(path.read_text(),'human-owned-existing');self.assertEqual(self.requests(),[])
        self.output.chmod(0o777)
        with self.assertRaisesRegex(archive.Refused,'PERMISSIONS'):a.execute(self.args(),self.env)

    def test_actual_partial_export_wiring_keeps_public_scope_and_private_receipts(self):
        self.job['profiles']=['public_schema','public_data'];self.bind()
        env=dict(self.env,COLLECT_POSTGRES_ARCHIVE_PYTHON=sys.executable,INCLUDE_DATA='1',
                 DATABASE_URL=urlunsplit(('postgresql', 'postgres:synthetic-secret@127.0.0.1:54321',
                                         '/postgres', 'sslmode=disable', '')))
        script=Path(__file__).resolve().parents[1]/'supabase_logical_backup.sh'
        result=subprocess.run(['/bin/bash',str(script),'--confirm-partial-export'],env=env,capture_output=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr.decode())
        self.assertIn(b'NOT a full recovery backup',result.stdout)
        self.assertNotIn(b'synthetic-secret',result.stdout+result.stderr)
        self.assertEqual([(r['tool'],r['stage']) for r in self.requests()],[('psql','server'),('pg_dump','operation'),('psql','server'),('pg_dump','operation')])
        for name in ('public_schema.sql','public_data.sql'):
            p=self.output/(name+'.admission.json');self.assertTrue(p.exists());self.assertEqual(stat.S_IMODE(p.stat().st_mode),0o600)

    def test_actual_archive_cli_refuses_operation_mixup_before_any_remote_read(self):
        command=[sys.executable,'-I','-B',archive.__file__,'restore','--',*self.args()]
        result=subprocess.run(command,env=self.env,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,1);self.assertIn(b'OPERATION_SCOPE_INVALID',result.stderr)
        self.assertEqual(self.requests(),[])

    def test_output_directory_parent_symlink_substitution_refuses_before_request(self):
        a=self.admit();self.output.rmdir();target=self.root/'other';target.mkdir(mode=0o700);self.output.symlink_to(target,target_is_directory=True)
        with self.assertRaisesRegex(archive.Refused,'PRIVATE_DIRECTORY'):a.execute(self.args(),self.env)
        self.assertEqual(self.requests(),[]);self.assertEqual(list(target.iterdir()),[])

    def test_real_success_parent_with_detached_stdio_descendant_refuses_and_removes_group(self):
        identity=self.root/'detached-group.json';program=self.root/'detached-parent'
        program.write_text(f"#!{sys.executable}\nimport json,os,subprocess,sys\nfrom pathlib import Path\nchild=subprocess.Popen([sys.executable,'-c','import time;time.sleep(20)'],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\nPath({str(identity)!r}).write_text(json.dumps(dict(parent_pgid=os.getpgrp(),descendant_pid=child.pid)))\nsys.stdout.buffer.write(b'PGDMP');sys.stdout.buffer.flush()\n")
        program.chmod(0o700);started=time.monotonic()
        with self.assertRaisesRegex(archive.Refused,'RESIDUAL_PROCESS_GROUP'):
            archive.run([str(program)],archive.pg.local_environment(),2,1024)
        observed=json.loads(identity.read_text())
        with self.assertRaises(ProcessLookupError):os.killpg(observed['parent_pgid'],0)
        elapsed=time.monotonic()-started;self.assertLess(elapsed,7)
        self.calls.write_text(json.dumps(dict(tool='genuine_detached_stdio_process',stage='runner_refusal',**observed,owned_group_absent=True,elapsed_seconds=elapsed,operation_bound_seconds=2,cleanup_bound_seconds=5))+'\n')

    def test_real_parent_completion_delivered_after_deadline_never_returns_success(self):
        original=archive.subprocess.Popen
        def delayed_wait(*args,**kwargs):
            process=original(*args,**kwargs);wait=process.wait;first=True
            def observed_wait(*a,**k):
                nonlocal first
                code=wait(*a,**k)
                if first:
                    first=False;time.sleep(1.05)
                return code
            process.wait=observed_wait
            return process
        started=time.monotonic()
        with mock.patch.object(archive.subprocess,'Popen',delayed_wait),self.assertRaisesRegex(archive.Refused,'COMMAND_TIMEOUT'):
            archive.run(['/bin/sh','-c','exit 0'],archive.pg.local_environment(),1,1024)
        elapsed=time.monotonic()-started;self.assertGreater(elapsed,1);self.assertLess(elapsed,3)
        self.calls.write_text(json.dumps(dict(tool='genuine_shell_with_delayed_wait_observer',stage='runner_refusal',elapsed_seconds=elapsed,operation_bound_seconds=1,injected_observer_delay_seconds=1.05,refusal='PG_ARCHIVE_COMMAND_TIMEOUT'))+'\n')

    def test_real_clean_stdio_completion_returns_exact_bytes_after_group_absence(self):
        started=time.monotonic()
        raw,count=archive.run(['/bin/sh','-c','printf PGDMP'],archive.pg.local_environment(),1,1024)
        self.assertEqual(raw,b'PGDMP');self.assertEqual(count,5);self.assertLess(time.monotonic()-started,1)
        self.calls.write_text(json.dumps(dict(tool='genuine_shell',stage='runner_success',stdout_bytes=count,operation_bound_seconds=1,group_absence_checked_by_runner=True))+'\n')

    def test_real_minimal_stdio_overflow_warning_and_timeout_keep_original_bounds(self):
        with self.assertRaisesRegex(archive.Refused,'STDOUT_LIMIT'):
            archive.run(['/bin/sh','-c','printf 123456789'],archive.pg.local_environment(),1,4)
        with self.assertRaisesRegex(archive.Refused,'WARNINGS_REFUSED') as caught:
            archive.run(['/bin/sh','-c','printf synthetic-private-diagnostic >&2'],archive.pg.local_environment(),1,1024)
        self.assertNotIn('synthetic-private-diagnostic',str(caught.exception))
        started=time.monotonic()
        with self.assertRaisesRegex(archive.Refused,'COMMAND_TIMEOUT'):
            archive.run(['/bin/sh','-c','exec /bin/sleep 20'],archive.pg.local_environment(),0.05,1024)
        self.assertLess(time.monotonic()-started,2)
        self.calls.write_text(json.dumps(dict(tool='genuine_shell_stdio',stage='runner_refusal',overflow_limit_bytes=4,timeout_seconds=0.05,warnings_scrubbed=True))+'\n')

    def test_real_stream_close_delivered_after_deadline_never_returns_success(self):
        original=archive.subprocess.Popen
        class DelayedClose:
            def __init__(self,stream):self.stream=stream
            def fileno(self):return self.stream.fileno()
            def close(self):
                self.stream.close();time.sleep(1.05)
        def delayed_close(*args,**kwargs):
            process=original(*args,**kwargs);process.stdout=DelayedClose(process.stdout);return process
        started=time.monotonic()
        with mock.patch.object(archive.subprocess,'Popen',delayed_close),self.assertRaisesRegex(archive.Refused,'COMMAND_TIMEOUT'):
            archive.run(['/bin/sh','-c','exit 0'],archive.pg.local_environment(),1,1024)
        elapsed=time.monotonic()-started;self.assertGreater(elapsed,1);self.assertLess(elapsed,3)
        self.calls.write_text(json.dumps(dict(tool='genuine_shell_with_delayed_stream_close_observer',stage='runner_refusal',elapsed_seconds=elapsed,operation_bound_seconds=1,injected_observer_delay_seconds=1.05,refusal='PG_ARCHIVE_COMMAND_TIMEOUT'))+'\n')

    def test_signal_permission_refusal_remains_fatal_while_owned_group_exists(self):
        original_popen=archive.subprocess.Popen;original_killpg=archive.os.killpg;owned=[]
        def captured(*a,**k):
            p=original_popen(*a,**k);owned.append(p);return p
        def refuse_kill(pgid,sig):
            if sig==9:raise PermissionError(1,'synthetic live-group signalling refusal')
            return original_killpg(pgid,sig)
        try:
            with mock.patch.object(archive.subprocess,'Popen',captured),mock.patch.object(archive.os,'killpg',refuse_kill),self.assertRaises(PermissionError):
                archive.run(['/bin/sh','-c','exec /bin/sleep 20'],archive.pg.local_environment(),0.05,1024)
            self.assertIsNone(owned[0].poll());self.assertTrue(archive.group_exists(owned[0].pid))
        finally:
            for p in owned:
                try:original_killpg(p.pid,9)
                except ProcessLookupError:pass
                p.wait(timeout=2)
                self.assertFalse(archive.group_exists(p.pid))
        self.calls.write_text(json.dumps(dict(tool='genuine_sleep_with_injected_live_group_EPERM',stage='runner_refusal',EPERM_fatal_while_group_exists=True,owned_group_removed_by_test_finally=True,operation_bound_seconds=0.05))+'\n')

    def hosted_fixture(self):
        ref='abcdefghijklmnopqrst';target={'kind':'supabase','project_ref':ref,'host':f'db.{ref}.supabase.co','port':5432,'user':'postgres','database':'postgres'}
        self.base_value['targets'].append(target);self.base_path.write_text(json.dumps(self.base_value));self.value['base_admission']=self.ref(self.base_path)
        self.job['target']=target;self.env['SUPABASE_PROJECT_REF']=ref
        self.set_service(target);self.bind()
        return target

    def test_hosted_dump_requires_verify_full_and_exact_pinned_rootcert_before_request(self):
        self.hosted_fixture();a=self.admit()
        with self.assertRaisesRegex(archive.Refused,'HOSTED_PINNED_TLS_REQUIRED'):a.execute(self.args(),self.env)
        self.assertEqual(self.requests(),[])
        cert=self.root/'synthetic-rootcert';cert.write_text('synthetic fixture certificate; no real TLS connection')
        self.value['tls_rootcert']=self.ref(cert);self.bind()
        self.service.write_text(self.service.read_text().replace('sslmode=disable','sslmode=verify-full')+'sslrootcert='+str(cert)+'\n')
        self.assertEqual(self.dump()['target']['kind'],'supabase')
        self.assertEqual([r['stage'] for r in self.requests()],['server','operation'])

    def test_pinned_rootcert_drift_refuses_before_first_request(self):
        self.hosted_fixture();cert=self.root/'synthetic-rootcert';cert.write_text('synthetic fixture certificate')
        self.value['tls_rootcert']=self.ref(cert);self.bind()
        self.service.write_text(self.service.read_text().replace('sslmode=disable','sslmode=verify-full')+'sslrootcert='+str(cert)+'\n')
        a=self.admit();cert.write_text('changed synthetic fixture certificate')
        with self.assertRaisesRegex(archive.Refused,'BINDING_CHANGED'):a.execute(self.args(),self.env)
        self.assertEqual(self.requests(),[])


if __name__ == '__main__':
    unittest.main()
