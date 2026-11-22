import {SQL_CHUNK_ROWS,ownRowKey,rowChunkState,rowChunkOutcome} from './privacy_retention_chunks.js';
import {digest,first,id,integer,stableJson,uuid} from './core.js';
import {engineTables,retentionEngineRows,engineRowsGuard,erasableTables,ownRows,retentionSnapshot,sourceRowsGuard,snapshotCompareGuards} from './privacy_retention_catalog.js';
import {actorGuard,authority,retentionFail,retentionInputHash,retentionPolicyFence,retentionBatch,seconds,taskAction,approvedQuarantineContinuation,priorRetentionWork,priorRetentionWorkCounts} from './privacy_retention_policy.js';
const all=async(env,sql,...args)=>(await env.DB.prepare(sql).bind(...args).all()).results;
const images=async rows=>Object.fromEntries(await Promise.all(Object.entries(rows).map(async([name,value])=>[name,{count:value.length,sha256:await digest(stableJson([...value].sort((a,b)=>stableJson(a).localeCompare(stableJson(b)))))}])));
async function identity(rows){return retentionInputHash({users:rows.users.map(({access_status,updated_at,revision,...r})=>r),sessions:rows.auth_sessions.map(({revoked_at,revocation_reason,...r})=>r)});}

/** A verified task supplies its exact postimage. Unknown outcomes may use only
 * observed absence/quarantine plus the original task identity, never a caller's
 * assertion that an operation succeeded. */
export async function checkRetentionSource(env,plan,tasks,current,{resume=null}={}){
 const original=JSON.parse(plan.scope_json),expected={...original.tables},objects=new Map(original.objects.map(o=>[o.key,o]));
 for(const task of tasks){
  const checkpoint=await rowChunkState(env,task,plan);if(checkpoint?.post)Object.assign(expected,checkpoint.post.tables);
  if(task.state==='verified'){const post=task.post_images_json?JSON.parse(task.post_images_json):{};Object.assign(expected,post.tables??{});for(const object of post.objects??[])objects.set(object.key,object);}
 }
 const permitted=new Set();
 if(resume&&erasableTables.includes(resume.class_name)&&!JSON.parse(resume.expected_json).row_chunks&&ownRows(resume.class_name,current.rows[resume.class_name],plan.subject_id).length===0){
  const target=JSON.parse(resume.expected_json),context=current.rows[resume.class_name].filter(r=>r.user_id!==plan.subject_id);
  if(await retentionInputHash(context)===target.context_sha256)permitted.add(resume.class_name);
 }
 if(resume?.class_name==='access'){
  const target=JSON.parse(resume.expected_json),barrier=await first(env,'SELECT * FROM privacy_retention_barriers WHERE subject_id=?',plan.subject_id);
  if(barrier&&await identity(current.rows)===target.identity_sha256&&current.rows.users.every(r=>{const before=target.user_states.find(u=>u.id===r.id);return before&&r.access_status===(before.access_status==='active'?'suspended':before.access_status)&&r.revision===before.revision+(before.access_status==='active'?1:0);})&&current.rows.auth_sessions.every(r=>r.user_id!==plan.subject_id||r.revoked_at!==null)&&current.rows.admin_sessions.length===0)
   ['users','auth_sessions','admin_sessions'].forEach(n=>permitted.add(n));
 }
 const effects=resume?.class_name==='r2:upload_objects'?await all(env,'SELECT * FROM privacy_retention_effects WHERE task_id=?',resume.id):[];
 if(effects.length){const target=JSON.parse(resume.expected_json);if(await retentionInputHash(current.rows.upload_objects.map(r=>r.user_id===plan.subject_id?(({status,deleted_at,...v})=>v)(r):r))!==target.catalog_identity_sha256)retentionFail('privacy_retention_object_catalog_changed');for(const row of current.rows.upload_objects.filter(r=>r.user_id===plan.subject_id)){const original=target.catalog_lifecycle.find(v=>v.id===row.id),effect=effects.find(e=>e.object_key===row.object_key);if(!original||row.status!==original.status&&!(effect&&row.status==='deleted'&&typeof row.deleted_at==='string'&&new Date(row.deleted_at).toISOString()===row.deleted_at)||row.status===original.status&&row.deleted_at!==original.deleted_at)retentionFail('privacy_retention_object_catalog_changed');}permitted.add('upload_objects');}
 for(const [name,value]of Object.entries(current.summary.tables))if(!permitted.has(name)&&stableJson(value)!==stableJson(expected[name]))retentionFail('privacy_retention_scope_changed');
 if(current.summary.schema_sha256!==plan.schema_sha256||current.summary.ledger_sha256!==plan.ledger_sha256||stableJson(current.summary.balances)!==stableJson(original.balances))retentionFail('privacy_retention_financial_source_changed');
 if(current.summary.objects.length!==objects.size)retentionFail('privacy_retention_object_scope_changed');
 for(const object of current.summary.objects){const before=objects.get(object.key);if(stableJson(object)===stableJson(before))continue;
  const started=effects.find(e=>e.object_key===object.key&&e.object_version===before?.version&&e.source_sha256===before?.body_sha256);
  if(!started||object.present||object.owner_user_id!==plan.subject_id||object.catalog_sha256!==before.catalog_sha256||object.catalog_size!==before.catalog_size||object.record_id!==before.record_id||object.class_name!==before.class_name)retentionFail('privacy_retention_object_changed');
 }
}

