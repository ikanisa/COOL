\set ON_ERROR_STOP on
begin;
set local statement_timeout='20s';
do $$ begin
  if current_database()<>'collect_fullstack_otp_20260914' then
    raise exception 'Dedicated task-owned OTP clone required';
  end if;
end $$;
create temp table otp_checks(label text primary key);
grant select,insert on otp_checks to authenticated,service_role;
create function pg_temp.check_otp(ok boolean,label text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %',label; end if;
  insert into pg_temp.otp_checks values(label);
end $$;
create function pg_temp.otp_denied(command text, expected_state text,label text) returns void language plpgsql as $$
begin
  begin execute command;
  exception when others then
    perform pg_temp.check_otp(sqlstate=expected_state,label); return;
  end;
  raise exception 'Unexpectedly allowed: %',label;
end $$;

select pg_temp.check_otp(not has_function_privilege('anon','public.reserve_otp_request(text,text)','execute'),'anonymous execute grant absent');
select pg_temp.check_otp(not has_function_privilege('authenticated','public.reserve_otp_request(text,text)','execute'),'member execute grant absent');
select pg_temp.check_otp(has_function_privilege('service_role','public.reserve_otp_request(text,text)','execute'),'service execute grant present');
select pg_temp.check_otp(not has_schema_privilege('service_role','collect_auth_security','usage'),'private lock schema inaccessible directly');
select pg_temp.check_otp(not has_table_privilege('service_role','collect_auth_security.otp_phone_locks','select'),'private lock table inaccessible directly');
select pg_temp.check_otp(not has_table_privilege('service_role','public.otp_rate_limits','select'),'legacy direct counter reads remain denied');
select pg_temp.check_otp(not has_table_privilege('service_role','public.otp_rate_limits','insert'),'legacy direct counter inserts remain denied');
set local role authenticated;
select pg_temp.otp_denied($q$select public.reserve_otp_request(repeat('a',64),null)$q$,'42501','member cannot reserve quota');
reset role;
set local role service_role;
select pg_temp.otp_denied($q$select public.reserve_otp_request(null,null)$q$,'22023','null phone rejected');
select pg_temp.otp_denied($q$select public.reserve_otp_request('not-a-hash',null)$q$,'22023','invalid phone rejected');
select pg_temp.otp_denied($q$select public.reserve_otp_request(repeat('A',64),null)$q$,'22023','noncanonical phone hash rejected');
select pg_temp.otp_denied($q$select public.reserve_otp_request(repeat('a',64),'raw-ip')$q$,'22023','invalid IP hash rejected');
select pg_temp.check_otp(public.reserve_otp_request(repeat('a',64),repeat('1',64)),'reservation one accepted');
select pg_temp.check_otp(public.reserve_otp_request(repeat('a',64),repeat('1',64)),'reservation two accepted');
select pg_temp.check_otp(public.reserve_otp_request(repeat('a',64),repeat('2',64)),'reservation three accepted');
select pg_temp.check_otp(public.reserve_otp_request(repeat('a',64),null),'reservation four accepted');
select pg_temp.check_otp(public.reserve_otp_request(repeat('a',64),null),'reservation five accepted');
select pg_temp.check_otp(not public.reserve_otp_request(repeat('a',64),repeat('3',64)),'sixth request with another IP refused');
select pg_temp.check_otp(public.reserve_otp_request(repeat('b',64),repeat('1',64)),'another phone has independent quota');
reset role;
select pg_temp.check_otp((select count(*)=5 from public.otp_rate_limits where phone_hash=repeat('a',64)),'exactly five accepted attempts persisted');
select pg_temp.check_otp((select count(*)=2 from collect_auth_security.otp_phone_locks),'one lock row per phone');

-- Old attempts survive the upgrade but only the rolling window consumes quota.
insert into public.otp_rate_limits(phone_hash,requested_at)
select repeat('c',64),clock_timestamp()-interval '11 minutes' from generate_series(1,5);
set local role service_role;
select pg_temp.check_otp(public.reserve_otp_request(repeat('c',64),null),'expired attempts release quota');
reset role;
select pg_temp.check_otp((select count(*)=6 from public.otp_rate_limits where phone_hash=repeat('c',64)),'expired attempt history retained');
insert into public.otp_rate_limits(phone_hash,requested_at)
select repeat('e',64),clock_timestamp()-interval '1 minute' from generate_series(1,5);
set local role service_role;
select pg_temp.check_otp(not public.reserve_otp_request(repeat('e',64),null),'existing pre-upgrade attempts enforce quota');
reset role;

create function pg_temp.fail_otp_storage() returns trigger language plpgsql as $$
begin
  if new.phone_hash=repeat('d',64) then raise exception 'Synthetic storage failure' using errcode='55000'; end if;
  return new;
end $$;
create trigger qa_otp_storage_failure before insert on public.otp_rate_limits
for each row execute function pg_temp.fail_otp_storage();
set local role service_role;
select pg_temp.otp_denied($q$select public.reserve_otp_request(repeat('d',64),null)$q$,'55000','storage failure propagates instead of accepting');
reset role;
select pg_temp.check_otp(not exists(select 1 from collect_auth_security.otp_phone_locks where phone_hash=repeat('d',64)),'failed storage rolls back new lock row');
select pg_temp.check_otp(not exists(select 1 from public.otp_rate_limits where phone_hash=repeat('d',64)),'failed storage records no reservation');
select pg_temp.check_otp((select count(*)=0 from public.payments),'OTP reservation creates no payment');
select pg_temp.check_otp((select count(*)=0 from collect_hybrid.sms_notification_outbox),'OTP reservation creates no notification transport');
select label from otp_checks order by label;
select 'OTP_RATE_LIMIT_UAT_PASS: '||count(*)||' checks' from otp_checks;
rollback;
