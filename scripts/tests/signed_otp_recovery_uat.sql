\set ON_ERROR_STOP on
begin;
set local statement_timeout='30s';
do $$ begin
 if current_setting('collect.otp_qa_fixture',true) is distinct from 'collect_fin_concurrency_qa_20260929' then
   raise exception 'Task-owned OTP fixture binding required';
 end if;
 if exists(select 1 from collect_security.signed_otp_requests where hook_id like 'qa_otp_20260930_%') then
   raise exception 'OTP synthetic namespace is not empty';
 end if;
end $$;
create temp table otp_recovery_checks(label text primary key);
grant select,insert on otp_recovery_checks to anon,authenticated,service_role;
create function pg_temp.check_otp_v3(ok boolean,label text) returns void language plpgsql as $$
begin
 if ok is not true then raise exception 'FAIL: %',label; end if;
 insert into pg_temp.otp_recovery_checks values(label);
end $$;
create function pg_temp.otp_v3_denied(command text,expected text,label text) returns void language plpgsql as $$
begin
 begin execute command;
 exception when others then perform pg_temp.check_otp_v3(sqlstate=expected,label);return;end;
 raise exception 'Unexpectedly permitted: %',label;
end $$;
create function pg_temp.otp_evidence(r jsonb,outcome text,provider_hash text default null)
returns text language sql as $$
 select jsonb_build_object('hook_id',r->>'hook_id','payload_hash',r->>'payload_hash','attempt_id',r->>'attempt_id',
 'outcome',outcome,'provider_message_hash',provider_hash,'observed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
 'source','operator_verified_provider_status')::text
$$;
create function pg_temp.otp_hash(t text) returns text language sql as $$
 select encode(extensions.digest(convert_to(t,'UTF8'),'sha256'),'hex')
$$;

select pg_temp.check_otp_v3(not has_schema_privilege('service_role','collect_security','usage'),'service cannot browse private schema');
select pg_temp.check_otp_v3(not has_table_privilege('service_role','collect_security.signed_otp_requests','select'),'service direct reservation read denied');
select pg_temp.check_otp_v3(not has_table_privilege('service_role','collect_security.signed_otp_evidence','insert'),'service direct evidence insert denied');
select pg_temp.check_otp_v3(not has_table_privilege('service_role','collect_security.otp_policy','update'),'service cannot change quota policy');
select pg_temp.check_otp_v3(not has_function_privilege('anon','public.reserve_signed_otp_v3(text,text,text)','execute'),'anonymous reserve execute denied');
select pg_temp.check_otp_v3(not has_function_privilege('authenticated','public.recover_signed_otp_v3(text,text,uuid,bigint,text,text)','execute'),'member recovery execute denied');
select pg_temp.check_otp_v3(has_function_privilege('service_role','public.reserve_signed_otp_v3(text,text,text)','execute'),'service reserve execute present');
set local role anon;
select pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3('qa_otp_20260930_denied',repeat('a',64),repeat('b',64))$q$,'42501','anonymous actual reserve denied');
reset role;
set local role authenticated;
select pg_temp.otp_v3_denied($q$select public.read_signed_otp_v3('qa_otp_20260930_denied',repeat('a',64),gen_random_uuid())$q$,'42501','member actual read denied');
reset role;
-- Missing/disabled policy never lets a hook initiate delivery.
delete from collect_security.otp_policy;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3('qa_otp_20260930_missing',repeat('a',64),repeat('b',64))$q$,'55000','missing policy fails closed');
reset role;
insert into collect_security.otp_policy(singleton,global_hourly_limit,global_daily_limit,enabled) values(true,1000,10000,false);
set local role service_role;
select pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3('qa_otp_20260930_disabled',repeat('a',64),repeat('b',64))$q$,'55000','disabled policy fails closed');
reset role;
update collect_security.otp_policy set enabled=true;
set local role service_role;
select pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3('qa_otp_20260930_invalid','raw-phone',repeat('b',64))$q$,'22023','malformed identity denied');
-- Execute grant does not substitute for the signed server role claim.
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
select pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3('qa_otp_20260930_wrongrole',repeat('a',64),repeat('b',64))$q$,'42501','wrong JWT role denied despite service execution role');
select set_config('request.jwt.claims','{"role":"service_role"}',true);

