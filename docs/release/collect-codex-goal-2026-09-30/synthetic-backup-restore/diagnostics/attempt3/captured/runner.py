#!/usr/bin/env python3
"""C34 synthetic PostgreSQL backup/restore in two task-owned offline targets.

Only the retained row-free schema153 and exact accepted scoped migrations are
loaded. No hosted Auth, Storage blobs, device journals, source rows or secrets
are read. This measures a fixture, not approved recovery objectives.
"""
import argparse,base64,datetime,hashlib,importlib.abc,importlib.util,json,os,pathlib
import stat,subprocess,sys,time,uuid

ROOT=pathlib.Path(__file__).resolve().parents[2]
HELPERS=['shadow_supervisor_uat','receipt_backlog_events_uat',
 'collect_admin_combined_upgrade_uat','collect_current_release_upgrade_uat','android_gateway_identity_uat']
NAMES=['20260930211605_android_gateway_identity.sql','20260930213000_operator_email_auth.sql',
 '20260930220527_operator_email_cutover_guard.sql','20260930230100_receipt_backlog_events.sql',
 '20260930230200_admin_receipt_overview.sql','20260930230300_admin_transaction_lifecycle.sql',
 '20261001000100_operational_exception_inbox.sql','20261001000200_admin_gateway_reads.sql',
 '20261001000300_admin_exception_reads.sql','20261001000400_receipt_supervisor_identity.sql',
 '20261001000519_safe_unstarted_receipt_cancel.sql','20261001001457_joined_operator_audit.sql',
 '20261001003338_unattended_operating_policy.sql','20261001004651_receipt_cancel_audit_actor.sql']
BASELINE=ROOT/'.cache/receipt-foundation-attempt8'
DUMP_HASH='77262947961ac1a724195ea77bdb98088cebd30caecc625ded1d4a93ccbf6d3d'
ACL_HASH='b430b8a2fb061f4422e8a53029a530a3d59f82f162507c8ae97e28541f52b577'
RELEASE=ROOT/'docs/release/collect-codex-goal-2026-09-30'
def sha(b):return hashlib.sha256(b).hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def q(v):return "'"+str(v).replace("'","''")+"'"
def uuid_new():return str(uuid.uuid4())
def write_json(p,v):p.write_text(json.dumps(v,indent=2)+'\n')

class CapturedHelpers(importlib.abc.MetaPathFinder,importlib.abc.Loader):
 def __init__(self,bodies):self.bodies=bodies
 def find_spec(self,fullname,path=None,target=None):
  if fullname in self.bodies:return importlib.util.spec_from_loader(fullname,self)
 def create_module(self,spec):return None
 def exec_module(self,module):
  body,path=self.bodies[module.__name__];module.__file__=str(path)
  exec(compile(body,str(path),'exec'),module.__dict__)

