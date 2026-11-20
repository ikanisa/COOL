-- Dynamic shared Admin receiving setup and authenticated native scope discovery.
-- Adopted proposal SHA-256: 083adda50d6aaf25bac20d763aaec1f53d86e6cdaf21d7a3862e58e5ca5d10e6
-- PROPOSAL ONLY. Root adopts a normal CLI migration and qualifies it on the
-- retained clone. Existing Collect identities/accounts/groups only; no data seed,
-- provider, ledger, pool, role or runtime activation is installed here.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$ BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.burimunsi_gateway_pair_classify(text)') IS NULL
  OR to_regclass('private.burimunsi_scope_setup_commands') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_scope_setup_install_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

CREATE TABLE private.burimunsi_scope_setup_commands(
 collection_id text NOT NULL REFERENCES app.collections(id),
 actor_id text NOT NULL REFERENCES app.users(id),request_id uuid NOT NULL,
 principal_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 operation text NOT NULL CHECK(operation IN('prepare','activate','cancelled')),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 delivery_ciphertext text,delivery_binding jsonb,created_at bigint NOT NULL,
 PRIMARY KEY(collection_id,actor_id,request_id),
 CHECK((operation IN('prepare','cancelled') AND delivery_ciphertext IS NULL AND delivery_binding IS NULL)
  OR(operation='activate' AND length(delivery_ciphertext) BETWEEN 100 AND 2048 AND jsonb_typeof(delivery_binding)='object'))
);
ALTER TABLE private.burimunsi_scope_setup_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_scope_setup_commands FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_scope_setup_commands FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE POLICY burimunsi_setup_owner ON private.burimunsi_scope_setup_commands TO postgres
 USING(collection_id=current_setting('burimunsi.collection_id',true))
 WITH CHECK(collection_id=current_setting('burimunsi.collection_id',true));
CREATE TRIGGER burimunsi_setup_retain BEFORE UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_scope_setup_commands
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_scope_setup_commands ENABLE ALWAYS TRIGGER burimunsi_setup_retain;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_scope_setup_commands
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_scope_setup_commands ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

-- Owner-only guarded windows; ordinary runtime collection RLS stays unchanged.
CREATE POLICY burimunsi_setup_scope_scan ON private.burimunsi_scopes FOR SELECT TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.scope_setup_scan',true)='1');
CREATE POLICY burimunsi_resolve_grant ON private.burimunsi_device_grants FOR SELECT TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND installation_id::text=current_setting('burimunsi.resolve_installation',true)
  AND token_hash=current_setting('burimunsi.resolve_device_hash',true));
CREATE POLICY burimunsi_resolve_scope ON private.burimunsi_scopes FOR SELECT TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND EXISTS(SELECT 1 FROM private.burimunsi_device_grants d WHERE d.collection_id=burimunsi_scopes.collection_id
   AND d.installation_id::text=current_setting('burimunsi.resolve_installation',true)
   AND d.token_hash=current_setting('burimunsi.resolve_device_hash',true)));

CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE aid text:=current_setting('collect.fence_admission_id',true);ep text:=current_setting('collect.fence_epoch',true);
 src text:=current_setting('collect.fence_source_sha256',true);
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF aid IS NULL OR aid !~ '^[a-f0-9-]{36}$' OR ep IS NULL OR ep !~ '^[1-9][0-9]{0,15}$'
  OR src IS NULL OR src !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'burimunsi_setup_unavailable' USING ERRCODE='55000';END IF;
 PERFORM private.collect_fence_assert_write(aid::uuid,ep::bigint,src);
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
END;$fn$;

REVOKE ALL ON FUNCTION private.burimunsi_setup_fence() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

