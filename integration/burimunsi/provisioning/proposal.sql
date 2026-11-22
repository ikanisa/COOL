-- PROPOSAL ONLY. Root must create the real migration with the installed
-- Supabase CLI, qualify on the retained native clone, review/lock and deploy.
-- No identity, approval, PIN, device, scope, wallet or financial data is seeded.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $check$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.burimunsi_operator_is_current(text,text,text,text,text[])') IS NULL
  OR to_regclass('private.burimunsi_provisioning_commands') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_provisioning_install_precondition' USING ERRCODE='55000';
 END IF;
END;$check$;

-- One native credential account per existing shared principal and group. If
-- historical duplicates exist, installation fails; no row is selected/merged.
CREATE UNIQUE INDEX burimunsi_provisioning_one_principal_per_scope
 ON private.burimunsi_accounts(collection_id,principal_user_id);
CREATE FUNCTION private.burimunsi_provisioning_account_identity() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF (NEW.id,NEW.collection_id,NEW.principal_user_id,NEW.created_at)
  IS DISTINCT FROM (OLD.id,OLD.collection_id,OLD.principal_user_id,OLD.created_at) THEN
  RAISE EXCEPTION 'burimunsi_native_principal_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_provisioning_account_identity()
 FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
CREATE TRIGGER burimunsi_provisioning_account_identity BEFORE UPDATE ON private.burimunsi_accounts
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_provisioning_account_identity();
ALTER TABLE private.burimunsi_accounts ENABLE ALWAYS TRIGGER burimunsi_provisioning_account_identity;

-- Immutable owner outcome and time-bounded encrypted delivery custody only.
-- The active device grant retains SHA256(token), never a recoverable token.
CREATE TABLE private.burimunsi_provisioning_commands(
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 actor_id text NOT NULL REFERENCES app.users(id),
 request_id uuid NOT NULL,
 principal_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 operation text NOT NULL CHECK(operation IN('set_pin','grant_installation','revoke_installation','cancelled')),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 delivery_ciphertext text,
 delivery_expires_at bigint,
 created_at bigint NOT NULL CHECK(created_at>=0),
 PRIMARY KEY(collection_id,actor_id,request_id),
 CHECK((operation='grant_installation' AND delivery_ciphertext IS NOT NULL AND delivery_expires_at IS NOT NULL
   AND length(delivery_ciphertext) BETWEEN 100 AND 2048 AND delivery_expires_at=created_at+900000)
  OR (operation<>'grant_installation' AND delivery_ciphertext IS NULL AND delivery_expires_at IS NULL))
);
ALTER TABLE private.burimunsi_provisioning_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_provisioning_commands FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_provisioning_commands FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
CREATE POLICY burimunsi_provisioning_owner ON private.burimunsi_provisioning_commands TO postgres
 USING(collection_id=current_setting('burimunsi.collection_id',true))
 WITH CHECK(collection_id=current_setting('burimunsi.collection_id',true));
CREATE TRIGGER burimunsi_provisioning_retain BEFORE UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_provisioning_commands
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_provisioning_commands ENABLE ALWAYS TRIGGER burimunsi_provisioning_retain;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_provisioning_commands
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_provisioning_commands ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

