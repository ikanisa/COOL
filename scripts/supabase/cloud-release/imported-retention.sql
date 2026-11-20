-- Preserve immutable migration provenance as blocked shared operational copies.
-- These descriptors do not assert subject absence, erasure or recovery success.
DO $install_imported_retention$
DECLARE old_body text; new_body text; classes jsonb;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced' AND project_ref='rrlduytparvsjfmegalh')
  OR to_regclass('private.collect_migration_actor_lineage') IS NULL
  OR to_regclass('private.collect_imported_native_history') IS NULL
  OR to_regclass('private.collect_migration_import_receipts') IS NULL THEN
  RAISE EXCEPTION 'import_retention_precondition' USING ERRCODE='55000';
 END IF;
 SELECT prosrc INTO STRICT old_body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure
  AND pg_get_userbyid(proowner)='postgres' AND NOT prosecdef AND provolatile='i'
  AND proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND proacl::text='{postgres=X/postgres}';
 IF encode(sha256(convert_to(old_body,'UTF8')),'hex')<>'5d017ece7db12d526cc5209ea6c346ae0411e76db27650958de09b36adb37693' THEN
  RAISE EXCEPTION 'import_retention_preimage_changed' USING ERRCODE='55000';
 END IF;
 classes:='[
  {"name":"private:collect_migration_actor_lineage","relation":"private.collect_migration_actor_lineage","scope":"shared_fence","purpose":"Immutable encrypted original identity and explicit Cloud primary mapping; blocked shared migration provenance","blocked":true},
  {"name":"private:collect_imported_native_history","relation":"private.collect_imported_native_history","scope":"shared_fence","purpose":"Immutable original SMS scope and ciphertext evidence; blocks imported-history replay and scopes authorized current disclosure","blocked":true},
  {"name":"private:collect_migration_import_receipts","relation":"private.collect_migration_import_receipts","scope":"shared_fence","purpose":"Immutable transaction receipt with source and destination bindings; preserves import reconciliation evidence","blocked":true}
 ]'::jsonb;
 new_body:=format('SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||%L::jsonb) FROM (%s) prior(base)',classes::text,old_body);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(new_body);
END;$install_imported_retention$;
