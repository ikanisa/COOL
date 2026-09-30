\set ON_ERROR_STOP on
-- Full-schema synthetic F09/F08 regression. Every write rolls back.
begin;
set local statement_timeout = '30s';

do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations) <> 133
     or (select max(version) from supabase_migrations.schema_migrations)
       <> '20260928174000'
     or (select count(*) from auth.users) <> 1
     or (select count(*) from public.payments) <> 2
     or (select count(*) from public.raw_payment_sms) <> 3
     or (select count(*) from public.parsed_payment_events) <> 2
     or (select count(*) from public.payment_intents) <> 1
     or coalesce((select enabled from public.feature_flags
       where key = 'hybrid_direct_ussd_allocation'), false)
     or not exists (select 1 from public.collection_receivers
       where id = '99300000-0000-4000-8000-000000000020'
         and collection_id = '99300000-0000-4000-8000-000000000010'
         and receiver_user_id = '99100000-0000-4000-8000-000000000001'
         and is_active)
     or exists (select 1 from auth.users
       where id in ('99500000-0000-4000-8000-000000000001',
                    '99500000-0000-4000-8000-000000000002')) then
    raise exception 'Exact isolated financial predecessor fixture required';
  end if;
end $$;

create temp table test_results(label text primary key);
grant all on pg_temp.test_results to service_role;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end $$;

