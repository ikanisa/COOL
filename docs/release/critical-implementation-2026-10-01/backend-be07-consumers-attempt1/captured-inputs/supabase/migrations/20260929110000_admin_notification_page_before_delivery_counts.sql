-- Admin delivery counts are page details. Keep the exact filtered total, but
-- avoid two delivery probes for every matching notification before LIMIT.
-- Schedule index creation against a measured hosted table before live apply.
create index notification_events_admin_created_idx
  on public.notification_events (created_at desc, id);
create index notification_events_admin_status_created_idx
  on public.notification_events (status, created_at desc, id);

create or replace function public.admin_list_notifications(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  perform public.assert_admin_permission('notifications.read');

  with page as materialized (
    select event.id, event.type, event.status, event.created_at,
      profile.public_id
    from public.notification_events event
    join public.profiles profile on profile.id = event.user_id
    where (p_status is null or event.status = p_status)
      and (
        p_search is null
        or event.type ilike '%' || p_search || '%'
        or profile.public_id = p_search
      )
    order by
      case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc'
        then event.created_at end asc nulls last,
      event.created_at desc,
      event.id
    limit v_limit offset v_offset
  ), enriched as (
    select page.*,
      delivery_counts.delivery_count,
      delivery_counts.failed_count
    from page
    left join lateral (
      select count(*)::bigint as delivery_count,
        count(*) filter (where delivery.status = 'failed')::bigint
          as failed_count
      from public.notification_deliveries delivery
      where delivery.event_id = page.id
    ) delivery_counts on true
  )
  select jsonb_build_object(
    'rows', coalesce((
      select jsonb_agg(
        public._admin_row(
          row.id,
          replace(initcap(replace(row.type, '_', ' ')), 'Momo', 'MoMo'),
          'Collect ID ' || row.public_id || ' • ' ||
            row.delivery_count || ' deliveries',
          row.status,
          case when row.failed_count > 0
            then row.failed_count || ' failed' else '' end,
          row.created_at,
          jsonb_build_object('failed_deliveries', row.failed_count)
        )
        order by
          case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc'
            then row.created_at end asc nulls last,
          row.created_at desc,
          row.id
      )
      from enriched row
    ), '[]'::jsonb),
    'total', (
      select count(*)
      from public.notification_events event
      join public.profiles profile on profile.id = event.user_id
      where (p_status is null or event.status = p_status)
        and (
          p_search is null
          or event.type ilike '%' || p_search || '%'
          or profile.public_id = p_search
        )
    )
  ) into v_result;

  return coalesce(v_result,
    jsonb_build_object('rows', '[]'::jsonb, 'total', 0));
end;
$$;

revoke execute on function public.admin_list_notifications(
  text, text, integer, integer, text
) from public, anon;
grant execute on function public.admin_list_notifications(
  text, text, integer, integer, text
) to authenticated;
