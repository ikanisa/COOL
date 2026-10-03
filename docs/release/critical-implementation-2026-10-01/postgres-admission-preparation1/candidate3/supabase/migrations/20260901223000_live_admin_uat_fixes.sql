begin;

-- Keep the public catalogue identity separate from the immutable official
-- receiver identity: the group is Gikundiro and the payee is Rayon Sports FC.
do $$
declare
  gikundiro_id uuid;
begin
  select collection.id
  into gikundiro_id
  from public.collections collection
  join public.collection_receivers receiver
    on receiver.collection_id = collection.id
   and receiver.is_active
  where collection.is_platform_sponsored
    and receiver.momo_number = '008000'
  order by collection.created_at, collection.id
  limit 1;

  if gikundiro_id is null then
    raise exception 'The official Gikundiro receiver route is missing';
  end if;

  if exists (
    select 1
    from public.collections collection
    where collection.slug = 'gikundiro'
      and collection.id <> gikundiro_id
  ) then
    raise exception 'The reserved Gikundiro slug is already assigned to another group';
  end if;

  update public.collections
  set slug = 'gikundiro',
      title = 'Gikundiro',
      description = 'Official Rayon Sports supporter group open to everyone.',
      category = 'Sports team',
      visibility = 'public_approved',
      public_status = 'public_approved',
      receiver_display_label = 'Rayon Sports FC',
      collection_type = 'sport',
      category_subtype = 'team_support',
      purpose_label = 'Team support',
      moderation_status = 'approved',
      diaspora_enabled = false,
      diaspora_regions = '{}'::text[],
      is_platform_sponsored = true,
      archived_at = null,
      updated_at = now()
  where id = gikundiro_id;

  update public.collection_receivers
  set network = 'mtn_momo',
      label = 'Rayon Sports FC',
      is_active = true
  where collection_id = gikundiro_id
    and momo_number = '008000';
end;
$$;

-- PostgreSQL names an unaliased UNION expression "?column?". The Admin
-- ledger projection consumes the stable `amount` key, so every unified column
-- is named explicitly before filtering and JSON aggregation.
create or replace function public.admin_list_collect_ledgers(
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
declare result jsonb;
begin
  perform public.assert_admin_permission('ledger.read');

  with unified as (
    select
      'momo:' || payment.id::text as id,
      coalesce(payment.transaction_id, 'Rwanda allocation ' || right(payment.id::text, 8)) as title,
      'Rwanda · payment clearing debit · group/member allocation credit' as subtitle,
      case when ledger.collection_credit = payment.amount_rwf
          and ledger.member_credit = payment.amount_rwf
        then 'balanced' else 'exception' end as status,
      ('RWF ' || to_char(payment.amount_rwf, 'FM999G999G999G999') || ' =') as amount,
      payment.created_at as created_at,
      jsonb_build_object(
        'rail', 'rw_momo',
        'payment_id', payment.id,
        'collection_id', payment.collection_id,
        'debit_total', payment.amount_rwf,
        'credit_total', least(ledger.collection_credit, ledger.member_credit),
        'currency', 'RWF',
        'line_count', ledger.line_count
      ) as extra
    from public.payments payment
    join lateral (
      select
        coalesce(sum(entry.amount_rwf) filter (where entry.entry_type = 'collection_credit'), 0) as collection_credit,
        coalesce(sum(entry.amount_rwf) filter (where entry.entry_type = 'member_credit'), 0) as member_credit,
        count(*) as line_count
      from public.ledger_entries entry
      where entry.payment_id = payment.id
    ) ledger on true

    union all

    select
      'diaspora:' || journal.id::text as id,
      coalesce(journal.external_reference, 'Diaspora journal ' || right(journal.id::text, 8)) as title,
      ('Diaspora · ' || journal.description) as subtitle,
      case when totals.debit_total = totals.credit_total and totals.debit_total > 0
        then 'balanced' else 'exception' end as status,
      (journal.currency || ' ' ||
        to_char(totals.debit_total::numeric / 100, 'FM999G999G999D00') || ' =') as amount,
      journal.posted_at as created_at,
      jsonb_build_object(
        'rail', 'diaspora_account',
        'journal_entry_id', journal.id,
        'transaction_id', journal.bank_transaction_id,
        'collection_id', journal.collection_id,
        'debit_total', totals.debit_total,
        'credit_total', totals.credit_total,
        'currency', journal.currency,
        'line_count', totals.line_count
      ) as extra
    from public.journal_entries journal
    join lateral (
      select
        coalesce(sum(line.amount_minor) filter (where line.direction = 'debit'), 0) as debit_total,
        coalesce(sum(line.amount_minor) filter (where line.direction = 'credit'), 0) as credit_total,
        count(*) as line_count
      from public.journal_lines line
      where line.journal_entry_id = journal.id
    ) totals on true
  ), filtered as (
    select *
    from unified
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or subtitle ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'title', title,
        'subtitle', subtitle,
        'status', status,
        'amount', amount,
        'created_at', created_at
      ) || extra
      order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  )
  into result
  from counted;

  return result;
end;
$$;

comment on function public.admin_list_collect_ledgers(text, text, integer, integer, text) is
  'Country-aware Collect ledger queue with explicit stable JSON projection names.';

commit;
