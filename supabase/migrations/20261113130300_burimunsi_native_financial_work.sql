-- Staged native work metadata only. No policies, grants, jobs or credits are
-- seeded; no managed-gateway binding or provider authentication is asserted.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regprocedure('private.burimunsi_auto_snapshot(text)') IS NULL
  OR to_regprocedure('private.burimunsi_auto_jobs_guard()') IS NULL
  OR to_regclass('private.burimunsi_native_receipt_origins') IS NULL
  OR to_regprocedure('private.burimunsi_setup_actor(text,text,text,text)') IS NULL
  OR to_regclass('private.burimunsi_native_work_grants') IS NOT NULL
  OR to_regclass('private.burimunsi_native_grant_commands') IS NOT NULL
  OR to_regclass('private.burimunsi_native_financial_work') IS NOT NULL THEN
  RAISE EXCEPTION 'burimunsi_native_work_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

-- Grant rows can only be created through the scoped owner command below.
-- A real recent Admin session approves the exact tuple; no native session is
-- promoted to an app.auth_sessions identity. Source is the admitted code hash.
CREATE TABLE private.burimunsi_native_work_grants(
 id uuid PRIMARY KEY,
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 owner text NOT NULL CHECK(owner ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 policy_version text NOT NULL CHECK(length(policy_version) BETWEEN 1 AND 128),
 approved_admin_id text NOT NULL REFERENCES app.admin_users(id),
 approved_principal_id text NOT NULL REFERENCES app.users(id),
 approval_request_id uuid NOT NULL,approval_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 approved_at bigint NOT NULL CHECK(approved_at>=0),expires_at bigint NOT NULL CHECK(expires_at>approved_at),
 enabled boolean NOT NULL DEFAULT false,version bigint NOT NULL CHECK(version>0),
 revoked_at bigint CHECK(revoked_at IS NULL OR revoked_at>=approved_at),
 UNIQUE(collection_id,owner,version),CHECK(NOT enabled OR revoked_at IS NULL)
);
CREATE TABLE private.burimunsi_native_grant_commands(
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 actor_id text NOT NULL REFERENCES app.users(id),principal_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 request_id uuid NOT NULL,operation text NOT NULL CHECK(operation IN('issue','revoke')),
 grant_id uuid NOT NULL REFERENCES private.burimunsi_native_work_grants(id),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object'),response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at bigint NOT NULL CHECK(created_at>=0),PRIMARY KEY(collection_id,actor_id,request_id)
);
ALTER TABLE private.burimunsi_native_work_grants ADD CONSTRAINT burimunsi_native_work_approval_command_fk
 FOREIGN KEY(collection_id,approved_principal_id,approval_request_id)
 REFERENCES private.burimunsi_native_grant_commands(collection_id,actor_id,request_id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE private.burimunsi_native_financial_work(
 id uuid PRIMARY KEY,
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 source_id text NOT NULL REFERENCES private.burimunsi_native_receipt_origins(source_id),
 transaction_id text NOT NULL REFERENCES app.momo_transactions(id),
 source_key text NOT NULL CHECK(source_key ~ '^[a-f0-9]{64}$'),
 source_key_content_sha256 text NOT NULL CHECK(source_key_content_sha256 ~ '^[a-f0-9]{64}$'),
 body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[a-f0-9]{64}$'),
 object_sha256 text NOT NULL CHECK(object_sha256 ~ '^[a-f0-9]{64}$'),
 source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[a-f0-9]{64}$'),
 state text NOT NULL DEFAULT 'queued' CHECK(state IN('queued','leased','waiting','completed')),
 lease_token uuid,lease_version bigint NOT NULL DEFAULT 0 CHECK(lease_version BETWEEN 0 AND 9007199254740991),
 lease_expires_at bigint,lease_admission_id uuid,lease_admission_epoch bigint,lease_source_sha256 text,
 grant_id uuid REFERENCES private.burimunsi_native_work_grants(id),grant_version bigint,
 attempts bigint NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 9007199254740991),
 next_attempt_at bigint NOT NULL,reason text CHECK(reason IS NULL OR reason IN('evidence_unavailable','identity_unavailable','source_unavailable','processing_unavailable')),
 created_at bigint NOT NULL,updated_at bigint NOT NULL CHECK(updated_at>=created_at),
 UNIQUE(collection_id,source_id),UNIQUE(collection_id,transaction_id),
 CHECK((state='leased' AND lease_token IS NOT NULL AND lease_version>0 AND lease_expires_at IS NOT NULL
    AND lease_admission_id IS NOT NULL AND lease_admission_epoch IS NOT NULL AND lease_admission_epoch>0
    AND lease_source_sha256 IS NOT NULL AND lease_source_sha256 ~ '^[a-f0-9]{64}$'
    AND grant_id IS NOT NULL AND grant_version IS NOT NULL AND grant_version>0 AND reason IS NULL)
  OR (state<>'leased' AND lease_token IS NULL AND lease_expires_at IS NULL AND lease_admission_id IS NULL
    AND lease_admission_epoch IS NULL AND lease_source_sha256 IS NULL AND grant_id IS NULL AND grant_version IS NULL)),
 CHECK((state='waiting' AND reason IS NOT NULL) OR (state<>'waiting' AND reason IS NULL))
);
CREATE INDEX burimunsi_native_financial_work_due ON private.burimunsi_native_financial_work(collection_id,state,next_attempt_at,created_at,id);

DO $rls$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_native_work_grants','burimunsi_native_grant_commands','burimunsi_native_financial_work'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE private.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime',t);
  EXECUTE format('CREATE POLICY native_work_frame ON private.%I TO postgres USING (current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.native_work_frame'',true)=''1'' AND collection_id=current_setting(''burimunsi.collection_id'',true)) WITH CHECK (current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.native_work_frame'',true)=''1'' AND collection_id=current_setting(''burimunsi.collection_id'',true))',t);
  IF t IN('burimunsi_native_work_grants','burimunsi_native_grant_commands') THEN
   EXECUTE format('CREATE POLICY native_work_operator ON private.%I FOR SELECT TO postgres USING (current_setting(''role'',true)=''none'' AND private._collect_fence_operator())',t);
  ELSE
   EXECUTE format('CREATE POLICY native_work_operator ON private.%I TO postgres USING (current_setting(''role'',true)=''none'' AND private._collect_fence_operator()) WITH CHECK (current_setting(''role'',true)=''none'' AND private._collect_fence_operator())',t);
  END IF;
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
 END LOOP;
