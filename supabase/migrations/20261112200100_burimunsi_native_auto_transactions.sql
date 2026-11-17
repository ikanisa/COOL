-- Native automatic transaction capture; deploy only with compatible callers.
-- Native transactions use the authenticated collection scope, not a fake gateway.
-- This migration writes no payments or ledger entries.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regclass('private.burimunsi_unresolved_observations') IS NULL
  OR to_regprocedure('private.burimunsi_observation_own(text,boolean)') IS NULL
  OR to_regclass('private.burimunsi_native_receipt_origins') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='app.sms_receipts'::regclass
       AND attname='originating_session_id' AND attnotnull AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='app.sms_receipts'::regclass
       AND attname='receiver_hash' AND attnotnull AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='app.sms_receipts'::regclass
       AND conname='fk_sms_receipts_0' AND contype='f'
       AND confrelid='app.auth_sessions'::regclass AND convalidated)
 THEN RAISE EXCEPTION 'burimunsi_native_intake_precondition' USING ERRCODE='55000'; END IF;
END;$preflight$;

-- The genuine managed-session FK remains intact.  Its absence is allowed only
-- for a source backed by the immutable native provenance enforced below.
ALTER TABLE app.sms_receipts ALTER COLUMN originating_session_id DROP NOT NULL;
ALTER TABLE app.sms_receipts ALTER COLUMN receiver_hash DROP NOT NULL;
ALTER TABLE app.sms_receipts ADD CONSTRAINT burimunsi_native_origin_shape CHECK(
 (originating_session_id IS NOT NULL AND receiver_hash IS NOT NULL) OR
 (originating_session_id IS NULL AND receiver_hash IS NULL));

CREATE TABLE private.burimunsi_native_receipt_origins(
 source_id text PRIMARY KEY REFERENCES private.burimunsi_unresolved_observations(source_id),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 account_id uuid NOT NULL,principal_user_id text NOT NULL REFERENCES app.users(id),
 installation_id uuid NOT NULL,grant_id uuid NOT NULL,grant_version bigint NOT NULL CHECK(grant_version>0),
 capture_session_id uuid NOT NULL REFERENCES private.burimunsi_sessions(id),
 admitting_session_id uuid REFERENCES private.burimunsi_sessions(id),
 admission_kind text NOT NULL CHECK(admission_kind IN ('native_actor','jobs')),
 request_id uuid NOT NULL,fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[a-f0-9]{64}$'),
 object_sha256 text NOT NULL CHECK(object_sha256 ~ '^[a-f0-9]{64}$'),
 admitted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id),
 FOREIGN KEY(grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id),
 FOREIGN KEY(source_id) REFERENCES app.sms_receipts(id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((admission_kind='native_actor' AND admitting_session_id IS NOT NULL) OR
       (admission_kind='jobs' AND admitting_session_id IS NULL))
);
ALTER TABLE private.burimunsi_native_receipt_origins ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_native_receipt_origins FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_native_receipt_origins FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE POLICY burimunsi_native_receipt_origin_frame ON private.burimunsi_native_receipt_origins TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_receipt_frame',true)='1')
 WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_receipt_frame',true)='1');
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
 ON private.burimunsi_native_receipt_origins FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_native_receipt_origins ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE FUNCTION private.burimunsi_native_receipt_origin_immutable() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN RAISE EXCEPTION 'burimunsi_native_origin_immutable' USING ERRCODE='23514'; END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_receipt_origin_immutable() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_native_receipt_origin_immutable BEFORE UPDATE OR DELETE
 ON private.burimunsi_native_receipt_origins FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_receipt_origin_immutable();
ALTER TABLE private.burimunsi_native_receipt_origins ENABLE ALWAYS TRIGGER burimunsi_native_receipt_origin_immutable;

-- Each native message has one protected processing record.  This is separate
-- from the existing managed gateway queue: it does not invent a binding or
-- change the semantics of a managed processing job.
CREATE TABLE private.burimunsi_auto_sms_jobs (
 source_id text PRIMARY KEY REFERENCES private.burimunsi_native_receipt_origins(source_id),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 receiving_account_id text NOT NULL REFERENCES app.momo_receiving_accounts(id),
 source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[a-f0-9]{64}$'),
 profile_sha256 text NOT NULL CHECK(profile_sha256 ~ '^[a-f0-9]{64}$'),
 state text NOT NULL CHECK(state IN ('processing','retry','failed','completed','security_message')),
 phase text NOT NULL CHECK(phase IN ('preflight','dispatched','finished')),
 lease_token uuid,lease_until bigint,
 attempt_count bigint NOT NULL DEFAULT 1 CHECK(attempt_count BETWEEN 1 AND 9007199254740991),
 dispatch_count bigint NOT NULL DEFAULT 0 CHECK(dispatch_count BETWEEN 0 AND 9007199254740991 AND dispatch_count<=attempt_count),
 next_attempt_at bigint,last_error text CHECK(last_error IS NULL OR last_error IN ('provider_unavailable','invalid_output','lease_expired')),
 retry_lease uuid,
 attempt_id uuid,transaction_id text REFERENCES app.momo_transactions(id),
 facts_sha256 text CHECK(facts_sha256 IS NULL OR facts_sha256 ~ '^[a-f0-9]{64}$'),
 relation text CHECK(relation IS NULL OR relation IN ('accepted','duplicate','conflict')),
 payment_outcome text CHECK(payment_outcome IS NULL OR payment_outcome IN ('successful','failed','pending','unknown')),
 created_at bigint NOT NULL,updated_at bigint NOT NULL,
 CHECK((state='processing' AND phase IN ('preflight','dispatched') AND lease_token IS NOT NULL AND lease_until IS NOT NULL
        AND next_attempt_at IS NULL AND last_error IS NULL AND retry_lease IS NULL
        AND attempt_id IS NULL AND transaction_id IS NULL AND facts_sha256 IS NULL AND relation IS NULL AND payment_outcome IS NULL)
    OR (state='retry' AND phase='preflight' AND lease_token IS NULL AND lease_until IS NULL
        AND next_attempt_at IS NOT NULL AND last_error IS NOT NULL AND retry_lease IS NOT NULL
        AND attempt_id IS NULL AND transaction_id IS NULL AND facts_sha256 IS NULL AND relation IS NULL AND payment_outcome IS NULL)
    OR (state='failed' AND phase='finished' AND lease_token IS NULL AND lease_until IS NULL
        AND next_attempt_at IS NULL AND last_error IS NOT NULL AND retry_lease IS NOT NULL AND attempt_count>=5
        AND attempt_id IS NULL AND transaction_id IS NULL AND facts_sha256 IS NULL AND relation IS NULL AND payment_outcome IS NULL)
    OR (state='completed' AND phase='finished' AND lease_token IS NULL AND lease_until IS NULL
        AND next_attempt_at IS NULL AND last_error IS NULL AND retry_lease IS NULL
        AND attempt_id IS NOT NULL AND transaction_id IS NOT NULL AND facts_sha256 IS NOT NULL AND relation IS NOT NULL AND payment_outcome IS NOT NULL)
    OR (state='security_message' AND phase='finished' AND lease_token IS NULL AND lease_until IS NULL
        AND next_attempt_at IS NULL AND last_error IS NULL AND retry_lease IS NULL
        AND attempt_id IS NULL AND transaction_id IS NULL AND facts_sha256 IS NULL AND relation IS NULL AND payment_outcome IS NULL))
);
ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_auto_sms_jobs FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_auto_sms_jobs FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE POLICY burimunsi_auto_job_frame ON private.burimunsi_auto_sms_jobs TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_receipt_frame',true)='1')
 WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_receipt_frame',true)='1');
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
 ON private.burimunsi_auto_sms_jobs FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

