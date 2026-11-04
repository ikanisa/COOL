import {adminEmailVerifiedAt} from './admin_email_policy.js';
import {rowChunkManifest} from './privacy_retention_chunks.js';
import {first,id,integer,stableJson,uuid} from './core.js';
import {erasableTables,ownRows,retentionSnapshot,retentionApprovalScope,rowKey,snapshotCompareGuards} from './privacy_retention_catalog.js';
import {actorGuard,authority,loadRetentionPolicy,retentionFail,retentionInputHash,retentionPolicyFence,retentionBatch,seconds,retentionBarrierObservation,priorRetentionWorkCounts} from './privacy_retention_policy.js';
export {executeRetentionTask} from './privacy_retention_tasks.js';
const all=async(env,sql,...args)=>(await env.DB.prepare(sql).bind(...args).all()).results;
function fields(value,allowed){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!allowed.includes(k)))retentionFail('privacy_retention_input_invalid',400);}
async function planRow(env,planId){const row=await first(env,'SELECT * FROM privacy_retention_plans WHERE id=?',uuid(planId,'plan_id'));if(!row)retentionFail('privacy_retention_plan_unavailable',404);return row;}
async function taskRows(env,planId){return all(env,'SELECT * FROM privacy_retention_tasks WHERE plan_id=? ORDER BY class_name',planId);}
function projection(plan,tasks,{current=true}={}){
 return {contract_version:1,scope:'approved_eligible_data_disposition',plan_id:plan.id,request_id:plan.request_id,
  policy_sha256:plan.policy_sha256,source_id:plan.source_id,schema_sha256:plan.schema_sha256,
  state:current?plan.state:'blocked',revision:plan.revision,scope_snapshot_sha256:plan.scope_sha256,
  erasure_completed:false,all_data_erased:false,financial_journal_preserved:false,
  policy_current:current,operational_acceptance_granted:false,
  tasks:tasks.map(t=>({task_id:t.id,class_name:t.class_name,action:t.action,state:t.state,revision:t.revision,fence:t.fence,
   outcome:t.outcome_json?JSON.parse(t.outcome_json):null}))};
}

export async function retentionContext(env,actor){
 await authority(env,actor);
 if(!/^[a-f0-9]{64}$/.test(env.BUILD_SOURCE_ID??''))retentionFail('privacy_retention_source_unavailable');
 return {contract_version:1,scope:'account_retention_inspection_context',source_id:env.BUILD_SOURCE_ID,
  checked_at:new Date().toISOString(),valid_until:new Date((adminEmailVerifiedAt(actor)+300)*1000).toISOString(),
  approval_granted:false,erasure_completed:false};
}

/** Reuses an existing authenticated intake. A review-only outcome never
 * becomes an erasure authorization without the separately bound policy. */
