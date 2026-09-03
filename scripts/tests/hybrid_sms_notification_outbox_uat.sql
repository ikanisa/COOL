\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';

do $$ begin
  if not (
       current_database() ~ '^collect_hybrid_sms_uat(_v[0-9]+)?_20260903$'
       or current_setting('application_name') = 'collect_hybrid_sms_outbox_uat'
       or current_setting('collect.local_sms_outbox_uat', true)
          = 'clean-replay-current'
       or current_setting('collect.recovery_drill', true)
          = 'production-archive-v1'
     )
     or (
       current_setting('collect.recovery_drill', true)
         is distinct from 'production-archive-v1'
       and exists (select 1 from public.payments)
     )
     or exists (select 1 from collect_hybrid.sms_notification_outbox) then
    raise exception 'Fresh isolated hybrid SMS outbox UAT database required';
  end if;
end $$;

create temp table test_results(label text primary key);
create temp table test_values(key text primary key, value jsonb);
grant all on pg_temp.test_results, pg_temp.test_values to authenticated, service_role;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end;
$$;
create function pg_temp.expect_error(command text, fragment text, label text)
returns void language plpgsql as $$
declare caught text;
begin
  begin execute command; exception when others then caught := sqlerrm; end;
  perform pg_temp.assert_true(
    caught is not null and position(fragment in caught) > 0,
    label
  );
end;
$$;

