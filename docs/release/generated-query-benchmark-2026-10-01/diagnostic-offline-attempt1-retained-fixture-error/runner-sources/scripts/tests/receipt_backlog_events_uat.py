#!/usr/bin/env python3
"""Local schema-only isolated receipt backlog/events UAT. No remote URL accepted.
Source rows/credentials are never copied. Synthetic provider confirmation is a
fixture for accounting transitions, not evidence of authentic provider payment.
"""
import argparse,datetime,hashlib,importlib.util,json,pathlib,re,sys,uuid,time
import shadow_supervisor_uat as u
ROOT=u.ROOT;DOCKER=u.DOCKER;CONTAINER=u.CONTAINER;PROJECT=u.PROJECT
command=u.command
_original_psql=u.psql
RAW_QUERY_LOG=None
def psql(db,sql,check=True,user='postgres'):
 if RAW_QUERY_LOG is not None:
  with RAW_QUERY_LOG.open('a') as log:log.write('-- database '+db+' (local synthetic/schema-only)\n'+sql+'\n')
 return _original_psql(db,sql,check,user)
u.psql=psql
UID=u.UID;SID=u.SID;OTHER=u.OTHER;OTHERSID=u.OTHERSID
MIGRATION=ROOT/'supabase/migrations/20260930230100_receipt_backlog_events.sql'
GROUP='99710000-0000-4000-8000-000000030001'
MEMBER='99710000-0000-4000-8000-000000040001'
NO_CONSENT='99710000-0000-4000-8000-000000040002'
ROLE='99710000-0000-4000-8000-000000020001'

