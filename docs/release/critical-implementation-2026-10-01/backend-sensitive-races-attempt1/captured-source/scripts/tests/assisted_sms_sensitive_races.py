"""Actual confirmation/send-start races inside the task-owned SQL UAT target.

This is invoked only by the captured current-migration runner. No connection
URL, provider, production stub or alternative financial policy is accepted.
"""
import concurrent.futures
import uuid


def run(*, target, fixture, actor, sid, claims, reset_actor, start, wait_for,
        case, quoted):
    q = quoted
    reset_actor()
    # Reuse the source-bound canonical positive setup, excluding its test-only
    # temp table assertions. Every job comes from the real financial API.
    profile = fixture.split('update public.profiles set country_code=', 1)[1]
    profile = 'update public.profiles set country_code=' + profile.split(';', 1)[0] + ';'
    setup = fixture.split('savepoint positive_pipeline;', 1)[1]
    setup = setup.split('insert into assisted_values', 1)[0]
    target.sql('begin;' + profile + setup + 'commit;',
               label='canonical synthetic positive setup for actual sensitive races')
    group = '99440000-0000-4000-8000-000000000071'
    member = '99440000-0000-4000-8000-000000000072'

    def prepare(operation):
        payment = str(uuid.uuid4())
        reference = 'ASSISTED-RACE-' + uuid.uuid4().hex
        target.sql("begin;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"
                   "insert into public.payments(id,collection_id,member_record_id,receiver_user_id,"
                   "receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,posted_at)"
                   "values(" + ','.join([q(payment), q(group), q(member), q(actor),
                       "encode(extensions.digest('+250788994401','sha256'),'hex')", '100', q(reference),
                       "'mtn_momo'", "'manual_admin'", "'review'", 'null']) + ');'
                   'select public.confirm_provider_payment(' + ','.join([
                       q(payment), "'mtn_momo'", q(reference), q('CONF-' + reference),
                       "encode(extensions.digest('+250788994401','sha256'),'hex')", '100',
                       'clock_timestamp()', "repeat('c',64)"]) + ');commit;',
                   label='new canonical financial job for ' + operation + ' race')
        job = target.json('select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id=' + q(payment) + ';')
        claim = target.json('begin;' + claims + 'select public.collect_claim_receipt_v2(' +
                            ','.join([q(actor), q(sid), q(job['id']), "'assisted-sensitive-race'", q(str(uuid.uuid4()))]) + ');commit;')
        assert claim['ok'] and claim['claim_token'], 'Real claim prerequisite failed'
        confirmation = str(uuid.uuid4())
        confirm_sql = 'select public.collect_confirm_receipt_v2(' + ','.join([
            q(actor), q(sid), q(job['id']), q(claim['claim_token']), str(claim['fence_version']),
            str(job['destination_revision']), q(job['body_sha256']), q(confirmation)]) + ');'
        send_sql = 'select public.collect_record_send_start_v2(' + ','.join([
            q(actor), q(sid), q(job['id']), q(claim['claim_token']), str(claim['fence_version']), q(confirmation)]) + ');'
        if operation == 'send_start':
            allowed = target.json('begin;' + claims + confirm_sql + 'commit;')
            assert allowed['ok'], 'Real confirmation prerequisite failed'
        return job, confirmation, confirm_sql if operation == 'confirmation' else send_sql

    def snapshot(job_id):
        condition = q(job_id)
        entries = [
            ('outbox', 'collect_hybrid.sms_notification_outbox', 'id', 'id'),
            ('confirmation', 'collect_hybrid.sms_notification_confirmations', 'outbox_id', 'id'),
            ('attempt', 'collect_hybrid.sms_notification_attempts', 'outbox_id', 'id'),
            ('private_provenance', 'collect_security.assisted_sms_session_evidence', 'outbox_id', 'capability_kind,capability_id'),
            ('audit', 'public.audit_logs', 'entity_id', 'id'),
        ]
        values = []
        for name, relation, key, ordering in entries:
            values += [q(name), "(select coalesce(jsonb_agg(to_jsonb(r)order by " + ordering +
                       "),'[]'::jsonb)from " + relation + ' r where ' + key + '::text=' + condition + ')']
        return target.json('select jsonb_build_object(' + ','.join(values) + ');')

    def provenance_survives(operation, job, confirmation):
        kind = 'confirmation' if operation == 'confirmation' else 'attempt'
        evidence = target.json("select coalesce(jsonb_agg(to_jsonb(e)),'[]')from collect_security.assisted_sms_session_evidence e"
                               ' where outbox_id=' + q(job['id']) + ' and capability_kind=' + q(kind) + ';')
        public_action = 'collect_confirm_receipt_v2' if operation == 'confirmation' else 'collect_record_send_start_v2'
        audited = target.scalar('select exists(select 1 from public.audit_logs where entity_id::text=' + q(job['id']) +
                                " and metadata->>'operation'=" + q(public_action) +
                                " and metadata->>'originating_session_id'=" + q(sid) + ');') == 't'
        return len(evidence) == 1 and evidence[0]['operator_user_id'] == actor and evidence[0]['originating_session_id'] == sid \
            and evidence[0]['body_sha256'] == job['body_sha256'] and audited \
            and (kind != 'confirmation' or evidence[0]['capability_id'] == confirmation)

    revocations = {
        'logout': 'delete from auth.sessions where id=' + q(sid) + ';',
        'session_expiry': "update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id=" + q(sid) + ';',
        'user_deletion': 'update auth.users set deleted_at=clock_timestamp()where id=' + q(actor) + ';',
        'role_revocation': 'update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=' + q(actor) + ';',
        'approval_revocation': 'update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id=' + q(actor) + ';',
        'permission_revocation': "delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name='platform_owner')and permission_name='notifications.manage';",
    }
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        for operation in ('confirmation', 'send_start'):
            for label, mutation in revocations.items():
                for ordering in ('revocation_first', 'operation_first'):
                    reset_actor()
                    job, confirmation, operation_sql = prepare(operation)
                    before = snapshot(job['id'])
                    name = 'sms_' + ('c' if operation == 'confirmation' else 's') + '_' + label + '_' + ordering
                    first_body = mutation if ordering == 'revocation_first' else claims + operation_sql
                    second_body = claims + operation_sql if ordering == 'revocation_first' else mutation
                    first = start(executor, name + '_first', first_body + 'select pg_sleep(2);commit;')
                    wait_for(name + '_first', "wait_event='PgSleep'")
                    second = start(executor, name + '_second', second_body + 'commit;')
                    wait_for(name + '_second', "wait_event_type='Lock'and cardinality(pg_blocking_pids(pid))>0")
                    first_result, second_result = first.result(timeout=20), second.result(timeout=20)
                    after = snapshot(job['id'])
                    if ordering == 'revocation_first':
                        ok = first_result.returncode == 0 and second_result.returncode != 0 \
                            and '42501' in second_result.stderr and before == after
                        retained = None
                    else:
                        later = target.sql('begin;' + claims + operation_sql + 'commit;', check=False,
                                           label='revoked exact session cannot replay completed sensitive operation')
                        retained = provenance_survives(operation, job, confirmation)
                        ok = first_result.returncode == 0 and second_result.returncode == 0 \
                            and retained and later.returncode != 0 and '42501' in later.stderr \
                            and after == snapshot(job['id']) and before != after
                    case(operation + ' ' + label + ' ' + ordering + ' actual blocking and durable provenance', ok,
                         blocked_wait_observed=True, first_exit=first_result.returncode, second_exit=second_result.returncode,
                         denied_operation_has_no_job_or_audit_mutation=before == after if ordering == 'revocation_first' else None,
                         completed_operation_provenance_retained=retained,
                         first_error=first_result.stderr, second_error=second_result.stderr)

            reset_actor()
            job, confirmation, operation_sql = prepare(operation)
            before = snapshot(job['id'])
            target.sql("update auth.sessions set not_after=clock_timestamp()+interval '1 second'where id=" + q(sid) + ';')
            name = 'sensitive_' + operation + '_clock_expiry'
            blocker = start(executor, name + '_blocker', 'select 1 from collect_hybrid.sms_notification_outbox where id=' +
                            q(job['id']) + 'for update;select pg_sleep(2);commit;')
            wait_for(name + '_blocker', "wait_event='PgSleep'")
            waiter = start(executor, name + '_waiter', claims + operation_sql + 'commit;')
            wait_for(name + '_waiter', "wait_event_type='Lock'and cardinality(pg_blocking_pids(pid))>0")
            blocker_result, waiter_result = blocker.result(timeout=20), waiter.result(timeout=20)
            case(operation + ' wall-clock expiry during legacy outbox wait rolls back all evidence',
                 blocker_result.returncode == 0 and waiter_result.returncode != 0 and '42501' in waiter_result.stderr
                 and before == snapshot(job['id']), blocked_wait_observed=True, error=waiter_result.stderr)
