-- ==========================================================================
-- Cool App — Bank admin: add member to group + AI allocation support
-- ==========================================================================

-- ── RPC: bank_add_member_to_group ──────────────────────────────────────
-- Allows bank admin to create a new group member by phone number.
-- If the user exists, adds them to the group. If not, returns an error
-- telling admin the user must register first.

create or replace function public.bank_add_member_to_group(
  p_partner_id uuid,
  p_group_id uuid,
  p_phone text,
  p_display_name text default null
)
returns table (
  member_user_id uuid,
  display_name text,
  group_id uuid,
  is_new_member boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_user_name text;
  v_phone text;
  v_already_member boolean;
begin
  -- Validate inputs
  if p_partner_id is null then
    raise exception 'Partner id is required.';
  end if;

  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;

  v_phone := btrim(coalesce(p_phone, ''));
  if v_phone = '' then
    raise exception 'Phone number is required.';
  end if;

  -- Normalize phone: ensure +250 prefix
  if v_phone ~ '^\d{9}$' then
    v_phone := '+250' || v_phone;
  elsif v_phone ~ '^0\d{9}$' then
    v_phone := '+25' || v_phone;
  elsif v_phone ~ '^250\d{9}$' then
    v_phone := '+' || v_phone;
  end if;

  -- Auth check
  if auth.uid() is null or not public.can_read_bank_custody(p_partner_id) then
    raise exception 'Not authorized to manage bank custody members.';
  end if;

  -- Verify group belongs to this partner
  if not public.group_belongs_to_bank_partner(p_group_id, p_partner_id) then
    raise exception 'The selected group does not belong to this bank workspace.';
  end if;

  -- Look up user by phone
  select u.id, coalesce(u.full_name, '')
  into v_user_id, v_user_name
  from public.users u
  where u.phone = v_phone;

  if v_user_id is null then
    raise exception 'No registered user found with phone %. The user must register in the app first.', v_phone;
  end if;

  -- Check if already a member
  select exists(
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id = v_user_id
  ) into v_already_member;

  if v_already_member then
    -- Return existing member info
    return query
    select
      v_user_id,
      coalesce(nullif(btrim(p_display_name), ''), v_user_name, 'Member'),
      p_group_id,
      false;
    return;
  end if;

  -- Insert new member
  insert into public.group_members (
    group_id,
    user_id,
    display_name,
    is_admin,
    is_anonymous,
    contribution_amount,
    joined_at
  )
  values (
    p_group_id,
    v_user_id,
    coalesce(nullif(btrim(p_display_name), ''), v_user_name, 'Member'),
    false,
    false,
    0,
    now()
  );

  -- Update group member count
  update public.groups
  set member_count = member_count + 1, updated_at = now()
  where id = p_group_id;

  return query
  select
    v_user_id,
    coalesce(nullif(btrim(p_display_name), ''), v_user_name, 'Member'),
    p_group_id,
    true;
end;
$$;

revoke all on function public.bank_add_member_to_group(uuid, uuid, text, text) from public;
grant execute on function public.bank_add_member_to_group(uuid, uuid, text, text)
  to authenticated, service_role;

-- ── RPC: bank_accept_suggested_allocation ──────────────────────────────
-- Accepts an AI-suggested allocation stored in momo_reconciliations metadata.
-- Reads suggested_group_id + suggested_member_user_id from metadata,
-- then delegates to bank_allocate_manual_review_allocation.

create or replace function public.bank_accept_suggested_allocation(
  p_partner_id uuid,
  p_review_id uuid,
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
  v_metadata jsonb;
  v_suggested_group_id uuid;
  v_suggested_member_user_id uuid;
begin
  -- Get metadata from the reconciliation
  select mr.metadata
  into v_metadata
  from public.momo_reconciliations mr
  where mr.id = p_review_id;

  if not found then
    raise exception 'Review item not found.';
  end if;

  v_suggested_group_id := (v_metadata ->> 'suggested_group_id')::uuid;
  v_suggested_member_user_id := (v_metadata ->> 'suggested_member_user_id')::uuid;

  if v_suggested_group_id is null or v_suggested_member_user_id is null then
    raise exception 'No AI suggestion available for this review item.';
  end if;

  -- Delegate to existing allocation RPC
  return query
  select *
  from public.bank_allocate_manual_review_allocation(
    p_partner_id,
    p_review_id,
    v_suggested_group_id,
    v_suggested_member_user_id,
    coalesce(nullif(btrim(p_note), ''), 'Accepted AI suggestion.')
  );
end;
$$;

revoke all on function public.bank_accept_suggested_allocation(uuid, uuid, text) from public;
grant execute on function public.bank_accept_suggested_allocation(uuid, uuid, text)
  to authenticated, service_role;
