import {ApiError} from './core.js';
import {retentionContext,inspectRetentionScope,inspectQuarantineContinuation,planRetention,claimRetentionTask,executeRetentionTask,retentionStatus,reconcileRetentionPlan,resolveRetentionOperation} from './privacy_retention.js';
import {authority} from './privacy_retention_policy.js';

// These are authenticated operations. Registration does not activate a policy:
// destructive work still requires the separately pinned, exact owner decision.
const operations=Object.freeze({
 admin_get_account_retention_context_v1:{run:retentionContext,fields:[]},
 admin_inspect_account_retention_scope_v1:{run:inspectRetentionScope,fields:['request_id','expected_review_revision','expected_source_id']},
 admin_inspect_account_quarantine_continuation_v1:{run:inspectQuarantineContinuation,fields:['request_id','expected_review_revision','expected_source_id']},
 admin_plan_account_retention_v1:{run:planRetention,fields:['operation_id','request_id','expected_review_revision','policy_sha256','expected_source_id']},
 admin_claim_account_retention_task_v1:{run:claimRetentionTask,fields:['operation_id','plan_id','task_id','expected_task_revision','lease_seconds']},
 admin_execute_account_retention_task_v1:{run:executeRetentionTask,fields:['operation_id','claim_id','fence']},
 admin_get_account_retention_status_v1:{run:retentionStatus,fields:['plan_id']},
 admin_reconcile_account_retention_v1:{run:reconcileRetentionPlan,fields:['plan_id']},
 admin_get_account_retention_operation_v1:{run:resolveRetentionOperation,fields:['operation_kind','operation_id']},
});
export const retentionRpcNames=Object.freeze(Object.keys(operations));
export async function privacyRetentionRpc(operation,body,env,actor){
 if(!Object.hasOwn(operations,operation))return {handled:false};
 await authority(env,actor);
 const {run,fields}=operations[operation],allowed=fields.map(name=>'p_'+name);
 if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(name=>!allowed.includes(name)))
  throw new ApiError(400,'privacy_retention_input_invalid','The request contains unsupported retention fields.');
 const input=Object.fromEntries(fields.filter(name=>Object.hasOwn(body,'p_'+name)).map(name=>[name,body['p_'+name]]));
 return {handled:true,value:await run(env,actor,input)};
}
