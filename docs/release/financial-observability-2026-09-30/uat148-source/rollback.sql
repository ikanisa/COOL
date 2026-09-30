begin;
set local collect.operational_health_qa='isolated_clone';
do $$ begin if (select count(*) from supabase_migrations.schema_migrations)<>148 or (select max(version) from supabase_migrations.schema_migrations)<>'20260930160000' then raise exception 'Exact148 required';end if;end $$;
-- Root recorder must validate exact isolated Docker/55722 identity first.
-- Run in the same rollback transaction as reviewed148 migration body on146,
-- or inside a guarded rollback transaction after the final148 owner apply.
set local statement_timeout='30s';
set local lock_timeout='5s';
do $$ begin
 if current_database()<>'postgres' or current_user<>'postgres'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or current_setting('collect.operational_health_qa',true) is distinct from 'isolated_clone'
  or exists(select 1 from auth.users where id::text like '99680000-%' or phone='250788968001') then
  raise exception 'Quiet isolated operational-health fixture required';end if;
end $$;
create temp table health_assertions(name text primary key);
create function pg_temp.health_assert(name text,ok boolean) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Health assertion failed: %',name;end if;
 insert into health_assertions values(name);end $$;
create function pg_temp.health_error(name text,statement text,expected text) returns void language plpgsql as $$
begin begin execute statement;exception when others then
 if sqlstate is distinct from expected then raise exception 'Unexpected health rejection SQLSTATE %',sqlstate;end if;
 perform pg_temp.health_assert(name,true);return;end;
 raise exception 'Expected health rejection: %',name;end $$;
grant all on health_assertions to authenticated,service_role,anon;
grant execute on function pg_temp.health_assert(text,boolean),pg_temp.health_error(text,text,text) to authenticated,service_role,anon;
do $$ begin execute format('grant usage on schema %I to authenticated,service_role,anon',pg_my_temp_schema()::regnamespace::text);end $$;

