-- Read-only catalog metadata; no application rows, credentials or cron commands.
select jsonb_build_object(
  'observed_at_utc', clock_timestamp(),
  'server_version', current_setting('server_version'),
  'migration_count', (select count(*) from supabase_migrations.schema_migrations),
  'last_migration', (select max(version) from supabase_migrations.schema_migrations),
  'exposed_schemas', current_setting('pgrst.db_schemas',true),
  'tables', (select coalesce(jsonb_agg(jsonb_build_object(
      'schema',n.nspname,'name',c.relname,'rls_enabled',c.relrowsecurity,
      'rls_forced',c.relforcerowsecurity,'owner',pg_get_userbyid(c.relowner),
      'acl',c.relacl::text) order by n.nspname,c.relname),'[]'::jsonb)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind in ('r','p','v','m') and n.nspname in
      ('public','collect_hybrid','collect_security','collect_admin_access','auth','storage')),
  'policies', (select coalesce(jsonb_agg(jsonb_build_object(
      'schema',schemaname,'table',tablename,'name',policyname,
      'roles',roles,'command',cmd,'permissive',permissive,
      'using',qual,'with_check',with_check) order by schemaname,tablename,policyname),'[]'::jsonb)
    from pg_policies where schemaname in
      ('public','collect_hybrid','collect_security','collect_admin_access','auth','storage')),
  'functions', (select coalesce(jsonb_agg(jsonb_build_object(
      'schema',n.nspname,'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),
      'security_definer',p.prosecdef,'config',p.proconfig,'acl',p.proacl::text,
      'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
      'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE'),
      'service_execute',has_function_privilege('service_role',p.oid,'EXECUTE'),
      'definition_md5',md5(pg_get_functiondef(p.oid))) order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),'[]'::jsonb)
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where p.prokind='f' and n.nspname in
      ('public','collect_hybrid','collect_security','collect_admin_access','auth')),
  'triggers', (select coalesce(jsonb_agg(jsonb_build_object(
      'schema',n.nspname,'table',c.relname,'name',t.tgname,'enabled',t.tgenabled,
      'definition_md5',md5(pg_get_triggerdef(t.oid))) order by n.nspname,c.relname,t.tgname),'[]'::jsonb)
    from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname in
      ('public','collect_hybrid','collect_security','collect_admin_access','auth')),
  'cron_jobs', (select coalesce(jsonb_agg(jsonb_build_object(
      'id',jobid,'name',jobname,'schedule',schedule,'active',active,
      'command_md5',md5(command)) order by jobid),'[]'::jsonb) from cron.job)
) as readback;
