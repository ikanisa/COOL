\set ON_ERROR_STOP on
-- Generated from migration SHA256 5a7a4e7773b65e4fcf015ac079ea18d57cbe08d363bd8b07b87471018b941d85.
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

-- 143: normal job-owner pause followed by separate postcommit verification.
-- cron.alter_job performs the owner-authorized UPDATE under pg_cron's extension
-- owner; no installer cron DML/table-lock privilege is required or granted.
-- A same-value schedule UPDATE takes the job row lock. SERIALIZABLE prevents
-- an owner API edit committed after this transaction's snapshot from being lost.
-- Disabling can cancel an already launched pg_cron task: refuse a live/queued
-- history row and operate outside the canonical schedule window before pausing.
select pg_catalog.pg_advisory_xact_lock(143, 20260930);

create table if not exists collect_hybrid.legacy_bank_scheduler_retirements (
  job_id bigint primary key check (job_id > 0),
  job_name text not null check (job_name = 'collect-daily-bank-reconciliation'),
  job_owner name not null check (job_owner in ('postgres', 'supabase_admin')),
  database_name name not null check (database_name = current_database()),
  schedule text not null check (schedule = '30 21 * * *'),
  command_sha256 text not null check (command_sha256 = '58ca13bd6915f92b194de581f89815718ac50a5d702055a4df3f07c0486bd597'),
  inactive_metadata_sha256 text not null check (inactive_metadata_sha256 ~ '^[0-9a-f]{64}$'),
  was_active boolean not null,
  retirement_version text not null unique check (retirement_version = '20260930110000'),
  retirement_reason text not null check (retirement_reason = 'rwanda_momo_only_bank_scheduler_retired'),
  state text not null check (state = 'paused_pending_verification'),
  paused_at timestamptz not null check (isfinite(paused_at)),
  paused_by name not null check (paused_by = job_owner),
  paused_xid bigint not null check (paused_xid > 0),
  cron_timezone text not null check (cron_timezone in ('GMT', 'UTC', 'Etc/UTC')),
  launcher_pid integer not null check (launcher_pid > 0),
  launcher_started_at timestamptz not null check (isfinite(launcher_started_at)),
  history_rows bigint not null check (history_rows >= 0),
  history_sha256 text not null check (history_sha256 ~ '^[0-9a-f]{64}$')
);
create table if not exists collect_hybrid.legacy_bank_scheduler_observations (
  job_id bigint primary key references collect_hybrid.legacy_bank_scheduler_retirements(job_id),
  observed_at timestamptz not null check (isfinite(observed_at)),
  observed_by name not null check (observed_by in ('postgres', 'supabase_admin')),
  observation_xid bigint not null check (observation_xid > 0),
  readback_sha256 text not null check (readback_sha256 ~ '^[0-9a-f]{64}$')
);
create table if not exists collect_hybrid.legacy_bank_scheduler_verifications (
  job_id bigint primary key references collect_hybrid.legacy_bank_scheduler_observations(job_id),
  state text not null check (state = 'retired_verified'),
  verified_at timestamptz not null check (isfinite(verified_at)),
  verified_by name not null check (verified_by in ('postgres', 'supabase_admin')),
  verification_xid bigint not null check (verification_xid > 0),
  readback_sha256 text not null check (readback_sha256 ~ '^[0-9a-f]{64}$'),
  observation_readback_sha256 text not null check (observation_readback_sha256 ~ '^[0-9a-f]{64}$'),
  observation_seconds numeric not null check (observation_seconds >= 30)
);
alter table collect_hybrid.legacy_bank_scheduler_retirements enable row level security;
alter table collect_hybrid.legacy_bank_scheduler_observations enable row level security;
alter table collect_hybrid.legacy_bank_scheduler_verifications enable row level security;
revoke all on collect_hybrid.legacy_bank_scheduler_retirements,
  collect_hybrid.legacy_bank_scheduler_observations,
  collect_hybrid.legacy_bank_scheduler_verifications from public, anon, authenticated, service_role;

create or replace function collect_hybrid.guard_bank_scheduler_retirement()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'bank_scheduler_retirement_immutable' using errcode = '55000';
end;
$$;
revoke all on function collect_hybrid.guard_bank_scheduler_retirement() from public, anon, authenticated, service_role;
do $$ declare table_name text; begin
  foreach table_name in array array['legacy_bank_scheduler_retirements', 'legacy_bank_scheduler_observations', 'legacy_bank_scheduler_verifications'] loop
    execute format('drop trigger if exists bank_scheduler_retirement_immutable on collect_hybrid.%I', table_name);
    execute format('create trigger bank_scheduler_retirement_immutable before update or delete on collect_hybrid.%I for each row execute function collect_hybrid.guard_bank_scheduler_retirement()', table_name);
    execute format('drop trigger if exists bank_scheduler_retirement_no_truncate on collect_hybrid.%I', table_name);
    execute format('create trigger bank_scheduler_retirement_no_truncate before truncate on collect_hybrid.%I for each statement execute function collect_hybrid.guard_bank_scheduler_retirement()', table_name);
  end loop;
