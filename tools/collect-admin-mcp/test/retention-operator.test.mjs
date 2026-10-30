import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,chmod,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {RetentionJournal} from '../src/retention_journal.mjs';
import {RetentionOperator} from '../src/retention_operator.mjs';
import {runRetentionCommand} from '../src/retention_cli.mjs';
import {ADMIN_ORIGIN,SafeError} from '../src/config.mjs';
import {digest} from '../src/retention_contract.mjs';

const id=n=>`${String(n).padStart(8,'0')}-1111-4111-8111-111111111111`,source='a'.repeat(64),policy='b'.repeat(64),schema='c'.repeat(64),snapshot='d'.repeat(64);
const binding={origin:ADMIN_ORIGIN,account_id:id(1),principal_id:id(2),session_id:id(3),role:'owner',capabilities_sha256:digest(['privacy.review'])};
const confirm=async(_record,phrase)=>phrase;
const copy=value=>structuredClone(value);
function initialPlan(){return {contract_version:1,scope:'approved_eligible_data_disposition',plan_id:id(6),request_id:id(4),policy_sha256:policy,source_id:source,schema_sha256:schema,state:'planned',revision:1,scope_snapshot_sha256:snapshot,erasure_completed:false,all_data_erased:false,financial_journal_preserved:false,policy_current:true,operational_acceptance_granted:false,tasks:[
 {task_id:id(7),class_name:'access',action:'quarantine',state:'pending',revision:0,fence:0,outcome:null},
 {task_id:id(8),class_name:'notification_events',action:'erase',state:'pending',revision:0,fence:0,outcome:null},
 {task_id:id(9),class_name:'external:backups',action:'retain',state:'pending',revision:0,fence:0,outcome:null},
 {task_id:id(10),class_name:'payment_evidence',action:'erase',state:'pending',revision:0,fence:0,outcome:null},
]};}
async function fixture(t){
 const dir=await mkdtemp(join(tmpdir(),'collect-retention-'));await chmod(dir,0o700);
 const config={origin:ADMIN_ORIGIN,credentialFile:join(dir,'session.json')};let journal=new RetentionJournal(config);
 const state={binding:copy(binding),plan:initialPlan(),holds:0,inFlight:false,changedSnapshot:false,failBefore:null,failAfter:null,failFence:false,reads:[],writes:[],effects:0,receipts:new Map(),claims:new Map()};
 const api={config,async withSession(callback){const value=await callback({binding:copy(state.binding),read:async(name,input={})=>{
  state.reads.push({name,input:copy(input)});
  if(name==='context')return {contract_version:1,scope:'account_retention_inspection_context',source_id:source,checked_at:new Date().toISOString(),valid_until:new Date(Date.now()+300000).toISOString(),approval_granted:false,erasure_completed:false};
  if(name==='inspect')return {contract_version:1,request_id:id(4),subject_id:id(5),source_id:source,schema_sha256:schema,snapshot_sha256:state.changedSnapshot?'e'.repeat(64):snapshot,table_counts:{notification_events:2},private_catalog_sha256:'e'.repeat(64),private_schema_sha256:'f'.repeat(64),private_copy_inventory:{'private:bff_sessions':{count:1,status:'verified'}},object_count:0,active_hold_count:state.holds,in_flight_unresolved:state.inFlight,approval_granted:false,erasure_completed:false};
  if(name==='status')return copy(state.plan);
  if(name==='lookup'){const receipt=state.receipts.get(input.p_operation_id)??null;return {contract_version:1,scope:'approved_eligible_data_disposition_operation',operation_kind:input.p_operation_kind,operation_id:input.p_operation_id,observed:!!receipt,receipt:copy(receipt),currentness_not_asserted:true,erasure_completed:false,all_data_erased:false};}
  assert.fail('unexpected read');
 },write:async(name,input)=>{
  state.writes.push({name,input:copy(input)});if(state.failBefore===name){state.failBefore=null;throw Error('synthetic network interruption');}
  let result;
  if(name==='plan'){
   const receipt={plan_id:id(6),request_id:id(4),operation_id:input.p_operation_id,policy_sha256:policy,source_id:source};state.receipts.set(input.p_operation_id,receipt);result=copy(state.plan);
  }else if(name==='claim'){
   const task=state.plan.tasks.find(row=>row.task_id===input.p_task_id);assert.equal(task.revision,input.p_expected_task_revision);task.revision++;task.fence++;task.state='claimed';state.plan.revision++;state.plan.state='processing';
   result={contract_version:1,claim_id:id(100+state.claims.size),task_id:task.task_id,operation_id:input.p_operation_id,fence:task.fence,claimed_seconds:Math.floor(Date.now()/1000),expires_seconds:Math.floor(Date.now()/1000)+120,erasure_completed:false};state.claims.set(result.claim_id,result);state.receipts.set(input.p_operation_id,copy(result));
  }else if(name==='execute'){
   const claim=state.claims.get(input.p_claim_id),task=state.plan.tasks.find(row=>row.task_id===claim.task_id);assert.equal(claim.fence,input.p_fence);
   result={verified:true,disposition:task.action==='quarantine'?'access_quarantined':'own_rows_absence_verified',source_id:source,policy_sha256:policy,observation_only:true,currentness_not_asserted:true,erasure_completed:false,all_data_erased:false};task.outcome=copy(result);task.revision++;task.state='verified';state.plan.revision++;state.effects++;state.receipts.set(input.p_operation_id,copy(result));
  }else if(name==='reconcile'){state.plan.revision++;state.plan.state='blocked';result={...copy(state.plan),eligible_dispositions_verified:false,all_actual_copy_outcomes_verified:false,financial_journal_preserved:true,retained_classes:['external:backups']};}
  else assert.fail('unexpected write');
  if(state.failAfter===name){state.failAfter=null;throw Error('synthetic lost response');}return result;
 }});if(state.failFence){state.failFence=false;throw new SafeError('retention_session_changed','synthetic final fence changed');}return value;}};
 let operator=new RetentionOperator(api,journal);
 t.after(async()=>{journal.close();await rm(dir,{recursive:true,force:true});});
 return {state,config,get operator(){return operator;},get journal(){return journal;},restart(){journal.close();journal=new RetentionJournal(config);operator=new RetentionOperator(api,journal);},async plan(){const preview=await operator.previewPlan(id(4),0,source,policy);await operator.apply(preview.preview_sha256,confirm);return preview;},async claim(task=id(7)){const p=await operator.previewClaim(id(6),task);const result=await operator.apply(p.preview_sha256,confirm);return {preview:p,receipt:result.receipt};}};
}