insert into auth.users(
  id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values
  ('99500000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', '250788004123', now(), '{}', '{}'),
  ('99500000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', '250738004123', now(), '{}', '{}');
update public.profiles
set country_code = 'RW', currency_code = 'RWF',
    momo_provider = 'mtn_momo', momo_number = '0788004123',
    momo_number_hash = encode(extensions.digest('+250788004123', 'sha256'), 'hex')
where id = '99500000-0000-4000-8000-000000000001';
update public.profiles
set country_code = 'RW', currency_code = 'RWF',
    momo_provider = 'airtel_money', momo_number = '0738004123',
    momo_number_hash = encode(extensions.digest('+250738004123', 'sha256'), 'hex')
where id = '99500000-0000-4000-8000-000000000002';
insert into public.collection_members(collection_id, user_id, role, status)
values
  ('99300000-0000-4000-8000-000000000010',
   '99500000-0000-4000-8000-000000000001', 'member', 'active'),
  ('99300000-0000-4000-8000-000000000010',
   '99500000-0000-4000-8000-000000000002', 'member', 'active');

select pg_temp.assert_true(
  public._authenticated_momo_phone_hash(
    '99500000-0000-4000-8000-000000000001') is not null
  and public._authenticated_momo_phone_hash(
    '99500000-0000-4000-8000-000000000001') is distinct from
      public._authenticated_momo_phone_hash(
        '99500000-0000-4000-8000-000000000002')
  and (select public_id from public.profiles
    where id = '99500000-0000-4000-8000-000000000001') is distinct from
      (select public_id from public.profiles
       where id = '99500000-0000-4000-8000-000000000002'),
  'two same-suffix members have distinct confirmed Auth identities'
);

insert into public.payment_intents(
  id, collection_id, contributor_user_id, contributor_public_id,
  contribution_code, expected_amount_rwf, receiver_momo_number_hash,
  sender_phone_hash, status, anonymity_choice, expires_at
)
select
  case when profile.id = '99500000-0000-4000-8000-000000000001'
    then '99500000-0000-4000-8000-000000000301'::uuid
    else '99500000-0000-4000-8000-000000000302'::uuid end,
  '99300000-0000-4000-8000-000000000010',
  profile.id, profile.public_id,
  case when profile.id = '99500000-0000-4000-8000-000000000001'
    then 'F09-SAME-001' else 'F09-SAME-002' end,
  2000, receiver.momo_number_hash,
  public._authenticated_momo_phone_hash(profile.id),
  'pending', 'public_id', now() + interval '1 hour'
from public.profiles profile
cross join public.collection_receivers receiver
where profile.id in ('99500000-0000-4000-8000-000000000001',
                     '99500000-0000-4000-8000-000000000002')
  and receiver.id = '99300000-0000-4000-8000-000000000020';
select pg_temp.assert_true(
  (select count(*) from public.payment_intents
   where id in ('99500000-0000-4000-8000-000000000301',
                '99500000-0000-4000-8000-000000000302')
     and expected_amount_rwf = 2000 and status = 'pending') = 2,
  'equal-value intents coexist without suffix-based payer selection'
);

create function pg_temp.seed_event(
  raw_id uuid, event_id uuid, provider_reference text,
  amount bigint, sender_hash text, detected_public_id text,
  receiver_hash text
) returns void language plpgsql as $$
declare body text := 'Synthetic payer ambiguity ' || event_id::text;
  capability_id uuid := gen_random_uuid();
  synthetic_request_hash text := encode(extensions.digest(body, 'sha256'), 'hex');
begin
  insert into public.native_action_capabilities(
    id, user_id, action, request_hash, request_payload,
    receiver_momo_number_hash, package_name, app_verdict, device_verdicts,
    verified_at, expires_at, consumed_at
  )
  select capability_id, capability.user_id, 'sms.ingest', synthetic_request_hash,
    jsonb_build_object('synthetic', true, 'event_id', event_id),
    coalesce(receiver_hash, capability.receiver_momo_number_hash),
    capability.package_name, capability.app_verdict,
    capability.device_verdicts, now(), now() + interval '4 minutes', now()
  from public.native_action_capabilities capability
  where capability.id = '99300000-0000-4000-8000-000000000101';
  insert into public.raw_payment_sms(
    id, collection_id, receiver_user_id, raw_sender, raw_body, body_hash,
    receiver_momo_number_hash, received_at_device, parse_status,
    native_action_capability_id, attestation_request_hash, device_attested_at
  ) values (
    raw_id, '99300000-0000-4000-8000-000000000010',
    '99100000-0000-4000-8000-000000000001', 'M-Money', body,
    encode(extensions.digest(body, 'sha256'), 'hex'), receiver_hash,
    now(), 'parsed', capability_id, synthetic_request_hash, now()
  );
  insert into public.parsed_payment_events(
    id, raw_sms_id, collection_id, receiver_user_id,
    is_mobile_money_payment, network, direction, amount_rwf, currency,
    transaction_id, sender_name, sender_phone_hash, receiver_phone_hash,
    detected_user_public_id, confidence, parser_model,
    parser_schema_version, payer_last3
  ) values (
    event_id, raw_id, '99300000-0000-4000-8000-000000000010',
    '99100000-0000-4000-8000-000000000001',
    true, 'mtn_momo', 'incoming', amount, 'RWF',
    provider_reference, 'DUPLICATE PERSON', sender_hash, receiver_hash,
    detected_public_id, 0.99, 'synthetic', 'collect.sms_parser.v4', '123'
  );
end;
$$;

select pg_temp.seed_event(
  '99500000-0000-4000-8000-000000000201',
  '99500000-0000-4000-8000-000000000211',
  'F09A2000', 2000,
  public._authenticated_momo_phone_hash(
    '99500000-0000-4000-8000-000000000001'), null,
  (select momo_number_hash from public.collection_receivers
    where id = '99300000-0000-4000-8000-000000000020')
);
select pg_temp.seed_event(
  '99500000-0000-4000-8000-000000000202',
  '99500000-0000-4000-8000-000000000212',
  'F09B2000', 2000,
  public._authenticated_momo_phone_hash(
    '99500000-0000-4000-8000-000000000002'), null,
  (select momo_number_hash from public.collection_receivers
    where id = '99300000-0000-4000-8000-000000000020')
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event(
    '99500000-0000-4000-8000-000000000211')
      = 'awaiting_provider_confirmation',
  'first equal-value suffix/name event creates only a review candidate'
);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event(
    '99500000-0000-4000-8000-000000000212')
      = 'awaiting_provider_confirmation',
  'second equal-value suffix/name event creates only its own review candidate'
);
reset role;
select pg_temp.assert_true(
  (select count(*) from public.payments
   where parsed_event_id in ('99500000-0000-4000-8000-000000000211',
                             '99500000-0000-4000-8000-000000000212')
     and status = 'review') = 2
  and exists (select 1 from public.payments
    where parsed_event_id = '99500000-0000-4000-8000-000000000211'
      and payment_intent_id = '99500000-0000-4000-8000-000000000301'
      and contributor_user_id = '99500000-0000-4000-8000-000000000001')
  and exists (select 1 from public.payments
    where parsed_event_id = '99500000-0000-4000-8000-000000000212'
      and payment_intent_id = '99500000-0000-4000-8000-000000000302'
      and contributor_user_id = '99500000-0000-4000-8000-000000000002'),
  'exact confirmed phone hashes bind equal-value receipts to separate payers'
);
select pg_temp.assert_true(
  not exists (select 1 from public.ledger_entries ledger
    join public.payments payment on payment.id = ledger.payment_id
    where payment.parsed_event_id in (
      '99500000-0000-4000-8000-000000000211',
      '99500000-0000-4000-8000-000000000212'))
  and not exists (select 1 from collect_hybrid.momo_journal_entries journal
    join public.payments payment on payment.id = journal.payment_id
    where payment.parsed_event_id in (
      '99500000-0000-4000-8000-000000000211',
      '99500000-0000-4000-8000-000000000212')),
  'SMS-only equal-value candidates cannot credit either payer or group'
);

