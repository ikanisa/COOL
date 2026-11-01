-- Sealed metadata inspection only. No personal-data erasure, provider request,
-- expiry/pruning or policy approval is introduced by this migration.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $$BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR to_regclass('private.collect_fence_stopped_admissions') IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='retention_manifest_owner_install_required';END IF;
END$$;

CREATE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $function$
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

CREATE TABLE private.retention_inventory_manifests(
 id uuid PRIMARY KEY, request_id text NOT NULL, subject_id text NOT NULL,
 actor_id text NOT NULL, session_id text NOT NULL, input_sha256 text NOT NULL CHECK(input_sha256~'^[a-f0-9]{64}$'),
 source_sha256 text NOT NULL CHECK(source_sha256~'^[a-f0-9]{64}$'),
 schema_sha256 text NOT NULL CHECK(schema_sha256~'^[a-f0-9]{64}$'),
 schema_identity jsonb NOT NULL, control_identity jsonb NOT NULL,
 descriptor_count bigint NOT NULL CHECK(descriptor_count BETWEEN 1 AND 1000000),
 page_count integer NOT NULL CHECK(page_count BETWEEN 1 AND 10000),
 class_counts jsonb NOT NULL,
 pages_sha256 text NOT NULL CHECK(pages_sha256~'^[a-f0-9]{64}$'),
 manifest_sha256 text NOT NULL CHECK(manifest_sha256~'^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.retention_inventory_pages(
 manifest_id uuid NOT NULL REFERENCES private.retention_inventory_manifests(id) DEFERRABLE INITIALLY DEFERRED,
 page_number integer NOT NULL CHECK(page_number BETWEEN 0 AND 9999),
 descriptors jsonb NOT NULL CHECK(octet_length(descriptors::text)<=131072 AND jsonb_typeof(descriptors)='array' AND jsonb_array_length(descriptors) BETWEEN 1 AND 100),
 descriptor_count integer GENERATED ALWAYS AS(jsonb_array_length(descriptors)) STORED,
 page_sha256 text NOT NULL CHECK(page_sha256~'^[a-f0-9]{64}$'),
 PRIMARY KEY(manifest_id,page_number) INCLUDE(page_sha256,descriptor_count),
 CHECK(encode(sha256(convert_to(descriptors::text,'UTF8')),'hex')=page_sha256)
);
CREATE INDEX retention_inventory_subject_created ON private.retention_inventory_manifests(subject_id,created_at DESC,id);
CREATE FUNCTION private._retention_manifest_immutable_v2() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $$BEGIN
 RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='retention_manifest_immutable';END$$;
DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['retention_inventory_manifests','retention_inventory_pages'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer',t);
  EXECUTE format('CREATE TRIGGER retention_manifest_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._retention_manifest_immutable_v2()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER retention_manifest_immutable',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
 END LOOP;
END$$;

CREATE FUNCTION private._retention_manifest_schema_v2() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE catalog jsonb:=private._retention_manifest_catalog_v2();r record;expected jsonb;actual jsonb;schema_rows jsonb;helpers jsonb;roles jsonb;memberships jsonb;
 known_auth text[]:=ARRAY['audit_log_entries','custom_oauth_providers','flow_state','identities','instances','mfa_amr_claims','mfa_challenges','mfa_factors','mfa_recovery_code_sets','mfa_recovery_codes','oauth_authorizations','oauth_client_states','oauth_clients','oauth_consents','one_time_tokens','refresh_tokens','saml_providers','saml_relay_states','schema_migrations','scim_tokens','scim_users','sessions','sso_domains','sso_providers','users','webauthn_challenges','webauthn_credentials'];
 known_storage text[]:=ARRAY['buckets','buckets_analytics','buckets_vectors','migrations','objects','s3_multipart_uploads','s3_multipart_uploads_parts','vector_indexes'];
BEGIN
 FOR r IN SELECT n.nspname,c.relname,c.relkind,c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN('app','private','auth','storage','collect_sms') AND c.relkind IN('r','p','v') LOOP
  IF r.nspname='app' AND r.relkind IN('r','p') THEN
   IF catalog->'engine_tables' ? r.relname THEN CONTINUE;END IF;
   expected:=catalog->'application'->r.relname->'columns';
   IF expected IS NULL THEN RAISE EXCEPTION 'retention_manifest_unknown_application_relation' USING ERRCODE='42501';END IF;
   SELECT jsonb_agg(a.attname ORDER BY a.attnum) INTO actual FROM pg_attribute a WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped;
   -- The entire SQL16 predecessor remains an explicit supported prefix.
   IF r.relname='notification_preferences' AND to_regclass('app.notification_email_deliveries') IS NULL THEN expected:=expected-ARRAY['email_enabled','payment_reminders','security_notices'];END IF;
   IF actual<>expected THEN RAISE EXCEPTION 'retention_manifest_application_columns_changed' USING ERRCODE='42501';END IF;
  ELSIF r.nspname='private' THEN
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(catalog->'private_classes') c WHERE c->>'relation'='private.'||r.relname) THEN
    RAISE EXCEPTION 'retention_manifest_unknown_private_relation' USING ERRCODE='42501';END IF;
  ELSIF r.nspname='auth' AND NOT r.relname=ANY(known_auth) OR r.nspname='storage' AND NOT r.relname=ANY(known_storage) THEN
   RAISE EXCEPTION 'retention_manifest_unknown_managed_relation' USING ERRCODE='42501';
  ELSIF r.nspname='collect_sms' AND NOT(catalog->'gateway_tables' ? r.relname) AND r.relname<>'attempt_evidence' THEN
   RAISE EXCEPTION 'retention_manifest_unknown_gateway_relation' USING ERRCODE='42501';
  END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(catalog->'application') k
   WHERE to_regclass('app.'||k) IS NULL AND k NOT IN('notification_email_deliveries','assisted_sms_dispatches','notification_email_job_dispatches'))
  OR(to_regclass('app.notification_email_deliveries') IS NULL)<>(to_regclass('app.assisted_sms_dispatches') IS NULL)
  OR(to_regclass('app.notification_email_deliveries') IS NULL)<>(to_regclass('app.notification_email_job_dispatches') IS NULL)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(catalog->'engine_tables') k WHERE to_regclass('app.'||k) IS NULL)
  OR(to_regclass('collect_sms.messages') IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements_text(catalog->'gateway_tables') k WHERE to_regclass('collect_sms.'||k) IS NULL)) THEN
  RAISE EXCEPTION 'retention_manifest_incomplete_schema' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'kind',c.relkind,
  'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'schema_acl',n.nspacl::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'generated',a.attgenerated,'identity',a.attidentity,'acl',a.attacl::text,'default',(SELECT pg_get_expr(d.adbin,d.adrelid) FROM pg_attrdef d WHERE d.adrelid=a.attrelid AND d.adnum=a.attnum)) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
  'constraints',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),
  'triggers',(SELECT jsonb_agg(jsonb_build_object('definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),
  'policies',(SELECT jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,'permissive',p.polpermissive,'roles',p.polroles::text,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid),
  'view',CASE WHEN c.relkind='v' THEN pg_get_viewdef(c.oid,true) END,
  'partition_bound',pg_get_expr(c.relpartbound,c.oid)) ORDER BY n.nspname,c.relname),'[]') INTO schema_rows
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('app','private','auth','storage','realtime','collect_sms','collect_ops','vault','net','cron','supabase_migrations') AND c.relkind IN('r','p','v');
 SELECT jsonb_agg(jsonb_build_object('name',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'sha256',encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')) ORDER BY p.oid::regprocedure::text) INTO helpers
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('app','private','api','auth','storage','realtime','collect_sms','collect_ops','vault','net','cron','supabase_migrations') AND p.prokind='f';
 SELECT jsonb_agg(jsonb_build_object('name',rolname,'super',rolsuper,'bypass',rolbypassrls,'inherit',rolinherit,'login',rolcanlogin,'create_role',rolcreaterole,'create_db',rolcreatedb,'replication',rolreplication) ORDER BY rolname) INTO roles
 FROM pg_roles WHERE rolname IN('postgres','anon','authenticated','service_role','collect_runtime','collect_importer','collect_edge','collect_sms_runtime','supabase_realtime_admin');
 SELECT coalesce(jsonb_agg(jsonb_build_object('role',pg_get_userbyid(roleid),'member',pg_get_userbyid(member),'grantor',pg_get_userbyid(grantor),'admin',admin_option,'inherit',inherit_option,'set',set_option) ORDER BY roleid,member,grantor),'[]') INTO memberships
 FROM pg_auth_members WHERE roleid IN(SELECT oid FROM pg_roles WHERE rolname IN('postgres','anon','authenticated','service_role','collect_runtime','collect_importer','collect_edge','collect_sms_runtime','supabase_realtime_admin'))
 OR member IN(SELECT oid FROM pg_roles WHERE rolname IN('postgres','anon','authenticated','service_role','collect_runtime','collect_importer','collect_edge','collect_sms_runtime','supabase_realtime_admin'));
 RETURN jsonb_build_object('contract','collect.retention.schema.v2','sha256',encode(sha256(convert_to(jsonb_build_object('relations',schema_rows,'helpers',helpers,'roles',roles,'memberships',memberships)::text,'UTF8')),'hex'),
  'catalog_sha256',encode(sha256(convert_to(catalog::text,'UTF8')),'hex'),'relation_count',jsonb_array_length(schema_rows),
  'gateway_relation_count',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='collect_sms' AND c.relkind IN('r','p','v')));
END$$;

CREATE FUNCTION private._retention_manifest_managed_rows_v2(p_subject text,p_limit integer DEFAULT 1000001)
RETURNS TABLE(class_name text,descriptor jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=app,pg_catalog,pg_temp AS $$
DECLARE relation record;managed_id uuid;bucket_name text;bucket_private boolean:=false;predicate text;sql_text text;produced bigint:=0;emitted bigint;
 owned_sql text:='SELECT object_key FROM private.storage_put_intents WHERE scope->>''ownerId''=$2 UNION SELECT object_key FROM private.storage_payload_reservations WHERE scope->>''ownerId''=$2 UNION SELECT object_key FROM app.payment_evidence WHERE owner_user_id=$2 UNION SELECT object_key FROM app.sms_receipts WHERE owner_user_id=$2 UNION SELECT source_object_key FROM app.roster_imports WHERE user_id=$2 UNION SELECT object_key FROM app.upload_objects WHERE user_id=$2';
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 3 AND 1000001 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 SELECT auth_user_id INTO managed_id FROM private.auth_principal_links WHERE user_id=p_subject;
 SELECT bucket INTO bucket_name FROM private.storage_namespace WHERE singleton;
 IF to_regclass('storage.buckets') IS NOT NULL AND bucket_name IS NOT NULL THEN EXECUTE 'SELECT NOT public FROM storage.buckets WHERE id=$1' INTO bucket_private USING bucket_name;END IF;
 RETURN QUERY SELECT 'managed:auth',jsonb_build_object('kind','class','status',CASE WHEN managed_id IS NULL THEN 'unmapped' ELSE 'observed' END,'provider_logs_backups','blocked');
 produced:=produced+1;
 FOR relation IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='auth' AND c.relkind IN('r','p') ORDER BY c.relname LOOP
  predicate:=CASE relation.relname
   WHEN 'users' THEN 'r.id=$1'
   WHEN 'refresh_tokens' THEN 'r.user_id=$1::text OR r.session_id IN(SELECT id FROM auth.sessions WHERE user_id=$1)'
   WHEN 'flow_state' THEN 'r.user_id=$1 OR to_jsonb(r)->>''linking_target_id''=$1::text'
   WHEN 'mfa_amr_claims' THEN 'r.session_id IN(SELECT id FROM auth.sessions WHERE user_id=$1)'
   WHEN 'mfa_challenges' THEN 'r.factor_id IN(SELECT id FROM auth.mfa_factors WHERE user_id=$1)'
   WHEN 'mfa_recovery_codes' THEN 'r.mfa_recovery_code_set_id IN(SELECT id FROM auth.mfa_recovery_code_sets WHERE user_id=$1)'
   WHEN 'oauth_client_states' THEN 'r.id IN(SELECT (to_jsonb(f)->>''oauth_client_state_id'')::uuid FROM auth.flow_state f WHERE f.user_id=$1 OR to_jsonb(f)->>''linking_target_id''=$1::text)'
   WHEN 'saml_relay_states' THEN 'r.flow_state_id IN(SELECT id FROM auth.flow_state WHERE user_id=$1)'
   WHEN 'audit_log_entries' THEN 'r.payload::jsonb->>''actor_id''=$1::text OR r.payload::jsonb->>''user_id''=$1::text'
   WHEN 'custom_oauth_providers' THEN NULL WHEN 'instances' THEN NULL WHEN 'oauth_clients' THEN NULL WHEN 'saml_providers' THEN NULL WHEN 'schema_migrations' THEN NULL WHEN 'scim_tokens' THEN NULL WHEN 'sso_domains' THEN NULL WHEN 'sso_providers' THEN NULL
   ELSE 'r.user_id=$1' END;
  IF predicate IS NULL OR managed_id IS NULL THEN CONTINUE;END IF;
  sql_text:=format('SELECT ''managed:auth''::text,jsonb_build_object(''kind'',''row'',''relation'',%L,''key_sha256'',encode(sha256(convert_to(%L||'':''||coalesce(to_jsonb(r)->>''id'',to_jsonb(r)->>''session_id'',to_jsonb(r)::text)||'':''||coalesce(to_jsonb(r)->>''authentication_method'',''''),''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''lifecycle'',''{}''::jsonb) FROM auth.%I r WHERE %s',relation.relname,relation.relname,relation.relname,predicate);
  RETURN QUERY EXECUTE sql_text||format(' LIMIT %s',greatest(p_limit-produced,1)) USING managed_id;
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
  IF produced>=p_limit THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 END LOOP;
 RETURN QUERY SELECT 'managed:storage',jsonb_build_object('kind','class','status',CASE WHEN bucket_name IS NOT NULL AND coalesce(bucket_private,false) AND to_regclass('storage.objects') IS NOT NULL THEN 'observed' ELSE 'unavailable' END,'scope','owned_catalog_and_principal_metadata','object_content_verification','not_performed');
 produced:=produced+1;
 IF bucket_name IS NOT NULL AND to_regclass('storage.objects') IS NOT NULL THEN
  FOR relation IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='storage' AND c.relkind IN('r','p') AND c.relname IN('objects','s3_multipart_uploads','s3_multipart_uploads_parts') ORDER BY c.relname LOOP
   predicate:=CASE relation.relname WHEN 'objects' THEN 'r.name IN('||owned_sql||') OR to_jsonb(r)->>''owner_id''=$1::text OR to_jsonb(r)->>''owner''=$1::text' ELSE 'r.key IN('||owned_sql||') OR to_jsonb(r)->>''owner_id''=$1::text' END;
   sql_text:=format('SELECT ''managed:storage''::text,jsonb_build_object(''kind'',''row'',''relation'',%L,''key_sha256'',encode(sha256(convert_to(%s,''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''lifecycle'',jsonb_build_object(''catalog_rows'',1,''erasure_verified'',false)) FROM storage.%I r WHERE r.bucket_id=$3 AND (%s)',relation.relname,CASE WHEN relation.relname='objects' THEN 'r.name' ELSE 'r.key' END,relation.relname,predicate);
   RETURN QUERY EXECUTE sql_text||format(' LIMIT %s',greatest(p_limit-produced,1)) USING managed_id,p_subject,bucket_name;
   GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
   IF produced>=p_limit THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  END LOOP;
 END IF;
 RETURN QUERY SELECT 'managed:realtime_messages',jsonb_build_object('kind','class','status',CASE WHEN managed_id IS NULL OR to_regclass('realtime.messages') IS NULL THEN 'unavailable' ELSE 'observed' END,'scope','retained_member_topics_only','provider_logs_backups','blocked','erasure_verified',false);
 produced:=produced+1;
 IF managed_id IS NOT NULL AND to_regclass('realtime.messages') IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM app.auth_sessions WHERE user_id=p_subject AND surface='member' AND id !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$') THEN RAISE EXCEPTION 'retention_manifest_realtime_attribution_unavailable' USING ERRCODE='42501';END IF;
  RETURN QUERY SELECT 'managed:realtime_messages',jsonb_build_object('kind','row','key_sha256',encode(sha256(convert_to(r.topic||':'||r.id::text||':'||r.inserted_at::text,'UTF8')),'hex'),
   'row_sha256',encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),'identity_sha256',encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),'lifecycle',jsonb_build_object('managed_copy',true,'erasure_verified',false))
   FROM realtime.messages r WHERE r.topic IN(SELECT 'collect:member:'||managed_id::text||':'||s.id FROM app.auth_sessions s WHERE s.user_id=p_subject AND s.surface='member') LIMIT greatest(p_limit-produced,1);
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
 END IF;
 IF produced>=p_limit THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
END$$;

CREATE FUNCTION private._retention_manifest_rows_v2(p_subject text)
RETURNS TABLE(class_name text,descriptor jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=app,pg_catalog,pg_temp AS $$
DECLARE catalog jsonb:=private._retention_manifest_catalog_v2();entry record;c jsonb;predicate text;sql_text text;life text;engine text;produced bigint:=0;emitted bigint;
BEGIN
 FOR entry IN SELECT * FROM jsonb_each(catalog->'application') ORDER BY key LOOP
  produced:=produced+1;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  IF to_regclass('app.'||entry.key) IS NULL THEN
   RETURN QUERY SELECT entry.key,jsonb_build_object('kind','class','status','absent_schema');CONTINUE;END IF;
  RETURN QUERY SELECT entry.key,jsonb_build_object('kind','class','status',CASE WHEN entry.key='client_diagnostic_reports' THEN 'unmapped' ELSE 'observed' END);
  predicate:=entry.value->>'where';
  -- Approved policy bytes bind separately; the approval cannot hash itself.
  IF entry.key='runtime_config' THEN predicate:='('||predicate||') AND key NOT IN(''privacy:retention:approved:v1'',''privacy:retention:approved:v2'')';END IF;
  life:=CASE entry.key
   WHEN 'privacy_holds' THEN 'jsonb_build_object(''hold'',r.active=1)'
   WHEN 'payment_evidence' THEN 'jsonb_build_object(''hold'',r.legal_hold=1,''physical_object_unverified'',true)'
   WHEN 'sms_receipts' THEN 'jsonb_build_object(''physical_object_unverified'',true)'
   WHEN 'upload_objects' THEN 'jsonb_build_object(''physical_object_unverified'',true)'
   WHEN 'roster_imports' THEN 'jsonb_build_object(''unresolved'',r.state IN(''processing'',''ambiguous''),''physical_object_unverified'',true)'
   WHEN 'native_reservations' THEN 'jsonb_build_object(''unresolved'',r.state NOT IN(''completed'',''rejected''))'
   WHEN 'auth_otp_challenges' THEN 'jsonb_build_object(''unresolved'',r.status IN(''dispatching'',''delivery_unknown''))'
   WHEN 'assisted_sms_jobs' THEN 'jsonb_build_object(''unresolved'',r.state NOT IN(''observed_sent'',''failed_no_send''))'
   WHEN 'momo_processing_jobs' THEN 'jsonb_build_object(''unresolved'',r.state<>''completed'')'
   WHEN 'momo_processing_guards' THEN 'jsonb_build_object(''unresolved'',true)'
   WHEN 'notification_deliveries' THEN 'jsonb_build_object(''unresolved'',r.state IN(''pending'',''claimed'',''sending'',''retry'',''unknown''))'
   WHEN 'notification_email_job_dispatches' THEN 'jsonb_build_object(''unresolved'',r.state IN(''claimed'',''unknown''),''shared'',true)'
   WHEN 'notification_email_deliveries' THEN 'jsonb_build_object(''unresolved'',r.state IN(''pending'',''sending'',''unknown''))'
   WHEN 'assisted_sms_dispatches' THEN 'jsonb_build_object(''unresolved'',r.state IN(''ready'',''sending'',''unknown''))'
   WHEN 'admin_email_otp_challenges' THEN 'jsonb_build_object(''unresolved'',r.used_at IS NULL AND r.delivery_status IN(''pending'',''accepted'',''unknown'') AND r.expires_at>app.unixepoch())'
   WHEN 'auth_google_flows' THEN 'jsonb_build_object(''unresolved'',r.status IN(''pending'',''exchanging'',''ready'') AND r.expires_at>app.unixepoch())'
   ELSE '''{}''::jsonb' END;
  sql_text:=format('SELECT %L::text,jsonb_build_object(''kind'',''row'',''key_sha256'',encode(sha256(convert_to(coalesce(to_jsonb(r)->>''id'',to_jsonb(r)->>''user_id'',to_jsonb(r)::text),''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''lifecycle'',%s) FROM app.%I r WHERE %s',entry.key,life,entry.key,predicate);
  RETURN QUERY EXECUTE sql_text||format(' LIMIT %s',1000001-produced) USING p_subject;
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 END LOOP;
 FOR engine IN SELECT jsonb_array_elements_text(catalog->'engine_tables') LOOP
  produced:=produced+1;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  RETURN QUERY SELECT engine,jsonb_build_object('kind','class','status','observed','erasure','blocked');
  predicate:=CASE WHEN engine='privacy_retention_plans' THEN 'r.subject_id=$1'
   WHEN engine='privacy_retention_barriers' THEN 'r.subject_id=$1'
   WHEN engine IN('privacy_retention_claims','privacy_retention_outcomes','privacy_retention_effects') THEN 'r.task_id IN(SELECT t.id FROM app.privacy_retention_tasks t JOIN app.privacy_retention_plans p ON p.id=t.plan_id WHERE p.subject_id=$1)'
   ELSE 'r.plan_id IN(SELECT id FROM app.privacy_retention_plans WHERE subject_id=$1)' END;
  RETURN QUERY EXECUTE format('SELECT %L::text,jsonb_build_object(''kind'',''row'',''key_sha256'',encode(sha256(convert_to(coalesce(to_jsonb(r)->>''id'',to_jsonb(r)->>''subject_id'',to_jsonb(r)::text),''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''lifecycle'',''{}''::jsonb) FROM app.%I r WHERE %s LIMIT %s',engine,engine,predicate,1000001-produced) USING p_subject;
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 END LOOP;
 FOR c IN SELECT value FROM jsonb_array_elements(catalog->'private_classes') LOOP
  produced:=produced+1;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  IF coalesce((c->>'blocked')::boolean,false) THEN
   -- These two request-attributed protocol tables are the capture receipt
   -- itself. Hashing a receipt into its own source root would be recursive.
   -- Keep their custody explicit and blocked; do not claim no subject copies.
   RETURN QUERY SELECT c->>'name',jsonb_build_object('kind','class',
    'status',CASE WHEN c->>'relation' IN('private.retention_inventory_manifests','private.retention_inventory_pages','private.retention_row_plans','private.retention_row_claims','private.retention_row_effects','private.retention_row_operations') THEN 'retained_control' ELSE 'unmapped' END,
    'subject_count',NULL,'erasure','blocked','present',to_regclass(c->>'relation') IS NOT NULL)||
    CASE WHEN c->>'relation' IN('private.retention_inventory_manifests','private.retention_inventory_pages','private.retention_row_plans','private.retention_row_claims','private.retention_row_effects','private.retention_row_operations') THEN
     jsonb_build_object('subject_mapping','request_subject_id','source_root_exclusion','immutable_capture_protocol_custody') ELSE '{}'::jsonb END;
   CONTINUE;
  END IF;
  IF to_regclass(c->>'relation') IS NULL THEN RAISE EXCEPTION 'retention_manifest_private_relation_missing' USING ERRCODE='42501';END IF;
  RETURN QUERY SELECT c->>'name',jsonb_build_object('kind','class','status','observed');
  sql_text:=format('SELECT %L::text,jsonb_build_object(''kind'',''row'',''key_sha256'',%s,''row_sha256'',%s,''identity_sha256'',%s,''lifecycle'',%s) FROM %s r WHERE %s',c->>'name',c->>'keyHash',c->>'rowHash',c->>'identityHash',c->>'lifecycle',c->>'relation',c->>'where');
  RETURN QUERY EXECUTE sql_text||format(' LIMIT %s',1000001-produced) USING p_subject;
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 END LOOP;
 RETURN QUERY SELECT * FROM private._retention_manifest_managed_rows_v2(p_subject,(1000001-produced)::integer);
 GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
 FOR c IN SELECT value FROM jsonb_array_elements(catalog->'copy_classes') LOOP
  produced:=produced+1;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  RETURN QUERY SELECT c#>>'{}',jsonb_build_object('kind','class','status','unverified','subject_count',NULL,'erasure','blocked','physical_object_verification','not_performed')||
   CASE WHEN c#>>'{}' IN('external:collect_sms','external:collect_ops','external:vault','external:net','external:cron','external:supabase_migrations') THEN
    jsonb_build_object('namespace_present',to_regnamespace(split_part(c#>>'{}',':',2)) IS NOT NULL,'relation_count',
     (SELECT count(*) FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname=split_part(c#>>'{}',':',2) AND t.relkind IN('r','p','v')))
   ELSE '{}'::jsonb END;
 END LOOP;
END$$;

CREATE FUNCTION private._retention_manifest_control_v2(p_request text,p_review bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE r app.deletion_requests%ROWTYPE;head jsonb;holds jsonb;review bigint;managed uuid;
BEGIN
 SELECT * INTO r FROM app.deletion_requests WHERE id=p_request;
 IF NOT FOUND THEN RAISE EXCEPTION 'retention_manifest_request_unavailable' USING ERRCODE='42501';END IF;
 SELECT to_jsonb(h),h.revision INTO head,review FROM app.privacy_review_heads h WHERE request_id=p_request;
 IF coalesce(review,0)<>p_review THEN RAISE EXCEPTION 'retention_manifest_review_changed' USING ERRCODE='42501';END IF;
 IF p_source IS NULL OR p_source!~'^[a-f0-9]{64}$' OR p_source IS DISTINCT FROM current_setting('collect.fence_source_sha256',true)
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND source_sha256=p_source AND mode='open') THEN
  RAISE EXCEPTION 'retention_manifest_source_changed' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.id),'[]') INTO holds FROM app.privacy_holds h WHERE h.user_id=r.user_id;
 SELECT auth_user_id INTO managed FROM private.auth_principal_links WHERE user_id=r.user_id;
 RETURN jsonb_build_object('request_id',r.id,'subject_id',r.user_id,'review_revision',p_review,'source_sha256',p_source,
  'request_sha256',encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),
  'review_sha256',encode(sha256(convert_to(coalesce(head,'null')::text,'UTF8')),'hex'),
  'holds_sha256',encode(sha256(convert_to(holds::text,'UTF8')),'hex'),
  'active_hold_count',(SELECT count(*) FROM app.privacy_holds WHERE user_id=r.user_id AND active=1),
  'principal_mapping_sha256',CASE WHEN managed IS NULL THEN NULL ELSE encode(sha256(convert_to(managed::text,'UTF8')),'hex') END);
END$$;

CREATE FUNCTION private._retention_manifest_commitment_v2(p_control jsonb,p_schema jsonb,p_count bigint,p_pages integer,p_classes jsonb,p_pages_sha text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$
 SELECT encode(sha256(convert_to(jsonb_build_object('contract','collect.retention.manifest.v2','control',p_control,'schema',p_schema,
 'descriptor_count',p_count,'page_count',p_pages,'class_counts',p_classes,'pages_sha256',p_pages_sha)::text,'UTF8')),'hex')
$$;

CREATE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE actor text;session text;subject text;fingerprint text;prior private.retention_inventory_manifests%ROWTYPE;control jsonb;result jsonb;
BEGIN
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);session:=api.current_session_id();
 IF p_operation IS NULL OR p_request IS NULL OR p_review IS NULL OR p_review<0 OR p_max_rows IS NULL OR p_max_rows NOT BETWEEN 1 AND 1000000 THEN RAISE EXCEPTION 'retention_manifest_input_invalid' USING ERRCODE='22023';END IF;
 control:=private._retention_manifest_control_v2(p_request,p_review,p_source);subject:=control->>'subject_id';
 IF actor=subject THEN RAISE EXCEPTION 'retention_manifest_independent_review_required' USING ERRCODE='42501';END IF;
 fingerprint:=encode(sha256(convert_to(jsonb_build_object('operation',p_operation,'request',p_request,'review',p_review,'source',p_source,'actor',actor,'session',session,'max_rows',p_max_rows)::text,'UTF8')),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('retention-manifest:'||p_operation::text,0));
 SELECT * INTO prior FROM private.retention_inventory_manifests WHERE id=p_operation;
 IF FOUND THEN
  IF prior.input_sha256<>fingerprint THEN RAISE EXCEPTION 'retention_manifest_operation_conflict' USING ERRCODE='42501';END IF;
  RETURN private.retention_inventory_page_v2(p_operation,prior.manifest_sha256,0,false);
 END IF;
 -- Both STABLE enumerators use this one statement's MVCC snapshot. No page
 -- is assembled from a later transaction; any over-budget capture rolls back.
 WITH metadata AS MATERIALIZED(SELECT private._retention_manifest_schema_v2() AS schema,private._retention_manifest_control_v2(p_request,p_review,p_source) AS control),
 observed AS MATERIALIZED(SELECT class_name,descriptor FROM private._retention_manifest_rows_v2(subject) LIMIT p_max_rows+1),
 ordered AS(SELECT class_name,descriptor,(row_number() OVER(ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text)-1)/100 AS page FROM observed),
 page_values AS(SELECT page::integer AS page_number,jsonb_agg(jsonb_build_object('class_name',class_name)||descriptor ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text) AS items FROM ordered GROUP BY page),
 written AS(INSERT INTO private.retention_inventory_pages(manifest_id,page_number,descriptors,page_sha256) SELECT p_operation,page_number,items,encode(sha256(convert_to(items::text,'UTF8')),'hex') FROM page_values RETURNING page_number,page_sha256),
 classes AS(SELECT jsonb_object_agg(class_name,jsonb_build_object('descriptor_count',n,'rows',row_count,'status',status,'unresolved_count',unresolved,'hold_count',holds) ORDER BY class_name) AS value FROM(
  SELECT class_name,count(*) AS n,count(*) FILTER(WHERE descriptor->>'kind'='row') AS row_count,
  max(descriptor->>'status') FILTER(WHERE descriptor->>'kind'='class') AS status,
  count(*) FILTER(WHERE descriptor->'lifecycle' @> '{"unresolved":true}' OR descriptor->'lifecycle' @> '{"active":true}') AS unresolved,
  count(*) FILTER(WHERE descriptor->'lifecycle' @> '{"hold":true}') AS holds FROM observed GROUP BY class_name) q),
 totals AS(SELECT (SELECT count(*) FROM observed) AS n,count(*)::integer AS pages,encode(sha256(convert_to(jsonb_agg(jsonb_build_object('page',page_number,'sha256',page_sha256) ORDER BY page_number)::text,'UTF8')),'hex') AS pages_sha FROM written),
 inserted AS(INSERT INTO private.retention_inventory_manifests(id,request_id,subject_id,actor_id,session_id,input_sha256,source_sha256,schema_sha256,schema_identity,control_identity,descriptor_count,page_count,class_counts,pages_sha256,manifest_sha256)
 SELECT p_operation,p_request,subject,actor,session,fingerprint,p_source,m.schema->>'sha256',m.schema,m.control,t.n,t.pages,c.value,t.pages_sha,
  private._retention_manifest_commitment_v2(m.control,m.schema,t.n,t.pages,c.value,t.pages_sha) FROM metadata m CROSS JOIN totals t CROSS JOIN classes c
 WHERE t.n<=p_max_rows RETURNING *) SELECT to_jsonb(inserted) INTO result FROM inserted;
 IF result IS NULL THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 IF private._retention_manifest_control_v2(p_request,p_review,p_source)<>result->'control_identity' OR private._retention_manifest_schema_v2()<>result->'schema_identity' THEN RAISE EXCEPTION 'retention_manifest_capture_changed' USING ERRCODE='42501';END IF;
 RETURN private.retention_inventory_page_v2(p_operation,result->>'manifest_sha256',0,false);
END$$;

CREATE FUNCTION private.retention_inventory_page_v2(p_manifest uuid,p_sha text,p_page integer,p_verify_current boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE actor text;m private.retention_inventory_manifests%ROWTYPE;p private.retention_inventory_pages%ROWTYPE;control jsonb;schema jsonb;pages_sha text;n bigint;page_count integer;current_sha text;currently_equal boolean:=NULL;
BEGIN
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);
 IF p_manifest IS NULL OR p_sha IS NULL OR p_sha!~'^[a-f0-9]{64}$' OR p_page IS NULL OR p_page<0 OR p_verify_current IS NULL THEN RAISE EXCEPTION 'retention_manifest_input_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO m FROM private.retention_inventory_manifests WHERE id=p_manifest;
 IF NOT FOUND OR m.manifest_sha256<>p_sha OR actor=m.subject_id OR p_page>=m.page_count THEN RAISE EXCEPTION 'retention_manifest_unavailable' USING ERRCODE='42501';END IF;
 control:=private._retention_manifest_control_v2(m.request_id,(m.control_identity->>'review_revision')::bigint,m.source_sha256);
 schema:=private._retention_manifest_schema_v2();
 IF control<>m.control_identity OR schema<>m.schema_identity THEN RAISE EXCEPTION 'retention_manifest_control_changed' USING ERRCODE='42501';END IF;
 -- Header integrity reads only small indexed hashes/counts. Resuming one page
 -- must not detoast every other descriptor page in a million-row capture.
 SELECT count(*),sum(descriptor_count),encode(sha256(convert_to(jsonb_agg(jsonb_build_object('page',page_number,'sha256',page_sha256) ORDER BY page_number)::text,'UTF8')),'hex') INTO page_count,n,pages_sha FROM private.retention_inventory_pages WHERE manifest_id=p_manifest;
 IF page_count<>m.page_count OR n<>m.descriptor_count OR pages_sha<>m.pages_sha256
  OR private._retention_manifest_commitment_v2(control,schema,n,page_count,m.class_counts,pages_sha)<>m.manifest_sha256 THEN RAISE EXCEPTION 'retention_manifest_integrity_failed' USING ERRCODE='42501';END IF;
 SELECT * INTO p FROM private.retention_inventory_pages WHERE manifest_id=p_manifest AND page_number=p_page;
 IF NOT FOUND OR encode(sha256(convert_to(p.descriptors::text,'UTF8')),'hex')<>p.page_sha256 THEN RAISE EXCEPTION 'retention_manifest_integrity_failed' USING ERRCODE='42501';END IF;
 IF p_verify_current THEN
  WITH observed AS MATERIALIZED(SELECT class_name,descriptor FROM private._retention_manifest_rows_v2(m.subject_id) LIMIT 1000001),
  ordered AS(SELECT class_name,descriptor,(row_number() OVER(ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text)-1)/100 AS page FROM observed),
  pages AS(SELECT page,jsonb_agg(jsonb_build_object('class_name',class_name)||descriptor ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text) AS items FROM ordered GROUP BY page)
  SELECT encode(sha256(convert_to(jsonb_agg(jsonb_build_object('page',page,'sha256',encode(sha256(convert_to(items::text,'UTF8')),'hex')) ORDER BY page)::text,'UTF8')),'hex') INTO current_sha FROM pages;
  currently_equal:=current_sha=m.pages_sha256;
 END IF;
 RETURN jsonb_build_object('contract_version',2,'scope','sealed_metadata_inventory','manifest_id',m.id,'manifest_sha256',m.manifest_sha256,
  'request_id',m.request_id,'subject_id',m.subject_id,'source_id',m.source_sha256,'schema_sha256',m.schema_sha256,
  'captured_at',m.created_at,'descriptor_count',m.descriptor_count,'page_count',m.page_count,'class_counts',m.class_counts,
  'active_hold_count',control->'active_hold_count','page_number',p_page,'page_sha256',p.page_sha256,'descriptors',p.descriptors,
  'next_page',CASE WHEN p_page+1<m.page_count THEN p_page+1 END,'complete_capture',true,'controls_current',true,
  'data_current',currently_equal,'currentness_checked',p_verify_current,'physical_objects_verified',false,'approval_granted',false,'erasure_completed',false);
END$$;

DO $$DECLARE routine record;BEGIN
 FOR routine IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND(p.proname LIKE '\_retention\_manifest\_%' ESCAPE '\' OR p.proname IN('retention_capture_inventory_v2','retention_inventory_page_v2')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer',routine.signature);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION private.retention_capture_inventory_v2(uuid,text,bigint,text,integer),private.retention_inventory_page_v2(uuid,text,integer,boolean) TO collect_runtime;
COMMIT;
