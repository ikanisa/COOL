import {ApiError,uuid} from './domain/core.js';
import {validPushAdmission,PUSH_BATCH_LIMIT} from './fcm-notifications.js';

export const RECEIPT_PROCESSING_MODE='receipt_processing_v1';
export const RECEIPT_PROCESSING_CONTRACT='collect.receipt-processing.v1';
// One 45-second provider attempt leaves room for cleanup, durable lease/commit
// work and the 120-second scheduler transport. Raising this is a new contract.
export const RECEIPT_PROCESSING_LIMIT=1;
export const NOTIFICATION_PROCESSING_MODE='notification_delivery_v1';
export const COMBINED_PROCESSING_MODE='receipt_and_push_v1';
const sha=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const model=value=>typeof value==='string'&&/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/.test(value);
const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const keys=(value,allowed)=>object(value)&&Object.keys(value).length===allowed.length&&Object.keys(value).every(key=>allowed.includes(key));
const fields=['contract','source_sha256','approval_sha256','model_id','batch_limit'];
const invalid=()=>{throw new ApiError(400,'invalid_job_dispatch','The scheduled dispatch contract is invalid.');};

export function parseScheduledDispatch(payload){
 if(!object(payload))invalid();
 const names=Object.keys(payload);
 if(names.length===0)return {dispatchId:null,processing:null,notifications:null}; // Legacy maintenance probe only.
 if(!names.includes('dispatch_id')||names.some(key=>!['dispatch_id','processing_admission','notification_admission'].includes(key)))invalid();
 const dispatchId=uuid(payload.dispatch_id,'dispatch_id'),processing=payload.processing_admission??null,notifications=payload.notification_admission??null;
 if(Object.hasOwn(payload,'processing_admission')&&(!keys(processing,fields)||processing.contract!==RECEIPT_PROCESSING_CONTRACT||
  !sha(processing.source_sha256)||!sha(processing.approval_sha256)||!model(processing.model_id)||processing.batch_limit!==RECEIPT_PROCESSING_LIMIT))invalid();
 if(Object.hasOwn(payload,'notification_admission')&&!validPushAdmission(notifications))invalid();
 return {dispatchId,processing,notifications};
}

export function scheduledProcessingAdmission(env,dispatch){
 const mode=env.COLLECT_JOBS_MODE??'maintenance_only';
 if(mode==='maintenance_only'){
  if(env.MOMO_PROCESSING_PAUSED!=='true'||dispatch.processing!==null||dispatch.notifications!=null)return {allowed:false,code:'maintenance_gate_changed'};
  return {allowed:true,mode,processing:null,notifications:null};
 }
 if(![RECEIPT_PROCESSING_MODE,NOTIFICATION_PROCESSING_MODE,COMBINED_PROCESSING_MODE].includes(mode))return {allowed:false,code:'job_mode_unavailable'};
 const receipts=[RECEIPT_PROCESSING_MODE,COMBINED_PROCESSING_MODE].includes(mode),push=[NOTIFICATION_PROCESSING_MODE,COMBINED_PROCESSING_MODE].includes(mode);
 let processing=null,notifications=null;
 if(receipts){
  if(!dispatch.dispatchId||!dispatch.processing)return {allowed:false,code:'processing_admission_required'};
  const input=dispatch.processing;
  if(env.MOMO_PROCESSING_PAUSED!=='false'||!sha(env.BUILD_SOURCE_ID)||!sha(env.COLLECT_JOBS_PROCESSING_APPROVAL_SHA256)||
   input.source_sha256!==env.BUILD_SOURCE_ID||input.approval_sha256!==env.COLLECT_JOBS_PROCESSING_APPROVAL_SHA256||
   !model(env.MOMO_AI_MODEL)||input.model_id!==env.MOMO_AI_MODEL)return {allowed:false,code:'processing_admission_changed'};
  if(env.MOMO_AI_ENABLED!=='true'||typeof env.OPENAI_API_KEY!=='string'||!env.OPENAI_API_KEY.trim()||typeof env.AI?.run!=='function')return {allowed:false,code:'processing_provider_unavailable'};
  processing={contract:RECEIPT_PROCESSING_CONTRACT,source_sha256:env.BUILD_SOURCE_ID,approval_sha256:env.COLLECT_JOBS_PROCESSING_APPROVAL_SHA256,model_id:env.MOMO_AI_MODEL,batch_limit:RECEIPT_PROCESSING_LIMIT};
 }else if(env.MOMO_PROCESSING_PAUSED!=='true'||dispatch.processing!==null)return {allowed:false,code:'maintenance_gate_changed'};
 if(push){
  const input=dispatch.notifications;
  if(!dispatch.dispatchId||!input)return {allowed:false,code:'notification_admission_required'};
  if(!sha(env.BUILD_SOURCE_ID)||!sha(env.COLLECT_JOBS_PUSH_APPROVAL_SHA256)||input.source_sha256!==env.BUILD_SOURCE_ID||input.approval_sha256!==env.COLLECT_JOBS_PUSH_APPROVAL_SHA256||
   input.project_id!==env.FCM_PROJECT_ID||input.android_package!==env.FCM_ANDROID_PACKAGE||String(input.admitted_from)!==env.COLLECT_PUSH_ADMITTED_FROM)return {allowed:false,code:'notification_admission_changed'};
  if(env.COLLECT_PUSH_ENABLED!=='true'||env.FCM?.available!==true||env.FCM.projectId!==input.project_id||env.FCM.androidPackage!==input.android_package||typeof env.FCM.prepare!=='function')return {allowed:false,code:'notification_provider_unavailable'};
  notifications={...input};
 }else if(dispatch.notifications!=null)return {allowed:false,code:'notification_admission_changed'};
 return {allowed:true,mode,processing,notifications};
}

export function scheduledNotificationResult(result){
 const states=new Set(['accepted','retry','rejected','suppressed','unknown']);
 if(!object(result)||result.status!=='complete'||result.paused!==false||!Number.isSafeInteger(result.processed)||result.processed<0||result.processed>PUSH_BATCH_LIMIT||
  !Array.isArray(result.results)||result.results.length!==result.processed||result.results.some(value=>!object(value)||!states.has(value.state))||
  !Number.isSafeInteger(result.recovered_unknown)||result.recovered_unknown<0||result.recovered_unknown>100)return {status:'unconfirmed',code:'notification_delivery_unconfirmed',processed:0,results:[]};
 return {status:'complete',paused:false,processed:result.processed,results:result.results.map(value=>({state:value.state})),recovered_unknown:result.recovered_unknown};
}

// The operational response records bounded outcomes, not extracted facts,
// transaction identifiers or a claim that provider settlement was confirmed.
export function scheduledProcessingResult(result){
 const states=new Set(['completed','needs_review','retry','not_claimed','superseded']);
 if(!object(result)||result.paused===true||!Number.isSafeInteger(result.processed)||result.processed<0||result.processed>RECEIPT_PROCESSING_LIMIT||
  !Array.isArray(result.results)||result.results.length!==result.processed||result.results.some(value=>!object(value)||!states.has(value.state)))
  return {status:'unconfirmed',code:'receipt_processing_unconfirmed',paused:false,processed:0,results:[]};
 return {status:'complete',paused:false,processed:result.processed,results:result.results.map(value=>({state:value.state}))};
}
