\set ON_ERROR_STOP on
-- Run as database owner only after the documented protocol2 deployment checks.
-- Supply -v expected_project_url=https://<verified-project-ref>.supabase.co.
-- This value is non-secret. Credentials must already be provisioned in Vault.
\if :{?expected_project_url}
\else
  \echo 'expected_project_url is required'
  \quit 1
\endif
begin;
select set_config('collect.notification_expected_url', :'expected_project_url', true);
do $$ declare config jsonb; begin
  config := public._notification_dispatch_configuration();
  if config->>'url' is distinct from current_setting('collect.notification_expected_url') || '/functions/v1/dispatch-notifications' then
    raise exception 'notification_scheduler_project_mismatch';
  end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='20260929160000') then
    raise exception 'notification_protocol2_migration_required';
  end if;
  perform public.configure_notification_dispatch_schedule(true);
end $$;
select jobname, schedule, active from cron.job where jobname='collect-dispatch-notifications';
commit;