test('approved-scope lifecycle previews, commits one effect per confirmation and keeps unsupported classes explicit',async t=>{
 const f=await fixture(t),plan=await f.plan();assert.equal(plan.preview.input.p_policy_sha256,policy);assert.equal(plan.approval_created,false);
 const status=await f.operator.status(id(6));assert.deepEqual(status.supported_tasks,[id(7),id(8)]);assert.deepEqual(status.unsupported_tasks,[id(9),id(10)]);
 const claim=await f.claim(),preview=await f.operator.previewExecute(claim.preview.preview.operation_id);
 const executed=await f.operator.apply(preview.preview_sha256,confirm);assert.equal(executed.state,'observed');assert.equal(executed.receipt.verified,true);assert.equal(executed.all_data_erased,false);assert.equal(f.state.effects,1);
 // A completed first task does not wait out its old lease before the next task.
 await f.claim(id(8));
 await assert.rejects(()=>f.operator.previewClaim(id(6),id(9)),{code:'retention_adapter_unavailable'});
 await assert.rejects(()=>f.operator.previewClaim(id(6),id(10)),{code:'retention_adapter_unavailable'});
});

test('confirmation mismatch, headless execution and unknown CLI arguments never dispatch',async t=>{
 const f=await fixture(t),p=await f.operator.previewPlan(id(4),0,source,policy);
 await assert.rejects(()=>f.operator.apply(p.preview_sha256,async()=> 'yes'),{code:'cancelled'});
 await assert.rejects(()=>runRetentionCommand(f.operator,['apply',p.preview_sha256],{interactive:false,confirm}),{code:'interactive_confirmation_required'});
 await assert.rejects(()=>runRetentionCommand(f.operator,['apply',p.preview_sha256,'--yes'],{interactive:true,confirm}),{code:'invalid_arguments'});
 assert.equal(f.state.writes.length,0);assert.equal(f.journal.get(p.preview_sha256).state,'prepared');
});

test('changed holds, scope, permissions or source cannot turn a saved preview into authority',async t=>{
 const f=await fixture(t),p=await f.operator.previewPlan(id(4),0,source,policy);
 f.state.holds=1;await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_obligations_unresolved'});f.state.holds=0;
 f.state.changedSnapshot=true;await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_preview_stale'});f.state.changedSnapshot=false;
 f.state.binding.session_id=id(99);await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_session_changed'});
 assert.equal(f.state.writes.length,0);assert.equal(f.journal.get(p.preview_sha256).dispatches,0);
});

