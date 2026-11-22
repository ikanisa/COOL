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
