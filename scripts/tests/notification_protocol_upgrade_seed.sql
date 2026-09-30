\set ON_ERROR_STOP on
-- Synthetic-only root-owned fixture. Run on guarded138, then apply139 and run
-- notification_protocol_upgrade_verify.sql. No provider/network invocation.
begin;
do $$ begin
  if current_setting('collect.notification_qa', true) is distinct from 'isolated_clone'
    or current_setting('cron.launch_active_jobs') <> 'off'
    or current_setting('pg_net.batch_size') <> '0'
    or (select count(*) from supabase_migrations.schema_migrations) <> 138
    or (select max(version) from supabase_migrations.schema_migrations) <> '20260929150000'
    or exists(select 1 from public.notification_deliveries)
    or exists(select 1 from public.notification_device_tokens)
    or exists(select 1 from auth.users where id::text like '99890000-%')
    or exists(select 1 from collect_hybrid.member_records where id::text like '99890000-%') then
    raise exception 'Guarded empty synthetic138 fixture required';
  end if;
end $$;
create table public.notification_protocol_upgrade_qa (delivery_id uuid, claim_token uuid, attempt_number integer, expires_at timestamptz);
revoke all on public.notification_protocol_upgrade_qa from public, anon, authenticated, service_role;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99890000-0000-4000-8000-000000000001','authenticated','authenticated','250788909001',now(),'{}','{}');
insert into public.notification_device_tokens(id,user_id,platform,provider,token,token_hash,environment)
values('99890000-0000-4000-8000-000000000010','99890000-0000-4000-8000-000000000001',
  'android','fcm','synthetic-upgrade-token',encode(extensions.digest('synthetic-upgrade-token','sha256'),'hex'),'production');
insert into public.notification_events(id,user_id,type,title,body)
values('99890000-0000-4000-8000-000000000020','99890000-0000-4000-8000-000000000001','group_update','Private synthetic title','Private synthetic body');
insert into public.notification_protocol_upgrade_qa(delivery_id,claim_token,attempt_number)
select delivery_id,claim_token,attempt_number from public.claim_notification_deliveries(1,1);
update public.notification_protocol_upgrade_qa q set expires_at=d.claim_expires_at
from public.notification_deliveries d where d.id=q.delivery_id;
do $$ begin
  if (select count(*) from public.notification_protocol_upgrade_qa) <> 1 then raise exception 'Upgrade seed missing live v1 claim'; end if;
end $$;
commit;
