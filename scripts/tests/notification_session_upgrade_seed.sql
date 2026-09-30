\set ON_ERROR_STOP on
-- Seed one real Auth session plus an intentionally unbound140 token. The141
-- migration must disable it rather than guessing that this session owns it.
begin;
do $$ begin
  if current_setting('collect.notification_qa',true) is distinct from 'isolated_clone'
    or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
    or (select count(*) from supabase_migrations.schema_migrations)<>140
    or (select max(version) from supabase_migrations.schema_migrations)<>'20260929170000'
    or exists(select 1 from public.notification_device_tokens)
    or exists(select 1 from public.notification_deliveries)
    or exists(select 1 from auth.users where id::text like '99720000-%')
    or exists(select 1 from collect_hybrid.member_records where id::text like '99720000-%') then
    raise exception 'Guarded empty synthetic140 fixture required'; end if;
end $$;
-- Preserve exact original telemetry plus this transaction's provenance for a
-- future fresh140→141 run. Never replay this seed on the current cleaned141.
create temp table notification_upgrade_telemetry_baseline on commit drop as
  select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]'::jsonb) as body
  from public.app_realtime_events e;
create table public.notification_session_upgrade_qa(delivery_id uuid,claim_token uuid,attempt_number integer,
  claim_expires_at timestamptz,seed_xid text not null,telemetry_baseline jsonb not null,
  seed_telemetry_ids uuid[] not null default '{}');
revoke all on public.notification_session_upgrade_qa from public,anon,authenticated,service_role;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99720000-0000-4000-8000-000000000001','authenticated','authenticated','250788927001',now(),'{}','{}');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99720000-0000-4000-8000-000000000101','99720000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1');
insert into public.notification_device_tokens(id,user_id,platform,provider,token,token_hash,environment)
values('99720000-0000-4000-8000-000000000010','99720000-0000-4000-8000-000000000001','android','fcm',
  'synthetic-session-upgrade-token',encode(extensions.digest('synthetic-session-upgrade-token','sha256'),'hex'),'production');
insert into public.notification_events(id,user_id,type,title,body)
values('99720000-0000-4000-8000-000000000020','99720000-0000-4000-8000-000000000001','group_update','Private synthetic title','Private synthetic body');
insert into public.notification_session_upgrade_qa(delivery_id,claim_token,attempt_number,seed_xid,telemetry_baseline)
select delivery_id,claim_token,attempt_number,pg_current_xact_id()::text,
  (select body from pg_temp.notification_upgrade_telemetry_baseline)
from public.claim_notification_deliveries(2,1);
update public.notification_session_upgrade_qa q set claim_expires_at=d.claim_expires_at
from public.notification_deliveries d where d.id=q.delivery_id;
do $$ begin
  if (select count(*) from public.notification_session_upgrade_qa)<>1 then raise exception 'Live140 claim was not seeded'; end if;
end $$;
update public.notification_session_upgrade_qa q set seed_telemetry_ids=array(
  select e.id from public.app_realtime_events e where e.xmin::text=q.seed_xid
    and not exists(select 1 from jsonb_array_elements(q.telemetry_baseline) b where b->>'id'=e.id::text)
  order by e.id);
select 'NOTIFICATION_SESSION_UPGRADE_TRACE:'||jsonb_build_object('phase','seed','xid',q.seed_xid,
  'baseline_rows',jsonb_array_length(q.telemetry_baseline),
  'events',(select jsonb_agg(jsonb_build_object('row',to_jsonb(e),'xmin',e.xmin::text) order by e.id)
    from public.app_realtime_events e where e.id=any(q.seed_telemetry_ids)))::text
from public.notification_session_upgrade_qa q;
commit;
