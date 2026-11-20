-- Additive native opaque phone/PIN authentication for the original BuriMunsi app.
-- No business identity, PIN, owner, GoTrue user/session or receiving account is seeded.
-- PIN derivation/constant-time comparison remains server-only, using the existing
-- peppered PBKDF2 implementation. This private CAS commits only after that check.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.burimunsi_setup_fence()') IS NULL
  OR to_regclass('private.burimunsi_pin_session_links') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_pin_install_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

-- Ordinary installations are distinct from the single canonically bound SMS
-- receiver. Existing canonical binding/credential uniqueness is unchanged.
DROP INDEX private.burimunsi_one_receiving_installation;
CREATE INDEX burimunsi_receiving_installations ON private.burimunsi_device_grants(collection_id)
 WHERE active AND profile='internal_receiver';
-- A persistent installation secret may serve successive authorized operators in
-- different server-resolved scopes. Its installation/profile identity remains
-- globally unique through the collision trigger below; financial credentials
-- retain all existing canonical uniqueness constraints.
DROP INDEX private.burimunsi_unique_device_secret;
CREATE UNIQUE INDEX burimunsi_scoped_device_secret ON private.burimunsi_device_grants(collection_id,token_hash);
ALTER TABLE private.burimunsi_sessions ADD COLUMN auth_method text NOT NULL DEFAULT 'managed_email'
 CHECK(auth_method IN('managed_email','phone_pin'));
CREATE OR REPLACE FUNCTION private.burimunsi_session_identity_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fn$
BEGIN
 IF (NEW.id,NEW.collection_id,NEW.account_id,NEW.grant_id,NEW.installation_id,
     NEW.principal_user_id,NEW.token_hash,NEW.credential_version,NEW.grant_version,
     NEW.created_at,NEW.expires_at,NEW.auth_method) IS DISTINCT FROM
    (OLD.id,OLD.collection_id,OLD.account_id,OLD.grant_id,OLD.installation_id,
     OLD.principal_user_id,OLD.token_hash,OLD.credential_version,OLD.grant_version,
     OLD.created_at,OLD.expires_at,OLD.auth_method) OR (OLD.revoked AND NOT NEW.revoked) THEN
  RAISE EXCEPTION 'burimunsi_session_identity_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;$fn$;

