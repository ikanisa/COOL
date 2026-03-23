-- ==========================================================================
-- Cool App - Bank admin manual allocation actions
-- ==========================================================================

create or replace function public.bank_manual_review_matches_partner(
  p_review_id uuid,
  p_partner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with candidate_groups as (
    select distinct scoped.group_id
    from (
      select gc.group_id
      from public.momo_reconciliations mr
      left join public.group_contributions gc
        on mr.target_table = 'group_contributions'
        and mr.target_record_id = gc.id
      where mr.id = p_review_id

      union all

      select nullif(mr.metadata ->> 'group_id', '')::uuid
      from public.momo_reconciliations mr
      where mr.id = p_review_id
        and nullif(mr.metadata ->> 'group_id', '') is not null

      union all

      select candidate_id::uuid
      from public.momo_reconciliations mr,
        jsonb_array_elements_text(
          coalesce(mr.metadata -> 'matching_group_ids', '[]'::jsonb)
        ) candidate(candidate_id)
      where mr.id = p_review_id
        and candidate_id ~* '^[0-9a-f-]{36}$'
    ) scoped
    where scoped.group_id is not null
  )
  select exists (
    select 1
    from candidate_groups cg
    where public.group_belongs_to_bank_partner(cg.group_id, p_partner_id)
  );
$$;
revoke all on function public.bank_manual_review_matches_partner(uuid, uuid) from public;
grant execute on function public.bank_manual_review_matches_partner(uuid, uuid)
  to authenticated, service_role;
create or replace function public.bank_allocate_manual_review_allocation(
  p_partner_id uuid,
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
set search_path = public
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
  if p_partner_id is null then
    raise exception 'Partner id is required.';
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

  if auth.uid() is null or not public.can_read_bank_custody(p_partner_id) then
    raise exception 'Not authorized to manage bank custody allocations.';
  end if;

  if not public.bank_manual_review_matches_partner(p_review_id, p_partner_id) then
    raise exception 'This review is not visible in the current bank workspace.';
  end if;

  if not public.group_belongs_to_bank_partner(p_group_id, p_partner_id) then
    raise exception 'The selected group is not linked to this bank workspace.';
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
    'Bank admin manually allocated this payment.'
  );

  update public.momo_reconciliations
  set
    target_table = 'group_contributions',
    target_record_id = v_contribution_id,
    match_type = 'bank_manual_group_allocation',
    match_status = 'matched',
    notes = v_note,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_allocation', true,
      'group_id', p_group_id,
      'allocated_user_id', p_member_user_id,
      'matched_reference', v_reference,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'bank_admin'
    ),
    reconciled_at = v_now,
    updated_at = v_now
  where id = v_review.id;

  update public.momo_ledger_entries
  set
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
      'allocation_source', 'bank_admin'
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
revoke all on function public.bank_allocate_manual_review_allocation(
  uuid,
  uuid,
  uuid,
  uuid,
  text
) from public;
grant execute on function public.bank_allocate_manual_review_allocation(
  uuid,
  uuid,
  uuid,
  uuid,
  text
) to authenticated, service_role;
create or replace function public.bank_reject_manual_review_allocation(
  p_partner_id uuid,
  p_review_id uuid,
  p_note text default null
)
returns table (
  review_id uuid,
  match_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_review public.momo_reconciliations%rowtype;
  v_note text;
  v_now timestamptz := now();
begin
  if p_partner_id is null then
    raise exception 'Partner id is required.';
  end if;

  if p_review_id is null then
    raise exception 'Review id is required.';
  end if;

  if auth.uid() is null or not public.can_read_bank_custody(p_partner_id) then
    raise exception 'Not authorized to manage bank custody allocations.';
  end if;

  if not public.bank_manual_review_matches_partner(p_review_id, p_partner_id) then
    raise exception 'This review is not visible in the current bank workspace.';
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
    raise exception 'Only pending or manual-review allocations can be rejected.';
  end if;

  v_note := coalesce(
    nullif(btrim(p_note), ''),
    'Bank admin rejected this payment allocation.'
  );

  update public.momo_reconciliations
  set
    target_table = null,
    target_record_id = null,
    match_type = 'bank_manual_rejection',
    match_status = 'rejected',
    notes = v_note,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'manual_rejection', true,
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'bank_admin',
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
      'allocation_actor_id', auth.uid(),
      'allocation_source', 'bank_admin',
      'rejected_at', v_now
    ),
    updated_at = v_now
  where parsed_sms_id = v_review.parsed_sms_id;

  return query
  select v_review.id, 'rejected'::text;
end;
$$;
revoke all on function public.bank_reject_manual_review_allocation(
  uuid,
  uuid,
  text
) from public;
grant execute on function public.bank_reject_manual_review_allocation(
  uuid,
  uuid,
  text
) to authenticated, service_role;
