import {ApiError,digest,stableJson} from './core.js';
import {erasableTables,ownRowInventory,rowPages,SQL_OWN_ROW_LIMIT} from './privacy_retention_chunks.js';
import {privateRetentionCatalogIdentity,privateRetentionClasses,inventoryPrivateRetention,privateRetentionGuards} from '../private-retention.js';
export {erasableTables} from './privacy_retention_chunks.js';

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
export const engineTables=Object.freeze(['privacy_retention_plans','privacy_retention_tasks','privacy_retention_claims','privacy_retention_outcomes','privacy_retention_effects','privacy_retention_guards','privacy_retention_barriers']);
export const copyClasses=Object.freeze(['r2:payment_evidence','r2:sms_receipts','r2:roster_imports','r2:upload_objects','external:derivatives','external:exports','external:backups','external:processors','external:unmapped_identifiers']);
export const retentionClasses=Object.freeze(['access',...Object.keys(retentionColumns),...engineTables,...copyClasses]);
const fail=code=>{throw new ApiError(409,code,'Retention source coverage could not be verified.');};
const all=async(env,sql,...args)=>(await env.DB.prepare(sql).bind(...args).all()).results;
const userFields=new Set(['user_id','owner_user_id','actor_user_id','member_id','proposed_member_id','proposed_by','recipient_user_id','observer_user_id','approved_by','created_by','creator_user_id','updated_by','actor_id','claim_actor','outcome_actor']);
const sessionFields=new Set(['session_id','originating_session_id','owner_session_id','auth_session_id','enrollment_session_id','proposed_session_id','observer_session_id']);
// Receipt metadata is also a copy when the actor is a different administrator.
// Keep these exact known relations; a decision head is never an erasable cache.
const relatedSmsRequests=`SELECT r.request_id FROM request_receipts r WHERE
 r.request_id IN(SELECT request_id FROM assisted_sms_claims WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?))
 OR r.request_id IN(SELECT request_id FROM assisted_sms_confirmations WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?))
 OR r.request_id IN(SELECT request_id FROM assisted_sms_send_starts WHERE job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?))
 OR r.request_id IN(SELECT request_id FROM assisted_sms_outcomes WHERE attempt_id IN(SELECT s.id FROM assisted_sms_send_starts s JOIN assisted_sms_jobs j ON j.id=s.job_id WHERE j.recipient_user_id=?))
 OR r.operation='assisted_sms.enqueue' AND json_extract(r.response_json,'$.job_id') IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?)
 OR r.operation='assisted_sms.materialize.plan' AND EXISTS(SELECT 1 FROM json_each(CASE WHEN r.operation='assisted_sms.materialize.plan' THEN r.response_json ELSE '{}' END,'$.sources') source WHERE json_extract(source.value,'$.entry_id') IN(SELECT id FROM ledger_entries WHERE member_id=?))
 OR r.operation IN('assisted_sms.materialize.intent','assisted_sms.materialize.blocked') AND json_extract(r.response_json,'$.source_entry_id') IN(SELECT id FROM ledger_entries WHERE member_id=?)
 OR r.operation='assisted_sms.policy.configure' AND json_extract(r.response_json,'$.collection_id') IN(SELECT collection_id FROM memberships WHERE user_id=? UNION SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=?)`;

// These are observed financial/source relationships. A masked payer suffix or
// name is never enough to claim personal ownership of another receipt.
function momoRelations(subject,columns){
 const financial=Object.hasOwn(columns,'momo_financial_links');
 const transactionSql=`SELECT t.id FROM momo_transactions t WHERE EXISTS(SELECT 1 FROM momo_transaction_sources s JOIN sms_receipts raw ON raw.id=s.raw_sms_id WHERE s.transaction_id=t.id AND raw.owner_user_id=?)${financial?` OR EXISTS(SELECT 1 FROM momo_financial_links f JOIN payments p ON p.id=f.payment_id WHERE f.transaction_id=t.id AND (f.beneficiary_member_id=? OR f.linked_by=? OR p.member_id=?))`:''}`;
 const transactionArgs=Array(financial?4:1).fill(subject);
 const rawSql=`SELECT raw.id FROM sms_receipts raw WHERE raw.owner_user_id=? OR EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=raw.id AND s.transaction_id IN(${transactionSql}))`;
 return {transactionSql,transactionArgs,rawSql,rawArgs:[subject,...transactionArgs]};
}

