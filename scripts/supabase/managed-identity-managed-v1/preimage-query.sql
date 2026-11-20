-- SELECT only, and aggregate catalogue evidence only. Project identity must be
-- independently verified from the authenticated provider endpoint. No rows,
-- credentials, profiles, object content or SQL statement text are returned.
WITH h AS (
 SELECT count(*)::integer AS n,
  encode(sha256(convert_to(coalesce(jsonb_agg(jsonb_build_array(version,name,statements) ORDER BY version)::text,'[]'),'UTF8')),'hex') AS digest,
  count(*) FILTER(WHERE version='20261022195747' AND name='collect_application_mutation_fence' AND cardinality(statements)=1
    AND encode(sha256(convert_to(statements[1],'UTF8')),'hex')='714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497')=1 AS fence,
  count(*) FILTER(WHERE version='20261101012309' AND name='collect_admission_archive' AND cardinality(statements)=1
    AND encode(sha256(convert_to(statements[1],'UTF8')),'hex')='82b09d4d2abd5994429a978ccf80daa796fd83e5dc5d29bc54076f2b7565ad84')=1 AS archive,
  count(*) FILTER(WHERE version='20261101013157' AND name='collect_deployment_identity' AND cardinality(statements)=1
    AND encode(sha256(convert_to(statements[1],'UTF8')),'hex')='916a7b3012135484c74f0a6b4707cdda39c637959f8564233fc8f6a8f5adbdc1')=1 AS identity
 FROM supabase_migrations.schema_migrations
), ids AS (
 SELECT (SELECT oid FROM pg_roles WHERE rolname='postgres') AS owner,
  (SELECT oid FROM pg_roles WHERE rolname='supabase_admin') AS provider,
  (SELECT oid FROM pg_roles WHERE rolname='cli_login_postgres') AS cli
), membership AS (
 SELECT count(*)::integer AS direct_count,
  min(m.oid::bigint) FILTER(WHERE m.roleid=ids.owner AND m.grantor=ids.provider AND m.set_option
   AND NOT m.inherit_option AND NOT m.admin_option) AS expected_oid
 FROM ids LEFT JOIN pg_auth_members m ON m.member=ids.cli
 WHERE m.oid IS NOT NULL
), roles AS (
 SELECT ids.*,
  EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=ids.owner AND NOT r.rolsuper AND r.rolcanlogin AND r.rolinherit
   AND r.rolcreatedb AND r.rolcreaterole AND r.rolreplication AND r.rolbypassrls) AS owner_ok,
  EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=ids.provider AND r.rolsuper) AS provider_ok,
  EXISTS(SELECT 1 FROM pg_roles r WHERE r.oid=ids.cli AND r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolinherit
   AND NOT r.rolcreatedb AND NOT r.rolcreaterole AND NOT r.rolreplication AND NOT r.rolbypassrls AND r.rolconnlimit=-1) AS cli_ok,
  NOT EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.oid NOT IN(ids.owner,ids.cli)
   AND (pg_has_role(r.oid,ids.owner,'MEMBER') OR pg_has_role(r.oid,ids.cli,'MEMBER'))) AS owner_paths_ok,
  NOT EXISTS(SELECT 1 FROM pg_roles r CROSS JOIN pg_roles s WHERE NOT r.rolsuper AND s.rolsuper
   AND pg_has_role(r.oid,s.oid,'MEMBER')) AS superuser_paths_ok
 FROM ids
), scheduler AS (
 SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') AS digest,
  (pg_get_userbyid(p.proowner)='postgres' AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='v' AND NOT p.proisstrict
   AND p.prorettype='jsonb'::regtype AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
   AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee<>p.proowner)) AS metadata_ok
 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('private._collect_fence_scheduler_status()')
), observed AS (SELECT clock_timestamp() AS at)
SELECT jsonb_build_object(
 'observedAt',to_char(observed.at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'suggestedValidUntil',to_char((observed.at+interval '10 minutes') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'database',current_database(),'serverVersion',current_setting('server_version_num')::integer,
 'sessionUser',session_user,'currentUser',current_user,'role',current_setting('role',true),
 'history',jsonb_build_object('count',h.n,'sha256',h.digest,'fence',h.fence,'archive',h.archive,'identity',h.identity),
 'roleOids',jsonb_build_object('owner',roles.owner::bigint,'provider',roles.provider::bigint,'cli',roles.cli::bigint,'membership',membership.expected_oid),
 'roleChecks',jsonb_build_object('owner',roles.owner_ok,'provider',roles.provider_ok,'cli',roles.cli_ok,
  'ownerPaths',roles.owner_paths_ok,'superuserPaths',roles.superuser_paths_ok,'directMembershipCount',membership.direct_count),
 'scheduler',jsonb_build_object('sha256',(SELECT digest FROM scheduler),'metadataOk',coalesce((SELECT metadata_ok FROM scheduler),false))
) AS preimage_observation FROM h CROSS JOIN roles CROSS JOIN membership CROSS JOIN observed;
