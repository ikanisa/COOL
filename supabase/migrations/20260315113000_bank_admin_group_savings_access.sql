-- ============================================================================
-- Cool App - Bank admin group savings custody access
-- ============================================================================

create or replace function public.bank_is_partner_admin(p_partner_id uuid)
returns boolean
language sql
stable
as $$
  select
    coalesce(auth.jwt() -> 'app_metadata' ->> 'is_bank_admin', 'false') = 'true'
    or coalesce(
      (auth.jwt() -> 'app_metadata' -> 'bank_admin_ids') ? p_partner_id::text,
      false
    );
$$;

create or replace function public.group_belongs_to_bank_partner(
  p_group_id uuid,
  p_partner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.groups g
    left join public.partners p
      on p.id = p_partner_id
    where g.id = p_group_id
      and (
        g.institution_id = p_partner_id::text
        or lower(btrim(coalesce(g.institution_id, ''))) = lower(btrim(coalesce(p.slug, '')))
        or lower(btrim(coalesce(g.bank_partner, ''))) = lower(btrim(coalesce(p.name, '')))
        or lower(btrim(coalesce(g.bank_partner, ''))) = lower(btrim(coalesce(p.slug, '')))
      )
  );
$$;

revoke all on function public.group_belongs_to_bank_partner(uuid, uuid) from public;
grant execute on function public.group_belongs_to_bank_partner(uuid, uuid)
  to authenticated, service_role;

