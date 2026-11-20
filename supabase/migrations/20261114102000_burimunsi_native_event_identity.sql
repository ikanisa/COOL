-- Same original SMS event, different device/request/inbox key: one canonical
-- transaction. Every encrypted source and its duplicate/conflict relation stays.
-- No historical payment, contribution, source identity or amount is rewritten.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regprocedure('private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb)') IS NULL
  OR to_regprocedure('private.burimunsi_auto_event_bind(text,uuid,text,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'burimunsi_native_event_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

ALTER TABLE private.burimunsi_auto_sms_jobs
 ADD COLUMN event_identity_sha256 text CHECK(event_identity_sha256 IS NULL OR event_identity_sha256 ~ '^[a-f0-9]{64}$'),
 ADD COLUMN event_inbox_sha256 text CHECK(event_inbox_sha256 IS NULL OR event_inbox_sha256 ~ '^[a-f0-9]{64}$'),
 ADD COLUMN event_has_service_time boolean NOT NULL DEFAULT false,
 ADD CONSTRAINT native_event_metadata_shape CHECK(event_identity_sha256 IS NOT NULL OR (event_inbox_sha256 IS NULL AND NOT event_has_service_time));
CREATE UNIQUE INDEX burimunsi_native_one_event ON private.burimunsi_auto_sms_jobs
 (collection_id,receiving_account_id,event_identity_sha256)
 WHERE state='completed' AND relation='accepted' AND event_identity_sha256 IS NOT NULL;

CREATE FUNCTION private.burimunsi_auto_event_immutable() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF current_setting('burimunsi.native_event_backfill',true)='1'
  AND (to_jsonb(NEW)-ARRAY['event_identity_sha256','event_inbox_sha256','event_has_service_time'])
   IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['event_identity_sha256','event_inbox_sha256','event_has_service_time']) THEN
  RAISE EXCEPTION 'burimunsi_native_event_metadata_only' USING ERRCODE='23514';END IF;
 IF ROW(NEW.event_identity_sha256,NEW.event_inbox_sha256,NEW.event_has_service_time)
   IS DISTINCT FROM ROW(OLD.event_identity_sha256,OLD.event_inbox_sha256,OLD.event_has_service_time) AND
  (OLD.event_identity_sha256 IS NOT NULL OR NEW.event_identity_sha256 IS NULL OR
   current_setting('burimunsi.native_event_frame',true) IS DISTINCT FROM '1') THEN
  RAISE EXCEPTION 'burimunsi_native_event_immutable' USING ERRCODE='23514';END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_event_immutable() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_auto_event_immutable BEFORE UPDATE ON private.burimunsi_auto_sms_jobs
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_auto_event_immutable();
ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ALWAYS TRIGGER burimunsi_auto_event_immutable;

-- The general fence intentionally rejects every DML while fenced. Preserve
-- that exact predecessor for normal work and add one table-specific exception
-- for the operator's metadata-only backfill. The row guard above rejects any
-- change outside the new identity column; inserts/deletes remain fenced.
DO $guard$
DECLARE body text;anchor text;replacement text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._collect_fence_statement()'::regprocedure;
 IF encode(sha256(convert_to(body,'UTF8')),'hex')<>'0b886c44b329012c91e5eb85fce1a160a60e4172e016a284f2c280121b0a217d' THEN
  RAISE EXCEPTION 'burimunsi_native_event_fence_predecessor_changed' USING ERRCODE='55000';END IF;
 anchor:=$old$BEGIN
 IF current_setting('role',true)='collect_runtime' THEN$old$;
 replacement:=$new$BEGIN
 IF current_setting('role',true)='none' AND private._collect_fence_operator()
  AND current_setting('burimunsi.native_event_backfill',true)='1' AND TG_OP='UPDATE' THEN
  PERFORM pg_advisory_xact_lock(7346371,1);
  IF EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced') THEN RETURN NULL;END IF;
 END IF;
 IF current_setting('role',true)='collect_runtime' THEN$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'burimunsi_native_event_fence_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE 'CREATE FUNCTION private._burimunsi_native_event_jobs_statement() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(replace(body,anchor,replacement));
END;$guard$;
REVOKE ALL ON FUNCTION private._burimunsi_native_event_jobs_statement() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
DROP TRIGGER collect_fence_statement_v1 ON private.burimunsi_auto_sms_jobs;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
 ON private.burimunsi_auto_sms_jobs FOR EACH STATEMENT EXECUTE FUNCTION private._burimunsi_native_event_jobs_statement();
ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