-- Exercise the real PostgreSQL parser at the documented hook-ID boundary.
-- This rejects an overlong/empty/non-ASCII identifier before charging quota.
select pg_temp.check_otp_v3(
 (public.reserve_signed_otp_v3(rpad('qa_otp_20260930_boundary_',256,'h'),repeat('a',64),repeat('4',64))->>'state')='reserved',
 '256 ASCII hook characters are admitted without regex engine failure');
select pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3(rpad('qa_otp_20260930_boundary_',257,'h'),repeat('a',64),repeat('4',64))$q$,
 '22023','257 hook characters denied before quota');
select pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3('',repeat('a',64),repeat('4',64))$q$,
 '22023','empty hook identity denied');
select pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3('qa_otp_20260930_é',repeat('a',64),repeat('4',64))$q$,
 '22023','non ASCII hook identity denied');

do $$ declare r jsonb; b jsonb; c jsonb; again jsonb; e text; ph text:=repeat('d',64); bh text:=repeat('a',64);
begin
 r:=public.reserve_signed_otp_v3('qa_otp_20260930_accept',bh,repeat('b',64));
 perform pg_temp.check_otp_v3(r->>'state'='reserved' and (r->>'can_send')::boolean,'enabled reservation is eligible once');
 again:=public.reserve_signed_otp_v3('qa_otp_20260930_accept',bh,repeat('b',64));
 perform pg_temp.check_otp_v3(r=again,'exact reservation replay returns same attempt');
 perform pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3('qa_otp_20260930_accept',repeat('c',64),repeat('b',64))$q$,'22023','changed body under same hook denied');
 perform pg_temp.otp_v3_denied($q$select public.reserve_signed_otp_v3('qa_otp_20260930_accept',repeat('a',64),repeat('c',64))$q$,'22023','changed phone under same hook denied');
 b:=public.begin_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,(r->>'revision')::bigint);
 perform pg_temp.check_otp_v3(b->>'state'='sending' and (b->>'started')::boolean and not (b->>'can_send')::boolean,'begin single-send fencing');
 again:=public.begin_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,(r->>'revision')::bigint);
 perform pg_temp.check_otp_v3(not (again->>'started')::boolean,'duplicate begin cannot send');
 perform pg_temp.otp_v3_denied(format('select public.begin_signed_otp_v3(%L,%L,gen_random_uuid(),2)',r->>'hook_id',bh),'22023','wrong generation begin denied');
 c:=public.record_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,2,'accepted',ph,repeat('e',64));
 perform pg_temp.check_otp_v3(c->>'state'='accepted' and c->>'revision'='3','provider acceptance persists as accepted');
 again:=public.record_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,2,'accepted',ph,repeat('e',64));
 perform pg_temp.check_otp_v3(again=c,'exact accepted completion replay idempotent');
 perform pg_temp.otp_v3_denied(format('select public.record_signed_otp_v3(%L,%L,%L::uuid,2,%L,%L,%L)',r->>'hook_id',bh,r->>'attempt_id','accepted',ph,repeat('f',64)),'40001','changed accepted completion denied');
 e:=pg_temp.otp_evidence(c,'delivered',ph);
 c:=public.recover_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,3,e,pg_temp.otp_hash(e));
 perform pg_temp.check_otp_v3(c->>'state'='delivered' and c->>'revision'='4','independently verified delivery outcome records explicitly');
 again:=public.recover_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,3,e,pg_temp.otp_hash(e));
 perform pg_temp.check_otp_v3(again=c,'same evidence recovery idempotent');
 again:=public.reserve_signed_otp_v3(r->>'hook_id',bh,repeat('b',64));
 perform pg_temp.check_otp_v3(again=c,'delivered replay reads outcome without another send');
 perform pg_temp.otp_v3_denied(format('select public.recover_signed_otp_v3(%L,%L,%L::uuid,4,%L,%L)',r->>'hook_id',bh,r->>'attempt_id',pg_temp.otp_evidence(c,'not_sent'),repeat('9',64)),'22023','mismatched exact evidence hash denied');
end $$;

