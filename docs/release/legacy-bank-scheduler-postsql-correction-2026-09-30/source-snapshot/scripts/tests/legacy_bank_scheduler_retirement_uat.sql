\set ON_ERROR_STOP on
-- Rollback-only. The root operator runs this on the exact isolated 143 fixture.
-- Synthetic cron identifiers avoid sequence changes; no command is dispatched.
begin;
set local statement_timeout = '30s';
do $$ begin
  if current_database() <> 'postgres'
    or current_setting('collect.legacy_bank_scheduler_qa', true) is distinct from 'isolated_clone'
    or current_setting('cron.launch_active_jobs', true) is distinct from 'off'
    or current_setting('pg_net.batch_size', true) is distinct from '0'
    or (select count(*) from supabase_migrations.schema_migrations) <> 143
    or (select max(version) from supabase_migrations.schema_migrations) <> '20260930110000'
    or (select count(*) from collect_hybrid.legacy_bank_scheduler_retirements) <> 1
    or exists (select 1 from cron.job where jobid between 9965000001 and 9965000010)
    or exists (select 1 from cron.job_run_details where runid = 9965000001)
  then raise exception 'Exact isolated 143 scheduler fixture required'; end if;
end $$;

create temp table test_results(label text primary key);
grant all on pg_temp.test_results to anon, authenticated, service_role;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values (label);
end $$;
create function pg_temp.expect_error(command text, expected text, label text) returns void
language plpgsql as $$ declare code text; begin
  begin execute command;
  exception when others then get stacked diagnostics code = returned_sqlstate;
  end;
  perform pg_temp.assert_true(code = expected, label);
end $$;
create function pg_temp.expect_safe_error(command text, expected text, label text) returns void
language plpgsql as $$ declare message text; begin
  begin execute command;
  exception when others then get stacked diagnostics message = message_text;
  end;
  perform pg_temp.assert_true(message = expected, label);
end $$;

-- Include every business base table, covering historical bank, MoMo, ledger,
-- balances, reconciliation, notification and roster data; retain hashes only.
create function pg_temp.business_snapshot() returns jsonb
language plpgsql as $$ declare item record; n bigint; h text; result jsonb := '{}'::jsonb; begin
  for item in select n.nspname, c.relname from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'collect_hybrid') and c.relkind in ('r', 'p')
      and c.relname <> 'legacy_bank_scheduler_retirements'
    order by n.nspname, c.relname
  loop
    execute format('select count(*), encode(extensions.digest(coalesce(string_agg(h, '''' order by h), ''''), ''sha256''), ''hex'') from (select encode(extensions.digest(to_jsonb(t)::text, ''sha256''), ''hex'') h from %I.%I t) hashes', item.nspname, item.relname) into n, h;
    result := result || jsonb_build_object(item.nspname || '.' || item.relname, jsonb_build_object('rows', n, 'sha256', h));
  end loop;
  return result;
end $$;
create temp table baseline as select pg_temp.business_snapshot() business,
  (select coalesce(jsonb_agg(to_jsonb(j) order by jobid), '[]') from cron.job j) jobs,
  (select coalesce(jsonb_agg(to_jsonb(d) order by runid), '[]') from cron.job_run_details d) history,
  (select to_jsonb(r) from collect_hybrid.legacy_bank_scheduler_retirements r) receipt;

select pg_temp.assert_true(not exists (select 1 from cron.job
  where jobname = 'collect-daily-bank-reconciliation' and active), 'canonical active job count is zero');
select pg_temp.assert_true((select collect_hybrid.retire_legacy_bank_scheduler()) =
  '{"contract_version":1,"retired":0,"already_retired":1,"active_jobs":0}'::jsonb,
  'repeat retirement is an acknowledged no-op');
select pg_temp.assert_true((select to_jsonb(r) from collect_hybrid.legacy_bank_scheduler_retirements r)
  = (select receipt from baseline), 'repeat retirement preserves exact original audit row');