export async function inspectRetentionScope(env,actor,input){
 fields(input,['request_id','expected_review_revision','expected_source_id']);await authority(env,actor);
 const requestId=uuid(input.request_id,'request_id'),review=integer(input.expected_review_revision,'review_revision',0,1000000000);
 if(input.expected_source_id!==env.BUILD_SOURCE_ID)retentionFail('privacy_retention_source_changed');
 const request=await first(env,'SELECT r.*,coalesce(h.revision,0) AS review_revision FROM deletion_requests r LEFT JOIN privacy_review_heads h ON h.request_id=r.id WHERE r.id=?',requestId);
 if(!request||request.user_id===actor.userId)retentionFail('privacy_retention_independent_review_required');
 if(request.review_revision!==review)retentionFail('privacy_retention_review_changed');
 const snapshot=await retentionSnapshot(env,request.user_id);
 await authority(env,actor);
 return {contract_version:1,request_id:requestId,subject_id:request.user_id,source_id:env.BUILD_SOURCE_ID,schema_sha256:snapshot.summary.schema_sha256,
  snapshot_sha256:await retentionApprovalScope(snapshot),table_counts:Object.fromEntries(Object.entries(snapshot.summary.tables).map(([name,row])=>[name,row.count])),
  private_catalog_sha256:snapshot.summary.private_inventory.catalog_sha256,private_schema_sha256:snapshot.summary.private_inventory.schema_sha256,private_copy_inventory:Object.fromEntries(Object.entries(snapshot.summary.private_inventory.classes).map(([name,row])=>[name,{count:row.count,status:row.status}])),
  object_count:snapshot.summary.objects.length,active_hold_count:snapshot.summary.holds.length,in_flight_unresolved:snapshot.summary.in_flight_unresolved,
  approval_granted:false,erasure_completed:false};
}
export async function inspectQuarantineContinuation(env,actor,input){
 const scope=await inspectRetentionScope(env,actor,input);
 const barrier=await retentionBarrierObservation(env,scope.subject_id);
 const pending=await priorRetentionWorkCounts(env,scope.subject_id);
 await authority(env,actor);
 return {contract_version:1,scope:'continued_account_quarantine_preview',request_id:scope.request_id,
  subject_id:scope.subject_id,source_id:scope.source_id,schema_sha256:scope.schema_sha256,
  snapshot_sha256:scope.snapshot_sha256,prior_quarantine:barrier?.projection??null,
  ...pending,approval_granted:false,reactivation_granted:false,erasure_completed:false,currentness_not_asserted:true};
}
export async function planRetention(env,actor,input){
 fields(input,['operation_id','request_id','expected_review_revision','policy_sha256','expected_source_id']);
 const operation=uuid(input.operation_id,'operation_id'),requestId=uuid(input.request_id,'request_id');
 const reviewRevision=integer(input.expected_review_revision,'review_revision',0,1000000000);
 await authority(env,actor);const approved=await loadRetentionPolicy(env,input.policy_sha256);
 if(input.expected_source_id!==env.BUILD_SOURCE_ID)retentionFail('privacy_retention_source_changed');
 const fingerprint=await retentionInputHash({input,actor_id:actor.userId,session_id:actor.sessionId});
 const previous=await first(env,'SELECT * FROM privacy_retention_plans WHERE operation_id=?',operation);
 if(previous){if(previous.input_sha256!==fingerprint)retentionFail('privacy_retention_operation_conflict');return retentionStatus(env,actor,{plan_id:previous.id});}
 const request=await first(env,'SELECT r.*,coalesce(h.revision,0) AS review_revision FROM deletion_requests r LEFT JOIN privacy_review_heads h ON h.request_id=r.id WHERE r.id=?',requestId);
 if(!request||request.user_id===actor.userId)retentionFail('privacy_retention_independent_review_required');
 if(request.review_revision!==reviewRevision)retentionFail('privacy_retention_review_changed');
 const snapshot=await retentionSnapshot(env,request.user_id);
 if(snapshot.summary.schema_sha256!==approved.policy.schema_sha256)retentionFail('privacy_retention_schema_changed');
 if(approved.policy.scope.request_id!==requestId||approved.policy.scope.subject_id!==request.user_id||approved.policy.scope.snapshot_sha256!==await retentionApprovalScope(snapshot))retentionFail('privacy_retention_scope_unapproved');
 const planId=id(),guard=actorGuard(env,actor),at=seconds();
 const writes=[guard.insert,env.DB.prepare(`INSERT INTO privacy_retention_plans(id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(planId,operation,requestId,request.user_id,actor.userId,actor.sessionId,fingerprint,approved.sha256,approved.raw,approved.revision,approved.policy.source_id,snapshot.summary.schema_sha256,stableJson(snapshot.summary),snapshot.sha256,snapshot.summary.ledger_sha256,reviewRevision,at)];
 writes.push(env.DB.prepare(`INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,'plan',(CASE WHEN
  coalesce((SELECT revision FROM privacy_review_heads WHERE request_id=?),0)=? AND
  EXISTS(SELECT 1 FROM runtime_config WHERE key='privacy:retention:approved:v1' AND revision=? AND value_json=? AND julianday(json_extract(value_json,'$.expires_at'))>julianday('now')) THEN 1 ELSE 0 END)`)
  .bind(id(),planId,requestId,reviewRevision,approved.revision,approved.raw));
 writes.push(...snapshotCompareGuards(env,{id:planId,subject_id:request.user_id},snapshot,'plan'));
 for(const name of snapshot.classes){
  let expected={};
  if(name==='access')expected={identity_sha256:await accessIdentity(snapshot.rows),user_states:snapshot.rows.users.map(({id,access_status,revision})=>({id,access_status,revision})),session_ids:snapshot.rows.auth_sessions.filter(r=>r.user_id===request.user_id).map(r=>r.id)};
  else if(snapshot.summary.tables[name])expected={...snapshot.summary.tables[name],...(erasableTables.includes(name)?{target_ids:ownRows(name,snapshot.rows[name],request.user_id).map(r=>rowKey(name,r)),row_chunks:await rowChunkManifest(ownRows(name,snapshot.rows[name],request.user_id).map(r=>rowKey(name,r))),context_sha256:await retentionInputHash(snapshot.rows[name].filter(r=>r.user_id!==request.user_id))}:{})};
  else if(name.startsWith('private:')||name.startsWith('managed:'))expected={...snapshot.summary.private_inventory.classes[name],catalog_sha256:snapshot.summary.private_inventory.catalog_sha256,schema_sha256:snapshot.summary.private_inventory.schema_sha256};
  else if(name.startsWith('r2:'))expected={objects:snapshot.summary.objects.filter(o=>o.class_name===name),...(name==='r2:upload_objects'?{catalog_identity_sha256:await retentionInputHash(snapshot.rows.upload_objects.map(r=>r.user_id===request.user_id?(({status,deleted_at,...v})=>v)(r):r)),catalog_lifecycle:snapshot.rows.upload_objects.filter(r=>r.user_id===request.user_id).map(({id,status,deleted_at})=>({id,status,deleted_at}))}:{})};
  else expected={inventory:'unverified',evidence_sha256:approved.policy.external_inventory.evidence_sha256};
  writes.push(env.DB.prepare('INSERT INTO privacy_retention_tasks(id,plan_id,class_name,action,expected_json) VALUES(?,?,?,?,?)').bind(id(),planId,name,approved.policy.rules[name].action,stableJson(expected)));
 }
 writes.push(env.DB.prepare('DELETE FROM privacy_retention_guards WHERE plan_id=?').bind(planId),guard.remove);
 try{await retentionBatch(env,writes);}catch(error){const replay=await first(env,'SELECT * FROM privacy_retention_plans WHERE operation_id=?',operation);if(replay&&replay.input_sha256===fingerprint){await authority(env,actor);return projection(replay,await taskRows(env,replay.id));}throw error;}
 return projection(await planRow(env,planId),await taskRows(env,planId));
}
export async function accessIdentity(rows){
 const users=rows.users.map(({access_status,updated_at,revision,...identity})=>identity);
 const sessions=rows.auth_sessions.map(({revoked_at,revocation_reason,...identity})=>identity);
 return retentionInputHash({users,sessions});
}

export async function claimRetentionTask(env,actor,input){
 fields(input,['operation_id','plan_id','task_id','expected_task_revision','lease_seconds']);
 const operation=uuid(input.operation_id,'operation_id'),plan=await planRow(env,input.plan_id),taskId=uuid(input.task_id,'task_id');
 const revision=integer(input.expected_task_revision,'task_revision',0,1000000000),lease=integer(input.lease_seconds??60,'lease_seconds',1,120);
 await retentionPolicyFence(env,plan);await authority(env,actor);
 const fingerprint=await retentionInputHash({input:{...input,lease_seconds:lease},actor_id:actor.userId,session_id:actor.sessionId});
 const prior=await first(env,'SELECT * FROM privacy_retention_claims WHERE operation_id=?',operation);
 if(prior){if(prior.input_sha256!==fingerprint)retentionFail('privacy_retention_operation_conflict');return claimProjection(prior);}
 const task=await first(env,'SELECT * FROM privacy_retention_tasks WHERE id=? AND plan_id=?',taskId,plan.id);
 if(!task||task.revision!==revision||task.state==='verified')retentionFail('privacy_retention_task_changed');
 const at=seconds(),claimId=id(),fence=task.fence+1,guard=actorGuard(env,actor);
 try{await retentionBatch(env,[guard.insert,env.DB.prepare(`INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,
  (CASE WHEN EXISTS(SELECT 1 FROM privacy_retention_tasks t LEFT JOIN privacy_retention_claims c ON c.id=t.claim_id
   WHERE t.id=? AND t.plan_id=? AND t.revision=? AND t.state!='verified' AND (t.state!='claimed' OR c.id IS NULL OR c.expires_seconds<=max(?,unixepoch()))) AND
   NOT EXISTS(SELECT 1 FROM privacy_retention_tasks t JOIN privacy_retention_claims c ON c.id=t.claim_id WHERE t.plan_id=? AND t.state='claimed' AND c.expires_seconds>max(?,unixepoch()) AND t.id!=?) AND
   EXISTS(SELECT 1 FROM runtime_config WHERE key='privacy:retention:approved:v1' AND revision=? AND value_json=? AND julianday(json_extract(value_json,'$.expires_at'))>julianday('now')) AND
   coalesce((SELECT revision FROM privacy_review_heads WHERE request_id=?),0)=?
   THEN 1 ELSE 0 END)`).bind(id(),plan.id,task.class_name,taskId,plan.id,revision,at,plan.id,at,taskId,plan.policy_config_revision,plan.policy_json,plan.request_id,plan.review_revision),
  env.DB.prepare('INSERT INTO privacy_retention_claims(id,operation_id,task_id,actor_id,session_id,input_sha256,expected_revision,fence,claimed_seconds,expires_seconds) VALUES(?,?,?,?,?,?,?,?,?,?)').bind(claimId,operation,taskId,actor.userId,actor.sessionId,fingerprint,revision,fence,at,at+lease),
  env.DB.prepare("UPDATE privacy_retention_tasks SET state='claimed',claim_id=?,revision=revision+1,fence=? WHERE id=? AND revision=?").bind(claimId,fence,taskId,revision),
  env.DB.prepare("UPDATE privacy_retention_plans SET state='processing',revision=revision+1 WHERE id=?").bind(plan.id),
  env.DB.prepare('DELETE FROM privacy_retention_guards WHERE plan_id=?').bind(plan.id),guard.remove]);
 }catch(error){const replay=await first(env,'SELECT * FROM privacy_retention_claims WHERE operation_id=?',operation);if(replay&&replay.input_sha256===fingerprint){await authority(env,actor);return claimProjection(replay);}throw error;}
 return claimProjection(await first(env,'SELECT * FROM privacy_retention_claims WHERE id=?',claimId));
}
function claimProjection(row){return {contract_version:1,claim_id:row.id,task_id:row.task_id,operation_id:row.operation_id,fence:row.fence,claimed_seconds:row.claimed_seconds,expires_seconds:row.expires_seconds,erasure_completed:false};}

export async function retentionStatus(env,actor,{plan_id}){
 const plan=await planRow(env,plan_id);await authority(env,actor);
 let current=true;try{await retentionPolicyFence(env,plan);const snapshot=await retentionSnapshot(env,plan.subject_id);const {checkRetentionSource}=await import('./privacy_retention_tasks.js');await checkRetentionSource(env,plan,await taskRows(env,plan.id),snapshot);}catch{current=false;}
 const tasks=await taskRows(env,plan.id);await authority(env,actor);
 return projection(plan,tasks,{current});
}

/** Lookup never starts or retries an effect. Unseen is an unknown outcome:
 * the original request may still arrive and its UUID must remain reserved. */
export async function resolveRetentionOperation(env,actor,input){
 fields(input,['operation_kind','operation_id']);await authority(env,actor);
 const operation=uuid(input.operation_id,'operation_id'),kind=input.operation_kind;
 if(!['plan','claim','execute'].includes(kind))retentionFail('privacy_retention_input_invalid',400);
 let row,receipt=null;
 if(kind==='plan'){
  row=await first(env,'SELECT id,request_id,operation_id,policy_sha256,source_id FROM privacy_retention_plans WHERE operation_id=? AND actor_id=? AND session_id=?',operation,actor.userId,actor.sessionId);
  if(row)receipt={plan_id:row.id,request_id:row.request_id,operation_id:row.operation_id,policy_sha256:row.policy_sha256,source_id:row.source_id};
 }else if(kind==='claim'){
  row=await first(env,'SELECT * FROM privacy_retention_claims WHERE operation_id=? AND actor_id=? AND session_id=?',operation,actor.userId,actor.sessionId);
  if(row)receipt=claimProjection(row);
 }else{
  row=await first(env,'SELECT o.* FROM privacy_retention_outcomes o JOIN privacy_retention_claims c ON c.id=o.claim_id WHERE o.operation_id=? AND c.actor_id=? AND c.session_id=?',operation,actor.userId,actor.sessionId);
  if(row)receipt=JSON.parse(row.outcome_json);
 }
 await authority(env,actor);
 return {contract_version:1,scope:'approved_eligible_data_disposition_operation',operation_kind:kind,operation_id:operation,
  observed:!!row,receipt,currentness_not_asserted:true,erasure_completed:false,all_data_erased:false};
}

export async function reconcileRetentionPlan(env,actor,{plan_id}){
 const plan=await planRow(env,plan_id);await retentionPolicyFence(env,plan);await authority(env,actor);
 const tasks=await taskRows(env,plan.id),current=await retentionSnapshot(env,plan.subject_id),original=JSON.parse(plan.scope_json);
 const {checkRetentionSource}=await import('./privacy_retention_tasks.js');await checkRetentionSource(env,plan,tasks,current);
 const complete=tasks.every(t=>t.state==='verified'),guard=actorGuard(env,actor);
 if(current.summary.holds.length||current.summary.in_flight_unresolved||stableJson(current.summary.balances)!==stableJson(original.balances)||current.summary.ledger_sha256!==plan.ledger_sha256)retentionFail('privacy_retention_source_changed');
 await retentionBatch(env,[guard.insert,...snapshotCompareGuards(env,plan,current,'reconcile'),env.DB.prepare(`INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,'reconcile',(CASE WHEN EXISTS(SELECT 1 FROM runtime_config WHERE key='privacy:retention:approved:v1' AND revision=? AND value_json=? AND julianday(json_extract(value_json,'$.expires_at'))>julianday('now')) AND coalesce((SELECT revision FROM privacy_review_heads WHERE request_id=?),0)=? THEN 1 ELSE 0 END)`).bind(id(),plan.id,plan.policy_config_revision,plan.policy_json,plan.request_id,plan.review_revision),env.DB.prepare('UPDATE privacy_retention_plans SET state=?,revision=revision+1 WHERE id=?').bind(complete?'disposition_verified':'blocked',plan.id),env.DB.prepare('DELETE FROM privacy_retention_guards WHERE plan_id=?').bind(plan.id),guard.remove]);
 return {...projection(await planRow(env,plan.id),tasks),eligible_dispositions_verified:complete,all_actual_copy_outcomes_verified:complete,financial_journal_preserved:true,
  retained_classes:tasks.filter(t=>t.action==='retain').map(t=>t.class_name)};
}
