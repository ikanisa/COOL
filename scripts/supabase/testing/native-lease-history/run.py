#!/usr/bin/env python3
"""Disposable 033-schema native-work SQL qualification; never live writes."""
from pathlib import Path
import hashlib,json,os,subprocess,sys,time,uuid
import re
TEST_ROOT=Path(__file__).resolve().parent
REPO=TEST_ROOT.parents[3]
def required_path(name):
 value=os.environ.get(name,'')
 if not value or not Path(value).is_absolute():raise RuntimeError(name+' must be an absolute path')
 return Path(value).resolve(strict=True)
FIX=required_path('COLLECT_NATIVE_HISTORY_FIXTURE_DIR')
PREDECESSOR=required_path('COLLECT_NATIVE_HISTORY_PREDECESSOR_MIGRATIONS')
evidence_value=os.environ.get('COLLECT_NATIVE_HISTORY_EVIDENCE_DIR','')
if not evidence_value or not Path(evidence_value).is_absolute():raise RuntimeError('COLLECT_NATIVE_HISTORY_EVIDENCE_DIR must be absolute')
evidence_path=Path(evidence_value)
EVIDENCE=evidence_path.parent.resolve(strict=True)/evidence_path.name
if EVIDENCE.exists():raise RuntimeError('evidence directory already exists')
context=os.environ.get('COLLECT_NATIVE_HISTORY_DOCKER_CONTEXT','')
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,80}',context):raise RuntimeError('explicit Docker context required')
D=['docker','--context',context]
suffix=uuid.uuid4().hex[:24];name='collect-native-work-qa-'+suffix;database='collect_burimunsi_'+suffix+'_test'
source='a'*64;baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3'
image='sha256:c141fd17ac6a76c4323e90b3aee8ff1a23d2e89e547c2b963cfadc309c079cc2'
limit=3*2**30+48*2**20
extra_paths=json.loads(os.environ.get('COLLECT_NATIVE_HISTORY_RESERVE_PATHS','[]'))
if not isinstance(extra_paths,list) or not extra_paths or any(not isinstance(p,str) or not Path(p).is_absolute() for p in extra_paths):
 raise RuntimeError('COLLECT_NATIVE_HISTORY_RESERVE_PATHS must be a nonempty JSON array of absolute paths')
paths={str(i):str(p) for i,p in enumerate([Path('/'),REPO,FIX,PREDECESSOR,EVIDENCE.parent,*[Path(p).resolve(strict=True) for p in extra_paths]])}
minimum={k:2**63-1 for k in paths};cid=None;events=[];error=None;os.umask(0o077)
def reserve():
 for k,path in paths.items():
  s=os.statvfs(path);n=s.f_bavail*s.f_frsize;minimum[k]=min(minimum[k],n)
  if n<limit:raise RuntimeError('storage reserve reached: '+k)
