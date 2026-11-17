// Candidate release pins; the database checks the actual migration and guards.
export const HELD_V2_PROTOCOL='burimunsi.held-recovery.v2';
export const HELD_V2_MIGRATION_SHA='89e9c06005bdd4f939d70c1e5e473379e068cfc72b9c0483c96e071e7208ebf5';
export const HELD_V2_READY_SHA='0dc05aea54573d01475395454826609b84797326ec4ca5b9711bf2413a0bfa0d';
export const HELD_V2_READY_IDENTITY_SQL=`SELECT coalesce(p.proowner='postgres'::regrole AND p.prosecdef
 AND p.provolatile='v' AND l.lanname='plpgsql' AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
 AND p.proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}'
 AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=$1,false) AS ok
 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
 WHERE p.oid=to_regprocedure('private.burimunsi_held_v2_ready(text,bigint,text)')`;
