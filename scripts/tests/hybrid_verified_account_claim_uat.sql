\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';

do $$ begin
  if not (
       current_setting('application_name') = 'collect_hybrid_account_claim_uat'
       or current_setting('collect.recovery_drill', true)
          = 'production-archive-v1'
     )
     or (
       current_setting('collect.recovery_drill', true)
         is distinct from 'production-archive-v1'
       and exists (select 1 from public.payments)
     )
     or exists (select 1 from collect_hybrid.member_account_claims) then
    raise exception 'Fresh isolated hybrid account-claim UAT database required';
  end if;
end $$;

create temp table test_results(label text primary key);
grant all on pg_temp.test_results to authenticated;
create function pg_temp.assert_true(ok boolean, label text)
returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end;
$$;

insert into auth.users(
  id, aud, role, phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data
) values
  ('97000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   '250788970001', now(), '{}', '{}'),
  ('97000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   '250788970002', now(), '{}', '{}'),
  ('97000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   '250788970003', now(), '{}', '{}');
update public.profiles set is_platform_admin = true
where id = '97000000-0000-4000-8000-000000000001';
insert into public.admin_user_roles(user_id, role_id, granted_by, reason, created_at)
select
  '97000000-0000-4000-8000-000000000001', role.id,
  '97000000-0000-4000-8000-000000000001',
  'Synthetic hybrid member-directory UAT', now() - interval '2 seconds'
from public.admin_roles role where role.name = 'platform_owner';
insert into auth.sessions(id, user_id, created_at, updated_at, not_after)
values (
  '97000000-0000-4000-8000-000000000099',
  '97000000-0000-4000-8000-000000000001',
  now() - interval '1 second', now(), now() + interval '1 hour'
);
insert into collect_admin_access.whatsapp_approvals(
  user_id, phone_e164, approved_at, approved_by, reason
) values (
  '97000000-0000-4000-8000-000000000001', '+250788970001',
  now() - interval '2 seconds',
  '97000000-0000-4000-8000-000000000001',
  'Synthetic hybrid member-directory UAT'
);

update public.feature_flags set enabled = true
where key in (
  'hybrid_member_onboarding',
  'hybrid_sms_notifications',
  'hybrid_verified_account_claim'
);

insert into public.collections(
  id, slug, creator_user_id, title, category, visibility, public_status,
  collection_type, contribution_visibility, allow_anonymous,
  diaspora_enabled, creation_origin
) values (
  '97000000-0000-4000-8000-000000000100',
  'synthetic-account-claim-uat',
  '97000000-0000-4000-8000-000000000001',
  'Buri Munsi Account Claim UAT', 'Family / friends', 'private', 'private',
  'ikimina', 'members', false, false, 'admin_assisted'
);
insert into public.collection_members(collection_id, user_id, role, status)
values (
  '97000000-0000-4000-8000-000000000100',
  '97000000-0000-4000-8000-000000000001', 'owner', 'active'
);

insert into collect_hybrid.member_records(
  id, collect_id, linked_user_id, origin, created_by
) values (
  '97000000-0000-4000-8000-000000000200', '970200', null,
  'admin_assisted', '97000000-0000-4000-8000-000000000001'
);
insert into collect_hybrid.member_momo_identities(
  member_id, member_name, momo_name, momo_number
) values (
  '97000000-0000-4000-8000-000000000200',
  'Verified Offline Member', 'VERIFIED OFFLINE MEMBER', '+250788970002'
);
insert into public.collection_members(
  collection_id, member_record_id, role, status
) values (
  '97000000-0000-4000-8000-000000000100',
  '97000000-0000-4000-8000-000000000200', 'member', 'active'
);
insert into collect_hybrid.sms_receipt_policies(
  collection_id, enabled, reason, updated_by
) values (
  '97000000-0000-4000-8000-000000000100', true,
  'Synthetic account claim receipt policy',
  '97000000-0000-4000-8000-000000000001'
);
insert into collect_hybrid.sms_receipt_member_consents(
  member_record_id, enabled, capture_method, reason, recorded_by
) values (
  '97000000-0000-4000-8000-000000000200', true, 'written',
  'Synthetic account claim receipt consent',
  '97000000-0000-4000-8000-000000000001'
);

insert into public.payments(
  id, collection_id, member_record_id, contributor_public_id,
  receiver_user_id, receiver_momo_number_hash, amount_rwf,
  transaction_id, provider_network, source, status, anonymity_choice, posted_at
) values (
  '97000000-0000-4000-8000-000000000300',
  '97000000-0000-4000-8000-000000000100',
  '97000000-0000-4000-8000-000000000200', '970200',
  '97000000-0000-4000-8000-000000000001', repeat('a', 64), 1500,
  'CLAIM-UAT-001', 'mtn_momo', 'manual_admin', 'posted', 'public_id', now()
);
select pg_temp.assert_true(
  (select count(*) from collect_hybrid.sms_notification_outbox
   where state = 'queued') = 1,
  'offline posted payment enters the consented assisted SMS queue'
);
select pg_temp.assert_true(
  (select contributor_user_id is null from public.payments
   where id = '97000000-0000-4000-8000-000000000300'),
  'offline payment starts without a fabricated Auth identity'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"97000000-0000-4000-8000-000000000099"}',
  true
);
select pg_temp.assert_true(
  jsonb_path_exists(
    public.admin_list_members(null, null, 25, 0, 'created_at_desc'),
    '$.rows[*] ? (@.public_id == "970200" && @.account_state == "feature_phone")'
  ) and position(
    '+250788970002' in public.admin_list_members(
      null, null, 25, 0, 'created_at_desc'
    )::text
  ) = 0,
  'Admin members queue combines offline records while masking full MoMo numbers'
);
select pg_temp.assert_true(
  public.admin_get_member_record(
    '97000000-0000-4000-8000-000000000200'
  )->>'momo_masked' <> '+250788970002',
  'Admin member detail keeps the MoMo destination masked'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select pg_temp.assert_true(
  public.claim_verified_current_account()->>'status' = 'no_match',
  'a different fully verified phone cannot claim by similar name or suffix'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select pg_temp.assert_true(
  public.claim_verified_current_account()->>'status' = 'claimed',
  'the exact full server-verified phone claims the offline member record'
);
select pg_temp.assert_true(
  public.claim_verified_current_account()->>'status' = 'already_claimed',
  'account claim retries are idempotent'
);
select pg_temp.assert_true(
  public.user_can_read_collection(
    '97000000-0000-4000-8000-000000000100',
    '97000000-0000-4000-8000-000000000002'
  ),
  'claimed offline membership unlocks the existing private group'
);
select pg_temp.assert_true(
  jsonb_path_exists(
    public.list_current_member_group_roster(
      '97000000-0000-4000-8000-000000000100'
    ),
    '$[*] ? (@.public_id == "970200" && @.account_state == "app")'
  ) and position(
    '+250788970002' in public.list_current_member_group_roster(
      '97000000-0000-4000-8000-000000000100'
    )::text
  ) = 0,
  'member roster combines claimed and feature-phone identities by safe Collect ID'
);
select pg_temp.assert_true(
  jsonb_path_exists(
    public.list_current_member_collection_balances(),
    '$[*] ? (@.collection_id == "97000000-0000-4000-8000-000000000100" && @.balances[*].current_user_balance_minor == 1500)'
  ),
  'claimed member sees the existing immutable member balance'
);
select pg_temp.assert_true(
  jsonb_path_exists(
    public.list_current_member_payment_history(),
    '$[*] ? (@.transaction_id == "CLAIM-UAT-001" && @.is_current_user_contribution == true)'
  ),
  'claimed member sees the existing payment as their own history'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"97000000-0000-4000-8000-000000000099"}',
  true
);
select pg_temp.assert_true(
  public.admin_get_member_record(
    '97000000-0000-4000-8000-000000000200'
  )->>'account_state' = 'app_claimed',
  'Admin member detail reflects the verified app claim without merging history'
);
reset role;

select pg_temp.assert_true(
  (select contributor_user_id = '97000000-0000-4000-8000-000000000002'
   from public.payments
   where id = '97000000-0000-4000-8000-000000000300'),
  'claim attaches only the nullable account pointer to prior payment evidence'
);
select pg_temp.assert_true(
  (select state = 'suppressed' and claim_token is null
   from collect_hybrid.sms_notification_outbox),
  'claim suppresses every queued or confirmation-pending assisted SMS'
);
select pg_temp.assert_true(
  not collect_hybrid.sms_receipt_job_is_current(
    (select id from collect_hybrid.sms_notification_outbox limit 1)
  ),
  'a claimed member can no longer pass the assisted SMS current-state gate'
);
select pg_temp.assert_true(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'collect_hybrid'
      and table_name = 'member_account_claims'
      and column_name in ('phone', 'phone_e164', 'momo_number')
  ) and (
    select verified_phone_sha256 ~ '^[0-9a-f]{64}$'
    from collect_hybrid.member_account_claims
  ),
  'claim state stores only a verified phone hash, never the full phone'
);

insert into public.payments(
  id, collection_id, member_record_id, contributor_public_id,
  receiver_user_id, receiver_momo_number_hash, amount_rwf,
  transaction_id, provider_network, source, status, anonymity_choice, posted_at
) values (
  '97000000-0000-4000-8000-000000000301',
  '97000000-0000-4000-8000-000000000100',
  '97000000-0000-4000-8000-000000000200', '970200',
  '97000000-0000-4000-8000-000000000001', repeat('a', 64), 100,
  'CLAIM-UAT-002', 'mtn_momo', 'manual_admin', 'posted', 'public_id', now()
);
select pg_temp.assert_true(
  (select contributor_user_id = '97000000-0000-4000-8000-000000000002'
   from public.payments
   where id = '97000000-0000-4000-8000-000000000301'),
  'future direct payment automatically routes to the claimed app account'
);
select pg_temp.assert_true(
  (select count(*) from collect_hybrid.sms_notification_outbox) = 1,
  'defense-in-depth guard prevents future assisted SMS for an app-linked claim'
);

delete from auth.users where id = '97000000-0000-4000-8000-000000000002';
select pg_temp.assert_true(
  exists (
    select 1 from collect_hybrid.member_records member
    where member.id = '97000000-0000-4000-8000-000000000200'
      and member.lifecycle = 'active'
  ) and exists (
    select 1 from public.collection_members membership
    where membership.member_record_id = '97000000-0000-4000-8000-000000000200'
  ) and exists (
    select 1 from collect_hybrid.member_account_claims claim
    where claim.member_record_id = '97000000-0000-4000-8000-000000000200'
      and claim.user_id is null
  ),
  'account deletion releases the claim but retains member and group history'
);
select pg_temp.assert_true(
  not has_table_privilege(
    'authenticated', 'collect_hybrid.member_account_claims', 'SELECT'
  ) and has_function_privilege(
    'authenticated', 'public.claim_verified_current_account()', 'EXECUTE'
  ),
  'browser access is limited to the exact-phone claim RPC'
);

select 'PASS ' || label from pg_temp.test_results order by label;
select 'HYBRID_VERIFIED_ACCOUNT_CLAIM_UAT_PASS: ' || count(*) ||
  ' assertions; synthetic rollback only; no SMS sent'
from pg_temp.test_results;
rollback;
