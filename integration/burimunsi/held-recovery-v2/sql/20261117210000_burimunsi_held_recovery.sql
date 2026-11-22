-- Candidate: serialize SMS evidence identity and retain recovered history
-- without granting it automated financial processing. Applied only under the
-- existing fenced, source-qualified Cloud release procedure.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regclass('private.collect_sms_witnesses') IS NOT NULL
  OR to_regclass('private.burimunsi_recovered_sms_holds') IS NOT NULL
  OR to_regprocedure('private.burimunsi_observation_legacy_candidates(text)') IS NULL
  OR to_regprocedure('private.collect_imported_native_source(text)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_reconcile_status()') IS NULL
  OR to_regprocedure('private.burimunsi_observation_reconcile_verified_status()') IS NOT NULL
  OR to_regprocedure('private.burimunsi_sms_recovery_ack_snapshot(text,uuid,text,text,text,text,timestamptz)') IS NOT NULL
  OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc
    WHERE oid=to_regprocedure('private.collect_imported_native_source(text)'))
    IS DISTINCT FROM '3de5a1c984b9cf3d3e00f0ae8930a85b89cdc9f74f6e70c4744df96717ba2cde'
  OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
    WHERE p.oid=to_regprocedure('private.burimunsi_observation_reconcile_status()')
     AND p.proowner='postgres'::regrole AND p.prosecdef AND p.provolatile='v'
     AND p.prorettype='jsonb'::regtype AND l.lanname='plpgsql'
     AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']
     AND p.proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}'
     AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='dbc081cd16057fb2bf07da3514aab3b3afe4e7d35427651bd8187da0e809c30e') THEN
  RAISE EXCEPTION 'sms_recovery_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

