begin;

-- Read history independently of today's profile country. These allowlists do
-- not expose names, contributor UUIDs, phone hashes, or raw payment evidence.
create function public.list_current_member_payment_history()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select coalesce(jsonb_agg(item order by happened_at desc, item->>'payment_id'), '[]'::jsonb)
  into result from (
    select p.posted_at as happened_at, jsonb_build_object(
      'payment_id', 'momo:' || p.id, 'collection_id', p.collection_id,
      'amount_minor', p.amount_rwf, 'currency', p.currency, 'rail', 'rwanda_momo',
      'posted_at', p.posted_at,
      'transaction_id', case when p.contributor_user_id = auth.uid() then p.transaction_id end,
      'is_current_user_contribution', coalesce(p.contributor_user_id = auth.uid(), false),
      'supporter_label', case when p.contributor_user_id = auth.uid() then 'You'
        when p.anonymity_choice = 'public_id' and p.contributor_public_id is not null
          then 'Collect ID ' || p.contributor_public_id else 'Anonymous supporter' end
    ) as item
    from public.payments p
    where p.status = 'posted' and (p.contributor_user_id = auth.uid()
      or public.user_can_read_collection(p.collection_id, auth.uid()))
    union all
    select t.reconciled_at, jsonb_build_object(
      'payment_id', 'bank:' || t.id, 'collection_id', a.collection_id,
      'amount_minor', t.amount_minor, 'currency', t.currency, 'rail', 'diaspora_bank',
      'posted_at', t.reconciled_at,
      'transaction_id', case when a.contributor_user_id = auth.uid()
        then coalesce(t.bank_transaction_id, t.end_to_end_id) end,
      'is_current_user_contribution', a.contributor_user_id = auth.uid(),
      'supporter_label', case when a.contributor_user_id = auth.uid()
        then 'You' else 'Collect member' end
    )
    from public.bank_transactions t
    join public.bank_transaction_allocations a on a.bank_transaction_id = t.id
    where t.status = 'reconciled' and (a.contributor_user_id = auth.uid()
      or public.user_can_read_collection(a.collection_id, auth.uid()))
  ) history;
  return result;
end $$;

-- Pending and completed intents keep their original rail and currency. Reads
-- calculate expiry without updating database rows or depending on a receiver
-- still being active. Historical receiver lookup must not drop the intent.
create function public.list_current_member_payment_intents()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select coalesce(jsonb_agg(item order by happened_at desc, item->>'rail', item->>'id'), '[]'::jsonb)
  into result from (
    select p.created_at as happened_at, jsonb_build_object(
      'id', p.id, 'collection_id', p.collection_id, 'rail', 'rwanda_momo',
      'amount_minor', p.expected_amount_rwf, 'currency', 'RWF',
      'receiver_momo_number', r.momo_number, 'receiver_label', r.label, 'network', r.network,
      'status', case when p.status = 'pending' and p.expires_at <= now()
        then 'expired' else p.status::text end,
      'created_at', p.created_at, 'expires_at', p.expires_at
    ) as item
    from public.payment_intents p
    left join lateral (
      select receiver.momo_number, receiver.label, receiver.network
      from public.collection_receivers receiver
      where receiver.collection_id = p.collection_id
        and receiver.momo_number_hash = p.receiver_momo_number_hash
      order by receiver.created_at desc, receiver.id limit 1
    ) r on true
    where p.contributor_user_id = auth.uid()
    union all
    select p.created_at, jsonb_build_object(
      'id', p.id, 'collection_id', p.collection_id, 'rail', 'diaspora_bank',
      'amount_minor', p.amount_minor, 'currency', p.currency,
      'destination', p.destination_snapshot, 'transfer_reference', p.transfer_reference,
      'status', case when p.status in ('awaiting_transfer','handoff_opened','awaiting_bank_evidence')
        and p.expires_at <= now() then 'expired' else p.status end,
      'created_at', p.created_at, 'expires_at', p.expires_at
    )
    from public.bank_transfer_intents p where p.contributor_user_id = auth.uid()
  ) history;
  return result;
