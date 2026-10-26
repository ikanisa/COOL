// ROOT ONLY. Source-only author has NOT executed this file or connected PostgreSQL.
// Explicit, non-skipping native fixture; ordinary *.test.mjs discovery excludes it.
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile,lstat,realpath,open,mkdir,mkdtemp,chmod,readdir} from 'node:fs/promises';
import {constants as fsConstants} from 'node:fs';
import {resolve,relative,isAbsolute,dirname,sep} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';

const SQL11_ROLE='supabase/migrations/20261023002500_collect_admin_recent_email_source_upgrade.sql';
const ROOT_SQL11_SHA256='02c93209f546880032cf38382c61e78a3de0b0073dd2cb88699319afc6f0f185';
const SOURCE3_PROVENANCE_SHA256='afacc0e47ed330439a42a244b3dbfdb68e2e77ba936ec03ce0d068a094d2e34f';
const REQUIRED_SOURCE_PINS=Object.freeze({
 "scripts/supabase/current-archive/bundle.mjs": "55c258aef1bba952eb5a9d09df7687f2dc178e6de2e183d97b7153b64f77078c",
 "scripts/supabase/current-archive/capture.mjs": "0d1f3cc180c3f4314ddb22780792bcf16f67cc7e5fdc365f14afa27c7b526f78",
 "scripts/supabase/current-archive/codec.mjs": "478e212519f1ea1e4351d5dad9ccdbb2b8fbd44a0f21f42e73b18486fd968496",
 "scripts/supabase/current-archive/operator.mjs": "a5b2c8fc804cf9ed3502daedf4cfb13a62a2e696b6228aa6213180180138dacc",
 "scripts/supabase/current-archive/restore.mjs": "b380b5542bae8fe2d79cd23e2e89c9f7e17521b953ecdbf5744682f1ad8d049c",
 "scripts/supabase/current-archive/sql.mjs": "d3995d52215b81b1284f84e1c04768c09262703f3daeb5005d5d50b5c1f4948c",
 "scripts/supabase/current-archive/transport.mjs": "e829844e3b029f793ff144ad967e31b021697a4ba49e4da88eb3a46e559386bb",
 "scripts/supabase/testing/curated-platform-fixture.mjs": "908a934cf884dfafc8f8008d0a3f235dd876ee944008a5781216426065f57f9a",
 "scripts/supabase/testing/member-realtime-fixture-plan.json": "6156561ea1b893b56afcf54d64934ca042dbb3251426ea3d27e532272bf65d6f",
 "scripts/supabase/testing/member-realtime-interface.sql": "074e380664493eea86a56d3f3042460bbb33352bc4f46483fd19d559446b0e1b",
 "scripts/supabase/testing/member-realtime-metadata.sql": "ed97cdf0838100502344d2d54563992df6170c6a64e95843c037aaec4cd703e3",
 "supabase/tests/sql/00_local_auth_fixture.sql": "b935e17f44219f018cf1a864505d1895d71903885ca6c61c039d7ab6596117ea",
 "supabase/migrations/20261020134444_collect_curated_platform_baseline.sql": "0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0",
 "supabase/migrations/20261020135932_collect_runtime_role_and_function_paths.sql": "59e4b13ddc81abeb39fb59b005c71a29f947023502727c118c9eb00b479e08a1",
 "supabase/migrations/20261020174856_collect_retention_retry_authority.sql": "d3ba38736fa46b70a0bb66520deffa56fd6f7317deb7c0144f8e06d791f8808c",
 "supabase/migrations/20261020184012_collect_admin_invitation_attempts.sql": "c6dc8aa6ac5130162c6e69904aae7221edde6dcb0c898af2cf9e10dba444b665",
 "supabase/migrations/20261020190301_collect_rls_helper_permissions.sql": "dccb79af17182164dc6afe0b8339b70bd35a80fc4a1c1fa7df1a09408310a645",
 "supabase/migrations/20261020191847_collect_privacy_email_reauthentication.sql": "d6f002a6e904226a88e666c70937a142f06aa5a7e29874c6edb564d59c5fcab4",
 "supabase/migrations/20261020193752_collect_admin_invitation_access_notice_v2.sql": "b48a381169e777160a37396539248325e40b331a61db986622514724517f8467",
 "supabase/migrations/20261020195249_collect_admin_invitation_public_id_preservation.sql": "78f8c454a9825b0d9e25622b0659245d9568e7b95f637d3e20160a945b4e0850",
 "supabase/migrations/20261022195747_collect_application_mutation_fence.sql": "714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497",
 "supabase/migrations/20261022200028_collect_private_member_realtime.sql": "ebfd0389e6ba3aa5fe1595f854b25c69b9b31a0500f202b8e0643209ab0ef6e4",
 [SQL11_ROLE]:ROOT_SQL11_SHA256
});
const PG_PACKAGE_ROOT='/Users/jeanbosco/Library/Caches/collect-supabase-implementation-20261020/node_modules/pg';
const PG_PACKAGE_JSON_SHA256='f7b678a8055c234669e8dd272dd624771e29d9f0e3a3353f15c3005ab1a5fd29';
const PG_LOCK_INTEGRITY='sha512-enxc1h0jA/aq5oSDMvqyW3q89ra6XIIDZgCX9vkMrnz5DFTw/Ny3Li2lFQ+pt3L6MCgm/5o2o8HW9hiJji+xvw==';
const FIXTURE_SOURCE='a'.repeat(64);
const BASELINE_SHA256='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const HOSTED_TENTH_SHA256='ebfd0389e6ba3aa5fe1595f854b25c69b9b31a0500f202b8e0643209ab0ef6e4';
const LOCAL_TENTH_SHA256='f27233a124b3b737f469915aa4eade6a4149272cfea2f6a15b6060389eefcf20';
const FIXTURE_BINDING_SHA256='6156561ea1b893b56afcf54d64934ca042dbb3251426ea3d27e532272bf65d6f';
const HTTP_WIRE_MAX=8*1024*1024;
const PAYLOAD_MAX=4*1024*1024-4096;
const QUERY_MAX=2*1024*1024;
const REQUEST_MAX=4*1024*1024;
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const need=(condition,code)=>{if(!condition)throw Object.assign(new Error(code),{code});};
const ownFile=fileURLToPath(import.meta.url);