test('pending operation persists across restart and original receipt recovery does not repeat the write',async t=>{
 const f=await fixture(t),p=await f.operator.previewPlan(id(4),0,source,policy);f.state.failAfter='plan';
 await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_outcome_unknown'});f.restart();
 assert.equal(f.operator.show(p.preview_sha256).state,'unknown');await assert.rejects(()=>f.operator.previewPlan(id(4),0,source,policy),{code:'retention_original_operation_unresolved'});
 const recovered=await f.operator.recover(p.preview.operation_id);assert.equal(recovered.state,'observed');assert.equal(recovered.receipt.operation_id,p.preview.operation_id);assert.equal(f.state.writes.length,1);
 await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_confirmation_required'});
});

test('an unseen operation remains unknown, then explicit retry retains the exact original UUID and body',async t=>{
 const f=await fixture(t),p=await f.operator.previewPlan(id(4),0,source,policy);f.state.failBefore='plan';
 await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_outcome_unknown'});
 const unseen=await f.operator.recover(p.preview.operation_id);assert.equal(unseen.state,'unknown');assert.equal(unseen.observations[0].observed,false);assert.equal(f.state.writes.length,1);
 await f.operator.apply(p.preview_sha256,confirm,{retry:true});assert.equal(f.state.writes.length,2);assert.deepEqual(f.state.writes[1],f.state.writes[0]);assert.equal(f.operator.list().length,1);
});

test('lost acknowledgement after final authority check stays unknown until same-session recovery',async t=>{
 const f=await fixture(t),p=await f.operator.previewPlan(id(4),0,source,policy);f.state.failFence=true;
 await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_outcome_unknown'});
 f.state.binding.session_id=id(77);await assert.rejects(()=>f.operator.recover(p.preview.operation_id),{code:'retention_session_changed'});
 f.state.binding.session_id=binding.session_id;assert.equal((await f.operator.recover(p.preview.operation_id)).state,'observed');assert.equal(f.state.writes.length,1);
});

test('concurrent confirms cannot dispatch a second request from the same prepared preview',async t=>{
 const f=await fixture(t),p=await f.operator.previewPlan(id(4),0,source,policy);
 const replies=await Promise.allSettled([f.operator.apply(p.preview_sha256,confirm),f.operator.apply(p.preview_sha256,confirm)]);
 assert.equal(replies.filter(r=>r.status==='fulfilled').length,1);assert.equal(f.state.writes.length,1);assert.equal(f.journal.get(p.preview_sha256).dispatches,1);
});

test('stale approval and expired or unobserved claim block execution; known expiry permits a newly fenced claim',async t=>{
 const f=await fixture(t);await f.plan();f.state.plan.policy_current=false;await assert.rejects(()=>f.operator.previewClaim(id(6),id(7)),{code:'retention_approval_stale'});f.state.plan.policy_current=true;
 const claim=await f.claim();f.state.plan.tasks[0].state='pending'; // Simulates a changed current task; no action may use the old claim.
 await assert.rejects(()=>f.operator.previewExecute(claim.preview.preview.operation_id),{code:'retention_lease_expired'});f.state.plan.tasks[0].state='claimed';
 await assert.rejects(()=>f.operator.previewClaim(id(6),id(7)),{code:'retention_lease_active'});
 const realNow=Date.now,advance=realNow()+121000;
 Date.now=()=>advance;
 try{const resumed=await f.claim();assert.equal(resumed.receipt.fence,claim.receipt.fence+1);}finally{Date.now=realNow;}
 // A different session cannot consume even an observed claim.
 f.state.binding.session_id=id(44);await assert.rejects(()=>f.operator.previewExecute(claim.preview.preview.operation_id),{code:'retention_session_changed'});
 assert.equal(f.state.effects,0);
});

test('unknown execute survives restart; recovery observes exact outcome and never claims all-copy erasure',async t=>{
 const f=await fixture(t);await f.plan();const claim=await f.claim(),p=await f.operator.previewExecute(claim.preview.preview.operation_id);f.state.failAfter='execute';
 await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_outcome_unknown'});f.restart();
 const result=await f.operator.recover(p.preview.operation_id);assert.equal(result.state,'observed');assert.equal(result.receipt.verified,true);assert.equal(result.erasure_completed,false);assert.equal(result.all_data_erased,false);assert.equal(f.state.effects,1);
});