CREATE FUNCTION private.burimunsi_setup_actor(p_actor text,p_cookie text,p_origin text,p_public text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE sid text;principal text;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 sid:=private.admin_invitation_actor(p_actor,p_cookie,p_origin,p_public)::text;
 principal:=private.assert_actor('receivers.manage',NULL,NULL,2,300);
 RETURN jsonb_build_object('principalId',principal,'sessionId',sid);
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_setup_actor(text,text,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

-- Serialize a missing original request with its late-arriving apply. The slot
-- records cancellation without creating a scope, wallet, grant or challenge.
CREATE FUNCTION private.burimunsi_setup_cancel(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,p_request uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;prior private.burimunsi_scope_setup_commands%ROWTYPE;result jsonb;
 old_group text:=current_setting('burimunsi.collection_id',true);
BEGIN
 actor:=private.burimunsi_setup_actor(p_actor,p_cookie,p_origin,p_public);
 IF p_request IS NULL OR NOT EXISTS(SELECT 1 FROM app.collections WHERE id=p_collection AND status='active') THEN
  RAISE EXCEPTION 'burimunsi_setup_invalid' USING ERRCODE='22023';END IF;
 BEGIN
  PERFORM set_config('burimunsi.collection_id',p_collection,true);
  SELECT * INTO prior FROM private.burimunsi_scope_setup_commands
   WHERE collection_id=p_collection AND actor_id=actor->>'principalId' AND request_id=p_request;
  IF FOUND THEN
   IF prior.principal_session_id<>actor->>'sessionId' THEN RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
   result:=prior.response;
  ELSE
   result:=jsonb_build_object('contractVersion',1,'collectionId',p_collection,'requestId',p_request,'operation','cancelled','applied',false);
   INSERT INTO private.burimunsi_scope_setup_commands(collection_id,actor_id,request_id,principal_session_id,operation,fingerprint,response,created_at)
    VALUES(p_collection,actor->>'principalId',p_request,actor->>'sessionId','cancelled',
     encode(sha256(convert_to(result::text,'UTF8')),'hex'),result,floor(extract(epoch FROM clock_timestamp())*1000)::bigint);
   INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
    VALUES(actor->>'principalId',actor->>'sessionId','burimunsi.scope.cancel','collection',p_collection,p_request::text,
     jsonb_build_object('applied',false)::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
  END IF;
 EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);RAISE;END;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);RETURN result;
END;$fn$;

-- Run only AFTER genuine shared managed-token verification/projection. The
-- header group is not consulted. One exact current principal/device grant must
-- resolve; an ambiguous cross-scope token fails closed rather than selecting one.
CREATE FUNCTION private.burimunsi_resolve_installation_scope(p_installation uuid,p_hash text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_group text:=current_setting('burimunsi.collection_id',true);
 old_install text:=current_setting('burimunsi.resolve_installation',true);old_hash text:=current_setting('burimunsi.resolve_device_hash',true);
 principal text;candidate record;chosen text;matches integer:=0;
BEGIN
 PERFORM private.burimunsi_setup_fence();principal:=private.assert_actor();
 IF p_installation IS NULL OR p_hash IS NULL OR octet_length(p_hash)<>64 OR p_hash !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
 BEGIN
  PERFORM set_config('burimunsi.resolve_installation',p_installation::text,true);
  PERFORM set_config('burimunsi.resolve_device_hash',p_hash,true);
  FOR candidate IN SELECT d.collection_id,d.id FROM private.burimunsi_device_grants d
   JOIN private.burimunsi_scopes s ON s.collection_id=d.collection_id
   JOIN app.collections c ON c.id=s.collection_id AND c.status='active'
   WHERE d.installation_id=p_installation AND d.token_hash=p_hash AND d.active AND s.enabled LOOP
   PERFORM set_config('burimunsi.collection_id',candidate.collection_id,true);
   IF EXISTS(SELECT 1 FROM private.burimunsi_device_accounts da
    JOIN private.burimunsi_accounts a ON a.id=da.account_id AND a.collection_id=da.collection_id
    JOIN private.burimunsi_device_grants d ON d.id=da.grant_id AND d.collection_id=da.collection_id
    WHERE d.id=candidate.id AND a.principal_user_id=principal AND a.active AND NOT a.removed
     AND (d.profile='staff' OR(d.profile='internal_receiver' AND a.role='admin' AND d.custodian_account_id=a.id))
     AND private.burimunsi_operator_is_current(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities)) THEN
    matches:=matches+1;chosen:=candidate.collection_id;
   END IF;
  END LOOP;
 EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
  PERFORM set_config('burimunsi.resolve_installation',coalesce(old_install,''),true);
  PERFORM set_config('burimunsi.resolve_device_hash',coalesce(old_hash,''),true);RAISE;
 END;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.resolve_installation',coalesce(old_install,''),true);
 PERFORM set_config('burimunsi.resolve_device_hash',coalesce(old_hash,''),true);
 IF matches<>1 THEN RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('collectionId',chosen);
END;$fn$;

CREATE FUNCTION private.burimunsi_setup_directory(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;old_group text:=current_setting('burimunsi.collection_id',true);old_scan text:=current_setting('burimunsi.scope_setup_scan',true);
 groups jsonb;accounts jsonb;scopes jsonb;devices jsonb:='[]';
BEGIN
 actor:=private.burimunsi_setup_actor(p_actor,p_cookie,p_origin,p_public);
 IF p_collection IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.collections WHERE id=p_collection AND status='active') THEN
  RAISE EXCEPTION 'burimunsi_scope_changed' USING ERRCODE='40001';END IF;
 IF (SELECT count(*) FROM app.collections WHERE status='active')>500
  OR (SELECT count(*) FROM app.momo_receiving_accounts WHERE status='active')>500 THEN
  RAISE EXCEPTION 'burimunsi_setup_directory_limit' USING ERRCODE='54000';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'receiverNetwork',receiver_network,
  'receiverNumber',receiver_momo_number,'version',revision) ORDER BY title,id),'[]') INTO groups FROM app.collections WHERE status='active';
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'provider',provider,'publicCode',public_code,'recipientName',recipient_name,
  'profileStatus',profile_status,'profileVersion',profile_version) ORDER BY recipient_name,id),'[]') INTO accounts
 FROM app.momo_receiving_accounts WHERE status='active';
 BEGIN
  PERFORM set_config('burimunsi.scope_setup_scan','1',true);
  SELECT coalesce(jsonb_agg(jsonb_build_object('collectionId',s.collection_id,'receivingAccountId',s.receiving_account_id,
   'enabled',s.enabled,'version',s.version,'bindingId',s.active_binding_id,'bindingVersion',s.binding_version,
   'paired',EXISTS(SELECT 1 FROM app.momo_gateway_credentials k WHERE k.binding_id=s.active_binding_id AND k.revoked_at IS NULL)) ORDER BY s.collection_id),'[]')
  INTO scopes FROM private.burimunsi_scopes s;
  PERFORM set_config('burimunsi.scope_setup_scan',coalesce(old_scan,''),true);
  IF p_collection IS NOT NULL THEN
   PERFORM set_config('burimunsi.collection_id',p_collection,true);
   SELECT coalesce(jsonb_agg(jsonb_build_object('grantId',d.id,'installationId',d.installation_id,'grantVersion',d.version,
    'custodianAccountId',a.id,'custodianName',a.name) ORDER BY a.name,d.installation_id),'[]') INTO devices
   FROM private.burimunsi_device_grants d JOIN private.burimunsi_accounts a ON a.id=d.custodian_account_id AND a.collection_id=d.collection_id
   JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.account_id=a.id AND da.collection_id=d.collection_id
   WHERE d.collection_id=p_collection AND d.active AND d.profile='internal_receiver' AND a.active AND NOT a.removed AND a.role='admin'
    AND a.principal_user_id=actor->>'principalId'
    AND private.burimunsi_operator_is_current(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities);
  END IF;
 EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
  PERFORM set_config('burimunsi.scope_setup_scan',coalesce(old_scan,''),true);RAISE;
 END;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 RETURN jsonb_build_object('contractVersion',1,'collections',groups,'accounts',accounts,'scopes',scopes,'installations',devices);
