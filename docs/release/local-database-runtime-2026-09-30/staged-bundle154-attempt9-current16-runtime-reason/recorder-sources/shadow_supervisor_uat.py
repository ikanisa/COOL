#!/usr/bin/env python3
"""Schema-only isolated local PostgreSQL UAT; never accepts a URL or remote host.

The quiet local QA container is read for schema/metadata only. New synthetic
identities, migration and race probes are confined to a new disposable database.
No credentials or source table rows are copied. Evidence stores hashes/counts.
"""
import argparse, datetime, hashlib, json, os, pathlib, re, subprocess, sys, time, uuid
ROOT=pathlib.Path(__file__).resolve().parents[2]
DOCKER='/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker'
CONTAINER='supabase_db_collect_fin_concurrency_qa_20260929'
PROJECT='collect_fin_concurrency_qa_20260929'
MIGRATION=ROOT/'supabase/migrations/20260930210000_shadow_supervisor_runs.sql'
UID='99710000-0000-4000-8000-000000000001'
SID='99710000-0000-4000-8000-000000010001'
SID2='99710000-0000-4000-8000-000000010002'
OTHER='99710000-0000-4000-8000-000000000002'
OTHERSID='99710000-0000-4000-8000-000000010003'
SQL_LOG=None
CONCURRENCY_LOG=None

def command(args,stdin=None,check=True):
 r=subprocess.run(args,input=stdin,text=True,capture_output=True)
 if check and r.returncode: raise RuntimeError(r.stderr[-4000:])
 return r

def psql(db,sql,check=True,user='postgres'):
 r=command([DOCKER,'exec','-i',CONTAINER,'psql','-XqAt','-U',user,'-d',db,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],sql,False)
 if SQL_LOG is not None:
  with SQL_LOG.open('a') as log:log.write(json.dumps({'database':db,'sql_sha256':hashlib.sha256(sql.encode()).hexdigest(),'exit_code':r.returncode})+'\n'+r.stdout+r.stderr+'\n')
 if check and r.returncode:raise RuntimeError(r.stderr[-4000:])
 return r

def auth(uid=UID,sid=SID):
 claims=json.dumps({'sub':uid,'session_id':sid,'role':'authenticated','aal':'aal1'})
 return "set local role authenticated;select set_config('request.jwt.claims','"+claims+"',true);"

def call(db,sql,uid=UID,sid=SID):
 r=psql(db,'begin;'+auth(uid,sid)+sql+';commit;')
 return json.loads(r.stdout.strip().splitlines()[-1])

def expected_error(db,sql,state,reason=None,uid=UID,sid=SID,role='authenticated'):
 a=auth(uid,sid) if role=='authenticated' else "set local role "+role+";select set_config('request.jwt.claims','{\"role\":\""+role+"\"}',true);"
 r=psql(db,'begin;'+a+sql+';commit;',False)
 assert r.returncode and state+':' in r.stderr and (reason is None or reason in r.stderr), r.stderr
 return {'sqlstate':state,'reason':reason}

def fingerprint(db):
 sql="""select jsonb_object_agg(name,jsonb_build_object('rows',n,'sha256',h)) from (
 select 'payments' name,count(*) n,encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by id),''),'sha256'),'hex') h from public.payments t
 union all select 'sms_outbox',count(*),encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by id),''),'sha256'),'hex') from collect_hybrid.sms_notification_outbox t
 union all select 'sms_attempts',count(*),encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by id),''),'sha256'),'hex') from collect_hybrid.sms_notification_attempts t
 union all select 'sms_heartbeats',count(*),encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by worker_id),''),'sha256'),'hex') from collect_hybrid.sms_operator_heartbeats t
 union all select 'push_deliveries',count(*),encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by id),''),'sha256'),'hex') from public.notification_deliveries t
 union all select 'push_attempts',count(*),encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by id),''),'sha256'),'hex') from public.notification_delivery_attempts t
 union all select 'journal',count(*),encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by id),''),'sha256'),'hex') from collect_hybrid.momo_journal_entries t
 )s;"""
 return json.loads(psql(db,sql).stdout)