function executionGuard(env,actor,plan,task,claim,{effect=false}={}){
 const key=id(),at=seconds();
 return env.DB.prepare(`INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,(CASE WHEN
  EXISTS(SELECT 1 FROM privacy_retention_tasks t JOIN privacy_retention_claims c ON c.id=t.claim_id WHERE t.id=? AND t.plan_id=? AND t.state='claimed' AND t.claim_id=? AND t.fence=? AND c.actor_id=? AND c.session_id=? AND c.expires_seconds>max(?,unixepoch())) AND
  EXISTS(SELECT 1 FROM runtime_config WHERE key='privacy:retention:approved:v1' AND revision=? AND value_json=? AND julianday(json_extract(value_json,'$.expires_at'))>julianday('now')) AND
  coalesce((SELECT revision FROM privacy_review_heads WHERE request_id=?),0)=?
  ${effect?`AND NOT EXISTS(SELECT 1 FROM privacy_holds WHERE user_id=? AND active=1)
  AND NOT EXISTS(SELECT 1 FROM native_reservations WHERE user_id=? AND state NOT IN('completed','rejected'))
  AND NOT EXISTS(SELECT 1 FROM roster_imports WHERE user_id=? AND state IN('processing','ambiguous'))
  AND NOT EXISTS(SELECT 1 FROM auth_otp_challenges WHERE identity_value IN(SELECT phone FROM users WHERE id=? UNION SELECT email FROM users WHERE id=?) AND status IN('dispatching','delivery_unknown'))`:''}
  THEN 1 ELSE 0 END)`).bind(key,plan.id,task.class_name,task.id,plan.id,claim.id,claim.fence,actor.userId,actor.sessionId,at,plan.policy_config_revision,plan.policy_json,plan.request_id,plan.review_revision,...(effect?Array(5).fill(plan.subject_id):[]));
}
async function commit(env,actor,plan,task,claim,operation,fingerprint,outcome,post={},writes=[],{effect=false}={}){
 const guard=actorGuard(env,actor);outcome={...outcome,source_id:plan.source_id,policy_sha256:plan.policy_sha256,observation_only:true,currentness_not_asserted:true};const json=stableJson(outcome);
 try{await retentionBatch(env,[guard.insert,executionGuard(env,actor,plan,task,claim,{effect}),...writes,
  env.DB.prepare('INSERT INTO privacy_retention_outcomes(operation_id,task_id,claim_id,fence,input_sha256,outcome_json,observed_seconds) VALUES(?,?,?,?,?,?,?)').bind(operation,task.id,claim.id,claim.fence,fingerprint,json,seconds()),
  env.DB.prepare('UPDATE privacy_retention_tasks SET state=?,revision=revision+1,post_images_json=?,outcome_json=? WHERE id=? AND claim_id=? AND fence=?').bind(outcome.verified?'verified':'blocked',stableJson(post),json,task.id,claim.id,claim.fence),
  env.DB.prepare("UPDATE privacy_retention_plans SET state=?,revision=revision+1 WHERE id=?").bind(outcome.verified?'processing':'blocked',plan.id),
  env.DB.prepare('DELETE FROM privacy_retention_guards WHERE plan_id=?').bind(plan.id),guard.remove]);
 }catch(error){const replay=await first(env,'SELECT * FROM privacy_retention_outcomes WHERE operation_id=?',operation);if(replay&&replay.input_sha256===fingerprint){await authority(env,actor);return JSON.parse(replay.outcome_json);}throw error;}
 return outcome;
}
const blocked=reason=>({verified:false,disposition:'blocked',reason,erasure_completed:false,all_data_erased:false});