function selection(table,subject,catalog=retentionColumns){
 const columns=catalog[table],parts=[],args=[];
 const add=(query,...values)=>{parts.push(query);args.push(...values);};
 if(table==='admin_email_otp_challenges')add('principal_user_id=? OR user_id IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=?)',subject,subject);
 if(table==='auth_google_flows')add('google_subject IN(SELECT subject FROM auth_google_identities WHERE user_id=?) OR email IN(SELECT lower(email) FROM users WHERE id=?)',subject,subject);
 if(Object.hasOwn(catalog,'momo_processing_jobs')){
  const r=momoRelations(subject,catalog),bindings=`SELECT id FROM momo_gateway_bindings WHERE owner_user_id=? OR receiving_account_id IN(SELECT receiving_account_id FROM momo_transactions WHERE id IN(${r.transactionSql}))`,bindingArgs=[subject,...r.transactionArgs];
  if(table==='sms_receipts')add(`id IN(${r.rawSql})`,...r.rawArgs);
  if(['momo_transactions','momo_transaction_sources','momo_financial_links'].includes(table))add(`${table==='momo_transactions'?'id':'transaction_id'} IN(${r.transactionSql})`,...r.transactionArgs);
  if(['momo_processing_jobs','momo_parse_attempts','momo_transaction_sources','momo_gateway_captures','momo_source_resolutions'].includes(table))add(`raw_sms_id IN(${r.rawSql})`,...r.rawArgs);
  if(table==='momo_source_resolutions')add('reviewed_by=?',subject);
  if(table==='momo_gateway_bindings')add(`id IN(${bindings})`,...bindingArgs);
  if(['momo_gateway_credentials','momo_gateway_pairings'].includes(table))add(`binding_id IN(${bindings})`,...bindingArgs);
  if(table==='momo_receiving_accounts')add(`id IN(SELECT receiving_account_id FROM momo_gateway_bindings WHERE id IN(${bindings})) OR id IN(SELECT receiving_account_id FROM momo_transactions WHERE id IN(${r.transactionSql}))`,...bindingArgs,...r.transactionArgs);
  if(table==='momo_financial_links')add('beneficiary_member_id=? OR linked_by=?',subject,subject);
  if(Object.hasOwn(catalog,'momo_financial_links')){
   const linkedPayments=`SELECT payment_id FROM momo_financial_links WHERE transaction_id IN(${r.transactionSql})`;
   if(table==='payments')add(`id IN(${linkedPayments})`,...r.transactionArgs);
   if(['ledger_entries','contribution_posting_snapshots'].includes(table))add(`payment_id IN(${linkedPayments})`,...r.transactionArgs);
   if(table==='payment_evidence')add(`id IN(SELECT evidence_id FROM payments WHERE id IN(${linkedPayments}))`,...r.transactionArgs);
   if(table==='collections')add(`id IN(SELECT collection_id FROM payments WHERE id IN(${linkedPayments}))`,...r.transactionArgs);
  }
  if(table==='momo_processing_guards')return {sql:'1=1',args:[]};
  if(['request_receipts','audit_log'].includes(table))add(`request_id IN(SELECT request_id FROM request_receipts WHERE operation='momo.assign' AND json_extract(response_json,'$.transaction_id') IN(${r.transactionSql}))`,...r.transactionArgs);
  if(table==='request_receipts')add(`json_extract(response_json,'$.raw_sms_id') IN(${r.rawSql}) OR json_extract(response_json,'$.transaction_id') IN(${r.transactionSql})`,...r.rawArgs,...r.transactionArgs);
  if(table==='audit_log')add(`entity_id IN(${r.rawSql}) OR entity_id IN(${r.transactionSql})`,...r.rawArgs,...r.transactionArgs);
 }
 if(table==='users')add('id=?',subject);
 if(table==='collections')add('id IN(SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=? UNION SELECT collection_id FROM assisted_sms_jobs WHERE recipient_user_id=?)',subject,subject);
 if(['runtime_config','admin_account_role_capabilities','auth_rate_buckets','admin_rate_limits'].includes(table))return {sql:'1=1',args:[]};
 if(['request_receipts','audit_log'].includes(table))add('request_id IN('+relatedSmsRequests+')',...Array(9).fill(subject));
 if(table.startsWith('assisted_sms_')){
  if(columns.includes('job_id'))add('job_id IN(SELECT id FROM assisted_sms_jobs WHERE recipient_user_id=?)',subject);
  if(table==='assisted_sms_outcomes')add('attempt_id IN(SELECT s.id FROM assisted_sms_send_starts s JOIN assisted_sms_jobs j ON j.id=s.job_id WHERE j.recipient_user_id=?)',subject);
  if(columns.includes('collection_id'))add('collection_id IN(SELECT collection_id FROM assisted_sms_authorizations WHERE recipient_user_id=? UNION SELECT collection_id FROM assisted_sms_jobs WHERE recipient_user_id=?)',subject,subject);
 }
 for(const column of columns){
  if(userFields.has(column))add('"'+column+'"=?',subject);
  if(sessionFields.has(column))add('"'+column+'" IN(SELECT id FROM auth_sessions WHERE user_id=?)',subject);
  if(['admin_user_id','actor_admin_id','observer_admin_id'].includes(column)||table==='admin_users'&&column==='id'||['admin_sessions','admin_challenges','admin_email_events','admin_role_assignments'].includes(table)&&column==='user_id')add('"'+column+'" IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=?)',subject);
  if(column==='collection_id')add('collection_id IN(SELECT collection_id FROM memberships WHERE user_id=? UNION SELECT id FROM collections WHERE creator_user_id=?)',subject,subject);
  if(column==='request_id'&&(table.startsWith('privacy_')||table==='deletion_reviews'))add('request_id IN(SELECT id FROM deletion_requests WHERE user_id=?)',subject);
  if(column==='request_id'&&table==='auth_identity_rate_aliases')add('request_id IN(SELECT id FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=? UNION SELECT email FROM users WHERE id=?))',subject,subject);
  if(['import_id','source_import_id'].includes(column))add('"'+column+'" IN(SELECT id FROM roster_imports WHERE user_id=? UNION SELECT source_import_id FROM roster_members WHERE linked_user_id=?)',subject,subject);
  if(column==='subject_id')add('subject_id=? OR subject_id IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=?)',subject,subject);
  if(column==='reservation_id')add('reservation_id IN(SELECT id FROM native_reservations WHERE user_id=?)',subject);
  if(column==='processing_id')add('processing_id IN(SELECT id FROM roster_processing_records WHERE actor_user_id=?)',subject);
  if(column==='reconciliation_id')add('reconciliation_id IN(SELECT id FROM reconciliations WHERE proposed_member_id=? OR proposed_by=? OR approved_by=?)',subject,subject,subject);
  if(column==='linked_user_id')add('linked_user_id=?',subject);
  if(column==='payment_id')add('payment_id IN(SELECT id FROM payments WHERE member_id=?)',subject);
  if(column==='evidence_id')add('evidence_id IN(SELECT evidence_id FROM payments WHERE member_id=? UNION SELECT id FROM payment_evidence WHERE owner_user_id=?)',subject,subject);
  if(column==='identity_value')add('identity_value IN(SELECT phone FROM users WHERE id=? UNION SELECT email FROM users WHERE id=?)',subject,subject);
  if(column==='identity_hash')add('identity_hash IN(SELECT identity_hash FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=? UNION SELECT email FROM users WHERE id=?))',subject,subject);
  if(column==='entity_id')add('entity_id=?',subject);
 }
 return {sql:parts.length?'('+parts.join(' OR ')+')':'0=1',args};
}
export async function retentionSchema(env){
 const provider={_cf_METADATA:"CREATE TABLE _cf_METADATA (\n        key INTEGER PRIMARY KEY,\n        value BLOB\n      )",_cf_KV:'CREATE TABLE _cf_KV (\n        key TEXT PRIMARY KEY,\n        value BLOB\n      ) WITHOUT ROWID',d1_migrations:'CREATE TABLE "d1_migrations"(\n\t\tid         INTEGER PRIMARY KEY AUTOINCREMENT,\n\t\tname       TEXT UNIQUE,\n\t\tapplied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL\n)'};
 const observed=await all(env,"SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' ORDER BY type,name"),schema=[];
 for(const row of observed){
  if(Object.hasOwn(provider,row.name)||Object.hasOwn(provider,row.tbl_name)||/^_cf_/i.test(row.name)||/^_cf_/i.test(row.tbl_name)){
   if(row.type!=='table'||row.name!==row.tbl_name||row.sql!==provider[row.name])fail('privacy_retention_unknown_class');
  }else schema.push(row);
 }
 for(const row of await all(env,'SELECT name FROM sqlite_sequence'))if(/^_cf_/i.test(row.name))fail('privacy_retention_unknown_class');
 const names=schema.filter(r=>r.type==='table').map(r=>r.name).sort();
 const auth17={...retentionColumns,...momoPipelineRetentionColumns,...momoFinancialRetentionColumns,...googleAuthRetentionColumns,...adminOtpRetentionColumns};
 const profiles=[['predecessor12_13',retentionColumns],['momo14',{...retentionColumns,...momoPipelineRetentionColumns}],['momo15',{...retentionColumns,...momoPipelineRetentionColumns,...momoFinancialRetentionColumns}],['auth16',{...retentionColumns,...momoPipelineRetentionColumns,...momoFinancialRetentionColumns,...googleAuthRetentionColumns}],['auth17',auth17],['admin_email11',{...auth17,...adminEmailRetentionColumns}]];
 const candidates=profiles.filter(([,columns])=>stableJson(names)===stableJson([...Object.keys(columns),...engineTables].sort()));
 if(!candidates.length)fail('privacy_retention_unknown_class');
 // auth17 and SQL11 have identical table names. Select only after comparing
 // every ordered column against a complete explicit catalog, never a subset.
 const actualColumns={};
 for(const table of Object.keys(candidates[0][1]))actualColumns[table]=(await all(env,'PRAGMA table_info("'+table+'")')).map(r=>r.name);
 const exactProfiles=candidates.filter(([,columns])=>Object.entries(columns).every(([table,expected])=>stableJson(actualColumns[table])===stableJson(expected)));
 if(exactProfiles.length!==1)fail('privacy_retention_schema_changed');
 const profile=exactProfiles[0];
 const privateInventory=await privateRetentionCatalogIdentity(env);
 const currentPrivate=['private:admin_email_operations','private:admin_sensitive_email_proofs','private:collect_fence_source_upgrades'];
 if(profile[0]==='admin_email11'?!currentPrivate.every(name=>privateInventory.classes.includes(name)):currentPrivate.some(name=>privateInventory.classes.includes(name)))fail('privacy_retention_schema_changed');
 return {sha256:await digest(stableJson({application:schema,private_inventory:privateInventory})),privateInventory,tables:names,catalog:observed,profile:profile[0],columns:profile[1],classes:['access',...Object.keys(profile[1]),...engineTables,...copyClasses,...privateRetentionClasses]};
}
export async function retentionSnapshot(env,subject,{limit=500}={}){
 const schema=await retentionSchema(env),tables={},rows={};let contextRows=0,ownRowsCount=0,totalBytes=0;
 if((await env.DB.prepare('SELECT count(*) AS n FROM privacy_retention_guards g JOIN privacy_retention_plans p ON p.id=g.plan_id WHERE p.subject_id=?').bind(subject).first()).n)fail('privacy_retention_orphan_guard_unresolved');
 for(const table of Object.keys(schema.columns)){
  const where=selection(table,subject,schema.columns),chunked=erasableTables.includes(table),found=chunked?await ownRowInventory(env,table,where):await all(env,'SELECT * FROM "'+table+'" WHERE '+where.sql+' LIMIT ?',...where.args,limit+1);
  const own=chunked?found.filter(row=>row.user_id===subject).length:0;ownRowsCount+=own;contextRows+=found.length-own;if(!chunked&&found.length>limit||contextRows>500||ownRowsCount>SQL_OWN_ROW_LIMIT)fail('privacy_retention_inventory_limit');
  for(const row of found)for(const value of Object.values(row))if(typeof value==='number'&&!Number.isSafeInteger(value))fail('privacy_retention_precision_unavailable');
  found.sort((a,b)=>stableJson(a).localeCompare(stableJson(b)));rows[table]=found;
  totalBytes+=new TextEncoder().encode(stableJson(found)).byteLength;if(totalBytes>1024*1024)fail('privacy_retention_inventory_limit');
  tables[table]={count:found.length,sha256:await digest(stableJson(found))};
 }
 const objects=[];let objectBytes=0;
 for(const table of ['payment_evidence','sms_receipts','roster_imports','upload_objects'])for(const row of rows[table]){
  const key=row.source_object_key??row.object_key;
  if(typeof key!=='string'||!key||key.length>1024)fail('privacy_retention_object_unknown');
  if(objects.some(o=>o.key===key))fail('privacy_retention_shared_object');
  if(!env.PRIVATE_MEDIA?.get||!env.PRIVATE_MEDIA?.head)fail('privacy_retention_storage_unavailable');
  if(objects.length>=20)fail('privacy_retention_object_limit');
  const observation=typeof env.PRIVATE_MEDIA.observeRetention==='function'?await env.PRIVATE_MEDIA.observeRetention(key):{kind:'legacy_observation',object:await env.PRIVATE_MEDIA.get(key)};
  if(!observation||!['present','absence_verified','pending_erasure_absence','legacy_observation'].includes(observation.kind)||observation.kind==='present'&&!observation.object||['absence_verified','pending_erasure_absence'].includes(observation.kind)&&observation.object!==null)fail('privacy_retention_object_unknown');
  if(observation.kind==='pending_erasure_absence'&&(typeof observation.operationId!=='string'||!/^[a-f0-9]{64}$/.test(observation.sourceSha256??'')))fail('privacy_retention_object_unknown');
  const object=observation.object;objectBytes+=object?.size??0;
  if(objectBytes>8*1024*1024)fail('privacy_retention_object_limit');
  const body=object?new Uint8Array(await object.arrayBuffer()):null;
  objects.push({class_name:'r2:'+table,record_id:row.id,key,catalog_sha256:row.object_sha256??row.sha256,catalog_size:row.size_bytes??row.source_size,owner_user_id:row.owner_user_id??row.user_id,
   present:!!object,version:object?.version??null,etag:object?.etag??null,size:body?.byteLength??null,body_sha256:body?await digest(body):null,...(observation.kind==='pending_erasure_absence'?{pending_erasure:{operation_id:observation.operationId,source_sha256:observation.sourceSha256,absence_verified:true}}:{})});
 }
 objects.sort((a,b)=>a.key.localeCompare(b.key));
 const balances={};for(const row of rows.ledger_entries){const key=row.collection_id+':'+(row.member_id??'unassigned');balances[key]=((BigInt(balances[key]??'0'))+BigInt(row.amount_minor)).toString();}
 const holds=[...rows.privacy_holds.filter(r=>r.active===1).map(r=>({id:r.id,category:r.category})),...rows.payment_evidence.filter(r=>r.legal_hold===1).map(r=>({id:r.id,category:'financial_evidence'}))];
 const inFlight=(rows.admin_email_otp_challenges??[]).some(r=>r.used_at===null&&['pending','accepted','unknown'].includes(r.delivery_status)&&r.expires_at>Math.floor(Date.now()/1000))||(rows.auth_google_flows??[]).some(r=>['pending','exchanging','ready'].includes(r.status)&&r.expires_at>Math.floor(Date.now()/1000))||rows.native_reservations.some(r=>!['completed','rejected'].includes(r.state))||rows.roster_imports.some(r=>['processing','ambiguous'].includes(r.state))||rows.auth_otp_challenges.some(r=>['dispatching','delivery_unknown'].includes(r.status))||rows.assisted_sms_jobs.some(r=>!['observed_sent','failed_no_send'].includes(r.state))||(rows.momo_processing_jobs??[]).some(r=>r.state!=='completed')||(rows.momo_processing_guards??[]).length>0;
 const privateInventory=await inventoryPrivateRetention(env,subject);
 const summary={subject_id:subject,schema_sha256:schema.sha256,tables,objects,holds,in_flight_unresolved:inFlight||privateInventory.in_flight_unresolved,balances,ledger_sha256:tables.ledger_entries.sha256,private_inventory:privateInventory};
 return {summary,rows,schemaCatalog:schema.catalog,columns:schema.columns,classes:schema.classes,sha256:await digest(stableJson(summary))};
}
export async function retentionApprovalScope(snapshot){
 // The approved decision cannot contain its own hash recursively. Its exact
 // raw bytes are pinned separately at activation and in every transaction;
 // every other configuration row remains part of the approved inventory.
 const config=snapshot.rows.runtime_config.filter(r=>r.key!=='privacy:retention:approved:v1');
 const tables={...snapshot.summary.tables,runtime_config:{count:config.length,sha256:await digest(stableJson(config))}};
 return digest(stableJson({...snapshot.summary,tables,approved_policy_copy:'separately_bound_by_raw_sha256'}));
}
export const ownRows=(table,rows,subject)=>rows.filter(row=>row.user_id===subject);
export const rowKey=(table,row)=>table==='notification_preferences'?row.user_id:row.id;
function preimageGuard(env,planId,className,table,where,found,totalCount=found.length){
 // Full-column JSON comparisons preserve exact coverage with a whole-scope
 // count in every guard. Only the four own-row adapters page these preimages;
 // transient row contents never enter retained task metadata.
 const columns=Object.keys(found[0]??{});
 // PostgreSQL row JSON preserves BIGINT/TEXT/NULL storage classes. Comparing
 // each BIGINT to the text json_extract return type is not equivalent SQL.
 const predicate=columns.length?' AND NOT EXISTS(SELECT 1 FROM json_each(?) j WHERE NOT EXISTS(SELECT 1 FROM "'+table+'" r WHERE to_jsonb(r)=j.value::jsonb))':'';
 return env.DB.prepare('INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,(CASE WHEN (SELECT count(*) FROM "'+table+'" WHERE '+where.sql+')=?'+predicate+' THEN 1 ELSE 0 END)')
  .bind(crypto.randomUUID(),planId,className,...where.args,totalCount,...(columns.length?[stableJson(found)]:[]));
}
export const sourceRowsGuard=(env,table,rows,subject,guard)=>{
 if(!erasableTables.includes(table))fail('privacy_retention_adapter_unavailable');
 const targets=ownRows(table,rows,subject);return rowPages(targets).map(page=>preimageGuard(env,guard.planId,table,table,{sql:'user_id=?',args:[subject]},page,targets.length));
};
export function snapshotCompareGuards(env,plan,snapshot,className,options={}){
 const statements=Object.entries(snapshot.rows).flatMap(([table,found])=>(erasableTables.includes(table)?rowPages(found):[found]).map(page=>preimageGuard(env,plan.id,className,table,selection(table,plan.subject_id,snapshot.columns??retentionColumns),page,found.length)));
 const catalog=snapshot.schemaCatalog;
 // Compare the entire exact raw source catalog, including reviewed metadata.
 // SQL LIKE underscores are wildcards; no provider-prefix or name is omitted
 // from this in-batch source fence after its initial strict admission.
 const filter="sql IS NOT NULL AND name NOT GLOB 'sqlite_*'";
 const match=['type','name','tbl_name','sql'].map(c=>`s."${c}" IS json_extract(j.value,'$."${c}"')`).join(' AND ');
 statements.push(env.DB.prepare('INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,(CASE WHEN (SELECT count(*) FROM sqlite_schema WHERE '+filter+')=? AND NOT EXISTS(SELECT 1 FROM json_each(?) j WHERE NOT EXISTS(SELECT 1 FROM sqlite_schema s WHERE '+match+')) THEN 1 ELSE 0 END)').bind(crypto.randomUUID(),plan.id,className,catalog.length,stableJson(catalog)));
 statements.push(...privateRetentionGuards(env,plan,snapshot,className,options));
 return statements;
}

export async function retentionEngineRows(env,planId,table){
 if(!engineTables.includes(table))fail('privacy_retention_unknown_class');
 const where=table==='privacy_retention_plans'?'id=?':table==='privacy_retention_claims'||table==='privacy_retention_outcomes'||table==='privacy_retention_effects'?'task_id IN(SELECT id FROM privacy_retention_tasks WHERE plan_id=?)':'plan_id=?';
 const found=await all(env,'SELECT * FROM "'+table+'" WHERE '+where+' LIMIT 501',planId);
 if(found.length>500||new TextEncoder().encode(stableJson(found)).byteLength>1024*1024)fail('privacy_retention_inventory_limit');
 return {rows:found,where:{sql:where,args:[planId]}};
}
export const engineRowsGuard=(env,planId,table,observed)=>preimageGuard(env,planId,table,table,observed.where,observed.rows);
