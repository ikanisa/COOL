// Explicit, staged production operator. Importing this module performs no I/O.
// No action below is run by the test suite against a live database or provider.
import {readFileSync,lstatSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {connect,management,record,ROOT,PROJECT,sha} from './access.mjs';
import {captureRuntimeSnapshot,checkSnapshot} from './runtime-plan.mjs';
import {renderManagedJobsHandler} from './managed-jobs-handler-patch.mjs';
import {keyEvidenceForSource,sameDeployedFunctions,verifyDeploymentEvidence} from './managed-jobs-key-operator.mjs';
import {requireRevisionSchedulerReady} from './revise-runtime.mjs';
import {readAncillaryRegistration,requireSameRegistration,requireVersionOnlyRequalification,registrationSnapshot,scopedInventory} from './ancillary-inventory.mjs';

const HASH=/^[a-f0-9]{64}$/;
const NAMES=['BUILD_SOURCE_ID','BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED','MOMO_AI_ENABLED','MOMO_AI_MODEL',
 'COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256','COLLECT_JOB_AUTH_MODE','COLLECT_JOB_SIGNING_KEY','OPENAI_API_KEY'];
const fail=message=>{throw Error(message);};
const copy=x=>JSON.parse(JSON.stringify(x));
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const safeName=name=>typeof name==='string'&&/^[a-z0-9_.-]+\.json$/.test(name);
const labelName=label=>{if(!/^[a-z][a-z0-9-]{3,50}$/.test(label??''))fail('rebind_label_invalid');return 'native-source-rebind-'+label;};
function privateFile(name,optional=false){
 if(!safeName(name))fail('rebind_evidence_invalid');const path=join(ROOT,name);let s;
 try{s=lstatSync(path);}catch(error){if(optional&&error?.code==='ENOENT')return null;throw error;}
 if(!s.isFile()||s.isSymbolicLink()||s.nlink!==1||s.uid!==process.getuid()||(s.mode&0o077)!==0||s.size<2||s.size>5*1024*1024)
  fail('rebind_evidence_invalid');
 const bytes=readFileSync(path);return {value:JSON.parse(bytes.toString('utf8')),digest:sha(bytes)};
}
const secretMap=rows=>{
 if(!Array.isArray(rows))fail('rebind_secret_preimage_changed');const map=new Map();
 for(const r of rows){if(typeof r?.name!=='string'||!HASH.test(r.value??'')||map.has(r.name))fail('rebind_secret_preimage_changed');map.set(r.name,r.value);}
 return Object.fromEntries(NAMES.map(name=>[name,map.get(name)??null]));
};
const integer=value=>{
 const v=String(value);if(!/^(0|[1-9][0-9]{0,15})$/.test(v)||BigInt(v)>9007199254740991n)fail('rebind_budget_invalid');return v;
};
const budget=row=>({source:row.native_provider_source_sha256,model:row.native_provider_model_id,
 approval:row.native_provider_approval_sha256,used:integer(row.native_provider_used),
 limit:row.native_provider_limit===null?null:integer(row.native_provider_limit),
 expires:row.native_provider_expires_at===null?null:new Date(row.native_provider_expires_at).toISOString()});
export const functions=(rows,registration=null)=>{
 try{const scoped=scopedInventory(rows,registration);return [...scoped.core,...scoped.ancillary];}
 catch{fail('rebind_functions_changed');}
};
function common(state,source,checkKeyFunctions=true){
 if(state?.control?.mode!=='open'||state.control.source_sha256!==source||!Number.isSafeInteger(Number(state.control.epoch))||
  state.enabled!==false||state.active!==false||state.pending!==0||state.activeAdmissions!==0||state.imported!==37||
  state.schedule!=='* * * * *'||state.command!=='SELECT collect_ops.tick_jobs();'||state.operator!==true)
  fail('rebind_scheduler_not_drained');
 requireRevisionSchedulerReady(state.scheduler);
 if(state.secrets.BUILD_SOURCE_ID!==sha(source)||state.secrets.COLLECT_JOB_AUTH_MODE!==sha('supabase_dispatch_hmac_v1')||
  !state.secrets.OPENAI_API_KEY||state.secrets.MOMO_AI_ENABLED!==sha('true'))fail('rebind_secret_preimage_changed');
 if(state.keyCount!==1||state.key?.id!==state.keyEvidence.vaultId||state.key?.digest!==state.keyEvidence.keySha256||
  state.key?.description!=='collect.jobs.key.v1:'+state.keyEvidence.operation||
  state.secrets.COLLECT_JOB_SIGNING_KEY!==state.keyEvidence.keySha256)fail('rebind_key_changed');
 try{scopedInventory(state.functions,state.ancillaryRegistration??null);}catch{fail('rebind_functions_changed');}
 if(checkKeyFunctions&&!sameDeployedFunctions(state.keyEvidence.functions,state.functions,state.ancillaryRegistration??null))fail('rebind_functions_changed');
}
function capturedKey(state,intent){
 try{requireSameRegistration(intent.ancillaryRegistration??null,state.ancillaryRegistration??null);}catch{fail('rebind_functions_changed');}
 const key=intent?.keyEvidence;
 if(!key||state.keyCount!==1||state.key?.id!==key.vaultId||state.key?.digest!==key.keySha256||
  state.key?.description!=='collect.jobs.key.v1:'+key.operation||state.keyEvidence?.vaultId!==key.vaultId||
  state.keyEvidence?.keySha256!==key.keySha256||state.keyEvidence?.operation!==key.operation||
  state.secrets.COLLECT_JOB_SIGNING_KEY!==key.keySha256)fail('rebind_key_changed');
}
function revisionLineage(revision,io){
 const reversed=[revision],seen=new Set();let current=revision;
 while(current.before?.mode!=='open'){
  const link=current.resumes,label=link?.label;
  if(!/^[a-z][a-z0-9-]{3,60}$/.test(label??'')||!HASH.test(link?.intentSha256??'')||seen.has(label)||seen.size>=16)
   fail('rebind_revision_changed');
  seen.add(label);const prior=io.read('revision-'+label+'-intent.json',true)?.value;
  if(!prior||sha(JSON.stringify(prior))!==link.intentSha256||prior.snapshot?.sourceSha256!==revision.snapshot?.sourceSha256)
   fail('rebind_revision_changed');
  reversed.push(prior);current=prior;
 }
 return reversed.reverse();
}
function revisionBoundIntent(intent,lineage,io){
 let result=intent;
 for(const revision of lineage){
  const previous=result.ancillaryRegistration??null,current=revision.ancillaryRegistration??null;
  if(same(previous,current))continue;
  const q=revision.ancillaryRequalification;
  if(!previous||!current||!q||q.previousDigest!==previous.digest||q.newDigest!==current.digest||
   !/^[a-z][a-z0-9-]{3,60}$/.test(q.sourceSecretAcknowledgedBy??''))fail('rebind_functions_changed');
  try{requireVersionOnlyRequalification(previous,current);}catch{fail('rebind_functions_changed');}
  const attempt=io.read('revision-'+q.sourceSecretAcknowledgedBy+'-source-secret-attempt.json',true)?.value,
   done=io.read('revision-'+q.sourceSecretAcknowledgedBy+'-source-secret-complete.json',true)?.value;
  if(attempt?.previousSourceSha256!==intent.oldSource||attempt?.sourceSha256!==intent.newSource||
   done?.sourceSha256!==intent.newSource||done?.secretSha256!==sha(intent.newSource))fail('rebind_functions_changed');
  result={...result,ancillaryRegistration:current};
 }
 return result;
}
function approvalEvidence(approval,source,previous,model,b,qualificationDigest){
 if(approval?.format!=='collect.native-sms.owner-approval.v1'||approval.project!==PROJECT||approval.sourceSha256!==source||
  approval.previousSourceSha256!==previous||approval.model!==model||String(approval.providerUsedPreserved)!==b.used||
  approval.applicationLimit!==(b.limit===null?null:Number(b.limit))||
  (approval.applicationDeadline===null?null:new Date(approval.applicationDeadline).toISOString())!==b.expires||
  approval.qualificationSha256!==qualificationDigest||typeof approval.scope!=='string'||!approval.scope.trim())
  fail('rebind_approval_changed');
}
function checkOld(state,prior,previousApprovalDigest,next){
 const old=prior?.sourceSha256,b=budget(state.budget);common(state,old);
 if(prior?.format!=='collect.native-sms.owner-approval.v1'||prior.project!==PROJECT||!HASH.test(old??'')||
  state.keyEvidence.sourceSha256!==old||
  !HASH.test(next??'')||next===old||b.source!==old||b.model!==prior.model||b.approval!==previousApprovalDigest||
  state.secrets.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED!==sha('true')||
  state.secrets.MOMO_AI_MODEL!==sha(b.model)||state.secrets.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256!==sha(b.approval)||
  (prior.applicationLimit===null?null:String(prior.applicationLimit))!==b.limit||
  (prior.applicationDeadline===null?null:new Date(prior.applicationDeadline).toISOString())!==b.expires||
  BigInt(integer(prior.providerUsedPreserved))>BigInt(b.used))fail('rebind_provider_preimage_changed');
 return b;
}

/** Compare all fields that can authorize or spend, including nullable limits. */
function checkTransition(state,intent,approvalDigest,disabled=true){
 const source=intent.newSource;common(state,source,false);capturedKey(state,intent);
 if(Number(state.control.epoch)!==Number(intent.epoch)+2||!same(budget(state.budget),{...intent.budget,source,approval:approvalDigest})||
  state.secrets.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED!==sha(disabled?'false':'true')||
  state.secrets.MOMO_AI_MODEL!==intent.secrets.MOMO_AI_MODEL||state.secrets.MOMO_AI_ENABLED!==intent.secrets.MOMO_AI_ENABLED||
  state.secrets.OPENAI_API_KEY!==intent.secrets.OPENAI_API_KEY||state.secrets.COLLECT_JOB_AUTH_MODE!==intent.secrets.COLLECT_JOB_AUTH_MODE||
  state.secrets.COLLECT_JOB_SIGNING_KEY!==intent.secrets.COLLECT_JOB_SIGNING_KEY)
  fail('rebind_provider_preimage_changed');
}

async function liveState(db,api,keyEvidence){
 const ancillaryRegistration=readAncillaryRegistration();
 const control=(await db.query('SELECT mode,epoch,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
 const x=(await db.query(`SELECT c.enabled,j.active,j.schedule,j.command,c.native_provider_source_sha256,c.native_provider_model_id,
  c.native_provider_approval_sha256,c.native_provider_used,c.native_provider_limit,c.native_provider_expires_at,
  (SELECT count(*)::int FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed')) AS pending,
  (SELECT count(*)::int FROM private.collect_imported_native_history) AS imported,
  (SELECT count(*)::int FROM private.collect_fence_admissions a WHERE state IN('active','unresolved')
   AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)) AS active_admissions,
  private._collect_fence_scheduler_status() AS scheduler,private._collect_fence_operator() AS operator
  FROM collect_ops.jobs_config c JOIN cron.job j ON j.jobid=c.cron_job_id WHERE c.singleton`)).rows[0];
 const keys=(await db.query("SELECT id::text,encode(sha256(convert_to(decrypted_secret,'UTF8')),'hex') digest,description FROM vault.decrypted_secrets WHERE name='collect_job_signing_key_v1'")).rows;
 if(!control||!x)fail('rebind_scheduler_not_drained');
 const [f,s]=await Promise.all([api('functions'),api('secrets')]);
 requireSameRegistration(ancillaryRegistration,readAncillaryRegistration());
 return {control,enabled:x.enabled,active:x.active,schedule:x.schedule,command:x.command,pending:x.pending,imported:x.imported,
  activeAdmissions:x.active_admissions,scheduler:x.scheduler,operator:x.operator,budget:x,keyCount:keys.length,key:keys[0]??null,
  keyEvidence,functions:functions(f.json(),ancillaryRegistration),ancillaryRegistration,secrets:secretMap(s.json())};
}

/** Existing evidence/adapter objects are injected for deterministic tests. */
export async function disableNative({label,nextSource,previousApprovalName},io){
 const stem=labelName(label),oldApproval=io.read(previousApprovalName),state=await io.state('old');
 const existing=io.read(stem+'-disable-intent.json',true),complete=io.read(stem+'-disable-complete.json',true);
 let intent;
 if(existing){
  if(existing.value.newSource!==nextSource||existing.value.previousApprovalDigest!==oldApproval.digest)fail('rebind_intent_changed');
  const attempted=io.read(stem+'-disable-attempt.json',true),ack=io.read(stem+'-disable-ack.json',true);
  if((attempted&&(attempted.value.oldSource!==existing.value.oldSource||attempted.value.newSource!==nextSource))||
   (ack&&(!attempted||!Number.isInteger(ack.value.status)||ack.value.status<200||ack.value.status>=300)))
   fail('rebind_intent_changed');
  if(complete&&(!attempted||!ack))fail('rebind_intent_changed');
  if(complete){common(state,existing.value.oldSource);capturedKey(state,existing.value);if(Number(state.control.epoch)!==existing.value.epoch||
    !same(budget(state.budget),existing.value.budget)||state.secrets.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED!==sha('false')||
    NAMES.filter(n=>n!=='BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED').some(n=>state.secrets[n]!==existing.value.secrets[n]))
    fail('rebind_disabled_state_changed');await io.guardStatus(intentGuard(existing.value.oldSource));return complete.value;}
  if(attempted){
   if(!ack)fail('rebind_disable_outcome_unknown');
   common(state,existing.value.oldSource);capturedKey(state,existing.value);
   if(Number(state.control.epoch)!==existing.value.epoch||state.secrets.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED!==sha('false')||
    !same(budget(state.budget),existing.value.budget)||
    NAMES.filter(n=>n!=='BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED').some(n=>state.secrets[n]!==existing.value.secrets[n]))
    fail('rebind_disable_outcome_unknown');
   await io.guardStatus(intentGuard(existing.value.oldSource));
   const result={oldSource:existing.value.oldSource,newSource:nextSource,at:new Date().toISOString()};
   io.save(stem+'-disable-complete.json',result);return result;
  }
  intent=existing.value;
 }else{
  const b=checkOld(state,oldApproval.value,oldApproval.digest,nextSource);
  await io.guardStatus(intentGuard(state.control.source_sha256));
  intent={project:PROJECT,oldSource:b.source,newSource:nextSource,epoch:Number(state.control.epoch),budget:b,
   previousApprovalDigest:oldApproval.digest,functions:scopedInventory(state.functions,state.ancillaryRegistration??null).core,secrets:state.secrets,keyEvidence:state.keyEvidence,
   ...(state.ancillaryRegistration?{ancillaryRegistration:registrationSnapshot(state.ancillaryRegistration)}:{}),at:new Date().toISOString()};
  io.save(stem+'-disable-intent.json',intent);
 }
 const snapshot=io.snapshot();if(snapshot.sourceSha!==nextSource||io.check(snapshot)?.status!=='passed')fail('rebind_snapshot_changed');
 const beforeCall=await io.state('old');common(beforeCall,intent.oldSource);capturedKey(beforeCall,intent);
 if(Number(beforeCall.control.epoch)!==intent.epoch||!same(budget(beforeCall.budget),intent.budget)||
  NAMES.some(n=>beforeCall.secrets[n]!==intent.secrets[n])||!sameDeployedFunctions(intent.functions,beforeCall.functions,beforeCall.ancillaryRegistration??null))
  fail('rebind_provider_preimage_changed');
 await io.guardStatus(intentGuard(intent.oldSource));
 // Only an intent without an attempt is retryable. The durable attempt is
 // written immediately before sending; an unacknowledged call is never resent.
 io.save(stem+'-disable-attempt.json',{oldSource:intent.oldSource,newSource:nextSource,at:new Date().toISOString()});
 const response=await io.api('secrets',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify([{name:'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED',value:'false'}])});
 io.save(stem+'-disable-ack.json',{status:response.status,at:new Date().toISOString()});
 const after=await io.state('old');common(after,intent.oldSource);capturedKey(after,intent);
 if(Number(after.control.epoch)!==intent.epoch||!same(budget(after.budget),intent.budget)||
  after.secrets.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED!==sha('false')||
  NAMES.filter(n=>n!=='BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED').some(n=>after.secrets[n]!==intent.secrets[n]))
  fail('rebind_disabled_state_changed');
 await io.guardStatus(intentGuard(intent.oldSource));
 const result={oldSource:intent.oldSource,newSource:nextSource,at:new Date().toISOString()};
 io.save(stem+'-disable-complete.json',result);return result;
}

export async function rebindProvider({label,approvalName,qualificationName,revisionIntentName,revisionCompleteName},io){
 const stem=labelName(label),baseIntent=io.read(stem+'-disable-intent.json').value;
 if(!io.read(stem+'-disable-complete.json',true))fail('rebind_disable_required');
 const approval=io.read(approvalName),qualification=io.read(qualificationName),ri=io.read(revisionIntentName).value,
  rd=io.read(revisionCompleteName).value;
 const lineage=revisionLineage(ri,io),origin=lineage[0],intent=revisionBoundIntent(baseIntent,lineage,io);
 if(qualification.value.project!==PROJECT||qualification.value.sourceSha256!==intent.newSource||
  qualification.value.checked?.status!=='passed'||qualification.value.checked.sourceSha256!==intent.newSource)
  fail('rebind_qualification_changed');
 approvalEvidence(approval.value,intent.newSource,intent.oldSource,intent.budget.model,intent.budget,qualification.digest);
 if(origin.before?.mode!=='open'||origin.before?.source_sha256!==intent.oldSource||Number(origin.before?.epoch)!==intent.epoch||
  ri.snapshot?.sourceSha256!==intent.newSource||ri.checked?.status!=='passed'||ri.checked?.sourceSha256!==intent.newSource||
  ri.testEvidence?.passed!==true||ri.testEvidence?.sourceSha256!==intent.newSource||ri.testEvidence?.evidenceSha256!==qualification.digest||
  rd.sourceSha256!==intent.newSource||Number(rd.epoch)!==intent.epoch+2)
  fail('rebind_revision_changed');
 const state=await io.state('new',intent.keyEvidence);
 if(!sameDeployedFunctions(rd.functions,state.functions,state.ancillaryRegistration??null))fail('rebind_functions_changed');
 io.verifyDeployment(ri,rd,state);
 const started=io.read(stem+'-provider-intent.json',true),completed=io.read(stem+'-provider-complete.json',true);
 if(started&&(!same(started.value.before,intent.budget)||started.value.approval!==approval.digest||started.value.newSource!==intent.newSource))
  fail('rebind_intent_changed');
 if(started&&!completed)fail('rebind_provider_outcome_unknown');
 if(!started){
  common(state,intent.newSource,false);capturedKey(state,intent);
  if(Number(state.control.epoch)!==intent.epoch+2||!same(budget(state.budget),intent.budget)||
   state.secrets.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED!==sha('false')||
   state.secrets.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256!==sha(intent.budget.approval)||
   NAMES.filter(n=>!['BUILD_SOURCE_ID','BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED'].includes(n)).some(n=>state.secrets[n]!==intent.secrets[n]))
   fail('rebind_provider_preimage_changed');
  io.save(stem+'-provider-intent.json',{before:intent.budget,newSource:intent.newSource,approval:approval.digest,at:new Date().toISOString()});
  // The adapter locks and rechecks the current fence, scheduler, all budget
  // fields and pending work in one READ COMMITTED compare-and-swap transaction.
  await io.updateBudget(intent,approval.digest);
  const after=await io.state('new',intent.keyEvidence);checkTransition(after,intent,approval.digest);
  io.save(stem+'-provider-complete.json',{newSource:intent.newSource,approval:approval.digest,at:new Date().toISOString()});
 }else checkTransition(state,intent,approval.digest);
 const secretIntent=io.read(stem+'-approval-secret-intent.json',true),secretAck=io.read(stem+'-approval-secret-ack.json',true),
  secretDone=io.read(stem+'-approval-secret-complete.json',true);
 if(secretIntent&&(secretIntent.value.approval!==approval.digest||secretIntent.value.newSource!==intent.newSource))fail('rebind_intent_changed');
 if(secretIntent&&!secretAck&&!secretDone)fail('rebind_approval_outcome_unknown');
 if(!secretIntent){
  const current=await io.state('new',intent.keyEvidence);checkTransition(current,intent,approval.digest);
  if(current.secrets.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256!==sha(intent.budget.approval)||
   !sameDeployedFunctions(rd.functions,current.functions,current.ancillaryRegistration??null))fail('rebind_secret_preimage_changed');
  io.verifyDeployment(ri,rd,current);
  io.save(stem+'-approval-secret-intent.json',{newSource:intent.newSource,approval:approval.digest,at:new Date().toISOString()});
  const response=await io.api('secrets',{method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify([{name:'COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256',value:approval.digest}])});
  io.save(stem+'-approval-secret-ack.json',{status:response.status,at:new Date().toISOString()});
 }
 const final=await io.state('new',intent.keyEvidence);checkTransition(final,intent,approval.digest);
 if(final.secrets.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256!==sha(approval.digest)||!sameDeployedFunctions(rd.functions,final.functions,final.ancillaryRegistration??null))
  fail('rebind_approval_outcome_unknown');
 io.verifyDeployment(ri,rd,final);
 if(!secretDone)io.save(stem+'-approval-secret-complete.json',{newSource:intent.newSource,approval:approval.digest,at:new Date().toISOString()});
 return {status:'provider_rebound_scheduler_inactive',sourceSha256:intent.newSource,used:intent.budget.used};
}

export async function bindExistingKey({label,revisionIntentName,revisionCompleteName},io){
 const stem=labelName(label),baseIntent=io.read(stem+'-disable-intent.json').value;
 const approval=io.read(stem+'-approval-secret-complete.json',true)?.value,
  provider=io.read(stem+'-provider-complete.json',true)?.value;
 const ri=io.read(revisionIntentName).value,rd=io.read(revisionCompleteName).value,
  intent=revisionBoundIntent(baseIntent,revisionLineage(ri,io),io);
 if(!approval||!provider||approval.newSource!==intent.newSource||provider.newSource!==intent.newSource||
  !HASH.test(approval.approval??'')||provider.approval!==approval.approval)fail('rebind_approval_required');
 const state=await io.state('new',intent.keyEvidence);
 if(rd.sourceSha256!==intent.newSource||!sameDeployedFunctions(rd.functions,state.functions,state.ancillaryRegistration??null))fail('rebind_revision_changed');
 io.verifyDeployment(ri,rd,state);checkTransition(state,intent,approval.approval);
 if(state.secrets.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256!==sha(approval.approval))fail('rebind_secret_preimage_changed');
 const name='managed-jobs-key-source-'+intent.newSource+'.json';
 if(!io.read(name,true))await io.bindKey(revisionIntentName,revisionCompleteName);
 const bound=io.read(name).value;
 const after=await io.state('new',intent.keyEvidence);checkTransition(after,intent,approval.approval);
 if(after.secrets.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256!==sha(approval.approval)||
  !sameDeployedFunctions(rd.functions,after.functions,after.ancillaryRegistration??null))fail('rebind_secret_preimage_changed');
 io.verifyDeployment(ri,rd,after);
 if(bound.sourceSha256!==intent.newSource||bound.vaultId!==intent.keyEvidence.vaultId||bound.keySha256!==intent.keyEvidence.keySha256||
  bound.keyChanged!==false||!sameDeployedFunctions(bound.functions,after.functions,after.ancillaryRegistration??null))fail('rebind_key_changed');
 await io.guardStatus(intentGuard(intent.newSource));
 if(!io.read(stem+'-key-complete.json',true))io.save(stem+'-key-complete.json',{sourceSha256:intent.newSource,at:new Date().toISOString()});
 return {status:'existing_key_bound_scheduler_inactive',sourceSha256:intent.newSource};
}

function intentGuard(source){return {project:PROJECT,sourceSha256:source,enabled:false,cronActive:false,pending:0,historicalProtected:37};}

export async function updateBudget(db,intent,approval){
 let commit=false;await db.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 try{
  // Dispatch/activation acquire the fence, scheduler advisory lock, then the
  // jobs_config row. pause_jobs uses that same row lock. The runtime mutation
  // lock is taken before the config row, as with native financial writers.
  await db.query("SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='15s'; SELECT private._collect_fence_require_operator(); SELECT private.collect_fence_assert_write(NULL,NULL,NULL); SELECT pg_advisory_xact_lock(hashtextextended('collect.scheduler.rrlduytparvsjfmegalh',0)); SELECT pg_advisory_xact_lock(734636924058501::bigint)");
  const c=(await db.query('SELECT mode,epoch,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  const x=(await db.query(`SELECT c.*,private._collect_fence_scheduler_status() AS scheduler,
   (SELECT count(*)::int FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed')) AS pending,
   (SELECT count(*)::int FROM private.collect_fence_admissions a WHERE state IN('active','unresolved')
    AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)) AS active_admissions
   FROM collect_ops.jobs_config c WHERE c.singleton FOR UPDATE OF c`)).rows[0];
  // Managed postgres has SELECT, but not UPDATE, on cron.job. The config row
  // and scheduler advisory lock remain held across this read and the CAS.
  const job=x?(await db.query('SELECT active,schedule,command FROM cron.job WHERE jobid=$1',[x.cron_job_id])).rows[0]:null;
  if(!c||c.mode!=='open'||c.source_sha256!==intent.newSource||Number(c.epoch)!==intent.epoch+2||!x||!job||x.enabled||job.active||
   x.pending!==0||x.active_admissions!==0||job.schedule!=='* * * * *'||job.command!=='SELECT collect_ops.tick_jobs();'||
   !same(budget(x),intent.budget))fail('rebind_provider_preimage_changed');
  requireRevisionSchedulerReady(x.scheduler);
  const changed=await db.query(`UPDATE collect_ops.jobs_config SET native_provider_source_sha256=$1,native_provider_approval_sha256=$2
   WHERE singleton AND NOT enabled AND native_provider_source_sha256=$3 AND native_provider_approval_sha256=$4
    AND native_provider_model_id=$5 AND native_provider_used=$6::bigint AND native_provider_limit IS NOT DISTINCT FROM $7::bigint
    AND native_provider_expires_at IS NOT DISTINCT FROM $8::timestamptz RETURNING *`,
   [intent.newSource,approval,intent.oldSource,intent.budget.approval,intent.budget.model,intent.budget.used,intent.budget.limit,intent.budget.expires]);
  if(changed.rows.length!==1||!same(budget(changed.rows[0]),{...intent.budget,source:intent.newSource,approval}))fail('rebind_provider_preimage_changed');
  commit=true;await db.query('COMMIT');
 }catch(error){if(!commit)await db.query('ROLLBACK').catch(()=>{});else error.outcome='commit_requires_reconciliation';throw error;}
}

async function main(){
 const [action,label,...args]=process.argv.slice(2);if(!['--disable','--rebind','--bind-key'].includes(action))fail('rebind_action_required');
 if(action==='--disable'&&args.length!==2||action==='--rebind'&&args.length!==4||action==='--bind-key'&&args.length!==2)
  fail('rebind_arguments_required');
 const db=await connect();try{
  const io={read:privateFile,save:record,api:management,snapshot:captureRuntimeSnapshot,check:checkSnapshot,
   state:async(mode,existingKey)=>{
    const f=(await db.query('SELECT source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
    const key=existingKey??keyEvidenceForSource(f?.source_sha256);return liveState(db,management,key);
   },
   verifyDeployment:(intent,deployment,state)=>verifyDeploymentEvidence({intent,deployment,currentFunctions:state.functions,
    currentSource:state.control.source_sha256,handler:io.handler,ancillaryRegistration:state.ancillaryRegistration??null}),handler:await renderManagedJobsHandler(),
   updateBudget:(intent,approval)=>updateBudget(db,intent,approval),
   bindKey:async(intentName,completeName)=>{execFileSync(process.execPath,[fileURLToPath(new URL('./managed-jobs-key-operator.mjs',import.meta.url)),
    '--bind-source',intentName,completeName],{stdio:'pipe',encoding:'utf8'});},
   guardStatus:async expected=>{const out=execFileSync(process.execPath,[fileURLToPath(new URL('./managed-jobs-operator.mjs',import.meta.url)),
    '--status'],{stdio:'pipe',encoding:'utf8'});if(!same(JSON.parse(out),expected))fail('rebind_history_guard_changed');}};
  const result=action==='--disable'?await disableNative({label,nextSource:args[0],previousApprovalName:args[1]},io):
   action==='--rebind'?await rebindProvider({label,approvalName:args[0],qualificationName:args[1],revisionIntentName:args[2],revisionCompleteName:args[3]},io):
   await bindExistingKey({label,revisionIntentName:args[0],revisionCompleteName:args[1]},io);
  console.log(JSON.stringify(result));
 }finally{await db.end();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(error=>{
 const message=/^rebind_[a-z_]+$/.test(error.message??'')?error.message:'rebind_unavailable';
 console.error(JSON.stringify({outcome:'unconfirmed',reason:message,detail:'Reconcile the recorded stage; do not repeat an unacknowledged provider or database operation.'}));
 process.exitCode=1;
});
