#!/usr/bin/env python3
"""Frozen schema153 subset upgrade in one disposable, guarded local database.

No URL is accepted. The shared QA database is never written or re-dumped.
The retained schema-only baseline contains no source rows. Synthetic financial
evidence exercises accounting; it does not attest a provider, device or carrier.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import time
import uuid

import receipt_backlog_events_uat as foundation
import shadow_supervisor_uat as u

ROOT = u.ROOT
SNAPSHOT = pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20260930-release-tooling-02')
SNAPSHOT_HASH = '4d49758c617893d96740bebc7ec9f34beac783c4d6019daadf754ed6e851a4fc'
BASELINE = ROOT / '.cache/receipt-foundation-attempt8'
DUMP_HASH = '77262947961ac1a724195ea77bdb98088cebd30caecc625ded1d4a93ccbf6d3d'
ACL_HASH = 'b430b8a2fb061f4422e8a53029a530a3d59f82f162507c8ae97e28541f52b577'
STAGES = [
    'supabase/migrations/20260930230100_receipt_backlog_events.sql',
    'supabase/migrations/20260930230200_admin_receipt_overview.sql',
    'supabase/migrations/20260930230300_admin_transaction_lifecycle.sql',
]
UID, SID = u.UID, u.SID
ROLE, GROUP, MEMBER = foundation.ROLE, foundation.GROUP, foundation.MEMBER
_base_business_fingerprint = foundation.business_fingerprint


def combined_business_fingerprint(db):
    result = _base_business_fingerprint(db)
    # Provider evidence and observed source records must be covered when a
    # read test claims unchanged financial/provider/observation evidence.
    for schema, table in [('public','payment_provider_confirmations'),
                          ('collect_hybrid','payment_provider_rejections'),
                          ('public','raw_payment_sms'),('public','parsed_payment_events'),
                          ('public','payment_allocations')]:
        text = "select jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),'sha256'),'hex')) from %s.%s t;" % (schema,table)
        result[table] = json.loads(u.psql(db,text).stdout)
    return result


foundation.business_fingerprint = combined_business_fingerprint


def sha(data):
    return hashlib.sha256(data).hexdigest()


def check(value):
    assert value, value
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir', required=True)
    args = parser.parse_args()
    report = pathlib.Path(args.report_dir).resolve()
    assert not report.exists(), 'Fresh report directory required'
    report.mkdir(parents=True)
    evidence = {
        'kind': 'schema153_three_migration_subset_upgrade',
        'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'clean_install_tested': False, 'hosted124_upgrade_tested': False,
        'production_written': False, 'shared_source_written': False,
        'provider_called': False, 'carrier_called': False,
        'source_rows_copied': False, 'signed_jwt_tested': False,
        'candidate_is_accepted_release': False, 'cases': [],
    }
    def save():
        (report / 'result.json').write_text(json.dumps(evidence, indent=2) + '\n')
    def case(name, fn):
        result = fn()
        evidence['cases'].append({'name': name, 'status': 'pass', 'detail': result})
        save()
        print('PASS ' + name, flush=True)
        return result

    db = 'collect_combined_upgrade_' + uuid.uuid4().hex[:12]
    made = False
    sessions = []
    foundation.RAW_QUERY_LOG = report / 'queries.sql'
    u.SQL_LOG = report / 'queries.log'
    u.CONCURRENCY_LOG = report / 'concurrency.log'
    try:
        labels = json.loads(u.command([u.DOCKER, 'inspect', u.CONTAINER, '--format', '{{json .Config.Labels}}']).stdout)
        ports = json.loads(u.command([u.DOCKER, 'inspect', u.CONTAINER, '--format', '{{json .HostConfig.PortBindings}}']).stdout)
        assert labels['com.supabase.cli.project'] == u.PROJECT
        assert labels['com.docker.compose.project'] == u.PROJECT
        assert all(p['HostPort'] == '55722' for p in ports['5432/tcp'])
        config = json.loads(u.psql('postgres', "select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'));").stdout)
        assert config == {'cron': 'off', 'net': '0'}, config
        evidence['local_container_guard'] = {'project': u.PROJECT, 'port': '55722', **config}
        manifest_bytes = (SNAPSHOT / '.collect-release-candidate.json').read_bytes()
        assert sha(manifest_bytes) == SNAPSHOT_HASH, 'Snapshot02 manifest changed'
        manifest = json.loads(manifest_bytes)
        evidence['candidate_binding'] = {
            'path': str(SNAPSHOT), 'manifest_sha256': SNAPSHOT_HASH,
            'scope': 'Selected migration/helper bytes only; current whole tree unaccepted',
            'approvals': manifest['approvals'],
        }
        bodies = {}
        evidence['staged_sources'] = []
        for relative in STAGES + ['scripts/tests/receipt_backlog_events_uat.py', 'scripts/tests/shadow_supervisor_uat.py']:
            source = (ROOT / relative).read_bytes()
            captured = (SNAPSHOT / relative).read_bytes()
            assert source == captured and sha(source) == manifest['source_files'][relative]['sha256'], relative
            evidence['staged_sources'].append({'path': relative, 'sha256': sha(source), 'snapshot02_byte_parity': True})
            if relative in STAGES:
                bodies[relative] = captured.decode()
        evidence['runner_sha256'] = sha(pathlib.Path(__file__).read_bytes())
        dump = (BASELINE / 'schema-only.sql').read_bytes()
        acl = (BASELINE / 'api-acl.sql').read_bytes()
        assert sha(dump) == DUMP_HASH and sha(acl) == ACL_HASH, 'Frozen schema153 baseline changed'
        old = json.loads((BASELINE / 'result.json').read_text())
        assert old['source_metadata'] == old['source_metadata_after_dump'] == {'count': 153, 'latest': '20260930220000', 'cron': 'off', 'net': '0'}
        evidence['baseline'] = {
            'schema_sha256': DUMP_HASH, 'api_acl_sha256': ACL_HASH,
            'metadata_before_and_after_capture': old['source_metadata'],
            'authority_prerequisite': old['authority_prerequisite'],
            'known_extra_migration_parity': old['known_extra_migration_parity'],
            'source': 'Retained attempt8 schema-only capture; quiet source not re-dumped',
            'owner_normalization': 'No-owner restore; API grants reconstructed from captured catalog',
            'excluded_runtime': ['pg_cron', 'pg_net', 'pg_graphql', 'pg_stat_statements'],
            'not_attested': 'Registry text parity is not universal deployed-function/body attestation',
        }
        (report / 'api-acl.sql').write_bytes(acl)
        (report / 'prerequisite-parity.json').write_text(json.dumps(evidence['baseline'], indent=2) + '\n')
        inventory(report, manifest, evidence)
        u.psql('postgres', 'create database ' + db + ' template template0;')
        made = True
        evidence['database'] = db
        mock = 'create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);'
        restored = u.psql(db, mock + dump.decode() + acl.decode(), False)
        (report / 'restore.stdout.log').write_text(restored.stdout)
        (report / 'restore.stderr.log').write_text(restored.stderr)
        assert restored.returncode == 0, restored.stderr[-3000:]
        foundation.seed(db)
        prior_sql = "update public.feature_flags set enabled=true where key='hybrid_sms_notifications';" + foundation.service(foundation.payment_sql('99710000-0000-4000-8000-000000049999', amount=50)) + "update public.feature_flags set enabled=false where key='hybrid_sms_notifications';"
        u.psql(db, prior_sql)
        (report / 'preexisting-receipt.sql').write_text('-- Synthetic local-only prior receipt; no live send.\n' + prior_sql + '\n')
        (report / 'synthetic-seed.sql').write_bytes((ROOT / 'docs/release/collect-codex-goal-2026-09-30/backend-foundation/synthetic-seed.sql').read_bytes())
        evidence['prior_receipt'] = json.loads(u.psql(db, "select to_jsonb(o) from collect_hybrid.sms_notification_outbox o where payment_id='99710000-0000-4000-8000-000000049999';").stdout)
        evidence['before_install'] = foundation.business_fingerprint(db)
        for relative in STAGES:
            before = foundation.business_fingerprint(db)
            install = u.psql(db, bodies[relative], False)
            stem = pathlib.Path(relative).stem
            (report / (stem + '.stdout.log')).write_text(install.stdout)
            (report / (stem + '.stderr.log')).write_text(install.stderr)
            assert install.returncode == 0, install.stderr[-4000:]
            case(stem + ' preserves all nonempty financial/outbox fingerprints', lambda before=before: foundation.equal(before, foundation.business_fingerprint(db)))
        evidence['installation_order'] = STAGES
        # These are the unchanged foundation's full adversarial tests, now run
        # with both new Admin read migrations installed in the same database.
        foundation.run_cases(db, case, evidence, report, sessions)
        run_admin_cases(db, case, evidence, report, sessions)
        evidence['status'] = 'pass'
    except Exception as error:
        evidence['status'] = 'failed'
        evidence['failure'] = str(error)
        save()
        raise
    finally:
        for session in sessions:
            try:
                session.close()
            except Exception as error:
                evidence.setdefault('cleanup_errors', []).append(str(error))
        if made:
            cleanup = u.psql('postgres', 'drop database ' + db + ' with (force);', False)
            evidence['isolated_database_removed'] = cleanup.returncode == 0
        foundation.RAW_QUERY_LOG = None
        u.SQL_LOG = None
        u.CONCURRENCY_LOG = None
        evidence['completed_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        evidence['case_count'] = len(evidence['cases'])
        save()


def inventory(report, manifest, evidence):
    hosted_path = ROOT / 'docs/release/collect-codex-goal-2026-09-30/hosted-readback/metadata.json'
    hosted = json.loads(hosted_path.read_text())['migrations']
    versions = {m['version'] for m in hosted}
    captured = sorted(p for p in manifest['source_files'] if p.startswith('supabase/migrations/') and p.endswith('.sql'))
    newer = [{'ordinal': i + 1, 'path': p, 'sha256': manifest['source_files'][p]['sha256'], 'in_subset': p in STAGES}
             for i, p in enumerate(captured) if pathlib.Path(p).name.split('_')[0] not in versions]
    later = []
    for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
        relative = str(path.relative_to(ROOT))
        digest = sha(path.read_bytes())
        prior = manifest['source_files'].get(relative)
        if prior is None or prior['sha256'] != digest:
            later.append({'path': relative, 'sha256': digest, 'reason': 'outside_capture' if prior is None else 'changed_after_capture'})
    result = {'hosted_registry_count': len(hosted), 'hosted_latest': max(versions),
              'hosted_metadata_sha256': sha(hosted_path.read_bytes()), 'candidate_migration_count': len(captured),
              'candidate_manifest_sha256': SNAPSHOT_HASH, 'pending_migrations': newer,
              'later_workspace_migrations': later, 'full_hosted_upgrade_executed': False,
              'subset_omission': '154 group-share rotation230000 is intentionally outside this three-migration rehearsal'}
    (report / 'hosted-upgrade-inventory.json').write_text(json.dumps(result, indent=2) + '\n')
    evidence['hosted_inventory'] = {'registry_count': len(hosted), 'candidate_migration_count': len(captured), 'pending_count': len(newer), 'later_workspace_migrations': later}


def run_admin_cases(db, case, evidence, report, sessions):
    sql = lambda text: u.psql(db, text).stdout.strip()
    call = lambda text: u.call(db, text)
    truth = lambda text: check(sql(text) == 't')
    overview = lambda: call('select public.admin_receipt_overview_v1();')
    listing = lambda args='': call('select public.admin_list_collect_transactions(' + args + ');')
    queries = [('Overview', 'select public.admin_receipt_overview_v1();'), ('transactions', 'select public.admin_list_collect_transactions();')]
    sql("insert into public.admin_permissions(name,description) values('overview.read','Synthetic combined read'),('payments.read','Synthetic combined read');insert into public.admin_role_permissions(role_id,permission_name) values('%s','overview.read'),('%s','payments.read');" % (ROLE, ROLE))
    # Direct database-owner fixture construction is observation-only. It does
    # not represent attested Android ingestion or authentic provider evidence.
    def ids(n):
        return tuple('99730000-0000-4000-8000-%012d' % (base + n) for base in (10100, 11100, 12100))
    def observed(n, amount=0, posted=False, member=MEMBER, parsed=True, allocation='allocated', parse='parsed'):
        raw, event, payment = ids(n)
        reference = 'COMBINED-%02d' % n
        text = "insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,parse_status,received_at_device,receiver_momo_number_hash) values('%s','%s','%s','M-Money','Synthetic combined raw body %d',encode(extensions.digest('synthetic-combined-%d','sha256'),'hex'),'%s',date_trunc('day',clock_timestamp())-interval '1 day',repeat('a',64));" % (raw, GROUP, UID, n, n, parse)
        if parsed:
            text += "insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,is_mobile_money_payment,network,direction,amount_rwf,currency,transaction_id,sender_name,allocation_status) values('%s','%s','%s','%s',true,'mtn_momo','incoming',%d,'RWF','%s','Synthetic combined payer','%s');" % (event, raw, GROUP, UID, amount, reference, allocation)
            text += foundation.payment_sql(payment, member=member, amount=amount, ref=reference, parsed=event, posted=posted)
        sql(foundation.service(text))
        return raw, event, payment
    observed(1, 400, posted=True)
    sql("update collect_hybrid.sms_receipt_member_consents set enabled=false where member_record_id='%s';" % foundation.NO_CONSENT)
    observed(2, 450, posted=True, member=foundation.NO_CONSENT)
    observed(3, 500, posted=False)
    observed(4, parsed=False, parse='pending')
    observed(5, parsed=False, parse='failed')
    observed(6, 600, posted=True)
    call("select public.admin_reverse_momo_payment('%s','Synthetic combined reversal','%s');" % (ids(6)[2], uuid.uuid4()))
    observed(7, 700, posted=True)
    observed(8, 800, posted=True)
    observed(9, 900, posted=True)
    baseline = foundation.business_fingerprint(db)
    evidence['combined_financial_baseline'] = baseline
    snapshot = overview()
    (report / 'observed-overview-paused.json').write_text(json.dumps(snapshot, indent=2) + '\n')
    def expected_posted(s):
        return json.loads(sql("select jsonb_build_object('count',count(*),'value_rwf',coalesce(sum(amount_rwf),0)::text) from public.payments where status='posted' and currency='RWF' and provider_network in ('mtn_momo','airtel_money') and posted_at>='%s' and posted_at<'%s' and posted_at<='%s';" % (s['day_start'], s['day_end'], s['checked_at'])))
    def expected_receipts():
        return json.loads(sql("select jsonb_build_object('queued',count(*) filter(where state='queued'),'awaiting_confirmation',count(*) filter(where state='awaiting_confirmation'),'oldest_pending_at',min(created_at) filter(where state in ('queued','awaiting_confirmation')),'failed_no_send',count(*) filter(where state='failed_no_send'),'uncertain',count(*) filter(where state='uncertain'),'send_started',count(*) filter(where state='send_started')) from collect_hybrid.sms_notification_outbox;"))
    case('Overview actual nonempty current-posted RWF totals match canonical payments', lambda: check(snapshot['posted'] == expected_posted(snapshot) and snapshot['posted']['count'] > 0 and int(snapshot['posted']['value_rwf']) > 0))
    case('Overview paused backlog and actionable counts match actual outbox states', lambda: check(snapshot['receipts'] == expected_receipts() and snapshot['receipts']['queued'] >= 3 and snapshot['receipts']['uncertain'] >= 1 and snapshot['receipts']['failed_no_send'] >= 1 and sql("select enabled from public.feature_flags where key='hybrid_sms_notifications';") == 'f'))
    case('Overview exact bounded response contains only aggregate fields', lambda: check(set(snapshot) == {'contract_version','scope','country_code','timezone','checked_at','sample_valid_until','day_start','day_end','posted','receipts_state','receipts'} and set(snapshot['posted']) == {'count','value_rwf'} and set(snapshot['receipts']) == {'queued','awaiting_confirmation','oldest_pending_at','failed_no_send','uncertain','send_started'}))
    date = lambda v: datetime.datetime.fromisoformat(v.replace('Z', '+00:00'))
    case('Overview Kigali day is UTC22-to-22 with a 60-second sample interval', lambda: check(snapshot['country_code'] == 'RW' and snapshot['scope'] == 'rwanda_momo' and snapshot['timezone'] == 'Africa/Kigali' and date(snapshot['day_start']).hour == 22 and (date(snapshot['day_end']) - date(snapshot['day_start'])).total_seconds() == 86400 and (date(snapshot['sample_valid_until']) - date(snapshot['checked_at'])).total_seconds() == 60))
    for country in ["'KE'", "''", "' rwx '"]:
        case('Overview rejects unsupported country ' + country, lambda country=country: u.expected_error(db, 'select public.admin_receipt_overview_v1(' + country + ');', '22023', 'overview_country_invalid'))
    case('Overview normalizes supported country and null default', lambda: check(call("select public.admin_receipt_overview_v1(' rw ');")['country_code'] == call('select public.admin_receipt_overview_v1(null);')['country_code'] == 'RW'))
    rows = listing()
    (report / 'observed-transactions.json').write_text(json.dumps(rows, indent=2) + '\n')
    by_ref = {row['reference']: row for row in rows['rows'] if row['reference']}
    case('transaction lifecycle exposes nine actual raw observations with Rwanda scope', lambda: check(rows['total'] == len(rows['rows']) == 9 and all(row['country_code'] == 'RW' and row['rail'] == 'rw_momo' for row in rows['rows'])))
    case('allocated review observation remains unverified and unposted', lambda: check(by_ref['COMBINED-03']['lifecycle']['allocation'] == 'allocated' and by_ref['COMBINED-03']['lifecycle']['verification'] == 'pending' and by_ref['COMBINED-03']['lifecycle']['ledger'] == 'not_posted' and by_ref['COMBINED-03']['lifecycle']['notification'] == 'not_created'))
    case('balanced posted receipt has distinct confirmation ledger and paused queue evidence', lambda: check(by_ref['COMBINED-01']['lifecycle'] == {'contract_version':1,'allocation':'allocated','verification':'confirmation_recorded','ledger':'posted','notification':'queued','evidence_limit':'confirmation_record_is_not_external_settlement_proof'}))
    case('deliberate no-consent suppression does not alter posted financial evidence', lambda: check(by_ref['COMBINED-02']['lifecycle']['ledger'] == 'posted' and by_ref['COMBINED-02']['lifecycle']['verification'] == 'confirmation_recorded' and by_ref['COMBINED-02']['lifecycle']['notification'] == 'not_created'))
    case('reversed canonical receipt and compensating lines are independently visible', lambda: check(by_ref['COMBINED-06']['lifecycle']['ledger'] == 'reversed' and by_ref['COMBINED-06']['lifecycle']['verification'] == 'confirmation_recorded'))
    case('parser pending and failure do not imply verification or journal state', lambda: check({row['lifecycle']['allocation'] for row in rows['rows'] if row['reference'] is None} == {'pending_parse','parse_failed'} and all(row['lifecycle']['verification'] == 'pending' and row['lifecycle']['ledger'] == 'not_posted' for row in rows['rows'] if row['reference'] is None)))
    case('raw SMS bodies and complete payer identity remain absent from list', lambda: check('Synthetic combined raw body' not in json.dumps(rows) and 'Synthetic combined payer' not in json.dumps(rows) and '+250788971' not in json.dumps(rows)))
    case('actual source observation yesterday does not hide today canonical posting', lambda: check(date(by_ref['COMBINED-01']['created_at']) < date(snapshot['day_start']) and snapshot['posted'] == expected_posted(snapshot)))
    for name, query in queries:
        for api_role in ['anon','service_role']:
            case(api_role + ' cannot invoke new ' + name + ' read', lambda query=query, api_role=api_role: u.expected_error(db, query, '42501', role=api_role))
        case(name + ' denies nonexistent current session', lambda query=query: u.expected_error(db, query, '42501', sid=str(uuid.uuid4())))
    for function in ["collect_hybrid.admin_overview_authorized('%s','%s','overview.read')" % (UID,SID), "collect_security.transaction_read_authority('payments.read')", "collect_security.transaction_lifecycle('%s',true)" % ids(1)[0]]:
        case('authenticated cannot call private read helper ' + function.split('(')[0], lambda function=function: u.expected_error(db,'select '+function+';', '42501'))
    for table in ['sms_notification_outbox','sms_notification_attempts','receipt_business_events']:
        case('authenticated direct private ' + table + ' access refused', lambda table=table: u.expected_error(db,'select * from collect_hybrid.'+table+' limit 1;', '42501'))
    def altered(mutation, query):
        response = sql('begin;' + mutation + u.auth() + query + 'rollback;')
        return json.loads(response.splitlines()[-1])
    def denied(mutation, query):
        result = u.psql(db, 'begin;' + mutation + u.auth() + query + 'rollback;', False)
        return check(result.returncode != 0 and '42501:' in result.stderr)
    denied_notice = "delete from public.admin_role_permissions where role_id='%s' and permission_name='notifications.read';" % ROLE
    case('Overview notification denial leaves authorized posted aggregate available', lambda: check((lambda r: r['receipts_state'] == 'denied' and r['receipts'] is None and r['posted'] == snapshot['posted'])(altered(denied_notice, queries[0][1]))))
    case('transaction notification denial hides every receipt existence and state', lambda: check(all(row['lifecycle']['notification'] == 'access_required' for row in altered(denied_notice, queries[1][1])['rows'])))
    for name, query in queries:
        permission = 'overview.read' if name == 'Overview' else 'payments.read'
        mutations = [
            ('expired session', "update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='%s';" % SID),
            ('unconfirmed phone', "update auth.users set phone_confirmed_at=null where id='%s';" % UID),
            ('revoked approval', "update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp() where user_id='%s';" % UID),
            ('revoked owner grant', "update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='%s';" % UID),
            ('missing required permission', "delete from public.admin_role_permissions where role_id='%s' and permission_name='%s';" % (ROLE,permission)),
            ('session predates new approval', "update collect_admin_access.whatsapp_approvals set approved_at=clock_timestamp()+interval '1 minute' where user_id='%s';" % UID),
            ('session predates owner grant', "update public.admin_user_roles set created_at=clock_timestamp()+interval '1 minute' where user_id='%s';" % UID),
        ]
        for label, mutation in mutations:
            case(name + ' current authority denies ' + label, lambda mutation=mutation,query=query: denied(mutation,query))
    no_health = "delete from public.admin_role_permissions where role_id='%s' and permission_name='system_health.read';" % ROLE
    case('Overview requires its own permission rather than unrelated system health', lambda: check(altered(no_health,queries[0][1])['receipts_state'] == 'available'))
    case('transaction read requires its own permission rather than unrelated system health', lambda: check(altered(no_health,queries[1][1])['total'] == 9))
    for args in ['null,null,0,0','null,null,101,0','null,null,25,-1','null,null,25,100001',"null,null,25,0,'unsafe'",'repeat(\'a\',129),null',"null,repeat('x',65)",'null,null,null,0','null,null,25,null',"null,null,25,0,null"]:
        case('transaction bounded query refuses ' + args, lambda args=args: u.expected_error(db,'select public.admin_list_collect_transactions('+args+');','22023','transaction_query_invalid'))
    case('empty page beyond end retains full source total', lambda: check(listing('null,null,2,9') == {'rows': [], 'total': 9}))
    pages = [listing('null,null,1,%d' % n)['rows'][0]['id'] for n in range(9)]
    case('equal observation timestamps paginate deterministically without duplicates', lambda: check(len(set(pages)) == 9 and pages == [row['id'] for row in rows['rows']]))
    for sort, first in [('amount_desc','COMBINED-09'),('amount_asc','COMBINED-01')]:
        case('transaction deterministic ' + sort + ' order is server derived', lambda sort=sort,first=first: check(listing("null,null,9,0,'%s'"%sort)['rows'][0]['reference'] == first))
    case('parse-failed filter reports only actual parsing failure', lambda: check(listing("null,'parse_failed'")['total'] == 1))
    case('specific reference filter retains current canonical financial state', lambda: check(listing("'COMBINED-06'")['total'] == 1 and listing("'COMBINED-06'")['rows'][0]['lifecycle']['ledger'] == 'reversed'))
    case('read authorization and paging matrix leaves every business fingerprint unchanged', lambda: foundation.equal(baseline,foundation.business_fingerprint(db)))
    # Fault injection stays inside a rollback transaction in the isolated DB.
    # It exercises actual read decisions against missing/conflicting evidence.
    payment = ids(1)[2]
    fault = "alter table collect_hybrid.momo_journal_lines disable trigger user;delete from collect_hybrid.momo_journal_lines where id=(select l.id from collect_hybrid.momo_journal_lines l join collect_hybrid.momo_journal_entries j on j.id=l.journal_entry_id where j.payment_id='%s' limit 1);" % payment
    case('isolated missing journal line never reports financial posting', lambda: check(altered(fault,"select public.admin_list_collect_transactions('COMBINED-01');")['rows'][0]['lifecycle']['ledger'] == 'evidence_missing'))
    fault = "alter table public.payment_provider_confirmations disable trigger user;update public.payment_provider_confirmations set amount_rwf=amount_rwf+1 where payment_id='%s';" % payment
    case('isolated conflicting confirmation stays separate from canonical ledger', lambda: check((lambda r:r['verification']=='evidence_conflict' and r['ledger']=='posted')(altered(fault,"select public.admin_list_collect_transactions('COMBINED-01');")['rows'][0]['lifecycle'])))
    case('evidence fault injection rolls back every canonical financial byte', lambda: foundation.equal(baseline,foundation.business_fingerprint(db)))
    # Clock-boundary fixtures change timestamps only in rollback transactions;
    # no test clock or alternate read implementation is introduced.
    reset = "alter table public.payments disable trigger user;update public.payments set posted_at='%s'::timestamptz-interval '1 day' where status='posted';" % snapshot['day_start']
    for label, stamp, count in [
        ('one microsecond before Kigali midnight', "'%s'::timestamptz-interval '1 microsecond'" % snapshot['day_start'],0),
        ('exact Kigali day start inclusive', "'%s'::timestamptz" % snapshot['day_start'],1),
        ('future within current day excluded', "clock_timestamp()+interval '1 minute'",0),
        ('next Kigali day start excluded', "'%s'::timestamptz" % snapshot['day_end'],0),
    ]:
        mutation = reset + "update public.payments set posted_at=%s where id='%s';" % (stamp,payment)
        case('Overview ' + label, lambda mutation=mutation,count=count: check(altered(mutation,queries[0][1])['posted'] == {'count':count,'value_rwf':'400' if count else '0'}))
    case('Overview excludes reversed payment even when timestamp is inside today', lambda: check(altered(reset+"update public.payments set posted_at='%s' where id='%s';"%(snapshot['day_start'],ids(6)[2]),queries[0][1])['posted'] == {'count':0,'value_rwf':'0'}))
    case('Overview boundary probes restore all business fingerprints', lambda: foundation.equal(baseline,foundation.business_fingerprint(db)))
    # Actual pre-send records provide all pending/started metrics. No send API,
    # Android gateway or carrier is invoked by these server-side fixtures.
    sql("update public.feature_flags set enabled=true where key='hybrid_sms_notifications';")
    def service_result(query):
        return json.loads(sql(foundation.service(query)).splitlines()[-1])
    for n, start in [(7,False),(8,True),(9,True)]:
        job = sql("select id from collect_hybrid.sms_notification_outbox where payment_id='%s';" % ids(n)[2])
        claim = service_result("select public.collect_claim_receipt('%s','%s','combined-worker','%s');" % (UID,job,uuid.uuid4()))
        if start:
            exact = service_result("select public.collect_get_claimed_receipt('%s','%s','%s',%d);" % (UID,job,claim['claim_token'],claim['fence_version']))
            confirmation = str(uuid.uuid4())
            service_result("select public.collect_confirm_receipt('%s','%s','%s',%d,%d,'%s','%s');" % (UID,job,claim['claim_token'],claim['fence_version'],exact['destination_revision'],exact['body_sha256'],confirmation))
            attempt = service_result("select public.collect_record_send_start('%s','%s','%s',%d,'%s');" % (UID,job,claim['claim_token'],claim['fence_version'],confirmation))
            if n == 9:
                service_result("select public.collect_record_observed_outcome('%s','%s','uncertain','synthetic-combined','No carrier called; synthetic uncertain state');" % (UID,attempt['attempt_id']))
    sql("update public.feature_flags set enabled=false where key='hybrid_sms_notifications';")
    status = overview()
    (report / 'observed-overview-all-states.json').write_text(json.dumps(status,indent=2)+'\n')
    case('Overview queued awaiting failed uncertain and started counters match durable source', lambda: check(status['receipts']==expected_receipts() and all(status['receipts'][state]>0 for state in ['queued','awaiting_confirmation','failed_no_send','uncertain','send_started'])))
    case('oldest pending age derives queued and awaiting timestamps only', lambda: check(status['receipts']['oldest_pending_at']==expected_receipts()['oldest_pending_at'] and date(status['receipts']['oldest_pending_at'])<=date(status['checked_at'])))
    current = listing()
    (report / 'observed-transactions-all-states.json').write_text(json.dumps(current,indent=2)+'\n')
    r = {row['reference']:row['lifecycle'] for row in current['rows'] if row['reference']}
    case('transaction read displays actual awaiting started and uncertain independently', lambda: check(r['COMBINED-07']['notification']=='awaiting_confirmation' and r['COMBINED-08']['notification']=='send_started' and r['COMBINED-09']['notification']=='uncertain' and all(r['COMBINED-%02d'%n]['ledger']=='posted' for n in [7,8,9])))
    final = foundation.business_fingerprint(db)
    overview();listing()
    case('all-state Admin reads cannot modify finance receipts attempts or provider evidence', lambda: foundation.equal(final,foundation.business_fingerprint(db)))
    # Expiry cannot cross a currently-held read authorization proof lock.
    a = u.Session(db,'combined-overview-read');b = u.Session(db,'combined-session-expiry');sessions.extend([a,b])
    a.write('begin;'+u.auth()+queries[0][1]+"select 'COMBINED_READ_HELD';")
    a.read('COMBINED_READ_HELD')
    b.write("begin;set application_name='combined-expiry-writer';update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='%s';select 'COMBINED_EXPIRY_UPDATED';" % SID)
    time.sleep(.2)
    case('concurrent session expiry waits on actual read authority locks', lambda: truth("select exists(select 1 from pg_stat_activity where datname=current_database() and application_name='combined-expiry-writer' and wait_event_type='Lock');"))
    a.write("commit;select 'COMBINED_READ_DONE';");a.read('COMBINED_READ_DONE')
    b.read('COMBINED_EXPIRY_UPDATED')
    b.write('rollback;'+"select 'COMBINED_EXPIRY_ROLLED_BACK';");b.read('COMBINED_EXPIRY_ROLLED_BACK')
    case('after concurrent expiry rollback both authorized reads remain usable', lambda: check(overview()['receipts_state']=='available' and listing()['total']==9))
    case('combined upgrade retains original nonempty primary receipt byte-for-byte', lambda: foundation.equal(evidence['prior_receipt'],json.loads(sql("select to_jsonb(o) from collect_hybrid.sms_notification_outbox o where payment_id='99710000-0000-4000-8000-000000049999';"))))
    case('every nonempty journal still has two exactly balanced canonical lines', lambda: truth("select not exists(select 1 from collect_hybrid.momo_journal_entries e left join collect_hybrid.momo_journal_lines l on l.journal_entry_id=e.id group by e.id,e.amount_rwf having count(*)<>2 or sum(case when l.direction='debit' then l.amount_rwf else -l.amount_rwf end)<>0 or min(l.amount_rwf)<>e.amount_rwf or max(l.amount_rwf)<>e.amount_rwf);"))
    case('final group balance equals currently posted nonempty canonical payments', lambda: truth("select b.confirmed_rwf=(select sum(amount_rwf) from public.payments where collection_id=b.collection_id and status='posted') from collect_hybrid.collection_balances b where collection_id='%s';"%GROUP))
    evidence['final_business_fingerprints'] = foundation.business_fingerprint(db)
    evidence['limits'] = ['Three staged SQL files on retained schema153 only; group-share154 not installed','No full hosted124 upgrade or clean installation','API roles and synthetic claim settings exercised; no GoTrue/PostgREST/signed JWT','No production data/volume, provider authenticity, Android capture, carrier delivery or performance acceptance','Kigali day-end fixture is also future at execution; midnight-crossing branch not wall-clock executed','Prior registry source parity covers explicitly recorded prerequisites; not universal body parity']


if __name__ == '__main__':
    main()
