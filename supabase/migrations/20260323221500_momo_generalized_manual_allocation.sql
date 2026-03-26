-- ==========================================================================
-- Cool App - Generalized MoMo SMS Manual Allocation
-- ==========================================================================

create or replace function public.allocate_momo_manual_review(
  p_review_id uuid,
  p_intent_id uuid,
  p_note text default null
)
returns table (
  review_id uuid,
  intent_id uuid,
  matched_reference text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_review public.momo_reconciliations%rowtype;
  v_intent public.payment_intents%rowtype;
  v_amount numeric;
  v_currency text;
  v_tx_datetime timestamptz;
  v_parsed_reference text;
  v_reference text;
  v_note text;
  v_user_id uuid;
  v_now timestamptz := now();
begin
  if p_review_id is null then
    raise exception 'Review id is required.';
  end if;

  if p_intent_id is null then
    raise exception 'Intent id is required.';
  end if;

  if not public.is_admin() then
    raise exception 'Admin privileges required to execute generalized manual allocation.';
  end if;

  -- 1. Lock and fetch the manual review
  select *
  into v_review
  from public.momo_reconciliations mr
  where mr.id = p_review_id
  for update;

  if not found then
    raise exception 'Manual review allocation was not found.';
  end if;

  if v_review.match_status not in ('pending_review', 'manual_review') then
    raise exception 'Only pending or manual-review allocations can be resolved.';
  end if;

  -- 2. Fetch parsed details
  select
    parsed.amount,
    parsed.currency,
    coalesce(parsed.tx_datetime, parsed.created_at),
    nullif(parsed.momo_tx_id, ''),
    parsed.user_id
  into
    v_amount,
    v_currency,
    v_tx_datetime,
    v_parsed_reference,
    v_user_id
  from public.momo_sms_parsed parsed
  where parsed.id = v_review.parsed_sms_id;

  if coalesce(v_amount, 0) <= 0 then
    raise exception 'The reviewed payment does not have a usable amount.';
  end if;

  -- 3. Lock and fetch intent
  select *
  into v_intent
  from public.payment_intents pi
  where pi.id = p_intent_id
  for update;

  if not found then
    raise exception 'Payment intent was not found.';
  end if;

  if v_intent.status <> 'pending' then
    raise exception 'Only pending payment intents can be allocated to.';
  end if;

  if v_intent.expected_amount <> v_amount then
    raise exception 'Payment intent expected amount (%) does not match SMS amount (%).', v_intent.expected_amount, v_amount;
  end if;

  v_reference := coalesce(
    v_parsed_reference,
    format('MR-%s', v_review.id)
  );

  -- 4. Update the Payment Intent
  update public.payment_intents
  set
    status = 'completed',
    updated_at = v_now
  where id = v_intent.id;

  v_note := coalesce(
    nullif(btrim(p_note), ''),
    'Admin manually allocated this payment.'
  );

  -- 5. Update reconciliation record
  update public.momo_reconciliations
  set
    target_table = coalesce(v_intent.target_table, 'payment_intents'),
    target_record_id = coalesce(v_intent.target_record_id, v_intent.id),
    match_type = format('admin_manual_allocation_to_%s', coalesce(v_intent.intent_type, 'intent')),
    match_status = 'matched',
    notes = v_note,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_allocation', true,
      'intent_id', p_intent_id,
      'matched_reference', v_reference,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'admin_operations'
    ),
    reconciled_at = v_now,
    updated_at = v_now
  where id = v_review.id;

  -- 6. Upsert the Ledger Entry (because pending review SMSs no longer default create ledger rows)
  insert into public.momo_ledger_entries (
    parsed_sms_id,
    user_id,
    entry_type,
    ledger_scope,
    ledger_status,
    amount,
    currency,
    tx_datetime,
    external_reference,
    target_table,
    target_record_id,
    description,
    metadata,
    created_at,
    updated_at
  ) values (
    v_review.parsed_sms_id,
    v_user_id,
    case when coalesce(v_amount, 0) >= 0 then 'credit' else 'debit' end,
    case
      when v_intent.intent_type = 'group_contribution' then 'group'
      when v_intent.intent_type = 'subscription' then 'subscription'
      when v_intent.intent_type = 'shop_order' then 'partner'
      else 'wallet'
    end,
    'posted',
    v_amount,
    coalesce(v_currency, 'RWF'),
    coalesce(v_tx_datetime, v_now),
    v_reference,
    coalesce(v_intent.target_table, 'payment_intents'),
    coalesce(v_intent.target_record_id, v_intent.id),
    'Manual allocation via admin review',
    jsonb_build_object(
      'manual_allocation', true,
      'intent_id', p_intent_id,
      'matched_reference', v_reference,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'admin_operations'
    ),
    v_now,
    v_now
  )
  on conflict (parsed_sms_id) do update set
    target_table = excluded.target_table,
    target_record_id = excluded.target_record_id,
    ledger_status = 'posted',
    ledger_scope = excluded.ledger_scope,
    external_reference = coalesce(public.momo_ledger_entries.external_reference, excluded.external_reference),
    metadata = coalesce(public.momo_ledger_entries.metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_allocation', true,
      'intent_id', p_intent_id,
      'matched_reference', excluded.external_reference,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'admin_operations'
    ),
    updated_at = v_now;

  return query
  select
    v_review.id,
    v_intent.id,
    v_reference;
end;
$$;

comment on function public.allocate_momo_manual_review(uuid, uuid, text) is
  'Admin-only operation to explicitly route a pending manual review SMS to a specific Payment Intent and post to the ledger.';

revoke all on function public.allocate_momo_manual_review(uuid, uuid, text) from public;
grant execute on function public.allocate_momo_manual_review(uuid, uuid, text)
  to authenticated, service_role;
