-- ==========================================================================
-- Cool App - Update MoMo SMS Manual Review Queues for Custodians
-- ==========================================================================

create or replace function public.get_momo_sms_manual_review_queue(
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  review_id uuid,
  raw_sms_id uuid,
  parsed_sms_id uuid,
  user_id uuid,
  sender text,
  tx_type text,
  tx_category text,
  cashflow_bucket text,
  amount integer,
  currency text,
  momo_tx_id text,
  payer_name text,
  payee_name text,
  payee_number_or_code text,
  merchant_code text,
  sms_received_at timestamptz,
  review_created_at timestamptz,
  updated_at timestamptz,
  review_kind text,
  reason text,
  notes text,
  sms_preview text,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_is_admin boolean;
begin
  v_is_admin := public.is_admin();

  return query
  with queue_rows as (
    select
      mr.id as review_id,
      raw.id as raw_sms_id,
      parsed.id as parsed_sms_id,
      mr.user_id,
      raw.sender,
      coalesce(parsed.tx_type, 'unknown') as tx_type,
      coalesce(parsed.tx_category, 'uncategorized') as tx_category,
      coalesce(parsed.cashflow_bucket, 'unknown') as cashflow_bucket,
      parsed.amount,
      coalesce(parsed.currency, 'RWF') as currency,
      parsed.momo_tx_id,
      parsed.payer_name,
      parsed.payee_name,
      parsed.payee_number_or_code,
      parsed.merchant_code,
      raw.sms_received_at,
      mr.created_at as review_created_at,
      coalesce(mr.updated_at, mr.created_at) as updated_at,
      case
        when coalesce(parsed.tx_type, 'unknown') in (
          'service_announcement',
          'account_status_update'
        )
          or coalesce(parsed.tx_category, 'uncategorized') = 'uncategorized'
          or coalesce(parsed.cashflow_bucket, 'unknown') = 'unknown'
          or coalesce(parsed.amount, 0) <= 0 then
          'non_actionable'
        when coalesce(mr.metadata ->> 'reason', '') = 'no_pending_transaction_match' then
          'unmatched_payment'
        else
          'needs_review'
      end as review_kind,
      coalesce(nullif(mr.metadata ->> 'reason', ''), 'manual_review') as reason,
      coalesce(
        nullif(btrim(mr.notes), ''),
        'Manual review required.'
      ) as notes,
      left(coalesce(raw.sms_body, ''), 220) as sms_preview
    from public.momo_reconciliations mr
    join public.momo_sms_parsed parsed
      on parsed.id = mr.parsed_sms_id
    join public.momo_sms_raw raw
      on raw.id = parsed.raw_sms_id
    left join public.payment_receiver_accounts pra
      on pra.payee_number_or_code = parsed.payee_number_or_code
    where mr.match_status = 'manual_review'
      and (
        v_is_admin
        or pra.owner_user_id = auth.uid()
        or exists (
          select 1
          from public.partner_users pu
          where pu.partner_id = pra.partner_id
            and pu.user_id = auth.uid()
        )
      )
  )
  select
    qr.review_id,
    qr.raw_sms_id,
    qr.parsed_sms_id,
    qr.user_id,
    qr.sender,
    qr.tx_type,
    qr.tx_category,
    qr.cashflow_bucket,
    qr.amount,
    qr.currency,
    qr.momo_tx_id,
    qr.payer_name,
    qr.payee_name,
    qr.payee_number_or_code,
    qr.merchant_code,
    qr.sms_received_at,
    qr.review_created_at,
    qr.updated_at,
    qr.review_kind,
    qr.reason,
    qr.notes,
    qr.sms_preview,
    count(*) over() as total_count
  from queue_rows qr
  order by qr.updated_at desc, qr.review_id desc
  limit greatest(coalesce(p_limit, 50), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

comment on function public.get_momo_sms_manual_review_queue(integer, integer) is
  'Queue for M-Money SMS manual reviews, filtered by admin access or receiver account ownership.';

create or replace function public.admin_reject_momo_sms_manual_review(
  p_review_id uuid,
  p_note text default null
)
returns table (
  review_id uuid,
  match_status text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_review public.momo_reconciliations%rowtype;
  v_parsed public.momo_sms_parsed%rowtype;
  v_pra public.payment_receiver_accounts%rowtype;
  v_note text;
  v_now timestamptz := now();
begin
  if p_review_id is null then
    raise exception 'Review id is required.';
  end if;

  select *
  into v_review
  from public.momo_reconciliations mr
  where mr.id = p_review_id
  for update;

  if not found then
    raise exception 'Manual review allocation was not found.';
  end if;

  if v_review.match_status not in ('pending_review', 'manual_review') then
    raise exception 'Only pending or manual-review reconciliations can be closed.';
  end if;

  select *
  into v_parsed
  from public.momo_sms_parsed
  where id = v_review.parsed_sms_id;

  select *
  into v_pra
  from public.payment_receiver_accounts
  where payee_number_or_code = v_parsed.payee_number_or_code;

  if not public.is_admin() then
    if v_pra.id is null then
      raise exception 'Admin privileges required to reject unowned reviews.';
    end if;
    if v_pra.owner_user_id <> auth.uid() and not exists (select 1 from public.partner_users pu where pu.partner_id = v_pra.partner_id and pu.user_id = auth.uid()) then
      raise exception 'Admin or custodian privileges required.';
    end if;
  end if;

  v_note := coalesce(
    nullif(btrim(p_note), ''),
    'Review rejected because it does not map to an app payment target.'
  );

  update public.momo_reconciliations
  set
    target_table = null,
    target_record_id = null,
    match_type = 'manual_rejection',
    match_status = 'rejected',
    notes = v_note,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_rejection', true,
      'manual_rejection_actor_id', auth.uid(),
      'manual_rejection_source', 'custodian_operations',
      'manual_rejection_reason', 'not_app_linked',
      'rejected_at', v_now
    ),
    reconciled_at = null,
    updated_at = v_now
  where id = v_review.id;

  update public.momo_ledger_entries
  set
    target_table = null,
    target_record_id = null,
    ledger_status = 'draft',
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_rejection', true,
      'manual_rejection_actor_id', auth.uid(),
      'manual_rejection_source', 'custodian_operations',
      'manual_rejection_reason', 'not_app_linked',
      'rejected_at', v_now
    ),
    updated_at = v_now
  where parsed_sms_id = v_review.parsed_sms_id;

  return query
  select v_review.id, 'rejected'::text;
end;
$$;

create or replace function public.admin_reject_momo_sms_manual_review_batch(
  p_review_ids uuid[],
  p_note text default null
)
returns table (
  rejected_count integer
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_now timestamptz := now();
  v_note text;
begin
  if coalesce(array_length(p_review_ids, 1), 0) = 0 then
    return query
    select 0::integer;
    return;
  end if;

  v_note := coalesce(
    nullif(btrim(p_note), ''),
    'Review rejected because it does not map to an app payment target.'
  );

  return query
  with input_ids as (
    select distinct review_id
    from unnest(p_review_ids) as review_id
    where review_id is not null
  ),
  eligible_reviews as (
    select mr.id, mr.parsed_sms_id
    from public.momo_reconciliations mr
    join input_ids ids
      on ids.review_id = mr.id
    join public.momo_sms_parsed parsed
      on parsed.id = mr.parsed_sms_id
    left join public.payment_receiver_accounts pra
      on pra.payee_number_or_code = parsed.payee_number_or_code
    where mr.match_status in ('pending_review', 'manual_review')
      and (
        public.is_admin()
        or pra.owner_user_id = auth.uid()
        or exists (
          select 1
          from public.partner_users pu
          where pu.partner_id = pra.partner_id
            and pu.user_id = auth.uid()
        )
      )
    for update
  ),
  updated_reviews as (
    update public.momo_reconciliations mr
    set
      target_table = null,
      target_record_id = null,
      match_type = 'manual_rejection',
      match_status = 'rejected',
      notes = v_note,
      metadata = coalesce(mr.metadata, '{}'::jsonb) || jsonb_build_object(
        'manual_rejection', true,
        'manual_rejection_actor_id', auth.uid(),
        'manual_rejection_source', 'custodian_operations',
        'manual_rejection_reason', 'not_app_linked',
        'rejected_at', v_now
      ),
      reconciled_at = null,
      updated_at = v_now
    from eligible_reviews er
    where mr.id = er.id
    returning mr.id, er.parsed_sms_id
  ),
  updated_ledgers as (
    update public.momo_ledger_entries le
    set
      target_table = null,
      target_record_id = null,
      ledger_status = 'draft',
      metadata = coalesce(le.metadata, '{}'::jsonb) || jsonb_build_object(
        'manual_rejection', true,
        'manual_rejection_actor_id', auth.uid(),
        'manual_rejection_source', 'custodian_operations',
        'manual_rejection_reason', 'not_app_linked',
        'rejected_at', v_now
      ),
      updated_at = v_now
    from updated_reviews ur
    where le.parsed_sms_id = ur.parsed_sms_id
    returning le.id
  )
  select count(*)::integer
  from updated_reviews;
end;
$$;
