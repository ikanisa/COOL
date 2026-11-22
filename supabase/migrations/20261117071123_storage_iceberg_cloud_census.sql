-- Managed Supabase rrlduytparvsjfmegalh catalog variant. Only buckets_analytics
-- exists in the observed provider schema. Preserve blocked copy-class descriptors;
-- do not create vendor tables or assert zero subject rows / erasure completion.
-- Inspection-only handling for shared Storage Iceberg catalogs. Subject
-- attribution and remote-table erasure are not implemented or asserted.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $install$
DECLARE r record;body text;next_body text;anchor text;replacement text;shape jsonb;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'storage_iceberg_retention_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM (VALUES
  ('private._retention_manifest_catalog_v2()','aa9aa0086b70ced2d8533946c98e53814c183891c9057c307b3d207a30650674',false,'i',ARRAY['search_path=pg_catalog, pg_temp']::text[],'sql','{postgres=X/postgres}'),
  ('private._retention_manifest_schema_v2()','afad38d443badf352c865abb5ca1f9fd939566da05c1c29f50f10ab8905a3feb',true,'s',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._retention_manifest_rows_v2(text)','79ca2b3459164c66c8ba52670f59f9e9fe31b91d34c20f80fabf9cc58a617f3d',true,'s',ARRAY['search_path=app, pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._retention_row_policy_v2(uuid,text,text,text)','642f9f6545776e0ed6abca60007a9ea8c2d79faed0945d70ccbc8219eaa86228',true,'s',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','9f89fad1121d4f33e25fb5b9a7f56ff67873bf101ab3d7da294ca3f141b713f5',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) e(sig,hash,definer,volatility,config,language,acl) LOOP
  IF to_regprocedure(r.sig) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(r.sig) AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=r.definer
   AND p.provolatile=r.volatility AND p.prokind='f' AND p.proparallel='u' AND NOT p.proleakproof
   AND l.lanname=r.language AND p.proacl::text=r.acl AND p.proconfig=r.config
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.hash) THEN
   RAISE EXCEPTION 'storage_iceberg_retention_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 WITH rels AS (SELECT c.oid,c.relname,c.relkind,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner) AS owner
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='storage'
  AND c.relname IN('buckets_analytics','iceberg_namespaces','iceberg_tables'))
 SELECT jsonb_agg(jsonb_build_object('name',rel.relname,'kind',rel.relkind,'owner',rel.owner,'rls',rel.relrowsecurity,'force_rls',rel.relforcerowsecurity,
  'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum)
   FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=rel.oid AND a.attnum>0 AND NOT a.attisdropped),
  'constraints',(SELECT coalesce(jsonb_agg(jsonb_build_object('name',conname,'type',contype,'definition',pg_get_constraintdef(oid,true)) ORDER BY conname),'[]')
   FROM pg_constraint WHERE conrelid=rel.oid)) ORDER BY rel.relname) INTO shape FROM rels rel;
 IF shape IS NULL OR jsonb_array_length(shape)<>1 OR encode(sha256(convert_to(shape::text,'UTF8')),'hex')<>'60faa1b39c5f81d48d6a9c18eeafee033a545b94f3dbac49d1ac9eb6a4d8e381'
  OR private._retention_manifest_catalog_v2()->'copy_classes' ?| ARRAY['managed:storage_iceberg_namespaces','managed:storage_iceberg_tables'] THEN
  RAISE EXCEPTION 'storage_iceberg_retention_schema_changed' USING ERRCODE='55000';END IF;
 -- Reuse the existing copy-class descriptor: unverified, subject_count null,
 -- erasure blocked, and physical-object verification not performed.
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 next_body:=format('SELECT jsonb_set(base,''{copy_classes}'',(base->''copy_classes'')||%L::jsonb) FROM (%s) prior(base)', '["managed:storage_iceberg_namespaces","managed:storage_iceberg_tables"]',body);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_schema_v2()'::regprocedure;
 anchor:=$a$'buckets','buckets_analytics','buckets_vectors','iceberg_namespaces','iceberg_tables','migrations'$a$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'storage_iceberg_schema_already_extended_unconfirmed' USING ERRCODE='55000';END IF;
 -- A class-only descriptor is not an observation of zero subject rows.
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
 anchor:=$a$'managed:storage','r2:sms_receipts'$a$;
 replacement:=$b$'managed:storage','managed:storage_iceberg_namespaces','managed:storage_iceberg_tables','r2:sms_receipts'$b$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'storage_iceberg_capture_anchor_changed' USING ERRCODE='55000';END IF;
 next_body:=replace(body,anchor,replacement);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
END;$install$;
COMMIT;
