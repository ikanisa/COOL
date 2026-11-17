-- Attribute an already accepted canonical fact to its immutable native capture.
-- Routing metadata only: no parser, approval, actor, payment or ledger writer.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regclass('private.burimunsi_gateway_handoffs') IS NULL
  OR to_regclass('private.burimunsi_sms_source_scopes') IS NULL
  OR to_regprocedure('private.burimunsi_adopt_completed_receipt()') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced') THEN
  RAISE EXCEPTION 'burimunsi_canonical_adoption_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

-- The definer can inspect ONLY the immutable source named by the triggering
-- canonical job. Ordinary runtime/HTTP callers retain their existing scoped
-- SELECT policy and cannot execute the trigger function or assume its owner.
CREATE POLICY burimunsi_canonical_source_lookup ON private.burimunsi_sms_source_scopes
 FOR SELECT TO postgres USING(source_id=current_setting('burimunsi.canonical_source_id',true));

CREATE FUNCTION private.burimunsi_adopt_completed_receipt() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE
 old_group text:=current_setting('burimunsi.collection_id',true);
 old_source text:=current_setting('burimunsi.canonical_source_id',true);
 captured private.burimunsi_sms_source_scopes%ROWTYPE;
 origin private.burimunsi_sms_source_scopes%ROWTYPE;
 existing private.burimunsi_transaction_scopes%ROWTYPE;
 fact record;
 accepted_count integer;
 duplicate_count integer;
 conflict_count integer;
 at_seconds bigint;