end $$;

-- Private, invoker-only authoritative readback; no raw command/return messages.
create or replace function collect_hybrid.bank_scheduler_retirement_readback()
returns jsonb language plpgsql set search_path = '' as $$
declare
  canonical_command constant text := $command$select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');$command$;
  candidate record;
  launcher record;
  history_count bigint;
  history_hash text;
  nonterminal bigint;
  live_commands bigint;
  cron_zone text := current_setting('cron.timezone', true);
  observed timestamptz := clock_timestamp();
  local_time time;
begin
  if current_user not in ('postgres', 'supabase_admin')
    or not exists (select 1 from pg_catalog.pg_roles where rolname = current_user and (rolsuper or rolbypassrls)) then
    raise exception 'bank_scheduler_owner_required' using errcode = '42501';
  end if;
  if current_setting('transaction_isolation') <> 'serializable' then
    raise exception 'bank_scheduler_serializable_required' using errcode = '25001';
  end if;
  if not pg_catalog.pg_has_role(current_user, 'pg_read_all_stats', 'USAGE')
    and not exists (select 1 from pg_catalog.pg_roles where rolname = current_user and rolsuper) then
    raise exception 'bank_scheduler_stats_visibility_required' using errcode = '42501';
  end if;
  perform pg_catalog.set_config('row_security', 'off', true);
  if (select extversion from pg_catalog.pg_extension where extname = 'pg_cron') is distinct from '1.6.4'
    or current_setting('cron.log_run', true) is distinct from 'on'
    or cron_zone is null or cron_zone not in ('GMT', 'UTC', 'Etc/UTC') then
    raise exception 'bank_scheduler_runtime_review_required' using errcode = '55000';
  end if;
  -- Daily fixed UTC schedule. A five-minute margin excludes launch/catch-up
  -- boundaries. No canonical run can still be recent, queued or executing.
  local_time := (observed at time zone cron_zone)::time;
  if local_time >= time '21:25:00' and local_time <= time '21:35:00' then
    raise exception 'bank_scheduler_schedule_window' using errcode = '55000';
  end if;
  if (select count(*) from cron.job where jobname = 'collect-daily-bank-reconciliation') <> 1 then
    raise exception 'bank_scheduler_identity_review_required' using errcode = '55000';
  end if;
  select * into strict candidate from cron.job where jobname = 'collect-daily-bank-reconciliation';
  if candidate.command is distinct from canonical_command
    or candidate.schedule is distinct from '30 21 * * *'
    or candidate.username is distinct from current_user::text
    or candidate.database is distinct from current_database()
    or candidate.nodename is distinct from 'localhost'
    or candidate.nodeport is distinct from current_setting('port')::integer then
    raise exception 'bank_scheduler_identity_review_required' using errcode = '55000';
  end if;
  if (select count(*) from pg_catalog.pg_stat_activity where backend_type = 'pg_cron launcher') <> 1 then
    raise exception 'bank_scheduler_launcher_review_required' using errcode = '55000';
  end if;
  select pid, backend_start into strict launcher from pg_catalog.pg_stat_activity where backend_type = 'pg_cron launcher';
  select count(*), encode(extensions.digest(coalesce(string_agg(hashes.h, '' order by hashes.h), ''), 'sha256'), 'hex')
    into history_count, history_hash
    from (select encode(extensions.digest(to_jsonb(d)::text, 'sha256'), 'hex') h from cron.job_run_details d where d.jobid = candidate.jobid) hashes;
  select count(*) into nonterminal from cron.job_run_details d where d.jobid = candidate.jobid
    and (d.end_time is null or d.status is null or d.status not in ('succeeded', 'failed'));
  select count(*) into live_commands from pg_catalog.pg_stat_activity a
    where a.pid <> pg_catalog.pg_backend_pid() and a.datname = current_database()
      and a.state is distinct from 'idle' and a.query ~* '^\s*(select|call)\s+(public\.)?run_daily_bank_reconciliation\s*\(';
  if nonterminal <> 0 or live_commands <> 0 or exists (
    select 1 from cron.job_run_details d where d.jobid = candidate.jobid
      and greatest(d.start_time, d.end_time) > observed - interval '5 minutes'
  ) then
    raise exception 'bank_scheduler_drain_required' using errcode = '55000';
  end if;
  return jsonb_build_object('contract_version', 2, 'job_id', candidate.jobid,
    'active', candidate.active, 'job_owner', candidate.username,
    'metadata_sha256', encode(extensions.digest(to_jsonb(candidate)::text, 'sha256'), 'hex'),
    'observed_at', observed, 'observed_by', current_user,
    'cron_timezone', cron_zone, 'log_run', true,
    'launcher_pid', launcher.pid, 'launcher_started_at', launcher.backend_start,
    'history_rows', history_count, 'history_sha256', history_hash,
    'nonterminal_runs', nonterminal, 'live_bank_commands', live_commands);
