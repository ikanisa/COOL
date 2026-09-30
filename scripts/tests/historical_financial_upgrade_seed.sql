\set ON_ERROR_STOP on
-- Synthetic, committed predecessor rows for the task-owned financial QA fixture.
-- Run only after the isolated replay stops at 20260925190000. No provider call.
begin;
set local statement_timeout = '30s';
do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations) <> 127
     or (select max(version) from supabase_migrations.schema_migrations) <> '20260925190000'
     or (select count(*) from auth.users) <> 1
     or not exists(select 1 from auth.users where id = '99100000-0000-4000-8000-000000000001')
     or exists(select 1 from public.payments)
     or exists(select 1 from public.raw_payment_sms)
     or to_regprocedure('public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)') is not null then
    raise exception 'Exact isolated financial predecessor with synthetic owner required';
  end if;
end $$;

update public.profiles
set country_code = 'RW', currency_code = 'RWF',
    momo_provider = 'mtn_momo', momo_number = '0788991001',
    momo_number_hash = encode(extensions.digest('+250788991001', 'sha256'), 'hex')
where id = '99100000-0000-4000-8000-000000000001';
insert into public.collections(
  id, slug, creator_user_id, title, category, visibility, public_status,
  collection_type, contribution_visibility, allow_anonymous, diaspora_enabled
) values (
  '99300000-0000-4000-8000-000000000010', 'historical-upgrade-synthetic',
  '99100000-0000-4000-8000-000000000001', 'Synthetic historical savings',
  'Family / friends', 'private', 'private', 'ikimina', 'members', false, false
);
insert into public.collection_members(collection_id, user_id, role, status)
values ('99300000-0000-4000-8000-000000000010',
        '99100000-0000-4000-8000-000000000001', 'owner', 'active');
insert into public.collection_receivers(
  id, collection_id, receiver_user_id, momo_number, momo_number_hash,
  network, label, is_active
) values (
  '99300000-0000-4000-8000-000000000020',
  '99300000-0000-4000-8000-000000000010',
  '99100000-0000-4000-8000-000000000001', '0788991001',
  encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
  'mtn_momo', 'Synthetic historical receiver', true
);
insert into public.native_action_capabilities(
  id, user_id, action, request_hash, request_payload,
  receiver_momo_number_hash, package_name, app_verdict, device_verdicts,
  verified_at, expires_at, consumed_at
)
select id, '99100000-0000-4000-8000-000000000001'::uuid,
  'sms.ingest', repeat('b', 64), '{}'::jsonb,
  encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
  'app.cool.mobile', 'PLAY_RECOGNIZED', array['MEETS_DEVICE_INTEGRITY'],
  now() - interval '3 minutes', now() + interval '1 minute', now() - interval '2 minutes'
from unnest(array[
  '99300000-0000-4000-8000-000000000101'::uuid,
  '99300000-0000-4000-8000-000000000102'::uuid,
  '99300000-0000-4000-8000-000000000103'::uuid
]) id;
with receipt(id, body, minutes_old, capability) as (values
  ('99300000-0000-4000-8000-000000000201'::uuid,
   'Txn HIST1500. Received 1,500 RWF from the synthetic payer.', 5,
   '99300000-0000-4000-8000-000000000101'::uuid),
  ('99300000-0000-4000-8000-000000000202'::uuid,
   'Txn HIST1200. Received 1,200 RWF from an unverified payer.', 4,
   '99300000-0000-4000-8000-000000000102'::uuid),
  ('99300000-0000-4000-8000-000000000203'::uuid,
   'Txn HIST900. Observed 900 RWF; still waiting for reconciliation.', 3,
   '99300000-0000-4000-8000-000000000103'::uuid)
)
insert into public.raw_payment_sms(
  id, collection_id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
)
select id, '99300000-0000-4000-8000-000000000010',
  '99100000-0000-4000-8000-000000000001', 'M-Money', body,
  encode(extensions.digest(body, 'sha256'), 'hex'),
  encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
  now() - make_interval(mins => minutes_old),
  case when id = '99300000-0000-4000-8000-000000000203'::uuid
    then 'pending' else 'parsed' end,
  capability, repeat('b', 64), now() - interval '2 minutes'
