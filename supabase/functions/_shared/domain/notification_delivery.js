import {ApiError,digest} from './core.js';
import {decrypt} from './encryption.js';
import {androidNotificationMessage,validPushAdmission,PUSH_BATCH_LIMIT} from '../fcm-notifications.js';

const q=(env,sql,...values)=>env.DB.prepare(sql).bind(...values);
const stamp=()=>Math.floor(Date.now()/1000);
const unavailable=()=>new ApiError(503,'notification_delivery_unconfirmed','Notification delivery could not be confirmed.');
const eligible=alias=>`private.notification_delivery_eligible(${alias}.event_id,${alias}.device_id,${alias}.user_id,${alias}.owner_session_id,${alias}.token_sha256,${alias}.event_sha256)`;
const eventDigest="encode(sha256(convert_to(jsonb_build_array(e.id,e.user_id,e.event_type,e.created_at,e.data_json)::text,'UTF8')),'hex')";
const terminal=new Set(['accepted','rejected','suppressed','unknown']);

// The existing event is committed with the contribution. Bounded INSERT SELECT
// derives each durable event/device obligation without a business/queue dual
// write. Existing or unknown attempts can never be recreated by this scan.
async function enqueue(env,admission){
 return q(env,`INSERT INTO app.notification_deliveries(id,event_id,device_id,user_id,owner_session_id,token_sha256,event_sha256,project_id,android_package,available_at,created_at,updated_at)
  SELECT gen_random_uuid()::text,e.id,d.id,e.user_id,d.owner_session_id,d.token_hash,${eventDigest},?,?,app.unixepoch(),app.unixepoch(),app.unixepoch()
  FROM app.notification_events e JOIN app.notification_devices d ON d.user_id=e.user_id
  WHERE e.event_type='contribution' AND e.status='pending' AND e.created_at>=? AND e.created_at<=?
   AND d.created_at<=e.created_at AND NOT EXISTS(SELECT 1 FROM app.notification_deliveries existing WHERE existing.event_id=e.id AND existing.device_id=d.id)
   AND private.notification_delivery_eligible(e.id,d.id,e.user_id,d.owner_session_id,d.token_hash,${eventDigest})
  ORDER BY e.created_at,e.id,d.id LIMIT 100 ON CONFLICT(event_id,device_id) DO NOTHING`,
  admission.project_id,admission.android_package,new Date(admission.admitted_from*1000).toISOString(),new Date().toISOString()).run();
}

async function recoverExpired(env){
 const result=await q(env,`WITH expired AS MATERIALIZED(
  SELECT id FROM app.notification_deliveries WHERE state IN('claimed','sending') AND lease_until<=app.unixepoch()
  ORDER BY lease_until,id LIMIT 100 FOR UPDATE SKIP LOCKED
 ) UPDATE app.notification_deliveries delivery SET
  state=CASE WHEN delivery.state='sending' THEN 'unknown' WHEN attempt_count>=4 THEN 'rejected' ELSE 'retry' END,
  last_error=CASE WHEN delivery.state='sending' THEN 'delivery_unconfirmed' WHEN attempt_count>=4 THEN 'retry_budget_exhausted' ELSE 'claim_expired_before_send' END,
  attempt_log=jsonb_set(attempt_log,ARRAY[(attempt_count-1)::text],(attempt_log->(attempt_count-1))||jsonb_build_object(
   'state',CASE WHEN delivery.state='sending' THEN 'unknown' WHEN attempt_count>=4 THEN 'rejected' ELSE 'retry' END,
   'code',CASE WHEN delivery.state='sending' THEN 'delivery_unconfirmed' WHEN attempt_count>=4 THEN 'retry_budget_exhausted' ELSE 'claim_expired_before_send' END,'finished_at',app.unixepoch())),
  lease_token=NULL,lease_until=NULL,available_at=app.unixepoch()+60,updated_at=app.unixepoch()
  FROM expired WHERE delivery.id=expired.id RETURNING delivery.state`).all();
 return result.results.filter(row=>row.state==='unknown').length;
}