END;$rls$;

CREATE FUNCTION private.burimunsi_native_work_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'native_work_immutable' USING ERRCODE='23514';END IF;
 IF TG_TABLE_NAME='burimunsi_native_work_grants' THEN
  IF ROW(NEW.id,NEW.collection_id,NEW.owner,NEW.source_sha256,NEW.policy_version,NEW.approved_admin_id,NEW.approved_principal_id,NEW.approval_request_id,NEW.approval_session_id,NEW.approved_at,NEW.expires_at,NEW.version)
    IS DISTINCT FROM ROW(OLD.id,OLD.collection_id,OLD.owner,OLD.source_sha256,OLD.policy_version,OLD.approved_admin_id,OLD.approved_principal_id,OLD.approval_request_id,OLD.approval_session_id,OLD.approved_at,OLD.expires_at,OLD.version)
   OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at)
   OR (NOT OLD.enabled AND NEW.enabled) THEN RAISE EXCEPTION 'native_work_grant_immutable' USING ERRCODE='23514';END IF;
 ELSE
  IF ROW(NEW.id,NEW.collection_id,NEW.source_id,NEW.transaction_id,NEW.source_key,NEW.source_key_content_sha256,NEW.body_sha256,NEW.object_sha256,NEW.source_fingerprint,NEW.created_at)
    IS DISTINCT FROM ROW(OLD.id,OLD.collection_id,OLD.source_id,OLD.transaction_id,OLD.source_key,OLD.source_key_content_sha256,OLD.body_sha256,OLD.object_sha256,OLD.source_fingerprint,OLD.created_at)
   OR (OLD.state='completed' AND NEW IS DISTINCT FROM OLD) THEN RAISE EXCEPTION 'native_work_immutable' USING ERRCODE='23514';END IF;
 END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_work_immutable() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER native_work_immutable BEFORE UPDATE OR DELETE ON private.burimunsi_native_work_grants FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_work_immutable();
CREATE TRIGGER native_work_immutable BEFORE UPDATE OR DELETE ON private.burimunsi_native_financial_work FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_work_immutable();
ALTER TABLE private.burimunsi_native_work_grants ENABLE ALWAYS TRIGGER native_work_immutable;
ALTER TABLE private.burimunsi_native_financial_work ENABLE ALWAYS TRIGGER native_work_immutable;
CREATE TRIGGER native_grant_commands_retain BEFORE UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_native_grant_commands
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_native_grant_commands ENABLE ALWAYS TRIGGER native_grant_commands_retain;
CREATE TRIGGER native_work_grants_no_truncate BEFORE TRUNCATE ON private.burimunsi_native_work_grants
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
CREATE TRIGGER native_financial_work_no_truncate BEFORE TRUNCATE ON private.burimunsi_native_financial_work
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_native_work_grants ENABLE ALWAYS TRIGGER native_work_grants_no_truncate;
ALTER TABLE private.burimunsi_native_financial_work ENABLE ALWAYS TRIGGER native_financial_work_no_truncate;
CREATE FUNCTION private._burimunsi_native_grant_write_guard() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime'
  OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true'
  OR current_setting('burimunsi.native_grant_command_frame',true) IS DISTINCT FROM '1' THEN
  RAISE EXCEPTION 'native_grant_command_required' USING ERRCODE='42501';END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;$fn$;
REVOKE ALL ON FUNCTION private._burimunsi_native_grant_write_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER native_grant_write_guard BEFORE INSERT OR UPDATE OR DELETE ON private.burimunsi_native_work_grants
 FOR EACH ROW EXECUTE FUNCTION private._burimunsi_native_grant_write_guard();
CREATE TRIGGER native_grant_write_guard BEFORE INSERT ON private.burimunsi_native_grant_commands
 FOR EACH ROW EXECUTE FUNCTION private._burimunsi_native_grant_write_guard();
ALTER TABLE private.burimunsi_native_work_grants ENABLE ALWAYS TRIGGER native_grant_write_guard;
ALTER TABLE private.burimunsi_native_grant_commands ENABLE ALWAYS TRIGGER native_grant_write_guard;

