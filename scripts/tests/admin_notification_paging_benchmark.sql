\set ON_ERROR_STOP on
\if :{?bench_events}
\else
\set bench_events 1000
\endif
-- Full-schema read-plan rehearsal only; every synthetic row rolls back.
begin;
set local statement_timeout = '180s';
select set_config('collect.bench_events', :'bench_events', true) \gset
do $$ begin
  if current_database() <> 'collect_financial_restore_empty_20260928'
     or current_setting('collect.bench_events')::int not between 100 and 20000
     or current_setting('cron.launch_active_jobs') <> 'off'
     or current_setting('pg_net.database_name') <> 'template1'
     or (select count(*) from supabase_migrations.schema_migrations) <> 133
     or (select count(*) from auth.users) <> 1
     or (select count(*) from public.notification_events) <> 1
     or (select count(*) from public.notification_deliveries) <> 0
     or (select count(*) from public.admin_user_roles link
         join public.admin_roles role on role.id=link.role_id
         where link.user_id='99100000-0000-4000-8000-000000000001'::uuid
           and role.name='platform_owner' and link.revoked_at is null) <> 1 then
    raise exception 'Exact isolated restored financial fixture required';
  end if;
end $$;

alter table public.notification_events disable trigger user;
insert into public.notification_events(
  id,user_id,collection_id,type,title,body,status,created_at
)
select ('99800000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  '99100000-0000-4000-8000-000000000001'::uuid,
  '99300000-0000-4000-8000-000000000010'::uuid,
  'group_update','Synthetic notification '||n,'Synthetic body '||n,
  case when n%3=0 then 'failed' else 'sent' end,
  now()-make_interval(secs=>n)
from generate_series(1,current_setting('collect.bench_events')::int) n;
alter table public.notification_events enable trigger user;

insert into public.notification_device_tokens(
  id,user_id,platform,token_hash,enabled
) values (
  '99810000-0000-4000-8000-000000000001',
  '99100000-0000-4000-8000-000000000001',
  'android',repeat('c',64),true
);
alter table public.notification_deliveries disable trigger user;
insert into public.notification_deliveries(
  id,event_id,device_id,status,attempt_count,next_attempt_at,created_at
)
select ('99820000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  ('99800000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  '99810000-0000-4000-8000-000000000001'::uuid,
  case when n%3=0 then 'failed' else 'sent' end,
  1,now(),now()-make_interval(secs=>n)
from generate_series(1,current_setting('collect.bench_events')::int) n;
alter table public.notification_deliveries enable trigger user;
analyze public.notification_events;
analyze public.notification_deliveries;

insert into collect_admin_access.whatsapp_approvals(
  user_id,phone_e164,approved_at,approved_by,reason
) values (
  '99100000-0000-4000-8000-000000000001', '+250788991001',
  now()-interval '2 seconds',
  '99100000-0000-4000-8000-000000000001',
  'Synthetic notification plan benchmark'
);
insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
values (
  '99830000-0000-4000-8000-000000000001',
  '99100000-0000-4000-8000-000000000001',
  now()-interval '1 second',now(),now()+interval '1 hour'
);

-- BEFORE_RPC_BENCHMARK
set client_min_messages=log;
set auto_explain.log_min_duration='0ms';
set auto_explain.log_analyze=on;
set auto_explain.log_buffers=on;
set auto_explain.log_nested_statements=on;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000001",'
  || '"role":"authenticated",'
  || '"session_id":"99830000-0000-4000-8000-000000000001"}',true) \gset
\timing on
\echo BENCHMARK_NOTIFICATION_EVENTS :bench_events
with result as materialized (
  select public.admin_list_notifications(null,null,25,0,'created_at_desc') doc
)
select 'first-desc' case_name, jsonb_array_length(doc->'rows') items,
  (doc->>'total')::bigint total from result;
with result as materialized (
  select public.admin_list_notifications(null,'failed',25,0,'created_at_asc') doc
)
select 'failed-asc' case_name, jsonb_array_length(doc->'rows') items,
  (doc->>'total')::bigint total from result;
with result as materialized (
  select public.admin_list_notifications(null,null,25,
    current_setting('collect.bench_events')::int-25,'created_at_desc') doc
)
select 'deep-desc' case_name, jsonb_array_length(doc->'rows') items,
  (doc->>'total')::bigint total from result;
\timing off
reset role;
set auto_explain.log_min_duration='10s';
rollback;