insert into auth.users(
  id, aud, role, phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data
) values
  ('96000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   '250788960001', now(), '{}', '{}'),
  ('96000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   '250788960002', now(), '{}', '{}');
update public.profiles set is_platform_admin = true
where id = '96000000-0000-4000-8000-000000000001';
insert into public.admin_user_roles(user_id, role_id, granted_by, reason, created_at)
select
  '96000000-0000-4000-8000-000000000001', role.id,
  '96000000-0000-4000-8000-000000000001',
  'Synthetic SMS operator UAT', now() - interval '2 seconds'
from public.admin_roles role where role.name = 'platform_owner';
insert into auth.sessions(id, user_id, created_at, updated_at, not_after)
values (
  '96000000-0000-4000-8000-000000000099',
  '96000000-0000-4000-8000-000000000001',
  now() - interval '1 second', now(), now() + interval '1 hour'
);
insert into collect_admin_access.whatsapp_approvals(
  user_id, phone_e164, approved_at, approved_by, reason
) values (
  '96000000-0000-4000-8000-000000000001', '+250788960001',
  now() - interval '2 seconds',
  '96000000-0000-4000-8000-000000000001',
  'Synthetic SMS operator UAT'
);
select pg_temp.assert_true(
  (select not enabled from public.feature_flags
   where key = 'hybrid_sms_notifications')
  and not exists (
    select 1 from collect_hybrid.sms_receipt_member_consents
  ),
  'SMS receipts and member consent start disabled with no inferred opt-ins'
);
update public.feature_flags set enabled = true
where key in ('hybrid_member_onboarding', 'hybrid_sms_notifications');

insert into public.collections(
  id, slug, creator_user_id, title, category, visibility, public_status,
  collection_type, contribution_visibility, allow_anonymous,
  diaspora_enabled, creation_origin
) values (
  '96000000-0000-4000-8000-000000000100',
  'synthetic-sms-outbox-uat',
  '96000000-0000-4000-8000-000000000001',
  'Buri Munsi SMS UAT', 'Family / friends', 'private', 'private',
  'ikimina', 'members', false, false, 'admin_assisted'
);
insert into public.collection_members(collection_id, user_id, role, status)
values (
  '96000000-0000-4000-8000-000000000100',
  '96000000-0000-4000-8000-000000000001', 'owner', 'active'
);
insert into collect_hybrid.member_records(
  id, collect_id, linked_user_id, origin, created_by
) values (
  '96000000-0000-4000-8000-000000000200', '960200', null,
  'admin_assisted', '96000000-0000-4000-8000-000000000001'
);
insert into collect_hybrid.member_momo_identities(
  member_id, member_name, momo_name, momo_number
) values (
  '96000000-0000-4000-8000-000000000200',
  'Feature Phone Member', 'FEATURE PHONE MEMBER', '+250788960200'
);
insert into public.collection_members(
  collection_id, member_record_id, role, status
) values (
  '96000000-0000-4000-8000-000000000100',
  '96000000-0000-4000-8000-000000000200', 'member', 'active'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"96000000-0000-4000-8000-000000000099"}',
  true
);
select pg_temp.assert_true(
  public.admin_set_sms_receipt_policy(
    '96000000-0000-4000-8000-000000000100', true,
    'Enable synthetic Buri Munsi SMS outbox UAT'
  )->>'enabled' = 'true',
  'authorized admin explicitly enables the collection receipt policy'
);
select pg_temp.assert_true(
  public.admin_set_member_sms_receipt_consent(
    '96000000-0000-4000-8000-000000000200', true, 'written',
    'Synthetic member opted in to transaction receipt SMS for UAT'
  )->>'enabled' = 'true',
  'authorized admin records explicit offline-member receipt consent'
);
reset role;

-- A separate account-independent member has a MoMo identity but no receipt
-- consent. A posted payment must not infer opt-in from that phone number.
insert into collect_hybrid.member_records(
  id, collect_id, linked_user_id, origin, created_by
) values (
  '96000000-0000-4000-8000-000000000201', '960201', null,
  'admin_assisted', '96000000-0000-4000-8000-000000000001'
);
insert into collect_hybrid.member_momo_identities(
  member_id, member_name, momo_name, momo_number
) values (
  '96000000-0000-4000-8000-000000000201',
  'No Consent Member', 'NO CONSENT MEMBER', '+250788960201'
);
insert into public.collection_members(
  collection_id, member_record_id, role, status
) values (
  '96000000-0000-4000-8000-000000000100',
  '96000000-0000-4000-8000-000000000201', 'member', 'active'
);
insert into public.payments(
  id, collection_id, member_record_id, contributor_public_id,
  receiver_user_id, receiver_momo_number_hash, amount_rwf,
  transaction_id, provider_network, source, status, anonymity_choice, posted_at
) values (
  '96000000-0000-4000-8000-000000000300',
  '96000000-0000-4000-8000-000000000100',
  '96000000-0000-4000-8000-000000000201', '960201',
  '96000000-0000-4000-8000-000000000001', repeat('a', 64), 250,
  'SYNTHETIC-NO-CONSENT', 'mtn_momo', 'manual_admin', 'posted',
  'public_id', now()
);
select pg_temp.assert_true(
  (select count(*) from collect_hybrid.sms_notification_outbox) = 0,
  'MoMo identity alone never infers consent or creates a receipt job'
);

insert into public.payments(
  id, collection_id, member_record_id, contributor_public_id,
  receiver_user_id, receiver_momo_number_hash, amount_rwf,
  transaction_id, provider_network, source, status, anonymity_choice, posted_at
) values (
  '96000000-0000-4000-8000-000000000301',
  '96000000-0000-4000-8000-000000000100',
  '96000000-0000-4000-8000-000000000200', '960200',
  '96000000-0000-4000-8000-000000000001', repeat('a', 64), 1500,
  'SYNTHETIC-001', 'mtn_momo', 'manual_admin', 'posted', 'public_id', now()
);
select pg_temp.assert_true(
  (select count(*) from collect_hybrid.sms_notification_outbox) = 1,
  'one posted offline-member receipt creates one durable SMS job'
);
select pg_temp.assert_true(
  (select message_body from collect_hybrid.sms_notification_outbox) =
    'BuriMunsi: Twakiriye ubwizigame bwawe bwa 1,500 RWF. Balance yawe: 1,500 RWF; balance y''itsinda: 1,750 RWF. Ref: SYNTHETIC-001.',
  'queued body preserves the exact easyMO wording and freezes canonical balances'
);
select pg_temp.assert_true(
  (select state = 'queued' and amount_rwf = 1500
     and member_balance_rwf = 1500 and group_balance_rwf = 1750
     and destination_revision = 1 and consent_revision = 1
     and body_sha256 ~ '^[0-9a-f]{64}$'
   from collect_hybrid.sms_notification_outbox),
  'job freezes destination, template and immutable financial snapshot'
);

-- A linked app member continues on the existing app-notification channel and
-- is not duplicated into the assisted SMS queue.
insert into public.collection_members(collection_id, user_id, role, status)
values (
  '96000000-0000-4000-8000-000000000100',
  '96000000-0000-4000-8000-000000000002', 'member', 'active'
);
insert into public.payments(
  id, collection_id, member_record_id, contributor_public_id,
  receiver_user_id, receiver_momo_number_hash, amount_rwf,
  transaction_id, provider_network, source, status, anonymity_choice, posted_at
) values (
  '96000000-0000-4000-8000-000000000302',
  '96000000-0000-4000-8000-000000000100',
  '96000000-0000-4000-8000-000000000002',
  (select public_id from public.profiles where id = '96000000-0000-4000-8000-000000000002'),
  '96000000-0000-4000-8000-000000000001', repeat('a', 64), 500,
  'SYNTHETIC-APP-001', 'mtn_momo', 'manual_admin', 'posted', 'public_id', now()
);
select pg_temp.assert_true(
  (select count(*) from collect_hybrid.sms_notification_outbox) = 1,
  'app-linked member is not duplicated into the assisted SMS channel'
);
insert into pg_temp.test_values
select 'job_one', jsonb_build_object('id', id)
from collect_hybrid.sms_notification_outbox;

set local role service_role;
select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);
select pg_temp.assert_true(
  (public.collect_notification_health(
    '96000000-0000-4000-8000-000000000001'
  )->>'queued')::int = 1,
  'operator health exposes safe aggregate queue state'
);
select pg_temp.assert_true(
  jsonb_array_length(public.collect_list_pending_receipts(
    '96000000-0000-4000-8000-000000000001', 20, null
  )) = 1
  and public.collect_list_pending_receipts(
    '96000000-0000-4000-8000-000000000001', 20, null
  )->0 ? 'destination_masked'
  and not (public.collect_list_pending_receipts(
    '96000000-0000-4000-8000-000000000001', 20, null
  )->0 ? 'message_body'),
  'pending list is bounded and does not expose full destination or body'
);
insert into pg_temp.test_values values (
  'claim_one',
  public.collect_claim_receipt(
    '96000000-0000-4000-8000-000000000001',
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one'),
    'collect-mac-mini-uat',
    '96000000-0000-4000-8000-000000000401'
  )
);
insert into pg_temp.test_values values (
  'exact_one',
  public.collect_get_claimed_receipt(
    '96000000-0000-4000-8000-000000000001',
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one'),
    (select (value->>'claim_token')::uuid from pg_temp.test_values where key = 'claim_one'),
    (select (value->>'fence_version')::integer from pg_temp.test_values where key = 'claim_one')
  )
);
select pg_temp.assert_true(
  (select value->>'destination_e164' from pg_temp.test_values where key = 'exact_one')
    = '+250788960200'
  and (select value->>'message_body' from pg_temp.test_values where key = 'exact_one')
    like 'BuriMunsi: Twakiriye ubwizigame bwawe bwa %SYNTHETIC-001.',
  'exact destination and immutable body require a current fenced claim'
);
select pg_temp.expect_error(
  format(
    'select public.collect_get_claimed_receipt(%L,%L,%L,%s)',
    '96000000-0000-4000-8000-000000000001',
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one'),
    (select value->>'claim_token' from pg_temp.test_values where key = 'claim_one'),
    999
  ),
  'Current notification claim required',
  'stale fencing version cannot read a claimed receipt'
);
insert into pg_temp.test_values values (
  'confirmation_one',
  public.collect_confirm_receipt(
    '96000000-0000-4000-8000-000000000001',
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one'),
    (select (value->>'claim_token')::uuid from pg_temp.test_values where key = 'claim_one'),
    (select (value->>'fence_version')::integer from pg_temp.test_values where key = 'claim_one'),
    (select (value->>'destination_revision')::integer from pg_temp.test_values where key = 'exact_one'),
    (select value->>'body_sha256' from pg_temp.test_values where key = 'exact_one'),
    '96000000-0000-4000-8000-000000000402'
  )
);
insert into pg_temp.test_values values (
  'attempt_one',
  public.collect_record_send_start(
    '96000000-0000-4000-8000-000000000001',
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one'),
    (select (value->>'claim_token')::uuid from pg_temp.test_values where key = 'claim_one'),
    (select (value->>'fence_version')::integer from pg_temp.test_values where key = 'claim_one'),
    '96000000-0000-4000-8000-000000000402'
  )
);
select pg_temp.assert_true(
  (public.collect_notification_health(
    '96000000-0000-4000-8000-000000000001'
  )->>'send_started')::int = 1
  and (select value->>'attempt_id' from pg_temp.test_values where key = 'attempt_one') is not null,
  'fresh exact confirmation is consumed at the durable pre-send boundary'
);
select pg_temp.expect_error(
  format(
    'select public.collect_claim_receipt(%L,%L,%L,%L)',
    '96000000-0000-4000-8000-000000000001',
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one'),
    'collect-mac-mini-uat',
    '96000000-0000-4000-8000-000000000403'
  ),
  'not available to claim',
  'send-started receipt cannot be claimed or blindly retried'
);
select public.collect_record_observed_outcome(
  '96000000-0000-4000-8000-000000000001',
  (select (value->>'attempt_id')::uuid from pg_temp.test_values where key = 'attempt_one'),
  'uncertain', 'synthetic Messages state could not be read',
  'UAT proves the uncertain path never becomes observed sent'
);
select pg_temp.assert_true(
  (public.collect_notification_health(
    '96000000-0000-4000-8000-000000000001'
  )->>'uncertain')::int = 1,
  'uncertain UI outcome is retained without claiming delivery'
);
select pg_temp.expect_error(
  format(
    'select public.collect_claim_receipt(%L,%L,%L,%L)',
    '96000000-0000-4000-8000-000000000001',
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one'),
    'collect-mac-mini-uat',
    '96000000-0000-4000-8000-000000000404'
  ),
  'not available to claim',
  'uncertain receipt is never automatically retried'
);

