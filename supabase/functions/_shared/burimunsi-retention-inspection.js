// Inspection-only schema names; no subject selector or disposition is approved.
// Missing/ambiguous ciphertext custody remains unknown, never an empty count.
export const burimunsiBaseRelations=Object.freeze([
  "burimunsi_accounts",
  "burimunsi_audit",
  "burimunsi_command_receipts",
  "burimunsi_device_accounts",
  "burimunsi_device_grants",
  "burimunsi_email_preauth",
  "burimunsi_email_preauth_limits",
  "burimunsi_gateway_handoffs",
  "burimunsi_gateway_pair_targets",
  "burimunsi_gateway_retirements",
  "burimunsi_identity_proofs",
  "burimunsi_integration_policies",
  "burimunsi_native_staff_delegations",
  "burimunsi_operator_approvals",
  "burimunsi_owner_commands",
  "burimunsi_pin_login_limits",
  "burimunsi_pin_session_links",
  "burimunsi_provisioning_commands",
  "burimunsi_rate_limits",
  "burimunsi_receipt_jobs",
  "burimunsi_rematch_jobs",
  "burimunsi_schedulers",
  "burimunsi_scope_setup_commands",
  "burimunsi_scopes",
  "burimunsi_session_links",
  "burimunsi_sessions",
  "burimunsi_sms_source_scopes",
  "burimunsi_transaction_scopes",
  "burimunsi_worker_grants"
]);
export const burimunsiObservationRelations=Object.freeze([
  "burimunsi_observation_consents",
  "burimunsi_observation_requests",
  "burimunsi_unresolved_observations"
]);
// This separate, optional cohort is present only with detection-only profile
// storage. Its subject mapping and erasure disposition are not assumed.
export const burimunsiDetectionRelations=Object.freeze(["burimunsi_detection_profiles"]);
// These cohorts contain shared source, actor and financial references. A
// source owner or grant approver alone is not a complete subject selector.
export const burimunsiNativeAutoRelations=Object.freeze([
 'burimunsi_auto_sms_jobs','burimunsi_native_receipt_origins'
]);
export const burimunsiNativeFinancialRelations=Object.freeze([
 'burimunsi_native_financial_work','burimunsi_native_grant_commands','burimunsi_native_work_grants'
]);
export const burimunsiNativeLeaseHistoryRelations=Object.freeze(['burimunsi_native_lease_history']);
export const burimunsiNativeLeaseHistoryKnownLinks=Object.freeze({
 burimunsi_native_lease_history:'work_id and grant_id bind the actual admitted lease; payer, other shared subjects and pre-install lease versions remain unresolved'
});
export const burimunsiNativeFinancialKnownLinks=Object.freeze({
 burimunsi_native_financial_work:'source_id links to the native receipt origin and its principal; transaction_id may involve other subjects',
 burimunsi_native_grant_commands:'actor_id and principal_session_id identify the command actor; grant_id links to the approved grant',
 burimunsi_native_work_grants:'approved_principal_id and approved_admin_id identify the approver; collection ownership may involve other subjects'
});
export const burimunsiUnmappedStorageClasses=Object.freeze([
 'private:storage_payload_reservations','private:storage_put_intents','private:storage_upload_attempts',
 'private:storage_objects','private:storage_delete_intents','private:object_metadata','managed:storage'
]);
export const burimunsiInspectionCatalog=Object.freeze({contract:'collect.burimunsi.retention.inspection.v1',
 base:burimunsiBaseRelations,observations:burimunsiObservationRelations,
 disposition:'blocked',subject_mapping:'unreviewed',object_custody:'unverified'});
