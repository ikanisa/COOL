\set ON_ERROR_STOP on
\if :{?bench_rows}
\else
\set bench_rows 1000
\endif
-- Read-plan rehearsal only. Synthetic posted rows deliberately have no provider
-- confirmation or journal; user triggers are disabled inside this transaction.
-- Run solely in the task-owned empty-database restore, never in production.
begin;
set local statement_timeout = '180s';
select set_config('collect.bench_rows', :'bench_rows', true) \gset
do $$ begin
  if current_database() <> 'collect_financial_restore_empty_20260928'
     or current_setting('collect.bench_rows')::int not between 100 and 20000
     or current_setting('cron.launch_active_jobs') <> 'off'
     or current_setting('pg_net.database_name') <> 'template1'
     or (select count(*) from supabase_migrations.schema_migrations) <> 133
     or (select count(*) from auth.users) <> 1
     or (select count(*) from public.payments) <> 2
     or (select count(*) from public.raw_payment_sms) <> 3
     or exists (select 1 from pg_trigger
       where tgrelid = 'public.payments'::regclass
         and not tgisinternal and tgenabled <> 'O') then
    raise exception 'Exact isolated restored financial fixture required';
  end if;
end $$;

alter table public.payments disable trigger user;
insert into public.payments(
  id, collection_id, contributor_user_id, receiver_user_id,
  receiver_momo_number_hash, amount_rwf, currency, transaction_id,
  source, status, anonymity_choice, provider_network, posted_at
)
select ('99400000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  case when n % 2 = 0
    then '99300000-0000-4000-8000-000000000010'::uuid
    else '5bc47df4-6d56-4a83-bd07-c9c5dbc9b6fe'::uuid end,
  '99100000-0000-4000-8000-000000000001'::uuid,
  '99100000-0000-4000-8000-000000000001'::uuid,
  profile.momo_number_hash,
  500 + (n % 37) * 100, 'RWF', 'SYNTH-HISTORY-' || n,
  'import', 'posted', 'anonymous', 'mtn_momo',
  now() - make_interval(secs => n / 3)
from generate_series(1, current_setting('collect.bench_rows')::int) n
cross join public.profiles profile
where profile.id = '99100000-0000-4000-8000-000000000001';
alter table public.payments enable trigger user;
analyze public.payments;

do $$ begin
  if (select count(*) from public.payments) <>
       current_setting('collect.bench_rows')::int + 2
     or (select count(*) from public.ledger_entries) <> 2
     or exists (select 1 from pg_trigger
       where tgrelid = 'public.payments'::regclass
         and not tgisinternal and tgenabled <> 'O') then
    raise exception 'Benchmark seed or trigger-state invariant failed';
  end if;
end $$;

create temp table benchmark_anchors(
  sort_name text not null, scope_name text not null,
  payment_id uuid not null, primary key(sort_name, scope_name)
);
grant select on pg_temp.benchmark_anchors to authenticated;
do $$
declare
  sort_name text;
  scope_name text;
  order_clause text;
  scope_clause text;
  offset_rows integer;
  anchor uuid;
begin
  foreach sort_name in array array['newest','oldest','highest','lowest'] loop
    order_clause := case sort_name
      when 'newest' then 'posted_at desc, id'
      when 'oldest' then 'posted_at, id'
      when 'highest' then 'amount_rwf desc, posted_at desc, id'
      else 'amount_rwf, posted_at desc, id' end;
    foreach scope_name in array array['all','private'] loop
      scope_clause := case scope_name when 'private' then
        'and collection_id = ''99300000-0000-4000-8000-000000000010'''
        else '' end;
      offset_rows := greatest(1, (current_setting('collect.bench_rows')::int
        * case scope_name when 'private' then 0.375 else 0.75 end)::integer);
      execute format(
        'select id from public.payments where status = ''posted'' '
        || 'and currency = ''RWF'' %s order by %s offset %s limit 1',
        scope_clause, order_clause, offset_rows) into anchor;
      if anchor is null then raise exception 'Missing % % deep anchor',
        sort_name, scope_name; end if;
      insert into pg_temp.benchmark_anchors values(sort_name, scope_name, anchor);
    end loop;
  end loop;
end $$;

set client_min_messages = log;
set auto_explain.log_min_duration = '0ms';
set auto_explain.log_analyze = on;
set auto_explain.log_buffers = on;
set auto_explain.log_nested_statements = on;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000001",'
  || '"role":"authenticated"}', true) \gset
\timing on
\echo BENCHMARK_ROWS :bench_rows
with cases(sort_name, scope_name, collection_id) as (values
  ('newest','all',null::uuid),
  ('oldest','all',null::uuid),
  ('highest','all',null::uuid),
  ('lowest','all',null::uuid),
  ('newest','private','99300000-0000-4000-8000-000000000010'::uuid),
  ('oldest','private','99300000-0000-4000-8000-000000000010'::uuid),
  ('highest','private','99300000-0000-4000-8000-000000000010'::uuid),
  ('lowest','private','99300000-0000-4000-8000-000000000010'::uuid)
), first_page as materialized (
  select cases.*,
    public.list_current_member_history_page(
      cases.collection_id, '', cases.sort_name, null, 50) as page
  from cases
), deep_page as materialized (
  select first_page.sort_name, first_page.scope_name,
    public.list_current_member_history_page(
      first_page.collection_id, '', first_page.sort_name,
      jsonb_build_object('revision', first_page.page->>'revision',
        'after', 'momo:' || anchor.payment_id::text), 50) as page
  from first_page
  join pg_temp.benchmark_anchors anchor
    on anchor.sort_name = first_page.sort_name
   and anchor.scope_name = first_page.scope_name
)
select first_page.sort_name, first_page.scope_name,
  (first_page.page->>'total_count')::integer as first_total,
  jsonb_array_length(first_page.page->'items') as first_items,
  (deep_page.page->>'total_count')::integer as deep_total,
  jsonb_array_length(deep_page.page->'items') as deep_items
from first_page join deep_page using(sort_name,scope_name)
order by first_page.scope_name, first_page.sort_name;

with probe as materialized (select public.list_current_member_history_page(
  null, 'synthetic historical savings', 'newest', null, 50) page)
select 'private-title-search' as case_name,
  (page->>'total_count')::integer as total_count,
  jsonb_array_length(page->'items') as page_items
from probe;
with probe as materialized (select public.list_current_member_history_page(
  null, 'no-match-benchmark', 'newest', null, 50) page)
select 'no-match-search' as case_name,
  (page->>'total_count')::integer as total_count,
  jsonb_array_length(page->'items') as page_items
from probe;
\timing off
reset role;
set auto_explain.log_min_duration = '10s';
rollback;
