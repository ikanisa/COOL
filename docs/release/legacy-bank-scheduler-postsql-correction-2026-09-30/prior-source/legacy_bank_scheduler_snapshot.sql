\set ON_ERROR_STOP on
-- Root-owned isolated upgrade readback, before142->143 and after143.
-- Hashes/counts only; no financial rows, raw commands or provider secrets.
begin;
set local statement_timeout = '30s';
do $$ begin
  if current_database() <> 'postgres'
    or current_setting('collect.legacy_bank_scheduler_qa', true) is distinct from 'isolated_clone'
    or current_setting('cron.launch_active_jobs', true) is distinct from 'off'
    or current_setting('pg_net.batch_size', true) is distinct from '0'
    or not (
      ((select count(*) from supabase_migrations.schema_migrations) = 142
       and (select max(version) from supabase_migrations.schema_migrations) = '20260930100000')
      or ((select count(*) from supabase_migrations.schema_migrations) = 143
       and (select max(version) from supabase_migrations.schema_migrations) = '20260930110000')
    ) then raise exception 'Exact isolated 142 or 143 scheduler snapshot required'; end if;
end $$;
create function pg_temp.scheduler_upgrade_snapshot() returns jsonb
language plpgsql as $$ declare item record; n bigint; h text; business jsonb := '{}'::jsonb; receipts jsonb := '[]'::jsonb; begin
  for item in select n.nspname, c.relname from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'collect_hybrid') and c.relkind in ('r', 'p')
      and c.relname <> 'legacy_bank_scheduler_retirements'
    order by n.nspname, c.relname
  loop
    execute format('select count(*), encode(extensions.digest(coalesce(string_agg(h, '''' order by h), ''''), ''sha256''), ''hex'') from (select encode(extensions.digest(to_jsonb(t)::text, ''sha256''), ''hex'') h from %I.%I t) hashes', item.nspname, item.relname) into n, h;
    business := business || jsonb_build_object(item.nspname || '.' || item.relname, jsonb_build_object('rows', n, 'sha256', h));
  end loop;
  if to_regclass('collect_hybrid.legacy_bank_scheduler_retirements') is not null then
    execute 'select coalesce(jsonb_agg(to_jsonb(r) order by job_id), ''[]'') from collect_hybrid.legacy_bank_scheduler_retirements r' into receipts;
  end if;
  return jsonb_build_object(
    'migration_count', (select count(*) from supabase_migrations.schema_migrations),
    'migration_max', (select max(version) from supabase_migrations.schema_migrations),
    'business_tables', business,
    'cron_jobs', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', jobid, 'name', jobname, 'schedule', schedule, 'owner', username,
      'database', database, 'host', nodename, 'port', nodeport, 'active', active,
      'command_sha256', encode(extensions.digest(command, 'sha256'), 'hex')) order by jobid), '[]') from cron.job),
    'cron_history', (select jsonb_build_object('rows', count(*), 'sha256', encode(extensions.digest(coalesce(string_agg(h, '' order by h), ''), 'sha256'), 'hex'))
      from (select encode(extensions.digest(to_jsonb(d)::text, 'sha256'), 'hex') h from cron.job_run_details d) hashes),
    'retirement_audit', receipts
  );
end $$;
select pg_temp.scheduler_upgrade_snapshot();
rollback;
