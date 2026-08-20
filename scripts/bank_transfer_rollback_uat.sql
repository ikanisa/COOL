begin;

do $$
declare
  owner_id uuid := gen_random_uuid();
  contributor_id uuid := gen_random_uuid();
  maker_id uuid := gen_random_uuid();
  checker_id uuid := gen_random_uuid();
  group_id uuid;
  destination_request_id uuid;
  intent_id uuid;
  intent_reference text;
  raw_evidence_id uuid;
  evidence_event_id uuid;
  transaction_id uuid;
  first_ingest jsonb;
  replay_ingest jsonb;
  reveal_result jsonb;
  statement_hash text;
  journal_debits bigint;
  journal_credits bigint;
  failure_message text;
begin
  insert into auth.users (
    id, aud, role, phone, phone_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values
    (owner_id, 'authenticated', 'authenticated', '+250780100001', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (contributor_id, 'authenticated', 'authenticated', '+250780100002', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (maker_id, 'authenticated', 'authenticated', '+250780100003', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (checker_id, 'authenticated', 'authenticated', '+250780100004', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

  insert into public.admin_user_roles (user_id, role_id, granted_by, reason)
  select user_id, role.id, maker_id, 'Bank transfer rollback UAT'
  from unnest(array[maker_id, checker_id]) user_id
  cross join public.admin_roles role
  where role.name = 'platform_owner';

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', maker_id, 'role', 'authenticated')::text,
    true
  );
  destination_request_id := (
    public.admin_propose_bank_destination(
      'Collect Test Beneficiary',
      'DE89370400440532013000',
      'COBADEFFXXX',
      'Collect Test Bank',
      true,
      'Rollback UAT beneficiary proposal'
    ) ->> 'id'
  )::uuid;

  begin
    perform public.admin_review_bank_destination_change(
      destination_request_id,
      true,
      'Maker must not approve own proposal'
    );
    raise exception 'Maker-checker destination self-approval unexpectedly passed';
  exception when others then
    get stacked diagnostics failure_message = message_text;
    if failure_message not like 'Maker-checker control prohibits approving your own%' then
      raise;
    end if;
  end;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', checker_id, 'role', 'authenticated')::text,
    true
  );
  perform public.admin_review_bank_destination_change(
    destination_request_id,
    true,
    'Independent rollback UAT approval'
  );
  if not exists (
    select 1 from public.bank_transfer_destinations
    where status = 'active' and not is_placeholder and currency = 'EUR'
  ) or not exists (
    select 1 from public.feature_flags
    where key = 'bank_transfer_v1' and enabled
  ) then
    raise exception 'Approved destination did not activate the bank transfer rail';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', owner_id, 'role', 'authenticated')::text,
    true
  );
  group_id := public.create_bank_transfer_group(
    'Bank transfer rollback UAT',
    'Rollback-only full financial lifecycle',
    'other',
    null,
    null,
    false,
    null,
    '#087A55'
  );
  insert into public.collection_members (collection_id, user_id, role, status)
  values (group_id, contributor_id, 'member', 'active');

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', contributor_id, 'role', 'authenticated')::text,
    true
  );
  select
    (created ->> 'id')::uuid,
    created ->> 'transfer_reference'
  into intent_id, intent_reference
  from (
    select public.create_bank_transfer_intent(group_id, 12345) created
  ) value;
  if intent_reference !~ '^COL-[A-Z0-9]{10}$' then
    raise exception 'Transfer reference is invalid: %', intent_reference;
  end if;
  perform public.mark_bank_transfer_handoff_opened(intent_id);

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', maker_id, 'role', 'service_role')::text,
    true
  );
  first_ingest := public.ingest_bank_evidence(
    'sms',
    'bank-uat-sms-001',
    'COLLECT TEST BANK',
    'Incoming transfer received EUR 123.45 reference ' || intent_reference || ' transaction BANK-UAT-001 completed',
    now(),
    'incoming',
    12345,
    'EUR',
    'BANK-UAT-001',
    'E2E-UAT-001',
    intent_reference,
    'Rollback Payer',
    '1234',
    now(),
    1,
    'collect.bank_rules.v1',
    jsonb_build_object('signals', array['incoming', 'amount_eur', 'collect_reference', 'bank_identifier', 'success']),
    '{}'::jsonb
  );
  replay_ingest := public.ingest_bank_evidence(
    'sms',
    'bank-uat-sms-001',
    'COLLECT TEST BANK',
    'Incoming transfer received EUR 123.45 reference ' || intent_reference || ' transaction BANK-UAT-001 completed',
    now(),
    'incoming',
    12345,
    'EUR',
    'BANK-UAT-001',
    'E2E-UAT-001',
    intent_reference,
    'Rollback Payer',
    '1234',
    now(),
    1,
    'collect.bank.rules.v1',
    '{}'::jsonb,
    '{}'::jsonb
  );
  if first_ingest ->> 'event_id' is distinct from replay_ingest ->> 'event_id'
     or first_ingest ->> 'bank_transaction_id' is distinct from replay_ingest ->> 'bank_transaction_id' then
    raise exception 'Evidence replay was not idempotent';
  end if;
  evidence_event_id := (first_ingest ->> 'event_id')::uuid;
  raw_evidence_id := (first_ingest ->> 'evidence_id')::uuid;
  transaction_id := (first_ingest ->> 'bank_transaction_id')::uuid;
  if (select status from public.bank_transfer_intents where id = intent_id) <> 'received_unreconciled' then
    raise exception 'Notification evidence incorrectly skipped received_unreconciled state';
  end if;
  if (select status from public.bank_transactions where id = transaction_id) <> 'received' then
    raise exception 'Notification evidence incorrectly created a reconciled transaction';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', checker_id, 'role', 'authenticated')::text,
    true
  );
  reveal_result := public.admin_reveal_raw_bank_evidence(
    evidence_event_id,
    'Rollback UAT audited evidence access'
  );
  if reveal_result ->> 'body' is null then
    raise exception 'Audited raw evidence reveal returned no content';
  end if;
  if not exists (
    select 1 from public.admin_sensitive_access_logs
    where actor_user_id = checker_id
      and entity_id = raw_evidence_id
  ) then
    raise exception 'Raw evidence reveal was not recorded in the sensitive access log';
  end if;

  statement_hash := encode(
    extensions.digest('bank-transfer-rollback-uat-statement', 'sha256'),
    'hex'
  );
  perform public.admin_import_bank_statement(
    'bank-transfer-rollback-uat.csv',
    statement_hash,
    current_date,
    current_date,
    jsonb_build_array(jsonb_build_object(
      'bank_transaction_id', 'BANK-UAT-001',
      'end_to_end_id', 'E2E-UAT-001',
      'transfer_reference', intent_reference,
      'payer_name', 'Rollback Payer',
      'amount_minor', 12345,
      'currency', 'EUR',
      'booked_at', now(),
      'value_date', current_date
    )),
    'Rollback UAT daily statement reconciliation'
  );

  if (select status from public.bank_transfer_intents where id = intent_id) <> 'reconciled'
     or (select status from public.bank_transactions where id = transaction_id) <> 'reconciled' then
    raise exception 'Statement confirmation did not reconcile intent and transaction';
  end if;
  select
    coalesce(sum(amount_minor) filter (where direction = 'debit'), 0),
    coalesce(sum(amount_minor) filter (where direction = 'credit'), 0)
  into journal_debits, journal_credits
  from public.journal_lines line
  join public.journal_entries entry on entry.id = line.journal_entry_id
  where entry.bank_transaction_id = transaction_id;
  if journal_debits <> 12345 or journal_credits <> 12345 then
    raise exception 'Journal is not balanced: debit %, credit %', journal_debits, journal_credits;
  end if;
  if (select count(*) from public.notification_events where bank_transfer_intent_id = intent_id and type = 'contribution_confirmed') <> 1 then
    raise exception 'Reconciliation did not emit exactly one contribution confirmation';
  end if;
  if not exists (
    select 1 from public.daily_bank_closes
    where close_date = current_date
      and currency = 'EUR'
      and status = 'balanced'
      and variance_minor = 0
  ) then
    raise exception 'Daily bank close is not balanced';
  end if;
  if (select count(*) from public.raw_payment_evidence where source_uid = 'bank-uat-sms-001') <> 1
     or (select count(*) from public.bank_transactions where id = transaction_id) <> 1
     or (select count(*) from public.journal_entries where bank_transaction_id = transaction_id and entry_type = 'bank_receipt') <> 1 then
    raise exception 'Exact-once evidence, transaction, or journal invariant failed';
  end if;
  if to_regclass('public.stripe_customers') is not null
     or to_regclass('public.stripe_payment_methods') is not null
     or to_regclass('public.stripe_webhook_events') is not null then
    raise exception 'Stripe persistence still exists after bank-only cutover';
  end if;

  raise notice 'BANK_TRANSFER_ROLLBACK_UAT_PASS group=% intent=% transaction=%',
    group_id, intent_id, transaction_id;
end;
$$;

rollback;
