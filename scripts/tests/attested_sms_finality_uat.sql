\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';

do $$ begin
  if coalesce(current_setting('collect.recovery_drill', true), '')
       <> 'production-archive-v1'
     and current_database() not in (
       'collect_attested_uat_20260903',
       'collect_hybrid_money_uat_20260903'
     ) then
    raise exception 'Isolated attested-SMS UAT database required';
  end if;
  if to_regprocedure('public.finalize_attested_payment_sms(uuid)') is null then
    raise exception 'Attested-SMS contract migration is required';
  end if;
end $$;

create temp table test_results(label text primary key);
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
grant all on pg_temp.test_results to service_role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.attested_sms_contract_version() = 0,
  'installed clients remain on the legacy SMS contract before rollout acceptance'
);
reset role;
update public.feature_flags
set enabled = true
where key = 'native_sms_attestation_enforcement';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.attested_sms_contract_version() = 1,
  'accepted rollout can activate the attested SMS contract independently'
);
reset role;

insert into auth.users(
  id, aud, role, phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data
) values (
  '99000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
  '250788990001', now(), '{}', '{}'
);
insert into public.collections(
  id, slug, creator_user_id, title, category, visibility, public_status,
  collection_type, contribution_visibility, allow_anonymous,
  diaspora_enabled, creation_origin
) values (
  '99000000-0000-4000-8000-000000000010', 'attested-sms-finality-uat',
  '99000000-0000-4000-8000-000000000001', 'Attested SMS finality UAT',
  'Family / friends', 'private', 'private', 'ikimina', 'members', false,
  false, 'member_app'
);
insert into public.collection_members(collection_id, user_id, role, status)
values (
  '99000000-0000-4000-8000-000000000010',
  '99000000-0000-4000-8000-000000000001', 'owner', 'active'
);
insert into public.collection_receivers(
  id, collection_id, receiver_user_id, momo_number, momo_number_hash,
  network, label, is_active
) values (
  '99000000-0000-4000-8000-000000000020',
  '99000000-0000-4000-8000-000000000010',
  '99000000-0000-4000-8000-000000000001', '0788990001', repeat('a', 64),
  'mtn_momo', 'Attested UAT receiver', true
);
insert into public.receiver_mode_consents(
  id, user_id, enabled, momo_number_hash, build_channel, device_label, created_at
) values (
  '99000000-0000-4000-8000-000000000030',
  '99000000-0000-4000-8000-000000000001', true, repeat('a', 64),
  'android_sms_ingest_attested', 'synthetic_play_integrity', now()
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.mint_native_action_capability(
  '99000000-0000-4000-8000-000000000001',
  'sms.ingest', repeat('b', 64),
  jsonb_build_object(
    'receiver_momo_number_hash', repeat('a', 64),
    'client_envelope_id', '99000000-0000-4000-8000-000000000040',
    'raw_sender', 'M-Money',
    'raw_body_sha256', encode(extensions.digest(
      'You have received RWF 1,234. Transaction ID ATTESTED1234', 'sha256'
    ), 'hex'),
    'received_at_device', null
  ),
  repeat('a', 64), 'app.cool.mobile', 'PLAY_RECOGNIZED',
  array['MEETS_DEVICE_INTEGRITY'], now()
) as capability_id \gset

select public.ingest_attested_raw_payment_sms(
  :'capability_id',
  '99000000-0000-4000-8000-000000000001', null,
  'M-Money', 'You have received RWF 1,234. Transaction ID ATTESTED1234',
  encode(extensions.digest(
    'You have received RWF 1,234. Transaction ID ATTESTED1234', 'sha256'
  ), 'hex'),
  '99000000-0000-4000-8000-000000000040', repeat('a', 64), null
) as ingestion \gset

select pg_temp.assert_true(
  :'ingestion'::jsonb ->> 'attested' = 'true'
    and :'ingestion'::jsonb ->> 'replay' = 'false',
  'fresh Play Integrity capability binds one raw SMS envelope'
);
reset role;
select pg_temp.assert_true(
  exists (
    select 1 from public.raw_payment_sms raw
    join public.native_action_capabilities capability
      on capability.id = raw.native_action_capability_id
    where raw.id = (:'ingestion'::jsonb ->> 'id')::uuid
      and raw.attestation_request_hash = repeat('b', 64)
      and raw.device_attested_at is not null
      and capability.consumed_at is not null
  ),
  'raw provider evidence retains its consumed attestation binding'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.ingest_attested_raw_payment_sms(
  :'capability_id',
  '99000000-0000-4000-8000-000000000001', null,
  'M-Money', 'You have received RWF 1,234. Transaction ID ATTESTED1234',
  encode(extensions.digest(
    'You have received RWF 1,234. Transaction ID ATTESTED1234', 'sha256'
  ), 'hex'),
  '99000000-0000-4000-8000-000000000040', repeat('a', 64), null
) as replay \gset
select pg_temp.assert_true(
  :'replay'::jsonb ->> 'replay' = 'true'
    and :'replay'::jsonb ->> 'id' = :'ingestion'::jsonb ->> 'id',
  'consumed capability retry returns the same raw evidence'
);
reset role;
select pg_temp.expect_error(
  format(
    'update public.raw_payment_sms set attestation_request_hash=%L where id=%L',
    repeat('c', 64), :'ingestion'::jsonb ->> 'id'
  ),
  'Raw SMS attestation is immutable',
  'attested raw evidence cannot be rewritten'
);

insert into public.parsed_payment_events(
  id, raw_sms_id, receiver_user_id, is_mobile_money_payment, network,
  direction, amount_rwf, currency, transaction_id, receiver_phone_hash,
  confidence, parser_schema_version, allocation_status, transaction_time
) values (
  '99000000-0000-4000-8000-000000000050',
  (:'ingestion'::jsonb ->> 'id')::uuid,
  '99000000-0000-4000-8000-000000000001', true, 'mtn_momo', 'incoming',
  1234, 'RWF', 'ATTESTED1234', repeat('a', 64), 0.99,
  'collect.sms_parser.v4', 'needs_review', now()
);
insert into public.payments(
  id, parsed_event_id, collection_id, contributor_user_id, receiver_user_id,
  receiver_momo_number_hash, amount_rwf, transaction_id, provider_network,
  source, status, anonymity_choice, posted_at
) values (
  '99000000-0000-4000-8000-000000000060',
  '99000000-0000-4000-8000-000000000050',
  '99000000-0000-4000-8000-000000000010',
  '99000000-0000-4000-8000-000000000001',
  '99000000-0000-4000-8000-000000000001', repeat('a', 64), 1234,
  'ATTESTED1234', 'mtn_momo', 'sms_auto', 'review', 'anonymous', null
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.finalize_attested_payment_sms(
  (:'ingestion'::jsonb ->> 'id')::uuid
) as finality \gset
reset role;
select pg_temp.assert_true(
  :'finality'::jsonb ->> 'status' = 'posted'
    and :'finality'::jsonb ->> 'payment_id'
      = '99000000-0000-4000-8000-000000000060',
  'attested provider SMS finalizes its matching review candidate'
);
select pg_temp.assert_true(
  (select status = 'posted' and posted_at is not null
   from public.payments where id = '99000000-0000-4000-8000-000000000060'),
  'provider-attested candidate transitions to posted'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.payment_provider_confirmations
   where payment_id = '99000000-0000-4000-8000-000000000060'),
  'one immutable provider confirmation is retained'
);
select pg_temp.assert_true(
  (select count(*) = 2 and sum(amount_rwf) = 2468
   from public.ledger_entries
   where payment_id = '99000000-0000-4000-8000-000000000060'),
  'legacy read projection receives one group and one member credit'
);
select pg_temp.assert_true(
  (select count(*) = 1
   from collect_hybrid.momo_journal_entries
   where payment_id = '99000000-0000-4000-8000-000000000060'
     and entry_type = 'receipt'),
  'canonical journal posts exactly one balanced receipt'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.finalize_attested_payment_sms(
  (:'ingestion'::jsonb ->> 'id')::uuid
) as replay_finality \gset
select pg_temp.assert_true(
  :'replay_finality'::jsonb ->> 'status' = 'posted'
    and :'replay_finality'::jsonb ->> 'replayed' = 'true',
  'attested finality retry is idempotent'
);
reset role;

select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated',
    'public.ingest_attested_raw_payment_sms(uuid,uuid,uuid,text,text,text,uuid,text,text)',
    'execute'
  ) and not has_function_privilege(
    'authenticated', 'public.finalize_attested_payment_sms(uuid)', 'execute'
  ),
  'browser clients cannot invoke attestation or finality functions'
);
select pg_temp.assert_true(
  has_function_privilege(
    'service_role',
    'public.ingest_attested_raw_payment_sms(uuid,uuid,uuid,text,text,text,uuid,text,text)',
    'execute'
  ) and has_function_privilege(
    'service_role', 'public.finalize_attested_payment_sms(uuid)', 'execute'
  ),
  'service boundary can ingest and finalize attested evidence'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.feature_flags
    where key = 'hybrid_direct_ussd_allocation' and not enabled
  ),
  'direct USSD allocation remains disabled'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.feature_flags
    where key = 'native_sms_attestation_enforcement' and enabled
  ),
  'attested SMS enforcement is explicit in the isolated acceptance scenario'
);

select label from pg_temp.test_results order by label;
select 'ATTESTED_SMS_FINALITY_UAT_PASS: '
  || count(*) || ' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