function barrierGuard(env,plan,className,barrier,{continuation=false}={}){
 const row=barrier?`AND EXISTS(SELECT 1 FROM privacy_retention_barriers WHERE subject_id=? AND plan_id=? AND source_id=? AND policy_sha256=? AND activated_seconds=?)`:'';
 return env.DB.prepare(`INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,(CASE WHEN
  (SELECT count(*) FROM privacy_retention_barriers WHERE subject_id=?)=? ${row}
  ${continuation?`AND NOT EXISTS(${priorRetentionWork.claims}) AND NOT EXISTS(${priorRetentionWork.effects})`:''}
  THEN 1 ELSE 0 END)`).bind(id(),plan.id,className,plan.subject_id,barrier?1:0,
   ...(barrier?[barrier.subject_id,barrier.plan_id,barrier.source_id,barrier.policy_sha256,barrier.activated_seconds]:[]),
   ...(continuation?[plan.subject_id,plan.id,plan.subject_id,plan.id]:[]));
}
async function committedContinuation(env,plan,proof){
 if(!proof)return false;
 const found=await first(env,`SELECT 1 AS observed FROM privacy_retention_outcomes o
  JOIN privacy_retention_tasks t ON t.id=o.task_id WHERE t.plan_id=? AND t.class_name='access'
   AND json_extract(o.outcome_json,'$.verified')=1
   AND json_extract(o.outcome_json,'$.disposition')='access_quarantine_continued'
   AND json_extract(o.outcome_json,'$.source_id')=? AND json_extract(o.outcome_json,'$.policy_sha256')=?
   AND json_extract(o.outcome_json,'$.continuation.previous_barrier_sha256')=?
   AND json_extract(o.outcome_json,'$.continuation.previous_plan_id')=?
   AND json_extract(o.outcome_json,'$.continuation.approval_evidence_sha256')=? LIMIT 1`,
  plan.id,plan.source_id,plan.policy_sha256,proof.previous_barrier_sha256,proof.previous_plan_id,proof.approval_evidence_sha256);
 return !!found;
}