-- A transaction can be routed by a genuine managed binding or an immutable
-- native source.  These alternatives do not assert that a sender label proves
-- the provider destination. The collection/account are the configured scope.
ALTER TABLE private.burimunsi_transaction_scopes ALTER COLUMN source_binding_id DROP NOT NULL;
ALTER TABLE private.burimunsi_transaction_scopes ALTER COLUMN source_binding_version DROP NOT NULL;
ALTER TABLE private.burimunsi_transaction_scopes ADD COLUMN native_source_id text
 REFERENCES private.burimunsi_native_receipt_origins(source_id);
ALTER TABLE private.burimunsi_transaction_scopes ADD CONSTRAINT burimunsi_transaction_origin_shape CHECK(
 (source_binding_id IS NOT NULL AND source_binding_version>0 AND native_source_id IS NULL) OR
 (source_binding_id IS NULL AND source_binding_version IS NULL AND native_source_id IS NOT NULL));
ALTER TABLE app.momo_transactions ALTER COLUMN provider_transaction_id DROP NOT NULL;
ALTER TABLE app.momo_transactions ALTER COLUMN amount_minor DROP NOT NULL;
ALTER TABLE app.momo_transactions ALTER COLUMN currency DROP NOT NULL;
ALTER TABLE app.momo_transactions ALTER COLUMN currency_scale DROP NOT NULL;
ALTER TABLE app.momo_transactions DROP CONSTRAINT momo_transactions_event_kind_check;
ALTER TABLE app.momo_transactions ADD CONSTRAINT momo_transactions_event_kind_check
 CHECK(event_kind IN ('incoming_receipt','outgoing','reversal','failed','pending','other','unknown'));
ALTER TABLE app.momo_transactions DROP CONSTRAINT momo_transactions_allocation_state_check;
ALTER TABLE app.momo_transactions ADD CONSTRAINT momo_transactions_allocation_state_check
 CHECK(allocation_state IN ('unallocated','linked','needs_review','not_applicable'));
ALTER TABLE app.momo_transactions ADD CONSTRAINT burimunsi_native_nullable_fact_shape CHECK(
 (provider_transaction_id IS NOT NULL AND amount_minor IS NOT NULL AND currency IS NOT NULL AND currency_scale IS NOT NULL)
 OR (allocation_state='not_applicable' AND (currency IS NULL AND currency_scale IS NULL OR currency IS NOT NULL AND currency_scale=0)));

-- Every NULL managed origin must have one exact native origin at COMMIT.  No
-- native origin can masquerade as a managed session or change source bytes.
CREATE FUNCTION private.burimunsi_auto_receipt_invariant() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE k text; r app.sms_receipts%ROWTYPE;o private.burimunsi_native_receipt_origins%ROWTYPE;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 IF TG_TABLE_NAME='sms_receipts' THEN
  k:=NEW.id;
 ELSE
  k:=NEW.source_id;
 END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO r FROM app.sms_receipts WHERE id=k;
 SELECT * INTO o FROM private.burimunsi_native_receipt_origins WHERE source_id=k;
 IF r.id IS NULL THEN RAISE EXCEPTION 'burimunsi_native_receipt_missing' USING ERRCODE='23514';END IF;
 IF r.originating_session_id IS NULL THEN
  IF o.source_id IS NULL OR r.receiver_hash IS NOT NULL OR
   ROW(r.owner_user_id,r.client_envelope_id,r.body_sha256,r.object_sha256,r.object_key,r.evidence_level)
    IS DISTINCT FROM ROW(o.principal_user_id,o.request_id::text,o.body_sha256,o.object_sha256,'sms/'||k,'client_received') OR
   NOT EXISTS(SELECT 1 FROM private.burimunsi_auto_sms_jobs j WHERE j.source_id=k AND j.collection_id=o.collection_id
    AND j.source_fingerprint=o.fingerprint)
  THEN RAISE EXCEPTION 'burimunsi_native_receipt_mismatch' USING ERRCODE='23514';END IF;
 ELSIF o.source_id IS NOT NULL OR r.receiver_hash IS NULL THEN
  RAISE EXCEPTION 'burimunsi_native_receipt_mismatch' USING ERRCODE='23514';
 END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RETURN NULL;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_receipt_invariant() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE CONSTRAINT TRIGGER burimunsi_auto_receipt_invariant AFTER INSERT OR UPDATE ON app.sms_receipts
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION private.burimunsi_auto_receipt_invariant();
CREATE CONSTRAINT TRIGGER burimunsi_auto_origin_invariant AFTER INSERT ON private.burimunsi_native_receipt_origins
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION private.burimunsi_auto_receipt_invariant();

