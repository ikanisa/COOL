import {applicationWorkTuple} from './application-fence.js';
import {PostgresNativeAuthority} from './domain/burimunsi/postgres-authority.js';
import {lockCollectMutation} from './postgres-mutation-lock.js';
import {PostgresNativeFinancialJobs} from './domain/burimunsi/postgres-native-financial-jobs.js';
import {requireId,requireRequestId} from './domain/burimunsi/values.js';

const HASH=/^[a-f0-9]{64}$/;
const MODEL=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;
const unavailable=()=>({status:'unconfirmed',code:'native_financial_work_unavailable'});
const held=()=>({status:'held',code:'independent_evidence_unavailable'});
const field=(v,k)=>{const d=v&&typeof v==='object'&&!Array.isArray(v)?Object.getOwnPropertyDescriptor(v,k):null;
 if(!d||!Object.hasOwn(d,'value')||!d.enumerable)throw Error('native_work_invalid');return d.value;};

async function discover(env,work,assertCurrent,groupFilter){
 const db=env.DB;await assertCurrent();
 return db.transaction(async sql=>{
  await assertCurrent();await db.context(sql);await lockCollectMutation(sql);
  const rows=await sql.unsafe('SELECT private.burimunsi_native_work_discover($1::integer,$2) AS result',[1,groupFilter||null]);
  await assertCurrent();
  if(!Array.isArray(rows)||rows.length!==1||!Array.isArray(rows[0].result)||rows[0].result.length>1)throw Error('native_work_unavailable');
  return rows[0].result;
 });
}
const openJobs=(env,groupId)=>new PostgresNativeFinancialJobs({authority:new PostgresNativeAuthority({db:env.DB,groupId})});

/** The live scheduler is held until shared source/actor/beneficiary retention
 * mappings have a reviewed disposition. A flag cannot bypass this hold. */
export async function scheduledNativeFinancialWork(env){
 if(env?.BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED!=='true')return null;
 if(env.MOMO_PROCESSING_PAUSED!=='false')return {status:'paused'};
 return {status:'held',code:'retention_scope_unapproved'};
}

/** Qualification-only bounded queue. It is not composed into the scheduled
 * handler. Every claimed item is deferred; it has no provider or writer. */
export async function qualifyNativeFinancialWork(env,admission,{find=discover,makeJobs=openJobs}={}){
 if(env?.BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED!=='true')return null;
 if(env.MOMO_PROCESSING_PAUSED!=='false')return {status:'paused'};
 try{
  const work=env.DB?.applicationWork,tuple=applicationWorkTuple(work),p=admission?.processing;
  const source=env.BUILD_SOURCE_ID,approval=env.COLLECT_JOBS_PROCESSING_APPROVAL_SHA256,model=env.MOMO_AI_MODEL,
   mode=env.COLLECT_JOBS_MODE,apiKey=env.OPENAI_API_KEY,
   groupFilter=env.BURIMUNSI_COLLECTION_ID??'';
  const permitted=()=>env.BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED==='true'&&env.MOMO_PROCESSING_PAUSED==='false'&&
   env.BURIMUNSI_NATIVE_ENABLED==='true'&&env.BURIMUNSI_NATIVE_WORKERS_ENABLED==='true'&&
   env.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED==='true'&&env.MOMO_AI_ENABLED==='true'&&
   ['receipt_processing_v1','receipt_and_push_v1'].includes(mode)&&env.COLLECT_JOBS_MODE===mode&&
   typeof apiKey==='string'&&apiKey.length>0&&env.OPENAI_API_KEY===apiKey&&HASH.test(source??'')&&
   HASH.test(approval??'')&&MODEL.test(model??'')&&admission?.allowed===true&&admission.processing===p&&
   p?.contract==='collect.receipt-processing.v1'&&p.source_sha256===source&&p.batch_limit===1&&
   p.approval_sha256===approval&&p.model_id===model&&env.DB?.applicationWork===work&&work?.kind==='jobs'&&
   tuple[2]===source&&env.BUILD_SOURCE_ID===source&&env.COLLECT_JOBS_PROCESSING_APPROVAL_SHA256===approval&&
   env.MOMO_AI_MODEL===model&&(env.BURIMUNSI_COLLECTION_ID??'')===groupFilter;
  const assertCurrent=async()=>{
   if(!permitted())throw Error('native_work_gate_changed');await work.assert();
   if(!permitted()||JSON.stringify(applicationWorkTuple(work))!==JSON.stringify(tuple))throw Error('native_work_gate_changed');
  };
  if(typeof find!=='function'||typeof makeJobs!=='function'||!permitted())return unavailable();
  if(groupFilter)requireId(groupFilter);
  await assertCurrent();const groups=await find(env,work,assertCurrent,groupFilter);await assertCurrent();
  if(!Array.isArray(groups)||groups.length>1)throw Error('native_work_invalid');
  if(groups.length===0)return {status:'idle'};
  const groupId=requireId(field(groups[0],'groupId')),grantId=requireRequestId(field(groups[0],'grantId'));
  if(groupFilter&&groupFilter!==groupId)return {status:'idle'};
  const jobs=makeJobs(env,groupId);
  if(!jobs||!['sources','enqueue','candidates','claim','defer'].every(k=>typeof jobs[k]==='function'))throw Error('native_work_unavailable');
  const sources=await jobs.sources(grantId,5);await assertCurrent();
  if(!Array.isArray(sources)||sources.length>5)throw Error('native_work_invalid');
  let queued=0;
  for(const sourceId of sources){
   requireRequestId(sourceId);await assertCurrent();
   try{const accepted=await jobs.enqueue(grantId,sourceId);if(accepted?.durable!==true||!['queued','leased','waiting','completed'].includes(accepted.state))throw Error('native_work_unavailable');if(accepted.state!=='completed')queued++;}
   catch(error){if(!['42501','40001','55000'].includes(error?.code))throw error;}
   await assertCurrent();
  }
  const due=await jobs.candidates(grantId,1);await assertCurrent();
  if(!Array.isArray(due)||due.length>1)throw Error('native_work_invalid');
  if(!due.length)return queued?held():{status:'idle'};
  const jobId=requireRequestId(due[0]),lease=await jobs.claim(grantId,jobId,180000);await assertCurrent();
  // This lane intentionally cannot claim posting success. A later qualified
  // evidence and writer integration may reconsider the same durable work.
  const deferred=await jobs.defer(lease,'evidence_unavailable',300000);await assertCurrent();
  if(deferred?.state!=='waiting')throw Error('native_work_unavailable');
  return held();
 }catch{return unavailable();}
}