// Declared current11 column expectation, independent of runtime metadata.
// Root must fill the reviewed SQL11 hash and qualify this physical layout.
const EXPECTED_COLUMNS=Object.freeze({
 "app.admin_account_audit":Object.freeze(["id","actor_id","subject_id","action","occurred_at"]),
 "app.admin_account_guards":Object.freeze(["id","passed"]),
 "app.admin_account_role_capabilities":Object.freeze(["role","permission"]),
 "app.admin_bridge_guards":Object.freeze(["id","passed"]),
 "app.admin_bridge_reconciliation_snapshots":Object.freeze(["reconciliation_id","collection_id","collection_revision","member_id","member_revision","membership_id","membership_revision","payment_identity_json","receiver_number","receiver_network","receiver_label","created_at"]),
 "app.admin_bridge_requests":Object.freeze(["admin_user_id","idempotency_key","request_id","session_id","operation","body_sha256","created_at"]),
 "app.admin_challenges":Object.freeze(["token_hash","user_id","kind","auth_version","challenge_version","delivery_status","created_at","expires_at","used_at"]),
 "app.admin_email_events":Object.freeze(["id","user_id","kind","status","provider_message_id","created_at","updated_at"]),
 "app.admin_email_otp_challenges":Object.freeze(["id","user_id","principal_user_id","origin","role","auth_version","challenge_version","account_status","code_hash","created_at","expires_at","attempts","delivery_status","used_at","consumed_session_id"]),
 "app.admin_grants":Object.freeze(["user_id","permission","granted_by","granted_at"]),
 "app.admin_operator_notes":Object.freeze(["id","entity_type","entity_id","body_ciphertext","body_sha256","created_by","session_id","created_at"]),
 "app.admin_owner_bootstrap_claims":Object.freeze(["operation_id","admin_user_id","principal_user_id","password_hash","display_name","approval_reference","created_at","created_seconds"]),
 "app.admin_principal_links":Object.freeze(["admin_user_id","user_id","approved_by","approved_at"]),
 "app.admin_rate_limits":Object.freeze(["key_hash","bucket","count","expires_at"]),
 "app.admin_role_assignments":Object.freeze(["user_id","role","granted_by","granted_at"]),
 "app.admin_sessions":Object.freeze(["token_hash","public_id","user_id","auth_version","auth_session_id","origin","issued_assurance_level","issued_mfa_at","issued_mfa_factor_id","created_at","expires_at"]),
 "app.admin_users":Object.freeze(["id","email","role","status","display_name","password_hash","auth_version","challenge_version","created_at","invited_at","accepted_at","updated_at"]),
 "app.assisted_sms_authorizations":Object.freeze(["collection_id","recipient_user_id","enabled","consent_revision","destination_revision","destination_ciphertext","destination_sha256","phone_verification_challenge_id","authorization_receipt_sha256","updated_at"]),
 "app.assisted_sms_claims":Object.freeze(["id","request_id","job_id","actor_admin_id","actor_user_id","originating_session_id","public_session_id","actor_role","actor_auth_version","actor_mfa_at","origin","worker_id","previous_fence","fence","created_seconds","expires_seconds","actor_email_proof_id","actor_email_verified_at"]),
 "app.assisted_sms_confirmations":Object.freeze(["id","request_id","job_id","claim_id","fence","actor_admin_id","actor_user_id","originating_session_id","public_session_id","body_sha256","destination_sha256","destination_revision","confirmed_seconds","expires_seconds"]),
 "app.assisted_sms_jobs":Object.freeze(["id","payment_id","entry_id","collection_id","recipient_user_id","payment_revision","amount_minor","destination_revision","destination_sha256","destination_ciphertext","consent_revision","policy_revision","policy_approval_sha256","authorization_receipt_sha256","template_key","body_ciphertext","body_sha256","state","fence","active_claim_id","created_at"]),
 "app.assisted_sms_outcomes":Object.freeze(["id","request_id","attempt_id","observer_admin_id","observer_user_id","observer_session_id","observer_public_session_id","observation","evidence_reference_sha256","observed_seconds"]),
 "app.assisted_sms_policies":Object.freeze(["collection_id","enabled","revision","template_key","approval_reference_sha256","updated_at"]),
 "app.assisted_sms_send_starts":Object.freeze(["id","request_id","job_id","confirmation_id","claim_id","fence","actor_admin_id","actor_user_id","originating_session_id","public_session_id","body_sha256","destination_sha256","destination_revision","started_seconds"]),
 "app.audit_log":Object.freeze(["id","actor_user_id","actor_session_id","action","entity_type","entity_id","request_id","details_json","created_at"]),
 "app.auth_google_flows":Object.freeze(["id","state_hash","nonce","provider_verifier","client_challenge","client_state","return_origin","registration_allowed","created_at","expires_at","status","google_subject","email","handoff_hash","consumed_operation_id"]),
 "app.auth_google_identities":Object.freeze(["subject","user_id","created_at"]),
 "app.auth_identity_rate_aliases":Object.freeze(["request_id","identity_key_id","identity_hash","requested_at","hourly_window_ends_at"]),
 "app.auth_mfa_budgets":Object.freeze(["user_id","window_start","kind","used"]),
 "app.auth_mfa_challenges":Object.freeze(["id","user_id","session_id","factor_id","created_at","expires_at","attempts","consumed_at","consumed_operation_id"]),
 "app.auth_mfa_claims":Object.freeze(["operation_id","challenge_id","factor_id","user_id","session_id","totp_counter","verified_at"]),
 "app.auth_mfa_factors":Object.freeze(["id","user_id","friendly_name","secret_ciphertext","status","created_at","enrollment_session_id","verified_at","last_totp_counter","revoked_at"]),
 "app.auth_mfa_revocations":Object.freeze(["operation_id","factor_id","user_id","session_id","revoked_at"]),
 "app.auth_otp_challenges":Object.freeze(["id","identity_hash","identity_type","identity_value","surface","registration_allowed","code_hash","created_at","expires_at","attempts","status","consumed_at","consumed_operation_id","identity_key_id"]),
 "app.auth_otp_throttles":Object.freeze(["identity_hash","last_requested_at","identity_key_id"]),
 "app.auth_otp_verifications":Object.freeze(["operation_id","challenge_id","user_id","session_id","verified_at"]),
 "app.auth_rate_buckets":Object.freeze(["bucket_key","used","window_ends_at"]),
 "app.auth_rate_claims":Object.freeze(["request_id","identity_hash","identity_bucket","ip_bucket","global_bucket","requested_at","hourly_window_ends_at","daily_window_ends_at","identity_limit","ip_limit","global_limit","cooldown_seconds","identity_key_id","identity_aliases_json"]),
 "app.auth_refresh_tokens":Object.freeze(["token_hash","session_id","created_at","expires_at","used_at","replaced_by_hash"]),
 "app.auth_sessions":Object.freeze(["id","user_id","surface","auth_at","created_at","expires_at","revoked_at","revocation_reason","assurance_level","mfa_at","mfa_factor_id"]),
 "app.collections":Object.freeze(["id","slug","creator_user_id","title","description","collection_type","country_code","currency","status","visibility_status","is_platform_sponsored","receiver_momo_number","receiver_network","receiver_display_label","share_code_hash","share_code_ciphertext","share_code_version","revision","data_json","created_at","updated_at"]),
 "app.contribution_posting_snapshots":Object.freeze(["ledger_entry_id","payment_id","member_balance_after_minor","group_balance_after_minor","posted_at"]),
 "app.deletion_requests":Object.freeze(["id","user_id","submission_id","reason","status","revision","created_at","updated_at"]),
 "app.deletion_reviews":Object.freeze(["id","request_id","actor_user_id","expected_revision","outcome","details_json","created_at"]),
 "app.ledger_entries":Object.freeze(["id","payment_id","collection_id","member_id","currency","amount_minor","kind","reverses_entry_id","evidence_id","actor_user_id","request_id","posted_at"]),
 "app.memberships":Object.freeze(["id","collection_id","user_id","role","active","joined_at","revision"]),
 "app.momo_financial_links":Object.freeze(["transaction_id","payment_id","beneficiary_member_id","linked_by","reason","historical_existing","created_at"]),
 "app.momo_gateway_bindings":Object.freeze(["id","owner_user_id","receiving_account_id","version","status","subscription_evidence","created_at","revoked_at"]),
 "app.momo_gateway_captures":Object.freeze(["raw_sms_id","credential_id","identity_sha256","service_centre_at","captured_at","inbox_received_at","subscription_id","completeness","source_mode","created_at"]),
 "app.momo_gateway_credentials":Object.freeze(["id","binding_id","pairing_id","installation_id","token_sha256","token_ciphertext","last_contact_at","last_sms_at","pending_count","oldest_pending_at","revoked_at","created_at"]),
 "app.momo_gateway_pairings":Object.freeze(["id","binding_id","code_sha256","originating_session_id","expires_at","claimed_installation_id","created_at"]),
 "app.momo_parse_attempts":Object.freeze(["id","raw_sms_id","attempt_number","model_id","schema_version","prompt_version","parser_version","profile_version","profile_json","source_body_sha256","output_json","validation_json","outcome","created_at"]),
 "app.momo_processing_guards":Object.freeze(["id","passed"]),
 "app.momo_processing_jobs":Object.freeze(["raw_sms_id","binding_id","binding_version","receiving_account_id","mode","state","attempt_count","max_attempts","available_at","lease_token","lease_until","last_error","created_at","updated_at"]),
 "app.momo_receiving_accounts":Object.freeze(["id","provider","public_code","recipient_name","receiver_hash","currency","timezone","status","profile_status","profile_version","profile_json","created_at"]),
 "app.momo_source_resolutions":Object.freeze(["id","raw_sms_id","receiving_account_id","source_body_sha256","reviewed_by","evidence_reference","reason","created_at"]),
 "app.momo_transaction_sources":Object.freeze(["transaction_id","raw_sms_id","parse_attempt_id","relation","created_at"]),
 "app.momo_transactions":Object.freeze(["id","receiving_account_id","provider","provider_transaction_id","event_kind","original_transaction_id","amount_minor","currency","currency_scale","payer_name","payer_identifier","payer_last3","transaction_at","transaction_datetime_raw","transaction_timezone","transaction_time_source","fee_minor","wallet_balance_after_minor","parse_attempt_id","mode","allocation_state","has_conflict","version","created_at","updated_at"]),
 "app.mutation_guards":Object.freeze(["id","user_id","session_id","now_seconds","collection_id","required_group_role","permission","fresh_seconds","expected_collection_revision","payment_id","expected_payment_revision","minimum_assurance","expected_mfa_at","expected_preference_revision","invite_collection_id","expected_share_hash","expected_share_version","recipient_user_id","recipient_collection_id","target_collection_id","expected_target_collection_revision"]),
 "app.native_capabilities":Object.freeze(["id","token_sha256","reservation_id","user_id","session_id","action","receiver_hash","verified_phone","payload_sha256","created_seconds","expires_seconds","verdict_sha256"]),
 "app.native_capability_claims":Object.freeze(["id","capability_id","user_id","session_id","action","payload_sha256","receiver_hash","claimed_seconds"]),
 "app.native_completions":Object.freeze(["reservation_id","capability_id","result_ciphertext","provider_response_sha256","completed_seconds","decode_duration_ms"]),
 "app.native_consents":Object.freeze(["id","user_id","session_id","receiver_hash","enabled","created_seconds","build_channel","request_id"]),
 "app.native_phases":Object.freeze(["reservation_id","phase","started_seconds"]),
 "app.native_reservations":Object.freeze(["id","user_id","session_id","nonce","action","request_hash","token_sha256","receiver_hash","verified_phone","payload_sha256","payload_ciphertext","policy_sha256","approval_id","approval_evidence_sha256","project_id","created_seconds","expires_seconds","actor_hour_limit","project_day_limit","state"]),
 "app.notification_devices":Object.freeze(["id","user_id","token_hash","owner_session_id","provider","token_ciphertext","platform","active","created_at","updated_at"]),
 "app.notification_events":Object.freeze(["id","user_id","event_type","title","body","data_json","status","created_at","read_at"]),
 "app.notification_preferences":Object.freeze(["user_id","push_enabled","payment_updates","group_updates","revision","updated_at"]),
 "app.payment_evidence":Object.freeze(["id","collection_id","owner_user_id","object_key","object_sha256","size_bytes","content_type","authenticity","external_reference","receiver_momo_number","amount_minor","currency","observed_at","created_at","retained_until","legal_hold","receiver_network","receiver_display_label"]),
 "app.payment_intents":Object.freeze(["id","collection_id","member_id","amount_minor","currency","rail","status","receiver_momo_number","receiver_network","receiver_label","originating_session_id","created_at","expires_at","request_id","request_sha256"]),
 "app.payments":Object.freeze(["id","collection_id","member_id","evidence_id","intent_id","amount_minor","currency","rail","status","payer_display_name","created_at","revision"]),
 "app.privacy_holds":Object.freeze(["id","user_id","category","reason_code","active","created_at","released_at"]),
 "app.privacy_retention_barriers":Object.freeze(["subject_id","plan_id","source_id","policy_sha256","activated_seconds"]),
 "app.privacy_retention_claims":Object.freeze(["id","operation_id","task_id","actor_id","session_id","input_sha256","expected_revision","fence","claimed_seconds","expires_seconds"]),
 "app.privacy_retention_effects":Object.freeze(["operation_id","task_id","claim_id","fence","source_sha256","object_key","object_version","started_seconds"]),
 "app.privacy_retention_guards":Object.freeze(["id","plan_id","class_name","passed"]),
 "app.privacy_retention_outcomes":Object.freeze(["operation_id","task_id","claim_id","fence","input_sha256","outcome_json","observed_seconds"]),
 "app.privacy_retention_plans":Object.freeze(["id","operation_id","request_id","subject_id","actor_id","session_id","input_sha256","policy_sha256","policy_json","policy_config_revision","source_id","schema_sha256","scope_json","scope_sha256","ledger_sha256","review_revision","state","revision","created_seconds"]),
 "app.privacy_retention_tasks":Object.freeze(["id","plan_id","class_name","action","expected_json","state","revision","fence","claim_id","post_images_json","outcome_json"]),
 "app.privacy_review_claims":Object.freeze(["claim_id","claim_request_id","request_id","actor_id","originating_session_id","expected_revision","revision","fence","lease_seconds","claimed_at","expires_at"]),
 "app.privacy_review_heads":Object.freeze(["request_id","revision","fence","state","latest_claim_id","last_outcome_id","created_at","updated_at"]),
 "app.privacy_review_outcomes":Object.freeze(["outcome_request_id","request_id","claim_id","actor_id","originating_session_id","fence","revision","outcome_code","recorded_at"]),
 "app.privacy_submissions":Object.freeze(["submission_id","request_id","user_id","originating_session_id","input_sha256","created_at"]),
 "app.reconciliations":Object.freeze(["id","payment_id","proposed_member_id","proposed_by","proposed_session_id","expected_payment_revision","status","evidence_id","approved_by","request_id","request_sha256","created_at","approved_at"]),
 "app.request_receipts":Object.freeze(["user_id","request_id","operation","session_id","body_sha256","response_json","created_at"]),
 "app.roster_commit_guards":Object.freeze(["id","import_id","revision_id","actor_user_id","session_id","now_seconds","expected_state","expected_latest_revision","permission","collection_id","expected_collection_revision"]),
 "app.roster_dispatch_phases":Object.freeze(["processing_id","phase","started_seconds"]),
 "app.roster_imports":Object.freeze(["id","user_id","session_id","request_id","collection_id","request_sha256","source_sha256","object_sha256","source_object_key","source_size","source_kind","source_receipt_json","state","latest_revision_id","source_ciphertext","created_seconds","expires_seconds","error_code"]),
 "app.roster_intents":Object.freeze(["id","import_id","user_id","session_id","kind","request_id","body_sha256","payload_ciphertext","created_seconds"]),
 "app.roster_members":Object.freeze(["id","collection_id","source_import_id","source_revision_id","member_name","momo_name","momo_number","linked_user_id","created_at"]),
 "app.roster_processing_records":Object.freeze(["id","import_id","actor_user_id","session_id","source_sha256","source_object_sha256","policy_sha256","approval_id","approval_evidence_sha256","processor_policy_json","project_id","organization_id","provider","model","processing_region_evidence_ref","retention_evidence_ref","decoder_build_sha256","decoder_lineage_json","created_seconds","expires_seconds"]),
 "app.roster_revisions":Object.freeze(["id","import_id","request_id","parent_revision_id","revision_number","rows_sha256","preview_ciphertext","human_reviewed","review_reason","created_seconds"]),
 "app.runtime_config":Object.freeze(["key","value_json","revision","updated_by","updated_at"]),
 "app.sms_receipts":Object.freeze(["id","owner_user_id","originating_session_id","client_envelope_id","body_sha256","receiver_hash","object_key","object_sha256","size_bytes","received_at_device","status","evidence_level","created_at"]),
 "app.support_requests":Object.freeze(["id","user_id","collection_id","kind","message","status","created_at"]),
 "app.upload_objects":Object.freeze(["id","user_id","collection_id","object_key","sha256","size_bytes","content_type","purpose","status","created_at","deleted_at"]),
 "app.users":Object.freeze(["id","phone","email","full_name","public_id","country_code","currency_code","momo_provider","momo_number","momo_pay_code","access_status","created_at","updated_at","member_type","revision"]),
 "private.admin_email_operations":Object.freeze(["challenge_id","purpose","mode","admin_id","principal_id","original_auth_user_id","original_session_id","cookie_hash","public_session_id","auth_version","origin","identity_value","created_at","send_claim","verification_state","verification_operation_id","verify_receipts","cleanup_state","cleanup_claim","verified_session_id","verified_amr_at"]),
 "private.admin_invitation_attempts":Object.freeze(["request_id","attempt_sequence","actor_id","actor_principal_id","idempotency_key","subject_id","principal_id","body_sha256","kind","replayed_request_id","original_session_id","subject_identity_sha256","state","claim_nonce","dispatch_session_id","created_at","claimed_at","finished_at","safe_error_code","contract_version","message_kind","template_version","managed_auth_user_id","notice_origin","source_request_id"]),
 "private.admin_sensitive_email_proofs":Object.freeze(["id","challenge_id","purpose","admin_id","principal_id","auth_user_id","original_session_id","cookie_hash","public_session_id","auth_version","origin","identity_value","verified_session_id","verified_at","recorded_at"]),
 "private.auth_principal_links":Object.freeze(["auth_user_id","user_id","linked_at","proof_reference"]),
 "private.bff_sessions":Object.freeze(["token_hash","auth_user_id","auth_session_id","token_ciphertext","version","refresh_lease","refresh_lease_until"]),
 "private.collect_fence_admissions":Object.freeze(["admission_id","epoch","source_sha256","kind","state","reason","external_dispatches","uncertain_dispatches","created_at","closed_at"]),
 "private.collect_fence_control":Object.freeze(["singleton","project_ref","baseline_manifest_sha256","source_sha256","epoch","mode","operation_id","changed_at"]),
 "private.collect_fence_operations":Object.freeze(["operation_id","action","epoch","source_sha256","recorded_at"]),
 "private.collect_fence_scheduler_lifecycle":Object.freeze(["dispatch_id","native_epoch","evidence_sha256","review_operation_id","recorded_at"]),
 "private.collect_fence_source_upgrades":Object.freeze(["operation_id","prior_fence_operation_id","project_ref","baseline_manifest_sha256","old_source_sha256","old_epoch","new_source_sha256","new_epoch","prior_control_snapshot","plan_sha256","qualification_sha256","deployment_readback_sha256","recorded_transaction","recorded_by","recorded_at"]),
 "private.google_flow_context":Object.freeze(["flow_id","surface","request_origin","created_at"]),
 "private.managed_mfa_proofs":Object.freeze(["session_id","user_id","factor_id","verified_at_epoch"]),
 "private.managed_phone_verifications":Object.freeze(["challenge_id","auth_user_id","session_id","user_id","phone","verified_at"]),
 "private.member_realtime_control":Object.freeze(["singleton","enabled","source_sha256","policy_sha256","activation_evidence_sha256","last_audit_id","attempted_total","failed_total","window_started_at","window_attempted","changed_at"]),
 "private.storage_delete_intents":Object.freeze(["operation_id","object_key","fingerprint","expected_sha256","scope","state","last_outcome","absence_proof","created_at","committed_at"]),
 "private.storage_namespace":Object.freeze(["singleton","origin","bucket","created_at"]),
 "private.storage_objects":Object.freeze(["object_key","operation_id","fingerprint","sha256","size","scope","http_metadata","custom_metadata","etag","committed_at"]),
 "private.storage_payload_reservations":Object.freeze(["object_key","source_fingerprint","scope","aad","key_id","plaintext_sha256","sealed_body","created_at","cleared_at"]),
 "private.storage_put_intents":Object.freeze(["operation_id","object_key","fingerprint","sha256","size","scope","http_metadata","custom_metadata","state","attempts","active_attempt","upload_unresolved","delete_tombstone","last_outcome","created_at","updated_at"]),
 "private.storage_upload_attempts":Object.freeze(["id","operation_id","outcome","started_at","completed_at"]),
 "private.supabase_otp_challenges":Object.freeze(["id","identity_hash","identity_type","identity_value","surface","registration_allowed","created_at","expires_at","attempts","consumed_at","delivery_status","privacy_mode","privacy_context_hash","privacy_expected_auth_user_id","privacy_expected_user_id","privacy_initiating_session_id","privacy_initiating_user_revision","privacy_send_claim","privacy_verification_state","privacy_verification_operation_id","privacy_verify_receipts","privacy_verified_auth_user_id","privacy_verified_user_id","privacy_verified_session_id","privacy_verified_amr_at","privacy_cancelled_at","privacy_cleanup_state","privacy_cleanup_claim","privacy_cleanup_session_id"])
});