CATALOG_SQL="""
select jsonb_build_object(
 'schemas',(select jsonb_agg(jsonb_build_object('name',n.nspname,'owner',pg_get_userbyid(n.nspowner),'acl',
  (select jsonb_agg(jsonb_build_array(case when a.grantee=0 then 'PUBLIC' else pg_get_userbyid(a.grantee)end,
   pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable)order by a.grantee,a.grantor,a.privilege_type,a.is_grantable)
   from aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner)))a))order by n.nspname)
  from pg_namespace n where n.nspname not like 'pg_%'and n.nspname<>'information_schema'),
 'relations',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'kind',c.relkind,
  'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'options',c.reloptions,'acl',(select jsonb_agg(jsonb_build_array(case when a.grantee=0 then 'PUBLIC'else pg_get_userbyid(a.grantee)end,
   pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable)order by a.grantee,a.grantor,a.privilege_type,a.is_grantable)
   from aclexplode(coalesce(c.relacl,acldefault(case when c.relkind='S'then 's'::"char"else 'r'::"char"end,c.relowner)))a))
   order by n.nspname,c.relname)from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname not like 'pg_%'and n.nspname<>'information_schema'and c.relkind in('r','p','S','v','m')),
 'columns',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',a.attname,'ordinal',a.attnum,
  'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,
  'default',pg_get_expr(d.adbin,d.adrelid))order by n.nspname,c.relname,a.attnum)
  from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
  left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum where a.attnum>0 and not a.attisdropped
  and n.nspname not like 'pg_%'and n.nspname<>'information_schema'and c.relkind in('r','p','S','v','m')),
 'functions',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),
  'owner',pg_get_userbyid(p.proowner),'definition',pg_get_functiondef(p.oid),'acl',
  (select jsonb_agg(jsonb_build_array(case when a.grantee=0 then 'PUBLIC'else pg_get_userbyid(a.grantee)end,
   pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable)order by a.grantee,a.grantor,a.privilege_type,a.is_grantable)
   from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a))order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname not like 'pg_%'
  and n.nspname<>'information_schema'and p.prokind<>'a'),
 'constraints',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',x.conname,
  'definition',pg_get_constraintdef(x.oid,true),'validated',x.convalidated)order by n.nspname,c.relname,x.conname)
  from pg_constraint x join pg_class c on c.oid=x.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname not like 'pg_%'and n.nspname<>'information_schema'),
 'indexes',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',i.relname,
  'definition',pg_get_indexdef(i.oid),'owner',pg_get_userbyid(i.relowner))order by n.nspname,c.relname,i.relname)from pg_index x join pg_class i on i.oid=x.indexrelid
  join pg_class c on c.oid=x.indrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname not like 'pg_%'and n.nspname<>'information_schema'),
 'views',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'definition',pg_get_viewdef(c.oid,true))order by n.nspname,c.relname)from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not like 'pg_%'and n.nspname<>'information_schema'and c.relkind in('v','m')),
 'types',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'name',t.typname,'kind',t.typtype,'owner',pg_get_userbyid(t.typowner),'base',format_type(t.typbasetype,t.typtypmod),'not_null',t.typnotnull,'default',t.typdefault,'enum',(select jsonb_agg(e.enumlabel order by e.enumsortorder)from pg_enum e where e.enumtypid=t.oid))order by n.nspname,t.typname)from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname not like 'pg_%'and n.nspname<>'information_schema'and t.typtype in('e','d')),
 'triggers',(select jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',t.tgname,
  'definition',pg_get_triggerdef(t.oid,true),'enabled',t.tgenabled)order by n.nspname,c.relname,t.tgname)
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal and n.nspname not like 'pg_%'and n.nspname<>'information_schema'),
 'policies',(select jsonb_agg(jsonb_build_object('schema',schemaname,'relation',tablename,'name',policyname,
  'permissive',permissive,'roles',roles,'command',cmd,'using',qual,'check',with_check)order by schemaname,tablename,policyname)from pg_policies),
 'default_acl',(select jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),'schema',n.nspname,'kind',d.defaclobjtype,
  'acl',(select jsonb_agg(jsonb_build_array(case when a.grantee=0 then 'PUBLIC'else pg_get_userbyid(a.grantee)end,
  pg_get_userbyid(a.grantor),a.privilege_type,a.is_grantable)order by a.grantee,a.grantor,a.privilege_type,a.is_grantable)
  from aclexplode(d.defaclacl)a))order by pg_get_userbyid(d.defaclrole),n.nspname,d.defaclobjtype)
  from pg_default_acl d left join pg_namespace n on n.oid=d.defaclnamespace),
 'extensions',(select jsonb_agg(jsonb_build_array(e.extname,e.extversion,n.nspname,pg_get_userbyid(e.extowner))order by e.extname)
  from pg_extension e join pg_namespace n on n.oid=e.extnamespace),
 'roles',(select jsonb_agg(jsonb_build_array(rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,rolconfig)
  order by rolname)from pg_roles),
 'database',(select jsonb_build_object('encoding',pg_encoding_to_char(encoding),'collate',datcollate,'ctype',datctype,
  'owner',pg_get_userbyid(datdba))from pg_database where datname=current_database())
);
"""

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--report-dir',required=True)
 args=parser.parse_args();out=pathlib.Path(args.report_dir).resolve();assert not out.exists();out.mkdir(parents=True)
 evidence={'kind':'C34_synthetic_offline_postgresql_backup_restore_schema153_subset','started_at':utc(),
  'production_written':False,'shared_database_written':False,'private_source_rows_read':False,
  'hosted_auth_storage_configuration_read':False,'provider_or_sender_called':False,'real_keys_created':False,
  'approved_rpo_rto_claimed':False,'full_current_or_hosted_acceptance':False,'cases':[]}
 def save():write_json(out/'result.json',evidence)
 def case(name,condition=True,detail=None):
  assert condition,name;evidence['cases'].append({'name':name,'status':'pass','detail':detail});save();print('PASS '+name,flush=True)
 own=pathlib.Path(__file__).read_bytes();captured=out/'captured';captured.mkdir();(captured/'runner.py').write_bytes(own)
 helpers={name:((ROOT/'scripts/tests'/(name+'.py')).read_bytes(),ROOT/'scripts/tests'/(name+'.py'))for name in HELPERS}
 for name,(body,path)in helpers.items():(captured/path.name).write_bytes(body)
 bodies={ROOT/'supabase/migrations'/name:(ROOT/'supabase/migrations'/name).read_bytes()for name in NAMES}
 for p,b in bodies.items():(captured/p.name).write_bytes(b)
 baseline=(BASELINE/'schema-only.sql').read_bytes();acl=(BASELINE/'api-acl.sql').read_bytes()
 assert sha(baseline)==DUMP_HASH and sha(acl)==ACL_HASH
 (captured/'schema153-row-free.sql').write_bytes(baseline);(captured/'schema153-api-acl.sql').write_bytes(acl)
 accepted=json.loads((RELEASE/'unattended-operating-policy/publication-binding.json').read_text())['source_sha256']
 accepted.update(json.loads((RELEASE/'safe-receipt-audit-attribution/publication-binding.json').read_text())['source_sha256'])
 audit=json.loads((RELEASE/'joined-operator-audit/publication.json').read_text());accepted[audit['published_path']]=audit['sha256']
 accepted.update(json.loads((RELEASE/'gateway-admin/backend-uat/result.json').read_text())['selected_source_sha256'])
 for p,b in bodies.items():assert sha(b)==accepted[str(p.relative_to(ROOT))]
 evidence['captured_sha256']={str(p.relative_to(ROOT)):sha(b)for p,b in bodies.items()}
 evidence['executed_helpers_sha256']={str(p.relative_to(ROOT)):sha(b)for b,p in helpers.values()}
 evidence['runner_sha256']=sha(own);evidence['baseline']={'count':153,'row_free_sha256':DUMP_HASH,'acl_sha256':ACL_HASH,'owners_previously_normalized':True}
 finder=CapturedHelpers(helpers);sys.meta_path.insert(0,finder)
 import collect_admin_combined_upgrade_uat as fixture
 import collect_current_release_upgrade_uat as private
 import android_gateway_identity_uat as keys
 u,f=fixture.u,fixture.foundation
 targets=[];databases=[];src_db='collect_c34_source_'+uuid.uuid4().hex[:12];dst_db='collect_c34_restore_'+uuid.uuid4().hex[:12]
 def use(target):u.CONTAINER=target.name;u.SQL_LOG=out/(target.phase+'-queries.log');f.RAW_QUERY_LOG=out/(target.phase+'-queries.sql')
 def sql(target,db,text,check=True):use(target);return u.psql(db,"set timezone='UTC';set search_path=public,extensions,auth;"+text,check)
 def value(target,db,text):return json.loads(sql(target,db,text).stdout.strip().splitlines()[-1])
 def owner(target,db,text,uid=None,sid=None):use(target);return u.call(db,text,uid or u.UID,sid or u.SID)
 def service(target,db,text):return value(target,db,f.service(text))
 def snapshot(target,db,prefix):
  catalog=value(target,db,CATALOG_SQL);write_json(out/(prefix+'-catalog.json'),catalog)
  names=value(target,db,"select coalesce(jsonb_agg(jsonb_build_array(n.nspname,c.relname,c.relkind)order by n.nspname,c.relname),'[]')from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname not like 'pg_%'and n.nspname<>'information_schema'and c.relkind in('r','p','S');")
  rows={};sequences={};digests={}
  for schema,name,kind in names:
   table='"'+schema.replace('"','""')+'"."'+name.replace('"','""')+'"';key=schema+'.'+name
   if kind=='S':sequences[key]=value(target,db,"select jsonb_build_object('last_value',s.last_value,'is_called',s.is_called)from "+table+' s;');continue
   data=value(target,db,"select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text collate \"C\"),'[]')from "+table+' t;')
   rows[key]=data;digests[key]={'rows':len(data),'sha256':sha(json.dumps(data,sort_keys=True,separators=(',',':')).encode())}
  write_json(out/(prefix+'-rows.json'),rows);write_json(out/(prefix+'-sequences.json'),sequences);write_json(out/(prefix+'-projection.json'),digests)
  return {'catalog':catalog,'rows':rows,'sequences':sequences,'projection':digests}
 try:
  source=private.Target(out,'c34_source',evidence.setdefault('source_target',{}));targets.append(source);source.__enter__();use(source)
  sql(source,'postgres','create database '+src_db+' template template0;');databases.append((source,src_db))
  restored=sql(source,src_db,'create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+baseline.decode()+acl.decode(),False)
  (out/'baseline-load.log').write_text(restored.stdout+restored.stderr);assert restored.returncode==0,restored.stderr[-3000:]
  f.seed(src_db)
  sql(source,src_db,"insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('audit.read','Synthetic'),('admin_users.manage','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select %s,name from public.admin_permissions on conflict do nothing;insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values(%s,%s,'+250788971001',repeat('a',64),'mtn_momo');insert into collect_security.shadow_supervisor_lease(id)values(true)on conflict do nothing;"%(q(f.ROLE),q(f.GROUP),q(u.UID)))
  primary_pid='99880000-0000-4000-8000-000000050001';queue_pid='99880000-0000-4000-8000-000000050002'
  sql(source,src_db,"update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+f.service(f.payment_sql(primary_pid,amount=50))+"update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
  before_install=f.business_fingerprint(src_db)
  for p,b in bodies.items():
   r=sql(source,src_db,b.decode(),False);(out/(p.stem+'.install.log')).write_text(r.stdout+r.stderr);assert r.returncode==0,r.stderr[-3000:]
   case(p.name+' preserves existing synthetic financial primary receipt',f.business_fingerprint(src_db)==before_install)
  sql(source,src_db,"insert into public.admin_role_permissions(role_id,permission_name)select %s,name from public.admin_permissions on conflict do nothing;"%q(f.ROLE))
  for uid,email in [(u.UID,'restore-owner@collect.example'),(u.OTHER,'restore-other@collect.example')]:
   sql(source,src_db,"update auth.users set email=%s,email_confirmed_at=clock_timestamp()where id=%s;insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values(%s,%s,clock_timestamp()-interval '2 minutes','Synthetic recovery owner');"%tuple(map(q,[email,uid,uid,email])))
  owner(source,src_db,"select public.admin_set_operator_email_mode_v1('Synthetic offline restore email mode')")
  sql(source,src_db,f.service(f.payment_sql(queue_pid,amount=100)));job=value(source,src_db,'select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id='+q(primary_pid)+';')['id']
  cancel_request=uuid_new();cancel_query='select public.admin_cancel_unstarted_receipt_v1(%s,%s,1,\'operator_cancelled\')'%(q(cancel_request),q(job))
  cancelled=owner(source,src_db,cancel_query);write_json(out/'source-cancel-receipt.json',cancelled)
  run=owner(source,src_db,'select public.begin_collect_shadow_run_v1('+q(uuid_new())+');')['run']
  for action in ['sample','finish']:owner(source,src_db,'select public.%s_collect_shadow_run_v1(%s,%d);'%(action,q(run['run_id']),run['fence_version']))
  device_key=bytes.fromhex(keys.PREFIX+keys.POINTS[0]);device_spki=base64.b64encode(device_key).decode();device_hash=sha(device_key);device_req=uuid_new();installation=uuid_new();cert='c'*64
  device_query='select public.admin_enroll_gateway_device_v1(%s,%s,%s,%s,%s);'%tuple(map(q,[device_req,installation,device_spki,device_hash,cert]))
  enrolled=owner(source,src_db,device_query);device=enrolled['device_id'];health_request=uuid_new()
  payload="jsonb_build_object('sms_permission',false,'network','offline','telephony','unknown','sim_selected',false,'sim_revision_sha256',null,'local_pause',true,'reported_at',collect_gateway.utc(clock_timestamp()))"
  heartbeat=service(source,src_db,'select public.gateway_heartbeat_v1(%s,%s,repeat(\'7\',64),%s);'%(q(device),q(health_request),payload));write_json(out/'source-gateway-heartbeat.json',heartbeat)
  owner(source,src_db,'select public.admin_activate_gateway_device_v1(%s,%s,%s,%s);'%tuple(map(q,[device,uuid_new(),device_hash,cert])))
  owner(source,src_db,'select public.admin_revoke_gateway_device_v1(%s,%s,%s,%s);'%tuple(map(q,[device,uuid_new(),device_hash,cert])))
  public_key=bytes.fromhex(keys.PREFIX+keys.POINTS[1]);spki=base64.b64encode(public_key).decode();key_hash=sha(public_key);principal_req=uuid_new();expiry=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=1)).isoformat()
  principal_query='select public.admin_enroll_receipt_supervisor_v1(%s,%s,%s,%s);'%tuple(map(q,[principal_req,spki,key_hash,expiry]))
  principal_receipt=owner(source,src_db,principal_query);principal=principal_receipt['principal_id']
  service(source,src_db,'select public.receipt_supervisor_observe_v1(%s,%s,%s,repeat(\'8\',64),clock_timestamp(),\'prove_key\');'%tuple(map(q,[principal,uuid_new(),key_hash])))
  owner(source,src_db,'select public.admin_activate_receipt_supervisor_v1(%s,%s,%s);'%tuple(map(q,[principal,uuid_new(),key_hash])))
  supervisor_health_req=uuid_new();supervisor_health=service(source,src_db,'select public.receipt_supervisor_observe_v1(%s,%s,%s,repeat(\'9\',64),clock_timestamp(),\'shadow_health\');'%tuple(map(q,[principal,supervisor_health_req,key_hash])));write_json(out/'source-supervisor-health.json',supervisor_health)
  policy_req=uuid_new();policy_query='select public.admin_configure_unattended_operating_policy_v1(%s,1,\'Shadow\',false,\'operator_reviewed_configuration\');'%q(policy_req)
  policy_receipt=owner(source,src_db,policy_query);write_json(out/'source-policy-receipt.json',policy_receipt)
  owner(source,src_db,'select public.admin_configure_unattended_operating_policy_v1(%s,2,\'Shadow\',false,\'operator_reviewed_configuration\');'%q(uuid_new()))
  owner(source,src_db,'select public.admin_configure_unattended_operating_policy_v1(%s,2,\'Paused\',true,\'operator_emergency_stop\');'%q(uuid_new()))
  raw=uuid_new();sql(source,src_db,"insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values(%s,%s,%s,'M-Money','Synthetic recovery failed-parser record',repeat('e',64),repeat('a',64),'failed');"%tuple(map(q,[raw,f.GROUP,u.UID])))
  exception=value(source,src_db,'select jsonb_build_object(\'id\',id,\'revision\',revision)from collect_ops.exceptions where source_kind=\'raw_sms\'and source_id='+q(raw)+' and active;')
  exception_req=uuid_new();exception_receipt=owner(source,src_db,'select public.admin_act_operational_exception_v1(%s,%s,%d,\'acknowledge\',\'review_started\');'%(q(exception_req),q(exception['id']),exception['revision']))
  consumer=owner(source,src_db,'select public.register_receipt_monitor_consumer_v1();')['consumer_id']
  event=value(source,src_db,'select to_jsonb(e)from collect_hybrid.receipt_business_events e order by created_at,id limit 1;')['id']
  owner(source,src_db,'select public.ack_receipt_monitor_event_v1(%s,%s,%s,\'observed\',\'monitoring_only\');'%tuple(map(q,[consumer,event,uuid_new()])))
  source_snapshot=snapshot(source,src_db,'source')
  important=['public.payments','collect_hybrid.momo_journal_entries','collect_hybrid.momo_journal_lines','collect_hybrid.momo_balance_snapshots',
   'collect_hybrid.sms_notification_outbox','auth.users','auth.sessions','collect_admin_access.email_approvals','public.admin_user_roles',
   'collect_gateway.devices','collect_gateway.admin_requests','collect_gateway.requests','collect_gateway.health_observations',
   'collect_supervisor.identities','collect_supervisor.owner_requests','collect_supervisor.requests','collect_receipt_actions.cancellations',
   'collect_automation.operating_policy','collect_automation.policy_requests','collect_operator_audit.shadow_events','public.audit_logs',
   'collect_ops.exception_actions','collect_hybrid.receipt_monitor_acknowledgements','public.feature_flags']
  case('critical recovery projections are actually nonempty',all(source_snapshot['projection'][t]['rows']>0 for t in important),{t:source_snapshot['projection'][t]['rows']for t in important})
  case('the dump contains only synthetic Auth mocks and no Storage object/blob fixture',len(source_snapshot['rows']['auth.users'])==2 and source_snapshot['rows'].get('storage.objects',[])==[])
  dump_file=out/'synthetic-postgresql.custom.dump';fd=os.open(dump_file,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
  start=time.monotonic()
  with os.fdopen(fd,'wb')as stream:r=subprocess.run([private.DOCKER,'exec',source.name,'pg_dump','--format=custom','--username=postgres','--dbname='+src_db],stdout=stream,stderr=subprocess.PIPE,timeout=90)
  dump_seconds=time.monotonic()-start;(out/'pg-dump.stderr.log').write_bytes(r.stderr);assert r.returncode==0,r.stderr[-3000:]
  backup=dump_file.read_bytes();assert backup[:5]==b'PGDMP'
  mode=stat.S_IMODE(dump_file.stat().st_mode);case('real custom dump is nonempty mode0600 with owners and ACLs retained',mode==0o600 and len(backup)>0)
  listing=subprocess.run([private.DOCKER,'exec','-i',source.name,'pg_restore','--list'],input=backup,capture_output=True,timeout=30);assert listing.returncode==0,listing.stderr[-3000:];(out/'pg-restore-toc.list').write_bytes(listing.stdout)
  evidence['backup']={'sha256':sha(backup),'bytes':len(backup),'mode':oct(mode),'format':'PostgreSQL custom archive','dump_seconds':dump_seconds,'dump_options':['--format=custom','--username=postgres','--dbname=<synthetic-source>'],'owner_and_acl_omission_flags_used':False}
  destination=private.Target(out,'c34_restored',evidence.setdefault('restore_target',{}));targets.append(destination);destination.__enter__()
  sql(destination,'postgres','create database '+dst_db+' template template0;');databases.append((destination,dst_db))
  start=time.monotonic();r=subprocess.run([private.DOCKER,'exec','-i',destination.name,'pg_restore','--exit-on-error','--username=postgres','--dbname='+dst_db],input=backup,capture_output=True,timeout=90);restore_seconds=time.monotonic()-start
  (out/'pg-restore.stdout.log').write_bytes(r.stdout);(out/'pg-restore.stderr.log').write_bytes(r.stderr);assert r.returncode==0,r.stderr[-4000:]
  evidence['backup']['restore_seconds']=restore_seconds;evidence['backup']['restore_options']=['--exit-on-error','--username=postgres','--dbname=<empty-synthetic-destination>']
  restored_snapshot=snapshot(destination,dst_db,'restored')
  for category in source_snapshot['catalog']:case('restored '+category+' owners authority and definitions match exactly',source_snapshot['catalog'][category]==restored_snapshot['catalog'][category])
  case('all table rows restore exactly with original identities and state',source_snapshot['rows']==restored_snapshot['rows'],{'table_count':len(source_snapshot['rows'])})
  case('all sequence positions restore exactly',source_snapshot['sequences']==restored_snapshot['sequences'],{'sequence_count':len(source_snapshot['sequences'])})
  for table in important:case(table+' recovery retains exact nonempty row projections',source_snapshot['projection'][table]==restored_snapshot['projection'][table])
  queue=value(destination,dst_db,'select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id='+q(queue_pid)+';')
  case('paused dispatch preserves the queued primary receipt and cancelled identity separately',queue['state']=='queued'and value(destination,dst_db,'select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+q(job)+';')['state']=='suppressed')
  case('financial journals remain canonical two-line balanced pairs',value(destination,dst_db,"select to_jsonb(not exists(select 1 from collect_hybrid.momo_journal_entries e left join collect_hybrid.momo_journal_lines l on l.journal_entry_id=e.id group by e.id,e.amount_rwf having count(*)<>2 or sum(case when l.direction='debit'then l.amount_rwf else -l.amount_rwf end)<>0 or min(l.amount_rwf)<>e.amount_rwf or max(l.amount_rwf)<>e.amount_rwf));"))
  def error(name,query,state='42501',reason=None,role='authenticated',uid=None,sid=None,mutation=''):
   claims=u.auth(uid or u.UID,sid or u.SID)if role=='authenticated'else 'set local role '+role+';'
   r=sql(destination,dst_db,'begin;'+mutation+claims+query+';rollback;',False)
   case(name,r.returncode!=0 and state+':'in r.stderr and(reason is None or reason in r.stderr),{'sqlstate':state,'reason':reason})
  restored_cancel=owner(destination,dst_db,cancel_query);case('restored original cancellation UUID replay is identical historical receipt',restored_cancel==cancelled)
  restored_policy=owner(destination,dst_db,policy_query);case('restored original policy UUID replay does not grant a new action',restored_policy==policy_receipt)
  case('restored original gateway enrollment UUID retains its historical identity',owner(destination,dst_db,device_query)==enrolled)
  case('restored original supervisor enrollment UUID retains its historical identity',owner(destination,dst_db,principal_query)==principal_receipt)
  cancel_lookup=owner(destination,dst_db,'select public.admin_get_unstarted_receipt_action_v1('+q(cancel_request)+');');write_json(out/'restored-cancel-lookup.json',cancel_lookup);case('restored cancellation request lookup binds the original UUID and immutable receipt',cancel_lookup['receipt']==cancelled)
  policy_lookup=owner(destination,dst_db,'select public.admin_get_unattended_policy_request_v1('+q(policy_req)+');');write_json(out/'restored-policy-lookup.json',policy_lookup);case('restored policy request lookup binds the original UUID and immutable receipt',policy_lookup['receipt']==policy_receipt)
  gateway_lookup=owner(destination,dst_db,'select public.admin_get_gateway_owner_request_v1('+q(device_req)+');');write_json(out/'restored-gateway-owner-lookup.json',gateway_lookup);case('restored owner gateway lookup retains original enrollment receipt',gateway_lookup['receipt']==enrolled)
  reconcile=service(destination,dst_db,'select public.gateway_reconcile_v1(%s,%s,repeat(\'6\',64),jsonb_build_object(\'target_request_id\',%s::text));'%tuple(map(q,[device,uuid_new(),health_request])));write_json(out/'restored-gateway-reconcile.json',reconcile);case('revoked gateway can reconcile original health evidence without resuming',reconcile['recorded_result']==heartbeat)
  reconcile=service(destination,dst_db,'select public.receipt_supervisor_reconcile_v1(%s,%s,%s,repeat(\'6\',64),clock_timestamp(),%s);'%tuple(map(q,[principal,uuid_new(),key_hash,supervisor_health_req])));write_json(out/'restored-supervisor-reconcile.json',reconcile);case('restored active fixed Shadow principal reconciles unchanged original observation',reconcile['receipt']==supervisor_health)
  for kind,entity,count in [('receipt',job,1),('shadow_run',run['run_id'],3),('gateway_device',device,3),('supervisor_identity',principal,2),('exception',exception['id'],1)]:
   result=owner(destination,dst_db,'select public.admin_get_operator_entity_audit_v1(%s,%s);'%(q(kind),q(entity)));write_json(out/('restored-audit-'+kind+'.json'),result);case('restored '+kind+' joined audit reads actual retained history',result['status']=='available'and len(result['rows'])==count)
  current=owner(destination,dst_db,'select public.admin_get_unattended_operating_policy_v1();');write_json(out/'restored-policy-current.json',current);case('restored emergency-stop preference stays Paused and execution authority unavailable',current['configured_mode']=='Paused'and current['emergency_stop']and not current['execution']['unattended_dispatch_available'])
  for role in ['anon','service_role']:
   error(role+' cannot cancel with a restored request identity',cancel_query,role=role)
   error(role+' cannot configure restored policy',policy_query,role=role)
   error(role+' cannot read joined owner audit','select public.admin_get_operator_entity_audit_v1(\'receipt\','+q(job)+')',role=role)
   error(role+' cannot directly read private cancellation history','select *from collect_receipt_actions.cancellations',role=role)
  error('another owner cannot reuse restored original cancellation UUID',cancel_query,'22023','receipt_action_request_conflict',uid=u.OTHER,sid=u.OTHERSID)
  error('another owner cannot reuse restored original policy UUID',policy_query,'22023','operating_policy_request_conflict',uid=u.OTHER,sid=u.OTHERSID)
  error('changed input cannot reuse restored policy UUID',policy_query.replace("'Shadow'","'Dry-run'"),'22023','operating_policy_request_conflict')
  error('new UUID cannot turn a cancelled receipt into a new cancellation',cancel_query.replace(cancel_request,uuid_new()).replace(',1,',',2,'),'55000','receipt_not_cancellable')
  error('restored role does not grant Live unattended dispatch','select public.admin_configure_unattended_operating_policy_v1(%s,3,\'Live\',false,\'operator_reviewed_configuration\')'%q(uuid_new()),'55000','OPERATING_POLICY_LIVE_AUTHORITY_PENDING')
  for name,mutation in [('expired session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id="+q(u.SID)+';'),('revoked email approval','update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id='+q(u.UID)+';'),('unverified email','update auth.users set email_confirmed_at=null where id='+q(u.UID)+';')]:
   error('restored authority refuses '+name,policy_query,mutation=mutation)
  error('restored authenticated role cannot call supervisor trusted service','select public.receipt_supervisor_key_v1('+q(principal)+')')
  error('restored authenticated role cannot read gateway trusted service key','select public.gateway_device_key_v1('+q(device)+')')
  immutable_reasons={'collect_receipt_actions.cancellations':'receipt_action_evidence_retained','collect_automation.policy_requests':'operating_policy_evidence_retained','collect_operator_audit.shadow_events':'operator_audit_evidence_retained','collect_gateway.admin_requests':'gateway_evidence_immutable','collect_gateway.requests':'gateway_evidence_immutable','collect_supervisor.owner_requests':'supervisor_evidence_immutable','collect_supervisor.requests':'supervisor_evidence_immutable','collect_ops.exception_actions':'operational_exception_evidence_immutable','collect_hybrid.receipt_monitor_acknowledgements':'receipt_event_evidence_immutable'}
  for table in ['collect_receipt_actions.cancellations','collect_automation.policy_requests','collect_operator_audit.shadow_events','collect_gateway.admin_requests','collect_gateway.requests','collect_supervisor.owner_requests','collect_supervisor.requests','collect_ops.exception_actions','collect_hybrid.receipt_monitor_acknowledgements']:
   for verb in ['update','delete']:
    query=('update '+table+' set '+('request_id=request_id'if table not in ['collect_operator_audit.shadow_events','collect_hybrid.receipt_monitor_acknowledgements']else 'event_id=event_id')+';'if verb=='update'else'delete from '+table+';')
    r=sql(destination,dst_db,'begin;'+query+'rollback;',False);case('restored '+table+' retains '+verb+' immutability',r.returncode!=0 and '55000:'in r.stderr and immutable_reasons[table]in r.stderr)
  r=sql(destination,dst_db,'begin;update collect_hybrid.sms_notification_outbox set message_body=message_body||\' changed\'where id='+q(job)+';rollback;',False);case('restored immutable primary payload cannot be rewritten',r.returncode!=0 and 'immutable'in r.stderr)
  r=sql(destination,dst_db,'begin;insert into collect_hybrid.sms_notification_outbox select(jsonb_populate_record(null::collect_hybrid.sms_notification_outbox,to_jsonb(o)||jsonb_build_object(\'id\',gen_random_uuid()))).*from collect_hybrid.sms_notification_outbox o where id='+q(job)+';rollback;',False);case('restored lifetime primary receipt identity remains unique',r.returncode!=0 and '23505:'in r.stderr)
  final_snapshot=snapshot(destination,dst_db,'restored-after-verification')
  case('all post-restore replay/read/refusal probes leave every row unchanged',final_snapshot['rows']==restored_snapshot['rows'])
  case('post-restore probes preserve sequence positions and all authority definitions',final_snapshot['sequences']==restored_snapshot['sequences']and final_snapshot['catalog']==restored_snapshot['catalog'])
  evidence['source_drift']=[str(p.relative_to(ROOT))for p,b in bodies.items()if p.read_bytes()!=b]
  evidence['helper_drift']=[str(p.relative_to(ROOT))for b,p in helpers.values()if p.read_bytes()!=b]
  case('captured SQL and executed auxiliary helper bytes stay unchanged',not evidence['source_drift']and not evidence['helper_drift'])
  case('executed runner bytes stay unchanged',pathlib.Path(__file__).read_bytes()==own)
  evidence['status']='pass'
 except BaseException as error:evidence['status']='failed';evidence['error_type']=type(error).__name__;evidence['error']=str(error);save();raise
 finally:
  for target,db in reversed(databases):
   try:evidence.setdefault('database_cleanup',{})[db]=sql(target,'postgres','drop database '+db+' with(force);',False).returncode==0
   except Exception as error:evidence.setdefault('cleanup_errors',[]).append(str(error))
  for target in reversed(targets):
   try:target.close()
   except Exception as error:evidence.setdefault('cleanup_errors',[]).append(str(error))
  u.SQL_LOG=None;f.RAW_QUERY_LOG=None;sys.meta_path.remove(finder)
  evidence['case_count']=len(evidence['cases']);evidence['completed_at']=utc();save()

if __name__=='__main__':main()
