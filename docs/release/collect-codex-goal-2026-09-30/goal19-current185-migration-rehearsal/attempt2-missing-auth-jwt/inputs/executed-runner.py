"""Goal19 exact app candidate, actual cached managed roles/extensions, no promotion/mock/skip."""
from pathlib import Path
import subprocess, time, uuid, json, hashlib, datetime, re, importlib.util, shutil
ROOT=Path.cwd();REPORT=ROOT/'.cache/goal19-current185-attempt2';REPORT.mkdir(exist_ok=False)
HREL=Path('scripts/tests/collect_current_release_upgrade_uat.py')
BASE=Path('.cache/receipt-foundation-attempt8/schema-only.sql')
HOST=Path('docs/release/collect-codex-goal-2026-09-30/hosted-readback/metadata.json')
sha=lambda b:hashlib.sha256(b).hexdigest()
x={'scope':'Captured current185 app candidate; real cached Supabase PG managed roles/extensions; two private offline targets; no managed-host or Auth-provider runtime acceptance','started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'phases':{},'cases':[],'production_written':False,'shared_database_written':False,'source_rows_copied':False,'scheduler_executed':False,'provider_called':False,'privilege_promotion':False,'synthetic_vault_or_net':False,'skipped_migrations':False}
def save():(REPORT/'result.json').write_text(json.dumps(x,indent=2)+'\n')
def case(name,ok=True):
 assert ok,name
 x['cases'].append({'name':name,'status':'pass'});save();print('PASS '+name,flush=True)
inputs=REPORT/'inputs';inputs.mkdir()
for name,path in [('executed-runner.py',Path(__file__)),('executed-full-helper.py',ROOT/HREL),('row-free-schema153.sql',ROOT/BASE),('hosted-read-only-metadata.json',ROOT/HOST)]:
 b=path.read_bytes();(inputs/name).write_bytes(b);assert sha((inputs/name).read_bytes())==sha(b)
x['executed_inputs_sha256']={p.name:sha(p.read_bytes())for p in inputs.iterdir()};save()
# Capture and verify every SQL byte before helper import or target initialization.
items=[];mp=inputs/'migrations';mp.mkdir()
for p in sorted((ROOT/'supabase/migrations').glob('*.sql')):
 b=p.read_bytes();v,n=p.stem.split('_',1);q=mp/p.name;q.write_bytes(b);assert sha(q.read_bytes())==sha(b)
 items.append({'path':str(p.relative_to(ROOT)),'version':v,'name':n,'sha256':sha(b),'body':b.decode()})
assert len(items)==185 and len({i['version']for i in items})==185
host=json.loads((inputs/'hosted-read-only-metadata.json').read_text());reg=host['migrations'];assert len(reg)==124 and reg[-1]['version']=='20260906160000';assert[i['version']for i in items[:124]]==[i['version']for i in reg]
x['source_inventory']=[{k:v for k,v in i.items()if k!='body'}for i in items];x['hosted_boundary']={'count':124,'latest':reg[-1]['version'],'version_prefix_parity':True,'all_installed_body_parity':False};x['candidate_manifest_sha256']=sha(json.dumps(x['source_inventory'],sort_keys=True,separators=(',',':')).encode());save()
spec=importlib.util.spec_from_file_location('captured_goal19_helper',inputs/'executed-full-helper.py');h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
assert sha((inputs/'row-free-schema153.sql').read_bytes())==h.BASELINE_HASH
DOCKER=h.DOCKER;IMAGE='public.ecr.aws/supabase/postgres:17.6.1.021';IID='sha256:3f8ad1de081c241b0ed59468590ed789453f352daeff3bc4dff2b169b3bbf43a'
PRELOAD='pg_stat_statements,pgaudit,plpgsql,plpgsql_check,pg_cron,pg_net,pgsodium,auto_explain,pg_tle,plan_filter,supabase_vault'
x['image']={'name':IMAGE,'id':IID,'preload_from_image_config':PRELOAD,'server_version_expected':'17.6','hosted_extension_version_match':{'pg_cron':'1.6.4','pg_net':'0.19.5'},'hosted_owner_privilege_parity_verified':False}
blocks=[];omitted=[];raw=(inputs/'row-free-schema153.sql').read_text();ms=list(re.finditer(r'^--\n-- Name: (.*?); Type: (.*?); Schema: (.*?); Owner: -\n--\n',raw,re.M))
for j,m in enumerate(ms):
 name,kind,schema=m.groups();body=raw[m.end():ms[j+1].start()if j+1<len(ms)else len(raw)]
 if schema!='auth':continue
 if kind in('FUNCTION','COMMENT')or(kind=='TRIGGER'and 'EXECUTE FUNCTION public.'in body):omitted.append({'name':name,'kind':kind,'reason':'Preserve image-provided Auth functions; omit comments and application triggers recreated by app SQL'});continue
 assert kind not in('POLICY','ACL','DEFAULT ACL');blocks.append(m.group()+body)
assert len(blocks)>100 and any('CREATE TABLE auth.sessions' in b for b in blocks)
platform="""set check_function_bodies=off;set standard_conforming_strings=on;
-- Private row-free bootstrap only. Preserve image schemas, owners, grants,
-- default ACLs and Auth functions. Recreate Auth tables as their genuine image role.
do $$declare r record;begin
 for r in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='auth'and c.relkind in('r','p')loop
 execute format('drop table if exists auth.%I cascade',r.relname);end loop;
 for r in select t.typname from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='auth'and t.typtype='e'loop
 execute format('drop type if exists auth.%I cascade',r.typname);end loop;end$$;
set role supabase_auth_admin;
"""+'\n'.join(blocks)+'\nreset role;\n'
(inputs/'platform-auth-shape.sql').write_text(platform);x['platform_bootstrap']={'sha256':sha(platform.encode()),'retained_auth_blocks':len(blocks),'omitted':omitted,'table_creation_role':'supabase_auth_admin','image_schema_function_default_acl_preserved':True,'table_rows_copied':False,'auth_service_runtime_tested':False,'storage_service_runtime_tested':False};save()
ROLE_SQL="select jsonb_agg(jsonb_build_object('name',rolname,'superuser',rolsuper,'inherit',rolinherit,'create_role',rolcreaterole,'create_db',rolcreatedb,'bypass_rls',rolbypassrls,'memberships',(select coalesce(jsonb_agg(r.rolname order by r.rolname),'[]')from pg_auth_members m join pg_roles r on r.oid=m.roleid where m.member=p.oid))order by rolname)from pg_roles p where rolname in('postgres','supabase_admin','supabase_auth_admin','supabase_storage_admin','anon','authenticated','service_role');"
class Target(h.Target):
 def __enter__(self):
  assert h.command([DOCKER,'image','inspect',IMAGE,'--format','{{.Id}}']).stdout.strip()==IID
  password=uuid.uuid4().hex+uuid.uuid4().hex
  cid=h.command([DOCKER,'run','--detach','--pull=never','--name',self.name,'--label','collect.goal19.owner='+self.name,'--network','none','--tmpfs','/var/lib/postgresql/goal19:rw,size=1073741824','-e','POSTGRES_PASSWORD='+password,'-e','PGDATA=/var/lib/postgresql/goal19/data',IMAGE,'postgres','-D','/var/lib/postgresql/goal19/data','-c','shared_preload_libraries='+PRELOAD,'-c','wal_level=logical','-c','cron.database_name=postgres','-c','cron.launch_active_jobs=off','-c','cron.log_run=on','-c','cron.timezone=UTC','-c','pg_net.batch_size=0','-c','listen_addresses=']).stdout.strip();self.made=True;self.evidence['container_id']=cid;self.evidence['container_name']=self.name
  for _ in range(240):
   logs=h.command([DOCKER,'logs',self.name],check=False)
   if 'PostgreSQL init process complete; ready for start up.' in logs.stdout and h.command([DOCKER,'exec',self.name,'pg_isready','-U','postgres'],check=False).returncode==0:break
   time.sleep(.25)
  else:raise RuntimeError('Private image initialization bound expired')
  hostcfg=json.loads(h.command([DOCKER,'inspect',self.name,'--format','{{json .HostConfig}}']).stdout);labels=json.loads(h.command([DOCKER,'inspect',self.name,'--format','{{json .Config.Labels}}']).stdout)
  assert hostcfg['NetworkMode']=='none'and not hostcfg['PortBindings']and labels['collect.goal19.owner']==self.name
  self.evidence['guard']={'network':'none','ports':False,'label_verified':True,**self.json("select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'listen',current_setting('listen_addresses'),'server',current_setting('server_version'),'shared_preload_libraries',current_setting('shared_preload_libraries'));",user='supabase_admin')}
  assert self.evidence['guard']['cron']=='off'and self.evidence['guard']['net']=='0'and self.evidence['guard']['listen']==''
  self.evidence['roles_before']=self.json_role(ROLE_SQL)
  assert next(r for r in self.evidence['roles_before']if r['name']=='postgres')['superuser']is False
  self.evidence['initial_extensions']=self.json_role("select jsonb_agg(jsonb_build_object('name',e.extname,'version',e.extversion,'schema',n.nspname,'owner',pg_get_userbyid(e.extowner))order by e.extname)from pg_extension e join pg_namespace n on n.oid=e.extnamespace;")
  self.sql("create extension if not exists pg_cron with schema pg_catalog version '1.6.4';create extension if not exists pg_net with schema extensions version '0.19.5';",user='supabase_admin',label='genuine platform-extension prerequisite; no application role promotion/grant/owner changes')
  self.evidence['platform_extension_setup']={'role':'supabase_admin','pg_cron':'1.6.4','pg_net':'0.19.5','synthetic_substitution':False,'application_role_promoted':False,'manually_added_grants_or_indexes':False,'hosted_extension_versions_match':True,'hosted_owner_privilege_parity_verified':False}
  return self
 def json_role(self,s):return json.loads(self.sql(s,user='supabase_admin').stdout.strip().splitlines()[-1])
 # Preserve inherited query/fingerprint/app methods, only add role-selectable json.
 def json(self,s,user='postgres'):return json.loads(self.sql(s,user=user).stdout.strip().splitlines()[-1])

PRIVATE_SCHEMAS=['collect_receipt_operations','collect_gateway_dispatch','collect_gateway_archive']
def narrow(t,phase):
 role_after=t.json_role(ROLE_SQL);t.evidence['roles_after']=role_after;case(phase+' preserves every image role attribute/membership',role_after==t.evidence['roles_before'])
 ext=t.json_role("select jsonb_agg(jsonb_build_object('name',e.extname,'version',e.extversion,'schema',n.nspname,'owner',pg_get_userbyid(e.extowner))order by e.extname)from pg_extension e join pg_namespace n on n.oid=e.extnamespace;");t.evidence['final_extensions']=ext
 case(phase+' has real Vault, pg_net and pg_cron',all(any(e['name']==n for e in ext)for n in ['supabase_vault','pg_net','pg_cron']))
 obs=t.json("select jsonb_build_object('policy',(select jsonb_build_object('mode',mode,'stop',emergency_stop,'revision',revision)from collect_receipt_operations.policy where singleton),'worker_enabled',(select enabled from collect_ops.receipt_worker_configuration where singleton),'transport_schema_valid',collect_ops.receipt_transport_schema_valid(),'attempts',(select count(*)from collect_gateway_dispatch.attempts),'archive_acks',(select count(*)from collect_gateway_archive.acknowledgements),'principals',(select count(*)from collect_supervisor.identities),'devices',(select count(*)from collect_gateway.devices),'queue',(select count(*)from net.http_request_queue),'cron_history',(select count(*)from cron.job_run_details));")
 (t.report/'observed-default-composition.json').write_text(json.dumps(obs,indent=2)+'\n')
 case(phase+' combined110000–180000 defaults preserve paused policy and no dispatch',obs['policy']['mode']=='Paused'and obs['policy']['stop']and not obs['worker_enabled']and obs['attempts']==obs['archive_acks']==obs['principals']==obs['devices']==obs['queue']==obs['cron_history']==0)
 case(phase+' genuine pg_net response index/grants satisfy strict transport read predicate',obs['transport_schema_valid']is True)
 for role in ['anon','authenticated','service_role']:
  ok=t.scalar("select not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname=any(array['collect_receipt_operations','collect_gateway_dispatch','collect_gateway_archive'])and c.relkind='r'and (not c.relrowsecurity or has_table_privilege("+h.quoted(role)+",c.oid,'SELECT,INSERT,UPDATE,DELETE')));")=='t';case(phase+' '+role+' cannot directly read/write new private authority tables',ok)
 t.evidence['schema_privacy']=t.json_role("select jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'acl',c.relacl::text)order by n.nspname,c.relname)from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('collect_receipt_operations','collect_gateway_dispatch','collect_gateway_archive','net','vault')and c.relkind in('r','v');")
 t.evidence['rpc_grants']=t.json_role("select jsonb_agg(jsonb_build_object('name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),'owner',pg_get_userbyid(p.proowner),'definer',p.prosecdef,'acl',p.proacl::text)order by p.proname)from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('receipt_operations_execute_v2','gateway_dispatch_grant_v2','gateway_arm_dispatch_v2','gateway_callback_v2','gateway_archive_attempt_v3','gateway_archive_lookup_v3','process_receipt_deferral_exceptions_v1','execute_receipt_exception_worker_v1','reconcile_receipt_worker_transport_v1','admin_list_receipt_operations_identities_v3');")

try:
 for phase in ['clean','populated']:
  o=x['phases'][phase]={'status':'running'};t=Target(REPORT,phase,o)
  try:
   t.__enter__();save();t.sql(platform,user='supabase_admin',label='row-free platform Auth bootstrap preserving genuine image role/defaultACL');case(phase+' Auth shape has no users/source rows',t.scalar('select count(*)=0 from auth.users;')=='t')
   case(phase+' Auth tables retain genuine managed owner and existing installer REFERENCES/TRIGGER grants',t.scalar("select pg_get_userbyid(c.relowner)='supabase_auth_admin'and has_table_privilege(current_user,c.oid,'REFERENCES,TRIGGER')from pg_class c where c.oid='auth.users'::regclass;")=='t')
   t.sql('create schema if not exists supabase_migrations;create table supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);',label='task-owned source registry as unchanged postgres installer')
   if phase=='clean':h.apply(t,items,o)
   else:
    h.apply(t,items[:124],o);case('populated reaches exact hosted124 source-version boundary',int(t.scalar('select count(*)from supabase_migrations.schema_migrations;'))==124)
    h.seed_populated(t,x,case)
    for i in items[124:]:
     before=h.fingerprints(t,x['preserved_columns']);h.apply(t,[i],o);after=h.fingerprints(t,x['preserved_columns']);assert before==after,'Canonical predecessor changed at '+i['path'];o['migrations'][-1]['18_predecessor_fingerprints_preserved']=True;save()
    case('every pending migration preserves18 predecessor financial/receipt/Auth/authority projections',h.fingerprints(t,x['preserved_columns'])==x['populated_predecessor_fingerprints'])
    case('all original journals remain exactly two lines balanced',t.scalar("select not exists(select 1 from collect_hybrid.momo_journal_entries j left join collect_hybrid.momo_journal_lines l on l.journal_entry_id=j.id group by j.id having count(*)<>2 or sum(case when l.direction='debit'then l.amount_rwf else-l.amount_rwf end)<>0);")=='t')
    case('paused historical payment is never automatically backfilled',t.scalar("select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='99780000-0000-4000-8000-000000050003');")=='t')
   case(phase+' registry reaches every exact captured185 migration',int(t.scalar('select count(*)from supabase_migrations.schema_migrations;'))==185)
   narrow(t,phase);o['status']='pass'
  except Exception as e:
   o['status']='failed';o['failure']=str(e);print(phase+' FAILED '+str(e),flush=True)
  finally:
   if t.made:
    try:o['end_role_state']=t.json_role(ROLE_SQL)
    except Exception as e:o['end_role_state_error']=str(e)
   t.close();save()
 x['status']='pass'if all(p['status']=='pass'for p in x['phases'].values())else'failed'
finally:
 x['source_drift']=[i['path']for i in items if not(ROOT/i['path']).exists()or sha((ROOT/i['path']).read_bytes())!=i['sha256']]
 x['executed_input_drift']=[p.name for p in inputs.iterdir()if p.is_file()and p.name in x['executed_inputs_sha256']and sha(p.read_bytes())!=x['executed_inputs_sha256'][p.name]]
 x['runner_unchanged']=sha(Path(__file__).read_bytes())==x['executed_inputs_sha256']['executed-runner.py'];x['ended_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save();print(json.dumps({'status':x['status'],'passed_cases':len(x['cases']),'source_drift':x['source_drift'],'phases':{k:{a:v[a]for a in ['status','task_container_removed']if a in v}for k,v in x['phases'].items()}}))