export async function executeRetentionTask(env,actor,input){
 const allowed=['operation_id','claim_id','fence'];
 if(!input||typeof input!=='object'||Object.keys(input).some(k=>!allowed.includes(k)))retentionFail('privacy_retention_input_invalid',400);
 const operation=uuid(input.operation_id,'operation_id'),claimId=uuid(input.claim_id,'claim_id'),fence=integer(input.fence,'fence',1,1000000000);
 await authority(env,actor);
 const fingerprint=await retentionInputHash({input,actor_id:actor.userId,session_id:actor.sessionId});
 const prior=await first(env,'SELECT * FROM privacy_retention_outcomes WHERE operation_id=?',operation);
 if(prior){if(prior.input_sha256!==fingerprint)retentionFail('privacy_retention_operation_conflict');return JSON.parse(prior.outcome_json);}
 const claim=await first(env,'SELECT * FROM privacy_retention_claims WHERE id=?',claimId);
 if(!claim||claim.actor_id!==actor.userId||claim.session_id!==actor.sessionId||claim.fence!==fence||claim.expires_seconds<=seconds())retentionFail('privacy_retention_claim_stale');
 const task=await first(env,'SELECT * FROM privacy_retention_tasks WHERE id=? AND claim_id=? AND fence=?',claim.task_id,claimId,fence);
 if(!task||task.state!=='claimed'){
  const replay=await first(env,'SELECT * FROM privacy_retention_outcomes WHERE operation_id=?',operation);
  if(replay&&replay.input_sha256===fingerprint)return JSON.parse(replay.outcome_json);
  retentionFail('privacy_retention_claim_stale');
 }
 const plan=await first(env,'SELECT * FROM privacy_retention_plans WHERE id=?',task.plan_id),approved=await retentionPolicyFence(env,plan);
 const current=await retentionSnapshot(env,plan.subject_id),tasks=await all(env,'SELECT * FROM privacy_retention_tasks WHERE plan_id=?',plan.id);
 await checkRetentionSource(env,plan,tasks,current,{resume:task});
 const decision=taskAction(approved.policy.rules[task.class_name]);
 const stop=reason=>commit(env,actor,plan,task,claim,operation,fingerprint,blocked(reason));
 if(decision.blocked)return stop(decision.blocked);
 if(task.class_name.startsWith('external:')){
  // No deployed backup/export/processor disposition adapter exists. A policy
  // statement or operator-entered hash cannot become a verified copy outcome.
  return stop('external_copy_adapter_and_actual_inventory_required');
 }
 if(decision.action==='retain'){
  if(engineTables.includes(task.class_name)){
   const observed=await retentionEngineRows(env,plan.id,task.class_name);
   if(task.class_name==='privacy_retention_guards'&&observed.rows.length)return stop('orphan_retention_guard_unresolved');
   const writes=snapshotCompareGuards(env,plan,current,task.class_name);
   if(task.class_name!=='privacy_retention_guards')writes.push(engineRowsGuard(env,plan.id,task.class_name,observed));
   return commit(env,actor,plan,task,claim,operation,fingerprint,{verified:true,disposition:'control_records_retained',engine_rows_observed:observed.rows.length,engine_snapshot_sha256:await retentionInputHash(observed.rows),retained_until:approved.policy.rules[task.class_name].deadline,erasure_completed:false,all_data_erased:false},{},writes);
  }
  const copies=current.summary.objects.filter(o=>o.class_name===task.class_name);
  if(copies.some(o=>!o.present))return stop('retained_object_missing');
  return commit(env,actor,plan,task,claim,operation,fingerprint,{verified:true,disposition:'retained',retained_until:approved.policy.rules[task.class_name].deadline,erasure_completed:false,all_data_erased:false},{},snapshotCompareGuards(env,plan,current,task.class_name));
 }
 if(current.summary.holds.length)return stop('legal_hold_active');
 if(current.summary.in_flight_unresolved)return stop('in_flight_operation_unresolved');
 const activeBarrier=await first(env,'SELECT * FROM privacy_retention_barriers WHERE subject_id=?',plan.subject_id);
 const ownBarrier=activeBarrier?.plan_id===plan.id&&activeBarrier.policy_sha256===plan.policy_sha256&&activeBarrier.source_id===plan.source_id;
 const continuation=await approvedQuarantineContinuation(env,plan,approved.policy,activeBarrier);
 if(task.class_name==='access'&&decision.action==='quarantine'){
  const at=seconds(),date=new Date(at*1000).toISOString(),expected=JSON.parse(task.expected_json);
  if(await identity(current.rows)!==expected.identity_sha256)return stop('access_identity_changed');
  if(activeBarrier&&!ownBarrier&&!continuation||approved.policy.quarantine_continuation&&!continuation)return stop('prior_quarantine_requires_explicit_recovery_authority');
  if(continuation){const prior=await priorRetentionWorkCounts(env,plan.subject_id,plan.id);if(prior.active_claim_count||prior.unresolved_effect_count)return stop('prior_retention_work_unresolved');}
  const users=current.rows.users.map(r=>r.id===plan.subject_id&&r.access_status==='active'?{...r,access_status:'suspended',updated_at:date,revision:r.revision+1}:r);
  const sessions=current.rows.auth_sessions.map(r=>r.user_id===plan.subject_id&&r.revoked_at===null?{...r,revoked_at:at,revocation_reason:'privacy_retention_quarantine'}:r);
  const post={tables:await images({users,auth_sessions:sessions,admin_sessions:[]})};
  const writes=[...snapshotCompareGuards(env,plan,current,task.class_name),barrierGuard(env,plan,task.class_name,activeBarrier,{continuation:!!continuation}),env.DB.prepare('INSERT INTO privacy_retention_barriers(subject_id,plan_id,source_id,policy_sha256,activated_seconds) VALUES(?,?,?,?,?) ON CONFLICT(subject_id) DO NOTHING').bind(plan.subject_id,plan.id,plan.source_id,plan.policy_sha256,at),
   env.DB.prepare("UPDATE users SET access_status='suspended',updated_at=? WHERE id=? AND access_status='active'").bind(date,plan.subject_id),
   env.DB.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='privacy_retention_quarantine' WHERE user_id=? AND revoked_at IS NULL").bind(at,plan.subject_id),
   env.DB.prepare('DELETE FROM admin_sessions WHERE user_id IN(SELECT admin_user_id FROM admin_principal_links WHERE user_id=?)').bind(plan.subject_id)];
  return commit(env,actor,plan,task,claim,operation,fingerprint,{verified:true,disposition:continuation?'access_quarantine_continued':'access_quarantined',...(continuation?{continuation}:{}),session_reapproval_required:true,erasure_completed:false,all_data_erased:false},post,writes,{effect:true});
 }
 if(!ownBarrier&&!await committedContinuation(env,plan,continuation))return stop('subject_write_barrier_required');
 if(continuation){const prior=await priorRetentionWorkCounts(env,plan.subject_id,plan.id);if(prior.active_claim_count||prior.unresolved_effect_count)return stop('prior_retention_work_unresolved');}
 if(erasableTables.includes(task.class_name)&&decision.action==='erase'){
  const table=task.class_name,rows=current.rows[table],targets=ownRows(table,rows,plan.subject_id),expected=JSON.parse(task.expected_json),checkpoint=await rowChunkState(env,task,plan);
  if(!checkpoint&&targets.length&&stableJson(current.summary.tables[table])!==stableJson({count:expected.count,sha256:expected.sha256}))return stop('erase_source_changed');
  const key=ownRowKey(table),remaining=checkpoint?expected.target_ids.filter(value=>!checkpoint.absent.has(value)):expected.target_ids;
  if(checkpoint&&(targets.length!==remaining.length||targets.some(row=>!remaining.includes(row[key]))))return stop('erase_chunk_source_changed');
  const ids=checkpoint?remaining.slice(0,SQL_CHUNK_ROWS):targets.map(row=>row[key]),selected=new Set(ids),after=rows.filter(row=>row.user_id!==plan.subject_id||!selected.has(row[key]));
  const post={tables:await images({[table]:after})};
  const writes=[...snapshotCompareGuards(env,plan,current,task.class_name),barrierGuard(env,plan,task.class_name,activeBarrier,{continuation:!!continuation}),...sourceRowsGuard(env,table,rows,plan.subject_id,{id:id(),planId:plan.id})];
  // Historical whole-task plans keep their original one-parameter delete.
  // Only a chunk-marked plan may use the bounded, retained target-ID slice.
  if(ids.length)writes.push(checkpoint?env.DB.prepare('DELETE FROM "'+table+'" WHERE user_id=? AND "'+key+'" IN('+ids.map(()=>'?').join(',')+')').bind(plan.subject_id,...ids):env.DB.prepare('DELETE FROM "'+table+'" WHERE user_id=?').bind(plan.subject_id));
  const absent=checkpoint&&ids.length?' AND NOT EXISTS(SELECT 1 FROM "'+table+'" WHERE user_id=? AND "'+key+'" IN('+ids.map(()=>'?').join(',')+'))':'';
  writes.push(env.DB.prepare('INSERT INTO privacy_retention_guards(id,plan_id,class_name,passed) SELECT ?,?,?,(CASE WHEN (SELECT count(*) FROM "'+table+'" WHERE user_id=?)=?'+absent+' THEN 1 ELSE 0 END)').bind(id(),plan.id,table,plan.subject_id,targets.length-ids.length,...(checkpoint&&ids.length?[plan.subject_id,...ids]:[])));
  const outcome=checkpoint?await rowChunkOutcome(checkpoint,ids,post):{verified:true,disposition:'own_rows_absence_verified',rows_erased_or_confirmed_absent:expected.target_ids.length,erasure_completed:false,all_data_erased:false};
  return commit(env,actor,plan,task,claim,operation,fingerprint,outcome,post,writes,{effect:true});
 }
 if(task.class_name==='r2:upload_objects'&&decision.action==='erase')return eraseCatalogObjects(env,actor,plan,task,claim,operation,fingerprint,approved.policy,current,{barrier:activeBarrier,continuation:!!continuation});
 return stop('immutable_or_unimplemented_class_adapter');
}