CREATE TABLE private.burimunsi_pin_login_limits(
 bucket text NOT NULL CHECK(bucket ~ '^(account|installation|network):[a-f0-9]{64}$'),
 window_start bigint NOT NULL CHECK(window_start>=0),
 attempts bigint NOT NULL CHECK(attempts>0),
 PRIMARY KEY(bucket,window_start)
);
CREATE TABLE private.burimunsi_native_staff_delegations(
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 principal_user_id text NOT NULL REFERENCES app.users(id),
 parent_account_id uuid NOT NULL,
 capability_ceiling text[] NOT NULL CHECK(cardinality(capability_ceiling)>0 AND 'records.read'=ANY(capability_ceiling)
  AND capability_ceiling <@ ARRAY['records.read','members.enroll','payments.allocate']::text[]),
 active boolean NOT NULL DEFAULT true,
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 created_request_id uuid NOT NULL,
 creation_fingerprint text NOT NULL CHECK(creation_fingerprint ~ '^[a-f0-9]{64}$'),
 created_at bigint NOT NULL,
 PRIMARY KEY(collection_id,principal_user_id),UNIQUE(collection_id,parent_account_id,created_request_id),
 FOREIGN KEY(parent_account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
CREATE TABLE private.burimunsi_pin_session_links(
 native_session_id uuid PRIMARY KEY REFERENCES private.burimunsi_sessions(id),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 account_id uuid NOT NULL,
 principal_user_id text NOT NULL REFERENCES app.users(id),
 account_version bigint NOT NULL CHECK(account_version>0),
 scope_version bigint NOT NULL CHECK(scope_version>0),
 authority_snapshot jsonb NOT NULL CHECK(jsonb_typeof(authority_snapshot)='object'),
 created_at bigint NOT NULL,
 FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
DO $policies$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_pin_login_limits','burimunsi_native_staff_delegations','burimunsi_pin_session_links'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE private.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime',t);
  EXECUTE format('CREATE POLICY burimunsi_pin_owner_frame ON private.%I TO postgres USING(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.pin_frame'',true)=''1'') WITH CHECK(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.pin_frame'',true)=''1'')',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
  EXECUTE format('CREATE TRIGGER burimunsi_pin_retain BEFORE DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER burimunsi_pin_retain',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['burimunsi_native_staff_delegations','burimunsi_pin_session_links'] LOOP
  EXECUTE format('GRANT SELECT ON private.%I TO collect_runtime',t);
  EXECUTE format('CREATE POLICY burimunsi_scoped_runtime ON private.%I TO collect_runtime USING(collection_id=current_setting(''burimunsi.collection_id'',true))',t);
  EXECUTE format('CREATE POLICY burimunsi_scoped_owner ON private.%I TO postgres USING(collection_id=current_setting(''burimunsi.collection_id'',true)) WITH CHECK(collection_id=current_setting(''burimunsi.collection_id'',true))',t);
 END LOOP;
 -- Only SECURITY DEFINER owner code can use this cross-scope discovery window.
 -- collect_runtime cannot become postgres. A client-controlled group/actor GUC
 -- does not satisfy any native credential check below.
 FOREACH t IN ARRAY ARRAY['burimunsi_scopes','burimunsi_accounts','burimunsi_device_grants','burimunsi_device_accounts',
  'burimunsi_sessions','burimunsi_operator_approvals'] LOOP
  EXECUTE format('CREATE POLICY burimunsi_pin_owner_frame ON private.%I TO postgres USING(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.pin_frame'',true)=''1'') WITH CHECK(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.pin_frame'',true)=''1'')',t);
 END LOOP;
END;$policies$;
CREATE POLICY burimunsi_pin_device_collision_owner ON private.burimunsi_device_grants TO postgres
 USING(private._collect_fence_operator() AND current_setting('burimunsi.pin_frame',true)='1')
 WITH CHECK(private._collect_fence_operator() AND current_setting('burimunsi.pin_frame',true)='1');
-- Serialize identity reuse across scopes independently of caller-selected GUCs.
CREATE FUNCTION private.burimunsi_pin_device_secret_identity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.pin_frame',true);
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM set_config('burimunsi.pin_frame','1',true);
 IF EXISTS(SELECT 1 FROM private.burimunsi_device_grants d WHERE d.id<>NEW.id AND d.token_hash=NEW.token_hash
  AND (d.installation_id<>NEW.installation_id OR d.profile<>NEW.profile)) THEN
  RAISE EXCEPTION 'burimunsi_device_secret_collision' USING ERRCODE='23505';END IF;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
 RETURN NEW;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
CREATE TRIGGER burimunsi_pin_device_secret_identity BEFORE INSERT OR UPDATE ON private.burimunsi_device_grants
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_pin_device_secret_identity();
ALTER TABLE private.burimunsi_device_grants ENABLE ALWAYS TRIGGER burimunsi_pin_device_secret_identity;
CREATE TRIGGER burimunsi_pin_link_immutable BEFORE UPDATE ON private.burimunsi_pin_session_links
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_pin_session_links ENABLE ALWAYS TRIGGER burimunsi_pin_link_immutable;
CREATE FUNCTION private.burimunsi_pin_delegation_identity() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW;END IF;
 IF to_jsonb(NEW)-ARRAY['active','version'] IS DISTINCT FROM to_jsonb(OLD)-ARRAY['active','version']
  OR NOT OLD.active OR NEW.active OR NEW.version<>OLD.version+1 THEN
  RAISE EXCEPTION 'burimunsi_native_delegation_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER burimunsi_pin_delegation_identity BEFORE UPDATE ON private.burimunsi_native_staff_delegations
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_pin_delegation_identity();
CREATE FUNCTION private.burimunsi_pin_account_version() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF ((NEW.phone,NEW.name,NEW.role,NEW.capabilities,NEW.pin_hash) IS DISTINCT FROM
    (OLD.phone,OLD.name,OLD.role,OLD.capabilities,OLD.pin_hash) OR (NOT OLD.active AND NEW.active))
  AND (NEW.version<>OLD.version+1 OR NEW.credential_version<>OLD.credential_version+1 OR NEW.updated_at<OLD.updated_at) THEN
  RAISE EXCEPTION 'burimunsi_account_version_required' USING ERRCODE='23514';
 END IF;
 IF NEW.version<OLD.version OR NEW.credential_version<OLD.credential_version OR (OLD.removed AND NOT NEW.removed) THEN
  RAISE EXCEPTION 'burimunsi_account_version_regressed' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER burimunsi_pin_account_version BEFORE UPDATE ON private.burimunsi_accounts
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_pin_account_version();

-- A genuine owner-approved shared principal is still the root of each native
-- admin. Staff added in the original app get a scoped delegation, never a web
-- Admin role, GoTrue identity, email proof or global permission projection.
CREATE FUNCTION private.burimunsi_pin_root_snapshot(p_collection text,p_principal text,p_phone text,p_role text,p_capabilities text[])
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT CASE WHEN count(*)=1 THEN (jsonb_agg(x.snapshot)->0) END FROM(
  SELECT jsonb_build_object('kind','shared_approval','approvalVersion',o.version,'adminId',a.id,
   'adminVersion',a.auth_version,'principalRevision',u.revision,'sharedRole',a.role) AS snapshot
  FROM private.burimunsi_operator_approvals o
  JOIN app.users u ON u.id=o.principal_user_id AND u.access_status='active'
  JOIN app.admin_principal_links l ON l.user_id=u.id AND l.admin_user_id=o.admin_user_id
  JOIN app.admin_users a ON a.id=l.admin_user_id AND a.status='active'
  JOIN private.auth_principal_links p ON p.user_id=u.id
  JOIN auth.users actual ON actual.id=p.auth_user_id
  JOIN app.collections c ON c.id=o.collection_id AND c.status='active'
  WHERE o.collection_id=p_collection AND o.principal_user_id=p_principal AND o.phone=p_phone
   AND o.active AND o.role=p_role AND p_capabilities <@ o.capabilities AND cardinality(p_capabilities)>0
   AND 'records.read'=ANY(p_capabilities) AND (o.role='staff' OR a.role IN('owner','admin'))
   AND actual.email_confirmed_at IS NOT NULL AND lower(actual.email)=lower(a.email)
   AND actual.deleted_at IS NULL AND (actual.banned_until IS NULL OR actual.banned_until<=statement_timestamp())
 ) x
$fn$;
CREATE FUNCTION private.burimunsi_pin_authority_snapshot(p_collection text,p_principal text,p_phone text,p_role text,p_capabilities text[])
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE direct jsonb;delegated jsonb;
BEGIN
 direct:=private.burimunsi_pin_root_snapshot(p_collection,p_principal,p_phone,p_role,p_capabilities);
 IF direct IS NOT NULL THEN RETURN direct;END IF;
 IF p_role<>'staff' OR cardinality(p_capabilities)=0 OR NOT('records.read'=ANY(p_capabilities))
  OR NOT(p_capabilities <@ ARRAY['records.read','members.enroll','payments.allocate']::text[]) THEN RETURN NULL;END IF;
 SELECT CASE WHEN count(*)=1 THEN (jsonb_agg(x.snapshot)->0) END INTO delegated FROM(
  SELECT jsonb_build_object('kind','native_delegation','delegationVersion',d.version,
   'principalRevision',u.revision,'parentAccountId',parent.id,'parentAccountVersion',parent.version,
   'parentCredentialVersion',parent.credential_version,'parentAuthority',root.snapshot,'sharedRole','staff') AS snapshot
  FROM private.burimunsi_native_staff_delegations d
  JOIN app.users u ON u.id=d.principal_user_id AND u.access_status='active'
  JOIN private.burimunsi_accounts parent ON parent.id=d.parent_account_id AND parent.collection_id=d.collection_id
   AND parent.active AND NOT parent.removed AND parent.role='admin' AND 'staff.manage'=ANY(parent.capabilities)
  JOIN app.collections c ON c.id=d.collection_id AND c.status='active'
  CROSS JOIN LATERAL(SELECT private.burimunsi_pin_root_snapshot(parent.collection_id,parent.principal_user_id,
   parent.phone,parent.role,parent.capabilities) AS snapshot) root
  WHERE d.collection_id=p_collection AND d.principal_user_id=p_principal AND d.active
   AND p_capabilities <@ d.capability_ceiling AND p_capabilities <@ parent.capabilities AND root.snapshot IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM app.admin_principal_links l WHERE l.user_id=u.id)
 ) x;
 RETURN delegated;
END;$fn$;
CREATE OR REPLACE FUNCTION private.burimunsi_operator_is_current(p_collection text,p_principal text,p_phone text,p_role text,p_capabilities text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT coalesce(p_collection=current_setting('burimunsi.collection_id',true)
  AND private.burimunsi_pin_authority_snapshot(p_collection,p_principal,p_phone,p_role,p_capabilities) IS NOT NULL,false)
$fn$;

CREATE FUNCTION private.burimunsi_pin_login_budget(p_phone_hash text,p_installation uuid,p_network_hash text,p_now_ms bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 old_frame text:=current_setting('burimunsi.pin_frame',true);v_bucket text;n bigint;limit_n bigint;admitted boolean:=true;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 IF p_phone_hash IS NULL OR p_phone_hash !~ '^[a-f0-9]{64}$' OR p_installation IS NULL
  OR p_network_hash IS NULL OR p_network_hash !~ '^[a-f0-9]{64}$'
  OR p_now_ms IS NULL OR p_now_ms NOT BETWEEN at_ms-5000 AND at_ms+5000 THEN
  RAISE EXCEPTION 'burimunsi_pin_login_invalid' USING ERRCODE='22023';
 END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 FOR v_bucket,limit_n IN SELECT v.k,v.n FROM(VALUES
  ('account:'||p_phone_hash,5::bigint),
  ('installation:'||encode(sha256(convert_to(p_installation::text,'UTF8')),'hex'),10::bigint),
  ('network:'||p_network_hash,50::bigint)) v(k,n) LOOP
  INSERT INTO private.burimunsi_pin_login_limits AS l(bucket,window_start,attempts)
   VALUES(v_bucket,at_ms-(at_ms%900000),1) ON CONFLICT(bucket,window_start)
   DO UPDATE SET attempts=least(l.attempts+1,1000000) RETURNING attempts INTO n;
  admitted:=admitted AND n<=limit_n;
 END LOOP;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
 RETURN admitted;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
CREATE FUNCTION private.burimunsi_pin_login_account(p_phone text,p_phone_hash text,p_installation uuid,p_network_hash text,p_now_ms bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.pin_frame',true);account_json jsonb;
BEGIN
 IF p_phone IS NULL OR p_phone !~ '^\+2507[2389][0-9]{7}$'
  OR p_phone_hash IS DISTINCT FROM encode(sha256(convert_to(p_phone,'UTF8')),'hex') THEN
  RAISE EXCEPTION 'burimunsi_pin_login_invalid' USING ERRCODE='22023';
 END IF;
 -- Commit a denied admission, and do not inspect identities/hashes after it.
 IF NOT private.burimunsi_pin_login_budget(p_phone_hash,p_installation,p_network_hash,p_now_ms) THEN
  RETURN jsonb_build_object('allowed',false,'account',NULL);
 END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT CASE WHEN count(*)=1 THEN (jsonb_agg(x.snapshot)->0) END INTO account_json FROM(
  SELECT jsonb_build_object('id',a.id,'groupId',a.collection_id,'principalUserId',a.principal_user_id,
   'phone',a.phone,'name',a.name,'role',a.role,'capabilities',a.capabilities,'active',a.active,'removed',a.removed,
   'pinHash',a.pin_hash,'credentialVersion',a.credential_version,'version',a.version) AS snapshot
  FROM private.burimunsi_accounts a JOIN private.burimunsi_scopes s ON s.collection_id=a.collection_id
  JOIN app.collections c ON c.id=s.collection_id AND c.status='active'
  WHERE a.phone=p_phone AND a.active AND NOT a.removed
   AND private.burimunsi_pin_authority_snapshot(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities) IS NOT NULL
 ) x;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('allowed',true,'account',account_json);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_pin_create_session(p_collection text,p_account uuid,p_installation uuid,p_profile text,
 p_device_token_hash text,p_credential_version bigint,p_session uuid,p_session_token_hash text,p_created_ms bigint,p_expires_ms bigint,p_account_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.pin_frame',true);a private.burimunsi_accounts%ROWTYPE;
 scope private.burimunsi_scopes%ROWTYPE;d private.burimunsi_device_grants%ROWTYPE;proof jsonb;
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;matches bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 IF p_account IS NULL OR p_session IS NULL OR p_installation IS NULL OR p_collection IS NULL
  OR p_profile NOT IN('staff','internal_receiver') OR p_profile IS NULL
  OR p_device_token_hash IS NULL OR p_device_token_hash !~ '^[a-f0-9]{64}$'
  OR p_session_token_hash IS NULL OR p_session_token_hash !~ '^[a-f0-9]{64}$'
  OR p_device_token_hash=p_session_token_hash OR p_credential_version IS NULL OR p_credential_version<1
  OR p_account_version IS NULL OR p_account_version<1
  OR p_created_ms IS NULL OR p_created_ms NOT BETWEEN at_ms-5000 AND at_ms+5000
  OR p_expires_ms IS NULL OR p_expires_ms<=at_ms OR p_expires_ms>p_created_ms+28800000 THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';
 END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT * INTO a FROM private.burimunsi_accounts WHERE collection_id=p_collection AND id=p_account FOR UPDATE;
 IF NOT FOUND OR NOT a.active OR a.removed OR a.credential_version<>p_credential_version OR a.version<>p_account_version THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';
 END IF;
 SELECT * INTO scope FROM private.burimunsi_scopes WHERE collection_id=p_collection FOR SHARE;
 proof:=private.burimunsi_pin_authority_snapshot(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities);
 IF scope.collection_id IS NULL OR proof IS NULL THEN RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 -- The selected phone must still be globally unambiguous at the CAS boundary.
 SELECT count(*) INTO matches FROM private.burimunsi_accounts other
  JOIN private.burimunsi_scopes s ON s.collection_id=other.collection_id
  JOIN app.collections c ON c.id=s.collection_id AND c.status='active'
  WHERE other.phone=a.phone AND other.active AND NOT other.removed
   AND private.burimunsi_pin_authority_snapshot(other.collection_id,other.principal_user_id,other.phone,other.role,other.capabilities) IS NOT NULL;
 IF matches<>1 THEN RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 SELECT * INTO d FROM private.burimunsi_device_grants WHERE collection_id=p_collection AND installation_id=p_installation FOR UPDATE;
 IF FOUND THEN
  IF NOT d.active OR d.token_hash<>p_device_token_hash OR d.profile<>p_profile THEN
   RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM private.burimunsi_device_grants WHERE token_hash=p_device_token_hash
   AND (installation_id<>p_installation OR profile<>p_profile)) THEN
   RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
  INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
   VALUES(gen_random_uuid(),p_collection,p_installation,p_device_token_hash,p_profile,NULL,at_ms)
   RETURNING * INTO d;
 END IF;
 INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id) VALUES(d.id,a.id,p_collection)
  ON CONFLICT(grant_id,account_id) DO NOTHING;
 INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,
  token_hash,created_at,expires_at,principal_user_id,auth_method)
  VALUES(p_session,p_collection,a.id,d.id,p_installation,a.credential_version,d.version,p_session_token_hash,
   p_created_ms,p_expires_ms,a.principal_user_id,'phone_pin');
 INSERT INTO private.burimunsi_pin_session_links(native_session_id,collection_id,account_id,principal_user_id,
  account_version,scope_version,authority_snapshot,created_at)
  VALUES(p_session,p_collection,a.id,a.principal_user_id,a.version,scope.version,proof,p_created_ms);
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('created',true,'expiresAt',p_expires_ms,'grantId',d.id,'grantVersion',d.version);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Opaque secrets, not stored hashes, are the proof. The private function hashes
-- BOTH secrets itself, preventing a stored-hash or actor/group GUC from acting
-- as a bearer credential. This path is safe inside a repeatable-read READ ONLY
-- transaction: it takes no row locks and performs no application-table writes.
CREATE FUNCTION private.burimunsi_pin_session_context(p_token text,p_installation uuid,p_device_token text,p_profile text)
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
  a.role,a.capabilities,s.created_at,s.expires_at,a.credential_version,d.version,proof.snapshot->>'sharedRole'
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
 WHERE s.auth_method='phone_pin' AND NOT s.revoked AND s.created_at<=at_ms AND s.expires_at>at_ms
  AND s.created_at=link.created_at AND proof.snapshot IS NOT NULL AND proof.snapshot=link.authority_snapshot
  AND s.token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex')
  AND d.token_hash=encode(sha256(convert_to(p_device_token,'UTF8')),'hex')
  AND s.installation_id=p_installation AND d.profile=p_profile;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
CREATE FUNCTION private.burimunsi_pin_context()
RETURNS TABLE(collection_id text,account_id uuid,principal_user_id text,native_session_id uuid,grant_id uuid,
 installation_id uuid,profile text,role text,capabilities text[],created_at bigint,expires_at bigint,
 credential_version bigint,grant_version bigint,shared_role text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE installation_text text:=current_setting('burimunsi.pin_installation',true);
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF installation_text IS NULL OR installation_text !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' THEN RETURN;END IF;
 RETURN QUERY SELECT * FROM private.burimunsi_pin_session_context(
  current_setting('burimunsi.pin_token',true),installation_text::uuid,
  current_setting('burimunsi.pin_device',true),current_setting('burimunsi.pin_profile',true));
END;$fn$;
CREATE FUNCTION private.burimunsi_set_pin_context(p_token text,p_installation uuid,p_device_token text,p_profile text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor record;
BEGIN
 SELECT * INTO actor FROM private.burimunsi_pin_session_context(p_token,p_installation,p_device_token,p_profile);
 IF NOT FOUND THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.pin_token',p_token,true);
 PERFORM set_config('burimunsi.pin_installation',p_installation::text,true);
 PERFORM set_config('burimunsi.pin_device',p_device_token,true);
 PERFORM set_config('burimunsi.pin_profile',p_profile,true);
 -- This routing GUC is derived from proof. Every subsequent authority call
 -- revalidates the four raw proofs and current rows, regardless of this GUC.
 PERFORM set_config('burimunsi.collection_id',actor.collection_id,true);
 RETURN to_jsonb(actor);
END;$fn$;

CREATE FUNCTION private.burimunsi_pin_claim_custody(p_collection text,p_grant uuid,p_actor_account uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor record;d private.burimunsi_device_grants%ROWTYPE;old_frame text:=current_setting('burimunsi.pin_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();
 PERFORM private.burimunsi_pin_assert_actor('receivers.manage',p_collection,NULL,1,300);
 SELECT * INTO actor FROM private.burimunsi_pin_context();
 IF NOT FOUND OR actor.collection_id IS DISTINCT FROM p_collection OR actor.account_id IS DISTINCT FROM p_actor_account
  OR actor.grant_id IS DISTINCT FROM p_grant OR actor.profile<>'internal_receiver' OR actor.role<>'admin'
  OR NOT('gateway.manage'=ANY(actor.capabilities)) THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT * INTO d FROM private.burimunsi_device_grants WHERE collection_id=p_collection AND id=p_grant FOR UPDATE;
 IF NOT FOUND OR NOT d.active OR d.version<>actor.grant_version
  OR (d.custodian_account_id IS NOT NULL AND d.custodian_account_id<>p_actor_account) THEN
  RAISE EXCEPTION 'burimunsi_gateway_custody_conflict' USING ERRCODE='42501';END IF;
 -- This one-time assignment does not change the installation secret/profile or
 -- interactive grant version. Capture still requires canonical pairing/credential
 -- issuance by the caller in this same admitted transaction.
 IF d.custodian_account_id IS NULL THEN
  UPDATE private.burimunsi_device_grants SET custodian_account_id=p_actor_account WHERE id=d.id AND collection_id=p_collection;
 END IF;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('claimed',true,'grantId',d.id,'grantVersion',d.version);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_pin_resolve_staff(p_collection text,p_actor_session uuid,p_actor_principal text,
 p_name text,p_phone text,p_capabilities text[],p_request uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor record;old_frame text:=current_setting('burimunsi.pin_frame',true);target text;
 ceiling text[];fingerprint text;prior private.burimunsi_native_staff_delegations%ROWTYPE;
 public_id_text text;at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 PERFORM private.burimunsi_pin_assert_actor(NULL,p_collection,NULL,1,300);
 SELECT * INTO actor FROM private.burimunsi_pin_context();
 IF NOT FOUND OR actor.collection_id IS DISTINCT FROM p_collection OR actor.native_session_id IS DISTINCT FROM p_actor_session
  OR actor.principal_user_id IS DISTINCT FROM p_actor_principal OR actor.role<>'admin'
  OR NOT('staff.manage'=ANY(actor.capabilities)) OR actor.created_at<at_ms-300000 THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 IF p_request IS NULL OR p_name IS NULL OR p_name<>btrim(p_name) OR length(p_name) NOT BETWEEN 2 AND 100
  OR p_name ~ '[[:cntrl:]]' OR p_phone IS NULL OR p_phone !~ '^\+2507[2389][0-9]{7}$'
  OR p_capabilities IS NULL OR cardinality(p_capabilities)=0 OR NOT('records.read'=ANY(p_capabilities))
  OR NOT(p_capabilities <@ ARRAY['records.read','members.enroll','payments.allocate']::text[])
  OR NOT(p_capabilities <@ actor.capabilities) THEN RAISE EXCEPTION 'burimunsi_invalid_staff' USING ERRCODE='42501';END IF;
 SELECT array_agg(cap ORDER BY cap) INTO ceiling FROM unnest(actor.capabilities) cap
  WHERE cap=ANY(ARRAY['records.read','members.enroll','payments.allocate']::text[]);
 fingerprint:=encode(sha256(convert_to(jsonb_build_array(p_name,p_phone,
  ARRAY(SELECT DISTINCT c FROM unnest(p_capabilities) c ORDER BY c))::text,'UTF8')),'hex');
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT * INTO prior FROM private.burimunsi_native_staff_delegations
  WHERE collection_id=p_collection AND parent_account_id=actor.account_id AND created_request_id=p_request;
 IF FOUND THEN
  IF prior.creation_fingerprint<>fingerprint OR NOT prior.active THEN RAISE EXCEPTION 'burimunsi_staff_request_conflict' USING ERRCODE='23505';END IF;
  PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
  RETURN jsonb_build_object('id',prior.principal_user_id);
 END IF;
 IF EXISTS(SELECT 1 FROM private.burimunsi_accounts WHERE collection_id=p_collection AND phone=p_phone) THEN
  RAISE EXCEPTION 'burimunsi_duplicate_phone' USING ERRCODE='23505';END IF;
 -- Exact canonical contact identity only. No MoMo sender/beneficiary or existing
 -- unrelated app identity is manufactured from a display name.
 SELECT u.id INTO target FROM app.users u WHERE u.phone=p_phone FOR UPDATE;
 IF target IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM app.users u WHERE u.id=target AND u.access_status='active')
   OR EXISTS(SELECT 1 FROM app.admin_principal_links l WHERE l.user_id=target)
   OR EXISTS(SELECT 1 FROM private.burimunsi_accounts a WHERE a.collection_id=p_collection AND a.principal_user_id=target)
   OR EXISTS(SELECT 1 FROM private.burimunsi_operator_approvals o WHERE o.collection_id=p_collection AND o.principal_user_id=target) THEN
   RAISE EXCEPTION 'burimunsi_staff_identity_conflict' USING ERRCODE='42501';END IF;
 ELSE
  SELECT lpad(min(candidate)::text,6,'0') INTO public_id_text FROM(
   SELECT 0::bigint candidate UNION ALL SELECT u.public_id::bigint+1 FROM app.users u WHERE u.public_id<>'999999'
  ) candidates WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM app.users u WHERE u.public_id=lpad(candidate::text,6,'0'));
  IF public_id_text IS NULL THEN RAISE EXCEPTION 'public_id_exhausted' USING ERRCODE='54000';END IF;
  target:=gen_random_uuid()::text;
  INSERT INTO app.users(id,phone,full_name,public_id,member_type,created_at,updated_at)
   VALUES(target,p_phone,p_name,public_id_text,'operator',
    to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
 END IF;
 INSERT INTO private.burimunsi_native_staff_delegations(collection_id,principal_user_id,parent_account_id,
  capability_ceiling,created_request_id,creation_fingerprint,created_at)
  VALUES(p_collection,target,actor.account_id,ceiling,p_request,fingerprint,at_ms);
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
  VALUES(actor.principal_user_id,actor.native_session_id::text,'burimunsi.staff.delegation','user',target,p_request::text,
   jsonb_build_object('collection_id',p_collection,'native_actor_id',actor.account_id,'capabilities',p_capabilities)::text,
   to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('id',target);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Native presence is fail-closed: partial/forged native proof never falls back
-- to unrelated managed JWT claims. These functions retain the web signatures.
CREATE OR REPLACE FUNCTION api.current_principal_id() RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE principal text;
BEGIN
 IF coalesce(nullif(current_setting('burimunsi.pin_token',true),''),nullif(current_setting('burimunsi.pin_installation',true),''),
  nullif(current_setting('burimunsi.pin_device',true),''),nullif(current_setting('burimunsi.pin_profile',true),'')) IS NOT NULL THEN
  SELECT c.principal_user_id INTO principal FROM private.burimunsi_pin_context() c;
  RETURN principal;
 END IF;
 SELECT l.user_id INTO principal FROM private.auth_principal_links l WHERE l.auth_user_id::text=private.request_claims()->>'sub';
 RETURN principal;
END;$fn$;
CREATE OR REPLACE FUNCTION api.current_session_id() RETURNS text
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $fn$
DECLARE sid text;
BEGIN
 IF coalesce(nullif(current_setting('burimunsi.pin_token',true),''),nullif(current_setting('burimunsi.pin_installation',true),''),
  nullif(current_setting('burimunsi.pin_device',true),''),nullif(current_setting('burimunsi.pin_profile',true),'')) IS NOT NULL THEN
  SELECT c.native_session_id::text INTO sid FROM private.burimunsi_pin_context() c;
  RETURN sid;
 END IF;
 RETURN private.request_claims()->>'session_id';
END;$fn$;

CREATE FUNCTION private.burimunsi_pin_assert_actor(p_permission text,p_collection text,p_group_role text,p_min_aal bigint,p_fresh_seconds bigint)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor record;required_capability text;now_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 SELECT * INTO actor FROM private.burimunsi_pin_context();
 IF NOT FOUND THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 IF p_collection IS NOT NULL AND p_collection<>actor.collection_id THEN RAISE EXCEPTION 'group_access_denied' USING ERRCODE='42501';END IF;
 IF current_setting('transaction_read_only')='off' THEN
  -- Keep current authority stable until this admitted command commits. The
  -- separate snapshot API remains genuinely lock-free for READ ONLY callers.
  PERFORM 1 FROM private.burimunsi_sessions s
   JOIN private.burimunsi_accounts a ON a.id=s.account_id AND a.collection_id=s.collection_id
   JOIN private.burimunsi_device_grants d ON d.id=s.grant_id AND d.collection_id=s.collection_id
   JOIN private.burimunsi_scopes scope ON scope.collection_id=s.collection_id
   JOIN app.users u ON u.id=a.principal_user_id
   WHERE s.id=actor.native_session_id FOR SHARE OF s,a,d,scope,u;
  PERFORM 1 FROM private.burimunsi_native_staff_delegations delegation
   JOIN private.burimunsi_accounts parent ON parent.id=delegation.parent_account_id AND parent.collection_id=delegation.collection_id
   JOIN app.users u ON u.id=parent.principal_user_id
   WHERE delegation.collection_id=actor.collection_id AND delegation.principal_user_id=actor.principal_user_id
   FOR SHARE OF delegation,parent,u;
  PERFORM 1 FROM private.burimunsi_operator_approvals approval
   JOIN app.users u ON u.id=approval.principal_user_id
   JOIN app.admin_principal_links link ON link.user_id=u.id AND link.admin_user_id=approval.admin_user_id
   JOIN app.admin_users admin ON admin.id=link.admin_user_id
   JOIN private.auth_principal_links principal ON principal.user_id=u.id
   JOIN auth.users actual ON actual.id=principal.auth_user_id
   WHERE approval.collection_id=actor.collection_id AND (approval.principal_user_id=actor.principal_user_id OR
    approval.principal_user_id IN(SELECT parent.principal_user_id FROM private.burimunsi_native_staff_delegations delegation
     JOIN private.burimunsi_accounts parent ON parent.id=delegation.parent_account_id AND parent.collection_id=delegation.collection_id
     WHERE delegation.collection_id=actor.collection_id AND delegation.principal_user_id=actor.principal_user_id))
   FOR SHARE OF approval,u,link,admin,principal,actual;
  -- READ COMMITTED may have waited behind revocation. Never return the pre-wait
  -- snapshot or silently adopt a newer approval/credential than the issued link.
  SELECT * INTO actor FROM private.burimunsi_pin_context();
  IF NOT FOUND THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 END IF;
 IF p_min_aal>1 THEN RAISE EXCEPTION 'native_pin_is_not_aal2' USING ERRCODE='42501';END IF;
 IF p_fresh_seconds IS NOT NULL AND (p_fresh_seconds<1 OR actor.created_at<now_ms-p_fresh_seconds*1000) THEN
  RAISE EXCEPTION 'fresh_auth_required' USING ERRCODE='42501';END IF;
 IF p_group_role IS NOT NULL AND NOT(actor.role='admin' AND p_group_role IN('admin','owner')) THEN
  RAISE EXCEPTION 'group_access_denied' USING ERRCODE='42501';END IF;
 required_capability:=CASE p_permission
  WHEN 'users.manage' THEN 'members.enroll' WHEN 'collections.manage' THEN 'members.enroll'
  WHEN 'payments.reconcile' THEN 'payments.allocate'
  WHEN 'sms.read' THEN 'sms.read' WHEN 'sms.reveal' THEN 'sms.read'
  WHEN 'receivers.read' THEN 'gateway.manage' WHEN 'receivers.manage' THEN 'gateway.manage'
  ELSE NULL END;
 IF p_permission IS NOT NULL AND (required_capability IS NULL OR NOT(required_capability=ANY(actor.capabilities))) THEN
  RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 -- Native commands carry their actual scope, never a global web Admin grant.
 IF p_permission IS NOT NULL AND p_collection IS DISTINCT FROM actor.collection_id THEN
  RAISE EXCEPTION 'group_access_denied' USING ERRCODE='42501';END IF;
 IF p_permission IN('receivers.read','receivers.manage','sms.read','sms.reveal') AND actor.role<>'admin' THEN
  RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 IF p_permission IN('payments.reconcile','sms.read','sms.reveal') AND NOT EXISTS(
  SELECT 1 FROM private.burimunsi_scopes s JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id
   AND b.receiving_account_id=s.receiving_account_id AND b.version=s.binding_version AND b.status='active'
  JOIN app.momo_receiving_accounts wallet ON wallet.id=b.receiving_account_id AND wallet.status='active'
  WHERE s.collection_id=actor.collection_id AND s.enabled AND b.owner_user_id=actor.principal_user_id) THEN
  -- Scoped delegated staff may allocate existing evidence under the SAME active
  -- receiver binding owned by its currently approved native administrator.
  IF p_permission<>'payments.reconcile' OR NOT EXISTS(
   SELECT 1 FROM private.burimunsi_scopes s JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id
    AND b.receiving_account_id=s.receiving_account_id AND b.version=s.binding_version AND b.status='active'
   JOIN app.momo_receiving_accounts wallet ON wallet.id=b.receiving_account_id AND wallet.status='active'
   JOIN private.burimunsi_accounts owner ON owner.collection_id=s.collection_id AND owner.principal_user_id=b.owner_user_id
    AND owner.role='admin' AND owner.active AND NOT owner.removed
   WHERE s.collection_id=actor.collection_id AND s.enabled
    AND private.burimunsi_pin_authority_snapshot(owner.collection_id,owner.principal_user_id,owner.phone,owner.role,owner.capabilities) IS NOT NULL
  ) THEN RAISE EXCEPTION 'group_access_denied' USING ERRCODE='42501';END IF;
 END IF;
 IF p_permission IN('sms.read','sms.reveal') AND (actor.profile<>'internal_receiver' OR NOT EXISTS(
  SELECT 1 FROM private.burimunsi_scopes s
  JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id AND b.receiving_account_id=s.receiving_account_id
   AND b.version=s.binding_version AND b.status='active' AND b.owner_user_id=actor.principal_user_id
  JOIN app.momo_receiving_accounts wallet ON wallet.id=b.receiving_account_id AND wallet.status='active'
  JOIN app.momo_gateway_credentials c ON c.binding_id=b.id AND c.installation_id=actor.installation_id::text AND c.revoked_at IS NULL
  JOIN app.momo_gateway_pairings p ON p.id=c.pairing_id AND p.binding_id=b.id AND p.claimed_installation_id=c.installation_id
  JOIN private.burimunsi_device_grants d ON d.id=actor.grant_id AND d.collection_id=s.collection_id
   AND d.installation_id=actor.installation_id AND d.version=actor.grant_version AND d.active
   AND d.profile='internal_receiver' AND d.custodian_account_id=actor.account_id
  CROSS JOIN LATERAL(SELECT CASE WHEN app.json_valid(b.subscription_evidence) THEN b.subscription_evidence::jsonb ELSE '{}'::jsonb END AS evidence) e
  WHERE s.collection_id=actor.collection_id AND s.enabled
   AND CASE WHEN jsonb_typeof(e.evidence->'subscription_id')='number'
    AND e.evidence->>'subscription_id' ~ '^[0-9]{1,10}$' THEN (e.evidence->>'subscription_id')::bigint BETWEEN 0 AND 2147483647 ELSE false END
 )) THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 RETURN actor.principal_user_id;
END;$fn$;

-- Existing managed web/Member authority body is preserved verbatim after this branch.
CREATE OR REPLACE FUNCTION private.assert_actor(p_permission text DEFAULT NULL,p_collection_id text DEFAULT NULL,p_group_role text DEFAULT NULL,p_min_aal bigint DEFAULT 1,p_fresh_seconds bigint DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
DECLARE principal text;claims jsonb;projected app.auth_sessions%ROWTYPE;managed jsonb;
 now_seconds bigint:=app.unixepoch();admin_actor jsonb;email_ttl bigint;
BEGIN
 IF coalesce(nullif(current_setting('burimunsi.pin_token',true),''),nullif(current_setting('burimunsi.pin_installation',true),''),nullif(current_setting('burimunsi.pin_device',true),''),nullif(current_setting('burimunsi.pin_profile',true),'')) IS NOT NULL THEN
  RETURN private.burimunsi_pin_assert_actor(p_permission,p_collection_id,p_group_role,p_min_aal,p_fresh_seconds);
 END IF;
 IF p_permission='auth.mfa.enroll' THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 claims:=private.request_claims();principal:=api.current_principal_id();
 IF principal IS NULL OR claims->>'role' IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 SELECT s.* INTO projected FROM app.auth_sessions s JOIN app.users u ON u.id=s.user_id
 WHERE s.id=api.current_session_id() AND s.user_id=principal AND s.revoked_at IS NULL
 AND s.expires_at>now_seconds AND u.access_status='active' FOR SHARE OF s,u;
 IF NOT FOUND THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 SELECT to_jsonb(s) INTO managed FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
 WHERE s.id::text=projected.id AND u.id::text=claims->>'sub' AND to_jsonb(u)->>'deleted_at' IS NULL
 AND (to_jsonb(u)->>'banned_until' IS NULL OR (to_jsonb(u)->>'banned_until')::timestamptz<=now())
 AND (to_jsonb(s)->>'not_after' IS NULL OR (to_jsonb(s)->>'not_after')::timestamptz>now()) FOR SHARE OF s,u;
 IF managed IS NULL THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 IF projected.surface='admin' THEN
  admin_actor:=private._admin_email_context();
  IF admin_actor->>'principal_id' IS DISTINCT FROM principal OR admin_actor->>'session_id' IS DISTINCT FROM projected.id
  THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
  -- Requested policy thresholds remain unchanged in stored mutation guards.
  -- Admin policy is satisfied by email possession/current intent, not fake AAL2.
  IF p_min_aal>1 OR p_fresh_seconds IS NOT NULL THEN
   email_ttl:=CASE WHEN p_min_aal>1 THEN least(300,coalesce(p_fresh_seconds,300)) ELSE p_fresh_seconds END;
   PERFORM private.assert_admin_email_context(email_ttl);
  END IF;
  IF p_permission IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.admin_account_role_capabilities c
    WHERE c.role=admin_actor->>'role' AND c.permission=p_permission)
  THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 ELSE
  -- Exact preexisting managed MFA and freshness conditions for members.
  IF p_min_aal>1 AND (claims->>'aal' IS DISTINCT FROM 'aal2' OR managed->>'aal' IS DISTINCT FROM 'aal2' OR projected.assurance_level<>2 OR projected.mfa_at IS NULL OR projected.mfa_at<now_seconds-300 OR NOT EXISTS(SELECT 1 FROM private.managed_mfa_proofs proof JOIN auth.mfa_factors f ON f.id=proof.factor_id AND f.user_id=proof.user_id WHERE proof.session_id::text=projected.id AND proof.user_id::text=claims->>'sub' AND proof.factor_id::text=projected.mfa_factor_id AND f.status::text='verified' AND proof.verified_at_epoch=projected.mfa_at)) THEN RAISE EXCEPTION 'mfa_required' USING ERRCODE='42501';END IF;
  IF p_fresh_seconds IS NOT NULL AND greatest(projected.auth_at,coalesce(projected.mfa_at,0))<now_seconds-p_fresh_seconds THEN RAISE EXCEPTION 'fresh_auth_required' USING ERRCODE='42501';END IF;
 END IF;
 IF p_permission IS NOT NULL AND (projected.surface<>'admin' OR NOT EXISTS(SELECT 1 FROM app.admin_grants g WHERE g.user_id=principal AND g.permission=p_permission)) THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 IF p_collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.memberships m JOIN app.collections c ON c.id=m.collection_id WHERE m.user_id=principal AND m.collection_id=p_collection_id AND m.active=1 AND c.status='active' AND (p_group_role IS NULL OR m.role=p_group_role OR (p_group_role='admin' AND m.role='owner'))) THEN RAISE EXCEPTION 'group_access_denied' USING ERRCODE='42501';END IF;
 RETURN principal;
END$$;

-- Existing managed mutation authority body is preserved verbatim after this branch.
CREATE OR REPLACE FUNCTION private.trg_mutation_authority() RETURNS trigger
LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
DECLARE admin_surface boolean;native_actor record;
BEGIN
 IF coalesce(nullif(current_setting('burimunsi.pin_token',true),''),nullif(current_setting('burimunsi.pin_installation',true),''),nullif(current_setting('burimunsi.pin_device',true),''),nullif(current_setting('burimunsi.pin_profile',true),'')) IS NOT NULL THEN
  SELECT * INTO native_actor FROM private.burimunsi_pin_context();
  IF NOT FOUND OR NEW.user_id IS DISTINCT FROM native_actor.principal_user_id
   OR NEW.session_id IS DISTINCT FROM native_actor.native_session_id::text
   OR NEW.collection_id IS DISTINCT FROM native_actor.collection_id
   OR (NEW.target_collection_id IS NOT NULL AND NEW.target_collection_id<>native_actor.collection_id)
   OR (NEW.recipient_collection_id IS NOT NULL AND NEW.recipient_collection_id<>native_actor.collection_id)
   OR NEW.now_seconds NOT BETWEEN app.unixepoch()-5 AND app.unixepoch()+5 THEN
   RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
  IF NEW.minimum_assurance IS NOT NULL OR NEW.expected_mfa_at IS NOT NULL THEN
   RAISE EXCEPTION 'native_pin_provenance_required' USING ERRCODE='42501';END IF;
  PERFORM private.burimunsi_pin_assert_actor(NEW.permission,NEW.collection_id,NEW.required_group_role,1,NEW.fresh_seconds);
  IF NEW.permission IS NULL OR NEW.invite_collection_id IS NOT NULL OR NEW.expected_share_hash IS NOT NULL
   OR NEW.expected_share_version IS NOT NULL OR NEW.expected_preference_revision IS NOT NULL THEN
   RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
  IF NEW.recipient_user_id IS NOT NULL AND (NEW.permission<>'payments.reconcile'
   OR NEW.recipient_collection_id IS DISTINCT FROM native_actor.collection_id OR NOT EXISTS(
    SELECT 1 FROM app.memberships m JOIN app.users u ON u.id=m.user_id
    WHERE m.user_id=NEW.recipient_user_id AND m.collection_id=NEW.recipient_collection_id AND m.active=1 AND u.access_status='active')) THEN
   RAISE EXCEPTION 'recipient_changed' USING ERRCODE='42501';END IF;
  IF NEW.payment_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.payments p WHERE p.id=NEW.payment_id AND p.collection_id=native_actor.collection_id) THEN
   RAISE EXCEPTION 'stale_payment' USING ERRCODE='42501';END IF;
  IF NEW.expected_collection_revision IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.collections c WHERE c.id=NEW.collection_id AND c.revision=NEW.expected_collection_revision) THEN
   RAISE EXCEPTION 'stale_collection' USING ERRCODE='42501';END IF;
  IF NEW.expected_payment_revision IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.payments p WHERE p.id=NEW.payment_id AND p.revision=NEW.expected_payment_revision) THEN
   RAISE EXCEPTION 'stale_payment' USING ERRCODE='42501';END IF;
  RETURN NEW;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.id=NEW.session_id AND s.user_id=NEW.user_id AND s.revoked_at IS NULL AND s.expires_at>NEW.now_seconds AND u.access_status='active') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='session_changed';END IF;
 SELECT s.surface='admin' INTO admin_surface FROM auth_sessions s WHERE s.id=NEW.session_id;
 IF admin_surface THEN
  PERFORM private.assert_actor(NEW.permission,NEW.collection_id,NEW.required_group_role,coalesce(NEW.minimum_assurance,1),NEW.fresh_seconds);
  IF NEW.expected_mfa_at IS NOT NULL THEN RAISE EXCEPTION 'admin_email_mfa_field_must_remain_null' USING ERRCODE='42501';END IF;
 ELSE
  IF NEW.fresh_seconds IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth_sessions s WHERE s.id=NEW.session_id AND (CASE WHEN s.assurance_level=2 THEN s.mfa_at ELSE s.auth_at END)>=NEW.now_seconds-NEW.fresh_seconds) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='fresh_auth_required';END IF;
  IF NEW.minimum_assurance IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN auth_mfa_factors f ON f.id=s.mfa_factor_id AND f.status='verified' WHERE s.id=NEW.session_id AND s.assurance_level>=NEW.minimum_assurance AND s.mfa_at=NEW.expected_mfa_at AND s.mfa_at>=NEW.now_seconds-300 AND s.mfa_factor_id IS NOT NULL) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='mfa_required';END IF;
 END IF;
 IF NEW.permission IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN admin_grants g ON g.user_id=s.user_id WHERE s.id=NEW.session_id AND s.surface='admin' AND g.permission=NEW.permission) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='permission_denied';END IF;
 IF NEW.collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM memberships m JOIN collections c ON c.id=m.collection_id WHERE m.collection_id=NEW.collection_id AND m.user_id=NEW.user_id AND m.active=1 AND c.status='active' AND (NEW.required_group_role IS NULL OR m.role=NEW.required_group_role OR (NEW.required_group_role='admin' AND m.role='owner'))) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='group_access_denied';END IF;
 IF NEW.invite_collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections c WHERE c.id=NEW.invite_collection_id AND c.status='active' AND c.share_code_hash=NEW.expected_share_hash AND c.share_code_version=NEW.expected_share_version) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='invitation_changed';END IF;
 IF NEW.recipient_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM memberships m JOIN users u ON u.id=m.user_id WHERE m.user_id=NEW.recipient_user_id AND m.collection_id=NEW.recipient_collection_id AND m.active=1 AND u.access_status='active') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='recipient_changed';END IF;
 IF NEW.expected_preference_revision IS NOT NULL AND coalesce((SELECT revision FROM notification_preferences WHERE user_id=NEW.user_id),1)!=NEW.expected_preference_revision THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='stale_preferences';END IF;
 IF NEW.expected_collection_revision IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections c WHERE c.id=NEW.collection_id AND c.revision=NEW.expected_collection_revision) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='stale_collection';END IF;
 IF NEW.expected_payment_revision IS NOT NULL AND NOT EXISTS(SELECT 1 FROM payments p WHERE p.id=NEW.payment_id AND p.revision=NEW.expected_payment_revision) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='stale_payment';END IF;
 RETURN NEW;
