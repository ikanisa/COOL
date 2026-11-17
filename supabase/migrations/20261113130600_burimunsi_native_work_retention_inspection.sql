-- Inventory the new shared native-work classes without asserting a complete
-- subject selector or authorizing erasure. Existing blocked classes remain so.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $install$
DECLARE r record;body text;next_body text;anchor text;replacement text;additions jsonb;
 names text[]:=ARRAY['burimunsi_native_financial_work','burimunsi_native_grant_commands','burimunsi_native_work_grants'];
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'native_work_retention_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM (VALUES
  ('private._retention_manifest_catalog_v2()','75deddb08514c8ff8feac3f489cff24e5f389566b6cb97c26c4fa84af2f9a01b',false,'i',ARRAY['search_path=pg_catalog, pg_temp']::text[],'sql','{postgres=X/postgres}'),
  ('private._retention_manifest_rows_v2(text)','5aa6ca4011d0fa45e644066da4e90fd74fa55fe0c115a13c047e5399319a30a0',true,'s',ARRAY['search_path=app, pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','c8e3aab919cb31382ab38e1f3bf6c048648dee7e1e2133e84f4aee14196342da',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) e(sig,hash,definer,volatility,config,language,acl) LOOP
  IF to_regprocedure(r.sig) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
    WHERE p.oid=to_regprocedure(r.sig) AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=r.definer
    AND p.provolatile=r.volatility AND p.prokind='f' AND p.proparallel='u' AND NOT p.proleakproof
    AND l.lanname=r.language AND p.proacl::text=r.acl AND p.proconfig=r.config
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.hash) THEN
   RAISE EXCEPTION 'native_work_retention_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM unnest(names) n WHERE NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace p ON p.oid=c.relnamespace
    WHERE p.nspname='private' AND c.relname=n AND c.relkind='r' AND c.relrowsecurity AND c.relforcerowsecurity))
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') c
    WHERE c->>'relation'=ANY(SELECT 'private.'||n FROM unnest(names) n)) THEN
  RAISE EXCEPTION 'native_work_retention_schema_changed' USING ERRCODE='55000';END IF;
 additions:=jsonb_build_array(
  jsonb_build_object('name','private:burimunsi_native_financial_work','relation','private.burimunsi_native_financial_work',
   'scope','unmapped_private','purpose','Shared source and transaction references; inspection only, effects blocked',
   'known_links','source_id links to the native receipt origin and its principal; transaction_id may involve other subjects','blocked',true),
  jsonb_build_object('name','private:burimunsi_native_grant_commands','relation','private.burimunsi_native_grant_commands',
   'scope','unmapped_private','purpose','Shared grant command and actor references; inspection only, effects blocked',
   'known_links','actor_id and principal_session_id identify the command actor; grant_id links to the approved grant','blocked',true),
  jsonb_build_object('name','private:burimunsi_native_work_grants','relation','private.burimunsi_native_work_grants',
   'scope','unmapped_private','purpose','Shared approval and collection references; inspection only, effects blocked',
   'known_links','approved_principal_id and approved_admin_id identify the approver; collection ownership may involve other subjects','blocked',true));
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 next_body:=format('SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||%L::jsonb) FROM (%s) prior(base)',additions::text,body);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 -- A class descriptor is present for every subject, but its aggregate count
 -- remains unknown rather than falsely reporting zero for shared data.
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
 anchor:=$a$'private:burimunsi_auto_sms_jobs','private:burimunsi_native_receipt_origins','private:burimunsi_accounts',$a$;
 replacement:=$b$'private:burimunsi_native_financial_work','private:burimunsi_native_grant_commands','private:burimunsi_native_work_grants','private:burimunsi_auto_sms_jobs','private:burimunsi_native_receipt_origins','private:burimunsi_accounts',$b$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'native_work_retention_anchor_changed' USING ERRCODE='55000';END IF;
 next_body:=replace(body,anchor,replacement);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
END;$install$;
COMMIT;