end;
$$;
revoke all on function collect_hybrid.bank_scheduler_retirement_readback() from public, anon, authenticated, service_role;

create or replace function collect_hybrid.retire_legacy_bank_scheduler()
returns jsonb language plpgsql set search_path = '' as $$
declare
  before_readback jsonb;
  after_readback jsonb;
  receipt collect_hybrid.legacy_bank_scheduler_retirements%rowtype;
  candidate record;
begin
  perform pg_catalog.pg_advisory_xact_lock(143, 20260930);
  before_readback := collect_hybrid.bank_scheduler_retirement_readback();
  -- Row lock through owner API, never cron DML/table locking. A changed row
  -- after the transaction snapshot causes 40001 and rolls the whole call back.
  perform cron.alter_job((before_readback->>'job_id')::bigint, schedule := '30 21 * * *');
  after_readback := collect_hybrid.bank_scheduler_retirement_readback();
  if before_readback->>'metadata_sha256' is distinct from after_readback->>'metadata_sha256'
    or before_readback->>'history_sha256' is distinct from after_readback->>'history_sha256' then
    raise exception 'bank_scheduler_snapshot_changed' using errcode = '40001';
  end if;
  select * into receipt from collect_hybrid.legacy_bank_scheduler_retirements where job_id = (before_readback->>'job_id')::bigint;
  if found then
    if (after_readback->>'active')::boolean is distinct from false
      or receipt.inactive_metadata_sha256 is distinct from after_readback->>'metadata_sha256'
      or receipt.history_rows is distinct from (after_readback->>'history_rows')::bigint
      or receipt.history_sha256 is distinct from after_readback->>'history_sha256'
      or receipt.cron_timezone is distinct from after_readback->>'cron_timezone'
      or receipt.launcher_pid is distinct from (after_readback->>'launcher_pid')::integer
      or receipt.launcher_started_at is distinct from (after_readback->>'launcher_started_at')::timestamptz then
      raise exception 'bank_scheduler_retirement_drift' using errcode = '55000';
    end if;
    return jsonb_build_object('contract_version', 2, 'job_id', receipt.job_id,
      'state', case when exists (select 1 from collect_hybrid.legacy_bank_scheduler_verifications where job_id = receipt.job_id) then 'retired_verified' else 'paused_pending_verification' end,
      'replayed', true, 'active_jobs', 0);
  end if;
  perform cron.alter_job((before_readback->>'job_id')::bigint, active := false);
  after_readback := collect_hybrid.bank_scheduler_retirement_readback();
  if (after_readback->>'active')::boolean is distinct from false
    or before_readback->>'history_sha256' is distinct from after_readback->>'history_sha256' then
    raise exception 'bank_scheduler_retirement_failed' using errcode = '55000';
  end if;
  select * into strict candidate from cron.job where jobid = (after_readback->>'job_id')::bigint;
  insert into collect_hybrid.legacy_bank_scheduler_retirements (
    job_id, job_name, job_owner, database_name, schedule, command_sha256,
    inactive_metadata_sha256, was_active, retirement_version, retirement_reason,
    state, paused_at, paused_by, paused_xid, cron_timezone, launcher_pid,
    launcher_started_at, history_rows, history_sha256
  ) values (candidate.jobid, candidate.jobname, candidate.username, candidate.database,
    candidate.schedule, encode(extensions.digest(candidate.command, 'sha256'), 'hex'),
    after_readback->>'metadata_sha256', (before_readback->>'active')::boolean,
    '20260930110000', 'rwanda_momo_only_bank_scheduler_retired',
    'paused_pending_verification', clock_timestamp(), current_user, pg_catalog.txid_current(),
    after_readback->>'cron_timezone', (after_readback->>'launcher_pid')::integer,
    (after_readback->>'launcher_started_at')::timestamptz,
    (after_readback->>'history_rows')::bigint, after_readback->>'history_sha256');
  return jsonb_build_object('contract_version', 2, 'job_id', candidate.jobid,
    'state', 'paused_pending_verification', 'replayed', false, 'active_jobs', 0);