END;$fn$;

CREATE FUNCTION private.burimunsi_setup_apply(p_actor text,p_cookie text,p_origin text,p_public text,p_command jsonb,p_fingerprint text,p_delivery jsonb DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;principal text;sid text;cid text;rid uuid;operation text;expected bigint;wallet text;
 scope private.burimunsi_scopes%ROWTYPE;prior private.burimunsi_scope_setup_commands%ROWTYPE;
 device private.burimunsi_device_grants%ROWTYPE;native private.burimunsi_accounts%ROWTYPE;
 binding text;pairing text;response jsonb;subscription bigint;at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 old_group text:=current_setting('burimunsi.collection_id',true);renew boolean:=false;
BEGIN
 actor:=private.burimunsi_setup_actor(p_actor,p_cookie,p_origin,p_public);principal:=actor->>'principalId';sid:=actor->>'sessionId';
 IF jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$'
  OR NOT(p_command ?& ARRAY['operation','requestId','collectionId','expectedScopeVersion','receivingAccountId','reason'])
  OR p_command->>'operation' IS NULL OR p_command->>'operation' NOT IN('prepare','activate') OR p_command->>'collectionId' IS NULL
  OR p_command->>'reason' IS NULL OR length(p_command->>'reason') NOT BETWEEN 8 AND 500
  OR p_command->>'reason' ~ '[[:cntrl:]]' OR p_command->>'reason' ~* '[a-f0-9]{64}'
  OR btrim(p_command->>'reason') IS DISTINCT FROM p_command->>'reason'
  OR jsonb_typeof(p_command->'expectedScopeVersion') IS DISTINCT FROM 'number'
  OR (SELECT count(*) FROM jsonb_object_keys(p_command))<>(CASE WHEN p_command->>'operation'='prepare' THEN 6 ELSE 11 END)
  OR(p_command->>'operation'='activate' AND NOT(p_command ?& ARRAY['installationId','grantId','custodianAccountId','expectedGrantVersion','subscriptionId']))
  THEN RAISE EXCEPTION 'burimunsi_setup_invalid' USING ERRCODE='22023';END IF;
 cid:=p_command->>'collectionId';rid:=(p_command->>'requestId')::uuid;operation:=p_command->>'operation';
 expected:=(p_command->>'expectedScopeVersion')::bigint;wallet:=p_command->>'receivingAccountId';
 IF rid IS NULL OR expected<0 OR expected>=9007199254740991 THEN RAISE EXCEPTION 'burimunsi_setup_invalid' USING ERRCODE='22023';END IF;
 BEGIN
  PERFORM set_config('burimunsi.collection_id',cid,true);
  SELECT * INTO prior FROM private.burimunsi_scope_setup_commands WHERE collection_id=cid AND actor_id=principal AND request_id=rid;
  IF FOUND THEN
   IF prior.principal_session_id<>sid OR prior.fingerprint<>p_fingerprint OR prior.operation<>operation THEN
    RAISE EXCEPTION 'burimunsi_setup_request_conflict' USING ERRCODE='23505';END IF;
   response:=prior.response;
  ELSE
   -- Match the already approved Collect payment destination. This command never
   -- changes that destination or creates another financial account/ledger.
   IF NOT EXISTS(SELECT 1 FROM app.collections c JOIN app.momo_receiving_accounts a ON a.id=wallet
    WHERE c.id=cid AND c.status='active' AND a.status='active' AND c.receiver_network=a.provider
     AND CASE WHEN c.receiver_momo_number ~ '^07[2389][0-9]{7}$' THEN '250'||substr(c.receiver_momo_number,2)
      ELSE regexp_replace(c.receiver_momo_number,'^\+','') END
      =CASE WHEN a.public_code ~ '^07[2389][0-9]{7}$' THEN '250'||substr(a.public_code,2)
       ELSE regexp_replace(a.public_code,'^\+','') END) THEN
    RAISE EXCEPTION 'burimunsi_receiver_mismatch' USING ERRCODE='40001';END IF;
   SELECT * INTO scope FROM private.burimunsi_scopes WHERE collection_id=cid FOR UPDATE;
   IF (FOUND AND scope.version<>expected) OR (NOT FOUND AND expected<>0) THEN RAISE EXCEPTION 'burimunsi_scope_changed' USING ERRCODE='40001';END IF;
   IF operation='prepare' THEN
    IF p_delivery IS NOT NULL OR (scope.collection_id IS NOT NULL AND(scope.enabled OR scope.active_binding_id IS NOT NULL)) THEN
     RAISE EXCEPTION 'gateway_handoff_unavailable' USING ERRCODE='55000';END IF;
    INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at)
     VALUES(cid,wallet,false,at_ms) ON CONFLICT(collection_id) DO UPDATE SET receiving_account_id=EXCLUDED.receiving_account_id,version=burimunsi_scopes.version+1;
   ELSE
    IF scope.collection_id IS NULL OR scope.receiving_account_id<>wallet THEN RAISE EXCEPTION 'burimunsi_scope_changed' USING ERRCODE='40001';END IF;
    subscription:=(p_command->>'subscriptionId')::bigint;
    IF subscription IS NULL OR subscription NOT BETWEEN 0 AND 2147483646 OR jsonb_typeof(p_delivery) IS DISTINCT FROM 'object'
     OR NOT(p_delivery ?& ARRAY['bindingId','pairingId','codeHash','ciphertext','binding'])
     OR (SELECT count(*) FROM jsonb_object_keys(p_delivery))<>5
     OR p_delivery->>'codeHash' IS NULL OR octet_length(p_delivery->>'codeHash')<>64 OR p_delivery->>'codeHash' !~ '^[a-f0-9]{64}$'
     OR p_delivery->>'ciphertext' IS NULL OR length(p_delivery->>'ciphertext') NOT BETWEEN 100 AND 2048 THEN
     RAISE EXCEPTION 'burimunsi_setup_invalid' USING ERRCODE='22023';END IF;
    -- The retained encrypted delivery must describe this exact owner/session
    -- and public intent. A malformed handoff fails before binding creation.
    IF jsonb_typeof(p_delivery->'binding') IS DISTINCT FROM 'object'
     OR octet_length(p_delivery->'binding'->>'profileSha') IS DISTINCT FROM 64
     OR (p_delivery->'binding'->>'profileSha') !~ '^[a-f0-9]{64}$'
     OR ((p_delivery->'binding')-'profileSha') IS DISTINCT FROM jsonb_build_object(
      'actorId',principal,'sessionId',sid,'collectionId',cid,'requestId',rid::text,'receivingAccountId',wallet,
      'expectedScopeVersion',expected,'bindingId',p_delivery->>'bindingId','pairingId',p_delivery->>'pairingId',
      'installationId',p_command->>'installationId','custodianAccountId',p_command->>'custodianAccountId',
      'grantId',p_command->>'grantId','grantVersion',(p_command->>'expectedGrantVersion')::bigint,'subscriptionId',subscription) THEN
     RAISE EXCEPTION 'burimunsi_setup_invalid' USING ERRCODE='22023';END IF;
    SELECT * INTO device FROM private.burimunsi_device_grants WHERE collection_id=cid
     AND installation_id=(p_command->>'installationId')::uuid AND id=(p_command->>'grantId')::uuid FOR SHARE;
    IF NOT FOUND OR NOT device.active OR device.profile<>'internal_receiver' OR device.version<>(p_command->>'expectedGrantVersion')::bigint
     OR device.custodian_account_id<>(p_command->>'custodianAccountId')::uuid THEN RAISE EXCEPTION 'burimunsi_scope_changed' USING ERRCODE='40001';END IF;
    SELECT * INTO native FROM private.burimunsi_accounts WHERE collection_id=cid AND id=device.custodian_account_id FOR SHARE;
    IF NOT FOUND OR NOT native.active OR native.removed OR native.role<>'admin' OR native.principal_user_id<>principal
     OR NOT private.burimunsi_operator_is_current(cid,native.principal_user_id,native.phone,native.role,native.capabilities)
     OR NOT EXISTS(SELECT 1 FROM private.burimunsi_device_accounts WHERE collection_id=cid AND grant_id=device.id AND account_id=native.id) THEN
     RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
    binding:=p_delivery->>'bindingId';pairing:=p_delivery->>'pairingId';
    IF scope.active_binding_id IS NOT NULL THEN
     -- Recover an UNPAIRED initial setup only. A working credential/phone is
     -- never replaced by this flow, even if its local pending count looks zero.
     IF EXISTS(SELECT 1 FROM app.momo_gateway_credentials WHERE binding_id=scope.active_binding_id)
      OR binding IS DISTINCT FROM scope.active_binding_id
      OR NOT EXISTS(SELECT 1 FROM app.momo_gateway_bindings WHERE id=scope.active_binding_id AND owner_user_id=principal
       AND receiving_account_id=wallet AND status='active' AND subscription_evidence::jsonb=jsonb_build_object('subscription_id',subscription)) THEN
      RAISE EXCEPTION 'gateway_handoff_unavailable' USING ERRCODE='55000';END IF;
     binding:=scope.active_binding_id;renew:=true;
    END IF;
    IF EXISTS(SELECT 1 FROM app.momo_gateway_bindings WHERE receiving_account_id=wallet AND status='active' AND id<>binding) THEN
     RAISE EXCEPTION 'gateway_handoff_unavailable' USING ERRCODE='55000';END IF;
    IF NOT renew THEN
     INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,subscription_evidence,created_at)
      VALUES(binding,principal,wallet,jsonb_build_object('subscription_id',subscription)::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
    ELSE UPDATE app.momo_gateway_pairings SET expires_at=least(expires_at,app.unixepoch()-1) WHERE binding_id=binding;END IF;
    INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,created_at)
     VALUES(pairing,binding,p_delivery->>'codeHash',sid,app.unixepoch()+600,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
    UPDATE private.burimunsi_scopes SET active_binding_id=binding,binding_version=1,enabled=true,version=version+1
     WHERE collection_id=cid AND version=expected;
   END IF;
   SELECT * INTO STRICT scope FROM private.burimunsi_scopes WHERE collection_id=cid;
   response:=jsonb_build_object('contractVersion',1,'requestId',rid,'collectionId',cid,'operation',operation,
    'receivingAccountId',wallet,'scopeVersion',scope.version,'enabled',scope.enabled,'bindingId',scope.active_binding_id);
   IF operation='activate' THEN
    response:=response||jsonb_build_object('pairingId',pairing,'bindingVersion',1,'installationId',device.installation_id,
     'custodianAccountId',native.id,'grantId',device.id,'grantVersion',device.version,'subscriptionId',subscription,
     'deliveryExpiresAt',(app.unixepoch()+600)*1000);
   END IF;
   INSERT INTO private.burimunsi_scope_setup_commands(collection_id,actor_id,request_id,principal_session_id,operation,fingerprint,response,delivery_ciphertext,delivery_binding,created_at)
    VALUES(cid,principal,rid,sid,operation,p_fingerprint,response,p_delivery->>'ciphertext',p_delivery->'binding',at_ms);
   INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
    VALUES(principal,sid,'burimunsi.scope.'||operation,'collection',cid,rid::text,
     jsonb_build_object('reason',p_command->>'reason','receiving_account_id',wallet,'scope_version',scope.version,'binding_id',scope.active_binding_id)::text,
     app.strftime('%Y-%m-%dT%H:%M:%fZ'));
  END IF;
 EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);RAISE;END;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);RETURN response;