-- A second receipt is queued while consent is current. Revocation before the
-- next claim must suppress it without exposing the full destination or body.
reset role;
insert into public.payments(
  id, collection_id, member_record_id, contributor_public_id,
  receiver_user_id, receiver_momo_number_hash, amount_rwf,
  transaction_id, provider_network, source, status, anonymity_choice, posted_at
) values (
  '96000000-0000-4000-8000-000000000303',
  '96000000-0000-4000-8000-000000000100',
  '96000000-0000-4000-8000-000000000200', '960200',
  '96000000-0000-4000-8000-000000000001', repeat('a', 64), 100,
  'SYNTHETIC-REVOKED', 'mtn_momo', 'manual_admin', 'posted', 'public_id', now()
);
insert into pg_temp.test_values
select 'job_revoked', jsonb_build_object('id', id)
from collect_hybrid.sms_notification_outbox
where payment_id = '96000000-0000-4000-8000-000000000303';
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"96000000-0000-4000-8000-000000000099"}',
  true
);
select pg_temp.assert_true(
  public.admin_set_member_sms_receipt_consent(
    '96000000-0000-4000-8000-000000000200', false, 'written',
    'Synthetic member revoked transaction receipt SMS consent for UAT'
  )->>'enabled' = 'false',
  'member receipt consent can be explicitly revoked with an audit reason'
);
reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  (public.collect_claim_receipt(
    '96000000-0000-4000-8000-000000000001',
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_revoked'),
    'collect-mac-mini-uat',
    '96000000-0000-4000-8000-000000000406'
  )->>'state') = 'suppressed',
  'revoked consent suppresses a queued receipt before payload disclosure'
);
select pg_temp.assert_true(
  (public.collect_notification_health(
    '96000000-0000-4000-8000-000000000001'
  )->>'suppressed')::int = 1,
  'consent-invalidated receipt remains visible only as aggregate suppressed state'
);
select pg_temp.assert_true(
  public.collect_worker_heartbeat(
    '96000000-0000-4000-8000-000000000001',
    'collect-mac-mini-uat',
    '96000000-0000-4000-8000-000000000405',
    'no_send',
    '{"queue_checked":true}'
  )->>'mode' = 'no_send',
  'one-minute worker heartbeat records only safe aggregate state'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"96000000-0000-4000-8000-000000000099"}',
  true
);
select pg_temp.assert_true(
  (public.admin_list_hybrid_sms_receipts(null, 'uncertain', 25, 0, 'created_at_desc')->>'total')::int = 1
  and not (
    public.admin_list_hybrid_sms_receipts(null, 'uncertain', 25, 0, 'created_at_desc')->'rows'->0
    ? 'message_body'
  )
  and not (
    public.admin_list_hybrid_sms_receipts(null, 'uncertain', 25, 0, 'created_at_desc')->'rows'->0
    ? 'destination_e164'
  )
  and (
    public.admin_list_hybrid_sms_receipts(null, 'uncertain', 25, 0, 'created_at_desc')->'rows'->0
    ->> 'authorization_current'
  ) = 'false'
  and (
    public.admin_list_hybrid_sms_receipts(null, 'uncertain', 25, 0, 'created_at_desc')->'rows'->0
    ->> 'consent_revision'
  )::int > 0,
  'Admin PWA surfaces revoked authorization without exposing exact phone or body'
);
select pg_temp.assert_true(
  public.admin_get_hybrid_sms_receipt(
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one')
  )->>'destination_masked' = '+250•••200'
  and public.admin_get_hybrid_sms_receipt(
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one')
  )->>'message_body' = 'Hidden until a current fenced operator claim'
  and public.admin_get_hybrid_sms_receipt(
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one')
  )->>'channel' = 'Assisted SMS operator'
  and public.admin_get_hybrid_sms_receipt(
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one')
  )->>'authorization_current' = 'false'
  and (public.admin_get_hybrid_sms_receipt(
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one')
  )->>'consent_revision')::int > 0
  and not (
    public.admin_get_hybrid_sms_receipt(
      (select (value->>'id')::uuid from pg_temp.test_values where key = 'job_one')
    ) ? 'destination_e164'
  ),
  'Admin detail is provider-neutral, masked and claim-gated after consent revocation'
);
reset role;

select pg_temp.expect_error(
  $q$delete from collect_hybrid.sms_notification_outbox$q$,
  'retained',
  'SMS job and attempt evidence cannot be deleted'
);
select pg_temp.expect_error(
  $q$update collect_hybrid.sms_notification_outbox set amount_rwf = 999$q$,
  'immutable',
  'queued financial snapshot cannot be rewritten'
);
select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated', 'public.collect_get_claimed_receipt(uuid,uuid,uuid,integer)',
    'EXECUTE'
  ) and not has_table_privilege(
    'service_role', 'collect_hybrid.sms_notification_outbox', 'SELECT'
  ) and not has_table_privilege(
    'authenticated', 'collect_hybrid.sms_receipt_member_consents', 'SELECT'
  ),
  'operator uses narrow commands and never direct private-table access'
);

select 'PASS ' || label from pg_temp.test_results order by label;
select 'HYBRID_SMS_NOTIFICATION_OUTBOX_UAT_PASS: ' || count(*) ||
  ' assertions; synthetic rollback only; no SMS sent'
from pg_temp.test_results;
rollback;
