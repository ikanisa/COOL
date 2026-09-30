\set ON_ERROR_STOP on
-- Commit only synthetic rows in the dedicated 136–138-migration concurrency
-- fixture. The two parsed events share one provider reference by design.
begin;
set local statement_timeout = '30s';

do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations) <>
       (case (select max(version) from supabase_migrations.schema_migrations)
         when '20260929130000' then 136
         when '20260929140000' then 137
         when '20260929150000' then 138
         else -1 end)
     or (select count(*) from auth.users) <> 1
     or (select count(*) from public.payments) <> 0
     or (select count(*) from public.payment_intents) <> 0
     or (select count(*) from public.raw_payment_sms) <> 0
     or (select count(*) from public.parsed_payment_events) <> 0
     or (select count(*) from public.collections where slug = 'buri-munsi'
       and currency = 'RWF' and not diaspora_enabled) <> 1
     or (select count(*) from public.collection_receivers receiver
       join public.collections collection on collection.id = receiver.collection_id
       where collection.slug = 'buri-munsi' and receiver.is_active
         and receiver.network = 'mtn_momo') <> 1
     or exists (select 1 from auth.users
       where id = '99600000-0000-4000-8000-000000000001') then
    raise exception 'Exact clean local concurrency fixture required';
  end if;
end $$;

insert into auth.users(
  id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '99600000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', '250788006123', now(), '{}', '{}'
);
update public.profiles
set country_code = 'RW', currency_code = 'RWF',
    momo_provider = 'mtn_momo', momo_number = '0788006123',
    momo_number_hash = encode(extensions.digest('+250788006123', 'sha256'), 'hex')
where id = '99600000-0000-4000-8000-000000000001';
insert into public.collection_members(collection_id, user_id, role, status)
select collection.id, '99600000-0000-4000-8000-000000000001',
  'member', 'active'
from public.collections collection where collection.slug = 'buri-munsi';

insert into public.payment_intents(
  id, collection_id, contributor_user_id, contributor_public_id,
  contribution_code, expected_amount_rwf, receiver_momo_number_hash,
  sender_phone_hash, status, anonymity_choice, expires_at
)
select
  '99600000-0000-4000-8000-000000000301',
  collection.id, profile.id, profile.public_id,
  'F08-RACE-2500', 2500, receiver.momo_number_hash,
  public._authenticated_momo_phone_hash(profile.id),
  'pending', 'public_id', now() + interval '1 hour'
from public.collections collection
join public.collection_receivers receiver
  on receiver.collection_id = collection.id and receiver.is_active
join public.profiles profile
  on profile.id = '99600000-0000-4000-8000-000000000001'
where collection.slug = 'buri-munsi';

insert into public.native_action_capabilities(
  id, user_id, action, request_hash, request_payload,
  receiver_momo_number_hash, package_name, app_verdict, device_verdicts,
  verified_at, expires_at, consumed_at
)
select capability.id,
  '99100000-0000-4000-8000-000000000001', 'sms.ingest',
  capability.request_hash,
  jsonb_build_object('synthetic', true, 'race_event', capability.label),
  receiver.momo_number_hash, 'app.cool.mobile', 'PLAY_RECOGNIZED',
  array['MEETS_DEVICE_INTEGRITY']::text[],
  now(), now() + interval '4 minutes', now()
from (values
  ('99600000-0000-4000-8000-000000000101'::uuid, repeat('1', 64), 'A'),
  ('99600000-0000-4000-8000-000000000102'::uuid, repeat('2', 64), 'B')
) capability(id, request_hash, label)
cross join public.collections collection
join public.collection_receivers receiver
  on receiver.collection_id = collection.id and receiver.is_active
where collection.slug = 'buri-munsi';

insert into public.raw_payment_sms(
  id, collection_id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
)
select sms.id, collection.id,
  '99100000-0000-4000-8000-000000000001', 'M-Money',
  sms.body, encode(extensions.digest(sms.body, 'sha256'), 'hex'),
  receiver.momo_number_hash, now(), 'parsed',
  sms.capability_id, sms.request_hash, now()
from (values
  ('99600000-0000-4000-8000-000000000201'::uuid,
   'Synthetic concurrent receipt A',
   '99600000-0000-4000-8000-000000000101'::uuid, repeat('1', 64)),
  ('99600000-0000-4000-8000-000000000202'::uuid,
   'Synthetic concurrent receipt B',
   '99600000-0000-4000-8000-000000000102'::uuid, repeat('2', 64))
) sms(id, body, capability_id, request_hash)
cross join public.collections collection
join public.collection_receivers receiver
  on receiver.collection_id = collection.id and receiver.is_active
where collection.slug = 'buri-munsi';

insert into public.parsed_payment_events(
  id, raw_sms_id, collection_id, receiver_user_id,
  is_mobile_money_payment, network, direction, amount_rwf, currency,
  transaction_id, sender_name, sender_phone_hash, receiver_phone_hash,
  confidence, parser_model, parser_schema_version, payer_last3
)
select event.id, event.raw_id, collection.id,
  '99100000-0000-4000-8000-000000000001',
  true, 'mtn_momo', 'incoming', 2500, 'RWF',
  'RACE2500', 'RACE PAYER',
  public._authenticated_momo_phone_hash(
    '99600000-0000-4000-8000-000000000001'),
  receiver.momo_number_hash, 0.99, 'synthetic',
  'collect.sms_parser.v4', '123'
from (values
  ('99600000-0000-4000-8000-000000000211'::uuid,
   '99600000-0000-4000-8000-000000000201'::uuid),
  ('99600000-0000-4000-8000-000000000212'::uuid,
   '99600000-0000-4000-8000-000000000202'::uuid)
) event(id, raw_id)
cross join public.collections collection
join public.collection_receivers receiver
  on receiver.collection_id = collection.id and receiver.is_active
where collection.slug = 'buri-munsi';

do $$ begin
  if (select count(*) from auth.users) <> 2
     or (select count(*) from public.payment_intents
       where id = '99600000-0000-4000-8000-000000000301'
         and status = 'pending' and expected_amount_rwf = 2500) <> 1
     or (select count(*) from public.raw_payment_sms) <> 2
     or (select count(*) from public.parsed_payment_events
       where transaction_id = 'RACE2500') <> 2
     or (select count(*) from public.payments) <> 0 then
    raise exception 'Synthetic concurrent fixture seed incomplete';
  end if;
end $$;
commit;
select 'FINANCIAL_CONCURRENCY_SEED_PASS';
