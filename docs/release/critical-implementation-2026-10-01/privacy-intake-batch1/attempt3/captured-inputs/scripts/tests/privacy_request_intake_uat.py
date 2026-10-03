#!/usr/bin/env python3
"""Actual isolated current-chain privacy intake SQL and concurrent revocation UAT.

No database URL, external credential, provider request or shared target accepted.
Reuses the maintained row-free platform/owned Target installer. Synthetic Auth
claims execute SQL admission; this does not attest signed JWT or GoTrue runtime.
"""
from pathlib import Path
import argparse,contextlib,datetime,hashlib,json,os,signal,subprocess,time,traceback,types

ROOT=Path(__file__).resolve().parents[2]
HELPER=Path('scripts/tests/collect_current_release_upgrade_uat.py')
BASELINE=Path('.cache/receipt-foundation-attempt8/schema-only.sql')
PREREQ=Path('scripts/sql/receipt_transport_platform_prerequisites.sql')
SQL=Path('scripts/tests/privacy_request_intake_uat.sql')
LEGACY=Path('scripts/local_backend_privacy_lifecycle_uat.sql')
MIGRATION='20261002031500'
LOCAL_NET=('alter function net.http_get(text,jsonb,jsonb,integer)security definer;'
 'alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;'
 'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;'
 'alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;')
FUNCTIONS="""select coalesce(jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object(
 'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'config',p.proconfig)), '{}')
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where
 (n.nspname='public'and p.proname in('_lock_notification_session_gate','_notification_session_is_live',
 '_lock_notification_registration_session','lock_notification_auth_revocation','lock_notification_auth_activity',
 'is_platform_admin'))or(n.nspname='collect_hybrid'and p.proname in('require_fresh_roster_auth','require_roster_caller'))
 or(n.nspname='collect_admin_access'and p.proname in('platform_admin','caller_eligible','approved_identity'));"""
FKS="""select coalesce(jsonb_object_agg(c.conrelid::regclass::text||':'||c.conname,
 pg_get_constraintdef(c.oid)),'{}')from pg_constraint c where c.contype='f';"""
CATALOG="""select jsonb_build_object('functions',(select jsonb_agg(jsonb_build_object(
 'identity',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),
 'acl',p.proacl::text,'anon',has_function_privilege('anon',p.oid,'execute'),
 'authenticated',has_function_privilege('authenticated',p.oid,'execute'),
 'service',has_function_privilege('service_role',p.oid,'execute'))order by p.oid::regprocedure::text)
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='collect_privacy'
 or(n.nspname='public'and p.proname in('request_account_deletion','request_account_deletion_v1',
 'get_account_deletion_request_status_v1','_account_deletion_read_is_live_v1'))),
 'policies',(select jsonb_agg(to_jsonb(p))from pg_policies p where schemaname='public'and tablename='mobile_account_deletion_requests'),
 'request_table',jsonb_build_object('acl',(select relacl::text from pg_class where oid='public.mobile_account_deletion_requests'::regclass),
 'client_select',has_table_privilege('authenticated','public.mobile_account_deletion_requests','select'),
 'client_insert',has_table_privilege('authenticated','public.mobile_account_deletion_requests','insert'),
 'service_select',has_table_privilege('service_role','public.mobile_account_deletion_requests','select'),
 'service_insert',has_table_privilege('service_role','public.mobile_account_deletion_requests','insert')));"""

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def uid(i):return '99870000-0000-4000-8000-'+str(i).zfill(12)
def claims(actor,sid):return json.dumps(dict(sub=uid(actor),role='authenticated',session_id=uid(sid),exp=int(time.time())+3600))
def actor_sql(actor,sid,query):
 return "set local role authenticated;select set_config('request.jwt.claims',"+"'"+claims(actor,sid)+"',true);"+query
def submit(request,reason):return "select public.request_account_deletion_v1('%s','%s');"%(uid(request),reason)

def snapshot(target,financial=False):
 where="and n.nspname<>'collect_privacy'and not(n.nspname='public'and c.relname in('profiles','audit_logs','mobile_account_deletion_requests'))"if financial else ''
 schemas="n.nspname='public'or n.nspname like 'collect_%'"if financial else "n.nspname in('public','auth','storage')or n.nspname like 'collect_%'"
 return target.json("""create temporary table qa_snapshot(name text,value jsonb);
 do $b$declare r record;v jsonb;begin for r in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where c.relkind='r'and("""+schemas+")"+where+"""order by 1,2 loop
 execute format('select jsonb_build_object(''count'',count(*),''rows_sha256'',encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E''\\n''order by to_jsonb(t)::text),''''),''sha256''),''hex''))from %I.%I t',r.nspname,r.relname)into v;
 insert into qa_snapshot values(r.nspname||'.'||r.relname,v);end loop;end$b$;
 select jsonb_object_agg(name,value order by name)from qa_snapshot;drop table qa_snapshot;""")