do $$ declare r jsonb; b jsonb; c jsonb; e text; bh text:=repeat('a',64);
begin
 r:=public.reserve_signed_otp_v3('qa_otp_20260930_unsent',bh,repeat('c',64));
 e:=pg_temp.otp_evidence(r,'not_sent');
 c:=public.recover_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,1,e,pg_temp.otp_hash(e));
 perform pg_temp.check_otp_v3(c->>'state'='not_sent' and not (c->>'can_send')::boolean,'confirmed not-sent is terminal without resend');
 b:=public.begin_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,1);
 perform pg_temp.check_otp_v3(not (b->>'started')::boolean,'not-sent replay cannot begin');
 r:=public.reserve_signed_otp_v3('qa_otp_20260930_ambiguous',bh,repeat('c',64));
 b:=public.begin_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,1);
 c:=public.record_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,2,'ambiguous',null,repeat('e',64));
 perform pg_temp.check_otp_v3(c->>'state'='ambiguous' and not (c->>'can_send')::boolean,'timeout/error outcome ambiguous and no resend');
 e:=pg_temp.otp_evidence(c,'accepted',repeat('f',64));
 c:=public.recover_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,3,e,pg_temp.otp_hash(e));
 perform pg_temp.check_otp_v3(c->>'state'='accepted','lost acceptance completion recovered with bound evidence');
 e:=pg_temp.otp_evidence(c,'failed',repeat('f',64));
 c:=public.recover_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,4,e,pg_temp.otp_hash(e));
 perform pg_temp.check_otp_v3(c->>'state'='failed' and not (c->>'can_send')::boolean,'verified provider failure terminal and distinct from delivery');
 e:=pg_temp.otp_evidence(c,'delivered',repeat('f',64));
 perform pg_temp.otp_v3_denied(format('select public.recover_signed_otp_v3(%L,%L,%L::uuid,5,%L,%L)',r->>'hook_id',bh,r->>'attempt_id',e,pg_temp.otp_hash(e)),'40001','contradictory terminal status rejected');
 r:=public.reserve_signed_otp_v3('qa_otp_20260930_binding',bh,repeat('c',64));
 b:=public.begin_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,1);
 e:=pg_temp.otp_evidence(b,'delivered',repeat('f',64));
 perform pg_temp.otp_v3_denied(format('select public.recover_signed_otp_v3(%L,%L,%L::uuid,1,%L,%L)',r->>'hook_id',bh,r->>'attempt_id',e,pg_temp.otp_hash(e)),'40001','stale expected revision rejected');
 perform pg_temp.otp_v3_denied(format('select public.recover_signed_otp_v3(%L,%L,gen_random_uuid(),2,%L,%L)',r->>'hook_id',bh,e,pg_temp.otp_hash(e)),'22023','cross-attempt evidence denied');
 e:=(e::jsonb||jsonb_build_object('source','unverified_user_report'))::text;
 perform pg_temp.otp_v3_denied(format('select public.recover_signed_otp_v3(%L,%L,%L::uuid,2,%L,%L)',r->>'hook_id',bh,r->>'attempt_id',e,pg_temp.otp_hash(e)),'22023','unverified recovery source rejected');
 e:=(pg_temp.otp_evidence(b,'delivered',repeat('f',64))::jsonb||jsonb_build_object('private_phone','+250700000000'))::text;
 perform pg_temp.otp_v3_denied(format('select public.recover_signed_otp_v3(%L,%L,%L::uuid,2,%L,%L)',r->>'hook_id',bh,r->>'attempt_id',e,pg_temp.otp_hash(e)),'22023','extra private evidence fields rejected');
 perform pg_temp.check_otp_v3(not public.complete_signed_otp_v2(r->>'hook_id',bh),'legacy completion cannot claim success');
 perform pg_temp.check_otp_v3(public.reserve_signed_otp_v2(r->>'hook_id',bh,repeat('c',64))='unresolved','legacy unresolved cannot authorize another send');