async function eraseCatalogObjects(env,actor,plan,task,claim,operation,fingerprint,policy,current,{barrier,continuation}){
 const stop=reason=>commit(env,actor,plan,task,claim,operation,fingerprint,blocked(reason));
 const expected=JSON.parse(task.expected_json).objects.filter(o=>o.owner_user_id===plan.subject_id);
 if(!policy.writer_fence.generic_upload_catalog_only||policy.writer_fence.unknown_in_flight)return stop('object_writer_drain_or_chunk_coverage_required');
 const effects=await all(env,'SELECT * FROM privacy_retention_effects WHERE task_id=?',task.id);
 let candidate=null;
 for(const object of expected){
  if(object.body_sha256!==object.catalog_sha256||object.size!==object.catalog_size)return stop('catalog_body_format_unverified');
  const observed=current.summary.objects.find(o=>o.key===object.key),started=effects.find(e=>e.object_key===object.key);
  if(started&&(started.object_version!==object.version||started.source_sha256!==object.body_sha256))return stop('object_effect_identity_changed');
  if(observed?.present&&started?.claim_id===claim.id)retentionFail('privacy_retention_effect_outcome_unknown');
  if(!observed?.present&&!started)return stop('object_absence_without_retained_effect_identity');
  if(observed?.present&&!candidate)candidate={object,started};
 }
 if(candidate){
  const {object,started}=candidate,before=await env.PRIVATE_MEDIA.head(object.key);
  if(!before||before.version!==object.version||before.etag!==object.etag||before.size!==object.size)return stop('object_version_changed');
  const guard=actorGuard(env,actor),writes=[guard.insert,executionGuard(env,actor,plan,task,claim,{effect:true}),...snapshotCompareGuards(env,plan,current,task.class_name),barrierGuard(env,plan,task.class_name,barrier,{continuation})];
  if(!started)writes.push(env.DB.prepare('INSERT INTO privacy_retention_effects(operation_id,task_id,claim_id,fence,source_sha256,object_key,object_version,started_seconds) VALUES(?,?,?,?,?,?,?,?)').bind(id(),task.id,claim.id,claim.fence,object.body_sha256,object.key,object.version,seconds()));
  writes.push(env.DB.prepare('DELETE FROM privacy_retention_guards WHERE plan_id=?').bind(plan.id),guard.remove);
  // This admission runs again for an earlier send-start: a new hold, revoked
  // reviewer or changed source must prevent a renewed provider request.
  await retentionBatch(env,writes);
  // R2 has no conditional delete. An approved, exact writer-drain receipt and
  // active application barrier are required; HEAD cannot prove quiescence.
  await authority(env,actor);if(claim.expires_seconds<=seconds())retentionFail('privacy_retention_claim_stale');
  await env.PRIVATE_MEDIA.delete(object.key);
  if(await env.PRIVATE_MEDIA.head(object.key)!==null||await env.PRIVATE_MEDIA.get(object.key)!==null)return stop('object_absence_unconfirmed');
 }
 // Re-read actual storage and every source after the effect. A lost response
 // leaves the immutable send-start, and a subsequent claim reconciles absence.
 const observed=await retentionSnapshot(env,plan.subject_id),tasks=await all(env,'SELECT * FROM privacy_retention_tasks WHERE plan_id=?',plan.id);
 await checkRetentionSource(env,plan,tasks,observed,{resume:task});
 const absent=expected.filter(o=>!observed.summary.objects.find(v=>v.key===o.key)?.present),keys=new Set(absent.map(o=>o.key));
 const at=new Date().toISOString(),uploadRows=observed.rows.upload_objects.map(r=>keys.has(r.object_key)&&r.status!=='deleted'?{...r,status:'deleted',deleted_at:at}:r);
 const writes=[...snapshotCompareGuards(env,plan,observed,task.class_name),barrierGuard(env,plan,task.class_name,barrier,{continuation})];
 for(const object of absent)writes.push(env.DB.prepare("UPDATE upload_objects SET status='deleted',deleted_at=? WHERE id=? AND user_id=? AND object_key=? AND sha256=? AND status!='deleted'").bind(at,object.record_id,plan.subject_id,object.key,object.catalog_sha256));
 const complete=absent.length===expected.length;
 const outcome={verified:complete,disposition:complete?'catalog_object_absence_verified':'partial',...(complete?{}:{reason:'more_objects_remaining'}),objects_verified_absent:absent.length,objects_remaining:expected.length-absent.length,erasure_completed:false,all_data_erased:false};
 const post={tables:await images({upload_objects:uploadRows}),objects:absent.map(o=>observed.summary.objects.find(v=>v.key===o.key))};
 return commit(env,actor,plan,task,claim,operation,fingerprint,outcome,post,writes,{effect:true});
}
