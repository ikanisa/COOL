\set ON_ERROR_STOP on
-- Root-only, rollback-only: the exact isolated normal-postgres 143 fixture.
begin isolation level serializable;
set local statement_timeout = '30s';
do $$ begin
  if current_database() <> 'postgres' or current_user <> 'postgres'
    or (select rolsuper from pg_roles where rolname = current_user)
    or has_table_privilege(current_user, 'cron.job', 'INSERT')
    or has_table_privilege(current_user, 'cron.job', 'UPDATE')
    or has_table_privilege(current_user, 'cron.job', 'DELETE')
    or has_table_privilege(current_user, 'cron.job', 'MAINTAIN')
    or current_setting('collect.legacy_bank_scheduler_qa', true) is distinct from 'isolated_clone'
    or current_setting('cron.launch_active_jobs', true) is distinct from 'off'
    or current_setting('pg_net.batch_size', true) is distinct from '0'
    or (select count(*) from supabase_migrations.schema_migrations) <> 143
    or (select max(version) from supabase_migrations.schema_migrations) <> '20260930110000'
    or (select count(*) from collect_hybrid.legacy_bank_scheduler_retirements) <> 1
    or (select count(*) from collect_hybrid.legacy_bank_scheduler_observations) <> 1
    or (select count(*) from collect_hybrid.legacy_bank_scheduler_verifications) <> 1
  then raise exception 'Exact isolated normal-owner verified 143 fixture required'; end if;
end $$;
create temp table test_results(label text primary key);
grant all on pg_temp.test_results to anon, authenticated, service_role;
create function pg_temp.assert_true(ok boolean, label text) returns void language plpgsql as $$ begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values (label);
end $$;
create function pg_temp.expect_error(command text, expected_code text, expected_message text, label text) returns void
language plpgsql as $$ declare code text; message text; begin
  begin execute command;
  exception when others then get stacked diagnostics code = returned_sqlstate, message = message_text;
  end;
  perform pg_temp.assert_true(code = expected_code and (expected_message is null or message = expected_message), label);
end $$;
create function pg_temp.business_snapshot() returns jsonb language plpgsql as $$
declare item record; n bigint; h text; result jsonb := '{}'::jsonb; begin
  for item in select n.nspname, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'collect_hybrid') and c.relkind in ('r', 'p')
      and c.relname not in ('legacy_bank_scheduler_retirements', 'legacy_bank_scheduler_observations', 'legacy_bank_scheduler_verifications')
    order by n.nspname, c.relname loop
    execute format('select count(*), encode(extensions.digest(coalesce(string_agg(hashes.h, '''' order by hashes.h), ''''), ''sha256''), ''hex'') from (select encode(extensions.digest(to_jsonb(t)::text, ''sha256''), ''hex'') h from %I.%I t) hashes', item.nspname, item.relname) into n, h;
    result := result || jsonb_build_object(item.nspname || '.' || item.relname, jsonb_build_object('rows', n, 'sha256', h));
  end loop;
  return result;
end $$;
create temp table baseline as select pg_temp.business_snapshot() business,
  (select coalesce(jsonb_agg(to_jsonb(j) order by jobid), '[]') from cron.job j) jobs,
  (select coalesce(jsonb_agg(to_jsonb(d) order by runid), '[]') from cron.job_run_details d) history,
  (select to_jsonb(r) from collect_hybrid.legacy_bank_scheduler_retirements r) pause,
  (select to_jsonb(r) from collect_hybrid.legacy_bank_scheduler_observations r) observation,
  (select to_jsonb(r) from collect_hybrid.legacy_bank_scheduler_verifications r) verification;

select pg_temp.assert_true(has_table_privilege(current_user, 'cron.job', 'SELECT') and
  has_function_privilege(current_user, 'cron.alter_job(bigint,text,text,text,text,boolean)', 'EXECUTE'),
  'normal installer has only job read and owner API rights');
select pg_temp.expect_error('lock table cron.job in share row exclusive mode', '42501', null,
  'old candidate table lock is prohibited for normal installer');
select pg_temp.expect_error('update cron.job set active = false', '42501', null, 'direct cron DML is prohibited');
select pg_temp.assert_true((collect_hybrid.retire_legacy_bank_scheduler()->>'state') = 'retired_verified', 'pause replay is a validated acknowledged no-op');
select pg_temp.assert_true((collect_hybrid.verify_legacy_bank_scheduler_retirement()->>'replayed')::boolean,
  'verification replay requires fresh authoritative checks');
select pg_temp.assert_true((collect_hybrid.bank_scheduler_retirement_readback()->>'active')::boolean = false,
  'authoritative readback confirms inactive canonical job');
select pg_temp.assert_true((select verification->>'observation_seconds' from baseline)::numeric >= 30,
  'final verification binds minimum postcommit observation interval');
select pg_temp.assert_true((select pause->>'paused_xid' from baseline) <> (select observation->>'observation_xid' from baseline)
  and (select observation->>'observation_xid' from baseline) <> (select verification->>'verification_xid' from baseline),
  'pause observation and verification were separate transactions');