select pg_temp.health_assert('private metric table RLS', (select relrowsecurity from pg_class where oid='collect_security.operational_metric_buckets'::regclass));
select pg_temp.health_assert('no raw metric table API grant', not has_table_privilege('anon','collect_security.operational_metric_buckets','SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('authenticated','collect_security.operational_metric_buckets','SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('service_role','collect_security.operational_metric_buckets','SELECT,INSERT,UPDATE,DELETE'));
select pg_temp.health_assert('private purge denies service',not has_function_privilege('service_role','collect_security.purge_operational_metrics(integer)','EXECUTE'));
select pg_temp.health_assert('alert evaluator denies all API roles',not has_function_privilege('anon','collect_security.operational_health_alerts(jsonb)','EXECUTE')
 and not has_function_privilege('authenticated','collect_security.operational_health_alerts(jsonb)','EXECUTE')
 and not has_function_privilege('service_role','collect_security.operational_health_alerts(jsonb)','EXECUTE'));
select pg_temp.health_assert('absent health is unknown',(select bool_and(a->>'state'='unknown') from jsonb_array_elements(collect_security.operational_health_alerts('{}')) a));
select pg_temp.health_assert('empty queue age not applicable',(select a->>'state'='not_applicable' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_due":0}')) a where a->>'code'='push_queue_age'));
select pg_temp.health_assert('pending without age unknown',(select a->>'state'='unknown' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_due":1}')) a where a->>'code'='push_queue_age'));
select pg_temp.health_assert('age below threshold ok',(select a->>'state'='ok' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_due":1,"push_due_age_seconds":119}')) a where a->>'code'='push_queue_age'));
select pg_temp.health_assert('exact age threshold alerts',(select a->>'state'='attention' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_due":1,"push_due_age_seconds":120}')) a where a->>'code'='push_queue_age'));
select pg_temp.health_assert('expired lease alerts',(select a->>'state'='attention' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_expired_leases":1}')) a where a->>'code'='push_expired_lease'));
select pg_temp.health_assert('stale telemetry alerts',(select a->>'state'='attention' from jsonb_array_elements(collect_security.operational_health_alerts('{"durable_receipts_24h":1,"receipt_telemetry_age_seconds":300}')) a where a->>'code'='receipt_telemetry_stale'));
select pg_temp.health_error('null metrics denied','select collect_security.operational_health_alerts(null)','22023');
select pg_temp.health_error('negative counters denied','select collect_security.operational_health_alerts(''{"sms_pending":-1}'')','22023');
select pg_temp.health_error('string counters denied','select collect_security.operational_health_alerts(''{"sms_pending":"100"}'')','22023');
select pg_temp.health_error('fraction counters denied','select collect_security.operational_health_alerts(''{"sms_pending":1.5}'')','22023');
select pg_temp.health_error('unsafe counters denied','select collect_security.operational_health_alerts(''{"sms_pending":9007199254740992}'')','22023');

set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select pg_temp.health_error('anonymous telemetry denied','select public.record_operational_metric_v1(''receipt_ack_generated'',5)','42501');
select pg_temp.health_error('anonymous health denied','select public.admin_system_health()','42501');
reset role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.health_assert('service bounded sample', public.record_operational_metric_v1('receipt_ack_generated',12));
select pg_temp.health_assert('service unmeasured sample',public.record_operational_metric_v1('receipt_ack_generated',null));
select pg_temp.health_error('arbitrary diagnostic text denied','select public.record_operational_metric_v1(''secret-canary-phone-250788968001'',1)','22023');
select pg_temp.health_error('missing event denied','select public.record_operational_metric_v1(null,1)','22023');
select pg_temp.health_error('negative duration denied','select public.record_operational_metric_v1(''receipt_ack_generated'',-1)','22023');
select pg_temp.health_error('unbounded duration denied','select public.record_operational_metric_v1(''receipt_ack_generated'',120001)','22023');
select pg_temp.health_error('service health read denied','select public.admin_system_health()','42501');
reset role;
select pg_temp.health_assert('measured versus missing duration distinct',exists(select 1 from collect_security.operational_metric_buckets
 where event_code='receipt_ack_generated' and event_count=2 and measured_count=1 and duration_total_ms=12 and duration_max_ms=12));

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99680000-0000-4000-8000-000000000001','authenticated','authenticated','250788968001',now(),'{}','{}');
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99680000-0000-4000-8000-000000000001','+250788968001',now()-interval '2 minutes','Synthetic health fixture identity');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99680000-0000-4000-8000-000000000001',id,'Synthetic health fixture role',now()-interval '1 minute'
from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99680000-0000-4000-8000-000000000011','99680000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1');
insert into public.raw_payment_sms(id,receiver_user_id,raw_sender,raw_body,body_hash,ingested_at)
values('99680000-0000-4000-8000-000000000101','99680000-0000-4000-8000-000000000001',
 'secret-sender-canary','secret-body-canary',encode(extensions.digest('secret-body-canary','sha256'),'hex'),now()-interval '6 minutes');
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1","sub":"99680000-0000-4000-8000-000000000001","session_id":"99680000-0000-4000-8000-000000000011"}',true);
create temp table health_receipt as select public.admin_system_health() receipt;
select pg_temp.health_assert('health read schema and freshness', (select receipt->>'id'='system' and receipt->>'contract_version'='1'
 and (receipt->>'sample_valid_until')::timestamptz=(receipt->>'checked_at')::timestamptz+interval '60 seconds' from health_receipt));
select pg_temp.health_assert('actual pending age alerts',(select exists(select 1 from jsonb_array_elements(receipt->'alerts') a
 where a->>'code'='receipt_parse_age' and a->>'state'='attention') from health_receipt));
select pg_temp.health_assert('actual ACK counts and latency',(select receipt->'metrics'->>'receipt_ack_generated_24h'='2'
 and receipt->'metrics'->>'receipt_ack_latency_mean_ms'='12' from health_receipt));
select pg_temp.health_assert('no private source facts',(select receipt::text !~ 'secret-|250788968001|99680000|raw_body|raw_sender|token_hash|provider_message_id' from health_receipt));
select pg_temp.health_assert('disabled scheduler explicit',(select receipt->'scheduler'->>'state'='disabled'
 and receipt->'scheduler'->>'configuration_verified'='false' from health_receipt));
select pg_temp.health_error('arbitrary caller ID not reflected','select public.admin_system_health(''secret-id-canary'')','22023');
reset role;
delete from public.admin_user_roles where user_id='99680000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.health_error('revoked role denied','select public.admin_system_health()','42501');
reset role;
delete from auth.sessions where id='99680000-0000-4000-8000-000000000011';
set local role authenticated;
select pg_temp.health_error('deleted Auth session denied','select public.admin_system_health()','42501');
reset role;
select pg_temp.health_error('unbounded purge denied','select collect_security.purge_operational_metrics(10001)','22023');
select pg_temp.health_assert('fresh metrics preserved',collect_security.purge_operational_metrics(1)=0);
select 'OPERATIONAL_HEALTH_ASSERTIONS|'||count(*) from health_assertions;
-- Recorder/parent controls rollback and checks all tables, catalog and cron.

rollback;