-- The acknowledgement delegates actor, consent, request and custody checks
-- to these exact existing functions. Refuse changed ownership or ACLs.
DO $ack_predecessors$
DECLARE item record;
BEGIN
 FOR item IN SELECT * FROM (VALUES
  ('private.burimunsi_observation_actor(boolean)','e6f1bf1db6c84209a8bf00465201e1db997dc8c03a972399af7e6fcb48f4f9e1','{postgres=X/postgres}'),
  ('private.burimunsi_observation_consent_current()','4c7f0cea13f47ef0a040c36e3059ded889f42932f0696a554513bf470fa060f9','{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.burimunsi_observation_own(text,boolean)','f306b9c50fafa238f64816bf7a242a21d9f828ad9df5a8c565ada001b15aa7d1','{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.burimunsi_observation_lookup(uuid,text)','bda49fee71b6944325a1fa9d7d884016a00691f4a9a4a0b0f7212a4fb50c71ae','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) e(signature,digest,acl) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure(item.signature)
   AND p.proowner='postgres'::regrole AND p.prosecdef AND p.provolatile='v' AND p.prorettype='jsonb'::regtype
   AND l.lanname='plpgsql' AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND p.proacl::text=item.acl
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=item.digest) THEN
   RAISE EXCEPTION 'sms_recovery_ack_predecessor_changed: %',item.signature USING ERRCODE='55000';END IF;
 END LOOP;
END;$ack_predecessors$;

-- Body digest is not an event identity. A different inbox time can result from
-- delivery or restore, so it does not prove that equal bodies are distinct.
CREATE TABLE private.collect_sms_witnesses(
 object_key text PRIMARY KEY CHECK(object_key ~ '^sms/[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'),
 owner_id text NOT NULL REFERENCES app.users(id),
 collection_id text REFERENCES private.burimunsi_scopes(collection_id),
 request_digest text NOT NULL CHECK(request_digest ~ '^[a-f0-9]{64}$'),
 body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[a-f0-9]{64}$'),
 inbox_received_at timestamptz,
 storage_fingerprint text CHECK(storage_fingerprint IS NULL OR storage_fingerprint ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX collect_sms_witness_collection_body ON private.collect_sms_witnesses(collection_id,body_sha256);
CREATE TABLE private.burimunsi_recovered_sms_holds(
 source_id text PRIMARY KEY REFERENCES private.burimunsi_observation_requests(source_id),
 object_key text NOT NULL UNIQUE REFERENCES private.collect_sms_witnesses(object_key),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 account_id uuid NOT NULL,owner_id text NOT NULL REFERENCES app.users(id),
 body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[a-f0-9]{64}$'),
 inbox_received_at timestamptz NOT NULL,
 request_digest text NOT NULL CHECK(request_digest ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(object_key='sms/'||source_id),
 FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
CREATE INDEX burimunsi_recovered_sms_holds_collection_body ON private.burimunsi_recovered_sms_holds(collection_id,body_sha256);
DO $policy$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['collect_sms_witnesses','burimunsi_recovered_sms_holds'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE private.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime',t);
  EXECUTE format('CREATE POLICY collect_sms_witness_owner_frame ON private.%I TO postgres USING(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''collect.sms_witness_frame'',true)=''1'') WITH CHECK(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''collect.sms_witness_frame'',true)=''1'')',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
  EXECUTE format('CREATE TRIGGER collect_sms_no_erasure BEFORE DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_sms_no_erasure',t);
 END LOOP;
END;$policy$;
CREATE TRIGGER recovered_sms_hold_immutable BEFORE UPDATE ON private.burimunsi_recovered_sms_holds
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_recovered_sms_holds ENABLE ALWAYS TRIGGER recovered_sms_hold_immutable;
CREATE FUNCTION private.collect_sms_witness_immutable() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF NEW.object_key IS DISTINCT FROM OLD.object_key OR NEW.owner_id IS DISTINCT FROM OLD.owner_id
  OR NEW.collection_id IS DISTINCT FROM OLD.collection_id OR NEW.request_digest IS DISTINCT FROM OLD.request_digest
  OR NEW.body_sha256 IS DISTINCT FROM OLD.body_sha256 OR NEW.inbox_received_at IS DISTINCT FROM OLD.inbox_received_at
  OR NEW.created_at IS DISTINCT FROM OLD.created_at OR OLD.storage_fingerprint IS NOT NULL
  OR NEW.storage_fingerprint IS NULL THEN RAISE EXCEPTION 'sms_witness_immutable' USING ERRCODE='55000';END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_witness_immutable() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_sms_witness_immutable BEFORE UPDATE ON private.collect_sms_witnesses
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_witness_immutable();
ALTER TABLE private.collect_sms_witnesses ENABLE ALWAYS TRIGGER collect_sms_witness_immutable;

-- Called under the shared mutation lock both by native admission and inside
-- the protected Storage reservation. It never accepts a body from SQL clients.
CREATE FUNCTION private.collect_sms_witness_reserve(p_mode text,p_key text,p_owner text,p_collection text,
 p_request text,p_body text,p_inbox timestamptz,p_storage text DEFAULT NULL) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;c jsonb;prior_witness private.collect_sms_witnesses%ROWTYPE;created boolean:=false;
 old_w text:=current_setting('collect.sms_witness_frame',true);
 old_o text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 PERFORM private.collect_fence_assert_write(current_setting('collect.fence_admission_id',true)::uuid,
  current_setting('collect.fence_epoch',true)::bigint,current_setting('collect.fence_source_sha256',true));
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 IF p_mode NOT IN('native','recovery','storage') OR p_key IS NULL
  OR p_key !~ '^sms/[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
  OR p_owner IS NULL OR length(p_owner) NOT BETWEEN 1 AND 128
  OR p_request IS NULL OR p_request !~ '^[a-f0-9]{64}$'
  OR p_body IS NULL OR p_body !~ '^[a-f0-9]{64}$'
  OR (p_collection IS NOT NULL AND p_collection !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$')
  OR (p_storage IS NOT NULL AND p_storage !~ '^[a-f0-9]{64}$')
  OR (p_mode='storage' AND p_storage IS NULL) THEN
  RAISE EXCEPTION 'sms_witness_invalid' USING ERRCODE='22023';END IF;
 IF p_mode IN('native','recovery') THEN
  a:=private.burimunsi_observation_actor(p_mode='recovery');c:=private.burimunsi_observation_consent_current();
  IF a->>'collectionId' IS DISTINCT FROM p_collection OR a->>'principalUserId' IS DISTINCT FROM p_owner
   OR c->'enabled' IS DISTINCT FROM 'true'::jsonb OR (p_mode='recovery' AND p_inbox IS NULL) THEN
   RAISE EXCEPTION 'sms_witness_denied' USING ERRCODE='42501';END IF;
 END IF;
 PERFORM set_config('collect.sms_witness_frame','1',true);
 PERFORM set_config('burimunsi.observation_frame','1',true);
 -- A scoped Storage reservation must either continue a native witness that
 -- was created under the current actor, or be backed by the owner's active
 -- receiving gateway for this group. General member captures remain unscoped.
 IF p_mode='storage' AND p_collection IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM private.collect_sms_witnesses w WHERE w.object_key=p_key
    AND w.owner_id=p_owner AND w.collection_id=p_collection)
  AND NOT EXISTS(SELECT 1 FROM private.burimunsi_scopes s
    JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id AND b.version=s.binding_version
     AND b.receiving_account_id=s.receiving_account_id AND b.owner_user_id=p_owner AND b.status='active'
    JOIN app.momo_receiving_accounts receiving ON receiving.id=b.receiving_account_id AND receiving.status='active'
   WHERE s.collection_id=p_collection AND s.enabled) THEN
  RAISE EXCEPTION 'sms_witness_denied' USING ERRCODE='42501';END IF;
 SELECT * INTO prior_witness FROM private.collect_sms_witnesses WHERE object_key=p_key FOR UPDATE;
 IF FOUND THEN
  IF prior_witness.owner_id IS DISTINCT FROM p_owner OR prior_witness.request_digest IS DISTINCT FROM p_request
   OR prior_witness.body_sha256 IS DISTINCT FROM p_body OR prior_witness.inbox_received_at IS DISTINCT FROM p_inbox
   OR prior_witness.collection_id IS DISTINCT FROM p_collection
   OR (p_storage IS NOT NULL AND prior_witness.storage_fingerprint IS NOT NULL AND prior_witness.storage_fingerprint IS DISTINCT FROM p_storage) THEN
   RAISE EXCEPTION 'sms_witness_conflict' USING ERRCODE='23505';END IF;
  IF p_storage IS NOT NULL AND prior_witness.storage_fingerprint IS NULL THEN
   UPDATE private.collect_sms_witnesses SET storage_fingerprint=p_storage WHERE object_key=p_key;
  END IF;
 ELSE
  IF p_mode='recovery' THEN
   -- Compare only sources proved to belong to this collection. An
   -- unassociated member receipt does not grant authority over any group.
   IF EXISTS(SELECT 1 FROM private.collect_sms_witnesses x WHERE x.collection_id=p_collection
      AND x.object_key<>p_key AND x.body_sha256=p_body)
    OR EXISTS(SELECT 1 FROM private.burimunsi_observation_requests q
      LEFT JOIN private.burimunsi_unresolved_observations r ON r.source_id=q.source_id
      LEFT JOIN private.collect_sms_witnesses x ON x.object_key='sms/'||q.source_id
      WHERE q.collection_id=p_collection AND q.source_id<>substr(p_key,5) AND x.object_key IS NULL AND
       ((r.source_id IS NULL AND q.source_key_body_sha256 IS NULL) OR q.source_key_body_sha256=p_body OR r.body_sha256=p_body))
    OR EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes scope
      JOIN app.sms_receipts s ON s.id=scope.source_id
      WHERE scope.collection_id=p_collection AND s.object_key<>p_key AND s.body_sha256=p_body)
    -- A parsed source can already be adopted or financially linked even when
    -- it predates the source-scope table. Its collection is established by
    -- the transaction scope or by the linked payment, never by body alone.
    OR EXISTS(SELECT 1 FROM private.burimunsi_transaction_scopes x
      JOIN app.momo_transaction_sources s ON s.transaction_id=x.transaction_id
      JOIN app.sms_receipts r ON r.id=s.raw_sms_id
      WHERE x.collection_id=p_collection AND r.object_key<>p_key AND r.body_sha256=p_body)
    OR EXISTS(SELECT 1 FROM app.momo_financial_links f JOIN app.payments p ON p.id=f.payment_id
      JOIN app.momo_transaction_sources s ON s.transaction_id=f.transaction_id
      JOIN app.sms_receipts r ON r.id=s.raw_sms_id
      WHERE p.collection_id=p_collection AND r.object_key<>p_key AND r.body_sha256=p_body)
    OR EXISTS(SELECT 1 FROM private.storage_payload_reservations s
      LEFT JOIN private.collect_sms_witnesses x ON x.object_key=s.object_key
      LEFT JOIN private.burimunsi_unresolved_observations r ON r.object_key=s.object_key
      LEFT JOIN private.burimunsi_observation_requests q ON 'sms/'||q.source_id=s.object_key
      LEFT JOIN private.burimunsi_sms_source_scopes scope ON 'sms/'||scope.source_id=s.object_key
      LEFT JOIN private.storage_put_intents i ON i.object_key=s.object_key
      WHERE s.scope->>'purpose'='sms_receipt' AND s.object_key<>p_key AND x.object_key IS NULL
       AND (q.collection_id=p_collection OR r.collection_id=p_collection OR scope.collection_id=p_collection)
       AND (r.object_key IS NULL AND scope.source_id IS NULL OR i.active_attempt IS NOT NULL OR i.upload_unresolved)) THEN
    RAISE EXCEPTION 'sms_witness_ambiguous' USING ERRCODE='55000';END IF;
  END IF;
  INSERT INTO private.collect_sms_witnesses(object_key,owner_id,collection_id,request_digest,body_sha256,inbox_received_at,storage_fingerprint)
   VALUES(p_key,p_owner,p_collection,p_request,p_body,p_inbox,p_storage);created:=true;
 END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_o,''),true);
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);
 RETURN created;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_o,''),true);
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text) TO collect_runtime;

