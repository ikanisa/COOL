#!/usr/bin/env python3
"""Task-owned, network-none PostgreSQL UAT for the bounded v3 owner workflow.

Only synthetic public curve points and local SQL role claims are used. No host
URL, credentials, private keys, Auth provider, enrollment host or sender exists.
"""
import argparse
import base64
import concurrent.futures
import datetime
import hashlib
import json
import pathlib
import time
import types
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = pathlib.Path('/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-08')
MIGRATION = ROOT / 'supabase/migrations/20261001180000_receipt_operations_enrollment_workflow.sql'
PREREQUISITE = ROOT / 'supabase/migrations/20261001110000_receipt_operational_authority.sql'
LEAF = ROOT / 'docs/release/collect-codex-goal-2026-09-30/receipt-operations-enrollment-workflow-20261001/sql'
UTC = datetime.timezone.utc


def sha(data):
    return hashlib.sha256(data).hexdigest()


def instant(delta=0):
    return (datetime.datetime.now(UTC) + datetime.timedelta(seconds=delta)).isoformat(timespec='microseconds').replace('+00:00', 'Z')


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def ident():
    return str(uuid.uuid4())


def public_key(scalar):
    # Standard generator multiplied by a synthetic public integer. No secret
    # key is generated or retained, and SQL role claims are not signature proof.
    prime = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff
    generator = (0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296,
                 0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5)

    def add(left, right):
        if left is None:
            return right
        if right is None:
            return left
        x, y = left
        rx, ry = right
        if x == rx and (y + ry) % prime == 0:
            return None
        slope = ((3*x*x - 3) * pow(2*y, -1, prime) if left == right else
                 (ry-y) * pow(rx-x, -1, prime)) % prime
        nx = (slope*slope-x-rx) % prime
        return nx, (slope*(x-nx)-y) % prime

    point, current = None, generator
    while scalar:
        if scalar & 1:
            point = add(point, current)
        current = add(current, current)
        scalar >>= 1
    data = bytes.fromhex('3059301306072a8648ce3d020106082a8648ce3d03010703420004' + '%064x%064x' % point)
    return base64.b64encode(data).decode(), sha(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-dir', required=True, type=pathlib.Path)
    args = parser.parse_args()
    report = args.report_dir.resolve()
    assert LEAF in report.parents and not report.exists()
    report.mkdir(parents=True)
    inputs = report / 'inputs'
    inputs.mkdir()
    (inputs / 'migrations').mkdir()
    marker = (SOURCE / '.collect-release-candidate.json').read_bytes()
    manifest = json.loads(marker)
    save(inputs / 'source08-marker.json', manifest)
    helper = (SOURCE / 'scripts/tests/collect_current_release_upgrade_uat.py').read_bytes()
    (inputs / 'executed-helper.py').write_bytes(helper)
    runner = pathlib.Path(__file__).read_bytes()
    (inputs / 'executed-runner.py').write_bytes(runner)
    baseline = (ROOT / '.cache/receipt-foundation-attempt8/schema-only.sql').read_bytes()
    (inputs / 'row-free-platform.sql').write_bytes(baseline)
    captured = {path: path.read_bytes() for path in [PREREQUISITE, MIGRATION]}
    for path, content in captured.items():
        (inputs / path.name).write_bytes(content)
    items = []
    for path in sorted((SOURCE / 'supabase/migrations').glob('*.sql')):
        content = path.read_bytes()
        relative = str(path.relative_to(SOURCE))
        assert sha(content) == manifest['source_files'][relative]['sha256']
        (inputs / 'migrations' / path.name).write_bytes(content)
        version, name = path.stem.split('_', 1)
        items.append(dict(version=version, name=name, path=relative, sha256=sha(content), body=content.decode()))
    assert len(items) == 177
    result = dict(scope='additive enrollment workflow on exact source08 prerequisites in fresh owned PG17.6',
                  started_at=instant(), source08_manifest_sha256=sha(marker), helper_sha256=sha(helper),
                  runner_sha256=sha(runner), baseline_sha256=sha(baseline),
                  migrations_sha256={str(path.relative_to(ROOT)): sha(content) for path, content in captured.items()},
                  checks=[], target={}, hosted_written=False, source_rows_copied=False,
                  private_key_created=False, auth_provider_tested=False, signed_jwt_tested=False,
                  signature_verified_in_sql=False, sms_sent=False, device_used=False)
    save(report / 'execution-binding.json', {k: v for k, v in result.items() if k not in ['checks', 'target']})
    module = types.ModuleType('captured_enrollment_installer')
    module.__file__ = str(inputs / 'executed-helper.py')
    exec(compile(helper, module.__file__, 'exec'), module.__dict__)
    module.ROOT, module.BASELINE = SOURCE, inputs / 'row-free-platform.sql'
    q = module.quoted

    def case(name, passed=True):
        result['checks'].append(dict(name=name, passed=bool(passed)))
        save(report / 'result.json', result)
        print(('PASS ' if passed else 'FAIL ') + name, flush=True)
        if not passed:
            raise AssertionError(name)

    try:
        with module.Target(report, 'enrollment', result['target']) as target:
            platform, _ = module.platform_shape()
            target.sql(platform, label='captured row-free platform prerequisites')
            module.apply(target, items[:124], result['target'])
            module.seed_populated(target, result['target'], case)
            module.apply(target, items[124:], result['target'])
            target.sql("begin;update auth.users set email='enrollment-owner@example.test',email_confirmed_at=clock_timestamp()where id=" + q(module.UID) +
                       ";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values(" + q(module.UID) +
                       ",'enrollment-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic enrollment workflow owner');commit;")
            preserved = [('public', 'payments'), ('collect_hybrid', 'momo_journal_entries'), ('collect_hybrid', 'momo_journal_lines'),
                         ('collect_hybrid', 'momo_balance_snapshots'), ('collect_hybrid', 'sms_notification_outbox')]
            columns = module.columns(target, preserved)
            original = module.fingerprints(target, columns)
            for path, content in captured.items():
                target.sql(content.decode(), label='captured additive ' + path.name)
                case('install ' + path.name + ' preserves canonical finance and receipts', module.fingerprints(target, columns) == original)

            def auth(actor=module.UID, session=module.SID, role='authenticated'):
                claims = dict(sub=actor, session_id=session, role=role, aal='aal1')
                return 'set local role ' + role + ";select set_config('request.jwt.claims'," + q(json.dumps(claims)) + ',true);'

            def call(expression, actor=module.UID, session=module.SID, role='authenticated'):
                return target.json('begin;' + auth(actor, session, role) + 'select ' + expression + ';commit;')

            def error(expression, code, name, prefix='', actor=module.UID, session=module.SID, role='authenticated'):
                observed = target.sql('begin;' + prefix + auth(actor, session, role) + 'select ' + expression + ';rollback;', check=False, label=name)
                case(name, observed.returncode != 0 and code + ':' in observed.stderr)

            def enroll(request, scalar, expiry, deadline):
                public, key_hash = public_key(scalar)
                return 'public.admin_enroll_receipt_operations_identity_v3(' + ','.join(map(q, [request, public, key_hash, expiry, deadline])) + ')'

            def lookup(request):
                return 'public.admin_get_receipt_operations_enrollment_request_v3(' + q(request) + ')'

            def activate(principal, request, key_hash, deadline):
                return 'public.admin_activate_receipt_operations_identity_v3(' + ','.join(map(q, [principal, request, key_hash, deadline])) + ')'

            def revoke(principal, request, key_hash, deadline, reason):
                return 'public.admin_revoke_receipt_operations_identity_v3(' + ','.join(map(q, [principal, request, key_hash, deadline, reason])) + ')'

            def counts():
                return target.json("select jsonb_build_object('identities',(select count(*)from collect_supervisor.identities),"
                                   "'legacy_requests',(select count(*)from collect_receipt_operations.owner_requests),"
                                   "'supervisor_requests',(select count(*)from collect_supervisor.owner_requests),"
                                   "'workflow_requests',(select count(*)from collect_receipt_operations.enrollment_workflow_requests));")

            signatures = ['admin_enroll_receipt_operations_identity_v3(uuid,text,text,timestamptz,timestamptz)',
                          'admin_activate_receipt_operations_identity_v3(uuid,uuid,text,timestamptz)',
                          'admin_revoke_receipt_operations_identity_v3(uuid,uuid,text,timestamptz,text)',
                          'admin_get_receipt_operations_enrollment_request_v3(uuid)', 'admin_get_receipt_operations_identity_v3(uuid)',
                          'admin_list_receipt_operations_identities_v3(integer,timestamptz,uuid)']
            for signature in signatures:
                case(signature + ' grants authenticated only', target.scalar('select has_function_privilege(\'authenticated\',' + q('public.' + signature) +
                     ",'EXECUTE')and not has_function_privilege('anon'," + q('public.' + signature) + ",'EXECUTE')and not has_function_privilege('service_role'," + q('public.' + signature) + ",'EXECUTE');") == 't')
            case('private workflow evidence has RLS and no caller table/helper access', target.scalar("select c.relrowsecurity and not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE'))from pg_class c where c.oid='collect_receipt_operations.enrollment_workflow_requests'::regclass;") == 't')

            expiry, deadline, request = instant(86_400), instant(90), ident()
            expression = enroll(request, 1, expiry, deadline)
            for name, mutation in [
                ('expired session', "update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id=" + q(module.SID) + ';'),
                ('unverified email', 'update auth.users set email_confirmed_at=null where id=' + q(module.UID) + ';'),
                ('revoked owner', 'update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=' + q(module.UID) + ';'),
                ('revoked email approval', 'update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id=' + q(module.UID) + ';'),
            ]:
                error(expression, '42501', 'enrollment refuses ' + name, prefix=mutation)
            for permission in ['admin_users.manage', 'notifications.manage', 'system_health.read']:
                error(expression, '42501', 'enrollment requires ' + permission,
                      prefix="delete from public.admin_role_permissions where permission_name=" + q(permission) + ';')
            error(enroll(ident(), 3, expiry, instant(-1)), '55000', 'already expired request cannot mutate')
            error(enroll(ident(), 3, expiry, instant(121)), '22023', 'request deadline cannot exceed 120 seconds')
            error(enroll(ident(), 3, instant(31*86_400), instant(90)), '22023', 'identity expiry retains existing thirty-day bound')
            enrolled = call(expression)
            save(report / 'observed-enroll-v3.json', enrolled)
            save(report / 'observed-enroll-input-v3.json', {'request_id': request, 'public_key_spki_base64': public_key(1)[0],
                 'key_sha256': public_key(1)[1], 'identity_expires_at': expiry, 'request_expires_at': deadline})
            expected_receipt = {'contract_version', 'action', 'request_id', 'principal_id', 'state_at_action', 'scope', 'key_sha256',
                                'identity_expires_at', 'recorded_at', 'request_expires_at'}
            case('enrollment exact receipt binds scope key identity expiry and original request deadline', set(enrolled) == expected_receipt and
                 enrolled['contract_version'] == 3 and enrolled['action'] == 'enroll' and enrolled['request_id'] == request and
                 enrolled['state_at_action'] == 'pending' and enrolled['scope'] == 'rw_receipt_operations' and enrolled['key_sha256'] == public_key(1)[1] and
                 enrolled['identity_expires_at'] == expiry and enrolled['request_expires_at'] == deadline)
            principal, key_hash = enrolled['principal_id'], enrolled['key_sha256']
            before = counts()
            case('exact live-deadline duplicate returns immutable receipt without new identity or record', call(expression) == enrolled and counts() == before)
            error(enroll(request, 1, expiry, instant(95)), '22023', 'changed original deadline cannot reuse reserved request')
            observed = call(lookup(request))
            save(report / 'observed-enroll-lookup-v3.json', observed)
            expected_lookup = {'contract_version', 'request_id', 'action', 'status', 'checked_at', 'sample_valid_until', 'request_expires_at', 'receipt'}
            case('original enrollment lookup returns exact receipt and deadline with sixty-second freshness', set(observed) == expected_lookup and
                 observed['receipt'] == enrolled and observed['action'] == 'enroll' and observed['status'] == 'recorded' and
                 (datetime.datetime.fromisoformat(observed['sample_valid_until'].replace('Z', '+00:00')) - datetime.datetime.fromisoformat(observed['checked_at'].replace('Z', '+00:00'))).total_seconds() == 60)
            error(lookup(request), '42501', 'historical receipt lookup still requires current authority', prefix='update auth.users set email_confirmed_at=null where id=' + q(module.UID) + ';')

            activation_request, activation_deadline = ident(), instant(90)
            error(activate(principal, activation_request, key_hash, activation_deadline), '55000', 'activation without recent possession proof rolls back all workflow writes')
            proof_request = ident()
            proof = call('public.receipt_operations_execute_v2(' + ','.join([q(principal), q(proof_request), q(key_hash), q('a'*64), 'clock_timestamp()', "'prove_key'", "'{}'::jsonb"]) + ')', role='service_role')
            case('synthetic service fixture uses actual pending-key proof RPC without financial or sender action', proof['send_action'] is False and proof['financial_action'] is False)

            def held_lock(lock_sql, marker, during):
                with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                    pending = pool.submit(target.sql, 'begin;set local application_name=' + q(marker) + ';' + lock_sql + 'select pg_sleep(2);commit;', label=marker)
                    for _ in range(100):
                        if target.scalar('select exists(select 1 from pg_stat_activity where application_name=' + q(marker) + "and wait_event='PgSleep');") == 't':
                            break
                        time.sleep(.01)
                    else:
                        raise AssertionError('lock fixture did not start')
                    during()
                    pending.result()

            blocked = ident()
            def request_delay():
                progress = call(lookup(blocked)); save(report / 'observed-in-progress-v3.json', progress)
                case('trylock lookup reports real contention without receipt or deadline', progress['status'] == 'in_progress' and progress['action'] is None and progress['receipt'] is None and progress['request_expires_at'] is None)
                pub, kh = public_key(3)
                delayed = 'public.admin_enroll_receipt_operations_identity_v3(' + ','.join([q(blocked), q(pub), q(kh), q(expiry), "clock_timestamp()+interval '0.3 seconds'"]) + ')'
                error(delayed, '55000', 'request deadline is rechecked after actual UUID lock wait')
            held_lock("select pg_advisory_xact_lock(hashtextextended('collect-operations-owner:" + blocked + "',0));", 'workflow-original-lock', request_delay)
            absent = call(lookup(blocked)); save(report / 'observed-not-recorded-v3.json', absent)
            case('post-deadline original lookup proves current absence with no invented retained deadline', absent['status'] == 'not_recorded' and absent['receipt'] is None and absent['request_expires_at'] is None)
            before = counts()
            held_lock('select id from collect_supervisor.identities where id=' + q(principal) + 'for update;', 'workflow-identity-lock',
                      lambda: error(activate(principal, activation_request, key_hash, instant(.3)), '55000', 'expiry after inner identity lock rolls back activation and both evidence namespaces'))
            case('late v2 delegation leaves pending identity and no request evidence', counts() == before and target.scalar('select state from collect_supervisor.identities where id=' + q(principal) + ';') == 'pending')
            session_blocked = ident()
            target.sql('update auth.sessions set not_after=clock_timestamp()+interval \'0.7 seconds\'where id=' + q(module.SID) + ';')
            try:
                held_lock("select pg_advisory_xact_lock(hashtextextended('collect-operations-owner:" + session_blocked + "',0));", 'workflow-authority-lock',
                          lambda: error(enroll(session_blocked, 4, expiry, instant(90)), '42501', 'current owner session expiry is rechecked after UUID lock wait'))
            finally:
                target.sql('update auth.sessions set not_after=clock_timestamp()+interval \'1 hour\'where id=' + q(module.SID) + ';')
            activated = call(activate(principal, activation_request, key_hash, instant(90)))
            save(report / 'observed-activate-v3.json', activated)
            case('activation exact receipt retains original key and identity expiry', set(activated) == expected_receipt and activated['action'] == 'activate' and activated['state_at_action'] == 'active' and activated['key_sha256'] == key_hash and activated['identity_expires_at'] == expiry)
            activation_lookup = call(lookup(activation_request)); save(report / 'observed-activate-lookup-v3.json', activation_lookup)
            case('activation can be recovered by its exact original request lookup', activation_lookup['receipt'] == activated and activation_lookup['action'] == 'activate')

            legacy_request = ident(); pub, legacy_key = public_key(2)
            legacy = call('public.admin_enroll_receipt_operations_identity_v2(' + ','.join(map(q, [legacy_request, pub, legacy_key, expiry])) + ')')
            before = counts()
            error(enroll(legacy_request, 2, expiry, instant(90)), '22023', 'legacy v2 reserved request cannot acquire a new v3 mutation or deadline')
            error(lookup(legacy_request), '22023', 'legacy recorded owner UUID cannot be mislabeled absent by v3 lookup')
            case('legacy collision preserves original identity and evidence', counts() == before)

            other_session = ident()
            target.sql("begin;update auth.users set email='other-enrollment-owner@example.test',email_confirmed_at=clock_timestamp()where id=" + q(module.OTHER) +
                       ";insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values(" + q(module.OTHER) +
                       ",'other-enrollment-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic second current owner');"
                       "insert into public.admin_user_roles(user_id,role_id,reason,created_at)select " + q(module.OTHER) + ",id,'Synthetic owner',clock_timestamp()-interval '1 minute'from public.admin_roles where name='platform_owner';"
                       'insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(' + q(other_session) + ',' + q(module.OTHER) + ",clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');commit;")
            hidden = call(lookup(request), actor=module.OTHER, session=other_session)
            case('another current owner cannot inspect original actor receipt or deadline', hidden['status'] == 'not_recorded' and hidden['action'] is None and hidden['receipt'] is None and hidden['request_expires_at'] is None)
            error(expression, '22023', 'another actor cannot replay the original enrollment request', actor=module.OTHER, session=other_session)
            fresh_session = ident()
            target.sql('insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values(' + q(fresh_session) + ',' + q(module.UID) + ",clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');")
            case('same actor fresh authenticated session can recover prior immutable receipt', call(lookup(request), session=fresh_session)['receipt'] == enrolled)
            foreign = call(enroll(ident(), 40, expiry, instant(90)), actor=module.OTHER, session=other_session)
            foreign_proof = call('public.receipt_operations_execute_v2(' + ','.join([q(foreign['principal_id']), q(ident()), q(foreign['key_sha256']), q('b'*64), 'clock_timestamp()', "'prove_key'", "'{}'::jsonb"]) + ')', role='service_role')
            before = counts()
            error(activate(foreign['principal_id'], ident(), foreign['key_sha256'], instant(90)), '42501', 'activation refuses another current owner pending identity with valid possession proof')
            case('foreign identity activation refusal preserves pending source and both request namespaces', counts() == before and
                 target.scalar('select state from collect_supervisor.identities where id=' + q(foreign['principal_id']) + ';') == 'pending' and foreign_proof['send_action'] is False)

            short_id, short_enrollment = ident(), ident(); short_pub, short_key = public_key(43)
            target.sql('insert into collect_supervisor.identities(id,enrollment_request_id,owner_actor_id,owner_session_id,public_key_spki_base64,key_sha256,scope,state,created_at,expires_at)values(' +
                       ','.join(map(q, [short_id, short_enrollment, module.UID, module.SID, short_pub, short_key])) + ",'rw_receipt_operations','pending',clock_timestamp()-interval '1 minute',clock_timestamp()+interval '1.5 seconds');")
            call('public.receipt_operations_execute_v2(' + ','.join([q(short_id), q(ident()), q(short_key), q('c'*64), 'clock_timestamp()', "'prove_key'", "'{}'::jsonb"]) + ')', role='service_role')
            target.sql("create function public.synthetic_identity_delay()returns trigger language plpgsql as $$begin if new.id=" + q(short_id) + "::uuid then perform pg_sleep(2);end if;return new;end$$;create trigger synthetic_identity_delay after update on collect_supervisor.identities for each row execute function public.synthetic_identity_delay();")
            try:
                before = counts()
                error(activate(short_id, ident(), short_key, instant(90)), '55000', 'identity expiry after delegated activation rolls back instead of emitting invalid receipt')
                case('late source expiry preserves pending identity and both request namespaces', counts() == before and
                     target.scalar('select state from collect_supervisor.identities where id=' + q(short_id) + ';') == 'pending')
            finally:
                target.sql('drop trigger synthetic_identity_delay on collect_supervisor.identities;drop function public.synthetic_identity_delay();')
            shadow_pub, shadow_key = public_key(41)
            shadow_request = ident()
            shadow = call('public.admin_enroll_receipt_supervisor_v1(' + ','.join(map(q, [shadow_request, shadow_pub, shadow_key, expiry])) + ')')
            for scalar in range(10, 36):
                call(enroll(ident(), scalar, expiry, instant(90)))
            row_keys = {'principal_id', 'key_sha256', 'state', 'scope', 'created_at', 'expires_at', 'activated_at', 'revoked_at'}
            get = call('public.admin_get_receipt_operations_identity_v3(' + q(principal) + ')'); save(report / 'observed-identity-active-v3.json', get)
            case('identity get is fresh redacted and exact source state', get['found'] and set(get['identity']) == row_keys and get['identity']['state'] == 'active' and get['identity']['key_sha256'] == key_hash)
            case('identity get hides other owner', call('public.admin_get_receipt_operations_identity_v3(' + q(foreign['principal_id']) + ')')['found'] is False)
            rows, cursor, pages = [], None, []
            while True:
                expression = 'public.admin_list_receipt_operations_identities_v3(2,' + ('null,null' if cursor is None else q(cursor['created_at']) + ',' + q(cursor['principal_id'])) + ')'
                page = call(expression); pages.append(page); rows.extend(page['rows']); cursor = page['next_cursor']
                if cursor is None:
                    break
                assert len(pages) < 50
            save(report / 'observed-identity-pages-v3.json', pages)
            own_count = int(target.scalar("select count(*)from collect_supervisor.identities where owner_actor_id=" + q(module.UID) + "and scope='rw_receipt_operations';"))
            case('bounded tuple pagination enumerates each own operations identity once without foreign or shadow rows', len(rows) == own_count and len({row['principal_id'] for row in rows}) == own_count and all(set(row) == row_keys and row['scope'] == 'rw_receipt_operations' for row in rows) and all(len(page['rows']) <= 2 for page in pages))
            error('public.admin_list_receipt_operations_identities_v3(26,null,null)', '22023', 'directory rejects oversized page')
            error('public.admin_list_receipt_operations_identities_v3(2,clock_timestamp(),null)', '22023', 'directory rejects unpaired cursor')
            reason = 'Replace compromised credential – owner request'
            error(revoke(principal, ident(), 'f'*64, instant(90), reason), '42501', 'v3 revoke retains exact current key binding')
            error(revoke(principal, ident(), key_hash, instant(90), reason), '42501', 'another current owner cannot revoke this actor identity', actor=module.OTHER, session=other_session)
            error(revoke(shadow['principal_id'], ident(), shadow_key, instant(90), reason), '42501', 'v3 revoke refuses shadow scope identity')
            for invalid_reason in ['too few', 'r'*501]:
                error(revoke(principal, ident(), key_hash, instant(90), invalid_reason), '22023', 'v3 revoke rejects reason length ' + str(len(invalid_reason)))
            error(revoke(principal, ident(), key_hash, instant(-1), reason), '55000', 'expired v3 revoke request cannot mutate')
            error(revoke(principal, ident(), key_hash, instant(121), reason), '22023', 'v3 revoke request deadline cannot exceed 120 seconds')
            blocked_revoke = ident(); before = counts()
            held_lock('select id from collect_supervisor.identities where id=' + q(principal) + 'for update;', 'workflow-revoke-identity-lock',
                      lambda: error(revoke(principal, blocked_revoke, key_hash, instant(.3), reason), '55000', 'v3 revoke deadline is rechecked after identity lock wait'))
            case('late v3 revoke preserves active identity and all three request namespaces', counts() == before and target.scalar('select state from collect_supervisor.identities where id=' + q(principal) + ';') == 'active')
            second_lock_revoke = ident(); before = counts()
            def blocked_supervisor():
                progress = call(lookup(second_lock_revoke))
                case('v3 lookup recognizes original legacy-v1 namespace contention', progress['status'] == 'in_progress' and progress['receipt'] is None)
                error(revoke(principal, second_lock_revoke, key_hash, instant(.3), reason), '55000', 'v3 revoke deadline is rechecked after legacy-v1 UUID lock wait')
            held_lock("select pg_advisory_xact_lock(hashtextextended('collect-supervisor-owner:" + second_lock_revoke + "',0));", 'workflow-revoke-supervisor-lock', blocked_supervisor)
            case('legacy-v1 lock expiry leaves active source and all evidence unchanged', counts() == before and target.scalar('select state from collect_supervisor.identities where id=' + q(principal) + ';') == 'active')
            authority_revoke = ident()
            target.sql('update auth.sessions set not_after=clock_timestamp()+interval \'0.7 seconds\'where id=' + q(module.SID) + ';')
            try:
                held_lock("select pg_advisory_xact_lock(hashtextextended('collect-supervisor-owner:" + authority_revoke + "',0));", 'workflow-revoke-authority-lock',
                          lambda: error(revoke(principal, authority_revoke, key_hash, instant(90), reason), '42501', 'v3 revoke renews current session authority after legacy-v1 lock wait'))
            finally:
                target.sql('update auth.sessions set not_after=clock_timestamp()+interval \'1 hour\'where id=' + q(module.SID) + ';')
            target.sql("create function public.synthetic_revoke_delay()returns trigger language plpgsql as $$begin if new.id=" + q(principal) + "::uuid and new.state='revoked' then perform pg_sleep(2);end if;return new;end$$;create trigger synthetic_revoke_delay after update on collect_supervisor.identities for each row execute function public.synthetic_revoke_delay();")
            try:
                before = counts()
                error(revoke(principal, ident(), key_hash, instant(.3), reason), '55000', 'v3 revoke deadline after v1 delegation rolls back late mutation')
                case('late delegated revoke leaves active identity and all three evidence namespaces unchanged', counts() == before and
                     target.scalar('select state from collect_supervisor.identities where id=' + q(principal) + ';') == 'active')
            finally:
                target.sql('drop trigger synthetic_revoke_delay on collect_supervisor.identities;drop function public.synthetic_revoke_delay();')

            revoke_request, revoke_deadline = ident(), instant(90)
            revoke_expression = revoke(principal, revoke_request, key_hash, revoke_deadline, '  ' + reason + '  ')
            before = counts()
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(lambda _: call(revoke_expression), range(2)))
            revoked = results[0]
            after = counts()
            case('concurrent same UUID revoke produces one mutation and exact retained receipt', results[0] == results[1] and
                 after['identities'] == before['identities'] and after['legacy_requests'] == before['legacy_requests'] and
                 after['supervisor_requests'] == before['supervisor_requests'] + 1 and after['workflow_requests'] == before['workflow_requests'] + 1)
            expected_revoke = expected_receipt | {'reason_sha256'}
            case('v3 revoke receipt binds trimmed UTF8 reason digest without raw reason', set(revoked) == expected_revoke and revoked['action'] == 'revoke' and
                 revoked['state_at_action'] == 'revoked' and revoked['reason_sha256'] == sha(reason.encode()) and revoked['key_sha256'] == key_hash and
                 revoked['identity_expires_at'] == expiry and revoked['request_expires_at'] == revoke_deadline and reason not in json.dumps(revoked))
            save(report / 'observed-revoke-v3.json', revoked)
            save(report / 'observed-revoke-input-v3.json', {'principal_id': principal, 'request_id': revoke_request, 'key_sha256': key_hash,
                 'identity_expires_at': expiry, 'request_expires_at': revoke_deadline, 'reason': reason, 'reason_sha256': sha(reason.encode())})
            error(revoke(principal, revoke_request, key_hash, revoke_deadline, 'Different withdrawal reason'), '22023', 'same original UUID cannot alter retained revoke reason')
            error(revoke(principal, ident(), key_hash, instant(90), reason), '55000', 'new UUID cannot make a fresh mutation on already revoked identity')
            revoke_lookup = call(lookup(revoke_request), session=fresh_session); save(report / 'observed-revoke-lookup-v3.json', revoke_lookup)
            case('same actor fresh session recovers exact original v3 revoke receipt', set(revoke_lookup) == expected_lookup and revoke_lookup['status'] == 'recorded' and
                 revoke_lookup['action'] == 'revoke' and revoke_lookup['receipt'] == revoked and revoke_lookup['request_expires_at'] == revoke_deadline)
            hidden_revoke = call(lookup(revoke_request), actor=module.OTHER, session=other_session)
            case('other actor cannot read retained revoke receipt or reason digest', hidden_revoke['status'] == 'not_recorded' and hidden_revoke['receipt'] is None and hidden_revoke['action'] is None)
            case('private v3 revoke input retains reason hash and immutable expiry but no raw reason',
                 reason not in target.scalar('select input::text from collect_receipt_operations.enrollment_workflow_requests where request_id=' + q(revoke_request) + ';') and
                 revoked['reason_sha256'] in target.scalar('select input::text from collect_receipt_operations.enrollment_workflow_requests where request_id=' + q(revoke_request) + ';'))
            error('public.receipt_operations_execute_v2(' + ','.join([q(principal), q(ident()), q(key_hash), q('d'*64), 'clock_timestamp()', "'prove_key'", "'{}'::jsonb"]) + ')',
                  '42501', 'actual operations service boundary refuses revoked key', role='service_role')
            get_revoked = call('public.admin_get_receipt_operations_identity_v3(' + q(principal) + ')'); save(report / 'observed-identity-revoked-v3.json', get_revoked)
            case('existing governed revoke is visible while immutable identity/key/expiry remain', revoked['state_at_action'] == 'revoked' and get_revoked['identity']['state'] == 'revoked' and get_revoked['identity']['revoked_at'] is not None and get_revoked['identity']['key_sha256'] == key_hash and get_revoked['identity']['expires_at'] == expiry)
            case('historical activation lookup remains historical after revoke', call(lookup(activation_request))['receipt'] == activated)
            expired_id, expired_request = ident(), ident(); expired_pub, expired_key = public_key(42)
            target.sql('insert into collect_supervisor.identities(id,enrollment_request_id,owner_actor_id,owner_session_id,public_key_spki_base64,key_sha256,scope,state,created_at,expires_at,activated_at)values(' +
                       ','.join(map(q, [expired_id, expired_request, module.UID, module.SID, expired_pub, expired_key])) + ",'rw_receipt_operations','active',clock_timestamp()-interval '1 day',clock_timestamp()-interval '1 hour',clock_timestamp()-interval '1 day');")
            expired = call('public.admin_get_receipt_operations_identity_v3(' + q(expired_id) + ')'); save(report / 'observed-identity-expired-active-v3.json', expired)
            case('expired retained identity keeps actual active state rather than invented expired state', expired['identity']['state'] == 'active' and datetime.datetime.fromisoformat(expired['identity']['expires_at'].replace('Z', '+00:00')) < datetime.datetime.now(UTC))
            expired_revoked = call(revoke(expired_id, ident(), expired_key, instant(90), reason)); save(report / 'observed-revoke-expired-active-v3.json', expired_revoked)
            case('expired active identity may be revoked with retained immutable expiry', expired_revoked['state_at_action'] == 'revoked' and
                 expired_revoked['identity_expires_at'] == expired['identity']['expires_at'] and expired_revoked['reason_sha256'] == sha(reason.encode()))
            pending_revoked = call(revoke(short_id, ident(), short_key, instant(90), reason)); save(report / 'observed-revoke-expired-pending-v3.json', pending_revoked)
            case('expired pending identity may be revoked without activation or possession replay', pending_revoked['state_at_action'] == 'revoked' and
                 target.scalar('select activated_at is null from collect_supervisor.identities where id=' + q(short_id) + ';') == 't')
            legacy_v1_request = ident()
            call('public.admin_revoke_receipt_supervisor_v1(' + ','.join(map(q, [shadow['principal_id'], legacy_v1_request, shadow_key])) + ')')
            before = counts()
            for collision, name in [(enroll(legacy_v1_request, 60, expiry, instant(90)), 'enroll'),
                 (activate(legacy['principal_id'], legacy_v1_request, legacy_key, instant(90)), 'activate'),
                 (revoke(legacy['principal_id'], legacy_v1_request, legacy_key, instant(90), reason), 'revoke')]:
                error(collision, '22023', 'v3 ' + name + ' refuses original UUID recorded in legacy-v1 namespace')
            error(lookup(legacy_v1_request), '22023', 'v3 lookup refuses legacy-v1 recorded UUID instead of false absence')
            case('legacy-v1 UUID collisions leave source and all request namespaces unchanged', counts() == before)
            before = counts()
            target.sql("create function public.synthetic_workflow_failure()returns trigger language plpgsql as $$begin raise exception 'synthetic_workflow_failure'using errcode='55000';end$$;create trigger synthetic_workflow_failure before insert on collect_receipt_operations.enrollment_workflow_requests for each row execute function public.synthetic_workflow_failure();")
            try:
                error(enroll(ident(), 50, expiry, instant(90)), '55000', 'workflow persistence failure atomically rolls back delegated v2 enrollment')
                case('persistence failure leaves no identity or either owner request', counts() == before)
                error(revoke(legacy['principal_id'], ident(), legacy_key, instant(90), reason), '55000', 'workflow persistence failure atomically rolls back delegated v1 revoke')
                case('failed revoke persistence preserves pending source and all request namespaces', counts() == before and
                     target.scalar('select state from collect_supervisor.identities where id=' + q(legacy['principal_id']) + ';') == 'pending')
            finally:
                target.sql('drop trigger synthetic_workflow_failure on collect_receipt_operations.enrollment_workflow_requests;drop function public.synthetic_workflow_failure();')
            for operation in ['update collect_receipt_operations.enrollment_workflow_requests set action=action;', 'delete from collect_receipt_operations.enrollment_workflow_requests;']:
                error_result = target.sql(operation, check=False)
                case('immutable workflow rejects ' + operation.split()[0], error_result.returncode != 0 and '55000:' in error_result.stderr)
            case('workflow operations leave canonical finance and receipt fingerprints unchanged', module.fingerprints(target, columns) == original)
            case('identity directory and owner recovery never return SPKI/session/input/source bodies', all(not any(field in json.dumps(value) for field in ['public_key_spki_base64', 'owner_session_id', 'input']) for value in [observed, activation_lookup, get, get_revoked, pages]))
            save(report / 'observed-fixture-manifest.json', {'contract_version': 3, 'receipt_keys': sorted(expected_receipt), 'revoke_receipt_keys': sorted(expected_revoke), 'lookup_keys': sorted(expected_lookup), 'identity_keys': sorted(row_keys), 'fixture_source': 'actual isolated SQL API outputs'})
        result['status'] = 'pass'
    except BaseException as error:
        result['status'], result['error'] = 'failed', str(error)
        raise
    finally:
        result['migration_source_drift'] = [str(path.relative_to(ROOT)) for path, content in captured.items() if path.read_bytes() != content]
        result['runner_unchanged'] = sha(pathlib.Path(__file__).read_bytes()) == result['runner_sha256']
        result['finished_at'] = instant()
        if result['migration_source_drift'] or not result['runner_unchanged']:
            result['status'] = 'failed_source_drift'
        save(report / 'result.json', result)


if __name__ == '__main__':
    main()
