# Emits a rollback-only 142->143 populated-history rehearsal. Does NOT connect.
# Root runs emitted SQL as supabase_admin for synthetic fixture setup, then the
# script switches to the real nonsuperuser postgres installer for ALL migration
# code and retirement/helper operations. No grants on cron or global GUC changes.
require 'digest'
ROOT = File.expand_path('../..', __dir__)
MIGRATION = File.join(ROOT, 'supabase/migrations/20260930110000_retire_legacy_bank_scheduler.sql')
source = File.read(MIGRATION)
abort 'Expected exact explicit SERIALIZABLE wrapper' unless source.start_with?("begin isolation level serializable;\n") && source.end_with?("commit;\n")
body = source.sub(/\Abegin isolation level serializable;\n/, '').sub(/commit;\n\z/, '')
abort 'Usage: ruby legacy_bank_scheduler_populated_uat.rb --emit-sql' unless ARGV == ['--emit-sql']
puts <<~SQL
  \\set ON_ERROR_STOP on
  -- Generated from migration SHA256 #{Digest::SHA256.hexdigest(source)}.
  -- Privileged role is fixture setup only. Every installer/helper call below
  -- runs as ordinary postgres with cron SELECT/owner API permissions only.
  begin isolation level serializable;
  set local statement_timeout='30s';
  set local collect.legacy_bank_scheduler_qa='isolated_clone';
  do $$ begin
    if current_user <> 'supabase_admin' or not (select rolsuper from pg_roles where rolname=current_user)
      or current_database() <> 'postgres' or current_setting('cron.launch_active_jobs') <> 'off'
      or current_setting('pg_net.batch_size') <> '0'
      or (select count(*) from supabase_migrations.schema_migrations) <> 142
      or (select max(version) from supabase_migrations.schema_migrations) <> '20260930100000'
      or to_regclass('collect_hybrid.legacy_bank_scheduler_retirements') is not null
      or (select count(*) from cron.job where jobname='collect-daily-bank-reconciliation' and username='postgres' and active) <> 1
      or exists(select 1 from cron.job_run_details where runid between 9965000001 and 9965000010)
    then raise exception 'Exact isolated 142 pre-retirement fixture required'; end if;
  end $$;
  create function pg_temp.business_snapshot() returns jsonb language plpgsql as $$
  declare item record; n bigint; h text; result jsonb := '{}'::jsonb; begin
    for item in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname in('public','collect_hybrid') and c.relkind in('r','p')
        and c.relname not in('legacy_bank_scheduler_retirements','legacy_bank_scheduler_observations','legacy_bank_scheduler_verifications')
      order by n.nspname,c.relname loop
      execute format('select count(*),encode(extensions.digest(coalesce(string_agg(hashes.h, '''' order by hashes.h),''''),''sha256''),''hex'') from(select encode(extensions.digest(to_jsonb(t)::text,''sha256''),''hex'') h from %I.%I t) hashes',item.nspname,item.relname) into n,h;
      result:=result||jsonb_build_object(item.nspname||'.'||item.relname,jsonb_build_object('rows',n,'sha256',h));
    end loop;
    return result;
  end $$;
  create temp table baseline as select pg_temp.business_snapshot() business,
    (select coalesce(jsonb_agg(to_jsonb(j) order by jobid),'[]') from cron.job j) jobs,
    (select coalesce(jsonb_agg(to_jsonb(d) order by runid),'[]') from cron.job_run_details d) history,
    (select count(*) from cron.job_run_details d join cron.job j on j.jobid=d.jobid where j.jobname='collect-daily-bank-reconciliation') canonical_rows;
  grant select on pg_temp.baseline to postgres;
  insert into cron.job_run_details(jobid,runid,database,username,command,status,start_time,end_time,return_message)
    select jobid,9965000001,database,username,command,'succeeded',timestamptz '2026-01-01 21:30:00+00',timestamptz '2026-01-01 21:30:01+00','fixture completed'
    from cron.job where jobname='collect-daily-bank-reconciliation';
  insert into cron.job_run_details(jobid,runid,database,username,command,status,start_time,end_time,return_message)
    select jobid,9965000002,database,username,command,'failed',timestamptz '2026-01-02 21:30:00+00',timestamptz '2026-01-02 21:30:01+00','fixture failed'
    from cron.job where jobname='collect-daily-bank-reconciliation';
  set local role postgres;
  do $$ begin
    if (select rolsuper from pg_roles where rolname=current_user)
      or has_table_privilege(current_user,'cron.job','INSERT,UPDATE,DELETE,MAINTAIN')
    then raise exception 'Ordinary installer ACLs required'; end if;
  end $$;
SQL
puts body
puts <<~SQL
  do $$ declare code text; begin
    if pg_temp.business_snapshot() <> (select business from pg_temp.baseline)
      or (select history_rows from collect_hybrid.legacy_bank_scheduler_retirements) <> (select canonical_rows+2 from pg_temp.baseline)
      or (select count(*) from collect_hybrid.legacy_bank_scheduler_observations) <> 0
      or (select count(*) from collect_hybrid.legacy_bank_scheduler_verifications) <> 0
      or exists(select 1 from cron.job where jobname='collect-daily-bank-reconciliation' and active)
      or (select coalesce(jsonb_agg(to_jsonb(d) order by runid),'[]') from cron.job_run_details d where runid not between 9965000001 and 9965000010) <> (select history from pg_temp.baseline)
      or (select count(*) from cron.job_run_details where runid in(9965000001,9965000002) and status in('succeeded','failed')) <> 2
    then raise exception 'Populated retirement preservation failed'; end if;
    begin perform collect_hybrid.verify_legacy_bank_scheduler_retirement();
    exception when others then get stacked diagnostics code=returned_sqlstate;
    end;
    if code is distinct from '25001' then raise exception 'Uncommitted pause must never verify'; end if;
  end $$;
  select jsonb_build_object('ok',true,'installer',current_user,'phase','paused_only_rollback_rehearsal',
    'historical_fixture_rows',2,'business_and_original_history_preserved',true,'same_transaction_verification_rejected',true);
  rollback;
SQL
