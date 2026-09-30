\set ON_ERROR_STOP on
-- Rollback-only content binding UAT. Run only after the caller verifies the
-- task-owned collect_fin_concurrency_qa_20260929 container labels and port.
-- Start with the synthetic RACE2500 review candidate produced by the seed and
-- allocation race. No real provider, customer or hosted project is involved.
begin;
set local statement_timeout = '30s';

do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations) not in (136, 137, 138)
     or not exists (select 1 from supabase_migrations.schema_migrations
       where version = '20260929130000')
     or (select count(*) from auth.users) <> 2
     or not exists (select 1 from auth.users
       where id = '99600000-0000-4000-8000-000000000001'
         and phone = '250788006123')
     or (select count(*) from public.payments) <> 1
     or (select count(*) from public.payments
       where transaction_id = 'RACE2500' and amount_rwf = 2500
         and status = 'review') <> 1
     or (select count(*) from public.provider_finality_requests) <> 0
     or (select count(*) from public.payment_provider_confirmations) <> 0
     or (select count(*) from collect_hybrid.payment_provider_rejections) <> 0
     or (select count(*) from public.ledger_entries) <> 0
     or (select count(*) from collect_hybrid.momo_journal_entries) <> 0
     or (select count(*) from collect_hybrid.momo_reversal_requests) <> 0 then
    raise exception 'Exact review-only finality content fixture required';
  end if;
end $$;

create temporary table finality_content_cases (
  name text primary key, body jsonb not null
) on commit drop;
do $$ begin
  execute format('grant usage on schema %I to service_role, anon, authenticated',
    pg_my_temp_schema()::regnamespace::text);
end $$;
insert into finality_content_cases(name, body)
select 'confirmed', jsonb_build_object(
  'request_id', '99600000-0000-4000-8000-000000000701',
  'event_type', 'payment.confirmed', 'payload_sha256', repeat('a', 64),
  'payment_id', id, 'provider_network', 'mtn_momo',
  'transaction_id', 'RACE2500', 'provider_confirmation_id', 'CONTENT-CONFIRM',
  'receiver_hash', receiver_momo_number_hash, 'amount_rwf', 2500,
  'occurred_at', '2026-09-28T12:00:00Z', 'evidence_sha256', repeat('b', 64),
  'rejection_reason', null, 'provider_reference', null
) from public.payments where transaction_id = 'RACE2500';
insert into finality_content_cases(name, body)
select 'rejected', body || jsonb_build_object(
  'request_id', '99600000-0000-4000-8000-000000000702',
  'event_type', 'payment.rejected', 'provider_confirmation_id', null,
  'rejection_reason', 'Synthetic provider rejected candidate',
  'provider_reference', 'CONTENT-REJECT'
) from finality_content_cases where name = 'confirmed';
grant select on finality_content_cases to service_role;

-- Include full rows (including processed request counts, timestamps and audit)
-- so a rejected call cannot silently mutate evidence even if totals match.
create function pg_temp.finality_snapshot()
returns jsonb language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare
  source_name text;
  source_rows jsonb;
  snapshot jsonb := '{}'::jsonb;
begin
  foreach source_name in array array[
    'public.payments', 'public.payment_intents', 'public.parsed_payment_events',
    'public.provider_finality_requests', 'public.payment_provider_confirmations',
    'collect_hybrid.payment_provider_rejections', 'public.ledger_entries',
    'collect_hybrid.momo_journal_entries', 'collect_hybrid.momo_journal_lines',
    'collect_hybrid.momo_balance_snapshots', 'collect_hybrid.collection_balances',
    'collect_hybrid.member_balances', 'collect_hybrid.momo_reversal_requests',
    'collect_hybrid.momo_reconciliation_exceptions', 'public.audit_logs'
  ] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text), ''[]''::jsonb) from %s t',
      source_name::regclass) into source_rows;
    snapshot := snapshot || jsonb_build_object(source_name, source_rows);
  end loop;
  return snapshot;
end $$;
revoke all on function pg_temp.finality_snapshot() from public;
grant execute on function pg_temp.finality_snapshot() to service_role, anon, authenticated;