function physicalAbsolute(value,code){need(typeof value==='string'&&isAbsolute(value)&&resolve(value)===value,code);return value;}
async function privateParent(path){
 physicalAbsolute(path,'PRIVATE_AUDIT_PARENT_REQUIRED');
 const st=await lstat(path);
 need(st.isDirectory()&&!st.isSymbolicLink()&&st.uid===process.getuid()&&(st.mode&0o777)===0o700&&await realpath(path)===path,'PRIVATE_AUDIT_PARENT_REQUIRED');
}
async function stableFile(path,maximum=16*1024*1024){
 need(await realpath(path)===path,'PHYSICAL_SOURCE_FILE_REQUIRED');
 const fd=await open(path,fsConstants.O_RDONLY|fsConstants.O_NOFOLLOW);
 try{
  const before=await fd.stat();
  need(before.isFile()&&before.nlink===1&&before.uid===process.getuid()&&before.size<=maximum,'SOURCE_FILE_BOUND_OR_IDENTITY');
  const bytes=await fd.readFile(),after=await fd.stat();
  need(bytes.length===before.size&&before.ino===after.ino&&before.size===after.size&&before.mtimeMs===after.mtimeMs&&after.nlink===1,'SOURCE_CHANGED_DURING_READ');
  return bytes;
 }finally{await fd.close();}
}
async function saveNew(path,value){
 const fd=await open(path,fsConstants.O_WRONLY|fsConstants.O_CREAT|fsConstants.O_EXCL|fsConstants.O_NOFOLLOW,0o600);
 try{await fd.writeFile(JSON.stringify(value,null,2)+'\n');await fd.sync();}finally{await fd.close();}
 const dir=await open(dirname(path),fsConstants.O_RDONLY);try{await dir.sync();}finally{await dir.close();}
}
async function verifySourceTree(root,expected){
 physicalAbsolute(root,'EXPLICIT_PHYSICAL_SOURCE_ROOT_REQUIRED');
 need(await realpath(root)===root,'EXPLICIT_PHYSICAL_SOURCE_ROOT_REQUIRED');
 need(typeof expected==='string'&&/^[a-f0-9]{64}$/.test(expected),'EXPLICIT_REVIEWED_INTEGRATION_SHA_REQUIRED');
 const bytes=await stableFile(resolve(root,'INTEGRATION.json'),2*1024*1024);
 need(sha(bytes)===expected,'INTEGRATION_MANIFEST_CHANGED');
 const manifest=JSON.parse(bytes.toString('utf8'));
 need(manifest.format==='collect.private.member-realtime.integration.v1'&&manifest.files&&typeof manifest.files==='object'&&!Array.isArray(manifest.files)&&Number.isSafeInteger(manifest.source_roles)&&manifest.source_roles===Object.keys(manifest.files).length&&manifest.source_roles>=Object.keys(REQUIRED_SOURCE_PINS).length&&manifest.source_roles<=4096&&manifest.migrations===11,'EXACT_PRIVATE_INTEGRATION_REQUIRED');
 need(manifest.hosted_SQL10_sha256===HOSTED_TENTH_SHA256&&manifest.Root_static_binding_sha256===FIXTURE_BINDING_SHA256,'INTEGRATION_SCOPE_CHANGED');
 for(const [role,pin]of Object.entries(REQUIRED_SOURCE_PINS))need(manifest.files[role]?.sha256===pin,'REQUIRED_RUNTIME_SQL10_OR_HELPER_PIN_CHANGED');
 for(const [role,pin]of Object.entries(manifest.files)){
  need(typeof role==='string'&&!isAbsolute(role)&&role.split('/').every(part=>part&&part!=='.'&&part!=='..')&&/^[a-f0-9]{64}$/.test(pin.sha256)&&Number.isSafeInteger(pin.bytes),'SOURCE_ROLE_INVALID');
  const path=resolve(root,role),from=relative(root,path);
  need(from!==''&&from!=='..'&&!from.startsWith('..'+sep)&&!isAbsolute(from),'SOURCE_ROLE_OUTSIDE_ROOT');
  const actual=await stableFile(path);
  need(actual.length===pin.bytes&&sha(actual)===pin.sha256,'REVIEWED_SOURCE_ROLE_CHANGED');
 }
 const binding=await stableFile(resolve(root,'scripts/supabase/testing/member-realtime-fixture-plan.json'),65536);
 need(sha(binding)===FIXTURE_BINDING_SHA256,'FIXTURE_BINDING_CHANGED');
 return {manifest_sha256:expected,roles:manifest.source_roles,manifest};
}
function cleanEnvironment(){
 for(const [name,value]of Object.entries(process.env))if(value){
  need(!/^(?:https?|all|no)_proxy$/i.test(name)&&!['NODE_OPTIONS','NODE_PATH','NODE_USE_ENV_PROXY','GLOBAL_AGENT_HTTP_PROXY','COLLECT_PG_MODULE'].includes(name)&&!/^PG/i.test(name),'CLEAN_EXPLICIT_FIXTURE_ENVIRONMENT_REQUIRED');
 }
 need(!process.env.NODE_TLS_REJECT_UNAUTHORIZED||process.env.NODE_TLS_REJECT_UNAUTHORIZED==='1','TLS_OVERRIDE_REFUSED');
 need(process.versions.node==='24.19.0','PINNED_NODE24_REQUIRED');
}
function explicitLocalAdmin(raw){
 // Reject alternate IPv4 spellings, implicit ports, extra URL parameters and usernames.
 need(typeof raw==='string'&&/^(?:postgres|postgresql):\/\/collect_test:[^@\/?#\s]+@127\.0\.0\.1:[1-9][0-9]{0,4}\/postgres$/.test(raw),'EXPLICIT_LOOPBACK_COLLECT_TEST_ADMIN_REQUIRED');
 let parsed;try{parsed=new URL(raw);}catch{need(false,'EXPLICIT_LOOPBACK_COLLECT_TEST_ADMIN_REQUIRED');}
 need(parsed.hostname==='127.0.0.1'&&parsed.username==='collect_test'&&parsed.password&&parsed.port&&Number(parsed.port)<=65535&&parsed.pathname==='/postgres'&&!parsed.search&&!parsed.hash,'EXPLICIT_LOOPBACK_COLLECT_TEST_ADMIN_REQUIRED');
 return parsed;
}
async function verifiedPg(root){
 need(process.env.COLLECT_ARCHIVE_CURATED_PG_PACKAGE_ROOT===PG_PACKAGE_ROOT,'ROOT_SUPPLIED_QUALIFIED_PG_PACKAGE_REQUIRED');
 need(await realpath(PG_PACKAGE_ROOT)===PG_PACKAGE_ROOT,'PHYSICAL_PG_PACKAGE_REQUIRED');
 const bytes=await stableFile(resolve(PG_PACKAGE_ROOT,'package.json'),16384),pkg=JSON.parse(bytes.toString('utf8'));
 need(sha(bytes)===PG_PACKAGE_JSON_SHA256&&pkg.name==='pg'&&pkg.version==='8.16.3','PINNED_PG8163_PACKAGE_REQUIRED');
 const declaration=JSON.parse((await stableFile(resolve(root,'scripts/supabase/package.json'),16384)).toString('utf8'));
 const lock=JSON.parse((await stableFile(resolve(root,'scripts/supabase/package-lock.json'),1024*1024)).toString('utf8'));
 need(declaration.dependencies?.pg==='8.16.3'&&lock.packages?.['node_modules/pg']?.version==='8.16.3'&&lock.packages['node_modules/pg'].integrity===PG_LOCK_INTEGRITY,'PINNED_PG8163_LOCK_REQUIRED');
 return {package_json_sha256:sha(bytes),version:pkg.version,lock_integrity:PG_LOCK_INTEGRITY};
}
const safeCode=error=>typeof error?.code==='string'&&/^[A-Z][A-Z0-9_]{0,79}$/.test(error.code)?error.code:'CURATED_ARCHIVE_FIXTURE_UNCONFIRMED';

// All execution stays inside one bounded explicit test. Missing inputs fail, never skip.
test('Root exact-current11 curated 118-table native SQL capture and encrypted inert restore; local doubles only',{timeout:300000},async()=>{
 let attempt,sourceName,inertName,sourceCreated=false,sourceCreationState='not_attempted',phase='explicit_input',inputRoot,inputPin,fixtureSourcePin,sourceBeforeVerified=false;
 const clients=[],nativeBatches=[];
 try{
  cleanEnvironment();
  const adminRaw=process.env.COLLECT_ARCHIVE_TEST_ADMIN_URL;delete process.env.COLLECT_ARCHIVE_TEST_ADMIN_URL;
  const adminUri=explicitLocalAdmin(adminRaw);
  const sourceRoot=physicalAbsolute(process.env.COLLECT_ARCHIVE_CURATED_SOURCE_ROOT,'EXPLICIT_PHYSICAL_SOURCE_ROOT_REQUIRED');
  const integrationPin=process.env.COLLECT_ARCHIVE_CURATED_INTEGRATION_SHA256;inputRoot=sourceRoot;inputPin=integrationPin;
  const outputParent=physicalAbsolute(process.env.COLLECT_ARCHIVE_FIXTURE_OUTPUT_PARENT,'PRIVATE_AUDIT_PARENT_REQUIRED');
  await privateParent(outputParent);
  const outputRelative=relative(sourceRoot,outputParent);need(outputRelative==='..'||outputRelative.startsWith('..'+sep)||isAbsolute(outputRelative),'AUDIT_OUTPUT_MUST_BE_OUTSIDE_SOURCE');
  attempt=await mkdtemp(resolve(outputParent,'root-curated-exact-current11-'));await chmod(attempt,0o700);
  sourceName='collect_archive_source_'+randomUUID().replaceAll('-','')+'_test';
  const ownPin=sha(await stableFile(ownFile,256*1024));fixtureSourcePin=ownPin;
  await saveNew(resolve(attempt,'INTENT.json'),{format:'collect.archive.curated-native-fixture.intent.v1',source_database:sourceName,create_template0_only:true,source_root:sourceRoot,integration_sha256:integrationPin,fixture_source_sha256:ownPin,expected_migrations:11,expected_tables:118,expected_app_tables:97,expected_private_tables:21,hosted_sql10_sha256:HOSTED_TENTH_SHA256,applied_local_sql10_sha256:LOCAL_TENTH_SHA256,sql11_sha256:ROOT_SQL11_SHA256,synthetic_data_only:true,management_http201_envelope_simulated:true,no_database_drop_reset_or_cleanup:true,automatic_retry:false,hosted_acceptance:false});
  phase='verify_current_source';
  const before=await verifySourceTree(sourceRoot,integrationPin),pgPin=await verifiedPg(sourceRoot);sourceBeforeVerified=true;
  const moduleAt=role=>import(pathToFileURL(resolve(sourceRoot,role)).href);
  const [codec,capture,bundle,restore,sql,fixture]=await Promise.all([
   moduleAt('scripts/supabase/current-archive/codec.mjs'),moduleAt('scripts/supabase/current-archive/capture.mjs'),
   moduleAt('scripts/supabase/current-archive/bundle.mjs'),moduleAt('scripts/supabase/current-archive/restore.mjs'),
   moduleAt('scripts/supabase/current-archive/sql.mjs'),moduleAt('scripts/supabase/testing/curated-platform-fixture.mjs'),
  ]);
  const {identifier,canonical,outputExpression,sealTable}=codec;
  const {compilePlanningRequest,decodeManagementResult,preparePlanCandidate,compileCaptureRequest,assembleManagementSnapshot,sealManagementResponse}=capture;
  const {readEncryptedBundle,privateDirectory}=bundle;
  const {restoreInertArchive}=restore;
  const reviewed=await fixture.loadReviewedPlatformFixture(sourceRoot);
  need(reviewed.names.length===11&&reviewed.successor?.sha256===ROOT_SQL11_SHA256&&reviewed.successor?.name===SQL11_ROLE.slice('supabase/migrations/'.length)&&reviewed.binding.hosted_sql_sha256===HOSTED_TENTH_SHA256&&reviewed.binding.synthetic_sql_sha256===LOCAL_TENTH_SHA256,'EXACT_CURRENT11_HELPER_INPUT_REQUIRED');
  const applied=reviewed.rawMigrations.map((item,index)=>({filename:item.name,source_sha256:item.sha256,sql:index===9?fixture.renderSyntheticSql(item.sql,reviewed.binding):item.sql}));
  for(const [index,item]of applied.entries()){
   need(sha(item.sql)===(index===9?LOCAL_TENTH_SHA256:item.source_sha256),'APPLIED_MIGRATION_SOURCE_CHANGED');
   need(item.filename===reviewed.names[index],'EXACT_CURRENT11_SOURCE_IDENTITY_REQUIRED');
  }
  const sourceMigrations=applied.map(item=>{const match=/^(\d{14})_([a-z0-9_]+)\.sql$/.exec(item.filename);need(match,'EXACT_MIGRATION_FILENAME_REQUIRED');return{version:match[1],name:match[2],sha256:sha(item.sql)};});
  need(new Set(sourceMigrations.map(m=>m.version)).size===11,'UNIQUE_ELEVEN_MIGRATIONS_REQUIRED');
  await saveNew(resolve(attempt,'SOURCE_INPUTS.json'),{integration_sha256:before.manifest_sha256,source_roles:before.roles,source3_provenance_sha256:SOURCE3_PROVENANCE_SHA256,fixture_source_sha256:ownPin,pg:pgPin,files:before.manifest.files});
  const require=createRequire(resolve(PG_PACKAGE_ROOT,'package.json')),{Client}=require(PG_PACKAGE_ROOT);
  const makeClient=connectionString=>{
   // pg receives only this explicit URL; PG*, preload and module overrides were refused.
   const client=new Client({connectionString,ssl:false,connectionTimeoutMillis:5000,query_timeout:35000,statement_timeout:30000,options:'-c statement_timeout=30000 -c lock_timeout=5000'});
   let idleFailure=false,ended=false;
   client.on('error',()=>{idleFailure=true;});
   const wrapped={
    async connect(){need(!idleFailure,'LOCAL_PG_IDLE_ERROR');await client.connect();need(!idleFailure,'LOCAL_PG_IDLE_ERROR');},
    async query(query,values){need(!idleFailure,'LOCAL_PG_IDLE_ERROR');const result=await client.query(query,values);need(!idleFailure,'LOCAL_PG_IDLE_ERROR');return result;},
    async end(){if(!ended){ended=true;await client.end();}need(!idleFailure,'LOCAL_PG_IDLE_ERROR');},
   };
   clients.push(wrapped);return wrapped;
  };
  phase='create_new_source_database';
  const admin=makeClient(adminUri.href);await admin.connect();
  try{
   const identity=(await admin.query("SELECT current_database()::text AS database,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,current_setting('server_version_num') AS version,current_user::text AS username,session_user::text AS session_username,rolsuper,rolbypassrls FROM pg_catalog.pg_roles WHERE rolname=current_user")).rows[0];
   need(identity?.database==='postgres'&&identity.address==='127.0.0.1'&&/^17[0-9]{4}$/.test(identity.version)&&identity.username==='collect_test'&&identity.session_username==='collect_test'&&identity.rolsuper&&identity.rolbypassrls,'EXACT_LOCAL_ADMIN_IDENTITY_REQUIRED');
   sourceCreationState='requested_unconfirmed';await admin.query('CREATE DATABASE '+identifier(sourceName)+" TEMPLATE template0 ENCODING 'UTF8'");sourceCreated=true;sourceCreationState='confirmed_created';
  }finally{await admin.end();}
  const sourceUri=new URL(adminUri);sourceUri.pathname='/'+sourceName;
  const source=makeClient(sourceUri.href);await source.connect();
  phase='apply_exact_current11_with_reviewed_local_doubles';
  const occupied=(await source.query("SELECT nspname FROM pg_catalog.pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname NOT IN('information_schema','public') UNION ALL SELECT n.nspname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' LIMIT 1")).rows;
  need(occupied.length===0,'PRISTINE_NEW_SOURCE_REQUIRED');
  const setupCommands=[];
  await reviewed.apply(async text=>{setupCommands.push({sql_sha256:sha(text),sql_bytes:Buffer.byteLength(text)});return source.query(text);},{includeAuth:true});
  // The real helper checks identity, seven restricted postgres flags, rejects
  // actual hosted SQL10 locally, rolls it back and applies only reviewed local SQL10.
  for(const item of applied)need(setupCommands.filter(command=>command.sql_sha256===sha(item.sql)).length===1,'EXACTLY_ONCE_APPLIED_MIGRATION_REQUIRED');
  need(setupCommands.filter(command=>command.sql_sha256===HOSTED_TENTH_SHA256).length===1,'ACTUAL_HOSTED_TENTH_REFUSAL_REQUIRED');
  need(setupCommands.filter(command=>command.sql_sha256===fixture.AUTH_FIXTURE_SHA256).length===1,'IMMUTABLE_AUTH_FIXTURE_ONCE_REQUIRED');
  await saveNew(resolve(attempt,'SETUP_COMMANDS.json'),{commands:setupCommands,hosted_sql10_genuinely_refused_on_local_profile:true,managed_auth_realtime_are_local_doubles:true});
  phase='synthetic_local_migration_history';
  await source.query('CREATE SCHEMA supabase_migrations; CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text NOT NULL,statements text[] NOT NULL)');
  const migrationProvenance=[];
  for(const [index,migration]of sourceMigrations.entries()){
   await source.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3::text[])',[migration.version,migration.name,[applied[index].sql]]);
   migrationProvenance.push({version:migration.version,name:migration.name,source_path:'supabase/migrations/'+applied[index].filename,original_source_file_sha256:applied[index].source_sha256,actually_applied_sql_sha256:migration.sha256,history_statements_are_actual_applied_sql:true,local_metadata_literal_substitution:index===9,hosted_bytes_applied:index!==9,synthetic_local_history_only:true});
  }
  await saveNew(resolve(attempt,'HISTORY_PROVENANCE.private.json'),{migrations:migrationProvenance,hosted_tenth_is_separate_provenance:true,production_history_writes:false});
  phase='prove_owner_path_and_initialize_once';
  await source.query(fixture.fixtureIdentitySql);await source.query(fixture.restrictedPostgresSql);
  const owner=(await source.query("SELECT private._collect_fence_operator() AS operator,current_setting('role',true) AS role,current_user::text AS username,session_user::text AS session_username,(SELECT pg_catalog.pg_get_userbyid(c.relowner) FROM pg_catalog.pg_class c WHERE c.oid='private.collect_fence_control'::regclass) AS control_owner,(SELECT pg_catalog.pg_get_userbyid(c.relowner) FROM pg_catalog.pg_class c WHERE c.oid='app.users'::regclass) AS users_owner")).rows[0];
  need(owner.operator===true&&owner.role==='none'&&owner.username==='collect_test'&&owner.session_username==='collect_test'&&owner.control_owner==='collect_test'&&owner.users_owner==='collect_test','LEGITIMATE_LOCAL_OWNER_PATH_REQUIRED');
  const initialization=randomUUID();
  await source.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try{const initialized=(await source.query('SELECT private.collect_fence_initialize($1,$2,$3) AS value',[initialization,FIXTURE_SOURCE,BASELINE_SHA256])).rows[0].value;need(initialized.mode==='open'&&initialized.epoch===1&&initialized.operationId===initialization&&initialized.sourceSha256===FIXTURE_SOURCE,'GENUINE_FENCE_INITIALIZATION_REQUIRED');await source.query('COMMIT');}catch(error){await source.query('ROLLBACK');throw error;}
  // No admission/control/operation rows are forged or erased. This is the actual
  // declared owner path enforced by _collect_fence_statement/assert_write.
  const userId='archive-synthetic-user-'+randomUUID(),requestId='archive-synthetic-request-'+randomUUID();
  const userName='Synthetic archive fixture\né / unknown',revision='9007199254740993';
  const receiptJson=' {"state":"unknown", "may_send":false, "native":9007199254740993, "duplicate":1, "duplicate":2} ';
  const stamp='2026-10-22T00:00:00.123456Z';
  phase='bounded_owner_seed';
  await source.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try{
   const write=(await source.query('SELECT private.collect_fence_assert_write(NULL,NULL,NULL) AS value')).rows[0].value;
   need(write.mode==='open'&&write.epoch===1,'GENUINE_OWNER_WRITE_GUARD_REQUIRED');
   await source.query('INSERT INTO app.users(id,full_name,public_id,created_at,updated_at,revision) VALUES($1,$2,$3,$4,$4,$5::bigint)',[userId,userName,'archive-synthetic-public-'+randomUUID(),stamp,revision]);
   await source.query('INSERT INTO app.request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at) VALUES($1,$2,$3,$4,$5,$6,$7)',[userId,requestId,'synthetic_archive_unknown','synthetic-no-auth-session',sha('synthetic-unknown-receipt-only'),receiptJson,stamp]);
   await source.query('COMMIT');
  }catch(error){await source.query('ROLLBACK');throw error;}
  const seeded=(await source.query('SELECT revision::text AS revision,full_name::text AS name,phone,email FROM app.users WHERE id=$1',[userId])).rows[0];
  need(seeded.revision===revision&&seeded.name===userName&&seeded.phone===null&&seeded.email===null,'SYNTHETIC_NATIVE_BIGINT_TEXT_SEED_REQUIRED');
  need((await source.query('SELECT response_json::text AS value FROM app.request_receipts WHERE user_id=$1 AND request_id=$2',[userId,requestId])).rows[0].value===receiptJson,'TEXT_JSON_BYTES_SEED_REQUIRED');
  const guardRows=(await source.query("SELECT n.nspname||'.'||c.relname AS identity,t.tgenabled::text AS enabled,t.tgtype::text AS type FROM pg_catalog.pg_trigger t JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE t.tgname='collect_fence_statement_v1' ORDER BY n.nspname::text COLLATE pg_catalog.\"C\",c.relname::text COLLATE pg_catalog.\"C\"")).rows;
  const expectedGuards=Object.keys(EXPECTED_COLUMNS).filter(name=>!['private.collect_fence_control','private.collect_fence_admissions','private.collect_fence_operations','private.collect_fence_scheduler_lifecycle','private.collect_fence_source_upgrades'].includes(name));
  assert.deepEqual(guardRows.map(row=>row.identity),expectedGuards);need(guardRows.length===113&&guardRows.every(row=>row.enabled==='A'&&row.type==='62'),'EXACT_113_ALWAYS_GUARDS_REQUIRED');
  const control=(await source.query('SELECT enabled FROM private.member_realtime_control WHERE singleton')).rows;
  need(control.length===1&&control[0].enabled===false,'SQL10_MUST_REMAIN_INACTIVE');
  const fenceCounts=(await source.query('SELECT (SELECT count(*)::text FROM private.collect_fence_control) AS controls,(SELECT count(*)::text FROM private.collect_fence_operations) AS operations,(SELECT count(*)::text FROM private.collect_fence_admissions) AS admissions,(SELECT count(*)::text FROM private.collect_fence_scheduler_lifecycle) AS lifecycle')).rows[0];
  assert.deepEqual(fenceCounts,{controls:'1',operations:'1',admissions:'0',lifecycle:'0'});
  const noEffectTables=['ledger_entries','payments','payment_evidence','payment_intents','reconciliations','momo_transactions','momo_financial_links','assisted_sms_jobs','notification_events'];
  for(const name of noEffectTables)need((await source.query('SELECT count(*)::text AS n FROM app.'+identifier(name))).rows[0].n==='0','FINANCIAL_OR_SEND_EFFECT_FORBIDDEN');
  await saveNew(resolve(attempt,'OWNER_SEED_PROOF.json'),{owner,initialization_operation_id:initialization,fixture_source_sha256:FIXTURE_SOURCE,baseline_sha256:BASELINE_SHA256,one_real_initialization:true,legitimate_owner_guard_path:true,forged_open_or_fence_bypass:false,fence_counts:fenceCounts,guard_identities:guardRows,sql10_enabled:false,seeded_tables:['app.users','app.request_receipts'],seeded_rows:2,financial_and_send_rows_zero:noEffectTables,real_email_phone_provider_business_data:false});
  phase='exact_curated_schema_shape';
  const shape=(await source.query("SELECT n.nspname||'.'||c.relname AS identity,a.attname::text AS column,a.attnum::text AS position,a.atttypid::text AS type_oid,a.atttypmod::text AS typmod,a.attnotnull AS not_null FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped WHERE n.nspname IN('app','private') AND c.relkind IN('r','p') ORDER BY n.nspname::text COLLATE pg_catalog.\"C\",c.relname::text COLLATE pg_catalog.\"C\",a.attnum")).rows;
  const expectedNames=Object.keys(EXPECTED_COLUMNS),observedNames=[...new Set(shape.map(row=>row.identity))];
  assert.deepEqual(observedNames,expectedNames);need(observedNames.length===118&&observedNames.filter(name=>name.startsWith('app.')).length===97&&observedNames.filter(name=>name.startsWith('private.')).length===21&&shape.length===1143,'EXACT_118_RELATION_SCOPE_REQUIRED');
  for(const name of expectedNames)assert.deepEqual(shape.filter(row=>row.identity===name).map(row=>row.column),EXPECTED_COLUMNS[name]);
  await saveNew(resolve(attempt,'SCHEMA_SHAPE.private.json'),{tables:118,app_tables:97,private_tables:21,columns:shape,shape_sha256:sha(canonical(shape))});
  async function localManagementShape(compiled){
   need(compiled.method==='LOCAL_NATIVE_FIXTURE'&&compiled.url===null&&compiled.fixture_database===sourceName&&compiled.body.read_only===true&&compiled.body.query.endsWith('\nROLLBACK;'),'LOCAL_NATIVE_COMPILED_REQUEST_REQUIRED');
   need(Buffer.byteLength(compiled.body.query)<=QUERY_MAX&&Buffer.byteLength(JSON.stringify(compiled.body))<=REQUEST_MAX,'COMPILED_REQUEST_BOUND');
   const result=await source.query(compiled.body.query);
   need(Array.isArray(result)&&result.at(-1).command==='ROLLBACK','NATIVE_TRAILING_ROLLBACK_REQUIRED');
   const selected=result.filter(item=>item.fields?.length);need(selected.length===1,'EXACT_NATIVE_SELECT_REQUIRED');
   const body=Buffer.from(JSON.stringify(selected[0].rows));need(body.length<=HTTP_WIRE_MAX,'LOCAL_WIRE_RESPONSE_BOUND');
   need(selected[0].rows.length===1&&typeof selected[0].rows[0].payload==='string'&&Buffer.byteLength(selected[0].rows[0].payload)<=PAYLOAD_MAX,'LOCAL_SERVER_PAYLOAD_BOUND');
   nativeBatches.push({kind:compiled.kind,request_sql_sha256:compiled.query_sha256,response_sha256:sha(body),response_bytes:body.length,payload_bytes:Buffer.byteLength(selected[0].rows[0].payload),native_final_command:'ROLLBACK',management_http201_envelope_simulated:true});
   return {status:201,body};
  }
  phase='real_native_planning';
  const planning=compilePlanningRequest({fixtureDatabase:sourceName,expectedMigrationCount:11});
  const metadataResponse=await localManagementShape(planning);
  let metadata;try{metadata=decodeManagementResult(metadataResponse,planning);}finally{metadataResponse.body.fill(0);}
  need(metadata.postgres.database===sourceName&&metadata.postgres.server_address==='127.0.0.1'&&metadata.relations.length===118&&metadata.migrations.length===11,'REAL_CURATED_METADATA_REQUIRED');
  assert.deepEqual(metadata.relations.map(row=>row.schema+'.'+row.name),expectedNames);
  for(const [index,record]of metadata.migrations.entries()){
   assert.deepEqual(JSON.parse(record.observed_record),{version:sourceMigrations[index].version,name:sourceMigrations[index].name,statements:[applied[index].sql]});
   need(sha(record.observed_record)===record.observed_record_sha256,'EXACT_OBSERVED_RECORD_SHA_REQUIRED');
  }
  const plan=preparePlanCandidate(metadata,{runtimeSourceSha256:integrationPin,sourceMigrations,fixtureDatabase:sourceName,expectedMigrationCount:11});
  await saveNew(resolve(attempt,'METADATA.private.json'),metadata);
  await saveNew(resolve(attempt,'LOCAL_CANDIDATE_PLAN.json'),plan);
  phase='real_native_exact_current11_capture';
  const compiled=compileCaptureRequest(plan),response=await localManagementShape(compiled);
  const snapshot=assembleManagementSnapshot(response,plan,compiled);
  need(snapshot.fixture===true&&snapshot.tables.length===118&&snapshot.management_provenance.response_shape_simulated===true&&snapshot.management_provenance.native_rollback_command_complete_observed===false,'LOCAL_ONLY_CAPTURE_PROVENANCE_REQUIRED');
  assert.deepEqual(snapshot.tables.map(table=>table.schema+'.'+table.name),expectedNames);
  for(const table of snapshot.tables){const name=table.schema+'.'+table.name;assert.deepEqual(table.columns.map(column=>column.name),EXPECTED_COLUMNS[name]);assert.deepEqual(table.columns.map(column=>({name:column.name,type_oid:column.type_oid,typmod:column.typmod,not_null:column.not_null})),shape.filter(row=>row.identity===name).map(row=>({name:row.column,type_oid:row.type_oid,typmod:row.typmod,not_null:row.not_null})));}
  // Independently read every native source cell through PostgreSQL text outputs.
  // No native numeric cell is decoded through JavaScript Number.
  phase='independent_native_all_table_comparison';
  await source.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
  try{
   for(const setting of sql.SETTINGS)await source.query(setting);
   for(const table of snapshot.tables){
    const native=await source.query({text:'SELECT '+table.columns.map(column=>outputExpression(column)).join(',')+' FROM ONLY '+identifier(table.schema)+'.'+identifier(table.name)+' t LIMIT $1',values:[table.row_count+1],rowMode:'array'});
    need(native.fields.length===table.columns.length&&native.fields.every(field=>field.dataTypeID===25),'NATIVE_TEXT_OUTPUTS_REQUIRED');
    const independentlySealed=sealTable({schema:table.schema,name:table.name,kind:table.kind,columns:table.columns,rows:native.rows},snapshot.limits);
    need(canonical(independentlySealed)===canonical(table),'ALL_SOURCE_NATIVE_CELLS_MUST_MATCH');
   }
   await source.query('ROLLBACK');
  }catch(error){await source.query('ROLLBACK');throw error;}
  const userTable=snapshot.tables.find(table=>table.schema==='app'&&table.name==='users'),receiptTable=snapshot.tables.find(table=>table.schema==='app'&&table.name==='request_receipts');
  need(userTable.rows.length===1&&receiptTable.rows.length===1,'NONEMPTY_OWNED_SEED_CAPTURE_REQUIRED');
  need(userTable.rows[0].cells[userTable.columns.findIndex(column=>column.name==='revision')]===revision&&userTable.rows[0].cells[userTable.columns.findIndex(column=>column.name==='full_name')]===userName,'NATIVE_BIGINT_AND_TEXT_CAPTURE_REQUIRED');
  need(receiptTable.rows[0].cells[receiptTable.columns.findIndex(column=>column.name==='response_json')]===receiptJson,'EXACT_UNKNOWN_TEXT_JSON_CAPTURE_REQUIRED');
  need(snapshot.migrations.length===11&&snapshot.migrations[9].sha256===LOCAL_TENTH_SHA256&&snapshot.migrations[9].sha256!==HOSTED_TENTH_SHA256,'LOCAL_TENTH_DESCRIPTOR_MUST_NOT_CLAIM_HOSTED_BYTES');
  need(snapshot.migrations[10].sha256===ROOT_SQL11_SHA256,'EXACT_ELEVENTH_DESCRIPTOR_REQUIRED');
  phase='encrypt_separate_key_and_authenticated_readback';
  const archiveDirectory=resolve(attempt,'encrypted'),keyDirectory=resolve(attempt,'separate-keys');
  await mkdir(archiveDirectory,{mode:0o700});await mkdir(keyDirectory,{mode:0o700});
  await privateDirectory(archiveDirectory);await privateDirectory(keyDirectory);
  const sealed=await sealManagementResponse(response,plan,compiled,{archiveDirectory,keyDirectory});
  need(response.body.every(byte=>byte===0),'TRANSIENT_RESPONSE_BUFFER_MUST_BE_CLEARED');
  const archiveStat=await lstat(sealed.archive_path),keyStat=await lstat(sealed.key_path);
  need((archiveStat.mode&0o777)===0o600&&(keyStat.mode&0o777)===0o600&&archiveStat.nlink===1&&keyStat.nlink===1&&keyStat.size===32,'PRIVATE_ENCRYPTED_CUSTODY_REQUIRED');
  need((await readdir(archiveDirectory)).length===1&&(await readdir(keyDirectory)).length===1&&sealed.authenticated_readback===true,'ONE_AUTHENTICATED_ARCHIVE_AND_KEY_REQUIRED');
  const {snapshot:back}=await readEncryptedBundle({archivePath:sealed.archive_path,keyPath:sealed.key_path,expectedArchiveSha256:sealed.archive_sha256});
  need(canonical(back)===canonical(snapshot),'AUTHENTICATED_FULL_SNAPSHOT_MISMATCH');
  await saveNew(resolve(attempt,'ARCHIVE_RECEIPT.json'),sealed);
  phase='new_inert_restore_all_118';
  const restored=await restoreInertArchive(back,{adminUrl:adminUri.href,makeClient});inertName=restored.database;
  need(restored.created_new_database===true&&restored.tables.length===118&&restored.columns_and_native_cells_exact===true&&restored.operational_functions_triggers===false&&restored.managed_auth_storage_ddl_dml===false&&restored.full_recovery_acceptance===false,'GENUINE_NEW_INERT_RESTORE_REQUIRED');
  assert.deepEqual(restored.tables.map(table=>table.source),expectedNames);
  for(const [index,table]of snapshot.tables.entries()){need(restored.tables[index].rows===table.row_count&&restored.tables[index].sha256===table.sha256,'EXACT_118_TABLE_NATIVE_RESTORE_REQUIRED');}
  const inertUri=new URL(adminUri);inertUri.pathname='/'+inertName;const inert=makeClient(inertUri.href);await inert.connect();
  try{
   await inert.query(fixture.fixtureIdentitySql);await inert.query(fixture.restrictedPostgresSql);
   const descriptors=(await inert.query('SELECT descriptor FROM archive_data.manifest')).rows;
   need(descriptors.length===1,'INERT_MANIFEST_REQUIRED');
   const recoveredDescriptor=JSON.parse(descriptors[0].descriptor),{tables,...snapshotMeta}=snapshot;
   need(canonical(recoveredDescriptor)===canonical({...snapshotMeta,tables:tables.map(({rows,...table})=>table)})&&canonical(recoveredDescriptor.migrations)===canonical(snapshot.migrations),'EXACT_INERT_MIGRATION_AND_SOURCE_DESCRIPTOR_REQUIRED');
  }finally{await inert.end();}
  await saveNew(resolve(attempt,'INERT_RESTORE.json'),restored);
  phase='real_count_drift_negatives';
  const negatives=[];
  // Each obsolete count actually queries native current eleven-record history.
  for(const expected of [8,9,10]){
   const oldRequest=compilePlanningRequest({fixtureDatabase:sourceName,expectedMigrationCount:expected}),oldResponse=await localManagementShape(oldRequest);
   let oldMetadata;try{oldMetadata=decodeManagementResult(oldResponse,oldRequest);}finally{oldResponse.body.fill(0);}
   need(oldMetadata.migrations.length===expected+1,'REAL_NATIVE_EXTRA_HISTORY_RECORD_REQUIRED');
   assert.throws(()=>preparePlanCandidate(oldMetadata,{runtimeSourceSha256:integrationPin,sourceMigrations:sourceMigrations.slice(0,expected),fixtureDatabase:sourceName,expectedMigrationCount:expected}),{code:'MIGRATIONS_INVALID'});
   negatives.push({case:'expected_'+expected+'_against_real_eleven',refused:true,code:'MIGRATIONS_INVALID'});
  }
  // The offline operator suite owns other missing/extra, duplicate,
  // reordered/mis-mapped identity and old plan/result/receipt tamper boundaries.
  phase='actual_same_version_name_eleventh_statement_tamper';
  const eleventh=sourceMigrations[10],tamperedSql=applied[10].sql+'\n-- synthetic retained same-version/name tamper negative only\n';
  await saveNew(resolve(attempt,'ELEVENTH_TAMPER_INTENT.json'),{version:eleventh.version,name:eleventh.name,before_applied_sql_sha256:eleventh.sha256,after_tampered_sql_sha256:sha(tamperedSql),synthetic_local_history_only:true,restore_original_history_afterward:false});
  const changed=await source.query('UPDATE supabase_migrations.schema_migrations SET statements=$1::text[] WHERE version=$2 AND name=$3 RETURNING version::text,name::text,statements',[ [tamperedSql],eleventh.version,eleventh.name ]);
  need(changed.rowCount===1&&changed.rows[0].version===eleventh.version&&changed.rows[0].name===eleventh.name&&changed.rows[0].statements.length===1&&changed.rows[0].statements[0]===tamperedSql,'ACTUAL_ELEVENTH_HISTORY_MUTATION_REQUIRED');
  const refused=await localManagementShape(compiled);
  try{assert.throws(()=>assembleManagementSnapshot(refused,plan,compiled),{code:'MANAGEMENT_CAPTURE_REFUSED'});}finally{refused.body.fill(0);}
  negatives.push({case:'same_version_name_eleventh_statements_changed',refused:true,code:'MANAGEMENT_CAPTURE_REFUSED'});
  need((await readdir(archiveDirectory)).length===1,'REFUSED_CAPTURE_MUST_NOT_ADD_ARCHIVE');
  await saveNew(resolve(attempt,'NEGATIVES.json'),{cases:negatives,failed_eleventh_history_preserved_in_source_database:true,prior_history_preserved_in_encrypted_archive_and_metadata:true});
  phase='verify_unchanged_complete_source_after';
  await reviewed.parity();const after=await verifySourceTree(sourceRoot,integrationPin),pgAfter=await verifiedPg(sourceRoot);
  need(after.manifest_sha256===before.manifest_sha256&&after.roles===before.roles&&canonical(after.manifest.files)===canonical(before.manifest.files)&&canonical(pgAfter)===canonical(pgPin)&&sha(await stableFile(ownFile,256*1024))===ownPin,'FULL_SOURCE_OR_FIXTURE_CHANGED_DURING_RUN');
  await source.query(fixture.fixtureIdentitySql);await source.query(fixture.restrictedPostgresSql);
  await source.end();
  need(nativeBatches.length===6&&nativeBatches.every(batch=>batch.native_final_command==='ROLLBACK'),'ALL_NATIVE_ROLLBACK_TAGS_REQUIRED');
  const result={format:'collect.archive.curated-native-fixture.result.v1',source_database:sourceName,inert_database:inertName,attempt_directory:attempt,integration_sha256:integrationPin,source_roles_verified_before_and_after:before.roles,source3_provenance_sha256:SOURCE3_PROVENANCE_SHA256,fixture_source_sha256:ownPin,pg_version:'8.16.3',migrations:11,tables:118,app_tables:97,private_tables:21,column_names_and_order:1143,rows:snapshot.tables.reduce((total,table)=>total+table.row_count,0),nonempty_seeded_tables:['app.users','app.request_receipts'],exact_native_columns_cells_and_migration_descriptors:true,archive_sha256:sealed.archive_sha256,authenticated_private_readback:true,native_generated_batches:nativeBatches,negatives:negatives.length,hosted_sql10_source_sha256:HOSTED_TENTH_SHA256,actually_applied_local_sql10_sha256:LOCAL_TENTH_SHA256,actually_applied_sql11_sha256:ROOT_SQL11_SHA256,management_http201_envelope_simulated:true,local_managed_auth_realtime_doubles:true,management_api_real_data_capture:false,operational_managed_restore:false,provider_or_device_acceptance:false,rpo_rto_acceptance:false,sb29_satisfied:false,full_recovery_acceptance:false,cutover_acceptance:false,databases_and_all_artifacts_preserved:true};
  await saveNew(resolve(attempt,'RESULT.json'),result);
  // Safe summary only: no URL/password, source cells, SQL body, key or raw response.
  process.stdout.write(JSON.stringify({attempt_directory:attempt,source_database:sourceName,inert_database:inertName,migrations:11,tables:118,rows:result.rows,archive_sha256:sealed.archive_sha256,native_rollback_tags:6,local_native_only:true,full_recovery_acceptance:false})+'\n');
 }catch(error){
  if(!inertName&&/^collect_archive_[a-f0-9]{32}_test$/.test(error?.database??''))inertName=error.database;
  if(attempt&&inputRoot&&inputPin){
   let post;try{const checked=await verifySourceTree(inputRoot,inputPin);await verifiedPg(inputRoot);need(sha(await stableFile(ownFile,256*1024))===fixtureSourcePin,'FIXTURE_CHANGED_DURING_FAILED_RUN');post={complete_source_pins_after_failure_verified:true,source_roles:checked.roles};}catch(postError){post={complete_source_pins_after_failure_verified:false,code:safeCode(postError)};}
   await saveNew(resolve(attempt,'FAILED_SOURCE_POSTCHECK.json'),{before_verification_succeeded:sourceBeforeVerified,...post}).catch(()=>{});
  }
  if(attempt)await saveNew(resolve(attempt,'FAILED.json'),{format:'collect.archive.curated-native-fixture.failure.v1',phase,code:safeCode(error),sqlstate:typeof error?.code==='string'&&/^[0-9A-Z]{5}$/.test(error.code)?error.code:null,source_database:sourceName??null,source_created_confirmed:sourceCreated,source_creation_state:sourceCreationState,inert_database:inertName??null,attempt_directory:attempt,preserve_every_database_and_artifact:true,automatic_retry:false,credential_values_logged:false,full_recovery_acceptance:false}).catch(()=>{});
  throw Object.assign(new Error('CURATED_ARCHIVE_FIXTURE_REFUSED_OR_UNCONFIRMED; preserve private artifacts and databases.'),{code:safeCode(error)});
 }finally{
  // Close connections only. Never reset/drop an application schema or database.
  for(const client of clients)await client.end().catch(()=>{});
 }
});
