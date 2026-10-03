#!/usr/bin/env python3
"""Private schema153 subset UAT for additive exception reads; no live services.

Auxiliary Python is captured before import and executed from those exact bytes.
Only a new network-none task container and a disposable database are written.
"""
import argparse, base64, datetime, hashlib, importlib.abc, importlib.util
import json, pathlib, sys, time, uuid
import jsonschema

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATION = ROOT/'supabase/migrations/20261001000300_admin_exception_reads.sql'
SCHEMA = ROOT/'contracts/collect-admin-exception-v2.schema.json'
STAGES = [
 'supabase/migrations/20260930213000_operator_email_auth.sql',
 'supabase/migrations/20260930220527_operator_email_cutover_guard.sql',
 'supabase/migrations/20260930230100_receipt_backlog_events.sql',
 'supabase/migrations/20260930230200_admin_receipt_overview.sql',
 'supabase/migrations/20260930230300_admin_transaction_lifecycle.sql',
 'supabase/migrations/20260930211605_android_gateway_identity.sql',
 'supabase/migrations/20261001000100_operational_exception_inbox.sql',
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

def validate(value, schema, active=None, kind=None, limit=None, before=None):
 jsonschema.Draft202012Validator(schema).validate(value)
 if value['contract_version'] == 1: return True
 checked = ts(value['checked_at'])
 assert ts(value['sample_valid_until']) == checked+datetime.timedelta(seconds=60)
 if 'rows' in value:
  if active is not None: assert value['active'] is active
  assert value['source_kind'] == kind
  if limit is not None: assert value['limit'] == limit
  rows = value['rows']; keys = [(ts(r['last_changed_at']), r['id']) for r in rows]
  assert keys == sorted(set(keys), reverse=True) and len(rows) <= value['limit']
  if before: assert all(k < before for k in keys)
  if value['next_cursor']:
   assert len(rows) == value['limit']
   assert value['next_cursor'] == {'changed_at': rows[-1]['last_changed_at'], 'id': rows[-1]['id']}
  for row in rows:
   assert row['active'] == value['active'] and (kind is None or row['source_kind'] == kind)
   assert ts(row['first_observed_at']) <= ts(row['last_changed_at']) <= checked
   if row['source_kind'] == 'raw_sms' and row['transaction_sms_id']: assert row['transaction_sms_id'] == row['source_id']
   if row['source_kind'] in ('receipt', 'gateway'): assert row['transaction_sms_id'] is None
 else:
  if value['status'] == 'recorded':
   assert value['receipt']['request_id'] == value['request_id']
   assert ts(value['receipt']['recorded_at']) <= checked
  else: assert value['receipt'] is None
 return True

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
 evidence = {'kind': 'offline_exception_reads_v2_schema153_subset', 'started_at': now(),
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
 (report/'executed-python'/'admin_exception_reads_uat.py').write_bytes(pathlib.Path(__file__).read_bytes())
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
 sessions = []; made = False; target = None; db = 'collect_exception_v2_'+uuid.uuid4().hex[:12]
 try:
  target = private.Target(report, 'exception_v2', evidence.setdefault('target', {})); target.__enter__()
  u.CONTAINER = target.name; u.SQL_LOG = report/'queries.log'; u.CONCURRENCY_LOG = report/'concurrency.log'; f.RAW_QUERY_LOG = report/'queries.sql'
  dump = (fixture.BASELINE/'schema-only.sql').read_bytes(); acl = (fixture.BASELINE/'api-acl.sql').read_bytes()
  assert sha(dump) == fixture.DUMP_HASH and sha(acl) == fixture.ACL_HASH
  evidence['baseline'] = {'schema_sha256': sha(dump), 'acl_sha256': sha(acl), 'captured_migration_count': 153,
   'no_rows_copied': True, 'not_attested': 'Complete managed-host Auth/platform/source parity; this is the retained schema153 subset'}
  u.psql('postgres', 'create database '+db+' template template0;'); made = True
  restore = u.psql(db, 'create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'+dump.decode()+acl.decode(), False)
  (report/'restore.log').write_text(restore.stdout+restore.stderr); assert restore.returncode == 0, restore.stderr[-4000:]
  f.seed(db)
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
 sql = lambda text: u.psql(db, text).stdout.strip()
 owner = lambda text, uid=u.UID, sid=u.SID: u.call(db, text, uid, sid)
 truth = lambda text: sql(text) == 't'
 def error(query, state='42501', reason=None, uid=u.UID, sid=u.SID, role='authenticated', mutation=''):
  claims = u.auth(uid, sid) if role == 'authenticated' else "set local role "+role+";select set_config('request.jwt.claims','{\"role\":\""+role+"\"}',true);"
  result = u.psql(db, 'begin;'+mutation+claims+query+';rollback;', False)
  assert result.returncode and state+':' in result.stderr and (reason is None or reason in result.stderr), result.stderr
  return {'sqlstate': state, 'reason': reason}
 def listing(active=True, kind=None, limit=50, before=None):
  cursor = 'null,null' if before is None else quote(before['changed_at'])+','+quote(before['id'])
  query = 'select public.admin_list_operational_exceptions_v2(%s,%d,%s,%s)' % ('true' if active else 'false', limit, cursor, 'null' if kind is None else quote(kind))
  result = owner(query); validate(result, schema, active, kind, limit, (ts(before['changed_at']), before['id']) if before else None); return result
 def lookup(request, uid=u.UID, sid=u.SID):
  result = owner('select public.admin_get_operational_exception_action_v2('+quote(request)+')', uid, sid)
  validate(result, schema); assert result['request_id'] == request; return result
 def retain(name, result): (report/('observed-'+name+'.json')).write_text(json.dumps(result, indent=2)+'\n'); return result
 sql("insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('admin_users.manage','Synthetic') on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select '%s',name from public.admin_permissions on conflict do nothing;" % f.ROLE)
 for uid, email in [(u.UID, 'exception-owner@collect.example'), (u.OTHER, 'exception-other@collect.example')]:
  sql("update auth.users set email=%s,email_confirmed_at=clock_timestamp(),phone_confirmed_at=null where id=%s;insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values(%s,%s,clock_timestamp()-interval '2 minutes','Synthetic already-verified approved owner');" % tuple(map(quote, [email, uid, uid, email])))
 owner("select public.admin_set_operator_email_mode_v1('Synthetic exception read email cutover')")
 empty = retain('empty', listing()); case('new read genuinely has no historical exception backfill', empty['rows'] == [] and empty['next_cursor'] is None)
 case('new helpers remain inaccessible to every API role', truth("select not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace='collect_ops'::regnamespace and has_function_privilege(r,p.oid,'EXECUTE'));"))
 case('private operational records retain RLS without direct API access', truth("select count(*)=9 and bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c cross join unnest(array['anon','authenticated','service_role'])r where c.relnamespace='collect_ops'::regnamespace and c.relname in('exceptions','exception_observations','exception_actions');"))
 case('v2 functions grant execution only to authenticated', truth("select count(*)=2 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')and not has_function_privilege('anon',p.oid,'EXECUTE')and not has_function_privilege('service_role',p.oid,'EXECUTE'))from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('admin_list_operational_exceptions_v2','admin_get_operational_exception_action_v2');"))
 unknown_request = str(uuid.uuid4()); list_query = 'select public.admin_list_operational_exceptions_v2()'; lookup_query = 'select public.admin_get_operational_exception_action_v2('+quote(unknown_request)+')'
 for role in ['anon', 'service_role']:
  for label, query in [('list', list_query), ('lookup', lookup_query)]: case(role+' cannot execute '+label, lambda role=role, query=query: error(query, role=role))
 mutations = [
  ('expired session', "update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id=%s;" % quote(u.SID)),
  ('banned account', "update auth.users set banned_until=clock_timestamp()+interval '1 hour'where id=%s;" % quote(u.UID)),
  ('revoked owner grant', "update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=%s;" % quote(u.UID)),
  ('changed owner role', "update public.admin_roles set name='fixture_invalid_role'where id=%s;" % quote(f.ROLE)),
  ('revoked email approval', "update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id=%s;" % quote(u.UID)),
  ('expired email approval', "update collect_admin_access.email_approvals set expires_at=clock_timestamp()-interval '1 second'where user_id=%s;" % quote(u.UID)),
  ('unverified email', "update auth.users set email_confirmed_at=null where id=%s;" % quote(u.UID)),
  ('changed email', "update auth.users set email='changed-exception@collect.example'where id=%s;" % quote(u.UID)),
  *[(permission, "delete from public.admin_role_permissions where role_id=%s and permission_name=%s;" % (quote(f.ROLE), quote(permission))) for permission in ['payments.read', 'notifications.read', 'system_health.read']],
 ]
 for label, mutation in mutations:
  for name, query in [('list', list_query), ('lookup', lookup_query)]: case(name+' refuses '+label, lambda query=query, mutation=mutation: error(query, mutation=mutation))
 for query in [list_query, lookup_query]:
  case('bound session cannot be replaced for '+query, lambda query=query: error(query, sid=u.OTHERSID))
  case('repeatable-read snapshot is refused for '+query, lambda query=query: error(query, '40001', 'operational_exception_snapshot_retry', mutation='set transaction isolation level repeatable read;'))
 case('read does not require mutation permission', owner_read_without_manage(db, u, f, list_query))
 for args in ['null', 'true,0', 'true,51', "true,1,null,'%s'" % uuid.uuid4(), 'true,1,clock_timestamp(),null', "true,1,'infinity','%s'" % uuid.uuid4(), "true,1,null,null,''", "true,1,null,null,'all'"]:
  case('invalid list arguments '+args, lambda args=args: error('select public.admin_list_operational_exceptions_v2('+args+')', '22023', 'operational_exception_query_invalid'))
 case('null request is rejected only after authority', lambda: error('select public.admin_get_operational_exception_action_v2(null)', '22023', 'operational_exception_action_invalid'))
 sql("insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values('%s','%s','+250788971001',repeat('a',64),'mtn_momo');" % (f.GROUP, u.UID))
 sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values('%s','%s','%s','M-Money','Protected synthetic parser failure',repeat('e',64),repeat('a',64),'failed');" % (RAW, f.GROUP, u.UID))
 raw_row = listing(kind='raw_sms')['rows'][0]; case('bound raw exception links only its own authoritative Rwanda UUID', raw_row['transaction_sms_id'] == RAW and raw_row['source_id'] == RAW)
 sql("insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,direction,currency,receiver_phone_hash,allocation_status)values('%s','%s','%s','%s',true,'mtn_momo','incoming','RWF',repeat('a',64),'ambiguous');" % (PARSED, RAW, f.GROUP, u.UID))
 case('allocation ID is not mistaken for the raw SMS ID', listing(kind='allocation')['rows'][0]['transaction_sms_id'] == RAW)
 sql(f.service(f.payment_sql(PAYMENT, posted=False, parsed=PARSED)))
 sql(f.service(f.payment_sql(UNLINKED, posted=False)))
 payments = {row['source_id']: row for row in listing(kind='payment')['rows']}
 case('payment uses its actual parsed/raw join', payments[PAYMENT]['transaction_sms_id'] == RAW)
 case('valid route without a parsed source returns nullable link', payments[UNLINKED]['transaction_sms_id'] is None)
 currency_refusal = u.psql(db, "begin;update public.parsed_payment_events set currency='EUR'where id='%s';rollback;" % PARSED, False)
 case('foreign parsed currency cannot persist past the real schema constraint', currency_refusal.returncode != 0 and '23514:' in currency_refusal.stderr)
 for label, fields in [('outgoing', "direction='outgoing'"), ('nonpayment', 'is_mobile_money_payment=false'), ('different receiving provider', "network='airtel_money'"), ('parsed receiving hash conflict', "receiver_phone_hash=repeat('b',64)"), ('parsed receiver conflict', "receiver_user_id='%s'" % u.OTHER)]:
  mutation = "update public.parsed_payment_events set %s where id='%s';" % (fields, PARSED)
  result = json.loads(sql('begin;'+mutation+u.auth()+list_query+';rollback;').splitlines()[-1]); validate(result, schema)
  linked = [r for r in result['rows'] if r['source_kind'] in ('raw_sms', 'allocation', 'payment') and r['source_id'] in (RAW, PARSED, PAYMENT)]
  case('current '+label+' cannot supply any canonical SMS link', len(linked) == 3 and all(r['transaction_sms_id'] is None for r in linked))
 case('absent raw identity does not become a guessed transaction link', sql("select collect_ops.transaction_sms_id('raw_sms','%s')is null;" % uuid.uuid4()) == 't')
 # Source transitions are isolated trusted-boundary fixtures; they establish
 # actual receipt/gateway conditions without contacting a handset or carrier.
 service = lambda query: json.loads(sql(f.service(query)).splitlines()[-1])
 receipt_payment = str(uuid.uuid4()); sql(f.service(f.payment_sql(receipt_payment)))
 outbox = sql("select id from collect_hybrid.sms_notification_outbox where payment_id='%s';" % receipt_payment)
 sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';")
 claim = service("select public.collect_claim_receipt('%s','%s','exception-v2-synthetic-worker','%s');" % (u.UID, outbox, uuid.uuid4()))
 exact = service("select public.collect_get_claimed_receipt('%s','%s','%s',%d);" % (u.UID, outbox, claim['claim_token'], claim['fence_version']))
 approval = str(uuid.uuid4())
 service("select public.collect_confirm_receipt('%s','%s','%s',%d,%d,'%s','%s');" % (u.UID, outbox, claim['claim_token'], claim['fence_version'], exact['destination_revision'], exact['body_sha256'], approval))
 attempt = service("select public.collect_record_send_start('%s','%s','%s',%d,'%s');" % (u.UID, outbox, claim['claim_token'], claim['fence_version'], approval))
 sql("update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
 service("select public.collect_record_observed_outcome('%s','%s','uncertain','synthetic-v2-uat','No handset or carrier was contacted');" % (u.UID, attempt['attempt_id']))
 receipt_rows = listing(kind='receipt')['rows']
 case('actual uncertain receipt uses only its own opaque source ID', any(r['source_id'] == outbox and r['reason_code'] == 'SEND_UNCERTAIN' and r['transaction_sms_id'] is None for r in receipt_rows))
 key_bytes = bytes.fromhex('3059301306072a8648ce3d020106082a8648ce3d030107034200046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5')
 key, digest, cert = base64.b64encode(key_bytes).decode(), sha(key_bytes), 'c'*64
 enrolled = owner("select public.admin_enroll_gateway_device_v1('%s','%s','%s','%s','%s')" % (uuid.uuid4(), uuid.uuid4(), key, digest, cert))
 device = enrolled['device_id']; payload = {'sms_permission': True, 'network': 'offline', 'telephony': 'ready', 'sim_selected': True, 'sim_revision_sha256': 'a'*64, 'local_pause': False, 'reported_at': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')}
 service("select public.gateway_heartbeat_v1('%s','%s',repeat('a',64),'%s'::jsonb);" % (device, uuid.uuid4(), json.dumps(payload)))
 owner("select public.admin_activate_gateway_device_v1('%s','%s','%s','%s')" % (device, uuid.uuid4(), digest, cert))
 gateway_rows = listing(kind='gateway')['rows']
 case('actual gateway observation uses its device ID with no invented transaction', any(r['source_id'] == device and r['reason_code'] == 'GATEWAY_NETWORK' and r['transaction_sms_id'] is None for r in gateway_rows))
 previous = retain('populated', listing()); case('server category filters the full candidate set before paging', all(r['source_kind'] == 'allocation' for r in retain('filtered', listing(kind='allocation', limit=1))['rows']))
 request = str(uuid.uuid4()); action = "select public.admin_act_operational_exception_v1('%s','%s',%d,'acknowledge','review_started')" % (request, raw_row['id'], raw_row['revision'])
 acted = retain('action-receipt', owner(action)); validate(acted, schema)
 recorded = retain('recorded-lookup', lookup(request)); case('v2 projects the exact immutable v1 receipt', recorded['status'] == 'recorded' and recorded['receipt'] == acted)
 case('another current owner cannot read the original actor receipt', lookup(request, u.OTHER, u.OTHERSID)['status'] == 'not_recorded')
 unknown = retain('unknown-lookup', lookup(unknown_request)); case('absent UUID is a read result without mutation replay permission', unknown['status'] == 'not_recorded' and unknown['receipt'] is None)
 business = f.business_fingerprint(db); retained = sql('select count(*) from collect_ops.exception_actions;')
 for kind in [None, 'raw_sms', 'allocation', 'payment', 'receipt', 'gateway']:
  listing(kind=kind)
 case('all categories and reconciliation reads preserve financial/outbox and action rows', business == f.business_fingerprint(db) and retained == sql('select count(*) from collect_ops.exception_actions;'))
 # Multiple committed observations at an equal timestamp test UUID tie-breaks.
 for n in range(2, 5):
  rid = '99770000-0000-4000-8000-%012d' % (60000+n)
  sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values('%s','%s','%s','M-Money','Synthetic page source %d',encode(extensions.digest('page-%d','sha256'),'hex'),repeat('a',64),'failed');" % (rid, f.GROUP, u.UID, n, n))
 # Clock timestamps differ naturally; retain their exact microsecond cursors.
 first = listing(kind='raw_sms', limit=2); second = listing(kind='raw_sms', limit=2, before=first['next_cursor'])
 case('paired keyset pages are bounded, ordered and disjoint', first['next_cursor'] is not None and not ({r['id'] for r in first['rows']} & {r['id'] for r in second['rows']}))
 tail = listing(kind='raw_sms', limit=2, before={'changed_at': second['rows'][-1]['last_changed_at'], 'id': second['rows'][-1]['id']})
 case('cursor beyond known category returns genuine empty window', not tail['rows'] and tail['next_cursor'] is None)
 sql("update public.raw_payment_sms set parse_status='pending'where id='%s';" % RAW)
 cleared = retain('cleared', listing(active=False, kind='raw_sms')); case('cleared source stays visible only in its requested category/state', any(r['source_id'] == RAW and not r['active'] for r in cleared['rows']))
 sql("update public.raw_payment_sms set parse_status='failed'where id='%s';" % RAW)
 changed = next(r for r in listing(kind='raw_sms')['rows'] if r['source_id'] == RAW)
 case('new source revision resets historical review flags', changed['revision'] > raw_row['revision'] and not changed['acknowledged'] and not changed['escalation_requested'])
 run_races(db, case, evidence, report, u, f, schema, sessions, listing, lookup, error, changed)
 case('canonical menu is provisioned with backend read permission', truth("select label='Exceptions'and route_path='/admin/exceptions'and required_permission='payments.read'and enabled from public.admin_navigation_items where key='exceptions';"))
 nav = 'lock table public.admin_navigation_items'+MIGRATION.read_text().split('lock table public.admin_navigation_items')[1].split("notify pgrst")[0]
 probe = u.psql(db, "begin;update public.admin_navigation_items set enabled=false,label='Synthetic custom exceptions',updated_reason='Synthetic disable'where key='exceptions';"+nav+"select not enabled and label='Synthetic custom exceptions'from public.admin_navigation_items where key='exceptions';rollback;", False)
 case('navigation conflict preserves explicit disabled customization', probe.returncode == 0 and probe.stdout.strip().splitlines()[-1] == 't')
 case('v2 never broadens or edits v1 function definitions', truth("select exists(select 1 from pg_proc where oid='public.admin_act_operational_exception_v1(uuid,uuid,bigint,text,text)'::regprocedure) and not has_function_privilege('service_role','public.admin_act_operational_exception_v1(uuid,uuid,bigint,text,text)','EXECUTE');"))
 case('read UAT never opens dispatch or scheduler execution', truth("select not(select enabled from public.feature_flags where key='hybrid_sms_notifications')and not exists(select 1 from collect_gateway.dispatch_arms)and not exists(select 1 from cron.job_run_details);"))
 case('all actual synthetic receipt journals remain two-line balanced', truth("select not exists(select 1 from collect_hybrid.momo_journal_entries j left join collect_hybrid.momo_journal_lines l on l.journal_entry_id=j.id group by j.id having count(*)<>2 or sum(case when l.direction='debit'then l.amount_rwf else-l.amount_rwf end)<>0);"))
 evidence['final_business_fingerprints'] = f.business_fingerprint(db)

def owner_read_without_manage(db, u, f, query):
 result = u.psql(db, 'begin;delete from public.admin_role_permissions where role_id='+quote(f.ROLE)+"and permission_name='notifications.manage';"+u.auth()+query+';rollback;', False)
 return result.returncode == 0

def run_races(db, case, evidence, report, u, f, schema, sessions, listing, lookup, error, changed):
 def session(name): s = u.Session(db, name); sessions.append(s); return s
 holder, action_session = session('v2_source_holder'), session('v2_original_action')
 holder.write("begin;select pg_advisory_xact_lock(hashtextextended('collect-ops-source:raw_sms:%s',0));select 'SOURCE_LOCKED';" % RAW); holder.read('SOURCE_LOCKED')
 request = str(uuid.uuid4())
 action_sql = "select public.admin_act_operational_exception_v1('%s','%s',%d,'escalate','owner_review_required');" % (request, changed['id'], changed['revision'])
 action_input = "set application_name='collect_exception_v2_original_action';begin;"+u.auth()+action_sql+"commit;select 'ACTION_FINISHED';"
 (report/'actual-action-race.sql').write_text(action_input+'\n'); action_session.write(action_input)
 deadline = time.monotonic()+8; waiting = False
 while time.monotonic() < deadline:
  waiting = u.psql(db, "select exists(select 1 from pg_stat_activity where datname='%s'and application_name='collect_exception_v2_original_action'and wait_event_type='Lock');" % db).stdout.strip() == 't'
  if waiting: break
  time.sleep(.05)
 assert waiting, 'Actual action did not wait on the real source lock'
 started = time.monotonic()
 refusal = error('select public.admin_get_operational_exception_action_v2('+quote(request)+')', '55P03', 'operational_exception_authority_busy')
 elapsed = time.monotonic()-started
 case('actual held action produces bounded authority_busy without request disclosure', elapsed < 2 and refusal['reason'] == 'operational_exception_authority_busy')
 case('unrelated UUID has identical busy authority refusal', lambda: error('select public.admin_get_operational_exception_action_v2('+quote(uuid.uuid4())+')', '55P03', 'operational_exception_authority_busy'))
 holder.write("commit;select 'SOURCE_RELEASED';"); holder.read('SOURCE_RELEASED')
 output = action_session.read('ACTION_FINISHED')
 receipts = [json.loads(line) for line in output if line.startswith('{') and 'exception_id' in line]
 assert len(receipts) == 1, output
 result = lookup(request); case('manual post-commit lookup reconciles exact original v1 action receipt', result['status'] == 'recorded' and result['receipt'] == receipts[0])
 evidence['actual_action_lookup_race'] = {'actually_waited': waiting, 'busy_seconds': elapsed, 'action_output': output, 'post_commit_lookup': result}
 # A held namespace key without a held authority proof exercises the truthful
 # secondary in_progress branch; it is not claimed as an authentic sender job.
 key_holder = session('v2_request_lock_only'); unknown = str(uuid.uuid4())
 key_holder.write("begin;select pg_advisory_xact_lock(hashtextextended('collect-ops-action:%s',0));select 'REQUEST_LOCKED';" % unknown); key_holder.read('REQUEST_LOCKED')
 progress = lookup(unknown); validate(progress, schema); (report/'observed-progress-lookup.json').write_text(json.dumps(progress, indent=2)+'\n')
 case('request-lock branch is in_progress only after current authority succeeds', progress['status'] == 'in_progress' and progress['receipt'] is None)
 key_holder.write("commit;select 'REQUEST_RELEASED';"); key_holder.read('REQUEST_RELEASED')
 case('released unrecorded request stays unrecorded without retry', lookup(unknown)['status'] == 'not_recorded')
 restored = u.psql(db, "begin;set local lock_timeout='7s';"+u.auth()+"select public.admin_get_operational_exception_action_v2('%s');select current_setting('lock_timeout');rollback;" % unknown).stdout.strip().splitlines()[-1]
 case('function-local lock timeout restores caller setting on success', restored == '7s')
 # Same-session authority failure is caught in a subtransaction, proving the
 # bounded function setting does not escape its error path either.
 restored_error = u.psql(db, "begin;set local lock_timeout='7s';"+u.auth()+"do $$begin perform public.admin_get_operational_exception_action_v2(null);exception when invalid_parameter_value then null;end$$;select current_setting('lock_timeout');rollback;").stdout.strip().splitlines()[-1]
 case('function-local lock timeout restores caller setting on error', restored_error == '7s')
 for s in sessions: s.close()
 sessions.clear()

if __name__ == '__main__': main()
