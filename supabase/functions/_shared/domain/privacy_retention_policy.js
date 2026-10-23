import {requireFreshAdminEmail} from './admin_email_policy.js';
import {ApiError,digest,first,id,stableJson} from './core.js';
import {retentionSchema,engineTables} from './privacy_retention_catalog.js';
import {assertPrivateRetentionPolicy} from '../private-retention.js';

export const retentionSha=/^[a-f0-9]{64}$/;
export const retentionUuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const seconds=()=>Math.floor(Date.now()/1000);
export function retentionFail(code,status=409){throw new ApiError(status,code,'Retention processing is blocked. Refresh the approved source or contact the privacy reviewer.');}
const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).length===keys.length&&keys.every(k=>Object.hasOwn(value,k));
const timestamp=value=>typeof value==='string'&&Number.isFinite(Date.parse(value))&&new Date(value).toISOString()===value;
export function retentionActor(actor){
 if(actor?.surface!=='admin'||!actor.permissions?.has('privacy.review')||!retentionUuid.test(actor.userId)||!retentionUuid.test(actor.sessionId))retentionFail('privacy_retention_authority_required',403);
 requireFreshAdminEmail(actor);
}
export function actorGuard(env,actor){
 retentionActor(actor);const key=id();
 return {key,insert:env.DB.prepare(`INSERT INTO mutation_guards(id,user_id,session_id,now_seconds,permission,fresh_seconds,minimum_assurance,expected_mfa_at)
 VALUES(?,?,?,unixepoch(),?,300,2,?)`).bind(key,actor.userId,actor.sessionId,'privacy.review',null),remove:env.DB.prepare('DELETE FROM mutation_guards WHERE id=?').bind(key)};
}
export async function retentionBatch(env,statements){
 try{return await env.DB.batch(statements);}catch(error){
  if(/recent_email_(?:verification|sign_in)_required/.test(String(error?.message)))throw new ApiError(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');
  if(/session_changed|fresh_auth_required|mfa_required|permission_denied/.test(String(error?.message)))retentionFail('privacy_retention_authority_changed',403);
  if(/CHECK constraint failed: passed=1/.test(String(error?.message)))retentionFail('privacy_retention_source_or_claim_changed');
  throw error;
 }
}
export async function authority(env,actor){const guard=actorGuard(env,actor);await retentionBatch(env,[guard.insert,guard.remove]);}

/** Configuration is an externally approved, exact content-addressed decision.
 * The engine cannot grant legal approval. Production has no default policy. */
export async function loadRetentionPolicy(env,expectedSha){
 if(!retentionSha.test(env.PRIVACY_RETENTION_APPROVAL_SHA256??'')||expectedSha!==env.PRIVACY_RETENTION_APPROVAL_SHA256)
  retentionFail('privacy_retention_policy_unavailable');
 const row=await first(env,"SELECT * FROM runtime_config WHERE key='privacy:retention:approved:v1'");
 if(!row||await digest(row.value_json)!==expectedSha)retentionFail('privacy_retention_policy_changed');
 let policy;try{policy=JSON.parse(row.value_json);}catch{retentionFail('privacy_retention_policy_unavailable');}
 const schema=await retentionSchema(env),retentionClasses=schema.classes;
 const keys=['contract_version','policy_id','version','environment','synthetic_test_only','approval_evidence_sha256','approved_by','approved_at','expires_at','source_id','schema_sha256','scope','rules','writer_fence','external_inventory','copy_inventory'];
 if(policy&&Object.hasOwn(policy,'quarantine_continuation'))keys.push('quarantine_continuation');
 if(!exact(policy,keys)||policy.contract_version!==1||!retentionUuid.test(policy.policy_id)||typeof policy.version!=='string'||!policy.version||policy.version.length>64||policy.environment!==env.APP_ENVIRONMENT||typeof policy.synthetic_test_only!=='boolean'||policy.synthetic_test_only&&env.APP_ENVIRONMENT!=='test'||!retentionSha.test(policy.approval_evidence_sha256)||!retentionUuid.test(policy.approved_by)||!timestamp(policy.approved_at)||!timestamp(policy.expires_at)||Date.parse(policy.approved_at)>Date.now()||Date.parse(policy.expires_at)<=Date.now()||!retentionSha.test(policy.source_id)||policy.source_id!==env.BUILD_SOURCE_ID||!retentionSha.test(policy.schema_sha256)||!exact(policy.rules,retentionClasses))
  retentionFail('privacy_retention_policy_unavailable');
 if(!exact(policy.scope,['request_id','subject_id','snapshot_sha256'])||!retentionUuid.test(policy.scope.request_id)||!retentionUuid.test(policy.scope.subject_id)||!retentionSha.test(policy.scope.snapshot_sha256))retentionFail('privacy_retention_scope_unapproved');
 for(const [name,rule]of Object.entries(policy.rules)){
  if(!exact(rule,['action','basis_reference','deadline'])||!['retain','erase','quarantine','blocked'].includes(rule.action)||typeof rule.basis_reference!=='string'||!rule.basis_reference.trim()||rule.basis_reference.length>256||!timestamp(rule.deadline)||name==='access'&&!['quarantine','blocked'].includes(rule.action)||name!=='access'&&rule.action==='quarantine'||engineTables.includes(name)&&!['retain','blocked'].includes(rule.action))
   retentionFail('privacy_retention_policy_rule_invalid');
 }
 const fence=policy.writer_fence;
 if(!exact(fence,['source_id','evidence_sha256','generic_upload_catalog_only','unknown_in_flight'])||fence.source_id!==policy.source_id||!retentionSha.test(fence.evidence_sha256)||typeof fence.generic_upload_catalog_only!=='boolean'||typeof fence.unknown_in_flight!=='boolean')retentionFail('privacy_retention_writer_coverage_unknown');
 if(!exact(policy.external_inventory,['status','evidence_sha256'])||!retentionSha.test(policy.external_inventory.evidence_sha256)||!['unverified','synthetic_empty'].includes(policy.external_inventory.status)||policy.external_inventory.status==='synthetic_empty'&&(!policy.synthetic_test_only||env.APP_ENVIRONMENT!=='test'))retentionFail('privacy_retention_copy_inventory_unknown');
 assertPrivateRetentionPolicy(policy,schema.privateInventory);
 if(policy.schema_sha256!==schema.sha256)retentionFail('privacy_retention_schema_changed');
 if(Object.hasOwn(policy,'quarantine_continuation')){
  const c=policy.quarantine_continuation;
  if(!exact(c,['action','previous_plan_id','previous_barrier_sha256','approval_evidence_sha256'])||c.action!=='continue_quarantine'||!retentionUuid.test(c.previous_plan_id)||!retentionSha.test(c.previous_barrier_sha256)||!retentionSha.test(c.approval_evidence_sha256))retentionFail('privacy_retention_continuation_unapproved');
 }
 return {policy,raw:row.value_json,sha256:expectedSha,revision:row.revision};
}

// Only an immutable predecessor barrier and its actual original plan can be
// adopted. Expired approval is historical evidence, never current authority.
export async function retentionBarrierObservation(env,subject){
 const row=await first(env,'SELECT * FROM privacy_retention_barriers WHERE subject_id=?',subject);
 if(!row)return null;
 const prior=await first(env,'SELECT id,subject_id,source_id,policy_sha256 FROM privacy_retention_plans WHERE id=?',row.plan_id);
 if(!prior||prior.subject_id!==subject||prior.source_id!==row.source_id||prior.policy_sha256!==row.policy_sha256||!Number.isSafeInteger(row.activated_seconds))retentionFail('privacy_retention_barrier_unavailable');
 return {row,projection:{previous_plan_id:row.plan_id,previous_source_id:row.source_id,previous_policy_sha256:row.policy_sha256,
  previous_barrier_sha256:await retentionInputHash(row),activated_seconds:row.activated_seconds}};
}
export async function approvedQuarantineContinuation(env,plan,policy,barrier){
 const decision=policy.quarantine_continuation;
 if(!decision||!barrier||barrier.subject_id!==plan.subject_id)return null;
 const observed=await retentionBarrierObservation(env,plan.subject_id);
 if(!observed||stableJson(observed.row)!==stableJson(barrier)||decision.previous_plan_id!==observed.projection.previous_plan_id||decision.previous_barrier_sha256!==observed.projection.previous_barrier_sha256)return null;
 return {...observed.projection,approval_evidence_sha256:decision.approval_evidence_sha256};
}
export const priorRetentionWork=Object.freeze({
 claims:`SELECT 1 FROM privacy_retention_tasks t JOIN privacy_retention_plans p ON p.id=t.plan_id
  JOIN privacy_retention_claims c ON c.id=t.claim_id
  WHERE p.subject_id=? AND p.id!=coalesce(?,'') AND t.state='claimed' AND c.expires_seconds>unixepoch()`,
 effects:`SELECT 1 FROM privacy_retention_effects e JOIN privacy_retention_tasks t ON t.id=e.task_id
  JOIN privacy_retention_plans p ON p.id=t.plan_id WHERE p.subject_id=? AND p.id!=coalesce(?,'')
  AND NOT EXISTS(SELECT 1 FROM privacy_retention_outcomes o WHERE o.task_id=t.id
   AND json_extract(o.outcome_json,'$.verified')=1
   AND json_extract(o.outcome_json,'$.disposition')='catalog_object_absence_verified')`,
});
export async function priorRetentionWorkCounts(env,subject,exceptPlan=null){
 const result=await first(env,`SELECT (SELECT count(*) FROM (${priorRetentionWork.claims})) AS active_claim_count,
  (SELECT count(*) FROM (${priorRetentionWork.effects})) AS unresolved_effect_count`,subject,exceptPlan,subject,exceptPlan);
 if(!result||!Number.isSafeInteger(result.active_claim_count)||!Number.isSafeInteger(result.unresolved_effect_count))retentionFail('privacy_retention_prior_work_unknown');
 return result;
}
export async function retentionPolicyFence(env,plan){
 const approved=await loadRetentionPolicy(env,plan.policy_sha256);
 if(approved.raw!==plan.policy_json||approved.revision!==plan.policy_config_revision||approved.policy.source_id!==plan.source_id)retentionFail('privacy_retention_policy_changed');
 return approved;
}
export function taskAction(rule,nowSeconds=seconds()){
 if(rule.action==='blocked')return {blocked:'policy_class_unapproved'};
 if(rule.action==='retain'&&Date.parse(rule.deadline)<=nowSeconds*1000)return {blocked:'retention_deadline_requires_new_decision'};
 if(rule.action==='erase'&&Date.parse(rule.deadline)>nowSeconds*1000)return {blocked:'retention_deadline_not_reached'};
 return {action:rule.action};
}
export async function retentionInputHash(value){return digest(stableJson(value));}
