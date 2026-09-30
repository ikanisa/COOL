\set ON_ERROR_STOP on
-- Execute only against the task-owned empty-target restore upgraded 133 -> 134.
-- Synthetic Admin approval/session rows and all queries roll back.
begin;
set local statement_timeout = '30s';
do $$ begin
  if current_database() <> 'collect_notification_upgrade_20260929'
     or current_setting('cron.launch_active_jobs') <> 'off'
     or current_setting('cron.database_name') not in ('postgres', current_database())
     or current_setting('pg_net.database_name') <> 'template1'
     or current_setting('pg_net.batch_size') <> '0'
     or (select count(*) from supabase_migrations.schema_migrations) <> 134
     or (select max(version) from supabase_migrations.schema_migrations) <> '20260929110000'
     or (select count(*) from public.notification_events) <> 1
     or (select count(*) from public.notification_deliveries) <> 0
     or (select count(*) from public.admin_user_roles link
         join public.admin_roles role on role.id = link.role_id
         where link.user_id = '99100000-0000-4000-8000-000000000001'::uuid
           and role.name = 'platform_owner' and link.revoked_at is null) <> 1
     or has_function_privilege('anon',
          'public.admin_list_notifications(text,text,integer,integer,text)',
          'EXECUTE')
     or not has_function_privilege('authenticated',
          'public.admin_list_notifications(text,text,integer,integer,text)',
          'EXECUTE')
     or (select count(*) from pg_indexes
         where schemaname = 'public' and tablename = 'notification_events'
           and indexname in ('notification_events_admin_created_idx',
                             'notification_events_admin_status_created_idx')) <> 2 then
    raise exception 'Exact historical 134 notification fixture required';
  end if;
end $$;

insert into collect_admin_access.whatsapp_approvals(
  user_id, phone_e164, approved_at, approved_by, reason
) values (
  '99100000-0000-4000-8000-000000000001', '+250788991001',
  now() - interval '2 seconds',
  '99100000-0000-4000-8000-000000000001',
  'Synthetic historical notification upgrade check'
);
insert into auth.sessions(id, user_id, created_at, updated_at, not_after)
values (
  '99830000-0000-4000-8000-000000000001',
  '99100000-0000-4000-8000-000000000001',
  now() - interval '1 second', now(), now() + interval '1 hour'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000001",'
  || '"role":"authenticated",'
  || '"session_id":"99830000-0000-4000-8000-000000000001"}', true) \gset
do $$
declare
  first_page jsonb := public.admin_list_notifications(null, null, 25, 0,
    'created_at_desc');
  empty_page jsonb := public.admin_list_notifications(null, null, 25, 100,
    'created_at_desc');
  filtered_page jsonb := public.admin_list_notifications(null, 'unknown', 25, 0,
    'created_at_desc');
begin
  if first_page->>'total' <> '1'
     or jsonb_array_length(first_page->'rows') <> 1
     or empty_page->>'total' <> '1'
     or jsonb_array_length(empty_page->'rows') <> 0
     or filtered_page->>'total' <> '0'
     or jsonb_array_length(filtered_page->'rows') <> 0 then
    raise exception 'Historical Admin notification page result changed';
  end if;
end $$;
reset role;
\echo HISTORICAL_NOTIFICATION_134_UAT_PASS: 3 pages, grants and indexes
rollback;