class Session:
 def __init__(self,db,name):
  self.p=subprocess.Popen([DOCKER,'exec','-i',CONTAINER,'psql','-XqAt','-U','postgres','-d',db,'-v','ON_ERROR_STOP=0','-v','VERBOSITY=verbose'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,bufsize=1)
  self.name=name
 def write(self,sql):self.p.stdin.write(sql+'\n');self.p.stdin.flush()
 def read(self,marker,timeout=12):
  import select
  lines=[];end=time.monotonic()+timeout
  # psql line buffering may retain lines in TextIOWrapper, so use one character
  # stream and only wait on its FD when needed using a separate reader thread.
  import queue,threading
  if not hasattr(self,'q'):
   self.q=queue.Queue()
   threading.Thread(target=lambda:[self.q.put(line.rstrip()) for line in self.p.stdout],daemon=True).start()
  while time.monotonic()<end:
   try:line=self.q.get(timeout=max(.01,end-time.monotonic()))
   except queue.Empty:break
   lines.append(line)
   if CONCURRENCY_LOG is not None:
    with CONCURRENCY_LOG.open('a') as log:log.write(self.name+': '+line+'\n')
   if line==marker:return lines
  raise RuntimeError('Session marker timeout '+marker+' '+repr(lines))
 def close(self):
  if self.p.poll() is None:
   self.write('rollback;\\q');self.p.wait(timeout=10)

def main():
 global SQL_LOG,CONCURRENCY_LOG
 parser=argparse.ArgumentParser();parser.add_argument('--report-dir',required=True);parser.add_argument('--setup-only',action='store_true');args=parser.parse_args()
 report=pathlib.Path(args.report_dir).resolve();assert not report.exists(),'Fresh report directory required';report.mkdir(parents=True)
 evidence={'kind':'manual_shadow_supervisor_isolated_schema_only','started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'production_written':False,'provider_called':False,'cases':[]}
 def save(): (report/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
 def case(name,fn):
  value=fn();evidence['cases'].append({'name':name,'status':'pass','detail':value});save();print('PASS '+name,flush=True);return value
 labels=json.loads(command([DOCKER,'inspect',CONTAINER,'--format','{{json .Config.Labels}}']).stdout)
 ports=json.loads(command([DOCKER,'inspect',CONTAINER,'--format','{{json .HostConfig.PortBindings}}']).stdout)
 assert labels['com.supabase.cli.project']==PROJECT and labels['com.docker.compose.project']==PROJECT and all(x['HostPort']=='55722' for x in ports['5432/tcp'])
 metadata=json.loads(psql('postgres',"select jsonb_build_object('count',(select count(*) from supabase_migrations.schema_migrations),'latest',(select max(version) from supabase_migrations.schema_migrations),'cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size')); ").stdout)
 assert metadata=={'count':150,'latest':'20260930180000','cron':'off','net':'0'},metadata
 evidence['source_metadata']=metadata;evidence['migration_sha256']=hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
 prerequisites={}
 for version,name,pattern in [
  ('20260930170000','roster_fresh_auth_recovery',r'create function collect_hybrid\.require_roster_actor_authority\(.*?end \$\$;'),
  ('20260930180000','operational_health_authority',r'create or replace function public\.admin_system_health\(.*?end \$\$;')]:
  source=(ROOT/'supabase/migrations'/('%s_%s.sql'%(version,name))).read_text()
  installed=psql('postgres',"select statements[1] from supabase_migrations.schema_migrations where version='%s';"%version).stdout.removesuffix('\n')
  current_match=re.search(pattern,source,re.S);installed_match=re.search(pattern,installed,re.S)
  assert current_match and installed_match,'Prerequisite function extraction unavailable'
  prerequisites[version]={'current_source_sha256':hashlib.sha256(source.encode()).hexdigest(),'installed_migration_sha256':psql('postgres',"select encode(extensions.digest(statements[1],'sha256'),'hex') from supabase_migrations.schema_migrations where version='%s';"%version).stdout.strip(),'whole_migration_parity':source.rstrip()==installed.rstrip(),'normalized_source_sha256':hashlib.sha256(source.rstrip().encode()).hexdigest(),'normalized_installed_sha256':hashlib.sha256(installed.rstrip().encode()).hexdigest(),'relevant_function_source_parity':current_match.group()==installed_match.group(),'current_relevant_function_sha256':hashlib.sha256(current_match.group().encode()).hexdigest(),'installed_relevant_function_sha256':hashlib.sha256(installed_match.group().encode()).hexdigest()}
  assert prerequisites[version]['relevant_function_source_parity'],'Current relevant prerequisite function differs from installed quiet fixture'
 evidence['prerequisites']=prerequisites;save()
 db='collect_shadow_uat_'+uuid.uuid4().hex[:12];evidence['database']=db;made=False;sessions=[]
 try:
  # Copy schema definitions/ACLs only. Scheduling/network extension members are
  # replaced with empty local catalog fixtures; no source records or credentials.
  dump=command([DOCKER,'exec',CONTAINER,'pg_dump','-U','postgres','-d','postgres','--schema-only','--no-owner','--no-privileges','--no-publications','--no-subscriptions','--exclude-extension=pg_cron','--exclude-extension=pg_net','--exclude-extension=pg_stat_statements','--exclude-extension=pg_graphql','--exclude-schema=graphql','--exclude-schema=graphql_public','--exclude-schema=cron','--exclude-schema=net']).stdout
  evidence['source_schema_dump_sha256']=hashlib.sha256(dump.encode()).hexdigest()
  # API-facing ACLs are reconstructed from catalog privilege rows, without
  # source grantors/owners or superuser builtin grants. Authority function bodies,
  # RLS policies and business schemas are the actual installed150 definitions.
  acl_sql="""
  with targets as (select p.oid,'FUNCTION' kind,p.oid::regprocedure::text identity,
    coalesce(p.proacl,acldefault('f',p.proowner)) acl from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','auth','collect_security','collect_admin_access','collect_hybrid')
   union all select c.oid,case when c.relkind='S' then 'SEQUENCE' else 'TABLE' end,
    format('%I.%I',n.nspname,c.relname),coalesce(c.relacl,acldefault(case when c.relkind='S' then 'S'::"char" else 'r'::"char" end,c.relowner))
    from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p','v','m','S')
    and n.nspname in ('public','auth','collect_security','collect_admin_access','collect_hybrid')
   union all select n.oid,'SCHEMA',quote_ident(n.nspname),coalesce(n.nspacl,acldefault('n',n.nspowner)) from pg_namespace n
    where n.nspname in ('public','auth','collect_security','collect_admin_access','collect_hybrid')
  ) select string_agg(statement,E'\n' order by priority,kind,identity) from (
   select 0 priority,kind,identity,format('REVOKE ALL ON %s %s FROM PUBLIC,anon,authenticated,service_role;',kind,identity) statement from targets
   union all select 1,kind,identity,format('GRANT %s ON %s %s TO %s;',x.privilege_type,kind,identity,
     case when x.grantee=0 then 'PUBLIC' else quote_ident(r.rolname) end) from targets cross join lateral aclexplode(acl)x
     left join pg_roles r on r.oid=x.grantee where x.grantee=0 or r.rolname in ('anon','authenticated','service_role')
  )s;
  """
  acl='set search_path=public,auth;'+psql('postgres',acl_sql).stdout
  evidence['application_api_acl_sha256']=hashlib.sha256(acl.encode()).hexdigest()
  evidence['restored_schema_dump_sha256']=hashlib.sha256(dump.encode()).hexdigest();save()
  psql('postgres','create database '+db+' template template0;');made=True
  mock="create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);"
  restored=psql(db,mock+dump+acl,False)
  (report/'restore.log').write_text(restored.stderr)
  if restored.returncode:raise RuntimeError('Schema-only restore failed: '+restored.stderr[-3000:])
  # Static product authority catalog from source migration text; no user data.
  role='99710000-0000-4000-8000-000000020001'
  psql(db,"""insert into public.admin_roles(id,name,description) values('%s','platform_owner','Synthetic shadow owner');
  insert into public.admin_permissions(name,description) values('system_health.read','Synthetic read'),('notifications.read','Synthetic read');
  insert into public.admin_role_permissions(role_id,permission_name) values('%s','system_health.read'),('%s','notifications.read');
  insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
  ('%s','authenticated','authenticated','250788971001',now(),'{}','{}'),('%s','authenticated','authenticated','250788971002',now(),'{}','{}');
  insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason) values('%s','+250788971001',clock_timestamp()-interval '2 minutes','Synthetic shadow identity'),('%s','+250788971002',clock_timestamp()-interval '2 minutes','Synthetic shadow identity');
  insert into public.admin_user_roles(user_id,role_id,reason,created_at) values('%s','%s','Synthetic shadow grant',clock_timestamp()-interval '1 minute'),('%s','%s','Synthetic shadow grant',clock_timestamp()-interval '1 minute');
  insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
  insert into cron.job values(1,'collect-dispatch-notifications',false);
  """%(role,role,role,UID,OTHER,UID,OTHER,UID,role,OTHER,role,SID,UID,SID2,UID,OTHERSID,OTHER))
  install=psql(db,MIGRATION.read_text(),False)
  (report/'install.stdout.log').write_text(install.stdout);(report/'install.stderr.log').write_text(install.stderr)
  evidence['install_exit_code']=install.returncode
  if install.returncode:raise RuntimeError('Candidate install failed '+install.stderr[-4000:])
  case('migration installs in isolated schema-only database',lambda:True)
  if args.setup_only:return
  SQL_LOG=report/'queries.log';CONCURRENCY_LOG=report/'concurrency.log'
  run_cases(db,case,evidence,report,sessions,role)
  evidence['status']='pass'
 except Exception as e:
  evidence['status']='failed';evidence['failure']=str(e);save();raise
 finally:
  SQL_LOG=None
  for s in sessions:
   try:s.close()
   except Exception as e:evidence.setdefault('cleanup_errors',[]).append(str(e))
  if made:
   cleanup=psql('postgres','drop database '+db+' with (force);',False);evidence['isolated_database_removed']=cleanup.returncode==0
  evidence['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()

def run_cases(db,case,evidence,report,sessions,role):
 def assert_true(v):assert v;return True
 def scalar_bool(sql):return psql(db,sql).stdout.strip()=='t'
 def raw_error(sql,state,reason):
  r=psql(db,sql,False);assert r.returncode and state+':' in r.stderr and reason in r.stderr,r.stderr;return {'sqlstate':state,'reason':reason}
 def begin(req,sid=SID,uid=UID):return call(db,"select public.begin_collect_shadow_run_v1('%s');"%req,uid,sid)
 def sample(run,sid=SID):return call(db,"select public.sample_collect_shadow_run_v1('%s',%s);"%(run['run_id'],run['fence_version']),sid=sid)
 def finish(run,sid=SID):return call(db,"select public.finish_collect_shadow_run_v1('%s',%s);"%(run['run_id'],run['fence_version']),sid=sid)
 def get(req,sid=SID,uid=UID):return call(db,"select public.get_collect_shadow_run_v1('%s');"%req,uid,sid)
 def hist(limit=20,cursor=None,sid=SID):
  args=str(limit) if cursor is None else "%d,'%s','%s'"%(limit,cursor['started_at'],cursor['run_id'])
  return call(db,'select public.list_collect_shadow_runs_v1('+args+');',sid=sid)
 def lifecycle_sql(name,run,fence=None):return "select public.%s_collect_shadow_run_v1('%s',%s);"%(name,run['run_id'],run['fence_version'] if fence is None else fence)
 baseline=fingerprint(db);evidence['business_before']=baseline
 case('private tables have RLS and no API grants',lambda:assert_true(scalar_bool("select bool_and(c.relrowsecurity and not has_table_privilege(r, c.oid,'SELECT,INSERT,UPDATE,DELETE')) from pg_class c cross join unnest(array['anon','authenticated','service_role']) r where c.relnamespace='collect_security'::regnamespace and c.relname like 'shadow_supervisor_%' and c.relkind='r';")))
 case('public RPCs authenticated-only',lambda:assert_true(scalar_bool("select bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE')) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname like '%collect_shadow%';")))
 case('private helpers deny all API roles',lambda:assert_true(scalar_bool("select bool_and(not has_function_privilege(r,p.oid,'EXECUTE')) from pg_proc p cross join unnest(array['anon','authenticated','service_role']) r where p.pronamespace='collect_security'::regnamespace and p.proname like '%shadow%';")))
 for api_role in ['anon','service_role']:
  case(api_role+' cannot begin',lambda api_role=api_role:expected_error(db,'select public.begin_collect_shadow_run_v1(gen_random_uuid())','42501',role=api_role))
 case('missing Auth session denied',lambda:expected_error(db,'select public.list_collect_shadow_runs_v1()','42501','shadow_session_required',sid=str(uuid.uuid4())))
 def rollback_guard_probe(mutation,uid=UID,sid=SID):
  sql='begin;'+mutation+auth(uid,sid)+"do $$begin begin perform public.list_collect_shadow_runs_v1();raise exception 'Unexpected authorized actor';exception when sqlstate '42501' then null;end;end$$;select 'ACTOR_REFUSED';rollback;"
  r=psql(db,sql);assert 'ACTOR_REFUSED' in r.stdout;return True
 identity_probes=[
  ('unconfirmed phone',"update auth.users set phone_confirmed_at=null where id='%s';"%UID),
  ('banned actor',"update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='%s';"%UID),
  ('anonymous actor',"update auth.users set is_anonymous=true where id='%s';"%UID),
  ('expired Auth session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='%s';"%SID),
  ('session predates approval',"update collect_admin_access.whatsapp_approvals set approved_at=clock_timestamp()+interval '1 minute' where user_id='%s';"%UID),
  ('revoked approval',"update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp() where user_id='%s';"%UID),
  ('revoked platform grant',"update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='%s';"%UID),
  ('session predates grant',"update public.admin_user_roles set created_at=clock_timestamp()+interval '1 minute' where user_id='%s';"%UID)]
 for name,mutation in identity_probes:
  case('current authority requires '+name+' rejection',lambda mutation=mutation:rollback_guard_probe(mutation))
 alternate='99710000-0000-4000-8000-000000020002'
 wrong_role="insert into public.admin_roles(id,name,description) values('%s','shadow_reader','Synthetic role');insert into public.admin_role_permissions(role_id,permission_name) values('%s','notifications.read'),('%s','system_health.read');update public.admin_user_roles set role_id='%s' where user_id='%s';"%(alternate,alternate,alternate,alternate,UID)
 case('both permissions cannot substitute for platform_owner',lambda:rollback_guard_probe(wrong_role))
 case('valid session belonging to different actor denied',lambda:expected_error(db,'select public.list_collect_shadow_runs_v1()','42501','shadow_session_required',sid=OTHERSID))
 case('null request denied',lambda:expected_error(db,'select public.begin_collect_shadow_run_v1(null)','22023','shadow_request_invalid'))
 for args in ['0','51','null',"20,now(),null","20,'infinity','00000000-0000-0000-0000-000000000000'"]:
  case('invalid history arguments '+args,lambda args=args:expected_error(db,'select public.list_collect_shadow_runs_v1('+args+')','22023','shadow_request_invalid'))
 for permission in ['system_health.read','notifications.read']:
  psql(db,"delete from public.admin_role_permissions where role_id='%s' and permission_name='%s';"%(role,permission))
  case('current '+permission+' permission required',lambda:expected_error(db,'select public.list_collect_shadow_runs_v1()','42501','shadow_permission_required'))
  psql(db,"insert into public.admin_role_permissions values('%s','%s');"%(role,permission))
 req=str(uuid.uuid4());b=case('authenticated begin creates120-second platform lease',lambda:begin(req));run=b['run']
 assert b['outcome']=='started' and b['mode']=='shadow' and b['scope']=='collect_platform' and run['status']=='running'
 assert datetime.datetime.fromisoformat(run['lease_expires_at'])-datetime.datetime.fromisoformat(run['started_at'])==datetime.timedelta(seconds=120)
 case('same request original session replays stable run',lambda:assert_true(begin(req)['run']==run))
 case('competing actor sees bounded busy without token',lambda:assert_true(begin(str(uuid.uuid4()),uid=OTHER,sid=OTHERSID)['outcome']=='busy'))
 case('same actor new session cannot reuse request',lambda:expected_error(db,"select public.begin_collect_shadow_run_v1('%s')"%req,'40001','shadow_request_conflict',sid=SID2))
 case('different actor cannot reuse request',lambda:expected_error(db,"select public.begin_collect_shadow_run_v1('%s')"%req,'40001','shadow_request_conflict',uid=OTHER,sid=OTHERSID))
 case('new session read-only reconciliation finds original request',lambda:assert_true(get(req,SID2)['run']==run))
 case('other actor request lookup is absent',lambda:assert_true(get(req,OTHERSID,OTHER)=={'contract_version':1,'mode':'shadow','scope':'collect_platform','found':False,'run':None}))
 case('finish requires actual persisted sample',lambda:expected_error(db,lifecycle_sql('finish',run),'55000','shadow_sample_required'))
 case('wrong fence sample refused',lambda:expected_error(db,lifecycle_sql('sample',run,run['fence_version']+1),'40001','shadow_fence_lost'))
 rr=psql(db,'begin isolation level repeatable read;'+auth()+lifecycle_sql('sample',run)+'commit;',False)
 case('Repeatable Read cannot stamp an old health snapshot',lambda:assert_true(rr.returncode and '40001:' in rr.stderr and 'shadow_snapshot_retry' in rr.stderr))
 sampled=case('sample derives real150 health and SMS aggregates',lambda:sample(run));samplebody=sampled['sample']
 assert samplebody['system_health']['contract_version']==1 and len(samplebody['system_health']['alerts'])==13
 assert sum(samplebody['summary']['alert_counts'].values())==13
 assert samplebody['summary']['business_mutations']==0 and samplebody['summary']['provider_sends']==0
 assert not any(x in json.dumps(samplebody) for x in ['250788971','99710000','actor_id','session_id','destination','raw_body','provider_message_id'])
 case('sample replay preserves immutable sample and hash',lambda:assert_true(sample(run)['sample']==samplebody))
 case('server SHA matches persisted canonical jsonb',lambda:assert_true(scalar_bool("select content_sha256=encode(extensions.digest(convert_to(body::text,'UTF8'),'sha256'),'hex') from collect_security.shadow_supervisor_samples where run_id='%s';"%run['run_id'])))
 case('even owner cannot rewrite immutable sample',lambda:raw_error("update collect_security.shadow_supervisor_samples set body='{}' where run_id='%s';"%run['run_id'],'55000','shadow_history_immutable'))
 case('even owner cannot delete immutable sample',lambda:raw_error("delete from collect_security.shadow_supervisor_samples where run_id='%s';"%run['run_id'],'55000','shadow_history_immutable'))
 completed=case('server completion records existing sample',lambda:finish(run));assert completed['run']['status']=='completed'
 case('completed original request replay stable',lambda:assert_true(begin(req)['run']==completed['run']))
 case('completed finish replay stable',lambda:assert_true(finish(run)['replayed']))
 req2=str(uuid.uuid4());run2=begin(req2)['run'];assert run2['fence_version']==run['fence_version']+1
 case('old completed finish does not clear newer lease',lambda:assert_true(finish(run)['replayed'] and hist()['lease']['active_run_id']==run2['run_id']))
 case('wrong session cannot sample another session lease',lambda:expected_error(db,lifecycle_sql('sample',run2),'42501','shadow_run_unavailable',sid=SID2))
 sample(run2);finish(run2)
 h=hist(1);assert h['next_cursor'] and h['rows'][0]['run_id']==run2['run_id']
 h2=hist(1,h['next_cursor']);assert h2['rows'][0]['run_id']==run['run_id'] and h2['next_cursor'] is None and h2['total']==2
 case('strict paired keyset produces no repeated rows',lambda:True)
 (report/'actual-history.json').write_text(json.dumps(hist(),indent=2)+'\n')
 (report/'actual-lifecycle.json').write_text(json.dumps({'begin':b,'sample':sampled,'finish':completed,'get':get(req)},indent=2)+'\n')
 # Current source health must remain valid; malformed and stale helper inputs
 # test fail-closed server validation without replacing trusted public RPCs.
 valid=samplebody['system_health'];start=run['started_at'];observed=samplebody['checked_at']
 variants=[('null',None),('missing contract',{k:v for k,v in valid.items() if k!='contract_version'}),('null alerts',{**valid,'alerts':None}),('missing alert state',{**valid,'alerts':[{k:v for k,v in valid['alerts'][0].items() if k!='state'}]+valid['alerts'][1:]}),('invalid alert state',{**valid,'alerts':[{**valid['alerts'][0],'state':'sent'}]+valid['alerts'][1:]}),('missing valid until',{k:v for k,v in valid.items() if k!='sample_valid_until'}),('infinite checked_at',{**valid,'checked_at':'infinity'}),('null status',{**valid,'health_status':None}),('numeric checked_at',{**valid,'checked_at':2026}),('numeric valid until',{**valid,'sample_valid_until':2026}),('wrong severity',{**valid,'health_status':'attention' if valid['health_status']!='attention' else 'ok'}),('unexpected sensitive field',{**valid,'recipient':'private-canary'}),('unexpected nested metric',{**valid,'metrics':{**valid['metrics'],'recipient':'private-canary'}}),('null metrics',{**valid,'metrics':None}),('array metrics',{**valid,'metrics':[]}),('fraction metric',{**valid,'metrics':{**valid['metrics'],'reversals_24h':0.5}}),('unsafe metric',{**valid,'metrics':{**valid['metrics'],'reversals_24h':9007199254740992}})]
 for name,value in variants:
  literal='null' if value is None else "'"+json.dumps(value).replace("'","''")+"'::jsonb"
  case('malformed source health '+name,lambda literal=literal:raw_error("select collect_security.require_shadow_health(%s,'%s','%s');"%(literal,start,observed),'55000','shadow_integrity_unavailable'))
 case('source health cannot be relabeled after expiry',lambda:raw_error("select collect_security.require_shadow_health('%s'::jsonb,'%s','%s'::timestamptz+interval '61 seconds');"%(json.dumps(valid).replace("'","''"),start,valid['checked_at']),'55000','shadow_health_stale'))
 # A malformed trusted dependency must not publish even an immutable sample.
 # These altered function bodies exist solely inside isolated rollback probes.
 fault_run=begin(str(uuid.uuid4()))['run']
 def fault_probe(value):
  literal='null::jsonb' if value is None else "'"+json.dumps(value).replace("'","''")+"'::jsonb"
  sql="begin;create or replace function public.admin_system_health(p_id text default 'system') returns jsonb language sql volatile security definer set search_path='' as $fault$select "+literal+"$fault$;"+auth()+"do $$begin begin perform public.sample_collect_shadow_run_v1('%s',%d);raise exception 'unexpected allowed sample';exception when sqlstate '55000' then if sqlerrm<>'shadow_integrity_unavailable' then raise;end if;end;end$$;select 'PUBLIC_FAULT_REFUSED';rollback;"%(fault_run['run_id'],fault_run['fence_version'])
  r=psql(db,sql);assert 'PUBLIC_FAULT_REFUSED' in r.stdout
  assert psql(db,"select count(*) from collect_security.shadow_supervisor_samples where run_id='%s';"%fault_run['run_id']).stdout.strip()=='0'
  return True
 for name,value in [('null',None),('missing status',{k:v for k,v in valid.items() if k!='health_status'}),('redaction leak',{**valid,'recipient':'private-canary'}),('malformed alerts',{**valid,'alerts':[]})]:
  case('public sampling refuses dependency '+name,lambda value=value:fault_probe(value))
 sample(fault_run);finish(fault_run)
 # Freshness-at-finish uses a real sampled run. A synthetic trusted owner fixture
 # changes its source clock under disabled immutable trigger, keeping its digest
 # consistent; the authenticated API must still refuse completion.
 run3=begin(str(uuid.uuid4()))['run'];sample(run3)
 psql(db,"alter table collect_security.shadow_supervisor_samples disable trigger shadow_sample_immutable;update collect_security.shadow_supervisor_samples set body=jsonb_set(jsonb_set(body,'{system_health,checked_at}',to_jsonb((clock_timestamp()-interval '61 seconds')::text)),'{system_health,sample_valid_until}',to_jsonb((clock_timestamp()-interval '1 seconds')::text));update collect_security.shadow_supervisor_samples set content_sha256=encode(extensions.digest(convert_to(body::text,'UTF8'),'sha256'),'hex');alter table collect_security.shadow_supervisor_samples enable trigger shadow_sample_immutable;")
 # Both mutated source times predate this run, so integrity refusal is stronger
 # than stale refusal; testing the age branch above uses internally valid times.
 case('finish refuses forged old source timestamp',lambda:expected_error(db,lifecycle_sql('finish',run3),'55000','shadow_integrity_unavailable'))
 # Release this synthetic active fixture by moving only private lease ownership;
 # no actual lifecycle ever gets permission to expire a lease early.
 psql(db,"update collect_security.shadow_supervisor_lease set active_run_id=null,lease_expires_at=null where id;")
 # Source age can expire while the120s lease still lives. Build a trusted
 # private fixture with exactly paired timestamps, not a forged new sample.
 staleid,stalereq=str(uuid.uuid4()),str(uuid.uuid4());stalef=int(psql(db,'select fence_version+1 from collect_security.shadow_supervisor_lease;').stdout)
 template=json.dumps(samplebody).replace("'","''")
 psql(db,"""with timing as (select clock_timestamp()-interval '70 seconds' started),
 r as (insert into collect_security.shadow_supervisor_runs(id,request_id,actor_id,session_id,fence_version,started_at,lease_expires_at)
 select '%s','%s','%s','%s',%d,started,started+interval '120 seconds' from timing returning *)
 update collect_security.shadow_supervisor_lease set fence_version=r.fence_version,active_run_id=r.id,lease_expires_at=r.lease_expires_at from r where shadow_supervisor_lease.id;
 with r as (select * from collect_security.shadow_supervisor_runs where id='%s'),body as (
 select r.id,r.started_at+interval '9 seconds' checked,
 jsonb_set(jsonb_set(jsonb_set(('%s'::jsonb)-array['sample_id','content_sha256'],'{checked_at}',to_jsonb(r.started_at+interval '9 seconds')),'{system_health,checked_at}',to_jsonb(r.started_at+interval '9 seconds')),'{system_health,sample_valid_until}',to_jsonb(r.started_at+interval '69 seconds')) data from r)
 insert into collect_security.shadow_supervisor_samples(run_id,checked_at,body,content_sha256) select id,checked,data,encode(extensions.digest(convert_to(data::text,'UTF8'),'sha256'),'hex') from body;
 """%(staleid,stalereq,UID,SID,stalef,staleid,template))
 stale={'run_id':staleid,'fence_version':stalef}
 case('initial finish refuses stale health before lease expiry',lambda:expected_error(db,lifecycle_sql('finish',stale),'55000','shadow_health_stale'))
 case('sample replay refuses stale source evidence',lambda:expected_error(db,lifecycle_sql('sample',stale),'55000','shadow_health_stale'))
 psql(db,'update collect_security.shadow_supervisor_lease set active_run_id=null,lease_expires_at=null where id;')
 # Concurrency helper observes pg_blocking_pids from a separate DB connection.
 a=Session(db,'A');bworker=Session(db,'B');sessions.extend([a,bworker])
 def pid(s):
  marker='PID_'+s.name;s.write("select 'PID:'||pg_backend_pid();select '%s';"%marker);lines=s.read(marker);return int(next(x[4:] for x in lines if x.startswith('PID:')))
 pa,pb=pid(a),pid(bworker)
 def blocked(waiter,holder):
  end=time.monotonic()+5
  while time.monotonic()<end:
   if psql(db,'select %d=any(pg_blocking_pids(%d));'%(holder,waiter)).stdout.strip()=='t':return True
   time.sleep(.05)
  raise AssertionError('Expected database blocking was not observed')
 def result(lines):return json.loads(next(x for x in lines if x.startswith('{') and 'outcome' in x))
 race1,race2=str(uuid.uuid4()),str(uuid.uuid4())
 a.write('begin;'+auth()+"select public.begin_collect_shadow_run_v1('%s');select 'A_HELD';"%race1);ar=result(a.read('A_HELD'))
 bworker.write('begin;'+auth(OTHER,OTHERSID)+"select public.begin_collect_shadow_run_v1('%s');select 'B_DONE';"%race2)
 blocking=blocked(pb,pa);a.write("commit;select 'A_COMMITTED';");a.read('A_COMMITTED');br=result(bworker.read('B_DONE'));bworker.write("commit;select 'B_COMMITTED';");bworker.read('B_COMMITTED')
 case('concurrent begins serialize exactly one new lease',lambda:assert_true(blocking and ar['outcome']=='started' and br['outcome']=='busy'))
 sample(ar['run']);finish(ar['run'])
 race_run=begin(str(uuid.uuid4()))['run'];sample(race_run)
 a.write('begin;'+auth()+"select public.list_collect_shadow_runs_v1();select 'HISTORY_HELD';");history_lines=a.read('HISTORY_HELD');held_history=json.loads(next(x for x in history_lines if x.startswith('{') and 'checked_at' in x))
 bworker.write('begin;'+auth()+lifecycle_sql('finish',race_run)+"select 'FINISH_AFTER_HISTORY';")
 blocking=blocked(pb,pa);a.write("commit;select 'HISTORY_COMMITTED';");a.read('HISTORY_COMMITTED');done=result(bworker.read('FINISH_AFTER_HISTORY'));bworker.write("commit;select 'FINISH_COMMITTED';");bworker.read('FINISH_COMMITTED')
 held_row=next(r for r in held_history['rows'] if r['run_id']==race_run['run_id'])
 case('history snapshot serializes concurrent finish',lambda:assert_true(blocking and held_row['status']=='running' and held_history['lease']['active_run_id']==race_run['run_id'] and done['run']['status']=='completed'))
 race_run=begin(str(uuid.uuid4()))['run'];sample(race_run)
 bworker.write('begin;'+auth()+lifecycle_sql('finish',race_run)+"select 'FINISH_HELD';");bworker.read('FINISH_HELD')
 a.write('begin;'+auth()+"select public.list_collect_shadow_runs_v1();select 'HISTORY_AFTER_FINISH';")
 blocking=blocked(pa,pb);bworker.write("commit;select 'FINISH_RELEASED';");bworker.read('FINISH_RELEASED');new_lines=a.read('HISTORY_AFTER_FINISH');new_history=json.loads(next(x for x in new_lines if x.startswith('{') and 'checked_at' in x));a.write("commit;select 'HISTORY_RELEASED';");a.read('HISTORY_RELEASED')
 new_row=next(r for r in new_history['rows'] if r['run_id']==race_run['run_id'])
 case('finish-first history observes coherent completion',lambda:assert_true(blocking and new_row['status']=='completed' and new_history['lease']['state']=='idle' and datetime.datetime.fromisoformat(new_row['completed_at'])<=datetime.datetime.fromisoformat(new_history['checked_at'])))
 # Established RR snapshot loses to a subsequent physical lease-row writer.
 bworker.write("begin isolation level repeatable read;select count(*) from collect_security.shadow_supervisor_runs;select 'RR_SNAPSHOT';");bworker.read('RR_SNAPSHOT')
 a.write('begin;'+auth()+"select public.begin_collect_shadow_run_v1('%s');select 'WRITE_HELD';"%str(uuid.uuid4()));rrwinner=result(a.read('WRITE_HELD'))
 bworker.write(auth(OTHER,OTHERSID)+"do $$begin begin perform public.begin_collect_shadow_run_v1('%s');perform set_config('collect.shadow_probe','allowed',true);exception when others then perform set_config('collect.shadow_probe',sqlstate,true);end;end$$;select 'RR_RESULT:'||current_setting('collect.shadow_probe');select 'RR_DONE';"%str(uuid.uuid4()))
 blocking=blocked(pb,pa);a.write("commit;select 'WRITE_COMMITTED';");a.read('WRITE_COMMITTED');lines=bworker.read('RR_DONE');bworker.write("rollback;select 'RR_CLOSED';");bworker.read('RR_CLOSED')
 case('physical lease write fences established RR waiter',lambda:assert_true(blocking and 'RR_RESULT:40001' in lines))
 sample(rrwinner['run']);finish(rrwinner['run'])
 # Revoke-first and read-first lock races exercise actual authoritative Auth and
 # permission rows; no permissive stub replaces the149/150 authority helper.
 a.write('begin;'+auth()+"select public.list_collect_shadow_runs_v1();select 'READ_HELD';");a.read('READ_HELD')
 bworker.write("begin;delete from public.admin_role_permissions where role_id='%s' and permission_name='notifications.read';select 'REVOKE_DONE';"%role)
 blocking=blocked(pb,pa);a.write("commit;select 'READ_COMMITTED';");a.read('READ_COMMITTED');bworker.read('REVOKE_DONE');bworker.write("commit;select 'REVOKE_COMMITTED';");bworker.read('REVOKE_COMMITTED')
 case('read-first authority locks block permission revocation',lambda:assert_true(blocking))
 case('committed permission revocation denies later history',lambda:expected_error(db,'select public.list_collect_shadow_runs_v1()','42501','shadow_permission_required'))
 psql(db,"insert into public.admin_role_permissions values('%s','notifications.read');"%role)
 bworker.write("begin;delete from auth.sessions where id='%s';select 'SESSION_REVOKE_HELD';"%SID);bworker.read('SESSION_REVOKE_HELD')
 a.write('begin;'+auth()+"do $$begin begin perform public.list_collect_shadow_runs_v1();perform set_config('collect.shadow_probe','allowed',true);exception when others then perform set_config('collect.shadow_probe',sqlstate,true);end;end$$;select 'AUTH_RESULT:'||current_setting('collect.shadow_probe');select 'AUTH_DONE';")
 blocking=blocked(pa,pb);bworker.write("commit;select 'SESSION_REVOKKED';");bworker.read('SESSION_REVOKKED');lines=a.read('AUTH_DONE');a.write("rollback;select 'AUTH_CLOSED';");a.read('AUTH_CLOSED')
 case('revoke-first session deletion denies queued history',lambda:assert_true(blocking and 'AUTH_RESULT:42501' in lines))
 case('durable record survives deleted original session',lambda:assert_true(get(req,SID2)['run']['status']=='completed'))
 case('new session cannot finish original completed run',lambda:expected_error(db,lifecycle_sql('finish',run),'42501','shadow_run_unavailable',sid=SID2))
 # Insert a legitimate expired private fixture and bind singleton at a higher
 # fence. All server APIs still derive expiry from clocks, never client data.
 expid,expreq=str(uuid.uuid4()),str(uuid.uuid4());f=int(psql(db,'select fence_version+1 from collect_security.shadow_supervisor_lease;').stdout)
 psql(db,"insert into collect_security.shadow_supervisor_runs(id,request_id,actor_id,session_id,fence_version,started_at,lease_expires_at) select '%s','%s','%s','%s',%d,t,t+interval '120 seconds' from (select clock_timestamp()-interval '121 seconds' t)s;update collect_security.shadow_supervisor_lease set fence_version=%d,active_run_id='%s',lease_expires_at=(select lease_expires_at from collect_security.shadow_supervisor_runs where id='%s') where id;"%(expid,expreq,UID,SID2,f,f,expid,expid))
 expired={'run_id':expid,'fence_version':f}
 case('expired same request cannot restart',lambda:assert_true(begin(expreq,SID2)['run']['status']=='expired'))
 for name in ['sample','finish']:
  case('expired lease '+name+' refused',lambda name=name:expected_error(db,lifecycle_sql(name,expired),'55000','shadow_lease_expired',sid=SID2))
 fresh=begin(str(uuid.uuid4()),SID2)['run'];assert fresh['fence_version']==f+1
 case('takeover increments fence and expires prior owner',lambda:assert_true(get(expreq,SID2)['run']['status']=='expired'))
 case('old fence cannot complete after takeover',lambda:expected_error(db,lifecycle_sql('finish',expired),'40001','shadow_fence_lost',sid=SID2))
 sample(fresh,SID2);finish(fresh,SID2)
 # Exercise the fence cap independently, before quota exhaustion. Rollback
 # restores the trusted fixture's fence; no API can rewind a lease version.
 def cap_probe():
  sql="begin;update collect_security.shadow_supervisor_lease set fence_version=1000000000 where id;do $$begin if (select count(*) from collect_security.shadow_supervisor_runs where started_at>clock_timestamp()-interval '1 hour')>=60 then raise exception 'Cap test masked by quota';end if;end$$;"+auth(sid=SID2)+"do $$begin begin perform public.begin_collect_shadow_run_v1(gen_random_uuid());raise exception 'Cap unexpectedly allowed';exception when sqlstate '55000' then if sqlerrm<>'shadow_limit_reached' then raise;end if;end;end$$;select 'CAP_REFUSED_BELOW_QUOTA';rollback;"
  r=psql(db,sql);assert 'CAP_REFUSED_BELOW_QUOTA' in r.stdout;return {'below_quota':True,'fence_version':1000000000,'sqlstate':'55000','reason':'shadow_limit_reached'}
 case('fence cap cannot overflow independently of quota',cap_probe)
 # Global quota is tested with trusted expired fixture rows, all at one time.
 current=int(psql(db,"select count(*) from collect_security.shadow_supervisor_runs where started_at>clock_timestamp()-interval '1 hour';").stdout)
 psql(db,"insert into collect_security.shadow_supervisor_runs(request_id,actor_id,session_id,fence_version,status,started_at,lease_expires_at) select gen_random_uuid(),'%s','%s',1000+g,'expired',t,t+interval '120 seconds' from generate_series(1,%d)g cross join (select clock_timestamp()-interval '3 minutes't)s;"%(UID,SID2,60-current))
 case('global rolling-hour60-run limit is enforced',lambda:expected_error(db,'select public.begin_collect_shadow_run_v1(gen_random_uuid())','55000','shadow_limit_reached',sid=SID2))
 h=hist(50,sid=SID2);h2=hist(50,h['next_cursor'],SID2);assert len(h['rows'])==50 and len(h2['rows'])==10 and len({r['run_id'] for r in h['rows']+h2['rows']})==60
 case('same timestamp keyset tie paging is stable',lambda:True)
 after=fingerprint(db);evidence['business_after']=after;case('seven scoped payment journal outbox attempt heartbeat fingerprints unchanged',lambda:assert_true(after==baseline))


if __name__=='__main__':main()
