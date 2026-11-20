-- Forward-only candidate: both existing positive-link readers accept the
-- application's bounded user-ID format. Retention and erasure remain blocked.
-- This file is not deployed and does not rewrite any historical migration.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $migration$
DECLARE item record;body text;changed text;
 old_guard text:=$old$p_subject !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'$old$;
 new_guard text:=$new$p_subject !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'$new$;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM private.collect_fence_control)<>1
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private._retention_manifest_rows_v2(text)')
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND p.provolatile='s'
   AND p.proacl::text='{postgres=X/postgres}' AND p.proconfig=ARRAY['search_path=app, pg_catalog, pg_temp']::text[]
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='25597e57accb602949e65108db895113ee66e657b5c20e4cc1fbbdabf266973a') THEN
  RAISE EXCEPTION 'retention_text_subject_precondition' USING ERRCODE='55000';
 END IF;
 FOR item IN SELECT * FROM(VALUES
  ('private._burimunsi_retention_positive_links_v1(text,text)','private._burimunsi_retention_positive_links_v1',
   '3124613986def2fde264d20fc75c3b5974ad9e093dc6b623175c5b03cbbab583','f35281816661c456bc0e3e17bc0c70961bbef2160cfed729d8e0463cf79ac7a7'),
  ('private._burimunsi_retention_evidence_v2(text,text)','private._burimunsi_retention_evidence_v2',
   '0c256f792a377bb868faefee3d81d5dee310db86380f20a4c56444bd2a7cb852','2a37dc0e053bb3146e46d8a6f7ce76afc02c16fe6574f3a2a2781064d16c617a')
 ) AS expected(signature,fn,prehash,posthash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(item.signature) AND pg_get_userbyid(p.proowner)='postgres'
    AND p.prosecdef AND p.provolatile='s' AND p.prokind='f' AND p.proparallel='u'
    AND NOT p.proleakproof AND NOT p.proretset AND l.lanname='plpgsql'
    AND p.proacl::text='{postgres=X/postgres}' AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
    AND pg_get_function_identity_arguments(p.oid)='p_subject text, p_class text'
    AND pg_get_function_result(p.oid)='jsonb'
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=item.prehash) THEN
   RAISE EXCEPTION 'retention_text_subject_precondition' USING ERRCODE='55000';
  END IF;
  SELECT p.prosrc INTO STRICT body FROM pg_proc p WHERE p.oid=to_regprocedure(item.signature);
  IF length(body)-length(replace(body,old_guard,''))<>length(old_guard) THEN
   RAISE EXCEPTION 'retention_text_subject_anchor_changed' USING ERRCODE='55000';
  END IF;
  changed:=replace(body,old_guard,new_guard);
  IF encode(sha256(convert_to(changed,'UTF8')),'hex')<>item.posthash THEN
   RAISE EXCEPTION 'retention_text_subject_postimage_changed' USING ERRCODE='55000';
  END IF;
  EXECUTE 'CREATE OR REPLACE FUNCTION '||item.fn||'(p_subject text,p_class text) RETURNS jsonb '
   ||'LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(changed);
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(item.signature)
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND p.proacl::text='{postgres=X/postgres}'
   AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=item.posthash) THEN
   RAISE EXCEPTION 'retention_text_subject_postcondition' USING ERRCODE='55000';
  END IF;
 END LOOP;
END;$migration$;
COMMIT;