-- A shared name/last-three/amount without a confirmed sender hash is review.
select pg_temp.seed_event(
  '99500000-0000-4000-8000-000000000203',
  '99500000-0000-4000-8000-000000000213',
  'F09NOHASH', 2000, null, null,
  (select momo_number_hash from public.collection_receivers
    where id = '99300000-0000-4000-8000-000000000020')
);
set local role service_role;
select pg_temp.assert_true(
  public.allocate_parsed_payment_event(
    '99500000-0000-4000-8000-000000000213') = 'needs_review',
  'same amount name and suffix cannot replace confirmed payer evidence'
);
reset role;
select pg_temp.assert_true(
  not exists (select 1 from public.payments
    where parsed_event_id = '99500000-0000-4000-8000-000000000213')
  and exists (select 1 from collect_hybrid.momo_reconciliation_exceptions
    where parsed_event_id = '99500000-0000-4000-8000-000000000213'
      and code = 'no_candidate' and status = 'open'),
  'weak-name/suffix evidence records review without a payment candidate'
);

-- A public ID naming the other payer cannot override the exact sender hash.
select pg_temp.seed_event(
  '99500000-0000-4000-8000-000000000204',
  '99500000-0000-4000-8000-000000000214',
  'F09WRONGID', 2000,
  public._authenticated_momo_phone_hash(
    '99500000-0000-4000-8000-000000000001'),
  (select public_id from public.profiles
   where id = '99500000-0000-4000-8000-000000000002'),
  (select momo_number_hash from public.collection_receivers
    where id = '99300000-0000-4000-8000-000000000020')
);
set local role service_role;
select pg_temp.assert_true(
  public.allocate_parsed_payment_event(
    '99500000-0000-4000-8000-000000000214') = 'needs_review',
  'conflicting public ID cannot select the other same-suffix payer'
);
reset role;
select pg_temp.assert_true(
  not exists (select 1 from public.payments
    where parsed_event_id = '99500000-0000-4000-8000-000000000214'),
  'public-ID conflict adds no payment or balance'
);

