// Candidate release pins; the database checks the actual migration and guards.
export const HELD_V2_PROTOCOL='burimunsi.held-recovery.v2';
export const HELD_V2_MIGRATION_SHA='5a290aba0da81db64946c22e8fb11bab6ffc22ffd9e5bf05814cabc301e38206';
export const HELD_V2_READY_SHA='d89d94e8388ced1a36cb3897db640fff6592a91fff58bf8d172fae42fddc5f51';
export const HELD_V2_UNEXPECTED_ROLE_SQL=`EXISTS(SELECT 1 FROM pg_roles r
 WHERE NOT r.rolsuper AND r.rolname NOT IN('postgres','collect_runtime')
 AND (has_function_privilege(r.oid,p.oid,'EXECUTE') OR
  (pg_has_role(r.oid,'collect_runtime','MEMBER') AND NOT (
   r.rolname='cli_login_postgres' AND r.rolcanlogin AND NOT r.rolinherit
   AND NOT r.rolcreaterole AND NOT r.rolcreatedb AND NOT r.rolreplication AND NOT r.rolbypassrls
   AND EXISTS(SELECT 1 FROM pg_roles owner_role WHERE owner_role.rolname='postgres'
    AND NOT owner_role.rolsuper AND owner_role.rolcanlogin AND owner_role.rolinherit
    AND owner_role.rolcreaterole AND owner_role.rolbypassrls)
   AND (SELECT count(*) FROM pg_auth_members d WHERE d.member=r.oid)=1
   AND EXISTS(SELECT 1 FROM pg_auth_members d WHERE d.member=r.oid AND d.roleid=to_regrole('postgres')
    AND d.grantor=to_regrole('supabase_admin') AND NOT d.admin_option AND NOT d.inherit_option AND d.set_option)
   AND (SELECT count(*) FROM pg_auth_members d WHERE d.member=to_regrole('postgres')
    AND d.roleid=to_regrole('collect_runtime'))=2
   AND EXISTS(SELECT 1 FROM pg_auth_members d WHERE d.member=to_regrole('postgres') AND d.roleid=to_regrole('collect_runtime')
    AND d.grantor=to_regrole('postgres') AND NOT d.admin_option AND NOT d.inherit_option AND d.set_option)
   AND EXISTS(SELECT 1 FROM pg_auth_members d WHERE d.member=to_regrole('postgres') AND d.roleid=to_regrole('collect_runtime')
    AND d.grantor=to_regrole('supabase_admin') AND d.admin_option AND NOT d.inherit_option AND NOT d.set_option)
  )))
)`;
export const HELD_V2_READY_IDENTITY_SQL=`SELECT coalesce(p.proowner='postgres'::regrole AND p.prosecdef
 AND p.provolatile='v' AND l.lanname='plpgsql' AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
 AND p.proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}'
 AND NOT ${HELD_V2_UNEXPECTED_ROLE_SQL}
 AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=$1,false) AS ok
 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
 WHERE p.oid=to_regprocedure('private.burimunsi_held_v2_ready(text,bigint,text)')`;