create or replace function public.can_read_bank_custody(
  p_partner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin_user()
    or public.bank_is_partner_admin(p_partner_id);
$$;

revoke all on function public.can_read_bank_custody(uuid) from public;
grant execute on function public.can_read_bank_custody(uuid)
  to authenticated, service_role;

create or replace function public.can_read_group_payment_ledger(
  p_group_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin_user()
    or exists (
      select 1
      from public.groups g
      where g.id = p_group_id
        and g.creator_id = auth.uid()
    )
    or exists (
      select 1
      from public.group_members gm
      where gm.group_id = p_group_id
        and gm.user_id = auth.uid()
        and gm.is_admin = true
    )
    or exists (
      select 1
      from public.partners p
      where public.bank_is_partner_admin(p.id)
        and public.group_belongs_to_bank_partner(p_group_id, p.id)
    );
$$;

revoke all on function public.can_read_group_payment_ledger(uuid) from public;
grant execute on function public.can_read_group_payment_ledger(uuid)
  to authenticated, service_role;

create or replace function public.get_bank_custody_groups(
  p_partner_id uuid,
  p_search text default null,
  p_limit integer default 1000,
  p_offset integer default 0
)
returns table (
  id uuid,
  creator_id uuid,
  name text,
  type text,
  visibility text,
  amount integer,
  target_amount integer,
  country text,
  member_count integer,
  monthly_contribution integer,
  description text,
  bank_partner text,
  momo_number text,
  receiving_momo_route_type text,
  institution_id text,
  invite_code text,
  frequency text,
  created_at timestamptz,
  updated_at timestamptz,
  admin_count integer,
  contribution_count integer,
  contribution_total integer,
  last_contribution_at timestamptz,
  total_count bigint
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
  with scoped_groups as (
    select g.*
    from public.groups g
    where public.group_belongs_to_bank_partner(g.id, p_partner_id)
      and (
        p_search is null
        or btrim(p_search) = ''
        or g.name ilike '%' || btrim(p_search) || '%'
        or coalesce(g.description, '') ilike '%' || btrim(p_search) || '%'
        or coalesce(g.invite_code, '') ilike '%' || btrim(p_search) || '%'
      )
  ),
  aggregated as (
    select
      g.id,
      g.creator_id,
      g.name,
      g.type,
      g.visibility,
      g.amount,
      g.target_amount,
      g.country,
      g.monthly_contribution,
      g.description,
      g.bank_partner,
      g.momo_number,
      g.receiving_momo_route_type,
      g.institution_id,
      g.invite_code,
      g.frequency,
      g.created_at,
      g.updated_at,
      count(distinct gm.user_id)::int as member_count,
      count(distinct gm.user_id) filter (where gm.is_admin = true)::int as admin_count,
      count(distinct gc.id)::int as contribution_count,
      coalesce(sum(gc.amount), 0)::int as contribution_total,
      max(gc.created_at) as last_contribution_at
    from scoped_groups g
    left join public.group_members gm
      on gm.group_id = g.id
    left join public.group_contributions gc
      on gc.group_id = g.id
    group by
      g.id,
      g.creator_id,
      g.name,
      g.type,
      g.visibility,
      g.amount,
      g.target_amount,
      g.country,
      g.monthly_contribution,
      g.description,
      g.bank_partner,
      g.momo_number,
      g.receiving_momo_route_type,
      g.institution_id,
      g.invite_code,
      g.frequency,
      g.created_at,
      g.updated_at
  )
  select
    a.id,
    a.creator_id,
    a.name,
    a.type,
    a.visibility,
    a.amount,
    a.target_amount,
    a.country,
    a.member_count,
    a.monthly_contribution,
    a.description,
    a.bank_partner,
    a.momo_number,
    a.receiving_momo_route_type,
    a.institution_id,
    a.invite_code,
    a.frequency,
    a.created_at,
    a.updated_at,
    a.admin_count,
    a.contribution_count,
    a.contribution_total,
    a.last_contribution_at,
    count(*) over() as total_count
  from aggregated a
  order by a.updated_at desc nulls last, a.created_at desc nulls last, a.id desc
  limit greatest(coalesce(p_limit, 1000), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.get_bank_custody_groups(uuid, text, integer, integer) from public;
grant execute on function public.get_bank_custody_groups(uuid, text, integer, integer)
  to authenticated, service_role;

create or replace function public.get_bank_custody_group_members(
  p_partner_id uuid,
  p_group_id uuid default null,
  p_search text default null,
  p_limit integer default 1000,
  p_offset integer default 0
)
returns table (
  group_id uuid,
  group_name text,
  user_id uuid,
  display_name text,
  is_admin boolean,
  is_anonymous boolean,
  contribution_amount integer,
  joined_at timestamptz,
  total_count bigint
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
    raise exception 'Not authorized to view bank custody members.';
  end if;

  if p_group_id is not null and not public.group_belongs_to_bank_partner(p_group_id, p_partner_id) then
    raise exception 'This group is not linked to the requested bank workspace.';
  end if;

  return query
  with scoped_members as (
    select
      gm.group_id,
      g.name as group_name,
      gm.user_id,
      coalesce(
        nullif(btrim(gm.display_name), ''),
        nullif(btrim(u.public_user_id), ''),
        nullif(btrim(u.full_name), ''),
        'Member'
      ) as display_name,
      gm.is_admin,
      gm.is_anonymous,
      gm.contribution_amount,
      gm.joined_at
    from public.group_members gm
    join public.groups g
      on g.id = gm.group_id
    left join public.users u
      on u.id = gm.user_id
    where public.group_belongs_to_bank_partner(g.id, p_partner_id)
      and (p_group_id is null or gm.group_id = p_group_id)
      and (
        p_search is null
        or btrim(p_search) = ''
        or coalesce(gm.display_name, '') ilike '%' || btrim(p_search) || '%'
        or coalesce(u.public_user_id, '') ilike '%' || btrim(p_search) || '%'
        or coalesce(u.full_name, '') ilike '%' || btrim(p_search) || '%'
        or g.name ilike '%' || btrim(p_search) || '%'
      )
  )
  select
    sm.group_id,
    sm.group_name,
    sm.user_id,
    sm.display_name,
    sm.is_admin,
    sm.is_anonymous,
    sm.contribution_amount,
    sm.joined_at,
    count(*) over() as total_count
  from scoped_members sm
  order by sm.joined_at desc nulls last, sm.group_name asc, sm.display_name asc
  limit greatest(coalesce(p_limit, 1000), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.get_bank_custody_group_members(uuid, uuid, text, integer, integer) from public;
grant execute on function public.get_bank_custody_group_members(uuid, uuid, text, integer, integer)
  to authenticated, service_role;

create or replace function public.get_bank_custody_contributions(
  p_partner_id uuid,
  p_group_id uuid default null,
  p_status text default null,
  p_limit integer default 1000,
  p_offset integer default 0
)
returns table (
  contribution_id uuid,
  group_id uuid,
  group_name text,
  user_id uuid,
  contributor_name text,
  amount integer,
  status text,
  momo_reference text,
  created_at timestamptz,
  total_count bigint
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
    raise exception 'Not authorized to view bank custody contributions.';
  end if;

  if p_group_id is not null and not public.group_belongs_to_bank_partner(p_group_id, p_partner_id) then
    raise exception 'This group is not linked to the requested bank workspace.';
  end if;

  return query
  with scoped_contributions as (
    select
      gc.id as contribution_id,
      gc.group_id,
      g.name as group_name,
      gc.user_id,
      coalesce(
        nullif(btrim(gm.display_name), ''),
        nullif(btrim(u.public_user_id), ''),
        nullif(btrim(u.full_name), ''),
        'Member'
      ) as contributor_name,
      gc.amount,
      gc.status,
      gc.momo_reference,
      gc.created_at
    from public.group_contributions gc
    join public.groups g
      on g.id = gc.group_id
    left join public.group_members gm
      on gm.group_id = gc.group_id
      and gm.user_id = gc.user_id
    left join public.users u
      on u.id = gc.user_id
    where public.group_belongs_to_bank_partner(g.id, p_partner_id)
      and (p_group_id is null or gc.group_id = p_group_id)
      and (
        p_status is null
        or btrim(p_status) = ''
        or lower(gc.status) = lower(btrim(p_status))
      )
  )
  select
    sc.contribution_id,
    sc.group_id,
    sc.group_name,
    sc.user_id,
    sc.contributor_name,
    sc.amount,
    sc.status,
    sc.momo_reference,
    sc.created_at,
    count(*) over() as total_count
  from scoped_contributions sc
  order by sc.created_at desc, sc.contribution_id desc
  limit greatest(coalesce(p_limit, 1000), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.get_bank_custody_contributions(uuid, uuid, text, integer, integer) from public;
grant execute on function public.get_bank_custody_contributions(uuid, uuid, text, integer, integer)
  to authenticated, service_role;

create or replace function public.get_bank_manual_review_allocations(
  p_partner_id uuid,
  p_limit integer default 1000,
  p_offset integer default 0
)
returns table (
  review_id uuid,
  group_id uuid,
  group_name text,
  payer_user_id uuid,
  payer_name text,
  match_status text,
  reason text,
  matched_reference text,
  amount integer,
  provider text,
  payee_digits text,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
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
    raise exception 'Not authorized to view bank custody allocations.';
  end if;

  return query
  with candidate_rows as (
    select
      mr.id as review_id,
      coalesce(
        gc.group_id,
        nullif(mr.metadata ->> 'group_id', '')::uuid,
        (
          select candidate_id::uuid
          from jsonb_array_elements_text(coalesce(mr.metadata -> 'matching_group_ids', '[]'::jsonb)) candidate(candidate_id)
          where candidate_id ~* '^[0-9a-f-]{36}$'
          limit 1
        )
      ) as group_id,
      mr.user_id as payer_user_id,
      coalesce(
        nullif(btrim(u.public_user_id), ''),
        nullif(btrim(u.full_name), ''),
        'Member'
      ) as payer_name,
      mr.match_status,
      coalesce(nullif(mr.metadata ->> 'reason', ''), nullif(mr.notes, ''), 'manual_review') as reason,
      nullif(mr.metadata ->> 'matched_reference', '') as matched_reference,
      coalesce((mr.metadata ->> 'amount')::integer, 0) as amount,
      nullif(mr.metadata ->> 'provider', '') as provider,
      coalesce(
        nullif(mr.metadata ->> 'receiver_source_of_truth', ''),
        nullif(mr.metadata ->> 'payee_number_or_code', ''),
        nullif(mr.metadata ->> 'merchant_code', '')
      ) as payee_digits,
      mr.created_at,
      coalesce(mr.updated_at, mr.created_at) as updated_at
    from public.momo_reconciliations mr
    left join public.group_contributions gc
      on mr.target_table = 'group_contributions'
      and mr.target_record_id = gc.id
    left join public.users u
      on u.id = mr.user_id
    where mr.match_status in ('pending_review', 'manual_review')
  ),
  scoped_reviews as (
    select
      cr.review_id,
      cr.group_id,
      g.name as group_name,
      cr.payer_user_id,
      cr.payer_name,
      cr.match_status,
      cr.reason,
      cr.matched_reference,
      cr.amount,
      cr.provider,
      cr.payee_digits,
      cr.created_at,
      cr.updated_at
    from candidate_rows cr
    join public.groups g
      on g.id = cr.group_id
    where public.group_belongs_to_bank_partner(g.id, p_partner_id)
  )
  select
    sr.review_id,
    sr.group_id,
    sr.group_name,
    sr.payer_user_id,
    sr.payer_name,
    sr.match_status,
    sr.reason,
    sr.matched_reference,
    sr.amount,
    sr.provider,
    sr.payee_digits,
    sr.created_at,
    sr.updated_at,
    count(*) over() as total_count
  from scoped_reviews sr
  order by sr.updated_at desc, sr.review_id desc
  limit greatest(coalesce(p_limit, 1000), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.get_bank_manual_review_allocations(uuid, integer, integer) from public;
grant execute on function public.get_bank_manual_review_allocations(uuid, integer, integer)
  to authenticated, service_role;