END$$;

-- Native staff changes are authorized by the real, current scoped native admin.
-- A self PIN-only change remains a credential operation, not staff delegation.
CREATE FUNCTION private.burimunsi_pin_account_actor() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor record;
BEGIN
 IF coalesce(nullif(current_setting('burimunsi.pin_token',true),''),nullif(current_setting('burimunsi.pin_installation',true),''),
  nullif(current_setting('burimunsi.pin_device',true),''),nullif(current_setting('burimunsi.pin_profile',true),'')) IS NULL THEN RETURN NEW;END IF;
 PERFORM private.burimunsi_pin_assert_actor(NULL,NEW.collection_id,NULL,1,300);
 SELECT * INTO actor FROM private.burimunsi_pin_context();
 IF NOT FOUND OR actor.collection_id IS DISTINCT FROM NEW.collection_id
  OR actor.created_at<floor(extract(epoch FROM clock_timestamp())*1000)::bigint-300000 THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 IF TG_OP='UPDATE' THEN
  IF actor.account_id=OLD.id
   AND to_jsonb(NEW)-ARRAY['pin_hash','version','credential_version','updated_at']=to_jsonb(OLD)-ARRAY['pin_hash','version','credential_version','updated_at'] THEN
   RETURN NEW;
  END IF;
 END IF;
 IF actor.role<>'admin' OR NOT('staff.manage'=ANY(actor.capabilities)) OR NEW.role<>'staff'
  OR NOT(NEW.capabilities <@ actor.capabilities) THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER burimunsi_pin_account_actor BEFORE INSERT OR UPDATE ON private.burimunsi_accounts
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_pin_account_actor();

