import {randomUUID} from 'node:crypto';
import {SafeError,UUID,object,invalid,unavailable} from './config.mjs';
import {SHA,canonical,digest,parseContext,parseInspection,parsePlan,parseClaim,parseLookup,parseOutcome,supportedTask,inspectInput,assertBinding,retentionBlocked} from './retention_contract.mjs';

const uuid=value=>{if(!UUID.test(value??''))invalid();return value;};
function current(plan){if(!plan.policy_current)retentionBlocked('retention_approval_stale');return plan;}
function taskOf(plan,id){const task=plan.tasks.find(row=>row.task_id===id);if(!task||task.state==='verified'||!supportedTask(task))retentionBlocked('retention_adapter_unavailable');return task;}
function scopeSafe(scope){if(scope.active_hold_count||scope.in_flight_unresolved)retentionBlocked('retention_obligations_unresolved');return scope;}
function expectedPlan(plan,task){return {plan_id:plan.plan_id,request_id:plan.request_id,source_id:plan.source_id,policy_sha256:plan.policy_sha256,schema_sha256:plan.schema_sha256,scope_snapshot_sha256:plan.scope_snapshot_sha256,task:task??null};}
function same(left,right){if(canonical(left)!==canonical(right))retentionBlocked('retention_preview_stale');}
function planReceipt(plan,input){
 if(plan.request_id!==input.p_request_id||plan.policy_sha256!==input.p_policy_sha256||plan.source_id!==input.p_expected_source_id)unavailable();
 return {plan_id:plan.plan_id,request_id:plan.request_id,operation_id:input.p_operation_id,policy_sha256:plan.policy_sha256,source_id:plan.source_id};
}
function parsedPlanReceipt(value,input){
 if(!object(value)||Object.keys(value).sort().join(',')!=='operation_id,plan_id,policy_sha256,request_id,source_id'||!UUID.test(value.plan_id??'')||value.operation_id!==input.p_operation_id||value.request_id!==input.p_request_id||value.policy_sha256!==input.p_policy_sha256||value.source_id!==input.p_expected_source_id)unavailable();return value;
}
function outcome(value,preview){const result=parseOutcome(value);if(result.source_id!==preview.expected.source_id||result.policy_sha256!==preview.expected.policy_sha256)unavailable();return result;}
export function displayRecord(record){
 const {binding,...preview}=record.preview;
 return {preview_sha256:record.preview_sha256,state:record.state,dispatches:record.dispatches,
  preview:{...preview,operator:{origin:binding.origin,account_id:binding.account_id,principal_id:binding.principal_id,role:binding.role}},
  receipt:record.receipt,observations:record.observations,
  erasure_completed:false,all_data_erased:false,approval_created:false,
  confirmation:record.state==='prepared'?'APPLY '+record.preview_sha256:'RETRY '+record.preview_sha256};
}
export class RetentionOperator {
 constructor(api,journal){this.api=api;this.journal=journal;}
 async context(){return this.api.withSession(async session=>parseContext(await session.read('context')));}
 async inspect(request,revision,source){const input=inspectInput(request,revision,source);return this.api.withSession(async session=>parseInspection(await session.read('inspect',input),input));}
 async status(plan){uuid(plan);return this.api.withSession(async session=>{
  const value=parsePlan(await session.read('status',{p_plan_id:plan}),plan);
  return {...value,supported_tasks:value.tasks.filter(supportedTask).map(task=>task.task_id),unsupported_tasks:value.tasks.filter(task=>!supportedTask(task)).map(task=>task.task_id)};
 });}
 #unresolved(kind,field,value){return this.journal.list().some(row=>row.preview.kind===kind&&row.preview.input[field]===value&&!['observed','cancelled'].includes(row.state));}
 async #prepare(kind,build){
  const operation=randomUUID();
  const preview=await this.api.withSession(async session=>{
   const {input,expected}=await build(session,operation);
   return {contract_version:1,scope:'approved_eligible_data_disposition',kind,operation_id:operation,binding:session.binding,input,expected,created_at:new Date().toISOString()};
  });
  return displayRecord(this.journal.save(preview));
 }
 async previewPlan(request,revision,source,policy){
  const input=inspectInput(request,revision,source);if(!SHA.test(policy??''))invalid();
  if(this.#unresolved('plan','p_request_id',request))retentionBlocked('retention_original_operation_unresolved');
  return this.#prepare('plan',async(session,operation)=>{
   const context=parseContext(await session.read('context'));if(context.source_id!==source)retentionBlocked('retention_source_changed');
   const inspection=scopeSafe(parseInspection(await session.read('inspect',input),input));
   return {input:{...input,p_policy_sha256:policy,p_operation_id:operation},expected:inspection};
  });
 }
 async previewClaim(planId,taskId){
  uuid(planId);uuid(taskId);
  if(this.#unresolved('claim','p_plan_id',planId))retentionBlocked('retention_original_operation_unresolved');
  return this.#prepare('claim',async(session,operation)=>{
   const plan=current(parsePlan(await session.read('status',{p_plan_id:planId}),planId)),task=taskOf(plan,taskId);
   // Known expired claims may be replaced under a new server fence. An
   // unknown claim is never replaced: recover/retry its original UUID first.
   this.#leaseReady(plan,task);
   return {input:{p_operation_id:operation,p_plan_id:planId,p_task_id:taskId,p_expected_task_revision:task.revision,p_lease_seconds:120},expected:expectedPlan(plan,task)};
  });
 }
 #leaseReady(plan,task){
  for(const row of this.journal.list()){
   if(row.preview.kind!=='claim'||row.preview.input.p_plan_id!==plan.plan_id||row.state!=='observed')continue;
   const claim=parseClaim(row.receipt,row.preview.input);
   if(plan.tasks.some(current=>current.task_id===claim.task_id&&current.state==='claimed'&&current.fence===claim.fence)&&claim.expires_seconds>Math.floor(Date.now()/1000))retentionBlocked('retention_lease_active');
  }
  if(task.state==='claimed'){
   const known=this.journal.list().find(row=>row.preview.kind==='claim'&&row.state==='observed'&&row.preview.input.p_task_id===task.task_id&&row.receipt?.fence===task.fence);
   if(!known||parseClaim(known.receipt,known.preview.input).expires_seconds>Math.floor(Date.now()/1000))retentionBlocked('retention_lease_unobserved');
  }
 }
 #resumeOriginal(session,operation,plan,task){
  const original=this.journal.operation(operation),p=original.preview;
  if(p.kind!=='execute'||original.dispatches<1||!['dispatching','unknown','observed'].includes(original.state)||original.state==='observed'&&original.receipt?.verified!==false)retentionBlocked('retention_resume_unavailable');
  assertBinding(session.binding,p.binding);
  const previous=this.journal.operation(p.expected.claim_operation);
  if(previous.preview.kind!=='claim'||previous.state!=='observed')retentionBlocked('retention_claim_unresolved');
  assertBinding(session.binding,previous.preview.binding);
  const claim=parseClaim(previous.receipt,previous.preview.input);
  same({...expectedPlan(plan,task),task:null},Object.fromEntries(Object.entries({...p.expected,task:null}).filter(([key])=>!['claim','claim_operation','resume_from_operation','source_currentness'].includes(key))));
  if(task.task_id!==claim.task_id||task.class_name!==p.expected.task.class_name||task.action!==p.expected.task.action||task.fence!==claim.fence||p.input.p_claim_id!==claim.claim_id||p.input.p_fence!==claim.fence)retentionBlocked('retention_resume_changed');
  const completedPartial=original.state==='observed'&&original.receipt.verified===false&&task.state==='blocked';
  if(!completedPartial&&claim.expires_seconds>Math.floor(Date.now()/1000))retentionBlocked('retention_lease_active');
 }
 async previewResumeClaim(executeOperation){
  const original=this.journal.operation(uuid(executeOperation)),planId=original.preview.expected.plan_id;
  if(original.preview.kind!=='execute'||!UUID.test(planId??''))retentionBlocked('retention_resume_unavailable');
  if(this.#unresolved('claim','p_plan_id',planId))retentionBlocked('retention_original_operation_unresolved');
  return this.#prepare('claim',async(session,operation)=>{
   const plan=parsePlan(await session.read('status',{p_plan_id:planId}),planId),task=taskOf(plan,original.preview.expected.task.task_id);
   this.#resumeOriginal(session,executeOperation,plan,task);this.#leaseReady(plan,task);
   return {input:{p_operation_id:operation,p_plan_id:planId,p_task_id:task.task_id,p_expected_task_revision:task.revision,p_lease_seconds:120},
    expected:{...expectedPlan(plan,task),resume_from_operation:executeOperation,source_currentness:'requires_execution_recheck'}};
  });
 }
 async previewExecute(claimOperation){
  const record=this.journal.operation(uuid(claimOperation));
  if(record.preview.kind!=='claim'||record.state!=='observed')retentionBlocked('retention_claim_unresolved');
  const claim=parseClaim(record.receipt,record.preview.input),planId=record.preview.input.p_plan_id;
  if(this.#unresolved('execute','p_claim_id',claim.claim_id))retentionBlocked('retention_original_operation_unresolved');
  return this.#prepare('execute',async(session,operation)=>{
   assertBinding(session.binding,record.preview.binding);
   const value=parsePlan(await session.read('status',{p_plan_id:planId}),planId),plan=record.preview.expected.resume_from_operation?value:current(value),task=taskOf(plan,claim.task_id);
   if(task.state!=='claimed'||task.fence!==claim.fence||claim.expires_seconds<=Math.floor(Date.now()/1000))retentionBlocked('retention_lease_expired');
   const resume=record.preview.expected.resume_from_operation?{resume_from_operation:record.preview.expected.resume_from_operation,source_currentness:'requires_execution_recheck'}:{};
   const expected={...expectedPlan(plan,task),...resume};same({...record.preview.expected,task:null},{...expected,task:null});
   return {input:{p_operation_id:operation,p_claim_id:claim.claim_id,p_fence:claim.fence},expected:{...expected,claim,claim_operation:claimOperation}};
  });
 }
 async previewReconcile(planId){uuid(planId);return this.#prepare('reconcile',async session=>{
  const plan=current(parsePlan(await session.read('status',{p_plan_id:planId}),planId));
  return {input:{p_plan_id:planId},expected:{...expectedPlan(plan),tasks_sha256:digest(plan.tasks),revision:plan.revision}};
 });}
 async #revalidate(session,preview){
  assertBinding(session.binding,preview.binding);const {kind,input,expected}=preview;
  if(kind==='plan'){
   const inspect=inspectInput(input.p_request_id,input.p_expected_review_revision,input.p_expected_source_id);
   same(scopeSafe(parseInspection(await session.read('inspect',inspect),inspect)),expected);return;
  }
  const value=parsePlan(await session.read('status',{p_plan_id:expected.plan_id}),expected.plan_id),plan=expected.resume_from_operation?value:current(value);
  if(kind==='reconcile'){same({...expectedPlan(plan),tasks_sha256:digest(plan.tasks),revision:plan.revision},expected);return;}
  const task=taskOf(plan,expected.task.task_id);
  same(expectedPlan(plan,task),Object.fromEntries(Object.entries(expected).filter(([key])=>!['claim','claim_operation','resume_from_operation','source_currentness'].includes(key))));
  if(kind==='claim'){if(expected.resume_from_operation)this.#resumeOriginal(session,expected.resume_from_operation,plan,task);this.#leaseReady(plan,task);return;}
  const original=this.journal.operation(expected.claim_operation);
  assertBinding(session.binding,original.preview.binding);
  if(original.state!=='observed'||original.preview.kind!=='claim')retentionBlocked('retention_claim_unresolved');
  same(parseClaim(original.receipt,original.preview.input),expected.claim);
  if(task.state!=='claimed'||task.fence!==input.p_fence||expected.claim.claim_id!==input.p_claim_id||expected.claim.expires_seconds<=Math.floor(Date.now()/1000))retentionBlocked('retention_lease_expired');
 }
 #response(value,preview){
  if(preview.kind==='plan')return planReceipt(parsePlan(value),preview.input);
  if(preview.kind==='claim')return parseClaim(value,preview.input);
  if(preview.kind==='execute')return outcome(value,preview);
  return parsePlan(value,preview.input.p_plan_id);
 }
 async apply(hash,confirm,{retry=false}={}){
  const record=this.journal.get(hash),preview=record.preview;
  if(typeof confirm!=='function'||(!retry&&record.state!=='prepared')||(retry&&!['unknown','dispatching'].includes(record.state))||retry&&preview.kind==='reconcile')retentionBlocked('retention_confirmation_required');
  const phrase=(retry?'RETRY ':'APPLY ')+hash;
  if(await confirm(displayRecord(record),phrase)!==phrase)throw new SafeError('cancelled','Confirmation did not match. No retention action was dispatched.');
  let dispatch=null,recoveredReceipt=null;
  try{
   const result=await this.api.withSession(async session=>{
    assertBinding(session.binding,preview.binding);
    // A retry first observes the original immutable receipt. If absent it
    // remains unknown, and only an explicitly confirmed identical call may
    // proceed under the current preview, claim, holds and policy checks.
    if(retry){
     const recovered=await this.#lookup(session,record);
     if(recovered.observed){recoveredReceipt=recovered.receipt;return recovered.receipt;}
    }
    await this.#revalidate(session,preview);
    dispatch=this.journal.begin(hash,{retry,expectedDispatches:record.dispatches});
    return this.#response(await session.write(preview.kind,preview.input),preview);
   });
   if(dispatch)this.journal.finish(hash,dispatch.dispatches,'observed',result);
   else if(recoveredReceipt)this.journal.observe(hash,{checked_at:new Date().toISOString(),observed:true},{receipt:recoveredReceipt,committed:true});
   return displayRecord(this.journal.get(hash));
  }catch(error){
   if(dispatch){try{this.journal.finish(hash,dispatch.dispatches,'unknown',null);}catch{/* Durable dispatch marker remains if completion persistence fails. */}
    throw new SafeError('retention_outcome_unknown',`The original ${preview.kind} outcome is unconfirmed. Preserve operation ${preview.operation_id}. Run recover with that reference; no automatic retry occurred.`);}
   throw error;
  }
 }
 async #lookup(session,record){
  const p=record.preview;
  const result=parseLookup(await session.read('lookup',{p_operation_kind:p.kind,p_operation_id:p.operation_id}),p.kind,p.operation_id);
  if(!result.observed)return {observed:false,receipt:null};
  return {observed:true,receipt:p.kind==='plan'?parsedPlanReceipt(result.receipt,p.input):p.kind==='claim'?parseClaim(result.receipt,p.input):outcome(result.receipt,p)};
 }
 async recover(operationId){
  const record=this.journal.operation(uuid(operationId)),p=record.preview;
  if(record.dispatches<1)retentionBlocked('retention_not_dispatched');
  const result=await this.api.withSession(async session=>{
   assertBinding(session.binding,p.binding);
   if(p.kind==='reconcile')return {observed:false,receipt:parsePlan(await session.read('status',{p_plan_id:p.input.p_plan_id}),p.input.p_plan_id)};
   return this.#lookup(session,record);
  });
  // Reconcile has no immutable operation receipt API. A current status read
  // is useful evidence, but cannot convert the original unknown call into a
  // committed receipt. A newly reviewed reconcile is a distinct operation.
  const observation={checked_at:new Date().toISOString(),observed:result.observed,...(p.kind==='reconcile'?{current_plan:result.receipt,currentness_not_asserted:true}:{})};
  return displayRecord(this.journal.observe(record.preview_sha256,observation,{receipt:p.kind==='reconcile'?null:result.receipt,committed:result.observed}));
 }
 list(){return this.journal.list().map(row=>({operation_id:row.preview.operation_id,preview_sha256:row.preview_sha256,kind:row.preview.kind,state:row.state,dispatches:row.dispatches,created_at:row.preview.created_at}));}
 show(hash){return displayRecord(this.journal.get(hash));}
 cancel(hash){return displayRecord(this.journal.cancel(hash));}
}
