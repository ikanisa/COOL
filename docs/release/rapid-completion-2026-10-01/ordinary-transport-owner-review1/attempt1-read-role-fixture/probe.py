#!/usr/bin/env python3
"""Task-owned, network-none owner/index/column-ACL proposal proof only."""
from pathlib import Path
import datetime,hashlib,importlib.util,json,re

ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT=Path(__file__).resolve().parent
helper=OUT/'captured-source/scripts/tests/collect_current_release_upgrade_uat.py'
spec=importlib.util.spec_from_file_location('captured_ordinary_target',helper)
replay=importlib.util.module_from_spec(spec);spec.loader.exec_module(replay)
replay.ROOT=ROOT
result={'status':'running','scope':'Only proposed ordinary-owner index preflight, exact type/index/column ACL validator, and original bounded sample function. Not full16:00migration/185replay or auth/server acceptance.',
 'shared_database_written':False,'hosted_called':False,'provider_called':False,'source_files_written':False,'cases':[],
 'retained_original_denial':'docs/release/rapid-completion-2026-10-01/platform-owned-index-preflight1/result.json',
 'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
phase=result['owned_target']={}
def save(): (OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n')
def case(name,value=True):
 if not value: raise AssertionError(name)
 result['cases'].append({'name':name,'status':'pass'});save();print('PASS '+name,flush=True)
def read(name):return(OUT/name).read_text()
idx=read('candidate-index-preflight.sql');validator=read('candidate-validator.sql');sample=read('exact-source-sample.sql')
source=read('captured-source/supabase/migrations/20261001000100_operational_exception_inbox.sql')
utc=re.search(r'create function collect_ops.utc\(p_time timestamptz\)[\s\S]*?\$\$;',source).group()
target=replay.Target(OUT,'owned_probe',phase)
try:
 save()
 with target:
  target.sql('create schema if not exists extensions;create extension if not exists pg_net with schema extensions;',user='supabase_admin',label='platform-owner pg_net prerequisite')
  result['platform']=target.json("select jsonb_build_object('extension_owner',pg_get_userbyid(e.extowner),'schema',n.nspname,'version',e.extversion,'response_owner',(select pg_get_userbyid(relowner)from pg_class where oid='net._http_response'::regclass))from pg_extension e join pg_namespace n on n.oid=e.extnamespace where extname='pg_net';")
  case('actual retained pg_net0.20.0 and response table remain platform owned',result['platform']=={'extension_owner':'supabase_admin','schema':'extensions','version':'0.20.0','response_owner':'supabase_admin'})
  target.sql('alter role postgres nosuperuser;',user='supabase_admin',label='ordinary application authority before any candidate DDL')
  result['ordinary']=target.json("select jsonb_build_object('current_user',current_user,'superuser',rolsuper,'owns_response',pg_has_role(current_user,(select relowner from pg_class where oid='net._http_response'::regclass),'USAGE'))from pg_roles where rolname=current_user;")
  case('candidate installer is postgres NOSUPERUSER without response ownership',result['ordinary']=={'current_user':'postgres','superuser':False,'owns_response':False})
  target.sql('create schema collect_ops;'+utc,label='ordinary-owned diagnostic schema and exact canonical UTC function')
  missing=target.sql(idx,check=False,label='missing platform index ordinary candidate denial')
  result['missing_index_error']={'exit_code':missing.returncode,'stderr':missing.stderr}
  case('missing platform index refuses with55000 and never escalates installer',missing.returncode!=0 and '55000' in missing.stderr and 'receipt_transport_platform_index_prerequisite' in missing.stderr)
  target.sql('create index collect_receipt_http_response_id on net._http_response(id);',user='supabase_admin',label='declared platform-owner index provision only')
  case('ordinary candidate accepts existing compatible index without CREATE INDEX owner failure',target.sql(idx,check=False,label='ordinary existing index branch').returncode==0)
  target.sql(validator.split('do $transport_read_prerequisite$')[0],label='ordinary-owned proposed strict definer validator')
  result['initial_read_privileges']=target.json("select jsonb_build_object('schema_usage',has_schema_privilege('postgres','net','USAGE'),'response_table_select',has_table_privilege('postgres','net._http_response','SELECT'),'queue_table_select',has_table_privilege('postgres','net.http_request_queue','SELECT'),'headers_select',has_column_privilege('postgres','net._http_response','headers','SELECT'),'queue_body_select',has_column_privilege('postgres','net.http_request_queue','body','SELECT'));")
  # Restrictive synthetic platform profile. These revokes are fixture setup,
  # never part of the proposed migration/platform prerequisite patch.
  target.sql('revoke all on net._http_response,net.http_request_queue from public,anon,authenticated,service_role,postgres;',user='supabase_admin',label='clone-only restrictive table ACL fixture')
  case('strict validator rejects absent required read privileges',target.scalar('select collect_ops.receipt_transport_schema_valid();')=='f')
  denied=target.sql(validator.split('do $transport_read_prerequisite$')[1].join(['do $transport_read_prerequisite$','']),check=False,label='ordinary read prerequisite rejection')
  case('ordinary migration preflight refuses missing read ACL with55000',denied.returncode!=0 and '55000' in denied.stderr)
  target.sql(read('proposed-platform-prerequisites.sql'),user='supabase_admin',label='exact owner-declared index usage and seven column SELECT prerequisites')
  case('strict type index and actual definer read privilege validation passes',target.scalar('select collect_ops.receipt_transport_schema_valid();')=='t')
  case('proposed ordinary validator preflight now passes',target.sql(validator.split('do $transport_read_prerequisite$')[1].join(['do $transport_read_prerequisite$','']),check=False,label='ordinary satisfied read prerequisite').returncode==0)
  result['minimal_acl']=target.json("select jsonb_build_object('response_table_select',has_table_privilege('postgres','net._http_response','SELECT'),'queue_table_select',has_table_privilege('postgres','net.http_request_queue','SELECT'),'headers_select',has_column_privilege('postgres','net._http_response','headers','SELECT'),'queue_body_select',has_column_privilege('postgres','net.http_request_queue','body','SELECT'),'response_dml',has_table_privilege('postgres','net._http_response','INSERT,UPDATE,DELETE'),'queue_dml',has_table_privilege('postgres','net.http_request_queue','INSERT,UPDATE,DELETE'),'client_column_select',exists(select 1 from(values('anon'),('authenticated'),('service_role'))r(role_name)where has_any_column_privilege(r.role_name,'net._http_response','SELECT')or has_any_column_privilege(r.role_name,'net.http_request_queue','SELECT')));")
  case('column-only proposal adds no table SELECT raw headers queue body DML or client reads',all(v is False for v in result['minimal_acl'].values()))
  target.sql(sample+'revoke all on function collect_ops.receipt_transport_sample(bigint,uuid),collect_ops.receipt_transport_schema_valid()from public,anon,authenticated,service_role;',label='exact source bounded sampler and original private execution restriction')
  result['definer_owner']=target.json("select jsonb_build_object('owner',pg_get_userbyid(proowner),'definer',prosecdef,'search_path',proconfig)from pg_proc where oid='collect_ops.receipt_transport_sample(bigint,uuid)'::regprocedure;")
  case('bounded sampler runs as ordinary postgres definer with empty search path',result['definer_owner']=={'owner':'postgres','definer':True,'search_path':['search_path=""']})
  empty=target.json("select collect_ops.receipt_transport_sample(94160001,'94160000-0000-4000-8000-000000000001');")
  case('actual empty sample reads queue.id without requiring whole queue SELECT',empty['outcome']=='RESPONSE_UNOBSERVED'and empty['response_rows_observed']==0)
  target.sql("insert into net._http_response(id,status_code,content,timed_out,error_msg,created)values(94160001,403,'{\"error\":\"WORKER_AUTH_REQUIRED\"}',false,null,clock_timestamp());",user='supabase_admin',label='clone-only synthetic ephemeral response; no HTTP call or queue insert')
  result['bounded_sample']=target.json("select collect_ops.receipt_transport_sample(94160001,'94160000-0000-4000-8000-000000000001');")
  case('actual original sampler consumes six permitted response columns and emits bounded metadata',result['bounded_sample']['outcome']=='AUTH_REFUSED'and result['bounded_sample']['response_rows_observed']==1 and set(result['bounded_sample'])=={'outcome','transport_terminal','http_status','worker_error_code','response_rows_observed','response_at'})
  target.sql("insert into net._http_response(id,status_code,content,timed_out,error_msg,created)values(94160001,200,'{}',false,null,clock_timestamp());",user='supabase_admin',label='clone-only duplicate response evidence; no enqueue')
  duplicate=target.json("select collect_ops.receipt_transport_sample(94160001,'94160000-0000-4000-8000-000000000001');")
  case('required nonunique index preserves duplicate conflict detection',duplicate['outcome']=='RESPONSE_CONFLICT'and duplicate['response_rows_observed']==2)
  for name,definition in [('wrong-column','status_code'),('partial','id)where id>0--'),('expression','(id+1)')]:
   # The partial spelling closes its CREATE INDEX parenthesis intentionally.
   sql='create index collect_receipt_http_response_id on net._http_response('+definition+');'
   if name=='partial':sql='create index collect_receipt_http_response_id on net._http_response(id)where id>0;'
   target.sql('drop index net.collect_receipt_http_response_id;'+sql,user='supabase_admin',label='clone-only '+name+' index negative control')
   case('strict validator rejects '+name+' index',target.scalar('select collect_ops.receipt_transport_schema_valid();')=='f')
   refused=target.sql(idx+validator.split('do $transport_read_prerequisite$')[1].join(['do $transport_read_prerequisite$','']),check=False,label='ordinary '+name+' prerequisite refusal')
   case('ordinary preflight refuses '+name+' without altering platform index',refused.returncode!=0 and '55000' in refused.stderr and 'receipt_transport_platform_read_prerequisite' in refused.stderr)
   target.sql('drop index net.collect_receipt_http_response_id;create index collect_receipt_http_response_id on net._http_response(id);',user='supabase_admin',label='restore own compatible platform index')
  for relation,column in [('net._http_response','content'),('net.http_request_queue','id')]:
   target.sql(f'revoke select({column})on {relation}from postgres;',user='supabase_admin',label='clone-only individual required column ACL refusal')
   case('strict validator detects absent '+relation+'.'+column+' SELECT',target.scalar('select collect_ops.receipt_transport_schema_valid();')=='f')
   sampled=target.sql("select collect_ops.receipt_transport_sample(94160002,'94160000-0000-4000-8000-000000000001');",check=False,label='actual missing column sampler rejection')
   case('actual definer cannot bypass missing '+relation+'.'+column+' SELECT',sampled.returncode!=0 and '42501' in sampled.stderr)
   target.sql(f'grant select({column})on {relation}to postgres;',user='supabase_admin',label='restore own exact column prerequisite')
  case('all final prerequisite checks restore to valid and installer stays NOSUPERUSER',target.scalar("select collect_ops.receipt_transport_schema_valid()and not(select rolsuper from pg_roles where rolname=current_user);")=='t')
  result['final_guard']=target.json("select jsonb_build_object('net',current_setting('pg_net.batch_size'),'cron',current_setting('cron.launch_active_jobs'),'queue_rows',(select count(id)from net.http_request_queue));")
  case('network dispatch and scheduler stay disabled with zero queued requests',result['final_guard']=={'net':'0','cron':'off','queue_rows':0})
 result['status']='pass'
except Exception as exc:
 result['status']='failed';result['failure']=str(exc);save();raise
finally:
 target.close()
 result['owned_container_removed']=phase.get('task_container_removed')is True
 original=json.loads((OUT/'source-before.json').read_text())
 result['source_drift']=[name for name,digest in original.items()if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
 result['migration_source_unchanged']='supabase/migrations/20261001160000_receipt_worker_transport_health.sql'not in result['source_drift']
 result['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
