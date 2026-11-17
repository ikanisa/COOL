-- Additive receiver authorization and truthful, target-bound handoff.
-- No business, user, PIN, device or receiving record is seeded or deleted.
-- Existing canonical capture, source, jobs and ledger history is preserved.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.burimunsi_pin_context()') IS NULL
  OR to_regclass('private.burimunsi_gateway_handoffs') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_handoff_install_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;
ALTER TABLE private.burimunsi_scope_setup_commands DROP CONSTRAINT burimunsi_scope_setup_commands_operation_check;
ALTER TABLE private.burimunsi_scope_setup_commands ADD CONSTRAINT burimunsi_scope_setup_commands_operation_check
 CHECK(operation IN('prepare','activate','cancelled','prepare_replacement','finalize_replacement'));
-- Replacement preparations contain the same protected encrypted code delivery
-- as activation. Finalization is an acknowledgement, never another secret.
ALTER TABLE private.burimunsi_scope_setup_commands DROP CONSTRAINT burimunsi_scope_setup_commands_check;
ALTER TABLE private.burimunsi_scope_setup_commands ADD CONSTRAINT burimunsi_scope_setup_commands_check CHECK(
 (operation IN('prepare','cancelled','finalize_replacement') AND delivery_ciphertext IS NULL AND delivery_binding IS NULL)
 OR(operation IN('activate','prepare_replacement') AND length(delivery_ciphertext) BETWEEN 100 AND 2048 AND jsonb_typeof(delivery_binding)='object'));

