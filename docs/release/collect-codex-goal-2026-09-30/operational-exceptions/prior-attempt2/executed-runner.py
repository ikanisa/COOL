#!/usr/bin/env python3
"""Derived exception UAT in a task-owned networkless schema-only fixture.

No URL, source rows, credentials, Auth provider or sender is used. Synthetic
provider records exercise the accounting contracts, not authentic settlement.
"""
import argparse, base64, datetime, hashlib, json, pathlib, time, uuid
import collect_admin_combined_upgrade_uat as fixture
import collect_current_release_upgrade_uat as private
import android_gateway_identity_uat as gateway_fixture

u, foundation, ROOT = fixture.u, fixture.foundation, fixture.ROOT
STAGES = ['supabase/migrations/20260930213000_operator_email_auth.sql',
          'supabase/migrations/20260930220527_operator_email_cutover_guard.sql',
          *fixture.STAGES,
          'supabase/migrations/20260930211605_android_gateway_identity.sql',
          'supabase/migrations/20261001000100_operational_exception_inbox.sql']
EMAIL = '99790000-0000-4000-8000-000000000001'
EMAIL_SID = '99790000-0000-4000-8000-000000010001'
RAW = '99790000-0000-4000-8000-000000060001'
PARSED = '99790000-0000-4000-8000-000000070001'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir', required=True)
    args = parser.parse_args()
    report = pathlib.Path(args.report_dir).resolve()
    assert not report.exists(), 'Fresh evidence directory required'
    report.mkdir(parents=True)
    evidence = {'kind': 'offline_operational_exception_schema153_subset',
                'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'production_written': False, 'shared_database_written': False,
                'source_rows_copied': False, 'provider_called': False, 'sms_sent': False,
                'signed_jwt_or_auth_provider_tested': False, 'cases': []}
    db = 'collect_ops_'+uuid.uuid4().hex[:12]
    made = False
    target = None
    sessions = []

    def save():
        (report/'result.json').write_text(json.dumps(evidence, indent=2)+'\n')

    def check(value):
        assert value, value
        return True

    def case(name, fn):
        detail = fn()
        evidence['cases'].append({'name': name, 'status': 'pass', 'detail': detail})
        save()
        print('PASS '+name, flush=True)
        return detail

    sql = lambda text: u.psql(db, text).stdout.strip()
    truth = lambda text: check(sql(text) == 't')
    service = lambda text: json.loads(sql(foundation.service(text)).splitlines()[-1])
    owner = lambda text: u.call(db, text, EMAIL, EMAIL_SID)
    refresh = lambda kind, ids: service("select public.refresh_operational_exception_sources_v1('%s',array[%s]::uuid[]);" % (kind, ','.join("'%s'" % x for x in ids)))
    count = lambda: int(sql('select count(*) from collect_ops.exception_observations;'))
    exception = lambda kind, source, code: json.loads(sql("select to_jsonb(e) from collect_ops.exceptions e where source_kind='%s' and source_id='%s' and reason_code='%s';" % (kind, source, code)))
    action_sql = lambda request, item, action='acknowledge': "select public.admin_act_operational_exception_v1('%s','%s',%s,'%s','review_started');" % (request, item['id'], item['revision'], action)

    try:
        target = private.Target(report, 'root_exceptions', evidence.setdefault('offline_target', {}))
        target.__enter__()
        u.CONTAINER = target.name
        u.SQL_LOG = report/'queries.log'
        u.CONCURRENCY_LOG = report/'concurrency.log'
        foundation.RAW_QUERY_LOG = report/'queries.sql'
        dump = (fixture.BASELINE/'schema-only.sql').read_bytes()
        acl = (fixture.BASELINE/'api-acl.sql').read_bytes()
        assert fixture.sha(dump) == fixture.DUMP_HASH and fixture.sha(acl) == fixture.ACL_HASH
        bodies = {path: (ROOT/path).read_bytes() for path in STAGES}
        (report/'executed-migrations').mkdir()
        for path, body in bodies.items():
            (report/'executed-migrations'/pathlib.Path(path).name).write_bytes(body)
        (report/'executed-runner.py').write_bytes(pathlib.Path(__file__).read_bytes())
        evidence['source_sha256'] = {p: fixture.sha(b) for p, b in bodies.items()}
        evidence['runner_sha256'] = fixture.sha(pathlib.Path(__file__).read_bytes())
        evidence['baseline'] = {'schema_sha256': fixture.DUMP_HASH, 'acl_sha256': fixture.ACL_HASH, 'captured_migration_count': 153}
        u.psql('postgres', 'create database '+db+' template template0;')
        made = True
        u.psql(db, "create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);"+dump.decode()+acl.decode())
        foundation.seed(db)
        sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';"+foundation.service(foundation.payment_sql('99710000-0000-4000-8000-000000049999', amount=50))+"update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
        sql("insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network) values('%s','%s','+250788971001',repeat('a',64),'mtn_momo');" % (foundation.GROUP, u.UID))
        evidence['prior_receipt'] = json.loads(sql("select to_jsonb(o) from collect_hybrid.sms_notification_outbox o where payment_id='99710000-0000-4000-8000-000000049999';"))
        baseline = foundation.business_fingerprint(db)
        for path, body in bodies.items():
            executed = u.psql(db, body.decode(), False)
            (report/(pathlib.Path(path).stem+'.install.log')).write_text(executed.stdout+executed.stderr)
            assert executed.returncode == 0, executed.stderr
            case(path+' preserves existing financial evidence', lambda: check(foundation.business_fingerprint(db) == baseline))
        case('migration creates no synthetic historical exception backfill', lambda: truth('select not exists(select 1 from collect_ops.exceptions);'))
        foundation.run_cases(db, lambda name, fn: case('receipt regression: '+name, fn), evidence, report, sessions)
        sql("insert into public.admin_permissions(name,description)values('payments.read','Synthetic'),('admin_users.manage','Synthetic') on conflict do nothing;insert into public.admin_role_permissions(role_id,permission_name)select '%s',name from public.admin_permissions on conflict do nothing;" % foundation.ROLE)
        sql("insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data) values('%s','authenticated','authenticated','info@ikanisa.com',clock_timestamp(),'{}','{}');" % EMAIL)
        service("select public.bootstrap_collect_email_operator_v1('%s');" % EMAIL)
        sql("insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values('%s','%s',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');" % (EMAIL_SID, EMAIL))
        owner("select public.admin_set_operator_email_mode_v1('Synthetic exception email cutover');")
        case('current approved email owner can inspect the actual exception contract', lambda: check(owner('select public.admin_list_operational_exceptions_v1();')['contract_version'] == 1))
        case('private operational tables retain RLS and no API grants', lambda: truth("select count(*)=9 and bool_and(c.relrowsecurity and not has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c cross join unnest(array['anon','authenticated','service_role'])r where c.relnamespace='collect_ops'::regnamespace and c.relname in('exceptions','exception_observations','exception_actions');"))
        case('private schema/helpers deny API usage and execution', lambda: truth("select not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_schema_privilege(r,'collect_ops','USAGE')) and not exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])r where p.pronamespace='collect_ops'::regnamespace and has_function_privilege(r,p.oid,'EXECUTE'));"))
        for role in ['anon', 'service_role']:
            case(role+' cannot inspect owner inbox', lambda role=role: u.expected_error(db, 'select public.admin_list_operational_exceptions_v1();', '42501', role=role))
        for role in ['anon', 'authenticated']:
            case(role+' cannot invoke service source refresh', lambda role=role: u.expected_error(db, "select public.refresh_operational_exception_sources_v1('payment',array['99710000-0000-4000-8000-000000050001']::uuid[]);", '42501', role=role, uid=EMAIL, sid=EMAIL_SID))
        for label, mutation in [
            ('expired session', "update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='%s';" % EMAIL_SID),
            ('revoked email approval', "update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id='%s';" % EMAIL),
            ('revoked role', "update public.admin_user_roles set revoked_at=clock_timestamp()where user_id='%s';" % EMAIL),
            *[(permission, "delete from public.admin_role_permissions where role_id='%s'and permission_name='%s';" % (foundation.ROLE, permission)) for permission in ['payments.read', 'notifications.read', 'system_health.read']],
        ]:
            def deny(mutation=mutation):
                probe = u.psql(db, 'begin;'+mutation+u.auth(EMAIL, EMAIL_SID)+'select public.admin_list_operational_exceptions_v1();rollback;', False)
                return check(probe.returncode != 0 and '42501:' in probe.stderr)
            case('inbox refuses '+label, deny)
        sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values('%s','%s','%s','M-Money','Synthetic parser failure',repeat('e',64),repeat('a',64),'failed');" % (RAW, foundation.GROUP, u.UID))
        parse = exception('raw_sms', RAW, 'PARSING_FAILED')
        case('failed bound Rwanda observation creates one durable parsing exception', lambda: check(parse['active'] and parse['revision'] == 1))
        prior = count()
        refresh('raw_sms', [RAW]); refresh('raw_sms', [RAW])
        case('unchanged source refresh deduplicates the observation', lambda: check(count() == prior))
        request = str(uuid.uuid4())
        acted = owner(action_sql(request, parse))
        case('acknowledgement receipt explicitly leaves financial/send/source actions false', lambda: check(acted['request_id'] == request and not acted['source_resolved'] and not acted['financial_action'] and not acted['send_action']))
        case('exact action replay returns its immutable receipt', lambda: check(owner(action_sql(request, parse)) == acted))
        case('request collision cannot change action', lambda: u.expected_error(db, action_sql(request, parse, 'escalate'), '22023', 'operational_exception_request_conflict', uid=EMAIL, sid=EMAIL_SID))
        found = owner("select public.admin_get_operational_exception_action_v1('%s');" % request)
        case('unknown response can be reconciled by original request UUID', lambda: check(found['status'] == 'recorded' and found['receipt'] == acted))
        missing = owner("select public.admin_get_operational_exception_action_v1('%s');" % uuid.uuid4())
        case('unrecorded UUID never implies source handling or delivery', lambda: check(missing['status'] == 'not_recorded' and missing['receipt'] is None))
        escrow = owner(action_sql(str(uuid.uuid4()), parse, 'escalate'))
        case('escalation persists a request without claiming alert delivery', lambda: check(escrow['action'] == 'escalate' and not escrow['escalation_delivery_verified']))
        sql("update public.raw_payment_sms set parse_status='pending'where id='%s';" % RAW)
        cleared = exception('raw_sms', RAW, 'PARSING_FAILED')
        case('only changed actual source clears its active condition', lambda: check(not cleared['active'] and cleared['revision'] == 2))
        case('stale revision cannot acknowledge a cleared source', lambda: u.expected_error(db, action_sql(str(uuid.uuid4()), parse), '55000', 'operational_exception_source_changed', uid=EMAIL, sid=EMAIL_SID))
        sql("update public.raw_payment_sms set parse_status='failed'where id='%s';" % RAW)
        reopened = exception('raw_sms', RAW, 'PARSING_FAILED')
        case('reopened condition reuses stable identity with new immutable revision', lambda: check(reopened['id'] == parse['id'] and reopened['active'] and reopened['revision'] == 3))
        row = next(x for x in owner('select public.admin_list_operational_exceptions_v1(true,50);')['rows'] if x['id'] == reopened['id'])
        case('new revision is not hidden by old acknowledgement/escalation', lambda: check(not row['acknowledged'] and not row['escalation_requested']))
        held=u.Session(db,'exception_source_holder');waiter=u.Session(db,'exception_action_waiter');sessions.extend([held,waiter])
        held.write("begin;update public.raw_payment_sms set parse_status='pending'where id='%s';select 'SOURCE_HELD';"%RAW);held.read('SOURCE_HELD')
        race_request=str(uuid.uuid4())
        waiter.write("set application_name='collect_ops_stale_action';begin;"+u.auth(EMAIL,EMAIL_SID)+action_sql(race_request,reopened)+"commit;select 'ACTION_FINISHED';")
        waiting=False;deadline=time.monotonic()+8
        while time.monotonic()<deadline:
            waiting=sql("select exists(select 1 from pg_stat_activity where datname='%s'and application_name='collect_ops_stale_action'and wait_event_type='Lock');"%db)=='t'
            if waiting:break
            time.sleep(.05)
        assert waiting,'Stale action did not reach the actual source lock'
        held.write("commit;select 'SOURCE_COMMITTED';");held.read('SOURCE_COMMITTED')
        race=waiter.read('ACTION_FINISHED')
        case('concurrent source change fences stale acknowledgement after a real lock wait',lambda:check(any('55000:'in line and 'operational_exception_source_changed'in line for line in race)
             and sql("select count(*)from collect_ops.exception_actions where request_id='%s';"%race_request)=='0'))
        sql("update public.raw_payment_sms set parse_status='failed'where id='%s';"%RAW)
        wrong = str(uuid.uuid4())
        sql("insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,receiver_momo_number_hash,parse_status)values('%s','%s','%s','M-Money','Synthetic mismatched route',repeat('f',64),repeat('b',64),'failed');" % (wrong, foundation.GROUP, u.UID))
        case('unbound/mismatched observation cannot become a Rwanda parsing exception', lambda: truth("select not exists(select 1 from collect_ops.exceptions where source_kind='raw_sms'and source_id='%s');" % wrong))
        sql("insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,direction,currency,allocation_status)values('%s','%s','%s','%s',true,'mtn_momo','incoming','RWF','ambiguous');" % (PARSED, RAW, foundation.GROUP, u.UID))
        case('bound ambiguous allocation creates a separate durable exception', lambda: check(exception('allocation', PARSED, 'ALLOCATION_REVIEW')['active']))
        sql("update public.parsed_payment_events set allocation_status='ignored'where id='%s';" % PARSED)
        case('actual ignored allocation clears its review condition', lambda: check(not exception('allocation', PARSED, 'ALLOCATION_REVIEW')['active']))
        pending_payment = str(uuid.uuid4())
        sql(foundation.service(foundation.payment_sql(pending_payment, posted=False)))
        case('review payment creates verification-pending evidence without posting', lambda: check(exception('payment', pending_payment, 'VERIFICATION_PENDING')['active']))
        sql("insert into collect_hybrid.payment_provider_rejections(payment_id,provider_network,transaction_id,receiver_momo_number_hash,amount_rwf,occurred_at,reason,provider_reference)select id,provider_network,transaction_id,receiver_momo_number_hash,amount_rwf,clock_timestamp(),'Synthetic rejection observation','synthetic-ops'from public.payments where id='%s';"%pending_payment)
        case('stored rejection clears pending and remains separate verification evidence',lambda:check(exception('payment',pending_payment,'VERIFICATION_REJECTED')['active'] and not exception('payment',pending_payment,'VERIFICATION_PENDING')['active']))
        contact_member=str(uuid.uuid4());contact_payment=str(uuid.uuid4())
        sql("insert into collect_hybrid.member_records(id,collect_id,origin,created_by)values('%s','971299','admin_assisted','%s');insert into public.collection_members(collection_id,member_record_id,role,status)values('%s','%s','member','active');insert into collect_hybrid.sms_receipt_member_consents(member_record_id,enabled,capture_method,reason,recorded_by)values('%s',true,'written','Synthetic explicit consent','%s');"%(contact_member,u.UID,foundation.GROUP,contact_member,contact_member,u.UID))
        sql(foundation.service(foundation.payment_sql(contact_payment,member=contact_member)))
        contact=exception('payment',contact_payment,'CONTACT_MISSING')
        case('eligible policy with missing member contact creates review evidence',lambda:check(contact['active']))
        sql("insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)values('%s','Synthetic contact','SYNTHETIC CONTACT','+250788971299');"%contact_member)
        case('action refresh refuses stale contact issue after actual identity enrollment',lambda:u.expected_error(db,action_sql(str(uuid.uuid4()),contact),'55000','operational_exception_source_changed',uid=EMAIL,sid=EMAIL_SID))
        refresh('payment',[contact_payment])
        case('contact review never backfills or retries its historical receipt',lambda:truth("select not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id='%s');"%contact_payment))
        case('prior uncertain sends are durable operational exceptions', lambda: truth("select exists(select 1 from collect_ops.exceptions e join collect_hybrid.sms_notification_outbox o on o.id=e.source_id where e.reason_code='SEND_UNCERTAIN'and e.active and o.state='uncertain');"))
        case('definite not-sent failure remains distinct from uncertainty', lambda: truth("select exists(select 1 from collect_ops.exceptions e join collect_hybrid.sms_notification_outbox o on o.id=e.source_id where e.reason_code='SEND_FAILED_NO_SEND'and e.active and o.state='failed_no_send');"))
        case('suppression requires review and does not enqueue a replacement', lambda: truth("select exists(select 1 from collect_ops.exceptions where reason_code='RECEIPT_SUPPRESSED'and active);"))
        raw_key = bytes.fromhex(gateway_fixture.PREFIX+gateway_fixture.POINTS[0])
        key = base64.b64encode(raw_key).decode();digest = hashlib.sha256(raw_key).hexdigest();cert = 'c'*64
        enrolled = owner("select public.admin_enroll_gateway_device_v1('%s','%s','%s','%s','%s');" % (uuid.uuid4(), uuid.uuid4(), key, digest, cert))
        device = enrolled['device_id']
        def heartbeat(unhealthy=False,age_seconds=0):
            payload = {'sms_permission': not unhealthy, 'network': 'offline' if unhealthy else 'validated',
                       'telephony': 'unavailable' if unhealthy else 'ready', 'sim_selected': not unhealthy,
                       'sim_revision_sha256': None if unhealthy else 'a'*64, 'local_pause': False,
                       'reported_at': (datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=age_seconds)).isoformat(timespec='milliseconds').replace('+00:00', 'Z')}
            return service("select public.gateway_heartbeat_v1('%s','%s',repeat('a',64),'%s'::jsonb);" % (device, uuid.uuid4(), json.dumps(payload)))
        heartbeat()
        owner("select public.admin_activate_gateway_device_v1('%s','%s','%s','%s');" % (device, uuid.uuid4(), digest, cert))
        heartbeat(True)
        codes = json.loads(sql("select jsonb_agg(reason_code order by reason_code)from collect_ops.exceptions where source_kind='gateway'and source_id='%s'and active;" % device))
        case('gateway permission/network/telephony/SIM fail independently', lambda: check(codes == sorted(['GATEWAY_SMS_PERMISSION', 'GATEWAY_NETWORK', 'GATEWAY_TELEPHONY', 'GATEWAY_SIM'])))
        heartbeat()
        case('fresh healthy observation clears only actual gateway conditions', lambda: truth("select not exists(select 1 from collect_ops.exceptions where source_kind='gateway'and source_id='%s'and active);" % device))
        heartbeat(age_seconds=119)
        time.sleep(1.1)
        refresh('gateway',[device])
        case('reported observation expiry is not renewed by recent ingestion or refresh',lambda:check(exception('gateway',device,'GATEWAY_STALE')['active']))
        heartbeat()
        case('new observation clears stale condition without changing dispatch authority',lambda:truth("select not exists(select 1 from collect_ops.exceptions where source_kind='gateway'and source_id='%s'and active)and not exists(select 1 from collect_gateway.dispatch_arms);"%device))
        for query in ["select public.admin_list_operational_exceptions_v1(true,0);", "select public.admin_list_operational_exceptions_v1(true,51);", "select public.admin_list_operational_exceptions_v1(true,20,clock_timestamp(),null);"]:
            case('bounded list rejects '+query, lambda query=query: u.expected_error(db, query, '22023', 'operational_exception_query_invalid', uid=EMAIL, sid=EMAIL_SID))
        page = owner('select public.admin_list_operational_exceptions_v1(true,2);')
        cursor = page['next_cursor'];assert cursor is not None
        page2 = owner("select public.admin_list_operational_exceptions_v1(true,2,'%s','%s');" % (cursor['changed_at'], cursor['id']))
        case('paired keyset pages do not duplicate identities', lambda: check(not ({x['id'] for x in page['rows']} & {x['id'] for x in page2['rows']})))
        before_read = (foundation.business_fingerprint(db), count(), sql('select count(*)from collect_ops.exception_actions;'))
        observed = owner('select public.admin_list_operational_exceptions_v1(true,50);')
        (report/'observed-inbox.json').write_text(json.dumps(observed, indent=2)+'\n')
        case('read-only inbox/reconciliation preserve actual financial and exception evidence', lambda: check(before_read == (foundation.business_fingerprint(db), count(), sql('select count(*)from collect_ops.exception_actions;'))))
        case('read contract has no contacts, raw bodies, receipt text or financial amounts', lambda: check(all(set(row) == set('id source_kind source_id reason_code active revision source_sha256 first_observed_at last_changed_at acknowledged escalation_requested'.split()) for row in observed['rows']) and not observed['source_scan_complete'] and not observed['escalation_delivery_verified']))
        for table, query in [('exception_observations', 'update collect_ops.exception_observations set active=false;'), ('exception_actions', 'delete from collect_ops.exception_actions;')]:
            probe = u.psql(db, query, False)
            case(table+' evidence is immutable even to fixture owner', lambda probe=probe: check(probe.returncode != 0 and '55000:' in probe.stderr))
        probe=u.psql(db,"update collect_ops.exceptions set source_id=gen_random_uuid()where id='%s';"%parse['id'],False)
        case('stable exception source identity cannot be rewritten',lambda:check(probe.returncode!=0 and '55000:'in probe.stderr))
        evidence['source_still_matches_executed_bytes'] = all((ROOT/path).read_bytes() == body for path, body in bodies.items())
        assert evidence['source_still_matches_executed_bytes']
        evidence['status'] = 'pass'
    except Exception as error:
        evidence['status'] = 'failed';evidence['error'] = str(error);save();raise
    finally:
        for session in sessions:
            session.close()
        if made:
            evidence['isolated_database_removed'] = u.psql('postgres', 'drop database '+db+' with(force);', False).returncode == 0
        if target is not None:
            target.close()
        u.SQL_LOG = None;u.CONCURRENCY_LOG = None;foundation.RAW_QUERY_LOG = None
        evidence['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat();save()


if __name__ == '__main__':
    main()