select pg_temp.assert_true(not exists (
  select 1 from unnest(array['anon', 'authenticated', 'service_role']) role_name
  where has_table_privilege(role_name, 'collect_hybrid.legacy_bank_scheduler_retirements', 'select,insert,update,delete,truncate,references,trigger')
    or has_function_privilege(role_name, 'collect_hybrid.retire_legacy_bank_scheduler()', 'execute')
    or has_function_privilege(role_name, 'collect_hybrid.guard_bank_scheduler_retirement()', 'execute')
), 'all API roles lack audit and helper privileges');
select pg_temp.assert_true((select relrowsecurity from pg_class
  where oid = 'collect_hybrid.legacy_bank_scheduler_retirements'::regclass)
  and not exists (select 1 from pg_policy where polrelid = 'collect_hybrid.legacy_bank_scheduler_retirements'::regclass),
  'audit storage has RLS and no client policies');
select pg_temp.expect_error('update collect_hybrid.legacy_bank_scheduler_retirements set retired_at = clock_timestamp()', '55000', 'audit update is refused');
select pg_temp.expect_error('delete from collect_hybrid.legacy_bank_scheduler_retirements', '55000', 'audit deletion is refused');
select pg_temp.expect_error('truncate collect_hybrid.legacy_bank_scheduler_retirements', '55000', 'audit truncation is refused');

set local role anon;
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '42501', 'anon cannot retire jobs');
select pg_temp.expect_error('select * from collect_hybrid.legacy_bank_scheduler_retirements', '42501', 'anon cannot read audit');
reset role;
set local role authenticated;
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '42501', 'authenticated cannot retire jobs');
select pg_temp.expect_error('delete from collect_hybrid.legacy_bank_scheduler_retirements', '42501', 'authenticated cannot write audit');
reset role;
set local role service_role;
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '42501', 'service role cannot retire jobs');
select pg_temp.expect_error('delete from collect_hybrid.legacy_bank_scheduler_retirements', '42501', 'service role cannot write audit');
reset role;

-- A synthetic second admitted installation owner exercises fresh retirement.
insert into cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname)
select 9965000001, '30 21 * * *',
  $command$select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');$command$,
  'localhost', current_setting('port')::integer, current_database(),
  case when job_owner = 'postgres' then 'supabase_admin' else 'postgres' end,
  true, 'collect-daily-bank-reconciliation'
from collect_hybrid.legacy_bank_scheduler_retirements;
insert into cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname)
values (9965000002, '15 * * * *', 'select 1;', 'localhost', current_setting('port')::integer,
  current_database(), current_user, true, 'collect-qa-unrelated-9965');

-- These errors must leave the fresh valid candidate enabled and unaudited.
update cron.job set command = command || ' -- unexpected' where jobid = 9965000001;
select pg_temp.expect_safe_error('select collect_hybrid.retire_legacy_bank_scheduler()', 'bank_scheduler_identity_review_required', 'same-name altered command fails review');
update cron.job set command = $command$select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');$command$ where jobid = 9965000001;
update cron.job set username = 'authenticated' where jobid = 9965000001;
select pg_temp.expect_safe_error('select collect_hybrid.retire_legacy_bank_scheduler()', 'bank_scheduler_identity_review_required', 'same-name untrusted owner fails review');
update cron.job set username = (select case when job_owner = 'postgres' then 'supabase_admin' else 'postgres' end from collect_hybrid.legacy_bank_scheduler_retirements) where jobid = 9965000001;
update cron.job set database = 'template1' where jobid = 9965000001;
select pg_temp.expect_safe_error('select collect_hybrid.retire_legacy_bank_scheduler()', 'bank_scheduler_identity_review_required', 'same-name other database fails review');
update cron.job set database = current_database(), schedule = '* * * * *' where jobid = 9965000001;
select pg_temp.expect_safe_error('select collect_hybrid.retire_legacy_bank_scheduler()', 'bank_scheduler_identity_review_required', 'same-name unexpected schedule fails review');
update cron.job set schedule = '30 21 * * *', nodename = 'unexpected.invalid' where jobid = 9965000001;
select pg_temp.expect_safe_error('select collect_hybrid.retire_legacy_bank_scheduler()', 'bank_scheduler_identity_review_required', 'same-name remote host fails review');
update cron.job set nodename = 'localhost', nodeport = current_setting('port')::integer + 1 where jobid = 9965000001;
select pg_temp.expect_safe_error('select collect_hybrid.retire_legacy_bank_scheduler()', 'bank_scheduler_identity_review_required', 'same-name alternate port fails review');
update cron.job set nodeport = current_setting('port')::integer where jobid = 9965000001;