CREATE FUNCTION private.burimunsi_auto_event_bind(p_source text,p_lease uuid,p_fingerprint text,p_event jsonb) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE snap jsonb;n integer;old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
 old_event text:=current_setting('burimunsi.native_event_frame',true);
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();snap:=private.burimunsi_auto_snapshot(p_source);
 IF jsonb_typeof(p_event) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'burimunsi_native_event_invalid' USING ERRCODE='22023';END IF;
 IF NOT p_event ?& ARRAY['identity','inboxIdentity','serviceTimePresent']
  OR p_event-ARRAY['identity','inboxIdentity','serviceTimePresent']<>'{}'::jsonb
  OR jsonb_typeof(p_event->'identity') IS DISTINCT FROM 'string' OR p_event->>'identity' !~ '^[a-f0-9]{64}$'
  OR jsonb_typeof(p_event->'inboxIdentity') NOT IN ('string','null')
  OR (p_event->>'inboxIdentity' IS NOT NULL AND p_event->>'inboxIdentity' !~ '^[a-f0-9]{64}$')
  OR jsonb_typeof(p_event->'serviceTimePresent') IS DISTINCT FROM 'boolean' THEN
  RAISE EXCEPTION 'burimunsi_native_event_invalid' USING ERRCODE='22023';END IF;
 IF snap->'proof'->>'fingerprint' IS DISTINCT FROM p_fingerprint
  OR p_lease IS NULL THEN RAISE EXCEPTION 'burimunsi_native_event_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);PERFORM set_config('burimunsi.native_event_frame','1',true);
 UPDATE private.burimunsi_auto_sms_jobs SET event_identity_sha256=p_event->>'identity',event_inbox_sha256=p_event->>'inboxIdentity',
  event_has_service_time=(p_event->>'serviceTimePresent')::boolean
 WHERE source_id=p_source AND collection_id=current_setting('burimunsi.collection_id',true)
  AND source_fingerprint=p_fingerprint AND state='processing' AND phase='dispatched'
  AND lease_token=p_lease AND lease_until>floor(extract(epoch FROM clock_timestamp())*1000)::bigint
  AND (event_identity_sha256 IS NULL OR (event_identity_sha256=p_event->>'identity'
   AND event_inbox_sha256 IS NOT DISTINCT FROM p_event->>'inboxIdentity' AND event_has_service_time=(p_event->>'serviceTimePresent')::boolean));
 GET DIAGNOSTICS n=ROW_COUNT;
 PERFORM set_config('burimunsi.native_event_frame',coalesce(old_event,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 IF n<>1 THEN RAISE EXCEPTION 'burimunsi_native_event_changed' USING ERRCODE='40001';END IF;RETURN true;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_event_frame',coalesce(old_event,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_event_bind(text,uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_event_bind(text,uuid,text,jsonb) TO collect_runtime;

-- A fenced, metadata-only backfill is needed before opening the new release.
-- The operator independently decrypts/verifies each retained source and computes
-- the exact same identity helper. The original source/fingerprint must match.
CREATE POLICY burimunsi_native_event_operator ON private.burimunsi_auto_sms_jobs TO postgres
 USING(current_setting('role',true)='none' AND private._collect_fence_operator()
  AND current_setting('burimunsi.native_event_backfill',true)='1'
  AND EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced'))
 WITH CHECK(current_setting('role',true)='none' AND private._collect_fence_operator()
  AND current_setting('burimunsi.native_event_backfill',true)='1'
  AND EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced'));
CREATE FUNCTION private.burimunsi_auto_event_backfill(p_source text,p_fingerprint text,p_event jsonb) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE n integer;old_backfill text:=current_setting('burimunsi.native_event_backfill',true);
 old_event text:=current_setting('burimunsi.native_event_frame',true);
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM pg_advisory_xact_lock(7346371,1);
 IF jsonb_typeof(p_event) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'burimunsi_native_event_invalid' USING ERRCODE='22023';END IF;
 IF NOT p_event ?& ARRAY['identity','inboxIdentity','serviceTimePresent']
  OR p_event-ARRAY['identity','inboxIdentity','serviceTimePresent']<>'{}'::jsonb
  OR jsonb_typeof(p_event->'identity') IS DISTINCT FROM 'string' OR p_event->>'identity' !~ '^[a-f0-9]{64}$'
  OR jsonb_typeof(p_event->'inboxIdentity') NOT IN ('string','null')
  OR (p_event->>'inboxIdentity' IS NOT NULL AND p_event->>'inboxIdentity' !~ '^[a-f0-9]{64}$')
  OR jsonb_typeof(p_event->'serviceTimePresent') IS DISTINCT FROM 'boolean' THEN
  RAISE EXCEPTION 'burimunsi_native_event_invalid' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'burimunsi_native_event_precondition' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.native_event_backfill','1',true);PERFORM set_config('burimunsi.native_event_frame','1',true);
 UPDATE private.burimunsi_auto_sms_jobs SET event_identity_sha256=p_event->>'identity',event_inbox_sha256=p_event->>'inboxIdentity',
  event_has_service_time=(p_event->>'serviceTimePresent')::boolean
 WHERE source_id=p_source AND source_fingerprint=p_fingerprint
  AND (event_identity_sha256 IS NULL OR (event_identity_sha256=p_event->>'identity'
   AND event_inbox_sha256 IS NOT DISTINCT FROM p_event->>'inboxIdentity' AND event_has_service_time=(p_event->>'serviceTimePresent')::boolean));
 GET DIAGNOSTICS n=ROW_COUNT;
 PERFORM set_config('burimunsi.native_event_frame',coalesce(old_event,''),true);
 PERFORM set_config('burimunsi.native_event_backfill',coalesce(old_backfill,''),true);
 IF n<>1 THEN RAISE EXCEPTION 'burimunsi_native_event_changed' USING ERRCODE='40001';END IF;RETURN true;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_event_frame',coalesce(old_event,''),true);
 PERFORM set_config('burimunsi.native_event_backfill',coalesce(old_backfill,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_event_backfill(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

DO $finish$
DECLARE body text;anchor text;replacement text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb)'::regprocedure;
 anchor:=$old$ t app.momo_transactions%ROWTYPE;sc private.burimunsi_transaction_scopes%ROWTYPE;$old$;
 replacement:=$new$ t app.momo_transactions%ROWTYPE;sc private.burimunsi_transaction_scopes%ROWTYPE;canonical_facts jsonb;canonical_ids text[];$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'burimunsi_native_event_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$ new_id:=p_source;
 IF ref IS NOT NULL THEN
  SELECT * INTO t FROM app.momo_transactions WHERE provider=wallet_provider AND receiving_account_id=j.receiving_account_id
   AND event_kind=kind AND provider_transaction_id=ref FOR UPDATE;
  IF FOUND THEN$old$;
 replacement:=$new$ new_id:=p_source;
 IF j.event_identity_sha256 IS NULL THEN RAISE EXCEPTION 'burimunsi_native_event_required' USING ERRCODE='55000';END IF;
 IF (SELECT count(DISTINCT prior.transaction_id) FROM private.burimunsi_auto_sms_jobs prior
  JOIN app.momo_transactions canonical ON canonical.id=prior.transaction_id
  JOIN private.burimunsi_native_receipt_origins origin ON origin.source_id=prior.source_id
   AND origin.collection_id=prior.collection_id AND origin.fingerprint=prior.source_fingerprint
  WHERE prior.collection_id=j.collection_id AND prior.receiving_account_id=j.receiving_account_id
   AND (prior.event_identity_sha256=j.event_identity_sha256 OR
    ((canonical.provider_transaction_id IS NOT NULL OR EXISTS(
     SELECT 1 FROM private.burimunsi_auto_sms_jobs facts_job WHERE facts_job.transaction_id=canonical.id
      AND facts_job.collection_id=j.collection_id AND facts_job.receiving_account_id=j.receiving_account_id
      AND facts_job.state='completed' AND facts_job.relation='accepted'
      AND facts_job.posting_facts->>'provider_transaction_id' IS NOT NULL)) AND origin.body_sha256=proof->>'bodySha256') OR
    (j.event_inbox_sha256 IS NOT NULL AND prior.event_inbox_sha256=j.event_inbox_sha256
     AND NOT (j.event_has_service_time AND EXISTS(SELECT 1 FROM private.burimunsi_auto_sms_jobs strong
      WHERE strong.collection_id=j.collection_id AND strong.receiving_account_id=j.receiving_account_id
       AND strong.transaction_id=prior.transaction_id AND strong.state='completed' AND strong.relation IN ('accepted','duplicate','conflict')
       AND strong.event_has_service_time AND strong.event_identity_sha256<>j.event_identity_sha256))))
   AND prior.source_id<>j.source_id AND prior.state='completed' AND prior.relation IN ('accepted','duplicate','conflict'))>1 THEN
  RAISE EXCEPTION 'burimunsi_native_event_ambiguous' USING ERRCODE='40001';END IF;
 SELECT canonical.* INTO t FROM private.burimunsi_auto_sms_jobs prior
 JOIN app.momo_transactions canonical ON canonical.id=prior.transaction_id
 JOIN private.burimunsi_native_receipt_origins origin ON origin.source_id=prior.source_id
  AND origin.collection_id=prior.collection_id AND origin.fingerprint=prior.source_fingerprint
 WHERE prior.collection_id=j.collection_id AND prior.receiving_account_id=j.receiving_account_id
  AND (prior.event_identity_sha256=j.event_identity_sha256 OR
   ((canonical.provider_transaction_id IS NOT NULL OR EXISTS(
     SELECT 1 FROM private.burimunsi_auto_sms_jobs facts_job WHERE facts_job.transaction_id=canonical.id
      AND facts_job.collection_id=j.collection_id AND facts_job.receiving_account_id=j.receiving_account_id
      AND facts_job.state='completed' AND facts_job.relation='accepted'
      AND facts_job.posting_facts->>'provider_transaction_id' IS NOT NULL)) AND origin.body_sha256=proof->>'bodySha256') OR
   (j.event_inbox_sha256 IS NOT NULL AND prior.event_inbox_sha256=j.event_inbox_sha256
    AND NOT (j.event_has_service_time AND EXISTS(SELECT 1 FROM private.burimunsi_auto_sms_jobs strong
     WHERE strong.collection_id=j.collection_id AND strong.receiving_account_id=j.receiving_account_id
      AND strong.transaction_id=prior.transaction_id AND strong.state='completed' AND strong.relation IN ('accepted','duplicate','conflict')
      AND strong.event_has_service_time AND strong.event_identity_sha256<>j.event_identity_sha256))))
  AND prior.source_id<>j.source_id AND prior.state='completed' AND prior.relation IN ('accepted','duplicate','conflict')
 ORDER BY prior.created_at,prior.source_id LIMIT 1 FOR UPDATE OF canonical;
 IF NOT FOUND AND ref IS NOT NULL THEN
  SELECT array_agg(canonical.id ORDER BY canonical.id) INTO canonical_ids FROM app.momo_transactions canonical
  WHERE canonical.provider=wallet_provider AND canonical.receiving_account_id=j.receiving_account_id
   AND ((canonical.event_kind=kind AND canonical.provider_transaction_id=ref) OR EXISTS(
    SELECT 1 FROM private.burimunsi_auto_sms_jobs facts_job WHERE facts_job.transaction_id=canonical.id
     AND facts_job.collection_id=j.collection_id AND facts_job.receiving_account_id=j.receiving_account_id
     AND facts_job.state='completed' AND facts_job.relation='accepted'
     AND facts_job.posting_facts->>'event_kind'=kind
     AND coalesce(canonical.provider_transaction_id,facts_job.posting_facts->>'provider_transaction_id')=ref));
  IF cardinality(canonical_ids)>1 THEN RAISE EXCEPTION 'burimunsi_native_event_ambiguous' USING ERRCODE='40001';END IF;
  IF cardinality(canonical_ids)=1 THEN
   SELECT * INTO t FROM app.momo_transactions WHERE id=canonical_ids[1] FOR UPDATE;
  END IF;
 END IF;
 IF t.id IS NOT NULL THEN$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'burimunsi_native_event_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$v_relation:=CASE WHEN ROW(t.amount_minor,t.currency,t.payer_name,t.payer_identifier,t.transaction_at,t.fee_minor,t.wallet_balance_after_minor)$old$;
 replacement:=$new$-- Historical canonical rows may predate the source-bound facts projection.
   -- Prefer that one accepted job's validated facts only in this local record;
   -- never rewrite the immutable transaction or its existing financial effect.
   canonical_facts:=(SELECT facts_job.posting_facts FROM private.burimunsi_auto_sms_jobs facts_job
    WHERE facts_job.transaction_id=t.id AND facts_job.collection_id=j.collection_id
     AND facts_job.receiving_account_id=j.receiving_account_id
     AND facts_job.state='completed' AND facts_job.relation='accepted');
   IF canonical_facts IS NOT NULL THEN
    t:=jsonb_populate_record(t,jsonb_build_object(
     'event_kind',canonical_facts->'event_kind','amount_minor',canonical_facts->'amount_minor',
     'currency',canonical_facts->'currency','payer_name',canonical_facts->'counterparty_name',
     'payer_identifier',canonical_facts->'counterparty_identifier','transaction_at',canonical_facts->'transaction_at',
     'fee_minor',canonical_facts->'fee_minor','wallet_balance_after_minor',canonical_facts->'wallet_balance_after_minor',
     'provider_transaction_id',coalesce(t.provider_transaction_id,canonical_facts->>'provider_transaction_id')));
   END IF;
   v_relation:=CASE WHEN t.event_kind=kind AND (ref IS NULL OR t.provider_transaction_id IS NULL OR ref=t.provider_transaction_id)
    AND ROW(t.amount_minor,t.currency,t.payer_name,t.payer_identifier,t.transaction_at,t.fee_minor,t.wallet_balance_after_minor)$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'burimunsi_native_event_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$   new_id:=t.id;
  END IF;
 END IF;
 INSERT INTO app.momo_parse_attempts$old$;
 replacement:=$new$   new_id:=t.id;
 END IF;
 INSERT INTO app.momo_parse_attempts$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'burimunsi_native_event_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.burimunsi_auto_finish(p_source text,p_lease uuid,p_fingerprint text,p_profile_sha text,p_attempt uuid,p_model text,p_output jsonb,p_facts jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(body);
END;$finish$;
COMMIT;
