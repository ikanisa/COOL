\set ON_ERROR_STOP on
-- Rollback-only characterization of the current late-SMS intent behavior.
-- These are synthetic SMS observations, never independent provider evidence.
begin;
set local statement_timeout = '60s';

do $$ begin
  if current_database() <> 'collect_financial_restore_empty_20260928'
     or current_setting('cron.launch_active_jobs') <> 'off'
     or current_setting('pg_net.database_name') <> 'template1'
     or (select count(*) from supabase_migrations.schema_migrations) <> 133
     or (select count(*) from auth.users) <> 1
     or (select count(*) from public.payment_intents) <> 1
     or (select count(*) from public.raw_payment_sms) <> 3
     or (select count(*) from public.payments) <> 2 then
    raise exception 'Exact isolated restored financial fixture required';
  end if;
end $$;

create temp table boundary_cases(
  n integer primary key, label text not null,
  intent_created_at timestamptz not null,
  intent_expires_at timestamptz not null,
  device_received_at timestamptz not null,
  expected_result text not null
);
insert into pg_temp.boundary_cases values
  (1, 'active-on-time', now() - interval '1 hour',
    now() + interval '5 minutes', now() - interval '30 seconds',
    'awaiting_provider_confirmation'),
  (2, 'exact-expiry', now() - interval '1 hour',
    now(), now() - interval '30 seconds', 'needs_review'),
  (3, 'one-minute-late-upload', now() - interval '1 hour',
    now() - interval '1 minute', now() - interval '2 minutes', 'needs_review'),
  (4, 'past-two-hour-evidence-window', now() - interval '3 hours',
    now() - interval '2 hours 1 minute', now() - interval '2 hours 2 minutes',
    'needs_review'),
  (5, 'fourteen-minute-early-device-clock', now() - interval '30 minutes',
    now() + interval '5 minutes', now() - interval '44 minutes',
    'awaiting_provider_confirmation'),
  (6, 'sixteen-minute-early-device-clock', now() - interval '30 minutes',
    now() + interval '5 minutes', now() - interval '46 minutes',
    'needs_review');

create temp table boundary_results(
  n integer primary key, result text not null
);
grant select on pg_temp.boundary_cases to service_role;
grant insert, select on pg_temp.boundary_results to service_role;

insert into public.native_action_capabilities(
  id, user_id, action, request_hash, request_payload,
  receiver_momo_number_hash, package_name, app_verdict, device_verdicts,
  verified_at, expires_at, consumed_at
)
select ('99730000-0000-4000-8000-' || lpad(c.n::text,12,'0'))::uuid,
  '99100000-0000-4000-8000-000000000001'::uuid,
  'sms.ingest', repeat('b',64), '{}'::jsonb,
  route.momo_number_hash, 'app.cool.mobile', 'PLAY_RECOGNIZED',
  array['MEETS_DEVICE_INTEGRITY'], now(), now() + interval '5 minutes', now()
from pg_temp.boundary_cases c
join public.collection_receivers route
  on route.id = '99300000-0000-4000-8000-000000000020'::uuid;

insert into public.payment_intents(
  id, collection_id, contributor_user_id, contribution_code,
  expected_amount_rwf, receiver_momo_number_hash, sender_phone_hash,
  status, anonymity_choice, created_at, expires_at
)
select ('99700000-0000-4000-8000-' || lpad(c.n::text,12,'0'))::uuid,
  route.collection_id, profile.id, 'SYNTH-BOUNDARY-' || c.n,
  5000 + c.n, route.momo_number_hash, profile.momo_number_hash,
  'pending', 'anonymous', c.intent_created_at, c.intent_expires_at
from pg_temp.boundary_cases c
join public.collection_receivers route
  on route.id = '99300000-0000-4000-8000-000000000020'::uuid
join public.profiles profile
  on profile.id = '99100000-0000-4000-8000-000000000001'::uuid;

insert into public.raw_payment_sms(
  id, collection_id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
)
select ('99710000-0000-4000-8000-' || lpad(c.n::text,12,'0'))::uuid,
  route.collection_id, route.receiver_user_id, 'M-Money',
  'SYNTH-BOUNDARY-SMS-' || c.n,
  encode(extensions.digest('SYNTH-BOUNDARY-SMS-' || c.n, 'sha256'), 'hex'),
  route.momo_number_hash, c.device_received_at, 'parsed',
  ('99730000-0000-4000-8000-' || lpad(c.n::text,12,'0'))::uuid,
  repeat('b',64), now()
