#!/usr/bin/env node
import {readFile,readdir,writeFile,lstat,realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {operationInventory} from '../src/operations.js';
import worker from '../src/index.js';

const root=fileURLToPath(new URL('../',import.meta.url));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
async function sourceFiles(directory,prefix='',strictMetadata=false){
  const result={};
  for(const entry of (await readdir(directory,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name,'en'))){
    const path=resolve(directory,entry.name),name=prefix+entry.name;
    if(entry.name.startsWith('._')){
      if(strictMetadata)need(await auth17MetadataSidecar(path,entry.name),'Auth17 refuses unverified metadata-looking source input');
      continue;
    }
    if(entry.isSymbolicLink())throw new Error('Operation inventory does not follow source aliases.');
    if(entry.isDirectory())Object.assign(result,await sourceFiles(path,name+'/',strictMetadata));
    else if(entry.isFile())result[name]=sha(await readFile(path));
    else throw new Error('Operation inventory requires regular source inputs.');
  }
  return result;
}

const reviewedOperations=Object.freeze({
 "receipts.js": [
  "ingest-client-sms",
  "ingest-payment-sms"
 ],
 "roster.js": [
  "prepare-roster-import",
  "roster-import-commit",
  "roster-import-extract",
  "roster-import-upload",
  "admin_commit_roster_import",
  "admin_execute_roster_import_intent",
  "admin_get_roster_import",
  "admin_review_roster_import",
  "admin_stage_roster_import_intent"
 ],
 "native_integrity.js": [
  "verify-play-integrity",
  "record_sms_access_consent"
 ],
 "groups.js": [
  "add_group_admin",
  "archive_group",
  "create_private_group_with_owner_media_attested",
  "ensure_current_member_profile",
  "get_current_member_profile",
  "get_group_share_code",
  "get_owner_group_health",
  "join_group_by_share_code",
  "list_current_member_group_roster",
  "list_current_user_collections",
  "rotate_group_share_code_v2",
  "transfer_group_ownership",
  "update_current_member_profile",
  "update_rwanda_momo_group_profile"
 ],
 "privacy.js": [
  "admin_claim_account_deletion_review_v1",
  "admin_get_account_deletion_review_operation_v1",
  "admin_get_account_deletion_review_v1",
  "admin_list_account_deletion_reviews_v1",
  "admin_record_account_deletion_review_v1",
  "get_account_deletion_request_status_v1",
  "get_account_deletion_review_status_v1",
  "get_current_account_deletion_request_status_v1",
  "request_account_deletion",
  "request_account_deletion_v1"
 ],
 "privacy_retention_rpc.js": [
  "admin_claim_account_retention_task_v1",
  "admin_execute_account_retention_task_v1",
  "admin_get_account_retention_context_v1",
  "admin_get_account_retention_operation_v1",
  "admin_get_account_retention_status_v1",
  "admin_inspect_account_quarantine_continuation_v1",
  "admin_inspect_account_retention_scope_v1",
  "admin_plan_account_retention_v1",
  "admin_reconcile_account_retention_v1"
 ],
 "admin.js": [
  "admin_current_user",
  "admin_get_queue_sla",
  "admin_get_user",
  "admin_list_audit_logs",
  "admin_list_collect_ledgers",
  "admin_list_collect_reconciliations",
  "admin_list_collect_transactions",
  "admin_list_collections",
  "admin_list_ledger",
  "admin_list_members",
  "admin_list_non_member_users",
  "admin_list_notifications",
  "admin_list_payment_intents",
  "admin_list_payments",
  "admin_list_settings",
  "admin_list_users",
  "admin_overview",
  "admin_runtime_config",
  "admin_set_user_access",
  "admin_system_health",
  "is_platform_admin"
 ],
 "evidence.js": [
  "admin_record_full_payment_compensation_v1",
  "admin_reverse_payment_v1"
 ],
 "operator_notes.js": [
  "admin_record_operator_note"
 ],
 "payments.js": [
  "approve_payment_reconciliation_v2",
  "create_contribution_intent",
  "get_payment_reconciliation_v2",
  "list_current_member_collection_balances",
  "list_current_member_history_page",
  "list_current_member_recent_intents",
  "list_payment_reconciliations_v2",
  "propose_payment_reconciliation_v2",
  "reject_payment_reconciliation_v2"
 ],
 "notifications.js": [
  "create_mobile_support_request",
  "get_current_member_payment_review_request_v1",
  "get_notification_preferences_v2",
  "mark_notification_event_read",
  "register_notification_device",
  "set_notification_preferences_v2",
  "unregister_notification_device"
 ],
 "index.js": [
  "get_active_policy_document",
  "get_collection_type_catalog",
  "get_public_runtime_config",
  "list_account_request_reasons"
 ],
 "notification_operator_consent.js": [
  "get_assisted_sms_consent_v1",
  "set_assisted_sms_consent_v1"
 ]
});

const routeFamilies=Object.freeze([
      {path:'/health',source:'index.js',authentication:'public'},
      {path:'/privacy/account-deletion/**',source:'privacy_portal.js',authentication:'public_presentation_authenticated_intake'},
      {path:'/v1/auth/**',source:'auth.js',authentication:'action_specific'},
      {path:'/v1/security/challenge',source:'challenge.js',authentication:'public'},
      {path:'/v1/query/public-collections',source:'groups.js',authentication:'public'},
      {path:'/v1/query/notification-events',source:'notifications.js',authentication:'bearer_session'},
      {path:'/v1/sync',source:'sync.js',authentication:'bearer_session'},
      {path:'/v1/evidence/:id?',source:'evidence.js',authentication:'bearer_session'},
      {path:'/v1/receipts/:id',source:'receipts.js',authentication:'bearer_session'},
      {path:'/api/admin/**',source:'admin_bridge.js',authentication:'origin_bound_httponly_cookie'},
      {path:'/api/admin/notification-operator',source:'notification_operator.js',authentication:'origin_bound_current_cookie_fresh_aal2',methods:['POST'],actions:['list_pending','claim','get_claimed','confirm','record_send_start','record_outcome','release_claim','get_operation'],permissions:{list_pending:'assisted_sms.read',other_actions:'assisted_sms.manage'},transport_dispatch:false},
      {path:'/api/admin/notification-operator/access',source:'notification_operator_management.js',authentication:'current_owner_cookie_admin_users.manage_fresh_aal2',methods:['GET','POST'],target:'derived_current_principal_only',automatic_activation:false},
      {path:'/api/admin/notification-operator/access/operations/:request_id',source:'notification_operator_management.js',authentication:'current_owner_cookie_admin_users.manage_fresh_aal2_original_session',methods:['GET'],historical_decision_only:true,transport_dispatch:false},
      {path:'/api/admin/notification-operator/operations',source:'notification_operator_management.js',authentication:'current_owner_cookie_admin_users.manage_fresh_aal2_original_session',methods:['GET'],maximum_records:25,named_kinds:['access','policy','materialization'],metadata_only:true,transport_dispatch:false},
      {path:'/api/admin/notification-operator/policies/:collection_id',source:'notification_operator_management.js',authentication:'current_owner_cookie_assisted_sms.manage_fresh_aal2',methods:['GET','POST'],automatic_activation:false},
      {path:'/api/admin/notification-operator/policies/operations/:request_id',source:'notification_operator_management.js',authentication:'current_owner_cookie_assisted_sms.manage_fresh_aal2_original_session',methods:['GET'],historical_decision_only:true,transport_dispatch:false},
      {path:'/api/admin/notification-operator/materialize',source:'notification_operator_management.js',authentication:'current_owner_cookie_assisted_sms.manage_fresh_aal2_original_session',methods:['POST'],maximum_source_rows:10,durable_bounded_request_plan:true,transport_dispatch:false},
      {path:'/api/admin/notification-operator/materialize/:request_id',source:'notification_operator_management.js',authentication:'current_owner_cookie_assisted_sms.manage_fresh_aal2_original_session',methods:['GET'],historical_plan_status_only:true,transport_dispatch:false},
      {path:'/api/admin/sms/receipts',source:'admin_sms_receipts.js',authentication:'origin_bound_current_cookie_sms.read',methods:['GET'],permissions:{read:'sms.read'},metadata_only:true,transport_dispatch:false},
      {path:'/api/admin/sms/receipts/capture/:receipt_id',source:'admin_sms_receipts.js',authentication:'origin_bound_current_cookie_sms.read',methods:['GET'],permissions:{read:'sms.read'},metadata_only:true,transport_dispatch:false},
      {path:'/api/admin/gateway/receipts',source:'admin_member_receipts.js',authentication:'origin_bound_current_cookie_payments.read',methods:['GET'],permissions:{read:'payments.read'},metadata_only:true,transport_dispatch:false},
      {path:'/api/admin/gateway/receipts/:receipt_id',source:'admin_member_receipts.js',authentication:'origin_bound_current_cookie_payments.read',methods:['GET'],permissions:{read:'payments.read'},metadata_only:true,transport_dispatch:false},
    ]);

// The complete13 artifact and validator remain a separate historical contract.
// This successor describes the current source candidate without admitting it to
// release/recovery tooling or inheriting any predecessor approval.
const momoProfile='momo15_candidate';
// This read was added after complete13 was sealed. Keep its runtime wire in
// the current successor only; never rewrite the preserved historical artifact.
const momoOnlyOperations=new Set(['get_current_member_payment_review_request_v1']);
const profileOperations=momo=>momo?operationInventory:operationInventory.filter(row=>!momoOnlyOperations.has(row.name));
const momoWranglerSha256='5db2b2c14b7b3e4fe48f1b56c863b1a7557e20d917732aef1ff631e232a80224';
const predecessorInventory=Object.freeze({path:'operations-manifest.json',profile:'complete13',sha256:'968bb1754e4c9f425e173b7548ce5dafe2daec57ef7e3f827272818ce7a6ca29',approval_or_release_acceptance_inherited:false});
const momoMigrationDigests=Object.freeze({
 '0001_core.sql':'299b0358d2545a6bbc3f6dc004eadb19168ba9d72131368d0e814165ab6b6455',
 '0002_auth.sql':'2106f1db68d8bd21a540c747079da4df032842ae42f38979be7f687e8af0b2a7',
 '0003_mutation_guards.sql':'c1a4aa837663235af26b41977a531db33e9c61b18006ca167cb7eca486562744',
 '0004_privacy.sql':'e7ba2d670e3620e7c4042f6291fa62c83407df7270987d8df5ac6431e8766ef3',
 '0005_ingestion.sql':'b8974163e228cbc776ae88378c7fb3aece26b560841e2f7f76b7a53f254c75f7',
 '0006_admin_accounts.sql':'ed56c5d5da367cccbc877848ffa0cbdb418a5cb6ef58a443318d2b6b7d794ba0',
 '0007_admin_bridge.sql':'9668f1394a24dc18c75eed61d98f24c598dc8b763103c3144fef25988e0ef3b2',
 '0008_receipt_capture.sql':'247771ccb826bb48e894dc1de703ce1cb0706c18ece1620557447faa673449fd',
 '0009_operator_notes.sql':'e7ee374a172bb818c0a382e1e94fdc467f776f05bc31789d1215484d4fbce970',
 '0010_privacy_retention.sql':'94d7ec5146a4ef3e4721cb185a4700edea76c3e72e1cf992dd9fcb2d2e1571d2',
 '0011_auth_identity_keys.sql':'7e315ad76f45a6e5735d5ee42e7ae94f931e413de37b329a009f31ce9027e8f0',
 '0012_notification_operator.sql':'f6bfc6603505b8a29338d845707b3347c8c767d230f41f8347a1979d4c70bac7',
 '0013_sms_receipt_metadata_read.sql':'724f94ab29413b6e1e69c25678078f1e3161d8b0b7bcfe3cd20b1fd25cbc146b',
 '0014_momo_pipeline.sql':'b31e0590ad4d0b5b2e6acf3c6c069b84ec1cbe8d003eb69f7c5d5f306a3a63d6',
 '0015_momo_gateway_allocation.sql':'c84e3ea9330c0506781072173af7f5b9a7324017943ca58a967e399df515c422',
});
const momoRouteFamilies=Object.freeze([
 {path:'/v1/momo/gateway/pair',source:'momo_gateway.js',authentication:'short_lived_pairing_secret_and_installation_id',methods:['POST'],actions:[{method:'POST',path:'/v1/momo/gateway/pair'}],transport_dispatch:false},
 {path:'/v1/momo/gateway/ingest',source:'momo_gateway.js',authentication:'installation_bound_ingest_health_credential',methods:['POST'],actions:[{method:'POST',path:'/v1/momo/gateway/ingest'}],transport_dispatch:false},
 {path:'/v1/momo/gateway/status',source:'momo_gateway.js',authentication:'installation_bound_ingest_health_credential',methods:['GET'],actions:[{method:'GET',path:'/v1/momo/gateway/status'}],transport_dispatch:false},
 {path:'/v1/momo/gateway/heartbeat',source:'momo_gateway.js',authentication:'installation_bound_ingest_health_credential',methods:['POST'],actions:[{method:'POST',path:'/v1/momo/gateway/heartbeat'}],transport_dispatch:false},
 {path:'/api/admin/momo/accounts/**',source:'admin_momo.js',authentication:'origin_bound_current_cookie_action_capability',methods:['GET','POST'],actions:[
  {method:'GET',path:'/api/admin/momo/accounts',permissions:['receivers.read']},
  {method:'POST',path:'/api/admin/momo/accounts',permissions:['receivers.read','receivers.manage']},
  {method:'POST',path:'/api/admin/momo/accounts/:id/profile',permissions:['receivers.read','receivers.manage']}],transport_dispatch:false},
 {path:'/api/admin/momo/bindings/**',source:'admin_momo.js',authentication:'origin_bound_current_cookie_action_capability',methods:['GET','POST'],actions:[
  {method:'GET',path:'/api/admin/momo/bindings',permissions:['receivers.read']},
  {method:'POST',path:'/api/admin/momo/bindings',permissions:['receivers.read','receivers.manage']},
  {method:'POST',path:'/api/admin/momo/bindings/:id/revoke',permissions:['receivers.read','receivers.manage']}],transport_dispatch:false},
 {path:'/api/admin/momo/transactions/**',source:'admin_momo.js',authentication:'origin_bound_current_cookie_action_capability',methods:['GET','POST'],actions:[
  {method:'GET',path:'/api/admin/momo/transactions',permissions:['payments.read']},
  {method:'GET',path:'/api/admin/momo/transactions/payment-checks',permissions:['payments.read','users.read','collections.read'],member_supplied_unverified_context_only:true},
  {method:'GET',path:'/api/admin/momo/transactions/:id',permissions:['payments.read']},
  {method:'GET',path:'/api/admin/momo/transactions/:id/candidates',permissions:['payments.read','users.read','collections.read']},
  {method:'POST',path:'/api/admin/momo/transactions/:id/assign',permissions:['payments.read','payments.write']},
  {method:'POST',path:'/api/admin/momo/transactions/:id/review-conflict',permissions:['payments.read','payments.write','sms.extract'],fresh_aal2:true,unlinked_only:true,immutable_facts_replaced:false}],transport_dispatch:false},
 {path:'/api/admin/momo/sources/**',source:'admin_momo.js',authentication:'origin_bound_current_cookie_action_capability',methods:['GET','POST'],actions:[
  {method:'GET',path:'/api/admin/momo/sources',permissions:['sms.read']},
  {method:'GET',path:'/api/admin/momo/sources/:id/content',permissions:['sms.read','sms.reveal'],fresh_aal2:true,reason_required:true},
  {method:'POST',path:'/api/admin/momo/sources/backfill',permissions:['sms.read','sms.extract']},
  {method:'POST',path:'/api/admin/momo/sources/:id/resolve',permissions:['sms.read','sms.extract']},
  {method:'POST',path:'/api/admin/momo/sources/:id/reparse',permissions:['sms.read','sms.extract']},
  {method:'POST',path:'/api/admin/momo/sources/:id/correct-extraction',permissions:['sms.read','sms.extract'],fresh_aal2:true,no_accepted_canonical_or_financial_source_link:true},
  {method:'POST',path:'/api/admin/momo/sources/:id/classify-non-payment',permissions:['sms.read','sms.extract'],fresh_aal2:true,no_accepted_canonical_or_financial_source_link:true}],transport_dispatch:false},
]);

// Source-only release metadata. It describes existing code; runtime dispatch
// never reads these declarations as a permission, provider approval or send permit.
const need=(ok,message)=>{if(!ok)throw new Error(message);};
const canonical=value=>JSON.stringify(value);
const callerCatalog=Object.freeze({
 member_app:{mode:'bearer_session',source_scope:'Collect member repository/native bridge source; installed acceptance is separate'},
 admin_panel:{mode:'origin_bound_httponly_cookie',source_scope:'Collect Cloudflare Admin client source; deployed/browser acceptance is separate'},
 authorized_operator_api:{mode:'bearer_session',source_scope:'Registered operator contract; a current first-party direct bearer consumer is not asserted where only a cookie bridge is used'},
 anonymous_public_client:{mode:'public',source_scope:'Public configuration/group/presentation callers; content/provider approval is not implied'},
 native_android_member:{mode:'bearer_session_and_request_bound_native_capability',source_scope:'Member Android owner/SMS bridge; device/store policy and provider admission remain separate'},
});
const momoCallerCatalog=Object.freeze({...callerCatalog,
 native_android_gateway:{mode:'installation_bound_ingest_health_credential',source_scope:'Dedicated incoming Android gateway source only; no member/admin bearer authority or physical-device acceptance'},
});
const roleSources=Object.freeze({
 AUTH_JWT_SECRET:['auth.js'],AUTH_TOKEN_HASH_SECRET:['auth.js'],
 DATA_ENCRYPTION_KEY:['encryption.js'],DATA_DECRYPTION_KEYS_JSON:['encryption.js'],TURNSTILE_SECRET:['auth.js'],OTP_DELIVERY_TOKEN:['auth.js'],
 AUTH_IDENTITY_HASH_KEY:['identity_keys.js'],AUTH_IDENTITY_PREVIOUS_KEYS_JSON:['identity_keys.js'],
 PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON:['native_integrity.js'],OPENAI_API_KEY:['roster.js'],
 PRIVACY_RETENTION_APPROVAL_SHA256:['privacy_retention_policy.js'],
});
const requirement=(role,when)=>({role,when,source:roleSources[role],configured_or_approved_by_manifest:false});
const sessionRoles=()=>[
 requirement('AUTH_JWT_SECRET','When verifying or issuing authenticated sessions'),
 requirement('AUTH_TOKEN_HASH_SECRET','When Auth configuration/session validation or legacy identity hashing is used'),
 requirement('AUTH_IDENTITY_HASH_KEY','Only when the explicit AUTH_IDENTITY_KEY_ID/active-key pair is configured; legacy fallback remains supported'),
 requirement('AUTH_IDENTITY_PREVIOUS_KEYS_JSON','Only when an optional historical identity-key map is explicitly configured; it is not a baseline required role'),
];
const encryption=when=>requirement('DATA_ENCRYPTION_KEY',when);
const historicalEncryption=()=>requirement('DATA_DECRYPTION_KEYS_JSON','Only when an explicitly configured bounded historical decryption-key map is needed; no key provisioning or rotation acceptance is implied');
const policyPin=()=>requirement('PRIVACY_RETENTION_APPROVAL_SHA256','Only for retained-policy plan/claim/effect/reconciliation or explicit continued-quarantine authorization; read-only context/status is not a policy activation');
const rolloutOrder=Object.freeze(['exact_current_schema','immutable_worker_bundle','source_configuration_migration_readback','declared_HTTP_modes_and_compatible_callers']);
const profile=(state,callers,checks,notes)=>({state,callers,checks,notes});
const profiles=Object.freeze({
 'index.js':profile('conditional',['anonymous_public_client','member_app'],['Public only for the four registered configuration operations','Exact runtime_config record/document key; absence fails configuration_unavailable'],['Content is returned as stored; registration does not approve legal content or establish a live configuration']),
 'groups.js':profile('active',['member_app'],['Current approved principal/session','Own profile or current collection membership/owner authority as the selected handler requires','Group revision, receiver/native capability and mutation-session guards where required'],['Existing group/identity capability is preserved; metadata is not a grant']),
 'payments.js':profile('active',['member_app','authorized_operator_api','admin_panel'],['Current principal/session and authorized member/group scope','Operator reconciliation uses actual permissions, AAL2 and separate proposer/reviewer with current source revisions','Original request/session on mutations and immutable evidence/journal lineage where the selected handler requires them'],['Recorded/reconciled evidence is not itself provider settlement; no provider route is activated']),
 'admin.js':profile('active',['authorized_operator_api'],['Current approved principal/session and exact handler permission','Protected operator/active-owner target guards for member management','Fresh AAL2 on sensitive writes; read handlers retain their existing authority'],['These bearer compatibility operations remain registered; cookie Admin uses its separately listed current routes']),
 'notifications.js':profile('active',['member_app'],['Current principal/session and self-only device/preferences/events','Registration and withdrawal preserve token/session ownership and revision checks'],['Device storage/preferences/events do not constitute an outbound push transport or device presentation']),
 'evidence.js':profile('active',['authorized_operator_api','admin_panel'],['payments.reconcile, fresh AAL2, exact payment/source revision','Immutable original contribution and compensating entry lineage','Original request/session replay and current authority'],['Correction/reversal preserves evidence history; no independent provider settlement is inferred']),
 'privacy.js':profile('active',['member_app','authorized_operator_api','admin_panel'],['Self-only authenticated intake/status, or current privacy.review Admin surface with required fresh AAL2','Original request/claim/session and review revision guards'],['Receiving or reviewing a deletion request is not erasure completion']),
 'privacy_retention_rpc.js':profile('conditional',['authorized_operator_api','admin_panel'],['privacy.review, current Admin session and fresh issued AAL2','Exact current source/schema/scope/approved policy/holds/lease and copy outcomes for effects','Immutable barriers, journals and truthful incomplete/blocked outcomes'],['No default approved policy, erasure schedule, copy authority or recovery acceptance is supplied']),
 'operator_notes.js':profile('active',['authorized_operator_api','admin_panel'],['Entity-specific collections.read or users.read','Current original mutation request/session and exact entity type','Encrypted note body with audit/receipt metadata only'],['Notes do not modify financial facts or grant access']),
 'native_integrity.js':profile('conditional',['native_android_member'],['Current member/session and exact verified receiving-phone/SMS consent binding','For verification: approved pinned Google policy/service account, budget/reservation, nonce/request/package/certificate/version/license/device evidence','One-use content-bound capability; ambiguous provider effects are not blindly replayed'],['No Google/provider/device/store/SMS permission is activated by inventory']),
 'receipts.js':profile('conditional',['native_android_member'],['Current original member/session, verified receiver and one-use sms.ingest capability','Exact envelope/body/object hashes and private encrypted evidence','Receipt observation never posts settlement or delivery authority'],['Actual Android/SMS policy/native-provider prerequisites remain conditional']),
 'roster.js':profile('conditional',['authorized_operator_api','admin_panel'],['Admin surface, roster.import, fresh AAL2 and original import session','Retained source/revision/request/collection guards and human-reviewed deterministic commit','PDF/image AI branch separately requires exact approved processor/decoder/project policy'],['Text/XLSX deterministic paths do not require an AI key; AI is not enabled by registration']),
 'notification_operator_consent.js':profile('conditional',['member_app'],['Current member principal/session and active collection scope','Opt-in binds consumed destination-phone proof/current profile; no inference from MoMo/push/privacy','Monotonic immutable decision head including no-ops; exact original request/session replay'],['Consent alone supplies neither enabled collection policy, materialized job, transport authority nor delivery']),
});
const reviewedCallerReferences=Object.freeze({
 "get_current_member_payment_review_request_v1":["lib/shared/repositories/collect_repository.dart"],
 "ingest-client-sms":[],
 "ingest-payment-sms":["lib/shared/repositories/collect_repository_contribution_actions.dart"],
 "prepare-roster-import":["lib/admin/core/admin_repository_runtime.dart","lib/admin/core/admin_roster_gateway.dart"],
 "roster-import-commit":[],
 "roster-import-extract":[],
 "roster-import-upload":[],
 "verify-play-integrity":["lib/core/security/play_integrity_service.dart"],
 "add_group_admin":["lib/shared/repositories/collect_repository_group_actions.dart"],
 "admin_claim_account_deletion_review_v1":["lib/admin/core/admin_privacy_review_models.dart","lib/admin/core/cloudflare_admin_privacy_review_host.dart"],
 "admin_claim_account_retention_task_v1":[],
 "admin_commit_roster_import":["lib/admin/core/admin_roster_gateway.dart"],
 "admin_current_user":["lib/admin/core/admin_repository_runtime.dart"],
 "admin_execute_account_retention_task_v1":[],
 "admin_execute_roster_import_intent":["lib/admin/core/admin_roster_gateway.dart","lib/admin/core/admin_roster_import.dart"],
 "admin_get_account_deletion_review_operation_v1":["lib/admin/core/admin_privacy_review_sdk.dart","lib/admin/core/cloudflare_admin_privacy_review_host.dart"],
 "admin_get_account_deletion_review_v1":["lib/admin/core/admin_privacy_review_sdk.dart","lib/admin/core/cloudflare_admin_privacy_review_host.dart"],
 "admin_get_account_retention_context_v1":["lib/admin/core/cloudflare_admin_privacy_review_host.dart"],
 "admin_get_account_retention_operation_v1":[],
 "admin_get_account_retention_status_v1":[],
 "admin_get_queue_sla":["lib/admin/core/admin_repository_runtime.dart"],
 "admin_get_roster_import":["lib/admin/core/admin_roster_gateway.dart"],
 "admin_get_user":["lib/admin/admin_router.dart","lib/admin/core/admin_detail_formatters.dart","lib/admin/core/admin_detail_runtime.dart","lib/admin/core/admin_detail_specs.dart","lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_read_contracts.dart","lib/admin/core/admin_runtime.dart"],
 "admin_inspect_account_quarantine_continuation_v1":[],
 "admin_inspect_account_retention_scope_v1":["lib/admin/core/cloudflare_admin_privacy_review_host.dart","lib/admin/core/cloudflare_admin_retention_inspection.dart"],
 "admin_list_account_deletion_reviews_v1":["lib/admin/core/admin_privacy_review_sdk.dart","lib/admin/core/cloudflare_admin_privacy_review_host.dart"],
 "admin_list_audit_logs":["lib/admin/admin_router.dart","lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/shared/components/admin_data_table.dart"],
 "admin_list_collect_ledgers":["lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/core/admin_overview_runtime.dart","lib/admin/core/admin_runtime.dart","lib/admin/core/cloudflare_admin_repository_models.dart","lib/admin/shared/components/admin_data_table.dart"],
 "admin_list_collect_reconciliations":["lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/core/admin_overview_runtime.dart","lib/admin/core/admin_reconciliation_runtime.dart","lib/admin/core/admin_runtime.dart","lib/admin/shared/components/admin_data_table.dart"],
 "admin_list_collect_transactions":["lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/core/admin_runtime.dart","lib/admin/core/cloudflare_admin_repository_models.dart"],
 "admin_list_collections":["lib/admin/admin_router.dart","lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/core/admin_receipt_notice_content_host.dart","lib/admin/core/admin_runtime.dart","lib/admin/core/cloudflare_admin_repository_models.dart"],
 "admin_list_ledger":["lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_specs.dart"],
 "admin_list_members":["lib/admin/admin_router.dart","lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/core/admin_runtime.dart","lib/admin/core/cloudflare_admin_repository_models.dart","lib/admin/shared/components/admin_data_table.dart"],
 "admin_list_non_member_users":["lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/core/admin_runtime.dart","lib/admin/shared/components/admin_data_table.dart"],
 "admin_list_notifications":["lib/admin/admin_router.dart","lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/core/admin_runtime.dart","lib/admin/shared/components/admin_data_table.dart"],
 "admin_list_payment_intents":["lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_specs.dart"],
 "admin_list_payments":["lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_specs.dart"],
 "admin_list_settings":["lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/shared/components/admin_data_table.dart"],
 "admin_list_users":["lib/admin/admin_router.dart","lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_list_runtime.dart","lib/admin/core/admin_list_specs.dart","lib/admin/core/admin_operator_draft_owner.dart","lib/admin/core/admin_runtime.dart","lib/admin/core/cloudflare_admin_repository_models.dart"],
 "admin_overview":["lib/admin/core/admin_repository_runtime.dart"],
 "admin_plan_account_retention_v1":[],
 "admin_reconcile_account_retention_v1":[],
 "admin_record_account_deletion_review_v1":["lib/admin/core/admin_privacy_review_models.dart","lib/admin/core/cloudflare_admin_privacy_review_host.dart"],
 "admin_record_full_payment_compensation_v1":["lib/admin/core/admin_full_payment_compensation_sdk.dart"],
 "admin_record_operator_note":["lib/admin/core/admin_action_contracts.dart","lib/admin/core/admin_detail_runtime.dart"],
 "admin_reverse_payment_v1":[],
 "admin_review_roster_import":["lib/admin/core/admin_roster_gateway.dart"],
 "admin_runtime_config":["lib/admin/core/admin_repository_runtime.dart"],
 "admin_set_user_access":["lib/admin/core/admin_action_contracts.dart","lib/admin/core/admin_platform_access.dart"],
 "admin_stage_roster_import_intent":["lib/admin/core/admin_roster_gateway.dart","lib/admin/core/admin_roster_import.dart"],
 "admin_system_health":["lib/admin/admin_router.dart","lib/admin/core/admin_automations_page.dart","lib/admin/core/admin_detail_formatters.dart","lib/admin/core/admin_detail_runtime.dart","lib/admin/core/admin_detail_specs.dart","lib/admin/core/admin_evidence_mode.dart","lib/admin/core/admin_overview_runtime.dart","lib/admin/core/admin_runtime.dart"],
 "approve_payment_reconciliation_v2":["lib/admin/core/admin_repository_runtime.dart"],
 "archive_group":["lib/shared/repositories/collect_repository_group_actions.dart"],
 "create_contribution_intent":["lib/shared/repositories/collect_repository_contribution_actions.dart"],
 "create_mobile_support_request":["lib/shared/repositories/collect_repository.dart"],
 "create_private_group_with_owner_media_attested":["lib/shared/repositories/collect_repository_contribution_actions.dart"],
 "ensure_current_member_profile":["lib/shared/repositories/collect_repository_live_reader.dart"],
 "get_account_deletion_request_status_v1":["lib/features/privacy/privacy_transport.dart"],
 "get_account_deletion_review_status_v1":["lib/features/privacy/privacy_transport.dart"],
 "get_active_policy_document":["lib/shared/repositories/collect_repository_providers.dart"],
 "get_assisted_sms_consent_v1":["lib/shared/repositories/collect_repository_receipt_sms_actions.dart"],
 "get_collection_type_catalog":["lib/shared/repositories/collect_repository_providers.dart"],
 "get_current_account_deletion_request_status_v1":["lib/features/privacy/privacy_transport.dart"],
 "get_current_member_profile":["lib/shared/repositories/collect_repository_live_reader.dart"],
 "get_group_share_code":["lib/shared/repositories/collect_repository_group_actions.dart"],
 "get_notification_preferences_v2":["lib/shared/repositories/collect_repository_live_reader.dart"],
 "get_owner_group_health":["lib/shared/repositories/collect_repository_group_actions.dart"],
 "get_payment_reconciliation_v2":["lib/admin/core/admin_repository_runtime.dart"],
 "get_public_runtime_config":["lib/shared/repositories/collect_repository_providers.dart"],
 "is_platform_admin":["lib/admin/core/admin_evidence_mode.dart"],
 "join_group_by_share_code":["lib/shared/repositories/collect_repository_group_actions.dart"],
 "list_account_request_reasons":["lib/shared/repositories/collect_repository_providers.dart"],
 "list_current_member_collection_balances":["lib/shared/repositories/collect_repository_live_reader.dart"],
 "list_current_member_group_roster":["lib/shared/repositories/collect_repository_group_actions.dart"],
 "list_current_member_history_page":["lib/shared/repositories/collect_repository_live_reader.dart"],
 "list_current_member_recent_intents":["lib/shared/repositories/collect_repository_live_reader.dart"],
 "list_current_user_collections":["lib/shared/repositories/collect_repository_live_reader.dart"],
 "list_payment_reconciliations_v2":["lib/admin/core/admin_repository_runtime.dart"],
 "mark_notification_event_read":["lib/shared/repositories/collect_repository_notification_actions.dart"],
 "propose_payment_reconciliation_v2":["lib/admin/core/admin_repository_runtime.dart"],
 "record_sms_access_consent":["lib/shared/repositories/collect_repository.dart","lib/shared/repositories/collect_repository_contribution_actions.dart"],
 "register_notification_device":["lib/shared/repositories/collect_repository_notification_actions.dart"],
 "reject_payment_reconciliation_v2":[],
 "request_account_deletion":[],
 "request_account_deletion_v1":["lib/features/privacy/privacy_transport.dart"],
 "rotate_group_share_code_v2":["lib/shared/repositories/collect_repository_group_actions.dart"],
 "set_assisted_sms_consent_v1":["lib/shared/repositories/collect_repository_receipt_sms_actions.dart"],
 "set_notification_preferences_v2":["lib/shared/repositories/collect_repository_notification_actions.dart"],
 "transfer_group_ownership":["lib/shared/repositories/collect_repository_group_actions.dart"],
 "unregister_notification_device":["lib/shared/repositories/collect_repository.dart","lib/shared/repositories/collect_repository_notification_actions.dart"],
 "update_current_member_profile":["lib/shared/repositories/collect_repository.dart"],
 "update_rwanda_momo_group_profile":["lib/shared/repositories/collect_repository_contribution_actions.dart"],
});
function callerDisposition(op){
 const references=reviewedCallerReferences[op.name];need(Array.isArray(references),'Unreviewed caller disposition');
 return {state:references.length?'bounded_source_references_observed':'registered_contract_without_literal_reference_in_bounded_scope',
  references,reference_scope:'Reviewed Dart/Kotlin/Swift source only; includes compatibility SDK, adapters and display/fixture literals',
  reference_is_executed_call_proof:false,dynamic_or_indirect_consumers_excluded:false,
  disposition:'Registration is preserved. Literal presence is not installed usage; absence does not authorize retirement or prove a capability unused.'};
}
const listPermissions=Object.freeze({
 admin_list_collections:'collections.read',admin_list_members:'users.read',admin_list_users:'users.read',admin_list_non_member_users:'users.read',
 admin_list_payments:'payments.read',admin_list_collect_transactions:'payments.read',admin_list_payment_intents:'payments.read',admin_list_collect_reconciliations:'payments.read',
 admin_list_collect_ledgers:'ledger.read',admin_list_ledger:'ledger.read',admin_list_notifications:'notifications.read',admin_list_audit_logs:'audit.read',admin_list_settings:'settings.read',
 admin_overview:'overview.read',admin_runtime_config:'overview.read',admin_get_user:'users.read',admin_set_user_access:'users.manage',admin_system_health:'system_health.read',admin_get_queue_sla:'overview.read',
});
function operationMetadata(op,migrations,{momo=false}={}){
 need(reviewedOperations[op.source]?.includes(op.name),'Operation metadata needs explicit current source/name review: '+op.name);
 const p=profiles[op.source];need(p,'Unreviewed operation metadata profile');
 const permission=listPermissions[op.name]??(op.source==='privacy_retention_rpc.js'||op.source==='privacy.js'&&op.name.startsWith('admin_')?'privacy.review':op.source==='roster.js'?'roster.import':op.source==='evidence.js'?'payments.reconcile':null);
 let state=p.state,checks=[...p.checks],roles=op.authentication==='public'?[]:sessionRoles();
 if(op.source==='groups.js'&&['get_group_share_code','rotate_group_share_code_v2','create_private_group_with_owner_media_attested'].includes(op.name))roles.push(encryption('When this handler retains or reveals encrypted share/native source data'));
 if(op.source==='notifications.js'&&op.name==='register_notification_device')roles.push(encryption('When retaining an encrypted notification-device token; no transport key is implied'));
 if(momo&&op.name==='create_mobile_support_request')checks.push('Typed payment_review branch requires the current actor exact intent and matching collection; stable original request/session retry and commit-time intent/session ownership',
  'Typed payment_review retains context in existing support_requests only with zero financial/notification effects; generic support remains its existing separate branch');
 if(momo&&op.name==='get_current_member_payment_review_request_v1')checks.push('Read-only current actor, exact own intent and collection, current active principal/session and group membership checked in the same D1 batch',
  'Reconciles the original request ID across replacement sign-in without returning notes or references; received requires matching retained support and mutation receipt, absence is a current snapshot only',
  'Unknown or inconsistent state fails closed; retries retain the original request ID and immutable body, with zero financial or notification effects');
 if(['operator_notes.js','receipts.js','roster.js'].includes(op.source)||op.name==='set_assisted_sms_consent_v1')roles.push(encryption('When retaining or reading the private encrypted records used by this handler'));
 if(op.source==='native_integrity.js'){
  if(op.name==='record_sms_access_consent'){state='active';checks=['Current member principal/session','Verified current receiver matches exact phone hash','Self-only native SMS consent audit; not receipt-SMS consent or a send permit'];}
  else roles.push(encryption('When retaining/replaying encrypted native request/completion content'),requirement('PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON','Only for approved Google Play Integrity decode; policy/package/project/certificate/budget checks remain mandatory'));
 }
 if(op.source==='roster.js'&&['prepare-roster-import','roster-import-extract','admin_execute_roster_import_intent'].includes(op.name))roles.push(requirement('OPENAI_API_KEY','Only the PDF/image AI extraction branch, after exact ROSTER_AI_APPROVAL_JSON/SHA256, decoder service/build/project/organization/model policy admission; deterministic text/XLSX does not require it'));
 if(op.source==='privacy_retention_rpc.js')roles.push(policyPin());
 if(roles.some(r=>r.role==='DATA_ENCRYPTION_KEY'))roles.push(historicalEncryption());
 return {
  lifecycle:{state,scope:'source_implementation_and_explicit_dependencies',disposition:p.notes,live_configuration_or_deployment_asserted:false,installed_client_acceptance:false},
  supported_callers:op.source==='payments.js'?(op.name.startsWith('list_current_member_')||op.name==='create_contribution_intent'?['member_app']:['authorized_operator_api','admin_panel']):op.source==='privacy.js'?(op.name.startsWith('admin_')?['authorized_operator_api','admin_panel']:['member_app']):p.callers,caller_disposition:callerDisposition(op),
  authority_boundary:{entry:op.authentication,checks,permission:permission,source:[op.source,...(op.authentication==='public'?[]:['auth.js','mutations.js'])],metadata_grants_authority:false},
  service_boundary:operationServices(op),conditional_secret_requirements:roles,migration_dependencies:migrations,rollout_order:rolloutOrder,
 };
}
const operatorActions=Object.freeze(['list_pending','claim','get_claimed','confirm','record_send_start','record_outcome','release_claim','get_operation']);
function familyMetadata(row,migrations){
 const auth=row.authentication,roles=auth==='public'?[]:sessionRoles();let state='active',checks=[],notes=[],sources=[row.source];
 if(row.path==='/health')checks=['Public database availability/current BUILD_SOURCE_ID read; no business authority'];
 else if(row.path==='/privacy/account-deletion/**'){state='conditional';checks=['Public no-store presentation/assets','Actual intake/status uses current self-only Auth/privacy contracts; no anonymous deletion authority'];notes=['OTP delivery must be configured before verification; intake/review is not erasure'];sources.push('auth.js','privacy.js');}
 else if(row.path==='/v1/auth/**'){state='conditional';checks=['Action-specific real OTP/session/refresh/MFA contracts','Strict current identity-key ring and explicit no-registration purpose where selected','Replay/expiry/session/revocation and bot/source budgets'];roles.push(requirement('OTP_DELIVERY_TOKEN','Only when the configured outbound OTP_DELIVERY_URL relay is used'),requirement('TURNSTILE_SECRET','Only when TURNSTILE_REQUIRED is true'),encryption('Only when enrolling/verifying encrypted MFA factors'));sources.push('identity_keys.js','encryption.js');notes=['Phone/email/relay/provider availability is not inferred from source'];}
 else if(row.path==='/v1/security/challenge'){state='conditional';checks=['Public configured site-key presentation with origin/action/expiry binding','The site key is public; verification secret is required by the consuming Auth route only'];notes=['No CAPTCHA provider success or solving is asserted'];}
 else if(row.path==='/v1/query/public-collections')checks=['Public listed collection projection only; no member/private source authority'];
 else if(['/v1/query/notification-events','/v1/sync'].includes(row.path))checks=['Current bearer principal/session','Self-only events or authorized member/group synchronization projection'];
 else if(row.path==='/v1/evidence/:id?'){state='conditional';checks=['Authenticated evidence read/write with actual permission and source/group guards','Sensitive writes use fresh AAL2; decrypted reads revalidate live permission','Private retained object/hash/provenance, not provider settlement'];roles.push(encryption('When storing or reading private payment-evidence objects'));sources.push('auth.js','encryption.js','mutations.js');}
 else if(row.path==='/v1/receipts/:id'){state='conditional';checks=['Current bearer session and sms.raw.reveal permission','Recorded reason/audit and live authority recheck before returning decrypted raw evidence'];roles.push(encryption('When decrypting retained raw receipt evidence'));sources.push('auth.js','encryption.js');}
 else if(row.path==='/api/admin/**'){state='conditional';checks=['Action-specific origin-bound HttpOnly cookie/current approved account/link/role/capabilities','Fresh issued AAL2/original-session/source guards where the selected operation requires them','PLATFORM_API binding from Admin proxy is not a trusted service-role bypass'];roles.push(encryption('Only MFA or private-data actions needing encrypted records'));sources.push('admin_accounts.js','auth.js');notes=['EMAIL binding is conditional for existing invitation/recovery mail; no invented SMTP secret or configured delivery'];}
 else if(row.path.startsWith('/api/admin/sms/receipts')){state='conditional';checks=['Current origin-bound cookie, explicit principal link and capped live sms.read grant','Read-only canonical capture metadata, counted bounded pages, live authority guard','Preserved capture status and opaque device time; no parser/payment/provider or duplicate-reference facts invented','No raw reveal, extraction, assisted-SMS access or transport authority'];sources.push('admin_accounts.js','auth.js');notes=['Capture variant requires the paired Admin DTO successor and additive migration0013; legacy member/receiver sources are not fabricated'];}
 else if(row.path.startsWith('/api/admin/gateway/receipts')){state='conditional';checks=['Current origin-bound cookie, explicit principal link and capped live payments.read grant','Bounded read-only canonical capture metadata; live authority guard before D1 response','Exact capture status, opaque device time and explicit unknown review/transaction facts','No source reveal, review, payment association, provider finality or assisted transport authority'];sources.push('admin_accounts.js','auth.js','admin_sms_receipts.js');notes=['Requires the paired explicit Member capture DTO successor; no new grant or migration'];}
 else if(row.path.startsWith('/api/admin/notification-operator')){
  state='conditional';checks=['Current origin-bound cookie/principal/link/role and fresh issued AAL2','Original canonical/public session and immutable request/decision receipts; unknown is not failure or a send permit'];roles.push(encryption('When retaining or revealing encrypted destination/message data'));sources.push('admin_accounts.js','auth.js','mutations.js');
  if(row.path==='/api/admin/notification-operator')checks.push('list_pending requires assisted_sms.read; every other action assisted_sms.manage','One-use confirm/send-start content binding; lost acknowledgement does not reissue may_send');
  else if(['/api/admin/notification-operator/access','/api/admin/notification-operator/access/operations/:request_id','/api/admin/notification-operator/operations'].includes(row.path))checks.push('Current Owner plus admin_users.manage; exact self principal and original-session historical readback','Explicit self-grant/revoke compares booleans and monotonic immutable decision_revision, including no-op choices');
  else checks.push('Current Owner plus assisted_sms.manage; original request/session and current source/policy/materialization fences','Policy/history reads are not activation or fresh replay/send authority');
  notes=['Disabled without explicit current owner access/collection policy, valid destination consent and reconciled ledger source as applicable','No transport sender is supplied by these handlers; actual one-shot adapter/send/provider outcome remains separate'];
 }
 else throw new Error('Unreviewed route-family metadata: '+row.path);
 if(roles.some(r=>r.role==='DATA_ENCRYPTION_KEY'))roles.push(historicalEncryption());
 return {caller_disposition:{state:'source_route_family_contract',references:[row.source],reference_is_executed_call_proof:false,disposition:'Concrete method/authority/caller compatibility must be exercised separately; source metadata grants no caller access'},lifecycle:{state,scope:'source_implementation_and_explicit_dependencies',disposition:notes,live_configuration_or_deployment_asserted:false,installed_client_acceptance:false},supported_callers:row.path.startsWith('/api/admin/')?['admin_panel']:row.path==='/privacy/account-deletion/**'||row.authentication==='public'?['anonymous_public_client']:['/v1/evidence/:id?','/v1/receipts/:id'].includes(row.path)?['authorized_operator_api','admin_panel']:row.path==='/v1/auth/**'?['member_app','authorized_operator_api']:['member_app'],authority_boundary:{entry:auth,checks,source:[...new Set(sources)],metadata_grants_authority:false},service_boundary:familyServices(row),conditional_secret_requirements:roles,migration_dependencies:migrations,rollout_order:rolloutOrder};
}
const service=(name,kind,when)=>({name,kind,when,availability_or_authority_asserted:false});
const db=()=>service('DB','private_D1_binding','Current application schema and guarded primary reads/mutations; no direct client DB authority');
const privateMedia=when=>service('PRIVATE_MEDIA','private_R2_binding',when);
function operationServices(op){
 const dependencies=[db()];
 if(op.source==='receipts.js')dependencies.push(privateMedia('Retained encrypted SMS receipt object body'));
 if(op.source==='roster.js'){
  dependencies.push(privateMedia('Retained roster source object and current object integrity'));
  if(['prepare-roster-import','roster-import-extract','admin_execute_roster_import_intent'].includes(op.name))dependencies.push(service('ROSTER_DECODER','conditional_service_binding','PDF/image branch only, under exact separately approved decoder build/project/processor policy'),service('api.openai.com','conditional_outbound_provider','PDF/image branch only, approved processor/model/project/retention/spend policy and key'));
 }
 if(op.name==='verify-play-integrity')dependencies.push(service('oauth2.googleapis.com and playintegrity.googleapis.com','conditional_outbound_provider','Only after exact Google policy/service-account and request/budget admission'));
 if(op.source==='privacy_retention_rpc.js')dependencies.push(privateMedia('Only covered guarded object inventory/effects; external copy tasks remain blocked without exact approved outcomes'));
 return {entry_transport:op.authentication,service_role_or_metadata_bypass:false,dependencies};
}
function familyServices(row){
 const dependencies=row.path==='/v1/security/challenge'||row.path==='/privacy/account-deletion/**'?[]:[db()];
 if(row.path==='/v1/evidence/:id?'||row.path==='/v1/receipts/:id')dependencies.push(privateMedia('Retained encrypted private evidence objects'));
 if(row.path==='/v1/auth/**')dependencies.push(service('OTP_DELIVERY_URL','conditional_outbound_relay','Only configured accepted OTP relay; no real phone/email provider availability asserted'),service('challenges.cloudflare.com','conditional_outbound_provider','Only when TURNSTILE_REQUIRED is true'));
 if(row.path==='/api/admin/**')dependencies.push(service('EMAIL','conditional_send_email_binding','Existing team invitation/account-recovery mail when configured; no delivery proof'));
 if(row.path.startsWith('/api/admin/'))dependencies.push(service('PLATFORM_API','upstream_Admin_proxy_binding','Admin proxy delegates to this API using current cookie/origin authority; binding supplies no service-role bypass'));
 return {entry_transport:row.authentication,service_role_or_metadata_bypass:false,dependencies};
}
function momoFamilyMetadata(row,migrations){
 const admin=row.source==='admin_momo.js',pair=row.path==='/v1/momo/gateway/pair',ingest=row.path==='/v1/momo/gateway/ingest';
 const objects=ingest||row.path.includes('/transactions/')||row.path.includes('/sources/');
 const roles=admin?sessionRoles():[],sources=[row.source,'core.js'],dependencies=[db()];
 const checks=admin?[
  'Current origin-bound HttpOnly cookie, canonical principal link and live action-specific role/capabilities',
  'Fresh issued AAL2 on writes and source reveal; original-session/idempotency/source-revision guards on mutations',
 ]:pair?[
  'Unexpired 600-second pairing secret, installation ID and active immutable receiving binding/account/owner',
  'Same pairing and installation recover the exact credential; a second installation is refused',
 ]:[
  'Installation-bound credential is ingest/health scoped only; it has no member/admin session authority',
  'Non-revoked credential, active immutable binding/account, canonical owner and linked admin account are rechecked in guarded SQL',
 ];
 if(admin)sources.push('admin_accounts.js','auth.js','mutations.js');
 if(pair||objects){roles.push(encryption('Only when retaining/recovering the scoped credential or encrypting/revealing private retained evidence'),historicalEncryption());sources.push('encryption.js');}
 if(objects)dependencies.push(privateMedia('Exact encrypted retained SMS/payment evidence with object/hash integrity; not provider settlement'));
 if(ingest)checks.push('Exact raw envelope/capture/binding identity; raw source, capture metadata and processing obligation commit atomically');
 else if(row.path.endsWith('/status'))checks.push('Current-binding queue count and contact observation only; this status read updates last_contact_at');
 else if(row.path.endsWith('/heartbeat'))checks.push('Bounded pending count and oldest/last-source timestamps only; no raw message body or financial effect');
 else if(row.path.includes('/accounts/'))checks.push('Real provider/code/name; profile remains unverified until explicit versioned source-profile approval');
 else if(row.path.includes('/bindings/'))checks.push('Enrollment creates immutable account/SIM evidence and short-lived pairing; revocation withdraws credential authority while retaining source');
 else if(row.path.includes('/transactions/'))checks.push('Payer is separate from beneficiary; exact receiver/member/intent/version/conflict/historical-overlap guards',
  'Payment-check reads require payments.read/users.read/collections.read; valid typed own-intent/group context only, bounded pages, member reference/note explicitly unverified and no close/association/financial command',
  'Assignment links/records retained evidence only; existing independent proposer/reviewer command remains the sole contribution writer',
  'Conflict review requires payments.read/payments.write/sms.extract, fresh AAL2 and exact version/full bounded attempt set; only unlinked records, original immutable facts retained, later conflicts reflag');
 else if(row.path.includes('/sources/'))checks.push('Raw reveal requires sms.read plus sms.reveal, fresh AAL2, live authority recheck and audited reason',
  'Backfill/resolve/reparse require sms.read plus sms.extract; bounded cursor, immutable exact receiving-hash source resolution and retained attempt history',
  'Operator source correction/classification requires live sms.read/sms.extract and fresh AAL2, exact state/attempt/digest and supporting evidence; no accepted canonical or financial source linkage',
  'Same deterministic validation/canonical dedup and labelled immutable operator attempts; negative classification requires explicit source markers and cannot discard recognized incoming/reversal evidence',
  'Raw source and retained candidate evidence excerpts are returned only through the separately reasoned sms.reveal path; metadata lists contain digests/attempt IDs only');
 const references=admin?['lib/admin/core/cloudflare_admin_momo_page.dart']:['android/app/src/main/kotlin/app/cool/mobile/receiver_sms/MomoGatewayHttp.kt'];
 return {lifecycle:{state:'conditional',scope:'source_implementation_and_explicit_dependencies',disposition:[
  'Capture/processing/source assignment does not itself post a financial contribution, enable outbound notification transport or establish provider settlement',
  'Provider-profile accuracy, installed-phone behavior, deployed bindings and release/recovery acceptance remain separate',
 ],live_configuration_or_deployment_asserted:false,installed_client_acceptance:false},supported_callers:admin?['admin_panel']:['native_android_gateway'],
 caller_disposition:{state:'bounded_source_references_observed',references,reference_scope:'Reviewed current dedicated gateway/Admin source only',reference_is_executed_call_proof:false,dynamic_or_indirect_consumers_excluded:false,disposition:'Source references are not installed/hosted journey acceptance'},
 authority_boundary:{entry:row.authentication,checks,source:[...new Set(sources)],metadata_grants_authority:false},
 service_boundary:{entry_transport:row.authentication,service_role_or_metadata_bypass:false,dependencies},conditional_secret_requirements:roles,migration_dependencies:migrations,rollout_order:rolloutOrder};
}
function momoLegacyAliases(){return legacyAliases().map(row=>{
 const current={
  'collect-android-gateway':{replacements:momoRouteFamilies.filter(f=>f.source==='momo_gateway.js').map(f=>f.path),disposition:'Dedicated scoped gateway source routes now exist; old-wire equivalence and installed/provider acceptance are not asserted'},
  'parse-payment-sms':{replacements:[],disposition:'Internal scheduled/post-ingest structured extraction and authorized source reparse now exist; no standalone parser wire or old-wire equivalence is asserted'},
  'collect-receipt-exception-worker':{replacements:[],disposition:'Internal durable processing cases and explicit Admin source review now exist; no exact old-worker equivalence is asserted'},
  'collect-receipt-supervisor':{replacements:[],disposition:'Bounded scheduled durable-outbox recovery now exists in source; no old-supervisor or hosted scheduler equivalence is asserted'},
 }[row.name];
 return current?{...row,...current,source_provenance:[...row.source_provenance,'src/momo_gateway.js','src/momo_pipeline.js','src/admin_momo.js']}:row;
});}
const legacyDefinitions=Object.freeze([
 ['auth-send-whatsapp-otp',['/v1/auth/**'],'Current OTP/session relay boundary; WhatsApp delivery/equivalence is not asserted'],
 ['collect-android-gateway',[],'No exact standalone current gateway route; capability equivalence/disposition remains separately reviewed'],
 ['collect-notification-operator',['/api/admin/notification-operator'],'Current assisted-SMS cookie interface counterpart; no actual sender/provider delivery inferred'],
 ['collect-receipt-exception-worker',[],'No exact active current worker counterpart or scheduler; capability equivalence is not asserted'],
 ['collect-receipt-supervisor',[],'No exact active current supervisor counterpart or scheduler; capability equivalence is not asserted'],
 ['dispatch-notifications',[],'No current dispatch wire interface; stored device/events/preferences are not transport dispatch'],
 ['ingest-payment-sms',['/v1/functions/ingest-payment-sms','/v1/functions/ingest-client-sms'],'Current request-bound receipt ingestion aliases; receipt evidence never implies settlement'],
 ['parse-payment-sms',[],'No separate current parser wire route; ingestion/decoder equivalence is not asserted'],
 ['prepare-roster-import',['/v1/functions/prepare-roster-import','/v1/functions/roster-import-upload','/v1/functions/roster-import-extract','/v1/functions/roster-import-commit'],'Current retained source/import family; AI/provider gates remain independent'],
 ['reconciliation-finalize',['/v1/rpc/approve_payment_reconciliation_v2'],'Current evidence reconciliation counterpart only; no independent provider-finality equivalence'],
 ['send-notification',[],'No current send wire interface; no transport is enabled by inventory'],
 ['verify-play-integrity',['/v1/functions/verify-play-integrity'],'Current bearer/request-bound Google admission counterpart; configured/device/provider acceptance is separate'],
]);
function legacyAliases(){return legacyDefinitions.map(([name,replacements,disposition])=>({
 name,path:'/functions/v1/'+name,method:'POST',lifecycle:'retired_wire_alias',scope:'old_prefix_at_current_Cloudflare_origin_only',
 source_disposition:'Intentionally unhandled by current index routing; a valid current session reaches not_found, while unauthenticated requests may fail earlier authentication',
 replacements,disposition,capability_equivalence:'not_asserted',capability_removed_by_metadata:false,
 source_provenance:['src/index.js','src/operations.js'],historical_inventory_provenance:{path:'docs/release/critical-review-2026-10-01/backend-inventory.json',sha256:'87e899985450a429d3384bcc2abefb51ae10788bed48d6226c33c23a6405a923'},
 hosted_denial_acceptance_carried_by_manifest:false,old_Supabase_project_state_asserted:false,
 }));}
const metadataFields=Object.freeze(['lifecycle','supported_callers','caller_disposition','authority_boundary','service_boundary','conditional_secret_requirements','migration_dependencies','rollout_order']);
const baseOperation=row=>Object.fromEntries(['kind','name','method','path','authentication','source'].map(k=>[k,row[k]]));
const currentMigrationReview=Object.freeze({
 migration:'0013_sms_receipt_metadata_read.sql',sha256:'724f94ab29413b6e1e69c25678078f1e3161d8b0b7bcfe3cd20b1fd25cbc146b',
 scope:'Source-only intended additive12-to13 effects; actual target data/grants require separate observation',
 previous_fresh_capability_definitions:60,expected_fresh_capability_definitions:63,
 added_role_definitions:Object.freeze(['owner','admin','staff'].map(role=>Object.freeze({role,permission:'sms.read'}))),
 existing_grant_adoption:'INSERT OR IGNORE only active owner/admin/staff accounts linked by admin_principal_links to active canonical users; unlinked/invited/revoked/suspended principals are not adopted',
 added_index:'sms_receipts_metadata_order',new_tables:0,retention_classes:91,
 raw_extract_or_assisted_access_granted:false,actual_target_migration_or_grants_observed:false,approval_supplied:false,
});
const momoMigrationReview=Object.freeze({
 previous_profile:'complete13',predecessor_inventory_sha256:predecessorInventory.sha256,
 scope:'Source-only candidate13-to15 effects; no target data/grant migration, recovery or release approval is supplied',
 additive_migrations:[
  {migration:'0014_momo_pipeline.sql',sha256:momoMigrationDigests['0014_momo_pipeline.sql'],new_tables:7,added_role_definitions:[]},
  {migration:'0015_momo_gateway_allocation.sql',sha256:momoMigrationDigests['0015_momo_gateway_allocation.sql'],new_tables:6,
   added_role_definitions:['owner','admin'].flatMap(role=>['sms.reveal','sms.extract'].map(permission=>({role,permission})))},
 ],
 previous_fresh_capability_definitions:63,expected_fresh_capability_definitions:67,previous_fresh_application_tables:81,expected_fresh_application_tables:94,
 existing_grant_adoption:'Only active owner/admin accounts linked to active canonical users; only the four new owner/admin sms.reveal/sms.extract role definitions are adopted',
 financial_writes:'No migration posts ledger contributions; assignment links evidence and the existing independent review command remains the financial writer',
 assisted_sms_authority_added:false,actual_target_migration_or_grants_observed:false,approval_supplied:false,
});
const momoRuntimeBoundary=Object.freeze({
 handler_exports:['fetch','scheduled'],configured_crons:['* * * * *'],configured_ai_binding:'AI',
 configuration_scope:'Selected current wrangler source only; deployed configuration and scheduler readback remain separate',
 inbound_service_role_bypass:false,functions_are_scheduler_evidence:false,
 scheduler_acceptance:'Source scheduled/post-ingest durable-outbox recovery exists; actual deployment, scheduler readback, processing and provider accuracy are unverified',
 processing:{source:['index.js','momo_pipeline.js'],default_jobs_per_drain:5,maximum_jobs_per_drain:20,lease_seconds:180,default_attempt_budget:4,
  operator_retry_budget_extension_preserves_attempts:true,pause_variable:'MOMO_PROCESSING_PAUSED',pause_value:'true',pause_preserves_raw_capture:true,
  pause_scope:'Automatic drain only; explicit fresh-MFA operator source-review commands do not invoke an AI provider and remain separately authorized',
  authority:'Private database outbox and approved active receiving source profile/sender; no caller-supplied service-role bypass',
  dependencies:[db(),privateMedia('Encrypted source integrity before extraction'),service('AI','conditional_Workers_AI_binding','Approved active source profile and sender only; raw sender/body are submitted for structured extraction')],
  ai:{binding:'AI',is_api_key_secret:false,model_id:'@cf/meta/llama-3.3-70b-instruct-fp8-fast',schema_version:'momo-extraction.v1',prompt_version:'momo-evidence.v1',parser_version:'momo-validation.v1',response_format:'json_schema',deterministic_source_validation:true},
  canonical_transaction_before_beneficiary:true,immutable_attempt_history:true,financial_posting:false,outbound_notification_transport:false,
  actual_processing_or_provider_accuracy_asserted:false},
});
// Explicit auth17 source-only successor. Predecessor profiles remain exact and
// are never relabeled, rewritten or treated as release/provider approval.
async function auth17MetadataSidecar(path,name){
 try{
  const info=await lstat(path);if(!info.isFile()||info.isSymbolicLink()||info.size<26||info.size>1048576||name.length<=2)return false;
  const companion=await lstat(resolve(path,'..',name.slice(2)));if(companion.isSymbolicLink()||!companion.isFile()&&!companion.isDirectory())return false;
  const bytes=await readFile(path);if(bytes.length!==info.size||bytes.readUInt32BE(0)!==0x00051607||bytes.readUInt32BE(4)!==0x00020000)return false;
  const count=bytes.readUInt16BE(24),tableEnd=26+count*12;if(!count||tableEnd>bytes.length)return false;
  const ids=new Set(),spans=[];
  for(let i=0;i<count;i++){const start=26+i*12,id=bytes.readUInt32BE(start),offset=bytes.readUInt32BE(start+4),length=bytes.readUInt32BE(start+8);
   if(!id||ids.has(id)||offset<tableEnd||offset+length>bytes.length)return false;ids.add(id);if(length)spans.push([offset,offset+length]);}
  spans.sort((a,b)=>a[0]-b[0]);return spans.every((span,i)=>!i||spans[i-1][1]<=span[0]);
 }catch{return false;}
}
const auth17Profile='auth17_candidate';
const auth17ProducerSha256=sha(await readFile(fileURLToPath(import.meta.url)));
const auth17SourceDigests=Object.freeze({
 "admin.js": "6205e836e6f6dbdb0bb431466f3a3af4592245deca2745d8adff6b3736a10235",
 "admin_account_support/NOBLE-LICENSE.txt": "4f221aee6e072336700c408c68ab3b96a3fc09f6aebe6f48f1bd99e5ef13faec",
 "admin_account_support/bootstrap-owner.mjs": "84e4a302f653284bbd909dfe81aa0cface4ef88e84bbcec9b17f134e742fb359",
 "admin_account_support/emails.js": "94a0b2ccbb367106ad0f4db83520906e77a9a04add06a33915c857e9d9b06509",
 "admin_account_support/provenance.json": "5c8ed7d0d1cb32c4ea56ee3e4acd7828f1c93040d659dbbe06277c23d8131fa7",
 "admin_account_support/security.js": "1c69619b364fca9eb58022aed6ecb945a053abc342ffeb0bc13647a162be8ede",
 "admin_accounts.js": "5e269168be2276ed25554c85547ecbd4aea53b56a5977a797214c4193462e2ec",
 "admin_bridge.js": "6e14c60a1ca195b73e8822c7850dc4e2c49106255b2a35a58991acfc894cbabd",
 "admin_member_receipts.js": "3e1a5795ba3e91c186a1925cfb4641cc013435b2afebb75008a40bfe1c924f22",
 "admin_momo.js": "9b645e58ae049a1c236211e0d7d841f937a427a07074d37797d11c36596b8a50",
 "admin_privacy.js": "21c947bc4ce7d37644a9bd429cc71ffddafc222355c8da6737352756d8ccd12a",
 "admin_reconciliation_reads.js": "8a8c7a0b00fc55386df80f8cebef6d9bf74fdce5848873705d27086009a5c287",
 "admin_records.js": "f3e30d8c6c21cdc297abd60b6cacf82e8c604e44909efa44f8e52a71269ac1cd",
 "admin_search.js": "00473c46f0b06aaf77d1d6cb6ee484199c76f757f1722aa82421e996f940aff4",
 "admin_sms_receipts.js": "ca190dd5c3af2bf50504a0bfa5c861b663cedf72321b350813996975da81e734",
 "admin_sync.js": "f698744d0713d701ae732114d5c1e8047c4971144c844420f0105f45bb1a10dc",
 "auth.js": "4738350027bb080d59f87d96a078bcd7041b4278d8f52fe4691bcbeb4f1d20f7",
 "challenge.js": "4e8325c1a01718dde06e5062097a37a216682392afde5b6c2db35dd29ea3a11d",
 "core.js": "18ce95c133a4895d13475338089fb00c9ba4c9283ee72c7d4d6f88ae8ea8723e",
 "email_delivery.js": "9406281fe5fab56ef5ed3082b0ab8a6ef4f5506f6bde50c8146a959ea87446cf",
 "encryption.js": "ee5935065cd86b486b268a5da7026bcfaf123068e866f0ff56347f8582326e1c",
 "evidence.js": "a471a6a0f57d2645d5e3aefb0c36ed4b8dae284138ddac04e1a398c7658d3f5f",
 "google_auth.js": "8ce95c45e665fadaa05da42b2618abdae7fe3ead17978e4a0f58d72d2edf1418",
 "groups.js": "cc59f090e0e7cbe26d68af17e83feb37eb05fa3adccc00881134e3ab24dfafa7",
 "identity_keys.js": "c0c9fbfb48b44c72c7192acd3853644349a000ba3e7fbf62fdc11037d5f6d4f7",
 "index.js": "cce6e539a9f103b2528f7dc9724c19e5301f4953b2826ac5706dbb18d0c54ec4",
 "member_history.js": "69d7c02ccac051daa6660cc0ab1e27893f2f8429b1d865c8b4ad089542d96eb3",
 "momo_gateway.js": "ba78b06bfdd394ba639981d4753a55b990b67a476decc36dba5368a5ef908bdf",
 "momo_pipeline.js": "b99baf0e5c0a735a14fb54b2d5e09acae1e236ad0739733d62a8b75aad75a413",
 "mutations.js": "7415b73eff96e0e96468039262d278e161f7753b31ff7ef59ff789a2761c6dc3",
 "native_integrity.js": "6a87742a78be16765e51a3bc5a7ca9132ba0d6c72eb9195a95e84e7649ae52a4",
 "notification_operator.js": "ab0eb97ecb5aadb31865d4d7698d293d6d83cea90d86c06cd554f54819d7d14a",
 "notification_operator_consent.js": "85ef56454c325532b64b7c49193e021d2fde8e016d8601d3d8648dbcb6ab76db",
 "notification_operator_management.js": "1535538c18ced81cfdc38b28ae9cb0eb0984d5dcf0449b7cc49d11fd0649b72e",
 "notifications.js": "6e901ce25913075dc89f4dcd26419a371bdb82025c07f9804dc8737bbf7b9131",
 "observability.js": "46aae2218b24c3b110ab9817db6990504a3f0bd3ce03ed6cfa0ab2dce448297f",
 "operations.js": "17549b736c0e731c9f9dd36bfa9d9f7614c47edabe9501c2083a721a3f0e7be9",
 "operator_notes.js": "9fb388bd916cc7bc1ad0ed294591bf01b77fe0f493f3575ae91dcbfafb9920a3",
 "payments.js": "61518365f2597d051bc8a9bd771ffc3ef59a45b59a43841f1e5da9c7f19424ca",
 "privacy.js": "a9388a581eddf82d46f34f7b94c7ce4ee8d915b1d8085f8b1611e81943cb2f7a",
 "privacy_portal.js": "b3854f2528e4516826576acee9e264808bcc67453dfbcf00284d282b983b8313",
 "privacy_portal_assets.js": "01fd23b0449d13c0959d21c54ef46d0a1cb973d898c68e92a6861051c3574100",
 "privacy_retention.js": "09742d7379274c6681ca89808186132f3dbf0e9bea34651522dd5cdd8b7e8bac",
 "privacy_retention_catalog.js": "d08d64d7efd2b9389f2d2a2c12c28fc0c3f125024a61e654dd1cb57b44af4d5d",
 "privacy_retention_chunks.js": "b6c3d9cab1d5fac8e026e36c251e12731a26fc364536c11543640c3c83c34066",
 "privacy_retention_policy.js": "7a1d0a7fa0b136a876b2b45b8decc5e82f0b6a386a9aeeb08d3987ae5f824410",
 "privacy_retention_rpc.js": "41ca1fb58b4440f5ff744f678978d8af901348dfd1c366be66f83732415e29f3",
 "privacy_retention_tasks.js": "8e9caf7f8bc398bbc078197be0f6baafc597553500e69ff3448e51bb35f3ff8f",
 "receipts.js": "ac6e718aaf96ca2515d63088a4b05a58ee2c1357423287ae9273c561fe3d71c0",
 "roster.js": "6033502dc040947b1a635b6ad5ba7d01a0caa0c5c095f6bf8c8d33c8bbaca0e8",
 "sync.js": "436f820c6795a77fd25b8450c937bd6396d934207dc7879d136d1a1bdb499f54",
 "user_access.js": "76abb6576d7dddd1dcb710a925e337182a6e429680283b518e0e4de0a20c118b"
});
const auth17MigrationDigests=Object.freeze({
 "0001_core.sql": "299b0358d2545a6bbc3f6dc004eadb19168ba9d72131368d0e814165ab6b6455",
 "0002_auth.sql": "2106f1db68d8bd21a540c747079da4df032842ae42f38979be7f687e8af0b2a7",
 "0003_mutation_guards.sql": "c1a4aa837663235af26b41977a531db33e9c61b18006ca167cb7eca486562744",
 "0004_privacy.sql": "e7ba2d670e3620e7c4042f6291fa62c83407df7270987d8df5ac6431e8766ef3",
 "0005_ingestion.sql": "b8974163e228cbc776ae88378c7fb3aece26b560841e2f7f76b7a53f254c75f7",
 "0006_admin_accounts.sql": "ed56c5d5da367cccbc877848ffa0cbdb418a5cb6ef58a443318d2b6b7d794ba0",
 "0007_admin_bridge.sql": "9668f1394a24dc18c75eed61d98f24c598dc8b763103c3144fef25988e0ef3b2",
 "0008_receipt_capture.sql": "247771ccb826bb48e894dc1de703ce1cb0706c18ece1620557447faa673449fd",
 "0009_operator_notes.sql": "e7ee374a172bb818c0a382e1e94fdc467f776f05bc31789d1215484d4fbce970",
 "0010_privacy_retention.sql": "94d7ec5146a4ef3e4721cb185a4700edea76c3e72e1cf992dd9fcb2d2e1571d2",
 "0011_auth_identity_keys.sql": "7e315ad76f45a6e5735d5ee42e7ae94f931e413de37b329a009f31ce9027e8f0",
 "0012_notification_operator.sql": "f6bfc6603505b8a29338d845707b3347c8c767d230f41f8347a1979d4c70bac7",
 "0013_sms_receipt_metadata_read.sql": "724f94ab29413b6e1e69c25678078f1e3161d8b0b7bcfe3cd20b1fd25cbc146b",
 "0014_momo_pipeline.sql": "b31e0590ad4d0b5b2e6acf3c6c069b84ec1cbe8d003eb69f7c5d5f306a3a63d6",
 "0015_momo_gateway_allocation.sql": "c84e3ea9330c0506781072173af7f5b9a7324017943ca58a967e399df515c422",
 "0016_google_auth.sql": "4b225302c08f6b1839dd14256552f0de122a8edb58d22ff05a3e50c44542ca61",
 "0017_admin_email_otp.sql": "9485792aeff5157859335c629f8a2e96f8da6bb957e1a85922c99c78168f2743"
});
const auth17WranglerSha256='1fa3792055ebeb9d14f09563cdc6b30afc127086ee7ebcb2dd482391f2702d40';
const auth17ConfigurationSource='wrangler.auth17-source.jsonc';
const auth17Predecessors=Object.freeze([predecessorInventory,
 {path:'operations-manifest-momo15.json',profile:momoProfile,sha256:'ad11e18f723b8f0bf9bf6c98aa9b59fb71b55629cedc45ac42502112730dc258',approval_or_release_acceptance_inherited:false}]);
const auth17RoleSources=Object.freeze({...roleSources,
 AUTH_JWT_SECRET:['auth.js','admin_accounts.js'],AUTH_TOKEN_HASH_SECRET:['auth.js','admin_accounts.js'],
 GOOGLE_CLIENT_SECRET:['google_auth.js']});
const auth17Requirement=(role,when)=>({role,when,source:auth17RoleSources[role],configured_or_approved_by_manifest:false});
const auth17RouteFamilies=Object.freeze([
 {path:'/v1/auth/otp',source:'auth.js',authentication:'identity_otp_request_action_specific',methods:['POST'],actions:[{method:'POST',path:'/v1/auth/otp',identities:['phone','email'],no_registration_purpose_supported:true}]},
 {path:'/v1/auth/verify',source:'auth.js',authentication:'single_use_identity_bound_otp',methods:['POST'],actions:[{method:'POST',path:'/v1/auth/verify',issued_surface:'retained_challenge_surface',assurance_level:1}]},
 {path:'/v1/auth/google/start',source:'google_auth.js',authentication:'origin_captcha_rate_and_client_pkce_bound_start',methods:['POST'],actions:[{method:'POST',path:'/v1/auth/google/start',surface:'member',provider_scopes:['openid','email']}]},
 {path:'/v1/auth/google/callback',source:'google_auth.js',authentication:'single_use_state_nonce_provider_pkce_and_signed_id_token',methods:['GET'],actions:[{method:'GET',path:'/v1/auth/google/callback',ambient_cookie_authority:false,session_tokens_returned:false}]},
 {path:'/v1/auth/google/exchange',source:'google_auth.js',authentication:'single_use_handoff_and_client_pkce',methods:['POST'],actions:[{method:'POST',path:'/v1/auth/google/exchange',surface:'member',assurance_level:1,admin_grants_issued:false}]},
 {path:'/api/admin/auth/otp',source:'admin_accounts.js',authentication:'same_origin_owner_approved_explicit_principal_email',methods:['POST'],actions:[{method:'POST',path:'/api/admin/auth/otp',unknown_account_exception:'admin_access_not_approved',automatic_registration:false}]},
 {path:'/api/admin/auth/verify',source:'admin_accounts.js',authentication:'same_origin_single_use_admin_account_otp',methods:['POST'],actions:[{method:'POST',path:'/api/admin/auth/verify',issued_surface:'admin_cookie',assurance_level:1,invitation_activation:'only_after_valid_current_otp'}]},
 {path:'/api/admin/team/invite',source:'admin_accounts.js',authentication:'current_owner_cookie_admin_users.manage_fresh_aal2',methods:['POST'],actions:[{method:'POST',path:'/api/admin/team/invite',permissions:['admin_users.manage'],fresh_aal2:true,owner_only:true,roles:['admin','staff'],invitation_is_session:false}]},
 {path:'/api/admin/team/:id/resend',source:'admin_accounts.js',authentication:'current_owner_cookie_admin_users.manage_fresh_aal2',methods:['POST'],actions:[{method:'POST',path:'/api/admin/team/:id/resend',permissions:['admin_users.manage'],fresh_aal2:true,owner_only:true,target_status:'invited',invitation_is_session:false}]},
]);
const auth17MigrationReview=Object.freeze({
 previous_profile:'complete13',predecessor_inventory_sha256:predecessorInventory.sha256,
 scope:'Exact source-only13-to17 effects; target data/grants, recovery, provider and release approval require separate readback and acceptance',
 additive_migrations:[...momoMigrationReview.additive_migrations,
  {migration:'0016_google_auth.sql',sha256:auth17MigrationDigests['0016_google_auth.sql'],new_tables:2,added_role_definitions:[]},
  {migration:'0017_admin_email_otp.sql',sha256:auth17MigrationDigests['0017_admin_email_otp.sql'],new_tables:1,added_role_definitions:[]}],
 previous_fresh_capability_definitions:63,expected_fresh_capability_definitions:67,previous_fresh_application_tables:81,expected_fresh_application_tables:97,
 existing_grant_adoption:momoMigrationReview.existing_grant_adoption,
 google_identity:'Stable verified Google sub links only to unique active Gmail/Workspace-authoritative email; no phone-only merge or Admin grant',
 admin_invitation:'An explicitly approved linked invited Admin activates only after valid account/version/origin-bound OTP; no migration activates staff',
 financial_writes:momoMigrationReview.financial_writes,assisted_sms_authority_added:false,actual_target_migration_or_grants_observed:false,approval_supplied:false,
});
const auth17Rollout=Object.freeze({migration_order:Object.keys(auth17MigrationDigests).sort(),release_order:rolloutOrder,additive_migration_review:auth17MigrationReview,
 instruction:'Review and admit the frozen combined source/config/schema17 tuple and compatible clients; read back target schema/config and verify real email/OAuth before reporting activation. This proposal supplies no approval.',approval_supplied:false});
const auth17RuntimeBoundary=Object.freeze({
 ...momoRuntimeBoundary,configured_crons:[],configured_ai_binding:null,
 scheduler_acceptance:'Scheduled handler exists in source, but this exact candidate omits cron and AI and sets MOMO_PROCESSING_PAUSED=true; no scheduler or AI activation is admitted',
 processing:{...momoRuntimeBoundary.processing,automatic_drain_paused:true,configured_ai_binding:null},
 authentication:{native_email_binding:'AUTH_EMAIL',legacy_email_binding:'EMAIL',sender:'info@ikanisa.com',
  native_email_binding_configured:true,actual_email_sender_or_delivery_verified:false,
  google_enabled_by_selected_configuration:false,actual_google_credentials_verified:false,
  member_surface_google_only:true,admin_otp_assurance_level:1,staff_mutations_require_current_owner_fresh_aal2:true,
  provider_activation_approval_supplied:false},
});
const auth17FingerprintsEqual=(left,right)=>canonical(Object.entries(left).sort(([a],[b])=>a.localeCompare(b,'en')))===canonical(Object.entries(right).sort(([a],[b])=>a.localeCompare(b,'en')));
function auth17Operation(op,migrations){
 const row={...op,...operationMetadata(op,migrations,{momo:true})};
 if(op.name==='ingest-client-sms')row.caller_disposition={...row.caller_disposition,state:'bounded_source_references_observed',references:[
  'lib/shared/repositories/collect_repository_contribution_actions.dart','android/app/src/main/kotlin/app/cool/mobile/receiver_sms/MemberSmsJobs.kt']};
 if(op.source==='receipts.js'){
  row.authority_boundary.checks=['Current original active member/session; explicit latest Android capture consent checked inside the committing D1 batch',
   'Ordinary capture has no receiving wallet, group, gateway binding, provider profile or native-integrity prerequisite',
   'Exact retained encrypted raw sender/body, device time and completeness; immutable envelope/body identity and retained ACK',
   'Per-member capture budgets60/minute and1000/day; consent withdrawal or session revocation wins before commit',
   'Explicit legacy receiving/native-capability branch retains verified receiver and one-use sms.ingest admission',
   'No balance/financial effect from upload; optional processing schema enqueues unresolved source only'];
  row.lifecycle.disposition=['Ordinary unverified member capture and explicit legacy provider-backed admission are separate source branches',
   'Android permission/device/provider acceptance and actual release delivery remain separately verified'];
  row.admission_branches={ordinary_member_capture:{when:'receiver_momo_number and native_capability both absent',
   consent:'latest explicit enabled android_* capture consent/current member and original session',
   receiver_wallet_required:false,group_required:false,gateway_binding_allowed:false,provider_or_native_integrity_required:false,
   budgets:{per_minute:60,per_day:1000},capture_works_through_schema13:true,financial_effects:0},
   legacy_receiver_capability:{when:'explicit receiving/native-capability fields supplied',verified_receiver_required:true,one_use_capability:'sms.ingest',conditional_google_policy_preserved:true}};
 }
 if(op.name==='record_sms_access_consent'){
  row.authority_boundary.checks=['Current active member principal/session and explicit enabled boolean',
   'Ordinary Android capture consent omits momo_number_hash and requires android_* build_channel; no verified wallet prerequisite',
   'Explicit legacy momo_number_hash branch retains current verified-receiver check',
   'Immutable request/session consent audit; later explicit withdrawal wins; no group-attestation or financial/send permit'];
  row.admission_branches={ordinary_capture:{momo_number_hash_absent:true,build_channel:'android_[a-z0-9_]+',verified_wallet_required:false},
   legacy_receiver:{momo_number_hash_supplied:true,verified_receiver_required:true}};
 }
 return row;
}
function auth17Family(row,migrations){
 if(!auth17RouteFamilies.includes(row)){
  const metadata=momoRouteFamilies.includes(row)?momoFamilyMetadata(row,migrations):familyMetadata(row,migrations);
  if(['/v1/auth/**','/api/admin/**'].includes(row.path)){
   metadata.authority_boundary.source.push('email_delivery.js');
   if(row.path==='/api/admin/**')metadata.authority_boundary.checks.push('Authenticated cookie MFA setup labels use the approved Admin account email without copying it into the separate canonical principal or changing secret/issuer/algorithm');
   metadata.authority_boundary.checks.push('Auth17 explicit leaf contracts separately describe member email/Google, approved Admin OTP and fresh-owner-MFA staff invitations');
   metadata.service_boundary.dependencies=metadata.service_boundary.dependencies.filter(item=>item.name!=='EMAIL');
   metadata.service_boundary.dependencies.push(service('AUTH_EMAIL or legacy EMAIL','conditional_native_email_binding','Configured verified sender and acknowledged messageId; no fallback after unknown send, local simulators refused'));
   metadata.lifecycle.disposition=['Native email and Google availability are not established by source/configuration; explicit auth17 leaves retain their own identity, grant and provider requirements'];
  }
  return {...row,...metadata};
 }
 const google=row.source==='google_auth.js',admin=row.path.startsWith('/api/admin/'),invite=row.path.includes('/team/');
 const checks=google?[
  'GOOGLE_AUTH_ENABLED, real configured client ID/secret and exact HTTPS redirect; no client secret in app/browser assets',
  'Single-use server state, nonce and provider PKCE; separate client PKCE and state-bound native/web handoff; replay/expiry enforced',
  'RS256 Google JWKS signature, issuer/audience/authorized-party/iat/exp/nonce/verified authoritative Gmail or Workspace email',
  'Stable Google sub, unique active email linkage, current active principal, no phone-only merge and no Admin grants',
  'Exchange consumes handoff atomically and issues only member AAL1 Collect session/rotating refresh; callback returns no session token',
 ]:admin?[
  'Exact allowed Admin origin, same-origin mutation and HttpOnly Secure SameSite=Strict cookie boundaries',
  'Only owner-preapproved admin_users and explicit admin_principal_links; member email equality never grants Admin authority',
  ...(invite?['Current owner plus live admin_users.manage, real issued AAL2 and freshness checked in committing owner guard',
    'Create or resend invitation only; mail points to Admin login and never creates a session or skips OTP activation']:
   ['Keyed recipient-email/account/principal/origin/role/auth-version/challenge-version OTP, five-minute expiry, five guesses and atomic sixty-second cooldown',
    'Current account status/email/link/role/principal access/grants rechecked in atomic claim; invited activation precedes new linked AAL1 cookie session',
    'Unknown/unapproved email gets typed contact-super-admin exception; no automatic account creation',
    'Valid OTP is single-use AAL1; real TOTP and fresh owner MFA remain required for staff administration']),
 ]:[
  'Exactly one canonical phone/email identity, retained challenge surface and explicit registration policy/purpose',
  'Cloudflare-native email or configured existing relay, HMAC single-use code, identity/source budgets and expiry/attempt limits',
  'Origin/Turnstile action and host when enabled; current user access and Admin grants remain action-specific',
  'Provider acknowledgement uncertainty retains original challenge and cooldown; never automatic resend or false delivery claim'];
 const sources=[row.source,'auth.js',...(google?['encryption.js']:['email_delivery.js',...(admin?['admin_account_support/emails.js']:['identity_keys.js'])])];
 const roles=[...sessionRoles()];
 if(google)roles.push(auth17Requirement('GOOGLE_CLIENT_SECRET','Only when Google sign-in is explicitly enabled with its real reviewed OAuth client'),encryption('When retaining the encrypted provider PKCE verifier'),historicalEncryption());
 else if(!admin)roles.push(requirement('OTP_DELIVERY_TOKEN','Only when phone/email actually uses the configured existing relay'),requirement('TURNSTILE_SECRET','Only when TURNSTILE_REQUIRED is true'));
 const dependencies=[db()];
 if(google)dependencies.push(service('accounts.google.com','conditional_OIDC_authorization_provider','Only enabled configured OAuth flow'),service('oauth2.googleapis.com/token','conditional_OIDC_code_exchange','Server-side exact client/redirect/provider PKCE'),service('www.googleapis.com/oauth2/v3/certs','conditional_Google_JWKS_provider','RS256 exact issuer/audience/nonce verification'));
 else dependencies.push(service('AUTH_EMAIL or legacy EMAIL','conditional_native_email_binding','Configured sender, bounded message and acknowledged messageId; local simulators refused and no fallback after uncertainty'));
 if(!admin&&!google)dependencies.push(service('OTP_DELIVERY_URL','conditional_outbound_relay','Existing configured WhatsApp/explicit email relay'),service('challenges.cloudflare.com','conditional_Turnstile_provider','Only when TURNSTILE_REQUIRED is true'));
 return {...row,lifecycle:{state:'conditional',scope:'source_implementation_and_explicit_dependencies',disposition:['Exact source/configuration only; real sender/OAuth/deployed/provider/browser/device acceptance is separate'],live_configuration_or_deployment_asserted:false,installed_client_acceptance:false},
  supported_callers:admin?['admin_panel']:['member_app'],caller_disposition:{state:'source_route_family_contract',references:[row.source],reference_is_executed_call_proof:false,disposition:'Explicit HTTP method and current authority must be exercised independently; no release approval supplied'},
  authority_boundary:{entry:row.authentication,checks,source:[...new Set(sources)],metadata_grants_authority:false},
  service_boundary:{entry_transport:row.authentication,service_role_or_metadata_bypass:false,dependencies},conditional_secret_requirements:roles,migration_dependencies:migrations,rollout_order:rolloutOrder};
}
function assertAuth17ManifestMetadata(manifest){
 need(canonical(Object.keys(manifest).sort())===canonical(['schema_version','metadata_version','profile','predecessor_inventories','configuration_sha256','configuration_source','service','operation_scope','registration_is_provider_availability','whole_endpoint_acceptance','metadata_is_source_only','metadata_grants_authority','migration_dependencies_scope','callers','secret_role_sources','operations','route_families','retired_wire_aliases','runtime_boundaries','rollout','producer','source_sha256','migrations_sha256'].sort()),'Auth17 refuses unknown top-level metadata or approval fields');
 need(manifest.service==='collect-platform-api','Auth17 service identity changed');
 need(manifest.schema_version===1&&manifest.metadata_version===3&&manifest.profile===auth17Profile,'Unknown auth17 endpoint metadata schema');
 need(canonical(manifest.predecessor_inventories)===canonical(auth17Predecessors),'Auth17 must retain exact predecessor provenance without inherited approval');
 need(manifest.configuration_sha256===auth17WranglerSha256,'Auth17 exact no-AI/no-cron candidate configuration changed');
 need(manifest.configuration_source===auth17ConfigurationSource,'Auth17 requires its explicit fixed source-configuration role');
 need(auth17FingerprintsEqual(manifest.source_sha256,auth17SourceDigests),'Auth17 requires all exact52 current source fingerprints');
 need(auth17FingerprintsEqual(manifest.migrations_sha256,auth17MigrationDigests),'Auth17 requires the exact complete17 migration prefix');
 const migrations=Object.keys(auth17MigrationDigests).sort(),families=[...routeFamilies,...momoRouteFamilies,...auth17RouteFamilies];
 need(canonical(manifest.operations)===canonical(profileOperations(true).map(op=>auth17Operation(op,migrations))),'Auth17 operation inventory or ordinary/legacy SMS admission changed');
 need(canonical(manifest.route_families)===canonical(families.map(row=>auth17Family(row,migrations))),'Auth17 route methods, actions, authority or provider requirements changed');
 need(canonical(manifest.callers)===canonical(momoCallerCatalog)&&canonical(manifest.secret_role_sources)===canonical(auth17RoleSources),'Auth17 caller/secret catalog changed');
 need(canonical(manifest.runtime_boundaries)===canonical(auth17RuntimeBoundary),'Auth17 configuration must not activate AI, scheduler, provider or MFA bypass');
 need(canonical(manifest.retired_wire_aliases)===canonical(momoLegacyAliases()),'Auth17 cannot relabel retired aliases as released equivalents');
 need(manifest.metadata_is_source_only===true&&manifest.metadata_grants_authority===false&&manifest.registration_is_provider_availability===false&&manifest.whole_endpoint_acceptance===false,'Auth17 source metadata cannot confer approval or acceptance');
 need(canonical(manifest.rollout)===canonical(auth17Rollout),'Auth17 rollout/adoption approval changed');
 need(canonical(manifest.producer)===canonical({path:'scripts/operation_inventory.mjs',sha256:auth17ProducerSha256}),'Auth17 producer fingerprint changed');
 for(const row of [...manifest.operations,...manifest.route_families]){
  need(row.authority_boundary.metadata_grants_authority===false&&row.lifecycle.live_configuration_or_deployment_asserted===false&&row.lifecycle.installed_client_acceptance===false,'Auth17 metadata cannot grant access or assert deployment');
  for(const name of row.authority_boundary.source)need(Object.hasOwn(manifest.source_sha256,name),'Auth17 authority source missing');
  for(const role of row.conditional_secret_requirements)need(Object.hasOwn(auth17RoleSources,role.role)&&role.configured_or_approved_by_manifest===false,'Auth17 invented or approved secret role');
 }
 return true;
}
async function buildAuth17Manifest(){
 for(const prior of auth17Predecessors){const raw=await readFile(resolve(root,prior.path));need(sha(raw)===prior.sha256,'Auth17 predecessor bytes changed');assertManifestMetadata(JSON.parse(raw),{profile:prior.profile});}
 const source=await sourceFiles(resolve(root,'src'),'',true),migrations=await sourceFiles(resolve(root,'migrations'),'',true);
 need(auth17FingerprintsEqual(source,auth17SourceDigests),'Auth17 source snapshot changed; explicit tuple review required');
 need(auth17FingerprintsEqual(migrations,auth17MigrationDigests),'Auth17 migration snapshot changed; explicit tuple review required');
 const configPath=resolve(root,auth17ConfigurationSource),info=await lstat(configPath);
 need(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&await realpath(configPath)===configPath,'Auth17 source configuration must be an independent physical regular file');
 const configRaw=await readFile(configPath),config=JSON.parse(configRaw);
 need(sha(configRaw)===auth17WranglerSha256,'Auth17 no-AI/no-cron candidate configuration fingerprint changed');
 need(!config.ai&&!config.triggers?.crons?.length&&config.vars?.MOMO_PROCESSING_PAUSED==='true'&&config.vars?.GOOGLE_AUTH_ENABLED==='false','Auth17 proposal cannot activate AI, cron or unconfigured Google');
 const migrationNames=Object.keys(migrations).sort(),families=[...routeFamilies,...momoRouteFamilies,...auth17RouteFamilies];
 const manifest={schema_version:1,metadata_version:3,profile:auth17Profile,predecessor_inventories:auth17Predecessors,configuration_sha256:sha(configRaw),configuration_source:auth17ConfigurationSource,service:'collect-platform-api',
  operation_scope:'Exact current RPC/functions plus explicit email/Google/Admin OTP/invitation leaves; metadata is source evidence only',
  registration_is_provider_availability:false,whole_endpoint_acceptance:false,metadata_is_source_only:true,metadata_grants_authority:false,
  migration_dependencies_scope:'Exact complete17 source proposal; target upgrade, minimum per-handler schema, source adoption and release acceptance are separate',
  callers:momoCallerCatalog,secret_role_sources:auth17RoleSources,operations:profileOperations(true).map(op=>auth17Operation(op,migrationNames)),
  route_families:families.map(row=>auth17Family(row,migrationNames)),retired_wire_aliases:momoLegacyAliases(),runtime_boundaries:auth17RuntimeBoundary,
  rollout:auth17Rollout,
  producer:{path:'scripts/operation_inventory.mjs',sha256:sha(await readFile(fileURLToPath(import.meta.url)))},source_sha256:source,migrations_sha256:migrations};
 assertAuth17ManifestMetadata(manifest);return structuredClone(manifest);
}

export function assertManifestMetadata(manifest,{profile=manifest.profile??'complete13'}={}){
 if(profile===auth17Profile)return assertAuth17ManifestMetadata(manifest);
 need(['complete13',momoProfile].includes(profile),'Unknown endpoint metadata profile');const momo=profile===momoProfile;
 need(manifest.schema_version===1&&manifest.metadata_version===(momo?2:1),'Unknown endpoint metadata schema');
 if(momo){need(manifest.profile===momoProfile&&canonical(manifest.predecessor_inventory)===canonical(predecessorInventory),'Successor must retain exact source-only complete13 provenance');need(manifest.configuration_sha256===momoWranglerSha256,'MoMo candidate requires its exact source configuration');}
 else need(manifest.profile===undefined,'The complete13 artifact cannot be relabeled as a current successor');
 const expectedOperations=profileOperations(momo);
 need(canonical(manifest.operations.map(baseOperation))===canonical(expectedOperations),'Endpoint metadata must preserve the exact profile dispatch inventory');
 const migrations=Object.keys(manifest.migrations_sha256).sort();
 if(momo)need(canonical(manifest.migrations_sha256)===canonical(momoMigrationDigests),'MoMo candidate requires the exact complete15-schema prefix');
 else need(migrations.length===13&&migrations.every((n,i)=>n.startsWith(String(i+1).padStart(4,'0')+'_'))&&migrations.at(-1)===currentMigrationReview.migration&&manifest.migrations_sha256[currentMigrationReview.migration]===currentMigrationReview.sha256,'Current metadata requires the reviewed complete13-schema prefix and exact0013');
 const reviewed=Object.values(reviewedOperations).flat().filter(name=>momo||!momoOnlyOperations.has(name));need(reviewed.length===expectedOperations.length&&new Set(reviewed).size===reviewed.length,'Reviewed operation metadata is stale or duplicated');
 for(const row of manifest.operations){const expected=operationMetadata(row,migrations,{momo});for(const key of metadataFields)need(canonical(row[key])===canonical(expected[key]),'Unreviewed endpoint metadata: '+row.name+' '+key);}
 const families=momo?[...routeFamilies,...momoRouteFamilies]:routeFamilies;
 need(manifest.route_families.length===families.length,'Route-family metadata inventory changed');
 for(let i=0;i<families.length;i++){const row=manifest.route_families[i],base=families[i],expected=momoRouteFamilies.includes(base)?momoFamilyMetadata(base,migrations):familyMetadata(base,migrations);for(const [k,v]of Object.entries(base))need(canonical(row[k])===canonical(v),'Route-family authentication/method boundary changed');for(const key of metadataFields)need(canonical(row[key])===canonical(expected[key]),'Unreviewed family metadata: '+base.path+' '+key);}
 const callers=momo?momoCallerCatalog:callerCatalog;
 need(canonical(manifest.callers)===canonical(callers),'Caller catalog changed without metadata review');
 need(canonical(manifest.secret_role_sources)===canonical(roleSources),'Conditional role catalog changed without review');
 need(manifest.metadata_is_source_only===true&&manifest.metadata_grants_authority===false,'Metadata cannot grant authority');
 need(canonical(manifest.retired_wire_aliases)===canonical(momo?momoLegacyAliases():legacyAliases()),'Retired alias inventory/disposition changed');
 for(const row of [...manifest.operations,...manifest.route_families]){
  need(row.lifecycle.live_configuration_or_deployment_asserted===false&&row.lifecycle.installed_client_acceptance===false&&row.authority_boundary.metadata_grants_authority===false,'Source metadata cannot grant or assert release acceptance');
  for(const caller of row.supported_callers)need(Object.hasOwn(callers,caller),'Unknown supported caller');
  for(const source of row.authority_boundary.source)need(Object.hasOwn(manifest.source_sha256,source),'Authority metadata source missing');
  for(const r of row.conditional_secret_requirements){need(Object.hasOwn(roleSources,r.role)&&r.configured_or_approved_by_manifest===false,'Unknown or falsely approved secret role');for(const source of r.source)need(Object.hasOwn(manifest.source_sha256,source),'Conditional role source missing');}
  need(row.service_boundary.service_role_or_metadata_bypass===false&&row.service_boundary.dependencies.every(s=>s.availability_or_authority_asserted===false),'Service metadata cannot supply availability or authority');
 }
 need(canonical(manifest.rollout.migration_order)===canonical(migrations)&&canonical(manifest.rollout.release_order)===canonical(rolloutOrder)&&manifest.rollout.approval_supplied===false,'Rollout metadata must preserve reviewed schema order and approval boundary');
 need(canonical(manifest.rollout.additive_migration_review)===canonical(momo?momoMigrationReview:currentMigrationReview),'Current migration intended-effect metadata changed');
 if(momo){need(canonical(manifest.runtime_boundaries)===canonical(momoRuntimeBoundary),'MoMo scheduler/AI/service boundary differs from the candidate profile');for(const source of manifest.runtime_boundaries.processing.source)need(Object.hasOwn(manifest.source_sha256,source),'MoMo processing source missing');}
 else need(canonical(manifest.runtime_boundaries.handler_exports)===canonical(['fetch'])&&manifest.runtime_boundaries.configured_crons.length===0&&manifest.runtime_boundaries.inbound_service_role_bypass===false,'Scheduler/service boundary requires review');
 return true;
}


export async function buildManifest({profile=momoProfile}={}){
 if(profile===auth17Profile)return buildAuth17Manifest();
 need(['complete13',momoProfile].includes(profile),'Unknown endpoint metadata profile');const momo=profile===momoProfile;
 if(momo){const preserved=await readFile(resolve(root,predecessorInventory.path));need(sha(preserved)===predecessorInventory.sha256,'The complete13 predecessor artifact changed');assertManifestMetadata(JSON.parse(preserved.toString()),{profile:'complete13'});}
 const source=await sourceFiles(resolve(root,'src')),migrations=await sourceFiles(resolve(root,'migrations'));
 const migrationNames=Object.keys(migrations).sort(),configRaw=await readFile(resolve(root,'wrangler.jsonc')),config=JSON.parse(configRaw.toString());
 const families=momo?[...routeFamilies,...momoRouteFamilies]:routeFamilies;
 const manifest={
  schema_version:1,metadata_version:momo?2:1,...(momo?{profile:momoProfile,predecessor_inventory:predecessorInventory,configuration_sha256:sha(configRaw)}:{}),service:'collect-platform-api',
  operation_scope:'Runtime dispatch for /v1/rpc and /v1/functions; each separate route family retains its own methods/authority. Metadata is source evidence, not installed/hosted acceptance.',
  registration_is_provider_availability:false,whole_endpoint_acceptance:false,
  metadata_is_source_only:true,metadata_grants_authority:false,
  migration_dependencies_scope:momo?'The exact complete15 source candidate; minimum per-handler schema, target upgrade and release acceptance are not asserted':'The complete reviewed release schema, not a claim of minimum tables needed by each individual handler',
  callers:momo?momoCallerCatalog:callerCatalog,secret_role_sources:roleSources,
  operations:profileOperations(momo).map(op=>({...op,...operationMetadata(op,migrationNames,{momo})})),
  route_families:families.map(row=>({...row,...(momoRouteFamilies.includes(row)?momoFamilyMetadata(row,migrationNames):familyMetadata(row,migrationNames))})),
  retired_wire_aliases:momo?momoLegacyAliases():legacyAliases(),
  runtime_boundaries:momo?{...momoRuntimeBoundary,handler_exports:Object.keys(worker).sort(),configured_crons:config.triggers?.crons??[],configured_ai_binding:config.ai?.binding??null}:{handler_exports:Object.keys(worker).sort(),configured_crons:config.triggers?.crons??[],
   configuration_scope:'Selected current wrangler source only; deployed configuration and scheduler readback remain separate',
   inbound_service_role_bypass:false,functions_are_scheduler_evidence:false,
   scheduler_acceptance:'No scheduled handler or configured cron in this reviewed source; no retired worker replacement is inferred'},
  rollout:{migration_order:migrationNames,release_order:rolloutOrder,additive_migration_review:momo?momoMigrationReview:currentMigrationReview,
   instruction:'Admit the exact complete reviewed schema before its compatible immutable Worker; independently read back source/config/migrations and exercise declared clients/HTTP authority. Metadata does not approve deployment or a destructive migration.',
   approval_supplied:false},
  producer:{path:'scripts/operation_inventory.mjs',sha256:sha(await readFile(fileURLToPath(import.meta.url)))},
  source_sha256:source,migrations_sha256:migrations,
 };
 assertManifestMetadata(manifest,{profile});return structuredClone(manifest);
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const mode=process.argv[2];
  if(process.argv.length!==3||!['--write','--check','--check-complete13','--write-auth17','--check-auth17'].includes(mode))throw new Error('Use --write/--check for momo15, --write-auth17/--check-auth17 for the separate exact auth17 proposal, or --check-complete13 for the preserved profile.');
  const historical=mode==='--check-complete13',auth17=mode.endsWith('-auth17'),profile=auth17?auth17Profile:historical?'complete13':momoProfile;
  const bytes=JSON.stringify(await buildManifest({profile}),null,2)+'\n',target=resolve(root,auth17?'operations-manifest-auth17.json':historical?'operations-manifest.json':'operations-manifest-momo15.json');
  if(mode==='--write'||mode==='--write-auth17')await writeFile(target,bytes,{mode:0o644});
  else if(await readFile(target,'utf8')!==bytes)throw new Error('Cloudflare operation/source inventory changed; review and regenerate it.');
  process.stdout.write(JSON.stringify({status:'pass',mode,profile,target,rpc:operationInventory.filter(r=>r.kind==='rpc').length,
    functions:operationInventory.filter(r=>r.kind==='function').length,provider_or_hosted_acceptance:false})+'\n');
}
