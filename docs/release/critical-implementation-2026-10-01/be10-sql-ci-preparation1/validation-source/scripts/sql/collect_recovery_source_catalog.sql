-- PostgreSQL17 read-only recovery identity. Names replace OIDs; source/default/
-- configuration values are hashed. This does not read business or Auth rows.
-- Full archive data, schema and role comparisons remain separate requirements.
-- NULL ACLs expand to PostgreSQL defaults: pg_dump may omit redundant default
-- ACL entries. Explicit empty ACLs retain zero grants; all entries remain intact.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL timezone = 'UTC';
SET LOCAL statement_timeout = '120s';
WITH ns AS (
  SELECT * FROM pg_namespace WHERE left(nspname,3) <> 'pg_' AND nspname <> 'information_schema'
), rel AS (
  SELECT c.*, n.nspname FROM pg_class c JOIN ns n ON n.oid=c.relnamespace
), routine AS (
  SELECT p.*, n.nspname FROM pg_proc p JOIN ns n ON n.oid=p.pronamespace
), dependency AS (
  SELECT d.deptype, a.type AS object_type, a.schema AS object_schema,
    a.identity AS object_identity, b.type AS referenced_type,
    b.schema AS referenced_schema, b.identity AS referenced_identity
  FROM pg_depend d
  CROSS JOIN LATERAL pg_identify_object(d.classid,d.objid,d.objsubid) a
  CROSS JOIN LATERAL pg_identify_object(d.refclassid,d.refobjid,d.refobjsubid) b
  WHERE (a.schema IN (SELECT nspname FROM ns) OR b.schema IN (SELECT nspname FROM ns))
    -- Rebuilt TOAST names and internal FK trigger names contain source OIDs.
    -- Their logical table/column/constraint definitions are compared above.
    AND (a.schema IS NULL OR left(a.schema,3) <> 'pg_')
    AND NOT (d.classid='pg_trigger'::regclass AND EXISTS (
      SELECT 1 FROM pg_trigger t WHERE t.oid=d.objid AND t.tgisinternal))
)
SELECT jsonb_build_object(
 'format','collect-recovery-catalog-v1',
 'server',jsonb_build_object('major',current_setting('server_version_num')::integer/10000,
                            'version',current_setting('server_version')),
 'database',(SELECT jsonb_build_object('name',datname,'owner',pg_get_userbyid(datdba),
   'encoding',pg_encoding_to_char(encoding),'locale_provider',datlocprovider,
   'collate',datcollate,'ctype',datctype,'locale',datlocale,
   'icu_rules_sha256',encode(sha256(convert_to(daticurules,'UTF8')),'hex'),
   'collation_version',datcollversion,'connection_limit',datconnlimit,
   'acl',to_jsonb(ARRAY(SELECT x::text FROM unnest(coalesce(datacl,acldefault('d',datdba))) x ORDER BY x::text COLLATE "C")))
   FROM pg_database WHERE datname=current_database()),
 'migrations',(SELECT coalesce(jsonb_agg(version::text ORDER BY version::text COLLATE "C"),'[]')
   FROM supabase_migrations.schema_migrations),
 'schemas',(SELECT coalesce(jsonb_agg(jsonb_build_array(nspname,pg_get_userbyid(nspowner),
   to_jsonb(ARRAY(SELECT x::text FROM unnest(coalesce(nspacl,acldefault('n',nspowner))) x ORDER BY x::text COLLATE "C")))
   ORDER BY nspname COLLATE "C"),'[]') FROM ns),
 'extensions',(SELECT coalesce(jsonb_agg(jsonb_build_array(e.extname,e.extversion,n.nspname,
   pg_get_userbyid(e.extowner)) ORDER BY e.extname COLLATE "C"),'[]')
   FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace),
 'roles',(SELECT coalesce(jsonb_agg(jsonb_build_array(rolname,rolsuper,rolinherit,rolcreaterole,
   rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,rolconnlimit,rolvaliduntil::text,
   encode(sha256(convert_to(ARRAY(SELECT x FROM unnest(rolconfig) x ORDER BY x COLLATE "C")::text,'UTF8')),'hex'))
   ORDER BY rolname COLLATE "C"),'[]') FROM pg_roles),
 'memberships',(SELECT coalesce(jsonb_agg(jsonb_build_array(pg_get_userbyid(roleid),
   pg_get_userbyid(member),pg_get_userbyid(grantor),admin_option,inherit_option,set_option)
   ORDER BY pg_get_userbyid(roleid) COLLATE "C",pg_get_userbyid(member) COLLATE "C",
   pg_get_userbyid(grantor) COLLATE "C"),'[]') FROM pg_auth_members),
 'settings',(SELECT coalesce(jsonb_agg(jsonb_build_array(
   CASE WHEN setdatabase=0 THEN '*' ELSE current_database() END,
   CASE WHEN setrole=0 THEN '*' ELSE pg_get_userbyid(setrole) END,
   encode(sha256(convert_to(ARRAY(SELECT x FROM unnest(setconfig) x ORDER BY x COLLATE "C")::text,'UTF8')),'hex'))
   ORDER BY setdatabase=0,CASE WHEN setrole=0 THEN '*' ELSE pg_get_userbyid(setrole) END COLLATE "C"),'[]')
   FROM pg_db_role_setting WHERE setdatabase=0 OR setdatabase=(SELECT oid FROM pg_database WHERE datname=current_database())),
 'relations',(SELECT coalesce(jsonb_agg(jsonb_build_array(nspname,relname,relkind,
   relpersistence,pg_get_userbyid(relowner),relrowsecurity,relforcerowsecurity,
   to_jsonb(ARRAY(SELECT x::text FROM unnest(coalesce(relacl,
     acldefault(CASE WHEN relkind='S' THEN 's'::"char" ELSE 'r'::"char" END,relowner))) x ORDER BY x::text COLLATE "C")),
   to_jsonb(ARRAY(SELECT x FROM unnest(reloptions) x ORDER BY x COLLATE "C")),
   CASE WHEN relkind IN ('v','m') THEN encode(sha256(convert_to(pg_get_viewdef(oid),'UTF8')),'hex') END)
   ORDER BY nspname COLLATE "C",relname COLLATE "C"),'[]') FROM rel),
 'columns',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.nspname,c.relname,a.attnum,
   a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attidentity,a.attgenerated,
   to_jsonb(ARRAY(SELECT x::text FROM unnest(coalesce(a.attacl,acldefault('c',c.relowner))) x ORDER BY x::text COLLATE "C")),
   encode(sha256(convert_to(pg_get_expr(d.adbin,d.adrelid),'UTF8')),'hex'),
   CASE WHEN a.attcollation=0 THEN NULL ELSE a.attcollation::regcollation::text END)
   ORDER BY c.nspname COLLATE "C",c.relname COLLATE "C",a.attnum),'[]')
   FROM rel c JOIN pg_attribute a ON a.attrelid=c.oid
   LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_array(n.nspname,
   CASE WHEN k.conrelid=0 THEN k.contypid::regtype::text ELSE k.conrelid::regclass::text END,
   k.conname,k.contype,k.convalidated,k.condeferrable,k.condeferred,
   encode(sha256(convert_to(pg_get_constraintdef(k.oid),'UTF8')),'hex'))
   ORDER BY n.nspname COLLATE "C",k.conrelid::regclass::text COLLATE "C",
   k.contypid::regtype::text COLLATE "C",k.conname COLLATE "C"),'[]')
   FROM pg_constraint k JOIN ns n ON n.oid=k.connamespace),
 'indexes',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.nspname,c.relname,
   i.indisvalid,i.indisready,i.indislive,encode(sha256(convert_to(pg_get_indexdef(c.oid),'UTF8')),'hex'))
   ORDER BY c.nspname COLLATE "C",c.relname COLLATE "C"),'[]') FROM rel c JOIN pg_index i ON i.indexrelid=c.oid),
 'functions',(SELECT coalesce(jsonb_agg(jsonb_build_array(nspname,proname,
   pg_get_function_identity_arguments(oid),prokind,pg_get_userbyid(proowner),
   prosecdef,provolatile,proparallel,proleakproof,proisstrict,
   to_jsonb(ARRAY(SELECT x::text FROM unnest(coalesce(proacl,acldefault('f',proowner))) x ORDER BY x::text COLLATE "C")),
   encode(sha256(convert_to(prosrc,'UTF8')),'hex'),
   CASE WHEN prokind <> 'a' THEN encode(sha256(convert_to(pg_get_functiondef(oid),'UTF8')),'hex') END)
   ORDER BY nspname COLLATE "C",proname COLLATE "C",pg_get_function_identity_arguments(oid) COLLATE "C"),'[]') FROM routine),
 'policies',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.nspname,c.relname,p.polname,
   p.polcmd,p.polpermissive,to_jsonb(ARRAY(SELECT CASE WHEN x=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x) END
     FROM unnest(p.polroles) x ORDER BY CASE WHEN x=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x) END COLLATE "C")),
   encode(sha256(convert_to(pg_get_expr(p.polqual,p.polrelid),'UTF8')),'hex'),
   encode(sha256(convert_to(pg_get_expr(p.polwithcheck,p.polrelid),'UTF8')),'hex'))
   ORDER BY c.nspname COLLATE "C",c.relname COLLATE "C",p.polname COLLATE "C"),'[]')
   FROM pg_policy p JOIN rel c ON c.oid=p.polrelid),
 'triggers',(SELECT coalesce(jsonb_agg(jsonb_build_array(c.nspname,c.relname,t.tgname,t.tgenabled,
   encode(sha256(convert_to(pg_get_triggerdef(t.oid),'UTF8')),'hex'))
   ORDER BY c.nspname COLLATE "C",c.relname COLLATE "C",t.tgname COLLATE "C"),'[]')
   FROM pg_trigger t JOIN rel c ON c.oid=t.tgrelid WHERE NOT t.tgisinternal),
 'default_acls',(SELECT coalesce(jsonb_agg(jsonb_build_array(pg_get_userbyid(d.defaclrole),
   CASE WHEN d.defaclnamespace=0 THEN '*' ELSE n.nspname END,d.defaclobjtype,
   to_jsonb(ARRAY(SELECT x::text FROM unnest(d.defaclacl) x ORDER BY x::text COLLATE "C")))
   ORDER BY pg_get_userbyid(d.defaclrole) COLLATE "C",coalesce(n.nspname,'*') COLLATE "C",d.defaclobjtype),'[]')
   FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
   WHERE d.defaclnamespace=0 OR n.nspname IN (SELECT nspname FROM ns)),
 'types',(SELECT coalesce(jsonb_agg(jsonb_build_array(n.nspname,t.typname,t.typtype,
   pg_get_userbyid(t.typowner),t.typnotnull,t.typbasetype::regtype::text,
   encode(sha256(convert_to(t.typdefault,'UTF8')),'hex'),
   to_jsonb(ARRAY(SELECT x::text FROM unnest(coalesce(t.typacl,acldefault('T',t.typowner))) x ORDER BY x::text COLLATE "C")),
   (SELECT coalesce(jsonb_agg(e.enumlabel ORDER BY e.enumsortorder),'[]') FROM pg_enum e WHERE e.enumtypid=t.oid))
   ORDER BY n.nspname COLLATE "C",t.typname COLLATE "C"),'[]') FROM pg_type t JOIN ns n ON n.oid=t.typnamespace),
 'event_triggers',(SELECT coalesce(jsonb_agg(jsonb_build_array(evtname,evtevent,
   pg_get_userbyid(evtowner),evtfoid::regprocedure::text,evtenabled,
   to_jsonb(ARRAY(SELECT x FROM unnest(evttags) x ORDER BY x COLLATE "C"))) ORDER BY evtname COLLATE "C"),'[]') FROM pg_event_trigger),
 'dependencies',(SELECT coalesce(jsonb_agg(jsonb_build_array(deptype,object_type,object_schema,
   object_identity,referenced_type,referenced_schema,referenced_identity)
   ORDER BY deptype,object_type COLLATE "C",object_schema COLLATE "C",object_identity COLLATE "C",
   referenced_type COLLATE "C",referenced_schema COLLATE "C",referenced_identity COLLATE "C"),'[]') FROM dependency)
);
COMMIT;
