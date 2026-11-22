import {ApiError} from './core.js';
import {groupRpc} from './groups.js';
import {financialRpc} from './payments.js';
import {adminRpc,adminListOperations} from './admin.js';
import {notificationRpc} from './notifications.js';
import {compensationRpc} from './evidence.js';
import {privacyRpc} from './privacy.js';
import {privacyRetentionRpc,retentionRpcNames} from './privacy_retention_rpc.js';
import {nativeRpc,functionRpc as nativeFunction} from './native_integrity.js';
import {rosterRpc,functionRpc as rosterFunction} from './roster.js';
import {receiptFunction} from './receipts.js';
import {operatorNoteRpc} from './operator_notes.js';
import {assistedSmsConsentRpc} from './notification_operator_consent.js';

export const publicRpcNames=Object.freeze([
  'get_public_runtime_config','get_collection_type_catalog',
  'get_active_policy_document','list_account_request_reasons',
]);

// This inventory is the actual dispatch boundary, not a second list of intended
// features. Registration does not assert provider configuration or acceptance.
const definitions=[
  ['rpc','groups.js',groupRpc,[
    'get_current_member_profile','ensure_current_member_profile',
    'update_current_member_profile','list_current_user_collections',
    'list_current_member_group_roster','get_group_share_code',
    'rotate_group_share_code_v2','join_group_by_share_code','archive_group',
    'add_group_admin','transfer_group_ownership','update_rwanda_momo_group_profile',
    'get_owner_group_health','create_private_group_with_owner_media_attested',
  ]],
  ['rpc','payments.js',financialRpc,[
    'create_contribution_intent','list_current_member_recent_intents',
    'list_current_member_collection_balances','list_current_member_history_page',
    'propose_payment_reconciliation_v2','approve_payment_reconciliation_v2',
    'reject_payment_reconciliation_v2','get_payment_reconciliation_v2',
    'list_payment_reconciliations_v2',
  ]],
  ['rpc','admin.js',adminRpc,[...adminListOperations,
    'admin_current_user','is_platform_admin','admin_overview','admin_runtime_config',
    'admin_get_user','admin_set_user_access','admin_system_health','admin_get_queue_sla',
  ]],
  ['rpc','notifications.js',notificationRpc,[
    'get_notification_preferences_v2','set_notification_preferences_v2',
    'mark_notification_event_read','register_notification_device',
    'unregister_notification_device','create_mobile_support_request',
    'get_current_member_payment_review_request_v1',
  ]],
  ['rpc','evidence.js',compensationRpc,[
    'admin_reverse_payment_v1','admin_record_full_payment_compensation_v1',
  ]],
  ['rpc','privacy.js',privacyRpc,[
    'request_account_deletion','request_account_deletion_v1',
    'get_account_deletion_request_status_v1',
    'get_current_account_deletion_request_status_v1',
    'get_account_deletion_review_status_v1','admin_list_account_deletion_reviews_v1',
    'admin_get_account_deletion_review_v1','admin_claim_account_deletion_review_v1',
    'admin_record_account_deletion_review_v1','admin_get_account_deletion_review_operation_v1',
  ]],
  ['rpc','native_integrity.js',nativeRpc,['record_sms_access_consent']],
  ['rpc','privacy_retention_rpc.js',privacyRetentionRpc,retentionRpcNames],
  ['rpc','roster.js',rosterRpc,[
    'admin_review_roster_import','admin_commit_roster_import','admin_get_roster_import',
    'admin_stage_roster_import_intent','admin_execute_roster_import_intent',
  ]],
  ['rpc','operator_notes.js',operatorNoteRpc,['admin_record_operator_note']],
  ['rpc','notification_operator_consent.js',assistedSmsConsentRpc,['get_assisted_sms_consent_v1','set_assisted_sms_consent_v1']],
  ['function','native_integrity.js',nativeFunction,['verify-play-integrity']],
  ['function','roster.js',rosterFunction,[
    'prepare-roster-import','roster-import-upload','roster-import-extract','roster-import-commit',
  ]],
  ['function','receipts.js',receiptFunction,['ingest-payment-sms','ingest-client-sms']],
];

const handlers=new Map();
const registered=publicRpcNames.map(name=>Object.freeze({
  kind:'rpc',name,method:'POST',path:`/v1/rpc/${name}`,authentication:'public',source:'index.js',
}));
for(const [kind,source,handler,names] of definitions){
  for(const name of names){
    const key=`${kind}:${name}`,pattern=kind==='rpc'?/^[a-z][a-z0-9_]{0,100}$/:/^[a-z][a-z0-9_-]{0,100}$/;
    if(!pattern.test(name)||handlers.has(key)||kind==='rpc'&&publicRpcNames.includes(name))
      throw new Error('Duplicate or invalid API operation registration.');
    handlers.set(key,handler);
    registered.push(Object.freeze({kind,name,method:'POST',path:`/v1/${kind==='rpc'?'rpc':'functions'}/${name}`,
      authentication:'bearer_session',source}));
  }
}
export const operationInventory=Object.freeze(registered.sort((a,b)=>a.path.localeCompare(b.path,'en')));

export async function dispatchOperation(kind,name,body,env,actor){
  const handler=handlers.get(`${kind}:${name}`);
  if(!handler)throw new ApiError(501,'operation_unavailable','This action is not available yet. Please contact support.');
  const result=await handler(name,body,env,actor);
  if(!result||result.handled!==true)throw new Error('Registered API operation has no handler.');
  return result.value;
}
