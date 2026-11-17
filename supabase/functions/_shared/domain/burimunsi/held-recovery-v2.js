// Candidate release pins; the database checks the actual migration and guards.
export const HELD_V2_PROTOCOL='burimunsi.held-recovery.v2';
export const HELD_V2_MIGRATION_SHA='5108ab3821cca114d8ce737c6f0d7b9eaefc2982d16ab2056b817b898a6f7aa6';
export const HELD_V2_READY_SHA='737f1c0b1860669cfd68a815da690954f75a29133dd6cd09174c0beab5cecdd5';
export const HELD_V2_READY_IDENTITY_SQL=`SELECT coalesce(p.proowner='postgres'::regrole AND p.prosecdef
 AND p.provolatile='v' AND l.lanname='plpgsql' AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
 AND p.proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}'
 AND NOT EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.rolname NOT IN('postgres','collect_runtime')
  AND (has_function_privilege(r.oid,p.oid,'EXECUTE') OR pg_has_role(r.oid,'collect_runtime','MEMBER')))
 AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=$1,false) AS ok
 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
 WHERE p.oid=to_regprocedure('private.burimunsi_held_v2_ready(text,bigint,text)')`;
