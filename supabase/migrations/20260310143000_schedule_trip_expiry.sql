-- ==========================================================================
-- Cool App - Schedule trip expiry
-- ==========================================================================
-- Uses pg_cron to expire mobility trips every 5 minutes directly in Postgres.
-- This keeps trip expiry live even when Edge Function deployment is blocked.
-- ==========================================================================

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;
select cron.unschedule(jobid)
from cron.job
where jobname = 'expire-mobility-trips';
select cron.schedule(
  'expire-mobility-trips',
  '*/5 * * * *',
  $$
  update public.mobility_trips
  set
    status = 'expired',
    updated_at = now()
  where status in ('open', 'active')
    and departure_at < now() - interval '60 minutes';
  $$
)
where not exists (
  select 1
  from cron.job
  where jobname = 'expire-mobility-trips'
);
