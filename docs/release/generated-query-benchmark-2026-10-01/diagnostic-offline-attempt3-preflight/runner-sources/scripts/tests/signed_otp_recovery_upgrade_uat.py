#!/usr/bin/env python3
"""Emit source-bound rollback SQL for root; this script never connects to a DB."""
import argparse,hashlib,pathlib,re
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--emit-source-only',action='store_true');p.add_argument('--migration-sha256',required=True);a=p.parse_args()
if not a.emit_source_only:raise SystemExit('Source-only SQL emitter; explicit --emit-source-only required')
migration=ROOT/'supabase/migrations/20260930130000_signed_otp_uncertain_recovery.sql'
legacy=ROOT/'docs/release/otp-uncertain-recovery-2026-09-30/sources/legacy-signed-otp-limits-v2.sql'
if hashlib.sha256(migration.read_bytes()).hexdigest()!=a.migration_sha256:raise SystemExit('Migration source changed')
if hashlib.sha256(legacy.read_bytes()).hexdigest()!='c053dde0c0ba93d0d8d342c1b0a285fd5d1fbb16e58bd2a8fdae5a6fea58a8f6':raise SystemExit('Historical v2 source mismatch')
def body(file):
 s=file.read_text();s,n=re.subn(r'^begin;\s*$', '',s,count=1,flags=re.M)
 s,m=re.subn(r'^commit;\s*$', '',s,count=1,flags=re.M)
 if n!=1 or m!=1:raise SystemExit('Unsafe migration transaction envelope')
 return s
print(r'''\set ON_ERROR_STOP on
begin;
set local statement_timeout='60s';
do $$ begin
 if current_setting('collect.otp_qa_fixture',true) is distinct from 'collect_fin_concurrency_qa_20260929'
   or (select max(version) from supabase_migrations.schema_migrations)<>'20260930130000' then
   raise exception 'Exact task-owned migration145 fixture required';end if;
end $$;
-- Drops are inside this rollback-only transaction and scoped to OTP objects.
-- Source restoration includes private rows, definitions, owners, grants and triggers.
drop function public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text),
 public.reserve_signed_otp_v3(text,text,text),public.begin_signed_otp_v3(text,text,uuid,bigint),
 public.read_signed_otp_v3(text,text,uuid),public.record_signed_otp_v3(text,text,uuid,bigint,text,text,text),
 public.recover_signed_otp_v3(text,text,uuid,bigint,text,text);
drop table collect_security.signed_otp_evidence;
drop table collect_security.signed_otp_requests cascade;
drop table collect_security.otp_policy;
create temp table otp_upgrade_checks(label text primary key);
grant select,insert on otp_upgrade_checks to service_role;
create function pg_temp.otp_upgrade_check(ok boolean,label text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %',label;end if;
 insert into pg_temp.otp_upgrade_checks values(label);end $$;
''')
print(body(legacy))
print(r'''
insert into collect_security.otp_policy values(true,1000,10000,true);
insert into collect_security.signed_otp_requests(hook_id,payload_hash,phone_hash,requested_at,delivered_at,status) values
 ('qa_otp_upgrade_sent',repeat('a',64),repeat('8',64),clock_timestamp()-interval '2 minutes',clock_timestamp()-interval '1 minute','sent'),
 ('qa_otp_upgrade_unknown',repeat('a',64),repeat('8',64),clock_timestamp()-interval '2 minutes',null,'reserved');
insert into public.otp_rate_limits(phone_hash,requested_at) values
 (repeat('8',64),clock_timestamp()-interval '2 minutes'),(repeat('8',64),clock_timestamp()-interval '2 minutes');
''')
print(body(migration))
print(r'''
select pg_temp.otp_upgrade_check((select status='accepted' and accepted_at is not null and delivered_at is null and contract_version=2
 from collect_security.signed_otp_requests where hook_id='qa_otp_upgrade_sent'),'legacy sent becomes acceptance only');
select pg_temp.otp_upgrade_check((select status='ambiguous' and started_at is null and delivered_at is null and contract_version=2
 from collect_security.signed_otp_requests where hook_id='qa_otp_upgrade_unknown'),'legacy reserved remains unknown without resend');
select pg_temp.otp_upgrade_check((select enabled and global_hourly_limit=1000 and global_daily_limit=10000 from collect_security.otp_policy),'legacy policy preserved');
select pg_temp.otp_upgrade_check((select count(*)=2 from public.otp_rate_limits where phone_hash=repeat('8',64)),'legacy quota charges retained');
create temp table otp_before_reapply as select hook_id,to_jsonb(r) row_body from collect_security.signed_otp_requests r;
''')
print(body(migration))
print(r'''
select pg_temp.otp_upgrade_check(not exists(select 1 from otp_before_reapply b full join collect_security.signed_otp_requests r using(hook_id)
 where b.row_body is distinct from to_jsonb(r)),'reapply preserves every attempt and stored outcome');
select pg_temp.otp_upgrade_check((select count(*)=0 from collect_security.signed_otp_evidence),'reapply invents no historical provider evidence');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select pg_temp.otp_upgrade_check(public.reserve_signed_otp_v2('qa_otp_upgrade_sent',repeat('a',64),repeat('8',64))='already_sent','legacy accepted hook acknowledgement preserved');
select pg_temp.otp_upgrade_check(public.reserve_signed_otp_v2('qa_otp_upgrade_unknown',repeat('a',64),repeat('8',64))='unresolved','legacy unresolved cannot authorize send');
select pg_temp.otp_upgrade_check(not public.complete_signed_otp_v2('qa_otp_upgrade_unknown',repeat('a',64)),'legacy completion cannot fabricate success');
reset role;
select label from otp_upgrade_checks order by label;
select 'SIGNED_OTP_UPGRADE_UAT_PASS: '||count(*)||' checks' from otp_upgrade_checks;
rollback;
''')
