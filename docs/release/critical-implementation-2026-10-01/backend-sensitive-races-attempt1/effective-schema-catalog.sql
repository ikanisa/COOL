with scopes as (
 select oid,nspname,nspowner,nspacl from pg_namespace
 where nspname in('public','auth','storage','extensions','net','supabase_migrations')or nspname like 'collect\_%'escape '\'
), relations as (
 select c.* from pg_class c join scopes n on n.oid=c.relnamespace
 where c.relkind in('r','p','v','m','S','f')
), functions as (
 select p.* from pg_proc p join scopes n on n.oid=p.pronamespace
)
select jsonb_build_object(
 'schemas',(select coalesce(jsonb_agg(jsonb_build_object('schema',nspname,'owner',pg_get_userbyid(nspowner),
  'acl',nspacl,'effective_acl',coalesce(nspacl,acldefault('n',nspowner)))order by nspname),'[]')from scopes),
 'relations',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'kind',c.relkind,
  'owner',pg_get_userbyid(c.relowner),'row_security',c.relrowsecurity,'force_row_security',c.relforcerowsecurity,
  'acl',c.relacl,'effective_acl',coalesce(c.relacl,acldefault(case when c.relkind='S'then 's'else 'r'end::"char",c.relowner)))
  order by n.nspname,c.relname),'[]')from relations c join scopes n on n.oid=c.relnamespace),
 'functions',(select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'schema',n.nspname,
  'name',p.proname,'kind',p.prokind,'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,
  'configuration',p.proconfig,'acl',p.proacl,'effective_acl',coalesce(p.proacl,acldefault('f',p.proowner)),
  'language',l.lanname,'return_type',pg_get_function_result(p.oid),
  'definition',case when p.prokind in('f','p')and(n.nspname='public'or n.nspname like 'collect\_%'escape '\')then pg_get_functiondef(p.oid)end)
  order by n.nspname,p.proname,p.oid::regprocedure::text),'[]')from functions p join scopes n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang),
 'column_acl',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'column',a.attname,
  'owner',pg_get_userbyid(c.relowner),'acl',a.attacl)order by n.nspname,c.relname,a.attnum),'[]')
  from pg_attribute a join relations c on c.oid=a.attrelid join scopes n on n.oid=c.relnamespace where a.attnum>0 and not a.attisdropped and a.attacl is not null),
 'default_acl',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'owner',pg_get_userbyid(d.defaclrole),
  'object_kind',d.defaclobjtype,'acl',d.defaclacl)order by coalesce(n.nspname,''),d.defaclrole,d.defaclobjtype),'[]')
  from pg_default_acl d left join scopes n on n.oid=d.defaclnamespace where d.defaclnamespace=0 or n.oid is not null),
 'policies',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'name',p.polname,
  'command',p.polcmd,'permissive',p.polpermissive,'roles',p.polroles,'using',pg_get_expr(p.polqual,p.polrelid),
  'with_check',pg_get_expr(p.polwithcheck,p.polrelid))order by n.nspname,c.relname,p.polname),'[]')
  from pg_policy p join relations c on c.oid=p.polrelid join scopes n on n.oid=c.relnamespace),
 'platform_normalized',true,'hosted_schema_observed',false,'table_row_data_exported',false);
