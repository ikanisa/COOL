-- UNVERIFIED ADDITIVE DESIGN DRAFT. Requires the separately qualified private
-- quarantine draft. Never register or deploy without independent full-chain,
-- managed-session, email-assurance, storage, race and retention qualification.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR to_regclass('private.burimunsi_observation_requests') IS NULL
  OR to_regclass('private.burimunsi_unresolved_observations') IS NULL
  OR to_regprocedure('private.burimunsi_managed_admin_snapshot()') IS NULL
  OR to_regprocedure('private.burimunsi_pin_root_snapshot(text,text,text,text,text[])') IS NULL
  OR to_regprocedure('private.assert_actor(text,text,text,bigint,bigint)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_admin_collections()') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced') THEN
  RAISE EXCEPTION 'burimunsi_observation_admin_install_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

-- This guard uses the current real managed BFF/GoTrue context and the same
-- SQL sensitive-operation rule as canonical Admin SMS disclosure. For Admin,
-- the requested freshness threshold is current email proof; it is not an AAL2
-- claim or a second factor. Neither native PIN nor request JSON may supply it.
CREATE FUNCTION private.burimunsi_observation_admin_actor(p_sensitive boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a record;email_actor jsonb;principal text;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF p_sensitive IS NULL OR coalesce(nullif(current_setting('burimunsi.pin_token',true),''),
  nullif(current_setting('burimunsi.pin_installation',true),''),nullif(current_setting('burimunsi.pin_device',true),''),
  nullif(current_setting('burimunsi.pin_profile',true),'')) IS NOT NULL THEN
  RAISE EXCEPTION 'burimunsi_observation_admin_denied' USING ERRCODE='42501';END IF;
 SELECT * INTO a FROM private.burimunsi_managed_admin_snapshot();
 IF NOT FOUND OR a.surface<>'admin' OR a.shared_role NOT IN('admin','owner') THEN
  RAISE EXCEPTION 'burimunsi_observation_admin_denied' USING ERRCODE='42501';END IF;
 email_actor:=private._admin_email_context();
 IF email_actor->>'admin_id' IS DISTINCT FROM a.admin_id OR email_actor->>'principal_id' IS DISTINCT FROM a.principal_user_id
  OR email_actor->>'session_id' IS DISTINCT FROM a.principal_session_id OR email_actor->>'cookie_hash' IS DISTINCT FROM a.cookie_hash
  OR email_actor->>'public_session_id' IS DISTINCT FROM a.public_session_id OR email_actor->>'origin' IS DISTINCT FROM a.origin
  OR email_actor->>'role' IS DISTINCT FROM a.shared_role THEN
  RAISE EXCEPTION 'burimunsi_observation_admin_denied' USING ERRCODE='42501';END IF;
 principal:=private.assert_actor('sms.read',NULL,NULL,1,NULL);
 IF principal IS DISTINCT FROM a.principal_user_id THEN RAISE EXCEPTION 'burimunsi_observation_admin_denied' USING ERRCODE='42501';END IF;
 IF p_sensitive AND private.assert_actor('sms.reveal',NULL,NULL,2,300) IS DISTINCT FROM a.principal_user_id THEN
  RAISE EXCEPTION 'burimunsi_observation_admin_denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('adminId',a.admin_id,'principalId',a.principal_user_id,'sessionId',a.principal_session_id,'role',a.shared_role);
END;$fn$;

CREATE FUNCTION private.burimunsi_observation_admin_scope(p_collection text,p_sensitive boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_admin_actor(p_sensitive);o record;
 old_frame text:=current_setting('burimunsi.pin_frame',true);
BEGIN
 IF p_collection IS NULL OR p_collection !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$' THEN
  RAISE EXCEPTION 'burimunsi_observation_admin_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT x.collection_id,x.principal_user_id,x.admin_user_id,x.phone,x.role,x.capabilities,c.title INTO o
 FROM private.burimunsi_operator_approvals x JOIN app.collections c ON c.id=x.collection_id AND c.status='active'
 WHERE x.collection_id=p_collection AND x.principal_user_id=a->>'principalId' AND x.admin_user_id=a->>'adminId'
  AND x.active AND x.role='admin' AND 'sms.read'=ANY(x.capabilities) FOR SHARE OF x,c;
 IF NOT FOUND OR private.burimunsi_pin_root_snapshot(o.collection_id,o.principal_user_id,o.phone,o.role,o.capabilities) IS NULL THEN
  RAISE EXCEPTION 'burimunsi_observation_admin_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
 RETURN a||jsonb_build_object('collectionId',p_collection,'label',o.title);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- The caller sees only labels for its own currently approved Admin scopes.
CREATE FUNCTION private.burimunsi_observation_admin_collections() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_admin_actor(false);v jsonb;n bigint;
 old_frame text:=current_setting('burimunsi.pin_frame',true);
BEGIN
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT count(*),coalesce(jsonb_agg(jsonb_build_object('collectionId',o.collection_id,'label',c.title)
  ORDER BY lower(c.title),o.collection_id),'[]'::jsonb) INTO n,v
 FROM private.burimunsi_operator_approvals o JOIN app.collections c ON c.id=o.collection_id AND c.status='active'
 WHERE o.principal_user_id=a->>'principalId' AND o.admin_user_id=a->>'adminId' AND o.active AND o.role='admin'
  AND 'sms.read'=ANY(o.capabilities)
  AND private.burimunsi_pin_root_snapshot(o.collection_id,o.principal_user_id,o.phone,o.role,o.capabilities) IS NOT NULL;
 IF n>500 THEN RAISE EXCEPTION 'burimunsi_observation_admin_limit' USING ERRCODE='54000';END IF;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RETURN v;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Internal immutable intent projection. "retained" is a matching committed
-- journal and source row, not a fresh physical provider read or financial fact.
CREATE FUNCTION private.burimunsi_observation_admin_rows(p_collection text)
RETURNS TABLE(request_id uuid,source_id text,admitted_at bigint,retention_state text,body_sha256 text,
 owner_user_id text,object_key text,object_sha256 text,size_bytes bigint,fingerprint text,key_id text,source_fingerprint text,
 storage_operation_id text,storage_fingerprint text,cipher_sha256 text,cipher_size bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_admin_scope(p_collection,false);
 old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 PERFORM set_config('burimunsi.observation_frame','1',true);
 RETURN QUERY
 SELECT r.request_id,r.source_id,r.created_at,
  CASE WHEN x.source_id IS NOT NULL AND i.object_key IS NOT NULL AND m.object_key IS NOT NULL AND v.object_key IS NOT NULL
    AND i.state='committed' AND NOT i.delete_tombstone AND NOT i.upload_unresolved AND i.active_attempt IS NULL
    AND i.operation_id=m.operation_id AND i.fingerprint=m.fingerprint AND i.sha256=m.sha256 AND i.size=m.size
    AND i.scope=m.scope AND i.http_metadata=m.http_metadata AND i.custom_metadata=m.custom_metadata
    AND i.scope=jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id)
    AND v.scope=i.scope AND v.plaintext_sha256=x.object_sha256 AND v.sealed_body IS NULL AND v.cleared_at IS NOT NULL
    AND v.aad='sms:'||r.source_id||':'||x.object_sha256 AND v.key_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
    AND i.http_metadata=jsonb_build_object('contentType','application/octet-stream')
    AND i.custom_metadata=jsonb_build_object('sha256',x.object_sha256,'key_id',v.key_id,'source_fingerprint',v.source_fingerprint)
    AND i.custom_metadata->>'sha256'=x.object_sha256 AND i.custom_metadata->>'source_fingerprint'=v.source_fingerprint
    AND NOT EXISTS(SELECT 1 FROM private.storage_delete_intents d WHERE d.object_key=x.object_key)
   THEN 'retained' ELSE 'unresolved' END,
  CASE WHEN x.source_id IS NOT NULL AND i.object_key IS NOT NULL AND m.object_key IS NOT NULL AND v.object_key IS NOT NULL
    AND i.state='committed' AND NOT i.delete_tombstone AND NOT i.upload_unresolved AND i.active_attempt IS NULL
    AND i.operation_id=m.operation_id AND i.fingerprint=m.fingerprint AND i.sha256=m.sha256 AND i.size=m.size
    AND i.scope=m.scope AND i.http_metadata=m.http_metadata AND i.custom_metadata=m.custom_metadata
    AND i.scope=jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id)
    AND v.scope=i.scope AND v.plaintext_sha256=x.object_sha256 AND v.sealed_body IS NULL AND v.cleared_at IS NOT NULL
    AND v.aad='sms:'||r.source_id||':'||x.object_sha256 AND v.key_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
    AND i.http_metadata=jsonb_build_object('contentType','application/octet-stream')
    AND i.custom_metadata=jsonb_build_object('sha256',x.object_sha256,'key_id',v.key_id,'source_fingerprint',v.source_fingerprint)
    AND i.custom_metadata->>'sha256'=x.object_sha256 AND i.custom_metadata->>'source_fingerprint'=v.source_fingerprint
    AND NOT EXISTS(SELECT 1 FROM private.storage_delete_intents d WHERE d.object_key=x.object_key)
   THEN x.body_sha256 ELSE NULL END,
  r.principal_user_id,x.object_key,x.object_sha256,x.size_bytes,r.fingerprint,v.key_id,v.source_fingerprint,
  i.operation_id,i.fingerprint,i.sha256,i.size
 FROM private.burimunsi_observation_requests r
 LEFT JOIN private.burimunsi_unresolved_observations x ON x.source_id=r.source_id AND x.collection_id=r.collection_id
  AND x.account_id=r.account_id AND x.principal_user_id=r.principal_user_id AND x.installation_id=r.installation_id
  AND x.grant_id=r.grant_id AND x.grant_version=r.grant_version AND x.request_id=r.request_id AND x.fingerprint=r.fingerprint
  -- A successful exact retry may use a renewed native session or refreshed
  -- consent/profile; these are validated by the commit guard, not equated to
  -- the earlier pre-admission snapshot.
 LEFT JOIN private.storage_put_intents i ON i.object_key=x.object_key
 LEFT JOIN private.storage_objects m ON m.object_key=x.object_key
 LEFT JOIN private.storage_payload_reservations v ON v.object_key=x.object_key
 WHERE r.collection_id=p_collection;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_observation_admin_page(p_collection text,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE result jsonb;n bigint;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000 THEN
  RAISE EXCEPTION 'burimunsi_observation_admin_invalid' USING ERRCODE='22023';END IF;
 WITH records AS MATERIALIZED(SELECT * FROM private.burimunsi_observation_admin_rows(p_collection)),
 totals AS(SELECT count(*) AS n,encode(sha256(convert_to(coalesce(string_agg(jsonb_build_array(
  source_id,request_id,admitted_at,retention_state,body_sha256,owner_user_id,object_key,object_sha256,
  fingerprint,key_id,source_fingerprint,storage_operation_id,storage_fingerprint,cipher_sha256,cipher_size)::text,
  E'\n' ORDER BY source_id),''),'UTF8')),'hex') AS revision FROM records),
 page AS(SELECT * FROM records ORDER BY admitted_at DESC,source_id LIMIT p_limit OFFSET p_offset)
 SELECT totals.n,jsonb_build_object('collectionId',p_collection,'totalCount',totals.n,'revision',totals.revision,
  'items',coalesce((SELECT jsonb_agg(jsonb_build_object('requestId',request_id,'sourceId',source_id,
   'admittedAt',admitted_at,'retentionState',retention_state,'bodySha256',body_sha256,
   'ownerUserId',owner_user_id,'objectKey',object_key,'objectSha256',object_sha256,'fingerprint',fingerprint,
   'keyId',key_id,'sourceFingerprint',source_fingerprint)
   ORDER BY admitted_at DESC,source_id) FROM page),'[]'::jsonb)) INTO n,result FROM totals;
 IF n>100000 THEN RAISE EXCEPTION 'burimunsi_observation_admin_limit' USING ERRCODE='54000';END IF;
 RETURN result;
END;$fn$;

-- Source metadata is available only after the independent fresh-email guard.
-- Per-object lock serializes the final proof with the existing deletion fence.
CREATE FUNCTION private.burimunsi_observation_admin_source(p_collection text,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_admin_scope(p_collection,true);r record;
BEGIN
 IF p_source IS NULL OR p_source !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' THEN
  RAISE EXCEPTION 'burimunsi_observation_admin_invalid' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sms/'||p_source,7346369));
 SELECT * INTO r FROM private.burimunsi_observation_admin_rows(p_collection)
 WHERE source_id=p_source AND retention_state='retained';
 IF NOT FOUND THEN RETURN NULL;END IF;
 RETURN jsonb_build_object('collectionId',p_collection,'sourceId',r.source_id,'requestId',r.request_id,
  'bodySha256',r.body_sha256,'ownerUserId',r.owner_user_id,'objectKey',r.object_key,'objectSha256',r.object_sha256,
  'sizeBytes',r.size_bytes,'fingerprint',r.fingerprint,'keyId',r.key_id,'sourceFingerprint',r.source_fingerprint,
  'storageOperationId',r.storage_operation_id,'storageFingerprint',r.storage_fingerprint,
  'cipherSha256',r.cipher_sha256,'cipherSize',r.cipher_size,'admittedAt',r.admitted_at);
END;$fn$;

-- The current collection Admin may request a profile proof only for a source
-- independently authorized for reveal. No account number is returned.
CREATE FUNCTION private.burimunsi_observation_admin_hint_profile(p_collection text,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE scope jsonb:=private.burimunsi_observation_admin_scope(p_collection,true);source jsonb;v jsonb;
 old_frame text:=current_setting('burimunsi.observation_frame',true);
 old_pin text:=current_setting('burimunsi.pin_frame',true);
BEGIN
 source:=private.burimunsi_observation_admin_source(p_collection,p_source);IF source IS NULL THEN RETURN NULL;END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);PERFORM set_config('burimunsi.pin_frame','1',true);
 -- Match detection writers' scope-then-profile lock order before the joined
 -- lookup; absence is also protected from a concurrent profile insertion.
 PERFORM 1 FROM private.burimunsi_scopes s JOIN app.momo_receiving_accounts w ON w.id=s.receiving_account_id
  WHERE s.collection_id=p_collection FOR SHARE OF s,w;
 PERFORM 1 FROM private.burimunsi_detection_profiles d WHERE d.collection_id=p_collection FOR SHARE;
 SELECT jsonb_build_object('profileSha256',r.profile_sha256,'profile',jsonb_build_object(
  'provider',w.provider,'status',w.status,'profile_status',w.profile_status,'profile_version',w.profile_version,
  'profile_json',w.profile_json,'currency',w.currency,'timezone',w.timezone)) INTO v
 FROM private.burimunsi_unresolved_observations r
 JOIN private.burimunsi_scopes s ON s.collection_id=r.collection_id
 JOIN app.momo_receiving_accounts w ON w.id=s.receiving_account_id
 WHERE r.source_id=p_source AND r.collection_id=p_collection AND (s.enabled OR s.active_binding_id IS NULL)
  AND w.status='active' AND w.profile_status='approved' AND w.profile_version=r.profile_version
  AND NOT EXISTS(SELECT 1 FROM private.burimunsi_detection_profiles active_filter WHERE active_filter.collection_id=r.collection_id)
  AND encode(sha256(convert_to(w.profile_json,'UTF8')),'hex')=r.profile_sha256
  AND encode(sha256(convert_to(jsonb_build_array(w.id,w.provider,w.status,w.profile_status,w.profile_version,w.profile_json,w.currency,w.timezone)::text,'UTF8')),'hex')=r.profile_tuple_sha256 FOR SHARE OF r,s,w;
 IF v IS NULL THEN
  SELECT jsonb_build_object('profileSha256',r.profile_sha256,'profile',jsonb_build_object(
   'provider',w.provider,'status',w.status,'profile_status','approved','profile_version',d.profile_version,
   'profile_json',d.profile_json,'currency',w.currency,'timezone',w.timezone)) INTO v
  FROM private.burimunsi_unresolved_observations r
  JOIN private.burimunsi_scopes s ON s.collection_id=r.collection_id
  JOIN app.momo_receiving_accounts w ON w.id=s.receiving_account_id
  JOIN private.burimunsi_detection_profiles d ON d.collection_id=r.collection_id
  WHERE r.source_id=p_source AND r.collection_id=p_collection AND (s.enabled OR s.active_binding_id IS NULL)
   AND w.status='active' AND d.enabled AND d.expected_receiving_account_id=w.id AND d.profile_version=r.profile_version
   AND encode(sha256(convert_to(d.profile_json,'UTF8')),'hex')=r.profile_sha256
   AND encode(sha256(convert_to(jsonb_build_array('detection_only',w.id,w.provider,w.status,w.profile_status,
    w.profile_version,w.profile_json,w.currency,w.timezone,d.revision,d.enabled,d.profile_version,d.profile_json,d.evidence_sha256)::text,'UTF8')),'hex')=r.profile_tuple_sha256
  FOR SHARE OF r,s,w,d;
 END IF;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RETURN v;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

REVOKE ALL ON FUNCTION private.burimunsi_observation_admin_actor(boolean),private.burimunsi_observation_admin_scope(text,boolean),
 private.burimunsi_observation_admin_collections(),private.burimunsi_observation_admin_rows(text),
 private.burimunsi_observation_admin_page(text,integer,integer),private.burimunsi_observation_admin_source(text,text),
 private.burimunsi_observation_admin_hint_profile(text,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_admin_collections(),
 private.burimunsi_observation_admin_page(text,integer,integer),private.burimunsi_observation_admin_source(text,text),
 private.burimunsi_observation_admin_hint_profile(text,text) TO collect_runtime;
COMMIT;
