-- ==========================================================================
-- Cool App - Group-Level Transaction Allocation RPCs
-- ==========================================================================
-- These RPCs allow group admins (privileged admin role) to allocate or
-- unallocate ledger entries to/from group members directly from the
-- group statements screen.
-- ==========================================================================

-- ──────────────────────────────────────────────────────────────────────────
-- allocate_transaction_to_member
-- ──────────────────────────────────────────────────────────────────────────
-- Assigns a momo_ledger_entries row to a specific group member by updating
-- the target_record_id (the member's user_id in context of the group).

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
  v_member_exists boolean;
  v_now timestamptz := now();
begin
  -- Validate input
  if p_ledger_id is null then
    raise exception 'Ledger entry id is required.';
  end if;
  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;
  if p_member_user_id is null then
    raise exception 'Member user id is required.';
  end if;

  -- Check caller is a group admin or app admin
  select exists(
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = v_caller_id
      and gm.is_admin = true
  ) into v_is_group_admin;

  if not v_is_group_admin and not public.is_admin() then
    raise exception 'You must be a group admin to allocate transactions.';
  end if;

  -- Verify the target member exists in the group
  select exists(
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_member_user_id
  ) into v_member_exists;

  if not v_member_exists then
    raise exception 'The target member is not in this group.';
  end if;

  -- Lock and fetch the ledger entry
  select *
  into v_ledger
  from public.momo_ledger_entries
  where id = p_ledger_id
  for update;

  if not found then
    raise exception 'Ledger entry not found.';
  end if;

  -- Update the ledger entry
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
      'allocation_source', 'group_admin',
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

comment on function public.allocate_transaction_to_member(uuid, uuid, uuid) is
  'Group-admin action: allocate a ledger entry to a specific group member.';

revoke all on function public.allocate_transaction_to_member(uuid, uuid, uuid)
  from public;
grant execute on function public.allocate_transaction_to_member(uuid, uuid, uuid)
  to authenticated, service_role;


-- ──────────────────────────────────────────────────────────────────────────
-- unallocate_transaction
-- ──────────────────────────────────────────────────────────────────────────
-- Removes group allocation from a ledger entry, reverting it to wallet scope.

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
  v_now timestamptz := now();
begin
  -- Validate input
  if p_ledger_id is null then
    raise exception 'Ledger entry id is required.';
  end if;
  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;

  -- Check caller is a group admin or app admin
  select exists(
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = v_caller_id
      and gm.is_admin = true
  ) into v_is_group_admin;

  if not v_is_group_admin and not public.is_admin() then
    raise exception 'You must be a group admin to unallocate transactions.';
  end if;

  -- Lock and fetch the ledger entry
  select *
  into v_ledger
  from public.momo_ledger_entries
  where id = p_ledger_id
  for update;

  if not found then
    raise exception 'Ledger entry not found.';
  end if;

  -- Verify it's actually allocated to this group
  if v_ledger.target_record_id::text <> p_group_id::text then
    raise exception 'This ledger entry is not allocated to the specified group.';
  end if;

  -- Revert to wallet scope
  update public.momo_ledger_entries
  set
    target_table = null,
    target_record_id = null,
    ledger_scope = 'wallet',
    ledger_status = 'draft',
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'unallocated_from_group', p_group_id,
      'unallocation_actor_id', v_caller_id,
      'unallocation_source', 'group_admin',
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

comment on function public.unallocate_transaction(uuid, uuid) is
  'Group-admin action: remove group allocation from a ledger entry, reverting to wallet scope.';

revoke all on function public.unallocate_transaction(uuid, uuid) from public;
grant execute on function public.unallocate_transaction(uuid, uuid)
  to authenticated, service_role;