end $$;
reset role;
select pg_temp.check_otp_v3((select count(*)=1 from collect_security.signed_otp_requests where hook_id='qa_otp_20260930_accept'),'replays preserve one quota reservation');
select pg_temp.check_otp_v3((select count(*)=3 from public.otp_rate_limits where phone_hash=repeat('c',64)),'uncertain/failed/not-sent attempts retain per-phone quota');
select pg_temp.check_otp_v3((select delivered_at is not null from collect_security.signed_otp_requests where hook_id='qa_otp_20260930_accept'),'delivery timestamp only after delivery evidence');
select pg_temp.check_otp_v3((select delivered_at is null from collect_security.signed_otp_requests where hook_id='qa_otp_20260930_ambiguous'),'failed status never claims delivered timestamp');
select pg_temp.otp_v3_denied($q$update collect_security.signed_otp_evidence set source='hook_worker'$q$,'55000','durable evidence cannot be rewritten');
select pg_temp.otp_v3_denied($q$delete from collect_security.signed_otp_evidence$q$,'55000','durable evidence cannot be deleted');
-- Expired reservation and stale sending lease are different outcomes.
update collect_security.signed_otp_requests set requested_at=clock_timestamp()-interval '6 minutes'
 where hook_id='qa_otp_20260930_binding';
update collect_security.signed_otp_requests set started_at=clock_timestamp()-interval '2 minutes'
 where hook_id='qa_otp_20260930_binding';
set local role service_role;
do $$ declare r jsonb; c jsonb; bh text:=repeat('a',64);
begin
 r:=public.reserve_signed_otp_v3('qa_otp_20260930_binding',bh,repeat('c',64));
 perform pg_temp.check_otp_v3(r->>'state'='ambiguous' and r->>'revision'='3','stale sending lease becomes ambiguous');
 c:=public.record_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,2,'accepted',repeat('f',64),repeat('e',64));
 perform pg_temp.check_otp_v3(c->>'state'='accepted' and c->>'revision'='4','late accepted completion may resolve expired lease without resend');
 perform pg_temp.check_otp_v3(public.record_signed_otp_v3(r->>'hook_id',bh,(r->>'attempt_id')::uuid,2,'accepted',repeat('f',64),repeat('e',64))=c,'late accepted completion replay idempotent');
 r:=public.reserve_signed_otp_v3('qa_otp_20260930_expiry',bh,repeat('2',64));
end $$;
reset role;
update collect_security.signed_otp_requests set requested_at=clock_timestamp()-interval '6 minutes'
 where hook_id='qa_otp_20260930_expiry';
set local role service_role;
do $$ declare r jsonb;
begin
 r:=public.reserve_signed_otp_v3('qa_otp_20260930_expiry',repeat('a',64),repeat('2',64));
 perform pg_temp.check_otp_v3(r->>'state'='expired' and not (r->>'can_send')::boolean,'unsent expired reservation cannot send old OTP');
end $$;
reset role;
-- Enabled local policy actually enforces global and per-phone budgets.
update collect_security.otp_policy set global_hourly_limit=(select count(*) from collect_security.signed_otp_requests
 where requested_at>=clock_timestamp()-interval '1 hour');
set local role service_role;
select pg_temp.check_otp_v3(public.reserve_signed_otp_v3('qa_otp_20260930_global',repeat('a',64),repeat('3',64))='"throttled"'::jsonb,'enabled global budget enforced');
reset role;
update collect_security.otp_policy set global_hourly_limit=1000;
set local role service_role;
select public.reserve_signed_otp_v3('qa_otp_20260930_phone4',repeat('a',64),repeat('c',64));
select public.reserve_signed_otp_v3('qa_otp_20260930_phone5',repeat('a',64),repeat('c',64));
select pg_temp.check_otp_v3(public.reserve_signed_otp_v3('qa_otp_20260930_phone6',repeat('a',64),repeat('c',64))='"throttled"'::jsonb,'fifth charged attempt exhausts phone quota despite not-sent/uncertainty');
reset role;
select pg_temp.check_otp_v3(not exists(select 1 from collect_security.signed_otp_requests where hook_id in
 ('qa_otp_20260930_missing','qa_otp_20260930_disabled','qa_otp_20260930_invalid','qa_otp_20260930_wrongrole','qa_otp_20260930_global','qa_otp_20260930_phone6')),'denied attempts record no admitted send');
select label from otp_recovery_checks order by label;
select 'SIGNED_OTP_RECOVERY_UAT_PASS: '||count(*)||' checks' from otp_recovery_checks;
rollback;