-- No request can assert its own approver: the existing Admin BFF/session,
-- permissions and recent email proof establish the bound owner and session.
CREATE FUNCTION private._burimunsi_native_grant_actor(p_actor text,p_cookie text,p_origin text,p_public text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;f private.collect_fence_admissions%ROWTYPE;
BEGIN
 a:=private.burimunsi_setup_actor(p_actor,p_cookie,p_origin,p_public);
 f:=private._collect_fence_admission(current_setting('collect.fence_admission_id',true)::uuid,
  current_setting('collect.fence_epoch',true)::bigint,current_setting('collect.fence_source_sha256',true));
 IF f.kind IS DISTINCT FROM 'http_admin' OR NOT private.collect_owner_is(p_actor,a->>'principalId',private.collect_owner_email()) THEN
  RAISE EXCEPTION 'native_grant_owner_required' USING ERRCODE='42501';END IF;
 RETURN a||jsonb_build_object('adminId',p_actor,'sourceCodeSha256',f.source_sha256);
END;$fn$;

CREATE FUNCTION private.burimunsi_native_grant_issue(p_actor text,p_cookie text,p_origin text,p_public text,
 p_collection text,p_request uuid,p_grant uuid,p_owner text,p_version bigint,p_policy text,p_expires bigint,p_enabled boolean DEFAULT false) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;p private.burimunsi_integration_policies%ROWTYPE;prior private.burimunsi_native_grant_commands%ROWTYPE;
 payload jsonb;fingerprint text;response jsonb;at_ms bigint;
 old_group text:=current_setting('burimunsi.collection_id',true);old_frame text:=current_setting('burimunsi.native_work_frame',true);
 old_command text:=current_setting('burimunsi.native_grant_command_frame',true);
BEGIN
 a:=private._burimunsi_native_grant_actor(p_actor,p_cookie,p_origin,p_public);
 IF private.assert_actor('payments.reconcile',NULL,NULL,2,300) IS DISTINCT FROM a->>'principalId' THEN
  RAISE EXCEPTION 'native_grant_financial_authority_required' USING ERRCODE='42501';END IF;
 IF p_collection IS NULL OR length(p_collection) NOT BETWEEN 1 AND 200 OR p_request IS NULL OR p_grant IS NULL
  OR p_owner IS NULL OR p_owner !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$' OR p_version IS NULL OR p_version NOT BETWEEN 1 AND 9007199254740991
  OR p_policy IS NULL OR length(p_policy) NOT BETWEEN 1 AND 128 OR p_expires IS NULL OR p_expires>9007199254740991 OR p_enabled IS NULL THEN
  RAISE EXCEPTION 'native_grant_invalid' USING ERRCODE='22023';END IF;
 payload:=jsonb_build_object('operation','issue','groupId',p_collection,'grantId',p_grant,'owner',p_owner,'version',p_version,
  'policyVersion',p_policy,'expiresAt',p_expires,'enabled',p_enabled,'sourceCodeSha256',a->>'sourceCodeSha256');
 fingerprint:=encode(sha256(convert_to(payload::text,'UTF8')),'hex');
 PERFORM set_config('burimunsi.collection_id',p_collection,true);PERFORM set_config('burimunsi.native_work_frame','1',true);
 PERFORM set_config('burimunsi.native_grant_command_frame','1',true);
 SELECT * INTO prior FROM private.burimunsi_native_grant_commands WHERE collection_id=p_collection AND actor_id=a->>'principalId' AND request_id=p_request;
 IF FOUND THEN
  IF prior.operation<>'issue' OR prior.principal_session_id<>a->>'sessionId' OR prior.fingerprint<>fingerprint OR prior.payload<>payload THEN
   RAISE EXCEPTION 'native_grant_request_conflict' USING ERRCODE='23505';END IF;
  response:=prior.response;
 ELSE
  SELECT policy.* INTO p FROM private.burimunsi_integration_policies policy
   JOIN private.burimunsi_scopes s ON s.collection_id=policy.collection_id
   JOIN app.collections c ON c.id=s.collection_id AND c.status='active'
   JOIN app.momo_receiving_accounts account ON account.id=s.receiving_account_id
   WHERE policy.collection_id=p_collection AND policy.approved_version=p_policy AND policy.revoked_at IS NULL
    AND (NOT p_enabled OR (account.status='active' AND account.profile_status='approved'
     AND account.profile_version=policy.provider_profile_version
     AND encode(sha256(convert_to(account.profile_json,'UTF8')),'hex')=policy.provider_profile_sha256))
   FOR SHARE OF policy,s,c,account;
  at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
  IF NOT FOUND OR p.approved_at>at_ms OR p.expires_at<=at_ms OR p_expires<=at_ms OR p_expires>p.expires_at THEN
   RAISE EXCEPTION 'native_grant_policy_unavailable' USING ERRCODE='42501';END IF;
  IF p_enabled AND EXISTS(SELECT 1 FROM private.burimunsi_native_work_grants w WHERE w.collection_id=p_collection AND w.owner=p_owner
   AND w.enabled AND w.revoked_at IS NULL AND w.expires_at>at_ms) THEN RAISE EXCEPTION 'native_grant_owner_conflict' USING ERRCODE='23505';END IF;
  INSERT INTO private.burimunsi_native_work_grants(id,collection_id,owner,source_sha256,policy_version,approved_admin_id,approved_principal_id,
   approval_request_id,approval_session_id,approved_at,expires_at,enabled,version)
  VALUES(p_grant,p_collection,p_owner,a->>'sourceCodeSha256',p_policy,p_actor,a->>'principalId',p_request,a->>'sessionId',at_ms,p_expires,p_enabled,p_version);
  response:=jsonb_build_object('grantId',p_grant,'groupId',p_collection,'owner',p_owner,'version',p_version,'enabled',p_enabled,'expiresAt',p_expires);
  INSERT INTO private.burimunsi_native_grant_commands(collection_id,actor_id,principal_session_id,request_id,operation,grant_id,fingerprint,payload,response,created_at)
  VALUES(p_collection,a->>'principalId',a->>'sessionId',p_request,'issue',p_grant,fingerprint,payload,response,at_ms);
  INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
  VALUES(a->>'principalId',a->>'sessionId','burimunsi.native_worker.issue','collection',p_collection,p_request::text,payload::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 END IF;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);
 PERFORM set_config('burimunsi.native_grant_command_frame',coalesce(old_command,''),true);
 RETURN response;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);PERFORM set_config('burimunsi.native_grant_command_frame',coalesce(old_command,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_native_grant_revoke(p_actor text,p_cookie text,p_origin text,p_public text,
 p_collection text,p_request uuid,p_grant uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;g private.burimunsi_native_work_grants%ROWTYPE;prior private.burimunsi_native_grant_commands%ROWTYPE;
 payload jsonb;fingerprint text;response jsonb;at_ms bigint;applied boolean;
 old_group text:=current_setting('burimunsi.collection_id',true);old_frame text:=current_setting('burimunsi.native_work_frame',true);
 old_command text:=current_setting('burimunsi.native_grant_command_frame',true);
BEGIN
 a:=private._burimunsi_native_grant_actor(p_actor,p_cookie,p_origin,p_public);
 IF p_collection IS NULL OR length(p_collection) NOT BETWEEN 1 AND 200 OR p_request IS NULL OR p_grant IS NULL THEN
  RAISE EXCEPTION 'native_grant_invalid' USING ERRCODE='22023';END IF;
 payload:=jsonb_build_object('operation','revoke','groupId',p_collection,'grantId',p_grant,'sourceCodeSha256',a->>'sourceCodeSha256');
 fingerprint:=encode(sha256(convert_to(payload::text,'UTF8')),'hex');
 PERFORM set_config('burimunsi.collection_id',p_collection,true);PERFORM set_config('burimunsi.native_work_frame','1',true);
 PERFORM set_config('burimunsi.native_grant_command_frame','1',true);
 SELECT * INTO prior FROM private.burimunsi_native_grant_commands WHERE collection_id=p_collection AND actor_id=a->>'principalId' AND request_id=p_request;
 IF FOUND THEN
  IF prior.operation<>'revoke' OR prior.principal_session_id<>a->>'sessionId' OR prior.fingerprint<>fingerprint OR prior.payload<>payload THEN
   RAISE EXCEPTION 'native_grant_request_conflict' USING ERRCODE='23505';END IF;
  response:=prior.response;
 ELSE
  SELECT * INTO g FROM private.burimunsi_native_work_grants WHERE id=p_grant AND collection_id=p_collection FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'native_grant_unavailable' USING ERRCODE='42501';END IF;
  at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;applied:=g.revoked_at IS NULL;
  IF applied THEN UPDATE private.burimunsi_native_work_grants SET enabled=false,revoked_at=at_ms WHERE id=p_grant;END IF;
  response:=jsonb_build_object('grantId',p_grant,'groupId',p_collection,'revoked',true,'applied',applied);
  INSERT INTO private.burimunsi_native_grant_commands(collection_id,actor_id,principal_session_id,request_id,operation,grant_id,fingerprint,payload,response,created_at)
  VALUES(p_collection,a->>'principalId',a->>'sessionId',p_request,'revoke',p_grant,fingerprint,payload,response,at_ms);
  INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
  VALUES(a->>'principalId',a->>'sessionId','burimunsi.native_worker.revoke','collection',p_collection,p_request::text,payload::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 END IF;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);
 PERFORM set_config('burimunsi.native_grant_command_frame',coalesce(old_command,''),true);
 RETURN response;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);PERFORM set_config('burimunsi.native_grant_command_frame',coalesce(old_command,''),true);RAISE;
END;$fn$;

-- A lost response can be reconciled under the current fresh Owner session
-- without replaying a mutation or assuming the original session still exists.
CREATE FUNCTION private.burimunsi_native_grant_command(p_actor text,p_cookie text,p_origin text,p_public text,
 p_collection text,p_request uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;prior private.burimunsi_native_grant_commands%ROWTYPE;response jsonb;
 old_group text:=current_setting('burimunsi.collection_id',true);old_frame text:=current_setting('burimunsi.native_work_frame',true);
BEGIN
 a:=private._burimunsi_native_grant_actor(p_actor,p_cookie,p_origin,p_public);
 IF p_collection IS NULL OR length(p_collection) NOT BETWEEN 1 AND 200 OR p_request IS NULL THEN
  RAISE EXCEPTION 'native_grant_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.collection_id',p_collection,true);PERFORM set_config('burimunsi.native_work_frame','1',true);
 SELECT * INTO prior FROM private.burimunsi_native_grant_commands WHERE collection_id=p_collection AND actor_id=a->>'principalId' AND request_id=p_request;
 IF FOUND THEN response:=jsonb_build_object('found',true,'operation',prior.operation,'receipt',prior.response);
 ELSE response:=jsonb_build_object('found',false);END IF;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);
 RETURN response;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Returns only the immutable, genuinely native, keyed lineage. The existing
-- snapshot revalidates current capture grant, consent, storage and actor; it
-- does not make detection-only parsing profiles into financial approval.
CREATE FUNCTION private._burimunsi_native_work_source(p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE snapshot jsonb;v record;scope text:=current_setting('burimunsi.collection_id',true);
 old_obs text:=current_setting('burimunsi.observation_frame',true);
 old_native text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 IF scope IS NULL OR scope='' THEN RAISE EXCEPTION 'native_work_scope_required' USING ERRCODE='42501';END IF;
 snapshot:=private.burimunsi_auto_snapshot(p_source);
 PERFORM set_config('burimunsi.observation_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT o.collection_id,o.source_id,o.principal_user_id,o.fingerprint,o.body_sha256,o.object_sha256,o.size_bytes,
  q.source_key,q.source_key_content_sha256,q.source_key_body_sha256,j.transaction_id,t.mode
 INTO v FROM private.burimunsi_unresolved_observations o
 JOIN private.burimunsi_observation_requests q ON q.source_id=o.source_id AND q.collection_id=o.collection_id
 JOIN private.burimunsi_native_receipt_origins n ON n.source_id=o.source_id AND n.collection_id=o.collection_id
 JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=o.source_id AND j.collection_id=o.collection_id
 JOIN private.burimunsi_transaction_scopes x ON x.transaction_id=j.transaction_id AND x.collection_id=o.collection_id
  AND x.native_source_id=o.source_id AND x.source_binding_id IS NULL AND x.source_binding_version IS NULL
 JOIN private.burimunsi_scopes c ON c.collection_id=x.collection_id AND c.receiving_account_id=x.receiving_account_id
  AND j.receiving_account_id=x.receiving_account_id
 JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
 JOIN app.sms_receipts r ON r.id=o.source_id AND r.evidence_level='client_received' AND r.originating_session_id IS NULL
 WHERE o.source_id=p_source AND o.collection_id=scope AND j.state='completed' AND j.relation='accepted'
  AND j.source_fingerprint=o.fingerprint AND n.fingerprint=o.fingerprint AND n.body_sha256=o.body_sha256
  AND n.object_sha256=o.object_sha256 AND n.principal_user_id=o.principal_user_id
  AND q.source_key IS NOT NULL AND q.source_key_content_sha256 IS NOT NULL AND q.source_key_body_sha256=o.body_sha256
  AND r.owner_user_id=o.principal_user_id AND r.body_sha256=o.body_sha256 AND r.object_sha256=o.object_sha256
 FOR SHARE OF o,q,n,j,x,c,t,r;
 IF NOT FOUND OR snapshot->'proof'->>'sourceId' IS DISTINCT FROM p_source THEN
  RAISE EXCEPTION 'native_work_source_unavailable' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
 RETURN jsonb_build_object('groupId',v.collection_id,'sourceId',v.source_id,'transactionId',v.transaction_id,
  'sourceKey',v.source_key,'sourceKeyContentSha256',v.source_key_content_sha256,'sourceKeyBodySha256',v.source_key_body_sha256,
  'bodySha256',v.body_sha256,'objectSha256',v.object_sha256,'sourceFingerprint',v.fingerprint,
  'ownerUserId',v.principal_user_id,'objectSizeBytes',v.size_bytes,'transactionMode',v.mode);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);RAISE;
END;$fn$;

-- A current admitted jobs fence + explicit scoped grant + currently enabled
-- policy are necessary but not sufficient for a financial posting.
CREATE FUNCTION private._burimunsi_native_work_authority(p_grant uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE f private.collect_fence_admissions%ROWTYPE;g private.burimunsi_native_work_grants%ROWTYPE;
 scope text:=current_setting('burimunsi.collection_id',true);at_ms bigint;
 old_frame text:=current_setting('burimunsi.native_work_frame',true);
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 f:=private._collect_fence_admission(current_setting('collect.fence_admission_id',true)::uuid,
  current_setting('collect.fence_epoch',true)::bigint,current_setting('collect.fence_source_sha256',true));
 IF f.kind<>'jobs' OR scope IS NULL OR scope='' THEN RAISE EXCEPTION 'native_work_authority_required' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.native_work_frame','1',true);
 SELECT w.* INTO g FROM private.burimunsi_native_work_grants w
 JOIN private.burimunsi_native_grant_commands cmd ON cmd.collection_id=w.collection_id AND cmd.actor_id=w.approved_principal_id
  AND cmd.request_id=w.approval_request_id AND cmd.principal_session_id=w.approval_session_id AND cmd.operation='issue' AND cmd.grant_id=w.id
  AND cmd.created_at=w.approved_at AND cmd.payload=jsonb_build_object('operation','issue','groupId',w.collection_id,'grantId',w.id,
   'owner',w.owner,'version',w.version,'policyVersion',w.policy_version,'expiresAt',w.expires_at,'enabled',true,'sourceCodeSha256',w.source_sha256)
  AND cmd.fingerprint=encode(sha256(convert_to(cmd.payload::text,'UTF8')),'hex')
 JOIN private.burimunsi_integration_policies p ON p.collection_id=w.collection_id
 JOIN private.burimunsi_scopes s ON s.collection_id=w.collection_id
 JOIN app.momo_receiving_accounts account ON account.id=s.receiving_account_id AND account.status='active'
  AND account.profile_status='approved' AND account.profile_version=p.provider_profile_version
  AND encode(sha256(convert_to(account.profile_json,'UTF8')),'hex')=p.provider_profile_sha256
 JOIN app.admin_users a ON a.id=w.approved_admin_id AND a.role='owner' AND a.status='active'
 JOIN app.admin_principal_links l ON l.admin_user_id=a.id AND l.user_id=w.approved_principal_id
 JOIN app.users u ON u.id=w.approved_principal_id AND u.access_status='active'
 JOIN app.admin_account_role_capabilities rc ON rc.role=a.role AND rc.permission='payments.reconcile'
 JOIN app.admin_grants ag ON ag.user_id=u.id AND ag.permission='payments.reconcile'
 WHERE w.id=p_grant AND w.collection_id=scope AND w.enabled AND w.revoked_at IS NULL
  AND w.source_sha256=f.source_sha256 AND p.approved_version=w.policy_version
  AND private.collect_owner_is(w.approved_admin_id,w.approved_principal_id,a.email)
  AND p.processing_enabled AND p.scheduler_enabled AND p.identity_enabled AND p.revoked_at IS NULL AND s.enabled
 FOR SHARE OF w,cmd,p,s,account,a,l,u,rc,ag;
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 IF NOT FOUND OR g.approved_at>at_ms OR g.expires_at<=at_ms OR NOT EXISTS(
  SELECT 1 FROM private.burimunsi_integration_policies p WHERE p.collection_id=scope AND p.approved_at<=at_ms AND p.expires_at>at_ms)
 THEN RAISE EXCEPTION 'native_work_authority_required' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('workerGrantId',g.id,'workerGrantVersion',g.version,'owner',g.owner,
  'admissionId',f.admission_id,'admissionEpoch',f.epoch,'sourceCodeSha256',f.source_sha256);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Enqueue locks and rechecks the scoped grant in the same transaction as the
-- source and insert. A revocation that commits first prevents even metadata
-- enqueue; a concurrent revocation waits for this transaction to finish.
-- Replays return the existing job, not a second credit.
CREATE FUNCTION private.burimunsi_native_work_enqueue(p_grant uuid,p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;s jsonb;j private.burimunsi_native_financial_work%ROWTYPE;at_ms bigint;
 old_frame text:=current_setting('burimunsi.native_work_frame',true);
BEGIN
 a:=private._burimunsi_native_work_authority(p_grant);
 s:=private._burimunsi_native_work_source(p_source);
 IF private._burimunsi_native_work_authority(p_grant) IS DISTINCT FROM a THEN
  RAISE EXCEPTION 'native_work_authority_changed' USING ERRCODE='40001';END IF;
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 PERFORM set_config('burimunsi.native_work_frame','1',true);
 INSERT INTO private.burimunsi_native_financial_work(id,collection_id,source_id,transaction_id,source_key,source_key_content_sha256,
  body_sha256,object_sha256,source_fingerprint,next_attempt_at,created_at,updated_at)
 VALUES(gen_random_uuid(),s->>'groupId',s->>'sourceId',s->>'transactionId',s->>'sourceKey',s->>'sourceKeyContentSha256',
  s->>'bodySha256',s->>'objectSha256',s->>'sourceFingerprint',at_ms,at_ms,at_ms)
 ON CONFLICT DO NOTHING;
 SELECT * INTO j FROM private.burimunsi_native_financial_work WHERE collection_id=s->>'groupId' AND (source_id=p_source OR transaction_id=s->>'transactionId') FOR UPDATE;
 IF NOT FOUND OR ROW(j.source_id,j.transaction_id,j.source_key,j.source_key_content_sha256,j.body_sha256,j.object_sha256,j.source_fingerprint)
  IS DISTINCT FROM ROW(s->>'sourceId',s->>'transactionId',s->>'sourceKey',s->>'sourceKeyContentSha256',s->>'bodySha256',s->>'objectSha256',s->>'sourceFingerprint')
 THEN RAISE EXCEPTION 'native_work_source_conflict' USING ERRCODE='23505';END IF;
 PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('jobId',j.id,'state',j.state,'durable',true);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_native_work_candidates(p_grant uuid,p_limit integer) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;outcome jsonb;at_ms bigint;old_frame text:=current_setting('burimunsi.native_work_frame',true);
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'native_work_invalid' USING ERRCODE='22023';END IF;
 a:=private._burimunsi_native_work_authority(p_grant);at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 PERFORM set_config('burimunsi.native_work_frame','1',true);
 SELECT coalesce(jsonb_agg(id ORDER BY next_attempt_at,created_at,id),'[]'::jsonb) INTO outcome FROM (
  SELECT id,next_attempt_at,created_at FROM private.burimunsi_native_financial_work
  WHERE collection_id=current_setting('burimunsi.collection_id',true) AND
   ((state IN('queued','waiting') AND next_attempt_at<=at_ms) OR (state='leased' AND lease_expires_at<=at_ms))
  ORDER BY next_attempt_at,created_at,id LIMIT p_limit) due;
 PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);RETURN outcome;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_native_work_claim(p_grant uuid,p_job uuid,p_lease_ms bigint) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;s jsonb;j private.burimunsi_native_financial_work%ROWTYPE;at_ms bigint;
 old_frame text:=current_setting('burimunsi.native_work_frame',true);
BEGIN
 IF p_lease_ms IS NULL OR p_lease_ms NOT BETWEEN 30000 AND 600000 THEN RAISE EXCEPTION 'native_work_invalid' USING ERRCODE='22023';END IF;
 a:=private._burimunsi_native_work_authority(p_grant);
 PERFORM set_config('burimunsi.native_work_frame','1',true);
 SELECT * INTO j FROM private.burimunsi_native_financial_work WHERE id=p_job AND collection_id=current_setting('burimunsi.collection_id',true) FOR UPDATE;
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 IF NOT FOUND OR NOT ((j.state IN('queued','waiting') AND j.next_attempt_at<=at_ms) OR (j.state='leased' AND j.lease_expires_at<=at_ms))
  OR j.attempts>=9007199254740991 OR j.lease_version>=9007199254740991 THEN
  RAISE EXCEPTION 'native_work_lease_unavailable' USING ERRCODE='55000';END IF;
 s:=private._burimunsi_native_work_source(j.source_id);
 IF ROW(j.transaction_id,j.source_key,j.source_key_content_sha256,j.body_sha256,j.object_sha256,j.source_fingerprint)
  IS DISTINCT FROM ROW(s->>'transactionId',s->>'sourceKey',s->>'sourceKeyContentSha256',s->>'bodySha256',s->>'objectSha256',s->>'sourceFingerprint') THEN
  RAISE EXCEPTION 'native_work_source_changed' USING ERRCODE='40001';END IF;
 IF private._burimunsi_native_work_authority(p_grant) IS DISTINCT FROM a THEN
  RAISE EXCEPTION 'native_work_authority_changed' USING ERRCODE='40001';END IF;
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 UPDATE private.burimunsi_native_financial_work SET state='leased',lease_token=gen_random_uuid(),lease_version=lease_version+1,
  lease_expires_at=at_ms+p_lease_ms,lease_admission_id=(a->>'admissionId')::uuid,lease_admission_epoch=(a->>'admissionEpoch')::bigint,
  lease_source_sha256=a->>'sourceCodeSha256',grant_id=(a->>'workerGrantId')::uuid,grant_version=(a->>'workerGrantVersion')::bigint,
  attempts=attempts+1,reason=NULL,updated_at=at_ms WHERE id=j.id RETURNING * INTO j;
 PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('jobId',j.id,'leaseToken',j.lease_token,'leaseVersion',j.lease_version,'leaseExpiresAt',j.lease_expires_at);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Must be called in the SAME transaction as custody revalidation and posting.
CREATE FUNCTION private.burimunsi_native_work_assert(p_job uuid,p_token uuid,p_version bigint) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;s jsonb;j private.burimunsi_native_financial_work%ROWTYPE;at_ms bigint;
 old_frame text:=current_setting('burimunsi.native_work_frame',true);
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();PERFORM set_config('burimunsi.native_work_frame','1',true);
 SELECT * INTO j FROM private.burimunsi_native_financial_work WHERE id=p_job AND collection_id=current_setting('burimunsi.collection_id',true) FOR UPDATE;
 IF NOT FOUND OR j.state<>'leased' OR j.lease_token IS DISTINCT FROM p_token OR j.lease_version IS DISTINCT FROM p_version THEN
  RAISE EXCEPTION 'native_work_lease_unavailable' USING ERRCODE='55000';END IF;
 a:=private._burimunsi_native_work_authority(j.grant_id);s:=private._burimunsi_native_work_source(j.source_id);
 IF private._burimunsi_native_work_authority(j.grant_id) IS DISTINCT FROM a THEN
  RAISE EXCEPTION 'native_work_authority_changed' USING ERRCODE='40001';END IF;
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 IF j.lease_expires_at<=at_ms OR j.grant_version IS DISTINCT FROM (a->>'workerGrantVersion')::bigint
  OR j.lease_admission_id IS DISTINCT FROM (a->>'admissionId')::uuid
  OR j.lease_admission_epoch IS DISTINCT FROM (a->>'admissionEpoch')::bigint
  OR j.lease_source_sha256 IS DISTINCT FROM a->>'sourceCodeSha256'
  OR ROW(j.transaction_id,j.source_key,j.source_key_content_sha256,j.body_sha256,j.object_sha256,j.source_fingerprint)
   IS DISTINCT FROM ROW(s->>'transactionId',s->>'sourceKey',s->>'sourceKeyContentSha256',s->>'bodySha256',s->>'objectSha256',s->>'sourceFingerprint') THEN
  RAISE EXCEPTION 'native_work_lease_unavailable' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);
 RETURN s||a||jsonb_build_object('contractVersion',1,'kind','native_receipt','jobId',j.id,
  'leaseToken',j.lease_token,'leaseVersion',j.lease_version,'leaseExpiresAt',j.lease_expires_at);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Missing evidence is revisited on a bounded timer, without a manual SMS
-- verification screen or changing the historical capture's provenance.
CREATE FUNCTION private.burimunsi_native_work_defer(p_job uuid,p_token uuid,p_version bigint,p_reason text,p_delay_ms bigint) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;at_ms bigint;old_frame text:=current_setting('burimunsi.native_work_frame',true);
BEGIN
 IF p_reason IS NULL OR p_reason NOT IN('evidence_unavailable','identity_unavailable','source_unavailable','processing_unavailable')
  OR p_delay_ms IS NULL OR p_delay_ms NOT BETWEEN 30000 AND 86400000 THEN RAISE EXCEPTION 'native_work_invalid' USING ERRCODE='22023';END IF;
 a:=private.burimunsi_native_work_assert(p_job,p_token,p_version);at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 IF (a->>'leaseExpiresAt')::bigint<=at_ms THEN RAISE EXCEPTION 'native_work_lease_unavailable' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.native_work_frame','1',true);
 UPDATE private.burimunsi_native_financial_work SET state='waiting',lease_token=NULL,lease_expires_at=NULL,lease_admission_id=NULL,
  lease_admission_epoch=NULL,lease_source_sha256=NULL,grant_id=NULL,grant_version=NULL,reason=p_reason,
  next_attempt_at=at_ms+p_delay_ms,updated_at=at_ms WHERE id=p_job;
 PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('jobId',p_job,'state','waiting','nextAttemptAt',at_ms+p_delay_ms);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Completion is a readback of the existing Collect financial link and ledger,
-- never a credit or a caller-asserted success. Revalidation occurs after all
-- locks and before changing work state in the same transaction.
CREATE FUNCTION private.burimunsi_native_work_complete(p_job uuid,p_token uuid,p_version bigint) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;again jsonb;n bigint;at_ms bigint;
 old_frame text:=current_setting('burimunsi.native_work_frame',true);
BEGIN
 a:=private.burimunsi_native_work_assert(p_job,p_token,p_version);
 PERFORM 1 FROM app.momo_transactions t
 JOIN app.momo_financial_links f ON f.transaction_id=t.id
 JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=a->>'groupId'
 JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=p.collection_id
  AND l.member_id=p.member_id AND l.kind='contribution'
 WHERE t.id=a->>'transactionId' AND t.event_kind='incoming_receipt' AND t.has_conflict=0
  AND t.allocation_state='linked' AND t.amount_minor>0 AND t.amount_minor=p.amount_minor AND p.amount_minor=l.amount_minor
  AND t.currency='RWF' AND p.currency=t.currency AND l.currency=t.currency
  AND p.status IN('confirmed','reconciled') AND p.member_id=f.beneficiary_member_id
  AND l.reverses_entry_id IS NULL
  AND NOT EXISTS(SELECT 1 FROM app.ledger_entries reversal WHERE reversal.reverses_entry_id=l.id)
  AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict')
 FOR UPDATE OF t,f,p,l;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 THEN RAISE EXCEPTION 'native_work_posting_outcome_missing' USING ERRCODE='55000';END IF;
 again:=private.burimunsi_native_work_assert(p_job,p_token,p_version);
 IF again IS DISTINCT FROM a THEN RAISE EXCEPTION 'native_work_authority_changed' USING ERRCODE='40001';END IF;
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 IF (again->>'leaseExpiresAt')::bigint<=at_ms THEN RAISE EXCEPTION 'native_work_lease_unavailable' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.native_work_frame','1',true);
 UPDATE private.burimunsi_native_financial_work SET state='completed',lease_token=NULL,lease_expires_at=NULL,lease_admission_id=NULL,
  lease_admission_epoch=NULL,lease_source_sha256=NULL,grant_id=NULL,grant_version=NULL,reason=NULL,updated_at=at_ms WHERE id=p_job;
 PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('jobId',p_job,'state','completed','transactionId',a->>'transactionId');
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_work_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

REVOKE ALL ON FUNCTION private._burimunsi_native_work_source(text),private._burimunsi_native_work_authority(uuid),
 private._burimunsi_native_grant_actor(text,text,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
REVOKE ALL ON FUNCTION private.burimunsi_native_work_enqueue(uuid,text),private.burimunsi_native_work_candidates(uuid,integer),
 private.burimunsi_native_work_claim(uuid,uuid,bigint),private.burimunsi_native_work_assert(uuid,uuid,bigint),
 private.burimunsi_native_work_defer(uuid,uuid,bigint,text,bigint),private.burimunsi_native_work_complete(uuid,uuid,bigint),
 private.burimunsi_native_grant_issue(text,text,text,text,text,uuid,uuid,text,bigint,text,bigint,boolean),
 private.burimunsi_native_grant_revoke(text,text,text,text,text,uuid,uuid),
 private.burimunsi_native_grant_command(text,text,text,text,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_work_enqueue(uuid,text),private.burimunsi_native_work_candidates(uuid,integer),
 private.burimunsi_native_work_claim(uuid,uuid,bigint),private.burimunsi_native_work_assert(uuid,uuid,bigint),
 private.burimunsi_native_work_defer(uuid,uuid,bigint,text,bigint),private.burimunsi_native_work_complete(uuid,uuid,bigint),
 private.burimunsi_native_grant_issue(text,text,text,text,text,uuid,uuid,text,bigint,text,bigint,boolean),
 private.burimunsi_native_grant_revoke(text,text,text,text,text,uuid,uuid),
 private.burimunsi_native_grant_command(text,text,text,text,text,uuid) TO collect_runtime;
COMMIT;
