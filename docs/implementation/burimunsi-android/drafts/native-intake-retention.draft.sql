-- UNREGISTERED DRAFT.  This catalog addition is inspection-only: it assigns no
-- subject ownership or disposition to native provenance. Unknown counts and
-- object custody continue to block erasure and completion. Requires the exact
-- reviewed retention predecessor and native-intake draft in the same release.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $install$
DECLARE r record;body text;next_body text;anchor text;replacement text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regclass('private.burimunsi_native_receipt_origins') IS NULL
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') e
   WHERE e->>'relation'='private.burimunsi_native_receipt_origins' OR e->>'name'='private:burimunsi_native_receipt_origins')
 THEN RAISE EXCEPTION 'burimunsi_native_retention_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM (VALUES
  ('private._retention_manifest_catalog_v2()','e03d4606ccbfed5f102fb45ac8c05da8be1ae84f6964e56b1cec42633b1614a4',false,'i',ARRAY['search_path=pg_catalog, pg_temp']::text[],'sql','{postgres=X/postgres}'),
  ('private._retention_manifest_rows_v2(text)','5aa6ca4011d0fa45e644066da4e90fd74fa55fe0c115a13c047e5399319a30a0',true,'s',ARRAY['search_path=app, pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','0cdbf6ed4a27b797061898350f0ae32dec47cf2bc2ca25fbafc6802ac60e414e',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) e(sig,hash,definer,volatility,config,language,acl) LOOP
  IF to_regprocedure(r.sig) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(r.sig) AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=r.definer
   AND p.provolatile=r.volatility AND p.prokind='f' AND p.proparallel='u' AND NOT p.proleakproof
   AND l.lanname=r.language AND p.proacl::text=r.acl AND p.proconfig=r.config
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.hash)
  THEN RAISE EXCEPTION 'burimunsi_native_retention_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 next_body:='SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||''[{"name":"private:burimunsi_native_receipt_origins","relation":"private.burimunsi_native_receipt_origins","scope":"unmapped_private","purpose":"Unreviewed subject mapping and object custody; inspection only, effects blocked","blocked":true}]''::jsonb) FROM ('||body||') prior(base)';
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
 anchor:=$a$'private:burimunsi_worker_grants','private:storage_payload_reservations'$a$;
 replacement:=$b$'private:burimunsi_worker_grants','private:burimunsi_native_receipt_origins','private:storage_payload_reservations'$b$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor)
 THEN RAISE EXCEPTION 'burimunsi_native_retention_anchor_changed' USING ERRCODE='55000';END IF;
 next_body:=replace(body,anchor,replacement);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
END;$install$;
COMMIT;
