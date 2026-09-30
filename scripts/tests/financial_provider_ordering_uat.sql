\set ON_ERROR_STOP on
-- Rollback-only ordering cases on a 136–138-migration review candidate. Both
-- gateway calls use service-role claims; no independent provider is involved.
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
     or (select count(*) from public.payments
         where transaction_id = 'RACE2500' and status = 'review') <> 1
     or (select count(*) from public.provider_finality_requests) <> 0
     or (select count(*) from public.payment_provider_confirmations) <> 0
     or (select count(*) from public.ledger_entries) <> 0
     or (select count(*) from collect_hybrid.momo_journal_entries) <> 0 then
    raise exception 'Exact review-only provider ordering fixture required';
  end if;
end $$;

savepoint confirmation_first;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare
  payment_id uuid;
  receiver_hash text;
  result jsonb;
begin
  select id, receiver_momo_number_hash into payment_id, receiver_hash
  from public.payments where transaction_id = 'RACE2500';
  result := public.process_provider_finality_event(
    '99600000-0000-4000-8000-000000000521',
    'payment.confirmed', repeat('a', 64), payment_id,
    'mtn_momo', 'RACE2500', 'ORDERING-CONFIRMED', receiver_hash,
    2500, now(), repeat('b', 64), null, null
  );
  if result->>'replayed' <> 'false' then
    raise exception 'Initial provider confirmation did not post freshly';
  end if;
  begin
    perform public.process_provider_finality_event(
      '99600000-0000-4000-8000-000000000522',
      'payment.rejected', repeat('c', 64), payment_id,
      'mtn_momo', 'RACE2500', null, receiver_hash,
      2500, now(), null, 'Synthetic late rejection', 'REJECT-AFTER-CONFIRM'
    );
    raise exception 'Late provider rejection unexpectedly succeeded';
  exception when others then
    if sqlerrm <> 'Only a review payment can be rejected' then raise; end if;
  end;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.payments
      where transaction_id = 'RACE2500' and status = 'posted') <> 1
     or (select count(*) from public.provider_finality_requests
         where status = 'processed') <> 1
     or (select count(*) from public.payment_provider_confirmations) <> 1
     or (select count(*) from public.ledger_entries where amount_rwf = 2500) <> 2
     or (select count(*) from collect_hybrid.momo_journal_entries
         where entry_type = 'receipt') <> 1
     or (select confirmed_rwf from collect_hybrid.collection_balances limit 1)
       is distinct from 2500 then
    raise exception 'Late rejection changed confirmed financial state';
  end if;
end $$;
select 'CONFIRM_THEN_REJECT_PASS';
rollback to savepoint confirmation_first;

do $$ begin
  if (select count(*) from public.payments
      where transaction_id = 'RACE2500' and status = 'review') <> 1
     or (select count(*) from public.provider_finality_requests) <> 0
     or (select count(*) from public.payment_provider_confirmations) <> 0
     or (select count(*) from public.ledger_entries) <> 0
     or (select count(*) from collect_hybrid.momo_journal_entries) <> 0 then
    raise exception 'First ordering case did not roll back to review candidate';
  end if;
end $$;

savepoint rejection_first;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare
  payment_id uuid;
  receiver_hash text;
  result jsonb;
begin
  select id, receiver_momo_number_hash into payment_id, receiver_hash
  from public.payments where transaction_id = 'RACE2500';
  result := public.process_provider_finality_event(
    '99600000-0000-4000-8000-000000000523',
    'payment.rejected', repeat('d', 64), payment_id,
    'mtn_momo', 'RACE2500', null, receiver_hash,
    2500, now(), null, 'Synthetic provider rejection', 'REJECT-BEFORE-CONFIRM'
  );
  if result->>'replayed' <> 'false' then
    raise exception 'Initial provider rejection was not fresh';
  end if;
  begin
    perform public.process_provider_finality_event(
      '99600000-0000-4000-8000-000000000524',
      'payment.confirmed', repeat('e', 64), payment_id,
      'mtn_momo', 'RACE2500', 'ORDERING-LATE-CONFIRM', receiver_hash,
      2500, now(), repeat('f', 64), null, null
    );
    raise exception 'Late provider confirmation unexpectedly succeeded';
  exception when others then
    if sqlerrm <> 'Payment is not awaiting provider confirmation' then raise; end if;
  end;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.payments
      where transaction_id = 'RACE2500' and status = 'reversed') <> 1
     or (select count(*) from public.provider_finality_requests
         where status = 'processed') <> 1
     or (select count(*) from public.payment_provider_confirmations) <> 0
     or (select count(*) from public.ledger_entries) <> 0
     or (select count(*) from collect_hybrid.momo_journal_entries) <> 0
     or coalesce((select confirmed_rwf
         from collect_hybrid.collection_balances limit 1), 0) <> 0 then
    raise exception 'Late confirmation credited a rejected candidate';
  end if;
end $$;
select 'REJECT_THEN_CONFIRM_PASS';

rollback;
