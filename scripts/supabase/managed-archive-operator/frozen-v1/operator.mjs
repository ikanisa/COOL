// Fixed direct-project transport and one-use journal orchestration. No managed
// apply may pass until the separately reviewed plan gate is changed in source.
import {createHash} from 'node:crypto';
import pg from '../node_modules/pg/lib/index.js';
import {assertCleanEnvironment} from '../managed-cloud-migrations/operator-core.mjs';
import {managedReconciliationSsl,isManagedReconciliationPeer} from '../current-pg-transfer/managed-target.mjs';
import {archiveIdentity,MANAGED_REVIEWED_APPLY_PLAN_SHA256,captureArchivePreimage,applyArchiveInTransaction,reconcileArchive} from './archive-core.mjs';
import {beginAttempt,attachBackend,finishAttempt,beginReconciliation,finishReconciliation} from './journal.mjs';

const PROJECT='rrlduytparvsjfmegalh',HOST=`db.${PROJECT}.supabase.co`,HASH=/^[a-f0-9]{64}$/;
const fail=code=>{throw Object.assign(Error(code),{archiveCode:code});};
const exact=(o,k)=>!!o&&typeof o==='object'&&!Array.isArray(o)&&Object.getPrototypeOf(o)===Object.prototype&&
 Object.keys(o).sort().join('\0')===[...k].sort().join('\0');
export function archivePlanDigest({preimageSha256,admissions,exclusionEvidenceSha256}={}){
 if(!HASH.test(preimageSha256??'')||!HASH.test(exclusionEvidenceSha256??'')||!exact(admissions,['count','sha'])||
  !Number.isSafeInteger(admissions.count)||admissions.count<0||admissions.count>10000||!HASH.test(admissions.sha??''))fail('PLAN_REFUSED');
 const payload={format:'collect.managed-archive-plan.v1',project:PROJECT,host:HOST,port:5432,database:'postgres',user:'postgres',
  version:archiveIdentity.version,sourceSha256:archiveIdentity.sourceSha256,preimageSha256,admissionsCount:admissions.count,
  admissionsSha256:admissions.sha,exclusionEvidenceSha256};
 return createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}
function validPlan(plan){
 if(!exact(plan,['preimageSha256','admissions','exclusionEvidenceSha256','reviewedPlanSha256'])||
  !HASH.test(plan.reviewedPlanSha256??'')||archivePlanDigest(plan)!==plan.reviewedPlanSha256)fail('PLAN_REFUSED');
}
function password(secret){return typeof secret==='string'&&Buffer.byteLength(secret)>0&&Buffer.byteLength(secret)<=1024&&!/[\u0000-\u001f\u007f]/u.test(secret);}
function close(c){try{c?.connection?.stream?.destroy();}catch{}try{void c?.end()?.catch(()=>{});}catch{}}
async function managedClient(secret){
 if(!password(secret))fail('PRIVATE_INPUT_REFUSED');assertCleanEnvironment(process.env);
 const c=new pg.Client({host:HOST,port:5432,database:'postgres',user:'postgres',password:secret,ssl:managedReconciliationSsl(),
  connectionTimeoutMillis:10000,application_name:'collect_archive_preimage'});c.on('error',()=>{});
 let timer;try{
  await Promise.race([c.connect(),new Promise((_,reject)=>{timer=setTimeout(()=>{close(c);reject(Error('timeout'));},10000);})]);
  if(!isManagedReconciliationPeer(c.connectionParameters,c.connection.stream))fail('MANAGED_TRANSPORT_REFUSED');return c;
 }catch{close(c);fail('MANAGED_CONNECTION_UNAVAILABLE');}finally{clearTimeout(timer);}
}
// The caller must use a protected input/output channel; the result includes
// operational metadata. No credential is included in the returned object.
export async function captureManagedArchive({secret,timeoutMs=90000}={}){
 let client;try{client=await managedClient(secret);return await captureArchivePreimage({mode:'managed',client,timeoutMs});}
 finally{close(client);secret='';}
}
const definitive=new Set(['PREIMAGE_CHANGED','SYNTHETIC_AFTER_BODY','SYNTHETIC_AFTER_HISTORY','SYNTHETIC_HISTORY_MISMATCH',
 'SYNTHETIC_FENCE_NOT_FENCED','ARCHIVE_OBJECT_ALREADY_PRESENT','UNREVIEWED_EVENT_TRIGGER','POST_HISTORY_CATALOG_CHANGED']);
