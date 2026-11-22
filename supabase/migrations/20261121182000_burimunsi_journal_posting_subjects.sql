-- Add scoped, positive posting associations to the two private journal classes
-- returned by the existing authorized V2 capture and page RPCs.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
BEGIN
  PERFORM private._collect_fence_require_operator();
  IF current_user <> 'postgres' OR session_user <> 'postgres' OR NOT EXISTS (
    SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private._burimunsi_retention_journal_links_v1(text,text)')
      AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND p.provolatile='s'
      AND p.proacl::text='{postgres=X/postgres}' AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']
      AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='3444eca5abdac7e8e54df3a96556a63077a87e48c4e4ba8cf120ebd08b8fde55'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private._retention_manifest_rows_v2(text)')
      AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND p.provolatile='s'
      AND p.proacl::text='{postgres=X/postgres}' AND p.proconfig=ARRAY['search_path=app, pg_catalog, pg_temp']
      AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='6a1435008e15ffe4f7ba1d7921a1b098b1adb3f0032745031d3e069b19962710'
  ) THEN RAISE EXCEPTION 'burimunsi_journal_posting_links_precondition' USING ERRCODE='55000'; END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION private._burimunsi_retention_journal_links_v1(p_subject text, p_class text)
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

  PERFORM set_config('burimunsi.native_receipt_frame','1',true);
  IF p_class = 'private:burimunsi_observation_retry_commands' THEN
    PERFORM set_config('burimunsi.pin_frame','1',true);
  ELSE
    PERFORM set_config('burimunsi.payment_sms_frame','1',true);
  END IF;

  -- The immutable contribution and posting snapshot tie each ledger identity
  -- to its payment, collection, credited member and evidence. A reconciliation
  -- or reversal later in time does not remove these recorded associations.
  WITH postings AS NOT MATERIALIZED (
    SELECT p.id AS payment_id,p.collection_id,p.member_id,p.amount_minor,l.id AS ledger_id,
      l.actor_user_id,e.owner_user_id,f.linked_by,f.transaction_id
    FROM app.payments p
    JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=p.collection_id
      AND l.member_id=p.member_id AND l.kind='contribution' AND l.evidence_id=p.evidence_id
      AND l.amount_minor=p.amount_minor AND l.currency=p.currency
    JOIN app.contribution_posting_snapshots snapshot ON snapshot.payment_id=p.id
      AND snapshot.ledger_entry_id=l.id AND snapshot.posted_at=l.posted_at
    LEFT JOIN app.payment_evidence e ON e.id=p.evidence_id AND e.collection_id=p.collection_id
    LEFT JOIN app.momo_financial_links f ON f.payment_id=p.id
      AND f.beneficiary_member_id=p.member_id AND f.historical_existing=0
    WHERE p.rail='rwanda_momo' AND p.currency='RWF'
  ), accepted_sources AS NOT MATERIALIZED (
    -- Use the same accepted parse/source lineage as the original native
    -- beneficiary inventory. A duplicate, conflicting or merely quoted
    -- source identifier carries no capture or beneficiary authority.
    SELECT t.id AS transaction_id,o.collection_id,o.source_id,o.account_id,o.principal_user_id
    FROM app.momo_transactions t
    JOIN app.momo_transaction_sources ts ON ts.transaction_id=t.id
      AND ts.parse_attempt_id=t.parse_attempt_id AND ts.relation='accepted'
    JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=ts.raw_sms_id
      AND j.transaction_id=t.id AND j.attempt_id::text=ts.parse_attempt_id
      AND j.receiving_account_id=t.receiving_account_id AND j.state='completed'
      AND j.relation='accepted' AND j.payment_outcome='successful'
    JOIN private.burimunsi_native_receipt_origins o ON o.source_id=j.source_id
      AND o.collection_id=j.collection_id AND o.fingerprint=j.source_fingerprint
    WHERE t.mode='live' AND t.event_kind='incoming_receipt'
  ), links AS (
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
    UNION ALL
    SELECT delivery.attempt_id,role.relationship
    FROM private.burimunsi_payment_sms_deliveries delivery
    JOIN postings p ON p.payment_id=delivery.payment_id AND p.ledger_id=delivery.ledger_entry_id
      AND p.collection_id=delivery.collection_id AND p.member_id=delivery.recipient_user_id
      AND p.amount_minor=delivery.amount_rwf
    LEFT JOIN accepted_sources src ON src.transaction_id=p.transaction_id AND src.collection_id=p.collection_id
    CROSS JOIN LATERAL (VALUES ('posting_actor',p.actor_user_id),('evidence_owner',p.owner_user_id),
      ('allocation_actor',p.linked_by),('capture_principal',src.principal_user_id)) role(relationship,subject)
    WHERE p_class='private:burimunsi_payment_sms_deliveries' AND role.subject=p_subject
    UNION ALL
    SELECT retry.request_id,role.relationship
    FROM private.burimunsi_observation_retry_commands retry
    JOIN accepted_sources src ON src.source_id=retry.source_id AND src.collection_id=retry.collection_id
      AND src.account_id=retry.account_id
    JOIN postings p ON p.transaction_id=src.transaction_id AND p.collection_id=src.collection_id
    CROSS JOIN LATERAL (VALUES ('canonical_beneficiary',p.member_id),('posting_actor',p.actor_user_id),
      ('evidence_owner',p.owner_user_id),('allocation_actor',p.linked_by)) role(relationship,subject)
    WHERE p_class='private:burimunsi_observation_retry_commands' AND retry.result='scheduled'
      AND role.subject=p_subject
  ), bounded AS MATERIALIZED (
    SELECT DISTINCT id,relationship COLLATE "C" AS relationship FROM links ORDER BY id,relationship LIMIT 101
  ), numbered AS (
    SELECT id, relationship, row_number() OVER (ORDER BY id,relationship COLLATE "C") AS position FROM bounded
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

COMMIT;