END;$fn$;

CREATE FUNCTION private.burimunsi_setup_lookup(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,p_request uuid,p_delivery boolean DEFAULT false)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;prior private.burimunsi_scope_setup_commands%ROWTYPE;result jsonb;old_group text:=current_setting('burimunsi.collection_id',true);
BEGIN
 actor:=private.burimunsi_setup_actor(p_actor,p_cookie,p_origin,p_public);
 BEGIN
  PERFORM set_config('burimunsi.collection_id',p_collection,true);
  SELECT * INTO prior FROM private.burimunsi_scope_setup_commands
   WHERE collection_id=p_collection AND actor_id=actor->>'principalId' AND request_id=p_request;
  result:=jsonb_build_object('contractVersion',1,'collectionId',p_collection,'requestId',p_request,'found',FOUND);
  IF FOUND THEN
   IF prior.principal_session_id<>actor->>'sessionId' THEN RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
   result:=result||jsonb_build_object('receipt',prior.response,'fingerprint',prior.fingerprint);
   IF p_delivery THEN
    IF prior.operation<>'activate' OR (prior.response->>'deliveryExpiresAt')::bigint<=floor(extract(epoch FROM clock_timestamp())*1000)
     OR NOT EXISTS(SELECT 1 FROM private.burimunsi_scopes s JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id
      JOIN app.momo_gateway_pairings p ON p.binding_id=b.id
      JOIN private.burimunsi_device_grants d ON d.id=(prior.response->>'grantId')::uuid AND d.collection_id=s.collection_id
      JOIN private.burimunsi_accounts n ON n.id=d.custodian_account_id AND n.collection_id=s.collection_id
      WHERE s.collection_id=p_collection AND s.enabled AND s.active_binding_id=prior.response->>'bindingId'
       AND p.id=prior.response->>'pairingId' AND p.originating_session_id=actor->>'sessionId'
       AND (p.claimed_installation_id IS NULL OR p.claimed_installation_id=prior.response->>'installationId')
       AND p.expires_at>app.unixepoch() AND b.status='active' AND b.owner_user_id=actor->>'principalId'
       AND b.receiving_account_id=prior.response->>'receivingAccountId' AND s.receiving_account_id=b.receiving_account_id
       AND b.version=s.binding_version AND b.version=(prior.response->>'bindingVersion')::bigint
       AND d.active AND d.version=(prior.response->>'grantVersion')::bigint AND d.installation_id=(prior.response->>'installationId')::uuid
       AND d.profile='internal_receiver' AND d.custodian_account_id=(prior.response->>'custodianAccountId')::uuid
       AND n.active AND NOT n.removed AND n.role='admin' AND n.principal_user_id=actor->>'principalId'
       AND EXISTS(SELECT 1 FROM private.burimunsi_device_accounts da WHERE da.collection_id=p_collection AND da.grant_id=d.id AND da.account_id=n.id)
       AND private.burimunsi_operator_is_current(n.collection_id,n.principal_user_id,n.phone,n.role,n.capabilities)) THEN
     RAISE EXCEPTION 'burimunsi_setup_delivery_expired' USING ERRCODE='41000';END IF;
    result:=result||jsonb_build_object('ciphertext',prior.delivery_ciphertext,'binding',prior.delivery_binding,
     'codeHash',(SELECT code_sha256 FROM app.momo_gateway_pairings WHERE id=prior.response->>'pairingId'));
   END IF;
  ELSIF p_delivery THEN RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
 EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);RAISE;END;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);RETURN result;
END;$fn$;

REVOKE ALL ON FUNCTION private.burimunsi_resolve_installation_scope(uuid,text),private.burimunsi_setup_directory(text,text,text,text,text),
 private.burimunsi_setup_apply(text,text,text,text,jsonb,text,jsonb),private.burimunsi_setup_lookup(text,text,text,text,text,uuid,boolean),
 private.burimunsi_setup_cancel(text,text,text,text,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_resolve_installation_scope(uuid,text),private.burimunsi_setup_directory(text,text,text,text,text),
 private.burimunsi_setup_apply(text,text,text,text,jsonb,text,jsonb),private.burimunsi_setup_lookup(text,text,text,text,text,uuid,boolean),
 private.burimunsi_setup_cancel(text,text,text,text,text,uuid) TO collect_runtime;
COMMIT;