end;
$$;
revoke all on function collect_hybrid.retire_legacy_bank_scheduler() from public, anon, authenticated, service_role;

-- First call: immutable observation in a transaction after the pause committed.
-- Second call: another transaction >=30s after that observation. This avoids
-- incorrectly counting time spent holding an uncommitted pause transaction.
create or replace function collect_hybrid.verify_legacy_bank_scheduler_retirement()
returns jsonb language plpgsql set search_path = '' as $$
declare
  receipt collect_hybrid.legacy_bank_scheduler_retirements%rowtype;
  observation collect_hybrid.legacy_bank_scheduler_observations%rowtype;
  final_receipt collect_hybrid.legacy_bank_scheduler_verifications%rowtype;
  readback jsonb;
  readback_hash text;
  elapsed numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock(143, 20260930);
  readback := collect_hybrid.bank_scheduler_retirement_readback();
  perform cron.alter_job((readback->>'job_id')::bigint, schedule := '30 21 * * *');
  readback := collect_hybrid.bank_scheduler_retirement_readback();
  select * into receipt from collect_hybrid.legacy_bank_scheduler_retirements where job_id = (readback->>'job_id')::bigint;
  if not found then raise exception 'bank_scheduler_pause_receipt_required' using errcode = '55000'; end if;
  if receipt.paused_xid = pg_catalog.txid_current() then
    raise exception 'bank_scheduler_postcommit_transaction_required' using errcode = '25001';
  end if;
  if (readback->>'active')::boolean is distinct from false
    or receipt.inactive_metadata_sha256 is distinct from readback->>'metadata_sha256'
    or receipt.history_rows is distinct from (readback->>'history_rows')::bigint
    or receipt.history_sha256 is distinct from readback->>'history_sha256'
    or receipt.cron_timezone is distinct from readback->>'cron_timezone'
    or receipt.launcher_pid is distinct from (readback->>'launcher_pid')::integer
    or receipt.launcher_started_at is distinct from (readback->>'launcher_started_at')::timestamptz then
    raise exception 'bank_scheduler_retirement_drift' using errcode = '55000';
  end if;
  select * into final_receipt from collect_hybrid.legacy_bank_scheduler_verifications where job_id = receipt.job_id;
  if found then
    return jsonb_build_object('contract_version', 2, 'job_id', receipt.job_id,
      'state', 'retired_verified', 'replayed', true, 'active_jobs', 0,
      'verification', to_jsonb(final_receipt));
  end if;
  readback_hash := encode(extensions.digest(readback::text, 'sha256'), 'hex');
  select * into observation from collect_hybrid.legacy_bank_scheduler_observations where job_id = receipt.job_id;
  if not found then
    insert into collect_hybrid.legacy_bank_scheduler_observations
      values (receipt.job_id, (readback->>'observed_at')::timestamptz, current_user, pg_catalog.txid_current(), readback_hash);
    return jsonb_build_object('contract_version', 2, 'job_id', receipt.job_id,
      'state', 'awaiting_observation_interval', 'minimum_seconds', 30,
      'readback', readback, 'readback_sha256', readback_hash);
  end if;
  if observation.observation_xid = pg_catalog.txid_current() then
    raise exception 'bank_scheduler_postcommit_transaction_required' using errcode = '25001';
  end if;
  elapsed := extract(epoch from (readback->>'observed_at')::timestamptz - observation.observed_at);
  if elapsed < 30 then raise exception 'bank_scheduler_observation_interval_required' using errcode = '55000'; end if;
  insert into collect_hybrid.legacy_bank_scheduler_verifications
    values (receipt.job_id, 'retired_verified', (readback->>'observed_at')::timestamptz,
      current_user, pg_catalog.txid_current(), readback_hash, observation.readback_sha256, elapsed);
  select * into strict final_receipt from collect_hybrid.legacy_bank_scheduler_verifications where job_id = receipt.job_id;
  return jsonb_build_object('contract_version', 2, 'job_id', receipt.job_id,
    'state', 'retired_verified', 'replayed', false, 'active_jobs', 0,
    'readback', readback, 'verification', to_jsonb(final_receipt));
end;
$$;
revoke all on function collect_hybrid.verify_legacy_bank_scheduler_retirement() from public, anon, authenticated, service_role;

-- Installing 143 pauses only. Completion requires the documented postcommit
-- observation and final verification calls; this migration never claims GO.
select collect_hybrid.retire_legacy_bank_scheduler();
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
