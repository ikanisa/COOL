// Exact predecessor catalog. Additive MoMo profiles below are admitted as whole
// known schema versions, never by wildcard or by ignoring unknown tables.
export const retentionColumns=Object.freeze({
 "admin_account_audit": ["id","actor_id","subject_id","action","occurred_at"],
 "admin_account_guards": ["id","passed"],
 "admin_account_role_capabilities": ["role","permission"],
 "admin_bridge_guards": ["id","passed"],
 "admin_bridge_reconciliation_snapshots": ["reconciliation_id","collection_id","collection_revision","member_id","member_revision","membership_id","membership_revision","payment_identity_json","receiver_number","receiver_network","receiver_label","created_at"],
 "admin_bridge_requests": ["admin_user_id","idempotency_key","request_id","session_id","operation","body_sha256","created_at"],
 "admin_challenges": ["token_hash","user_id","kind","auth_version","challenge_version","delivery_status","created_at","expires_at","used_at"],
 "admin_email_events": ["id","user_id","kind","status","provider_message_id","created_at","updated_at"],
 "admin_grants": ["user_id","permission","granted_by","granted_at"],
 "admin_operator_notes": ["id","entity_type","entity_id","body_ciphertext","body_sha256","created_by","session_id","created_at"],
 "admin_owner_bootstrap_claims": ["operation_id","admin_user_id","principal_user_id","password_hash","display_name","approval_reference","created_at","created_seconds"],
 "admin_principal_links": ["admin_user_id","user_id","approved_by","approved_at"],
 "admin_rate_limits": ["key_hash","bucket","count","expires_at"],
 "admin_role_assignments": ["user_id","role","granted_by","granted_at"],
 "admin_sessions": ["token_hash","public_id","user_id","auth_version","auth_session_id","origin","issued_assurance_level","issued_mfa_at","issued_mfa_factor_id","created_at","expires_at"],
 "admin_users": ["id","email","role","status","display_name","password_hash","auth_version","challenge_version","created_at","invited_at","accepted_at","updated_at"],
 "audit_log": ["id","actor_user_id","actor_session_id","action","entity_type","entity_id","request_id","details_json","created_at"],
 "assisted_sms_authorizations": ["collection_id","recipient_user_id","enabled","consent_revision","destination_revision","destination_ciphertext","destination_sha256","phone_verification_challenge_id","authorization_receipt_sha256","updated_at"],
 "assisted_sms_claims": ["id","request_id","job_id","actor_admin_id","actor_user_id","originating_session_id","public_session_id","actor_role","actor_auth_version","actor_mfa_at","origin","worker_id","previous_fence","fence","created_seconds","expires_seconds"],
 "assisted_sms_confirmations": ["id","request_id","job_id","claim_id","fence","actor_admin_id","actor_user_id","originating_session_id","public_session_id","body_sha256","destination_sha256","destination_revision","confirmed_seconds","expires_seconds"],
 "assisted_sms_jobs": ["id","payment_id","entry_id","collection_id","recipient_user_id","payment_revision","amount_minor","destination_revision","destination_sha256","destination_ciphertext","consent_revision","policy_revision","policy_approval_sha256","authorization_receipt_sha256","template_key","body_ciphertext","body_sha256","state","fence","active_claim_id","created_at"],
 "assisted_sms_outcomes": ["id","request_id","attempt_id","observer_admin_id","observer_user_id","observer_session_id","observer_public_session_id","observation","evidence_reference_sha256","observed_seconds"],
 "assisted_sms_policies": ["collection_id","enabled","revision","template_key","approval_reference_sha256","updated_at"],
 "assisted_sms_send_starts": ["id","request_id","job_id","confirmation_id","claim_id","fence","actor_admin_id","actor_user_id","originating_session_id","public_session_id","body_sha256","destination_sha256","destination_revision","started_seconds"],
 "auth_identity_rate_aliases": ["request_id","identity_key_id","identity_hash","requested_at","hourly_window_ends_at"],
 "auth_mfa_budgets": ["user_id","window_start","kind","used"],
 "auth_mfa_challenges": ["id","user_id","session_id","factor_id","created_at","expires_at","attempts","consumed_at","consumed_operation_id"],
 "auth_mfa_claims": ["operation_id","challenge_id","factor_id","user_id","session_id","totp_counter","verified_at"],
 "auth_mfa_factors": ["id","user_id","friendly_name","secret_ciphertext","status","created_at","enrollment_session_id","verified_at","last_totp_counter","revoked_at"],
 "auth_mfa_revocations": ["operation_id","factor_id","user_id","session_id","revoked_at"],
 "auth_otp_challenges": ["id","identity_hash","identity_type","identity_value","surface","registration_allowed","code_hash","created_at","expires_at","attempts","status","consumed_at","consumed_operation_id","identity_key_id"],
 "auth_otp_throttles": ["identity_hash","last_requested_at","identity_key_id"],
 "auth_otp_verifications": ["operation_id","challenge_id","user_id","session_id","verified_at"],
 "auth_rate_buckets": ["bucket_key","used","window_ends_at"],
 "auth_rate_claims": ["request_id","identity_hash","identity_bucket","ip_bucket","global_bucket","requested_at","hourly_window_ends_at","daily_window_ends_at","identity_limit","ip_limit","global_limit","cooldown_seconds","identity_key_id","identity_aliases_json"],
 "auth_refresh_tokens": ["token_hash","session_id","created_at","expires_at","used_at","replaced_by_hash"],
 "auth_sessions": ["id","user_id","surface","auth_at","created_at","expires_at","revoked_at","revocation_reason","assurance_level","mfa_at","mfa_factor_id"],
 "collections": ["id","slug","creator_user_id","title","description","collection_type","country_code","currency","status","visibility_status","is_platform_sponsored","receiver_momo_number","receiver_network","receiver_display_label","share_code_hash","share_code_ciphertext","share_code_version","revision","data_json","created_at","updated_at"],
 "deletion_requests": ["id","user_id","submission_id","reason","status","revision","created_at","updated_at"],
 "deletion_reviews": ["id","request_id","actor_user_id","expected_revision","outcome","details_json","created_at"],
 "ledger_entries": ["id","payment_id","collection_id","member_id","currency","amount_minor","kind","reverses_entry_id","evidence_id","actor_user_id","request_id","posted_at"],
 "memberships": ["id","collection_id","user_id","role","active","joined_at","revision"],
 "mutation_guards": ["id","user_id","session_id","now_seconds","collection_id","required_group_role","permission","fresh_seconds","expected_collection_revision","payment_id","expected_payment_revision","minimum_assurance","expected_mfa_at","expected_preference_revision","invite_collection_id","expected_share_hash","expected_share_version","recipient_user_id","recipient_collection_id","target_collection_id","expected_target_collection_revision"],
 "native_capabilities": ["id","token_sha256","reservation_id","user_id","session_id","action","receiver_hash","verified_phone","payload_sha256","created_seconds","expires_seconds","verdict_sha256"],
 "native_capability_claims": ["id","capability_id","user_id","session_id","action","payload_sha256","receiver_hash","claimed_seconds"],
 "native_completions": ["reservation_id","capability_id","result_ciphertext","provider_response_sha256","completed_seconds","decode_duration_ms"],
 "native_consents": ["id","user_id","session_id","receiver_hash","enabled","created_seconds","build_channel","request_id"],
 "native_phases": ["reservation_id","phase","started_seconds"],
 "native_reservations": ["id","user_id","session_id","nonce","action","request_hash","token_sha256","receiver_hash","verified_phone","payload_sha256","payload_ciphertext","policy_sha256","approval_id","approval_evidence_sha256","project_id","created_seconds","expires_seconds","actor_hour_limit","project_day_limit","state"],
 "notification_devices": ["id","user_id","token_hash","owner_session_id","provider","token_ciphertext","platform","active","created_at","updated_at"],
 "notification_events": ["id","user_id","event_type","title","body","data_json","status","created_at","read_at"],
 "notification_preferences": ["user_id","push_enabled","payment_updates","group_updates","revision","updated_at"],
 "payment_evidence": ["id","collection_id","owner_user_id","object_key","object_sha256","size_bytes","content_type","authenticity","external_reference","receiver_momo_number","amount_minor","currency","observed_at","created_at","retained_until","legal_hold","receiver_network","receiver_display_label"],
 "payment_intents": ["id","collection_id","member_id","amount_minor","currency","rail","status","receiver_momo_number","receiver_network","receiver_label","originating_session_id","created_at","expires_at","request_id","request_sha256"],
 "payments": ["id","collection_id","member_id","evidence_id","intent_id","amount_minor","currency","rail","status","payer_display_name","created_at","revision"],
 "privacy_holds": ["id","user_id","category","reason_code","active","created_at","released_at"],
 "privacy_review_claims": ["claim_id","claim_request_id","request_id","actor_id","originating_session_id","expected_revision","revision","fence","lease_seconds","claimed_at","expires_at"],
 "privacy_review_heads": ["request_id","revision","fence","state","latest_claim_id","last_outcome_id","created_at","updated_at"],
 "privacy_review_outcomes": ["outcome_request_id","request_id","claim_id","actor_id","originating_session_id","fence","revision","outcome_code","recorded_at"],
 "privacy_submissions": ["submission_id","request_id","user_id","originating_session_id","input_sha256","created_at"],
 "reconciliations": ["id","payment_id","proposed_member_id","proposed_by","proposed_session_id","expected_payment_revision","status","evidence_id","approved_by","request_id","request_sha256","created_at","approved_at"],
 "request_receipts": ["user_id","request_id","operation","session_id","body_sha256","response_json","created_at"],
 "roster_commit_guards": ["id","import_id","revision_id","actor_user_id","session_id","now_seconds","expected_state","expected_latest_revision","permission","collection_id","expected_collection_revision"],
 "roster_dispatch_phases": ["processing_id","phase","started_seconds"],
 "roster_imports": ["id","user_id","session_id","request_id","collection_id","request_sha256","source_sha256","object_sha256","source_object_key","source_size","source_kind","source_receipt_json","state","latest_revision_id","source_ciphertext","created_seconds","expires_seconds","error_code"],
 "roster_intents": ["id","import_id","user_id","session_id","kind","request_id","body_sha256","payload_ciphertext","created_seconds"],
 "roster_members": ["id","collection_id","source_import_id","source_revision_id","member_name","momo_name","momo_number","linked_user_id","created_at"],
 "roster_processing_records": ["id","import_id","actor_user_id","session_id","source_sha256","source_object_sha256","policy_sha256","approval_id","approval_evidence_sha256","processor_policy_json","project_id","organization_id","provider","model","processing_region_evidence_ref","retention_evidence_ref","decoder_build_sha256","decoder_lineage_json","created_seconds","expires_seconds"],
 "roster_revisions": ["id","import_id","request_id","parent_revision_id","revision_number","rows_sha256","preview_ciphertext","human_reviewed","review_reason","created_seconds"],
 "runtime_config": ["key","value_json","revision","updated_by","updated_at"],
 "sms_receipts": ["id","owner_user_id","originating_session_id","client_envelope_id","body_sha256","receiver_hash","object_key","object_sha256","size_bytes","received_at_device","status","evidence_level","created_at"],
 "support_requests": ["id","user_id","collection_id","kind","message","status","created_at"],
 "upload_objects": ["id","user_id","collection_id","object_key","sha256","size_bytes","content_type","purpose","status","created_at","deleted_at"],
 "users": ["id","phone","email","full_name","public_id","country_code","currency_code","momo_provider","momo_number","momo_pay_code","access_status","created_at","updated_at","member_type","revision"]
});