async function claim(env,admission){
 const lease=crypto.randomUUID();
 return q(env,`WITH candidate AS MATERIALIZED(
  SELECT id FROM app.notification_deliveries WHERE state IN('pending','retry') AND available_at<=app.unixepoch() AND attempt_count<4
   AND project_id=? AND android_package=? ORDER BY available_at,id LIMIT 1 FOR UPDATE SKIP LOCKED
 ) UPDATE app.notification_deliveries delivery SET state='claimed',attempt_count=attempt_count+1,lease_token=?,lease_until=app.unixepoch()+90,
  attempt_log=attempt_log||jsonb_build_array(jsonb_build_object('attempt_id',?::text,'source_sha256',?::text,'approval_sha256',?::text,'started_at',app.unixepoch(),'state','claimed')),
  last_error=NULL,last_http_status=NULL,updated_at=app.unixepoch()
  FROM candidate WHERE delivery.id=candidate.id RETURNING delivery.*`,admission.project_id,admission.android_package,lease,lease,admission.source_sha256,admission.approval_sha256).first();
}

async function finish(env,job,outcome,{beforeSend=false}={}){
 let state=outcome.kind,code=outcome.code??null;
 if(state==='retry'&&job.attempt_count>=4){state='rejected';code='retry_budget_exhausted';}
 if(!['accepted','retry','rejected','suppressed','unknown'].includes(state))throw unavailable();
 const jitter=parseInt(job.id.replaceAll('-','').slice(0,6),16)%31;
 const backoff=Math.max(60*2**Math.max(0,job.attempt_count-1)+jitter,outcome.retryAfterSeconds??0);
 const entry={...job.attempt_log.at(-1),state,finished_at:stamp(),...(code?{code}:{}),...(outcome.httpStatus?{http_status:outcome.httpStatus}:{}),
  ...(state==='accepted'?{provider_message_id:outcome.messageId}:{})};
 const changed=q(env,`UPDATE app.notification_deliveries SET state=?,last_error=?,last_http_status=?,provider_message_id=?,
  available_at=app.unixepoch()+?,lease_token=NULL,lease_until=NULL,updated_at=app.unixepoch(),attempt_log=jsonb_set(attempt_log,ARRAY[(attempt_count-1)::text],(attempt_log->(attempt_count-1))||?::jsonb)
  WHERE id=? AND state=? AND lease_token=? RETURNING state`,state,code,outcome.httpStatus??null,state==='accepted'?outcome.messageId:null,state==='retry'?backoff:0,
  entry,job.id,beforeSend?'claimed':'sending',job.lease_token);
 const statements=[changed];
 if(outcome.disableDevice===true&&state==='rejected')statements.push(q(env,`UPDATE app.notification_devices device SET active=0,updated_at=?
  WHERE device.id=? AND device.user_id=? AND device.owner_session_id=? AND device.token_hash=? AND device.active=1
   AND NOT EXISTS(SELECT 1 FROM app.privacy_retention_barriers WHERE subject_id=device.user_id)
   AND EXISTS(SELECT 1 FROM app.notification_deliveries WHERE id=? AND state='rejected' AND last_error='invalid_registration' AND attempt_log->(attempt_count-1)->>'attempt_id'=?)`,
  new Date().toISOString(),job.device_id,job.user_id,job.owner_session_id,job.token_sha256,job.id,job.lease_token));
 try{const rows=await env.DB.batch(statements);if(rows[0]?.results?.[0]?.state===state)return {state};}catch{
  // A lost local commit response never authorizes another send. Only the same
  // original attempt's durable outcome can reconcile this request.
 }
 const retained=await q(env,'SELECT state,attempt_log FROM app.notification_deliveries WHERE id=?',job.id).first();
 if(retained?.attempt_log?.at(-1)?.attempt_id===job.lease_token&&(terminal.has(retained.state)||retained.state==='retry'))return {state:retained.state};
 throw unavailable();
}