async function journaledApply(ctx,root,plan,existingJob=null){
 validPlan(plan);const job=existingJob??await beginAttempt(root,plan);
 try{await attachBackend(job,ctx.client.processID);}catch{return {status:'journal_backend_unconfirmed_do_not_retry',writeAuthorized:false};}
 let result,state,code=null;
 try{result=await applyArchiveInTransaction({...ctx,backendPid:ctx.client.processID},{expectedPreimageSha256:plan.preimageSha256,expectedAdmissions:plan.admissions,reviewedPlanSha256:plan.reviewedPlanSha256});state='committed';}
 catch(e){code=e?.archiveCode??'APPLY_UNKNOWN';state=definitive.has(code)?'refused':'unconfirmed';}
 try{await finishAttempt(job,state,code);}catch{return {status:'journal_outcome_unconfirmed_do_not_retry',writeAuthorized:false};}
 if(state==='committed')return {...result,writeAuthorized:false};
 return {status:state==='refused'?'refused_do_not_retry':'outcome_unconfirmed_do_not_retry',code,writeAuthorized:false};
}
async function journaledReconcile(ctx,root,plan,existingJob=null){
 validPlan(plan);const job=existingJob??await beginReconciliation(root,plan);let status='unconfirmed';
 try{status=(await reconcileArchive(ctx,{priorBackendPid:job.priorBackendPid,expectedAdmissions:plan.admissions})).status;}catch{}
 try{await finishReconciliation(job,status);}catch{return {status:'journal_reconciliation_unconfirmed',writeAuthorized:false};}
 return {status,writeAuthorized:false};
}
export async function syntheticJournaledApply(ctx,root,plan){
 if(ctx?.mode!=='synthetic')fail('SYNTHETIC_ONLY');return journaledApply(ctx,root,plan);
}
export async function syntheticJournaledReconcile(ctx,root,plan){
 if(ctx?.mode!=='synthetic')fail('SYNTHETIC_ONLY');return journaledReconcile(ctx,root,plan);
}
export async function applyManagedArchive(options={}){
 const plan=options?.plan;
 if(MANAGED_REVIEWED_APPLY_PLAN_SHA256===null||plan?.reviewedPlanSha256!==MANAGED_REVIEWED_APPLY_PLAN_SHA256)fail('MANAGED_APPLY_UNQUALIFIED');
 let {secret,root,timeoutMs=90000}=options;
 validPlan(plan);const job=await beginAttempt(root,plan);let client;
 // This path remains closed in the reviewed source; a future successor must
 // journal intent before opening a connection or authorizing any dispatch.
 try{client=await managedClient(secret);return await journaledApply({mode:'managed',client,timeoutMs},root,plan,job);}
 catch{return {status:'outcome_unconfirmed_do_not_retry',writeAuthorized:false};}
 finally{close(client);secret='';}
}
export async function reconcileManagedArchive(options={}){
 const plan=options?.plan;
 if(MANAGED_REVIEWED_APPLY_PLAN_SHA256===null||plan?.reviewedPlanSha256!==MANAGED_REVIEWED_APPLY_PLAN_SHA256)fail('MANAGED_APPLY_UNQUALIFIED');
 let {secret,root,timeoutMs=90000}=options;
 validPlan(plan);const job=await beginReconciliation(root,plan);let client;
 try{client=await managedClient(secret);return await journaledReconcile({mode:'managed',client,timeoutMs},root,plan,job);}
 catch{return {status:'journal_reconciliation_unconfirmed',writeAuthorized:false};}
 finally{close(client);secret='';}
}
