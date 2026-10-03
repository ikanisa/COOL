-- Actual installed150 API performance, using rollback-only owner fixtures.
-- Disabled synthetic devices have no token; no dispatch/provider is invoked.
begin;
set local statement_timeout='30s';
set local lock_timeout='5s';
do $$ begin
 if current_user<>'postgres' or current_database()<>'postgres'
  or current_setting('collect.operational_health_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>150
  or (select max(version) from supabase_migrations.schema_migrations)<>'20260930180000'
  or exists(select 1 from auth.users where id::text like '99920000-%' or phone='250788992001')
  or exists(select 1 from public.notification_device_tokens)
  or exists(select 1 from public.notification_deliveries) then
  raise exception 'Exact quiet offline150 fixture required';end if;
end $$;
create temp table health_perf_assertions(name text primary key);
create temp table health_perf_runs(volume integer, iteration integer, elapsed_ms numeric, receipt jsonb);
create temp table health_perf_baseline(receipt jsonb);
create temp table health_perf_writer_baseline as select event_code,sum(event_count) events,sum(measured_count) measured,
 sum(duration_total_ms) duration,max(duration_max_ms) maximum from collect_security.operational_metric_buckets group by event_code;
create function pg_temp.perf_assert(p_name text,p_ok boolean) returns void language plpgsql as $$begin
 if p_ok is distinct from true then raise exception 'Health performance assertion failed:%',p_name;end if;
 insert into health_perf_assertions values(p_name);
end $$;
grant all on health_perf_assertions,health_perf_runs,health_perf_baseline to authenticated,service_role;
grant execute on function pg_temp.perf_assert(text,boolean) to authenticated,service_role;
do $$begin execute format('grant usage on schema %I to authenticated,service_role',pg_my_temp_schema()::regnamespace::text);end $$;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
 values('99920000-0000-4000-8000-000000000001','authenticated','authenticated','250788992001',now(),'{}','{}');
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
 values('99920000-0000-4000-8000-000000000001','+250788992001',clock_timestamp()-interval '2 minutes','Synthetic health performance approval');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
 select '99920000-0000-4000-8000-000000000001',id,'Synthetic health performance grant',clock_timestamp()-interval '1 minute'
 from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
 values('99920000-0000-4000-8000-000000000011','99920000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
insert into public.notification_device_tokens(id,user_id,platform,token_hash,enabled)
 values('99920000-0000-4000-8000-000000000012','99920000-0000-4000-8000-000000000001','android',repeat('d',64),false);
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','aal','aal1',
 'sub','99920000-0000-4000-8000-000000000001','session_id','99920000-0000-4000-8000-000000000011',
 'exp',floor(extract(epoch from clock_timestamp()))::bigint+3600)::text,true);