CREATE TABLE private.burimunsi_gateway_handoffs(
 id uuid PRIMARY KEY,collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 owner_principal_id text NOT NULL REFERENCES app.users(id),principal_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 expected_scope_version bigint NOT NULL CHECK(expected_scope_version>0),receiving_account_id text NOT NULL REFERENCES app.momo_receiving_accounts(id),
 old_binding_id text NOT NULL REFERENCES app.momo_gateway_bindings(id),old_binding_version bigint NOT NULL CHECK(old_binding_version>0),
 old_receiver_key_id text NOT NULL REFERENCES app.momo_gateway_credentials(id),old_receiver_hash text NOT NULL CHECK(old_receiver_hash ~ '^[a-f0-9]{64}$'),
 old_grant_id uuid NOT NULL,old_grant_version bigint NOT NULL CHECK(old_grant_version>0),old_installation_id uuid NOT NULL,
 old_custodian_id uuid NOT NULL,target_grant_id uuid NOT NULL,target_grant_version bigint NOT NULL CHECK(target_grant_version>0),
 target_installation_id uuid NOT NULL,target_custodian_id uuid NOT NULL,target_account_version bigint NOT NULL,target_pin_version bigint NOT NULL,
 target_authority jsonb NOT NULL,target_binding_id text NOT NULL UNIQUE,target_pairing_id text NOT NULL UNIQUE,
 code_hash text NOT NULL UNIQUE CHECK(code_hash ~ '^[a-f0-9]{64}$'),subscription_id bigint NOT NULL CHECK(subscription_id BETWEEN 0 AND 2147483646),
 state text NOT NULL DEFAULT 'prepared' CHECK(state IN('prepared','retired','expired')),
 created_at bigint NOT NULL,expires_at bigint NOT NULL CHECK(expires_at>created_at),retired_at bigint,
 retirement_method text CHECK(retirement_method IN('old_phone','owner_lost')),retirement_request_id uuid,
 CHECK(old_installation_id<>target_installation_id AND old_grant_id<>target_grant_id),
 CHECK((state='retired')=(retired_at IS NOT NULL AND retirement_method IS NOT NULL AND retirement_request_id IS NOT NULL)),
 FOREIGN KEY(old_grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id),
 FOREIGN KEY(target_grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id),
 FOREIGN KEY(old_custodian_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id),
 FOREIGN KEY(target_custodian_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
CREATE UNIQUE INDEX burimunsi_one_prepared_handoff ON private.burimunsi_gateway_handoffs(collection_id) WHERE state='prepared';
CREATE TABLE private.burimunsi_gateway_pair_targets(
 pairing_id text PRIMARY KEY REFERENCES app.momo_gateway_pairings(id),collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 binding_id text NOT NULL REFERENCES app.momo_gateway_bindings(id),scope_version bigint NOT NULL CHECK(scope_version>0),
 grant_id uuid NOT NULL,grant_version bigint NOT NULL CHECK(grant_version>0),installation_id uuid NOT NULL,custodian_id uuid NOT NULL,
 account_version bigint NOT NULL,pin_version bigint NOT NULL,authority_snapshot jsonb NOT NULL,
 owner_principal_id text NOT NULL REFERENCES app.users(id),subscription_id bigint NOT NULL CHECK(subscription_id BETWEEN 0 AND 2147483646),
 expires_at bigint NOT NULL,handoff_id uuid REFERENCES private.burimunsi_gateway_handoffs(id),created_at bigint NOT NULL,
 FOREIGN KEY(grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id),
 FOREIGN KEY(custodian_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
CREATE TABLE private.burimunsi_gateway_retirements(
 collection_id text NOT NULL,actor_id uuid NOT NULL,session_id uuid NOT NULL REFERENCES private.burimunsi_sessions(id),request_id uuid NOT NULL,
 handoff_id uuid NOT NULL REFERENCES private.burimunsi_gateway_handoffs(id),fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 installation_id uuid NOT NULL,grant_id uuid NOT NULL,device_hash text NOT NULL CHECK(device_hash ~ '^[a-f0-9]{64}$'),
 account_version bigint NOT NULL,pin_version bigint NOT NULL,authority_snapshot jsonb NOT NULL,
 response jsonb NOT NULL,created_at bigint NOT NULL,recover_until bigint NOT NULL,
 PRIMARY KEY(collection_id,actor_id,request_id),FOREIGN KEY(actor_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id),
 FOREIGN KEY(grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id)
);
DO $policies$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_gateway_handoffs','burimunsi_gateway_pair_targets','burimunsi_gateway_retirements'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE private.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime',t);
  EXECUTE format('GRANT SELECT ON private.%I TO collect_runtime',t);
  EXECUTE format('CREATE POLICY burimunsi_scoped_runtime ON private.%I TO collect_runtime USING(collection_id=current_setting(''burimunsi.collection_id'',true))',t);
  EXECUTE format('CREATE POLICY burimunsi_scoped_owner ON private.%I TO postgres USING(collection_id=current_setting(''burimunsi.collection_id'',true)) WITH CHECK(collection_id=current_setting(''burimunsi.collection_id'',true))',t);
  EXECUTE format('CREATE POLICY burimunsi_handoff_owner_frame ON private.%I TO postgres USING(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND (current_setting(''burimunsi.pin_frame'',true)=''1'' OR current_setting(''burimunsi.scope_setup_scan'',true)=''1''))',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
  EXECUTE format('CREATE TRIGGER burimunsi_handoff_retain BEFORE DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER burimunsi_handoff_retain',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['burimunsi_gateway_pair_targets','burimunsi_gateway_retirements'] LOOP
  EXECUTE format('CREATE TRIGGER burimunsi_handoff_immutable BEFORE UPDATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER burimunsi_handoff_immutable',t);
 END LOOP;
END;$policies$;
CREATE FUNCTION private.burimunsi_handoff_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF OLD.state<>'prepared' OR NEW.state NOT IN('expired','retired')
  OR to_jsonb(NEW)-ARRAY['state','retired_at','retirement_method','retirement_request_id'] IS DISTINCT FROM
     to_jsonb(OLD)-ARRAY['state','retired_at','retirement_method','retirement_request_id'] THEN
  RAISE EXCEPTION 'burimunsi_handoff_immutable' USING ERRCODE='23514';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER burimunsi_handoff_identity BEFORE UPDATE ON private.burimunsi_gateway_handoffs
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_handoff_identity();

-- An eligible target is an actual approved account-linked installation. NULL
-- custody means registration only; it is not inferred from an arbitrary grant.
CREATE FUNCTION private.burimunsi_gateway_target_snapshot(p_collection text,p_grant uuid,p_installation uuid,p_custodian uuid,p_version bigint)
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
    AND s.expires_at>floor(extract(epoch FROM clock_timestamp())*1000)::bigint
    AND l.collection_id=a.collection_id AND l.account_id=a.id AND l.principal_user_id=a.principal_user_id
    AND l.account_version=a.version AND l.authority_snapshot=proof.snapshot));
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RETURN result;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
-- Hold the selected target's genuine current authority until the admitted
-- write commits. Snapshot-only directory/recovery paths never acquire locks.
CREATE FUNCTION private.burimunsi_gateway_lock_target(p_collection text,p_grant uuid,p_installation uuid,p_custodian uuid,p_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF current_setting('transaction_read_only')='off' THEN
  PERFORM 1 FROM private.burimunsi_device_grants d
   JOIN private.burimunsi_accounts a ON a.collection_id=d.collection_id AND a.id=p_custodian
   JOIN private.burimunsi_device_accounts da ON da.collection_id=d.collection_id AND da.grant_id=d.id AND da.account_id=a.id
   JOIN app.users u ON u.id=a.principal_user_id JOIN app.collections collection ON collection.id=d.collection_id
   WHERE d.collection_id=p_collection AND d.id=p_grant AND d.installation_id=p_installation FOR SHARE OF d,a,u,collection;
  PERFORM 1 FROM private.burimunsi_operator_approvals approval
   JOIN private.burimunsi_accounts a ON a.collection_id=approval.collection_id AND a.principal_user_id=approval.principal_user_id
   JOIN app.users u ON u.id=approval.principal_user_id
   JOIN app.admin_principal_links link ON link.user_id=u.id AND link.admin_user_id=approval.admin_user_id
   JOIN app.admin_users admin ON admin.id=link.admin_user_id
   JOIN private.auth_principal_links principal ON principal.user_id=u.id
   JOIN auth.users actual ON actual.id=principal.auth_user_id
   WHERE a.id=p_custodian AND a.collection_id=p_collection FOR SHARE OF approval,u,link,admin,principal,actual;
 END IF;
 RETURN private.burimunsi_gateway_target_snapshot(p_collection,p_grant,p_installation,p_custodian,p_version);
END;$fn$;
CREATE FUNCTION private.burimunsi_gateway_pair_target(p_code text,p_installation uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor record;t private.burimunsi_gateway_pair_targets%ROWTYPE;proof jsonb;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF p_code IS NULL OR p_code !~ '^[a-f0-9]{64}$' OR p_installation IS NULL THEN RETURN false;END IF;
 SELECT * INTO actor FROM private.burimunsi_pin_context();
 IF NOT FOUND OR actor.installation_id<>p_installation OR actor.profile<>'internal_receiver' OR actor.role<>'admin'
  OR NOT('gateway.manage'=ANY(actor.capabilities)) THEN RETURN false;END IF;
 PERFORM private.burimunsi_pin_assert_actor('receivers.manage',actor.collection_id,NULL,1,300);
 IF current_setting('transaction_read_only')='off' THEN
  -- Hold canonical challenge/receiver/binding authority through credential
  -- mint/claim, then re-read every condition after any revocation lock wait.
  PERFORM 1 FROM private.burimunsi_gateway_pair_targets target
   JOIN app.momo_gateway_pairings p ON p.id=target.pairing_id
   JOIN private.burimunsi_scopes scope ON scope.collection_id=target.collection_id
   JOIN app.momo_gateway_bindings b ON b.id=target.binding_id AND b.id=scope.active_binding_id
   JOIN app.momo_receiving_accounts w ON w.id=b.receiving_account_id
   WHERE p.code_sha256=encode(sha256(convert_to(p_code,'UTF8')),'hex')
    AND target.collection_id=actor.collection_id AND target.installation_id=p_installation FOR SHARE OF p,b,w;
 END IF;
 SELECT target.* INTO t FROM private.burimunsi_gateway_pair_targets target
  JOIN app.momo_gateway_pairings p ON p.id=target.pairing_id
  JOIN private.burimunsi_scopes scope ON scope.collection_id=target.collection_id
  JOIN app.momo_gateway_bindings b ON b.id=target.binding_id AND b.id=scope.active_binding_id
  JOIN app.momo_receiving_accounts w ON w.id=b.receiving_account_id AND w.id=scope.receiving_account_id AND w.status='active'
 WHERE p.code_sha256=encode(sha256(convert_to(p_code,'UTF8')),'hex') AND p.binding_id=b.id
  AND target.collection_id=actor.collection_id AND target.scope_version=scope.version AND scope.enabled
  AND b.status='active' AND b.version=scope.binding_version AND b.owner_user_id=actor.principal_user_id
  AND target.owner_principal_id=actor.principal_user_id AND target.grant_id=actor.grant_id
  AND target.installation_id=actor.installation_id AND target.custodian_id=actor.account_id AND target.grant_version=actor.grant_version
  AND p.expires_at>app.unixepoch() AND target.expires_at>floor(extract(epoch FROM clock_timestamp())*1000)::bigint
  AND (p.claimed_installation_id IS NULL OR p.claimed_installation_id=p_installation::text)
  AND b.subscription_evidence::jsonb=jsonb_build_object('subscription_id',target.subscription_id)
  AND NOT EXISTS(SELECT 1 FROM app.momo_gateway_credentials c WHERE c.binding_id=b.id
    AND(c.revoked_at IS NOT NULL OR c.installation_id<>p_installation::text OR c.pairing_id<>p.id));
 IF NOT FOUND THEN RETURN false;END IF;
 proof:=private.burimunsi_gateway_lock_target(t.collection_id,t.grant_id,t.installation_id,t.custodian_id,t.grant_version);
 RETURN proof IS NOT NULL AND (proof->>'accountVersion')::bigint=t.account_version
  AND (proof->>'pinVersion')::bigint=t.pin_version AND proof->'authority'=t.authority_snapshot;
END;$fn$;

-- Queue inspection is SELECT-only owner code over the same authenticated scope;
-- ordinary runtime policy/privileges and financial writers stay unchanged.
CREATE POLICY burimunsi_handoff_queue_owner ON private.burimunsi_receipt_jobs FOR SELECT TO postgres
 USING(collection_id=current_setting('burimunsi.collection_id',true));
CREATE POLICY burimunsi_handoff_queue_owner ON private.burimunsi_rematch_jobs FOR SELECT TO postgres
 USING(collection_id=current_setting('burimunsi.collection_id',true));
CREATE POLICY burimunsi_handoff_queue_owner ON private.burimunsi_transaction_scopes FOR SELECT TO postgres
 USING(collection_id=current_setting('burimunsi.collection_id',true));

-- No local supplied-zero flag is authoritative. Preserve both canonical pending
-- counts and unresolved SMS storage/application obligations without erasing any.
CREATE FUNCTION private.burimunsi_gateway_queue_clear(p_owner text,p_receiver text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT EXISTS(SELECT 1 FROM app.momo_gateway_credentials c WHERE c.id=p_receiver AND c.pending_count=0)
 AND NOT EXISTS(SELECT 1 FROM private.storage_put_intents i WHERE i.scope->>'ownerId'=p_owner AND i.scope->>'purpose'='sms_receipt'
  AND(i.state='pending' OR i.active_attempt IS NOT NULL OR i.upload_unresolved
   OR(i.state='committed' AND NOT EXISTS(SELECT 1 FROM app.sms_receipts s WHERE s.object_key=i.object_key))))
 AND NOT EXISTS(SELECT 1 FROM app.momo_processing_jobs j JOIN app.momo_gateway_credentials c ON c.binding_id=j.binding_id
  WHERE c.id=p_receiver AND j.state<>'completed')
 AND NOT EXISTS(SELECT 1 FROM private.burimunsi_receipt_jobs j JOIN app.momo_gateway_credentials c ON c.binding_id=j.binding_id
  WHERE c.id=p_receiver AND j.collection_id=current_setting('burimunsi.collection_id',true) AND j.state NOT IN('completed','rejected','dead_letter'))
 AND NOT EXISTS(SELECT 1 FROM private.burimunsi_rematch_jobs j JOIN app.momo_gateway_credentials c ON c.id=p_receiver
  JOIN app.momo_gateway_bindings b ON b.id=c.binding_id AND b.receiving_account_id=j.receiving_account_id
  WHERE j.collection_id=current_setting('burimunsi.collection_id',true) AND j.state NOT IN('completed','dead_letter'))
 -- Parsing completion alone is not a settled financial outcome. Existing
 -- Allocate/processing must finish while its original source custody is valid.
 -- Accept only the same complete original contribution/inverse shape used by
 -- current command-outcome recovery; no historical rebasing or new ledger.
 AND NOT EXISTS(
  SELECT 1 FROM app.momo_gateway_credentials c JOIN app.momo_gateway_bindings b ON b.id=c.binding_id
  JOIN app.momo_transactions t ON t.receiving_account_id=b.receiving_account_id AND t.mode='live' AND t.event_kind='incoming_receipt'
  WHERE c.id=p_receiver AND(
   EXISTS(SELECT 1 FROM private.burimunsi_transaction_scopes x WHERE x.transaction_id=t.id
    AND x.collection_id=current_setting('burimunsi.collection_id',true) AND x.source_binding_id=b.id)
   OR EXISTS(SELECT 1 FROM app.momo_transaction_sources source JOIN app.momo_gateway_captures capture ON capture.raw_sms_id=source.raw_sms_id
    WHERE source.transaction_id=t.id AND capture.credential_id=c.id))
  AND NOT EXISTS(
   SELECT 1 FROM app.momo_financial_links f JOIN app.payments p ON p.id=f.payment_id
   JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=p.collection_id AND l.kind='contribution'
    AND l.amount_minor=p.amount_minor AND l.evidence_id=p.evidence_id AND l.currency=p.currency AND l.member_id=f.beneficiary_member_id
   LEFT JOIN LATERAL(SELECT count(*) AS n,min(inv.kind) AS kind,
    bool_and(inv.kind IN('reversal','correction') AND inv.payment_id=l.payment_id AND inv.collection_id=l.collection_id
     AND inv.member_id IS NOT DISTINCT FROM l.member_id AND inv.currency=l.currency AND inv.evidence_id=l.evidence_id
     AND inv.amount_minor=-l.amount_minor) AS valid FROM app.ledger_entries inv WHERE inv.reverses_entry_id=l.id) inverse ON true
   WHERE f.transaction_id=t.id AND p.collection_id=current_setting('burimunsi.collection_id',true)
    AND t.has_conflict=0 AND t.allocation_state='linked' AND p.amount_minor=t.amount_minor AND p.currency=t.currency AND p.rail='rwanda_momo'
    AND((p.status IN('reconciled','confirmed') AND inverse.n=0 AND p.member_id=l.member_id)
     OR(p.status='reversed' AND inverse.n=1 AND inverse.valid AND inverse.kind='reversal')
     OR(p.status='corrected' AND inverse.n=1 AND inverse.valid AND inverse.kind='correction'))))
$fn$;

-- The same atomic retirement is reached either with current old-phone proof or
-- a separately audited genuine Shared Owner lost-phone action. It never returns
-- or manufactures a credential for the old caller.
CREATE FUNCTION private.burimunsi_gateway_commit_handoff(p_id uuid,p_method text,p_request uuid)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE h private.burimunsi_gateway_handoffs%ROWTYPE;scope private.burimunsi_scopes%ROWTYPE;
 c app.momo_gateway_credentials%ROWTYPE;b app.momo_gateway_bindings%ROWTYPE;proof jsonb;at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 IF p_method IS NULL OR p_method NOT IN('old_phone','owner_lost') OR p_request IS NULL THEN RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
 SELECT * INTO scope FROM private.burimunsi_scopes WHERE collection_id=current_setting('burimunsi.collection_id',true) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_handoff_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO h FROM private.burimunsi_gateway_handoffs WHERE id=p_id AND collection_id=scope.collection_id FOR UPDATE;
 IF NOT FOUND OR h.state<>'prepared' OR h.expires_at<=at_ms THEN RAISE EXCEPTION 'burimunsi_handoff_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO b FROM app.momo_gateway_bindings WHERE id=h.old_binding_id FOR UPDATE;
 SELECT * INTO c FROM app.momo_gateway_credentials WHERE id=h.old_receiver_key_id FOR UPDATE;
 PERFORM 1 FROM app.momo_receiving_accounts WHERE id=h.receiving_account_id FOR SHARE;
 IF scope.version<>h.expected_scope_version OR scope.receiving_account_id<>h.receiving_account_id OR NOT scope.enabled
  OR scope.active_binding_id IS DISTINCT FROM h.old_binding_id OR scope.binding_version<>h.old_binding_version
  OR(p_method='old_phone' AND b.status<>'active') OR b.version<>h.old_binding_version OR b.owner_user_id<>h.owner_principal_id OR b.receiving_account_id<>h.receiving_account_id
  OR c.binding_id<>b.id OR c.token_sha256<>h.old_receiver_hash OR(p_method='old_phone' AND c.revoked_at IS NOT NULL) OR c.installation_id<>h.old_installation_id::text
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_device_grants d JOIN private.burimunsi_accounts a ON a.id=d.custodian_account_id AND a.collection_id=d.collection_id
   WHERE d.collection_id=h.collection_id AND d.id=h.old_grant_id AND d.installation_id=h.old_installation_id AND d.version=h.old_grant_version
    AND d.profile='internal_receiver' AND d.custodian_account_id=h.old_custodian_id AND a.principal_user_id=h.owner_principal_id
    AND(p_method='owner_lost' OR(d.active AND a.active AND NOT a.removed AND a.role='admin'
     AND private.burimunsi_operator_is_current(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities))))
  OR NOT EXISTS(SELECT 1 FROM app.momo_receiving_accounts w WHERE w.id=h.receiving_account_id AND w.status='active')
  THEN RAISE EXCEPTION 'burimunsi_handoff_changed' USING ERRCODE='40001';END IF;
 proof:=private.burimunsi_gateway_lock_target(h.collection_id,h.target_grant_id,h.target_installation_id,h.target_custodian_id,h.target_grant_version);
 IF proof IS NULL OR (proof->>'accountVersion')::bigint<>h.target_account_version OR (proof->>'pinVersion')::bigint<>h.target_pin_version
  OR proof->'authority'<>h.target_authority THEN RAISE EXCEPTION 'burimunsi_handoff_changed' USING ERRCODE='40001';END IF;
 IF NOT private.burimunsi_gateway_queue_clear(h.owner_principal_id,c.id) THEN RAISE EXCEPTION 'gateway_queue_not_empty' USING ERRCODE='55000';END IF;
 UPDATE app.momo_gateway_credentials SET revoked_at=app.strftime('%Y-%m-%dT%H:%M:%fZ') WHERE id=c.id AND revoked_at IS NULL;
 UPDATE app.momo_gateway_bindings SET status='revoked',revoked_at=app.strftime('%Y-%m-%dT%H:%M:%fZ') WHERE id=b.id AND status='active';
 IF EXISTS(SELECT 1 FROM app.momo_gateway_bindings WHERE receiving_account_id=h.receiving_account_id AND status='active') THEN
  RAISE EXCEPTION 'burimunsi_handoff_changed' USING ERRCODE='40001';END IF;
 INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,subscription_evidence,created_at)
  VALUES(h.target_binding_id,h.owner_principal_id,h.receiving_account_id,jsonb_build_object('subscription_id',h.subscription_id)::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,created_at)
  VALUES(h.target_pairing_id,h.target_binding_id,h.code_hash,h.principal_session_id,h.expires_at/1000,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 UPDATE private.burimunsi_scopes SET active_binding_id=h.target_binding_id,binding_version=1,version=version+1
  WHERE collection_id=h.collection_id AND version=h.expected_scope_version RETURNING * INTO scope;
 IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_handoff_changed' USING ERRCODE='40001';END IF;
 INSERT INTO private.burimunsi_gateway_pair_targets(pairing_id,collection_id,binding_id,scope_version,grant_id,grant_version,
  installation_id,custodian_id,account_version,pin_version,authority_snapshot,owner_principal_id,subscription_id,expires_at,handoff_id,created_at)
  VALUES(h.target_pairing_id,h.collection_id,h.target_binding_id,scope.version,h.target_grant_id,h.target_grant_version,
   h.target_installation_id,h.target_custodian_id,h.target_account_version,h.target_pin_version,h.target_authority,h.owner_principal_id,h.subscription_id,h.expires_at,h.id,at_ms);
 UPDATE private.burimunsi_gateway_handoffs SET state='retired',retired_at=at_ms,retirement_method=p_method,retirement_request_id=p_request WHERE id=h.id;
 RETURN scope.version;
END;$fn$;

CREATE FUNCTION private.burimunsi_gateway_admin_handoff(p_actor jsonb,p_command jsonb,p_fingerprint text,p_delivery jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE cid text:=p_command->>'collectionId';rid uuid:=(p_command->>'requestId')::uuid;operation text:=p_command->>'operation';
 principal text:=p_actor->>'principalId';sid text:=p_actor->>'sessionId';expected bigint:=(p_command->>'expectedScopeVersion')::bigint;
 scope private.burimunsi_scopes%ROWTYPE;h private.burimunsi_gateway_handoffs%ROWTYPE;prior private.burimunsi_scope_setup_commands%ROWTYPE;
 c app.momo_gateway_credentials%ROWTYPE;b app.momo_gateway_bindings%ROWTYPE;old_device private.burimunsi_device_grants%ROWTYPE;
 target private.burimunsi_accounts%ROWTYPE;target_device private.burimunsi_device_grants%ROWTYPE;proof jsonb;result jsonb;subscription bigint;
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;expires_ms bigint:=(app.unixepoch()+600)*1000;new_version bigint;
BEGIN
 IF operation NOT IN('prepare_replacement','finalize_replacement') OR cid IS NULL OR rid IS NULL OR principal IS NULL OR sid IS NULL
  OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$' OR expected IS NULL OR expected<1 OR expected>=9007199254740991
  OR jsonb_typeof(p_command) IS DISTINCT FROM 'object' OR NOT(p_command ?& ARRAY['operation','requestId','collectionId','expectedScopeVersion','receivingAccountId','reason'])
  OR p_command->>'reason' IS NULL OR btrim(p_command->>'reason')<>p_command->>'reason' OR length(p_command->>'reason') NOT BETWEEN 8 AND 500
  OR p_command->>'reason' ~ '[[:cntrl:]]' OR p_command->>'reason' ~* '[a-f0-9]{64}'
  THEN RAISE EXCEPTION 'burimunsi_setup_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO prior FROM private.burimunsi_scope_setup_commands WHERE collection_id=cid AND actor_id=principal AND request_id=rid;
 IF FOUND THEN
  IF prior.principal_session_id<>sid OR prior.fingerprint<>p_fingerprint OR prior.operation<>operation THEN
   RAISE EXCEPTION 'burimunsi_setup_request_conflict' USING ERRCODE='23505';END IF;
  RETURN prior.response;
 END IF;
 SELECT * INTO scope FROM private.burimunsi_scopes WHERE collection_id=cid FOR UPDATE;
 IF NOT FOUND OR scope.version<>expected OR scope.receiving_account_id IS DISTINCT FROM p_command->>'receivingAccountId' THEN
  RAISE EXCEPTION 'burimunsi_scope_changed' USING ERRCODE='40001';END IF;
 IF operation='finalize_replacement' THEN
  IF (SELECT count(*) FROM jsonb_object_keys(p_command))<>7 OR NOT(p_command ? 'handoffId') OR p_delivery IS NOT NULL THEN
   RAISE EXCEPTION 'burimunsi_setup_invalid' USING ERRCODE='22023';END IF;
  SELECT * INTO h FROM private.burimunsi_gateway_handoffs WHERE id=(p_command->>'handoffId')::uuid AND collection_id=cid FOR UPDATE;
  IF NOT FOUND OR h.owner_principal_id<>principal OR h.expected_scope_version<>expected THEN RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
  new_version:=private.burimunsi_gateway_commit_handoff(h.id,'owner_lost',rid);
  result:=jsonb_build_object('contractVersion',1,'requestId',rid,'collectionId',cid,'operation',operation,
   'receivingAccountId',scope.receiving_account_id,'scopeVersion',new_version,'enabled',true,'bindingId',h.target_binding_id,
   'handoffId',h.id,'bindingVersion',1,'retirementMethod','owner_lost','reauthenticationRequired',true);
 ELSE
  IF (SELECT count(*) FROM jsonb_object_keys(p_command))<>14
   OR NOT(p_command ?& ARRAY['installationId','grantId','custodianAccountId','expectedGrantVersion','subscriptionId','expectedBindingId','expectedBindingVersion','expectedReceiverKeyId'])
   OR NOT scope.enabled OR scope.active_binding_id IS DISTINCT FROM p_command->>'expectedBindingId'
   OR jsonb_typeof(p_command->'expectedGrantVersion') IS DISTINCT FROM 'number'
   OR jsonb_typeof(p_command->'expectedBindingVersion') IS DISTINCT FROM 'number'
   OR scope.binding_version<>(p_command->>'expectedBindingVersion')::bigint THEN RAISE EXCEPTION 'burimunsi_scope_changed' USING ERRCODE='40001';END IF;
  SELECT * INTO b FROM app.momo_gateway_bindings WHERE id=scope.active_binding_id FOR SHARE;
  SELECT * INTO c FROM app.momo_gateway_credentials WHERE id=p_command->>'expectedReceiverKeyId' AND binding_id=b.id FOR SHARE;
  IF b.id IS NULL OR c.id IS NULL OR b.owner_user_id<>principal OR b.receiving_account_id<>scope.receiving_account_id OR b.version<>scope.binding_version
   THEN RAISE EXCEPTION 'burimunsi_scope_changed' USING ERRCODE='40001';END IF;
  SELECT * INTO old_device FROM private.burimunsi_device_grants WHERE collection_id=cid AND installation_id=c.installation_id::uuid FOR SHARE;
  IF NOT FOUND OR old_device.profile<>'internal_receiver' OR old_device.custodian_account_id IS NULL THEN
   RAISE EXCEPTION 'burimunsi_scope_changed' USING ERRCODE='40001';END IF;
  SELECT * INTO target_device FROM private.burimunsi_device_grants WHERE collection_id=cid AND id=(p_command->>'grantId')::uuid FOR SHARE;
  SELECT * INTO target FROM private.burimunsi_accounts WHERE collection_id=cid AND id=(p_command->>'custodianAccountId')::uuid FOR SHARE;
  proof:=private.burimunsi_gateway_target_snapshot(cid,(p_command->>'grantId')::uuid,(p_command->>'installationId')::uuid,
   (p_command->>'custodianAccountId')::uuid,(p_command->>'expectedGrantVersion')::bigint);
  IF proof IS NULL OR target.principal_user_id<>principal OR target_device.id=old_device.id OR target_device.installation_id=old_device.installation_id THEN
   RAISE EXCEPTION 'burimunsi_scope_denied' USING ERRCODE='42501';END IF;
  subscription:=(p_command->>'subscriptionId')::bigint;
  IF jsonb_typeof(p_command->'subscriptionId') IS DISTINCT FROM 'number' OR subscription NOT BETWEEN 0 AND 2147483646
   OR p_delivery IS NULL OR jsonb_typeof(p_delivery) IS DISTINCT FROM 'object' OR (SELECT count(*) FROM jsonb_object_keys(p_delivery))<>5
   OR NOT(p_delivery ?& ARRAY['bindingId','pairingId','codeHash','ciphertext','binding'])
   OR p_delivery->>'codeHash' IS NULL OR p_delivery->>'codeHash' !~ '^[a-f0-9]{64}$'
   OR p_delivery->>'ciphertext' IS NULL OR length(p_delivery->>'ciphertext') NOT BETWEEN 100 AND 2048
   OR p_delivery->>'bindingId'=b.id OR EXISTS(SELECT 1 FROM app.momo_gateway_bindings WHERE id=p_delivery->>'bindingId')
   OR EXISTS(SELECT 1 FROM app.momo_gateway_pairings WHERE id=p_delivery->>'pairingId')
   OR jsonb_typeof(p_delivery->'binding') IS DISTINCT FROM 'object' OR p_delivery->'binding'->>'profileSha' IS NULL OR (p_delivery->'binding'->>'profileSha') !~ '^[a-f0-9]{64}$'
   OR ((p_delivery->'binding') - 'profileSha') IS DISTINCT FROM jsonb_build_object(
    'actorId',principal,'sessionId',sid,'collectionId',cid,'requestId',rid::text,'receivingAccountId',scope.receiving_account_id,
    'expectedScopeVersion',expected,'bindingId',p_delivery->>'bindingId','pairingId',p_delivery->>'pairingId',
    'installationId',p_command->>'installationId','custodianAccountId',p_command->>'custodianAccountId',
    'grantId',p_command->>'grantId','grantVersion',(p_command->>'expectedGrantVersion')::bigint,'subscriptionId',subscription,
    'expectedBindingId',b.id,'expectedBindingVersion',b.version,'expectedReceiverKeyId',c.id)
   THEN RAISE EXCEPTION 'burimunsi_setup_invalid' USING ERRCODE='22023';END IF;
  UPDATE private.burimunsi_gateway_handoffs SET state='expired' WHERE collection_id=cid AND state='prepared' AND expires_at<=at_ms;
  IF EXISTS(SELECT 1 FROM private.burimunsi_gateway_handoffs WHERE collection_id=cid AND state='prepared') THEN
   RAISE EXCEPTION 'burimunsi_handoff_already_prepared' USING ERRCODE='40001';END IF;
  INSERT INTO private.burimunsi_gateway_handoffs(id,collection_id,owner_principal_id,principal_session_id,expected_scope_version,receiving_account_id,
   old_binding_id,old_binding_version,old_receiver_key_id,old_receiver_hash,old_grant_id,old_grant_version,old_installation_id,old_custodian_id,
   target_grant_id,target_grant_version,target_installation_id,target_custodian_id,target_account_version,target_pin_version,target_authority,
   target_binding_id,target_pairing_id,code_hash,subscription_id,created_at,expires_at)
  VALUES(rid,cid,principal,sid,expected,scope.receiving_account_id,b.id,b.version,c.id,c.token_sha256,old_device.id,old_device.version,old_device.installation_id,old_device.custodian_account_id,
   target_device.id,target_device.version,target_device.installation_id,target.id,target.version,target.credential_version,proof->'authority',
   p_delivery->>'bindingId',p_delivery->>'pairingId',p_delivery->>'codeHash',subscription,at_ms,expires_ms);
  result:=jsonb_build_object('contractVersion',1,'requestId',rid,'collectionId',cid,'operation',operation,
   'receivingAccountId',scope.receiving_account_id,'scopeVersion',scope.version,'enabled',scope.enabled,'bindingId',p_delivery->>'bindingId',
   'pairingId',p_delivery->>'pairingId','bindingVersion',1,'installationId',target_device.installation_id,'custodianAccountId',target.id,
   'grantId',target_device.id,'grantVersion',target_device.version,'subscriptionId',subscription,'deliveryExpiresAt',expires_ms,
   'handoffId',rid,'expectedBindingId',b.id,'expectedBindingVersion',b.version,'expectedReceiverKeyId',c.id,'retirementRequired',true);
 END IF;
 INSERT INTO private.burimunsi_scope_setup_commands(collection_id,actor_id,request_id,principal_session_id,operation,fingerprint,response,delivery_ciphertext,delivery_binding,created_at)
  VALUES(cid,principal,rid,sid,operation,p_fingerprint,result,p_delivery->>'ciphertext',p_delivery->'binding',at_ms);
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
  VALUES(principal,sid,'burimunsi.scope.'||operation,'collection',cid,rid::text,
   jsonb_build_object('reason',p_command->>'reason','handoff_id',CASE WHEN operation='prepare_replacement' THEN rid::text ELSE p_command->>'handoffId' END,
    'retirement_method',CASE WHEN operation='finalize_replacement' THEN 'owner_lost' END)::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 RETURN result;
END;$fn$;

CREATE FUNCTION private.burimunsi_gateway_retire(p_collection text,p_code text,p_request uuid,p_fingerprint text)
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
  VALUES(p_collection,a.id,s.id,p_request,h.id,p_fingerprint,d.installation_id,d.id,d.token_hash,a.version,a.credential_version,link.authority_snapshot,result,at_ms,s.expires_at);
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
  VALUES(a.principal_user_id,s.id::text,'burimunsi.gateway.retired','momo_binding',h.old_binding_id,p_request::text,
   jsonb_build_object('collection_id',p_collection,'handoff_id',h.id,'retirement_method','old_phone','native_actor_id',a.id)::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 RETURN result;
END;$fn$;

-- This is a SELECT-only acknowledgement capability, NOT ordinary native auth.
-- Only a known exact retirement receipt tolerates its expected scope/grant/
-- session invalidation. Account/PIN/principal/approval changes and original
-- token expiry still deny. No target credential, code, source or actor ports.
CREATE FUNCTION private.burimunsi_gateway_retirement_outcome(p_token text,p_installation uuid,p_device text,p_profile text,p_request uuid,p_fingerprint text)
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
 SELECT * INTO s FROM private.burimunsi_sessions WHERE token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex')
  AND installation_id=p_installation AND auth_method='phone_pin' AND created_at<=at_ms AND expires_at>at_ms;
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

CREATE FUNCTION private.burimunsi_gateway_pending(p_collection text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT jsonb_build_object('handoffId',h.id,'targetInstallationId',h.target_installation_id,'targetGrantId',h.target_grant_id,
  'targetGrantVersion',h.target_grant_version,'targetCustodianAccountId',h.target_custodian_id,
  'expectedScopeVersion',h.expected_scope_version,'expectedBindingId',h.old_binding_id,'expectedBindingVersion',h.old_binding_version,
  'expectedReceiverKeyId',h.old_receiver_key_id,'expiresAt',h.expires_at,'phase',h.state,'subscriptionId',h.subscription_id)
 FROM private.burimunsi_gateway_handoffs h JOIN private.burimunsi_scopes scope ON scope.collection_id=h.collection_id
 WHERE h.collection_id=p_collection AND h.expires_at>floor(extract(epoch FROM clock_timestamp())*1000)::bigint
  AND((h.state='prepared' AND scope.version=h.expected_scope_version AND scope.active_binding_id=h.old_binding_id)
   OR(h.state='retired' AND scope.version=h.expected_scope_version+1 AND scope.active_binding_id=h.target_binding_id
    AND NOT EXISTS(SELECT 1 FROM app.momo_gateway_credentials c WHERE c.binding_id=h.target_binding_id)))
  AND private.burimunsi_gateway_target_snapshot(h.collection_id,h.target_grant_id,h.target_installation_id,h.target_custodian_id,h.target_grant_version)
   =jsonb_build_object('accountVersion',h.target_account_version,'pinVersion',h.target_pin_version,'authority',h.target_authority)
 ORDER BY h.created_at DESC,h.id LIMIT 1
$fn$;

CREATE OR REPLACE FUNCTION private.burimunsi_setup_directory(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text DEFAULT NULL)
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
   'paired',EXISTS(SELECT 1 FROM app.momo_gateway_credentials k WHERE k.binding_id=s.active_binding_id AND k.revoked_at IS NULL),
   'receiverKeyId',(SELECT k.id FROM app.momo_gateway_credentials k WHERE k.binding_id=s.active_binding_id),
   'receiverInstallationId',(SELECT k.installation_id FROM app.momo_gateway_credentials k WHERE k.binding_id=s.active_binding_id),
   'pendingReplacement',private.burimunsi_gateway_pending(s.collection_id)) ORDER BY s.collection_id),'[]')
  INTO scopes FROM private.burimunsi_scopes s;
  PERFORM set_config('burimunsi.scope_setup_scan',coalesce(old_scan,''),true);
  IF p_collection IS NOT NULL THEN
   PERFORM set_config('burimunsi.collection_id',p_collection,true);
   SELECT coalesce(jsonb_agg(jsonb_build_object('grantId',d.id,'installationId',d.installation_id,'grantVersion',d.version,
    'custodianAccountId',a.id,'custodianName',a.name,'custodyAssigned',d.custodian_account_id IS NOT NULL) ORDER BY a.name,d.installation_id),'[]') INTO devices
   FROM private.burimunsi_device_grants d JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.collection_id=d.collection_id
   JOIN private.burimunsi_accounts a ON a.id=da.account_id AND a.collection_id=d.collection_id
   WHERE d.collection_id=p_collection AND d.active AND d.profile='internal_receiver' AND a.active AND NOT a.removed AND a.role='admin'
    AND a.principal_user_id=actor->>'principalId' AND 'gateway.manage'=ANY(a.capabilities)
    AND(d.custodian_account_id IS NULL OR d.custodian_account_id=a.id)
    AND private.burimunsi_gateway_target_snapshot(d.collection_id,d.id,d.installation_id,a.id,d.version) IS NOT NULL;
  END IF;
 EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
  PERFORM set_config('burimunsi.scope_setup_scan',coalesce(old_scan,''),true);RAISE;
 END;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 RETURN jsonb_build_object('contractVersion',1,'collections',groups,'accounts',accounts,'scopes',scopes,'installations',devices);
END;$fn$;

CREATE OR REPLACE FUNCTION private.burimunsi_setup_apply(p_actor text,p_cookie text,p_origin text,p_public text,p_command jsonb,p_fingerprint text,p_delivery jsonb DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;principal text;sid text;cid text;rid uuid;operation text;expected bigint;wallet text;
 scope private.burimunsi_scopes%ROWTYPE;prior private.burimunsi_scope_setup_commands%ROWTYPE;
 device private.burimunsi_device_grants%ROWTYPE;native private.burimunsi_accounts%ROWTYPE;
 binding text;pairing text;response jsonb;subscription bigint;at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 old_group text:=current_setting('burimunsi.collection_id',true);renew boolean:=false;
BEGIN
 actor:=private.burimunsi_setup_actor(p_actor,p_cookie,p_origin,p_public);principal:=actor->>'principalId';sid:=actor->>'sessionId';
 IF p_command->>'operation' IN('prepare_replacement','finalize_replacement') THEN
  BEGIN
   PERFORM set_config('burimunsi.collection_id',p_command->>'collectionId',true);
   response:=private.burimunsi_gateway_admin_handoff(actor,p_command,p_fingerprint,p_delivery);
  EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);RAISE;END;
  PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);RETURN response;
 END IF;
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
     OR(device.custodian_account_id IS NOT NULL AND device.custodian_account_id<>(p_command->>'custodianAccountId')::uuid) THEN RAISE EXCEPTION 'burimunsi_scope_changed' USING ERRCODE='40001';END IF;
    SELECT * INTO native FROM private.burimunsi_accounts WHERE collection_id=cid AND id=(p_command->>'custodianAccountId')::uuid FOR SHARE;
    IF NOT FOUND OR NOT native.active OR native.removed OR native.role<>'admin' OR native.principal_user_id<>principal
     OR NOT('gateway.manage'=ANY(native.capabilities))
     OR NOT private.burimunsi_operator_is_current(cid,native.principal_user_id,native.phone,native.role,native.capabilities)
     OR NOT EXISTS(SELECT 1 FROM private.burimunsi_device_accounts WHERE collection_id=cid AND grant_id=device.id AND account_id=native.id)
     OR private.burimunsi_gateway_lock_target(cid,device.id,device.installation_id,native.id,device.version) IS NULL THEN
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
    INSERT INTO private.burimunsi_gateway_pair_targets(pairing_id,collection_id,binding_id,scope_version,grant_id,grant_version,
     installation_id,custodian_id,account_version,pin_version,authority_snapshot,owner_principal_id,subscription_id,expires_at,created_at)
     VALUES(pairing,cid,binding,expected+1,device.id,device.version,device.installation_id,native.id,native.version,native.credential_version,
      private.burimunsi_pin_authority_snapshot(native.collection_id,native.principal_user_id,native.phone,native.role,native.capabilities),
      principal,subscription,(SELECT p.expires_at*1000 FROM app.momo_gateway_pairings p WHERE p.id=pairing),at_ms);
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

CREATE OR REPLACE FUNCTION private.burimunsi_setup_lookup(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,p_request uuid,p_delivery boolean DEFAULT false)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;prior private.burimunsi_scope_setup_commands%ROWTYPE;result jsonb;handoff private.burimunsi_gateway_handoffs%ROWTYPE;target_proof jsonb;current_scope private.burimunsi_scopes%ROWTYPE;old_group text:=current_setting('burimunsi.collection_id',true);
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
   IF p_delivery AND prior.operation='prepare_replacement' THEN
    SELECT * INTO handoff FROM private.burimunsi_gateway_handoffs WHERE id=prior.request_id AND collection_id=p_collection;
    SELECT * INTO current_scope FROM private.burimunsi_scopes WHERE collection_id=p_collection;
    target_proof:=private.burimunsi_gateway_target_snapshot(p_collection,handoff.target_grant_id,handoff.target_installation_id,handoff.target_custodian_id,handoff.target_grant_version);
    IF handoff.id IS NULL OR handoff.owner_principal_id<>actor->>'principalId' OR handoff.principal_session_id<>actor->>'sessionId'
     OR handoff.expires_at<=floor(extract(epoch FROM clock_timestamp())*1000)::bigint OR target_proof IS NULL
     OR target_proof<>jsonb_build_object('accountVersion',handoff.target_account_version,'pinVersion',handoff.target_pin_version,'authority',handoff.target_authority)
     OR NOT((handoff.state='prepared' AND current_scope.version=handoff.expected_scope_version AND current_scope.active_binding_id=handoff.old_binding_id)
      OR(handoff.state='retired' AND current_scope.version=handoff.expected_scope_version+1 AND current_scope.active_binding_id=handoff.target_binding_id
       AND EXISTS(SELECT 1 FROM app.momo_gateway_pairings p JOIN app.momo_gateway_bindings b ON b.id=p.binding_id
        WHERE p.id=handoff.target_pairing_id AND p.binding_id=handoff.target_binding_id AND p.code_sha256=handoff.code_hash
         AND p.expires_at>app.unixepoch() AND b.status='active' AND b.owner_user_id=handoff.owner_principal_id))) THEN
     RAISE EXCEPTION 'burimunsi_setup_delivery_expired' USING ERRCODE='41000';END IF;
    result:=result||jsonb_build_object('ciphertext',prior.delivery_ciphertext,'binding',prior.delivery_binding,'codeHash',handoff.code_hash,
     'phase',handoff.state,'retirementRequired',handoff.state='prepared');
   ELSIF p_delivery THEN
    IF prior.operation<>'activate'  OR (prior.response->>'deliveryExpiresAt')::bigint<=floor(extract(epoch FROM clock_timestamp())*1000)
     OR NOT EXISTS(SELECT 1 FROM private.burimunsi_scopes s JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id
      JOIN app.momo_gateway_pairings p ON p.binding_id=b.id
      JOIN private.burimunsi_device_grants d ON d.id=(prior.response->>'grantId')::uuid AND d.collection_id=s.collection_id
      JOIN private.burimunsi_gateway_pair_targets target ON target.pairing_id=p.id AND target.collection_id=s.collection_id
      JOIN private.burimunsi_accounts n ON n.id=target.custodian_id AND n.collection_id=s.collection_id
      WHERE s.collection_id=p_collection AND s.enabled AND s.active_binding_id=prior.response->>'bindingId'
       AND p.id=prior.response->>'pairingId' AND p.originating_session_id=actor->>'sessionId'
       AND (p.claimed_installation_id IS NULL OR p.claimed_installation_id=prior.response->>'installationId')
       AND p.expires_at>app.unixepoch() AND b.status='active' AND b.owner_user_id=actor->>'principalId'
       AND b.receiving_account_id=prior.response->>'receivingAccountId' AND s.receiving_account_id=b.receiving_account_id
       AND b.version=s.binding_version AND b.version=(prior.response->>'bindingVersion')::bigint
       AND d.active AND d.version=(prior.response->>'grantVersion')::bigint AND d.installation_id=(prior.response->>'installationId')::uuid
       AND d.profile='internal_receiver' AND (d.custodian_account_id IS NULL OR d.custodian_account_id=(prior.response->>'custodianAccountId')::uuid)
       AND target.grant_id=d.id AND target.installation_id=d.installation_id AND target.scope_version=s.version
       AND target.account_version=n.version AND target.pin_version=n.credential_version
       AND target.authority_snapshot=private.burimunsi_pin_authority_snapshot(n.collection_id,n.principal_user_id,n.phone,n.role,n.capabilities)
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

DO $acl$
DECLARE f regprocedure;
BEGIN
 FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='private' AND p.proname IN('burimunsi_handoff_identity','burimunsi_gateway_target_snapshot','burimunsi_gateway_lock_target','burimunsi_gateway_pair_target',
   'burimunsi_gateway_queue_clear','burimunsi_gateway_commit_handoff','burimunsi_gateway_admin_handoff',
   'burimunsi_gateway_retire','burimunsi_gateway_retirement_outcome','burimunsi_gateway_pending') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime',f);
 END LOOP;
END;$acl$;
GRANT EXECUTE ON FUNCTION private.burimunsi_gateway_pair_target(text,uuid),private.burimunsi_gateway_retire(text,text,uuid,text),
 private.burimunsi_gateway_retirement_outcome(text,uuid,text,text,uuid,text) TO collect_runtime;
COMMIT;