update cron.job set active = true where jobid = (select job_id from collect_hybrid.legacy_bank_scheduler_retirements);
select pg_temp.expect_safe_error('select collect_hybrid.retire_legacy_bank_scheduler()', 'bank_scheduler_retirement_drift', 'reactivated audited job cannot silently reuse receipt');
select pg_temp.assert_true((select active from cron.job where jobid = 9965000001)
  and (select count(*) from collect_hybrid.legacy_bank_scheduler_retirements) = 1,
  'review failures never partly retire another valid candidate');
update cron.job set active = false where jobid = (select job_id from collect_hybrid.legacy_bank_scheduler_retirements);

insert into cron.job_run_details (jobid, runid, database, username, command, status, start_time)
select jobid, 9965000001, database, username, command, 'running', clock_timestamp()
from cron.job where jobid = 9965000001;
select pg_temp.expect_safe_error('select collect_hybrid.retire_legacy_bank_scheduler()', 'bank_scheduler_drain_required', 'in-flight canonical run requires drain');
update cron.job_run_details set status = 'succeeded', end_time = clock_timestamp() where runid = 9965000001;

select pg_temp.assert_true(collect_hybrid.retire_legacy_bank_scheduler() =
  '{"contract_version":1,"retired":1,"already_retired":1,"active_jobs":0}'::jsonb,
  'fresh verified owner job is retired with one receipt');
select pg_temp.assert_true((select was_active and command_sha256 = '58ca13bd6915f92b194de581f89815718ac50a5d702055a4df3f07c0486bd597'
  and retirement_version = '20260930110000' and retirement_reason = 'rwanda_momo_only_bank_scheduler_retired'
  from collect_hybrid.legacy_bank_scheduler_retirements where job_id = 9965000001),
  'fresh immutable receipt binds original command and retirement policy');
select pg_temp.assert_true(not exists (select 1 from cron.job
  where jobname = 'collect-daily-bank-reconciliation' and active), 'both admitted owners have zero active canonical jobs');
select pg_temp.assert_true((select count(*) from cron.job_run_details where runid = 9965000001 and status = 'succeeded') = 1,
  'retirement retains completed job history');
select pg_temp.assert_true((select active and command = 'select 1;' and schedule = '15 * * * *'
  from cron.job where jobid = 9965000002), 'unrelated synthetic job remains enabled and unchanged');
select pg_temp.assert_true((select coalesce(jsonb_agg(to_jsonb(j) order by jobid), '[]') from cron.job j
  where jobid not between 9965000001 and 9965000010) = (select jobs from baseline),
  'every original job row remains unchanged');
select pg_temp.assert_true((select coalesce(jsonb_agg(to_jsonb(d) order by runid), '[]') from cron.job_run_details d
  where runid <> 9965000001) = (select history from baseline), 'every original run-history row remains unchanged');
select pg_temp.assert_true(pg_temp.business_snapshot() = (select business from baseline),
  'every business and historical financial table preserves all row hashes');
select pg_temp.assert_true(not has_function_privilege('anon', 'public.run_daily_bank_reconciliation(date,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.run_daily_bank_reconciliation(date,text)', 'execute')
  and not has_function_privilege('service_role', 'public.run_daily_bank_reconciliation(date,text)', 'execute'),
  'retirement does not reopen the legacy bank API');

select jsonb_build_object('checks', count(*), 'labels', jsonb_agg(label order by label)) from test_results;
rollback;
