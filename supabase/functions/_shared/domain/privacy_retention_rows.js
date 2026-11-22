import {integer,uuid} from './core.js';
import {authority,retentionBatch,retentionFail,retentionSha} from './privacy_retention_policy.js';
const classes=new Set(['access','notification_devices','notification_preferences','notification_events','support_requests']);
function pin(env){if(!retentionSha.test(env.PRIVACY_RETENTION_V2_APPROVAL_SHA256??''))retentionFail('privacy_retention_row_policy_unavailable');return env.PRIVACY_RETENTION_V2_APPROVAL_SHA256;}
function fields(input,allowed){
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!allowed.includes(k)))
  retentionFail('privacy_retention_input_invalid',400);
}
async function run(env,statement){
 try{
  const value=(await retentionBatch(env,[statement]))[0]?.results?.[0]?.result;
  if(value?.contract_version!==2||value.erasure_completed!==false||!['approved_sql_row_disposition','sql_row_claim','sql_row_operation_receipt'].includes(value.scope))
   retentionFail('privacy_retention_row_result_invalid');
  return value;
 }catch(error){
  if(/^retention_(?:row|manifest)_/.test(String(error?.message??'')))retentionFail('privacy_'+error.message);
  throw error;
 }
}
export async function planRetentionRows(env,actor,input){
 fields(input,['operation_id','manifest_id','manifest_sha256','policy_sha256','expected_source_id']);await authority(env,actor);
 const operation=uuid(input.operation_id,'operation_id'),manifest=uuid(input.manifest_id,'manifest_id');
 if(!retentionSha.test(input.manifest_sha256??'')||!retentionSha.test(env.PRIVACY_RETENTION_V2_APPROVAL_SHA256??'')||
  input.policy_sha256!==env.PRIVACY_RETENTION_V2_APPROVAL_SHA256)retentionFail('privacy_retention_row_policy_unavailable');
 if(!retentionSha.test(env.BUILD_SOURCE_ID??'')||input.expected_source_id!==env.BUILD_SOURCE_ID)retentionFail('privacy_retention_source_changed');
 return run(env,env.DB.prepare('SELECT private.retention_plan_rows_v2(?::uuid,?::uuid,?::text,?::text,?::text,?::text) AS result')
  .bind(operation,manifest,input.manifest_sha256,input.policy_sha256,env.APP_ENVIRONMENT,env.BUILD_SOURCE_ID));
}
export async function claimRetentionRows(env,actor,input){
 fields(input,['operation_id','plan_id','class_name','expected_revision','lease_seconds']);await authority(env,actor);
 if(!classes.has(input.class_name))retentionFail('privacy_retention_row_adapter_unavailable',400);
 return run(env,env.DB.prepare('SELECT private.retention_claim_rows_v2(?::uuid,?::uuid,?::text,?::bigint,?::integer,?::text) AS result')
  .bind(uuid(input.operation_id,'operation_id'),uuid(input.plan_id,'plan_id'),input.class_name,
   integer(input.expected_revision,'expected_revision',0,1000000000),integer(input.lease_seconds??120,'lease_seconds',1,120),pin(env)));
}
export async function executeRetentionRows(env,actor,input){
 fields(input,['operation_id','claim_id','fence']);await authority(env,actor);
 return run(env,env.DB.prepare('SELECT private.retention_execute_rows_v2(?::uuid,?::uuid,?::bigint,?::text) AS result')
  .bind(uuid(input.operation_id,'operation_id'),uuid(input.claim_id,'claim_id'),integer(input.fence,'fence',1,1000000000),pin(env)));
}
export async function retentionRowsStatus(env,actor,input){
 fields(input,['plan_id','verify_current']);await authority(env,actor);
 if(input.verify_current!==undefined&&typeof input.verify_current!=='boolean')retentionFail('privacy_retention_input_invalid',400);
 return run(env,env.DB.prepare('SELECT private.retention_rows_status_v2(?::uuid,?::boolean,?::text) AS result').bind(uuid(input.plan_id,'plan_id'),input.verify_current??false,input.verify_current?pin(env):null));
}
export async function retentionRowsOperation(env,actor,input){
 fields(input,['operation_kind','operation_id']);await authority(env,actor);
 if(!['plan','claim','execute'].includes(input.operation_kind))retentionFail('privacy_retention_input_invalid',400);
 return run(env,env.DB.prepare('SELECT private.retention_rows_operation_v2(?::text,?::uuid) AS result').bind(input.operation_kind,uuid(input.operation_id,'operation_id')));
}
