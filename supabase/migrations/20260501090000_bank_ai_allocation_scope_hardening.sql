-- ==========================================================================
-- Cool App — Bank AI allocation scope hardening
-- ==========================================================================
-- Keeps AI allocation suggestions inside the caller's bank workspace and moves
-- suggestion writes behind authenticated SECURITY DEFINER RPC guards.
-- ==========================================================================

create or replace function public.get_bank_all_group_members_for_matching(
  p_partner_id uuid
)
returns table (
  user_id uuid,
  display_name text,
  phone text,
  group_id uuid,
  group_name text,
  contribution_amount integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_partner_id is null then
    raise exception 'Partner id is required.';
  end if;

  if auth.uid() is null or not public.can_read_bank_custody(p_partner_id) then
    raise exception 'Not authorized to view this bank custody workspace.';
  end if;

  return query
  select
    gm.user_id,
    coalesce(
      nullif(btrim(gm.display_name), ''),
      nullif(btrim(u.full_name), ''),
      'Member'
    ) as display_name,
    coalesce(u.phone, '') as phone,
    gm.group_id,
    g.name as group_name,
    coalesce(
      gm.contribution_amount,
      g.monthly_contribution,
      g.contribution_amount,
      g.amount,
      0
    )::integer as contribution_amount
  from public.group_members gm
  join public.groups g
    on g.id = gm.group_id
  left join public.users u
    on u.id = gm.user_id
  where public.group_belongs_to_bank_partner(g.id, p_partner_id)
  order by g.name, display_name, gm.joined_at desc;
end;
$$;

revoke all on function public.get_bank_all_group_members_for_matching(uuid)
  from public;
grant execute on function public.get_bank_all_group_members_for_matching(uuid)
  to authenticated, service_role;

create or replace function public.bank_write_ai_allocation_suggestion(
  p_partner_id uuid,
  p_review_id uuid,
  p_group_id uuid,
  p_member_user_id uuid,
  p_confidence integer,
  p_reasoning text default null
)
returns table (
  review_id uuid,
  group_id uuid,
  user_id uuid,
  confidence integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_review public.momo_reconciliations%rowtype;
  v_confidence integer;
  v_reasoning text;
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
    raise exception 'The suggested group is not linked to this bank workspace.';
  end if;

  if not exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.user_id = p_member_user_id
  ) then
    raise exception 'The suggested member does not belong to the target group.';
  end if;

  select *
  into v_review
  from public.momo_reconciliations mr
  where mr.id = p_review_id
  for update;

  if not found then
    raise exception 'Manual review allocation was not found.';
  end if;

  if v_review.match_status not in ('pending_review', 'manual_review', 'suggested') then
    raise exception 'Only pending, manual-review, or suggested allocations can be suggested.';
  end if;

  v_confidence := greatest(0, least(coalesce(p_confidence, 0), 100));
  v_reasoning := left(nullif(btrim(coalesce(p_reasoning, '')), ''), 500);

  update public.momo_reconciliations
  set
    match_status = 'suggested',
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'suggested_group_id', p_group_id,
      'suggested_member_user_id', p_member_user_id,
      'suggested_confidence', v_confidence,
      'ai_reasoning', v_reasoning,
      'ai_suggested_by', auth.uid(),
      'ai_suggested_at', v_now,
      'ai_suggestion_source', 'allocate-contributions'
    ),
    updated_at = v_now
  where id = v_review.id;

  return query
  select
    v_review.id,
    p_group_id,
    p_member_user_id,
    v_confidence;
end;
$$;

revoke all on function public.bank_write_ai_allocation_suggestion(
  uuid,
  uuid,
  uuid,
  uuid,
  integer,
  text
) from public;
grant execute on function public.bank_write_ai_allocation_suggestion(
  uuid,
  uuid,
  uuid,
  uuid,
  integer,
  text
) to authenticated, service_role;