-- The hold is recorded in the same fenced transaction as the new request.
-- An old ordinary pending request cannot be converted into a recovery hold.
CREATE FUNCTION private.burimunsi_sms_recovery_hold(p_source text,p_request uuid,p_fingerprint text,
 p_body text,p_inbox timestamptz) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(true);c jsonb:=private.burimunsi_observation_consent_current();
 old_w text:=current_setting('collect.sms_witness_frame',true);
 old_o text:=current_setting('burimunsi.observation_frame',true);q private.burimunsi_observation_requests%ROWTYPE;
 prior private.burimunsi_recovered_sms_holds%ROWTYPE;
BEGIN
 PERFORM private.collect_fence_assert_write(current_setting('collect.fence_admission_id',true)::uuid,
  current_setting('collect.fence_epoch',true)::bigint,current_setting('collect.fence_source_sha256',true));
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 IF p_source IS NULL OR p_source !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' OR p_request IS NULL
  OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$' OR p_body IS NULL OR p_body !~ '^[a-f0-9]{64}$'
  OR p_inbox IS NULL OR c->'enabled' IS DISTINCT FROM 'true'::jsonb THEN
  RAISE EXCEPTION 'sms_recovery_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('collect.sms_witness_frame','1',true);
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO q FROM private.burimunsi_observation_requests WHERE source_id=p_source FOR SHARE;
 IF NOT FOUND OR q.collection_id IS DISTINCT FROM a->>'collectionId' OR q.account_id IS DISTINCT FROM (a->>'accountId')::uuid
  OR q.principal_user_id IS DISTINCT FROM a->>'principalUserId' OR q.installation_id IS DISTINCT FROM (a->>'installationId')::uuid
  OR q.grant_id IS DISTINCT FROM (a->>'grantId')::uuid OR q.grant_version IS DISTINCT FROM (a->>'grantVersion')::bigint
  OR q.request_id IS DISTINCT FROM p_request OR q.fingerprint IS DISTINCT FROM p_fingerprint
  OR q.source_key IS NULL OR q.source_key_body_sha256 IS DISTINCT FROM p_body
  OR NOT EXISTS(SELECT 1 FROM private.collect_sms_witnesses w WHERE w.object_key='sms/'||p_source
   AND w.owner_id=q.principal_user_id AND w.collection_id=q.collection_id AND w.body_sha256=p_body
   AND w.inbox_received_at=p_inbox AND w.request_digest=p_fingerprint) THEN
  RAISE EXCEPTION 'sms_recovery_changed' USING ERRCODE='55000';END IF;
 SELECT * INTO prior FROM private.burimunsi_recovered_sms_holds WHERE source_id=p_source;
 IF FOUND THEN
  IF prior.object_key IS DISTINCT FROM 'sms/'||p_source OR prior.collection_id IS DISTINCT FROM q.collection_id
   OR prior.account_id IS DISTINCT FROM q.account_id OR prior.owner_id IS DISTINCT FROM q.principal_user_id
   OR prior.body_sha256 IS DISTINCT FROM p_body OR prior.inbox_received_at IS DISTINCT FROM p_inbox
   OR prior.request_digest IS DISTINCT FROM p_fingerprint THEN
   RAISE EXCEPTION 'sms_recovery_changed' USING ERRCODE='55000';END IF;
 ELSE
  -- An existing request might belong to a live upload. Only this transaction's
  -- fresh request may acquire the new immutable hold.
  IF NOT EXISTS(SELECT 1 FROM private.burimunsi_observation_requests n WHERE n.source_id=p_source
    AND n.xmin=pg_current_xact_id()::text::xid)
   OR EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r WHERE r.source_id=p_source)
   OR EXISTS(SELECT 1 FROM private.burimunsi_auto_sms_jobs j WHERE j.source_id=p_source)
   OR EXISTS(SELECT 1 FROM private.burimunsi_native_financial_work f WHERE f.source_id=p_source)
   OR EXISTS(SELECT 1 FROM app.sms_receipts s WHERE s.id=p_source) THEN
   RAISE EXCEPTION 'sms_recovery_changed' USING ERRCODE='55000';END IF;
  INSERT INTO private.burimunsi_recovered_sms_holds(source_id,object_key,collection_id,account_id,owner_id,
   body_sha256,inbox_received_at,request_digest)
  VALUES(p_source,'sms/'||p_source,q.collection_id,q.account_id,q.principal_user_id,p_body,p_inbox,p_fingerprint);
 END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_o,''),true);
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);RETURN true;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_o,''),true);
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz) TO collect_runtime;

