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
F='supabase/migrations/20261002000000_runtime_control_edit_eligibility.sql'
PRE=['20260930213000_operator_email_auth.sql','20260930220527_operator_email_cutover_guard.sql','20260930220000_runtime_control_authority.sql','20260930235500_operator_reason_whitespace.sql','20260930235600_runtime_control_reason_whitespace.sql','20261001220000_governed_settings_requests.sql']
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
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--workspace',type=Path,default=Path.cwd());p.add_argument('--candidate-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--scope',choices=('full','extended','extended-tail','final-only'),default='full');a=p.parse_args()
 W=a.workspace.resolve();C=a.candidate_root.resolve();P=a.output.resolve()
 assert C.is_relative_to(W) and P.is_relative_to(W) and not P.exists();P.mkdir(parents=True)
 allowed={'HOME','USER','LOGNAME','TMPDIR','PATH','LANG','LC_ALL','LC_CTYPE','SHELL'};env={k:v for k,v in os.environ.items()if k in allowed};os.environ.clear();os.environ.update(env,PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1')
 result=dict(kind='governed_settings_v2_networkless_sql',scope=a.scope,status='running',started_at=now(),cases=[],target={},actual_blocking_races=0,
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
  bodies={k:(W/k).read_bytes()for k in paths};bodies[F]=(C/F).read_bytes();bodies['scripts/tests/runtime_control_edit_eligibility_uat.py']=Path(__file__).read_bytes()
  sources={k:(C/F if k==F else Path(__file__)if k=='scripts/tests/runtime_control_edit_eligibility_uat.py'else W/k)for k in bodies}
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
  target=private.Target(P,'settings_eligibility',result['target']);target.__enter__();u.CONTAINER=target.name;u.SQL_LOG=P/'queries.log';u.CONCURRENCY_LOG=P/'concurrency.log';f.RAW_QUERY_LOG=P/'queries.sql'
  db='governed_settings_'+uuid.uuid4().hex[:10];result['database']=db
  sql=lambda s:u.psql(db,s).stdout.strip();scalar=lambda s:sql(s).splitlines()[-1];data=lambda s:json.loads(scalar(s));rpc=lambda s,uid=f.UID,sid=f.SID:u.call(db,'select '+s,uid,sid)
  def denied(s,state='42501',reason=None,**kw):return u.expected_error(db,'select '+s,state,reason,**kw)
  u.psql('postgres','create database '+db+' template template0;')
  sql('create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+baseline['schema-only.sql'].decode()+baseline['api-acl.sql'].decode());f.seed(db)
  permissions=sorted({'audit.read'}|{specs[k][field]for k in specs for field in('permission','read_permission','additional_permission')if field in specs[k]})
  sql('insert into public.admin_permissions(name,description)select n,\'Synthetic\'from unnest(array['+','.join(q(n)for n in permissions)+'])n on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select '+q(f.ROLE)+',name from public.admin_permissions on conflict do nothing;')
  for family,row in fixtures.items():
   relation=specs[family]['relation'];identity={k:row[k]for k in specs[family]['identity']}
   if scalar(f'select exists(select 1 from {relation} t where to_jsonb(t) @> {j(identity)});')=='t':
    assignments=','.join(f'{k}=(jsonb_populate_record(null::{relation},{j(row)})).{k}'for k in row if k not in identity);sql(f'update {relation} t set {assignments} where to_jsonb(t) @> {j(identity)};')
   else:sql(f"insert into {relation}({','.join(row)})select "+','.join(f'(jsonb_populate_record(null::{relation},{j(row)})).{k}'for k in row)+';')
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
  case('all seven predecessor private helpers retain no direct API execution',scalar("select count(*)=7 and bool_and(not has_function_privilege('anon',p.oid,'EXECUTE')and not has_function_privilege('authenticated',p.oid,'EXECUTE')and not has_function_privilege('service_role',p.oid,'EXECUTE'))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='collect_security'and (p.proname like 'runtime_control_v2_%'or p.proname='guard_runtime_control_request_v2');")=='t')
  def identity_for(k):return{k0:fixtures[k][k0]for k0 in specs[k]['identity']}
  def get(k,identity=None):return f'public.admin_get_runtime_control_v2({q(k)},{j(identity or identity_for(k))})'
  def make(k,patch=None,revision=None,request_id=None,deadline=None,reason='Synthetic accountable runtime edit'):
   ident=identity_for(k);revision=rpc(get(k))['revision']if revision is None else revision;request_id=request_id or str(uuid.uuid4());deadline=deadline or UTC(dt.datetime.now(dt.timezone.utc)+dt.timedelta(seconds=90));raw=patch if isinstance(patch,str)else json.dumps(patches[k]if patch is None else patch,ensure_ascii=False,separators=(',',':'))
   fingerprint=sha('\n'.join(['collect-runtime-control-request-v2',request_id,k]+[field+'='+str(ident[field]).lower()if isinstance(ident[field],bool)else field+'='+str(ident[field])for field in specs[k]['identity']]+[str(revision),deadline,sha(raw.encode()),sha(reason.strip().encode())]).encode())
   return dict(request_id=request_id,family=k,identity=ident,raw=raw,revision=revision,deadline=deadline,reason=reason,fingerprint=fingerprint,sql=f'public.admin_update_runtime_control_v2({q(request_id)},{q(k)},{j(ident)},{q(raw)},{revision},{q(reason)},{q(deadline)})')
  def lookup(r):return f"public.admin_get_runtime_control_request_v2({q(r['request_id'])},{q(r['family'])},{j(r['identity'])},{q(r['fingerprint'])},{q(r['deadline'])})"
  receipts={};requests={}
  def eligible(k,patch=None,identity=None,revision=None,raw=None):
   ident=identity if identity is not None else identity_for(k)
   rev=rpc(get(k,ident))['revision']if revision is None else revision
   raw=raw if raw is not None else json.dumps(patch or{},ensure_ascii=False,separators=(',',':'))
   return f'public.admin_get_runtime_control_eligibility_v1({q(k)},{j(ident)},{rev},{q(raw)})'
  if a.scope!='final-only':
   KEYS=set('contract_version scope family identity revision patch_sha256 checked_at sample_valid_until can_manage permitted_fields permitted_statuses create_allowed blocker'.split())
   observed={}
   for k in families:
    v=rpc(eligible(k));observed[k]=v
    case(k+' closed fresh eligibility with exact raw discovery digest',set(v)==KEYS and v['contract_version']==1 and v['scope']=='runtime_control_eligibility'and v['patch_sha256']==sha(b'{}')and v['identity']==identity_for(k)and v['revision']==rpc(get(k))['revision']and v['can_manage']is True and set(v['permitted_fields'])<=set(specs[k]['writable'])and not {'value','session_id','reason','relation'}&set(v),v)
   (P/'observed-eligibility.json').write_text(json.dumps(observed,indent=2)+'\n')
   case('actual draft sections are editable with immutable wiring excluded',set(observed['policy_document_sections']['permitted_fields'])==set(specs['policy_document_sections']['writable'])-{'policy_document_id','section_key'}and observed['policy_document_sections']['blocker']is None)
   case('actual all-draft template admits locale/event/metadata edits',set(observed['notification_templates']['permitted_fields'])==set(specs['notification_templates']['writable']))
   case('policy with actual sections admits publication','published'in observed['policy_documents']['permitted_statuses'])
   case('version with actual template admits publication','published'in observed['notification_template_versions']['permitted_statuses'])
   newsection={'id':str(uuid.uuid4())};newversion={'id':str(uuid.uuid4())};missing=str(uuid.uuid4())
   v=rpc(eligible('policy_document_sections',identity=newsection,revision=0));case('new section requires a prospective exact parent',v['blocker']=='parent_required'and not v['permitted_fields'])
   v=rpc(eligible('policy_document_sections',identity=newsection,revision=0,patch={'policy_document_id':missing}));case('missing exact prospective section parent is refused',v['blocker']=='patch_not_permitted'and not v['permitted_fields'])
   v=rpc(eligible('policy_document_sections',identity=newsection,revision=0,patch={'policy_document_id':identity_for('policy_documents')['id']}));case('new section with actual draft parent admits immutable wiring at creation',v['blocker']is None and 'policy_document_id'in v['permitted_fields']and v['create_allowed'])
   v=rpc(eligible('notification_template_versions',identity=newversion,revision=0,patch={'template_key':'missing_template'}));case('new version with missing prospective template is refused',v['blocker']=='patch_not_permitted'and not v['permitted_fields'])
   raw=' {"body":"Eligible UTF8 α"} ';v=rpc(eligible('policy_document_sections',raw=raw));case('eligibility binds exact UTF8 whitespace and text bytes',v['patch_sha256']==sha(raw.encode()))
   case('stale requested revision is refused',bool(denied(eligible('policy_documents',revision=observed['policy_documents']['revision']+1),'40001','runtime_control_conflict')))
   for raw in ['[1]','{"unknown":1}','{"body":',' '*65537]:case('invalid raw patch refused '+str(len(raw)),bool(denied(eligible('policy_document_sections',raw=raw),'22023')))
   for role in ['anon','service_role']:case(role+' eligibility execution denied',bool(denied(eligible('policy_documents'),role=role)))
   case('member-owned preferences are excluded',bool(denied("public.admin_get_runtime_control_eligibility_v1('notification_preferences','{}',0,'{}')",'22023','runtime_control_family_invalid')))
   e=eligible('policy_documents')
   rr=u.psql(db,'begin isolation level repeatable read;'+u.auth(f.UID,f.SID)+'select '+e+';rollback;',False);case('repeatable read eligibility refused',rr.returncode!=0 and '25001:'in rr.stderr)
   def permission_probe(permission,expression):return u.psql(db,'begin;delete from public.admin_role_permissions where role_id='+q(f.ROLE)+'and permission_name='+q(permission)+';'+u.auth(f.UID,f.SID)+'select '+expression+';rollback;',False)
   rr=permission_probe('settings.manage',e);v=json.loads(rr.stdout.strip().splitlines()[-1]);case('read-authorized missing manage is exact false capability without fields',rr.returncode==0 and v['can_manage']is False and v['blocker']=='manage_required'and not v['permitted_fields'])
   rr=permission_probe('settings.read',e);case('missing family read denies eligibility',rr.returncode!=0 and '42501:'in rr.stderr)
   rr=permission_probe('audit.read',e);case('eligibility requires family read independently of audit',rr.returncode==0)
   rr=permission_probe('settings.read',f"public.admin_list_runtime_control_history_v2('policy_documents',{j(identity_for('policy_documents'))},1,null,null)");case('independent audit history unaffected by missing settings read',rr.returncode==0)
   for label,change in [('revoked approval',f'update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id={q(f.UID)};'),('expired Auth',f"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id={q(f.SID)};"),('revoked role',f'update public.admin_user_roles set revoked_at=clock_timestamp()where user_id={q(f.UID)};')]:
    rr=u.psql(db,'begin;'+change+u.auth(f.UID,f.SID)+'select '+e+';rollback;',False);case(label+' refuses eligibility rather than false capability',rr.returncode!=0 and '42501:'in rr.stderr)
   def mutate(k,patch,revision=None):return rpc(make(k,patch=patch,revision=revision)['sql'])
   before=rpc(get('policy_document_sections'));mutate('policy_document_sections',{'body':'Supported draft section edit'});case('actual v2 mutation admits supported draft section edit',rpc(get('policy_document_sections'))['value']['body']=='Supported draft section edit')
   old_revision=before['revision'];case('eligibility cannot override changed current revision',bool(denied(eligible('policy_document_sections',revision=old_revision),'40001','runtime_control_conflict')))
   v=rpc(eligible('notification_templates',patch={'locale':'fr'}));mutate('notification_templates',{'locale':'fr'});case('draft template contextual edit then original v2 mutation is supported',v['blocker']is None and rpc(get('notification_templates'))['value']['locale']=='fr')
   v=rpc(eligible('notification_template_versions',patch={'status':'published'}));mutate('notification_template_versions',{'status':'published'});case('approved existing version publication goes through unchanged v2 final guards',v['blocker']is None and rpc(get('notification_template_versions'))['value']['status']=='published')
   v=rpc(eligible('notification_templates'));case('any actual non-draft version restricts template to enabled only',v['permitted_fields']==['enabled'])
   v=rpc(eligible('notification_template_versions'));case('published version exposes status-only permitted transitions',v['permitted_fields']==['status']and v['permitted_statuses']==['published','archived'])
   case('published version cannot return to draft',rpc(eligible('notification_template_versions',patch={'status':'draft'}))['blocker']=='status_not_permitted')
   case('published version content cannot be edited',rpc(eligible('notification_template_versions',patch={'body_template':'Forbidden'}))['blocker']=='patch_not_permitted')
   mutate('notification_template_versions',{'status':'archived'});case('archived version cannot unarchive',rpc(eligible('notification_template_versions'))['permitted_statuses']==['archived'])
   v=rpc(eligible('policy_documents',patch={'status':'published'}));mutate('policy_documents',{'status':'published'});case('actual policy publication with sections is supported by final v2 guard',v['blocker']is None and rpc(get('policy_documents'))['value']['status']=='published')
   v=rpc(eligible('policy_document_sections'));case('section eligibility changes immediately after actual parent publication',v['blocker']=='parent_published'and not v['permitted_fields'])
   case('stale draft eligibility cannot bypass final parent publication guard',bool(denied(make('policy_document_sections',patch={'body':'Forbidden after publication'})['sql'],'55000','runtime_control_published_immutable')))
   mutate('policy_documents',{'status':'archived'});case('archived policy cannot unarchive',rpc(eligible('policy_documents'))['permitted_statuses']==['archived'])
   # A fresh policy without sections has an actual context; publication alone
   # remains refused by both the reader and the unchanged v1 final guard.
   newdoc={'id':str(uuid.uuid4())};patch={'kind':'privacy','locale':'en','version':'eligibility-empty','title':'Synthetic empty draft'}
   request=make('policy_documents',patch=patch,revision=0);request['identity']=newdoc
   request['sql']=f"public.admin_update_runtime_control_v2({q(str(uuid.uuid4()))},'policy_documents',{j(newdoc)},{q(json.dumps(patch,separators=(',',':')))},0,'Synthetic draft policy creation',{q(UTC(dt.datetime.now(dt.timezone.utc)+dt.timedelta(seconds=90)))})"
   rpc(request['sql']);v=rpc(eligible('policy_documents',identity=newdoc));case('empty draft policy cannot publish without sections','published'not in v['permitted_statuses'])
   case('requested empty policy publication returns redacted sections blocker',rpc(eligible('policy_documents',identity=newdoc,patch={'status':'published'}))['blocker']=='sections_required')
  def session(name):
   x=u.Session(db,name);sessions.append(x);x.write("select pg_backend_pid();select 'PID_READY';");lines=x.read('PID_READY');x.pid=int(next(v for v in lines if v.isdigit()));return x
  def blocked(x,by):
   until=time.monotonic()+8
   while time.monotonic()<until:
    if scalar(f'select {by.pid}=any(pg_blocking_pids({x.pid}));')=='t':result['actual_blocking_races']+=1;return True
    time.sleep(.02)
   raise AssertionError('expected actual blocking absent')
  if a.scope!='final-only':
   b=session('context_writer');b.write("begin;lock table public.notification_template_versions in row exclusive mode;select 'CONTEXT_HELD';");b.read('CONTEXT_HELD');case('concurrent version insertion predicate writer refuses eligibility NOWAIT',bool(denied(eligible('notification_templates'),'42501','runtime_control_eligibility_unavailable')));b.write("rollback;select 'CONTEXT_RELEASED';");b.read('CONTEXT_RELEASED')
   # Read holds exact context predicate fences through its transaction; actual
   # parent mutation blocks, then a later observation sees the committed change.
   b=session('eligibility_context_observer');b.write('begin;'+u.auth(f.UID,f.SID)+'select '+eligible('policy_documents',identity=newdoc)+";select 'ELIGIBILITY_HELD';");b.read('ELIGIBILITY_HELD')
   w=session('parent_change');w.write('begin;update public.policy_documents set title=\'Changed after eligibility\'where id='+q(newdoc['id'])+";commit;select 'PARENT_CHANGED';");case('actual parent writer waits behind retained eligibility context fence',blocked(w,b));b.write("commit;select 'ELIGIBILITY_RELEASED';");b.read('ELIGIBILITY_RELEASED');lines=w.read('PARENT_CHANGED');case('parent change commits after eligibility transaction release',not any('ERROR:'in x for x in lines),lines)
   case('new eligibility rejects superseded parent revision',bool(denied(eligible('policy_documents',identity=newdoc,revision=v['revision']),'40001','runtime_control_conflict')))
  # Clock authority must be rechecked after an actual non-context head wait.
  sql(f"update collect_admin_access.email_approvals set expires_at=clock_timestamp()+interval '2 seconds'where user_id={q(f.UID)};")
  revision=rpc(get('brand_entities'),sid=u.SID2 if False else f.SID)['revision']
  b=session('eligibility_head_blocker');b.write("begin;select 1 from collect_security.runtime_control_heads where family='brand_entities'and identity="+j(identity_for('brand_entities'))+" for update;select 'HEAD_HELD';");b.read('HEAD_HELD')
  w=session('eligibility_expiry_waiter');w.write('begin;'+u.auth(f.UID,f.SID)+'select '+eligible('brand_entities',revision=revision)+";commit;select 'EXPIRY_DONE';");case('actual eligibility head wait observed',blocked(w,b));time.sleep(2.1);b.write("rollback;select 'HEAD_RELEASED';");b.read('HEAD_RELEASED');lines=w.read('EXPIRY_DONE');case('approval expiry after actual head wait denies instead of publishing stale observation',any('42501: runtime_control_permission_required'in x or '42501: runtime_control_session_required'in x for x in lines),lines);sql(f'update collect_admin_access.email_approvals set expires_at=null where user_id={q(f.UID)};')
  case('read-only eligibility and governed mutations preserve financial evidence',f.business_fingerprint(db)==financial)
  case('captured exact source inputs unchanged',all(sha(path.read_bytes())==result['source_sha256'][key]for key,path in sources.items()))
  result['status']='pass';result['completed_at']=now()
 except BaseException as e:result['status']='failed';result['failure']=str(e);result['completed_at']=now();save();raise
 finally:
  for x in sessions:
   try:x.close()
   except Exception:pass
  if target is not None:target.close();result['all_task_containers_removed']=result['target'].get('task_container_removed')is True
  save()
 print(json.dumps({'status':result['status'],'cases':len(result['cases']),'result':str(P/'result.json'),'all_task_containers_removed':result.get('all_task_containers_removed')}),flush=True)
if __name__=='__main__':main()
