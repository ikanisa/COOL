begin isolation level serializable;
    do $$begin if current_user<>'postgres' or current_database()<>'postgres'
      or (select rolsuper from pg_roles where rolname=current_user)
      or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
      or (select count(*) from supabase_migrations.schema_migrations)<>150
      or (select max(version) from supabase_migrations.schema_migrations)<>'20260930180000' then
      raise exception 'Exact offline sequential upgrade required';end if;end$$;
    create temp table collect_upgrade_rows(table_name text,rowdata jsonb,n bigint) on commit drop;
    create temp table collect_upgrade_counts(table_name text,n bigint) on commit drop;
    create temp table collect_upgrade_catalog on commit drop as with objects(family,object_name,identity,body) as (
      select 'schema',n.nspname::text,n.nspname::text,to_jsonb(n)-array['oid'] from pg_namespace n where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'relation',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname,
        jsonb_build_object('owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'kind',c.relkind)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_index ix on ix.indexrelid=c.oid
        left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'column',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||a.attname,
        jsonb_build_object('type',a.atttypid,'mod',a.atttypmod,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
        where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations') and a.attnum>0 and not a.attisdropped
      union all select 'routine',n.nspname||'.'||p.proname,n.nspname||'.'||p.proname||':'||pg_get_function_identity_arguments(p.oid),
        jsonb_build_object('owner',p.proowner,'acl',p.proacl,'source',p.prosrc,'config',p.proconfig,'definer',p.prosecdef,'volatile',p.provolatile,'result',p.prorettype)
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'trigger',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||t.tgname,
        jsonb_build_object('enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'constraint',n.nspname||'.'||cl.relname,n.nspname||'.'||cl.relname||':'||c.conname,to_jsonb(pg_get_constraintdef(c.oid))
        from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace n on n.oid=c.connamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'policy',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||p.polname,
        jsonb_build_object('roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
    ) select * from objects;
    do $$begin if exists(select 1 from pg_temp.collect_upgrade_catalog group by family,identity having count(*)<>1)
      or exists(select 1 from pg_temp.collect_upgrade_catalog where identity is null or object_name is null) then
      raise exception 'Catalog identity collision';end if;end$$;
    do $$declare t record;begin
      for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations') and c.relkind in ('r','p') loop
        execute format('insert into pg_temp.collect_upgrade_rows select %L,to_jsonb(t),count(*) from %I.%I t group by to_jsonb(t)',t.nspname||'.'||t.relname,t.nspname,t.relname);
        execute format('insert into pg_temp.collect_upgrade_counts select %L,count(*) from %I.%I',t.nspname||'.'||t.relname,t.nspname,t.relname);
      end loop;
    end$$;
    

-- Database-owner provisioning keeps the existing runtime-control audit guards.
-- Serialize the absence check: a conflicting BEFORE INSERT would otherwise
-- advance governance state even when ON CONFLICT skips the navigation row.
lock table public.admin_navigation_items in share row exclusive mode;

insert into public.admin_navigation_items (
  key, label, icon_key, route_path, required_permission,
  display_order, enabled, metadata, updated_reason
)
select
  'automations', 'Automations', 'manage_search', '/admin/automations',
  'system_health.read', 145, true, '{}'::jsonb,
  'Read-only payment and notification operations monitoring'
where not exists (
  select 1 from public.admin_navigation_items
  where key = 'automations' or route_path = '/admin/automations'
)
on conflict do nothing;

create table collect_security.unexpected_upgrade_probe(id integer);

    insert into supabase_migrations.schema_migrations(version,name,statements)
      values('20260930200000','admin_automation_navigation',array['begin;

-- Database-owner provisioning keeps the existing runtime-control audit guards.
-- Serialize the absence check: a conflicting BEFORE INSERT would otherwise
-- advance governance state even when ON CONFLICT skips the navigation row.
lock table public.admin_navigation_items in share row exclusive mode;

insert into public.admin_navigation_items (
  key, label, icon_key, route_path, required_permission,
  display_order, enabled, metadata, updated_reason
)
select
  ''automations'', ''Automations'', ''manage_search'', ''/admin/automations'',
  ''system_health.read'', 145, true, ''{}''::jsonb,
  ''Read-only payment and notification operations monitoring''
where not exists (
  select 1 from public.admin_navigation_items
  where key = ''automations'' or route_path = ''/admin/automations''
)
on conflict do nothing;

create table collect_security.unexpected_upgrade_probe(id integer);
commit;
']);
    create temp table collect_upgrade_catalog_after on commit drop as with objects(family,object_name,identity,body) as (
      select 'schema',n.nspname::text,n.nspname::text,to_jsonb(n)-array['oid'] from pg_namespace n where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'relation',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname,
        jsonb_build_object('owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'kind',c.relkind)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_index ix on ix.indexrelid=c.oid
        left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'column',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||a.attname,
        jsonb_build_object('type',a.atttypid,'mod',a.atttypmod,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
        where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations') and a.attnum>0 and not a.attisdropped
      union all select 'routine',n.nspname||'.'||p.proname,n.nspname||'.'||p.proname||':'||pg_get_function_identity_arguments(p.oid),
        jsonb_build_object('owner',p.proowner,'acl',p.proacl,'source',p.prosrc,'config',p.proconfig,'definer',p.prosecdef,'volatile',p.provolatile,'result',p.prorettype)
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'trigger',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||t.tgname,
        jsonb_build_object('enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'constraint',n.nspname||'.'||cl.relname,n.nspname||'.'||cl.relname||':'||c.conname,to_jsonb(pg_get_constraintdef(c.oid))
        from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace n on n.oid=c.connamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'policy',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||p.polname,
        jsonb_build_object('roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
    ) select * from objects;
    do $$declare t record;missing boolean;delta bigint;new_xid bigint;append_count bigint:=0;begin
      for t in select * from pg_temp.collect_upgrade_counts loop
        execute format('select exists(select 1 from pg_temp.collect_upgrade_rows b where b.table_name=%L and b.n>(select count(*) from %s t where to_jsonb(t)=b.rowdata))',t.table_name,t.table_name) into missing;
        if missing then raise exception 'Original row removed or changed in %',t.table_name;end if;
        execute format('select count(*)-%s from %s',t.n,t.table_name) into delta;
        if t.table_name='supabase_migrations.schema_migrations' then
          if delta<>1 then raise exception 'Migration registry delta invalid';end if;
        elsif t.table_name=any(array['public.admin_navigation_items','collect_security.runtime_control_heads','collect_security.runtime_control_events','public.app_realtime_events']::text[]) then
          if delta not in (0,1) then raise exception 'Append delta invalid in %',t.table_name;end if;
          execute format('select count(*) from %s where xmin::text::bigint=pg_current_xact_id()::text::bigint',t.table_name) into new_xid;
          if new_xid<>delta then raise exception 'Unattributed append in %',t.table_name;end if;
          append_count:=append_count+delta;
        elsif delta<>0 then raise exception 'Unexpected row insertion in %',t.table_name;end if;
      end loop;
      if append_count not in (0,4) then raise exception 'Navigation governance append incomplete';end if;
      missing:=false;
      for t in select b.family,b.identity,encode(extensions.digest(b.body::text,'sha256'),'hex') old_hash,
        encode(extensions.digest(a.body::text,'sha256'),'hex') new_hash
        from pg_temp.collect_upgrade_catalog b left join pg_temp.collect_upgrade_catalog_after a using(family,identity)
        where a.identity is null or a.body is distinct from b.body and not (b.family='routine' and b.object_name=any(array[]::text[])) loop
        raise notice 'CATALOG_DIFF|%|%|%|%',t.family,t.identity,t.old_hash,t.new_hash;
        missing:=true;
      end loop;
      if missing then raise exception 'Unexpected original catalog mutation';end if;
      if exists(select 1 from pg_temp.collect_upgrade_catalog_after a left join pg_temp.collect_upgrade_catalog b using(family,identity)
        where b.identity is null and not(a.object_name=any(array[]::text[]))) then
        raise exception 'Unexpected new catalog object';end if;
      if (select count(*) from supabase_migrations.schema_migrations)<>151 then raise exception 'Wrong installed count';end if;
      raise notice 'STAGED_UPGRADE_ROWS_PRESERVED|%|%',(select count(*) from pg_temp.collect_upgrade_counts),append_count;
    end$$;
    do $$begin if not exists(select 1 from public.admin_navigation_items n
          join collect_security.runtime_control_heads h on h.family='admin_navigation_items' and h.identity=jsonb_build_object('key',n.key)
          where n.key='automations' and n.route_path='/admin/automations' and n.required_permission='system_health.read'
            and n.enabled and h.content_sha256=collect_security.runtime_control_hash(to_jsonb(n))) then
          raise exception 'Navigation provision integrity failed';end if;end$$;
commit;