-- Exact acknowledgement is a read-only proof, never an admission or retry.
-- Absence, incomplete custody, mismatched ownership and unfinished work all
-- return NULL. The current actor must still hold reveal permission and consent.
CREATE FUNCTION private.burimunsi_sms_recovery_ack_snapshot(p_source text,p_request uuid,p_fingerprint text,
 p_source_key text,p_content text,p_body text,p_inbox timestamptz) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;consent jsonb;request_row private.burimunsi_observation_requests%ROWTYPE;
 retained jsonb;proof jsonb;hash text;expected_id text;
 old_w text:=current_setting('collect.sms_witness_frame',true);
 old_o text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 IF current_setting('transaction_read_only') IS DISTINCT FROM 'on' THEN
  RAISE EXCEPTION 'sms_recovery_ack_read_only_required' USING ERRCODE='25006';END IF;
 actor:=private.burimunsi_observation_actor(true);consent:=private.burimunsi_observation_consent_current();
 IF consent->'enabled' IS DISTINCT FROM 'true'::jsonb THEN
  RAISE EXCEPTION 'sms_recovery_ack_denied' USING ERRCODE='42501';END IF;
 IF p_source IS NULL OR p_source !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' OR p_request IS NULL
  OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$'
  OR p_source_key IS NULL OR p_source_key !~ '^[a-f0-9]{64}$'
  OR p_content IS NULL OR p_content !~ '^[a-f0-9]{64}$'
  OR p_body IS NULL OR p_body !~ '^[a-f0-9]{64}$' OR p_inbox IS NULL THEN
  RAISE EXCEPTION 'sms_recovery_ack_invalid' USING ERRCODE='22023';END IF;
 hash:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||
  (actor->>'principalUserId')||E'\n'||p_request::text,'UTF8')),'hex');
 expected_id:=substr(hash,1,8)||'-'||substr(hash,9,4)||'-5'||substr(hash,14,3)||'-8'||substr(hash,18,3)||'-'||substr(hash,21,12);
 IF p_source IS DISTINCT FROM expected_id THEN RAISE EXCEPTION 'sms_recovery_ack_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('collect.sms_witness_frame','1',true);
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO request_row FROM private.burimunsi_observation_requests q WHERE q.source_id=p_source
  AND q.collection_id=actor->>'collectionId' AND q.account_id=(actor->>'accountId')::uuid
  AND q.principal_user_id=actor->>'principalUserId' AND q.installation_id=(actor->>'installationId')::uuid
  AND q.grant_id=(actor->>'grantId')::uuid AND q.grant_version=(actor->>'grantVersion')::bigint
  AND q.initial_consent_generation=(consent->>'generation')::bigint AND q.request_id=p_request
  AND q.fingerprint=p_fingerprint AND q.source_key=p_source_key
  AND q.source_key_content_sha256=p_content AND q.source_key_body_sha256=p_body;
 IF FOUND AND EXISTS(SELECT 1 FROM private.burimunsi_recovered_sms_holds h
   JOIN private.collect_sms_witnesses w ON w.object_key=h.object_key
   WHERE h.source_id=p_source AND h.object_key='sms/'||p_source AND h.collection_id=request_row.collection_id
    AND h.account_id=request_row.account_id AND h.owner_id=request_row.principal_user_id
    AND h.body_sha256=p_body AND h.inbox_received_at=p_inbox AND h.request_digest=p_fingerprint
    AND w.owner_id=request_row.principal_user_id AND w.collection_id=request_row.collection_id
    AND w.body_sha256=p_body AND w.inbox_received_at=p_inbox AND w.request_digest=p_fingerprint)
  AND NOT EXISTS(SELECT 1 FROM private.burimunsi_auto_sms_jobs j WHERE j.source_id=p_source)
  AND NOT EXISTS(SELECT 1 FROM private.burimunsi_native_financial_work f WHERE f.source_id=p_source)
  AND NOT EXISTS(SELECT 1 FROM app.sms_receipts s WHERE s.id=p_source OR s.object_key='sms/'||p_source)
  AND NOT EXISTS(SELECT 1 FROM app.momo_processing_jobs j WHERE j.raw_sms_id=p_source)
  AND NOT EXISTS(SELECT 1 FROM app.momo_parse_attempts j WHERE j.raw_sms_id=p_source)
  AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources j WHERE j.raw_sms_id=p_source)
  AND NOT EXISTS(SELECT 1 FROM app.privacy_retention_barriers b WHERE b.subject_id=request_row.principal_user_id) THEN
  retained:=private.burimunsi_observation_lookup(p_request,p_fingerprint);
  IF retained IS NOT NULL AND retained->>'sourceId'=p_source AND retained->>'bodySha256'=p_body THEN
   SELECT jsonb_build_object('record',retained,'namespace',jsonb_build_object('origin',n.origin,'bucket',n.bucket),
     'put',to_jsonb(i),'metadata',to_jsonb(m),'reservation',to_jsonb(s)-'sealed_body',
     'reservationCipherSha256',CASE WHEN s.sealed_body IS NULL THEN NULL ELSE encode(sha256(convert_to(s.sealed_body,'UTF8')),'hex') END,
     'reservationCipherSize',CASE WHEN s.sealed_body IS NULL THEN NULL ELSE octet_length(s.sealed_body) END)
    INTO proof FROM private.storage_put_intents i
    JOIN private.storage_objects m ON m.object_key=i.object_key
    JOIN private.storage_payload_reservations s ON s.object_key=i.object_key
    JOIN private.storage_namespace n ON n.singleton=true
    WHERE i.object_key='sms/'||p_source AND i.state='committed' AND NOT i.delete_tombstone
     AND NOT i.upload_unresolved AND i.active_attempt IS NULL
     AND m.operation_id=i.operation_id AND m.fingerprint=i.fingerprint AND m.sha256=i.sha256 AND m.size=i.size
     AND m.scope=i.scope AND m.http_metadata=i.http_metadata AND m.custom_metadata=i.custom_metadata
     AND s.scope=i.scope AND s.plaintext_sha256=retained->>'object_sha256'
     AND ((s.sealed_body IS NULL)=(s.cleared_at IS NOT NULL))
     AND s.aad='sms:'||p_source||':'||(retained->>'object_sha256')
     AND i.scope=jsonb_build_object('ownerId',request_row.principal_user_id,'purpose','sms_receipt','entityId',p_source)
     AND EXISTS(SELECT 1 FROM private.collect_sms_witnesses w WHERE w.object_key=i.object_key
      AND w.collection_id=request_row.collection_id AND w.storage_fingerprint=s.source_fingerprint)
     AND i.custom_metadata->>'source_fingerprint'=s.source_fingerprint
     AND i.custom_metadata->>'key_id'=s.key_id AND i.custom_metadata->>'sha256'=retained->>'object_sha256'
     AND NOT EXISTS(SELECT 1 FROM private.storage_delete_intents d WHERE d.object_key=i.object_key);
  END IF;
 END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_o,''),true);
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);
 RETURN proof;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_o,''),true);
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_sms_recovery_ack_snapshot(text,uuid,text,text,text,text,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_sms_recovery_ack_snapshot(text,uuid,text,text,text,text,timestamptz) TO collect_runtime;

-- A native request and its witness commit together, including after retry.
CREATE FUNCTION private.collect_sms_request_witness_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE prior text:=current_setting('collect.sms_witness_frame',true);ok boolean;
BEGIN
 IF NEW.source_key IS NULL THEN RETURN NEW;END IF;
 PERFORM set_config('collect.sms_witness_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM private.collect_sms_witnesses w WHERE w.object_key='sms/'||NEW.source_id
  AND w.owner_id=NEW.principal_user_id AND w.collection_id=NEW.collection_id
  AND w.request_digest=NEW.fingerprint AND w.body_sha256=NEW.source_key_body_sha256) INTO ok;
 PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);
 IF NOT ok THEN RAISE EXCEPTION 'sms_witness_missing' USING ERRCODE='55000';END IF;
 RETURN NEW;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_request_witness_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE CONSTRAINT TRIGGER collect_sms_request_witness_guard AFTER INSERT ON private.burimunsi_observation_requests
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION private.collect_sms_request_witness_guard();
ALTER TABLE private.burimunsi_observation_requests ENABLE ALWAYS TRIGGER collect_sms_request_witness_guard;

