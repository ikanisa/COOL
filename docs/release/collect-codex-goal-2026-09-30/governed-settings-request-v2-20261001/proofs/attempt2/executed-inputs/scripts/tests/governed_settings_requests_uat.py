#!/usr/bin/env python3
"""Bounded networkless SQL proof of governed-settings original requests.

Captures exact local prerequisites and fixtures before execution. A retained
row-free schema/ACL and synthetic financial fixtures are installed in a new,
labelled network-none target. The additive migration runs as postgres NOSUPER.
No shared database, hosted Auth, signed JWT, provider or device is exercised.
"""
from pathlib import Path
import argparse,ast,datetime as dt,hashlib,json,os,re,sys,time,types,uuid

q=lambda v:"'"+str(v).replace("'","''")+"'"
j=lambda v:q(json.dumps(v,ensure_ascii=False,separators=(',',':')))+'::jsonb'
sha=lambda b:hashlib.sha256(b).hexdigest()
now=lambda:dt.datetime.now(dt.timezone.utc).isoformat()
UTC=lambda d:d.astimezone(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ')
F='supabase/migrations/20261001220000_governed_settings_requests.sql'
PRE=['20260930213000_operator_email_auth.sql','20260930220527_operator_email_cutover_guard.sql','20260930220000_runtime_control_authority.sql','20260930235500_operator_reason_whitespace.sql','20260930235600_runtime_control_reason_whitespace.sql']
HELP=['shadow_supervisor_uat','receipt_backlog_events_uat','collect_admin_combined_upgrade_uat','collect_current_release_upgrade_uat']
GET_KEYS=set('contract_version scope ok family identity revision exists value redacted content_sha256 checked_at sample_valid_until can_manage'.split())
RECEIPT_KEYS=set('contract_version scope request_id request_fingerprint family identity previous_revision revision changed updated_at content_sha256 recorded_at expires_at'.split())
LOOKUP_KEYS=set('contract_version scope request_id request_fingerprint family identity expires_at checked_at sample_valid_until status receipt'.split())
HISTORY_KEYS=set('contract_version scope family identity checked_at sample_valid_until limit history_complete changes_only rows next_cursor'.split())
ROW_KEYS=set('event_id request_id operation previous_revision revision recorded_at actor_id authority changed_fields old_sha256 new_sha256 reason_sha256 reason_characters redacted'.split())
CAT_KEYS=set('contract_version scope family checked_at sample_valid_until limit descriptor rows next_cursor'.split())
DESC_KEYS=set('identity_fields writable_fields immutable_fields nullable_fields field_types create_allowed can_manage'.split())
CAT_ROW_KEYS=set('identity revision exists redacted content_sha256 value'.split())

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--workspace',type=Path,default=Path.cwd());p.add_argument('--candidate-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 W=a.workspace.resolve();C=a.candidate_root.resolve();P=a.output.resolve()
 assert C.is_relative_to(W) and P.is_relative_to(W) and not P.exists();P.mkdir(parents=True)
 allowed={'HOME','USER','LOGNAME','TMPDIR','PATH','LANG','LC_ALL','LC_CTYPE','SHELL'};env={k:v for k,v in os.environ.items()if k in allowed};os.environ.clear();os.environ.update(env,PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1')
 result=dict(kind='governed_settings_v2_networkless_sql',status='running',started_at=now(),cases=[],target={},actual_blocking_races=0,
  hosted_called=False,signed_jwt_tested=False,provider_called=False,shared_database_written=False,source_rows_copied=False,
  fixture_limits=['Retained row-free schema153/ACL, current scoped prerequisites and all26 existing synthetic control fixtures.','Fresh feature DDL and API SQL execute as actual postgres NOSUPERUSER; original v1 catalog/body preserved.','Platform/Auth schema is owner-normalized; mock cron; no hosted or signed-JWT acceptance; not whole-candidate migration replay.'])
 save=lambda:(P/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
 def case(name,ok,detail=None):
  result['cases'].append(dict(name=name,status='pass'if ok else'failed',detail=detail));save();print(('PASS 'if ok else'FAIL ')+name,flush=True)
  if not ok:raise AssertionError(name+': '+repr(detail))
 target=None;sessions=[]
 try:
  B=W/'docs/release/collect-codex-goal-2026-09-30/exception-inbox-audit-v2-20261001/affected-plan-attempt1';proof=json.loads((B/'result.json').read_text());assert proof['status']=='pass'and proof['sources_unchanged']
  baseline={k:(B/'executed-inputs'/k).read_bytes()for k in proof['baseline_sha256']};assert all(sha(baseline[k])==v for k,v in proof['baseline_sha256'].items())
  paths=['scripts/tests/'+x+'.py'for x in HELP]+['scripts/tests/current_runtime_control_bundle_uat.py','supabase/migrations/20260930150000_runtime_control_governance.sql']+['supabase/migrations/'+x for x in PRE]
  bodies={k:(W/k).read_bytes()for k in paths};bodies[F]=(C/F).read_bytes();bodies['scripts/tests/governed_settings_requests_uat.py']=Path(__file__).read_bytes()
  sources={k:(C/F if k==F else Path(__file__)if k=='scripts/tests/governed_settings_requests_uat.py'else W/k)for k in bodies}
  frozen=P/'executed-inputs'
  for k,b in bodies.items():d=frozen/k;d.parent.mkdir(parents=True,exist_ok=True);d.write_bytes(b)
  for k,b in baseline.items():d=frozen/'.cache/receipt-foundation-attempt8'/k;d.parent.mkdir(parents=True,exist_ok=True);d.write_bytes(b)
  result['source_sha256']={k:sha(v)for k,v in bodies.items()};result['baseline_sha256']=proof['baseline_sha256'];result['retained_baseline_proof_sha256']=sha((B/'result.json').read_bytes());save()
  mods={}
  for name in HELP:
   m=types.ModuleType(name);m.__file__=str(frozen/'scripts/tests'/f'{name}.py');sys.modules[name]=m;exec(compile(bodies['scripts/tests/'+name+'.py'],m.__file__,'exec'),m.__dict__);mods[name]=m
  u=mods[HELP[0]];f=mods[HELP[1]];private=mods[HELP[3]]
  fixture_body=bodies['scripts/tests/current_runtime_control_bundle_uat.py'].decode();tree=ast.parse(fixture_body)
  constants={};ns={'json':json,'re':re}
  for n in tree.body:
   if isinstance(n,ast.Assign)and len(n.targets)==1 and isinstance(n.targets[0],ast.Name):
    try:ns[n.targets[0].id]=ast.literal_eval(n.value)
    except(ValueError,TypeError):pass
  for n in tree.body:
   if isinstance(n,ast.FunctionDef)and n.name in('fixtures','patches','specs_from_source'):exec(compile(ast.Module(body=[n],type_ignores=[]),'<exact retained fixture definitions>','exec'),ns)
  ns.update(UID=f.UID,OTHER=f.OTHER,SID=f.SID,OTHERSID=f.OTHERSID,ROLE=f.ROLE,GROUP=f.GROUP,MEMBER=f.MEMBER)
  specs=ns['specs_from_source'](bodies['supabase/migrations/20260930150000_runtime_control_governance.sql']);fixtures=ns['fixtures']();patches=ns['patches']();families=[k for k in specs if not specs[k].get('user_owned')];assert len(families)==25
  result['families']=families;result['tools']={'python':sys.version,'python_path':sys.executable,'python_sha256':sha(Path(sys.executable).read_bytes()),'docker_path':private.DOCKER,'docker_sha256':sha(Path(private.DOCKER).read_bytes()),'image':private.IMAGE,'image_id':private.IMAGE_ID}
  target=private.Target(P,'governed_settings',result['target']);target.__enter__();u.CONTAINER=target.name;u.SQL_LOG=P/'queries.log';u.CONCURRENCY_LOG=P/'concurrency.log';f.RAW_QUERY_LOG=P/'queries.sql'
  db='governed_settings_'+uuid.uuid4().hex[:10];result['database']=db
  sql=lambda s:u.psql(db,s).stdout.strip();scalar=lambda s:sql(s).splitlines()[-1];data=lambda s:json.loads(scalar(s));rpc=lambda s,uid=f.UID,sid=f.SID:u.call(db,'select '+s,uid,sid)
  def denied(s,state='42501',reason=None,**kw):return u.expected_error(db,'select '+s,state,reason,**kw)
  u.psql('postgres','create database '+db+' template template0;')
  sql('create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+baseline['schema-only.sql'].decode()+baseline['api-acl.sql'].decode());f.seed(db)
  for family,row in fixtures.items():
   relation=specs[family]['relation'];identity={k:row[k]for k in specs[family]['identity']}
   if scalar(f'select exists(select 1 from {relation} t where to_jsonb(t) @> {j(identity)});')=='t':
    assignments=','.join(f'{k}=(jsonb_populate_record(null::{relation},{j(row)})).{k}'for k in row if k not in identity);sql(f'update {relation}t set {assignments}where to_jsonb(t) @> {j(identity)};')
   else:sql(f"insert into {relation}({','.join(row)})select "+','.join(f'(jsonb_populate_record(null::{relation},{j(row)})).{k}'for k in row)+';')
  permissions=sorted({'audit.read'}|{specs[k][field]for k in specs for field in('permission','read_permission','additional_permission')if field in specs[k]})
  sql('insert into public.admin_permissions(name,description)select n,\'Synthetic\'from unnest(array['+','.join(q(n)for n in permissions)+'])n on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select '+q(f.ROLE)+',name from public.admin_permissions on conflict do nothing;')
  financial=f.business_fingerprint(db);assert financial['payments']['rows']>=1 and financial['journal']['rows']>=1
  for path in PRE:sql(bodies['supabase/migrations/'+path].decode())
  # Give the same retained actors verified email approvals without resetting
  # original session age/roles. These are synthetic fixtures, not live access.
  sql(f"update auth.users set email=case when id={q(f.UID)} then 'synthetic-runtime@collect.example' else 'synthetic-other@collect.example' end,email_confirmed_at=clock_timestamp() where id in({q(f.UID)},{q(f.OTHER)});insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)select id,email,clock_timestamp()-interval '2 minutes','Synthetic governed settings approval' from auth.users where id in({q(f.UID)},{q(f.OTHER)});update collect_admin_access.operator_auth_policy set mode='email'where id;")
  target.sql('alter role postgres nosuperuser;',user='supabase_admin',label='predecessor setup complete; actual ordinary feature installer')
  authority=data("select jsonb_build_object('user',current_user,'superuser',(select rolsuper from pg_roles where rolname=current_user));")
  case('feature installer is actual postgres NOSUPERUSER',authority=={'user':'postgres','superuser':False},authority)
  catalog=lambda:data("select coalesce(jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('oid',p.oid,'def',pg_get_functiondef(p.oid),'owner',p.proowner,'acl',p.proacl::text,'config',p.proconfig,'definer',p.prosecdef)),'{}')from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'or n.nspname like 'collect_%';")
  before=catalog();install=u.psql(db,bodies[F].decode(),False);(P/'install.log').write_text(install.stdout+install.stderr);case('additive v2 installs as ordinary owner',install.returncode==0,install.stderr[-1200:]);after=catalog()
  case('all preexisting function OIDs bodies owners ACL and configuration preserved',all(after.get(k)==v for k,v in before.items()))
  case('install preserves nonempty financial evidence',f.business_fingerprint(db)==financial)
  case('private original requests have RLS and no API grants',scalar("select c.relrowsecurity and not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'))from pg_class c where oid='collect_security.runtime_control_requests'::regclass;")=='t')
  case('all eight private helpers have no direct API execution',scalar("select count(*)=8 and bool_and(not has_function_privilege('anon',p.oid,'EXECUTE')and not has_function_privilege('authenticated',p.oid,'EXECUTE')and not has_function_privilege('service_role',p.oid,'EXECUTE'))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='collect_security'and (p.proname like 'runtime_control_v2_%'or p.proname='guard_runtime_control_request_v2');")=='t')
  def identity_for(k):return{k0:fixtures[k][k0]for k0 in specs[k]['identity']}
  def get(k,identity=None):return f'public.admin_get_runtime_control_v2({q(k)},{j(identity or identity_for(k))})'
  def make(k,patch=None,revision=None,request_id=None,deadline=None,reason='Synthetic accountable runtime edit'):
   ident=identity_for(k);revision=rpc(get(k))['revision']if revision is None else revision;request_id=request_id or str(uuid.uuid4());deadline=deadline or UTC(dt.datetime.now(dt.timezone.utc)+dt.timedelta(seconds=90));raw=patch if isinstance(patch,str)else json.dumps(patches[k]if patch is None else patch,ensure_ascii=False,separators=(',',':'))
   fingerprint=sha('\n'.join(['collect-runtime-control-request-v2',request_id,k]+[field+'='+str(ident[field]).lower()if isinstance(ident[field],bool)else field+'='+str(ident[field])for field in specs[k]['identity']]+[str(revision),deadline,sha(raw.encode()),sha(reason.strip().encode())]).encode())
   return dict(request_id=request_id,family=k,identity=ident,raw=raw,revision=revision,deadline=deadline,reason=reason,fingerprint=fingerprint,sql=f'public.admin_update_runtime_control_v2({q(request_id)},{q(k)},{j(ident)},{q(raw)},{revision},{q(reason)},{q(deadline)})')
  def lookup(r):return f"public.admin_get_runtime_control_request_v2({q(r['request_id'])},{q(r['family'])},{j(r['identity'])},{q(r['fingerprint'])},{q(r['deadline'])})"
  receipts={};requests={}
  for k in families:
   observed=rpc(get(k));case(k+' fresh typed read exact redaction and capability',set(observed)==GET_KEYS and observed['contract_version']==2 and observed['can_manage']is True and observed['identity']==identity_for(k) and set(observed['value'])<=set(specs[k]['identity']+specs[k]['writable']),observed)
   cat=rpc(f'public.admin_list_runtime_controls_v2({q(k)},25,null)');case(k+' bounded catalog closed descriptor and row contract',set(cat)==CAT_KEYS and set(cat['descriptor'])==DESC_KEYS and len(cat['rows'])<=25 and all(set(x)==CAT_ROW_KEYS for x in cat['rows']) and not {'relation','reason','session_id'}&set(cat['descriptor']),cat['descriptor'])
   req=make(k,revision=observed['revision']);ack=rpc(req['sql']);requests[k]=req;receipts[k]=ack
   case(k+' exact raw-input fingerprint and immutable request receipt',set(ack)==RECEIPT_KEYS and ack['request_fingerprint']==req['fingerprint']and ack['request_id']==req['request_id'] and ack['previous_revision']==observed['revision'] and ack['revision']==observed['revision']+1 and ack['changed']is True,ack)
   found=rpc(lookup(req));case(k+' original lookup recovers exact receipt',set(found)==LOOKUP_KEYS and found['status']=='recorded'and found['receipt']==ack,found['status'])
   history=rpc(f'public.admin_list_runtime_control_history_v2({q(k)},{j(identity_for(k))},25,null,null)');case(k+' identity history exact immutable metadata and old unassociated events',set(history)==HISTORY_KEYS and history['history_complete']is False and history['changes_only']is True and all(set(x)==ROW_KEYS for x in history['rows']) and history['rows'][0]['request_id']==req['request_id'] and any(x['request_id']is None for x in history['rows']),history['rows'][0])
  # no-op receipt must retain exact v1 head time without event creation.
  k='brand_entities';before_count=scalar('select count(*)from collect_security.runtime_control_events;');req=make(k);ack=rpc(req['sql']);case('no-op records an original receipt with unchanged true head time and no fake event',ack['changed']is False and ack['updated_at']==receipts[k]['updated_at']and scalar('select count(*)from collect_security.runtime_control_events;')==before_count and scalar('select event_id is null from collect_security.runtime_control_requests where request_id='+q(req['request_id'])+';')=='t',ack)
  case('exact original current-session duplicate returns original without audit growth',rpc(req['sql'])==ack and scalar('select count(*)from collect_security.runtime_control_events;')==before_count)
  case('changed raw whitespace same semantic JSON cannot reuse request UUID',bool(denied(req['sql'].replace(q(req['raw']),q(' '+req['raw'])),'22023','runtime_control_request_conflict')))
  case('changed original reason cannot reuse UUID',bool(denied(req['sql'].replace(q(req['reason']),q('Changed accountable reason')),'22023','runtime_control_request_conflict')))
  case('foreign actor original mutation refused',bool(denied(req['sql'],'42501','runtime_control_request_owner_required',uid=f.OTHER,sid=f.OTHERSID)))
  case('foreign actor original lookup refused',bool(denied(lookup(req),'42501','runtime_control_request_owner_required',uid=f.OTHER,sid=f.OTHERSID)))
  sid2=u.SID2;sql(f"insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values({q(sid2)},{q(f.UID)},clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');")
  case('same actor reauthentication may recover original evidence',rpc(lookup(req),sid=sid2)['receipt']==ack)
  case('same actor different session cannot resubmit mutation',bool(denied(req['sql'],'42501','runtime_control_request_owner_required',sid=sid2)))
  for role in('anon','service_role'):
   for name,s in [('get',get(k)),('catalog',f'public.admin_list_runtime_controls_v2({q(k)},1,null)'),('mutation',req['sql']),('lookup',lookup(req)),('history',f'public.admin_list_runtime_control_history_v2({q(k)},{j(identity_for(k))},1,null,null)')]:case(role+' denied public '+name,bool(denied(s,role=role)))
  for action in('select * from','update'):
   s='select * from collect_security.runtime_control_requests;'if action.startswith('select')else"update collect_security.runtime_control_requests set family=family;"
   rr=u.psql(db,'begin;'+u.auth(f.UID,f.SID)+s+'rollback;',False);case('authenticated private '+action+' is denied',rr.returncode!=0 and '42501:'in rr.stderr)
  for statement in("update collect_security.runtime_control_requests set family=family;","delete from collect_security.runtime_control_requests;"):
   rr=u.psql(db,statement,False);case('private original evidence remains immutable to ordinary owner '+statement.split()[0],rr.returncode!=0 and '55000:'in rr.stderr)
  for family in('notification_preferences','not_a_family'):
   case('unreviewed Admin family denied '+family,bool(denied(f'public.admin_list_runtime_controls_v2({q(family)},1,null)','22023','runtime_control_family_invalid')))
  case('repeatable-read mutation denied before any effects',u.psql(db,'begin isolation level repeatable read;'+u.auth(f.UID,f.SID)+'select '+make(k)['sql']+';rollback;',False).returncode!=0)
  case('repeatable-read lookup denied',u.psql(db,'begin isolation level repeatable read;'+u.auth(f.UID,f.SID)+'select '+lookup(req)+';rollback;',False).returncode!=0)
  # Permission changes happen within a rollback-only local owner transaction;
  # query through actual API role after removing one exact grant.
  def permission_probe(permission,s):
   return u.psql(db,'begin;delete from public.admin_role_permissions where role_id='+q(f.ROLE)+'and permission_name='+q(permission)+';'+u.auth(f.UID,f.SID)+'select '+s+';rollback;',False)
  rr=permission_probe(specs[k]['permission'],get(k));v=json.loads(rr.stdout.strip().splitlines()[-1]);case('missing family manage grant yields fresh read with capability false',rr.returncode==0 and v['can_manage']is False,v['can_manage'])
  rr=permission_probe('audit.read',f'public.admin_list_runtime_control_history_v2({q(k)},{j(identity_for(k))},1,null,null)');case('settings authority does not confer independent audit read',rr.returncode!=0 and '42501:'in rr.stderr)
  rr=permission_probe(specs[k]['read_permission'],f'public.admin_list_runtime_control_history_v2({q(k)},{j(identity_for(k))},1,null,null)');case('independent audit history does not require settings read',rr.returncode==0)
  # Fresh observations refuse changed/revoked current authority and expired Auth.
  for label,change in [('revoked email approval',f'update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id={q(f.UID)};'),('expired session',f"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id={q(f.SID)};"),('revoked role',f'update public.admin_user_roles set revoked_at=clock_timestamp()where user_id={q(f.UID)};')]:
   rr=u.psql(db,'begin;'+change+u.auth(f.UID,f.SID)+'select '+lookup(req)+';rollback;',False);case(label+' cannot investigate old request',rr.returncode!=0 and '42501:'in rr.stderr)
  # Remaining lock/race/publication/history tests are owned by this runner.
  run_extended(locals())
  case('governed settings and all failure cases preserve nonempty financial fingerprints',f.business_fingerprint(db)==financial)
  case('all captured input bytes remain unchanged',all(sha(path.read_bytes())==result['source_sha256'][key]for key,path in sources.items()))
  result['status']='pass';result['completed_at']=now()
 except BaseException as e:result['status']='failed';result['failure']=str(e);result['completed_at']=now();save();raise
 finally:
  for session in sessions:
   try:session.close()
   except Exception:pass
  if target is not None:target.close();result['all_task_containers_removed']=result['target'].get('task_container_removed')is True
  save()
 print(json.dumps({'status':result['status'],'cases':len(result['cases']),'result':str(P/'result.json'),'all_task_containers_removed':result.get('all_task_containers_removed')}),flush=True)

def run_extended(c):
 # Defined separately so causal refresh can retain the original failure scope.
 pass

if __name__=='__main__':main()
