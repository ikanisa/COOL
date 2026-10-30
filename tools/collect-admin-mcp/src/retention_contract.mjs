import {createHash} from 'node:crypto';
import {SafeError,UUID,object,invalid,unavailable} from './config.mjs';

export const SHA=/^[a-f0-9]{64}$/;
export const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']':object(value)?'{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}':JSON.stringify(value);
export const digest=value=>createHash('sha256').update(canonical(value)).digest('hex');
export const retentionBlocked=(code='retention_blocked')=>{throw new SafeError(code,'This retention step is blocked. Inspect the current approved scope, holds, original operations and supported adapters before continuing.');};
export const READ_RPC=Object.freeze({
 context:'admin_get_account_retention_context_v1',inspect:'admin_inspect_account_retention_scope_v1',
 continuation:'admin_inspect_account_quarantine_continuation_v1',status:'admin_get_account_retention_status_v1',lookup:'admin_get_account_retention_operation_v1',
});
export const WRITE_RPC=Object.freeze({plan:'admin_plan_account_retention_v1',claim:'admin_claim_account_retention_task_v1',execute:'admin_execute_account_retention_task_v1',reconcile:'admin_reconcile_account_retention_v1'});
export const SQL_ERASABLE=Object.freeze(['notification_devices','notification_preferences','notification_events','support_requests']);
export const CLASS=/^[a-z][a-z0-9_]*(?::[a-z][a-z0-9_.-]*)?$/;
const WORD=/^[a-z][a-z0-9_]{0,119}$/;
const exact=(value,keys)=>{if(!object(value)||Object.keys(value).length!==keys.length||keys.some(key=>!Object.hasOwn(value,key)))unavailable();};
export const instant=value=>typeof value==='string'&&Number.isFinite(Date.parse(value))&&new Date(value).toISOString()===value;
const count=value=>Number.isSafeInteger(value)&&value>=0;
function flags(value){if(value.erasure_completed!==false||Object.hasOwn(value,'all_data_erased')&&value.all_data_erased!==false)unavailable();}
export function parseContext(value){
 exact(value,['contract_version','scope','source_id','checked_at','valid_until','approval_granted','erasure_completed']);
 if(value.contract_version!==1||value.scope!=='account_retention_inspection_context'||!SHA.test(value.source_id??'')||!instant(value.checked_at)||!instant(value.valid_until)||Date.parse(value.valid_until)<=Date.now()||Date.parse(value.checked_at)>Date.now()+5000||Date.now()-Date.parse(value.checked_at)>120000||value.approval_granted!==false)unavailable();
 flags(value);return value;
}
export function parseInspection(value,input){
 exact(value,['contract_version','request_id','subject_id','source_id','schema_sha256','snapshot_sha256','table_counts','private_catalog_sha256','private_schema_sha256','private_copy_inventory','object_count','active_hold_count','in_flight_unresolved','approval_granted','erasure_completed']);
 if(value.contract_version!==1||value.request_id!==input.p_request_id||value.source_id!==input.p_expected_source_id||!UUID.test(value.subject_id??'')||value.approval_granted!==false||typeof value.in_flight_unresolved!=='boolean'||!count(value.object_count)||!count(value.active_hold_count))unavailable();
 for(const name of ['source_id','schema_sha256','snapshot_sha256','private_catalog_sha256','private_schema_sha256'])if(!SHA.test(value[name]??''))unavailable();
 for(const name of ['table_counts','private_copy_inventory'])if(!object(value[name])||Object.keys(value[name]).length>256||Object.keys(value[name]).some(key=>key.length>120||!CLASS.test(key)))unavailable();
 if(Object.values(value.table_counts).some(value=>!count(value)))unavailable();
 for(const row of Object.values(value.private_copy_inventory)){exact(row,['count','status']);if(!count(row.count)||!WORD.test(row.status??''))unavailable();}
 flags(value);return value;
}
export function parseOutcome(value){
 if(!object(value)||typeof value.verified!=='boolean'||!WORD.test(value.disposition??'')||value.reason!==undefined&&!WORD.test(value.reason)||!SHA.test(value.source_id??'')||!SHA.test(value.policy_sha256??'')||value.observation_only!==true||value.currentness_not_asserted!==true)unavailable();
 flags(value);
 const result={verified:value.verified,disposition:value.disposition,source_id:value.source_id,policy_sha256:value.policy_sha256,observation_only:true,currentness_not_asserted:true,erasure_completed:false,all_data_erased:false};
 for(const key of ['rows_erased_or_confirmed_absent','rows_remaining','objects_verified_absent','objects_remaining','engine_rows_observed'])if(value[key]!==undefined){if(!count(value[key]))unavailable();result[key]=value[key];}
 if(value.reason!==undefined)result.reason=value.reason;
 if(value.retained_until!==undefined){if(!instant(value.retained_until))unavailable();result.retained_until=value.retained_until;}
 if(value.session_reapproval_required!==undefined){if(value.session_reapproval_required!==true)unavailable();result.session_reapproval_required=true;}
 // Backend chunk postimages, object identities and all undeclared additions
 // stay server-side; operator output contains only this decision projection.
 return result;
}
export function parsePlan(value,expectedId){
 const required=['contract_version','scope','plan_id','request_id','policy_sha256','source_id','schema_sha256','state','revision','scope_snapshot_sha256','erasure_completed','all_data_erased','financial_journal_preserved','policy_current','operational_acceptance_granted','tasks'];
 if(!object(value)||required.some(key=>!Object.hasOwn(value,key))||Object.keys(value).some(key=>![...required,'eligible_dispositions_verified','all_actual_copy_outcomes_verified','retained_classes'].includes(key)))unavailable();
 if(value.contract_version!==1||value.scope!=='approved_eligible_data_disposition'||!UUID.test(value.plan_id??'')||expectedId!==undefined&&value.plan_id!==expectedId||!UUID.test(value.request_id??'')||!['planned','processing','blocked','disposition_verified'].includes(value.state)||!count(value.revision)||typeof value.policy_current!=='boolean'||typeof value.financial_journal_preserved!=='boolean'||value.operational_acceptance_granted!==false||!Array.isArray(value.tasks)||value.tasks.length>256)unavailable();
 for(const key of ['policy_sha256','source_id','schema_sha256','scope_snapshot_sha256'])if(!SHA.test(value[key]??''))unavailable();
 flags(value);const ids=new Set(),classes=new Set();
 const tasks=value.tasks.map(task=>{
  exact(task,['task_id','class_name','action','state','revision','fence','outcome']);
  if(!UUID.test(task.task_id??'')||ids.has(task.task_id)||typeof task.class_name!=='string'||task.class_name.length>120||!CLASS.test(task.class_name)||classes.has(task.class_name)||!['retain','erase','quarantine','blocked'].includes(task.action)||!['pending','claimed','blocked','verified'].includes(task.state)||!count(task.revision)||!count(task.fence))unavailable();
  ids.add(task.task_id);classes.add(task.class_name);return {...task,outcome:task.outcome===null?null:parseOutcome(task.outcome)};
 });
 const result={...value,tasks};
 for(const key of ['eligible_dispositions_verified','all_actual_copy_outcomes_verified'])if(value[key]!==undefined&&typeof value[key]!=='boolean')unavailable();
 if(value.retained_classes!==undefined&&(!Array.isArray(value.retained_classes)||value.retained_classes.length>256||value.retained_classes.some(name=>!classes.has(name))))unavailable();
 return result;
}
export function parseClaim(value,input){
 exact(value,['contract_version','claim_id','task_id','operation_id','fence','claimed_seconds','expires_seconds','erasure_completed']);
 if(value.contract_version!==1||!UUID.test(value.claim_id??'')||value.task_id!==input.p_task_id||value.operation_id!==input.p_operation_id||!count(value.fence)||value.fence<1||!count(value.claimed_seconds)||value.claimed_seconds<1||!count(value.expires_seconds)||value.expires_seconds<=value.claimed_seconds||value.expires_seconds>value.claimed_seconds+120)unavailable();flags(value);return value;
}
export function parseLookup(value,kind,id){
 exact(value,['contract_version','scope','operation_kind','operation_id','observed','receipt','currentness_not_asserted','erasure_completed','all_data_erased']);
 if(value.contract_version!==1||value.scope!=='approved_eligible_data_disposition_operation'||value.operation_kind!==kind||value.operation_id!==id||typeof value.observed!=='boolean'||value.currentness_not_asserted!==true||value.observed!==object(value.receipt))unavailable();flags(value);return value;
}
export function supportedTask(task){
 if(task.class_name.startsWith('external:')||task.action==='blocked')return false;
 if(task.action==='retain')return task.class_name!=='access';
 if(task.action==='quarantine')return task.class_name==='access';
 return task.action==='erase'&&(SQL_ERASABLE.includes(task.class_name)||task.class_name==='r2:upload_objects');
}
export function inspectInput(requestId,revision,source){
 if(typeof requestId!=='string'||!UUID.test(requestId)||!count(revision)||revision>1000000000||typeof source!=='string'||!SHA.test(source))invalid();
 return {p_request_id:requestId,p_expected_review_revision:revision,p_expected_source_id:source};
}
export function authorityBinding(user,origin){return {origin,account_id:user.id,principal_id:user.principalId,session_id:user.sessionId,role:user.role,capabilities_sha256:digest(user.permissions)};}
export function assertBinding(current,expected){if(canonical(current)!==canonical(expected))throw new SafeError('retention_session_changed','Use the original Admin session and unchanged grants. The original operation references remain retained; no action was replayed.');}
