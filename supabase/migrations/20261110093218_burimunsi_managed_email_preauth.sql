-- Registered native phones may request only their existing confirmed identity's
-- email OTP. This is a server-side admission, never a CAPTCHA credential or user.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $check$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.burimunsi_setup_fence()') IS NULL
  OR to_regclass('private.burimunsi_email_preauth') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_email_install_precondition' USING ERRCODE='55000';END IF;
END;$check$;

ALTER TABLE private.supabase_otp_challenges ADD COLUMN native_preauth boolean NOT NULL DEFAULT false;
ALTER TABLE private.supabase_otp_challenges ADD CONSTRAINT burimunsi_native_email_shape
 CHECK(NOT native_preauth OR(identity_type='email' AND surface='admin' AND registration_allowed=0));
-- Existing column-specific runtime INSERT/UPDATE grants intentionally exclude
-- this immutable marker. Only the fenced helper may create a native challenge.
CREATE TABLE private.burimunsi_email_preauth(
 challenge_id text PRIMARY KEY REFERENCES private.supabase_otp_challenges(id),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 installation_id uuid NOT NULL,
 token_hash text NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 email text NOT NULL CHECK(length(email)<=254 AND email=lower(email)),
 profile text NOT NULL CHECK(profile IN('staff','internal_receiver')),
 snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object'),
 created_at bigint NOT NULL CHECK(created_at>=0)
);
-- The global network budget also charges validly formed WRONG device tokens;
-- no principal/group is fabricated to gain an authenticated rate-limit context.
CREATE TABLE private.burimunsi_email_preauth_limits(
 bucket text NOT NULL CHECK(bucket ~ '^(network|device|email):[a-f0-9]{64}$'),
 window_start bigint NOT NULL CHECK(window_start>=0),
 attempts bigint NOT NULL CHECK(attempts>0),
 PRIMARY KEY(bucket,window_start)
);
DO $tables$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_email_preauth','burimunsi_email_preauth_limits'] LOOP
  EXECUTE format('ALTER TABLE private.%I OWNER TO postgres',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE private.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer',t);
  EXECUTE format('CREATE POLICY burimunsi_email_owner ON private.%I TO postgres USING(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.email_preauth'',true)=''1'') WITH CHECK(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.email_preauth'',true)=''1'')',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
  EXECUTE format('CREATE TRIGGER burimunsi_email_retain BEFORE DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER burimunsi_email_retain',t);
 END LOOP;
END;$tables$;
CREATE TRIGGER burimunsi_email_immutable BEFORE UPDATE ON private.burimunsi_email_preauth
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_email_preauth ENABLE ALWAYS TRIGGER burimunsi_email_immutable;

-- Private implementation, not executable by runtime callers. Token discovery
-- uses the existing exact-hash RLS window, then ordinary collection owner RLS.
CREATE FUNCTION private.burimunsi_managed_email_candidate(p_install uuid,p_hash text,p_email text,p_profile text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_group text:=current_setting('burimunsi.collection_id',true);
 old_install text:=current_setting('burimunsi.resolve_installation',true);
 old_hash text:=current_setting('burimunsi.resolve_device_hash',true);
 grant_row record;matches jsonb;chosen jsonb;total integer:=0;
BEGIN
 IF p_install IS NULL OR p_hash IS NULL OR p_hash !~ '^[a-f0-9]{64}$' OR p_email IS NULL
  OR length(p_email)>254 OR p_email<>lower(p_email) OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  OR p_profile IS NULL OR p_profile NOT IN('staff','internal_receiver') THEN RETURN NULL;END IF;
 BEGIN
  PERFORM set_config('burimunsi.resolve_installation',p_install::text,true);
  PERFORM set_config('burimunsi.resolve_device_hash',p_hash,true);
  FOR grant_row IN SELECT d.id,d.collection_id FROM private.burimunsi_device_grants d
   JOIN private.burimunsi_scopes s ON s.collection_id=d.collection_id
   WHERE d.installation_id=p_install AND d.token_hash=p_hash AND d.active AND d.profile=p_profile AND s.enabled LOOP
   PERFORM set_config('burimunsi.collection_id',grant_row.collection_id,true);
   SELECT jsonb_agg(jsonb_build_object('collectionId',s.collection_id,'scopeVersion',s.version,
    'receivingAccountId',s.receiving_account_id,'grantId',d.id,'grantVersion',d.version,'profile',d.profile,
    'accountId',a.id,'accountVersion',a.version,'credentialVersion',a.credential_version,
    'principalId',a.principal_user_id,'authUserId',actual.id,'adminId',au.id,'adminAuthVersion',au.auth_version,
    'approvalVersion',o.version,'email',lower(actual.email))) INTO matches
   FROM private.burimunsi_device_grants d
   JOIN private.burimunsi_scopes s ON s.collection_id=d.collection_id AND s.enabled
   JOIN app.collections c ON c.id=s.collection_id AND c.status='active'
   JOIN app.momo_receiving_accounts receiver ON receiver.id=s.receiving_account_id AND receiver.status='active'
   JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.collection_id=d.collection_id
   JOIN private.burimunsi_accounts a ON a.id=da.account_id AND a.collection_id=da.collection_id AND a.active AND NOT a.removed
   JOIN app.users u ON u.id=a.principal_user_id AND u.access_status='active'
   JOIN private.burimunsi_operator_approvals o ON o.collection_id=a.collection_id AND o.principal_user_id=u.id AND o.active
   JOIN app.admin_principal_links l ON l.user_id=u.id AND l.admin_user_id=o.admin_user_id
   JOIN app.admin_users au ON au.id=l.admin_user_id AND au.status='active'
   JOIN private.auth_principal_links auth_link ON auth_link.user_id=u.id
   JOIN auth.users actual ON actual.id=auth_link.auth_user_id
   WHERE d.id=grant_row.id AND d.installation_id=p_install AND d.token_hash=p_hash AND d.active AND d.profile=p_profile
    AND lower(au.email)=p_email AND lower(actual.email)=p_email AND actual.email_confirmed_at IS NOT NULL
    AND actual.deleted_at IS NULL AND (actual.banned_until IS NULL OR actual.banned_until<=statement_timestamp())
    AND coalesce(to_jsonb(actual)->>'is_anonymous','false')='false'
    AND private.burimunsi_operator_is_current(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities)
    AND (a.role='staff' OR au.role IN('owner','admin'))
    AND (d.profile='staff' OR(a.role='admin' AND d.custodian_account_id=a.id));
   IF matches IS NOT NULL THEN total:=total+jsonb_array_length(matches);chosen:=matches->0;END IF;
  END LOOP;
 EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
  PERFORM set_config('burimunsi.resolve_installation',coalesce(old_install,''),true);
  PERFORM set_config('burimunsi.resolve_device_hash',coalesce(old_hash,''),true);RAISE;
 END;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.resolve_installation',coalesce(old_install,''),true);
 PERFORM set_config('burimunsi.resolve_device_hash',coalesce(old_hash,''),true);
 IF total<>1 THEN RETURN NULL;END IF;
 RETURN chosen;
END;$fn$;

CREATE FUNCTION private.burimunsi_managed_email_reserve(p_challenge text,p_install uuid,p_hash text,p_email text,p_profile text,p_network text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_window text:=current_setting('burimunsi.email_preauth',true);candidate jsonb;at bigint:=app.unixepoch();
 identity_digest text;bucket_key text;bucket_limit integer;n bigint;allowed boolean:=true;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 IF p_challenge IS NULL OR p_challenge !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
  OR p_install IS NULL OR p_hash IS NULL OR p_hash !~ '^[a-f0-9]{64}$' OR p_network IS NULL OR p_network !~ '^[a-f0-9]{64}$'
  OR p_email IS NULL OR length(p_email)>254 OR p_email<>lower(p_email)
  OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  OR p_profile IS NULL OR p_profile NOT IN('staff','internal_receiver') THEN
  RETURN jsonb_build_object('allowed',false);END IF;
 identity_digest:=encode(sha256(convert_to('email:'||p_email,'UTF8')),'hex');
 BEGIN
  PERFORM set_config('burimunsi.email_preauth','1',true);
  INSERT INTO private.burimunsi_email_preauth_limits(bucket,window_start,attempts)
   VALUES('network:'||p_network,(at/900)*900,1) ON CONFLICT(bucket,window_start)
   DO UPDATE SET attempts=private.burimunsi_email_preauth_limits.attempts+1 RETURNING attempts INTO n;
  allowed:=n<=50;
  IF allowed THEN candidate:=private.burimunsi_managed_email_candidate(p_install,p_hash,p_email,p_profile);END IF;
  -- A guessed public installation UUID/email cannot exhaust somebody else's
  -- device/email budget. Charge those only after the strong device proof, and
  -- key the device bucket to this exact credential generation, not the UUID.
  IF candidate IS NOT NULL THEN
   FOR bucket_key,bucket_limit IN SELECT * FROM(VALUES
    ('device:'||encode(sha256(convert_to(p_install::text||':'||p_hash,'UTF8')),'hex'),10),
    ('email:'||identity_digest,5)) AS budgets(bucket,maximum) ORDER BY bucket LOOP
    INSERT INTO private.burimunsi_email_preauth_limits(bucket,window_start,attempts)
     VALUES(bucket_key,(at/900)*900,1) ON CONFLICT(bucket,window_start)
     DO UPDATE SET attempts=private.burimunsi_email_preauth_limits.attempts+1 RETURNING attempts INTO n;
    IF n>bucket_limit THEN allowed:=false;END IF;
   END LOOP;
  END IF;
  IF NOT allowed THEN candidate:=jsonb_build_object('allowed',false,'code','auth_rate_limited');
  ELSIF candidate IS NULL THEN candidate:=jsonb_build_object('allowed',false);
  ELSIF EXISTS(SELECT 1 FROM private.supabase_otp_challenges c WHERE c.identity_hash=identity_digest AND c.created_at+60>at) THEN
   candidate:=jsonb_build_object('allowed',false,'code','auth_rate_limited');
  ELSE
   INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status,native_preauth)
    VALUES(p_challenge,identity_digest,'email',p_email,'admin',0,at,at+300,'reserved',true);
   INSERT INTO private.burimunsi_email_preauth(challenge_id,collection_id,installation_id,token_hash,email,profile,snapshot,created_at)
    VALUES(p_challenge,candidate->>'collectionId',p_install,p_hash,p_email,p_profile,candidate,at);
   candidate:=jsonb_build_object('allowed',true,'challengeId',p_challenge,'collectionId',candidate->>'collectionId');
  END IF;
 EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('burimunsi.email_preauth',coalesce(old_window,''),true);RAISE;
 END;
 PERFORM set_config('burimunsi.email_preauth',coalesce(old_window,''),true);
 RETURN candidate;
END;$fn$;

CREATE FUNCTION private.burimunsi_managed_email_assert(p_challenge text,p_auth uuid,p_consume boolean)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_window text:=current_setting('burimunsi.email_preauth',true);binding private.burimunsi_email_preauth%ROWTYPE;
 challenge private.supabase_otp_challenges%ROWTYPE;candidate jsonb;allowed boolean:=false;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 BEGIN
  PERFORM set_config('burimunsi.email_preauth','1',true);
  SELECT * INTO binding FROM private.burimunsi_email_preauth WHERE challenge_id=p_challenge;
  IF FOUND THEN
   SELECT * INTO challenge FROM private.supabase_otp_challenges WHERE id=p_challenge FOR UPDATE;
   IF FOUND AND challenge.native_preauth AND challenge.surface='admin' AND challenge.identity_type='email'
    AND challenge.registration_allowed=0 AND challenge.identity_value=binding.email AND challenge.consumed_at IS NULL
    AND challenge.created_at<=app.unixepoch() AND challenge.expires_at>app.unixepoch() AND challenge.attempts<=5
    AND challenge.delivery_status IN('reserved','accepted','unknown')
    AND NOT EXISTS(SELECT 1 FROM private.supabase_otp_challenges newer WHERE newer.identity_hash=challenge.identity_hash
     AND newer.surface='admin' AND newer.created_at>challenge.created_at) THEN
    candidate:=private.burimunsi_managed_email_candidate(binding.installation_id,binding.token_hash,binding.email,binding.profile);
    allowed:=candidate IS NOT NULL AND candidate=binding.snapshot
     AND (p_auth IS NULL OR candidate->>'authUserId'=p_auth::text);
    IF p_consume THEN
     allowed:=allowed AND p_auth IS NOT NULL AND challenge.delivery_status IN('accepted','unknown');
     IF allowed THEN UPDATE private.supabase_otp_challenges SET consumed_at=app.unixepoch() WHERE id=p_challenge;END IF;
    END IF;
   END IF;
  END IF;
 EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('burimunsi.email_preauth',coalesce(old_window,''),true);RAISE;
 END;
 PERFORM set_config('burimunsi.email_preauth',coalesce(old_window,''),true);
 RETURN coalesce(allowed,false);
END;$fn$;

ALTER FUNCTION private.burimunsi_managed_email_candidate(uuid,text,text,text) OWNER TO postgres;
ALTER FUNCTION private.burimunsi_managed_email_reserve(text,uuid,text,text,text,text) OWNER TO postgres;
ALTER FUNCTION private.burimunsi_managed_email_assert(text,uuid,boolean) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.burimunsi_managed_email_candidate(uuid,text,text,text),
 private.burimunsi_managed_email_reserve(text,uuid,text,text,text,text),private.burimunsi_managed_email_assert(text,uuid,boolean)
 FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_managed_email_reserve(text,uuid,text,text,text,text),
 private.burimunsi_managed_email_assert(text,uuid,boolean) TO collect_runtime;
COMMIT;