insert into health_perf_baseline select public.admin_system_health();
reset role;
create function pg_temp.perf_seed(p_from integer,p_to integer) returns void language plpgsql as $$begin
 insert into public.raw_payment_sms(id,receiver_user_id,raw_sender,raw_body,body_hash,ingested_at,
  parse_status,parse_started_at,parse_lease_id)
 select ('99920000-0001-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  '99920000-0000-4000-8000-000000000001','private-health-sender-canary',
  'private-health-body-canary-'||n,encode(extensions.digest('private-health-body-canary-'||n,'sha256'),'hex'),
  clock_timestamp()-interval '8 minutes',
  case n%3 when 0 then 'pending' when 1 then 'parsed' else 'failed' end,
  case when n%15=0 then clock_timestamp()-interval '15 minutes' end,
  case when n%15=0 then ('99920000-0009-4000-8000-'||lpad(n::text,12,'0'))::uuid end
 from generate_series(p_from,p_to) n;
 insert into public.parsed_payment_events(id,raw_sms_id,receiver_user_id,allocation_status)
 select ('99920000-0002-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  ('99920000-0001-4000-8000-'||lpad(n::text,12,'0'))::uuid,'99920000-0000-4000-8000-000000000001',
  case n%3 when 0 then 'unallocated'::public.allocation_status when 1 then 'ambiguous'::public.allocation_status else 'needs_review'::public.allocation_status end
 from generate_series(p_from,p_to) n where n%5=0;
 insert into public.notification_events(id,user_id,type,title,body,status)
 select ('99920000-0003-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  '99920000-0000-4000-8000-000000000001','group_update','Synthetic performance event',
  'private-health-notification-canary-'||n,'sent' from generate_series(p_from,p_to) n;
 insert into public.notification_deliveries(id,event_id,device_id,status,next_attempt_at,claim_token,claim_expires_at,claim_user_id)
 select ('99920000-0004-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  ('99920000-0003-4000-8000-'||lpad(n::text,12,'0'))::uuid,'99920000-0000-4000-8000-000000000012',
  case n%4 when 0 then 'queued' when 1 then 'processing' when 2 then 'failed' else 'sent' end,
  clock_timestamp()-interval '5 minutes',
  case when n%8=5 then ('99920000-0008-4000-8000-'||lpad(n::text,12,'0'))::uuid end,
  case when n%8=5 then clock_timestamp()-interval '2 minutes' end,
  case when n%8=5 then '99920000-0000-4000-8000-000000000001'::uuid end
 from generate_series(p_from,p_to) n;
 insert into public.notification_delivery_attempts(id,delivery_id,attempt_number,outcome,latency_ms)
 select ('99920000-0005-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  ('99920000-0004-4000-8000-'||lpad(n::text,12,'0'))::uuid,1,
  case n%3 when 0 then 'failed' when 1 then 'sent' else 'retry' end,n%5000
 from generate_series(p_from,p_to) n;
end $$;
create function pg_temp.health_read_invariant() returns text language plpgsql security definer set search_path='' as $$
declare relation_name text; row_hash text; result text:='';begin
 foreach relation_name in array array[
  'public.payments','public.ledger_entries','collect_hybrid.momo_journal_entries','collect_hybrid.momo_journal_lines',
  'collect_hybrid.collection_balances','collect_hybrid.member_balances',
  'public.raw_payment_sms','public.parsed_payment_events','public.notification_events','public.notification_deliveries',
  'public.notification_delivery_attempts','public.notification_device_tokens',
  'collect_security.operational_metric_buckets','collect_hybrid.roster_import_sources',
  'collect_hybrid.roster_import_revisions','collect_hybrid.roster_import_editor_drafts','collect_hybrid.roster_recovery_transfers'
 ] loop
  execute format('select encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E''\n'' order by to_jsonb(t)::text),''''),''sha256''),''hex'') from %s t',relation_name) into row_hash;
  result:=result||relation_name||':'||row_hash||E'\n';
 end loop;
 return encode(extensions.digest(result,'sha256'),'hex');end $$;
grant execute on function pg_temp.health_read_invariant() to authenticated;
create function pg_temp.perf_read(p_volume integer) returns void language plpgsql as $$
declare started timestamptz; value jsonb; baseline jsonb:=(select receipt->'metrics' from health_perf_baseline);
 before_hash text:=pg_temp.health_read_invariant();
begin
 for n in 1..20 loop
  started:=clock_timestamp();value:=public.admin_system_health();
  insert into health_perf_runs values(p_volume,n,extract(epoch from clock_timestamp()-started)*1000,value);
  if value::text ~ 'private-health-|99920000|250788992001|token_hash|raw_body|raw_sender|provider_message_id' then
   raise exception 'Private source leaked into health sample';end if;
 end loop;
 perform pg_temp.perf_assert(p_volume||':durable-count',(value->'metrics'->>'durable_receipts_24h')::bigint=(baseline->>'durable_receipts_24h')::bigint+p_volume);
 perform pg_temp.perf_assert(p_volume||':pending-count',(value->'metrics'->>'sms_pending')::bigint=(baseline->>'sms_pending')::bigint+p_volume/3);
 perform pg_temp.perf_assert(p_volume||':unmatched-count',(value->'metrics'->>'unallocated_events')::bigint=(baseline->>'unallocated_events')::bigint+p_volume/5);
 perform pg_temp.perf_assert(p_volume||':due-count',(value->'metrics'->>'push_due')::bigint=p_volume/4);
 perform pg_temp.perf_assert(p_volume||':lease-loss-count',(value->'metrics'->>'push_expired_leases')::bigint=p_volume/8);
 perform pg_temp.perf_assert(p_volume||':missing-lease-count',(value->'metrics'->>'push_missing_leases')::bigint=p_volume/8);
 perform pg_temp.perf_assert(p_volume||':p95-local-budget',(select percentile_cont(0.95) within group(order by elapsed_ms)<1000 from health_perf_runs where volume=p_volume));
 perform pg_temp.perf_assert(p_volume||':attention-not-hidden-by-unknown',value->>'health_status'='attention'
  and exists(select 1 from jsonb_array_elements(value->'alerts') a where a->>'state'='unknown'));
 perform pg_temp.perf_assert(p_volume||':safe-disabled-scheduler',value->'scheduler'->>'state'='disabled'
  and value->'scheduler'->>'configuration_verified'='false');
 perform pg_temp.perf_assert(p_volume||':health-reads-preserve-all17-row-families',before_hash=pg_temp.health_read_invariant());
end $$;
grant execute on function pg_temp.perf_read(integer) to authenticated;
select pg_temp.perf_seed(1,1000);
analyze public.raw_payment_sms;analyze public.parsed_payment_events;
analyze public.notification_deliveries;analyze public.notification_delivery_attempts;
set local role authenticated;select pg_temp.perf_read(1000);reset role;
select pg_temp.perf_seed(1001,10000);
analyze public.raw_payment_sms;analyze public.parsed_payment_events;
analyze public.notification_deliveries;analyze public.notification_delivery_attempts;
set local role authenticated;select pg_temp.perf_read(10000);reset role;
select pg_temp.perf_seed(10001,50000);
analyze public.raw_payment_sms;analyze public.parsed_payment_events;
analyze public.notification_deliveries;analyze public.notification_delivery_attempts;
set local role authenticated;select pg_temp.perf_read(50000);reset role;
select pg_temp.perf_assert('all60-health-samples-read-only',(select count(*) from public.raw_payment_sms where id::text like '99920000-%')=50000
 and (select count(*) from public.parsed_payment_events where id::text like '99920000-%')=10000
 and (select count(*) from public.notification_deliveries where id::text like '99920000-%')=50000
 and not exists(select 1 from public.notification_device_tokens where enabled or token is not null));
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$declare started timestamptz:=clock_timestamp();code text;begin
 foreach code in array array['receipt_ack_generated','receipt_rejected','receipt_processing_accepted','receipt_processing_deferred'] loop
  for n in 1..500 loop
   if public.record_operational_metric_v1(code,case when n%2=0 then n end) is distinct from true then
    raise exception 'Metric writer did not acknowledge sample';end if;
  end loop;
 end loop;
 raise notice 'HEALTH_METRIC_WRITER_PERFORMANCE|%',jsonb_build_object('calls',2000,'elapsed_ms',extract(epoch from clock_timestamp()-started)*1000);
end $$;
reset role;
select pg_temp.perf_assert('all4-writer-codes-measured-denominators',(
 select count(*)=4 and bool_and(a.events-coalesce(b.events,0)=500 and a.measured-coalesce(b.measured,0)=250
  and a.duration-coalesce(b.duration,0)=62750 and a.maximum=greatest(coalesce(b.maximum,0),500))
 from (select event_code,sum(event_count) events,sum(measured_count) measured,sum(duration_total_ms) duration,
  max(duration_max_ms) maximum from collect_security.operational_metric_buckets group by event_code) a
 left join health_perf_writer_baseline b using(event_code)));
select 'HEALTH_PERFORMANCE_JSON|'||jsonb_agg(x order by volume)::text from (
 select volume,count(*) samples,min(elapsed_ms) minimum_ms,max(elapsed_ms) maximum_ms,
 percentile_cont(0.5) within group(order by elapsed_ms) p50_ms,
 percentile_cont(0.95) within group(order by elapsed_ms) p95_ms from health_perf_runs group by volume
) x;
select 'HEALTH_PERFORMANCE_ASSERTIONS|'||count(*) from health_perf_assertions;
rollback;
