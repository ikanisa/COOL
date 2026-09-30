begin;

-- Keep full migration replay in the helper's cron -> audit lock order, including
-- audit-table DDL, so a concurrent owner-only replay cannot reverse that order.
lock table cron.job in share row exclusive mode;

-- 143: close the scheduled owner path left behind by the Rwanda-only cutover.
-- No bank API, financial row, cron job, or cron run-history row is removed.
-- Deployment must pause cron launches and drain this job first; disabling a
-- schedule cannot cancel a command that was already dispatched.
create table if not exists collect_hybrid.legacy_bank_scheduler_retirements (
  job_id bigint primary key check (job_id > 0),
  job_name text not null check (job_name = 'collect-daily-bank-reconciliation'),
  job_owner name not null check (job_owner in ('postgres', 'supabase_admin')),
  database_name name not null check (database_name = current_database()),
  schedule text not null check (schedule = '30 21 * * *'),
  command_sha256 text not null check (
    command_sha256 = '58ca13bd6915f92b194de581f89815718ac50a5d702055a4df3f07c0486bd597'
  ),
  was_active boolean not null,
  retirement_version text not null check (retirement_version = '20260930110000'),
  retirement_reason text not null check (retirement_reason = 'rwanda_momo_only_bank_scheduler_retired'),
  retired_at timestamptz not null default clock_timestamp() check (isfinite(retired_at)),
  retired_by name not null default current_user check (retired_by in ('postgres', 'supabase_admin')),
  -- At most two receipts in this database, one per admitted installation owner.
  unique (job_owner, database_name)
);
alter table collect_hybrid.legacy_bank_scheduler_retirements enable row level security;
revoke all on collect_hybrid.legacy_bank_scheduler_retirements from public, anon, authenticated, service_role;

create or replace function collect_hybrid.guard_bank_scheduler_retirement()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'bank_scheduler_retirement_immutable' using errcode = '55000';
end;
$$;
revoke all on function collect_hybrid.guard_bank_scheduler_retirement() from public, anon, authenticated, service_role;
drop trigger if exists bank_scheduler_retirement_immutable on collect_hybrid.legacy_bank_scheduler_retirements;
create trigger bank_scheduler_retirement_immutable
  before update or delete on collect_hybrid.legacy_bank_scheduler_retirements
  for each row execute function collect_hybrid.guard_bank_scheduler_retirement();
drop trigger if exists bank_scheduler_retirement_no_truncate on collect_hybrid.legacy_bank_scheduler_retirements;
create trigger bank_scheduler_retirement_no_truncate
  before truncate on collect_hybrid.legacy_bank_scheduler_retirements
  for each statement execute function collect_hybrid.guard_bank_scheduler_retirement();

-- Invoker privileges only: this is not a new API or SECURITY DEFINER escape.
-- The installer must be able to inspect ALL cron jobs, including other owners.
create or replace function collect_hybrid.retire_legacy_bank_scheduler()
returns jsonb language plpgsql set search_path = '' as $$
declare
  canonical_command constant text := $command$select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');$command$;
  canonical_sha256 constant text := '58ca13bd6915f92b194de581f89815718ac50a5d702055a4df3f07c0486bd597';
  candidate record;
  retired integer := 0;
  already_retired integer := 0;
begin
  if current_user not in ('postgres', 'supabase_admin') then
    raise exception 'bank_scheduler_owner_required' using errcode = '42501';
  end if;
  if current_setting('cron.launch_active_jobs', true) is distinct from 'off' then
    raise exception 'bank_scheduler_pause_required' using errcode = '55000';
  end if;
  -- row_security=off makes a restricted RLS scan fail rather than hiding jobs.
  -- This function deliberately requires the migration owner's table privileges.
  perform set_config('row_security', 'off', true);
  lock table cron.job in share row exclusive mode;
  lock table collect_hybrid.legacy_bank_scheduler_retirements in share row exclusive mode;
  if encode(extensions.digest(canonical_command, 'sha256'), 'hex') <> canonical_sha256 then
    raise exception 'bank_scheduler_command_binding_invalid' using errcode = '55000';
  end if;

  -- Validate the entire named set before touching any candidate. Whitespace,
  -- alternate commands, database routing and unexpected owners need review.
  if exists (
    select 1 from cron.job j where j.jobname = 'collect-daily-bank-reconciliation'
      and (j.command is distinct from canonical_command
        or j.schedule is distinct from '30 21 * * *'
        or j.username not in ('postgres', 'supabase_admin')
        or j.username is null or j.database is distinct from current_database()
        or j.nodename is distinct from 'localhost'
        or j.nodeport is distinct from current_setting('port')::integer)
  ) or (select count(*) from cron.job where jobname = 'collect-daily-bank-reconciliation') > 2 then
    raise exception 'bank_scheduler_identity_review_required' using errcode = '55000';
  end if;
  if exists (
    select 1 from collect_hybrid.legacy_bank_scheduler_retirements r
    left join cron.job j on j.jobid = r.job_id
    where j.jobid is null or j.active is distinct from false
      or j.jobname is distinct from r.job_name or j.username is distinct from r.job_owner::text
      or j.database is distinct from r.database_name::text or j.schedule is distinct from r.schedule
      or encode(extensions.digest(j.command, 'sha256'), 'hex') is distinct from r.command_sha256
      or j.nodename is distinct from 'localhost'
      or j.nodeport is distinct from current_setting('port')::integer
  ) then
    -- Never reuse a historic receipt to silently retire a reactivated job.
    raise exception 'bank_scheduler_retirement_drift' using errcode = '55000';
  end if;
  if exists (
    select 1 from cron.job_run_details d join cron.job j on j.jobid = d.jobid
    where j.jobname = 'collect-daily-bank-reconciliation'
      and d.end_time is null and (d.status is null or d.status not in ('succeeded', 'failed'))
  ) then
    raise exception 'bank_scheduler_drain_required' using errcode = '55000';
  end if;

  for candidate in select * from cron.job
    where jobname = 'collect-daily-bank-reconciliation' order by jobid
  loop
    if exists (select 1 from collect_hybrid.legacy_bank_scheduler_retirements where job_id = candidate.jobid) then
      already_retired := already_retired + 1;
    else
      perform cron.alter_job(candidate.jobid, active := false);
      if not exists (select 1 from cron.job where jobid = candidate.jobid and active = false) then
        raise exception 'bank_scheduler_retirement_failed' using errcode = '55000';
      end if;
      insert into collect_hybrid.legacy_bank_scheduler_retirements (
        job_id, job_name, job_owner, database_name, schedule, command_sha256,
        was_active, retirement_version, retirement_reason
      ) values (
        candidate.jobid, candidate.jobname, candidate.username, candidate.database,
        candidate.schedule, canonical_sha256, candidate.active, '20260930110000',
        'rwanda_momo_only_bank_scheduler_retired'
      );
      retired := retired + 1;
    end if;
  end loop;
  if exists (select 1 from cron.job where jobname = 'collect-daily-bank-reconciliation' and active) then
    raise exception 'bank_scheduler_retirement_failed' using errcode = '55000';
  end if;
  return jsonb_build_object('contract_version', 1, 'retired', retired,
    'already_retired', already_retired, 'active_jobs', 0);
end;
$$;
revoke all on function collect_hybrid.retire_legacy_bank_scheduler() from public, anon, authenticated, service_role;

select collect_hybrid.retire_legacy_bank_scheduler();
commit;