async function processClaim(env,job,admission){
 const device=await q(env,`SELECT device.token_ciphertext FROM app.notification_deliveries delivery
  JOIN app.notification_devices device ON device.id=delivery.device_id WHERE delivery.id=? AND delivery.state='claimed' AND delivery.lease_token=?
   AND delivery.lease_until>app.unixepoch() AND ${eligible('delivery')}`,job.id,job.lease_token).first();
 if(!device)return finish(env,job,{kind:'suppressed',code:'authority_changed'},{beforeSend:true});
 let message;
 try{
  const bytes=await decrypt(env,device.token_ciphertext,'notification:'+job.device_id),token=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
  if(await digest(token)!==job.token_sha256)throw Error('invalid_push_payload');
  message=androidNotificationMessage({eventId:job.event_id,recipientId:job.user_id,token,androidPackage:admission.android_package});
 }catch{return finish(env,job,{kind:'rejected',code:'invalid_push_payload'},{beforeSend:true});}
 const prepared=await env.FCM.prepare();
 if(prepared?.kind!=='ready'||typeof prepared.send!=='function'){
  if(!['retry','rejected'].includes(prepared?.kind))throw unavailable();
  return finish(env,job,prepared,{beforeSend:true});
 }
 // This conditional durable marker is the authorization boundary after the
 // OAuth await. Revocation, read-state, token/session transfer, membership or
 // a privacy barrier before this transaction prevents any message dispatch.
 let started;
 try{started=await q(env,`UPDATE app.notification_deliveries delivery SET state='sending',updated_at=app.unixepoch(),
  attempt_log=jsonb_set(attempt_log,ARRAY[(attempt_count-1)::text],(attempt_log->(attempt_count-1))||jsonb_build_object('state','sending','send_started_at',app.unixepoch()))
  WHERE delivery.id=? AND delivery.state='claimed' AND delivery.lease_token=? AND delivery.lease_until>app.unixepoch()
   AND ${eligible('delivery')} RETURNING id`,job.id,job.lease_token).first();}
 catch(error){if(error?.message==='notification_delivery_authority_changed')return finish(env,job,{kind:'suppressed',code:'authority_changed'},{beforeSend:true});throw unavailable();}
 if(!started)return finish(env,job,{kind:'suppressed',code:'authority_changed'},{beforeSend:true});
 let outcome;try{outcome=await prepared.send(message);}catch{outcome={kind:'unknown',code:'delivery_unconfirmed'};}
 if(!['accepted','retry','rejected','unknown'].includes(outcome?.kind))outcome={kind:'unknown',code:'delivery_unconfirmed'};
 return finish(env,job,outcome);
}

/** @param {object} env
 * @param {{limit?:number,admission?:{contract:string,source_sha256:string,approval_sha256:string,project_id:string,android_package:string,admitted_from:number,batch_limit:number}}} [options] */
export async function drainNotificationDeliveries(env,{limit=PUSH_BATCH_LIMIT,admission}={}){
 if(env.COLLECT_PUSH_ENABLED!=='true')return {status:'disabled',paused:true,processed:0,results:[],recovered_unknown:0};
 if(limit!==PUSH_BATCH_LIMIT||!validPushAdmission(admission)||admission.source_sha256!==env.BUILD_SOURCE_ID||admission.approval_sha256!==env.COLLECT_JOBS_PUSH_APPROVAL_SHA256||
  admission.project_id!==env.FCM_PROJECT_ID||admission.android_package!==env.FCM_ANDROID_PACKAGE||String(admission.admitted_from)!==env.COLLECT_PUSH_ADMITTED_FROM||
  env.FCM?.available!==true||env.FCM.projectId!==admission.project_id||env.FCM.androidPackage!==admission.android_package)throw unavailable();
 const recovered=await recoverExpired(env);await enqueue(env,admission);const job=await claim(env,admission);
 const results=job?[await processClaim(env,job,admission)]:[];
 // 'accepted' is FCM acceptance only. 'unknown' is a retained terminal
 // obligation; acknowledging its durable record never retries that message.
 return {status:'complete',paused:false,processed:results.length,results,recovered_unknown:recovered};
}