-- Change only through normal owner APIs. The enclosing rollback restores every
-- job and receipt; these calls never dispatch the bank command.
select cron.alter_job((select (pause->>'job_id')::bigint from baseline), command := 'select 1;');
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '55000', 'bank_scheduler_identity_review_required', 'changed command fails pause replay');
select pg_temp.expect_error('select collect_hybrid.verify_legacy_bank_scheduler_retirement()', '55000', 'bank_scheduler_identity_review_required', 'changed command fails final verification');
select cron.alter_job((select (pause->>'job_id')::bigint from baseline), command := $command$select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');$command$);
select cron.alter_job((select (pause->>'job_id')::bigint from baseline), schedule := '15 * * * *');
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '55000', 'bank_scheduler_identity_review_required', 'changed schedule fails review');
select cron.alter_job((select (pause->>'job_id')::bigint from baseline), schedule := '30 21 * * *');
select cron.alter_job((select (pause->>'job_id')::bigint from baseline), database := 'template1');
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '55000', 'bank_scheduler_identity_review_required', 'changed database fails review');
select cron.alter_job((select (pause->>'job_id')::bigint from baseline), database := current_database());
select cron.alter_job((select (pause->>'job_id')::bigint from baseline), active := true);
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '55000', 'bank_scheduler_retirement_drift', 'reactivation cannot reuse pause receipt');
select pg_temp.expect_error('select collect_hybrid.verify_legacy_bank_scheduler_retirement()', '55000', 'bank_scheduler_retirement_drift', 'reactivation cannot reuse final receipt');
select cron.alter_job((select (pause->>'job_id')::bigint from baseline), active := false);
select pg_temp.expect_error('select cron.alter_job((select job_id from collect_hybrid.legacy_bank_scheduler_retirements), username := ''supabase_admin'')', 'XX000', null, 'normal installer cannot change job ownership');

-- All API roles lack each storage/helper capability; actual role calls verify it.
select pg_temp.assert_true(not exists (
  select 1 from unnest(array['anon','authenticated','service_role']) role_name
  cross join unnest(array['legacy_bank_scheduler_retirements','legacy_bank_scheduler_observations','legacy_bank_scheduler_verifications']) table_name
  where has_table_privilege(role_name, 'collect_hybrid.' || table_name, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
), 'all API roles lack every audit storage privilege');
select pg_temp.assert_true(not exists (
  select 1 from unnest(array['anon','authenticated','service_role']) role_name
  cross join unnest(array['guard_bank_scheduler_retirement','bank_scheduler_retirement_readback','retire_legacy_bank_scheduler','verify_legacy_bank_scheduler_retirement']) function_name
  where has_function_privilege(role_name, 'collect_hybrid.' || function_name || '()', 'EXECUTE')
), 'all API roles lack every helper capability');
select pg_temp.assert_true((select count(*) from pg_class where oid in
  ('collect_hybrid.legacy_bank_scheduler_retirements'::regclass, 'collect_hybrid.legacy_bank_scheduler_observations'::regclass, 'collect_hybrid.legacy_bank_scheduler_verifications'::regclass) and relrowsecurity) = 3
  and not exists (select 1 from pg_policy where polrelid in
  ('collect_hybrid.legacy_bank_scheduler_retirements'::regclass, 'collect_hybrid.legacy_bank_scheduler_observations'::regclass, 'collect_hybrid.legacy_bank_scheduler_verifications'::regclass)),
  'all three immutable tables use RLS with no API policies');
select pg_temp.expect_error('update collect_hybrid.legacy_bank_scheduler_retirements set paused_at = clock_timestamp()', '55000', 'bank_scheduler_retirement_immutable', 'pause update refused');
select pg_temp.expect_error('delete from collect_hybrid.legacy_bank_scheduler_observations', '55000', 'bank_scheduler_retirement_immutable', 'observation deletion refused');
select pg_temp.expect_error('truncate collect_hybrid.legacy_bank_scheduler_verifications', '55000', 'bank_scheduler_retirement_immutable', 'verification truncation refused');
set local role anon;
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '42501', null, 'anon cannot pause');
select pg_temp.expect_error('select collect_hybrid.verify_legacy_bank_scheduler_retirement()', '42501', null, 'anon cannot verify');
reset role;
set local role authenticated;
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '42501', null, 'member cannot pause');
select pg_temp.expect_error('select collect_hybrid.bank_scheduler_retirement_readback()', '42501', null, 'member cannot read private evidence');
reset role;
set local role service_role;
select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()', '42501', null, 'service cannot pause');
select pg_temp.expect_error('select collect_hybrid.verify_legacy_bank_scheduler_retirement()', '42501', null, 'service cannot verify');
reset role;
select pg_temp.assert_true((select coalesce(jsonb_agg(to_jsonb(j) order by jobid), '[]') from cron.job j) = (select jobs from baseline), 'every original job row remains unchanged');
select pg_temp.assert_true((select coalesce(jsonb_agg(to_jsonb(d) order by runid), '[]') from cron.job_run_details d) = (select history from baseline), 'every original run-history row remains unchanged');
select pg_temp.assert_true(pg_temp.business_snapshot() = (select business from baseline), 'every business and historical financial table preserves all row hashes');
select pg_temp.assert_true((select to_jsonb(r) from collect_hybrid.legacy_bank_scheduler_retirements r) = (select pause from baseline)
  and (select to_jsonb(r) from collect_hybrid.legacy_bank_scheduler_observations r) = (select observation from baseline)
  and (select to_jsonb(r) from collect_hybrid.legacy_bank_scheduler_verifications r) = (select verification from baseline), 'all three exact immutable receipts remain unchanged');
select pg_temp.assert_true(not has_function_privilege('anon', 'public.run_daily_bank_reconciliation(date,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.run_daily_bank_reconciliation(date,text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.run_daily_bank_reconciliation(date,text)', 'EXECUTE'), 'legacy bank API remains closed');
select jsonb_build_object('checks', count(*), 'labels', jsonb_agg(label order by label)) from test_results;
rollback;