def run_concurrency(target,helper,report,evidence):
 target.sql("""insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
 select ('99870000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'authenticated','authenticated',
 '250788987'||lpad(i::text,3,'0'),clock_timestamp(),'{}','{}'from generate_series(1,8)i;
 update public.profiles set country_code='RW',currency_code='RWF'where id::text like '99870000%';
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
 select ('99870000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
 ('99870000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval'1 hour','aal1'
 from generate_series(1,8)i;""",label='actual concurrent synthetic fixture')
 before=snapshot(target,True);(report/'financial-before.json').write_text(json.dumps(before,indent=2)+'\n')
 realtime_before=target.json("select coalesce(jsonb_object_agg(id::text,to_jsonb(e)),'{}')from public.app_realtime_events e;")
 cases=[]
 def race(name,first,second,expected_b=0,error=None):
  handles=[];records=[]
  def start(side,body,sleep=False):
   app='privacy_qa_'+name+'_'+side
   script="set application_name='%s';set statement_timeout='15s';begin;"%app+body+('select pg_sleep(3);'if sleep else '')+'commit;'
   (report/(name+'-'+side+'.sql')).write_text(script+'\n')
   p=subprocess.Popen([helper.DOCKER,'exec','-i',target.name,'psql','-XqAt','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
   handles.append(p);p.stdin.write(script);p.stdin.close();p.stdin=None
   return p,app
  def wait(app,kind):
   until=time.monotonic()+8
   while time.monotonic()<until:
    state=target.json("select coalesce((select jsonb_build_object('wait_type',wait_event_type,'wait',wait_event,'state',state)from pg_stat_activity where application_name='%s'),'{}');"%app)
    if(kind=='sleep'and state.get('wait')=='PgSleep')or(kind=='lock'and state.get('wait_type')=='Lock'):
     records.append(dict(app=app,observed=state));return
    time.sleep(.08)
   raise AssertionError('Actual overlap not observed: '+app+' '+kind)
  try:
   a,app_a=start('a',first,True);wait(app_a,'sleep')
   b,app_b=start('b',second);wait(app_b,'lock')
   for side,p,expected in [('a',a,0),('b',b,expected_b)]:
    out,err=p.communicate(timeout=22);(report/(name+'-'+side+'.log')).write_text(out+err)
    assert p.returncode==expected,(name,side,p.returncode,err)
    if side=='b'and error:assert error in err,(name,err)
   cases.append(dict(name=name,status='pass',actual_overlap=records,second_exit=expected_b,expected_error=error))
  finally:
   for p in handles:
    if p.poll()is None:
     os.killpg(p.pid,signal.SIGTERM)
     try:p.wait(timeout=3)
     except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
   (report/'concurrency.json').write_text(json.dumps(cases,indent=2)+'\n')
 race('duplicate_uuid',actor_sql(1,101,submit(4001,'same')),actor_sql(1,101,submit(4001,'same')))
 race('equivalent_uuid',actor_sql(2,102,submit(4002,'same')),actor_sql(2,102,submit(4003,'same')))
 race('payload_conflict',actor_sql(3,103,submit(4004,'same')),actor_sql(3,103,submit(4004,'changed')),3,'privacy_request_conflict')
 race('subject_conflict',actor_sql(4,104,submit(4005,'same')),actor_sql(5,105,submit(4005,'same')),3,'privacy_request_conflict')
 race('revocation_wins',"delete from auth.sessions where id='%s';"%uid(106),actor_sql(6,106,submit(4006,'same')),3,'privacy_request_session_required')
 race('intake_wins',actor_sql(7,107,submit(4007,'same')),"delete from auth.sessions where id='%s';"%uid(107))
 # A request accepted before logout remains evidence; the revoked SID cannot
 # read status or submit again after revocation obtains the exclusive gate.
 revoked=target.sql('begin;'+actor_sql(7,107,"select public.get_account_deletion_request_status_v1('%s');"%uid(4007))+'rollback;',check=False,label='post-winning intake revoked status')
 assert revoked.returncode==3 and 'privacy_request_session_required'in revoked.stderr
 counts=target.json("""select jsonb_build_object('canonical',(select count(*)from collect_privacy.intake_requests),
 'aliases',(select count(*)from collect_privacy.intake_submissions),'legacy',(select count(*)from public.mobile_account_deletion_requests),
 'acceptance_audits',(select count(*)from public.audit_logs where action='mobile.privacy_request_intake_accepted'),
 'request_audits',(select count(*)from public.audit_logs where action='mobile.account_deletion_requested'));""")
 assert counts==dict(canonical=5,aliases=6,legacy=5,acceptance_audits=5,request_audits=5),counts
 after=snapshot(target,True)
 (report/'financial-after.json').write_text(json.dumps(after,indent=2)+'\n')
 assert set(before)==set(after),'Financial/resource table inventory changed'
 for table,value in before.items():
  if table!='public.app_realtime_events':assert after[table]==value,'Unrelated financial/resource rows changed: '+table
 realtime_after=target.json("select coalesce(jsonb_object_agg(id::text,to_jsonb(e)),'{}')from public.app_realtime_events e;")
 assert all(realtime_after.get(k)==v for k,v in realtime_before.items()),'Existing realtime evidence altered'
 additions={k:v for k,v in realtime_after.items()if k not in realtime_before}
 assert len(additions)==10 and all(set(v)=={'id','area','created_at'}and v['area']=='audit'for v in additions.values()),'Unexpected realtime publication'
 (report/'expected-audit-invalidation.json').write_text(json.dumps(dict(before=realtime_before,after=realtime_after,
  exact_additions=additions,expected_audit_rows=10,old_rows_unchanged=True,new_rows_minimized=True),indent=2)+'\n')
 evidence['concurrency']=dict(cases=cases,counts=counts,post_revocation_status_denied=True,
  financial_resource_tables=len(before)-1,financial_resource_rows_unchanged=True,
  realtime_original_rows_unchanged=True,exact_minimized_audit_invalidations=10)

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--report-dir',required=True);args=parser.parse_args()
 report=Path(args.report_dir).resolve()
 permitted=ROOT/'docs/release/critical-implementation-2026-10-01/privacy-intake-batch1'
 assert report.is_relative_to(permitted)and not report.exists(),'Fresh task-owned evidence directory required'
 report.mkdir(parents=True);capture=report/'captured-inputs';hashes={};items=[]
 sources=[Path(__file__).relative_to(ROOT),HELPER,BASELINE,PREREQ,SQL,LEGACY,*[p.relative_to(ROOT)for p in sorted((ROOT/'supabase/migrations').glob('*.sql'))]]
 for rel in sources:
  data=(ROOT/rel).read_bytes();dest=capture/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data);hashes[str(rel)]=sha(dest)
 assert hashes[str(HELPER)]=='343cd3b21ac9629347b0080640891eac3bdacdea7df11752b129c5f943b6c33b'
 helper=types.ModuleType('privacy_maintained_target');helper.__file__=str(capture/HELPER)
 exec(compile((capture/HELPER).read_bytes(),str(capture/HELPER),'exec'),helper.__dict__);helper.ROOT=capture;helper.BASELINE=capture/BASELINE
 for p in sorted((capture/'supabase/migrations').glob('*.sql')):
  version,name=p.stem.split('_',1);datetime.datetime.strptime(version,'%Y%m%d%H%M%S')
  items.append(dict(path='supabase/migrations/'+p.name,version=version,name=name,sha256=sha(p),body=p.read_text()))
 assert len({i['version']for i in items})==len(items)and MIGRATION in[i['version']for i in items]
 result=dict(status='running',started_at_utc=now(),source_sha256=hashes,migration_count=len(items),max_version=items[-1]['version'],target={},
  hosted_written=False,provider_called=False,signed_jwt_tested=False,source_rows_copied=False,full_privacy_lifecycle_completed=False,
  limits=['Row-free retained platform schema and task-local superuser normalization','Synthetic claims; signed JWT/GoTrue not attested',
   'Intake only; policy/scope/retention approval and full BE05 execution pending'])
 def save():(report/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 save();failure=None
 try:
  platform,prov=helper.platform_shape();result['platform']=prov;(report/'platform-schema-only.sql').write_text(platform)
  with helper.Target(report,'privacy_intake',result['target'])as target:
   target.sql(platform,label='retained row-free platform shape')
   with(report/'migration-progress.log').open('w')as log,contextlib.redirect_stdout(log):
    for item in items:
     if item['version']=='20261001160000':
      target.sql(LOCAL_NET,user='supabase_admin',label='isolated trusted net metadata')
      target.sql((capture/PREREQ).read_text(),user='supabase_admin',label='maintained transport reader prerequisite')
     if item['version']==MIGRATION:
      before_functions=target.json(FUNCTIONS);before_fks=target.json(FKS)
      (report/'pre-intake-context.json').write_text(json.dumps(dict(functions=before_functions,foreign_keys=before_fks),indent=2)+'\n')
     helper.apply(target,[item],result['target'])
   assert int(target.scalar('select count(*)from supabase_migrations.schema_migrations;'))==len(items)
   assert target.scalar('select max(version)from supabase_migrations.schema_migrations;')==items[-1]['version']
   assert target.json(FUNCTIONS)==before_functions,'Existing shared Auth/Admin authority changed'
   after_fks=target.json(FKS);assert all(after_fks.get(k)==v for k,v in before_fks.items()),'Existing FK changed'
   catalog=target.json(CATALOG);(report/'final-effective-context.json').write_text(json.dumps(catalog,indent=2)+'\n')
   assert catalog['request_table']['client_select']and not catalog['request_table']['client_insert']and not catalog['request_table']['service_select']and not catalog['request_table']['service_insert']
   for f in catalog['functions']:
    assert not f['anon']and not f['service'],f
    assert f['authenticated']==(not f['identity'].startswith('collect_privacy.')),f
   result['context_invariance']=dict(shared_helper_functions=len(before_functions),old_foreign_keys=len(before_fks),old_foreign_keys_unchanged=True,
    added_foreign_keys={k:v for k,v in after_fks.items()if k not in before_fks},public_uuid_adapter_preserved=True)
   for label,source,marker in [('legacy',LEGACY,'LOCAL_BACKEND_PRIVACY_LIFECYCLE_PASS'),('intake',SQL,'PRIVACY_REQUEST_INTAKE_UAT_PASS')]:
    before=snapshot(target);execution=target.sql((capture/source).read_text(),label='actual '+label+' privacy rollback UAT')
    (report/(label+'-uat.log')).write_text(execution.stdout+execution.stderr);assert marker in execution.stdout
    after=snapshot(target);assert before==after,label+' rollback changed retained rows'
    (report/(label+'-rollback-snapshot.json')).write_text(json.dumps(dict(before=before,after=after,rows_unchanged=True),indent=2)+'\n')
    result[label+'_uat']=dict(status='pass',marker=marker,rollback_rows_unchanged=True,tables=len(before))
    if label=='intake':result[label+'_uat']['checks']=next(json.loads(line)for line in execution.stdout.splitlines()if line.startswith('{')and marker in line)
    save()
   isolation=target.sql('begin isolation level repeatable read;'+actor_sql(1,101,submit(4999,'snapshot'))+'rollback;',check=False,label='non-current SQL snapshot refused')
   (report/'snapshot-isolation-denial.log').write_text(isolation.stdout+isolation.stderr)
   assert isolation.returncode==3 and '40001'in isolation.stderr and 'privacy_request_snapshot_retry'in isolation.stderr
   result['repeatable_read_refused']=True
   run_concurrency(target,helper,report,result)
   result['status']='pass'
 except Exception as e:
  result['status']='fail';result['error']=str(e);(report/'failure.txt').write_text(traceback.format_exc());failure=e
 finally:
  result['changed_inputs']=[p for p,h in hashes.items()if not(ROOT/p).is_file()or sha(ROOT/p)!=h]
  result['migration_path_drift']=sorted(str(p.relative_to(ROOT))for p in(ROOT/'supabase/migrations').glob('*.sql'))!=sorted(i['path']for i in items)
  if result['changed_inputs']or result['migration_path_drift']:result['status']='stale-source'
  name=result['target'].get('container_name')
  if name:
   absent=helper.command([helper.DOCKER,'inspect',name],check=False)
   result['target']['absence_verified']=absent.returncode!=0 and 'no such object'in absent.stderr.lower()
   if not result['target']['absence_verified']:result['status']='fail'
  result['completed_at_utc']=now();save()
 print(json.dumps(dict(status=result['status'],migration_count=result['migration_count'],max_version=result['max_version'],
  migrations_passed=sum(m['status']=='pass'for m in result['target'].get('migrations',[])),
  target_removed=result['target'].get('absence_verified'),error=result.get('error'))),flush=True)
 if failure:raise failure
 if result['status']!='pass':raise SystemExit(1)
if __name__=='__main__':main()