create function pg_temp.invoke_finality(kind text, body jsonb)
returns jsonb language plpgsql set search_path = '' as $$
begin
  if kind = 'gateway' then
    return public.process_provider_finality_event(
      (body->>'request_id')::uuid, body->>'event_type', body->>'payload_sha256',
      (body->>'payment_id')::uuid, body->>'provider_network', body->>'transaction_id',
      body->>'provider_confirmation_id', body->>'receiver_hash',
      (body->>'amount_rwf')::bigint, (body->>'occurred_at')::timestamptz,
      body->>'evidence_sha256', body->>'rejection_reason', body->>'provider_reference'
    );
  elsif kind = 'confirm' then
    return to_jsonb(public.confirm_provider_payment(
      (body->>'payment_id')::uuid, body->>'provider_network', body->>'transaction_id',
      body->>'provider_confirmation_id', body->>'receiver_hash',
      (body->>'amount_rwf')::bigint, (body->>'occurred_at')::timestamptz,
      body->>'evidence_sha256'
    ));
  elsif kind = 'legacy_reject' then
    return to_jsonb(public.reject_provider_payment(
      (body->>'payment_id')::uuid, body->>'rejection_reason', body->>'provider_reference'
    ));
  end if;
  raise exception 'Unknown test invocation kind';
end $$;
revoke all on function pg_temp.invoke_finality(text,jsonb) from public;
grant execute on function pg_temp.invoke_finality(text,jsonb) to service_role, anon, authenticated;

create function pg_temp.expect_finality_rejected(kind text, body jsonb, label text)
returns void language plpgsql set search_path = '' as $$
declare
  before_state jsonb := pg_temp.finality_snapshot();
  rejected boolean := false;
begin
  begin
    perform pg_temp.invoke_finality(kind, body);
  exception when raise_exception or insufficient_privilege then
    rejected := true;
  end;
  if not rejected then raise exception '% unexpectedly succeeded', label; end if;
  if pg_temp.finality_snapshot() is distinct from before_state then
    raise exception '% changed financial/evidence rows', label;
  end if;
  raise notice 'PASS: % (rejected, complete snapshot unchanged)', label;
end $$;
revoke all on function pg_temp.expect_finality_rejected(text,jsonb,text) from public;
grant execute on function pg_temp.expect_finality_rejected(text,jsonb,text) to service_role, anon, authenticated;

-- ACL checks cover the gateway and both public helpers, independently of JWT
-- claim checking. Actual calls below verify denied roles cannot bypass them.
do $$
declare role_name text;
begin
  foreach role_name in array array['anon', 'authenticated'] loop
    if has_function_privilege(role_name,
        'public.process_provider_finality_event(uuid,text,text,uuid,text,text,text,text,bigint,timestamptz,text,text,text)', 'EXECUTE')
       or has_function_privilege(role_name,
        'public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamptz,text)', 'EXECUTE')
       or has_function_privilege(role_name,
        'public.reject_provider_payment(uuid,text,text)', 'EXECUTE') then
      raise exception '% can execute a financial finality helper', role_name;
    end if;
  end loop;
  if has_function_privilege('service_role',
       'public.reject_provider_payment(uuid,text,text)', 'EXECUTE') then
    raise exception 'Legacy rejection helper still executable by service role';
  end if;
  foreach role_name in array array['anon', 'authenticated', 'service_role'] loop
    if has_function_privilege(role_name,
        'collect_hybrid.reject_bound_provider_payment(uuid,text,text,text,bigint,timestamptz,text,text,text)', 'EXECUTE')
       or has_table_privilege(role_name,
        'collect_hybrid.payment_provider_rejections', 'INSERT,UPDATE,DELETE') then
      raise exception '% can bypass the gateway rejection contract', role_name;
    end if;
  end loop;
  raise notice 'PASS: finality ACL boundaries';
end $$;

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.expect_finality_rejected('gateway', '{}'::jsonb, 'anonymous gateway');
select pg_temp.expect_finality_rejected('confirm', '{}'::jsonb, 'anonymous direct confirmation');
select pg_temp.expect_finality_rejected('legacy_reject', '{}'::jsonb, 'anonymous legacy rejection');
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"role":"authenticated","sub":"99600000-0000-4000-8000-000000000001"}', true);
select pg_temp.expect_finality_rejected('gateway', '{}'::jsonb, 'member gateway');
select pg_temp.expect_finality_rejected('confirm', '{}'::jsonb, 'member direct confirmation');
select pg_temp.expect_finality_rejected('legacy_reject', '{}'::jsonb, 'member legacy rejection');
reset role;

-- Even an owner executing the old signature with service claims cannot use
-- the insufficient three-field API to bypass the new rejection contract.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.expect_finality_rejected('legacy_reject', body, 'owner legacy rejection fail closed')
from finality_content_cases where name = 'rejected';

savepoint confirmation_cases;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare
  base jsonb;
  normalized jsonb;
  patch jsonb;
  item record;
  response jsonb;
  before_state jsonb;
