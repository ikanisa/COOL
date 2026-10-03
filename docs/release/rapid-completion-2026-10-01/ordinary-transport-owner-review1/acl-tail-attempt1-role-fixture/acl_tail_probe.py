#!/usr/bin/env python3
"""Finite remaining owner-only ACL, definer, and required-column proof."""
from pathlib import Path
import datetime, hashlib, importlib.util, json, re
ROOT=Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
OUT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('captured_target',OUT/'captured-source/scripts/tests/collect_current_release_upgrade_uat.py')
replay=importlib.util.module_from_spec(spec);spec.loader.exec_module(replay);replay.ROOT=ROOT
result={'status':'running','scope':'Only remaining owner-only private net table/column ACL and exact sampler read tail. Earlier20 controls retained separately. Not full migration/replay, HTTP delivery, live Auth or whole L08/L23 closure.', 'shared_database_written':False,'hosted_called':False,'provider_called':False,'source_files_written':False,'cases':[], 'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
inputs=['acl_tail_probe.py','proposed-platform-prerequisites.sql','candidate-validator.sql','candidate-index-preflight.sql','exact-source-sample.sql','captured-source/scripts/tests/collect_current_release_upgrade_uat.py']
result['consumed_inputs']={name:hashlib.sha256((OUT/name).read_bytes()).hexdigest()for name in inputs}
phase=result['owned_target']={}
def save(): (OUT/'acl-tail-result.json').write_text(json.dumps(result,indent=2)+'\n')
def case(name,value=True):
 if not value: raise AssertionError(name)
 result['cases'].append({'name':name,'status':'pass'});save();print('PASS '+name,flush=True)
def read(name):return(OUT/name).read_text()
validator=read('candidate-validator.sql');preflight='do $transport_read_prerequisite$'+validator.split('do $transport_read_prerequisite$',1)[1]
utc=re.search(r'create function collect_ops.utc\(p_time timestamptz\)[\s\S]*?\$\$;',read('captured-source/supabase/migrations/20261001000100_operational_exception_inbox.sql')).group()
functions="select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'definer',p.prosecdef,'config',p.proconfig)order by p.oid::regprocedure::text),'[]')from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='net'and p.proname in('http_get','http_post','http_delete');"
target=replay.Target(OUT,'acl_tail_owned_probe',phase)
try:
 save()
 with target:
  target.sql('create schema if not exists extensions;create extension if not exists pg_net with schema extensions;',user='supabase_admin',label='actual cached platform-owned pg_net prerequisite')
  # Match only the independently read retained platform function metadata.
  # This is clone-only platform shape, not an application or proposed change.
  current_functions=target.json(functions)
  result['fresh_extension_functions']=current_functions
  for name,signature in [('http_get','text,jsonb,jsonb,integer'),('http_post','text,jsonb,jsonb,jsonb,integer')]:
   f=next(x for x in current_functions if x['signature'].startswith('net.'+name+'('))
   if not f['definer']or f['config']!=['search_path=net']:
    target.sql(f'alter function net.{name}({signature})security definer;alter function net.{name}({signature})set search_path=net;',user='supabase_admin',label='clone-only exact retained platform trusted function shape')
    result.setdefault('clone_platform_shape_adjustments',[]).append(name)
  before_functions=target.json(functions);result['retained_shape_functions']=before_functions
  target.sql('alter role postgres nosuperuser;',user='supabase_admin',label='ordinary installer before any candidate application DDL')
  target.sql('create schema collect_ops;'+utc,label='ordinary diagnostic schema and exact UTC helper')
  target.sql(read('candidate-index-preflight.sql'),check=False,label='retained missing index condition only')
  target.sql('create index collect_receipt_http_response_id on net._http_response(id);',user='supabase_admin',label='only platform owner provisions its response index')
  denied=target.sql(read('proposed-platform-prerequisites.sql'),check=False,label='ordinary installer cannot perform owner-only platform ACL setup')
  case('owner-only preparation denies ordinary NOSUPERUSER installer42501',denied.returncode!=0 and'42501'in denied.stderr and'receipt_transport_platform_owner_required'in denied.stderr)
  # Explicit table AND column leakage controls, including inherited PUBLIC ACL.
  target.sql('grant all on net._http_response,net.http_request_queue to public;grant select(headers)on net._http_response to anon,authenticated,service_role,postgres;grant select(body)on net.http_request_queue to anon,authenticated,service_role,postgres;',user='supabase_admin',label='clone-only original PUBLIC exposure plus explicit stale column grants')
  before=target.sql('select headers,content,error_msg from net._http_response limit 0;select url,headers,body from net.http_request_queue limit 0;',user='anon',check=False,label='actual original platform raw direct-read exposure control')
  case('preparation has actual prior PUBLIC raw response and queue positive control',before.returncode==0)
  target.sql(validator.split('do $transport_read_prerequisite$',1)[0],label='ordinary strict type index privilege privacy validator')
  case('app validator rejects preexisting raw table exposure',target.scalar('select collect_ops.receipt_transport_schema_valid();')=='f')
  exposed=target.sql(preflight,check=False,label='ordinary app refuses exposed platform prerequisites')
  case('app preflight refuses exposed platform55000',exposed.returncode!=0 and'55000'in exposed.stderr)
  target.sql(read('proposed-platform-prerequisites.sql'),user='supabase_admin',label='exact proposed owner-only full table and column revokes plus seven SELECT grants')
  case('ordinary current platform preflight passes after owner preparation',target.sql(read('candidate-index-preflight.sql')+preflight,check=False,label='ordinary fully satisfied proposal').returncode==0)
  result['direct_column_grants']=target.json("select jsonb_agg(jsonb_build_object('relation',a.attrelid::regclass::text,'column',a.attname,'privilege',acl.privilege_type)order by a.attrelid::regclass::text,a.attnum)from pg_attribute a cross join lateral aclexplode(a.attacl)acl where a.attrelid in('net._http_response'::regclass,'net.http_request_queue'::regclass)and acl.grantee=(select oid from pg_roles where rolname='postgres');")
  case('postgres direct grants exactly seven SELECT columns',len(result['direct_column_grants'])==7 and all(x['privilege']=='SELECT'for x in result['direct_column_grants'])and set((x['relation'],x['column'])for x in result['direct_column_grants'])=={('net._http_response',c)for c in ['id','status_code','content','timed_out','error_msg','created']}|{('net.http_request_queue','id')})
  result['table_direct_grants']=target.json("select jsonb_build_object('reader_direct_table_acl',exists(select 1 from pg_class c cross join lateral aclexplode(c.relacl)acl where c.oid in('net._http_response'::regclass,'net.http_request_queue'::regclass)and acl.grantee=(select oid from pg_roles where rolname='postgres')),'inherited_read_all_data',pg_has_role('postgres','pg_read_all_data','USAGE'),'inherited_headers_read',has_column_privilege('postgres','net._http_response','headers','SELECT'),'postgres_dml',has_table_privilege('postgres','net.http_request_queue','INSERT,UPDATE,DELETE')or has_table_privilege('postgres','net._http_response','INSERT,UPDATE,DELETE'));")
  case('proposal normalizes direct postgres ACL without silently changing inherited read authority',result['table_direct_grants']=={'reader_direct_table_acl':False,'inherited_read_all_data':True,'inherited_headers_read':True,'postgres_dml':False})
  negatives=[]
  operations=[('response whole read','select * from net._http_response limit 0;'),('response raw-column read','select headers,content,error_msg from net._http_response limit 0;'),('queue whole read','select * from net.http_request_queue limit 0;'),('queue raw-column read','select url,headers,body from net.http_request_queue limit 0;'),('response INSERT','insert into net._http_response default values;'),('response UPDATE','update net._http_response set content=null where false;'),('response DELETE','delete from net._http_response where false;'),('queue INSERT','insert into net.http_request_queue default values;'),('queue UPDATE','update net.http_request_queue set body=null where false;'),('queue DELETE','delete from net.http_request_queue where false;')]
  for role in ['anon','authenticated','service_role']:
   for name,sql in operations:
    denied=target.sql(sql,user=role,check=False,label='actual '+role+' direct '+name+' denial')
    negatives.append({'role':role,'operation':name,'exit_code':denied.returncode,'sqlstate_42501':'42501'in denied.stderr})
    case(role+' actual direct '+name+' denied42501',denied.returncode!=0 and'42501'in denied.stderr)
  result['actual_role_denials']=negatives
  case('existing trusted net functions are byte-metadata unchanged by platform ACL proposal',target.json(functions)==before_functions)
  result['worker']=target.json("select coalesce(jsonb_agg(jsonb_build_object('role',usename,'backend',backend_type,'response_owner',pg_get_userbyid(c.relowner),'owns_tables',pg_has_role(usename,c.relowner,'USAGE'))),'[]')from pg_stat_activity a cross join pg_class c where c.oid='net._http_response'::regclass and a.backend_type ilike '%pg_net%';")
  case('actual C worker retains platform owner identity and table ownership',len(result['worker'])==1 and result['worker'][0]['role']=='supabase_admin'and result['worker'][0]['owns_tables'])
  target.sql('select net.check_worker_is_up();',user='supabase_admin',label='actual existing worker liveness only; no queue insert or HTTP API')
  case('existing platform C worker remains up after private ACL changes')
  target.sql('grant select(headers)on net._http_response to authenticated;',user='supabase_admin',label='clone-only independent column leak negative')
  case('strict app validator rejects column leakage without table ACL',target.scalar('select collect_ops.receipt_transport_schema_valid();')=='f')
  leak=target.sql(preflight,check=False,label='ordinary preflight column leakage refusal')
  case('ordinary preflight refuses raw column exposure55000',leak.returncode!=0 and'55000'in leak.stderr)
  target.sql('revoke select(headers)on net._http_response from authenticated;revoke pg_read_all_data from postgres;',user='supabase_admin',label='restore leak then clone-only remove inherited read for exact minimum ACL proof')
  case('strict seven-column reader profile independently passes',target.scalar('select collect_ops.receipt_transport_schema_valid();')=='t')
  target.sql(read('exact-source-sample.sql')+'revoke all on function collect_ops.receipt_transport_sample(bigint,uuid),collect_ops.receipt_transport_schema_valid()from public,anon,authenticated,service_role;',label='original bounded sampler exact body and private function EXEC')
  empty=target.json("select collect_ops.receipt_transport_sample(94160002,'94160000-0000-4000-8000-000000000002');")
  case('original empty sampler needs only permitted queue.id read',empty['outcome']=='RESPONSE_UNOBSERVED')
  target.sql("insert into net._http_response(id,status_code,content,timed_out,error_msg,created)values(94160002,403,'{\"error\":\"WORKER_AUTH_REQUIRED\"}',false,null,clock_timestamp());",user='supabase_admin',label='only synthetic response evidence no queue or HTTP operation')
  bounded=target.json("select collect_ops.receipt_transport_sample(94160002,'94160000-0000-4000-8000-000000000002');")
  case('original response sampler works with exact minimum six response columns',bounded['outcome']=='AUTH_REFUSED'and set(bounded)=={'outcome','transport_terminal','http_status','worker_error_code','response_rows_observed','response_at'})
  for relation,column in [('net._http_response','content'),('net.http_request_queue','id')]:
   target.sql(f'revoke select({column})on {relation} from postgres;',user='supabase_admin',label='individual required column missing negative')
   case('strict validator rejects absent '+relation+'.'+column,target.scalar('select collect_ops.receipt_transport_schema_valid();')=='f')
   sampled=target.sql("select collect_ops.receipt_transport_sample(94160003,'94160000-0000-4000-8000-000000000003');",check=False,label='actual definer cannot bypass required missing column')
   case('actual definer sampler denies absent '+relation+'.'+column+'42501',sampled.returncode!=0 and'42501'in sampled.stderr)
   target.sql(f'grant select({column})on {relation} to postgres;',user='supabase_admin',label='restore exact minimal ACL')
  result['final_guard']=target.json("select jsonb_build_object('net',current_setting('pg_net.batch_size'),'cron',current_setting('cron.launch_active_jobs'),'queue_rows',(select count(id)from net.http_request_queue),'superuser',(select rolsuper from pg_roles where rolname=current_user),'valid',collect_ops.receipt_transport_schema_valid());")
  case('ordinary installer stays NOSUPERUSER with valid prerequisites no dispatch and zero queue',result['final_guard']=={'net':'0','cron':'off','queue_rows':0,'superuser':False,'valid':True})
 result['status']='pass'
except Exception as exc:
 result['status']='failed';result['failure']=str(exc);save();raise
finally:
 target.close();result['owned_container_removed']=phase.get('task_container_removed')is True
 original=json.loads((OUT/'source-before.json').read_text())
 result['source_drift']=[name for name,digest in original.items()if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
 result['consumed_input_drift']=[name for name,digest in result['consumed_inputs'].items()if hashlib.sha256((OUT/name).read_bytes()).hexdigest()!=digest]
 result['migration_source_unchanged']='supabase/migrations/20261001160000_receipt_worker_transport_health.sql'not in result['source_drift']
 result['completed_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