from receipt;
insert into public.parsed_payment_events(
  id, raw_sms_id, collection_id, receiver_user_id, is_mobile_money_payment,
  network, direction, amount_rwf, currency, transaction_id,
  sender_phone_hash, receiver_phone_hash, confidence, parser_schema_version,
  allocation_status, transaction_time
) values
  ('99300000-0000-4000-8000-000000000211',
   '99300000-0000-4000-8000-000000000201',
   '99300000-0000-4000-8000-000000000010',
   '99100000-0000-4000-8000-000000000001', true, 'mtn_momo',
   'incoming', 1500, 'RWF', 'HIST1500',
   encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
   encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
   0.99, 'collect.sms_parser.v4', 'allocated', now() - interval '5 minutes'),
  ('99300000-0000-4000-8000-000000000212',
   '99300000-0000-4000-8000-000000000202',
   '99300000-0000-4000-8000-000000000010',
   '99100000-0000-4000-8000-000000000001', true, 'mtn_momo',
   'incoming', 1200, 'RWF', 'HIST1200', repeat('f', 64),
   encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
   0.99, 'collect.sms_parser.v4', 'needs_review', now() - interval '4 minutes');
insert into public.payment_intents(
  id, collection_id, contributor_user_id, contributor_public_id,
  contribution_code, expected_amount_rwf, receiver_momo_number_hash,
  sender_phone_hash, status, anonymity_choice, expires_at
)
select '99300000-0000-4000-8000-000000000302',
  '99300000-0000-4000-8000-000000000010', profile.id, profile.public_id,
  'HIST-UNVERIFIED-1200', 1200,
  encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
  repeat('f', 64), 'pending', 'public_id', now() + interval '1 hour'
from public.profiles profile
where profile.id = '99100000-0000-4000-8000-000000000001';
insert into public.payments(
  id, parsed_event_id, payment_intent_id, collection_id,
  contributor_user_id, contributor_public_id, receiver_user_id,
  receiver_momo_number_hash, amount_rwf, transaction_id,
  provider_network, source, status, anonymity_choice, posted_at
)
select '99300000-0000-4000-8000-000000000221',
  '99300000-0000-4000-8000-000000000211', null,
  '99300000-0000-4000-8000-000000000010', profile.id, profile.public_id,
  profile.id, encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
  1500, 'HIST1500', 'mtn_momo', 'sms_auto', 'review', 'public_id', null
from public.profiles profile
where profile.id = '99100000-0000-4000-8000-000000000001';
insert into public.payments(
  id, parsed_event_id, payment_intent_id, collection_id,
  contributor_user_id, contributor_public_id, receiver_user_id,
  receiver_momo_number_hash, amount_rwf, transaction_id,
  provider_network, source, status, anonymity_choice, posted_at
)
select '99300000-0000-4000-8000-000000000222',
  '99300000-0000-4000-8000-000000000212',
  '99300000-0000-4000-8000-000000000302',
  '99300000-0000-4000-8000-000000000010', profile.id, profile.public_id,
  profile.id, encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
  1200, 'HIST1200', 'mtn_momo', 'sms_auto', 'review', 'public_id', null
from public.profiles profile
where profile.id = '99100000-0000-4000-8000-000000000001';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.confirm_provider_payment(
  '99300000-0000-4000-8000-000000000221', 'mtn_momo', 'HIST1500',
  'CONFIRM-HIST1500',
  encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
  1500, now() - interval '1 minute', repeat('c', 64)
);
reset role;
do $$ begin
  if (select status from public.payments
      where id = '99300000-0000-4000-8000-000000000221') <> 'posted'
     or (select status from public.payments
      where id = '99300000-0000-4000-8000-000000000222') <> 'review'
     or (select status from public.payment_intents
      where id = '99300000-0000-4000-8000-000000000302') <> 'pending'
     or (select confirmed_rwf from collect_hybrid.collection_balances
      where collection_id = '99300000-0000-4000-8000-000000000010') <> 1500
     or (select count(*) from public.ledger_entries
      where payment_id = '99300000-0000-4000-8000-000000000221') <> 2
     or (select count(*) from collect_hybrid.momo_journal_lines line
       join collect_hybrid.momo_journal_entries entry on entry.id = line.journal_entry_id
       where entry.payment_id = '99300000-0000-4000-8000-000000000221') <> 2
     or (select count(*) from public.raw_payment_sms) <> 3 then
    raise exception 'Historical seed financial invariants failed';
  end if;
end $$;
commit;
select 'HISTORICAL_FINANCIAL_UPGRADE_SEED_PASS';
