-- Durable native sign-in: preserve the original immutable PIN-session identity,
-- while permitting its exact device-bound proof to renew a short authority lease.
-- This does not create a managed Auth or web Admin session, or fresh PIN/MFA proof.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE r record;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.burimunsi_pin_session_context(text,uuid,text,text)') IS NULL
  OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='private.burimunsi_sessions'::regclass
   AND attname IN('pin_renewed_at','pin_lease_expires_at') AND NOT attisdropped)
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_session_renewal_precondition' USING ERRCODE='55000';
 END IF;
 FOR r IN SELECT * FROM(VALUES
  ('private.burimunsi_pin_session_context(text,uuid,text,text)','ffaabe2c48a52f0ee0d67f847111da738a4125e999a326210c1007ed2ca18263'),
  ('private.burimunsi_gateway_target_snapshot(text,uuid,uuid,uuid,bigint)','d6b461c1984d81e4b2aed73f11e25b09a20434c96c9750d9b55f8ef25d71c327'),
  ('private.burimunsi_gateway_retire(text,text,uuid,text)','5a88c71358547a6456b76d6652c234c88646b759ee654fb1c5b71090a906a471'),
  ('private.burimunsi_gateway_retirement_outcome(text,uuid,text,text,uuid,text)','316aea79ad373465c4c0416e62ad90b6b60dec830dc52489ba23226707d7c422')
 ) AS expected(signature,body_sha256) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r.signature)
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.body_sha256) THEN
   RAISE EXCEPTION 'burimunsi_session_renewal_function_preimage' USING ERRCODE='55000';
  END IF;
 END LOOP;
END;$preflight$;

-- Renewal is mutable metadata on the existing session relation; the original
-- expiry and journal identity remain protected by its immutable-identity guard.
ALTER TABLE private.burimunsi_sessions
 ADD COLUMN pin_renewed_at bigint,
 ADD COLUMN pin_lease_expires_at bigint,
 ADD CONSTRAINT burimunsi_pin_lease_bounds CHECK(
  (pin_renewed_at IS NULL AND pin_lease_expires_at IS NULL) OR
  (auth_method='phone_pin' AND pin_renewed_at IS NOT NULL AND pin_lease_expires_at IS NOT NULL
   AND pin_renewed_at>0 AND pin_lease_expires_at>pin_renewed_at
   AND pin_lease_expires_at>=expires_at AND pin_lease_expires_at<=pin_renewed_at+28800000)
 );