-- Never initiate a new SMS payload reservation without the exact bound witness.
CREATE FUNCTION private.collect_sms_payload_witness_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE prior text:=current_setting('collect.sms_witness_frame',true);ok boolean;
BEGIN
 IF NEW.scope->>'purpose'<>'sms_receipt' THEN RETURN NEW;END IF;
 PERFORM set_config('collect.sms_witness_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM private.collect_sms_witnesses w WHERE w.object_key=NEW.object_key
  AND w.owner_id=NEW.scope->>'ownerId' AND w.storage_fingerprint=NEW.source_fingerprint) INTO ok;
 PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);
 IF NOT ok THEN RAISE EXCEPTION 'sms_witness_missing' USING ERRCODE='55000';END IF;
 RETURN NEW;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_payload_witness_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_sms_payload_witness_guard BEFORE INSERT ON private.storage_payload_reservations
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_payload_witness_guard();
ALTER TABLE private.storage_payload_reservations ENABLE ALWAYS TRIGGER collect_sms_payload_witness_guard;

-- A held recovery's own source can never become a canonical receipt through
-- this path. Other uploads are allowed; an associated same-group source is
-- reflected as unmatched in that group's reconciliation snapshot.
CREATE FUNCTION private.collect_sms_held_source_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE prior text:=current_setting('collect.sms_witness_frame',true);blocked boolean;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM set_config('collect.sms_witness_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_recovered_sms_holds h
  WHERE h.object_key=NEW.object_key OR h.source_id=NEW.id)
  OR EXISTS(SELECT 1 FROM app.momo_transaction_sources s JOIN private.burimunsi_recovered_sms_holds h
   ON h.body_sha256=NEW.body_sha256 WHERE s.raw_sms_id=NEW.id
   AND (EXISTS(SELECT 1 FROM private.burimunsi_transaction_scopes x
     WHERE x.transaction_id=s.transaction_id AND x.collection_id=h.collection_id)
    OR EXISTS(SELECT 1 FROM app.momo_financial_links f JOIN app.payments p ON p.id=f.payment_id
     WHERE f.transaction_id=s.transaction_id AND p.collection_id=h.collection_id))) INTO blocked;
 PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);
 IF blocked THEN RAISE EXCEPTION 'sms_witness_ambiguous' USING ERRCODE='55000';END IF;
 RETURN NEW;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_held_source_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_sms_held_source_guard BEFORE INSERT OR UPDATE ON app.sms_receipts
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_held_source_guard();
ALTER TABLE app.sms_receipts ENABLE ALWAYS TRIGGER collect_sms_held_source_guard;