test('reconcile readback is an observation, never a fabricated original immutable receipt',async t=>{
 const f=await fixture(t);await f.plan();const p=await f.operator.previewReconcile(id(6));f.state.failAfter='reconcile';
 await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_outcome_unknown'});
 const observed=await f.operator.recover(p.preview.operation_id);assert.equal(observed.state,'unknown');assert.equal(observed.receipt,null);assert.equal(observed.observations[0].observed,false);assert.equal(observed.observations[0].current_plan.state,'blocked');
 await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm,{retry:true}),{code:'retention_confirmation_required'});assert.equal(f.state.writes.filter(row=>row.name==='reconcile').length,1);
});

test('only never-dispatched previews can be cancelled; journal is private and refuses unsafe permissions',async t=>{
 const f=await fixture(t),p=await f.operator.previewPlan(id(4),0,source,policy);assert.equal(f.operator.cancel(p.preview_sha256).state,'cancelled');
 const q=await f.operator.previewPlan(id(4),0,source,policy);await f.operator.apply(q.preview_sha256,confirm);assert.throws(()=>f.operator.cancel(q.preview_sha256));
 const path=join(f.config.credentialFile,'..','retention.sqlite');assert.equal((await stat(path)).mode&0o777,0o600);
 await chmod(path,0o644);assert.throws(()=>f.operator.list());await chmod(path,0o600);
});

test('explicit resume preserves an unknown original and requires its observed expired claim and exact current fence',async t=>{
 const f=await fixture(t);await f.plan();const first=await f.claim(),original=await f.operator.previewExecute(first.preview.preview.operation_id);f.state.failBefore='execute';
 await assert.rejects(()=>f.operator.apply(original.preview_sha256,confirm),{code:'retention_outcome_unknown'});
 // Full-snapshot status can be unconfirmed while the server's task-specific
 // resume is able to verify its immutable effect identity and current absence.
 f.state.plan.policy_current=false;
 await assert.rejects(()=>f.operator.previewClaim(id(6),id(7)),{code:'retention_approval_stale'});
 await assert.rejects(()=>f.operator.previewResumeClaim(original.preview.operation_id),{code:'retention_lease_active'});
 const realNow=Date.now,advance=realNow()+121000;Date.now=()=>advance;
 try{
  const resumed=await f.operator.previewResumeClaim(original.preview.operation_id);assert.equal(resumed.preview.expected.source_currentness,'requires_execution_recheck');
  const claimed=await f.operator.apply(resumed.preview_sha256,confirm);assert.equal(claimed.receipt.fence,first.receipt.fence+1);
  const execute=await f.operator.previewExecute(resumed.preview.operation_id);assert.equal(execute.preview.expected.resume_from_operation,original.preview.operation_id);
  await f.operator.apply(execute.preview_sha256,confirm);assert.equal(f.state.effects,1);assert.equal(f.operator.show(original.preview_sha256).state,'unknown');
 }finally{Date.now=realNow;}
});

test('an unrelated changed task or unverifiable original cannot authorize a resume preview',async t=>{
 const f=await fixture(t);await f.plan();const first=await f.claim(),original=await f.operator.previewExecute(first.preview.preview.operation_id);f.state.failBefore='execute';
 await assert.rejects(()=>f.operator.apply(original.preview_sha256,confirm),{code:'retention_outcome_unknown'});
 f.state.plan.tasks[0].fence++;
 await assert.rejects(()=>f.operator.previewResumeClaim(original.preview.operation_id),{code:'retention_resume_changed'});
 await assert.rejects(()=>f.operator.previewResumeClaim(first.preview.preview.operation_id),{code:'retention_resume_unavailable'});assert.equal(f.state.effects,0);
});

test('repeated unobserved recoveries stay bounded without exhausting the ability to recover a later receipt',async t=>{
 const f=await fixture(t),p=await f.operator.previewPlan(id(4),0,source,policy);f.state.failBefore='plan';
 await assert.rejects(()=>f.operator.apply(p.preview_sha256,confirm),{code:'retention_outcome_unknown'});
 for(let n=0;n<22;n++)await f.operator.recover(p.preview.operation_id);
 assert.equal(f.operator.show(p.preview_sha256).observations.length,20);assert.equal(f.operator.show(p.preview_sha256).state,'unknown');
 await f.operator.apply(p.preview_sha256,confirm,{retry:true});assert.equal(f.operator.show(p.preview_sha256).state,'observed');
});

test('concurrent previews atomically reserve one original identity for each unresolved scope',async t=>{
 const f=await fixture(t);
 const results=await Promise.allSettled([f.operator.previewPlan(id(4),0,source,policy),f.operator.previewPlan(id(4),0,source,policy)]);
 assert.equal(results.filter(result=>result.status==='fulfilled').length,1);assert.equal(f.operator.list().length,1);assert.equal(f.state.writes.length,0);
});
