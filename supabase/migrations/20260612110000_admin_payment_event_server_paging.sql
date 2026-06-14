create or replace function admin_list_payment_events(
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
  v_sort text := coalesce(nullif(p_sort, ''), 'created_at_desc');
  v_result jsonb;
begin
  perform assert_admin_permission('payment_events.read');
  if v_sort not in (
    'created_at_desc',
    'created_at_asc',
    'amount_desc',
    'amount_asc'
  ) then
    v_sort := 'created_at_desc';
  end if;

  with filtered as (
    select e.*
    from parsed_payment_events e
    where (p_status is null or e.allocation_status::text = p_status)
      and (p_search is null or e.transaction_id ilike '%' || p_search || '%')
  ),
  ordered as (
    select
      filtered.*,
      row_number() over (
        order by
          case when v_sort = 'created_at_asc' then filtered.created_at end asc nulls last,
          case when v_sort = 'created_at_desc' then filtered.created_at end desc nulls last,
          case when v_sort = 'amount_asc' then filtered.amount_rwf end asc nulls last,
          case when v_sort = 'amount_desc' then filtered.amount_rwf end desc nulls last,
          filtered.created_at desc nulls last,
          filtered.id
      ) as admin_rank
    from filtered
    order by
      case when v_sort = 'created_at_asc' then filtered.created_at end asc nulls last,
      case when v_sort = 'created_at_desc' then filtered.created_at end desc nulls last,
      case when v_sort = 'amount_asc' then filtered.amount_rwf end asc nulls last,
      case when v_sort = 'amount_desc' then filtered.amount_rwf end desc nulls last,
      filtered.created_at desc nulls last,
      filtered.id
    limit v_limit
    offset v_offset
  )
  select jsonb_build_object(
    'rows',
    coalesce(
      jsonb_agg(
        _admin_row(
          ordered.id,
          coalesce(ordered.transaction_id, 'Payment event'),
          'MoMo SMS',
          ordered.allocation_status::text,
          coalesce(ordered.amount_rwf::text || ' RWF', ''),
          ordered.created_at,
          jsonb_build_object('collection_id', ordered.collection_id)
        )
        order by ordered.admin_rank
      ),
      '[]'::jsonb
    ),
    'total',
    (select count(*) from filtered)
  )
  into v_result
  from ordered;

  return coalesce(v_result, jsonb_build_object('rows', '[]'::jsonb, 'total', 0));
end;
$$;

create or replace function admin_list_allocations(
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
begin
  perform assert_admin_permission('payment_events.read');
  return admin_list_payment_events(
    p_search,
    coalesce(p_status, 'allocated'),
    p_limit,
    p_offset,
    p_sort
  );
end;
$$;

create or replace function admin_list_unallocated(
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
  v_sort text := coalesce(nullif(p_sort, ''), 'created_at_desc');
  v_result jsonb;
begin
  perform assert_admin_permission('payment_events.read');
  if v_sort not in (
    'created_at_desc',
    'created_at_asc',
    'amount_desc',
    'amount_asc'
  ) then
    v_sort := 'created_at_desc';
  end if;

  with filtered as (
    select e.*
    from parsed_payment_events e
    where (
      (
        p_status is null
        and e.allocation_status in ('unallocated', 'ambiguous', 'needs_review')
      )
      or (
        p_status is not null
        and e.allocation_status::text = p_status
      )
    )
    and (
      p_search is null
      or e.transaction_id ilike '%' || p_search || '%'
    )
  ),
  ordered as (
    select
      filtered.*,
      row_number() over (
        order by
          case when v_sort = 'created_at_asc' then filtered.created_at end asc nulls last,
          case when v_sort = 'created_at_desc' then filtered.created_at end desc nulls last,
          case when v_sort = 'amount_asc' then filtered.amount_rwf end asc nulls last,
          case when v_sort = 'amount_desc' then filtered.amount_rwf end desc nulls last,
          filtered.created_at desc nulls last,
          filtered.id
      ) as admin_rank
    from filtered
    order by
      case when v_sort = 'created_at_asc' then filtered.created_at end asc nulls last,
      case when v_sort = 'created_at_desc' then filtered.created_at end desc nulls last,
      case when v_sort = 'amount_asc' then filtered.amount_rwf end asc nulls last,
      case when v_sort = 'amount_desc' then filtered.amount_rwf end desc nulls last,
      filtered.created_at desc nulls last,
      filtered.id
    limit v_limit
    offset v_offset
  )
  select jsonb_build_object(
    'rows',
    coalesce(
      jsonb_agg(
        _admin_row(
          ordered.id,
          coalesce(ordered.transaction_id, 'Payment event'),
          'MoMo SMS',
          ordered.allocation_status::text,
          coalesce(ordered.amount_rwf::text || ' RWF', ''),
          ordered.created_at,
          jsonb_build_object('collection_id', ordered.collection_id)
        )
        order by ordered.admin_rank
      ),
      '[]'::jsonb
    ),
    'total',
    (select count(*) from filtered)
  )
  into v_result
  from ordered;

  return coalesce(v_result, jsonb_build_object('rows', '[]'::jsonb, 'total', 0));
end;
$$;

grant execute on function admin_list_payment_events(text, text, integer, integer, text) to authenticated;
grant execute on function admin_list_allocations(text, text, integer, integer, text) to authenticated;
grant execute on function admin_list_unallocated(text, text, integer, integer, text) to authenticated;