-- This separate opt-in status builds on the unmodified deployed status. It is
-- limited to verified collection provenance and does not claim unscoped SMS.
CREATE FUNCTION private.burimunsi_observation_reconcile_verified_status() RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE base jsonb;cid text;rev text;extra text;witness_count bigint;
 witness_pending boolean;witness_unmatched boolean;
 old_w text:=current_setting('collect.sms_witness_frame',true);
 old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 -- The original pinned function independently checks current actor, consent,
 -- group and source custody. Its flags are lower bounds for this status.
 base:=private.burimunsi_observation_reconcile_status();cid:=base->>'groupId';
 IF cid IS NULL OR cid IS DISTINCT FROM current_setting('burimunsi.collection_id',true)
  OR jsonb_typeof(base->'hasPending') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(base->'hasRecorded') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(base->'hasUnmatchedCanonical') IS DISTINCT FROM 'boolean'
  OR coalesce(base->>'revision','') !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'sms_recovery_status_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 PERFORM set_config('collect.sms_witness_frame','1',true);
 SELECT count(*) INTO witness_count FROM (SELECT 1 FROM private.collect_sms_witnesses w
  WHERE w.collection_id=cid LIMIT 100001) bounded;
 IF witness_count>100000 THEN RAISE EXCEPTION 'sms_witness_limit' USING ERRCODE='54000';END IF;
 SELECT EXISTS(SELECT 1 FROM private.collect_sms_witnesses w
  LEFT JOIN private.storage_put_intents i ON i.object_key=w.object_key
  LEFT JOIN private.burimunsi_unresolved_observations r ON r.object_key=w.object_key AND r.collection_id=cid
  LEFT JOIN private.burimunsi_sms_source_scopes scoped ON 'sms/'||scoped.source_id=w.object_key AND scoped.collection_id=cid
  WHERE w.collection_id=cid
   AND ((r.object_key IS NULL AND scoped.source_id IS NULL) OR i.object_key IS NULL
     OR i.scope->>'ownerId' IS DISTINCT FROM w.owner_id OR i.active_attempt IS NOT NULL OR i.upload_unresolved))
  OR EXISTS(SELECT 1 FROM private.storage_payload_reservations p
   LEFT JOIN private.collect_sms_witnesses w ON w.object_key=p.object_key
   LEFT JOIN private.burimunsi_unresolved_observations r ON r.object_key=p.object_key AND r.collection_id=cid
   LEFT JOIN private.burimunsi_observation_requests q ON 'sms/'||q.source_id=p.object_key AND q.collection_id=cid
   LEFT JOIN private.burimunsi_sms_source_scopes scoped ON 'sms/'||scoped.source_id=p.object_key AND scoped.collection_id=cid
   LEFT JOIN private.storage_put_intents i ON i.object_key=p.object_key
   WHERE p.scope->>'purpose'='sms_receipt' AND w.object_key IS NULL
    AND (q.collection_id=cid OR r.collection_id=cid OR scoped.collection_id=cid)
    AND ((r.object_key IS NULL AND scoped.source_id IS NULL) OR i.active_attempt IS NOT NULL OR i.upload_unresolved))
  INTO witness_pending;
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r
  JOIN private.collect_sms_witnesses w ON w.collection_id=cid AND w.body_sha256=r.body_sha256 AND w.object_key<>r.object_key
  WHERE r.collection_id=cid
   AND (EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations other WHERE other.object_key=w.object_key AND other.collection_id=cid)
     OR EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes other WHERE other.collection_id=cid AND 'sms/'||other.source_id=w.object_key)))
  OR EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r
   JOIN private.burimunsi_sms_source_scopes scoped ON scoped.collection_id=cid
   JOIN app.sms_receipts s ON s.id=scoped.source_id AND s.body_sha256=r.body_sha256 AND s.object_key<>r.object_key
   WHERE r.collection_id=cid) INTO witness_unmatched;
 WITH entries AS (
  SELECT w.object_key AS k,encode(sha256(convert_to(jsonb_build_array(to_jsonb(w),to_jsonb(i),to_jsonb(r),to_jsonb(s))::text,'UTF8')),'hex') AS h
  FROM private.collect_sms_witnesses w LEFT JOIN private.storage_put_intents i ON i.object_key=w.object_key
  LEFT JOIN private.burimunsi_unresolved_observations r ON r.object_key=w.object_key AND r.collection_id=cid
  LEFT JOIN app.sms_receipts s ON s.object_key=w.object_key AND s.owner_user_id=w.owner_id
  WHERE w.collection_id=cid
 ) SELECT encode(sha256(convert_to(coalesce(string_agg(h,E'\n' ORDER BY k),''),'UTF8')),'hex') INTO extra FROM entries;
 rev:=encode(sha256(convert_to(jsonb_build_array(base->>'revision',extra,witness_pending,witness_unmatched)::text,'UTF8')),'hex');
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('groupId',cid,'hasPending',(base->>'hasPending')::boolean OR witness_pending,
  'hasRecorded',(base->>'hasRecorded')::boolean,'recordedCount',base->'recordedCount',
  'hasUnmatchedCanonical',(base->>'hasUnmatchedCanonical')::boolean OR witness_unmatched,'revision',rev);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_reconcile_verified_status() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_reconcile_verified_status() TO collect_runtime;

