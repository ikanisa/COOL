\set ON_ERROR_STOP on
\if :{?bench_intents}
\else
\set bench_intents 1000
\endif
-- Performance and visibility rehearsal only. Synthetic intents are loaded
-- without user triggers in a rollback transaction on the task-owned restore.
begin;
set local statement_timeout = '180s';
select set_config('collect.bench_intents', :'bench_intents', true) \gset
do $$ begin
  if current_database() <> 'collect_financial_restore_empty_20260928'
     or current_setting('collect.bench_intents')::int not between 100 and 20000
     or current_setting('cron.launch_active_jobs') <> 'off'
     or current_setting('pg_net.database_name') <> 'template1'
     or (select count(*) from supabase_migrations.schema_migrations) <> 133
     or (select count(*) from auth.users) <> 1
     or (select count(*) from public.payment_intents) <> 1
     or (select count(*) from public.payments) <> 2
     or exists (select 1 from pg_trigger
       where tgrelid = 'public.payment_intents'::regclass
         and not tgisinternal and tgenabled <> 'O') then
    raise exception 'Exact isolated restored financial fixture required';
  end if;
end $$;

alter table public.payment_intents disable trigger user;
insert into public.payment_intents(
  id, collection_id, contributor_user_id, contribution_code,
  expected_amount_rwf, receiver_momo_number_hash, sender_phone_hash,
  status, anonymity_choice, created_at, expires_at
)
select ('99500000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '99300000-0000-4000-8000-000000000010'::uuid,
  '99100000-0000-4000-8000-000000000001'::uuid,
  'SYNTH-INTENT-' || n,
  500 + n,
  profile.momo_number_hash, profile.momo_number_hash,
  case when n % 3 = 0 then 'cancelled'::public.payment_intent_status
    else 'pending'::public.payment_intent_status end,
  'anonymous', now() - make_interval(secs => n),
  case when n % 5 = 0 then now() - interval '1 minute'
    else now() + interval '1 hour' end
from generate_series(1, current_setting('collect.bench_intents')::int) n
cross join public.profiles profile
where profile.id = '99100000-0000-4000-8000-000000000001';
alter table public.payment_intents enable trigger user;
analyze public.payment_intents;

create temp table benchmark_expected(pending_count bigint not null);
grant select on pg_temp.benchmark_expected to authenticated;
insert into pg_temp.benchmark_expected
select count(*) from public.payment_intents intent
where intent.contributor_user_id = '99100000-0000-4000-8000-000000000001'
  and intent.status = 'pending' and intent.expires_at > now();
do $$ begin
  if (select count(*) from public.payment_intents) <>
       current_setting('collect.bench_intents')::int + 1
     or (select pending_count from pg_temp.benchmark_expected) <= 50
     or exists (select 1 from pg_trigger
       where tgrelid = 'public.payment_intents'::regclass
         and not tgisinternal and tgenabled <> 'O') then
    raise exception 'Intent benchmark seed or trigger-state invariant failed';
  end if;
end $$;

insert into auth.users(
  id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '99100000-0000-4000-8000-000000000004',
  'authenticated', 'authenticated', '250788991004', now(), '{}', '{}'
);

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
\echo BENCHMARK_INTENTS :bench_intents
with result as materialized (
  select public.list_current_member_recent_intents(null) doc
)
select 'recent-50' as case_name,
  jsonb_array_length(doc->'items') as items,
  (doc->>'pending_count')::bigint as pending_count,
  (select pending_count from pg_temp.benchmark_expected) as expected_pending,
  exists(select 1 from jsonb_array_elements(doc->'items') item
    where item->>'id' = '99500000-0000-4000-8000-000000000050') as includes_50,
  exists(select 1 from jsonb_array_elements(doc->'items') item
    where item->>'id' = '99500000-0000-4000-8000-000000000051') as includes_51,
  exists(select 1 from jsonb_array_elements(doc->'items') item
    where item->>'id' = '99500000-0000-4000-8000-000000000005'
      and item->>'status' = 'expired') as expired_visible,
  doc->'items'->0->>'network' = 'mtn_momo' as receiver_resolved
from result;

with result as materialized (
  select public.list_current_member_recent_intents(
    ('99500000-0000-4000-8000-' ||
      lpad(current_setting('collect.bench_intents'), 12, '0'))::uuid) doc
)
select 'exact-old-id' as case_name,
  jsonb_array_length(doc->'items') as items,
  (doc->>'pending_count')::bigint as pending_count,
  (select pending_count from pg_temp.benchmark_expected) as expected_pending
from result;

with result as materialized (
  select public.list_current_member_recent_intents(
    '99500000-0000-4000-8000-999999999999'::uuid) doc
)
select 'missing-id' as case_name,
  jsonb_array_length(doc->'items') as items,
  (doc->>'pending_count')::bigint as pending_count,
  (select pending_count from pg_temp.benchmark_expected) as expected_pending
from result;

select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000004",'
  || '"role":"authenticated"}', true) \gset
with result as materialized (
  select public.list_current_member_recent_intents(null) doc
)
select 'other-member-recent' as case_name,
  jsonb_array_length(doc->'items') as items,
  (doc->>'pending_count')::bigint as pending_count
from result;
with result as materialized (
  select public.list_current_member_recent_intents(
    ('99500000-0000-4000-8000-' ||
      lpad(current_setting('collect.bench_intents'), 12, '0'))::uuid) doc
)
select 'other-member-exact' as case_name,
  jsonb_array_length(doc->'items') as items,
  (doc->>'pending_count')::bigint as pending_count
from result;
\timing off
reset role;
set auto_explain.log_min_duration = '10s';
rollback;