export const momoPipelineRetentionColumns=Object.freeze({
 momo_receiving_accounts:['id','provider','public_code','recipient_name','receiver_hash','currency','timezone','status','profile_status','profile_version','profile_json','created_at'],
 momo_gateway_bindings:['id','owner_user_id','receiving_account_id','version','status','subscription_evidence','created_at','revoked_at'],
 momo_processing_jobs:['raw_sms_id','binding_id','binding_version','receiving_account_id','mode','state','attempt_count','max_attempts','available_at','lease_token','lease_until','last_error','created_at','updated_at'],
 momo_parse_attempts:['id','raw_sms_id','attempt_number','model_id','schema_version','prompt_version','parser_version','profile_version','profile_json','source_body_sha256','output_json','validation_json','outcome','created_at'],
 momo_transactions:['id','receiving_account_id','provider','provider_transaction_id','event_kind','original_transaction_id','amount_minor','currency','currency_scale','payer_name','payer_identifier','payer_last3','transaction_at','transaction_datetime_raw','transaction_timezone','transaction_time_source','fee_minor','wallet_balance_after_minor','parse_attempt_id','mode','allocation_state','has_conflict','version','created_at','updated_at'],
 momo_transaction_sources:['transaction_id','raw_sms_id','parse_attempt_id','relation','created_at'],
 momo_processing_guards:['id','passed']
});
export const momoFinancialRetentionColumns=Object.freeze({
 momo_gateway_pairings:['id','binding_id','code_sha256','originating_session_id','expires_at','claimed_installation_id','created_at'],
 momo_gateway_credentials:['id','binding_id','pairing_id','installation_id','token_sha256','token_ciphertext','last_contact_at','last_sms_at','pending_count','oldest_pending_at','revoked_at','created_at'],
 momo_gateway_captures:['raw_sms_id','credential_id','identity_sha256','service_centre_at','captured_at','inbox_received_at','subscription_id','completeness','source_mode','created_at'],
 momo_financial_links:['transaction_id','payment_id','beneficiary_member_id','linked_by','reason','historical_existing','created_at'],
 contribution_posting_snapshots:['ledger_entry_id','payment_id','member_balance_after_minor','group_balance_after_minor','posted_at'],
 momo_source_resolutions:['id','raw_sms_id','receiving_account_id','source_body_sha256','reviewed_by','evidence_reference','reason','created_at']
});

