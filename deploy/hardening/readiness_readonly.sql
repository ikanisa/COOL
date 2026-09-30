-- Read-only observations. No auth tokens, OTPs, phone values or message bodies.
\set ON_ERROR_STOP on
begin transaction read only;
set local statement_timeout='15s';
select current_database() as database_name,current_setting('server_version') as server_version,
       current_setting('transaction_read_only') as read_only;
select n.nspname as schema_name,c.relname,c.relrowsecurity,c.relforcerowsecurity
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind in ('r','p') order by c.relname;
select n.nspname as schema_name,p.proname,p.prosecdef,p.proconfig,
 has_function_privilege('anon',p.oid,'execute') as anon_can_execute,
 has_function_privilege('authenticated',p.oid,'execute') as member_can_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prosecdef order by p.proname;
select schemaname,tablename,policyname,roles,cmd from pg_policies
where schemaname in ('public','collect_security') order by schemaname,tablename,policyname;
select routine_name from information_schema.routines
where routine_schema='public' and routine_name in ('accept_attested_receipt_v2','reserve_signed_otp_v2','propose_payment_reconciliation_v2');
rollback;
-- An operator reviews these observations. A successful SELECT is not RLS approval,
-- a restore drill, proof of current backups, or evidence that all release gates pass.
