#!/usr/bin/env python3
"""Private schema153 subset UAT for unattended policy preparation; no live services.

Auxiliary Python is captured before import and executed from those exact bytes.
Only a new network-none task container and a disposable database are written.
"""
import argparse, base64, datetime, hashlib, importlib.abc, importlib.util
import json, pathlib, sys, time, uuid
import jsonschema

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATION = ROOT/'supabase/migrations/20261001003338_unattended_operating_policy.sql'
SCHEMA = ROOT/'contracts/collect-unattended-operating-policy-v1.schema.json'
STAGES = [
 'supabase/migrations/20260930213000_operator_email_auth.sql',
 'supabase/migrations/20260930220527_operator_email_cutover_guard.sql',
 'supabase/migrations/20260930230100_receipt_backlog_events.sql',
 'supabase/migrations/20260930230200_admin_receipt_overview.sql',
 'supabase/migrations/20260930230300_admin_transaction_lifecycle.sql',
 'supabase/migrations/20260930211605_android_gateway_identity.sql',
 'supabase/migrations/20261001000100_operational_exception_inbox.sql',
 'supabase/migrations/20261001000300_admin_exception_reads.sql',
 'supabase/migrations/20261001000400_receipt_supervisor_identity.sql',
 'supabase/migrations/20261001000519_safe_unstarted_receipt_cancel.sql',
 str(MIGRATION.relative_to(ROOT)),
]
HELPERS = ['shadow_supervisor_uat', 'receipt_backlog_events_uat',
           'collect_admin_combined_upgrade_uat', 'collect_current_release_upgrade_uat']
RAW = '99770000-0000-4000-8000-000000060001'
PARSED = '99770000-0000-4000-8000-000000070001'
PAYMENT = '99770000-0000-4000-8000-000000050001'
UNLINKED = '99770000-0000-4000-8000-000000050002'

def sha(value): return hashlib.sha256(value).hexdigest()
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def quote(value): return "'"+str(value).replace("'", "''")+"'"
def ts(value): return datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
def check(value): assert value, value; return True

class CapturedHelpers(importlib.abc.MetaPathFinder, importlib.abc.Loader):
 def __init__(self, bodies): self.bodies = bodies
 def find_spec(self, fullname, path=None, target=None):
  if fullname in self.bodies: return importlib.util.spec_from_loader(fullname, self)
 def create_module(self, spec): return None
 def exec_module(self, module):
  body, path = self.bodies[module.__name__]
  module.__file__ = str(path)
  exec(compile(body, str(path), 'exec'), module.__dict__)

def validate(value, schema):
 jsonschema.Draft202012Validator(schema).validate(value)
 if 'checked_at'in value:
  at=ts(value['checked_at']);assert ts(value['sample_valid_until'])==at+datetime.timedelta(seconds=60)
  if 'configured_mode'in value:
   assert ts(value['initialized_at'])<=ts(value['updated_at'])<=at
   assert value['effective_mode']==('Paused'if value['emergency_stop']else value['configured_mode'])
   if value['configured_mode']=='Paused':assert value['emergency_stop']
   if value['last_change_request_id']is None:assert value['revision']==1 and value['configured_mode']=='Paused'and value['emergency_stop']
  elif value['status']=='recorded':
   assert value['receipt']['request_id']==value['request_id']and ts(value['receipt']['recorded_at'])<=at
   validate(value['receipt'],schema)
 if 'changed'in value:
  assert value['revision']==value['expected_revision']+int(value['changed'])
  assert value['changed']==(value['mode_before']!=value['mode_after']or value['emergency_stop_before']!=value['emergency_stop_after'])
  if value['mode_after']=='Paused':assert value['emergency_stop_after']
  if value['reason_code']=='operator_emergency_stop':assert value['emergency_stop_after']
  if value['reason_code']=='operator_clear_future_stop':assert not value['emergency_stop_after']
 return value