def main():
 global RAW_QUERY_LOG
 parser=argparse.ArgumentParser();parser.add_argument('--report-dir',required=True);args=parser.parse_args()
 report=pathlib.Path(args.report_dir).resolve();assert not report.exists(),'Fresh report directory required';report.mkdir(parents=True)
 RAW_QUERY_LOG=report/'queries.sql'
 evidence={'kind':'receipt_backlog_events_schema_only_synthetic','started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'production_written':False,'provider_called':False,'cases':[]}
 def save():(report/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
 def case(name,fn):
  result=fn();evidence['cases'].append({'name':name,'status':'pass','detail':result});save();print('PASS '+name,flush=True);return result
 labels=json.loads(command([DOCKER,'inspect',CONTAINER,'--format','{{json .Config.Labels}}']).stdout)
 ports=json.loads(command([DOCKER,'inspect',CONTAINER,'--format','{{json .HostConfig.PortBindings}}']).stdout)
 assert labels['com.supabase.cli.project']==PROJECT and labels['com.docker.compose.project']==PROJECT and all(x['HostPort']=='55722' for x in ports['5432/tcp'])
 metadata=json.loads(psql('postgres',"select jsonb_build_object('count',(select count(*) from supabase_migrations.schema_migrations),'latest',(select max(version) from supabase_migrations.schema_migrations),'cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size')); ").stdout)
 assert (metadata['count'],metadata['latest']) in [(150,'20260930180000'),(151,'20260930200000'),(152,'20260930210000'),(153,'20260930220000')] and metadata['cron']=='off' and metadata['net']=='0',metadata
 evidence['source_metadata']=metadata;
 evidence['known_extra_migration_parity']={}
 for version,name in [('20260930200000','admin_automation_navigation'),('20260930210000','shadow_supervisor_runs'),('20260930220000','runtime_control_authority')]:
  if version>metadata['latest']:continue
  local=(ROOT/'supabase/migrations'/(version+'_'+name+'.sql')).read_text().rstrip()
  stored=psql('postgres',"select statements[1] from supabase_migrations.schema_migrations where version='%s';"%version).stdout.rstrip()
  assert local==stored,'Known extra migration source parity failed '+version
  evidence['known_extra_migration_parity'][version]={'normalized_source_sha256':hashlib.sha256(local.encode()).hexdigest(),'normalized_installed_sha256':hashlib.sha256(stored.encode()).hexdigest(),'exact_normalized_parity':True}
 evidence['migration_path']=str(MIGRATION.relative_to(ROOT));evidence['migration_sha256']=hashlib.sha256(MIGRATION.read_bytes()).hexdigest();evidence['runner_sha256']=hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()
 # Relevant authority source equality, not merely a quiet installed fixture.
 source=(ROOT/'supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql').read_text()
 installed=psql('postgres',"select statements[1] from supabase_migrations.schema_migrations where version='20260930170000';").stdout.rstrip()
 pattern=r'create function collect_hybrid\.require_roster_actor_authority\(.*?end \$\$;'
 sm=re.search(pattern,source,re.S);im=re.search(pattern,installed,re.S);assert sm and im and sm.group()==im.group()
 evidence['authority_prerequisite']={'relevant_function_sha256':hashlib.sha256(sm.group().encode()).hexdigest(),'relevant_function_source_parity':True,'whole_migration_parity':source.rstrip()==installed}
 db='collect_receipt_foundation_'+uuid.uuid4().hex[:12];evidence['database']=db;made=False;sessions=[]
 try:
  dump=command([DOCKER,'exec',CONTAINER,'pg_dump','-U','postgres','-d','postgres','--schema-only','--no-owner','--no-privileges','--no-publications','--no-subscriptions','--exclude-extension=pg_cron','--exclude-extension=pg_net','--exclude-extension=pg_stat_statements','--exclude-extension=pg_graphql','--exclude-schema=graphql','--exclude-schema=graphql_public','--exclude-schema=cron','--exclude-schema=net']).stdout
  (report/'schema-only.sql').write_text(dump)
  after_dump=json.loads(psql('postgres',"select jsonb_build_object('count',(select count(*) from supabase_migrations.schema_migrations),'latest',(select max(version) from supabase_migrations.schema_migrations),'cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'));").stdout)
  assert after_dump==metadata,'Source migration metadata changed during schema dump'
  evidence['source_metadata_after_dump']=after_dump
  evidence['source_schema_dump_sha256']=hashlib.sha256(dump.encode()).hexdigest()
  # API-facing ACLs are reconstructed from catalog privilege rows, without
  # source grantors/owners or superuser builtin grants. Authority function bodies,
  # RLS policies and business schemas are the actual installed source definitions (150 through source-verified runtime-control153).
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
  (report/'api-acl.sql').write_text(acl)
  evidence['application_api_acl_sha256']=hashlib.sha256(acl.encode()).hexdigest()
  evidence['restored_schema_dump_sha256']=hashlib.sha256(dump.encode()).hexdigest();save()
  psql('postgres','create database '+db+' template template0;');made=True
  mock="create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);"
  restored=psql(db,mock+dump+acl,False)
  (report/'restore.log').write_text(restored.stderr)
  if restored.returncode:raise RuntimeError('Schema-only restore failed: '+restored.stderr[-3000:])
  seed(db)
  # Retain a genuinely nonempty pre-migration primary receipt too; the paused
  # historical250RWF example alone would only exercise nonempty accounting.
  prior_sql="update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+service(payment_sql('99710000-0000-4000-8000-000000049999',amount=50))+"update public.feature_flags set enabled=false where key='hybrid_sms_notifications';"
  (report/'preexisting-receipt.sql').write_text('-- Synthetic local-only prior receipt, no live send.\n'+prior_sql+'\n')
  psql(db,prior_sql)
  before=business_fingerprint(db);evidence['before_install']=before
  evidence['prior_receipt']=json.loads(psql(db,"select to_jsonb(o) from collect_hybrid.sms_notification_outbox o where payment_id='99710000-0000-4000-8000-000000049999';").stdout)
  install=psql(db,MIGRATION.read_text(),False)
  (report/'install.stdout.log').write_text(install.stdout);(report/'install.stderr.log').write_text(install.stderr)
  evidence['install_exit_code']=install.returncode
  if install.returncode:raise RuntimeError(install.stderr[-4000:])
  case('install preserves nonempty financial/outbox fixture',lambda:equal(before,business_fingerprint(db)))
  u.SQL_LOG=report/'queries.log';u.CONCURRENCY_LOG=report/'concurrency.log'
  run_cases(db,case,evidence,report,sessions)
  evidence['status']='pass'
 except Exception as e:
  evidence['status']='failed';evidence['failure']=str(e);save();raise
 finally:
  u.SQL_LOG=None
  for session in sessions:
   try:session.close()
   except Exception as e:evidence.setdefault('cleanup_errors',[]).append(str(e))
  if made:
   cleanup=psql('postgres','drop database '+db+' with (force);',False);evidence['isolated_database_removed']=cleanup.returncode==0
  RAW_QUERY_LOG=None
  evidence['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()

def equal(a,b):assert a==b,(a,b);return True

def business_fingerprint(db):
 result=u.fingerprint(db)
 for table in ['momo_journal_lines','momo_balance_snapshots','collection_balances','member_balances']:
  sql="select jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),'sha256'),'hex')) from collect_hybrid."+table+' t;'
  result[table]=json.loads(psql(db,sql).stdout)
 return result

def service(sql):return "begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"+sql+';commit;'

def payment_sql(pid,member=MEMBER,amount=100,ref=None,parsed=None,posted=True):
 ref=ref or 'FOUNDATION-'+pid[-8:]
 member_sql="null" if member is None else "'%s'"%member
 event_sql="null" if parsed is None else "'%s'"%parsed
 body="insert into public.payments(id,parsed_event_id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at) values('%s',%s,'%s',%s,'%s',repeat('a',64),%d,'%s','mtn_momo','manual_admin','review',null);"%(pid,event_sql,GROUP,member_sql,UID,amount,ref)
 if posted:body+="select public.confirm_provider_payment('%s','mtn_momo','%s','%s',repeat('a',64),%d,clock_timestamp(),repeat('b',64));"%(pid,ref,'CONF-'+ref,amount)
 return body

def seed(db):
 psql(db,"""insert into public.admin_roles(id,name,description) values('%s','platform_owner','Synthetic foundation owner');
 insert into public.admin_permissions(name,description) values('system_health.read','Synthetic'),('notifications.read','Synthetic'),('notifications.manage','Synthetic'),('collections.moderate','Synthetic'),('payments.allocate','Synthetic');
 insert into public.admin_role_permissions(role_id,permission_name) select '%s',name from public.admin_permissions;
 insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
 ('%s','authenticated','authenticated','250788971001',now(),'{}','{}'),('%s','authenticated','authenticated','250788971002',now(),'{}','{}');
 insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason) values('%s','+250788971001',clock_timestamp()-interval '2 minutes','Synthetic foundation identity'),('%s','+250788971002',clock_timestamp()-interval '2 minutes','Synthetic foundation identity');
 insert into public.admin_user_roles(user_id,role_id,reason,created_at) values('%s','%s','Synthetic foundation grant',clock_timestamp()-interval '1 minute'),('%s','%s','Synthetic foundation grant',clock_timestamp()-interval '1 minute');
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
 insert into public.feature_flags(key,enabled,description) values('hybrid_sms_notifications',false,'Synthetic dispatch gate');
 insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin) values('%s','foundation-synthetic','%s','Synthetic receipt foundation','Family / friends','private','private','ikimina','members',false,false,'admin_assisted');
 insert into collect_hybrid.member_records(id,collect_id,origin,created_by) values('%s','971201','admin_assisted','%s'),('%s','971202','admin_assisted','%s');
 insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number) values('%s','Synthetic member','SYNTHETIC MEMBER','+250788971201'),('%s','No consent member','NO CONSENT MEMBER','+250788971202');
 insert into public.collection_members(collection_id,member_record_id,role,status) values('%s','%s','member','active'),('%s','%s','member','active');
 insert into collect_hybrid.sms_receipt_policies(collection_id,enabled,reason,updated_by) values('%s',true,'Synthetic receipt policy','%s');
 insert into collect_hybrid.sms_receipt_member_consents(member_record_id,enabled,capture_method,reason,recorded_by) values('%s',true,'written','Synthetic explicit consent','%s');
 """%(ROLE,ROLE,UID,OTHER,UID,OTHER,UID,ROLE,OTHER,ROLE,SID,UID,OTHERSID,OTHER,GROUP,UID,MEMBER,UID,NO_CONSENT,UID,MEMBER,NO_CONSENT,GROUP,MEMBER,GROUP,NO_CONSENT,GROUP,UID,MEMBER,UID))
 # Old paused behavior is represented by a real finalized synthetic payment.
 psql(db,service(payment_sql('99710000-0000-4000-8000-000000050000',amount=250)))

def run_cases(db,case,evidence,report,sessions):
 def check(v):assert v;return True
 def truth(sql):return check(psql(db,sql).stdout.strip()=='t')
 def scalar(sql):return psql(db,sql).stdout.strip()
 def result(sql):return json.loads(psql(db,service(sql)).stdout.strip().splitlines()[-1])
 def error(sql,state,reason,mode='service'):
  query=service(sql) if mode=='service' else sql
  before=business_fingerprint(db)
  r=psql(db,query,False);assert r.returncode and state+':' in r.stderr and reason in r.stderr,r.stderr
  equal(before,business_fingerprint(db));return {'sqlstate':state,'reason':reason,'financial_evidence_preserved':True}
 def pid(n):return '99710000-0000-4000-8000-%012d'%(50000+n)
 def flag(enabled):psql(db,"update public.feature_flags set enabled=%s where key='hybrid_sms_notifications';"%('true' if enabled else 'false'))
 def post(n,member=MEMBER,amount=100,parsed=None):
  psql(db,service(payment_sql(pid(n),member,amount,parsed=parsed)));return pid(n)
 def event_list(c,limit=50,uid=UID,sid=SID,skip=None):
  extra='' if skip is None else ",array[%s]::uuid[]"%(','.join("'%s'"%s for s in skip))
  return u.call(db,"select public.list_receipt_monitor_events_v1('%s',%d%s)"%(c,limit,extra),uid,sid)
 def ack(c,event,req=None,outcome='observed',reason='monitoring_only',uid=UID,sid=SID):
  req=req or str(uuid.uuid4())
  return u.call(db,"select public.ack_receipt_monitor_event_v1('%s','%s','%s','%s','%s')"%(c,event,req,outcome,reason),uid,sid)
 new_tables=['receipt_business_event_heads','receipt_business_events','receipt_monitor_consumers','receipt_monitor_acknowledgements','receipt_monitor_observed_events']
 quoted=','.join("'%s'"%x for x in new_tables)
 case('new private tables have RLS and no API direct grants',lambda:truth("select bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE')) from pg_class c cross join unnest(array['anon','authenticated','service_role']) r where c.relnamespace='collect_hybrid'::regnamespace and c.relname in (%s);"%quoted))
 case('five new RPCs grant only authenticated execution',lambda:truth("select count(*)=5 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE')) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('register_receipt_monitor_consumer_v1','list_receipt_monitor_events_v1','ack_receipt_monitor_event_v1','admin_preview_receipt_backlog_v1','admin_reconcile_receipt_backlog_v1');"))
 for api_role in ['anon','service_role']:
  case(api_role+' cannot register monitor',lambda api_role=api_role:u.expected_error(db,'select public.register_receipt_monitor_consumer_v1()','42501',role=api_role))
 case('invalid current session refused',lambda:u.expected_error(db,'select public.register_receipt_monitor_consumer_v1()','42501',sid=str(uuid.uuid4())))
 def revoked_authority_probe(mutation):
  sql='begin;'+mutation+u.auth()+"do $$begin begin perform public.register_receipt_monitor_consumer_v1();raise exception 'Unexpected receipt authority';exception when sqlstate '42501' then null;end;end$$;select 'AUTHORITY_REFUSED';rollback;"
  return check('AUTHORITY_REFUSED' in psql(db,sql).stdout)
 for label,mutation in [
  ('unconfirmed phone',"update auth.users set phone_confirmed_at=null where id='%s';"%UID),
  ('revoked approval',"update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp() where user_id='%s';"%UID),
  ('revoked platform grant',"update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='%s';"%UID),
  ('expired session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='%s';"%SID),
  ('missing notification permission',"delete from public.admin_role_permissions where role_id='%s' and permission_name='notifications.read';"%ROLE),
  ('missing system-health permission',"delete from public.admin_role_permissions where role_id='%s' and permission_name='system_health.read';"%ROLE),
  ('session predates approval',"update collect_admin_access.whatsapp_approvals set approved_at=clock_timestamp()+interval '1 minute' where user_id='%s';"%UID),
  ('session predates role grant',"update public.admin_user_roles set created_at=clock_timestamp()+interval '1 minute' where user_id='%s';"%UID),
 ]:
  case('monitor current authority rejects '+label,lambda mutation=mutation:revoked_authority_probe(mutation))
 consumer=u.call(db,'select public.register_receipt_monitor_consumer_v1()')['consumer_id']
 case('consumer registration is actor-bound and idempotent',lambda:equal(consumer,u.call(db,'select public.register_receipt_monitor_consumer_v1()')['consumer_id']))
 case('no historical event or receipt inserted at migration install',lambda:truth("select not exists(select 1 from collect_hybrid.receipt_business_events) and (select count(*) from collect_hybrid.sms_notification_outbox)=1;"))
 p1=case('paused new confirmed payment posts deterministic nonempty journal',lambda:post(1,amount=500))
 job=json.loads(scalar("select to_jsonb(o) from collect_hybrid.sms_notification_outbox o where payment_id='%s';"%p1))
 case('pause captures exactly one immutable eligible queued receipt',lambda:check(job['state']=='queued' and job['member_balance_rwf']==800 and job['group_balance_rwf']==800 and job['template_version']==1))
 case('lifetime primary receipt uniqueness prevents duplicate snapshot enqueue',lambda:error("insert into collect_hybrid.sms_notification_outbox select (jsonb_populate_record(null::collect_hybrid.sms_notification_outbox,to_jsonb(o)||jsonb_build_object('id',gen_random_uuid()))).* from collect_hybrid.sms_notification_outbox o where id='%s'"%job['id'],'23505','duplicate key','owner'))
 case('posting and receipt creation emit two committed UUID events',lambda:truth("select count(*)=2 and count(distinct id)=2 from collect_hybrid.receipt_business_events where payment_id='%s';"%p1))
 baseline=business_fingerprint(db);event_count=scalar('select count(*) from collect_hybrid.receipt_business_events;')
 psql(db,"select collect_hybrid.post_momo_receipt('%s');"%p1)
 case('idempotent journal replay preserves receipts, balances and events',lambda:check(business_fingerprint(db)==baseline and scalar('select count(*) from collect_hybrid.receipt_business_events;')==event_count))
 claim_sql="select public.collect_claim_receipt('%s','%s','foundation-worker','%s')"%(UID,job['id'],str(uuid.uuid4()))
 paused_commands=[claim_sql,
  "select public.collect_get_claimed_receipt('%s','%s','%s',1)"%(UID,job['id'],str(uuid.uuid4())),
  "select public.collect_confirm_receipt('%s','%s','%s',1,1,repeat('a',64),'%s')"%(UID,job['id'],str(uuid.uuid4()),str(uuid.uuid4())),
  "select public.collect_record_send_start('%s','%s','%s',1,'%s')"%(UID,job['id'],str(uuid.uuid4()),str(uuid.uuid4()))]
 for command in paused_commands:
  case('pause refuses assisted '+command.split('public.')[1].split('(')[0],lambda command=command:error(command,'55000','receipt_dispatch_paused'))
 case('pause refusal does not permanently suppress queued work',lambda:truth("select state='queued' and suppression_reason is null from collect_hybrid.sms_notification_outbox where id='%s';"%job['id']))
 case('direct future claim-state path also encounters hard pause guard',lambda:error("update collect_hybrid.sms_notification_outbox set state='awaiting_confirmation',claim_token=gen_random_uuid(),claimed_by='future-worker',claim_expires_at=clock_timestamp()+interval '5 minutes' where id='%s'"%job['id'],'55000','receipt_dispatch_paused','owner'))
 case('direct future attempt insertion also encounters hard pause guard',lambda:error("insert into collect_hybrid.sms_notification_attempts(outbox_id) values('%s')"%job['id'],'55000','receipt_dispatch_paused','owner'))
 flag(True);claim=result(claim_sql)
 case('resume can claim preexisting paused queue without re-enqueue',lambda:check(claim['ok'] and claim['fence_version']==1))
 exact=result("select public.collect_get_claimed_receipt('%s','%s','%s',%d)"%(UID,job['id'],claim['claim_token'],claim['fence_version']))
 confirmation_id=str(uuid.uuid4())
 confirm_sql="select public.collect_confirm_receipt('%s','%s','%s',%d,%d,'%s','%s')"%(UID,job['id'],claim['claim_token'],claim['fence_version'],exact['destination_revision'],exact['body_sha256'],confirmation_id)
 case('enabled exact human-confirmation boundary remains available',lambda:check(result(confirm_sql)['ok']))
 flag(False)
 case('pause blocks even an old successful claim request replay',lambda:error(claim_sql,'55000','receipt_dispatch_paused'))
 case('pause blocks even an old human confirmation replay',lambda:error(confirm_sql,'55000','receipt_dispatch_paused'))
 start_sql="select public.collect_record_send_start('%s','%s','%s',%d,'%s')"%(UID,job['id'],claim['claim_token'],claim['fence_version'],confirmation_id)
 case('pause blocks freshly confirmed durable pre-send authorization',lambda:error(start_sql,'55000','receipt_dispatch_paused'))
 flag(True);attempt=result(start_sql)
 case('enabled pre-send records attempt without contacting a carrier',lambda:check(attempt['ok'] and attempt['state']=='send_started'))
 flag(False)
 case('pause blocks old send-start request replay authority',lambda:error(start_sql,'55000','receipt_dispatch_paused'))
 # Outcome evidence is intentionally recordable while paused; no send begins.
 outcome_sql="select public.collect_record_observed_outcome('%s','%s','uncertain','synthetic-uat','Synthetic unknown send fixture, no carrier called')"%(UID,attempt['attempt_id'])
 outcome=result(outcome_sql);replayed_outcome=result(outcome_sql)
 case('paused operator can retain uncertainty evidence',lambda:check(outcome['state']=='uncertain'))
 case('old attempt uncertainty replay remains recordable while paused',lambda:check(replayed_outcome['state']=='uncertain' and replayed_outcome['replay']))
 case('uncertain transition emits exactly one actionable UUID event',lambda:truth("select count(*)=1 from collect_hybrid.receipt_business_events where outbox_id='%s' and event_kind='receipt_uncertain';"%job['id']))
 p2=post(2,NO_CONSENT,100)
 case('no consent skips receipt but preserves committed payment event',lambda:truth("select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='%s') and exists(select 1 from collect_hybrid.receipt_business_events where payment_id='%s' and event_kind='payment_posted');"%(p2,p2)))
 # Existing Auth trigger creates the app-linked member record for OTHER.
 p3=post(3,OTHER,150)
 case('app-linked policy does not broaden SMS recipients',lambda:truth("select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='%s') and exists(select 1 from collect_hybrid.receipt_business_events where payment_id='%s' and event_kind='payment_posted');"%(p3,p3)))
 psql(db,"update collect_hybrid.sms_receipt_policies set enabled=false where collection_id='%s';"%GROUP)
 p4=post(4,amount=75)
 case('disabled group policy is eligibility exclusion rather than dispatch pause',lambda:truth("select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='%s');"%p4))
 psql(db,"update collect_hybrid.sms_receipt_policies set enabled=true where collection_id='%s';"%GROUP)
 preview=u.call(db,'select public.admin_preview_receipt_backlog_v1(2)')
 case('bounded historical preview has explicit pending-policy refusal',lambda:check(len(preview['rows'])==2 and preview['next_cursor'] is not None and not preview['historical_enqueue_enabled'] and preview['catch_up']=='policy_pending'))
 cursor=preview['next_cursor']
 page2=u.call(db,"select public.admin_preview_receipt_backlog_v1(2,'%s','%s')"%(cursor['captured_at'],cursor['snapshot_id']))
 case('preview paired keyset pages avoid duplicates',lambda:check(not(set(x['snapshot_id'] for x in preview['rows'])&set(x['snapshot_id'] for x in page2['rows']))))
 all_preview=u.call(db,'select public.admin_preview_receipt_backlog_v1(50)')
 codes={x['payment_id']:x['eligibility_code'] for x in all_preview['rows']}
 case('preview reports current consent/app-link/eligible history without contacts',lambda:check(codes[p2]=='CONSENT_DISABLED' and codes[p3]=='APP_LINKED_MEMBER' and codes[pid(0)]=='CURRENTLY_ELIGIBLE_HISTORY_UNPROVEN' and all('destination_e164' not in x and 'message_body' not in x and 'amount_rwf' not in x for x in all_preview['rows'])))
 before=business_fingerprint(db);row=all_preview['rows'][0]
 refusal=u.call(db,"select public.admin_reconcile_receipt_backlog_v1('%s',array['%s']::uuid[],array['%s'])"%(str(uuid.uuid4()),row['snapshot_id'],row['review_version']))
 case('historical reconcile cannot enqueue while policy pending',lambda:check(refusal['code']=='CATCHUP_POLICY_PENDING' and refusal['queued']==0 and before==business_fingerprint(db)))
 # A parsed record created yesterday resolves today: event trigger is transition
 # based and cannot be skipped by transaction creation-time pagination.
 parsed=str(uuid.uuid4())
 psql(db,"insert into public.parsed_payment_events(id,collection_id,receiver_user_id,is_mobile_money_payment,network,direction,amount_rwf,currency,transaction_id,receiver_phone_hash,transaction_time,created_at) values('%s','%s','%s',true,'mtn_momo','incoming',300,'RWF','LATE-ALLOCATION',repeat('a',64),clock_timestamp(),clock_timestamp()-interval '1 day');"%(parsed,GROUP,UID))
 psql(db,"update public.parsed_payment_events set allocation_status='needs_review' where id='%s';"%parsed)
 p5=post(5,amount=300,parsed=parsed)
 case('late allocation produces immutable transition events and posted receipt',lambda:truth("select (select count(*) from collect_hybrid.receipt_business_events where source_kind='allocation' and source_id='%s')=3 and exists(select 1 from collect_hybrid.receipt_business_events where source_id='%s' and source_state='allocated') and exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='%s');"%(parsed,parsed,p5)))
 # Reversal uses the existing compensating accounting RPC unchanged.
 reverse=u.call(db,"select public.admin_reverse_momo_payment('%s','Synthetic receipt foundation reversal','%s')"%(p5,str(uuid.uuid4())))
 case('reversal emits event while retaining original receipt payload',lambda:check(reverse['ok'] and truth("select exists(select 1 from collect_hybrid.receipt_business_events where payment_id='%s' and event_kind='payment_reversed') and exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='%s' and amount_rwf=300);"%(p5,p5))))
 flag(True)
 reversed_job=scalar("select id from collect_hybrid.sms_notification_outbox where payment_id='%s';"%p5)
 suppressed=result("select public.collect_claim_receipt('%s','%s','foundation-worker','%s')"%(UID,reversed_job,str(uuid.uuid4())))
 case('reversed payment suppresses unsafe unsent receipt independently of pause',lambda:check(not suppressed['ok'] and suppressed['state']=='suppressed'))
 case('suppression emits actionable event',lambda:truth("select exists(select 1 from collect_hybrid.receipt_business_events where outbox_id='%s' and event_kind='receipt_suppressed');"%reversed_job))
 baseline=business_fingerprint(db);pending=event_list(consumer)
 (report/'events.fixture.json').write_text(json.dumps(pending,indent=2)+'\n')
 (report/'backlog.fixture.json').write_text(json.dumps(all_preview,indent=2)+'\n')
 case('event reads expose only redacted immutable IDs/status/version',lambda:check(all(set(x)=={'id','source_kind','source_id','source_version','event_kind','collection_id','payment_id','member_record_id','snapshot_id','outbox_id','source_state','created_at'} for x in pending['rows'])))
 first=pending['rows'][0]['id'];req=str(uuid.uuid4())
 deferred=ack(consumer,first,req,'deferred','review_required')
 case('deferred is durable observation but remains pending',lambda:check(deferred['pending'] and not deferred['business_handled'] and first in [x['id'] for x in event_list(consumer)['rows']]))
 case('exact ACK request replay returns existing immutable acknowledgement',lambda:equal(deferred,ack(consumer,first,req,'deferred','review_required')))
 case('ACK request collision cannot change outcome',lambda:u.expected_error(db,"select public.ack_receipt_monitor_event_v1('%s','%s','%s','observed','monitoring_only')"%(consumer,first,req),'22023','receipt_monitor_request_conflict'))
 observed=ack(consumer,first)
 case('observed UUID progress removes only one event from this consumer',lambda:check(not observed['pending'] and first not in [x['id'] for x in event_list(consumer)['rows']] and len(event_list(consumer)['rows'])==len(pending['rows'])-1))
 other_consumer=u.call(db,'select public.register_receipt_monitor_consumer_v1()',OTHER,OTHERSID)['consumer_id']
 case('independent consumer retains independently unobserved same event',lambda:check(first in [x['id'] for x in event_list(other_consumer,uid=OTHER,sid=OTHERSID)['rows']]))
 for command in ["select public.list_receipt_monitor_events_v1('%s')"%consumer,"select public.ack_receipt_monitor_event_v1('%s','%s','%s','observed','monitoring_only')"%(consumer,first,str(uuid.uuid4()))]:
  case('different actor cannot use another consumer '+command.split('public.')[1].split('(')[0],lambda command=command:u.expected_error(db,command,'42501','receipt_consumer_scope_denied',uid=OTHER,sid=OTHERSID))
 rollback_event=event_list(consumer)['rows'][0]['id'];rollback_req=str(uuid.uuid4())
 psql(db,'begin;'+u.auth()+"select public.ack_receipt_monitor_event_v1('%s','%s','%s','observed','monitoring_only');rollback;"%(consumer,rollback_event,rollback_req))
 case('rolled-back ACK never advances durable progress',lambda:check(rollback_event in [x['id'] for x in event_list(consumer)['rows']] and scalar("select count(*) from collect_hybrid.receipt_monitor_acknowledgements where request_id='%s';"%rollback_req)=='0'))
 ack(consumer,rollback_event)
 case('partial batch recovery resumes from remaining unobserved UUIDs',lambda:check(rollback_event not in [x['id'] for x in event_list(consumer)['rows']] and len(event_list(consumer)['rows'])==len(pending['rows'])-2))
 for args in ["'%s',0"%consumer,"'%s',51"%consumer,"'%s',20,null"%consumer]:
  case('invalid bounded event arguments '+args,lambda args=args:u.expected_error(db,'select public.list_receipt_monitor_events_v1('+args+')','22023','receipt_monitor_request_invalid'))
 case('ephemeral skip does not acknowledge or persist progress',lambda:check(first not in [x['id'] for x in event_list(other_consumer,uid=OTHER,sid=OTHERSID,skip=[first])['rows']] and first in [x['id'] for x in event_list(other_consumer,uid=OTHER,sid=OTHERSID)['rows']]))
 case('all monitoring and pending catch-up operations preserve nonempty finances/receipts',lambda:equal(baseline,business_fingerprint(db)))
 case('immutable event evidence cannot be edited',lambda:error("update collect_hybrid.receipt_business_events set source_state='ignored' where id='%s'"%first,'55000','receipt_event_evidence_immutable','owner'))
 # Receipt/policy change between events and observation cannot turn ACK into
 # authority to send. Consent revocation still enforces the old eligibility.
 p6=post(6,amount=100)
 psql(db,"update collect_hybrid.sms_receipt_member_consents set enabled=false where member_record_id='%s';"%MEMBER)
 consent_job=scalar("select id from collect_hybrid.sms_notification_outbox where payment_id='%s';"%p6)
 case('revoked consent suppresses newly captured immutable receipt',lambda:check(result("select public.collect_claim_receipt('%s','%s','foundation-worker','%s')"%(UID,consent_job,str(uuid.uuid4())))['state']=='suppressed'))
 psql(db,"update collect_hybrid.sms_receipt_member_consents set enabled=true where member_record_id='%s';"%MEMBER)
 p7=post(7,amount=125)
 failed_job=scalar("select id from collect_hybrid.sms_notification_outbox where payment_id='%s';"%p7)
 failed_claim=result("select public.collect_claim_receipt('%s','%s','foundation-worker','%s')"%(UID,failed_job,str(uuid.uuid4())))
 failed_exact=result("select public.collect_get_claimed_receipt('%s','%s','%s',%d)"%(UID,failed_job,failed_claim['claim_token'],failed_claim['fence_version']))
 failed_confirm=str(uuid.uuid4())
 result("select public.collect_confirm_receipt('%s','%s','%s',%d,%d,'%s','%s')"%(UID,failed_job,failed_claim['claim_token'],failed_claim['fence_version'],failed_exact['destination_revision'],failed_exact['body_sha256'],failed_confirm))
 failed_attempt=result("select public.collect_record_send_start('%s','%s','%s',%d,'%s')"%(UID,failed_job,failed_claim['claim_token'],failed_claim['fence_version'],failed_confirm))
 failed_outcome_sql="select public.collect_record_observed_outcome('%s','%s','failed_no_send','synthetic-uat','Synthetic definitely not sent fixture, no carrier called')"%(UID,failed_attempt['attempt_id'])
 result(failed_outcome_sql);result(failed_outcome_sql)
 case('definite not-sent failure and exact outcome replay emit one actionable event',lambda:truth("select count(*)=1 from collect_hybrid.receipt_business_events where outbox_id='%s' and event_kind='receipt_failed_no_send';"%failed_job))
 p8=post(8,member=None,amount=60)
 case('member-unassigned posting still emits committed payment event',lambda:truth("select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='%s') and exists(select 1 from collect_hybrid.receipt_business_events where payment_id='%s' and member_record_id is null and event_kind='payment_posted');"%(p8,p8)))
 p9=post(9,amount=100)
 identity_job=scalar("select id from collect_hybrid.sms_notification_outbox where payment_id='%s';"%p9)
 original_body=scalar("select body_sha256 from collect_hybrid.sms_notification_outbox where id='%s';"%identity_job)
 psql(db,"update collect_hybrid.member_momo_identities set momo_number='+250788971299',revision=revision+1 where member_id='%s';"%MEMBER)
 case('contact change suppresses old destination without replacing immutable payload',lambda:check(result("select public.collect_claim_receipt('%s','%s','foundation-worker','%s')"%(UID,identity_job,str(uuid.uuid4())))['state']=='suppressed' and original_body==scalar("select body_sha256 from collect_hybrid.sms_notification_outbox where id='%s';"%identity_job)))
 psql(db,"insert into collect_hybrid.sms_receipt_member_consents(member_record_id,enabled,capture_method,reason,recorded_by) values('%s',true,'written','Synthetic later consent not historical authorization','%s');"%(NO_CONSENT,UID))
 later_preview=u.call(db,'select public.admin_preview_receipt_backlog_v1(50)')
 case('later consent never automatically backfills historic recipient',lambda:check(not later_preview['historical_enqueue_enabled'] and not scalar("select exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='%s');"%p2)=='t'))
 run_concurrency(db,case,consumer,event_list,evidence,sessions)
 case('all synthetic posted/reversed journals remain exactly balanced',lambda:truth("select not exists(select 1 from collect_hybrid.momo_journal_entries e left join collect_hybrid.momo_journal_lines l on l.journal_entry_id=e.id group by e.id,e.amount_rwf having count(*)<>2 or sum(case when l.direction='debit' then l.amount_rwf else -l.amount_rwf end)<>0 or min(l.amount_rwf)<>e.amount_rwf or max(l.amount_rwf)<>e.amount_rwf);"))
 case('net canonical group balance equals nonempty posted payment value',lambda:truth("select b.confirmed_rwf=(select sum(amount_rwf) from public.payments where collection_id=b.collection_id and status='posted') from collect_hybrid.collection_balances b where collection_id='%s';"%GROUP))
 case('old primary receipt remains byte-for-byte unchanged after all new work',lambda:equal(evidence['prior_receipt'],json.loads(scalar("select to_jsonb(o) from collect_hybrid.sms_notification_outbox o where payment_id='99710000-0000-4000-8000-000000049999';"))))
 evidence['after_all']=business_fingerprint(db)
 evidence['event_count']=int(scalar('select count(*) from collect_hybrid.receipt_business_events;'))

def run_concurrency(db,case,consumer,event_list,evidence,sessions):
 def check(v):assert v;return True
 # A transaction with an earlier timestamp commits after a later event is ACKed.
 # Rescanning unobserved UUIDs must still return the late commit.
 early=str(uuid.uuid4());late=str(uuid.uuid4())
 a=u.Session(db,'event-earlier-commit-last');b=u.Session(db,'event-later-commit-first');sessions.extend([a,b])
 def parsed_sql(e):return "insert into public.parsed_payment_events(id,receiver_user_id,allocation_status) values('%s','%s','needs_review');"%(e,UID)
 a.write('begin;'+parsed_sql(early)+"select 'EARLY_UNCOMMITTED';");a.read('EARLY_UNCOMMITTED')
 b.write('begin;'+parsed_sql(late)+"commit;select 'LATER_COMMITTED';");b.read('LATER_COMMITTED')
 later_event=next(x for x in event_list(consumer)['rows'] if x['source_id']==late)
 u.call(db,"select public.ack_receipt_monitor_event_v1('%s','%s','%s','observed','monitoring_only')"%(consumer,later_event['id'],str(uuid.uuid4())))
 a.write("commit;select 'EARLY_COMMITTED';");a.read('EARLY_COMMITTED')
 case('per-event ACK cannot skip an earlier-created transaction that commits late',lambda:check(any(x['source_id']==early for x in event_list(consumer)['rows'])))
 # An event from an aborted business transaction must disappear atomically.
 aborted=str(uuid.uuid4());psql(db,'begin;'+parsed_sql(aborted)+'rollback;')
 case('business rollback atomically removes its emitted event',lambda:check(not any(x['source_id']==aborted for x in event_list(consumer)['rows'])))
 # Two distinct requests observing one event create one terminal per-consumer row.
 target=next(x for x in event_list(consumer)['rows'] if x['source_id']==early)
 q1=str(uuid.uuid4());q2=str(uuid.uuid4())
 c=u.Session(db,'ack-first');d=u.Session(db,'ack-second');sessions.extend([c,d])
 def ack_sql(req):return "select public.ack_receipt_monitor_event_v1('%s','%s','%s','observed','monitoring_only');"%(consumer,target['id'],req)
 c.write('begin;'+u.auth()+ack_sql(q1)+"select 'ACK_FIRST_HELD';");c.read('ACK_FIRST_HELD')
 d.write('begin;'+u.auth()+ack_sql(q2)+"commit;select 'ACK_SECOND_DONE';")
 time.sleep(.15);c.write("commit;select 'ACK_FIRST_DONE';");c.read('ACK_FIRST_DONE');d.read('ACK_SECOND_DONE')
 case('concurrent observation creates one terminal row and both immutable requests',lambda:check(psql(db,"select (select count(*) from collect_hybrid.receipt_monitor_observed_events where consumer_id='%s' and event_id='%s')=1 and (select count(*) from collect_hybrid.receipt_monitor_acknowledgements where request_id in ('%s','%s'))=2;"%(consumer,target['id'],q1,q2)).stdout.strip()=='t'))
 # Gate lock is held through authorization. A concurrent pause waits, then all
 # subsequent authorization is refused; neither transaction sends anything.
 e=u.Session(db,'dispatch-boundary');f=u.Session(db,'pause-writer');sessions.extend([e,f])
 psql(db,"update public.feature_flags set enabled=true where key='hybrid_sms_notifications';")
 e.write("begin;select collect_hybrid.require_receipt_dispatch_enabled();select 'DISPATCH_GATE_HELD';");e.read('DISPATCH_GATE_HELD')
 f.write("begin;update public.feature_flags set enabled=false where key='hybrid_sms_notifications';commit;select 'PAUSE_DONE';")
 time.sleep(.15)
 case('concurrent pause cannot commit across an open dispatch authorization lock',lambda:check(psql(db,"select enabled from public.feature_flags where key='hybrid_sms_notifications';").stdout.strip()=='t'))
 e.write("commit;select 'DISPATCH_DONE';");e.read('DISPATCH_DONE');f.read('PAUSE_DONE')
 case('pause commits after prior durable boundary and blocks future authority',lambda:check(psql(db,"select collect_hybrid.require_receipt_dispatch_enabled();",False).returncode!=0))
 # Existing canonical financial serialization remains unchanged under the new
 # receipt/event triggers. Independent payments cannot lose balance increments.
 one='99710000-0000-4000-8000-000000050010';two='99710000-0000-4000-8000-000000050011'
 g=u.Session(db,'financial-post-one');h=u.Session(db,'financial-post-two');sessions.extend([g,h])
 prefix="begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
 g.write(prefix+payment_sql(one,amount=130)+"select 'FIRST_FINANCE_HELD';");g.read('FIRST_FINANCE_HELD')
 h.write(prefix+payment_sql(two,amount=170)+"commit;select 'SECOND_FINANCE_DONE';")
 time.sleep(.15);g.write("commit;select 'FIRST_FINANCE_DONE';");g.read('FIRST_FINANCE_DONE');h.read('SECOND_FINANCE_DONE')
 case('concurrent financial posts create distinct immutable receipts and events',lambda:check(psql(db,"select (select count(*) from collect_hybrid.sms_notification_outbox where payment_id in ('%s','%s') and state='queued')=2 and (select count(*) from collect_hybrid.receipt_business_events where payment_id in ('%s','%s'))=4;"%(one,two,one,two)).stdout.strip()=='t'))

if __name__=='__main__':main()