from pg_temp.boundary_cases c
join public.collection_receivers route
  on route.id = '99300000-0000-4000-8000-000000000020'::uuid;

insert into public.parsed_payment_events(
  id, raw_sms_id, collection_id, receiver_user_id,
  is_mobile_money_payment, network, direction, amount_rwf, currency,
  sender_phone_hash, receiver_phone_hash, transaction_id,
  transaction_time, confidence, parser_model, parser_schema_version
)
select ('99720000-0000-4000-8000-' || lpad(c.n::text,12,'0'))::uuid,
  ('99710000-0000-4000-8000-' || lpad(c.n::text,12,'0'))::uuid,
  route.collection_id, route.receiver_user_id,
  true, 'mtn_momo', 'incoming', 5000 + c.n, 'RWF',
  profile.momo_number_hash, route.momo_number_hash,
  'SYNTH-BOUNDARY-TXN-' || c.n,
  c.device_received_at, 0.99, 'synthetic', 'collect.sms_parser.v4'
from pg_temp.boundary_cases c
join public.collection_receivers route
  on route.id = '99300000-0000-4000-8000-000000000020'::uuid
join public.profiles profile
  on profile.id = '99100000-0000-4000-8000-000000000001'::uuid;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true) \gset
do $$
declare case_row record;
begin
  for case_row in select n from pg_temp.boundary_cases order by n loop
    insert into pg_temp.boundary_results(n,result)
    values (case_row.n, public.allocate_parsed_payment_event(
      ('99720000-0000-4000-8000-' || lpad(case_row.n::text,12,'0'))::uuid));
  end loop;
end $$;
do $$
declare rejected boolean := false;
declare caught text;
begin
  begin
    perform public.post_payment_from_event(
      '99720000-0000-4000-8000-000000000003'::uuid,
      '99700000-0000-4000-8000-000000000003'::uuid,
      '99300000-0000-4000-8000-000000000010'::uuid,
      'Synthetic late-intent direct-call guard');
  exception when others then
    caught := sqlerrm;
    rejected := caught = 'permission denied for function post_payment_from_event';
  end;
  if not rejected then
    raise exception 'Service role directly called private post function: %',
      coalesce(caught, 'function returned');
  end if;
end $$;
reset role;
do $$
declare rejected boolean := false;
declare caught text;
begin
  begin
    perform public.post_payment_from_event(
      '99720000-0000-4000-8000-000000000003'::uuid,
      '99700000-0000-4000-8000-000000000003'::uuid,
      '99300000-0000-4000-8000-000000000010'::uuid,
      'Synthetic late-intent privileged guard');
  exception when others then
    caught := sqlerrm;
    rejected := caught = 'Payment intent is not active';
  end;
  if not rejected then
    raise exception 'Expired intent privileged post guard was not observed: %',
      coalesce(caught, 'function returned');
  end if;
end $$;

do $$ begin
  if exists (
    select 1 from pg_temp.boundary_cases c
    join pg_temp.boundary_results r on r.n = c.n
    where r.result <> c.expected_result
  ) or (select count(*) from pg_temp.boundary_results) <> 6 then
    raise exception 'Late-intent boundary result changed';
  end if;
  if (select count(*) from public.payments
      where parsed_event_id::text like '99720000-%') <> 2
     or (select count(*) from public.payments
      where parsed_event_id::text like '99720000-%' and status = 'posted') <> 0
     or (select count(*) from public.ledger_entries) <> 2
     or (select count(*) from public.payment_intents
      where id::text like '99700000-%' and status = 'matched') <> 2
     or (select count(*) from public.payment_intents
      where id::text like '99700000-%' and status = 'expired') <> 3 then
    raise exception 'Late-intent evidence altered positive financial state';
  end if;
end $$;

select c.n, c.label, r.result, intent.status,
  (select count(*) from public.payments payment
    where payment.parsed_event_id = event.id) as candidate_payments
from pg_temp.boundary_cases c
join pg_temp.boundary_results r on r.n = c.n
join public.payment_intents intent
  on intent.id = ('99700000-0000-4000-8000-' || lpad(c.n::text,12,'0'))::uuid
join public.parsed_payment_events event
  on event.id = ('99720000-0000-4000-8000-' || lpad(c.n::text,12,'0'))::uuid
order by c.n;
\echo LATE_INTENT_BOUNDARY_UAT_PASS_8
rollback;
