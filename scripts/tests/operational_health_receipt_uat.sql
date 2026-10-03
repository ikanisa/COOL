-- Capture the installed150 health API through real approved Auth authority.
-- Rollback-only synthetic actor; no sender, scheduler, token or provider call.
begin;
set local statement_timeout='30s';
set local lock_timeout='5s';
do $$ begin
 if current_user<>'postgres' or current_database()<>'postgres'
  or current_setting('collect.operational_health_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off'
  or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>150
  or (select max(version) from supabase_migrations.schema_migrations)<>'20260930180000'
  or exists(select 1 from auth.users where id::text like '99921000-%' or phone='250788992101') then
  raise exception 'Exact quiet offline150 fixture required';end if;
end $$;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
 values('99921000-0000-4000-8000-000000000001','authenticated','authenticated','250788992101',now(),'{}','{}');
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
 values('99921000-0000-4000-8000-000000000001','+250788992101',clock_timestamp()-interval '2 minutes','Synthetic health receipt approval');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
 select '99921000-0000-4000-8000-000000000001',id,'Synthetic health receipt grant',clock_timestamp()-interval '1 minute'
 from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
 values('99921000-0000-4000-8000-000000000011','99921000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
-- A real recorded receipt makes missing receipt telemetry applicable. An empty
-- queue correctly has no freshness incident and is tested separately in Dart.
insert into public.raw_payment_sms(id,receiver_user_id,raw_sender,raw_body,body_hash,ingested_at,parse_status)
 values('99921000-0000-4000-8000-000000000021','99921000-0000-4000-8000-000000000001',
 'private-health-receipt-canary','private-health-receipt-canary',
 encode(extensions.digest('private-health-receipt-canary','sha256'),'hex'),clock_timestamp(),'parsed');
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal1',
 'sub','99921000-0000-4000-8000-000000000001','session_id','99921000-0000-4000-8000-000000000011',
 'exp',floor(extract(epoch from clock_timestamp()))::bigint+3600)::text,true);
do $$declare sample jsonb:=public.admin_system_health();begin
 if (select count(*) from jsonb_object_keys(sample))<>19
  or (select count(*) from jsonb_object_keys(sample->'metrics'))<>31
  or jsonb_array_length(sample->'alerts')<>13
  or sample->>'auth'<>'authenticated' or sample->>'contract_version'<>'1'
  or (sample->'metrics'->>'durable_receipts_24h')::bigint<1
  or sample->>'health_status'<>'unknown'
  or sample::text ~ 'private-health-receipt-canary|99921000|250788992101|raw_body|raw_sender|provider_message_id|token_hash' then
  raise exception 'Actual health receipt shape or redaction failed';end if;
 raise notice 'HEALTH_RECEIPT_JSON|%',sample;
end $$;
reset role;
rollback;
