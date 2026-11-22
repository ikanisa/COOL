-- Candidate only: forward fix for an already installed retention helper.
-- Not a recorded migration, not applied to either real database, and not
-- qualified for managed use. Existing history and its hashes remain intact.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $migration$
DECLARE body text;next_body text;
 old_guard text:=$old$p_subject !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'$old$;
 new_guard text:=$new$p_subject !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'$new$;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM private.collect_fence_control)<>1
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure('private._burimunsi_retention_positive_links_v1(text,text)')
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND p.provolatile='s'
   AND p.prokind='f' AND p.proparallel='u' AND NOT p.proleakproof AND NOT p.proretset
   AND l.lanname='plpgsql' AND p.proacl::text='{postgres=X/postgres}'
   AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
   AND pg_get_function_identity_arguments(p.oid)='p_subject text, p_class text'
   AND pg_get_function_result(p.oid)='jsonb'
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='3124613986def2fde264d20fc75c3b5974ad9e093dc6b623175c5b03cbbab583') THEN
  RAISE EXCEPTION 'retention_user_id_forward_precondition' USING ERRCODE='55000';
 END IF;
 SELECT prosrc INTO STRICT body FROM pg_proc
  WHERE oid='private._burimunsi_retention_positive_links_v1(text,text)'::regprocedure;
 IF length(body)-length(replace(body,old_guard,''))<>length(old_guard) THEN
  RAISE EXCEPTION 'retention_user_id_forward_anchor_changed' USING ERRCODE='55000';
 END IF;
 next_body:=replace(body,old_guard,new_guard);
 IF encode(sha256(convert_to(next_body,'UTF8')),'hex')<>'f35281816661c456bc0e3e17bc0c70961bbef2160cfed729d8e0463cf79ac7a7' THEN
  RAISE EXCEPTION 'retention_user_id_forward_postimage_changed' USING ERRCODE='55000';
 END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION private._burimunsi_retention_positive_links_v1(p_subject text,p_class text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='private._burimunsi_retention_positive_links_v1(text,text)'::regprocedure
  AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND p.proacl::text='{postgres=X/postgres}'
  AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
  AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='f35281816661c456bc0e3e17bc0c70961bbef2160cfed729d8e0463cf79ac7a7') THEN
  RAISE EXCEPTION 'retention_user_id_forward_postcondition' USING ERRCODE='55000';
 END IF;
END;$migration$;
COMMIT;
