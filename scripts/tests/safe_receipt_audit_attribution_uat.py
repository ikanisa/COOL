#!/usr/bin/env python3
"""Private schema153 subset UAT for additive cancellation public-audit attribution; no live services.

Auxiliary Python is captured before import and executed from those exact bytes.
Only a new network-none task container and a disposable database are written.
"""
import argparse, base64, datetime, hashlib, importlib.abc, importlib.util
import json, pathlib, sys, time, uuid
import jsonschema

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATION = ROOT/'supabase/migrations/20261001004651_receipt_cancel_audit_actor.sql'
SCHEMA = ROOT/'contracts/collect-safe-receipt-action-v1.schema.json'
STAGES = [
 'supabase/migrations/20260930213000_operator_email_auth.sql',
 'supabase/migrations/20260930220527_operator_email_cutover_guard.sql',
 'supabase/migrations/20260930230100_receipt_backlog_events.sql',
 'supabase/migrations/20260930230200_admin_receipt_overview.sql',
 'supabase/migrations/20260930230300_admin_transaction_lifecycle.sql',
 'supabase/migrations/20260930211605_android_gateway_identity.sql',
 'supabase/migrations/20261001000100_operational_exception_inbox.sql',
 'supabase/migrations/20261001000300_admin_exception_reads.sql',
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
 if 'checked_at' in value:
  checked=ts(value['checked_at']);assert ts(value['sample_valid_until'])==checked+datetime.timedelta(seconds=60)
  if value['status']=='recorded':assert value['receipt']['request_id']==value['request_id'] and ts(value['receipt']['recorded_at'])<=checked
 if 'state_before'in value:assert value['revision']==value['expected_revision']+1
 if 'receipt'in value and value['receipt']and 'can_cancel'in value['receipt']:
  row=value['receipt'];assert row['outbox_id']==value['outbox_id'] and row['can_cancel']==(row['reason_code']=='eligible')
  if row['can_cancel']:assert row['state']=='queued'and row['revision']<1000000000
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
 evidence = {'kind': 'offline_safe_receipt_audit_attribution_schema153_subset', 'started_at': now(),
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
 (report/'executed-python'/'safe_receipt_audit_attribution_uat.py').write_bytes(pathlib.Path(__file__).read_bytes())
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
 sessions = []; made = False; target = None; db = 'collect_receipt_audit_actor_'+uuid.uuid4().hex[:12]
 try:
  target = private.Target(report, 'receipt_audit_actor', evidence.setdefault('target', {})); target.__enter__()
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
   attribution=path==str(MIGRATION.relative_to(ROOT))
   routine="'public.admin_cancel_unstarted_receipt_v1(uuid,uuid,bigint,text)'::regprocedure"
   if attribution:
    definition=u.psql(db,'select pg_get_functiondef('+routine+');').stdout
    attributes=u.psql(db,'select jsonb_build_object(\'oid\',oid,\'volatility\',provolatile,\'security_definer\',prosecdef,\'configuration\',proconfig,\'acl\',proacl)from pg_proc where oid='+routine+';').stdout
    (report/'before-cancel-function.sql').write_text(definition)
   result = u.psql(db, body.decode(), False); (report/(pathlib.Path(path).stem+'.install.log')).write_text(result.stdout+result.stderr)
   assert result.returncode == 0, result.stderr[-4000:]
   case(path+' preserves nonempty financial/receipt records', f.business_fingerprint(db) == baseline)
   if attribution:
    after=u.psql(db,'select pg_get_functiondef('+routine+');').stdout
    (report/'after-cancel-function.sql').write_text(after)
    needle="'reason_code',p_reason_code,'financial_action',false,'send_action',false),null);"
    replacement=needle.replace(',null);',',auth.uid());')
    case('installed cancellation definition differs only by public audit actor',definition.count(needle)==1 and after==definition.replace(needle,replacement))
    case('additive recreation preserves function OID authority configuration and grants',attributes==u.psql(db,'select jsonb_build_object(\'oid\',oid,\'volatility\',provolatile,\'security_definer\',prosecdef,\'configuration\',proconfig,\'acl\',proacl)from pg_proc where oid='+routine+';').stdout)
    evidence['function_delta']={'before_definition_sha256':sha(definition.encode()),'after_definition_sha256':sha(after.encode()),'allowed_change':'create_audit_log actor null becomes auth.uid()','oid_authority_configuration_acl_unchanged':True}
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

def run_cases(db, case, evidence, report, u, f, schema, sessions):
 sql=lambda query:u.psql(db,query).stdout.strip()
 truth=lambda query:sql(query)=='t'
 owner=lambda query,uid=u.UID,sid=u.SID:u.call(db,query,uid,sid)
 def retain(name,value):
  (report/('observed-'+name+'.json')).write_text(json.dumps(value,indent=2)+'\n');return value
 def full():
  result=f.business_fingerprint(db)
  for table in ['sms_notification_claim_requests','sms_notification_confirmations']:
   result[table]=json.loads(sql("select jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n'order by to_jsonb(t)::text),''),'sha256'),'hex'))from collect_hybrid.%s t;"%table))
  return result
 def audit_hash():
  return sql("select encode(extensions.digest(coalesce(string_agg(to_jsonb(a)::text,E'\\n'order by to_jsonb(a)::text),''),'sha256'),'hex')from public.audit_logs a where action='notification.sms.cancelled_unstarted';")
 def preserved():
  result=full();result.pop('sms_outbox')
  result['outbox_immutable_core']=json.loads(sql("select jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(coalesce(string_agg((to_jsonb(t)-array['state','suppression_reason','updated_at'])::text,E'\\n'order by id),''),'sha256'),'hex'))from collect_hybrid.sms_notification_outbox t;"))
  return result
 def inspect(job,uid=u.UID,sid=u.SID):
  value=owner('select public.admin_inspect_unstarted_receipt_v1('+quote(job)+')',uid,sid)
  validate(value,schema);assert value['outbox_id']==job;return value
 def cancel(job,revision=1,request=None,reason='operator_cancelled',uid=u.UID,sid=u.SID):
  request=request or str(uuid.uuid4())
  value=owner('select public.admin_cancel_unstarted_receipt_v1(%s,%s,%d,%s)'%(quote(request),quote(job),revision,quote(reason)),uid,sid)
  validate(value,schema);assert value['request_id']==request and value['outbox_id']==job;return value
 def lookup(request,uid=u.UID,sid=u.SID):
  value=owner('select public.admin_get_unstarted_receipt_action_v1('+quote(request)+')',uid,sid)
  validate(value,schema);assert value['request_id']==request;return value
 def error(query,state='42501',reason=None,uid=u.UID,sid=u.SID,role='authenticated',mutation=''):
  before=full();audit_before=audit_hash()
  claims=u.auth(uid,sid)if role=='authenticated'else "set local role "+role+";select set_config('request.jwt.claims','{\"role\":\""+role+"\"}',true);"
  r=u.psql(db,'begin;'+mutation+claims+query+';rollback;',False)
  assert r.returncode and state+':'in r.stderr and(reason is None or reason in r.stderr),r.stderr
  assert full()==before,'Refusal changed financial/receipt/transport evidence'
  assert audit_hash()==audit_before,'Refusal modified public cancellation audit evidence'
  return {'sqlstate':state,'reason':reason,'source_evidence_unchanged':True,'public_audit_unchanged':True}
 count=0
 def post(receiver=None,parsed=None):
  nonlocal count;count+=1;pid='99760000-0000-4000-8000-%012d'%(50000+count)
  query=f.payment_sql(pid,amount=100,parsed=parsed)
  if receiver:query=query.replace(quote(u.UID)+",repeat('a',64)",quote(receiver)+",repeat('a',64)")
  sql(f.service(query));return json.loads(sql("select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id=%s;"%quote(pid)))
 def query(job,revision=1,request=None,reason='operator_cancelled'):
  return 'select public.admin_cancel_unstarted_receipt_v1(%s,%s,%d,%s)'%(quote(request or str(uuid.uuid4())),quote(job),revision,quote(reason))
 sql("insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('admin_users.manage','Synthetic email-cutover fixture')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select '%s',name from public.admin_permissions on conflict do nothing;"%f.ROLE)
 for uid,email in [(u.UID,'receipt-owner@collect.example'),(u.OTHER,'receipt-other@collect.example')]:
  sql("update auth.users set email=%s,email_confirmed_at=clock_timestamp()where id=%s;insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values(%s,%s,clock_timestamp()-interval '2 minutes','Synthetic verified email owner');"%tuple(map(quote,[email,uid,uid,email])))
 owner("select public.admin_set_operator_email_mode_v1('Synthetic safe cancellation email mode')")
 prior=json.loads(sql("select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id='99770000-0000-4000-8000-000000049999';"))
 job=prior['id'];request=str(uuid.uuid4());baseline=full()
 case('install does not backfill revision heads or cancellation evidence',truth('select not exists(select 1 from collect_receipt_actions.revisions)and not exists(select 1 from collect_receipt_actions.cancellations);'))
 case('private schema and tables have no API grants with RLS enabled',truth("select count(*)=6 and bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE')and not has_schema_privilege(r,'collect_receipt_actions','USAGE'))from pg_class c cross join unnest(array['anon','authenticated','service_role'])r where c.relnamespace='collect_receipt_actions'::regnamespace and c.relkind='r';"))
 case('private helpers are unavailable to all API roles',truth("select not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace='collect_receipt_actions'::regnamespace and has_function_privilege(r,p.oid,'EXECUTE'));"))
 case('three public actions grant only authenticated execution',truth("select count(*)=3 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')and not has_function_privilege('anon',p.oid,'EXECUTE')and not has_function_privilege('service_role',p.oid,'EXECUTE'))from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('admin_inspect_unstarted_receipt_v1','admin_cancel_unstarted_receipt_v1','admin_get_unstarted_receipt_action_v1');"))
 read_query='select public.admin_inspect_unstarted_receipt_v1('+quote(job)+')'
 lookup_query='select public.admin_get_unstarted_receipt_action_v1('+quote(request)+')'
 mutation_query=query(job,request=request)
 for role in ['anon','service_role']:
  for label,q in [('inspect',read_query),('cancel',mutation_query),('lookup',lookup_query)]:case(role+' cannot execute '+label,lambda role=role,q=q:error(q,role=role))
 for label,change in [
  ('unverified email',"update auth.users set email_confirmed_at=null where id=%s;"%quote(u.UID)),
  ('wrong verified email',"update auth.users set email='changed@collect.example'where id=%s;"%quote(u.UID)),
  ('revoked email approval',"update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id=%s;"%quote(u.UID)),
  ('expired email approval',"update collect_admin_access.email_approvals set expires_at=clock_timestamp()-interval '1 second'where user_id=%s;"%quote(u.UID)),
  ('revoked role grant',"update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=%s;"%quote(u.UID)),
  ('expired session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id=%s;"%quote(u.SID)),
  ('banned account',"update auth.users set banned_until=clock_timestamp()+interval '1 hour'where id=%s;"%quote(u.UID)),
  ('anonymous account',"update auth.users set is_anonymous=true where id=%s;"%quote(u.UID)),
  ('approval after current session',"update collect_admin_access.email_approvals set approved_at=clock_timestamp()+interval '1 second'where user_id=%s;"%quote(u.UID)),
  ('grant after current session',"update public.admin_user_roles set created_at=clock_timestamp()+interval '1 second'where user_id=%s;"%quote(u.UID)),
 ]:
  for name,q in [('inspect',read_query),('cancel',mutation_query),('lookup',lookup_query)]:case(name+' refuses '+label,lambda q=q,change=change:error(q,mutation=change))
 for permission in ['payments.read','notifications.read','system_health.read']:
  change="delete from public.admin_role_permissions where role_id=%s and permission_name=%s;"%(quote(f.ROLE),quote(permission))
  for name,q in [('inspect',read_query),('cancel',mutation_query),('lookup',lookup_query)]:case(name+' refuses missing '+permission,lambda q=q,change=change:error(q,mutation=change))
 case('cancel independently requires notifications.manage',lambda:error(mutation_query,mutation="delete from public.admin_role_permissions where role_id=%s and permission_name='notifications.manage';"%quote(f.ROLE)))
 case('phone-only transition owner cannot use new actions',lambda:error(read_query,mutation="update collect_admin_access.operator_auth_policy set mode='transition'where id;delete from collect_admin_access.email_approvals where user_id=%s;update auth.users set email_confirmed_at=null where id=%s;"%(quote(u.UID),quote(u.UID)),reason='receipt_action_current_email_owner_required'))
 for name,q in [('inspect',read_query),('cancel',mutation_query),('lookup',lookup_query)]:
  case(name+' refuses stale Repeatable Read snapshot',lambda q=q:error(q,state='40001',reason='receipt_action_snapshot_retry',mutation='set transaction isolation level repeatable read;'))
 for label,q in [('null inspect','select public.admin_inspect_unstarted_receipt_v1(null)'),('null lookup','select public.admin_get_unstarted_receipt_action_v1(null)'),('null request','select public.admin_cancel_unstarted_receipt_v1(null,%s,1,\'operator_cancelled\')'%quote(job)),('null job','select public.admin_cancel_unstarted_receipt_v1(%s,null,1,\'operator_cancelled\')'%quote(str(uuid.uuid4()))),('zero revision',query(job,0)),('exhausted expected revision',query(job,1000000000)),('unknown reason',query(job,reason='resend')),('blank reason',query(job,reason='   '))]:case(label+' input is refused',lambda q=q:error(q,'22023','receipt_action_input_invalid'))
 eligible=retain('preexisting-eligible-inspection',inspect(job))
 case('preexisting pristine receipt has implicit revision1 and positive eligibility',eligible['status']=='available'and eligible['receipt']['revision']==1 and eligible['receipt']['can_cancel'])
 case('read-only inspect does not create heads or change source evidence',full()==baseline and truth('select not exists(select 1 from collect_receipt_actions.revisions);'))
 missing=retain('unavailable-inspection',inspect(str(uuid.uuid4())))
 case('missing receipt has no fabricated state/revision/eligibility',missing['status']=='unavailable'and missing['receipt']is None)
 before=preserved();first=retain('cancelled-action',cancel(job,request=request))
 case('new public cancellation audit records the actual executing owner',truth("select count(*)=1 and bool_and(actor_user_id=%s and entity_id=%s and metadata->>'request_id'=%s)from public.audit_logs where action='notification.sms.cancelled_unstarted';"%(quote(u.UID),quote(job),quote(request))))
 case('manual cancel preserves all immutable financial/payload/transport evidence',preserved()==before)
 case('first preexisting UPDATE advances1→2 and preserves original primary row',first['expected_revision']==1 and first['revision']==2 and truth("select state='suppressed'and suppression_reason='manual_pre_send_cancel'and attempt_count=0 and fence_version=0 from collect_hybrid.sms_notification_outbox where id=%s;"%quote(job)))
 cancelled=retain('cancelled-inspection',inspect(job));case('cancelled receipt is terminal and clearly ineligible',cancelled['receipt']['reason_code']=='already_cancelled'and not cancelled['receipt']['can_cancel'])
 record=retain('recorded-lookup',lookup(request));case('original UUID lookup binds immutable acknowledged result',record['receipt']==first)
 replay_before=full();replay_audit=audit_hash();case('same original actor/input UUID replay returns byte-equivalent receipt',cancel(job,request=request)==first and full()==replay_before)
 case('original UUID replay leaves public audit evidence unchanged',audit_hash()==replay_audit)
 case('different owner lookup cannot disclose original actor action',lookup(request,u.OTHER,u.OTHERSID)['status']=='not_recorded')
 case('different owner cannot reuse original action UUID',lambda:error(query(job,request=request),state='22023',reason='receipt_action_request_conflict',uid=u.OTHER,sid=u.OTHERSID))
 case('original UUID changed reason conflicts without source mutation',lambda:error(query(job,request=request,reason='recipient_review_required'),state='22023',reason='receipt_action_request_conflict'))
 case('fresh UUID cannot cancel the already suppressed receipt',lambda:error(query(job,2),state='55000',reason='receipt_not_cancellable'))
 for table in ['revisions','cancellations']:
  case('authenticated has no direct '+table+' read',lambda table=table:error('select * from collect_receipt_actions.'+table))
 case('immutable action cannot be rewritten',lambda:error('update collect_receipt_actions.cancellations set reason_code=\'recipient_review_required\'where request_id='+quote(request),state='55000',reason='receipt_action_evidence_retained',role='postgres'))
 case('immutable action cannot be deleted',lambda:error('delete from collect_receipt_actions.cancellations where request_id='+quote(request),state='55000',reason='receipt_action_evidence_retained',role='postgres'))
 case('cancelled primary cannot be returned to the queue',lambda:error("update collect_hybrid.sms_notification_outbox set state='queued'where id="+quote(job),state='55000',reason='receipt_manual_cancellation_final',role='postgres'))
 case('cancelled primary cannot be deleted',lambda:error('delete from collect_hybrid.sms_notification_outbox where id='+quote(job),state='P0001',reason='SMS notification evidence is retained',role='postgres'))
 case('lifetime primary identity still rejects duplicate retained receipt',lambda:error("insert into collect_hybrid.sms_notification_outbox select(jsonb_populate_record(null::collect_hybrid.sms_notification_outbox,to_jsonb(o)||jsonb_build_object('id',gen_random_uuid()))).*from collect_hybrid.sms_notification_outbox o where id="+quote(job),state='23505',role='postgres'))
 secondary=post();secondary_request=str(uuid.uuid4());secondary_action=cancel(secondary['id'],request=secondary_request,uid=u.OTHER,sid=u.OTHERSID)
 case('another authorized executing owner is attributed without borrowing original actor',truth("select count(*)=1 and bool_and(actor_user_id=%s)from public.audit_logs where action='notification.sms.cancelled_unstarted'and metadata->>'request_id'=%s;"%(quote(u.OTHER),quote(secondary_request)))and truth("select actor_id=%s and session_id=%s from collect_receipt_actions.cancellations where request_id=%s;"%(quote(u.OTHER),quote(u.OTHERSID),quote(secondary_request))))
 provisional=post();provisional_request=str(uuid.uuid4());before=full();audit_before=audit_hash();head_before=sql('select to_jsonb(r)from collect_receipt_actions.revisions r where outbox_id='+quote(provisional['id'])+';')
 returned=json.loads(sql('begin;'+u.auth()+query(provisional['id'],request=provisional_request)+';rollback;').splitlines()[-1]);validate(returned,schema)
 (report/'observed-rolled-back-provisional-receipt.json').write_text(json.dumps(returned,indent=2)+'\n')
 case('caller rollback removes cancellation audit action and revision atomically',full()==before and audit_hash()==audit_before and sql('select to_jsonb(r)from collect_receipt_actions.revisions r where outbox_id='+quote(provisional['id'])+';')==head_before and truth('select not exists(select 1 from collect_receipt_actions.cancellations where request_id='+quote(provisional_request)+');'))
 fresh=post();case('new pending receipt starts physical revision1 under paused dispatch',inspect(fresh['id'])['receipt']['revision']==1 and truth("select not enabled from public.feature_flags where key='hybrid_sms_notifications';"))
 unknown=post(receiver=u.OTHER);value=retain('unclassified-inspection',inspect(unknown['id']));case('unclassified receiving source does not expose row state',value['status']=='unavailable'and value['receipt']is None)
 case('unclassified receiving source cannot be cancelled',lambda:error(query(unknown['id']),state='55000',reason='receipt_action_unavailable'))
 sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values('%s','%s','%s','M-Money','Protected synthetic canonical receipt',repeat('e',64),repeat('a',64),'parsed');insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,direction,currency,receiver_phone_hash,allocation_status)values('%s','%s','%s','%s',true,'mtn_momo','incoming','RWF',repeat('a',64),'allocated');"%(RAW,f.GROUP,u.UID,PARSED,RAW,f.GROUP,u.UID))
 linked=post(parsed=PARSED);linked_view=retain('linked-rwanda-inspection',inspect(linked['id']))
 case('actual linked Rwanda raw/parsed payment is positively scoped',linked_view['receipt']['can_cancel'])
 for label,fields in [('outgoing',"direction='outgoing'"),('nonpayment','is_mobile_money_payment=false'),('receiving provider conflict',"network='airtel_money'"),('receiving hash conflict',"receiver_phone_hash=repeat('b',64)"),('receiving user conflict',"receiver_user_id="+quote(u.OTHER))]:
  mutation="update public.parsed_payment_events set %s where id=%s;"%(fields,quote(PARSED))
  value=json.loads(sql('begin;'+mutation+u.auth()+'select public.admin_inspect_unstarted_receipt_v1('+quote(linked['id'])+');rollback;').splitlines()[-1]);validate(value,schema)
  case('linked '+label+' exposes no guessed Rwanda receipt state',value['status']=='unavailable'and value['receipt']is None)
  case('linked '+label+' cancellation is refused despite a valid receiving route',lambda mutation=mutation:error(query(linked['id']),state='55000',reason='receipt_action_unavailable',mutation=mutation))
 for state in ['awaiting_confirmation','send_started','uncertain','observed_sent','failed_no_send','suppressed']:
  other=post();change="update public.feature_flags set enabled=true where key='hybrid_sms_notifications';update collect_hybrid.sms_notification_outbox set state=%s,claim_token=gen_random_uuid(),claimed_by='synthetic-previous-worker',claim_expires_at=clock_timestamp()+interval '5 minutes'%s where id=%s;"%(quote(state),",suppression_reason='Synthetic prior terminal suppression'"if state=='suppressed'else '',quote(other['id']))
  case('cancel refuses '+state+' state with no retry or reset',lambda other=other,change=change:error(query(other['id'],2),state='55000',reason='receipt_not_cancellable',mutation=change))
 for label,change in [('fence history',"fence_version=1"),('nonzero attempt count',"attempt_count=1"),('stray claim token',"claim_token=gen_random_uuid()"),('stray worker identity',"claimed_by='synthetic-old-worker'"),('stray claim expiry',"claim_expires_at=clock_timestamp()-interval '1 minute'"),('sent timestamp',"observed_sent_at=clock_timestamp()")]:
  other=post();mutation="update collect_hybrid.sms_notification_outbox set %s where id=%s;"%(change,quote(other['id']))
  case('queued receipt with '+label+' is ambiguous and refused',lambda other=other,mutation=mutation:error(query(other['id'],2),state='55000',reason='receipt_not_cancellable',mutation=mutation))
 other=post();history="insert into collect_hybrid.sms_notification_claim_requests(request_id,operator_user_id,outbox_id,worker_id,result)values(gen_random_uuid(),%s,%s,'synthetic-prior-request','{}');"%(quote(u.UID),quote(other['id']))
 case('claim request history alone makes pristine-looking queue ineligible',lambda:error(query(other['id']),state='55000',reason='receipt_not_cancellable',mutation=history))
 other=post();history="insert into collect_hybrid.sms_notification_confirmations(id,outbox_id,operator_user_id,claim_token,fence_version,destination_revision,body_sha256,expires_at)values(gen_random_uuid(),%s,%s,gen_random_uuid(),1,1,%s,clock_timestamp()+interval '1 minute');"%(quote(other['id']),quote(u.UID),quote(other['body_sha256']))
 case('approval history alone makes pristine-looking queue ineligible',lambda:error(query(other['id']),state='55000',reason='receipt_not_cancellable',mutation=history))
 for label,field in [('corrupt body digest',"body_sha256=repeat('f',64)"),('corrupt destination digest',"destination_sha256=repeat('f',64)"),('ambiguous receipt reference',"reference='unsafe whitespace'")]:
  other=post();mutation="alter table collect_hybrid.sms_notification_outbox disable trigger protect_sms_outbox_core_trigger;update collect_hybrid.sms_notification_outbox set %s where id=%s;alter table collect_hybrid.sms_notification_outbox enable trigger protect_sms_outbox_core_trigger;"%(field,quote(other['id']))
  case(label+' is refused without accepting ambiguous snapshot evidence',lambda other=other,mutation=mutation:error(query(other['id'],2),state='55000',reason='receipt_not_cancellable',mutation=mutation))
 other=post();mutation="alter table collect_hybrid.sms_notification_outbox disable trigger protect_sms_outbox_core_trigger;update collect_hybrid.sms_notification_outbox set reference='OTHER-REF',message_body=collect_hybrid.render_buri_munsi_receipt(amount_rwf,member_balance_rwf,group_balance_rwf,'OTHER-REF'),body_sha256=encode(extensions.digest(collect_hybrid.render_buri_munsi_receipt(amount_rwf,member_balance_rwf,group_balance_rwf,'OTHER-REF'),'sha256'),'hex')where id=%s;alter table collect_hybrid.sms_notification_outbox enable trigger protect_sms_outbox_core_trigger;"%quote(other['id'])
 case('internally consistent body with mismatched payment reference is ineligible',lambda:error(query(other['id'],2),state='55000',reason='receipt_not_cancellable',mutation=mutation))
 other=post();case('expected revision detects even a no-op intervening outbox update',lambda:error(query(other['id']),state='55000',reason='receipt_action_source_changed',mutation="update collect_hybrid.sms_notification_outbox set state=state where id=%s;"%quote(other['id'])))
 other=post();sql("update collect_receipt_actions.revisions set revision=revision+1 where outbox_id=%s;"%quote(other['id']));case('physical revisions cannot be decremented',lambda:error("update collect_receipt_actions.revisions set revision=1 where outbox_id="+quote(other['id']),state='55000',reason='receipt_action_revision_invalid',role='postgres'))
 cap=post();sql("alter table collect_receipt_actions.revisions disable trigger monotonic_receipt_action_revision;update collect_receipt_actions.revisions set revision=1000000000 where outbox_id=%s;alter table collect_receipt_actions.revisions enable trigger monotonic_receipt_action_revision;"%quote(cap['id']))
 capped=retain('revision-exhausted-inspection',inspect(cap['id']));case('exhausted revision has explicit ineligible inspection',capped['receipt']['reason_code']=='revision_exhausted'and not capped['receipt']['can_cancel'])
 case('revision exhaustion rolls back a source UPDATE rather than overflowing',lambda:error("update collect_hybrid.sms_notification_outbox set state=state where id="+quote(cap['id']),state='55000',reason='receipt_action_revision_exhausted',role='postgres'))
 race_cases(db,case,report,u,f,sql,post,query,inspect,cancel,lookup,error,sessions)
 new_sid=str(uuid.uuid4());sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');delete from auth.sessions where id=%s;"%(quote(new_sid),quote(u.UID),quote(u.SID)))
 recovered=retain('reauthenticated-original-lookup',lookup(request,sid=new_sid));case('durable original receipt survives originating session deletion',recovered['receipt']==first)
 case('new current session can safely replay immutable original result',cancel(job,request=request,sid=new_sid)==first)
 case('all retained journals remain canonical balanced pairs',truth("select not exists(select 1 from collect_hybrid.momo_journal_entries j join collect_hybrid.momo_journal_lines l on l.journal_entry_id=j.id group by j.id having count(*)<>2 or sum(case when l.direction='debit'then l.amount_rwf else-l.amount_rwf end)<>0);"))
 case('no gateway arm or operator heartbeat is manufactured',truth('select not exists(select 1 from collect_gateway.dispatch_arms)and not exists(select 1 from collect_hybrid.sms_operator_heartbeats);'))
 evidence['final_source_fingerprint']=full()

def race_cases(db,case,report,u,f,sql,post,query,inspect,cancel,lookup,error,sessions):
 def session(name):
  value=u.Session(db,name);sessions.append(value);value.write("set application_name=%s;"%quote(name));return value
 def wait_lock(name):
  end=time.monotonic()+8
  while time.monotonic()<end:
   if sql("select exists(select 1 from pg_stat_activity where application_name=%s and wait_event_type='Lock');"%quote(name))=='t':return True
   time.sleep(.02)
  raise AssertionError('Actual lock wait not observed: '+name)
 def service_claim(job,request):return "select public.collect_claim_receipt(%s,%s,'safe-uat-worker',%s)"%(quote(u.UID),quote(job),quote(request))
 sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';")
 job=post();holder=session('safe_actual_claim_holder');holder.write("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"+service_claim(job['id'],str(uuid.uuid4()))+";select 'CLAIM_READY';")
 claim_lines=holder.read('CLAIM_READY');assert any('"ok": true'in line for line in claim_lines),claim_lines
 waiter=session('safe_cancel_after_claim');request=str(uuid.uuid4());waiter.write('begin;'+u.auth()+query(job['id'],request=request)+";commit;select 'CANCEL_FINISHED';")
 case('real assisted claim and cancellation serialize on actual outbox row',wait_lock('safe_cancel_after_claim'))
 case('held cancellation authority gives bounded lookup refusal without outcome disclosure',lambda:error('select public.admin_get_unstarted_receipt_action_v1('+quote(request)+')',state='55P03',reason='receipt_action_authority_busy'))
 holder.write("commit;select 'CLAIM_COMMITTED';");holder.read('CLAIM_COMMITTED')
 lines=waiter.read('CANCEL_FINISHED');assert any('55000:'in line and 'receipt_action_source_changed'in line for line in lines),lines
 case('claim winning race refuses stale cancellation and retains awaiting confirmation',inspect(job['id'])['receipt']['state']=='awaiting_confirmation')
 # Release through the actual assisted API, not a manufactured stale row.
 data=json.loads(sql('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where id='+quote(job['id'])+';'))
 sql(f.service("select public.collect_release_unsent_claim(%s,%s,%s,%d,'Synthetic real released claim');"%(quote(u.UID),quote(job['id']),quote(data['claim_token']),data['fence_version'])))
 released=inspect(job['id']);case('actual previously claimed/released queue is ineligible',released['receipt']['state']=='queued'and released['receipt']['reason_code']=='prior_transport_evidence')
 case('released queue cannot be cancelled under its current revision',lambda:error(query(job['id'],released['receipt']['revision']),state='55000',reason='receipt_not_cancellable'))
 job=post();holder=session('safe_actual_cancel_holder');request=str(uuid.uuid4());holder.write('begin;'+u.auth()+query(job['id'],request=request)+";select 'CANCEL_READY';")
 lines=holder.read('CANCEL_READY');receipt=json.loads(next(line for line in lines if line.startswith('{')and '"action"'in line));assert receipt['state_after']=='suppressed'
 waiter=session('safe_claim_after_cancel');waiter.write("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"+service_claim(job['id'],str(uuid.uuid4()))+";commit;select 'CLAIM_FINISHED';")
 case('actual claim waits behind committed-intent cancellation',wait_lock('safe_claim_after_cancel'))
 holder.write("commit;select 'CANCEL_COMMITTED';");holder.read('CANCEL_COMMITTED')
 lines=waiter.read('CLAIM_FINISHED');assert any('Notification job is not available to claim'in line for line in lines),lines
 case('cancellation winning race prevents claim and creates no transport attempt',inspect(job['id'])['receipt']['reason_code']=='already_cancelled'and sql('select not exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id='+quote(job['id'])+');')=='t')
 case('uncertain caller manually reconciles exact original UUID after commit',lookup(request)['receipt']==receipt)
 # Synthetic request-lock-only branch follows current authority, while an
 # actual mutation-held authority path above correctly reports only busy.
 target=str(uuid.uuid4());holder=session('safe_request_lock_only');holder.write("begin;select pg_advisory_xact_lock(hashtextextended('collect-receipt-cancel-request:'||%s,0));select 'REQUEST_LOCKED';"%quote(target));holder.read('REQUEST_LOCKED')
 progress=lookup(target);(report/'observed-in-progress-lookup.json').write_text(json.dumps(progress,indent=2)+'\n');case('request-lock branch returns in_progress with no receipt after authority',progress['status']=='in_progress'and progress['receipt']is None)
 holder.write("rollback;select 'REQUEST_RELEASED';");holder.read('REQUEST_RELEASED')
 absent=lookup(target);(report/'observed-not-recorded-lookup.json').write_text(json.dumps(absent,indent=2)+'\n');case('manual lookup after uncommitted request has no fabricated result',absent['status']=='not_recorded'and absent['receipt']is None)
 # Exercise the real assisted journal boundary, with no handset/provider call.
 job=post()
 def service_value(query):return json.loads(sql(f.service(query)).splitlines()[-1])
 claim=service_value(service_claim(job['id'],str(uuid.uuid4())))
 exact=service_value("select public.collect_get_claimed_receipt(%s,%s,%s,%d)"%(quote(u.UID),quote(job['id']),quote(claim['claim_token']),claim['fence_version']))
 confirmation=str(uuid.uuid4())
 approved=service_value("select public.collect_confirm_receipt(%s,%s,%s,%d,%d,%s,%s)"%(quote(u.UID),quote(job['id']),quote(claim['claim_token']),claim['fence_version'],exact['destination_revision'],quote(exact['body_sha256']),quote(confirmation)))
 attempt=service_value("select public.collect_record_send_start(%s,%s,%s,%d,%s)"%(quote(u.UID),quote(job['id']),quote(claim['claim_token']),claim['fence_version'],quote(confirmation)))
 outcome=service_value("select public.collect_record_observed_outcome(%s,%s,'failed_no_send','synthetic-safe-uat','Synthetic transport journal fixture; no carrier called')"%(quote(u.UID),quote(attempt['attempt_id'])))
 observed=inspect(job['id']);(report/'observed-prior-attempt-inspection.json').write_text(json.dumps(observed,indent=2)+'\n')
 case('real assisted confirmation/start/outcome leaves immutable failed_no_send evidence',approved['ok']and attempt['state']=='send_started'and outcome['state']=='failed_no_send'and observed['receipt']['state']=='failed_no_send')
 case('actual failed_no_send attempt is ineligible for cancellation',lambda:error(query(job['id'],observed['receipt']['revision']),state='55000',reason='receipt_not_cancellable'))
 before=observed['receipt']['revision']
 reset="update collect_hybrid.sms_notification_outbox set state='queued',fence_version=0,attempt_count=0,claim_token=null,claimed_by=null,claim_expires_at=null,observed_sent_at=null where id=%s;"%quote(job['id'])
 case('privileged-looking reopened queue cannot erase prior actual transport history',lambda:error(query(job['id'],before+1),state='55000',reason='receipt_not_cancellable',mutation=reset))
 # Natural expiry is clock-based even while authority rows remain SHARE-locked.
 job=post();sql("update auth.sessions set not_after=clock_timestamp()+interval '2 seconds'where id=%s;"%quote(u.SID))
 holder=session('safe_expiry_source_holder');holder.write('begin;select id from collect_hybrid.sms_notification_outbox where id='+quote(job['id'])+"for update;select 'EXPIRY_SOURCE_LOCKED';");holder.read('EXPIRY_SOURCE_LOCKED')
 waiter=session('safe_cancel_expiring_session');waiter.write('begin;'+u.auth()+query(job['id'])+";commit;select 'EXPIRING_CANCEL_FINISHED';")
 case('cancellation with a live session waits on actual locked source',wait_lock('safe_cancel_expiring_session'))
 end=time.monotonic()+6
 while time.monotonic()<end and sql('select not_after<=clock_timestamp()from auth.sessions where id='+quote(u.SID)+';')!='t':time.sleep(.05)
 assert sql('select not_after<=clock_timestamp()from auth.sessions where id='+quote(u.SID)+';')=='t','Session clock did not expire'
 holder.write("rollback;select 'EXPIRY_SOURCE_RELEASED';");holder.read('EXPIRY_SOURCE_RELEASED')
 lines=waiter.read('EXPIRING_CANCEL_FINISHED');assert any('42501:'in line for line in lines),lines
 case('natural session expiry after source wait refuses cancellation without a receipt',sql('select state=\'queued\'and not exists(select 1 from collect_receipt_actions.cancellations where outbox_id=o.id)from collect_hybrid.sms_notification_outbox o where id='+quote(job['id'])+';')=='t')
 sql("update auth.sessions set not_after=clock_timestamp()+interval '1 hour'where id=%s;"%quote(u.SID))
 sql("update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")

if __name__=='__main__':main()