// Additive member authentication profile. Retain exact column coverage so a
// newly introduced identity record cannot silently escape privacy planning.
export const googleAuthRetentionColumns=Object.freeze({
 auth_google_flows:['id','state_hash','nonce','provider_verifier','client_challenge','client_state','return_origin','registration_allowed','created_at','expires_at','status','google_subject','email','handoff_hash','consumed_operation_id'],
 auth_google_identities:['subject','user_id','created_at'],
});
export const adminOtpRetentionColumns=Object.freeze({
 admin_email_otp_challenges:['id','user_id','principal_user_id','origin','role','auth_version','challenge_version','account_status','code_hash','created_at','expires_at','attempts','delivery_status','used_at','consumed_session_id'],
});
// SQL11 appends exact Admin email provenance without rewriting legacy claims.
// Keep the predecessor layout intact; a profile is an entire known schema.
export const adminEmailRetentionColumns=Object.freeze({
 assisted_sms_claims:Object.freeze([...retentionColumns.assisted_sms_claims,'actor_email_proof_id','actor_email_verified_at'])
});
// SQL15 adds only fixed-code, identity-free diagnostic report aggregates.
// This whole-schema profile creates a new approval hash; it never widens an
// already approved predecessor policy or supplies a new erasure adapter.
export const diagnosticRetentionColumns=Object.freeze({
 client_diagnostic_reports:Object.freeze(['report_id','payload_sha256','surface','environment','build_version','source_revision','code','fingerprint','occurrences','attempt','elapsed_ms','received_hour','expires_at'])
});
// SQL16 introduces retained provider obligations, never a new approved erasure
// class. Its exact identities and terminal uncertainty remain visible to review.
export const notificationDeliveryRetentionColumns=Object.freeze({
 notification_deliveries:Object.freeze(['id','event_id','device_id','user_id','owner_session_id','token_sha256','event_sha256','project_id','android_package','state','attempt_count','available_at','lease_token','lease_until','attempt_log','provider_message_id','last_error','last_http_status','created_at','updated_at'])
});
// New retained obligations have no erasure adapter. A distinct exact profile
// prevents a prior retention approval silently accepting additional copies.
export const notificationChannelRetentionColumns=Object.freeze({
 notification_preferences:Object.freeze([...retentionColumns.notification_preferences,'email_enabled','payment_reminders','security_notices']),
 assisted_sms_dispatches:Object.freeze(['attempt_id','grant_sha256','expires_seconds','application_id','provider_message_id','not_after','state','provider_state','evidence_sha256','started_seconds','updated_seconds']),
 notification_email_deliveries:Object.freeze(['id','event_id','user_id','recipient_sha256','event_sha256','state','attempt_id','started_seconds','provider_message_id','created_seconds','updated_seconds']),
 notification_email_job_dispatches:Object.freeze(['id','admission_sha256','admission_json','state','result_json','created_seconds','updated_seconds'])
});
export const engineTables=Object.freeze(['privacy_retention_plans','privacy_retention_tasks','privacy_retention_claims','privacy_retention_outcomes','privacy_retention_effects','privacy_retention_guards','privacy_retention_barriers']);
export const copyClasses=Object.freeze(['r2:payment_evidence','r2:sms_receipts','r2:roster_imports','r2:upload_objects','external:derivatives','external:exports','external:backups','external:processors','external:unmapped_identifiers','external:collect_sms','external:collect_ops','external:vault','external:net','external:cron','external:supabase_migrations']);
export const retentionClasses=Object.freeze(['access',...Object.keys(retentionColumns),...engineTables,...copyClasses]);
// Table sets and column order identify each supported schema. A schema that
// matches several historical profiles remains ambiguous to the caller.
export function retentionSchemaProfiles(){
 const auth17={...retentionColumns,...momoPipelineRetentionColumns,...momoFinancialRetentionColumns,...googleAuthRetentionColumns,...adminOtpRetentionColumns};
 const channels={...auth17,...adminEmailRetentionColumns,...diagnosticRetentionColumns,...notificationDeliveryRetentionColumns,...notificationChannelRetentionColumns};
 return [['predecessor12_13',retentionColumns],['momo14',{...retentionColumns,...momoPipelineRetentionColumns,...momoFinancialRetentionColumns}],['momo15',{...retentionColumns,...momoPipelineRetentionColumns,...momoFinancialRetentionColumns}],['auth16',{...retentionColumns,...momoPipelineRetentionColumns,...momoFinancialRetentionColumns,...googleAuthRetentionColumns}],['auth17',auth17],['admin_email11',{...auth17,...adminEmailRetentionColumns}],['diagnostics15',{...auth17,...adminEmailRetentionColumns,...diagnosticRetentionColumns}],['notifications16',{...auth17,...adminEmailRetentionColumns,...diagnosticRetentionColumns,...notificationDeliveryRetentionColumns}],['notification_channels17',channels],
  ['payment_display_reference',{...channels,payments:[...channels.payments,'payment_reference']}]];
}