-- Close every new function by exact signature, then expose only the native
-- server contract. No new public RPC, database login or broad role is introduced.
DO $acl$
DECLARE f regprocedure;
BEGIN
 FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname IN(
   'burimunsi_pin_device_secret_identity','burimunsi_pin_delegation_identity','burimunsi_pin_account_version','burimunsi_pin_root_snapshot',
   'burimunsi_pin_authority_snapshot','burimunsi_pin_login_budget','burimunsi_pin_login_account',
   'burimunsi_pin_create_session','burimunsi_pin_session_context','burimunsi_pin_context','burimunsi_set_pin_context',
   'burimunsi_pin_claim_custody','burimunsi_pin_resolve_staff','burimunsi_pin_assert_actor','burimunsi_pin_account_actor') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime',f);
 END LOOP;
END;$acl$;
GRANT EXECUTE ON FUNCTION private.burimunsi_pin_login_account(text,text,uuid,text,bigint),
 private.burimunsi_pin_create_session(text,uuid,uuid,text,text,bigint,uuid,text,bigint,bigint,bigint),
 private.burimunsi_pin_session_context(text,uuid,text,text),private.burimunsi_pin_context(),
 private.burimunsi_set_pin_context(text,uuid,text,text),private.burimunsi_pin_claim_custody(text,uuid,uuid),
 private.burimunsi_pin_resolve_staff(text,uuid,text,text,text,text[],uuid),
 private.burimunsi_pin_assert_actor(text,text,text,bigint,bigint) TO collect_runtime;
COMMIT;