BEGIN
 -- This hook is inside the SAME canonical fact/source/terminal-job transaction.
 -- It neither schedules work nor gives a completed row permission to reparse.
 IF TG_OP<>'UPDATE' OR NEW.state<>'completed' OR OLD.state='completed' THEN RETURN NEW;END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 at_seconds:=floor(extract(epoch FROM clock_timestamp()))::bigint;
 PERFORM set_config('burimunsi.canonical_source_id',NEW.raw_sms_id,true);
 SELECT * INTO captured FROM private.burimunsi_sms_source_scopes WHERE source_id=NEW.raw_sms_id;
 IF NOT FOUND OR captured.provenance<>'gateway_capture' THEN
  PERFORM set_config('burimunsi.canonical_source_id',coalesce(old_source,''),true);
  RETURN NEW;
 END IF;
 -- A legitimate Admin reparse retains earlier accepted/duplicate history.
 -- Only the terminal CURRENT attempt can attribute this completion.
 SELECT count(*) FILTER(WHERE s.relation='accepted'),count(*) FILTER(WHERE s.relation='duplicate'),
  count(*) FILTER(WHERE s.relation='conflict') INTO accepted_count,duplicate_count,conflict_count
 FROM app.momo_transaction_sources s JOIN app.momo_parse_attempts a ON a.id=s.parse_attempt_id AND a.raw_sms_id=s.raw_sms_id
 WHERE s.raw_sms_id=NEW.raw_sms_id AND a.attempt_number=NEW.attempt_count;
 -- A supported nonreceipt has no canonical fact and conveys no routing right.
 IF accepted_count=0 AND duplicate_count=0 AND conflict_count=0 THEN
  PERFORM set_config('burimunsi.canonical_source_id',coalesce(old_source,''),true);
  RETURN NEW;
 END IF;
 IF accepted_count+duplicate_count<>1 OR conflict_count<>0 OR OLD.state<>'processing'
  OR OLD.lease_token IS NULL OR OLD.lease_until IS NULL OR OLD.lease_until<=at_seconds
  OR NEW.last_error IS NOT NULL OR NEW.lease_token IS NOT NULL OR NEW.lease_until IS NOT NULL
  OR NEW.mode<>'live' OR ROW(NEW.raw_sms_id,NEW.binding_id,NEW.binding_version,NEW.receiving_account_id,NEW.mode,NEW.attempt_count)
   IS DISTINCT FROM ROW(OLD.raw_sms_id,OLD.binding_id,OLD.binding_version,OLD.receiving_account_id,OLD.mode,OLD.attempt_count) THEN
  RAISE EXCEPTION 'burimunsi_canonical_source_mismatch' USING ERRCODE='23514';
 END IF;
 SELECT t.id,t.receiving_account_id,t.parse_attempt_id,t.provider,t.event_kind,t.mode,
  t.amount_minor,t.currency,t.has_conflict,t.provider_transaction_id,
  s.raw_sms_id,s.relation,s.parse_attempt_id AS source_attempt,
  a.raw_sms_id AS attempt_source,a.attempt_number,a.outcome,a.source_body_sha256,a.profile_version,a.profile_json,
  r.owner_user_id,r.object_key,r.object_sha256,r.body_sha256,r.receiver_hash,
  c.credential_id,c.identity_sha256,c.completeness,c.source_mode,c.subscription_id,
  k.binding_id AS credential_binding,k.installation_id,
  b.owner_user_id AS binding_owner,b.receiving_account_id AS binding_account,b.version AS binding_version,
  CASE WHEN app.json_valid(b.subscription_evidence) THEN b.subscription_evidence::jsonb ELSE '{}'::jsonb END AS subscription_evidence,
  w.provider AS account_provider,w.receiver_hash AS account_receiver_hash,w.currency AS account_currency,
  w.status AS account_status,w.profile_status,w.profile_version AS account_profile_version,w.profile_json AS account_profile_json,
  (SELECT count(*) FROM app.momo_transaction_sources original
    WHERE original.transaction_id=t.id AND original.parse_attempt_id=t.parse_attempt_id AND original.relation='accepted') AS originals,
  (SELECT min(original.raw_sms_id) FROM app.momo_transaction_sources original
    WHERE original.transaction_id=t.id AND original.parse_attempt_id=t.parse_attempt_id AND original.relation='accepted') AS original_source,
  EXISTS(SELECT 1 FROM app.momo_transaction_sources conflict WHERE conflict.transaction_id=t.id AND conflict.relation='conflict') AS source_conflict
 INTO fact
 FROM app.momo_transaction_sources s
 JOIN app.momo_transactions t ON t.id=s.transaction_id
 JOIN app.momo_parse_attempts a ON a.id=s.parse_attempt_id AND a.raw_sms_id=s.raw_sms_id
 JOIN app.sms_receipts r ON r.id=s.raw_sms_id
 JOIN app.momo_gateway_captures c ON c.raw_sms_id=r.id
 JOIN app.momo_gateway_credentials k ON k.id=c.credential_id
 JOIN app.momo_gateway_bindings b ON b.id=k.binding_id
 JOIN app.momo_receiving_accounts w ON w.id=t.receiving_account_id
 WHERE s.raw_sms_id=NEW.raw_sms_id AND a.attempt_number=NEW.attempt_count AND s.relation IN('accepted','duplicate');
 IF NOT FOUND OR fact.originals<>1
  OR ROW(fact.raw_sms_id,fact.attempt_source,fact.owner_user_id,fact.object_sha256,fact.body_sha256,
         fact.credential_id,fact.credential_binding,fact.installation_id,
         fact.receiving_account_id,fact.binding_account,fact.binding_version,fact.binding_owner)
   IS DISTINCT FROM ROW(captured.source_id,captured.source_id,captured.owner_user_id,captured.object_sha256,captured.source_body_sha256,
         captured.credential_id,captured.binding_id,captured.installation_id::text,
         captured.receiving_account_id,captured.receiving_account_id,captured.binding_version,captured.owner_user_id)
  OR ROW(NEW.binding_id,NEW.binding_version,NEW.receiving_account_id)
   IS DISTINCT FROM ROW(captured.binding_id,captured.binding_version,captured.receiving_account_id)
  OR fact.object_key IS DISTINCT FROM 'sms/'||captured.source_id
  OR fact.receiver_hash IS DISTINCT FROM fact.account_receiver_hash
  OR fact.outcome IS DISTINCT FROM fact.relation OR fact.attempt_number IS DISTINCT FROM NEW.attempt_count
  OR (fact.relation='accepted' AND fact.parse_attempt_id IS DISTINCT FROM fact.source_attempt)
  OR fact.source_body_sha256 IS DISTINCT FROM captured.source_body_sha256
  OR fact.completeness IS DISTINCT FROM 'complete' OR fact.source_mode IS DISTINCT FROM 'live'
  OR fact.mode IS DISTINCT FROM 'live' OR fact.event_kind IS DISTINCT FROM 'incoming_receipt'
  OR fact.provider IS DISTINCT FROM fact.account_provider OR fact.provider NOT IN('mtn_momo','airtel_money')
  OR fact.currency IS DISTINCT FROM 'RWF' OR fact.account_currency IS DISTINCT FROM 'RWF'
  OR fact.amount_minor IS NULL OR fact.amount_minor<=0 OR fact.provider_transaction_id IS NULL
  OR length(fact.provider_transaction_id) NOT BETWEEN 1 AND 160
  OR fact.has_conflict IS DISTINCT FROM 0 OR fact.source_conflict IS DISTINCT FROM false
  OR fact.account_status IS DISTINCT FROM 'active' OR fact.profile_status IS DISTINCT FROM 'approved'
  OR fact.profile_version IS NULL OR fact.profile_version='unverified'
  OR fact.profile_version IS DISTINCT FROM fact.account_profile_version
  OR fact.profile_json IS DISTINCT FROM fact.account_profile_json
  OR fact.identity_sha256 IS NULL OR fact.identity_sha256 !~ '^[a-f0-9]{64}$'
  OR fact.subscription_id IS NULL OR fact.subscription_id<0
  OR fact.subscription_evidence IS DISTINCT FROM jsonb_build_object('subscription_id',fact.subscription_id)
  OR captured.proof_id IS DISTINCT FROM captured.source_id OR captured.proof_sha256 !~ '^[a-f0-9]{64}$'
  OR captured.custodian_account_id IS NULL OR captured.grant_id IS NULL OR captured.grant_version IS NULL THEN
  RAISE EXCEPTION 'burimunsi_canonical_source_mismatch' USING ERRCODE='23514';
 END IF;
 IF fact.relation='duplicate' THEN
  PERFORM set_config('burimunsi.canonical_source_id',fact.original_source,true);
  SELECT * INTO origin FROM private.burimunsi_sms_source_scopes WHERE source_id=fact.original_source;
  IF FOUND THEN
   IF ROW(origin.collection_id,origin.receiving_account_id) IS DISTINCT FROM ROW(captured.collection_id,captured.receiving_account_id) THEN
    RAISE EXCEPTION 'burimunsi_canonical_scope_conflict' USING ERRCODE='23514';
   END IF;
   PERFORM set_config('burimunsi.collection_id',origin.collection_id,true);
   SELECT * INTO existing FROM private.burimunsi_transaction_scopes WHERE transaction_id=fact.id;
   IF FOUND AND ROW(existing.collection_id,existing.receiving_account_id,existing.source_binding_id,existing.source_binding_version)
    IS DISTINCT FROM ROW(origin.collection_id,origin.receiving_account_id,origin.binding_id,origin.binding_version) THEN
    RAISE EXCEPTION 'burimunsi_canonical_scope_conflict' USING ERRCODE='23514';
   END IF;
  END IF;
  -- Never backfill an unassociated original or adopt a later observation's
  -- binding. A same-group/wallet duplicate preserves the FIRST scope verbatim.
 ELSE
  PERFORM set_config('burimunsi.collection_id',captured.collection_id,true);
  -- Capture-time routing survives a replacement. Current wallet/group,
  -- custodian and session state cannot reassign historical provenance.
  INSERT INTO private.burimunsi_transaction_scopes
   (transaction_id,collection_id,receiving_account_id,source_binding_id,source_binding_version,policy_version,created_at)
  VALUES(fact.id,captured.collection_id,captured.receiving_account_id,captured.binding_id,captured.binding_version,
   'canonical.manual.v1',floor(extract(epoch FROM clock_timestamp())*1000)::bigint)
  ON CONFLICT(transaction_id) DO NOTHING;
  SELECT * INTO existing FROM private.burimunsi_transaction_scopes WHERE transaction_id=fact.id;
  IF NOT FOUND OR ROW(existing.collection_id,existing.receiving_account_id,existing.source_binding_id,existing.source_binding_version)
   IS DISTINCT FROM ROW(captured.collection_id,captured.receiving_account_id,captured.binding_id,captured.binding_version) THEN
   RAISE EXCEPTION 'burimunsi_canonical_scope_conflict' USING ERRCODE='23514';
  END IF;
 END IF;
 -- This tag approves no policy, identity, worker, automatic match or financial
 -- effect. An existing exact scope retains its FIRST policy and created_at.
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.canonical_source_id',coalesce(old_source,''),true);
 RETURN NEW;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.canonical_source_id',coalesce(old_source,''),true);
 RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_adopt_completed_receipt()
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_adopt_completed_receipt AFTER UPDATE OF state ON app.momo_processing_jobs
 FOR EACH ROW WHEN(NEW.state='completed' AND OLD.state IS DISTINCT FROM NEW.state)
 EXECUTE FUNCTION private.burimunsi_adopt_completed_receipt();
ALTER TABLE app.momo_processing_jobs ENABLE ALWAYS TRIGGER burimunsi_adopt_completed_receipt;
-- PostgreSQL row locks require UPDATE on at least one selected column.
-- Existing namespace identity rejects every row UPDATE/DELETE. Object-key
-- changes remain forbidden by storage_object_identity; its existing no-op
-- behavior and all other metadata-column permissions remain unchanged.
-- These two column rights admit original custody FOR SHARE/FOR UPDATE only;
-- no table-wide UPDATE, new definer, credential or storage bypass is added.
GRANT UPDATE(singleton) ON private.storage_namespace TO collect_runtime;
GRANT UPDATE(object_key) ON private.storage_objects TO collect_runtime;
COMMIT;
