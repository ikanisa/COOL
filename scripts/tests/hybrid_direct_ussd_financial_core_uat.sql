\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';

do $$ begin
  if current_database() not in (
    'collect_hybrid_uat_20260902',
    'collect_hybrid_money_uat_20260903'
  ) and not (
    current_database() = 'postgres'
    and coalesce(current_setting('collect.local_financial_uat', true), '')
      = 'clean-replay-current'
  ) then
    raise exception 'Isolated local hybrid UAT database required';
  end if;
  if (select count(*) from auth.users) > 1
     or exists(select 1 from public.payments)
     or exists(select 1 from public.raw_payment_sms) then
    raise exception 'Synthetic UAT requires an empty transaction namespace and at most one bootstrap owner';
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

create function pg_temp.expect_error(command text, fragment text, label text) returns void
language plpgsql as $$
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
  ('97000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   '250788970001', now(), '{}', '{}'),
  ('97000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   '250788970002', now(), '{}', '{}');
update public.profiles set is_platform_admin = true
where id = '97000000-0000-4000-8000-000000000001';
insert into public.admin_user_roles(user_id, role_id, granted_by, reason, created_at)
select
  '97000000-0000-4000-8000-000000000001', role.id,
  '97000000-0000-4000-8000-000000000001',
  'Synthetic direct USSD financial UAT bootstrap', now() - interval '2 seconds'
from public.admin_roles role
where role.name = 'platform_owner';
insert into auth.sessions(id, user_id, created_at, updated_at, not_after)
values (
  '97000000-0000-4000-8000-000000000099',
  '97000000-0000-4000-8000-000000000001',
  now() - interval '1 second', now(), now() + interval '1 hour'
);
do $$ begin
  if to_regclass('collect_admin_access.whatsapp_approvals') is not null then
    execute $q$
      insert into collect_admin_access.whatsapp_approvals(
        user_id, phone_e164, approved_at, approved_by, reason
      ) values (
        '97000000-0000-4000-8000-000000000001', '+250788970001',
        now() - interval '2 seconds',
        '97000000-0000-4000-8000-000000000001',
        'Synthetic direct USSD financial UAT bootstrap'
      )
    $q$;
  end if;
end $$;
update public.feature_flags set enabled = true
where key in ('hybrid_member_onboarding', 'hybrid_direct_ussd_allocation');
insert into public.notification_channels(key, label, description, platform, display_order, enabled)
values ('collect_group_updates', 'Collect group updates', 'Synthetic UAT channel', 'all', 10, true)
on conflict (key) do update set enabled = true;
insert into public.notification_event_types(
  key, preference_key, label, description, default_channel_key, display_order, enabled
) values (
  'contribution_confirmed', 'contribution_confirmations', 'Contribution confirmed',
  'Synthetic UAT confirmation event', 'collect_group_updates', 10, true
)
on conflict (key) do update set enabled = true;
insert into public.notification_templates(key, event_type_key, locale, enabled)
values ('contribution.confirmed.default', 'contribution_confirmed', 'en', true)
on conflict (key) do update set enabled = true;
insert into public.notification_template_versions(
  template_key, version, title_template, body_template, status, effective_at, published_at
) values (
  'contribution.confirmed.default', 'synthetic-uat', 'Contribution confirmed',
  '{{amount}} has been confirmed for {{group}}.', 'published', now() - interval '1 hour', now() - interval '1 hour'
)
on conflict (template_key, version) do nothing;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"97000000-0000-4000-8000-000000000099"}',
  true
);
insert into pg_temp.test_values values (
  'group_one',
  public.admin_create_assisted_group(
    'Direct USSD savings one',
    'Synthetic direct allocation UAT group one',
    '97000000-0000-4000-8000-000000000101'
  )
);
insert into pg_temp.test_values values (
  'group_two',
  public.admin_create_assisted_group(
    'Direct USSD savings two',
    'Synthetic direct allocation UAT group two',
    '97000000-0000-4000-8000-000000000102'
  )
);
insert into pg_temp.test_values values (
  'roster_one',
  public.admin_add_assisted_roster(
    (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_one'),
    '[
      {"member_name":"UNIQUE MEMBER","momo_name":"UNIQUE MEMBER","momo_number":"0788000456"},
      {"member_name":"DUPLICATE ONE","momo_name":"DUPLICATE PERSON","momo_number":"0788000123"},
      {"member_name":"DUPLICATE TWO","momo_name":"DUPLICATE PERSON","momo_number":"0738000123"}
    ]',
    '97000000-0000-4000-8000-000000000103',
    'Reviewed synthetic direct allocation roster'
  )
);
insert into pg_temp.test_values values (
  'roster_two',
  public.admin_add_assisted_roster(
    (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_two'),
    '[{"member_name":"UNIQUE MEMBER","momo_name":"UNIQUE MEMBER","momo_number":"0788000456"}]',
    '97000000-0000-4000-8000-000000000104',
    'Reviewed synthetic cross group route conflict'
  )
);
reset role;

with inserted as (
  insert into public.collection_receivers(
    collection_id, receiver_user_id, momo_number, momo_number_hash,
    network, label, is_active
  ) values (
    (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_one'),
    '97000000-0000-4000-8000-000000000001', '41258', repeat('a', 64),
    'mtn_momo', 'Synthetic direct receiver one', true
  ) returning id
)
insert into pg_temp.test_values
select 'route_one', jsonb_build_object('id', id) from inserted;

with inserted as (
  insert into public.collection_receivers(
    collection_id, receiver_user_id, momo_number, momo_number_hash,
    network, label, is_active
  ) values (
    (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_two'),
    '97000000-0000-4000-8000-000000000001', '41258', repeat('a', 64),
    'mtn_momo', 'Synthetic direct receiver two', true
  ) returning id
)
insert into pg_temp.test_values
select 'route_two', jsonb_build_object('id', id) from inserted;

insert into pg_temp.test_values
select 'member_unique', jsonb_build_object('id', identity.member_id)
from collect_hybrid.member_momo_identities identity
where identity.momo_number = '+250788000456';
insert into pg_temp.test_values
select 'member_duplicate_one', jsonb_build_object('id', identity.member_id)
from collect_hybrid.member_momo_identities identity
where identity.momo_number = '+250788000123';
insert into pg_temp.test_values
select 'member_duplicate_two', jsonb_build_object('id', identity.member_id)
from collect_hybrid.member_momo_identities identity
where identity.momo_number = '+250738000123';
insert into public.collection_members(collection_id, user_id, role, status)
values (
  (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_two'),
  '97000000-0000-4000-8000-000000000002',
  'member',
  'active'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"97000000-0000-4000-8000-000000000099"}',
  true
);
insert into pg_temp.test_values values (
  'assign_unique',
  public.admin_assign_hybrid_receiving_route(
    (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_one'),
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'member_unique'),
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'route_one'),
    'Reviewed deterministic direct receiving assignment',
    '97000000-0000-4000-8000-000000000105'
  )
);
select pg_temp.assert_true(
  public.admin_assign_hybrid_receiving_route(
    (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_one'),
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'member_unique'),
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'route_one'),
    'Reviewed deterministic direct receiving assignment',
    '97000000-0000-4000-8000-000000000105'
  )->>'replay' = 'true',
  'receiving assignment retry is idempotent'
);
select pg_temp.expect_error(
  format(
    'select public.admin_assign_hybrid_receiving_route(%L,%L,%L,%L,%L)',
    (select value->>'collection_id' from pg_temp.test_values where key = 'group_two'),
    (select value->>'id' from pg_temp.test_values where key = 'member_unique'),
    (select value->>'id' from pg_temp.test_values where key = 'route_two'),
    'Reviewed conflicting physical receiving route',
    '97000000-0000-4000-8000-000000000106'
  ),
  'already assigned to another group',
  'same member and physical route cannot silently select another group'
);

do $$
declare target_member uuid;
begin
  for target_member in
    select (value->>'id')::uuid from pg_temp.test_values
    where key in ('member_duplicate_one', 'member_duplicate_two')
    order by key
  loop
    perform public.admin_assign_hybrid_receiving_route(
      (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_one'),
      target_member,
      (select (value->>'id')::uuid from pg_temp.test_values where key = 'route_one'),
      'Reviewed synthetic ambiguity receiving assignment',
      gen_random_uuid()
    );
  end loop;
end;
$$;
reset role;

insert into public.native_action_capabilities(
  id, user_id, action, request_hash, request_payload,
  receiver_momo_number_hash, package_name, app_verdict, device_verdicts,
  verified_at, expires_at, consumed_at
) select
  capability_id,
  '97000000-0000-4000-8000-000000000001'::uuid,
  'sms.ingest', repeat('b', 64), '{}'::jsonb, repeat('a', 64),
  'app.cool.mobile', 'PLAY_RECOGNIZED', array['MEETS_DEVICE_INTEGRITY'],
  now(), now() + interval '5 minutes', now()
from unnest(array[
  '97000000-0000-4000-8000-000000000801'::uuid,
  '97000000-0000-4000-8000-000000000802'::uuid,
  '97000000-0000-4000-8000-000000000803'::uuid,
  '97000000-0000-4000-8000-000000000804'::uuid,
  '97000000-0000-4000-8000-000000000805'::uuid,
  '97000000-0000-4000-8000-000000000806'::uuid,
  '97000000-0000-4000-8000-000000000807'::uuid
]) capability_id;

insert into public.raw_payment_sms(
  id, collection_id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
) values (
  '97000000-0000-4000-8000-000000000201', null,
  '97000000-0000-4000-8000-000000000001', 'M-Money',
  'Txn DIRECT1500. You have received 1,500 RWF from UNIQUE MEMBER (***456). Your balance: 9,500 RWF.',
  encode(extensions.digest(
    'Txn DIRECT1500. You have received 1,500 RWF from UNIQUE MEMBER (***456). Your balance: 9,500 RWF.',
    'sha256'
  ), 'hex'),
  repeat('a', 64), now(), 'parsed',
  '97000000-0000-4000-8000-000000000801', repeat('b', 64), now()
);
insert into public.parsed_payment_events(
  id, raw_sms_id, receiver_user_id, is_mobile_money_payment, network,
  direction, amount_rwf, currency, sender_name, receiver_phone_hash,
  transaction_id, transaction_time, confidence, parser_model, parser_schema_version,
  payer_last3, payer_match_key, wallet_balance_rwf
) select
  '97000000-0000-4000-8000-000000000211',
  '97000000-0000-4000-8000-000000000201',
  '97000000-0000-4000-8000-000000000001', true, 'mtn_momo',
  'incoming', 1500, 'RWF', 'UNIQUE MEMBER', repeat('a', 64),
  'DIRECT1500', now(), 0.99, 'synthetic', 'collect.sms_parser.v4',
  '456', identity.match_key, 9500
from collect_hybrid.member_momo_identities identity
where identity.momo_number = '+250788000456';

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event('97000000-0000-4000-8000-000000000211') = 'awaiting_provider_confirmation',
  'masked direct USSD receipt creates only a provider-confirmation candidate'
);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event('97000000-0000-4000-8000-000000000211') = 'awaiting_provider_confirmation',
  'direct candidate retry is idempotent while confirmation is pending'
);
reset role;

