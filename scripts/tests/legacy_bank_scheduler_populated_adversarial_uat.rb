# Emits root-only rollback-only negative fixtures, never connects to a DB.
# Supabase_admin is used ONLY for creating unsupported/history fixture states;
# every tested production readback, pause and verification runs as postgres.
require 'open3'
root = File.expand_path('../..', __dir__)
abort 'Usage: ruby legacy_bank_scheduler_populated_adversarial_uat.rb --emit-sql' unless ARGV == ['--emit-sql']
base, status = Open3.capture2('ruby', File.join(root, 'scripts/tests/legacy_bank_scheduler_populated_uat.rb'), '--emit-sql')
abort 'Base SQL generation failed' unless status.success? && base.end_with?("rollback;\n")
puts base.sub(/rollback;\n\z/, '')
puts <<~'SQL'
  create temp table adversarial_results(label text primary key);
  create function pg_temp.assert_true(ok boolean,label text) returns void language plpgsql as $$ begin
    if ok is not true then raise exception 'FAIL: %',label; end if;
    insert into pg_temp.adversarial_results values(label);
  end $$;
  create function pg_temp.expect_error(action text,expected_code text,expected_message text,label text) returns void language plpgsql as $$
  declare code text; message text; begin
    if current_user <> 'postgres' or (select rolsuper from pg_roles where rolname=current_user) then raise exception 'Normal installer required for operation test'; end if;
    begin execute action;
    exception when others then get stacked diagnostics code=returned_sqlstate,message=message_text;
    end;
    perform pg_temp.assert_true(code=expected_code and message=expected_message,label);
  end $$;
  select pg_temp.assert_true((collect_hybrid.retire_legacy_bank_scheduler()->>'replayed')::boolean,
    'nonempty succeeded and failed history allows exact pause replay');
  select pg_temp.assert_true((collect_hybrid.bank_scheduler_retirement_readback()->>'history_rows')::bigint=(select canonical_rows+2 from baseline),
    'readback sees all nonempty historical rows');

  -- Same-count content drift must fail, not merely added/deleted-row detection.
  set local role supabase_admin;
  update cron.job_run_details set return_message='fixture changed' where runid=9965000001;
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()','55000','bank_scheduler_retirement_drift','same-count historical content drift fails');
  set local role supabase_admin;
  update cron.job_run_details set return_message='fixture completed' where runid=9965000001;
  set local role postgres;
  select pg_temp.assert_true((collect_hybrid.retire_legacy_bank_scheduler()->>'replayed')::boolean,'exact historical bytes restore a valid replay');

  set local role supabase_admin;
  update cron.job_run_details set status='running',end_time=null where runid=9965000001;
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.bank_scheduler_retirement_readback()','55000','bank_scheduler_drain_required','running history blocks pause before any disable');
  set local role supabase_admin;
  update cron.job_run_details set status='starting' where runid=9965000001;
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()','55000','bank_scheduler_drain_required','queued starting history blocks pause');
  set local role supabase_admin;
  update cron.job_run_details set status='failed' where runid=9965000001;
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()','55000','bank_scheduler_drain_required','failed label without terminal timestamp still blocks');
  set local role supabase_admin;
  update cron.job_run_details set status='succeeded',end_time=clock_timestamp() where runid=9965000001;
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()','55000','bank_scheduler_drain_required','recent completed run requires five minute quiescent margin');
  set local role supabase_admin;
  update cron.job_run_details set end_time=timestamptz '2026-01-01 21:30:01+00' where runid=9965000001;
  select cron.alter_job((select job_id from collect_hybrid.legacy_bank_scheduler_retirements),username:='supabase_admin');
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()','55000','bank_scheduler_identity_review_required','different job owner is refused by normal installer');
  set local role supabase_admin;
  select cron.alter_job((select job_id from collect_hybrid.legacy_bank_scheduler_retirements),username:='postgres');
  -- Malformed metadata fixture setup only: postgres cannot issue these DMLs.
  update cron.job set jobname='collect-qa-malformed-name-9965' where jobid=(select job_id from collect_hybrid.legacy_bank_scheduler_retirements);
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()','55000','bank_scheduler_identity_review_required','missing canonical job name is refused');
  set local role supabase_admin;
  update cron.job set jobname='collect-daily-bank-reconciliation',nodename='qa.invalid' where jobid=(select job_id from collect_hybrid.legacy_bank_scheduler_retirements);
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()','55000','bank_scheduler_identity_review_required','alternate host fixture is refused');
  set local role supabase_admin;
  update cron.job set nodename='localhost',nodeport=current_setting('port')::integer+1 where jobid=(select job_id from collect_hybrid.legacy_bank_scheduler_retirements);
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()','55000','bank_scheduler_identity_review_required','alternate port fixture is refused');
  set local role supabase_admin;
  update cron.job set nodeport=current_setting('port')::integer where jobid=(select job_id from collect_hybrid.legacy_bank_scheduler_retirements);
  insert into cron.job(jobid,schedule,command,nodename,nodeport,database,username,active,jobname)
    select 9965000010,schedule,command,nodename,nodeport,database,'supabase_admin',false,jobname
    from cron.job where jobid=(select job_id from collect_hybrid.legacy_bank_scheduler_retirements);
  set local role postgres;
  select pg_temp.expect_error('select collect_hybrid.retire_legacy_bank_scheduler()','55000','bank_scheduler_identity_review_required','additional canonical other-owner fixture is refused');
  set local role supabase_admin;
  delete from cron.job where jobid=9965000010;
  set local role postgres;
  select pg_temp.assert_true((collect_hybrid.retire_legacy_bank_scheduler()->>'replayed')::boolean,'exact metadata and historical bytes restore valid final pause replay');
  select pg_temp.assert_true(pg_temp.business_snapshot()=(select business from baseline),'all prior business and historical financial tables remain unchanged');
  select pg_temp.assert_true((select coalesce(jsonb_agg(to_jsonb(d) order by runid),'[]') from cron.job_run_details d where runid not between 9965000001 and 9965000010)=(select history from baseline),'all original cron run history remains unchanged');
  select pg_temp.assert_true((select coalesce(jsonb_agg(to_jsonb(j)||jsonb_build_object('active',case when j.jobname='collect-daily-bank-reconciliation' then true else j.active end) order by jobid),'[]') from cron.job j)=(select jobs from baseline),'all original job metadata preserves every field except intended inactive flag');
  select jsonb_build_object('ok',true,'adversarial_checks',count(*),'labels',jsonb_agg(label order by label)) from adversarial_results;
  rollback;
SQL
