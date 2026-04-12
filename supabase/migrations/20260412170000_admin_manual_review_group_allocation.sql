-- ============================================================================
-- Platform admin manual-review allocation to savings group members
-- ============================================================================
-- Gives platform admins the same end-state capability as bank custodians for
-- resolving a manual-review MoMo SMS directly into a savings contribution.

create or replace function public.admin_allocate_momo_sms_manual_review_to_group_member(
  p_review_id uuid,
  p_group_id uuid,
  p_member_user_id uuid,
  p_note text default null
)
returns table (
  review_id uuid,
  contribution_id uuid,
  group_id uuid,
  user_id uuid,
  matched_reference text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_review public.momo_reconciliations%rowtype;
  v_amount integer;
  v_tx_datetime timestamptz;
  v_parsed_reference text;
  v_reference text;
  v_contribution_id uuid;
  v_existing_contribution_id uuid;
  v_note text;
  v_now timestamptz := now();
begin
  if not public.is_admin_user() then
    raise exception 'Platform admin access is required.';
  end if;

  if p_review_id is null then
    raise exception 'Review id is required.';
  end if;

  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;

  if p_member_user_id is null then
    raise exception 'Member user id is required.';
  end if;

  if not exists (
    select 1
    from public.groups g
    where g.id = p_group_id
      and g.type = 'saving'
  ) then
    raise exception 'Savings group not found.';
  end if;

  if not exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_member_user_id
  ) then
    raise exception 'The selected member does not belong to the target group.';
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
    raise exception 'Only pending or manual-review allocations can be resolved.';
  end if;

  select
    parsed.amount,
    coalesce(parsed.tx_datetime, parsed.created_at),
    nullif(parsed.momo_tx_id, '')
  into
    v_amount,
    v_tx_datetime,
    v_parsed_reference
  from public.momo_sms_parsed parsed
  where parsed.id = v_review.parsed_sms_id;

  if coalesce(v_amount, 0) <= 0 then
    raise exception 'The reviewed payment does not have a usable amount.';
  end if;

  v_reference := coalesce(
    nullif(v_review.metadata ->> 'matched_reference', ''),
    v_parsed_reference,
    format('MR-%s', v_review.id)
  );

  select gc.id
  into v_existing_contribution_id
  from public.group_contributions gc
  where gc.group_id = p_group_id
    and gc.user_id = p_member_user_id
    and (
      gc.momo_reference = v_reference
      or (
        gc.amount = v_amount
        and gc.status in ('pending', 'confirmed')
      )
    )
  order by
    case when gc.momo_reference = v_reference then 0 else 1 end,
    gc.created_at desc
  limit 1;

  if v_existing_contribution_id is null then
    insert into public.group_contributions (
      group_id,
      user_id,
      amount,
      status,
      momo_reference,
      created_at
    )
    values (
      p_group_id,
      p_member_user_id,
      v_amount,
      'confirmed',
      v_reference,
      coalesce(v_tx_datetime, v_review.created_at, v_now)
    )
    returning id
    into v_contribution_id;
  else
    update public.group_contributions
    set
      amount = v_amount,
      status = 'confirmed',
      momo_reference = coalesce(momo_reference, v_reference)
    where id = v_existing_contribution_id
    returning id
    into v_contribution_id;
  end if;

  v_note := coalesce(
    nullif(btrim(p_note), ''),
    'Platform admin manually allocated this payment.'
  );

  update public.momo_reconciliations
  set
    target_table = 'group_contributions',
    target_record_id = v_contribution_id,
    match_type = 'admin_manual_group_allocation',
    match_status = 'matched',
    notes = v_note,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_allocation', true,
      'group_id', p_group_id,
      'allocated_user_id', p_member_user_id,
      'matched_reference', v_reference,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'admin_operations'
    ),
    reconciled_at = v_now,
    updated_at = v_now
  where id = v_review.id;

  update public.momo_ledger_entries
  set
    user_id = p_member_user_id,
    target_table = 'group_contributions',
    target_record_id = v_contribution_id,
    payee_group_id = p_group_id,
    ledger_scope = 'savings',
    ledger_status = 'posted',
    external_reference = coalesce(external_reference, v_reference),
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_allocation', true,
      'group_id', p_group_id,
      'allocated_user_id', p_member_user_id,
      'matched_reference', v_reference,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'admin_operations'
    ),
    updated_at = v_now
  where parsed_sms_id = v_review.parsed_sms_id;

  return query
  select
    v_review.id,
    v_contribution_id,
    p_group_id,
    p_member_user_id,
    v_reference;
end;
$$;

revoke all on function public.admin_allocate_momo_sms_manual_review_to_group_member(
  uuid,
  uuid,
  uuid,
  text
) from public;

grant execute on function public.admin_allocate_momo_sms_manual_review_to_group_member(
  uuid,
  uuid,
  uuid,
  text
) to authenticated, service_role;

comment on function public.admin_allocate_momo_sms_manual_review_to_group_member(uuid, uuid, uuid, text) is
  'Platform-admin operation to resolve a MoMo manual-review record into a savings-group contribution.';