-- Internal credential check: no expiry decision is made here. It must never be
-- exposed as an application actor; only the two owner functions below may call it.
CREATE FUNCTION private.burimunsi_pin_bound_session(p_token text,p_installation uuid,p_device_token text,p_profile text)
RETURNS TABLE(collection_id text,account_id uuid,principal_user_id text,native_session_id uuid,grant_id uuid,
 installation_id uuid,profile text,role text,capabilities text[],created_at bigint,expires_at bigint,
 credential_version bigint,grant_version bigint,shared_role text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.pin_frame',true);
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' OR p_device_token IS NULL OR p_device_token !~ '^[a-f0-9]{64}$'
  OR p_installation IS NULL OR p_profile IS NULL OR p_profile NOT IN('staff','internal_receiver') THEN RETURN;END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 RETURN QUERY SELECT s.collection_id,a.id,a.principal_user_id,s.id,d.id,d.installation_id,d.profile,
  a.role,a.capabilities,s.created_at,greatest(s.expires_at,coalesce(s.pin_lease_expires_at,s.expires_at)),
  a.credential_version,d.version,proof.snapshot->>'sharedRole'
 FROM private.burimunsi_sessions s
 JOIN private.burimunsi_pin_session_links link ON link.native_session_id=s.id
  AND link.collection_id=s.collection_id AND link.account_id=s.account_id AND link.principal_user_id=s.principal_user_id
 JOIN private.burimunsi_accounts a ON a.id=s.account_id AND a.collection_id=s.collection_id
  AND a.principal_user_id=s.principal_user_id AND a.active AND NOT a.removed
  AND a.credential_version=s.credential_version AND a.version=link.account_version
 JOIN app.users u ON u.id=a.principal_user_id AND u.access_status='active'
 JOIN private.burimunsi_device_grants d ON d.id=s.grant_id AND d.collection_id=s.collection_id
  AND d.installation_id=s.installation_id AND d.active AND d.version=s.grant_version
 JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.account_id=a.id AND da.collection_id=a.collection_id
 JOIN private.burimunsi_scopes scope ON scope.collection_id=s.collection_id AND scope.version=link.scope_version
 JOIN app.collections c ON c.id=scope.collection_id AND c.status='active'
 CROSS JOIN LATERAL(SELECT private.burimunsi_pin_authority_snapshot(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities) AS snapshot) proof
 WHERE s.auth_method='phone_pin' AND NOT s.revoked AND s.created_at<=at_ms
  AND s.created_at=link.created_at AND proof.snapshot IS NOT NULL AND proof.snapshot=link.authority_snapshot
  AND s.token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex')
  AND d.token_hash=encode(sha256(convert_to(p_device_token,'UTF8')),'hex')
  AND s.installation_id=p_installation AND d.profile=p_profile;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_pin_bound_session(text,uuid,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

-- Table-level UPDATE is used by existing logout code. Protect the new columns
-- independently: only the owner-executed renewal frame, bound to this SQL
-- transaction, this session and its exact raw device proof, may extend them.
CREATE FUNCTION private.burimunsi_pin_lease_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.pin_renewed_at IS NOT NULL OR NEW.pin_lease_expires_at IS NOT NULL THEN
   RAISE EXCEPTION 'burimunsi_session_lease_denied' USING ERRCODE='42501';END IF;
  RETURN NEW;
 END IF;
 IF (NEW.pin_renewed_at,NEW.pin_lease_expires_at) IS DISTINCT FROM (OLD.pin_renewed_at,OLD.pin_lease_expires_at) THEN
  IF current_user<>'postgres' OR current_setting('role',true) IS DISTINCT FROM 'collect_runtime'
   OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true'
   OR current_setting('burimunsi.pin_renewal_frame',true) IS DISTINCT FROM txid_current()::text||':'||OLD.id::text
   OR OLD.revoked OR NEW.revoked OR OLD.auth_method<>'phone_pin'
   OR NEW.pin_renewed_at IS NULL OR NEW.pin_lease_expires_at IS NULL
   OR (OLD.pin_renewed_at IS NOT NULL AND NEW.pin_renewed_at<OLD.pin_renewed_at)
   OR (OLD.pin_lease_expires_at IS NOT NULL AND NEW.pin_lease_expires_at<OLD.pin_lease_expires_at)
   OR NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_bound_session(
     current_setting('burimunsi.pin_renewal_token',true),
     nullif(current_setting('burimunsi.pin_renewal_installation',true),'')::uuid,
     current_setting('burimunsi.pin_renewal_device',true),current_setting('burimunsi.pin_renewal_profile',true)) c
     WHERE c.native_session_id=OLD.id AND c.collection_id=OLD.collection_id) THEN
   RAISE EXCEPTION 'burimunsi_session_lease_denied' USING ERRCODE='42501';END IF;
 END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_pin_lease_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_pin_lease_guard BEFORE INSERT OR UPDATE ON private.burimunsi_sessions
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_pin_lease_guard();
ALTER TABLE private.burimunsi_sessions ENABLE ALWAYS TRIGGER burimunsi_pin_lease_guard;

-- Ordinary requests continue to require a current short lease; this read path
-- remains valid inside a genuine repeatable-read READ ONLY transaction.
CREATE OR REPLACE FUNCTION private.burimunsi_pin_session_context(p_token text,p_installation uuid,p_device_token text,p_profile text)
RETURNS TABLE(collection_id text,account_id uuid,principal_user_id text,native_session_id uuid,grant_id uuid,
 installation_id uuid,profile text,role text,capabilities text[],created_at bigint,expires_at bigint,
 credential_version bigint,grant_version bigint,shared_role text) LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT c.* FROM private.burimunsi_pin_bound_session(p_token,p_installation,p_device_token,p_profile) c
 WHERE c.expires_at>floor(extract(epoch FROM clock_timestamp())*1000)::bigint
$fn$;

-- Invoked only by the existing /session read/revalidation path, in a fenced
-- write transaction. A caller cannot turn a stored hash or claimed group into
-- authority. The same original bearer/session is never replaced or unrevoked.
CREATE FUNCTION private.burimunsi_pin_renew_session(p_token text,p_installation uuid,p_device_token text,p_profile text,
 p_collection text,p_ttl_ms bigint)
RETURNS TABLE(collection_id text,account_id uuid,principal_user_id text,native_session_id uuid,grant_id uuid,
 installation_id uuid,profile text,role text,capabilities text[],created_at bigint,expires_at bigint,
 credential_version bigint,grant_version bigint,shared_role text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.pin_frame',true);
 old_renewal_frame text:=current_setting('burimunsi.pin_renewal_frame',true);
 old_token text:=current_setting('burimunsi.pin_renewal_token',true);
 old_installation text:=current_setting('burimunsi.pin_renewal_installation',true);
 old_device text:=current_setting('burimunsi.pin_renewal_device',true);
 old_profile text:=current_setting('burimunsi.pin_renewal_profile',true);
 candidate record;verified record;
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 IF p_collection IS NULL OR length(p_collection) NOT BETWEEN 1 AND 128 OR p_ttl_ms IS NULL
  OR p_ttl_ms<60000 OR p_ttl_ms>28800000 THEN RETURN;END IF;
 SELECT * INTO candidate FROM private.burimunsi_pin_bound_session(p_token,p_installation,p_device_token,p_profile);
 IF NOT FOUND OR candidate.collection_id IS DISTINCT FROM p_collection THEN RETURN;END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 -- A normal early revalidation does not churn the deadline while another
 -- transaction is using its exact session snapshot. Serialized late retries
 -- reuse the first successful lease until it nears expiry again.
 IF candidate.expires_at<=at_ms+60000 THEN
  PERFORM set_config('burimunsi.pin_renewal_frame',txid_current()::text||':'||candidate.native_session_id::text,true);
  PERFORM set_config('burimunsi.pin_renewal_token',p_token,true);
  PERFORM set_config('burimunsi.pin_renewal_installation',p_installation::text,true);
  PERFORM set_config('burimunsi.pin_renewal_device',p_device_token,true);
  PERFORM set_config('burimunsi.pin_renewal_profile',p_profile,true);
  UPDATE private.burimunsi_sessions s SET
   pin_renewed_at=greatest(coalesce(s.pin_renewed_at,0),at_ms),
   pin_lease_expires_at=greatest(s.expires_at,coalesce(s.pin_lease_expires_at,s.expires_at),at_ms+p_ttl_ms)
  WHERE s.id=candidate.native_session_id AND s.collection_id=p_collection AND NOT s.revoked
   AND greatest(s.expires_at,coalesce(s.pin_lease_expires_at,s.expires_at))<=at_ms+60000;
  -- Another valid concurrent renewal may already have extended this row; the
  -- complete proof and authority are rechecked below in either case.
  PERFORM set_config('burimunsi.pin_renewal_frame',coalesce(old_renewal_frame,''),true);
  PERFORM set_config('burimunsi.pin_renewal_token',coalesce(old_token,''),true);
  PERFORM set_config('burimunsi.pin_renewal_installation',coalesce(old_installation,''),true);
  PERFORM set_config('burimunsi.pin_renewal_device',coalesce(old_device,''),true);
  PERFORM set_config('burimunsi.pin_renewal_profile',coalesce(old_profile,''),true);
 END IF;
 -- Re-check and lock all current operator/approval/device authority before the
 -- lease commits. A concurrent logout or approval change cannot revive it.
 PERFORM private.burimunsi_set_pin_context(p_token,p_installation,p_device_token,p_profile);
 PERFORM private.burimunsi_pin_assert_actor(NULL,p_collection,NULL,1,NULL);
 SELECT * INTO verified FROM private.burimunsi_pin_session_context(p_token,p_installation,p_device_token,p_profile);
 IF NOT FOUND OR verified.native_session_id IS DISTINCT FROM candidate.native_session_id
  OR verified.collection_id IS DISTINCT FROM p_collection THEN
  RAISE EXCEPTION 'burimunsi_session_changed' USING ERRCODE='42501';END IF;
 RETURN QUERY SELECT c.* FROM private.burimunsi_pin_session_context(p_token,p_installation,p_device_token,p_profile) c;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_renewal_frame',coalesce(old_renewal_frame,''),true);
 PERFORM set_config('burimunsi.pin_renewal_token',coalesce(old_token,''),true);
 PERFORM set_config('burimunsi.pin_renewal_installation',coalesce(old_installation,''),true);
 PERFORM set_config('burimunsi.pin_renewal_device',coalesce(old_device,''),true);
 PERFORM set_config('burimunsi.pin_renewal_profile',coalesce(old_profile,''),true);
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_pin_renew_session(text,uuid,text,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_pin_renew_session(text,uuid,text,text,text,bigint) TO collect_runtime;
-- Existing receiver handoff reads the same effective expiry. Recovery remains
-- bounded by the exact lease at retirement; revoked credentials cannot renew it.
CREATE OR REPLACE FUNCTION private.burimunsi_gateway_target_snapshot(p_collection text,p_grant uuid,p_installation uuid,p_custodian uuid,p_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.pin_frame',true);result jsonb;
BEGIN
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT jsonb_build_object('accountVersion',a.version,'pinVersion',a.credential_version,'authority',proof.snapshot) INTO result
 FROM private.burimunsi_device_grants d JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.collection_id=d.collection_id
 JOIN private.burimunsi_accounts a ON a.id=da.account_id AND a.collection_id=d.collection_id
 JOIN app.users u ON u.id=a.principal_user_id AND u.access_status='active'
 CROSS JOIN LATERAL(SELECT private.burimunsi_pin_authority_snapshot(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities) AS snapshot) proof
 WHERE d.collection_id=p_collection AND d.id=p_grant AND d.installation_id=p_installation AND d.version=p_version
  AND d.active AND d.profile='internal_receiver' AND (d.custodian_account_id IS NULL OR d.custodian_account_id=a.id)
  AND a.id=p_custodian AND a.active AND NOT a.removed AND a.role='admin' AND 'gateway.manage'=ANY(a.capabilities)
  AND proof.snapshot IS NOT NULL
  -- Candidate registration evidence survives the deliberate scope bump only as
  -- a candidate. Ordinary auth and actual Pair require fresh current scope.
  AND(d.custodian_account_id IS NOT NULL OR EXISTS(
   SELECT 1 FROM private.burimunsi_sessions s JOIN private.burimunsi_pin_session_links l ON l.native_session_id=s.id
   WHERE s.collection_id=a.collection_id AND s.account_id=a.id AND s.principal_user_id=a.principal_user_id
    AND s.grant_id=d.id AND s.installation_id=d.installation_id AND s.grant_version=d.version
    AND s.credential_version=a.credential_version AND s.auth_method='phone_pin' AND NOT s.revoked
    AND s.created_at=l.created_at AND s.created_at<=floor(extract(epoch FROM clock_timestamp())*1000)::bigint
    AND s.created_at>=floor(extract(epoch FROM clock_timestamp())*1000)::bigint-86400000
    AND greatest(s.expires_at,coalesce(s.pin_lease_expires_at,s.expires_at))
     >floor(extract(epoch FROM clock_timestamp())*1000)::bigint
    AND l.collection_id=a.collection_id AND l.account_id=a.id AND l.principal_user_id=a.principal_user_id
    AND l.account_version=a.version AND l.authority_snapshot=proof.snapshot));
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RETURN result;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

CREATE OR REPLACE FUNCTION private.burimunsi_gateway_retire(p_collection text,p_code text,p_request uuid,p_fingerprint text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor record;h private.burimunsi_gateway_handoffs%ROWTYPE;s private.burimunsi_sessions%ROWTYPE;
 a private.burimunsi_accounts%ROWTYPE;d private.burimunsi_device_grants%ROWTYPE;link private.burimunsi_pin_session_links%ROWTYPE;
 expected_hash text;result jsonb;new_version bigint;at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 SELECT * INTO actor FROM private.burimunsi_pin_context();
 IF NOT FOUND OR actor.collection_id IS DISTINCT FROM p_collection THEN RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
 -- Exclusive scope first: competing old-phone/Owner finalization serializes
 -- before either takes the handoff row or upgrades any native shared lock.
 PERFORM 1 FROM private.burimunsi_scopes WHERE collection_id=p_collection FOR UPDATE;
 PERFORM private.burimunsi_pin_assert_actor('receivers.manage',p_collection,NULL,1,300);
 SELECT * INTO actor FROM private.burimunsi_pin_context();
 IF NOT FOUND OR actor.collection_id<>p_collection OR actor.role<>'admin' OR actor.profile<>'internal_receiver'
  OR p_code IS NULL OR p_code !~ '^[a-f0-9]{64}$' OR p_request IS NULL THEN RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
 expected_hash:=encode(sha256(convert_to('burimunsi.gateway.retire.v1:'||encode(sha256(convert_to(p_code,'UTF8')),'hex')||':'||p_request::text,'UTF8')),'hex');
 IF p_fingerprint IS DISTINCT FROM expected_hash THEN RAISE EXCEPTION 'burimunsi_handoff_request_conflict' USING ERRCODE='23505';END IF;
 SELECT * INTO h FROM private.burimunsi_gateway_handoffs WHERE collection_id=p_collection AND code_hash=encode(sha256(convert_to(p_code,'UTF8')),'hex') FOR UPDATE;
 IF NOT FOUND OR h.old_installation_id<>actor.installation_id OR h.old_grant_id<>actor.grant_id OR h.old_grant_version<>actor.grant_version
  OR h.old_custodian_id<>actor.account_id OR h.owner_principal_id<>actor.principal_user_id THEN
  RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
 SELECT * INTO STRICT s FROM private.burimunsi_sessions WHERE id=actor.native_session_id;
 SELECT * INTO STRICT a FROM private.burimunsi_accounts WHERE id=actor.account_id AND collection_id=p_collection;
 SELECT * INTO STRICT d FROM private.burimunsi_device_grants WHERE id=actor.grant_id AND collection_id=p_collection;
 SELECT * INTO STRICT link FROM private.burimunsi_pin_session_links WHERE native_session_id=s.id;
 new_version:=private.burimunsi_gateway_commit_handoff(h.id,'old_phone',p_request);
 result:=jsonb_build_object('retired',true,'handoffId',h.id,'requestId',p_request,'reauthenticationRequired',true);
 INSERT INTO private.burimunsi_gateway_retirements(collection_id,actor_id,session_id,request_id,handoff_id,fingerprint,installation_id,grant_id,
  device_hash,account_version,pin_version,authority_snapshot,response,created_at,recover_until)
  VALUES(p_collection,a.id,s.id,p_request,h.id,p_fingerprint,d.installation_id,d.id,d.token_hash,a.version,a.credential_version,link.authority_snapshot,result,at_ms,actor.expires_at);
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
  VALUES(a.principal_user_id,s.id::text,'burimunsi.gateway.retired','momo_binding',h.old_binding_id,p_request::text,
   jsonb_build_object('collection_id',p_collection,'handoff_id',h.id,'retirement_method','old_phone','native_actor_id',a.id)::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 RETURN result;
END;$fn$;

CREATE OR REPLACE FUNCTION private.burimunsi_gateway_retirement_outcome(p_token text,p_installation uuid,p_device text,p_profile text,p_request uuid,p_fingerprint text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE prior_frame text:=current_setting('burimunsi.pin_frame',true);s private.burimunsi_sessions%ROWTYPE;
 a private.burimunsi_accounts%ROWTYPE;r private.burimunsi_gateway_retirements%ROWTYPE;d private.burimunsi_device_grants%ROWTYPE;
 proof jsonb;at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;result jsonb;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF pg_is_in_recovery() THEN RAISE EXCEPTION 'command_primary_required' USING ERRCODE='55000';END IF;
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' OR p_device IS NULL OR p_device !~ '^[a-f0-9]{64}$'
  OR p_profile IS DISTINCT FROM 'internal_receiver' OR p_installation IS NULL OR p_request IS NULL
  OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$' THEN RETURN NULL;END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT base.* INTO s FROM private.burimunsi_sessions base
  WHERE base.token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') AND base.installation_id=p_installation
  AND base.auth_method='phone_pin' AND base.created_at<=at_ms
  AND greatest(base.expires_at,coalesce(base.pin_lease_expires_at,base.expires_at))>at_ms;
 IF NOT FOUND THEN PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RETURN NULL;END IF;
 SELECT * INTO a FROM private.burimunsi_accounts WHERE id=s.account_id AND collection_id=s.collection_id
  AND principal_user_id=s.principal_user_id AND active AND NOT removed;
 proof:=private.burimunsi_pin_authority_snapshot(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities);
 IF a.id IS NULL OR proof IS NULL THEN PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RETURN NULL;END IF;
 SELECT * INTO r FROM private.burimunsi_gateway_retirements WHERE collection_id=s.collection_id AND actor_id=a.id AND request_id=p_request;
 IF FOUND THEN
  IF r.session_id<>s.id OR r.installation_id<>p_installation OR r.grant_id<>s.grant_id OR r.fingerprint<>p_fingerprint OR r.recover_until<=at_ms
   OR r.device_hash<>encode(sha256(convert_to(p_device,'UTF8')),'hex') OR a.version<>r.account_version OR a.credential_version<>r.pin_version
   OR proof<>r.authority_snapshot THEN PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RETURN NULL;END IF;
  result:=jsonb_build_object('kind','gateway_retirement_outcome','collectionId',s.collection_id,'actorId',a.id,'sessionId',s.id,
   'installationId',s.installation_id,'profile',p_profile,'requestId',p_request,'fingerprint',p_fingerprint,'state','retired','ack',r.response);
 ELSE
  IF NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(p_token,p_installation,p_device,p_profile) current_proof
   WHERE current_proof.native_session_id=s.id AND current_proof.account_id=a.id) THEN
   PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RETURN NULL;END IF;
  result:=jsonb_build_object('kind','gateway_retirement_outcome','collectionId',s.collection_id,'actorId',a.id,'sessionId',s.id,
   'installationId',s.installation_id,'profile',p_profile,'requestId',p_request,'fingerprint',p_fingerprint,'state','unknown','ack',NULL);
 END IF;
 PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RETURN result;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RAISE;
END;$fn$;
COMMIT;
