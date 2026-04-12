-- ============================================================================
-- Expand group transaction allocation RPCs to bank custody admins
-- ============================================================================
-- Bank admins already have ledger visibility for the groups in their custody.
-- This update lets them correct member attribution using the same audited RPCs
-- that platform admins and group admins use.

create or replace function public.allocate_transaction_to_member(
  p_ledger_id uuid,
  p_group_id uuid,
  p_member_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_ledger public.momo_ledger_entries%rowtype;
  v_caller_id uuid := auth.uid();
  v_is_group_admin boolean;
  v_is_bank_custody_admin boolean;
  v_member_exists boolean;
  v_now timestamptz := now();
begin
  if p_ledger_id is null then
    raise exception 'Ledger entry id is required.';
  end if;
  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;
  if p_member_user_id is null then
    raise exception 'Member user id is required.';
  end if;

  select exists(
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = v_caller_id
      and gm.is_admin = true
  ) into v_is_group_admin;

  select exists (
    select 1
    from public.partners p
    where public.bank_is_partner_admin(p.id)
      and public.group_belongs_to_bank_partner(p_group_id, p.id)
  ) into v_is_bank_custody_admin;

  if not v_is_group_admin and not public.is_admin() and not v_is_bank_custody_admin then
    raise exception 'You must be a group admin, bank custody admin, or platform admin to allocate transactions.';
  end if;

  select exists(
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_member_user_id
  ) into v_member_exists;

  if not v_member_exists then
    raise exception 'The target member is not in this group.';
  end if;

  select *
  into v_ledger
  from public.momo_ledger_entries
  where id = p_ledger_id
  for update;

  if not found then
    raise exception 'Ledger entry not found.';
  end if;

  update public.momo_ledger_entries
  set
    target_table = 'group_contributions',
    target_record_id = p_group_id,
    user_id = p_member_user_id,
    ledger_scope = 'group',
    ledger_status = 'posted',
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'group_allocation', true,
      'allocated_group_id', p_group_id,
      'allocated_member_id', p_member_user_id,
      'allocation_actor_id', v_caller_id,
      'allocation_source',
        case
          when v_is_bank_custody_admin then 'bank_admin'
          when v_is_group_admin then 'group_admin'
          else 'platform_admin'
        end,
      'allocated_at', v_now
    ),
    updated_at = v_now
  where id = p_ledger_id;

  return jsonb_build_object(
    'status', 'success',
    'ledger_id', p_ledger_id,
    'group_id', p_group_id,
    'member_user_id', p_member_user_id
  );
end;
$$;

create or replace function public.unallocate_transaction(
  p_ledger_id uuid,
  p_group_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_ledger public.momo_ledger_entries%rowtype;
  v_caller_id uuid := auth.uid();
  v_is_group_admin boolean;
  v_is_bank_custody_admin boolean;
  v_now timestamptz := now();
begin
  if p_ledger_id is null then
    raise exception 'Ledger entry id is required.';
  end if;
  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;

  select exists(
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = v_caller_id
      and gm.is_admin = true
  ) into v_is_group_admin;

  select exists (
    select 1
    from public.partners p
    where public.bank_is_partner_admin(p.id)
      and public.group_belongs_to_bank_partner(p_group_id, p.id)
  ) into v_is_bank_custody_admin;

  if not v_is_group_admin and not public.is_admin() and not v_is_bank_custody_admin then
    raise exception 'You must be a group admin, bank custody admin, or platform admin to unallocate transactions.';
  end if;

  select *
  into v_ledger
  from public.momo_ledger_entries
  where id = p_ledger_id
  for update;

  if not found then
    raise exception 'Ledger entry not found.';
  end if;

  if v_ledger.target_record_id::text <> p_group_id::text then
    raise exception 'This ledger entry is not allocated to the specified group.';
  end if;

  update public.momo_ledger_entries
  set
    target_table = null,
    target_record_id = null,
    ledger_scope = 'wallet',
    ledger_status = 'draft',
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'unallocated_from_group', p_group_id,
      'unallocation_actor_id', v_caller_id,
      'unallocation_source',
        case
          when v_is_bank_custody_admin then 'bank_admin'
          when v_is_group_admin then 'group_admin'
          else 'platform_admin'
        end,
      'unallocated_at', v_now
    ),
    updated_at = v_now
  where id = p_ledger_id;

  return jsonb_build_object(
    'status', 'success',
    'ledger_id', p_ledger_id,
    'group_id', p_group_id
  );
end;
$$;
