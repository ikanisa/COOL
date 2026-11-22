import {canonicalJson,sha256} from './domain/burimunsi/values.js';
import {runCollectNativeScheduledCycle} from './domain/burimunsi/collect-runtime.js';

const ID=/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const HASH=/^[a-f0-9]{64}$/;
const MODEL=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;
const JWT=/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;
const unavailable=()=>({status:'unconfirmed',code:'canonical_scheduler_unavailable'});

// This digest binds a release, group, worker owner and bounded work shape. It is
// an operational configuration check, not a replacement for the database's
// current policy, managed principal, grant, job lease or financial permission.
export async function canonicalSchedulerApproval({sourceSha256,collectionId,owner}){
 return sha256(canonicalJson({contract:'burimunsi.canonical-scheduler.v1',sourceSha256,collectionId,owner,
  receiptLimit:1,rematchLimit:0}));
}

/** Default-off adapter for the existing authenticated jobs endpoint. Nothing
 * in the dispatch body selects a collection, principal, source or financial
 * command. No source is enqueued and no native observation is promoted here.
 */
export async function scheduledCanonicalDrain(env,admission,{runCycle=runCollectNativeScheduledCycle}={}){
 if(env?.BURIMUNSI_CANONICAL_SCHEDULER_ENABLED!=='true')return null;
 try{
  const sourceSha256=env.BUILD_SOURCE_ID,collectionId=env.BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID,
   owner=env.BURIMUNSI_CANONICAL_SCHEDULER_OWNER,managedAccessToken=env.BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN,
   approved=env.BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256,p=admission?.processing,
   processingApproval=p?.approval_sha256,model=p?.model_id;
  if(env.BURIMUNSI_NATIVE_ENABLED!=='true'||env.BURIMUNSI_NATIVE_WORKERS_ENABLED!=='true'||
   env.MOMO_PROCESSING_PAUSED!=='false'||env.MOMO_AI_ENABLED!=='true'||
   !['receipt_processing_v1','receipt_and_push_v1'].includes(env.COLLECT_JOBS_MODE)||
   typeof env.OPENAI_API_KEY!=='string'||!env.OPENAI_API_KEY.trim()||admission?.allowed!==true||!p||
   p.contract!=='collect.receipt-processing.v1'||p.source_sha256!==sourceSha256||p.batch_limit!==1||
   !HASH.test(processingApproval??'')||!MODEL.test(model??'')||
   processingApproval!==env.COLLECT_JOBS_PROCESSING_APPROVAL_SHA256||model!==env.MOMO_AI_MODEL||
   !HASH.test(sourceSha256??'')||!HASH.test(approved??'')||!ID.test(collectionId??'')||!ID.test(owner??'')||
   env.BURIMUNSI_COLLECTION_ID&&env.BURIMUNSI_COLLECTION_ID!==collectionId||
   typeof managedAccessToken!=='string'||managedAccessToken.length<20||managedAccessToken.length>8192||!JWT.test(managedAccessToken)||
   typeof runCycle!=='function')return unavailable();
  if(await canonicalSchedulerApproval({sourceSha256,collectionId,owner})!==approved)return unavailable();
  // Take the exact captured settings across the awaited digest. Downstream
  // checks also revalidate the work fence, policy, grant and credential.
  if(env.BUILD_SOURCE_ID!==sourceSha256||env.BURIMUNSI_CANONICAL_SCHEDULER_ENABLED!=='true'||
   env.BURIMUNSI_NATIVE_ENABLED!=='true'||env.BURIMUNSI_NATIVE_WORKERS_ENABLED!=='true'||
   env.BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID!==collectionId||env.BURIMUNSI_CANONICAL_SCHEDULER_OWNER!==owner||
   env.BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN!==managedAccessToken||
   env.BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256!==approved||env.MOMO_PROCESSING_PAUSED!=='false'||
   env.MOMO_AI_ENABLED!=='true'||env.COLLECT_JOBS_PROCESSING_APPROVAL_SHA256!==processingApproval||
   env.MOMO_AI_MODEL!==model||env.BURIMUNSI_COLLECTION_ID&&env.BURIMUNSI_COLLECTION_ID!==collectionId)return unavailable();
  const result=await runCycle(env,{collectionId,owner,managedAccessToken});
  if(result?.status==='busy')return {status:'busy'};
  if(result?.status==='completed')return {status:'complete'};
  if(result?.status==='yielded')return {status:'yielded'};
  return unavailable();
 }catch{return unavailable();}
}