CREATE FUNCTION private.burimunsi_provisioning_directory(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE accounts jsonb;grants jsonb;scope private.burimunsi_scopes%ROWTYPE;ready boolean;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM private.admin_invitation_actor(p_actor,p_cookie,p_origin,p_public);
 IF p_collection IS DISTINCT FROM current_setting('burimunsi.collection_id',true) THEN
  RAISE EXCEPTION 'burimunsi_provisioning_denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO scope FROM private.burimunsi_scopes WHERE collection_id=p_collection FOR SHARE;
 ready:=FOUND AND EXISTS(SELECT 1 FROM app.collections c JOIN app.momo_receiving_accounts r ON r.id=scope.receiving_account_id
  WHERE c.id=p_collection AND c.status='active' AND r.status='active');
 IF (SELECT count(*) FROM private.burimunsi_operator_approvals WHERE collection_id=p_collection)>500
  OR (SELECT count(*) FROM private.burimunsi_device_grants WHERE collection_id=p_collection)>500 THEN
  RAISE EXCEPTION 'burimunsi_provisioning_directory_limit' USING ERRCODE='54000';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('principalId',o.principal_user_id,'accountId',n.id,
  'phone',o.phone,'name',left(coalesce(nullif(btrim(a.display_name),''),a.email),100),'role',o.role,
  'capabilities',o.capabilities,'approvalVersion',o.version,
  'approved',coalesce(private.burimunsi_operator_is_current(o.collection_id,o.principal_user_id,o.phone,o.role,o.capabilities),false),
  'version',coalesce(n.version,0),'credentialVersion',coalesce(n.credential_version,0),
  'active',coalesce(n.active,false),'removed',coalesce(n.removed,false)) ORDER BY a.email),'[]'::jsonb)
 INTO accounts FROM private.burimunsi_operator_approvals o
 JOIN app.admin_users a ON a.id=o.admin_user_id
 LEFT JOIN private.burimunsi_accounts n ON n.collection_id=o.collection_id AND n.principal_user_id=o.principal_user_id
 WHERE o.collection_id=p_collection;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',d.id,'accountId',d.custodian_account_id,
  'installationId',d.installation_id,'profile',d.profile,'active',d.active,'version',d.version)
  ORDER BY d.created_at,d.id),'[]'::jsonb) INTO grants
 FROM private.burimunsi_device_grants d WHERE d.collection_id=p_collection;
 RETURN jsonb_build_object('contractVersion',1,'collectionId',p_collection,'configured',coalesce(ready,false),
  'scopeVersion',scope.version,'scopeEnabled',coalesce(scope.enabled,false),'accounts',accounts,'grants',grants);
END;$fn$;

