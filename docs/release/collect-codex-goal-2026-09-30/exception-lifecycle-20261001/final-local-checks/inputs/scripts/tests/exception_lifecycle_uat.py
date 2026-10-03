#!/usr/bin/env python3
"""Real SQL lifecycle tests on a pinned, networkless disposable PostgreSQL target.

Uses the retained schema-only foundation and captured additive prerequisites.
No shared/hosted database, credentials, provider or carrier is used.
"""
import argparse
import datetime
import json
import pathlib
import uuid

import operational_exception_inbox_uat as base

ROOT, u, foundation, fixture, private = base.ROOT, base.u, base.foundation, base.fixture, base.private
MIGRATION = ROOT / 'supabase/migrations/20261001120000_operational_exception_lifecycle.sql'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir', required=True, type=pathlib.Path)
    args = parser.parse_args()
    report = args.report_dir.resolve()
    if report.exists() or not str(report).startswith(str(ROOT / 'docs/release') + '/'):
        parser.error('Fresh release evidence directory required')
    report.mkdir(parents=True)
    evidence = dict(kind='exception_lifecycle_isolated_sql', status='running', cases=[],
                    hosted_called=False, carrier_called=False, shared_database_written=False,
                    source_rows_copied=False, auth_provider_tested=False)
    save = lambda: (report / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    sources = {ROOT / name: (ROOT / name).read_bytes() for name in base.STAGES}
    sources[MIGRATION] = MIGRATION.read_bytes()
    sources[pathlib.Path(__file__)] = pathlib.Path(__file__).read_bytes()
    evidence['source_sha256'] = {str(p.relative_to(ROOT)): fixture.sha(b) for p, b in sources.items()}
    (report / 'sources').mkdir()
    for p, b in sources.items(): (report / 'sources' / p.name).write_bytes(b)
    def check(ok):
        if not ok: raise AssertionError('Expectation failed')
        return True
    def case(name, fn):
        try: value = fn()
        except Exception as error:
            evidence['cases'].append(dict(name=name, status='failed', error=str(error))); save(); raise
        evidence['cases'].append(dict(name=name, status='pass', detail=value)); save()
        print('PASS ' + name, flush=True)
        return value
    db = 'exception_lifecycle_' + uuid.uuid4().hex[:12]
    made = False
    sql = lambda body: u.psql(db, body).stdout.strip()
    owner = lambda body: u.call(db, body, base.EMAIL, base.EMAIL_SID)
    service = lambda body: json.loads(sql(foundation.service(body)).splitlines()[-1])
    fail = lambda body, state, reason=None: u.expected_error(db, body, state, reason, uid=base.EMAIL, sid=base.EMAIL_SID)
    def financial():
        return {k: v for k, v in foundation.business_fingerprint(db).items()
                if k not in ('raw_payment_sms', 'parsed_payment_events')}
    def act(item, revision, action, assignee='null', due='null', reason='review_started', request=None):
        expires = sql("select collect_ops.utc(clock_timestamp()+interval '90 seconds');")
        return "select public.admin_act_exception_workflow_v1('%s','%s',%s,%s,'%s',%s,%s,'%s','%s');" % (
            request or uuid.uuid4(), item['id'], item['revision'], revision, action, assignee, due, reason, expires)
    save()
    try:
        with private.Target(report, 'exception_lifecycle', evidence.setdefault('target', {})) as target:
            u.CONTAINER = target.name
            u.SQL_LOG, u.CONCURRENCY_LOG = report / 'queries.log', report / 'concurrency.log'
            dump, acl = (fixture.BASELINE / 'schema-only.sql').read_bytes(), (fixture.BASELINE / 'api-acl.sql').read_bytes()
            check(fixture.sha(dump) == fixture.DUMP_HASH and fixture.sha(acl) == fixture.ACL_HASH)
            u.psql('postgres', 'create database ' + db + ' template template0;'); made = True
            sql("create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);" + dump.decode() + acl.decode())
            foundation.seed(db)
            sql("insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)values('%s','%s','+250788971001',repeat('a',64),'mtn_momo');" % (foundation.GROUP, u.UID))
            before = financial()
            for path in [ROOT / name for name in base.STAGES] + [MIGRATION]:
                sql(sources[path].decode())
            case('additive install preserves financial evidence', lambda: check(before == financial()))
            sql("insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('admin_users.manage','Synthetic')on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select '%s',name from public.admin_permissions on conflict do nothing;" % foundation.ROLE)
            sql("insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)values('%s','authenticated','authenticated','info@ikanisa.com',clock_timestamp(),'{}','{}');" % base.EMAIL)
            service("select public.bootstrap_collect_email_operator_v1('%s');" % base.EMAIL)
            sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');" % (base.EMAIL_SID, base.EMAIL))
            owner("select public.admin_set_operator_email_mode_v1('Synthetic lifecycle email cutover');")
            sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values('%s','%s','%s','M-Money','Synthetic lifecycle failure',repeat('e',64),repeat('a',64),'failed');" % (base.RAW, foundation.GROUP, u.UID))
            item = json.loads(sql("select to_jsonb(e)from collect_ops.exceptions e where source_id='%s';" % base.RAW))
            read = "select public.admin_get_exception_workflow_v1('%s');" % item['id']
            case('unassigned source has no fabricated owner or deadline', lambda: check(owner(read)['status'] == 'unassigned' and owner(read)['workflow_revision'] == 0))
            unassigned = owner(read)
            case('unassigned active source has explicit false overdue', lambda: check(unassigned['overdue'] is False))
            (report / 'observed-unassigned.json').write_text(json.dumps(unassigned, indent=2)+'\n')
            uid = "'%s'" % base.EMAIL
            due = sql("select collect_ops.utc(clock_timestamp()+interval '2 hours');")
            request = str(uuid.uuid4()); assign = act(item, 0, 'assign', uid, "'%s'" % due, request=request)
            receipt = owner(assign)
            case('assignment records approved current owner and bounded deadline', lambda: check(owner(read)['assignee_id'] == base.EMAIL and owner(read)['due_at'] == due and receipt['workflow_revision'] == 1))
            case('exact request replay preserves immutable receipt', lambda: check(owner(assign) == receipt))
            case('request collision cannot reinterpret the original action', lambda: fail(act(item, 1, 'escalate', request=request), '22023', 'exception_workflow_request_conflict'))
            case('stale workflow revision refused', lambda: fail(act(item, 0, 'escalate'), '55000', 'exception_workflow_source_changed'))
            expired = act(item, 1, 'escalate').rsplit(',', 1)[0] + ",clock_timestamp()-interval '1 second');"
            distant = act(item, 1, 'escalate').rsplit(',', 1)[0] + ",clock_timestamp()+interval '121 seconds');"
            case('expired request cannot mutate after later arrival', lambda: fail(expired, '22023', 'exception_workflow_request_expired'))
            case('request lifetime is bounded to120seconds', lambda: fail(distant, '22023', 'exception_workflow_request_expired'))
            case('active source cannot be marked resolved', lambda: fail(act(item, 1, 'resolve', reason='source_rechecked'), '55000', 'exception_workflow_source_state_invalid'))
            case('past deadline refused', lambda: fail(act(item, 1, 'assign', uid, "clock_timestamp()-interval '1 second'"), '22023', 'exception_workflow_deadline_invalid'))
            case('unknown unapproved assignee refused', lambda: fail(act(item, 1, 'assign', "'%s'" % u.UID, "clock_timestamp()+interval '1 hour'"), '42501', 'exception_workflow_recipient_unavailable'))
            esc = owner(act(item, 1, 'escalate', reason='owner_review_required'))
            duplicate = owner(act(item, 2, 'escalate', reason='owner_review_required'))
            case('separate escalation requests deduplicate delivery work', lambda: check(esc['escalation_id'] == duplicate['escalation_id'] and sql('select count(*)from collect_ops.exception_escalations;') == '1'))
            case('unknown response reconciles by original actor request', lambda: check(owner("select public.admin_get_exception_workflow_request_v1('%s');" % request)['receipt'] == receipt))
            case('missing response lookup remains explicit not recorded', lambda: check(owner("select public.admin_get_exception_workflow_request_v1('%s');" % uuid.uuid4())['status'] == 'not_recorded'))
            case('delivery pump requires service role', lambda: fail('select public.process_exception_escalations_v1();', '42501'))
            for limit in [0, 51]:
                case('worker refuses batch limit '+str(limit), lambda limit=limit: u.expected_error(db,
                    'select public.process_exception_escalations_v1(%s);' % limit, '22023', 'exception_escalation_limit_invalid', role='service_role'))
            for role in ['anon', 'service_role']:
                case(role+' cannot inspect owner workflow', lambda role=role: u.expected_error(db, read, '42501', role=role))
            case('durable delivery commits once without external send', lambda: check(service('select public.process_exception_escalations_v1();')['delivered'] == 1))
            case('worker recovery does not redeliver committed work', lambda: check(service('select public.process_exception_escalations_v1();')['delivered'] == 0 and sql('select count(*)from collect_ops.exception_inbox_deliveries;') == '1'))
            inbox = owner('select public.admin_list_exception_escalation_inbox_v1();')
            case('recipient inbox contains delivered evidence and separate unread state', lambda: check(inbox['rows'][0]['escalation_id'] == esc['escalation_id'] and inbox['rows'][0]['read_at'] is None))
            read_action = "select public.admin_read_exception_escalation_v1('%s');" % esc['escalation_id']
            opened = owner(read_action)
            case('read acknowledgement is idempotent and does not resolve source', lambda: check(owner(read_action) == opened and not opened['source_resolved']))
            case('unauthorized receipt ID refused', lambda: fail("select public.admin_read_exception_escalation_v1('%s');" % uuid.uuid4(), '42501'))
            for table in ['exception_workflow_requests', 'exception_inbox_deliveries', 'exception_inbox_reads']:
                result = u.psql(db, 'delete from collect_ops.' + table + ';', False)
                case(table+' immutable even to table owner', lambda result=result: check(result.returncode != 0 and '55000:' in result.stderr))
            case('all lifecycle tables deny direct API access with RLS', lambda: check(sql("select count(*)=15 and bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c cross join unnest(array['anon','authenticated','service_role'])r where c.relnamespace='collect_ops'::regnamespace and c.relname in('exception_workflows','exception_workflow_requests','exception_escalations','exception_inbox_deliveries','exception_inbox_reads');") == 't'))
            sql("update public.raw_payment_sms set parse_status='pending'where id='%s';" % base.RAW)
            cleared = json.loads(sql("select to_jsonb(e)from collect_ops.exceptions e where id='%s';" % item['id']))
            case('real cleared source is visible before explicit resolution', lambda: check(owner(read)['status'] == 'source_cleared'))
            resolved = owner(act(cleared, 3, 'resolve', reason='source_rechecked'))
            case('resolution is tied to rechecked cleared source revision', lambda: check(resolved['source_resolved'] and owner(read)['status'] == 'resolved'))
            sql("update public.raw_payment_sms set parse_status='failed'where id='%s';" % base.RAW)
            reopened = json.loads(sql("select to_jsonb(e)from collect_ops.exceptions e where id='%s';" % item['id']))
            case('reopened source retains identity and does not inherit resolution', lambda: check(owner(read)['status'] == 'assigned' and reopened['revision'] > cleared['revision']))
            esc2 = owner(act(reopened, 4, 'escalate', reason='owner_review_required'))
            sql("update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id='%s';" % base.EMAIL)
            case('revoked recipient cannot receive escalation', lambda: check(service('select public.process_exception_escalations_v1();')['recipient_unavailable'] == 1))
            sql("update collect_admin_access.email_approvals set revoked_at=null where user_id='%s';update collect_ops.exception_escalations set retry_at=clock_timestamp()where id='%s';" % (base.EMAIL, esc2['escalation_id']))
            case('restored recipient is retried using same durable escalation ID', lambda: check(service('select public.process_exception_escalations_v1();')['delivered'] == 1))
            owner(act(reopened, 5, 'assign', uid, "clock_timestamp()+interval '1 second'"))
            # Existing delivered work deduplicates an overdue sweep of the same revision.
            case('deadline sweep reuses delivered identity without another delivery', lambda: check(service('select public.process_exception_escalations_v1();')['delivered'] == 0))
            sql("update public.raw_payment_sms set parse_status='pending'where id='%s';update public.raw_payment_sms set parse_status='failed'where id='%s';" % (base.RAW, base.RAW))
            overdue = json.loads(sql("select to_jsonb(e)from collect_ops.exceptions e where id='%s';" % item['id']))
            owner(act(overdue, 6, 'assign', uid, "clock_timestamp()+interval '500 milliseconds'"))
            sql('select pg_sleep(0.55);')
            case('real elapsed deadline creates and delivers one new revision escalation', lambda: check(owner(read)['overdue'] and service('select public.process_exception_escalations_v1();')['delivered'] == 1))
            case('bounded repeated deadline sweep does not duplicate delivery', lambda: check(service('select public.process_exception_escalations_v1();')['delivered'] == 0))
            sql("update public.raw_payment_sms set parse_status='pending'where id='%s';update public.raw_payment_sms set parse_status='failed'where id='%s';" % (base.RAW, base.RAW))
            newest = json.loads(sql("select to_jsonb(e)from collect_ops.exceptions e where id='%s';" % item['id']))
            owner(act(newest, 7, 'escalate', reason='owner_review_required'))
            sql("update public.raw_payment_sms set parse_status='pending'where id='%s';" % base.RAW)
            case('source cleared before delivery makes queued work obsolete', lambda: check(service('select public.process_exception_escalations_v1();')['obsolete'] == 1))
            denied = u.psql(db, "begin;update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id='%s';" % base.EMAIL_SID + u.auth(base.EMAIL, base.EMAIL_SID) + read + 'rollback;', False)
            case('expired session loses lifecycle read authority', lambda: check(denied.returncode != 0 and '42501:' in denied.stderr))
            case('all workflow actions preserve financial records', lambda: check(before == financial()))
            second_raw = '99790000-0000-4000-8000-000000060002'
            sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values('%s','%s','%s','M-Money','Synthetic never assigned condition',repeat('d',64),repeat('a',64),'failed');update public.raw_payment_sms set parse_status='pending'where id='%s';" % (second_raw, foundation.GROUP, u.UID, second_raw))
            unowned = json.loads(sql("select to_jsonb(e)from collect_ops.exceptions e where source_id='%s';" % second_raw))
            owner(act(unowned, 0, 'resolve', reason='source_rechecked'))
            closed_unowned = owner("select public.admin_get_exception_workflow_v1('%s');" % unowned['id'])
            case('cleared unassigned source resolves without inventing owner or deadline', lambda: check(closed_unowned['status'] == 'resolved' and closed_unowned['assignee_id'] is None and closed_unowned['due_at'] is None))
            (report / 'observed-unassigned-resolved.json').write_text(json.dumps(closed_unowned, indent=2)+'\n')
            (report / 'observed-workflow.json').write_text(json.dumps(owner(read), indent=2)+'\n')
            (report / 'observed-inbox.json').write_text(json.dumps(owner('select public.admin_list_exception_escalation_inbox_v1();'), indent=2)+'\n')
            u.psql('postgres', 'drop database ' + db + ' with(force);'); made = False
            evidence['database_removed'] = True
        evidence['status'] = 'pass'
    except BaseException:
        evidence['status'] = 'failed'; raise
    finally:
        evidence['sources_unchanged'] = all(p.read_bytes() == b for p, b in sources.items())
        evidence['finished_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat(); save()
        if not evidence['sources_unchanged']:
            raise RuntimeError('Input sources changed during the run; evidence is unaccepted')


if __name__ == '__main__': main()