begin
  select body into base from pg_temp.finality_content_cases where name = 'confirmed';
  for item in select * from (values
    ('occurred_at', to_jsonb('-infinity'::text)),
    ('occurred_at', to_jsonb('infinity'::text)),
    ('occurred_at', 'null'::jsonb),
    ('amount_rwf', 'null'::jsonb),
    ('receiver_hash', 'null'::jsonb)
  ) changes(field, value) loop
    perform pg_temp.expect_finality_rejected('gateway', base || jsonb_build_object(item.field, item.value),
      'initial confirmation invalid ' || item.field || '=' || item.value::text);
  end loop;
  response := pg_temp.invoke_finality('gateway', base);
  if response->>'replayed' <> 'false' or response->>'payment_id' <> base->>'payment_id' then
    raise exception 'Valid initial confirmation did not post';
  end if;
  before_state := pg_temp.finality_snapshot();
  response := pg_temp.invoke_finality('gateway', base);
  if response->>'replayed' <> 'true' or pg_temp.finality_snapshot() is distinct from before_state then
    raise exception 'Exact confirmation request retry mutated evidence';
  end if;
  normalized := base || jsonb_build_object(
    'provider_network', ' MTN_MOMO ', 'transaction_id', ' race2500 ',
    'provider_confirmation_id', ' content-confirm ',
    'receiver_hash', ' ' || upper(base->>'receiver_hash') || ' ',
    'evidence_sha256', ' ' || upper(base->>'evidence_sha256') || ' ',
    'occurred_at', '2026-09-28T14:00:00+02:00'
  );
  perform set_config('TimeZone', 'Pacific/Honolulu', true);
  response := pg_temp.invoke_finality('gateway', normalized);
  if response->>'replayed' <> 'true' or pg_temp.finality_snapshot() is distinct from before_state then
    raise exception 'Normalized confirmation retry was not read-only';
  end if;
  if pg_temp.invoke_finality('confirm', normalized) <> to_jsonb(base->>'payment_id')
     or pg_temp.finality_snapshot() is distinct from before_state then
    raise exception 'Exact normalized direct confirmation retry was not read-only';
  end if;
  perform set_config('TimeZone', 'UTC', true);
  raise notice 'PASS: exact, normalized and cross-timezone confirmation retries (gateway and direct helper)';

  for item in select * from (values
    ('provider_network', to_jsonb('airtel_money'::text)),
    ('transaction_id', to_jsonb('OTHER2500'::text)),
    ('provider_confirmation_id', to_jsonb('CONTENT-OTHER'::text)),
    ('receiver_hash', to_jsonb(repeat('0', 64))),
    ('amount_rwf', to_jsonb(2501)),
    ('occurred_at', to_jsonb('2026-09-28T12:00:01Z'::text)),
    ('evidence_sha256', to_jsonb(repeat('c', 64)))
  ) changes(field, value) loop
    patch := jsonb_build_object(item.field, item.value);
    perform pg_temp.expect_finality_rejected('gateway', base || patch,
      'same confirmation request + unchanged supplied digest / changed ' || item.field);
    perform pg_temp.expect_finality_rejected('gateway', base || patch || jsonb_build_object(
      'request_id', '99600000-0000-4000-8000-000000000703'),
      'new request with changed confirmation ' || item.field);
    perform pg_temp.expect_finality_rejected('confirm', base || patch,
      'direct helper changed confirmation ' || item.field);
  end loop;
  for item in select * from (values
    ('event_type', to_jsonb('payment.rejected'::text)),
    ('payment_id', to_jsonb('99600000-0000-4000-8000-000000000799'::text)),
    ('payload_sha256', to_jsonb(repeat('d', 64))),
    ('rejection_reason', to_jsonb('Unused but changed reason'::text)),
    ('provider_reference', to_jsonb('UNUSED-BUT-CHANGED'::text))
  ) changes(field, value) loop
    perform pg_temp.expect_finality_rejected('gateway', base || jsonb_build_object(item.field, item.value),
      'same confirmation request / changed ' || item.field);
  end loop;
  -- A fresh delivery ID for the exact same confirmation can be recorded once;
  -- financial rows still represent one receipt, never a second credit.
  response := pg_temp.invoke_finality('gateway', base || jsonb_build_object(
    'request_id', '99600000-0000-4000-8000-000000000704'));
  if response->>'replayed' <> 'false' then raise exception 'Fresh duplicate delivery not recorded'; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.provider_finality_requests where status = 'processed') <> 2
     or (select count(*) from public.payment_provider_confirmations) <> 1
     or (select count(*) from public.ledger_entries) <> 2
     or (select count(*) from collect_hybrid.momo_journal_entries where entry_type = 'receipt') <> 1
     or (select confirmed_rwf from collect_hybrid.collection_balances limit 1) is distinct from 2500 then
    raise exception 'Confirmation retries changed credit or left processing rows';
  end if;
  raise notice 'PASS: duplicate deliveries retain one confirmation and one RWF 2500 receipt';