-- Even a different confirmed payer cannot reuse a consumed provider reference.
select pg_temp.seed_event(
  '99500000-0000-4000-8000-000000000205',
  '99500000-0000-4000-8000-000000000215',
  'F09A2000', 2000,
  public._authenticated_momo_phone_hash(
    '99500000-0000-4000-8000-000000000002'), null,
  (select momo_number_hash from public.collection_receivers
    where id = '99300000-0000-4000-8000-000000000020')
);
set local role service_role;
select pg_temp.assert_true(
  public.allocate_parsed_payment_event(
    '99500000-0000-4000-8000-000000000215') = 'ignored',
  'provider reference consumed by first payer cannot route to second payer'
);
reset role;
select pg_temp.assert_true(
  not exists (select 1 from public.payments
    where parsed_event_id = '99500000-0000-4000-8000-000000000215')
  and (select allocation_status = 'ignored'
    from public.parsed_payment_events
    where id = '99500000-0000-4000-8000-000000000215'),
  'cross-payer provider-reference replay creates no extra candidate'
);

-- Two pending intents for the same verified payer and amount but different
-- receiving routes must be ambiguous when the SMS receiver is unavailable.
insert into public.collection_receivers(
  id, collection_id, receiver_user_id, momo_number, momo_number_hash,
  network, label, is_active
) values (
  '99500000-0000-4000-8000-000000000020',
  '99300000-0000-4000-8000-000000000010',
  '99100000-0000-4000-8000-000000000001',
  '41259', repeat('c', 64), 'mtn_momo', 'Second synthetic route', true
);
insert into public.payment_intents(
  id, collection_id, contributor_user_id, contributor_public_id,
  contribution_code, expected_amount_rwf, receiver_momo_number_hash,
  sender_phone_hash, status, anonymity_choice, expires_at
)
select
  case when route.id = '99500000-0000-4000-8000-000000000020'
    then '99500000-0000-4000-8000-000000000304'::uuid
    else '99500000-0000-4000-8000-000000000303'::uuid end,
  '99300000-0000-4000-8000-000000000010',
  profile.id, profile.public_id,
  case when route.id = '99500000-0000-4000-8000-000000000020'
    then 'F09-AMBIG-002' else 'F09-AMBIG-001' end,
  2300, route.momo_number_hash,
  public._authenticated_momo_phone_hash(profile.id),
  'pending', 'public_id', now() + interval '1 hour'
from public.profiles profile
join public.collection_receivers route
  on route.id in ('99300000-0000-4000-8000-000000000020',
                  '99500000-0000-4000-8000-000000000020')
where profile.id = '99500000-0000-4000-8000-000000000001';
select pg_temp.seed_event(
  '99500000-0000-4000-8000-000000000206',
  '99500000-0000-4000-8000-000000000216',
  'F09AMBIG', 2300,
  public._authenticated_momo_phone_hash(
    '99500000-0000-4000-8000-000000000001'), null, null
);
set local role service_role;
select pg_temp.assert_true(
  public.allocate_parsed_payment_event(
    '99500000-0000-4000-8000-000000000216') = 'ambiguous',
  'same payer and amount with two active routes requires review'
);
reset role;
select pg_temp.assert_true(
  not exists (select 1 from public.payments
    where parsed_event_id = '99500000-0000-4000-8000-000000000216')
  and exists (select 1 from collect_hybrid.momo_reconciliation_exceptions
    where parsed_event_id = '99500000-0000-4000-8000-000000000216'
      and code = 'ambiguous_candidate' and status = 'open'),
  'two-intent route ambiguity adds no payment or ledger credit'
);
select pg_temp.assert_true(
  (select confirmed_rwf = 1500
    from collect_hybrid.collection_balances
    where collection_id = '99300000-0000-4000-8000-000000000010')
  and (select count(*) from public.payments) = 4,
  'all adversarial SMS outcomes leave the confirmed balance unchanged'
);

select 'PAYER_IDENTITY_ADVERSARIAL_UAT_PASS: ' || count(*)
  || ' assertions; full-schema synthetic rollback only'
from pg_temp.test_results;
rollback;