end $$;

-- Each currency has its own balance. Never add cents to francs, infer FX, or
-- add the two rail-level distinct counts (the same account may use both).
create function public.list_current_member_collection_balances()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  with visible as (
    select c.id from public.collections c
    where public.user_can_read_collection(c.id, auth.uid())
  ), amounts as (
    select e.collection_id, e.currency,
      sum(e.amount_rwf) filter (where e.entry_type = 'collection_credit')::bigint as raised,
      coalesce(sum(e.amount_rwf) filter (where e.entry_type = 'member_credit'
        and e.user_id = auth.uid()), 0)::bigint as own
    from public.ledger_entries e join visible v on v.id = e.collection_id
    group by e.collection_id, e.currency
    union all
    select a.collection_id, t.currency, sum(t.amount_minor)::bigint,
      coalesce(sum(t.amount_minor) filter (where a.contributor_user_id = auth.uid()), 0)::bigint
    from public.bank_transactions t
    join public.bank_transaction_allocations a on a.bank_transaction_id = t.id
    join visible v on v.id = a.collection_id
    where t.status = 'reconciled' group by a.collection_id, t.currency
  ), contributors as (
    select p.collection_id, p.contributor_user_id
    from public.payments p join visible v on v.id = p.collection_id where p.status = 'posted'
    union all
    select a.collection_id, a.contributor_user_id
    from public.bank_transactions t
    join public.bank_transaction_allocations a on a.bank_transaction_id = t.id
    join visible v on v.id = a.collection_id where t.status = 'reconciled'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'collection_id', v.id,
    'balances', coalesce((select jsonb_agg(jsonb_build_object(
      'currency', a.currency, 'amount_raised_minor', coalesce(a.raised,0),
      'current_user_balance_minor', a.own) order by a.currency)
      from amounts a where a.collection_id = v.id), '[]'::jsonb),
    -- Anonymous unlinked receipts cannot prove a number of distinct people.
    'supporter_count', (select case when count(*) filter (where contributor_user_id is null) > 0
      then null else count(distinct contributor_user_id) end
      from contributors c where c.collection_id = v.id)
  ) order by v.id), '[]'::jsonb) into result from visible v;
  return result;
end $$;

-- Close the same peer-reference leak for already-installed bank clients.
create or replace function public.list_current_user_bank_contributions()
returns table (payment_id uuid, collection_id uuid, amount_rwf bigint,
  amount_minor bigint, currency text, posted_at timestamptz, transaction_id text,
  supporter_label text, is_current_user_contribution boolean)
language sql stable security definer set search_path = ''
as $$
  select t.id, a.collection_id, t.amount_minor, t.amount_minor, t.currency, t.reconciled_at,
    case when a.contributor_user_id = auth.uid() then coalesce(t.bank_transaction_id, t.end_to_end_id) end,
    case when a.contributor_user_id = auth.uid() then 'Your contribution' else 'Collect member' end,
    a.contributor_user_id = auth.uid()
  from public.bank_transactions t
  join public.bank_transaction_allocations a on a.bank_transaction_id = t.id
  where auth.uid() is not null and t.status = 'reconciled' and
    (a.contributor_user_id = auth.uid() or public.user_can_read_collection(a.collection_id, auth.uid()))
  order by t.reconciled_at desc, t.id;
$$;

revoke all on function public.list_current_member_payment_history() from public, anon, authenticated;
revoke all on function public.list_current_member_payment_intents() from public, anon, authenticated;
revoke all on function public.list_current_member_collection_balances() from public, anon, authenticated;
revoke all on function public.list_current_user_bank_contributions() from public, anon, authenticated;
grant execute on function public.list_current_member_payment_history() to authenticated;
grant execute on function public.list_current_member_payment_intents() to authenticated;
grant execute on function public.list_current_member_collection_balances() to authenticated;
grant execute on function public.list_current_user_bank_contributions() to authenticated;
commit;