-- Keep the imported-history predicate unchanged. A recovered source is held
-- permanently; another verified same-group source with equal body is also
-- restricted until independent evidence can distinguish it. Unscoped sources
-- and witnesses of other groups are never considered as cross-group matches.
CREATE FUNCTION private.collect_sms_recovery_held(p_source text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE prior text:=current_setting('collect.sms_witness_frame',true);answer boolean;
BEGIN
 PERFORM set_config('collect.sms_witness_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_recovered_sms_holds h WHERE h.source_id=p_source)
  OR EXISTS(SELECT 1 FROM private.collect_sms_witnesses w JOIN private.burimunsi_recovered_sms_holds h
    ON h.collection_id=w.collection_id AND h.body_sha256=w.body_sha256
   WHERE w.object_key='sms/'||p_source AND w.collection_id IS NOT NULL)
  OR EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes scoped
   JOIN app.sms_receipts s ON s.id=scoped.source_id
   JOIN private.burimunsi_recovered_sms_holds h ON h.collection_id=scoped.collection_id AND h.body_sha256=s.body_sha256
   WHERE scoped.source_id=p_source) INTO answer;
 PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RETURN answer;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_recovery_held(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

-- Final association and financial boundaries also cover a source parsed
-- before the recovery hold, including a source with no source-scope row.
-- All these checks and recovery admission take the same transaction lock so
-- either ordering sees the committed competing state before it can proceed.
CREATE FUNCTION private.collect_sms_recovery_transaction_matches(p_transaction text,p_collection text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE prior text:=current_setting('collect.sms_witness_frame',true);answer boolean;
BEGIN
 PERFORM set_config('collect.sms_witness_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM app.momo_transaction_sources s JOIN app.sms_receipts r ON r.id=s.raw_sms_id
  JOIN private.burimunsi_recovered_sms_holds h ON h.collection_id=p_collection AND h.body_sha256=r.body_sha256
  WHERE s.transaction_id=p_transaction) INTO answer;
 PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RETURN answer;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_recovery_transaction_matches(text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

CREATE FUNCTION private.collect_sms_recovery_scope_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 IF private.collect_sms_recovery_transaction_matches(NEW.transaction_id,NEW.collection_id) THEN
  RAISE EXCEPTION 'sms_recovery_financial_hold' USING ERRCODE='55000';END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_recovery_scope_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_sms_recovery_scope_guard BEFORE INSERT OR UPDATE ON private.burimunsi_transaction_scopes
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_recovery_scope_guard();
ALTER TABLE private.burimunsi_transaction_scopes ENABLE ALWAYS TRIGGER collect_sms_recovery_scope_guard;

CREATE FUNCTION private.collect_sms_recovery_financial_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE collection text;blocked boolean;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 IF TG_TABLE_NAME='momo_financial_links' THEN
  SELECT p.collection_id INTO collection FROM app.payments p WHERE p.id=NEW.payment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'sms_recovery_payment_missing' USING ERRCODE='55000';END IF;
  blocked:=private.collect_sms_recovery_transaction_matches(NEW.transaction_id,collection);
 ELSE
  SELECT EXISTS(SELECT 1 FROM app.momo_financial_links f WHERE f.payment_id=NEW.id
   AND private.collect_sms_recovery_transaction_matches(f.transaction_id,NEW.collection_id)) INTO blocked;
 END IF;
 IF blocked THEN RAISE EXCEPTION 'sms_recovery_financial_hold' USING ERRCODE='55000';END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_recovery_financial_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_sms_recovery_financial_guard BEFORE INSERT OR UPDATE ON app.momo_financial_links
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_recovery_financial_guard();
ALTER TABLE app.momo_financial_links ENABLE ALWAYS TRIGGER collect_sms_recovery_financial_guard;
CREATE TRIGGER collect_sms_recovery_financial_guard BEFORE UPDATE OF collection_id ON app.payments
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_recovery_financial_guard();
ALTER TABLE app.payments ENABLE ALWAYS TRIGGER collect_sms_recovery_financial_guard;

-- Preserve each original function identity and ACL while adding one pinned,
-- narrowly-scoped hold check. Each predecessor must be the reviewed version.
DO $patch_processing$
DECLARE item record;body text;definition text;changed text;
BEGIN
 FOR item IN SELECT * FROM (VALUES
  ('private.burimunsi_auto_snapshot(text)','29bcd9f8440ab6d99571871ca7dc0203ec516d6f4d673a91bfc20eb5cef227f6',
   $old$IF private.collect_imported_native_source(p_source) OR private.collect_imported_native_job_transaction(p_source)$old$,
   $new$IF private.collect_sms_recovery_held(p_source) OR private.collect_imported_native_source(p_source) OR private.collect_imported_native_job_transaction(p_source)$new$),
  ('private.burimunsi_auto_candidates(text)','de95126024a114bc696bb570b866aece8d2334bd4db5f742428270c71c682e28',
   $old$WHERE NOT private.collect_imported_native_source(o.source_id)$old$,
   $new$WHERE NOT private.collect_sms_recovery_held(o.source_id) AND NOT private.collect_imported_native_source(o.source_id)$new$),
  ('private.burimunsi_native_work_candidates(uuid,integer)','7f6186d02734c5e40ef0e66051d271d1d67e183b2c78ebbe86e7233b78fc729e',
   $old$WHERE NOT private.collect_imported_native_source(source_id)$old$,
   $new$WHERE NOT private.collect_sms_recovery_held(source_id) AND NOT private.collect_imported_native_source(source_id)$new$),
  ('private.burimunsi_native_sms_post_candidates(integer)','9e1a2a348a06f270afb65055c58edc7e88181385adac3dd24991384b86fe0adc',
   $old$WHERE NOT private.collect_imported_native_source(j.source_id)$old$,
   $new$WHERE NOT private.collect_sms_recovery_held(j.source_id) AND NOT private.collect_imported_native_source(j.source_id)$new$),
  ('private.burimunsi_observation_processing_status(jsonb)','088bb545a1b94022c1bb76203ca7250fa185ad948a5c36d87f4604ef5f32d332',
   $old$IF private.collect_imported_native_source(source) THEN status:='historical';$old$,
   $new$IF private.collect_sms_recovery_held(source) OR private.collect_imported_native_source(source) THEN status:='historical';$new$),
  ('private.burimunsi_observation_processing_retry(text,uuid)','dfa2af64c98f03135240ac62fb20276b1f9c72495e81d540e53853d5fd6ef863',
   $old$IF NOT private.collect_imported_native_source(p_source) AND NOT private.collect_imported_native_job_transaction(p_source)$old$,
   $new$IF NOT private.collect_sms_recovery_held(p_source) AND NOT private.collect_imported_native_source(p_source) AND NOT private.collect_imported_native_job_transaction(p_source)$new$)
 ) AS t(signature,digest,anchor,replacement) LOOP
  SELECT p.prosrc,pg_get_functiondef(p.oid) INTO STRICT body,definition FROM pg_proc p WHERE p.oid=to_regprocedure(item.signature);
  IF encode(sha256(convert_to(body,'UTF8')),'hex')<>item.digest
   OR length(body)-length(replace(body,item.anchor,''))<>length(item.anchor)
   OR length(definition)-length(replace(definition,body,''))<>length(body) THEN
   RAISE EXCEPTION 'sms_recovery_processing_predecessor_changed: %',item.signature USING ERRCODE='55000';END IF;
  changed:=replace(body,item.anchor,item.replacement);EXECUTE replace(definition,body,changed);
 END LOOP;
END;$patch_processing$;

CREATE FUNCTION private.collect_sms_recovery_work_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF (TG_OP<>'INSERT' AND private.collect_sms_recovery_held(OLD.source_id))
  OR (TG_OP<>'DELETE' AND private.collect_sms_recovery_held(NEW.source_id)) THEN
  RAISE EXCEPTION 'sms_recovery_financial_hold' USING ERRCODE='55000';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;ELSE RETURN NEW;END IF;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_recovery_work_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_sms_recovery_work_guard BEFORE INSERT OR UPDATE OR DELETE ON private.burimunsi_auto_sms_jobs
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_recovery_work_guard();
ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ALWAYS TRIGGER collect_sms_recovery_work_guard;
CREATE TRIGGER collect_sms_recovery_work_guard BEFORE INSERT OR UPDATE OR DELETE ON private.burimunsi_native_financial_work
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_recovery_work_guard();
ALTER TABLE private.burimunsi_native_financial_work ENABLE ALWAYS TRIGGER collect_sms_recovery_work_guard;

-- Canonical processing paths use raw_sms_id rather than source_id. A held
-- source must not enter those paths, even through a direct retry or association.
CREATE FUNCTION private.collect_sms_recovery_raw_work_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE prior text:=current_setting('collect.sms_witness_frame',true);blocked boolean;
BEGIN
 IF TG_TABLE_NAME='momo_transaction_sources' AND TG_OP<>'DELETE' THEN
  PERFORM pg_advisory_xact_lock(734636924058501::bigint);
  PERFORM set_config('collect.sms_witness_frame','1',true);
  SELECT EXISTS(SELECT 1 FROM app.sms_receipts r JOIN private.burimunsi_recovered_sms_holds h ON h.body_sha256=r.body_sha256
   WHERE r.id=NEW.raw_sms_id AND (EXISTS(SELECT 1 FROM private.burimunsi_transaction_scopes x
    WHERE x.transaction_id=NEW.transaction_id AND x.collection_id=h.collection_id)
    OR EXISTS(SELECT 1 FROM app.momo_financial_links f JOIN app.payments p ON p.id=f.payment_id
     WHERE f.transaction_id=NEW.transaction_id AND p.collection_id=h.collection_id))) INTO blocked;
  PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);
  IF blocked THEN RAISE EXCEPTION 'sms_recovery_financial_hold' USING ERRCODE='55000';END IF;
 END IF;
 -- Gateway capture creates its processing row in the same transaction as the
 -- receipt. Keep ingestion intact, but park an ambiguous new job so it cannot
 -- be claimed, parsed, resolved or posted without a future reviewed design.
 IF TG_TABLE_NAME='momo_processing_jobs' AND TG_OP='INSERT' AND private.collect_sms_recovery_held(NEW.raw_sms_id) THEN
  NEW.state:='source_unresolved';NEW.lease_token:=NULL;NEW.lease_until:=NULL;
  NEW.last_error:='sms_recovery_financial_hold';RETURN NEW;
 END IF;
 -- A previously unscoped queued source can acquire a verified group later.
 -- Park it as the queue reaches it, preserving unknown in-flight work for
 -- review rather than repeatedly failing the shared queue or hiding an effect.
 IF TG_TABLE_NAME='momo_processing_jobs' AND TG_OP='UPDATE' AND private.collect_sms_recovery_held(OLD.raw_sms_id) THEN
  IF OLD.state IN('pending','retry') THEN
   NEW:=OLD;NEW.state:='source_unresolved';NEW.lease_token:=NULL;NEW.lease_until:=NULL;
   NEW.last_error:='sms_recovery_financial_hold';RETURN NEW;
  ELSIF OLD.state='processing' THEN
   NEW:=OLD;NEW.state:='needs_review';NEW.lease_token:=NULL;NEW.lease_until:=NULL;
   NEW.last_error:='sms_recovery_financial_hold_unknown';RETURN NEW;
  END IF;
  RETURN NULL;
 END IF;
 IF (TG_OP<>'INSERT' AND private.collect_sms_recovery_held(OLD.raw_sms_id))
  OR (TG_OP<>'DELETE' AND private.collect_sms_recovery_held(NEW.raw_sms_id)) THEN
  RAISE EXCEPTION 'sms_recovery_financial_hold' USING ERRCODE='55000';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;ELSE RETURN NEW;END IF;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('collect.sms_witness_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_sms_recovery_raw_work_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_sms_recovery_raw_work_guard BEFORE INSERT OR UPDATE OR DELETE ON app.momo_processing_jobs
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_recovery_raw_work_guard();
ALTER TABLE app.momo_processing_jobs ENABLE ALWAYS TRIGGER collect_sms_recovery_raw_work_guard;
CREATE TRIGGER collect_sms_recovery_raw_work_guard BEFORE INSERT OR UPDATE OR DELETE ON app.momo_parse_attempts
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_recovery_raw_work_guard();
ALTER TABLE app.momo_parse_attempts ENABLE ALWAYS TRIGGER collect_sms_recovery_raw_work_guard;
CREATE TRIGGER collect_sms_recovery_raw_work_guard BEFORE INSERT OR UPDATE OR DELETE ON app.momo_transaction_sources
 FOR EACH ROW EXECUTE FUNCTION private.collect_sms_recovery_raw_work_guard();
ALTER TABLE app.momo_transaction_sources ENABLE ALWAYS TRIGGER collect_sms_recovery_raw_work_guard;

-- Register these immutable source/hold records for inspection without
-- claiming complete subject mapping or authorizing erasure or replay.
DO $held_retention$
DECLARE body text;next_body text;anchor text;replacement text;item record;entries jsonb;
BEGIN
 IF to_regprocedure('private._retention_manifest_catalog_v2()') IS NULL OR
  to_regprocedure('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)') IS NULL OR
  EXISTS(SELECT 1 FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') c
   WHERE c->>'relation' IN('private.collect_sms_witnesses','private.burimunsi_recovered_sms_holds')) THEN
  RAISE EXCEPTION 'sms_recovery_retention_precondition' USING ERRCODE='55000';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('private._retention_manifest_catalog_v2()','b05ee1ced84adfbde6f9144039cbd062730dece8dfc060f636425fa64c90d032',false,'i','{postgres=X/postgres}'),
  ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','9fcadb280a30843d3d1d8a006e556a8532f365e3e0b30596d5336e6ab3c9c336',true,'v','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) e(signature,digest,definer,volatility,acl) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(item.signature)
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=item.definer AND p.provolatile=item.volatility::"char"
   AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND p.proacl::text=item.acl
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=item.digest) THEN
   RAISE EXCEPTION 'sms_recovery_retention_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 entries:=jsonb_build_array(
  jsonb_build_object('name','private:collect_sms_witnesses','relation','private.collect_sms_witnesses','scope','unmapped_private',
   'purpose','Source digest and owner association; inspection only, effects blocked',
   'known_links','owner_id identifies the source owner; object_key identifies retained evidence','blocked',true),
  jsonb_build_object('name','private:burimunsi_recovered_sms_holds','relation','private.burimunsi_recovered_sms_holds','scope','unmapped_private',
   'purpose','Immutable non-financial recovery hold; inspection only, effects blocked',
   'known_links','owner_id and account_id identify the operator; source_id identifies retained evidence','blocked',true));
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 next_body:=format('SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||%L::jsonb) FROM (%s) prior(base)',entries::text,body);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
 anchor:=$a$'private:burimunsi_observation_retry_commands','managed:storage_iceberg','private:burimunsi_native_lease_history'$a$;
 replacement:=$b$'private:collect_sms_witnesses','private:burimunsi_recovered_sms_holds','private:burimunsi_observation_retry_commands','managed:storage_iceberg','private:burimunsi_native_lease_history'$b$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'sms_recovery_retention_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(replace(body,anchor,replacement));
END;$held_retention$;

COMMIT;
