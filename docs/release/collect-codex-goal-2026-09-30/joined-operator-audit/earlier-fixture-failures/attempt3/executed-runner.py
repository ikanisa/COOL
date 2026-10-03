#!/usr/bin/env python3
"""Offline joined-audit UAT in a task-owned, networkless PostgreSQL target.

Schema-only inputs and exact helper bytes are captured before use. No hosted
URL, credential, source row, Auth HTTP service, physical device or sender runs.
"""
import argparse, base64, datetime, hashlib, importlib.abc, importlib.util
import json, pathlib, sys, uuid
import jsonschema

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT = ROOT/'.cache/joined-operator-audit-preparation/supabase/migrations/20261001001457_joined_operator_audit.sql'
SCHEMA = ROOT/'contracts/collect-operator-entity-audit-v1.schema.json'
EMAIL = '99810000-0000-4000-8000-000000000001'
SID = '99810000-0000-4000-8000-000000010001'
HELPERS = ['shadow_supervisor_uat', 'receipt_backlog_events_uat',
           'collect_admin_combined_upgrade_uat', 'collect_current_release_upgrade_uat',
           'android_gateway_identity_uat', 'operational_exception_inbox_uat']
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
]

def sha(body): return hashlib.sha256(body).hexdigest()
def utc(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def quote(value): return "'"+str(value).replace("'", "''")+"'"
def instant(value): return datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
def check(value): assert value, value; return True

class CapturedHelpers(importlib.abc.MetaPathFinder, importlib.abc.Loader):
 def __init__(self, bodies): self.bodies = bodies
 def find_spec(self, fullname, path=None, target=None):
  if fullname in self.bodies: return importlib.util.spec_from_loader(fullname, self)
 def create_module(self, spec): return None
 def exec_module(self, module):
  body, path = self.bodies[module.__name__]; module.__file__ = str(path)
  exec(compile(body, str(path), 'exec'), module.__dict__)

def validate(result, schema, kind, entity, limit, cursor=None):
 jsonschema.Draft202012Validator(schema, format_checker=jsonschema.FormatChecker()).validate(result)
 assert (result['entity_kind'], result['entity_id'], result['limit']) == (kind, entity, limit)
 at = instant(result['checked_at'])
 assert instant(result['sample_valid_until']) == at+datetime.timedelta(seconds=60)
 keys = [(instant(r['recorded_at']), r['event_id']) for r in result['rows']]
 assert keys == sorted(set(keys), reverse=True) and len(keys) <= limit
 assert all(k[0] <= at for k in keys)
 if cursor: assert all(k < (instant(cursor['recorded_at']), cursor['event_id']) for k in keys)
 if result['next_cursor']:
  assert len(keys) == limit and result['next_cursor'] == {
   'recorded_at': result['rows'][-1]['recorded_at'], 'event_id': result['rows'][-1]['event_id']}
 source = {'shadow_run':'shadow_audit_event','gateway_device':'gateway_admin_request',
           'supervisor_identity':'supervisor_owner_request','exception':'exception_action','receipt':'receipt_cancellation'}[kind]
 prefix = {'shadow_run':'shadow.','gateway_device':'gateway.','supervisor_identity':'supervisor.',
           'exception':'exception.','receipt':'receipt.'}[kind]
 for row in result['rows']:
  assert row['source'] == source and row['action'].startswith(prefix)
  assert (row['fence_version'] is not None) == (kind == 'shadow_run')
  assert (row['revision'] is not None) == (kind in ['exception','receipt'])
  assert (row['reason_code'] is not None) == (kind in ['exception','receipt'])
 return result

def main():
 parser = argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--report-dir', required=True, type=pathlib.Path)
 parser.add_argument('--migration', default=DEFAULT, type=pathlib.Path)
 args = parser.parse_args(); out = args.report_dir.resolve(); assert not out.exists(); out.mkdir(parents=True)
 evidence = {'kind':'private_joined_operator_audit_schema153_subset','started_at':utc(),'cases':[],
  'hosted_mutations':False,'source_rows_copied':False,'signed_jwt_or_auth_provider_tested':False,
  'provider_or_sms_called':False,'production_ready':False}
 save = lambda:(out/'result.json').write_text(json.dumps(evidence,indent=2)+'\n')
 def case(name, fn):
  detail = fn(); evidence['cases'].append({'name':name,'status':'pass','detail':detail})
  save(); print('PASS '+name,flush=True); return detail
 helpers = {n:((ROOT/'scripts/tests'/(n+'.py')).read_bytes(), ROOT/'scripts/tests'/(n+'.py')) for n in HELPERS}
 (out/'executed-python').mkdir()
 for n,(body,p) in helpers.items(): (out/'executed-python'/p.name).write_bytes(body)
 own = pathlib.Path(__file__).read_bytes(); (out/'executed-python'/pathlib.Path(__file__).name).write_bytes(own)
 evidence['runner_sha256'] = sha(own); evidence['executed_helpers_sha256'] = {str(p.relative_to(ROOT)):sha(b) for b,p in helpers.values()}
 finder = CapturedHelpers(helpers); sys.meta_path.insert(0,finder)
 import operational_exception_inbox_uat as ops
 import collect_current_release_upgrade_uat as private
 import android_gateway_identity_uat as keys
 u,f,c = ops.u, ops.foundation, ops.fixture
 migration = args.migration.resolve(); assert ROOT in migration.parents and not migration.is_symlink()
 stages = {ROOT/p:(ROOT/p).read_bytes() for p in STAGES}; stages[migration] = migration.read_bytes()
 (out/'executed-migrations').mkdir()
 for p,body in stages.items(): (out/'executed-migrations'/p.name).write_bytes(body)
 schema_bytes = SCHEMA.read_bytes(); schema = json.loads(schema_bytes)
 jsonschema.Draft202012Validator.check_schema(schema); (out/'executed-migrations'/SCHEMA.name).write_bytes(schema_bytes)
 evidence['schema_sha256'] = sha(schema_bytes)
 evidence['executed_migrations_sha256'] = {str(p.relative_to(ROOT)):sha(b) for p,b in stages.items()}
 target = None; made = False; sessions = []; db = 'collect_joined_audit_'+uuid.uuid4().hex[:12]
 sql = lambda text:u.psql(db,text).stdout.strip()
 truth = lambda text:check(sql(text) == 't')
 owner = lambda text:u.call(db,text,EMAIL,SID)
 service = lambda text:json.loads(sql(f.service(text)).splitlines()[-1])
 def audit(kind, entity, limit=20, cursor=None):
  pair = 'null,null' if cursor is None else quote(cursor['recorded_at'])+','+quote(cursor['event_id'])
  result = owner('select public.admin_get_operator_entity_audit_v1(%s,%s,%d,%s);' % (quote(kind),quote(entity),limit,pair))
  return validate(result,schema,kind,entity,limit,cursor)
 try:
  target = private.Target(out,'joined_audit',evidence.setdefault('offline_target',{})); target.__enter__(); u.CONTAINER = target.name
  u.SQL_LOG = out/'queries.log'; u.CONCURRENCY_LOG = out/'concurrency.log'; f.RAW_QUERY_LOG = out/'queries.sql'
  dump = (c.BASELINE/'schema-only.sql').read_bytes(); acl = (c.BASELINE/'api-acl.sql').read_bytes()
  assert sha(dump) == c.DUMP_HASH and sha(acl) == c.ACL_HASH
  evidence['baseline'] = {'migration_count':153,'schema_sha256':c.DUMP_HASH,'acl_sha256':c.ACL_HASH}
  u.psql('postgres','create database '+db+' template template0;'); made = True
  sql('create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+dump.decode()+acl.decode())
  f.seed(db)
  sql("insert into public.admin_permissions(name,description)values('audit.read','Synthetic'),('payments.read','Synthetic'),('admin_users.manage','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select '%s',name from public.admin_permissions on conflict do nothing;" % f.ROLE)
  sql("insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values('%s','%s','+250788971001',repeat('a',64),'mtn_momo');" % (f.GROUP,u.UID))
  # Schema-only capture deliberately contains no singleton rows. Reproduce
  # the actual predecessor migration's lease seed before a real lifecycle.
  sql('insert into collect_security.shadow_supervisor_lease(id)values(true)on conflict do nothing;')
  old = u.call(db,"select public.begin_collect_shadow_run_v1(gen_random_uuid());")['run']
  lifecycle = lambda verb,r:"select public.%s_collect_shadow_run_v1('%s',%d);" % (verb,r['run_id'],r['fence_version'])
  u.call(db,lifecycle('sample',old)); u.call(db,lifecycle('finish',old))
  sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';")
  payment = '99810000-0000-4000-8000-000000050001'; sql(f.service(f.payment_sql(payment,amount=50)))
  sql("update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
  before = f.business_fingerprint(db)
  for p,body in stages.items():
   result = u.psql(db,body.decode(),False); (out/(p.stem+'.install.log')).write_text(result.stdout+result.stderr)
   assert result.returncode == 0,result.stderr[-4000:]
   case(p.name+' preserves financial and immutable receipt evidence',lambda:check(f.business_fingerprint(db) == before))
  case('installation does not invent historical shadow audit',lambda:truth('select count(*)=0 from collect_operator_audit.shadow_events;'))
  case('private audit table denies all API roles with RLS',lambda:truth("select c.relrowsecurity and not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c where c.oid='collect_operator_audit.shadow_events'::regclass;"))
  case('private audit schema and helpers are not API capabilities',lambda:truth("select not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_schema_privilege(r,'collect_operator_audit','USAGE'))and not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace='collect_operator_audit'::regnamespace and has_function_privilege(r,p.oid,'EXECUTE'));"))
  query = "select public.admin_get_operator_entity_audit_v1('shadow_run','%s');" % old['run_id']
  for role in ['anon','service_role']:
   case(role+' cannot access the joined audit',lambda role=role:u.expected_error(db,query,'42501',role=role))
  case('legacy phone owner cannot read email-owned audit',lambda:u.expected_error(db,query,'42501','operator_audit_current_email_owner_required'))
  sql("insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)values('%s','authenticated','authenticated','info@ikanisa.com',clock_timestamp(),'{}','{}');" % EMAIL)
  service("select public.bootstrap_collect_email_operator_v1('%s');" % EMAIL)
  sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');" % (SID,EMAIL))
  case('old real manual run has no fabricated audit timeline',lambda:check(audit('shadow_run',old['run_id'])['rows'] == []))
  mutations = [
   ('unverified email',"update auth.users set email_confirmed_at=null where id='%s';" % EMAIL),
   ('expired session',"update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id='%s';" % SID),
   ('revoked session',"delete from auth.sessions where id='%s';" % SID),
   ('revoked approval',"update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id='%s';" % EMAIL),
   ('revoked owner role',"update public.admin_user_roles set revoked_at=clock_timestamp()where user_id='%s';" % EMAIL),
  ]
  for permission in ['audit.read','notifications.read','system_health.read']:
   mutations.append(('missing '+permission,"delete from public.admin_role_permissions where role_id='%s'and permission_name='%s';" % (f.ROLE,permission)))
  for name,mutation in mutations:
   def denied(mutation=mutation):
    r = u.psql(db,'begin;'+mutation+u.auth(EMAIL,SID)+query+'rollback;',False)
    return check(r.returncode != 0 and '42501:' in r.stderr)
   case('audit refuses '+name,denied)
  for isolation in ['repeatable read','serializable']:
   r = u.psql(db,'begin isolation level '+isolation+';'+u.auth(EMAIL,SID)+query+'rollback;',False)
   case(isolation+' cannot retain audit authority',lambda r=r:check(r.returncode != 0 and '40001:' in r.stderr))
  for bad in ["null,'%s'" % old['run_id'],"'payment','%s'" % old['run_id'],"'shadow_run',null", "'shadow_run','%s',0" % old['run_id'],"'shadow_run','%s',51" % old['run_id'],"'shadow_run','%s',20,clock_timestamp(),null" % old['run_id'],"'shadow_run','%s',20,'infinity',gen_random_uuid()" % old['run_id']]:
   case('invalid audit arguments '+bad,lambda bad=bad:u.expected_error(db,'select public.admin_get_operator_entity_audit_v1('+bad+');','22023',uid=EMAIL,sid=SID))
  for kind in ['shadow_run','gateway_device','supervisor_identity','exception','receipt']:
   case(kind+' absent identity does not disclose events',lambda kind=kind:check(audit(kind,str(uuid.uuid4()))['status'] == 'unavailable'))
  new = owner("select public.begin_collect_shadow_run_v1(gen_random_uuid());")['run']
  owner(lifecycle('sample',new)); owner(lifecycle('finish',new))
  rows = audit('shadow_run',new['run_id'])['rows']; (out/'observed-shadow.json').write_text(json.dumps(audit('shadow_run',new['run_id']),indent=2)+'\n')
  case('actual shadow lifecycle yields three transactional audit events',lambda:check([x['action'] for x in rows] == ['shadow.completed','shadow.sampled','shadow.started'] and all(x['request_id'] == new['request_id'] and x['actor_id'] == EMAIL for x in rows)))
  case('private shadow events join actual public audit identities',lambda:truth("select count(*)=3 and bool_and(a.entity_id=e.run_id and a.action=e.action and a.created_at=e.recorded_at and a.actor_user_id=e.actor_id)from collect_operator_audit.shadow_events e join public.audit_logs a on a.id=e.event_id where e.run_id='%s';" % new['run_id']))
  owner(lifecycle('finish',new))
  case('manual finish replay does not duplicate audit',lambda:check(len(audit('shadow_run',new['run_id'])['rows']) == 3))
  first = audit('shadow_run',new['run_id'],1); second = audit('shadow_run',new['run_id'],1,first['next_cursor']); third = audit('shadow_run',new['run_id'],1,second['next_cursor'])
  case('keyset pages preserve ordering without duplicates',lambda:check([first['rows'][0],second['rows'][0],third['rows'][0]] == rows and third['next_cursor'] is None))
  for op in ['update collect_operator_audit.shadow_events set action=action;', 'delete from collect_operator_audit.shadow_events;']:
   case('private shadow audit is immutable '+op.split()[0],lambda op=op:check(u.psql(db,op,False).returncode != 0))
  def key(n):
   body = bytes.fromhex(keys.PREFIX+keys.POINTS[n]); return base64.b64encode(body).decode(),sha(body)
  k,h = key(0)
  device = owner("select public.admin_enroll_gateway_device_v1(gen_random_uuid(),gen_random_uuid(),'%s','%s','%s');" % (k,h,'c'*64))['device_id']
  owner("select public.admin_revoke_gateway_device_v1('%s',gen_random_uuid(),'%s','%s');" % (device,h,'c'*64))
  result = audit('gateway_device',device); (out/'observed-gateway.json').write_text(json.dumps(result,indent=2)+'\n')
  case('gateway audit reads original immutable enrollment and revocation',lambda:check([r['action'] for r in result['rows']] == ['gateway.revoke','gateway.enroll']))
  k,h = key(1); expiry = (datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=1)).isoformat()
  principal = owner("select public.admin_enroll_receipt_supervisor_v1(gen_random_uuid(),'%s','%s','%s');" % (k,h,expiry))['principal_id']
  owner("select public.admin_revoke_receipt_supervisor_v1('%s',gen_random_uuid(),'%s');" % (principal,h))
  result = audit('supervisor_identity',principal); (out/'observed-supervisor.json').write_text(json.dumps(result,indent=2)+'\n')
  case('supervisor audit reads original enrollment and revocation without key material',lambda:check([r['action'] for r in result['rows']] == ['supervisor.revoke','supervisor.enroll'] and h not in json.dumps(result) and k not in json.dumps(result)))
  exception = sql("select id from collect_ops.exceptions where source_kind='gateway'and source_id='%s'limit 1;" % device)
  if not exception:
   sql("select collect_ops.refresh_source('gateway','%s');" % device)
   exception = sql("select id from collect_ops.exceptions where source_kind='gateway'and source_id='%s'limit 1;" % device)
  rev = sql("select revision from collect_ops.exceptions where id='%s';" % exception)
  for action,reason in [('acknowledge','review_started'),('escalate','owner_review_required')]:
   owner("select public.admin_act_operational_exception_v1(gen_random_uuid(),'%s',%s,'%s','%s');" % (exception,rev,action,reason))
  result = audit('exception',exception); (out/'observed-exception.json').write_text(json.dumps(result,indent=2)+'\n')
  case('exception action audit does not imply source resolution or delivered escalation',lambda:check([r['action'] for r in result['rows']] == ['exception.escalate','exception.acknowledge']))
  receipt = sql("select id from collect_hybrid.sms_notification_outbox where payment_id='%s';" % payment)
  inspected = owner("select public.admin_inspect_unstarted_receipt_v1('%s');" % receipt)
  assert inspected['receipt']['can_cancel'],inspected
  owner("select public.admin_cancel_unstarted_receipt_v1(gen_random_uuid(),'%s',%d,'operator_cancelled');" % (receipt,inspected['receipt']['revision']))
  result = audit('receipt',receipt); (out/'observed-receipt.json').write_text(json.dumps(result,indent=2)+'\n')
  case('receipt audit joins actual cancellation while retaining primary receipt identity',lambda:check(len(result['rows']) == 1 and result['rows'][0]['action'] == 'receipt.cancel_unstarted' and result['rows'][0]['revision'] == 2))
  hidden = u.psql(db,"begin;delete from public.collection_receivers where collection_id='%s';" % f.GROUP+u.auth(EMAIL,SID)+"select public.admin_get_operator_entity_audit_v1('receipt','%s');rollback;" % receipt)
  hidden_result = json.loads(hidden.stdout.strip().splitlines()[-1]); validate(hidden_result,schema,'receipt',receipt,20)
  case('removing positive Rwanda receiving scope hides retained receipt actions',lambda:check(hidden_result['status'] == 'unavailable' and hidden_result['rows'] == []))
  for kind,entity in [('receipt',receipt),('exception',exception)]:
   r = u.psql(db,"begin;delete from public.admin_role_permissions where role_id='%s'and permission_name='payments.read';" % f.ROLE+u.auth(EMAIL,SID)+"select public.admin_get_operator_entity_audit_v1('%s','%s');rollback;" % (kind,entity),False)
   case(kind+' separately requires financial evidence permission',lambda r=r:check(r.returncode != 0 and '42501:' in r.stderr))
  read_before = f.business_fingerprint(db)
  for kind,entity in [('shadow_run',new['run_id']),('gateway_device',device),('supervisor_identity',principal),('exception',exception),('receipt',receipt)]: audit(kind,entity)
  case('all joined audit reads leave financial receipt and transport rows unchanged',lambda:check(f.business_fingerprint(db) == read_before))
  a = u.Session(db,'authority_holder'); sessions.append(a)
  a.write("begin;select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));select 'AUTHORITY_HELD';"); a.read('AUTHORITY_HELD')
  case('real overlapping authority lock gives bounded safe busy',lambda:u.expected_error(db,query,'55P03','operator_audit_authority_busy',uid=EMAIL,sid=SID))
  a.write("rollback;select 'AUTHORITY_RELEASED';"); a.read('AUTHORITY_RELEASED')
  case('audit recovers through manual read after busy',lambda:check(audit('shadow_run',new['run_id'])['status'] == 'available'))
  evidence['helper_source_drift'] = [str(p.relative_to(ROOT)) for b,p in helpers.values() if p.read_bytes() != b]
  evidence['migration_source_drift'] = [str(p.relative_to(ROOT)) for p,b in stages.items() if p.read_bytes() != b]
  assert not evidence['helper_source_drift'] and not evidence['migration_source_drift'] and SCHEMA.read_bytes() == schema_bytes
  evidence['status'] = 'pass';save()
 except BaseException as error:
  evidence['status'] = 'failed';evidence['error_type'] = type(error).__name__;evidence['error'] = str(error);save();raise
 finally:
  for session in sessions:
   try: session.close()
   except Exception as error: evidence.setdefault('cleanup_errors',[]).append(str(error))
  if made: evidence['isolated_database_removed'] = u.psql('postgres','drop database '+db+' with(force);',False).returncode == 0
  if target: target.close()
  u.SQL_LOG = None;u.CONCURRENCY_LOG = None;f.RAW_QUERY_LOG = None
  sys.meta_path.remove(finder);evidence['case_count'] = len(evidence['cases']);evidence['completed_at'] = utc();save()

if __name__ == '__main__': main()
