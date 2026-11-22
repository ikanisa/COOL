-- Gateway work joins the existing Collect source/epoch fence without receiving
-- general application privileges. A settled local request never proves that a
-- physical phone, callback receiver or FCM delivery settled.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

CREATE TABLE private.collect_sms_fence_admissions(
 admission_id uuid PRIMARY KEY REFERENCES private.collect_fence_admissions(admission_id),
 profile_sha256 text NOT NULL CHECK(profile_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.collect_sms_fence_admissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.collect_sms_fence_admissions FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer,collect_sms_runtime;
CREATE TRIGGER collect_sms_fence_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_sms_fence_admissions
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.collect_sms_fence_admissions ENABLE ALWAYS TRIGGER collect_sms_fence_immutable;
COMMENT ON TABLE private.collect_sms_fence_admissions IS 'Immutable shared gateway work ownership; no subject-erasure selector. Include in whole-system custody and recovery.';

CREATE FUNCTION collect_sms._require_work_runtime() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'collect_sms_runtime'
  OR current_setting('collect.sms_verified',true) IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='collect_sms_fence_forbidden';END IF;
END;$fn$;

CREATE FUNCTION collect_sms._owned_work(p_id uuid,p_epoch bigint,p_source text)
RETURNS private.collect_fence_admissions
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM collect_sms._require_work_runtime();
 IF NOT EXISTS(SELECT 1 FROM private.collect_sms_fence_admissions WHERE admission_id=p_id) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 a:=private._collect_fence_admission(p_id,p_epoch,p_source);
 RETURN a;
END;$fn$;

CREATE FUNCTION collect_sms.work_register(p_id uuid,p_source text,p_kind text,p_profile text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM collect_sms._require_work_runtime();PERFORM private._collect_fence_require_rc(true);
 PERFORM private.collect_assert_deployment(p_profile);
 IF p_id IS NULL OR p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$'
  OR p_kind IS NULL OR p_kind NOT IN('http_collect','jobs') THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_admission';END IF;
 PERFORM pg_advisory_xact_lock_shared(7346371,1);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF c.mode<>'open' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_closed';END IF;
 IF c.source_sha256<>p_source OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE admission_id=p_id) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 IF private._collect_fence_resources()->'capacityBlocked'='true'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state)
  VALUES(p_id,c.epoch,p_source,p_kind,'active');
 INSERT INTO private.collect_sms_fence_admissions(admission_id,profile_sha256)VALUES(p_id,p_profile);
 RETURN jsonb_build_object('contractVersion',1,'admissionId',p_id,'epoch',c.epoch,'sourceSha256',p_source,'state','active','mode','open','kind',p_kind);
END;$fn$;

CREATE FUNCTION collect_sms.work_assert(p_id uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_mode text;
BEGIN
 PERFORM collect_sms._require_work_runtime();PERFORM private._collect_fence_require_rc(false);
 IF NOT EXISTS(SELECT 1 FROM pg_locks WHERE locktype='advisory' AND pid=pg_backend_pid()
  AND database=(SELECT oid FROM pg_database WHERE datname=current_database())
  AND classid=7346371::oid AND objid=1::oid AND objsubid=2 AND mode='ShareLock' AND granted) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 PERFORM collect_sms._owned_work(p_id,p_epoch,p_source);
 SELECT mode INTO v_mode FROM private.collect_fence_control WHERE singleton;
 RETURN jsonb_build_object('contractVersion',1,'admissionId',p_id,'epoch',p_epoch,'sourceSha256',p_source,'state','active','mode',v_mode);
END;$fn$;

CREATE FUNCTION collect_sms.work_assert_write(p_id uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM collect_sms._require_work_runtime();PERFORM private._collect_fence_require_rc(true);
 PERFORM pg_advisory_xact_lock_shared(7346371,2);
 PERFORM collect_sms._owned_work(p_id,p_epoch,p_source);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton;
 RETURN jsonb_build_object('contractVersion',1,'mode',c.mode,'epoch',c.epoch);
END;$fn$;

CREATE FUNCTION collect_sms.work_close(p_id uuid,p_epoch bigint,p_source text,p_outcome text,p_reason text,p_external integer,p_uncertain integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM collect_sms._require_work_runtime();PERFORM private._collect_fence_require_rc(true);
 IF NOT EXISTS(SELECT 1 FROM private.collect_sms_fence_admissions WHERE admission_id=p_id) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 IF p_id IS NULL OR p_epoch IS NULL OR p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$'
 OR p_outcome IS NULL OR p_outcome NOT IN('settled','unresolved') OR p_reason IS NULL
 OR p_reason NOT IN('completed','completed_with_unknown_obligation','work_failed_before_dispatch','dispatch_unconfirmed','lease_lost','work_lost','close_unconfirmed','cancelled_before_work')
 OR p_external IS NULL OR p_uncertain IS NULL OR p_external<0 OR p_uncertain<0 OR p_uncertain>p_external
 OR (p_outcome='settled' AND NOT((p_uncertain=0 AND p_reason IN('completed','work_failed_before_dispatch','cancelled_before_work')) OR(p_uncertain>0 AND p_reason='completed_with_unknown_obligation')))
 OR (p_outcome='unresolved' AND p_reason NOT IN('dispatch_unconfirmed','lease_lost','work_lost','close_unconfirmed'))
 OR (p_reason IN('work_failed_before_dispatch','cancelled_before_work') AND p_external<>0) THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_close';END IF;
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=p_id FOR UPDATE;
 IF NOT FOUND OR a.epoch<>p_epoch OR a.source_sha256<>p_source THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 IF a.state='active' THEN
  UPDATE private.collect_fence_admissions SET state=p_outcome,reason=p_reason,external_dispatches=p_external,
   uncertain_dispatches=p_uncertain,closed_at=clock_timestamp() WHERE admission_id=p_id;
 ELSIF a.state<>p_outcome OR a.reason<>p_reason OR a.external_dispatches<>p_external OR a.uncertain_dispatches<>p_uncertain THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 RETURN jsonb_build_object('contractVersion',1,'admissionId',p_id,'epoch',p_epoch,'sourceSha256',p_source,
  'state',p_outcome,'reason',p_reason,'externalDispatches',p_external,'uncertainDispatches',p_uncertain);
END;$fn$;

CREATE FUNCTION collect_sms.work_status(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM collect_sms._require_work_runtime();
 IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_admission';END IF;
 SELECT a1.* INTO a FROM private.collect_fence_admissions a1
  JOIN private.collect_sms_fence_admissions g USING(admission_id) WHERE a1.admission_id=p_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('contractVersion',1,'found',false,'admissionId',p_id);END IF;
 RETURN jsonb_build_object('contractVersion',1,'found',true,'admissionId',p_id,'epoch',a.epoch,'sourceSha256',a.source_sha256,
  'state',a.state,'reason',a.reason,'externalDispatches',a.external_dispatches,'uncertainDispatches',a.uncertain_dispatches);
END;$fn$;

-- Existing ALWAYS triggers now require the exact application-work tuple even
-- for a direct internal SQL writer. A gateway lock alone grants no admission.
CREATE OR REPLACE FUNCTION collect_sms.serialize_gateway_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM collect_sms.work_assert_write(nullif(current_setting('collect.fence_admission_id',true),'')::uuid,
  nullif(current_setting('collect.fence_epoch',true),'')::bigint,
  nullif(current_setting('collect.fence_source_sha256',true),''));
 PERFORM pg_advisory_xact_lock(721340019927::bigint);
 RETURN NULL;
END;$fn$;

REVOKE ALL ON FUNCTION collect_sms._require_work_runtime(),collect_sms._owned_work(uuid,bigint,text),
 collect_sms.work_register(uuid,text,text,text),collect_sms.work_assert(uuid,bigint,text),
 collect_sms.work_assert_write(uuid,bigint,text),collect_sms.work_close(uuid,bigint,text,text,text,integer,integer),
 collect_sms.work_status(uuid),collect_sms.serialize_gateway_write()
 FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer,collect_sms_runtime;
GRANT EXECUTE ON FUNCTION collect_sms.work_register(uuid,text,text,text),collect_sms.work_assert(uuid,bigint,text),
 collect_sms.work_assert_write(uuid,bigint,text),collect_sms.work_close(uuid,bigint,text,text,text,integer,integer),
 collect_sms.work_status(uuid) TO collect_sms_runtime;

-- Generated exact shared SMS admission classification; no erasure authority.
CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $function$
 SELECT $catalog${
  "contract": "collect.retention.descriptor-catalog.v2",
  "application": {
    "admin_account_audit": {
      "columns": [
        "id",
        "actor_id",
        "subject_id",
        "action",
        "occurred_at"
      ],
      "where": "(\"actor_id\"=$1 OR subject_id=$1 OR subject_id IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1))"
    },
    "admin_account_guards": {
      "columns": [
        "id",
        "passed"
      ],
      "where": "0=1"
    },
    "admin_account_role_capabilities": {
      "columns": [
        "role",
        "permission"
      ],
      "where": "1=1"
    },
    "admin_bridge_guards": {
      "columns": [
        "id",
        "passed"
      ],
      "where": "0=1"
    },
    "admin_bridge_reconciliation_snapshots": {
      "columns": [
        "reconciliation_id",
        "collection_id",
        "collection_revision",
        "member_id",
        "member_revision",
        "membership_id",
        "membership_revision",
        "payment_identity_json",
        "receiver_number",
        "receiver_network",
        "receiver_label",
        "created_at"
      ],
      "where": "(reconciliation_id IN(SELECT id FROM reconciliations WHERE proposed_member_id=$1 OR proposed_by=$1 OR approved_by=$1) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR \"member_id\"=$1)"
    },
    "admin_bridge_requests": {
      "columns": [
        "admin_user_id",
        "idempotency_key",
        "request_id",
        "session_id",
        "operation",
        "body_sha256",
        "created_at"
      ],
      "where": "(\"admin_user_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1) OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "admin_challenges": {
      "columns": [
        "token_hash",
        "user_id",
        "kind",
        "auth_version",
        "challenge_version",
        "delivery_status",
        "created_at",
        "expires_at",
        "used_at"
      ],
      "where": "(\"user_id\"=$1 OR \"user_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1))"
    },
    "admin_email_events": {
      "columns": [
        "id",
        "user_id",
        "kind",
        "status",
        "provider_message_id",
        "created_at",
        "updated_at"
      ],
      "where": "(\"user_id\"=$1 OR \"user_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1))"
    },
    "admin_email_otp_challenges": {
      "columns": [
        "id",
        "user_id",
        "principal_user_id",
        "origin",
        "role",
        "auth_version",
        "challenge_version",
        "account_status",
        "code_hash",
        "created_at",
        "expires_at",
        "attempts",
        "delivery_status",
        "used_at",
        "consumed_session_id"
      ],
      "where": "(principal_user_id=$1 OR user_id IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1) OR \"user_id\"=$1)"
    },
    "admin_grants": {
      "columns": [
        "user_id",
        "permission",
        "granted_by",
        "granted_at"
      ],
      "where": "(\"user_id\"=$1)"
    },
    "admin_operator_notes": {
      "columns": [
        "id",
        "entity_type",
        "entity_id",
        "body_ciphertext",
        "body_sha256",
        "created_by",
        "session_id",
        "created_at"
      ],
      "where": "(entity_id=$1 OR \"created_by\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "admin_owner_bootstrap_claims": {
      "columns": [
        "operation_id",
        "admin_user_id",
        "principal_user_id",
        "password_hash",
        "display_name",
        "approval_reference",
        "created_at",
        "created_seconds"
      ],
      "where": "(\"admin_user_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1))"
    },
    "admin_principal_links": {
      "columns": [
        "admin_user_id",
        "user_id",
        "approved_by",
        "approved_at"
      ],
      "where": "(\"admin_user_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1) OR \"user_id\"=$1 OR \"approved_by\"=$1)"
    },
    "admin_rate_limits": {
      "columns": [
        "key_hash",
        "bucket",
        "count",
        "expires_at"
      ],
      "where": "1=1"
    },
    "admin_role_assignments": {
      "columns": [
        "user_id",
        "role",
        "granted_by",
        "granted_at"
      ],
      "where": "(\"user_id\"=$1 OR \"user_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1))"
    },
    "admin_sessions": {
      "columns": [
        "token_hash",
        "public_id",
        "user_id",
        "auth_version",
        "auth_session_id",
        "origin",
        "issued_assurance_level",
        "issued_mfa_at",
        "issued_mfa_factor_id",
        "created_at",
        "expires_at"
      ],
      "where": "(\"user_id\"=$1 OR \"user_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1) OR \"auth_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "admin_users": {
      "columns": [
        "id",
        "email",
        "role",
        "status",
        "display_name",
        "password_hash",
        "auth_version",
        "challenge_version",
        "created_at",
        "invited_at",
        "accepted_at",
        "updated_at"
      ],
      "where": "(\"id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1))"
    },
    "assisted_sms_authorizations": {
      "columns": [
        "collection_id",
        "recipient_user_id",
        "enabled",
        "consent_revision",
        "destination_revision",
        "destination_ciphertext",
        "destination_sha256",
        "phone_verification_challenge_id",
        "authorization_receipt_sha256",
        "updated_at"
      ],
      "where": "(collection_id IN(SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=$1 UNION SELECT collection_id FROM assisted_sms_jobs WHERE recipient_user_id=$1) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR \"recipient_user_id\"=$1)"
    },
    "assisted_sms_claims": {
      "columns": [
        "id",
        "request_id",
        "job_id",
        "actor_admin_id",
        "actor_user_id",
        "originating_session_id",
        "public_session_id",
        "actor_role",
        "actor_auth_version",
        "actor_mfa_at",
        "origin",
        "worker_id",
        "previous_fence",
        "fence",
        "created_seconds",
        "expires_seconds",
        "actor_email_proof_id",
        "actor_email_verified_at"
      ],
      "where": "(job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1) OR \"actor_admin_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1) OR \"actor_user_id\"=$1 OR \"originating_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "assisted_sms_confirmations": {
      "columns": [
        "id",
        "request_id",
        "job_id",
        "claim_id",
        "fence",
        "actor_admin_id",
        "actor_user_id",
        "originating_session_id",
        "public_session_id",
        "body_sha256",
        "destination_sha256",
        "destination_revision",
        "confirmed_seconds",
        "expires_seconds"
      ],
      "where": "(job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1) OR \"actor_admin_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1) OR \"actor_user_id\"=$1 OR \"originating_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "assisted_sms_dispatches": {
      "columns": [
        "attempt_id",
        "grant_sha256",
        "expires_seconds",
        "application_id",
        "provider_message_id",
        "not_after",
        "state",
        "provider_state",
        "evidence_sha256",
        "started_seconds",
        "updated_seconds"
      ],
      "where": "(attempt_id IN(SELECT s.id FROM assisted_sms_send_starts s JOIN assisted_sms_jobs j ON j.id=s.job_id WHERE j.recipient_user_id=$1))"
    },
    "assisted_sms_jobs": {
      "columns": [
        "id",
        "payment_id",
        "entry_id",
        "collection_id",
        "recipient_user_id",
        "payment_revision",
        "amount_minor",
        "destination_revision",
        "destination_sha256",
        "destination_ciphertext",
        "consent_revision",
        "policy_revision",
        "policy_approval_sha256",
        "authorization_receipt_sha256",
        "template_key",
        "body_ciphertext",
        "body_sha256",
        "state",
        "fence",
        "active_claim_id",
        "created_at"
      ],
      "where": "(collection_id IN(SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=$1 UNION SELECT collection_id FROM assisted_sms_jobs WHERE recipient_user_id=$1) OR payment_id IN(SELECT id FROM payments WHERE member_id=$1) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR \"recipient_user_id\"=$1)"
    },
    "assisted_sms_outcomes": {
      "columns": [
        "id",
        "request_id",
        "attempt_id",
        "observer_admin_id",
        "observer_user_id",
        "observer_session_id",
        "observer_public_session_id",
        "observation",
        "evidence_reference_sha256",
        "observed_seconds"
      ],
      "where": "(attempt_id IN(SELECT s.id FROM assisted_sms_send_starts s JOIN assisted_sms_jobs j ON j.id=s.job_id WHERE j.recipient_user_id=$1) OR \"observer_admin_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1) OR \"observer_user_id\"=$1 OR \"observer_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "assisted_sms_policies": {
      "columns": [
        "collection_id",
        "enabled",
        "revision",
        "template_key",
        "approval_reference_sha256",
        "updated_at"
      ],
      "where": "(collection_id IN(SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=$1 UNION SELECT collection_id FROM assisted_sms_jobs WHERE recipient_user_id=$1) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1))"
    },
    "assisted_sms_send_starts": {
      "columns": [
        "id",
        "request_id",
        "job_id",
        "confirmation_id",
        "claim_id",
        "fence",
        "actor_admin_id",
        "actor_user_id",
        "originating_session_id",
        "public_session_id",
        "body_sha256",
        "destination_sha256",
        "destination_revision",
        "started_seconds"
      ],
      "where": "(job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1) OR \"actor_admin_id\" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=$1) OR \"actor_user_id\"=$1 OR \"originating_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "audit_log": {
      "columns": [
        "id",
        "actor_user_id",
        "actor_session_id",
        "action",
        "entity_type",
        "entity_id",
        "request_id",
        "details_json",
        "created_at"
      ],
      "where": "(request_id IN(SELECT request_id FROM request_receipts WHERE operation='momo.assign' AND json_extract(response_json,'$.transaction_id') IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1)))) OR entity_id IN(SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=$1 OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))) OR entity_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))) OR request_id IN(SELECT r.request_id FROM request_receipts r WHERE\n r.request_id IN(SELECT request_id FROM assisted_sms_claims WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1))\n OR r.request_id IN(SELECT request_id FROM assisted_sms_confirmations WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1))\n OR r.request_id IN(SELECT request_id FROM assisted_sms_send_starts WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1))\n OR r.request_id IN(SELECT request_id FROM assisted_sms_outcomes WHERE attempt_id IN(SELECT s.id FROM assisted_sms_send_starts s JOIN assisted_sms_jobs j ON j.id=s.job_id WHERE j.recipient_user_id=$1))\n OR r.operation='assisted_sms.enqueue' AND json_extract(r.response_json,'$.job_id') IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1)\n OR r.operation='assisted_sms.materialize.plan' AND EXISTS(SELECT 1 FROM json_each(CASE WHEN r.operation='assisted_sms.materialize.plan' THEN r.response_json ELSE '{}' END,'$.sources') source WHERE json_extract(source.value,'$.entry_id') IN(SELECT id FROM ledger_entries WHERE member_id=$1))\n OR r.operation IN('assisted_sms.materialize.intent','assisted_sms.materialize.blocked') AND json_extract(r.response_json,'$.source_entry_id') IN(SELECT id FROM ledger_entries WHERE member_id=$1)\n OR r.operation='assisted_sms.policy.configure' AND json_extract(r.response_json,'$.collection_id') IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=$1)) OR \"actor_user_id\"=$1 OR entity_id=$1)"
    },
    "auth_google_flows": {
      "columns": [
        "id",
        "state_hash",
        "nonce",
        "provider_verifier",
        "client_challenge",
        "client_state",
        "return_origin",
        "registration_allowed",
        "created_at",
        "expires_at",
        "status",
        "google_subject",
        "email",
        "handoff_hash",
        "consumed_operation_id"
      ],
      "where": "(google_subject IN(SELECT subject FROM auth_google_identities WHERE user_id=$1) OR email IN(SELECT lower(email) FROM users WHERE id=$1))"
    },
    "auth_google_identities": {
      "columns": [
        "subject",
        "user_id",
        "created_at"
      ],
      "where": "(\"user_id\"=$1)"
    },
    "auth_identity_rate_aliases": {
      "columns": [
        "request_id",
        "identity_key_id",
        "identity_hash",
        "requested_at",
        "hourly_window_ends_at"
      ],
      "where": "(request_id IN(SELECT id FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=$1 UNION SELECT email FROM users WHERE id=$1)) OR identity_hash IN(SELECT identity_hash FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=$1 UNION SELECT email FROM users WHERE id=$1)))"
    },
    "auth_mfa_budgets": {
      "columns": [
        "user_id",
        "window_start",
        "kind",
        "used"
      ],
      "where": "(\"user_id\"=$1)"
    },
    "auth_mfa_challenges": {
      "columns": [
        "id",
        "user_id",
        "session_id",
        "factor_id",
        "created_at",
        "expires_at",
        "attempts",
        "consumed_at",
        "consumed_operation_id"
      ],
      "where": "(\"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "auth_mfa_claims": {
      "columns": [
        "operation_id",
        "challenge_id",
        "factor_id",
        "user_id",
        "session_id",
        "totp_counter",
        "verified_at"
      ],
      "where": "(\"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "auth_mfa_factors": {
      "columns": [
        "id",
        "user_id",
        "friendly_name",
        "secret_ciphertext",
        "status",
        "created_at",
        "enrollment_session_id",
        "verified_at",
        "last_totp_counter",
        "revoked_at"
      ],
      "where": "(\"user_id\"=$1 OR \"enrollment_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "auth_mfa_revocations": {
      "columns": [
        "operation_id",
        "factor_id",
        "user_id",
        "session_id",
        "revoked_at"
      ],
      "where": "(\"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "auth_otp_challenges": {
      "columns": [
        "id",
        "identity_hash",
        "identity_type",
        "identity_value",
        "surface",
        "registration_allowed",
        "code_hash",
        "created_at",
        "expires_at",
        "attempts",
        "status",
        "consumed_at",
        "consumed_operation_id",
        "identity_key_id"
      ],
      "where": "(identity_hash IN(SELECT identity_hash FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=$1 UNION SELECT email FROM users WHERE id=$1)) OR identity_value IN(SELECT phone FROM users WHERE id=$1 UNION SELECT email FROM users WHERE id=$1))"
    },
    "auth_otp_throttles": {
      "columns": [
        "identity_hash",
        "last_requested_at",
        "identity_key_id"
      ],
      "where": "(identity_hash IN(SELECT identity_hash FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=$1 UNION SELECT email FROM users WHERE id=$1)))"
    },
    "auth_otp_verifications": {
      "columns": [
        "operation_id",
        "challenge_id",
        "user_id",
        "session_id",
        "verified_at"
      ],
      "where": "(\"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "auth_rate_buckets": {
      "columns": [
        "bucket_key",
        "used",
        "window_ends_at"
      ],
      "where": "1=1"
    },
    "auth_rate_claims": {
      "columns": [
        "request_id",
        "identity_hash",
        "identity_bucket",
        "ip_bucket",
        "global_bucket",
        "requested_at",
        "hourly_window_ends_at",
        "daily_window_ends_at",
        "identity_limit",
        "ip_limit",
        "global_limit",
        "cooldown_seconds",
        "identity_key_id",
        "identity_aliases_json"
      ],
      "where": "(identity_hash IN(SELECT identity_hash FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=$1 UNION SELECT email FROM users WHERE id=$1)))"
    },
    "auth_refresh_tokens": {
      "columns": [
        "token_hash",
        "session_id",
        "created_at",
        "expires_at",
        "used_at",
        "replaced_by_hash"
      ],
      "where": "(\"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "auth_sessions": {
      "columns": [
        "id",
        "user_id",
        "surface",
        "auth_at",
        "created_at",
        "expires_at",
        "revoked_at",
        "revocation_reason",
        "assurance_level",
        "mfa_at",
        "mfa_factor_id"
      ],
      "where": "(\"user_id\"=$1)"
    },
    "client_diagnostic_reports": {
      "columns": [
        "report_id",
        "payload_sha256",
        "surface",
        "environment",
        "build_version",
        "source_revision",
        "code",
        "fingerprint",
        "occurrences",
        "attempt",
        "elapsed_ms",
        "received_hour",
        "expires_at"
      ],
      "where": "0=1"
    },
    "collections": {
      "columns": [
        "id",
        "slug",
        "creator_user_id",
        "title",
        "description",
        "collection_type",
        "country_code",
        "currency",
        "status",
        "visibility_status",
        "is_platform_sponsored",
        "receiver_momo_number",
        "receiver_network",
        "receiver_display_label",
        "share_code_hash",
        "share_code_ciphertext",
        "share_code_version",
        "revision",
        "data_json",
        "created_at",
        "updated_at"
      ],
      "where": "(id IN(SELECT collection_id FROM payments WHERE id IN(SELECT payment_id FROM momo_financial_links WHERE transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))) OR id IN(SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=$1 UNION SELECT collection_id FROM assisted_sms_jobs WHERE recipient_user_id=$1) OR \"creator_user_id\"=$1)"
    },
    "contribution_posting_snapshots": {
      "columns": [
        "ledger_entry_id",
        "payment_id",
        "member_balance_after_minor",
        "group_balance_after_minor",
        "posted_at"
      ],
      "where": "(payment_id IN(SELECT payment_id FROM momo_financial_links WHERE transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1)))) OR payment_id IN(SELECT id FROM payments WHERE member_id=$1))"
    },
    "deletion_requests": {
      "columns": [
        "id",
        "user_id",
        "submission_id",
        "reason",
        "status",
        "revision",
        "created_at",
        "updated_at"
      ],
      "where": "(\"user_id\"=$1)"
    },
    "deletion_reviews": {
      "columns": [
        "id",
        "request_id",
        "actor_user_id",
        "expected_revision",
        "outcome",
        "details_json",
        "created_at"
      ],
      "where": "(request_id IN(SELECT id FROM deletion_requests WHERE user_id=$1) OR \"actor_user_id\"=$1)"
    },
    "ledger_entries": {
      "columns": [
        "id",
        "payment_id",
        "collection_id",
        "member_id",
        "currency",
        "amount_minor",
        "kind",
        "reverses_entry_id",
        "evidence_id",
        "actor_user_id",
        "request_id",
        "posted_at"
      ],
      "where": "(payment_id IN(SELECT payment_id FROM momo_financial_links WHERE transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1)))) OR payment_id IN(SELECT id FROM payments WHERE member_id=$1) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR \"member_id\"=$1 OR evidence_id IN(SELECT evidence_id FROM payments WHERE member_id=$1 UNION SELECT id FROM payment_evidence WHERE owner_user_id=$1) OR \"actor_user_id\"=$1)"
    },
    "memberships": {
      "columns": [
        "id",
        "collection_id",
        "user_id",
        "role",
        "active",
        "joined_at",
        "revision"
      ],
      "where": "(collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR \"user_id\"=$1)"
    },
    "momo_financial_links": {
      "columns": [
        "transaction_id",
        "payment_id",
        "beneficiary_member_id",
        "linked_by",
        "reason",
        "historical_existing",
        "created_at"
      ],
      "where": "(transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))) OR beneficiary_member_id=$1 OR linked_by=$1 OR payment_id IN(SELECT id FROM payments WHERE member_id=$1))"
    },
    "momo_gateway_bindings": {
      "columns": [
        "id",
        "owner_user_id",
        "receiving_account_id",
        "version",
        "status",
        "subscription_evidence",
        "created_at",
        "revoked_at"
      ],
      "where": "(id IN(SELECT id FROM momo_gateway_bindings WHERE owner_user_id=$1 OR receiving_account_id IN(SELECT receiving_account_id FROM momo_transactions WHERE id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))) OR \"owner_user_id\"=$1)"
    },
    "momo_gateway_captures": {
      "columns": [
        "raw_sms_id",
        "credential_id",
        "identity_sha256",
        "service_centre_at",
        "captured_at",
        "inbox_received_at",
        "subscription_id",
        "completeness",
        "source_mode",
        "created_at"
      ],
      "where": "(raw_sms_id IN(SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=$1 OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))))"
    },
    "momo_gateway_credentials": {
      "columns": [
        "id",
        "binding_id",
        "pairing_id",
        "installation_id",
        "token_sha256",
        "token_ciphertext",
        "last_contact_at",
        "last_sms_at",
        "pending_count",
        "oldest_pending_at",
        "revoked_at",
        "created_at"
      ],
      "where": "(binding_id IN(SELECT id FROM momo_gateway_bindings WHERE owner_user_id=$1 OR receiving_account_id IN(SELECT receiving_account_id FROM momo_transactions WHERE id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))))"
    },
    "momo_gateway_pairings": {
      "columns": [
        "id",
        "binding_id",
        "code_sha256",
        "originating_session_id",
        "expires_at",
        "claimed_installation_id",
        "created_at"
      ],
      "where": "(binding_id IN(SELECT id FROM momo_gateway_bindings WHERE owner_user_id=$1 OR receiving_account_id IN(SELECT receiving_account_id FROM momo_transactions WHERE id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))) OR \"originating_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "momo_parse_attempts": {
      "columns": [
        "id",
        "raw_sms_id",
        "attempt_number",
        "model_id",
        "schema_version",
        "prompt_version",
        "parser_version",
        "profile_version",
        "profile_json",
        "source_body_sha256",
        "output_json",
        "validation_json",
        "outcome",
        "created_at"
      ],
      "where": "(raw_sms_id IN(SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=$1 OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))))"
    },
    "momo_processing_guards": {
      "columns": [
        "id",
        "passed"
      ],
      "where": "1=1"
    },
    "momo_processing_jobs": {
      "columns": [
        "raw_sms_id",
        "binding_id",
        "binding_version",
        "receiving_account_id",
        "mode",
        "state",
        "attempt_count",
        "max_attempts",
        "available_at",
        "lease_token",
        "lease_until",
        "last_error",
        "created_at",
        "updated_at"
      ],
      "where": "(raw_sms_id IN(SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=$1 OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))))"
    },
    "momo_receiving_accounts": {
      "columns": [
        "id",
        "provider",
        "public_code",
        "recipient_name",
        "receiver_hash",
        "currency",
        "timezone",
        "status",
        "profile_status",
        "profile_version",
        "profile_json",
        "created_at"
      ],
      "where": "(id IN(SELECT receiving_account_id FROM momo_gateway_bindings WHERE id IN(SELECT id FROM momo_gateway_bindings WHERE owner_user_id=$1 OR receiving_account_id IN(SELECT receiving_account_id FROM momo_transactions WHERE id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1)))))) OR id IN(SELECT receiving_account_id FROM momo_transactions WHERE id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1)))))"
    },
    "momo_source_resolutions": {
      "columns": [
        "id",
        "raw_sms_id",
        "receiving_account_id",
        "source_body_sha256",
        "reviewed_by",
        "evidence_reference",
        "reason",
        "created_at"
      ],
      "where": "(raw_sms_id IN(SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=$1 OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))) OR reviewed_by=$1)"
    },
    "momo_transaction_sources": {
      "columns": [
        "transaction_id",
        "raw_sms_id",
        "parse_attempt_id",
        "relation",
        "created_at"
      ],
      "where": "(transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))) OR raw_sms_id IN(SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=$1 OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))))"
    },
    "momo_transactions": {
      "columns": [
        "id",
        "receiving_account_id",
        "provider",
        "provider_transaction_id",
        "event_kind",
        "original_transaction_id",
        "amount_minor",
        "currency",
        "currency_scale",
        "payer_name",
        "payer_identifier",
        "payer_last3",
        "transaction_at",
        "transaction_datetime_raw",
        "transaction_timezone",
        "transaction_time_source",
        "fee_minor",
        "wallet_balance_after_minor",
        "parse_attempt_id",
        "mode",
        "allocation_state",
        "has_conflict",
        "version",
        "created_at",
        "updated_at"
      ],
      "where": "(id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))"
    },
    "mutation_guards": {
      "columns": [
        "id",
        "user_id",
        "session_id",
        "now_seconds",
        "collection_id",
        "required_group_role",
        "permission",
        "fresh_seconds",
        "expected_collection_revision",
        "payment_id",
        "expected_payment_revision",
        "minimum_assurance",
        "expected_mfa_at",
        "expected_preference_revision",
        "invite_collection_id",
        "expected_share_hash",
        "expected_share_version",
        "recipient_user_id",
        "recipient_collection_id",
        "target_collection_id",
        "expected_target_collection_revision"
      ],
      "where": "(\"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR payment_id IN(SELECT id FROM payments WHERE member_id=$1) OR \"recipient_user_id\"=$1)"
    },
    "native_capabilities": {
      "columns": [
        "id",
        "token_sha256",
        "reservation_id",
        "user_id",
        "session_id",
        "action",
        "receiver_hash",
        "verified_phone",
        "payload_sha256",
        "created_seconds",
        "expires_seconds",
        "verdict_sha256"
      ],
      "where": "(reservation_id IN(SELECT id FROM native_reservations WHERE user_id=$1) OR \"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "native_capability_claims": {
      "columns": [
        "id",
        "capability_id",
        "user_id",
        "session_id",
        "action",
        "payload_sha256",
        "receiver_hash",
        "claimed_seconds"
      ],
      "where": "(\"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "native_completions": {
      "columns": [
        "reservation_id",
        "capability_id",
        "result_ciphertext",
        "provider_response_sha256",
        "completed_seconds",
        "decode_duration_ms"
      ],
      "where": "(reservation_id IN(SELECT id FROM native_reservations WHERE user_id=$1))"
    },
    "native_consents": {
      "columns": [
        "id",
        "user_id",
        "session_id",
        "receiver_hash",
        "enabled",
        "created_seconds",
        "build_channel",
        "request_id"
      ],
      "where": "(\"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "native_phases": {
      "columns": [
        "reservation_id",
        "phase",
        "started_seconds"
      ],
      "where": "(reservation_id IN(SELECT id FROM native_reservations WHERE user_id=$1))"
    },
    "native_reservations": {
      "columns": [
        "id",
        "user_id",
        "session_id",
        "nonce",
        "action",
        "request_hash",
        "token_sha256",
        "receiver_hash",
        "verified_phone",
        "payload_sha256",
        "payload_ciphertext",
        "policy_sha256",
        "approval_id",
        "approval_evidence_sha256",
        "project_id",
        "created_seconds",
        "expires_seconds",
        "actor_hour_limit",
        "project_day_limit",
        "state"
      ],
      "where": "(\"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "notification_deliveries": {
      "columns": [
        "id",
        "event_id",
        "device_id",
        "user_id",
        "owner_session_id",
        "token_sha256",
        "event_sha256",
        "project_id",
        "android_package",
        "state",
        "attempt_count",
        "available_at",
        "lease_token",
        "lease_until",
        "attempt_log",
        "provider_message_id",
        "last_error",
        "last_http_status",
        "created_at",
        "updated_at"
      ],
      "where": "(\"user_id\"=$1 OR \"owner_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "notification_devices": {
      "columns": [
        "id",
        "user_id",
        "token_hash",
        "owner_session_id",
        "provider",
        "token_ciphertext",
        "platform",
        "active",
        "created_at",
        "updated_at"
      ],
      "where": "(\"user_id\"=$1 OR \"owner_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "notification_email_deliveries": {
      "columns": [
        "id",
        "event_id",
        "user_id",
        "recipient_sha256",
        "event_sha256",
        "state",
        "attempt_id",
        "started_seconds",
        "provider_message_id",
        "created_seconds",
        "updated_seconds"
      ],
      "where": "(\"user_id\"=$1)"
    },
    "notification_email_job_dispatches": {
      "columns": [
        "id",
        "admission_sha256",
        "admission_json",
        "state",
        "result_json",
        "created_seconds",
        "updated_seconds"
      ],
      "where": "1=1"
    },
    "notification_events": {
      "columns": [
        "id",
        "user_id",
        "event_type",
        "title",
        "body",
        "data_json",
        "status",
        "created_at",
        "read_at"
      ],
      "where": "(\"user_id\"=$1)"
    },
    "notification_preferences": {
      "columns": [
        "user_id",
        "push_enabled",
        "payment_updates",
        "group_updates",
        "revision",
        "updated_at",
        "email_enabled",
        "payment_reminders",
        "security_notices"
      ],
      "where": "(\"user_id\"=$1)"
    },
    "payment_evidence": {
      "columns": [
        "id",
        "collection_id",
        "owner_user_id",
        "object_key",
        "object_sha256",
        "size_bytes",
        "content_type",
        "authenticity",
        "external_reference",
        "receiver_momo_number",
        "amount_minor",
        "currency",
        "observed_at",
        "created_at",
        "retained_until",
        "legal_hold",
        "receiver_network",
        "receiver_display_label"
      ],
      "where": "(id IN(SELECT evidence_id FROM payments WHERE id IN(SELECT payment_id FROM momo_financial_links WHERE transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR \"owner_user_id\"=$1)"
    },
    "payment_intents": {
      "columns": [
        "id",
        "collection_id",
        "member_id",
        "amount_minor",
        "currency",
        "rail",
        "status",
        "receiver_momo_number",
        "receiver_network",
        "receiver_label",
        "originating_session_id",
        "created_at",
        "expires_at",
        "request_id",
        "request_sha256"
      ],
      "where": "(collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR \"member_id\"=$1 OR \"originating_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "payments": {
      "columns": [
        "id",
        "collection_id",
        "member_id",
        "evidence_id",
        "intent_id",
        "amount_minor",
        "currency",
        "rail",
        "status",
        "payer_display_name",
        "created_at",
        "revision"
      ],
      "where": "(id IN(SELECT payment_id FROM momo_financial_links WHERE transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1)))) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR \"member_id\"=$1 OR evidence_id IN(SELECT evidence_id FROM payments WHERE member_id=$1 UNION SELECT id FROM payment_evidence WHERE owner_user_id=$1))"
    },
    "privacy_holds": {
      "columns": [
        "id",
        "user_id",
        "category",
        "reason_code",
        "active",
        "created_at",
        "released_at"
      ],
      "where": "(\"user_id\"=$1)"
    },
    "privacy_review_claims": {
      "columns": [
        "claim_id",
        "claim_request_id",
        "request_id",
        "actor_id",
        "originating_session_id",
        "expected_revision",
        "revision",
        "fence",
        "lease_seconds",
        "claimed_at",
        "expires_at"
      ],
      "where": "(request_id IN(SELECT id FROM deletion_requests WHERE user_id=$1) OR \"actor_id\"=$1 OR \"originating_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "privacy_review_heads": {
      "columns": [
        "request_id",
        "revision",
        "fence",
        "state",
        "latest_claim_id",
        "last_outcome_id",
        "created_at",
        "updated_at"
      ],
      "where": "(request_id IN(SELECT id FROM deletion_requests WHERE user_id=$1))"
    },
    "privacy_review_outcomes": {
      "columns": [
        "outcome_request_id",
        "request_id",
        "claim_id",
        "actor_id",
        "originating_session_id",
        "fence",
        "revision",
        "outcome_code",
        "recorded_at"
      ],
      "where": "(request_id IN(SELECT id FROM deletion_requests WHERE user_id=$1) OR \"actor_id\"=$1 OR \"originating_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "privacy_submissions": {
      "columns": [
        "submission_id",
        "request_id",
        "user_id",
        "originating_session_id",
        "input_sha256",
        "created_at"
      ],
      "where": "(request_id IN(SELECT id FROM deletion_requests WHERE user_id=$1) OR \"user_id\"=$1 OR \"originating_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "reconciliations": {
      "columns": [
        "id",
        "payment_id",
        "proposed_member_id",
        "proposed_by",
        "proposed_session_id",
        "expected_payment_revision",
        "status",
        "evidence_id",
        "approved_by",
        "request_id",
        "request_sha256",
        "created_at",
        "approved_at"
      ],
      "where": "(payment_id IN(SELECT id FROM payments WHERE member_id=$1) OR \"proposed_member_id\"=$1 OR \"proposed_by\"=$1 OR \"proposed_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1) OR evidence_id IN(SELECT evidence_id FROM payments WHERE member_id=$1 UNION SELECT id FROM payment_evidence WHERE owner_user_id=$1) OR \"approved_by\"=$1)"
    },
    "request_receipts": {
      "columns": [
        "user_id",
        "request_id",
        "operation",
        "session_id",
        "body_sha256",
        "response_json",
        "created_at"
      ],
      "where": "(request_id IN(SELECT request_id FROM request_receipts WHERE operation='momo.assign' AND json_extract(response_json,'$.transaction_id') IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1)))) OR json_extract(response_json,'$.raw_sms_id') IN(SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=$1 OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))) OR json_extract(response_json,'$.transaction_id') IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))) OR request_id IN(SELECT r.request_id FROM request_receipts r WHERE\n r.request_id IN(SELECT request_id FROM assisted_sms_claims WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1))\n OR r.request_id IN(SELECT request_id FROM assisted_sms_confirmations WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1))\n OR r.request_id IN(SELECT request_id FROM assisted_sms_send_starts WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1))\n OR r.request_id IN(SELECT request_id FROM assisted_sms_outcomes WHERE attempt_id IN(SELECT s.id FROM assisted_sms_send_starts s JOIN assisted_sms_jobs j ON j.id=s.job_id WHERE j.recipient_user_id=$1))\n OR r.operation='assisted_sms.enqueue' AND json_extract(r.response_json,'$.job_id') IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=$1)\n OR r.operation='assisted_sms.materialize.plan' AND EXISTS(SELECT 1 FROM json_each(CASE WHEN r.operation='assisted_sms.materialize.plan' THEN r.response_json ELSE '{}' END,'$.sources') source WHERE json_extract(source.value,'$.entry_id') IN(SELECT id FROM ledger_entries WHERE member_id=$1))\n OR r.operation IN('assisted_sms.materialize.intent','assisted_sms.materialize.blocked') AND json_extract(r.response_json,'$.source_entry_id') IN(SELECT id FROM ledger_entries WHERE member_id=$1)\n OR r.operation='assisted_sms.policy.configure' AND json_extract(r.response_json,'$.collection_id') IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=$1)) OR \"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "roster_commit_guards": {
      "columns": [
        "id",
        "import_id",
        "revision_id",
        "actor_user_id",
        "session_id",
        "now_seconds",
        "expected_state",
        "expected_latest_revision",
        "permission",
        "collection_id",
        "expected_collection_revision"
      ],
      "where": "(\"import_id\" IN(SELECT id FROM roster_imports WHERE user_id=$1 UNION SELECT source_import_id FROM roster_members WHERE linked_user_id=$1) OR \"actor_user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1))"
    },
    "roster_dispatch_phases": {
      "columns": [
        "processing_id",
        "phase",
        "started_seconds"
      ],
      "where": "(processing_id IN(SELECT id FROM roster_processing_records WHERE actor_user_id=$1))"
    },
    "roster_imports": {
      "columns": [
        "id",
        "user_id",
        "session_id",
        "request_id",
        "collection_id",
        "request_sha256",
        "source_sha256",
        "object_sha256",
        "source_object_key",
        "source_size",
        "source_kind",
        "source_receipt_json",
        "state",
        "latest_revision_id",
        "source_ciphertext",
        "created_seconds",
        "expires_seconds",
        "error_code"
      ],
      "where": "(\"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1) OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1))"
    },
    "roster_intents": {
      "columns": [
        "id",
        "import_id",
        "user_id",
        "session_id",
        "kind",
        "request_id",
        "body_sha256",
        "payload_ciphertext",
        "created_seconds"
      ],
      "where": "(\"import_id\" IN(SELECT id FROM roster_imports WHERE user_id=$1 UNION SELECT source_import_id FROM roster_members WHERE linked_user_id=$1) OR \"user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "roster_members": {
      "columns": [
        "id",
        "collection_id",
        "source_import_id",
        "source_revision_id",
        "member_name",
        "momo_name",
        "momo_number",
        "linked_user_id",
        "created_at"
      ],
      "where": "(collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1) OR \"source_import_id\" IN(SELECT id FROM roster_imports WHERE user_id=$1 UNION SELECT source_import_id FROM roster_members WHERE linked_user_id=$1) OR linked_user_id=$1)"
    },
    "roster_processing_records": {
      "columns": [
        "id",
        "import_id",
        "actor_user_id",
        "session_id",
        "source_sha256",
        "source_object_sha256",
        "policy_sha256",
        "approval_id",
        "approval_evidence_sha256",
        "processor_policy_json",
        "project_id",
        "organization_id",
        "provider",
        "model",
        "processing_region_evidence_ref",
        "retention_evidence_ref",
        "decoder_build_sha256",
        "decoder_lineage_json",
        "created_seconds",
        "expires_seconds"
      ],
      "where": "(\"import_id\" IN(SELECT id FROM roster_imports WHERE user_id=$1 UNION SELECT source_import_id FROM roster_members WHERE linked_user_id=$1) OR \"actor_user_id\"=$1 OR \"session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "roster_revisions": {
      "columns": [
        "id",
        "import_id",
        "request_id",
        "parent_revision_id",
        "revision_number",
        "rows_sha256",
        "preview_ciphertext",
        "human_reviewed",
        "review_reason",
        "created_seconds"
      ],
      "where": "(\"import_id\" IN(SELECT id FROM roster_imports WHERE user_id=$1 UNION SELECT source_import_id FROM roster_members WHERE linked_user_id=$1))"
    },
    "runtime_config": {
      "columns": [
        "key",
        "value_json",
        "revision",
        "updated_by",
        "updated_at"
      ],
      "where": "1=1"
    },
    "sms_receipts": {
      "columns": [
        "id",
        "owner_user_id",
        "originating_session_id",
        "client_envelope_id",
        "body_sha256",
        "receiver_hash",
        "object_key",
        "object_sha256",
        "size_bytes",
        "received_at_device",
        "status",
        "evidence_level",
        "created_at"
      ],
      "where": "(id IN(SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=$1 OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=$1) OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=$1 OR f.linked_by=$1 OR p.member_id=$1))))) OR \"owner_user_id\"=$1 OR \"originating_session_id\" IN(SELECT id FROM auth_sessions WHERE user_id=$1))"
    },
    "support_requests": {
      "columns": [
        "id",
        "user_id",
        "collection_id",
        "kind",
        "message",
        "status",
        "created_at"
      ],
      "where": "(\"user_id\"=$1 OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1))"
    },
    "upload_objects": {
      "columns": [
        "id",
        "user_id",
        "collection_id",
        "object_key",
        "sha256",
        "size_bytes",
        "content_type",
        "purpose",
        "status",
        "created_at",
        "deleted_at"
      ],
      "where": "(\"user_id\"=$1 OR collection_id IN(SELECT collection_id FROM memberships WHERE user_id=$1 UNION SELECT id FROM collections WHERE creator_user_id=$1))"
    },
    "users": {
      "columns": [
        "id",
        "phone",
        "email",
        "full_name",
        "public_id",
        "country_code",
        "currency_code",
        "momo_provider",
        "momo_number",
        "momo_pay_code",
        "access_status",
        "created_at",
        "updated_at",
        "member_type",
        "revision"
      ],
      "where": "(id=$1)"
    }
  },
  "engine_tables": [
    "privacy_retention_plans",
    "privacy_retention_tasks",
    "privacy_retention_claims",
    "privacy_retention_outcomes",
    "privacy_retention_effects",
    "privacy_retention_guards",
    "privacy_retention_barriers"
  ],
  "private_classes": [
    {
      "name": "private:auth_principal_links",
      "relation": "private.auth_principal_links",
      "scope": "principal",
      "purpose": "Stable managed Auth to legacy principal proof",
      "where": "r.user_id=$1",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.auth_user_id::text)::text,'UTF8')),'hex')",
      "lifecycle": "'{}'::jsonb"
    },
    {
      "name": "private:supabase_otp_challenges",
      "relation": "private.supabase_otp_challenges",
      "scope": "otp",
      "purpose": "Identity, cooldown, provider outcome and consumed challenge evidence",
      "where": "r.privacy_expected_user_id=$1 OR r.privacy_verified_user_id=$1 OR r.identity_value IN(SELECT email FROM app.users WHERE id=$1 UNION SELECT phone FROM app.users WHERE id=$1 UNION SELECT a.email FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id WHERE l.user_id=$1)",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.id)::text,'UTF8')),'hex')",
      "lifecycle": "jsonb_build_object('active',r.consumed_at IS NULL AND r.expires_at>app.unixepoch() AND r.delivery_status IN('reserved','accepted','unknown') AND(r.privacy_mode IS NULL OR r.privacy_cancelled_at IS NULL),'unresolved',r.privacy_mode IS NOT NULL AND(r.privacy_verification_state IN('verifying','unconfirmed') OR r.privacy_cleanup_state IN('claimed','unconfirmed')))"
    },
    {
      "name": "private:bff_sessions",
      "relation": "private.bff_sessions",
      "scope": "bff",
      "purpose": "Encrypted Admin session token custody and refresh leases",
      "where": "r.auth_user_id IN(SELECT auth_user_id FROM private.auth_principal_links WHERE user_id=$1)",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.token_hash)::text,'UTF8')),'hex')",
      "lifecycle": "'{}'::jsonb"
    },
    {
      "name": "private:admin_email_operations",
      "relation": "private.admin_email_operations",
      "scope": "admin_email",
      "purpose": "Subject-linked Admin email purpose, exact original BFF binding, provider outcome and unresolved candidate cleanup evidence; blocked retained provenance",
      "where": "r.principal_id=$1",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r)-ARRAY['send_claim','verification_state','verification_operation_id','verify_receipts','cleanup_state','cleanup_claim','verified_session_id','verified_amr_at'])::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.challenge_id)::text,'UTF8')),'hex')",
      "lifecycle": "jsonb_build_object('state',r.verification_state,'cleanup',r.cleanup_state,'active',EXISTS(SELECT 1 FROM private.supabase_otp_challenges q WHERE q.id=r.challenge_id AND q.consumed_at IS NULL AND q.expires_at>app.unixepoch() AND q.delivery_status IN('reserved','accepted','unknown')),'unresolved',r.verification_state IN('verifying','unconfirmed') OR r.cleanup_state IN('claimed','unconfirmed') OR(r.mode='reauth' AND r.verification_state='verified' AND r.cleanup_state='not_started') OR(r.send_claim IS NOT NULL AND EXISTS(SELECT 1 FROM private.supabase_otp_challenges q WHERE q.id=r.challenge_id AND q.delivery_status='reserved')))"
    },
    {
      "name": "private:admin_sensitive_email_proofs",
      "relation": "private.admin_sensitive_email_proofs",
      "scope": "admin_email",
      "purpose": "Immutable subject-linked original email OTP event and exact Admin session proof; blocked retained provenance",
      "where": "r.principal_id=$1",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.id::text)::text,'UTF8')),'hex')",
      "lifecycle": "jsonb_build_object('immutable',true)"
    },
    {
      "name": "private:managed_mfa_proofs",
      "relation": "private.managed_mfa_proofs",
      "scope": "mfa",
      "purpose": "Verified managed factor/session freshness projection",
      "where": "r.user_id IN(SELECT auth_user_id FROM private.auth_principal_links WHERE user_id=$1)",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.session_id::text)::text,'UTF8')),'hex')",
      "lifecycle": "'{}'::jsonb"
    },
    {
      "name": "private:managed_phone_verifications",
      "relation": "private.managed_phone_verifications",
      "scope": "principal",
      "purpose": "Immutable original managed phone OTP event and confirmed canonical phone binding",
      "where": "r.user_id=$1",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.challenge_id)::text,'UTF8')),'hex')",
      "lifecycle": "'{}'::jsonb"
    },
    {
      "name": "private:google_flow_context",
      "relation": "private.google_flow_context",
      "scope": "google",
      "purpose": "Immutable OAuth surface and browser-origin custody",
      "where": "r.flow_id IN(SELECT f.id FROM app.auth_google_flows f WHERE f.email IN(SELECT email FROM app.users WHERE id=$1 UNION SELECT a.email FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id WHERE l.user_id=$1) OR f.google_subject IN(SELECT subject FROM app.auth_google_identities WHERE user_id=$1))",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.flow_id)::text,'UTF8')),'hex')",
      "lifecycle": "'{}'::jsonb"
    },
    {
      "name": "private:admin_invitation_attempts",
      "relation": "private.admin_invitation_attempts",
      "scope": "admin_invitation",
      "purpose": "Immutable staff preapproval, idempotency aliases and one native invitation dispatch claim/outcome; no email or token payload",
      "where": "r.principal_id=$1 OR r.actor_principal_id=$1",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.request_id::text)::text,'UTF8')),'hex')",
      "lifecycle": "jsonb_build_object('state',r.state,'active',r.replayed_request_id IS NULL AND r.state IN('reserved','dispatching','unknown'),'alias',r.replayed_request_id IS NOT NULL)"
    },
    {
      "name": "private:storage_namespace",
      "relation": "private.storage_namespace",
      "scope": "namespace",
      "purpose": "Shared immutable provider origin and private bucket identity",
      "where": "true",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to(('singleton')::text,'UTF8')),'hex')",
      "lifecycle": "'{}'::jsonb"
    },
    {
      "name": "private:storage_payload_reservations",
      "relation": "private.storage_payload_reservations",
      "scope": "storage",
      "purpose": "First random ciphertext reservation, semantic request binding and cleared-spool tombstone",
      "where": "r.object_key IN(SELECT object_key FROM private.storage_put_intents WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM private.storage_payload_reservations WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM app.payment_evidence WHERE owner_user_id=$1\n UNION SELECT object_key FROM app.sms_receipts WHERE owner_user_id=$1\n UNION SELECT source_object_key FROM app.roster_imports WHERE user_id=$1\n UNION SELECT object_key FROM app.upload_objects WHERE user_id=$1)",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r)-ARRAY['sealed_body','cleared_at'])::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.object_key)::text,'UTF8')),'hex')",
      "lifecycle": "jsonb_build_object('sealed',r.sealed_body IS NOT NULL,'cleared',r.cleared_at IS NOT NULL,'sha256',r.plaintext_sha256)"
    },
    {
      "name": "private:storage_put_intents",
      "relation": "private.storage_put_intents",
      "scope": "storage",
      "purpose": "Durable upload identity, unresolved provider outcomes and delete fence",
      "where": "r.object_key IN(SELECT object_key FROM private.storage_put_intents WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM private.storage_payload_reservations WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM app.payment_evidence WHERE owner_user_id=$1\n UNION SELECT object_key FROM app.sms_receipts WHERE owner_user_id=$1\n UNION SELECT source_object_key FROM app.roster_imports WHERE user_id=$1\n UNION SELECT object_key FROM app.upload_objects WHERE user_id=$1)",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r)-ARRAY['state','delete_tombstone','last_outcome','updated_at'])::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.object_key)::text,'UTF8')),'hex')",
      "lifecycle": "jsonb_build_object('state',r.state,'tombstone',r.delete_tombstone,'unresolved',r.upload_unresolved,'active',r.active_attempt IS NOT NULL,'sha256',r.sha256)"
    },
    {
      "name": "private:storage_upload_attempts",
      "relation": "private.storage_upload_attempts",
      "scope": "attempt",
      "purpose": "Individual provider upload send-start and terminal or unknown outcome",
      "where": "r.operation_id IN(SELECT operation_id FROM private.storage_put_intents WHERE object_key IN(SELECT object_key FROM private.storage_put_intents WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM private.storage_payload_reservations WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM app.payment_evidence WHERE owner_user_id=$1\n UNION SELECT object_key FROM app.sms_receipts WHERE owner_user_id=$1\n UNION SELECT source_object_key FROM app.roster_imports WHERE user_id=$1\n UNION SELECT object_key FROM app.upload_objects WHERE user_id=$1))",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.id::text)::text,'UTF8')),'hex')",
      "lifecycle": "'{}'::jsonb"
    },
    {
      "name": "private:storage_objects",
      "relation": "private.storage_objects",
      "scope": "storage",
      "purpose": "Canonical committed protected-object metadata",
      "where": "r.object_key IN(SELECT object_key FROM private.storage_put_intents WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM private.storage_payload_reservations WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM app.payment_evidence WHERE owner_user_id=$1\n UNION SELECT object_key FROM app.sms_receipts WHERE owner_user_id=$1\n UNION SELECT source_object_key FROM app.roster_imports WHERE user_id=$1\n UNION SELECT object_key FROM app.upload_objects WHERE user_id=$1)",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.object_key)::text,'UTF8')),'hex')",
      "lifecycle": "'{}'::jsonb"
    },
    {
      "name": "private:storage_delete_intents",
      "relation": "private.storage_delete_intents",
      "scope": "storage",
      "purpose": "Retained erasure identity and independently verified dual-absence receipt",
      "where": "r.object_key IN(SELECT object_key FROM private.storage_put_intents WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM private.storage_payload_reservations WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM app.payment_evidence WHERE owner_user_id=$1\n UNION SELECT object_key FROM app.sms_receipts WHERE owner_user_id=$1\n UNION SELECT source_object_key FROM app.roster_imports WHERE user_id=$1\n UNION SELECT object_key FROM app.upload_objects WHERE user_id=$1)",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r)-ARRAY['state','last_outcome','absence_proof','committed_at'])::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.object_key)::text,'UTF8')),'hex')",
      "lifecycle": "jsonb_build_object('state',r.state,'absence',coalesce(r.absence_proof @> '{\"headStatus\":404,\"getStatus\":404,\"bucketVerified\":true}'::jsonb,false),'sha256',r.expected_sha256)"
    },
    {
      "name": "private:object_metadata",
      "relation": "private.object_metadata",
      "scope": "metadata_view",
      "purpose": "Read-only alias of canonical metadata; not an additional byte copy",
      "where": "r.object_key IN(SELECT object_key FROM private.storage_put_intents WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM private.storage_payload_reservations WHERE scope->>'ownerId'=$1\n UNION SELECT object_key FROM app.payment_evidence WHERE owner_user_id=$1\n UNION SELECT object_key FROM app.sms_receipts WHERE owner_user_id=$1\n UNION SELECT source_object_key FROM app.roster_imports WHERE user_id=$1\n UNION SELECT object_key FROM app.upload_objects WHERE user_id=$1)",
      "rowHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "identityHash": "encode(sha256(convert_to((to_jsonb(r))::text,'UTF8')),'hex')",
      "keyHash": "encode(sha256(convert_to((r.object_key)::text,'UTF8')),'hex')",
      "lifecycle": "'{}'::jsonb"
    },
    {
      "name": "private:collect_fence_control",
      "relation": "private.collect_fence_control",
      "scope": "shared_fence",
      "purpose": "Shared source/epoch/mode control binding; owner-only authoritative history; blocked shared operational copy, never a subject-empty or erasure assertion",
      "blocked": true
    },
    {
      "name": "private:collect_fence_admissions",
      "relation": "private.collect_fence_admissions",
      "scope": "shared_fence",
      "purpose": "Opaque unattributed runtime admission lifecycle; active/unresolved/settled and unknown-obligation facts have no approved pruning; blocked shared operational copy, never a subject-empty or erasure assertion",
      "blocked": true
    },
    {
      "name": "private:collect_fence_operations",
      "relation": "private.collect_fence_operations",
      "scope": "shared_fence",
      "purpose": "Immutable opaque emergency control operation receipts; blocked shared operational copy, never a subject-empty or erasure assertion",
      "blocked": true
    },
    {
      "name": "private:collect_fence_scheduler_lifecycle",
      "relation": "private.collect_fence_scheduler_lifecycle",
      "scope": "shared_fence",
      "purpose": "Owner-only original scheduler dispatch local-lifecycle evidence; original provider unknowns remain unchanged; blocked shared operational copy, never a subject-empty or erasure assertion",
      "blocked": true
    },
    {
      "name": "private:collect_fence_source_upgrades",
      "relation": "private.collect_fence_source_upgrades",
      "scope": "shared_fence",
      "purpose": "Immutable owner-reviewed old/new source and epoch lineage, exact prior control snapshot and proof digests; blocked shared operational copy, no lost-work resolution or provider settlement",
      "blocked": true
    },
    {
      "name": "private:collect_fence_stopped_admissions",
      "relation": "private.collect_fence_stopped_admissions",
      "scope": "shared_fence",
      "purpose": "Immutable owner proof of stopped local work, original admission snapshot and unquantified unknown obligation; blocked shared operational copy, no recovered counters, provider settlement or subject-empty assertion",
      "blocked": true
    },
    {
      "name": "private:member_realtime_control",
      "relation": "private.member_realtime_control",
      "scope": "shared_realtime",
      "purpose": "Shared source/policy activation, global audit cursor and finite attempt/rate counters; no member/Auth/session/topic/event payload",
      "blocked": true
    },
    {
      "name": "private:collect_fence_working_admissions",
      "relation": "private.collect_fence_working_admissions",
      "scope": "shared_fence",
      "purpose": "Derived bounded working index; removing an index row requires an immutable safe-settlement archive receipt; original history and unknown effects remain retained",
      "blocked": true
    },
    {
      "name": "private:collect_fence_admission_archive",
      "relation": "private.collect_fence_admission_archive",
      "scope": "shared_fence",
      "purpose": "Immutable hash receipts of original settled admissions with zero uncertain dispatches; logical in-place archival, never erasure",
      "blocked": true
    },
    {
      "name": "private:collect_fence_admission_totals",
      "relation": "private.collect_fence_admission_totals",
      "scope": "shared_fence",
      "purpose": "Derived lifetime and logical-archive counts maintained atomically by lifecycle triggers; no subject-empty assertion",
      "blocked": true
    },
    {
      "name": "private:member_history_versions",
      "relation": "private.member_history_versions",
      "scope": "shared_fence",
      "purpose": "Shared group-scoped history revision counters for consistent cursor invalidation; no financial payload or subject erasure",
      "blocked": true
    },
    {
      "name": "private:collect_deployment_identity",
      "relation": "private.collect_deployment_identity",
      "scope": "shared_fence",
      "purpose": "Owner-only public deployment profile/hash and operation identity; blocked shared configuration lineage with no subject erasure",
      "blocked": true
    },
    {
      "name": "private:collect_sms_fence_admissions",
      "relation": "private.collect_sms_fence_admissions",
      "scope": "shared_fence",
      "purpose": "Immutable ownership of SMS gateway application admissions, deployment profile hash and creation time; shared controller lineage retained in database backups, no subject selector or erasure adapter",
      "blocked": true
    },
    {
      "name": "private:guest_upgrade_challenges",
      "relation": "private.guest_upgrade_challenges",
      "scope": "shared_fence",
      "purpose": "Retained guest identity upgrade and projection-denial journal; unknown, unverified, expired and delivery-rejected records remain while the native identity exists. No pruning or subject-empty assertion; verified completion requires the durable same-AuthUUID principal link.",
      "blocked": true
    },
    {
      "name": "private:retention_inventory_manifests",
      "relation": "private.retention_inventory_manifests",
      "scope": "shared_fence",
      "purpose": "Immutable subject/request/review/source/schema/hold-bound metadata inventory receipts; capture is not erasure authorization",
      "blocked": true
    },
    {
      "name": "private:retention_inventory_pages",
      "relation": "private.retention_inventory_pages",
      "scope": "shared_fence",
      "purpose": "Immutable bounded opaque descriptor pages and hashes; governed retention evidence, no raw Auth secrets or object bodies",
      "blocked": true
    },
    {
      "name": "private:retention_row_plans",
      "relation": "private.retention_row_plans",
      "scope": "shared_fence",
      "purpose": "Exact owner-approved manifest policy and retained SQL-row disposition state",
      "blocked": true
    },
    {
      "name": "private:retention_row_claims",
      "relation": "private.retention_row_claims",
      "scope": "shared_fence",
      "purpose": "Immutable actor/session/fence-bound SQL-row leases",
      "blocked": true
    },
    {
      "name": "private:retention_row_effects",
      "relation": "private.retention_row_effects",
      "scope": "shared_fence",
      "purpose": "Immutable opaque before/after descriptor commitments for authorized SQL changes",
      "blocked": true
    },
    {
      "name": "private:retention_row_operations",
      "relation": "private.retention_row_operations",
      "scope": "shared_fence",
      "purpose": "Immutable original-operation outcome receipts; atomic SQL results do not prove external erasure",
      "blocked": true
    }
  ],
  "copy_classes": [
    "r2:payment_evidence",
    "r2:sms_receipts",
    "r2:roster_imports",
    "r2:upload_objects",
    "external:derivatives",
    "external:exports",
    "external:backups",
    "external:processors",
    "external:unmapped_identifiers",
    "external:collect_sms",
    "external:collect_ops",
    "external:vault",
    "external:net",
    "external:cron",
    "external:supabase_migrations"
  ],
  "gateway_tables": [
    "acceptances",
    "application_outbox_health",
    "applications",
    "attempts",
    "audit_events",
    "campaign_budget",
    "campaigns",
    "contribution_events",
    "contribution_receipts",
    "device_events",
    "devices",
    "dispatch_permits",
    "ledger_notification_events",
    "ledger_notification_receipts",
    "message_parts",
    "messages",
    "metric_alert_events",
    "metric_alerts",
    "notification_schedules",
    "otp_capacity_requirements",
    "otp_capacity_reservations",
    "otp_challenges",
    "otp_slots",
    "schedule_occurrences",
    "sms_templates",
    "staff_accounts",
    "staff_sessions",
    "webhook_deliveries",
    "webhook_endpoints"
  ]
}
$catalog$::jsonb
$function$;

COMMIT;
