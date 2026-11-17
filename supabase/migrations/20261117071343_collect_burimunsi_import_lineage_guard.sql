-- Proposed additive schema; not a migration and not applied by this package.
-- Incorporate into the reviewed managed migration chain only after checking
-- target roles, privacy retention, backup and source/target identity evidence.
CREATE TABLE private.collect_migration_actor_lineage (
  source_actor_id text PRIMARY KEY REFERENCES app.users(id),
  cloud_primary_id text NOT NULL REFERENCES app.users(id),
  operation_id uuid NOT NULL,
  snapshot_hmac text NOT NULL CHECK (snapshot_hmac ~ '^[a-f0-9]{64}$'),
  envelope jsonb NOT NULL CHECK (
    jsonb_typeof(envelope) = 'object' AND
    envelope->>'version' = '1' AND envelope->>'algorithm' = 'AES-256-GCM' AND
    jsonb_typeof(envelope->'nonce') = 'string' AND
    jsonb_typeof(envelope->'ciphertext') = 'string' AND
    jsonb_typeof(envelope->'tag') = 'string'
  ),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CHECK (source_actor_id <> cloud_primary_id)
);

ALTER TABLE private.collect_migration_actor_lineage ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_migration_actor_lineage FORCE ROW LEVEL SECURITY;
CREATE POLICY collect_migration_actor_lineage_owner ON private.collect_migration_actor_lineage
  TO postgres USING (true) WITH CHECK (true);
REVOKE ALL ON private.collect_migration_actor_lineage
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;

CREATE FUNCTION private.collect_migration_actor_lineage_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fn$
BEGIN
  RAISE EXCEPTION 'migration_actor_lineage_immutable' USING ERRCODE='23514';
END
$fn$;
REVOKE ALL ON FUNCTION private.collect_migration_actor_lineage_immutable()
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE TRIGGER collect_migration_actor_lineage_immutable
  BEFORE UPDATE OR DELETE ON private.collect_migration_actor_lineage
  FOR EACH ROW EXECUTE FUNCTION private.collect_migration_actor_lineage_immutable();
ALTER TABLE private.collect_migration_actor_lineage
  ENABLE ALWAYS TRIGGER collect_migration_actor_lineage_immutable;

