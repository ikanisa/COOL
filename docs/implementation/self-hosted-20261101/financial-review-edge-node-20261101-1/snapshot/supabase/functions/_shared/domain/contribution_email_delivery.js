import {ApiError,digest,stableJson} from './core.js';
import {sendTransactionalEmail,transactionalEmailAvailable} from './email_delivery.js';

const q=(env,sql,...values)=>env.DB.prepare(sql).bind(...values);
const hash="encode(sha256(convert_to(jsonb_build_array(e.id,e.user_id,e.event_type,e.created_at,e.data_json)::text,'UTF8')),'hex')";
const eligible=alias=>`private.notification_email_eligible(${alias}.event_id,${alias}.user_id,${alias}.recipient_sha256,${alias}.event_sha256)`;
const invalid=()=>new ApiError(503,'contribution_email_unavailable','The contribution email could not be confirmed.');

export function renderContributionEmail(event){
 let data;try{data=typeof event.data_json==='string'?JSON.parse(event.data_json):event.data_json;}catch{throw invalid();}
 const fields=['payment_id','collection_id','amount_rwf','member_balance_after_contribution_rwf','group_balance_after_contribution_rwf','group_name','posted_at','balance_basis'];
 if(!data||Array.isArray(data)||Object.keys(data).sort().join('|')!==fields.sort().join('|')||
  !['payment_id','collection_id'].every(k=>/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(data[k]))||
  !['amount_rwf','member_balance_after_contribution_rwf','group_balance_after_contribution_rwf'].every(k=>Number.isSafeInteger(data[k]))||data.amount_rwf<=0||
  typeof data.group_name!=='string'||!data.group_name.trim()||data.group_name.length>160||/[\x00-\x1f\x7f-\x9f]/.test(data.group_name)||
  data.balance_basis!=='after_this_contribution'||typeof data.posted_at!=='string'||!Number.isFinite(Date.parse(data.posted_at)))throw invalid();
 return {subject:'Your recorded Collect contribution',text:[
  `Collect recorded a contribution of RWF ${data.amount_rwf} for ${data.group_name}.`,
  `Your recorded balance after this contribution: RWF ${data.member_balance_after_contribution_rwf}.`,
  `Group recorded balance after this contribution: RWF ${data.group_balance_after_contribution_rwf}.`,
  `Recorded at: ${data.posted_at}.`, `Reference: ${data.payment_id}.`,
  'These are the recorded positions at this entry, not a current available-funds or provider-settlement confirmation.',
  'You can change receipt email preferences in Collect.',
 ].join('\n\n')};
}

export function validContributionEmailAdmission(env,admission){
 return !!admission&&!Array.isArray(admission)&&Object.keys(admission).sort().join(',')==='admitted_from,approval_sha256,batch_limit,contract,source_sha256'&&admission.contract==='collect.contribution-email.v1'&&
  /^[a-f0-9]{64}$/.test(admission.source_sha256)&&admission.source_sha256===env.BUILD_SOURCE_ID&&
  /^[a-f0-9]{64}$/.test(admission.approval_sha256)&&admission.approval_sha256===env.COLLECT_JOBS_EMAIL_APPROVAL_SHA256&&
  Number.isSafeInteger(admission.admitted_from)&&admission.admitted_from>0&&admission.admitted_from<4102444800&&
  String(admission.admitted_from)===env.COLLECT_EMAIL_ADMITTED_FROM&&admission.batch_limit===1;
}

const unconfirmed=()=>({status:'unconfirmed',processed:0,results:[]});
function retainedResult(row,admissionJson,admissionSha){
 if(!row||row.admission_sha256!==admissionSha||row.admission_json!==admissionJson)throw invalid();
 if(row.state!=='completed')return unconfirmed();
 let result;try{result=JSON.parse(row.result_json);}catch{throw invalid();}
 if(!completeResult(result))throw invalid();return result;
}
function completeResult(result){
 return result&&Object.keys(result).sort().join(',')==='processed,results,status'&&result.status==='complete'&&
  Number.isSafeInteger(result.processed)&&result.processed>=0&&result.processed<=1&&Array.isArray(result.results)&&result.results.length===result.processed&&
  result.results.every(row=>row&&Object.keys(row).sort().join(',')==='delivery_confirmed,state'&&['accepted','suppressed','unknown'].includes(row.state)&&row.delivery_confirmed===false);
}

/** Persist the outer dispatch before claiming any event. Replays, including an
 * empty original probe, read its original result and never drain another event. */