def main():
 global MIGRATION, SCHEMA, STAGES
 parser = argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--report-dir', required=True)
 parser.add_argument('--migration-path', type=pathlib.Path, default=MIGRATION)
 parser.add_argument('--schema-path', type=pathlib.Path, default=SCHEMA)
 args = parser.parse_args(); report = pathlib.Path(args.report_dir).resolve()
 MIGRATION, SCHEMA = args.migration_path.resolve(), args.schema_path.resolve()
 assert MIGRATION.is_relative_to(ROOT) and SCHEMA.is_relative_to(ROOT), 'Repository-local immutable source required'
 STAGES = [*STAGES[:-1], str(MIGRATION.relative_to(ROOT))]
 assert not report.exists(), 'Fresh evidence directory required'; report.mkdir(parents=True)
 evidence = {'kind': 'offline_unattended_policy_preparation_v1_schema153_subset', 'started_at': now(),
  'production_written': False, 'shared_database_written': False, 'source_rows_copied': False,
  'provider_called': False, 'sms_sent': False, 'signed_jwt_or_auth_provider_tested': False,
  'full_hosted_upgrade_tested_here': False, 'draft_preparation_only': MIGRATION.is_relative_to(ROOT/'.cache'), 'cases': []}
 def save(): (report/'result.json').write_text(json.dumps(evidence, indent=2)+'\n')
 def case(name, fn=True):
  result = fn() if callable(fn) else fn; assert result is not False, name
  evidence['cases'].append({'name': name, 'status': 'pass', 'detail': result})
  save(); print('PASS '+name, flush=True); return result
 helper_bodies = {name: ((ROOT/'scripts/tests'/(name+'.py')).read_bytes(), ROOT/'scripts/tests'/(name+'.py')) for name in HELPERS}
 (report/'executed-python').mkdir()
 for name, (body, path) in helper_bodies.items(): (report/'executed-python'/path.name).write_bytes(body)
 (report/'executed-python'/'unattended_operating_policy_uat.py').write_bytes(pathlib.Path(__file__).read_bytes())
 evidence['executed_helper_sha256'] = {str(path.relative_to(ROOT)): sha(body) for body, path in helper_bodies.values()}
 evidence['runner_sha256'] = sha(pathlib.Path(__file__).read_bytes())
 finder = CapturedHelpers(helper_bodies); sys.meta_path.insert(0, finder)
 import collect_admin_combined_upgrade_uat as fixture
 import collect_current_release_upgrade_uat as private
 u, f = fixture.u, fixture.foundation
 bodies = {path: (ROOT/path).read_bytes() for path in STAGES}
 (report/'executed-migrations').mkdir()
 for path, body in bodies.items(): (report/'executed-migrations'/pathlib.Path(path).name).write_bytes(body)
 schema_bytes = SCHEMA.read_bytes(); schema = json.loads(schema_bytes)
 jsonschema.Draft202012Validator.check_schema(schema)
 (report/'executed-migrations'/SCHEMA.name).write_bytes(schema_bytes)
 evidence['source_sha256'] = {p: sha(b) for p, b in bodies.items()}
 evidence['schema_sha256'] = sha(schema_bytes)
 sessions = []; made = False; target = None; db = 'collect_operating_policy_'+uuid.uuid4().hex[:12]
 try:
  target = private.Target(report, 'operating_policy', evidence.setdefault('target', {})); target.__enter__()
  u.CONTAINER = target.name; u.SQL_LOG = report/'queries.log'; u.CONCURRENCY_LOG = report/'concurrency.log'; f.RAW_QUERY_LOG = report/'queries.sql'
  dump = (fixture.BASELINE/'schema-only.sql').read_bytes(); acl = (fixture.BASELINE/'api-acl.sql').read_bytes()
  assert sha(dump) == fixture.DUMP_HASH and sha(acl) == fixture.ACL_HASH
  evidence['baseline'] = {'schema_sha256': sha(dump), 'acl_sha256': sha(acl), 'captured_migration_count': 153,
   'no_rows_copied': True, 'not_attested': 'Complete managed-host Auth/platform/source parity; this is the retained schema153 subset'}
  u.psql('postgres', 'create database '+db+' template template0;'); made = True
  restore = u.psql(db, 'create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+dump.decode()+acl.decode(), False)
  (report/'restore.log').write_text(restore.stdout+restore.stderr); assert restore.returncode == 0, restore.stderr[-4000:]
  f.seed(db)
  u.psql(db,"insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values('%s','%s','+250788971001',repeat('a',64),'mtn_momo');"%(f.GROUP,u.UID))
  # The retained capture is schema-only. Real predecessor app migrations seed
  # this existing permission; reproduce it before the navigation FK is added.
  u.psql(db, "insert into public.admin_permissions(name,description)values('payments.read','Synthetic existing predecessor permission')on conflict do nothing;")
  u.psql(db, "update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+f.service(f.payment_sql('99770000-0000-4000-8000-000000049999', amount=50))+"update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
  baseline = f.business_fingerprint(db); evidence['before_install'] = baseline
  for path, body in bodies.items():
   result = u.psql(db, body.decode(), False); (report/(pathlib.Path(path).stem+'.install.log')).write_text(result.stdout+result.stderr)
   assert result.returncode == 0, result.stderr[-4000:]
   case(path+' preserves nonempty financial/receipt records', f.business_fingerprint(db) == baseline)
  run_cases(db, case, evidence, report, u, f, schema, sessions)
  evidence['source_after_sha256'] = {p: sha((ROOT/p).read_bytes()) for p in STAGES}
  assert evidence['source_after_sha256'] == evidence['source_sha256'], 'Selected SQL source changed'
  assert sha(SCHEMA.read_bytes()) == evidence['schema_sha256'], 'Selected schema changed'
  evidence['helper_source_drift'] = [str(path.relative_to(ROOT)) for body, path in helper_bodies.values() if sha(path.read_bytes()) != sha(body)]
  case('executed auxiliary Python bytes remain stable after the run', not evidence['helper_source_drift'])
  case('executed runner bytes remain stable after the run', sha(pathlib.Path(__file__).read_bytes())==evidence['runner_sha256'])
  evidence['status'] = 'pass'
 except Exception as error: evidence['status'] = 'failed'; evidence['failure'] = str(error); save(); raise
 finally:
  for session in sessions:
   try: session.close()
   except Exception as error: evidence.setdefault('cleanup_errors', []).append(str(error))
  if made: evidence['isolated_database_removed'] = u.psql('postgres', 'drop database '+db+' with(force);', False).returncode == 0
  if target: target.close()
  u.SQL_LOG = None; u.CONCURRENCY_LOG = None; f.RAW_QUERY_LOG = None
  sys.meta_path.remove(finder); evidence['case_count'] = len(evidence['cases']); evidence['completed_at'] = now(); save()

def run_cases(db,case,evidence,report,u,f,schema,sessions):
 sql=lambda query:u.psql(db,query).stdout.strip()
 owner=lambda query,uid=u.UID,sid=u.SID:u.call(db,query,uid,sid)
 def retain(name,value):
  (report/('observed-'+name+'.json')).write_text(json.dumps(value,indent=2)+'\n');return value
 def fingerprint():
  result=f.business_fingerprint(db)
  tables=['public.feature_flags','collect_hybrid.sms_notification_claim_requests',
   'collect_hybrid.sms_notification_confirmations','collect_hybrid.receipt_business_events',
   'collect_hybrid.receipt_business_event_heads','collect_hybrid.receipt_monitor_acknowledgements',
   'collect_security.shadow_supervisor_runs','collect_security.shadow_supervisor_lease',
   'collect_security.shadow_supervisor_samples','collect_gateway.devices','collect_gateway.health_observations',
   'collect_gateway.dispatch_arms','collect_gateway.segment_callbacks','collect_supervisor.identities',
   'collect_supervisor.requests','collect_receipt_actions.revisions','collect_receipt_actions.cancellations']
  pieces=[]
  for table in tables:
   pieces.append("select %s name,count(*) n,encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n'order by to_jsonb(t)::text),''),'sha256'),'hex')h from %s t"%(quote(table),table))
  result['independent_boundaries']=json.loads(sql("select jsonb_object_agg(name,jsonb_build_object('rows',n,'sha256',h))from("+' union all '.join(pieces)+')s;'))
  return result
 def current(uid=u.UID,sid=u.SID):
  return validate(owner('select public.admin_get_unattended_operating_policy_v1()',uid,sid),schema)
 def query(request=None,revision=1,mode='Shadow',stop=False,reason='operator_reviewed_configuration'):
  return "select public.admin_configure_unattended_operating_policy_v1(%s,%d,%s,%s,%s)"%(quote(request or str(uuid.uuid4())),revision,quote(mode),'true'if stop else'false',quote(reason))
 def change(request=None,revision=1,mode='Shadow',stop=False,reason='operator_reviewed_configuration',uid=u.UID,sid=u.SID):
  return validate(owner(query(request,revision,mode,stop,reason),uid,sid),schema)
 def lookup(request,uid=u.UID,sid=u.SID):
  return validate(owner('select public.admin_get_unattended_policy_request_v1('+quote(request)+')',uid,sid),schema)
 def error(query,state='42501',reason=None,role='authenticated',uid=u.UID,sid=u.SID,mutation=''):
  before=fingerprint();claims=u.auth(uid,sid)if role=='authenticated'else'set local role '+role+';'
  r=u.psql(db,'begin;'+mutation+claims+query+';rollback;',False)
  assert r.returncode and state+':'in r.stderr and(reason is None or reason in r.stderr),r.stderr
  assert fingerprint()==before,'Refusal modified a business or independent boundary'
  return {'sqlstate':state,'reason':reason,'independent_evidence_unchanged':True}
 sql("insert into public.admin_permissions(name,description)values('admin_users.manage','Synthetic existing cutover permission')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select %s,name from public.admin_permissions on conflict do nothing;"%quote(f.ROLE))
 for uid,email in [(u.UID,'policy-owner@collect.example'),(u.OTHER,'policy-other@collect.example')]:
  sql("update auth.users set email=%s,email_confirmed_at=clock_timestamp()where id=%s;insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values(%s,%s,clock_timestamp()-interval '2 minutes','Synthetic verified policy owner');"%tuple(map(quote,[email,uid,uid,email])))
 owner("select public.admin_set_operator_email_mode_v1('Synthetic policy preparation email mode')")
 request=str(uuid.uuid4());qs=[('current','select public.admin_get_unattended_operating_policy_v1()'),('configure',query(request)),('lookup','select public.admin_get_unattended_policy_request_v1('+quote(request)+')')]
 case('private policy/request tables have RLS and no API grants',sql("select count(*)=6 and bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE')and not has_schema_privilege(r,'collect_automation','USAGE'))from pg_class c cross join unnest(array['anon','authenticated','service_role'])r where c.relnamespace='collect_automation'::regnamespace and c.relkind='r';")=='t')
 case('private helpers have no API execution',sql("select not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace='collect_automation'::regnamespace and has_function_privilege(r,p.oid,'EXECUTE')); ")=='t')
 case('three public policy RPCs grant only authenticated execution',sql("select count(*)=3 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')and not has_function_privilege('anon',p.oid,'EXECUTE')and not has_function_privilege('service_role',p.oid,'EXECUTE'))from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('admin_get_unattended_operating_policy_v1','admin_configure_unattended_operating_policy_v1','admin_get_unattended_policy_request_v1');")=='t')
 for role in ['anon','service_role']:
  for name,q in qs:case(role+' cannot execute '+name,lambda q=q,role=role:error(q,role=role))
 for label,mutation in [
  ('unverified email',"update auth.users set email_confirmed_at=null where id=%s;"%quote(u.UID)),
  ('wrong email',"update auth.users set email='changed@collect.example'where id=%s;"%quote(u.UID)),
  ('revoked email approval',"update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id=%s;"%quote(u.UID)),
  ('expired email approval',"update collect_admin_access.email_approvals set expires_at=clock_timestamp()-interval '1 second'where user_id=%s;"%quote(u.UID)),
  ('expired session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id=%s;"%quote(u.SID)),
  ('revoked grant',"update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=%s;"%quote(u.UID)),
  ('banned account',"update auth.users set banned_until=clock_timestamp()+interval '1 hour'where id=%s;"%quote(u.UID)),
  ('anonymous account',"update auth.users set is_anonymous=true where id=%s;"%quote(u.UID)),
  ('approval after current session',"update collect_admin_access.email_approvals set approved_at=clock_timestamp()+interval '1 second'where user_id=%s;"%quote(u.UID)),
  ('grant after current session',"update public.admin_user_roles set created_at=clock_timestamp()+interval '1 second'where user_id=%s;"%quote(u.UID))]:
  for name,q in qs:case(name+' refuses '+label,lambda q=q,mutation=mutation:error(q,mutation=mutation))
 for permission in ['notifications.read','system_health.read']:
  mutation="delete from public.admin_role_permissions where role_id=%s and permission_name=%s;"%(quote(f.ROLE),quote(permission))
  for name,q in qs:case(name+' refuses missing '+permission,lambda q=q,mutation=mutation:error(q,mutation=mutation))
 case('configuration independently requires manage permission',lambda:error(qs[1][1],mutation="delete from public.admin_role_permissions where role_id=%s and permission_name='notifications.manage';"%quote(f.ROLE)))
 case('phone-only transition owner cannot configure policy',lambda:error(qs[1][1],reason='operating_policy_current_email_owner_required',mutation="update collect_admin_access.operator_auth_policy set mode='transition'where id;delete from collect_admin_access.email_approvals where user_id=%s;update auth.users set email_confirmed_at=null where id=%s;"%(quote(u.UID),quote(u.UID))))
 for name,q in qs:case(name+' refuses stale transaction isolation',lambda q=q:error(q,'40001','operating_policy_snapshot_retry',mutation='set transaction isolation level repeatable read;'))
 for mode in ['Live-limited','Live']:case(mode+' refuses executable authority and preserves all sources',lambda mode=mode:error(query(mode=mode),'55000','OPERATING_POLICY_LIVE_AUTHORITY_PENDING'))
 for label,q in [('null request',"select public.admin_configure_unattended_operating_policy_v1(null,1,'Shadow',false,'operator_reviewed_configuration')"),('null lookup','select public.admin_get_unattended_policy_request_v1(null)'),('zero revision',query(revision=0)),('revision overflow',query(revision=1000000001)),('unknown mode',query(mode='Automatic')),('Paused without stop',query(mode='Paused')),('unknown reason',query(reason='resume_carrier')),('false emergency reason',query(reason='operator_emergency_stop')),('contradictory clear reason',query(stop=True,reason='operator_clear_future_stop'))]:case(label+' intent is invalid',lambda q=q:error(q,'22023','operating_policy_input_invalid'))
 before=fingerprint();default=retain('default-current',current());policy=default['policy_id']
 case('server default is Paused/stopped with no fabricated owner action',default['configured_mode']=='Paused'and default['effective_mode']=='Paused'and default['emergency_stop']and default['revision']==1 and default['last_change_request_id']is None)
 case('requested modes/limits/schedule/approvals are truthful and unavailable',len(default['modes'])==5 and all(v is None for k,v in default['limits'].items()if k not in('enforcement','unavailable_reason'))and not default['limits']['enforcement']and all(v is None for k,v in default['schedule'].items()if k not in('configuration_available','unavailable_reason'))and not default['execution']['unattended_dispatch_available'])
 case('default read does not alter any business or independent boundary',fingerprint()==before)
 receipt=retain('shadow-preference-receipt',change(request));case('reviewed Shadow preference advances1→2 without granting execution',receipt['revision']==2 and receipt['changed']and receipt['mode_after']=='Shadow'and not receipt['unattended_dispatch_available'])
 record=retain('recorded-lookup',lookup(request));case('original request lookup binds exact immutable receipt',record['receipt']==receipt)
 case('same original actor/input UUID replay is identical',change(request)==receipt)
 case('policy changes preserve backlog finance assisted flag events principal and gateway evidence',fingerprint()==before)
 case('another current owner cannot see original action receipt',lookup(request,u.OTHER,u.OTHERSID)['status']=='not_recorded')
 case('another actor cannot reuse original request UUID',lambda:error(query(request),'22023','operating_policy_request_conflict',uid=u.OTHER,sid=u.OTHERSID))
 case('changed original UUID intent is refused',lambda:error(query(request,mode='Dry-run'),'22023','operating_policy_request_conflict'))
 case('stale expected revision is refused',lambda:error(query(),'55000','operating_policy_source_changed'))
 noop_request=str(uuid.uuid4());before_row=sql('select to_jsonb(p)from collect_automation.operating_policy p;');noop=retain('no-op-receipt',change(noop_request,2));case('new no-op intent records a receipt without rewriting the policy head',not noop['changed']and noop['revision']==2 and before_row==sql('select to_jsonb(p)from collect_automation.operating_policy p;'))
 dry=retain('dry-run-preference-receipt',change(revision=2,mode='Dry-run'));case('Dry-run is a stored preference with every external authority closed',dry['revision']==3 and current()['effective_mode']=='Dry-run'and fingerprint()==before)
 stopped=retain('shadow-stopped-receipt',change(revision=3,mode='Shadow',stop=True,reason='operator_emergency_stop'));view=retain('stopped-current',current());case('configured Shadow plus stop has effective Paused without altering assisted dispatch',stopped['revision']==4 and view['configured_mode']=='Shadow'and view['effective_mode']=='Paused'and view['boundaries']['assisted_dispatch']=='paused'and fingerprint()==before)
 cleared=retain('clear-future-stop-receipt',change(revision=4,mode='Shadow',reason='operator_clear_future_stop'));case('clearing stop records only a future preference with no execution grant',cleared['revision']==5 and current()['effective_mode']=='Shadow'and fingerprint()==before)
 paused=retain('paused-receipt',change(revision=5,mode='Paused',stop=True,reason='operator_emergency_stop'));case('Paused is stopped and preserves pending receipt backlog',paused['revision']==6 and current()['emergency_stop']and fingerprint()==before)
 for table in ['operating_policy','policy_requests']:case('authenticated cannot read private '+table,lambda table=table:error('select * from collect_automation.'+table))
 case('request evidence cannot be rewritten',lambda:error('update collect_automation.policy_requests set reason_code=\'operator_emergency_stop\'where request_id='+quote(request),'55000','operating_policy_evidence_retained',role='postgres'))
 case('request evidence cannot be deleted',lambda:error('delete from collect_automation.policy_requests where request_id='+quote(request),'55000','operating_policy_evidence_retained',role='postgres'))
 case('singleton policy cannot be deleted',lambda:error('delete from collect_automation.operating_policy','55000','operating_policy_revision_invalid',role='postgres'))
 case('physical policy revision cannot be decremented',lambda:error('update collect_automation.operating_policy set revision=1','55000','operating_policy_revision_invalid',role='postgres'))
 # Read the actual assisted flag independently, in rollback-only fixtures.
 value=json.loads(sql("begin;update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+u.auth()+'select public.admin_get_unattended_operating_policy_v1();rollback;').splitlines()[-1]);validate(value,schema)
 case('enabled assisted flag is exposed separately while unattended authority stays closed',value['boundaries']['assisted_dispatch']=='enabled'and not value['execution']['unattended_dispatch_available']and value['configured_mode']=='Paused')
 value=json.loads(sql("begin;delete from public.feature_flags where key='hybrid_sms_notifications';"+u.auth()+'select public.admin_get_unattended_operating_policy_v1();rollback;').splitlines()[-1]);validate(value,schema)
 case('missing assisted flag is unavailable rather than invented paused proof',value['boundaries']['assisted_dispatch']=='unavailable')
 concurrency(db,case,report,u,sql,query,current,lookup,error,sessions)
 # Cap fault injection is rollback-only; the public API has no cap setter.
 mutation="alter table collect_automation.operating_policy disable trigger protect_operating_policy;update collect_automation.operating_policy set revision=1000000000;alter table collect_automation.operating_policy enable trigger protect_operating_policy;"
 case('revision exhaustion refuses a change without overflow',lambda:error(query(revision=1000000000,mode='Shadow'),'55000','operating_policy_revision_exhausted',mutation=mutation))
 new_sid=str(uuid.uuid4());sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');delete from auth.sessions where id=%s;"%(quote(new_sid),quote(u.UID),quote(u.SID)))
 recovered=retain('reauthenticated-lookup',lookup(request,sid=new_sid));case('original actor can reconcile durable evidence after session deletion',recovered['receipt']==receipt)
 case('new current session replays original immutable intent without changing policy',change(request,sid=new_sid)==receipt and fingerprint()==before)
 evidence['final_independent_fingerprint']=fingerprint()

def concurrency(db,case,report,u,sql,query,current,lookup,error,sessions):
 def session(name):
  s=u.Session(db,name);sessions.append(s);s.write('set application_name='+quote(name)+';');return s
 def waited(name):
  end=time.monotonic()+8
  while time.monotonic()<end:
   if sql("select exists(select 1 from pg_stat_activity where application_name=%s and wait_event_type='Lock');"%quote(name))=='t':return True
   time.sleep(.02)
  raise AssertionError('No actual policy/authority lock wait: '+name)
 revision=current()['revision'];req=str(uuid.uuid4());holder=session('policy_configuration_holder');holder.write('begin;'+u.auth()+query(req,revision,'Shadow')+";select 'POLICY_CHANGED_HELD';")
 lines=holder.read('POLICY_CHANGED_HELD');receipt=json.loads(next(line for line in lines if line.startswith('{')and'"action"'in line))
 case('actual uncommitted policy mutation holds immutable evidence and authority',receipt['revision']==revision+1)
 case('current view has bounded busy refusal behind actual held authority',lambda:error('select public.admin_get_unattended_operating_policy_v1()','55P03','operating_policy_authority_busy'))
 case('uncertain request lookup has no disclosure before current authority',lambda:error('select public.admin_get_unattended_policy_request_v1('+quote(req)+')','55P03','operating_policy_authority_busy'))
 waiter=session('policy_competing_configuration');waiter.write('begin;'+u.auth()+query(revision=revision,mode='Dry-run')+";commit;select 'POLICY_WAITER_FINISHED';")
 case('competing current-owner changes serialize on real authority/policy locks',waited('policy_competing_configuration'))
 holder.write("commit;select 'POLICY_HOLDER_COMMITTED';");holder.read('POLICY_HOLDER_COMMITTED');lines=waiter.read('POLICY_WAITER_FINISHED');assert any('55000:'in line and'operating_policy_source_changed'in line for line in lines),lines
 case('stale concurrent change is refused after successful original commit',lookup(req)['receipt']==receipt and current()['revision']==revision+1)
 target=str(uuid.uuid4());holder=session('policy_synthetic_request_lock');holder.write("begin;select pg_advisory_xact_lock(hashtextextended('collect-operating-policy-request:'||%s,0));select 'POLICY_REQUEST_LOCKED';"%quote(target));holder.read('POLICY_REQUEST_LOCKED')
 progress=lookup(target);(report/'observed-in-progress-lookup.json').write_text(json.dumps(progress,indent=2)+'\n');case('synthetic request-only contention is in_progress after authority',progress['status']=='in_progress'and progress['receipt']is None)
 holder.write("rollback;select 'POLICY_REQUEST_RELEASED';");holder.read('POLICY_REQUEST_RELEASED');absent=lookup(target);(report/'observed-not-recorded-lookup.json').write_text(json.dumps(absent,indent=2)+'\n');case('manual unknown request never invents approval or execution',absent['status']=='not_recorded'and absent['receipt']is None)

if __name__=='__main__':main()
