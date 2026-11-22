-- Attach positive subject evidence to the authorized V2 inventory. The two
-- immutable journals retain blocked disposition and an unknown subject count.
BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  PERFORM private._collect_fence_require_operator();
  IF current_user <> 'postgres' OR session_user <> 'postgres'
    OR NOT EXISTS (SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode = 'fenced')
    OR to_regprocedure('private._burimunsi_retention_journal_links_v1(text,text)') IS NOT NULL
    OR NOT EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid = to_regprocedure('private._retention_manifest_rows_v2(text)')
        AND pg_get_userbyid(p.proowner) = 'postgres' AND p.prosecdef
        AND p.provolatile = 's' AND p.proacl::text = '{postgres=X/postgres}'
        AND p.proconfig = ARRAY['search_path=app, pg_catalog, pg_temp']
        AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') =
          '25597e57accb602949e65108db895113ee66e657b5c20e4cc1fbbdabf266973a'
    )
    OR (SELECT count(DISTINCT item->>'relation')
        FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') item
        WHERE item->>'relation' IN (
          'private.burimunsi_observation_retry_commands','private.burimunsi_payment_sms_deliveries'
        ) AND item->>'scope' = 'unmapped_private' AND item->'blocked' = 'true'::jsonb) <> 2 THEN
    RAISE EXCEPTION 'burimunsi_journal_links_precondition' USING ERRCODE = '55000';
  END IF;
END;
$preflight$;

CREATE INDEX burimunsi_observation_retry_subject_links
  ON private.burimunsi_observation_retry_commands (collection_id, account_id, request_id);
CREATE INDEX burimunsi_payment_sms_recipient_links
  ON private.burimunsi_payment_sms_deliveries (recipient_user_id, attempt_id);

CREATE FUNCTION private._burimunsi_retention_journal_links_v1(p_subject text, p_class text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
DECLARE
  old_native text := current_setting('burimunsi.native_receipt_frame',true);
  old_pin text := current_setting('burimunsi.pin_frame',true);
  old_payment text := current_setting('burimunsi.payment_sms_frame',true);
  answer jsonb;
BEGIN
  PERFORM private._collect_fence_require_runtime();
  IF p_subject IS NULL OR p_subject !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'
    OR p_class IS NULL OR p_class NOT IN (
      'private:burimunsi_observation_retry_commands','private:burimunsi_payment_sms_deliveries'
    ) THEN
    RAISE EXCEPTION 'burimunsi_journal_links_invalid' USING ERRCODE = '22023';
  END IF;

  IF p_class = 'private:burimunsi_observation_retry_commands' THEN
    PERFORM set_config('burimunsi.native_receipt_frame','1',true);
    PERFORM set_config('burimunsi.pin_frame','1',true);
  ELSE
    PERFORM set_config('burimunsi.payment_sms_frame','1',true);
  END IF;

  WITH links AS (
    SELECT retry.request_id AS id, 'retry_operator'::text AS relationship
    FROM private.burimunsi_accounts account
    JOIN private.burimunsi_observation_retry_commands retry
      ON retry.collection_id = account.collection_id AND retry.account_id = account.id
    WHERE p_class = 'private:burimunsi_observation_retry_commands'
      AND account.principal_user_id = p_subject
    UNION ALL
    SELECT delivery.attempt_id, 'receipt_recipient'
    FROM private.burimunsi_payment_sms_deliveries delivery
    WHERE p_class = 'private:burimunsi_payment_sms_deliveries'
      AND delivery.recipient_user_id = p_subject
  ), bounded AS MATERIALIZED (
    SELECT id, relationship FROM links ORDER BY id LIMIT 101
  ), numbered AS (
    SELECT id, relationship, row_number() OVER (ORDER BY id) AS position FROM bounded
  )
  SELECT jsonb_build_object(
    'contract_version',1,'complete',false,'erasure','blocked','limit',100,
    'missing_matches_prove_absence',false,'truncated',count(*) > 100,
    'matches',coalesce(jsonb_agg(jsonb_build_object(
      'relationship',relationship,
      'record_key_sha256',encode(sha256(convert_to(p_class || ':' || id::text,'UTF8')),'hex')
    ) ORDER BY position) FILTER (WHERE position <= 100),'[]'::jsonb)
  ) INTO answer FROM numbered;

  PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
  PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
  PERFORM set_config('burimunsi.payment_sms_frame',coalesce(old_payment,''),true);
  RETURN answer;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
  PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
  PERFORM set_config('burimunsi.payment_sms_frame',coalesce(old_payment,''),true);
  RAISE;
END;
$fn$;
REVOKE ALL ON FUNCTION private._burimunsi_retention_journal_links_v1(text,text)
  FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

DO $inventory$
DECLARE
  body text;
  anchor text := $old$  IF c->>'scope'='unmapped_private' OR c->>'name'=ANY(ARRAY['private:storage_payload_reservations'$old$;
  addition text := $new$  IF c->>'name' IN ('private:burimunsi_observation_retry_commands','private:burimunsi_payment_sms_deliveries') THEN
   RETURN QUERY SELECT c->>'name',jsonb_build_object('kind','class','status','unmapped','subject_count',NULL,
    'erasure','blocked','present',true,'object_custody','unverified',
    'lifecycle',jsonb_build_object('unresolved',true),
    'positive_subject_links',private._burimunsi_retention_journal_links_v1(p_subject,c->>'name'));
   CONTINUE;
  END IF;
$new$;
BEGIN
  SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid = 'private._retention_manifest_rows_v2(text)'::regprocedure;
  IF length(body) - length(replace(body,anchor,'')) <> length(anchor) THEN
    RAISE EXCEPTION 'burimunsi_journal_links_inventory_changed' USING ERRCODE = '55000';
  END IF;
  EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_rows_v2(p_subject text) '
    || 'RETURNS TABLE(class_name text,descriptor jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER '
    || 'SET search_path=app,pg_catalog,pg_temp AS ' || quote_literal(replace(body,anchor,addition || anchor));
END;
$inventory$;
COMMIT;