-- No synthetic phone session is created for service work. A worker must hold
-- a real jobs admission for the current deployment and a scoped collection.
-- It rechecks the original capture's active account, device grant, consent,
-- authority, detection tuple and retained object on every operation.
CREATE FUNCTION private.burimunsi_auto_snapshot(p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE f private.collect_fence_admissions%ROWTYPE; o private.burimunsi_unresolved_observations%ROWTYPE;
 a jsonb;proof jsonb;profile jsonb;v record;scope text;
 old_obs text:=current_setting('burimunsi.observation_frame',true);
 old_pin text:=current_setting('burimunsi.pin_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();
 f:=private._collect_fence_admission(current_setting('collect.fence_admission_id',true)::uuid,
  current_setting('collect.fence_epoch',true)::bigint,current_setting('collect.fence_source_sha256',true));
 IF f.kind='http_collect' THEN
  a:=private.burimunsi_observation_actor(true);proof:=private.burimunsi_observation_own(p_source,true);
  profile:=private.burimunsi_observation_hint_profile(p_source);
  IF proof IS NULL OR profile IS NULL THEN RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
  RETURN jsonb_build_object('kind','native_actor','actor',a,'proof',proof,'profile',profile);
 END IF;
 IF f.kind<>'jobs' THEN RAISE EXCEPTION 'burimunsi_auto_jobs_required' USING ERRCODE='42501';END IF;
 scope:=nullif(current_setting('burimunsi.collection_id',true),'');
 IF scope IS NULL THEN RAISE EXCEPTION 'burimunsi_auto_scope_required' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT * INTO o FROM private.burimunsi_unresolved_observations WHERE source_id=p_source AND collection_id=scope FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 SELECT b.phone,b.role,b.capabilities,s.receiving_account_id,w.provider,w.status,w.profile_status,w.profile_version,
  w.profile_json,w.currency,w.timezone,c.generation AS current_consent,d.id AS device_id
 INTO v FROM private.burimunsi_accounts b
 JOIN private.burimunsi_device_grants d ON d.id=o.grant_id AND d.collection_id=o.collection_id
  AND d.installation_id=o.installation_id AND d.version=o.grant_version AND d.active AND d.profile='internal_receiver'
 JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.collection_id=b.collection_id AND da.account_id=b.id
 JOIN private.burimunsi_observation_consents c ON c.collection_id=b.collection_id AND c.account_id=b.id
  AND c.installation_id=d.installation_id AND c.grant_id=d.id AND c.grant_version=d.version AND c.enabled
 JOIN private.burimunsi_scopes s ON s.collection_id=b.collection_id AND (s.enabled OR s.active_binding_id IS NULL)
 JOIN app.momo_receiving_accounts w ON w.id=s.receiving_account_id AND w.status='active'
 JOIN app.collections collection ON collection.id=s.collection_id AND collection.status='active'
 WHERE b.id=o.account_id AND b.collection_id=o.collection_id AND b.principal_user_id=o.principal_user_id
  AND b.active AND NOT b.removed AND b.role='admin' AND 'sms.read'=ANY(b.capabilities)
  AND 'gateway.manage'=ANY(b.capabilities)
  AND private.burimunsi_pin_root_snapshot(b.collection_id,b.principal_user_id,b.phone,b.role,b.capabilities) IS NOT NULL
  AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['sms.read','sms.reveal']::text[]) required(permission)
   WHERE NOT EXISTS(SELECT 1 FROM app.admin_grants g JOIN app.admin_principal_links l ON l.user_id=g.user_id
    JOIN app.admin_users u ON u.id=l.admin_user_id JOIN app.admin_account_role_capabilities rc ON rc.role=u.role AND rc.permission=g.permission
    WHERE g.user_id=o.principal_user_id AND g.permission=required.permission AND u.status='active'))
 FOR SHARE OF b,d,da,c,s,w,collection;
 IF NOT FOUND OR NOT private.burimunsi_observation_storage_matches(o.object_key,
  jsonb_build_object('ownerId',o.principal_user_id,'purpose','sms_receipt','entityId',o.source_id),o.object_sha256) THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 -- Use the exact profile tuple captured with the observation. A later edit
 -- cannot silently reinterpret an already retained message.
 SELECT jsonb_build_object('profileSha256',o.profile_sha256,'profile',jsonb_build_object(
  'provider',v.provider,'status',v.status,'profile_status','approved','profile_version',d.profile_version,
  'profile_json',d.profile_json,'currency',v.currency,'timezone',v.timezone)) INTO profile
 FROM private.burimunsi_detection_profiles d WHERE d.collection_id=o.collection_id AND d.enabled
  AND d.expected_receiving_account_id=v.receiving_account_id AND d.profile_version=o.profile_version
  AND encode(sha256(convert_to(d.profile_json,'UTF8')),'hex')=o.profile_sha256
  AND encode(sha256(convert_to(jsonb_build_array('detection_only',v.receiving_account_id,v.provider,v.status,v.profile_status,
   v.profile_version,v.profile_json,v.currency,v.timezone,d.revision,d.enabled,d.profile_version,d.profile_json,d.evidence_sha256)::text,'UTF8')),'hex')=o.profile_tuple_sha256
 FOR SHARE OF d;
 IF profile IS NULL AND v.profile_status='approved' AND v.profile_version=o.profile_version AND
  NOT EXISTS(SELECT 1 FROM private.burimunsi_detection_profiles d WHERE d.collection_id=o.collection_id) AND
  encode(sha256(convert_to(v.profile_json,'UTF8')),'hex')=o.profile_sha256 AND
  encode(sha256(convert_to(jsonb_build_array(v.receiving_account_id,v.provider,v.status,v.profile_status,v.profile_version,
   v.profile_json,v.currency,v.timezone)::text,'UTF8')),'hex')=o.profile_tuple_sha256 THEN
  profile:=jsonb_build_object('profileSha256',o.profile_sha256,'profile',jsonb_build_object(
   'provider',v.provider,'status',v.status,'profile_status',v.profile_status,'profile_version',v.profile_version,
   'profile_json',v.profile_json,'currency',v.currency,'timezone',v.timezone));
 END IF;
 IF profile IS NULL THEN RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 a:=jsonb_build_object('collectionId',o.collection_id,'accountId',o.account_id,'principalUserId',o.principal_user_id,
  'sessionId',NULL,'installationId',o.installation_id,'grantId',o.grant_id,'grantVersion',o.grant_version);
 proof:=jsonb_build_object('sourceId',o.source_id,'requestId',o.request_id,'bodySha256',o.body_sha256,
  'object_key',o.object_key,'object_sha256',o.object_sha256,'size_bytes',o.size_bytes,'id',o.source_id,
  'createdAt',o.created_at,'principalUserId',o.principal_user_id,'sessionId',NULL,
  'consentGeneration',v.current_consent,'fingerprint',o.fingerprint);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 RETURN jsonb_build_object('kind','jobs','actor',a,'proof',proof,'profile',profile);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_snapshot(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

-- Only a currently admitted server job may enumerate or plan background
-- processing. No PIN context or client-supplied principal is installed.
CREATE FUNCTION private.burimunsi_auto_jobs_guard() RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE f private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 f:=private._collect_fence_admission(current_setting('collect.fence_admission_id',true)::uuid,
  current_setting('collect.fence_epoch',true)::bigint,current_setting('collect.fence_source_sha256',true));
 IF f.kind IS DISTINCT FROM 'jobs' THEN RAISE EXCEPTION 'burimunsi_auto_jobs_required' USING ERRCODE='42501';END IF;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_jobs_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

-- Shared bounded selectors only return currently eligible capture metadata.
-- Revalidation and locking in auto_snapshot/begin are still authoritative.
-- A lost provider response may be retried after its lease expires; the
-- extraction request has no financial effect and source commit is idempotent.
CREATE FUNCTION private.burimunsi_auto_candidates(p_collection text DEFAULT NULL)
 RETURNS TABLE(collection_id text,source_id text,fingerprint text,profile_sha256 text,created_at bigint)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_obs text:=current_setting('burimunsi.observation_frame',true);
 old_pin text:=current_setting('burimunsi.pin_frame',true);
 old_native text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 PERFORM set_config('burimunsi.observation_frame','1',true);
 PERFORM set_config('burimunsi.pin_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 RETURN QUERY SELECT o.collection_id,o.source_id,o.fingerprint,o.profile_sha256,o.created_at
 FROM private.burimunsi_unresolved_observations o
 JOIN private.burimunsi_accounts b ON b.id=o.account_id AND b.collection_id=o.collection_id
  AND b.principal_user_id=o.principal_user_id AND b.active AND NOT b.removed AND b.role='admin'
  AND 'sms.read'=ANY(b.capabilities) AND 'gateway.manage'=ANY(b.capabilities)
 JOIN private.burimunsi_device_grants device ON device.id=o.grant_id AND device.collection_id=o.collection_id
  AND device.installation_id=o.installation_id AND device.version=o.grant_version
  AND device.active AND device.profile='internal_receiver'
 JOIN private.burimunsi_device_accounts da ON da.grant_id=device.id AND da.collection_id=b.collection_id AND da.account_id=b.id
 JOIN private.burimunsi_observation_consents c ON c.collection_id=o.collection_id AND c.account_id=o.account_id
  AND c.installation_id=o.installation_id AND c.grant_id=o.grant_id AND c.grant_version=o.grant_version AND c.enabled
 JOIN private.burimunsi_scopes s ON s.collection_id=o.collection_id AND (s.enabled OR s.active_binding_id IS NULL)
 JOIN app.collections collection ON collection.id=s.collection_id AND collection.status='active'
 JOIN app.momo_receiving_accounts w ON w.id=s.receiving_account_id AND w.status='active'
 LEFT JOIN private.burimunsi_detection_profiles detection ON detection.collection_id=o.collection_id
 LEFT JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=o.source_id
 WHERE (p_collection IS NULL OR o.collection_id=p_collection)
  AND (j.source_id IS NULL OR (j.state='processing' AND j.lease_until<=floor(extract(epoch FROM clock_timestamp())*1000)::bigint)
   OR (j.state='retry' AND j.next_attempt_at<=floor(extract(epoch FROM clock_timestamp())*1000)::bigint))
  AND private.burimunsi_pin_root_snapshot(b.collection_id,b.principal_user_id,b.phone,b.role,b.capabilities) IS NOT NULL
  AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['sms.read','sms.reveal']::text[]) required(permission)
   WHERE NOT EXISTS(SELECT 1 FROM app.admin_grants g JOIN app.admin_principal_links l ON l.user_id=g.user_id
    JOIN app.admin_users u ON u.id=l.admin_user_id JOIN app.admin_account_role_capabilities rc ON rc.role=u.role AND rc.permission=g.permission
    WHERE g.user_id=o.principal_user_id AND g.permission=required.permission AND u.status='active'))
  AND private.burimunsi_observation_storage_matches(o.object_key,
   jsonb_build_object('ownerId',o.principal_user_id,'purpose','sms_receipt','entityId',o.source_id),o.object_sha256)
  AND ((detection.collection_id IS NOT NULL AND detection.enabled AND detection.expected_receiving_account_id=w.id
    AND detection.profile_version=o.profile_version AND encode(sha256(convert_to(detection.profile_json,'UTF8')),'hex')=o.profile_sha256
    AND encode(sha256(convert_to(jsonb_build_array('detection_only',w.id,w.provider,w.status,w.profile_status,w.profile_version,
     w.profile_json,w.currency,w.timezone,detection.revision,detection.enabled,detection.profile_version,detection.profile_json,
     detection.evidence_sha256)::text,'UTF8')),'hex')=o.profile_tuple_sha256)
   OR (detection.collection_id IS NULL AND w.profile_status='approved' AND w.profile_version=o.profile_version
    AND encode(sha256(convert_to(w.profile_json,'UTF8')),'hex')=o.profile_sha256
    AND encode(sha256(convert_to(jsonb_build_array(w.id,w.provider,w.status,w.profile_status,w.profile_version,w.profile_json,
     w.currency,w.timezone)::text,'UTF8')),'hex')=o.profile_tuple_sha256));
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
 RETURN;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_candidates(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

CREATE FUNCTION private.burimunsi_auto_collections(p_limit integer) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE answer jsonb;
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 SELECT coalesce(jsonb_agg(collection_id ORDER BY oldest,collection_id),'[]'::jsonb) INTO answer FROM (
  SELECT c.collection_id,min(c.created_at) oldest FROM private.burimunsi_auto_candidates(NULL) c
  GROUP BY c.collection_id ORDER BY oldest,c.collection_id LIMIT p_limit
 ) q;
 RETURN answer;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_collections(integer) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_collections(integer) TO collect_runtime;

CREATE FUNCTION private.burimunsi_auto_sources(p_limit integer) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE scope text:=nullif(current_setting('burimunsi.collection_id',true),'');answer jsonb;
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 IF scope IS NULL THEN RAISE EXCEPTION 'burimunsi_auto_scope_required' USING ERRCODE='42501';END IF;
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('collectionId',collection_id,'sourceId',source_id,
  'fingerprint',fingerprint,'profileSha256',profile_sha256) ORDER BY created_at,source_id),'[]'::jsonb)
 INTO answer FROM (SELECT * FROM private.burimunsi_auto_candidates(scope) ORDER BY created_at,source_id LIMIT p_limit) q;
 RETURN answer;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_sources(integer) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_sources(integer) TO collect_runtime;

