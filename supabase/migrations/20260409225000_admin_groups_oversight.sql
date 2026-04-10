-- ==========================================================================
-- Admin Groups Oversight — read-only admin summary for groups
-- ==========================================================================

-- ── get_admin_groups_summary ────────────────────────────────────────────
-- Returns aggregate counts and a list of all groups with member stats.
-- Platform admin only.

create or replace function public.get_admin_groups_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin_user() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  select jsonb_build_object(
    'total_groups',   (select count(*) from public.groups),
    'active_groups',  (select count(*) from public.groups where is_active = true),
    'closed_groups',  (select count(*) from public.groups where is_closed = true),
    'public_groups',  (select count(*) from public.groups where visibility = 'public'),
    'private_groups', (select count(*) from public.groups where visibility = 'private'),
    'total_members',  (select count(*) from public.group_members),
    'groups', coalesce((
      select jsonb_agg(g_row order by g_row->>'created_at' desc)
      from (
        select jsonb_build_object(
          'id',                   g.id,
          'name',                 g.name,
          'type',                 g.type,
          'visibility',           g.visibility,
          'country',              g.country,
          'target_amount',        g.target_amount,
          'monthly_contribution', g.monthly_contribution,
          'momo_number',          g.momo_number,
          'invite_code',          g.invite_code,
          'creator_id',           g.creator_id,
          'created_at',           g.created_at,
          'member_count',         coalesce(mc.cnt, 0)
        ) as g_row
        from public.groups g
        left join lateral (
          select count(*) as cnt
          from public.group_members m
          where m.group_id = g.id
        ) mc on true
      ) sub
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

comment on function public.get_admin_groups_summary() is
  'Returns admin overview of all groups with member counts. Platform admin only.';

revoke all on function public.get_admin_groups_summary() from public;
grant execute on function public.get_admin_groups_summary()
  to authenticated;