select pg_temp.assert_true(
  (select payment.payment_intent_id is null
      and payment.member_record_id = identity.member_id
      and payment.status = 'review'
    from public.payments payment
    join collect_hybrid.member_momo_identities identity
      on identity.momo_number = '+250788000456'
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211'),
  'direct candidate is bound to the offline member record'
);
select pg_temp.assert_true(
  not exists(select 1 from public.ledger_entries ledger
    where ledger.payment_id = (select payment.id from public.payments payment
      where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211'))
  and not exists(select 1 from collect_hybrid.momo_journal_entries entry
    where entry.payment_id = (select payment.id from public.payments payment
      where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211')),
  'unconfirmed SMS candidate changes no ledger or canonical balance'
);
insert into pg_temp.test_values
select 'direct_payment', jsonb_build_object('id', payment.id)
from public.payments payment
where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211';

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.confirm_provider_payment(
  (select (value->>'id')::uuid from pg_temp.test_values where key = 'direct_payment'),
  'mtn_momo', 'DIRECT1500', 'CONFIRM-DIRECT1500', repeat('a', 64),
  1500, now(), repeat('c', 64)
);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event('97000000-0000-4000-8000-000000000211') = 'already_allocated',
  'provider-confirmed direct allocation retry is idempotent'
);
reset role;

select pg_temp.assert_true(
  (select payment.status = 'posted' from public.payments payment
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211'),
  'independent provider confirmation posts the direct candidate'
);
select pg_temp.assert_true(
  (select count(*) = 2
      and sum(line.amount_rwf) filter (where line.direction = 'debit') = 1500
      and sum(line.amount_rwf) filter (where line.direction = 'credit') = 1500
    from collect_hybrid.momo_journal_lines line
    join collect_hybrid.momo_journal_entries entry on entry.id = line.journal_entry_id
    where entry.payment_id = (
      select payment.id from public.payments payment
      where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211'
    )),
  'canonical RWF receipt journal has one balanced debit and credit'
);
select pg_temp.assert_true(
  (select snapshot.member_balance_after_rwf = 1500
      and snapshot.group_balance_after_rwf = 1500
      and snapshot.delta_rwf = 1500
    from collect_hybrid.momo_balance_snapshots snapshot
    where snapshot.payment_id = (
      select payment.id from public.payments payment
      where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211'
    )),
  'receipt stores immutable member and group after-balances'
);
select pg_temp.assert_true(
  (select count(*) = 2 from public.ledger_entries ledger
    where ledger.payment_id = (
      select payment.id from public.payments payment
      where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211'
    )),
  'legacy read projection remains exactly one group and one member credit'
);

-- The ordinary payer-intent route follows the same provider-finality boundary.
-- It may reserve a review candidate from SMS, but it cannot post money until a
-- replay-safe service gateway records matching independent provider evidence.
insert into public.payment_intents(
  id, collection_id, contributor_user_id, contributor_public_id,
  contribution_code, expected_amount_rwf, receiver_momo_number_hash,
  status, anonymity_choice, expires_at
) select
  '97000000-0000-4000-8000-000000000302',
  (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_two'),
  profile.id, profile.public_id, 'INTENT-FINALITY-001', 1200, repeat('a', 64),
  'pending', 'public_id', now() + interval '1 hour'
from public.profiles profile
where profile.id = '97000000-0000-4000-8000-000000000002';
insert into public.raw_payment_sms(
  id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
) values (
  '97000000-0000-4000-8000-000000000207',
  '97000000-0000-4000-8000-000000000001', 'M-Money',
  'Txn INTENT1200. You have received 1,200 RWF for payer 970002.',
  encode(extensions.digest(
    'Txn INTENT1200. You have received 1,200 RWF for payer 970002.', 'sha256'
  ), 'hex'),
  repeat('a', 64), now(), 'parsed',
  '97000000-0000-4000-8000-000000000807', repeat('b', 64), now()
);
insert into public.parsed_payment_events(
  id, raw_sms_id, receiver_user_id, is_mobile_money_payment, network,
  direction, amount_rwf, currency, transaction_id, receiver_phone_hash,
  detected_user_public_id, confidence, parser_schema_version
) select
  '97000000-0000-4000-8000-000000000217',
  '97000000-0000-4000-8000-000000000207',
  '97000000-0000-4000-8000-000000000001', true, 'mtn_momo',
  'incoming', 1200, 'RWF', 'INTENT1200', repeat('a', 64),
  profile.public_id, 0.99, 'collect.sms_parser.v4'
from public.profiles profile
where profile.id = '97000000-0000-4000-8000-000000000002';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event('97000000-0000-4000-8000-000000000217')
    = 'awaiting_provider_confirmation',
  'payer intent receipt creates only a provider-confirmation candidate'
);
reset role;
select pg_temp.assert_true(
  (select payment.status = 'review' and payment.payment_intent_id =
      '97000000-0000-4000-8000-000000000302'::uuid
    from public.payments payment
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000217')
  and not exists(
    select 1 from public.ledger_entries ledger
    join public.payments payment on payment.id = ledger.payment_id
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000217'
  ),
  'unconfirmed payer intent changes no financial ledger'
);
insert into pg_temp.test_values
select 'intent_payment', jsonb_build_object('id', payment.id)
from public.payments payment
where payment.parsed_event_id = '97000000-0000-4000-8000-000000000217';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
insert into pg_temp.test_values values (
  'intent_finality',
  public.process_provider_finality_event(
    '97000000-0000-4000-8000-000000000501',
    'payment.confirmed', repeat('d', 64),
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'intent_payment'),
    'mtn_momo', 'INTENT1200', 'CONFIRM-INTENT1200', repeat('a', 64),
    1200, now(), repeat('e', 64), null, null
  )
);
select pg_temp.assert_true(
  public.process_provider_finality_event(
    '97000000-0000-4000-8000-000000000501',
    'payment.confirmed', repeat('d', 64),
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'intent_payment'),
    'mtn_momo', 'INTENT1200', 'CONFIRM-INTENT1200', repeat('a', 64),
    1200, now(), repeat('e', 64), null, null
  )->>'replayed' = 'true',
  'provider finality gateway retry is idempotent'
);
reset role;
select pg_temp.assert_true(
  (select payment.status = 'posted' from public.payments payment
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000217')
  and (select count(*) = 2 from public.ledger_entries ledger
    join public.payments payment on payment.id = ledger.payment_id
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000217')
  and (select count(*) = 1 from collect_hybrid.momo_journal_entries entry
    join public.payments payment on payment.id = entry.payment_id
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000217'),
  'independent provider finality posts the payer intent exactly once'
);
select pg_temp.assert_true(
  (select confirmed_rwf = 1200 from collect_hybrid.collection_balances balance
    where balance.collection_id = (select (value->>'collection_id')::uuid
      from pg_temp.test_values where key = 'group_two')),
  'payer intent provider confirmation updates canonical group balance'
);
-- With immediate checking, an entry without its exact two lines is rejected.
set constraints all immediate;
select pg_temp.expect_error(
  format(
    'insert into collect_hybrid.momo_journal_entries(payment_id,parsed_event_id,collection_id,member_record_id,entry_type,amount_rwf,external_reference,reverses_entry_id) select payment.id,payment.parsed_event_id,payment.collection_id,payment.member_record_id,%L,payment.amount_rwf,%L,entry.id from public.payments payment join collect_hybrid.momo_journal_entries entry on entry.payment_id=payment.id and entry.entry_type=%L where payment.parsed_event_id=%L',
    'reversal', 'synthetic-unbalanced', 'receipt',
    '97000000-0000-4000-8000-000000000211'
  ),
  'exactly one balanced debit and credit',
  'unbalanced canonical journal is rejected'
);
set constraints all deferred;

-- No candidate is held for review; it never creates a payment.
insert into public.raw_payment_sms(
  id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
) values (
  '97000000-0000-4000-8000-000000000202',
  '97000000-0000-4000-8000-000000000001', 'M-Money',
  'You have received 700 RWF from UNKNOWN PERSON (***999).',
  encode(extensions.digest('You have received 700 RWF from UNKNOWN PERSON (***999).', 'sha256'), 'hex'),
  repeat('a', 64), now(), 'parsed',
  '97000000-0000-4000-8000-000000000802', repeat('b', 64), now()
);
insert into public.parsed_payment_events(
  id, raw_sms_id, receiver_user_id, is_mobile_money_payment, network,
  direction, amount_rwf, currency, receiver_phone_hash, confidence,
  transaction_id, payer_last3, payer_match_key, parser_schema_version
) values (
  '97000000-0000-4000-8000-000000000212',
  '97000000-0000-4000-8000-000000000202',
  '97000000-0000-4000-8000-000000000001', true, 'mtn_momo',
  'incoming', 700, 'RWF', repeat('a', 64), 0.99, 'UNKNOWN999',
  '999', repeat('f', 64),
  'collect.sms_parser.v4'
);
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event('97000000-0000-4000-8000-000000000212') = 'needs_review',
  'zero direct candidates is a review case'
);
reset role;
select pg_temp.assert_true(
  exists(select 1 from collect_hybrid.momo_reconciliation_exceptions exception
    where exception.parsed_event_id = '97000000-0000-4000-8000-000000000212'
      and exception.code = 'no_candidate' and exception.status = 'open')
  and not exists(select 1 from public.payments payment
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000212'),
  'zero-candidate receipt records an exception and no money'
);

-- Exact payer and route evidence without a provider transaction reference is
-- never sufficient to create a financial candidate.
insert into public.raw_payment_sms(
  id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
) values (
  '97000000-0000-4000-8000-000000000205',
  '97000000-0000-4000-8000-000000000001', 'M-Money',
  'You have received 650 RWF from UNIQUE MEMBER (***456).',
  encode(extensions.digest(
    'You have received 650 RWF from UNIQUE MEMBER (***456).', 'sha256'
  ), 'hex'),
  repeat('a', 64), now(), 'parsed',
  '97000000-0000-4000-8000-000000000805', repeat('b', 64), now()
);
insert into public.parsed_payment_events(
  id, raw_sms_id, receiver_user_id, is_mobile_money_payment, network,
  direction, amount_rwf, currency, receiver_phone_hash, confidence,
  payer_last3, payer_match_key, parser_schema_version
) select
  '97000000-0000-4000-8000-000000000215',
  '97000000-0000-4000-8000-000000000205',
  '97000000-0000-4000-8000-000000000001', true, 'mtn_momo',
  'incoming', 650, 'RWF', repeat('a', 64), 0.99,
  '456', identity.match_key, 'collect.sms_parser.v4'
from collect_hybrid.member_momo_identities identity
where identity.momo_number = '+250788000456';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event('97000000-0000-4000-8000-000000000215') = 'needs_review',
  'missing provider transaction reference can never auto-allocate'
);
reset role;
select pg_temp.assert_true(
  not exists(select 1 from public.payments payment
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000215'),
  'missing provider transaction reference creates no payment candidate'
);
select pg_temp.expect_error(
  $$delete from public.raw_payment_sms
    where id = '97000000-0000-4000-8000-000000000205'$$,
  'Raw SMS evidence is retained',
  'raw SMS evidence cannot be deleted outside a governed migration'
);

-- Same normalized name and last three digits across two assigned records is ambiguous.
insert into public.raw_payment_sms(
  id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
) values (
  '97000000-0000-4000-8000-000000000203',
  '97000000-0000-4000-8000-000000000001', 'M-Money',
  'You have received 800 RWF from DUPLICATE PERSON (***123).',
  encode(extensions.digest('You have received 800 RWF from DUPLICATE PERSON (***123).', 'sha256'), 'hex'),
  repeat('a', 64), now(), 'parsed',
  '97000000-0000-4000-8000-000000000803', repeat('b', 64), now()
);
insert into public.parsed_payment_events(
  id, raw_sms_id, receiver_user_id, is_mobile_money_payment, network,
  direction, amount_rwf, currency, receiver_phone_hash, confidence,
  transaction_id, payer_last3, payer_match_key, parser_schema_version
) select
  '97000000-0000-4000-8000-000000000213',
  '97000000-0000-4000-8000-000000000203',
  '97000000-0000-4000-8000-000000000001', true, 'mtn_momo',
  'incoming', 800, 'RWF', repeat('a', 64), 0.99, 'AMBIG123',
  '123', identity.match_key,
  'collect.sms_parser.v4'
from collect_hybrid.member_momo_identities identity
where identity.momo_number = '+250788000123';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event('97000000-0000-4000-8000-000000000213') = 'ambiguous',
  'multiple exact identity candidates are held for review'
);
reset role;
select pg_temp.assert_true(
  not exists(select 1 from public.payments payment
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000213'),
  'ambiguous direct receipt posts no money'
);

-- An independently valid intent that disagrees with the direct assignment is
-- also held; neither route is preferred by implementation order.
insert into public.payment_intents(
  id, collection_id, contributor_user_id, contributor_public_id,
  contribution_code, expected_amount_rwf, receiver_momo_number_hash,
  status, anonymity_choice, expires_at
) select
  '97000000-0000-4000-8000-000000000301',
  (select (value->>'collection_id')::uuid from pg_temp.test_values where key = 'group_two'),
  profile.id, profile.public_id, 'DIRECT-DISAGREE-001', 900, repeat('a', 64),
  'pending', 'public_id', now() + interval '1 hour'
from public.profiles profile
where profile.id = '97000000-0000-4000-8000-000000000002';
insert into public.raw_payment_sms(
  id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
) values (
  '97000000-0000-4000-8000-000000000204',
  '97000000-0000-4000-8000-000000000001', 'M-Money',
  'Txn DISAGREE. You have received 900 RWF from UNIQUE MEMBER (***456).',
  encode(extensions.digest('Txn DISAGREE. You have received 900 RWF from UNIQUE MEMBER (***456).', 'sha256'), 'hex'),
  repeat('a', 64), now(), 'parsed',
  '97000000-0000-4000-8000-000000000804', repeat('b', 64), now()
);
insert into public.parsed_payment_events(
  id, raw_sms_id, receiver_user_id, is_mobile_money_payment, network,
  direction, amount_rwf, currency, transaction_id, receiver_phone_hash,
  detected_user_public_id, confidence, payer_last3, payer_match_key,
  parser_schema_version
) select
  '97000000-0000-4000-8000-000000000214',
  '97000000-0000-4000-8000-000000000204',
  '97000000-0000-4000-8000-000000000001', true, 'mtn_momo',
  'incoming', 900, 'RWF', 'DISAGREE', repeat('a', 64),
  (select public_id from public.profiles where id = '97000000-0000-4000-8000-000000000002'),
  0.99, '456', identity.match_key, 'collect.sms_parser.v4'
from collect_hybrid.member_momo_identities identity
where identity.momo_number = '+250788000456';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event('97000000-0000-4000-8000-000000000214') = 'ambiguous',
  'intent and direct assignment disagreement is held for review'
);
reset role;
select pg_temp.assert_true(
  exists(select 1 from collect_hybrid.momo_reconciliation_exceptions exception
    where exception.parsed_event_id = '97000000-0000-4000-8000-000000000214'
      and exception.code = 'intent_direct_disagreement' and exception.status = 'open')
  and not exists(select 1 from public.payments payment
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000214'),
  'disagreement records a specific exception and no money'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"97000000-0000-4000-8000-000000000099"}',
  true
);
insert into pg_temp.test_values values (
  'reversal',
  public.admin_reverse_momo_payment(
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'direct_payment'),
    'Reviewed synthetic correction of direct contribution',
    '97000000-0000-4000-8000-000000000401'
  )
);
select pg_temp.assert_true(
  public.admin_reverse_momo_payment(
    (select (value->>'id')::uuid from pg_temp.test_values where key = 'direct_payment'),
    'Reviewed synthetic correction of direct contribution',
    '97000000-0000-4000-8000-000000000401'
  )->>'replay' = 'true',
  'compensating reversal retry is idempotent'
);
reset role;

select pg_temp.assert_true(
  (select payment.status = 'reversed' from public.payments payment
    where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211')
  and (select confirmed_rwf = 0 from collect_hybrid.collection_balances
    where collection_id = (select (value->>'collection_id')::uuid
      from pg_temp.test_values where key = 'group_one'))
  and (select confirmed_rwf = 0 from collect_hybrid.member_balances
    where collection_id = (select (value->>'collection_id')::uuid
      from pg_temp.test_values where key = 'group_one')
      and member_record_id = (select identity.member_id
        from collect_hybrid.member_momo_identities identity
        where identity.momo_number = '+250788000456')),
  'reversal changes status and restores canonical balances to zero'
);
select pg_temp.assert_true(
  (select count(*) = 2 and sum(snapshot.delta_rwf) = 0
    from collect_hybrid.momo_balance_snapshots snapshot
    where snapshot.payment_id = (select payment.id from public.payments payment
      where payment.parsed_event_id = '97000000-0000-4000-8000-000000000211')),
  'receipt and compensating reversal preserve immutable balance history'
);
select pg_temp.assert_true(
  (select count(*) = 4
      and coalesce(sum(ledger.amount_rwf) filter (
        where ledger.entry_type = 'collection_credit'
      ), 0) = 0
      and coalesce(sum(ledger.amount_rwf) filter (
        where ledger.entry_type = 'member_credit'
      ), 0) = 0
    from public.ledger_entries ledger
    where ledger.payment_id = (select (value->>'id')::uuid
      from pg_temp.test_values where key = 'direct_payment')),
  'reversal adds immutable compensating legacy projection rows'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"97000000-0000-4000-8000-000000000099"}',
  true
);
select pg_temp.assert_true(
  exists(
    select 1
    from jsonb_array_elements(public.list_current_member_collection_balances()) row
    cross join lateral jsonb_array_elements(row->'balances') balance
    where row->>'collection_id' = (select value->>'collection_id'
      from pg_temp.test_values where key = 'group_one')
      and balance->>'currency' = 'RWF'
      and (balance->>'amount_raised_minor')::bigint = 0
  ),
  'member balance API reads the zero canonical balance after reversal'
);
select pg_temp.assert_true(
  (select result->>'total' = '3'
      and exists(select 1 from jsonb_array_elements(result->'rows') row
        where row->>'status' = 'balanced')
      and exists(select 1 from jsonb_array_elements(result->'rows') row
        where row->>'status' = 'reversed')
    from (select public.admin_list_collect_ledgers(null, null, 25, 0, 'created_at_desc') result) readback),
  'Admin ledger exposes both canonical receipt and compensating reversal'
);
reset role;

-- A compensating reversal does not make its provider transaction reusable.
insert into public.raw_payment_sms(
  id, receiver_user_id, raw_sender, raw_body, body_hash,
  receiver_momo_number_hash, received_at_device, parse_status,
  native_action_capability_id, attestation_request_hash, device_attested_at
) values (
  '97000000-0000-4000-8000-000000000206',
  '97000000-0000-4000-8000-000000000001', 'M-Money',
  'Duplicate Txn DIRECT1500. Received 1,500 RWF from UNIQUE MEMBER (***456).',
  encode(extensions.digest(
    'Duplicate Txn DIRECT1500. Received 1,500 RWF from UNIQUE MEMBER (***456).',
    'sha256'
  ), 'hex'),
  repeat('a', 64), now(), 'parsed',
  '97000000-0000-4000-8000-000000000806', repeat('b', 64), now()
);
insert into public.parsed_payment_events(
  id, raw_sms_id, receiver_user_id, is_mobile_money_payment, network,
  direction, amount_rwf, currency, transaction_id, receiver_phone_hash,
  confidence, payer_last3, payer_match_key, parser_schema_version
) select
  '97000000-0000-4000-8000-000000000216',
  '97000000-0000-4000-8000-000000000206',
  '97000000-0000-4000-8000-000000000001', true, 'mtn_momo',
  'incoming', 1500, 'RWF', 'DIRECT1500', repeat('a', 64),
  0.99, '456', identity.match_key, 'collect.sms_parser.v4'
from collect_hybrid.member_momo_identities identity
where identity.momo_number = '+250788000456';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event('97000000-0000-4000-8000-000000000216') = 'ignored',
  'reversed provider transaction replay is ignored'
);
reset role;
select pg_temp.assert_true(
  (select count(*) = 1 from public.payments payment
    where payment.provider_network = 'mtn_momo'
      and upper(btrim(payment.transaction_id)) = 'DIRECT1500')
  and (select allocation_status = 'ignored'
    from public.parsed_payment_events event
    where event.id = '97000000-0000-4000-8000-000000000216'),
  'reversed transaction replay creates no second payment'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'collect_hybrid.member_receiving_assignments', 'SELECT')
  and not has_table_privilege('authenticated', 'collect_hybrid.momo_journal_entries', 'SELECT')
  and not has_table_privilege('service_role', 'collect_hybrid.member_momo_identities', 'SELECT'),
  'PII and canonical financial tables have no direct browser or service-role access'
);

select 'PASS ' || label from pg_temp.test_results order by label;
select 'HYBRID_DIRECT_USSD_FINANCIAL_CORE_UAT_PASS: ' || count(*)
  || ' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