export async function drainContributionEmailDispatch(env,{dispatchId,admission}={}){
 if(env.COLLECT_CONTRIBUTION_EMAIL_ENABLED!=='true'||!validContributionEmailAdmission(env,admission)||
  !/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(dispatchId??''))throw invalid();
 const admissionJson=stableJson(admission),admissionSha=await digest(admissionJson);
 const read=()=>q(env,'SELECT admission_sha256,admission_json,state,result_json FROM app.notification_email_job_dispatches WHERE id=?',dispatchId).first();
 await q(env,`UPDATE app.notification_email_job_dispatches SET state='unknown',updated_seconds=app.unixepoch()
  WHERE id IN(SELECT id FROM app.notification_email_job_dispatches WHERE state='claimed' AND created_seconds<app.unixepoch()-120 ORDER BY created_seconds,id LIMIT 100)`).run();
 let claimed;
 try{claimed=await q(env,`INSERT INTO app.notification_email_job_dispatches(id,admission_sha256,admission_json)
  VALUES(?,?,?) ON CONFLICT(id) DO NOTHING RETURNING id`,dispatchId,admissionSha,admissionJson).first();}
 catch{return retainedResult(await read(),admissionJson,admissionSha);}
 if(!claimed)return retainedResult(await read(),admissionJson,admissionSha);
 try{
  const result=await drainContributionEmails(env,{admission,dispatchId});if(!completeResult(result))throw invalid();
  const saved=await q(env,`UPDATE app.notification_email_job_dispatches SET state='completed',result_json=?,updated_seconds=app.unixepoch()
   WHERE id=? AND state='claimed' RETURNING id`,stableJson(result),dispatchId).first();
  if(!saved)throw invalid();return result;
 }catch{
  // A lost finish acknowledgment may already be durable. Read it before
  // retaining uncertainty; neither branch acquires another send obligation.
  try{const row=await read();if(row?.state==='completed')return retainedResult(row,admissionJson,admissionSha);
   await q(env,"UPDATE app.notification_email_job_dispatches SET state='unknown',updated_seconds=app.unixepoch() WHERE id=? AND state='claimed'",dispatchId).run();
  }catch{}return unconfirmed();
 }
}

/** One bounded obligation per call. A lost SMTP/commit result never retries. */
export async function drainContributionEmails(env,{admission,dispatchId}={}){
 if(env.COLLECT_CONTRIBUTION_EMAIL_ENABLED!=='true')return {status:'disabled',processed:0,results:[]};
 if(!validContributionEmailAdmission(env,admission)||!transactionalEmailAvailable(env)||
  dispatchId!==undefined&&!/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(dispatchId))throw invalid();
 await q(env,`UPDATE app.notification_email_deliveries SET state='unknown',updated_seconds=app.unixepoch()
  WHERE id IN(SELECT id FROM app.notification_email_deliveries WHERE state='sending' AND started_seconds<app.unixepoch()-120 ORDER BY started_seconds,id LIMIT 100)`).run();
 await q(env,`INSERT INTO app.notification_email_deliveries(id,event_id,user_id,recipient_sha256,event_sha256)
  SELECT gen_random_uuid()::text,e.id,e.user_id,encode(sha256(convert_to(lower(u.email),'UTF8')),'hex'),${hash}
  FROM app.notification_events e JOIN app.users u ON u.id=e.user_id
  WHERE e.event_type='contribution' AND e.created_at>=? AND e.created_at<=?
   AND NOT EXISTS(SELECT 1 FROM app.notification_email_deliveries old WHERE old.event_id=e.id)
   AND private.notification_email_eligible(e.id,e.user_id,encode(sha256(convert_to(lower(u.email),'UTF8')),'hex'),${hash})
  ORDER BY e.created_at,e.id LIMIT 100 ON CONFLICT(event_id) DO NOTHING`,
  new Date(admission.admitted_from*1000).toISOString(),new Date().toISOString()).run();
 await q(env,`UPDATE app.notification_email_deliveries delivery SET state='suppressed',updated_seconds=app.unixepoch()
  WHERE delivery.id IN(SELECT id FROM app.notification_email_deliveries candidate WHERE state='pending' AND NOT ${eligible('candidate')} ORDER BY created_seconds,id LIMIT 100)`).run();
 const candidate=await q(env,`SELECT delivery.*,e.data_json,lower(u.email) AS destination FROM app.notification_email_deliveries delivery
  JOIN app.notification_events e ON e.id=delivery.event_id JOIN app.users u ON u.id=delivery.user_id
  WHERE delivery.state='pending' AND ${eligible('delivery')} ORDER BY delivery.created_seconds,delivery.id LIMIT 1`).first();
 if(!candidate)return {status:'complete',processed:0,results:[]};
 let message;
 try{message=renderContributionEmail(candidate);if(await digest(candidate.destination)!==candidate.recipient_sha256)throw invalid();}
 catch{await q(env,"UPDATE app.notification_email_deliveries SET state='suppressed',updated_seconds=app.unixepoch() WHERE id=? AND state='pending'",candidate.id).run();return {status:'complete',processed:1,results:[{state:'suppressed',delivery_confirmed:false}]};}
 const attempt=dispatchId??crypto.randomUUID();
 const started=await q(env,`UPDATE app.notification_email_deliveries delivery SET state='sending',attempt_id=?,started_seconds=app.unixepoch(),updated_seconds=app.unixepoch()
  WHERE delivery.id=? AND delivery.state='pending' AND ${eligible('delivery')} RETURNING id`,attempt,candidate.id).first();
 if(!started)return {status:'complete',processed:0,results:[]};
 let state='unknown',messageId=null;
 try{const receipt=await sendTransactionalEmail(env,{to:candidate.destination,...message});messageId=receipt.messageId;state='accepted';}catch{}
 try{const saved=await q(env,`UPDATE app.notification_email_deliveries SET state=?,provider_message_id=?,updated_seconds=app.unixepoch()
  WHERE id=? AND state='sending' AND attempt_id=? RETURNING state`,state,messageId,candidate.id,attempt).first();if(!saved)throw invalid();state=saved.state;}
 catch{
  const retained=await q(env,'SELECT state,attempt_id FROM app.notification_email_deliveries WHERE id=?',candidate.id).first();
  if(retained?.attempt_id!==attempt||!['accepted','unknown'].includes(retained.state))throw invalid();
  state=retained.state;
 }
 return {status:'complete',processed:1,results:[{state,delivery_confirmed:false}]};
}