CREATE FUNCTION private.burimunsi_auto_plan(p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE snap jsonb;
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();snap:=private.burimunsi_auto_snapshot(p_source);
 IF snap->>'kind' IS DISTINCT FROM 'jobs' THEN RAISE EXCEPTION 'burimunsi_auto_jobs_required' USING ERRCODE='42501';END IF;
 RETURN snap;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_plan(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_plan(text) TO collect_runtime;

-- Begin with the actual current PIN actor and its retained observation. The
-- selected collection/account come from the server, not the parser payload.
CREATE FUNCTION private.burimunsi_auto_begin(p_source text,p_lease uuid,p_fingerprint text,p_profile_sha text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;proof jsonb;profile jsonb;snap jsonb;o private.burimunsi_unresolved_observations%ROWTYPE;
 j private.burimunsi_auto_sms_jobs%ROWTYPE;wallet text;at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
 old_obs text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();
 IF p_lease IS NULL OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$'
  OR p_profile_sha IS NULL OR p_profile_sha !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 snap:=private.burimunsi_auto_snapshot(p_source);a:=snap->'actor';proof:=snap->'proof';profile:=snap->'profile';
 IF proof IS NULL OR proof->>'fingerprint' IS DISTINCT FROM p_fingerprint OR profile IS NULL
  OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO STRICT o FROM private.burimunsi_unresolved_observations WHERE source_id=p_source;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 SELECT s.receiving_account_id INTO wallet FROM private.burimunsi_scopes s
 JOIN app.momo_receiving_accounts w ON w.id=s.receiving_account_id AND w.status='active'
 WHERE s.collection_id=a->>'collectionId' FOR SHARE OF s,w;
 IF wallet IS NULL OR ROW(o.collection_id,o.account_id,o.principal_user_id,o.installation_id,o.grant_id,o.grant_version,
   o.fingerprint,o.profile_sha256,o.body_sha256,o.object_sha256)
  IS DISTINCT FROM ROW(a->>'collectionId',(a->>'accountId')::uuid,a->>'principalUserId',(a->>'installationId')::uuid,
   (a->>'grantId')::uuid,(a->>'grantVersion')::bigint,p_fingerprint,p_profile_sha,proof->>'bodySha256',proof->>'object_sha256') THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO j FROM private.burimunsi_auto_sms_jobs WHERE source_id=p_source FOR UPDATE;
 IF FOUND THEN
  IF ROW(j.collection_id,j.receiving_account_id,j.source_fingerprint,j.profile_sha256)
   IS DISTINCT FROM ROW(o.collection_id,wallet,p_fingerprint,p_profile_sha) THEN
   RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
  IF j.state='security_message' THEN
   PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
   RETURN jsonb_build_object('sourceId',p_source,'state','security_message','started',false,'transactionId',NULL);
  END IF;
  IF j.state='completed' THEN
   PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
   RETURN jsonb_build_object('sourceId',p_source,'state','completed','started',false,
    'transactionId',j.transaction_id,'relation',j.relation);
  END IF;
  IF j.state='failed' THEN
   PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
   RETURN jsonb_build_object('sourceId',p_source,'state','failed','started',false,
    'attemptCount',j.attempt_count,'nextAttemptAt',NULL);
  END IF;
  IF j.state='processing' AND j.lease_until>at_ms OR j.state='retry' AND j.next_attempt_at>at_ms THEN
   PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
   RETURN jsonb_build_object('sourceId',p_source,'state',j.state,'started',false,
    'attemptCount',j.attempt_count,'nextAttemptAt',j.next_attempt_at);
  END IF;
  UPDATE private.burimunsi_auto_sms_jobs SET state='processing',phase='preflight',attempt_count=attempt_count+1,
   lease_token=p_lease,lease_until=at_ms+120000,next_attempt_at=NULL,last_error=NULL,retry_lease=NULL,updated_at=at_ms
   WHERE source_id=p_source;
 ELSE
  INSERT INTO private.burimunsi_native_receipt_origins(source_id,collection_id,account_id,principal_user_id,installation_id,
   grant_id,grant_version,capture_session_id,admitting_session_id,admission_kind,request_id,fingerprint,body_sha256,object_sha256)
  VALUES(o.source_id,o.collection_id,o.account_id,o.principal_user_id,o.installation_id,o.grant_id,o.grant_version,
   o.native_session_id,(a->>'sessionId')::uuid,snap->>'kind',o.request_id,o.fingerprint,o.body_sha256,o.object_sha256);
  INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,
   object_key,object_sha256,size_bytes,received_at_device,status,evidence_level,created_at)
  VALUES(o.source_id,o.principal_user_id,NULL,o.request_id::text,o.body_sha256,NULL,o.object_key,o.object_sha256,
   o.size_bytes,NULL,'received','client_received',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
  INSERT INTO private.burimunsi_auto_sms_jobs(source_id,collection_id,receiving_account_id,source_fingerprint,profile_sha256,
   state,phase,lease_token,lease_until,created_at,updated_at)
  VALUES(p_source,o.collection_id,wallet,p_fingerprint,p_profile_sha,'processing','preflight',p_lease,at_ms+120000,at_ms,at_ms);
 END IF;
 IF private.burimunsi_auto_snapshot(p_source) IS DISTINCT FROM snap THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('sourceId',p_source,'state','processing','started',true);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_begin(text,uuid,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_begin(text,uuid,text,text) TO collect_runtime;

CREATE FUNCTION private.burimunsi_auto_dispatch(p_source text,p_lease uuid,p_fingerprint text,p_profile_sha text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE proof jsonb;profile jsonb;snap jsonb;at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();snap:=private.burimunsi_auto_snapshot(p_source);proof:=snap->'proof';profile:=snap->'profile';
 IF proof IS NULL OR proof->>'fingerprint' IS DISTINCT FROM p_fingerprint OR profile IS NULL
  OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 UPDATE private.burimunsi_auto_sms_jobs SET phase='dispatched',dispatch_count=dispatch_count+1,updated_at=at_ms WHERE source_id=p_source
  AND state='processing' AND phase='preflight' AND lease_token=p_lease AND lease_until>at_ms
  AND source_fingerprint=p_fingerprint AND profile_sha256=p_profile_sha;
 IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RETURN true;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_dispatch(text,uuid,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_dispatch(text,uuid,text,text) TO collect_runtime;

-- Persist only a closed error code. An exact lost acknowledgement is safely
-- readable with the same original lease; another claim cannot reuse it.
CREATE FUNCTION private.burimunsi_auto_retry(p_source text,p_lease uuid,p_fingerprint text,p_profile_sha text,p_reason text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE snap jsonb;proof jsonb;profile jsonb;j private.burimunsi_auto_sms_jobs%ROWTYPE;
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;at_next bigint;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();snap:=private.burimunsi_auto_snapshot(p_source);proof:=snap->'proof';profile:=snap->'profile';
 IF p_lease IS NULL OR p_reason IS NULL OR p_reason NOT IN ('provider_unavailable','invalid_output') OR proof IS NULL
  OR proof->>'fingerprint' IS DISTINCT FROM p_fingerprint OR profile IS NULL
  OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha THEN
  RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO j FROM private.burimunsi_auto_sms_jobs WHERE source_id=p_source FOR UPDATE;
 IF NOT FOUND OR ROW(j.source_fingerprint,j.profile_sha256) IS DISTINCT FROM ROW(p_fingerprint,p_profile_sha) THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 IF j.state IN ('retry','failed') AND j.retry_lease=p_lease AND j.last_error=p_reason THEN
  PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
  RETURN jsonb_build_object('sourceId',p_source,'state',j.state,'attemptCount',j.attempt_count,'nextAttemptAt',j.next_attempt_at);
 END IF;
 IF j.state<>'processing' OR j.lease_token IS DISTINCT FROM p_lease OR j.lease_until<=at_ms THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 -- A temporary provider or parsing failure must not strand a message forever.
 -- Retry automatically with a capped hourly backoff to avoid a tight loop.
 at_next:=at_ms+least(3600000::bigint,10000::bigint*(1::bigint << least(j.attempt_count-1,9)::integer));
 UPDATE private.burimunsi_auto_sms_jobs SET state='retry',
  phase='preflight',lease_token=NULL,lease_until=NULL,
  retry_lease=p_lease,last_error=p_reason,next_attempt_at=at_next,updated_at=at_ms WHERE source_id=p_source;
 IF private.burimunsi_auto_snapshot(p_source) IS DISTINCT FROM snap THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('sourceId',p_source,'state','retry',
  'attemptCount',j.attempt_count,'nextAttemptAt',at_next);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_retry(text,uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_retry(text,uuid,text,text,text) TO collect_runtime;

-- The server has independently validated every non-null fact against the
-- decrypted SMS. SQL accepts exactly the closed facts shape, rechecks source,
-- actor and profile, and commits one stable outcome under the mutation lock.
-- model='local' can finish a locally classified provider notice without a
-- remote dispatch; an external model requires the committed dispatch marker.
CREATE FUNCTION private.burimunsi_auto_finish(p_source text,p_lease uuid,p_fingerprint text,p_profile_sha text,
 p_attempt uuid,p_model text,p_output jsonb,p_facts jsonb) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;proof jsonb;profile jsonb;snap jsonb;j private.burimunsi_auto_sms_jobs%ROWTYPE;
 t app.momo_transactions%ROWTYPE;sc private.burimunsi_transaction_scopes%ROWTYPE;
 expected_keys text[]:=ARRAY['amount_minor','counterparty_identifier','counterparty_name','currency','event_kind',
  'fee_minor','original_transaction_id','payment_outcome','provider_transaction_id','source_mode','transaction_at',
  'transaction_datetime_raw','wallet_balance_after_minor'];
 keys text[];k text;typ text;kind text;outcome text;ref text;wallet_provider text;wallet_timezone text;
 amount bigint;fee bigint;balance bigint;fhash text;new_id text;v_relation text:='accepted';
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 stamp text:=app.strftime('%Y-%m-%dT%H:%M:%fZ');
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
 old_group text:=current_setting('burimunsi.collection_id',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 snap:=private.burimunsi_auto_snapshot(p_source);a:=snap->'actor';proof:=snap->'proof';profile:=snap->'profile';
 IF proof IS NULL OR proof->>'fingerprint' IS DISTINCT FROM p_fingerprint OR profile IS NULL
  OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha OR p_attempt IS NULL OR p_lease IS NULL
  OR p_model IS NULL OR p_model !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
  OR jsonb_typeof(p_facts) IS DISTINCT FROM 'object'
  OR p_output IS NOT NULL AND (jsonb_typeof(p_output)<>'object' OR octet_length(p_output::text)>65536) THEN
  RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 SELECT array_agg(x ORDER BY x) INTO keys FROM jsonb_object_keys(p_facts) AS x;
 IF keys IS DISTINCT FROM expected_keys THEN RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 FOREACH k IN ARRAY ARRAY['event_kind','payment_outcome','source_mode'] LOOP
  IF jsonb_typeof(p_facts->k) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['provider_transaction_id','original_transaction_id','currency','counterparty_name',
  'counterparty_identifier','transaction_at','transaction_datetime_raw'] LOOP
  typ:=jsonb_typeof(p_facts->k);
  IF typ NOT IN ('string','null') OR (typ='string' AND (length(p_facts->>k) NOT BETWEEN 1 AND 512
    OR p_facts->>k ~ '[[:cntrl:]]')) THEN RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['amount_minor','fee_minor','wallet_balance_after_minor'] LOOP
  typ:=jsonb_typeof(p_facts->k);
  IF typ NOT IN ('number','null') OR (typ='number' AND
    (p_facts->>k !~ '^(0|[1-9][0-9]{0,15})$' OR (p_facts->>k)::numeric>9007199254740991)) THEN
   RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 kind:=p_facts->>'event_kind';outcome:=p_facts->>'payment_outcome';ref:=p_facts->>'provider_transaction_id';
 amount:=(p_facts->>'amount_minor')::bigint;fee:=(p_facts->>'fee_minor')::bigint;
 balance:=(p_facts->>'wallet_balance_after_minor')::bigint;
 IF p_facts->>'source_mode' NOT IN ('live','catch_up') OR kind NOT IN ('incoming_receipt','outgoing','reversal','failed','pending','other','unknown')
  OR outcome NOT IN ('successful','failed','pending','unknown') OR amount=0
  OR ref IS NOT NULL AND (length(ref)>160 OR ref ~ '[[:space:]]')
  OR p_facts->>'original_transaction_id' IS NOT NULL AND length(p_facts->>'original_transaction_id')>160
  OR p_facts->>'currency' IS NOT NULL AND p_facts->>'currency'<>'RWF'
  OR p_facts->>'transaction_at' IS NOT NULL AND
   (p_facts->>'transaction_at' !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' OR NOT pg_input_is_valid(p_facts->>'transaction_at','timestamp with time zone'))
  OR kind IN ('incoming_receipt','outgoing','reversal') AND outcome<>'successful'
  OR kind='failed' AND outcome<>'failed' OR kind='pending' AND outcome<>'pending' THEN
  RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 fhash:=encode(sha256(convert_to(jsonb_build_object('model',p_model,'output',p_output,'facts',p_facts)::text,'UTF8')),'hex');
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO j FROM private.burimunsi_auto_sms_jobs WHERE source_id=p_source FOR UPDATE;
 IF NOT FOUND OR ROW(j.collection_id,j.source_fingerprint,j.profile_sha256)
  IS DISTINCT FROM ROW(a->>'collectionId',p_fingerprint,p_profile_sha) THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 IF j.state='completed' THEN
  IF j.attempt_id IS DISTINCT FROM p_attempt OR j.facts_sha256 IS DISTINCT FROM fhash THEN
   RAISE EXCEPTION 'burimunsi_auto_conflict' USING ERRCODE='23505';END IF;
  PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
  RETURN jsonb_build_object('sourceId',p_source,'transactionId',j.transaction_id,'state','completed','relation',j.relation);
 END IF;
 IF j.lease_token IS DISTINCT FROM p_lease OR j.lease_until<=at_ms
  OR (p_model='local' AND j.phase<>'preflight') OR (p_model<>'local' AND j.phase<>'dispatched') THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 SELECT w.provider,w.timezone INTO wallet_provider,wallet_timezone FROM app.momo_receiving_accounts w
 JOIN private.burimunsi_scopes s ON s.receiving_account_id=w.id
 WHERE s.collection_id=j.collection_id AND w.id=j.receiving_account_id AND w.status='active' FOR SHARE OF s,w;
 IF NOT FOUND OR wallet_provider IS DISTINCT FROM profile->'profile'->>'provider'
  OR wallet_timezone IS DISTINCT FROM profile->'profile'->>'timezone' THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 new_id:=p_source;
 IF ref IS NOT NULL THEN
  SELECT * INTO t FROM app.momo_transactions WHERE provider=wallet_provider AND receiving_account_id=j.receiving_account_id
   AND event_kind=kind AND provider_transaction_id=ref FOR UPDATE;
  IF FOUND THEN
   PERFORM set_config('burimunsi.collection_id',j.collection_id,true);
   SELECT * INTO sc FROM private.burimunsi_transaction_scopes WHERE transaction_id=t.id;
   IF NOT FOUND OR ROW(sc.collection_id,sc.receiving_account_id) IS DISTINCT FROM ROW(j.collection_id,j.receiving_account_id) THEN
    RAISE EXCEPTION 'burimunsi_auto_scope_conflict' USING ERRCODE='23514';END IF;
   v_relation:=CASE WHEN ROW(t.amount_minor,t.currency,t.payer_name,t.payer_identifier,t.transaction_at,t.fee_minor,t.wallet_balance_after_minor)
     IS NOT DISTINCT FROM ROW(amount,p_facts->>'currency',p_facts->>'counterparty_name',p_facts->>'counterparty_identifier',
      p_facts->>'transaction_at',fee,balance) THEN 'duplicate' ELSE 'conflict' END;
   new_id:=t.id;
  END IF;
 END IF;
 INSERT INTO app.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,
  profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at)
 VALUES(p_attempt::text,p_source,1,p_model,'burimunsi-auto.v1','burimunsi-auto.v1','burimunsi-auto.v1',
  profile->'profile'->>'profile_version',profile->'profile'->>'profile_json',proof->>'bodySha256',
  p_output::text,'[]',v_relation,stamp);
 IF v_relation='accepted' THEN
  INSERT INTO app.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,original_transaction_id,
   amount_minor,currency,currency_scale,payer_name,payer_identifier,payer_last3,transaction_at,transaction_datetime_raw,
   transaction_timezone,transaction_time_source,fee_minor,wallet_balance_after_minor,parse_attempt_id,mode,allocation_state,created_at,updated_at)
  VALUES(new_id,j.receiving_account_id,wallet_provider,ref,kind,p_facts->>'original_transaction_id',amount,p_facts->>'currency',
   CASE WHEN p_facts->>'currency' IS NULL THEN NULL ELSE 0 END,p_facts->>'counterparty_name',p_facts->>'counterparty_identifier',NULL,
   p_facts->>'transaction_at',p_facts->>'transaction_datetime_raw',wallet_timezone,
   CASE WHEN p_facts->>'transaction_at' IS NULL THEN 'missing_provider_time' ELSE 'sms_body_and_provider_profile' END,
   fee,balance,p_attempt::text,CASE WHEN p_facts->>'source_mode'='live' THEN 'live' ELSE 'historical' END,
   CASE WHEN kind='incoming_receipt' AND outcome='successful' AND amount IS NOT NULL AND ref IS NOT NULL
    AND p_facts->>'currency' IS NOT NULL THEN 'unallocated' ELSE 'not_applicable' END,stamp,stamp);
  PERFORM set_config('burimunsi.collection_id',j.collection_id,true);
  INSERT INTO private.burimunsi_transaction_scopes(transaction_id,collection_id,receiving_account_id,source_binding_id,
   source_binding_version,policy_version,created_at,native_source_id)
  VALUES(new_id,j.collection_id,j.receiving_account_id,NULL,NULL,'native.auto.v1',at_ms,p_source);
 END IF;
 INSERT INTO app.momo_transaction_sources(transaction_id,raw_sms_id,parse_attempt_id,relation,created_at)
 VALUES(new_id,p_source,p_attempt::text,v_relation,stamp);
 UPDATE private.burimunsi_auto_sms_jobs SET state='completed',phase='finished',lease_token=NULL,lease_until=NULL,
  attempt_id=p_attempt,transaction_id=new_id,facts_sha256=fhash,relation=v_relation,payment_outcome=outcome,updated_at=at_ms
  WHERE source_id=p_source;
 IF private.burimunsi_auto_snapshot(p_source) IS DISTINCT FROM snap THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('sourceId',p_source,'transactionId',new_id,'state','completed','relation',v_relation);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb) TO collect_runtime;

-- Local security-message classification finishes without provider dispatch or
-- creating a financial event. The original encrypted source is retained.
CREATE FUNCTION private.burimunsi_auto_skip_security(p_source text,p_lease uuid,p_fingerprint text,p_profile_sha text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE proof jsonb;profile jsonb;snap jsonb;j private.burimunsi_auto_sms_jobs%ROWTYPE;
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();snap:=private.burimunsi_auto_snapshot(p_source);proof:=snap->'proof';profile:=snap->'profile';
 IF proof IS NULL OR proof->>'fingerprint' IS DISTINCT FROM p_fingerprint OR profile IS NULL
  OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO j FROM private.burimunsi_auto_sms_jobs WHERE source_id=p_source FOR UPDATE;
 IF NOT FOUND OR j.source_fingerprint IS DISTINCT FROM p_fingerprint OR j.profile_sha256 IS DISTINCT FROM p_profile_sha THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 IF j.state<>'security_message' THEN
  IF j.state<>'processing' OR j.phase<>'preflight' OR j.lease_token IS DISTINCT FROM p_lease OR j.lease_until<=at_ms THEN
   RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
  UPDATE private.burimunsi_auto_sms_jobs SET state='security_message',phase='finished',lease_token=NULL,lease_until=NULL,
   updated_at=at_ms WHERE source_id=p_source;
 END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('sourceId',p_source,'state','security_message','transactionId',NULL);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_skip_security(text,uuid,text,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_skip_security(text,uuid,text,text) TO collect_runtime;

-- Record projection for the current phone-PIN collection, including staff
-- with records.read. It exposes no message body, token or storage credential.
CREATE FUNCTION private.burimunsi_auto_projection(p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a record;j private.burimunsi_auto_sms_jobs%ROWTYPE;can_reveal boolean:=false;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private._collect_fence_require_runtime();
 SELECT * INTO a FROM private.burimunsi_pin_context();
 IF NOT FOUND OR NOT('records.read'=ANY(a.capabilities)) THEN
  RAISE EXCEPTION 'burimunsi_auto_denied' USING ERRCODE='42501';END IF;
 -- records.read permits both approved staff and admins; passing the actor's
 -- role as a required group role would make the assertion admin-only.
 PERFORM private.burimunsi_pin_assert_actor(NULL,a.collection_id,NULL,1,NULL);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO j FROM private.burimunsi_auto_sms_jobs WHERE source_id=p_source AND collection_id=a.collection_id
  AND state='completed';
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 IF NOT FOUND THEN RETURN NULL;END IF;
 IF a.role='admin' AND a.profile='internal_receiver' AND 'sms.read'=ANY(a.capabilities)
  AND 'gateway.manage'=ANY(a.capabilities) THEN
  BEGIN can_reveal:=private.burimunsi_observation_own(p_source,true) IS NOT NULL;
  EXCEPTION WHEN insufficient_privilege THEN can_reveal:=false;END;
 END IF;
 RETURN jsonb_build_object('sourceId',j.source_id,'outcome',j.payment_outcome,'canReveal',can_reveal);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_auto_projection(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_auto_projection(text) TO collect_runtime;

-- An exact native transaction lookup is available only to this definer. The
-- result distinguishes a managed row from a native row hidden from this Admin.
CREATE POLICY burimunsi_auto_admin_scope_lookup ON private.burimunsi_transaction_scopes FOR SELECT TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND transaction_id=current_setting('burimunsi.auto_admin_transaction',true));
CREATE FUNCTION private.burimunsi_admin_transaction_visibility(p_transaction text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a record;s private.burimunsi_transaction_scopes%ROWTYPE;allowed boolean:=false;
 old_tx text:=current_setting('burimunsi.auto_admin_transaction',true);
 old_pin text:=current_setting('burimunsi.pin_frame',true);
BEGIN
 PERFORM private._collect_fence_require_runtime();
 SELECT * INTO a FROM private.burimunsi_managed_admin_snapshot();
 IF NOT FOUND OR a.surface<>'admin' OR a.shared_role NOT IN ('owner','admin','staff') OR
  private.assert_actor('payments.read',NULL,NULL,1,NULL) IS DISTINCT FROM a.principal_user_id THEN
  RAISE EXCEPTION 'burimunsi_auto_admin_denied' USING ERRCODE='42501';END IF;
 IF p_transaction IS NULL OR length(p_transaction) NOT BETWEEN 1 AND 128 THEN
  RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.auto_admin_transaction',p_transaction,true);
 SELECT * INTO s FROM private.burimunsi_transaction_scopes WHERE transaction_id=p_transaction;
 IF NOT FOUND OR s.native_source_id IS NULL THEN
  PERFORM set_config('burimunsi.auto_admin_transaction',coalesce(old_tx,''),true);
  RETURN jsonb_build_object('kind','managed','groupId',NULL);
 END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_operator_approvals x
  JOIN app.collections c ON c.id=x.collection_id AND c.status='active'
  WHERE x.collection_id=s.collection_id AND x.principal_user_id=a.principal_user_id AND x.admin_user_id=a.admin_id
   AND x.active AND 'records.read'=ANY(x.capabilities)
   AND private.burimunsi_pin_root_snapshot(x.collection_id,x.principal_user_id,x.phone,x.role,x.capabilities) IS NOT NULL)
 INTO allowed;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.auto_admin_transaction',coalesce(old_tx,''),true);
 RETURN CASE WHEN allowed THEN jsonb_build_object('kind','visible','groupId',s.collection_id)
  ELSE jsonb_build_object('kind','hidden','groupId',NULL) END;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.auto_admin_transaction',coalesce(old_tx,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_admin_transaction_visibility(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_admin_transaction_visibility(text) TO collect_runtime;

-- Preserve the existing fail-closed retention inventory when these two new
-- private relations are installed. Their subject mapping remains unresolved;
-- neither record deletion nor an empty-subject assertion is enabled here.
DO $retention$
DECLARE body text;next_body text;anchor text;replacement text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure
  AND encode(sha256(convert_to(prosrc,'UTF8')),'hex')='e03d4606ccbfed5f102fb45ac8c05da8be1ae84f6964e56b1cec42633b1614a4')
 OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure
  AND encode(sha256(convert_to(prosrc,'UTF8')),'hex')='0cdbf6ed4a27b797061898350f0ae32dec47cf2bc2ca25fbafc6802ac60e414e')
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') item
  WHERE item->>'relation' IN ('private.burimunsi_auto_sms_jobs','private.burimunsi_native_receipt_origins')) THEN
  RAISE EXCEPTION 'burimunsi_auto_retention_predecessor_changed' USING ERRCODE='55000';END IF;
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 next_body:='SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||''[{"name":"private:burimunsi_auto_sms_jobs","relation":"private.burimunsi_auto_sms_jobs","scope":"unmapped_private","purpose":"Unreviewed subject mapping and object custody; inspection only, effects blocked","blocked":true},{"name":"private:burimunsi_native_receipt_origins","relation":"private.burimunsi_native_receipt_origins","scope":"unmapped_private","purpose":"Unreviewed subject mapping and object custody; inspection only, effects blocked","blocked":true}]''::jsonb) FROM ('||body||') prior(base)';
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
 anchor:=$a$'private:burimunsi_accounts',$a$;
 replacement:=$b$'private:burimunsi_auto_sms_jobs','private:burimunsi_native_receipt_origins','private:burimunsi_accounts',$b$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'burimunsi_auto_retention_predecessor_changed' USING ERRCODE='55000';END IF;
 next_body:=replace(body,anchor,replacement);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
END;$retention$;

COMMIT;