def run(args,data=None,timeout=90,check=True):
 reserve();p=subprocess.Popen(D+args,stdin=subprocess.PIPE if data is not None else subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 start=time.monotonic();first=True
 while True:
  try:out,err=p.communicate(input=data if first else None,timeout=.25);break
  except subprocess.TimeoutExpired:
   first=False
   try:reserve()
   except BaseException:p.kill();p.communicate();raise
   if time.monotonic()-start>timeout:p.kill();p.communicate();raise RuntimeError('Docker command timeout: '+args[0])
 if check and p.returncode:raise RuntimeError('Docker '+args[0]+' failed: '+(err+out).decode(errors='replace')[-2500:])
 return p.returncode,out,err
def sql(input,user='supabase_admin',db=database):
 return run(['exec','-i',cid,'psql','-h','/tmp','-U',user,'-d',db,'-XAtq','-v','ON_ERROR_STOP=1'],input.encode(),timeout=45)[1].decode().strip()
reserve()
EVIDENCE.mkdir(mode=0o700,exist_ok=False)
try:
 for filename,expected in [('schema-only.dump','5b60d0ac5989b5c4e47fd016377548b91defeb139d3b2cfd1e33774b7ae08d9e'),('synthetic-roles.sql','766c714dad3691c42850f06b70dacd2f782957a42ce8340b1c1f6a91b9de2081')]:
  if hashlib.sha256((FIX/filename).read_bytes()).hexdigest()!=expected:raise RuntimeError('fixture hash changed: '+filename)
 hashes=lambda p:{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in p.glob('*.sql') if x.name<='20261113130200_burimunsi_account_sms_history.sql'}
 if len(hashes(PREDECESSOR))!=52 or hashes(PREDECESSOR)!=hashes(REPO/'supabase/migrations'):
  raise RuntimeError('exact 033 predecessor migration source differs')
 pinned={
  '20261113130300_burimunsi_native_financial_work.sql':'91eef9b7c14172da6dd55da1f15d1db735077d6685b46813fd97d38982c50625',
  '20261113130400_burimunsi_native_financial_custody.sql':'01dece71d7152fd82f8d51d6626e4fd386edd3313ced588e9858ad07ac16ff05',
  '20261113130500_burimunsi_native_work_discovery.sql':'60a69f083659344521ee259175349cbca5da43366217ef882c8aebad78fca0a7',
  '20261113130600_burimunsi_native_work_retention_inspection.sql':'afcc2f76a37dd7b906f0b24390a42e8f135919dc88825ef2b2f3133f1b3e94bb',
  '20261113130700_storage_iceberg_retention_inspection.sql':'c2ba8c74e06046751483e08e9f8b278006e0a663598aeb5ce02d0b214af65402',
  '20261113130800_burimunsi_native_lease_history.sql':'63594a016df890437b6f98f2b68657c73252492435e686fb9166898acd508687'}
 for name,expected in pinned.items():
  if hashlib.sha256((REPO/'supabase/migrations'/name).read_bytes()).hexdigest()!=expected:
   raise RuntimeError('reviewed migration bytes changed: '+name)
 args=['create','--pull','never','--name',name,'--label','io.collect.native-work-qa='+suffix,'--network','none','--memory','768m','--cpus','1','--user','postgres','--tmpfs','/tmp:rw,size=256m,mode=1777','--env','PGDATA=/tmp/pgdata','--entrypoint','sh',image,'-c','initdb -D "$PGDATA" -U supabase_admin -A trust --encoding=UTF8 --no-locale >/dev/null && exec postgres -D "$PGDATA" -c listen_addresses= -c unix_socket_directories=/tmp']
 _,out,_=run(args);cid=out.decode().strip();_,out,_=run(['inspect',cid]);obj=json.loads(out)[0]
 if obj['Config']['Labels'].get('io.collect.native-work-qa')!=suffix or obj['HostConfig']['NetworkMode']!='none' or obj['HostConfig'].get('Binds') or obj['HostConfig'].get('PortBindings'):raise RuntimeError('fixture isolation failed')
 run(['start',cid])
 for _ in range(100):
  rc,_,_=run(['exec',cid,'pg_isready','-h','/tmp','-U','supabase_admin'],timeout=5,check=False)
  if rc==0:break
  time.sleep(.2)
 else:raise RuntimeError('fixture did not start')
 sql((FIX/'synthetic-roles.sql').read_text(),db='postgres')
 sql('GRANT collect_runtime TO postgres WITH SET TRUE;',db='postgres')
 sql('CREATE DATABASE '+database+' OWNER postgres;',db='postgres')
 run(['exec','-i',cid,'pg_restore','--single-transaction','--exit-on-error','--no-password','-h','/tmp','-U','supabase_admin','-d',database],(FIX/'schema-only.dump').read_bytes(),timeout=90)
 # The schema-only backup omits this singleton created by a historical migration.
 # Its ALWAYS guard is restored before any application work or migration.
 sql('BEGIN; ALTER TABLE private.collect_fence_admission_totals DISABLE TRIGGER collect_archive_totals_guard; INSERT INTO private.collect_fence_admission_totals VALUES(true,0,0); ALTER TABLE private.collect_fence_admission_totals ENABLE ALWAYS TRIGGER collect_archive_totals_guard; COMMIT;')
 if sql("SELECT tgenabled FROM pg_trigger WHERE tgrelid='private.collect_fence_admission_totals'::regclass AND tgname='collect_archive_totals_guard';")!='A':raise RuntimeError('guard not restored')
 init=str(uuid.uuid4());freeze=str(uuid.uuid4());release=str(uuid.uuid4())
 sql("SELECT private.collect_fence_initialize('"+init+"','"+source+"','"+baseline+"');",user='postgres')
 sql("SELECT private.collect_fence_begin_quiesce('"+freeze+"',1,'"+source+"');",user='postgres')
 sql("SELECT private.collect_fence_drain('"+freeze+"',1,'"+source+"');",user='postgres')
 if sql('SELECT mode FROM private.collect_fence_control;',user='postgres')!='fenced':raise RuntimeError('fence did not drain')
 migration=REPO/'supabase/migrations/20261113130300_burimunsi_native_financial_work.sql'
 sql(migration.read_text(),user='postgres')
 events.append({'migration':'PASS','sha256':hashlib.sha256(migration.read_bytes()).hexdigest(),'predecessor':'pinned-032-schema-only/033-migrations-identical'})
 custody=REPO/'supabase/migrations/20261113130400_burimunsi_native_financial_custody.sql'
 if hashlib.sha256(custody.read_bytes()).hexdigest()!='01dece71d7152fd82f8d51d6626e4fd386edd3313ced588e9858ad07ac16ff05':raise RuntimeError('custody migration changed')
 sql(custody.read_text(),user='postgres')
 events.append({'custody_migration':'PASS','sha256':hashlib.sha256(custody.read_bytes()).hexdigest()})
 discovery=REPO/'supabase/migrations/20261113130500_burimunsi_native_work_discovery.sql'
 if discovery.exists():
  sql(discovery.read_text(),user='postgres')
  events.append({'discovery_migration':'PASS','sha256':hashlib.sha256(discovery.read_bytes()).hexdigest()})
 retention=REPO/'supabase/migrations/20261113130600_burimunsi_native_work_retention_inspection.sql'
 sql(retention.read_text(),user='postgres')
 events.append({'retention_migration':'PASS','sha256':hashlib.sha256(retention.read_bytes()).hexdigest()})
 history_migration=REPO/'supabase/migrations/20261113130800_burimunsi_native_lease_history.sql'
 def reject_history_migration(expected):
  rc,out,err=run(['exec','-i',cid,'psql','-h','/tmp','-U','postgres','-d',database,'-XAtq','-v','ON_ERROR_STOP=1'],
   history_migration.read_bytes(),timeout=45,check=False)
  if rc==0 or expected.encode() not in err or sql("SELECT to_regclass('private.burimunsi_native_lease_history') IS NULL;",user='postgres')!='t':
   raise RuntimeError('history precondition did not fail closed: '+(err+out).decode(errors='replace')[-1000:])
 reject_history_migration('native_lease_history_predecessor_changed')
 for name in ['20261113130700_storage_iceberg_retention_inspection.sql']:
  migration=REPO/'supabase/migrations'/name
  sql(migration.read_text(),user='postgres')
  events.append({'additive_migration':name,'sha256':hashlib.sha256(migration.read_bytes()).hexdigest()})
 sql('ALTER FUNCTION private.burimunsi_native_work_assert(uuid,uuid,bigint) SECURITY INVOKER;',user='postgres')
 reject_history_migration('native_lease_history_predecessor_changed')
 sql('ALTER FUNCTION private.burimunsi_native_work_assert(uuid,uuid,bigint) SECURITY DEFINER;',user='postgres')
 # The blocked retention class depends on both the schema census and the row
 # policy.  Replacing either exact body must refuse the migration atomically.
 for sig,decl in [
  ('private._retention_manifest_schema_v2()', 'private._retention_manifest_schema_v2()'),
  ('private._retention_row_policy_v2(uuid,text,text,text)', 'private._retention_row_policy_v2(p_manifest uuid,p_sha text,p_environment text,p_source text)')]:
  original=sql("SELECT pg_get_functiondef('"+sig+"'::regprocedure);",user='postgres')
  sql("CREATE OR REPLACE FUNCTION "+decl+" RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$ BEGIN RETURN '{}'::jsonb; END $$;",user='postgres')
  reject_history_migration('native_lease_history_predecessor_changed')
  sql(original,user='postgres')
 for sig,security,path in [
  ('private.burimunsi_native_work_immutable()','INVOKER','pg_catalog'),
  ('private._collect_fence_no_erasure()','DEFINER','pg_catalog,pg_temp'),
  ('private._collect_fence_statement()','DEFINER','pg_catalog,pg_temp'),
  ('private._burimunsi_native_grant_write_guard()','DEFINER','pg_catalog,pg_temp')]:
  original=sql("SELECT pg_get_functiondef('"+sig+"'::regprocedure);",user='postgres')
  sql('CREATE OR REPLACE FUNCTION '+sig+' RETURNS trigger LANGUAGE plpgsql VOLATILE SECURITY '+security+' SET search_path='+path+' AS $$ BEGIN RETURN NEW; END $$;',user='postgres')
  reject_history_migration('native_lease_history_predecessor_changed')
  sql(original,user='postgres')
 sql('DROP TRIGGER native_work_immutable ON private.burimunsi_native_financial_work; CREATE TRIGGER native_work_immutable BEFORE UPDATE ON private.burimunsi_native_financial_work FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_work_immutable(); ALTER TABLE private.burimunsi_native_financial_work ENABLE ALWAYS TRIGGER native_work_immutable;',user='postgres')
 reject_history_migration('native_lease_history_schema_changed')
 sql('DROP TRIGGER native_work_immutable ON private.burimunsi_native_financial_work; CREATE TRIGGER native_work_immutable BEFORE UPDATE OR DELETE ON private.burimunsi_native_financial_work FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_work_immutable(); ALTER TABLE private.burimunsi_native_financial_work ENABLE ALWAYS TRIGGER native_work_immutable;',user='postgres')
 sql('ALTER TABLE private.burimunsi_native_financial_work DISABLE TRIGGER native_work_immutable;',user='postgres')
 reject_history_migration('native_lease_history_schema_changed')
 sql('ALTER TABLE private.burimunsi_native_financial_work ENABLE ALWAYS TRIGGER native_work_immutable;',user='postgres')
 events.append({'predecessor_guards':'PASS','wrong_order_rejected':True,'changed_function_authority_rejected':True,'retention_schema_body_tamper_rejected':True,'retention_row_policy_body_tamper_rejected':True,'guard_function_body_tampering_rejected':4,'changed_trigger_events_rejected':True,'disabled_immutable_trigger_rejected':True})
 sql("SELECT private.collect_fence_release('"+release+"',1,'"+source+"');",user='postgres')
 # Create an actual pre-308 lease and clear it before the next fenced upgrade.
 # Its grant attribution must remain unknown; the migration must not backfill it.
 seed=TEST_ROOT/'native-work-seed.sql';bootstrap=TEST_ROOT/'native-admin-bootstrap.sql'
 sql(seed.read_text(),user='supabase_admin')
 old_job_admission=str(uuid.uuid4());old_admin_admission=str(uuid.uuid4())
 def register(admission,kind):
  sql("BEGIN; SET LOCAL ROLE collect_runtime; SELECT set_config('collect.edge_verified','true',true); SELECT private.collect_fence_register('"+admission+"','"+source+"','"+kind+"'); COMMIT;",user='postgres')
 def frame(admission,epoch):
  return ("BEGIN; SELECT pg_advisory_xact_lock_shared(7346371,1); SET LOCAL ROLE collect_runtime; "
   "SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id','"+admission+"',true),"
   "set_config('collect.fence_epoch','"+str(epoch)+"',true),set_config('collect.fence_source_sha256','"+source+"',true),"
   "set_config('burimunsi.collection_id','synthetic-group',true); ")
 def value(out):return json.loads(next(x for x in reversed(out.splitlines()) if x.startswith('{')))
 register(old_job_admission,'jobs');register(old_admin_admission,'http_admin')
 sql(bootstrap.read_text().replace('__ADMIN_ADMISSION__',old_admin_admission).replace('__ADMISSION_SOURCE__',source),user='postgres')
 old_job=value(sql(frame(old_job_admission,2)+"SELECT private.burimunsi_native_work_enqueue('10000000-0000-4000-8000-000000000012','30000000-0000-4000-8000-000000000001'); COMMIT;",user='postgres'))['jobId']
 old_lease=value(sql(frame(old_job_admission,2)+"SELECT private.burimunsi_native_work_claim('10000000-0000-4000-8000-000000000012','"+old_job+"',30000); COMMIT;",user='postgres'))
 sql(frame(old_job_admission,2)+"SELECT private.burimunsi_native_work_defer('"+old_job+"','"+old_lease['leaseToken']+"',"+str(old_lease['leaseVersion'])+",'identity_unavailable',30000); COMMIT;",user='postgres')
 for admission in [old_job_admission,old_admin_admission]:
  sql("BEGIN; SET LOCAL ROLE collect_runtime; SELECT set_config('collect.edge_verified','true',true); SELECT private.collect_fence_close('"+admission+"',2,'"+source+"','settled','completed',0,0); COMMIT;",user='postgres')
 freeze2=str(uuid.uuid4());release2=str(uuid.uuid4())
 sql("SELECT private.collect_fence_begin_quiesce('"+freeze2+"',2,'"+source+"');",user='postgres')
 sql("SELECT private.collect_fence_drain('"+freeze2+"',2,'"+source+"');",user='postgres')
 if sql('SELECT mode FROM private.collect_fence_control;',user='postgres')!='fenced':raise RuntimeError('second fence did not drain')
 migration=REPO/'supabase/migrations/20261113130800_burimunsi_native_lease_history.sql'
 sql(migration.read_text(),user='postgres')
 if sql('SELECT count(*) FROM private.burimunsi_native_lease_history;',user='supabase_admin')!='0':raise RuntimeError('migration fabricated pre-install history')
 events.append({'history_migration':'PASS','sha256':hashlib.sha256(migration.read_bytes()).hexdigest(),'preinstall_lease_backfilled':False})
 sql("SELECT private.collect_fence_release('"+release2+"',2,'"+source+"');",user='postgres')
 job_admission=str(uuid.uuid4());admin_admission=str(uuid.uuid4());register(job_admission,'jobs');register(admin_admission,'http_admin')
 fixture=TEST_ROOT/'native-lease-history-contract.sql'
 text=(fixture.read_text().replace('__JOB_ADMISSION__',job_admission).replace('__ADMIN_ADMISSION__',admin_admission)
  .replace('__ADMISSION_SOURCE__',source).replace('__LEGACY_JOB_ID__',old_job))
 out=sql(text,user='supabase_admin')
 if '"status": "pass"' not in out:raise RuntimeError('lease history contract did not return PASS: '+out[-800:])
 events.append({'history_contract':'PASS','sha256':hashlib.sha256(fixture.read_bytes()).hexdigest(),'legacy_gap_preserved':True,'source_snapshot_stubbed':True})
except BaseException as exc:error=type(exc).__name__+': '+str(exc)
finally:
 removed=None
 if cid:
  try:
   p=subprocess.run(D+['inspect',cid],capture_output=True,timeout=10);obj=json.loads(p.stdout)[0] if p.returncode==0 else None
   if obj and obj['Config']['Labels'].get('io.collect.native-work-qa')==suffix:removed=subprocess.run(D+['rm','-f',cid],capture_output=True,timeout=30).returncode==0
   else:removed=False
  except Exception:removed=False
 try:reserve()
 except Exception as exc:error=error or str(exc)
 result={'status':'PASS' if not error and removed else 'FAIL','events':events,'error':error,'container_removed':removed,'network':'none','host_ports_published':False,'host_mounts':False,'synthetic_only':True,'minimum_free_bytes':minimum,'limit_bytes':limit}
 (EVIDENCE/('schema-result-'+suffix+'.json')).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));sys.exit(0 if result['status']=='PASS' else 2)