end $$;

-- Simulate a retained pre-migration row without fabricating an input binding.
-- The new gateway must not treat the old caller-supplied digest as sufficient.
update public.provider_finality_requests set input_sha256 = null
where request_id = '99600000-0000-4000-8000-000000000701';
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.expect_finality_rejected('gateway', body,
  'legacy null input hash requires reconciliation without rewriting evidence')
from finality_content_cases where name = 'confirmed';
reset role;
rollback to savepoint confirmation_cases;

savepoint absent_evidence;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare base jsonb; response jsonb; before_state jsonb;
begin
  select body || jsonb_build_object('evidence_sha256', null) into base
  from pg_temp.finality_content_cases where name = 'confirmed';
  response := pg_temp.invoke_finality('gateway', base);
  if response->>'replayed' <> 'false' then raise exception 'Optional absent evidence was not accepted'; end if;
  before_state := pg_temp.finality_snapshot();
  response := pg_temp.invoke_finality('gateway', base || jsonb_build_object('evidence_sha256', '  '));
  if response->>'replayed' <> 'true' or pg_temp.finality_snapshot() is distinct from before_state then
    raise exception 'Blank evidence did not normalize to absent evidence on retry';
  end if;
  if pg_temp.invoke_finality('confirm', base || jsonb_build_object('evidence_sha256', ''))
       <> to_jsonb(base->>'payment_id')
     or pg_temp.finality_snapshot() is distinct from before_state then
    raise exception 'Direct confirmation absent evidence retry mutated financial rows';
  end if;
  raise notice 'PASS: optional evidence null/blank normalization remains read-only on retry';
end $$;
reset role;
rollback to savepoint absent_evidence;

savepoint rejection_cases;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare base jsonb; item record; response jsonb; before_state jsonb;
begin
  select body into base from pg_temp.finality_content_cases where name = 'rejected';
  -- Before the first rejection, candidate identity must be checked rather
  -- than trusting payment UUID alone. No failed request may persist.
  for item in select * from (values
    ('provider_network', to_jsonb('airtel_money'::text)),
    ('transaction_id', to_jsonb('OTHER2500'::text)),
    ('receiver_hash', to_jsonb(repeat('0', 64))),
    ('amount_rwf', to_jsonb(2501)),
    ('provider_network', 'null'::jsonb), ('transaction_id', 'null'::jsonb),
    ('receiver_hash', 'null'::jsonb), ('amount_rwf', 'null'::jsonb),
    ('occurred_at', 'null'::jsonb), ('occurred_at', to_jsonb('-infinity'::text)),
    ('occurred_at', to_jsonb('infinity'::text)), ('rejection_reason', 'null'::jsonb),
    ('provider_reference', 'null'::jsonb)
  ) changes(field, value) loop
    perform pg_temp.expect_finality_rejected('gateway', base || jsonb_build_object(item.field, item.value),
      'initial rejection invalid candidate ' || item.field || '=' || item.value::text);
  end loop;
  response := pg_temp.invoke_finality('gateway', base);
  if response->>'replayed' <> 'false' then raise exception 'Valid initial rejection not recorded'; end if;
  before_state := pg_temp.finality_snapshot();
  response := pg_temp.invoke_finality('gateway', base || jsonb_build_object(
    'provider_network', ' MTN_MOMO ', 'transaction_id', ' race2500 ',
    'receiver_hash', ' ' || upper(base->>'receiver_hash') || ' ',
    'evidence_sha256', ' ' || upper(base->>'evidence_sha256') || ' ',
    'occurred_at', '2026-09-28T14:00:00+02:00',
    'rejection_reason', ' Synthetic provider rejected candidate ',
    'provider_reference', ' CONTENT-REJECT '
  ));
  if response->>'replayed' <> 'true' or pg_temp.finality_snapshot() is distinct from before_state then
    raise exception 'Normalized rejection retry mutated evidence';
  end if;
  raise notice 'PASS: exact normalized rejection retry is read-only';
  for item in select * from (values
    ('provider_network', to_jsonb('airtel_money'::text)),
    ('transaction_id', to_jsonb('OTHER2500'::text)),
    ('receiver_hash', to_jsonb(repeat('0', 64))),
    ('amount_rwf', to_jsonb(2501)),
    ('occurred_at', to_jsonb('2026-09-28T12:00:01Z'::text)),
    ('evidence_sha256', to_jsonb(repeat('c', 64))),
    ('rejection_reason', to_jsonb('Different provider rejection reason'::text)),
    ('provider_reference', to_jsonb('DIFFERENT-REJECTION-REF'::text))
  ) changes(field, value) loop
    perform pg_temp.expect_finality_rejected('gateway', base || jsonb_build_object(item.field, item.value),
      'same rejection request + unchanged supplied digest / changed ' || item.field);
    perform pg_temp.expect_finality_rejected('gateway', base || jsonb_build_object(item.field, item.value,
      'request_id', '99600000-0000-4000-8000-000000000705'),
      'new request with changed immutable rejection ' || item.field);
  end loop;
  perform pg_temp.expect_finality_rejected('gateway', base || jsonb_build_object(
    'provider_confirmation_id', 'UNUSED-BUT-CHANGED'), 'same rejection request changed unused confirmation ID');
  perform pg_temp.expect_finality_rejected('legacy_reject', base, 'service legacy rejection unavailable');
  response := pg_temp.invoke_finality('gateway', base || jsonb_build_object(
    'request_id', '99600000-0000-4000-8000-000000000706'));
  if response->>'replayed' <> 'false' then raise exception 'Fresh exact rejection delivery not recorded'; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.payments where status = 'reversed' and posted_at is null) <> 1
     or (select count(*) from public.provider_finality_requests where status = 'processed') <> 2
     or (select count(*) from collect_hybrid.payment_provider_rejections) <> 1
     or (select count(*) from public.payment_provider_confirmations) <> 0
     or (select count(*) from public.ledger_entries) <> 0
     or (select count(*) from collect_hybrid.momo_journal_entries) <> 0
     or coalesce((select confirmed_rwf from collect_hybrid.collection_balances limit 1), 0) <> 0 then
    raise exception 'Rejection retries created credit or duplicate rejection evidence';
  end if;
  raise notice 'PASS: duplicate rejection deliveries retain one rejection and zero credit';