-- A receipt is inserted with the graph and remains in the same transaction.
-- It lets an operator reconcile an uncertain COMMIT without replaying rows.
-- HMACs are keyed with the separately protected migration custody key.
CREATE TABLE private.collect_migration_import_receipts (
  operation_id uuid PRIMARY KEY,
  source_actor_id text NOT NULL REFERENCES private.collect_migration_actor_lineage(source_actor_id),
  cloud_primary_id text NOT NULL REFERENCES app.users(id),
  snapshot_hmac text NOT NULL CHECK (snapshot_hmac ~ '^[a-f0-9]{64}$'),
  object_proof_hmac text NOT NULL CHECK (object_proof_hmac ~ '^[a-f0-9]{64}$'),
  counts jsonb NOT NULL CHECK (jsonb_typeof(counts) = 'object'),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
ALTER TABLE private.collect_migration_import_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_migration_import_receipts FORCE ROW LEVEL SECURITY;
CREATE POLICY collect_migration_import_receipts_owner ON private.collect_migration_import_receipts
  TO postgres USING (true) WITH CHECK (true);
REVOKE ALL ON private.collect_migration_import_receipts
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE FUNCTION private.collect_migration_import_receipts_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fn$
BEGIN
  RAISE EXCEPTION 'migration_import_receipts_immutable' USING ERRCODE='23514';
END
$fn$;
REVOKE ALL ON FUNCTION private.collect_migration_import_receipts_immutable()
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE TRIGGER collect_migration_import_receipts_immutable
  BEFORE UPDATE OR DELETE ON private.collect_migration_import_receipts
  FOR EACH ROW EXECUTE FUNCTION private.collect_migration_import_receipts_immutable();
ALTER TABLE private.collect_migration_import_receipts
  ENABLE ALWAYS TRIGGER collect_migration_import_receipts_immutable;

-- Marks immutable imported evidence as historical. Runtime may read markers
-- only to deny automatic work; it cannot create or alter them.
CREATE TABLE private.collect_imported_native_history (
  source_id text PRIMARY KEY REFERENCES private.burimunsi_native_receipt_origins(source_id)
    DEFERRABLE INITIALLY DEFERRED,
  collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
  request_id uuid NOT NULL,
  transaction_id text REFERENCES app.momo_transactions(id) DEFERRABLE INITIALLY DEFERRED,
  body_sha256 text NOT NULL CHECK (body_sha256 ~ '^[a-f0-9]{64}$'),
  object_sha256 text NOT NULL CHECK (object_sha256 ~ '^[a-f0-9]{64}$'),
  source_fingerprint text NOT NULL CHECK (source_fingerprint ~ '^[a-f0-9]{64}$'),
  operation_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
CREATE INDEX collect_imported_native_history_transaction ON private.collect_imported_native_history(transaction_id)
  WHERE transaction_id IS NOT NULL;
ALTER TABLE private.collect_imported_native_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_imported_native_history FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.collect_imported_native_history
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
GRANT SELECT ON private.collect_imported_native_history TO collect_runtime;
CREATE POLICY collect_imported_native_history_runtime ON private.collect_imported_native_history
  FOR SELECT TO collect_runtime USING (true);
CREATE POLICY collect_imported_native_history_owner ON private.collect_imported_native_history
  TO postgres USING (true) WITH CHECK (true);

CREATE FUNCTION private.collect_imported_native_history_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fn$
BEGIN
  RAISE EXCEPTION 'imported_native_history_immutable' USING ERRCODE='23514';
END
$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_history_immutable()
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE TRIGGER collect_imported_native_history_immutable
  BEFORE UPDATE OR DELETE ON private.collect_imported_native_history
  FOR EACH ROW EXECUTE FUNCTION private.collect_imported_native_history_immutable();
ALTER TABLE private.collect_imported_native_history
  ENABLE ALWAYS TRIGGER collect_imported_native_history_immutable;

-- Recheck the completed cross-table provenance at commit, not just in JS.
CREATE FUNCTION private.collect_imported_native_history_check()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.burimunsi_native_receipt_origins o
    JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=o.source_id
    JOIN app.sms_receipts r ON r.id=o.source_id
    WHERE o.source_id=NEW.source_id AND o.collection_id=NEW.collection_id
      AND o.request_id=NEW.request_id AND o.body_sha256=NEW.body_sha256
      AND o.object_sha256=NEW.object_sha256 AND o.fingerprint=NEW.source_fingerprint
      AND j.collection_id=o.collection_id AND j.source_fingerprint=o.fingerprint
      AND j.transaction_id IS NOT DISTINCT FROM NEW.transaction_id
      AND r.owner_user_id=o.principal_user_id AND r.client_envelope_id=o.request_id::text
      AND r.body_sha256=o.body_sha256 AND r.object_sha256=o.object_sha256
      AND r.object_key='sms/'||o.source_id AND r.originating_session_id IS NULL
      AND r.receiver_hash IS NULL AND r.evidence_level='client_received'
  ) THEN RAISE EXCEPTION 'imported_native_history_mismatch' USING ERRCODE='23514'; END IF;
  RETURN NULL;
END
$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_history_check()
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE CONSTRAINT TRIGGER collect_imported_native_history_check
  AFTER INSERT ON private.collect_imported_native_history
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION private.collect_imported_native_history_check();

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

-- Candidate for a reviewed forward migration; not applied by this file.
-- Embed inside the same owner transaction, AFTER the fenced import of original
-- jobs, links, ledger rows and immutable history markers, BEFORE commit and
-- release. Fresh captures still need separately verified event dedup.
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(7346371,1);
SELECT pg_advisory_xact_lock(7346371,2);

DO $preflight$
DECLARE item record; actual text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regclass('private.collect_imported_native_history') IS NULL
  OR to_regclass('private.burimunsi_auto_sms_jobs') IS NULL
  OR to_regclass('private.burimunsi_native_financial_work') IS NULL
  OR to_regclass('app.momo_financial_links') IS NULL
  OR to_regclass('app.ledger_entries') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='private.collect_imported_native_history'::regclass
       AND attname='transaction_id' AND atttypid='text'::regtype AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.collect_imported_native_history'::regclass
       AND relrowsecurity AND relforcerowsecurity AND relowner='postgres'::regrole)
  OR NOT EXISTS(SELECT 1 FROM pg_policy p WHERE p.polrelid='private.collect_imported_native_history'::regclass
       AND p.polcmd IN ('r','*') AND 'postgres'::regrole=ANY(p.polroles)
       AND pg_get_expr(p.polqual,p.polrelid)='true')
  OR has_table_privilege('collect_runtime','private.collect_imported_native_history','INSERT')
  OR has_table_privilege('collect_runtime','private.collect_imported_native_history','UPDATE')
  OR has_table_privilege('collect_runtime','private.collect_imported_native_history','DELETE')
  OR to_regprocedure('private.collect_imported_native_source(text)') IS NOT NULL
  OR to_regprocedure('private.collect_imported_native_transaction(text)') IS NOT NULL
  OR to_regprocedure('private.collect_imported_native_job_transaction(text)') IS NOT NULL
  OR to_regprocedure('private.collect_imported_native_history_write_guard()') IS NOT NULL
  OR to_regprocedure('private.collect_imported_native_history_link_guard()') IS NOT NULL
  OR to_regprocedure('private.collect_imported_native_history_ledger_guard()') IS NOT NULL
  OR EXISTS(SELECT 1 FROM pg_trigger WHERE NOT tgisinternal AND tgname='collect_imported_native_history_guard'
       AND tgrelid IN ('private.burimunsi_auto_sms_jobs'::regclass,'private.burimunsi_native_financial_work'::regclass,
        'app.momo_financial_links'::regclass,'app.ledger_entries'::regclass)) THEN
  RAISE EXCEPTION 'imported_history_guard_precondition' USING ERRCODE='55000';
 END IF;
 FOR item IN SELECT * FROM (VALUES
  ('private.burimunsi_auto_snapshot(text)','eca8e37c9f32b6cb5aed09fffd2e23389c334dfd96ba8cf4626800dcea64ecf6'),
  ('private.burimunsi_auto_candidates(text)','4a4ed2f3b9b05bbb29e731b536d57df2e4872e09b9ac8f37b1658b15a9841398'),
  ('private.burimunsi_native_work_candidates(uuid,integer)','74516bc8f9be32e22450b6251e141caa0e2bc1dc697ea3d09b3903bc36127753'),
  ('private.burimunsi_native_sms_post_candidates(integer)','e94bdf789a4e10e17ce66606134538131b58cb10db4be02de33f09b530a503a7')
 ) AS t(signature,expected) LOOP
  SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') INTO actual FROM pg_proc p
   WHERE p.oid=to_regprocedure(item.signature) AND p.proowner='postgres'::regrole AND p.prosecdef;
  IF actual IS DISTINCT FROM item.expected THEN RAISE EXCEPTION 'imported_history_guard_predecessor_changed: %',item.signature USING ERRCODE='55000';END IF;
 END LOOP;
