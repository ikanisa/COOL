create or replace function public.get_rayon_member_registry(
  p_partner_id uuid,
  p_search_query text default null,
  p_filter_tier text default null,
  p_region text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  display_name text,
  membership_number text,
  points integer,
  tier text,
  chapter text,
  joined_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text := nullif(btrim(coalesce(p_search_query, '')), '');
  v_tier text := lower(nullif(btrim(coalesce(p_filter_tier, '')), ''));
  v_region text := nullif(btrim(coalesce(p_region, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if p_partner_id is null then
    raise exception 'Partner id is required.';
  end if;

  return query
  select
    membership.user_id,
    profile.public_user_id as display_name,
    membership.membership_number,
    membership.points,
    membership.tier,
    coalesce(nullif(btrim(membership.chapter), ''), 'Kigali Central') as chapter,
    membership.joined_at
  from public.rs_fan_memberships membership
  join public.users profile on profile.id = membership.user_id
  where membership.partner_id = p_partner_id
    and (v_tier is null or lower(membership.tier) = v_tier)
    and (
      v_region is null
      or coalesce(membership.chapter, '') ilike '%' || v_region || '%'
    )
    and (
      v_search is null
      or profile.public_user_id ilike '%' || v_search || '%'
      or membership.membership_number ilike '%' || v_search || '%'
    )
  order by
    membership.points desc,
    membership.joined_at asc,
    membership.membership_number asc
  limit greatest(coalesce(p_limit, 20), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