end $$;
rollback to savepoint rejection_cases;

-- Use the real Admin reversal function, not a status UPDATE, to prove that
-- an already compensated receipt cannot masquerade as a provider rejection.
savepoint compensated_receipt;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.invoke_finality('gateway', body)
from finality_content_cases where name = 'confirmed';
reset role;
update public.profiles set country_code = 'RW', currency_code = 'RWF',
  momo_provider = 'mtn_momo', momo_number = '0788991001',
  momo_number_hash = encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
  is_platform_admin = true
where id = '99100000-0000-4000-8000-000000000001';
insert into auth.sessions(id, user_id, created_at, updated_at, not_after)
values ('99600000-0000-4000-8000-000000000907',
  '99100000-0000-4000-8000-000000000001', now() - interval '1 second', now(), now() + interval '1 hour');
insert into collect_admin_access.whatsapp_approvals(user_id, phone_e164, approved_at, approved_by, reason)
values ('99100000-0000-4000-8000-000000000001', '+250788991001', now() - interval '2 seconds',
  '99100000-0000-4000-8000-000000000001', 'Synthetic finality content UAT approval');
grant select on finality_content_cases to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000001","role":"authenticated","session_id":"99600000-0000-4000-8000-000000000907"}', true);
select public.admin_reverse_momo_payment((body->>'payment_id')::uuid,
  'Synthetic provider dispute confirmed by operator', '99600000-0000-4000-8000-000000000707')
from finality_content_cases where name = 'confirmed';
reset role;
do $$ begin
  if (select count(*) from collect_hybrid.momo_journal_entries where entry_type = 'reversal') <> 1
     or (select count(*) from public.payment_provider_confirmations) <> 1
     or (select count(*) from collect_hybrid.payment_provider_rejections) <> 0
     or (select confirmed_rwf from collect_hybrid.collection_balances limit 1) is distinct from 0 then
    raise exception 'Admin compensation fixture was not established';
  end if;
end $$;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.expect_finality_rejected('gateway', body, 'provider rejection after Admin compensation')
from finality_content_cases where name = 'rejected';
select pg_temp.expect_finality_rejected('legacy_reject', body, 'legacy rejection after Admin compensation')
from finality_content_cases where name = 'rejected';
reset role;
rollback to savepoint compensated_receipt;

select 'FINANCIAL_FINALITY_CONTENT_UAT_PASS';
rollback;