END;$preflight$;

CREATE FUNCTION private.collect_imported_native_source(p_source text) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT EXISTS(SELECT 1 FROM private.collect_imported_native_history h WHERE h.source_id=p_source)
$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_source(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

CREATE FUNCTION private.collect_imported_native_transaction(p_transaction text) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT EXISTS(SELECT 1 FROM private.collect_imported_native_history h WHERE h.transaction_id=p_transaction)
$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_transaction(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

-- A fresh source may resolve to the imported canonical transaction. Use the
-- existing job RLS frame when looking it up and restore the caller's frame.
CREATE FUNCTION private.collect_imported_native_job_transaction(p_source text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.native_receipt_frame',true); answer boolean;
BEGIN
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_auto_sms_jobs j
  WHERE j.source_id=p_source AND private.collect_imported_native_transaction(j.transaction_id)) INTO answer;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN answer;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_job_transaction(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

-- Retain each existing function's OID, signature, grants, config, and body;
-- change only one pinned, unique anchor in each predecessor function.
DO $patch$
DECLARE item record; oldbody text; newbody text; definition text;
BEGIN
 FOR item IN SELECT * FROM (VALUES
  ('private.burimunsi_auto_snapshot(text)',
   $old$ PERFORM private.burimunsi_setup_fence();$old$,
   $new$ PERFORM private.burimunsi_setup_fence();
 IF private.collect_imported_native_source(p_source) OR private.collect_imported_native_job_transaction(p_source)
  THEN RAISE EXCEPTION 'imported_native_history_blocked' USING ERRCODE='55000';END IF;$new$),
  ('private.burimunsi_auto_candidates(text)',
   $old$ WHERE (p_collection IS NULL OR o.collection_id=p_collection)$old$,
   $new$ WHERE NOT private.collect_imported_native_source(o.source_id)
  AND (p_collection IS NULL OR o.collection_id=p_collection)$new$),
  ('private.burimunsi_native_work_candidates(uuid,integer)',
   $old$  WHERE collection_id=current_setting('burimunsi.collection_id',true) AND$old$,
   $new$  WHERE NOT private.collect_imported_native_source(source_id)
   AND NOT private.collect_imported_native_transaction(transaction_id)
   AND collection_id=current_setting('burimunsi.collection_id',true) AND$new$),
  ('private.burimunsi_native_sms_post_candidates(integer)',
   $old$  WHERE j.state='completed' AND j.relation='accepted'$old$,
   $new$  WHERE NOT private.collect_imported_native_source(j.source_id)
   AND NOT private.collect_imported_native_transaction(j.transaction_id)
   AND j.state='completed' AND j.relation='accepted'$new$)
 ) AS t(signature,anchor,replacement) LOOP
  SELECT p.prosrc,pg_get_functiondef(p.oid) INTO STRICT oldbody,definition FROM pg_proc p WHERE p.oid=to_regprocedure(item.signature);
  IF length(oldbody)-length(replace(oldbody,item.anchor,''))<>length(item.anchor)
   OR length(definition)-length(replace(definition,oldbody,''))<>length(oldbody) THEN
   RAISE EXCEPTION 'imported_history_guard_anchor_changed: %',item.signature USING ERRCODE='55000';END IF;
  newbody:=replace(oldbody,item.anchor,item.replacement);
  EXECUTE replace(definition,oldbody,newbody);
 END LOOP;
END;$patch$;

-- Block direct retry, defer, claim, enqueue and other writes as a second line
-- of defense, including operations that do not call auto_snapshot.
CREATE FUNCTION private.collect_imported_native_history_write_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF (TG_OP<>'INSERT' AND private.collect_imported_native_source(OLD.source_id))
  OR (TG_OP<>'DELETE' AND private.collect_imported_native_source(NEW.source_id))
  OR (TG_OP<>'INSERT' AND private.collect_imported_native_transaction(OLD.transaction_id))
  OR (TG_TABLE_NAME='burimunsi_native_financial_work' AND TG_OP<>'DELETE'
      AND private.collect_imported_native_transaction(NEW.transaction_id))
  OR (TG_TABLE_NAME='burimunsi_auto_sms_jobs' AND TG_OP='INSERT'
      AND private.collect_imported_native_transaction(NEW.transaction_id)) THEN
  RAISE EXCEPTION 'imported_native_history_blocked' USING ERRCODE='55000';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;ELSE RETURN NEW;END IF;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_history_write_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_imported_native_history_guard BEFORE INSERT OR UPDATE OR DELETE
 ON private.burimunsi_auto_sms_jobs FOR EACH ROW EXECUTE FUNCTION private.collect_imported_native_history_write_guard();
ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ALWAYS TRIGGER collect_imported_native_history_guard;
CREATE TRIGGER collect_imported_native_history_guard BEFORE INSERT OR UPDATE OR DELETE
 ON private.burimunsi_native_financial_work FOR EACH ROW EXECUTE FUNCTION private.collect_imported_native_history_write_guard();
ALTER TABLE private.burimunsi_native_financial_work ENABLE ALWAYS TRIGGER collect_imported_native_history_guard;

-- Both automatic and direct/manual receipt allocation create this link in the
-- same transaction as payment/ledger writes. A failed link rolls all back.
CREATE FUNCTION private.collect_imported_native_history_link_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF (TG_OP<>'INSERT' AND EXISTS(SELECT 1 FROM private.collect_imported_native_history h WHERE h.transaction_id=OLD.transaction_id))
  OR (TG_OP<>'DELETE' AND EXISTS(SELECT 1 FROM private.collect_imported_native_history h WHERE h.transaction_id=NEW.transaction_id)) THEN
  RAISE EXCEPTION 'imported_native_history_blocked' USING ERRCODE='55000';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;ELSE RETURN NEW;END IF;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_history_link_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_imported_native_history_guard BEFORE INSERT OR UPDATE OR DELETE
 ON app.momo_financial_links FOR EACH ROW EXECUTE FUNCTION private.collect_imported_native_history_link_guard();
ALTER TABLE app.momo_financial_links ENABLE ALWAYS TRIGGER collect_imported_native_history_guard;

-- Generic reconciliation can credit an already-linked payment without adding
-- a new link. Keep existing entries and allow separate reversal/correction
-- entries, but do not add or rewrite contributions tied to imported history.
CREATE FUNCTION private.collect_imported_native_history_ledger_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF (TG_OP<>'INSERT' AND OLD.kind='contribution' AND EXISTS(
     SELECT 1 FROM app.momo_financial_links f JOIN private.collect_imported_native_history h ON h.transaction_id=f.transaction_id
     WHERE f.payment_id=OLD.payment_id))
  OR (TG_OP<>'DELETE' AND NEW.kind='contribution' AND EXISTS(
     SELECT 1 FROM app.momo_financial_links f JOIN private.collect_imported_native_history h ON h.transaction_id=f.transaction_id
     WHERE f.payment_id=NEW.payment_id)) THEN
  RAISE EXCEPTION 'imported_native_history_blocked' USING ERRCODE='55000';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;ELSE RETURN NEW;END IF;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_history_ledger_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_imported_native_history_guard BEFORE INSERT OR UPDATE OR DELETE
 ON app.ledger_entries FOR EACH ROW EXECUTE FUNCTION private.collect_imported_native_history_ledger_guard();
ALTER TABLE app.ledger_entries ENABLE ALWAYS TRIGGER collect_imported_native_history_guard;

-- Candidate for the fenced import transaction, AFTER lineage/marker creation
-- and imported graph, BEFORE commit and release. It patches only the existing
-- native history reader and its role-checked record projection.
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(7346371,1);
SELECT pg_advisory_xact_lock(7346371,2);
DO $preflight$
DECLARE item record;actual text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regclass('private.collect_migration_actor_lineage') IS NULL
  OR to_regclass('private.collect_imported_native_history') IS NULL
  OR to_regclass('private.burimunsi_native_receipt_origins') IS NULL
  OR to_regprocedure('private.collect_imported_native_source(text)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_history_own(text)') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_policy p WHERE p.polrelid='private.collect_migration_actor_lineage'::regclass
    AND p.polcmd IN ('r','*') AND 'postgres'::regrole=ANY(p.polroles) AND pg_get_expr(p.polqual,p.polrelid)='true')
  OR NOT EXISTS(SELECT 1 FROM pg_policy p WHERE p.polrelid='private.collect_imported_native_history'::regclass
    AND p.polcmd IN ('r','*') AND 'postgres'::regrole=ANY(p.polroles) AND pg_get_expr(p.polqual,p.polrelid)='true') THEN
  RAISE EXCEPTION 'imported_history_read_precondition' USING ERRCODE='55000';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('private.burimunsi_observation_history_rows(text)','84b3a0b23ac8d2b54f695e68755b077107a273d7e95cca5070430d373afc018a'),
  ('private.burimunsi_auto_projection(text)','975b5580a464de2f78464dd953809def6a1ed01e3b29c2fa195986635690805a')
 ) AS t(signature,expected) LOOP
  SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') INTO actual FROM pg_proc p
   WHERE p.oid=to_regprocedure(item.signature) AND p.proowner='postgres'::regrole AND p.prosecdef;
  IF actual IS DISTINCT FROM item.expected THEN RAISE EXCEPTION 'imported_history_read_predecessor_changed: %',item.signature USING ERRCODE='55000';END IF;
 END LOOP;
END;$preflight$;

DO $patch$
DECLARE body text;definition text;anchor text;replacement text;
BEGIN
 SELECT p.prosrc,pg_get_functiondef(p.oid) INTO STRICT body,definition FROM pg_proc p
  WHERE p.oid='private.burimunsi_observation_history_rows(text)'::regprocedure;
 anchor:=$old$ old_pin text:=current_setting('burimunsi.pin_frame',true);$old$;
 replacement:=$new$ old_pin text:=current_setting('burimunsi.pin_frame',true);
 old_native text:=current_setting('burimunsi.native_receipt_frame',true);$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$ PERFORM set_config('burimunsi.pin_frame','1',true);$old$;
 replacement:=$new$ PERFORM set_config('burimunsi.pin_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$  USING a,p_source;$old$;
 replacement:=$new$  USING a,p_source;
 -- Only immutable, lineage-proven imported observations owned by THIS exact
 -- current account and collection qualify. Historical grant/session and old
 -- principal remain retired; neither is used as present authority.
 RETURN QUERY EXECUTE $q$SELECT r.* FROM private.burimunsi_unresolved_observations r
 JOIN private.burimunsi_native_receipt_origins o ON o.source_id=r.source_id
  AND o.collection_id=r.collection_id AND o.account_id=r.account_id AND o.principal_user_id=r.principal_user_id
  AND o.installation_id=r.installation_id AND o.grant_id=r.grant_id AND o.grant_version=r.grant_version
  AND o.request_id=r.request_id AND o.fingerprint=r.fingerprint AND o.body_sha256=r.body_sha256 AND o.object_sha256=r.object_sha256
 JOIN private.collect_imported_native_history h ON h.source_id=r.source_id AND h.collection_id=r.collection_id
  AND h.request_id=r.request_id AND h.source_fingerprint=r.fingerprint
  AND h.body_sha256=r.body_sha256 AND h.object_sha256=r.object_sha256
 JOIN private.collect_migration_actor_lineage l ON l.source_actor_id=o.principal_user_id AND l.cloud_primary_id=$1->>'principalUserId'
 WHERE r.collection_id=$1->>'collectionId' AND r.account_id=($1->>'accountId')::uuid
  AND ($2 IS NULL OR r.source_id=$2)$q$
  ||CASE WHEN current_setting('transaction_read_only')='off' THEN ' FOR SHARE OF r,o,h,l' ELSE '' END
  USING a,p_source;$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$ PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);$old$;
 replacement:=$new$ PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);$new$;
 IF length(body)-length(replace(body,anchor,''))<>2*length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 SELECT prosrc INTO anchor FROM pg_proc WHERE oid='private.burimunsi_observation_history_rows(text)'::regprocedure;
 IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE replace(definition,anchor,body);

 SELECT p.prosrc,pg_get_functiondef(p.oid) INTO STRICT body,definition FROM pg_proc p
  WHERE p.oid='private.burimunsi_auto_projection(text)'::regprocedure;
 anchor:=$old$  BEGIN can_reveal:=private.burimunsi_observation_own(p_source,true) IS NOT NULL;$old$;
 replacement:=$new$  BEGIN can_reveal:=CASE WHEN private.collect_imported_native_source(p_source)
   THEN private.burimunsi_observation_history_own(p_source) IS NOT NULL
   ELSE private.burimunsi_observation_own(p_source,true) IS NOT NULL END;$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor)
  OR length(definition)-length(replace(definition,body,''))<>length(body) THEN
  RAISE EXCEPTION 'imported_history_read_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE replace(definition,body,replace(body,anchor,replacement));
END;$patch$;