CREATE FUNCTION private.burimunsi_provisioning_lookup(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE principal text;sid text;prior private.burimunsi_provisioning_commands%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 sid:=private.admin_invitation_actor(p_actor,p_cookie,p_origin,p_public)::text;principal:=api.current_principal_id();
 IF p_collection IS DISTINCT FROM current_setting('burimunsi.collection_id',true) OR p_request IS NULL THEN
  RAISE EXCEPTION 'burimunsi_provisioning_denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO prior FROM private.burimunsi_provisioning_commands
  WHERE collection_id=p_collection AND actor_id=principal AND request_id=p_request;
 IF NOT FOUND THEN RETURN jsonb_build_object('contractVersion',1,'collectionId',p_collection,'requestId',p_request,'found',false);END IF;
 IF prior.principal_session_id<>sid THEN
  RAISE EXCEPTION 'burimunsi_provisioning_request_conflict' USING ERRCODE='23505';
 END IF;
 RETURN jsonb_build_object('contractVersion',1,'collectionId',p_collection,'requestId',p_request,'found',true,'receipt',prior.response);
END;$fn$;

-- A PIN is never retained in the browser checkpoint. When its original request
-- has no receipt, this owner-only tombstone settles that key under the writer
-- lock. A late original request then cannot issue a different/lost credential.
CREATE FUNCTION private.burimunsi_provisioning_cancel(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE principal text;sid text;prior private.burimunsi_provisioning_commands%ROWTYPE;result jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 sid:=private.admin_invitation_actor(p_actor,p_cookie,p_origin,p_public)::text;principal:=api.current_principal_id();
 IF p_collection IS DISTINCT FROM current_setting('burimunsi.collection_id',true) OR p_request IS NULL THEN
  RAISE EXCEPTION 'burimunsi_provisioning_denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO prior FROM private.burimunsi_provisioning_commands
  WHERE collection_id=p_collection AND actor_id=principal AND request_id=p_request;
 IF FOUND THEN
  IF prior.principal_session_id<>sid THEN RAISE EXCEPTION 'burimunsi_provisioning_request_conflict' USING ERRCODE='23505';END IF;
  RETURN prior.response;
 END IF;
 result:=jsonb_build_object('contractVersion',1,'collectionId',p_collection,'requestId',p_request,'operation','cancelled','applied',false);
 INSERT INTO private.burimunsi_provisioning_commands(collection_id,actor_id,request_id,principal_session_id,operation,fingerprint,response,created_at)
  VALUES(p_collection,principal,p_request,sid,'cancelled',repeat('0',64),result,floor(extract(epoch FROM clock_timestamp())*1000)::bigint);
 RETURN result;
END;$fn$;

CREATE FUNCTION private.burimunsi_provisioning_apply(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,
 p_command jsonb,p_fingerprint text,p_ciphertext text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE principal text;sid text;request_uuid uuid;operation text;target text;expected bigint;approval_version bigint;
 approval private.burimunsi_operator_approvals%ROWTYPE;account private.burimunsi_accounts%ROWTYPE;
 grant_row private.burimunsi_device_grants%ROWTYPE;scope private.burimunsi_scopes%ROWTYPE;
 prior private.burimunsi_provisioning_commands%ROWTYPE;result jsonb;record jsonb;
 account_uuid uuid;grant_uuid uuid;installation_uuid uuid;grant_expected bigint;at_ms bigint;
 display_name text;keys_count integer;expiry bigint;new_version bigint;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 sid:=private.admin_invitation_actor(p_actor,p_cookie,p_origin,p_public)::text;principal:=api.current_principal_id();
 IF p_collection IS DISTINCT FROM current_setting('burimunsi.collection_id',true)
  OR jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$'
  OR p_command->>'requestId' IS NULL OR p_command->>'operation' NOT IN('set_pin','grant_installation','revoke_installation') THEN
  RAISE EXCEPTION 'burimunsi_provisioning_invalid' USING ERRCODE='22023';
 END IF;
 request_uuid:=(p_command->>'requestId')::uuid;operation:=p_command->>'operation';
 SELECT * INTO prior FROM private.burimunsi_provisioning_commands
  WHERE collection_id=p_collection AND actor_id=principal AND request_id=request_uuid;
 IF FOUND THEN
  IF prior.principal_session_id<>sid OR prior.operation<>operation OR prior.fingerprint<>p_fingerprint THEN
   RAISE EXCEPTION 'burimunsi_provisioning_request_conflict' USING ERRCODE='23505';
  END IF;
  RETURN prior.response;
 END IF;
 SELECT count(*) INTO keys_count FROM jsonb_object_keys(p_command);
 IF NOT(p_command ?& ARRAY['requestId','collectionId','scopeVersion','principalId','approvalVersion','expectedAccountVersion','reason','operation'])
  OR p_command->>'collectionId' IS DISTINCT FROM p_collection
  OR jsonb_typeof(p_command->'scopeVersion') IS DISTINCT FROM 'number'
  OR jsonb_typeof(p_command->'approvalVersion') IS DISTINCT FROM 'number'
  OR jsonb_typeof(p_command->'expectedAccountVersion') IS DISTINCT FROM 'number'
  OR jsonb_typeof(p_command->'reason') IS DISTINCT FROM 'string'
  OR length(p_command->>'reason') NOT BETWEEN 8 AND 300 OR p_command->>'reason' ~ '[[:cntrl:]]'
  OR p_command->>'reason' ~* '[a-f0-9]{64}'
  OR btrim(p_command->>'reason') IS DISTINCT FROM p_command->>'reason'
  OR (operation='set_pin' AND (keys_count<>10 OR NOT(p_command ?& ARRAY['pinHash','accountId']) OR p_ciphertext IS NOT NULL))
  OR (operation='grant_installation' AND (keys_count<>14 OR NOT(p_command ?& ARRAY['accountId','grantId','installationId','profile','expectedGrantVersion','tokenHash'])
    OR p_ciphertext IS NULL OR length(p_ciphertext) NOT BETWEEN 100 AND 2048))
  OR (operation='revoke_installation' AND (keys_count<>13 OR NOT(p_command ?& ARRAY['accountId','grantId','installationId','profile','expectedGrantVersion']) OR p_ciphertext IS NOT NULL)) THEN
  RAISE EXCEPTION 'burimunsi_provisioning_invalid' USING ERRCODE='22023';
 END IF;
 target:=p_command->>'principalId';expected:=(p_command->>'expectedAccountVersion')::bigint;
 approval_version:=(p_command->>'approvalVersion')::bigint;
 IF target IS NULL OR expected NOT BETWEEN 0 AND 9007199254740990 OR approval_version NOT BETWEEN 1 AND 9007199254740991 THEN
  RAISE EXCEPTION 'burimunsi_provisioning_invalid' USING ERRCODE='22023';
 END IF;
 SELECT * INTO scope FROM private.burimunsi_scopes WHERE collection_id=p_collection FOR SHARE;
 IF NOT FOUND OR scope.version<>(p_command->>'scopeVersion')::bigint THEN
  RAISE EXCEPTION 'burimunsi_provisioning_changed' USING ERRCODE='40001';
 END IF;
 IF operation<>'revoke_installation' AND NOT EXISTS(SELECT 1 FROM app.collections c
  JOIN app.momo_receiving_accounts r ON r.id=scope.receiving_account_id
  WHERE c.id=p_collection AND c.status='active' AND r.status='active') THEN
  RAISE EXCEPTION 'burimunsi_provisioning_denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO approval FROM private.burimunsi_operator_approvals
  WHERE collection_id=p_collection AND principal_user_id=target FOR SHARE;
 IF NOT FOUND OR approval.version<>approval_version THEN
  RAISE EXCEPTION 'burimunsi_provisioning_changed' USING ERRCODE='40001';
 END IF;
 IF operation<>'revoke_installation' AND NOT coalesce(private.burimunsi_operator_is_current(
  approval.collection_id,approval.principal_user_id,approval.phone,approval.role,approval.capabilities),false) THEN
  RAISE EXCEPTION 'burimunsi_provisioning_denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO account FROM private.burimunsi_accounts WHERE collection_id=p_collection AND principal_user_id=target FOR UPDATE;
 IF (FOUND AND (account.version<>expected OR account.version>=9007199254740991 OR
   operation<>'revoke_installation' AND account.removed)) OR (NOT FOUND AND (expected<>0 OR operation<>'set_pin')) THEN
  RAISE EXCEPTION 'burimunsi_provisioning_changed' USING ERRCODE='40001';
 END IF;
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 IF operation='set_pin' THEN
  record:=p_command->'pinHash';
  IF jsonb_typeof(record) IS DISTINCT FROM 'object' OR (SELECT count(*) FROM jsonb_object_keys(record))<>5
   OR NOT(record ?& ARRAY['algorithm','pepperId','iterations','salt','hash']) THEN
   RAISE EXCEPTION 'burimunsi_provisioning_invalid' USING ERRCODE='22023';
  END IF;
  IF record->>'algorithm' IS DISTINCT FROM 'pbkdf2-sha256+hmac-v1'
   OR record->>'pepperId' IS NULL OR record->>'pepperId' !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'
   OR jsonb_typeof(record->'iterations') IS DISTINCT FROM 'number' OR (record->>'iterations')::bigint NOT BETWEEN 600000 AND 2000000
   OR record->>'salt' IS NULL OR record->>'salt' !~ '^[a-f0-9]{32}$' OR record->>'hash' IS NULL OR record->>'hash' !~ '^[a-f0-9]{64}$' THEN
   RAISE EXCEPTION 'burimunsi_provisioning_invalid' USING ERRCODE='22023';
  END IF;
  IF account.id IS NULL THEN
   account_uuid:=(p_command->>'accountId')::uuid;
   SELECT left(coalesce(nullif(btrim(a.display_name),''),a.email),100) INTO display_name
    FROM app.admin_users a WHERE a.id=approval.admin_user_id;
   INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,active,removed,credential_version,version,created_at,updated_at)
    VALUES(account_uuid,p_collection,target,approval.phone,display_name,approval.role,approval.capabilities,record,true,false,1,1,at_ms,at_ms)
    RETURNING * INTO account;
  ELSE
   IF account.credential_version>=9007199254740991 THEN RAISE EXCEPTION 'burimunsi_provisioning_changed' USING ERRCODE='40001';END IF;
   UPDATE private.burimunsi_accounts SET pin_hash=record,phone=approval.phone,role=approval.role,capabilities=approval.capabilities,
    active=true,credential_version=credential_version+1,version=version+1,updated_at=at_ms
    WHERE collection_id=p_collection AND id=account.id RETURNING * INTO account;
  END IF;
  UPDATE private.burimunsi_sessions SET revoked=true WHERE collection_id=p_collection AND account_id=account.id AND NOT revoked;
 ELSE
  IF account.id IS DISTINCT FROM (p_command->>'accountId')::uuid OR account.version<>expected THEN
   RAISE EXCEPTION 'burimunsi_provisioning_changed' USING ERRCODE='40001';
  END IF;
  IF operation='grant_installation' AND (NOT account.active OR account.removed OR account.phone<>approval.phone OR account.role<>approval.role
   OR NOT(account.capabilities <@ approval.capabilities) OR p_command->>'profile'='internal_receiver' AND account.role<>'admin') THEN
   RAISE EXCEPTION 'burimunsi_provisioning_denied' USING ERRCODE='42501';
  END IF;
  installation_uuid:=(p_command->>'installationId')::uuid;grant_uuid:=(p_command->>'grantId')::uuid;
  IF jsonb_typeof(p_command->'expectedGrantVersion') IS DISTINCT FROM 'number' OR
   p_command->>'profile' IS NULL OR p_command->>'profile' NOT IN('staff','internal_receiver') THEN
   RAISE EXCEPTION 'burimunsi_provisioning_invalid' USING ERRCODE='22023';
  END IF;
  grant_expected:=(p_command->>'expectedGrantVersion')::bigint;
  IF grant_expected NOT BETWEEN 0 AND 9007199254740990 OR installation_uuid IS NULL OR grant_uuid IS NULL THEN
   RAISE EXCEPTION 'burimunsi_provisioning_invalid' USING ERRCODE='22023';
  END IF;
  SELECT * INTO grant_row FROM private.burimunsi_device_grants
   WHERE collection_id=p_collection AND installation_id=installation_uuid FOR UPDATE;
  IF FOUND THEN
   IF grant_row.id<>grant_uuid OR grant_row.version<>grant_expected OR grant_row.profile<>p_command->>'profile'
    OR grant_row.custodian_account_id IS DISTINCT FROM account.id
    OR EXISTS(SELECT 1 FROM private.burimunsi_device_accounts da WHERE da.collection_id=p_collection AND da.grant_id=grant_row.id AND da.account_id<>account.id) THEN
    RAISE EXCEPTION 'burimunsi_provisioning_changed' USING ERRCODE='40001';
   END IF;
  ELSIF grant_expected<>0 OR operation<>'grant_installation' THEN
   RAISE EXCEPTION 'burimunsi_provisioning_changed' USING ERRCODE='40001';
  END IF;
  new_version:=grant_expected+1;
  IF operation='grant_installation' THEN
   IF p_command->>'tokenHash' IS NULL OR p_command->>'tokenHash' !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'burimunsi_provisioning_invalid' USING ERRCODE='22023';
   END IF;
   IF grant_row.id IS NULL THEN
    INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,active,version,created_at)
     VALUES(grant_uuid,p_collection,installation_uuid,p_command->>'tokenHash',p_command->>'profile',account.id,true,1,at_ms);
   ELSE
    UPDATE private.burimunsi_device_grants SET token_hash=p_command->>'tokenHash',active=true,version=new_version
     WHERE collection_id=p_collection AND id=grant_uuid;
   END IF;
   INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
    VALUES(grant_uuid,account.id,p_collection) ON CONFLICT(grant_id,account_id) DO NOTHING;
   expiry:=at_ms+900000;
  ELSE
   UPDATE private.burimunsi_device_grants SET active=false,version=new_version WHERE collection_id=p_collection AND id=grant_uuid;
   expiry:=NULL;
  END IF;
  UPDATE private.burimunsi_sessions SET revoked=true WHERE collection_id=p_collection AND grant_id=grant_uuid AND NOT revoked;
 END IF;
 result:=jsonb_build_object('contractVersion',1,'requestId',request_uuid,'collectionId',p_collection,'operation',operation,
  'principalId',target,'accountId',account.id,'accountVersion',account.version,'credentialVersion',account.credential_version,
  'approvalVersion',approval.version,'scopeVersion',scope.version,'applied',true);
 IF operation<>'set_pin' THEN result:=result||jsonb_build_object('grantId',grant_uuid,'installationId',installation_uuid,
  'profile',p_command->>'profile','grantVersion',new_version,'active',operation='grant_installation','deliveryExpiresAt',expiry);END IF;
 INSERT INTO private.burimunsi_provisioning_commands(collection_id,actor_id,request_id,principal_session_id,operation,fingerprint,response,delivery_ciphertext,delivery_expires_at,created_at)
  VALUES(p_collection,principal,request_uuid,sid,operation,p_fingerprint,result,p_ciphertext,expiry,at_ms);
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
  VALUES(principal,sid,'burimunsi.native.'||operation,'user',target,request_uuid::text,
   (jsonb_build_object('collection_id',p_collection,'account_id',account.id,'account_version',account.version,
    'approval_version',approval.version,'scope_version',scope.version,'reason',p_command->>'reason')||
    CASE WHEN operation='set_pin' THEN '{}'::jsonb ELSE jsonb_build_object('grant_id',grant_uuid,'grant_version',new_version,
     'installation_id',installation_uuid,'profile',p_command->>'profile') END)::text,
   to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
 RETURN result;
END;$fn$;

CREATE FUNCTION private.burimunsi_provisioning_delivery(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,
 p_request uuid,p_installation uuid,p_profile text,p_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE principal text;sid text;prior private.burimunsi_provisioning_commands%ROWTYPE;token_digest text;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 sid:=private.admin_invitation_actor(p_actor,p_cookie,p_origin,p_public)::text;principal:=api.current_principal_id();
 IF p_collection IS DISTINCT FROM current_setting('burimunsi.collection_id',true) THEN
  RAISE EXCEPTION 'burimunsi_provisioning_denied' USING ERRCODE='42501';
 END IF;
 SELECT * INTO prior FROM private.burimunsi_provisioning_commands
  WHERE collection_id=p_collection AND actor_id=principal AND request_id=p_request;
 IF NOT FOUND OR prior.principal_session_id<>sid OR prior.operation<>'grant_installation'
  OR prior.delivery_expires_at<=floor(extract(epoch FROM clock_timestamp())*1000)::bigint
  OR prior.response->>'installationId' IS DISTINCT FROM p_installation::text
  OR prior.response->>'profile' IS DISTINCT FROM p_profile
  OR (prior.response->>'grantVersion')::bigint IS DISTINCT FROM p_version THEN
  RAISE EXCEPTION 'burimunsi_delivery_expired' USING ERRCODE='42501';
 END IF;
 SELECT d.token_hash INTO token_digest FROM private.burimunsi_device_grants d
 JOIN private.burimunsi_accounts a ON a.collection_id=d.collection_id AND a.id=d.custodian_account_id
 JOIN private.burimunsi_device_accounts da ON da.collection_id=d.collection_id AND da.grant_id=d.id AND da.account_id=a.id
 JOIN private.burimunsi_operator_approvals o ON o.collection_id=a.collection_id AND o.principal_user_id=a.principal_user_id
 JOIN private.burimunsi_scopes c ON c.collection_id=a.collection_id
 JOIN app.collections g ON g.id=c.collection_id AND g.status='active'
 JOIN app.momo_receiving_accounts r ON r.id=c.receiving_account_id AND r.status='active'
 WHERE d.collection_id=p_collection AND d.id=(prior.response->>'grantId')::uuid AND d.installation_id=p_installation
  AND d.profile=p_profile AND d.version=p_version AND d.active AND a.active AND NOT a.removed
  AND a.id=(prior.response->>'accountId')::uuid AND a.principal_user_id=prior.response->>'principalId'
  AND a.version=(prior.response->>'accountVersion')::bigint AND a.credential_version=(prior.response->>'credentialVersion')::bigint
  AND o.version=(prior.response->>'approvalVersion')::bigint AND c.version=(prior.response->>'scopeVersion')::bigint
  AND private.burimunsi_operator_is_current(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities)
 FOR SHARE OF d,a,da,o,c,g,r;
 IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_delivery_expired' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('receipt',prior.response,'ciphertext',prior.delivery_ciphertext,'tokenHash',token_digest);
END;$fn$;

REVOKE ALL ON FUNCTION private.burimunsi_provisioning_directory(text,text,text,text,text),
 private.burimunsi_provisioning_lookup(text,text,text,text,text,uuid),
 private.burimunsi_provisioning_cancel(text,text,text,text,text,uuid),
 private.burimunsi_provisioning_apply(text,text,text,text,text,jsonb,text,text),
 private.burimunsi_provisioning_delivery(text,text,text,text,text,uuid,uuid,text,bigint)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_provisioning_directory(text,text,text,text,text),
 private.burimunsi_provisioning_lookup(text,text,text,text,text,uuid),
 private.burimunsi_provisioning_cancel(text,text,text,text,text,uuid),
 private.burimunsi_provisioning_apply(text,text,text,text,text,jsonb,text,text),
 private.burimunsi_provisioning_delivery(text,text,text,text,text,uuid,uuid,text,bigint) TO collect_runtime;
COMMIT;
