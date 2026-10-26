import {ApiError,first,uuid,id,now,digest,integer,text} from './core.js';
import {mutation} from './mutations.js';
import {encrypt} from './encryption.js';
import {momoGuard} from './momo_gateway.js';
function preferences(row,actor) {return {contract_version:1,user_id:actor.userId,revision:row?.revision??1,preferences:{push_enabled:row?.push_enabled!==0,payment_updates:row?.payment_updates!==0,group_updates:row?.group_updates!==0}};}

function registrationGuard(env,actor) {
 const guardId=id();
 // Evaluate expiry in the committing database, after encryption/queue awaits.
 return [env.DB.prepare('INSERT INTO mutation_guards(id,user_id,session_id,now_seconds) VALUES(?,?,?,unixepoch())').bind(guardId,actor.userId,actor.sessionId),
  env.DB.prepare('DELETE FROM mutation_guards WHERE id=?').bind(guardId)];
}
function registrationFailure(error) {
 if(error instanceof ApiError)return error;
 if(/session_changed/.test(String(error?.message??error)))return new ApiError(403,'notification_registration_session_stale','Sign in again to register notifications on this device.');
 return new ApiError(503,'notification_registration_unavailable','Notifications could not connect. Please try again.');
}
async function reconcileRegistration(env,actor,tokenHash,provider,platform) {
 const [check,remove]=registrationGuard(env,actor);
 const result=await env.DB.batch([check,env.DB.prepare(`SELECT id FROM notification_devices WHERE token_hash=? AND user_id=?
  AND owner_session_id=? AND provider=? AND platform=? AND active=1`).bind(tokenHash,actor.userId,actor.sessionId,provider,platform),remove]);
 return result[1].results[0]?.id??null;
}
async function registerDevice(body,env,actor) {
 const token=text(body.p_token,'token',4096),platform=body.p_platform,provider=body.p_provider;
 if(!['android','ios','web'].includes(platform)||!['fcm','apns'].includes(provider)||(provider==='apns'&&platform!=='ios'))
  throw new ApiError(400,'invalid_device','Invalid notification device.');
 if(body.p_environment!==env.APP_ENVIRONMENT)throw new ApiError(400,'invalid_environment','Notification environment does not match.');
 const sha=await digest(token),existing=await first(env,'SELECT id,user_id,owner_session_id,provider,platform FROM notification_devices WHERE token_hash=?',sha);
 if(existing&&existing.user_id!==actor.userId)throw new ApiError(409,'device_owned','This device belongs to a different account.');
 if(existing&&(existing.provider!==provider||existing.platform!==platform))throw new ApiError(409,'notification_device_mismatch','This token belongs to a different notification device.');
 const deviceId=existing?.id??id(),encrypted=await encrypt(env,new TextEncoder().encode(token),`notification:${deviceId}`);
 const [check,remove]=registrationGuard(env,actor),timestamp=now(),requestId=id();
 let result;
 try {
  // Auth session identity and creation time are immutable. D1's insertion
  // order breaks equal-second ties; client tokens, UUID sorting and request
  // arrival after an await never determine which session is newer.
  result=await env.DB.batch([check,
   env.DB.prepare(`INSERT INTO notification_devices(id,user_id,owner_session_id,provider,token_hash,token_ciphertext,platform,active,created_at,updated_at)
    VALUES(?,?,?,?,?,?,?,1,?,?) ON CONFLICT(token_hash) DO UPDATE SET
    owner_session_id=excluded.owner_session_id,active=1,updated_at=excluded.updated_at,
    token_ciphertext=(CASE WHEN notification_devices.id=excluded.id THEN excluded.token_ciphertext ELSE notification_devices.token_ciphertext END)
    WHERE notification_devices.user_id=excluded.user_id AND notification_devices.provider=excluded.provider AND notification_devices.platform=excluded.platform
     AND (notification_devices.owner_session_id=excluded.owner_session_id OR EXISTS(
      SELECT 1 FROM auth_sessions incoming JOIN auth_sessions previous ON previous.id=notification_devices.owner_session_id
      WHERE incoming.id=excluded.owner_session_id AND incoming.user_id=notification_devices.user_id AND previous.user_id=incoming.user_id
       AND (incoming.created_at>previous.created_at OR (incoming.created_at=previous.created_at AND incoming.rowid>previous.rowid))))
    RETURNING id`).bind(deviceId,actor.userId,actor.sessionId,provider,sha,encrypted,platform,timestamp,timestamp),
   // A refused UPSERT must produce neither an acknowledgement nor a success
   // audit. Concurrent first registrations may retain a different stable ID.
   env.DB.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
    SELECT ?,?,'register_notification_device','notification_device',id,?,?,? FROM notification_devices
    WHERE token_hash=? AND user_id=? AND owner_session_id=? AND changes()=1`)
    .bind(actor.userId,actor.sessionId,requestId,JSON.stringify({provider,platform}),timestamp,sha,actor.userId,actor.sessionId),remove]);
 }catch(error) {
  const failure=registrationFailure(error);if(failure.status!==503)throw failure;
  // A lost D1 reply does not establish rollback. Reconcile only the exact
  // stored identity, with current authorization in the same readback batch.
  try {const retained=await reconcileRegistration(env,actor,sha,provider,platform);if(retained)return retained;}
  catch(reconcileError){throw registrationFailure(reconcileError);}
  throw failure;
 }
 const registered=result[1].results[0]?.id;if(registered)return registered;
 const current=await first(env,'SELECT user_id,provider,platform FROM notification_devices WHERE token_hash=?',sha);
 if(current&&current.user_id!==actor.userId)throw new ApiError(409,'device_owned','This device belongs to a different account.');
 if(current&&(current.provider!==provider||current.platform!==platform))throw new ApiError(409,'notification_device_mismatch','This token belongs to a different notification device.');
 throw new ApiError(409,'notification_registration_session_stale','Sign in again to register notifications on this device.');
}
// A support write remains session-bound. This separate read reconciles only
// an already known member-owned request after replacement sign-in, without
// weakening mutation replay or exposing submitted notes/provider references.
async function paymentReviewRequest(body,env,actor){
 const fields=['p_request_id','p_collection_id','p_intent_id'];
 if(Object.keys(body).length!==fields.length||!fields.every(key=>Object.hasOwn(body,key)))throw new ApiError(400,'invalid_payment_review_query','Use the original transfer request and support request identities.');
 const requestId=uuid(body.p_request_id,'request_id'),collectionId=uuid(body.p_collection_id,'collection_id'),intentId=uuid(body.p_intent_id,'intent_id'),guardId=id();
 const [source,removeSource]=momoGuard(env,'EXISTS(SELECT 1 FROM payment_intents WHERE id=? AND member_id=? AND collection_id=?)',[intentId,actor.userId,collectionId]);
 let result;
 try{
  // The current session/user, active membership/group and exact intent are
  // fenced in the same primary D1 batch as both retained record reads.
  result=await env.DB.batch([
   env.DB.prepare('INSERT INTO mutation_guards(id,user_id,session_id,now_seconds,collection_id) VALUES(?,?,?,unixepoch(),?)').bind(guardId,actor.userId,actor.sessionId,collectionId),source,
   env.DB.prepare('SELECT operation,response_json FROM request_receipts WHERE user_id=? AND request_id=?').bind(actor.userId,requestId),
   env.DB.prepare('SELECT id,collection_id,kind,message FROM support_requests WHERE user_id=? AND id=?').bind(actor.userId,requestId),
   removeSource,env.DB.prepare('DELETE FROM mutation_guards WHERE id=?').bind(guardId),
  ]);
 }catch(error){
  const message=String(error?.message??error);
  if(/session_changed/.test(message))throw new ApiError(403,'payment_review_access_changed','Sign in again to check this request.');
  if(/group_access_denied|momo_processing_state/.test(message))throw new ApiError(404,'payment_intent_unavailable','This transfer request is unavailable.');
  throw new ApiError(503,'payment_review_status_unavailable','This request could not be checked. Try again.');
 }
 if(!Array.isArray(result)||result.some(item=>item.success!==true)||!Array.isArray(result[2]?.results)||!Array.isArray(result[3]?.results))throw new ApiError(503,'payment_review_status_unavailable','This request could not be checked. Try again.');
 const receipt=result[2].results[0],support=result[3].results[0],value={id:requestId,status:'received',collection_id:collectionId,intent_id:intentId,financial_effects:0};
 // Absence is a readback at this batch. Retrying must keep the same request
 // ID/body: a late original commit is still fenced by global idempotency.
 if(!receipt&&!support)return {...value,status:'absent'};
 if(receipt&&receipt.operation!=='create_mobile_support_request')throw new ApiError(409,'request_conflict','This request belongs to a different operation or transfer request.');
 if(!receipt||!support)throw new ApiError(503,'payment_review_status_unavailable','This request could not be checked. Try again.');
 if(support.kind!=='payment_review'||support.collection_id!==collectionId)throw new ApiError(409,'request_conflict','This request belongs to a different operation or transfer request.');
 let committed,context;try{committed=JSON.parse(receipt.response_json);context=JSON.parse(support.message);}catch{throw new ApiError(503,'payment_review_status_unavailable','This request could not be checked. Try again.');}
 if(committed?.id!==requestId||committed?.collection_id!==collectionId||committed?.intent_id!==intentId||context?.intent_id!==intentId||context?.collection_id!==collectionId)throw new ApiError(409,'request_conflict','This request belongs to a different operation or transfer request.');
 if(committed.status!=='received'||committed.financial_effects!==0||context.contract_version!==1)throw new ApiError(503,'payment_review_status_unavailable','This request could not be checked. Try again.');
 return value;
}
export async function notificationRpc(operation,body,env,actor) {
 switch(operation){
 case 'get_current_member_payment_review_request_v1':return {handled:true,value:await paymentReviewRequest(body,env,actor)};
 case 'get_notification_preferences_v2':return {handled:true,value:preferences(await first(env,'SELECT * FROM notification_preferences WHERE user_id=?',actor.userId),actor)};
 case 'set_notification_preferences_v2': {
  const p=body.p_preferences;
  if(!p||['push_enabled','payment_updates','group_updates'].some(k=>typeof p[k]!=='boolean'))throw new ApiError(400,'invalid_preferences','Invalid notification preferences.');
  const expected=integer(body.p_expected_revision,'revision',1);const old=await first(env,'SELECT * FROM notification_preferences WHERE user_id=?',actor.userId);
  if((old?.revision??1)!==expected)throw new ApiError(409,'notification_preferences_revision_conflict','Refresh notification preferences before saving.');
  const revision=expected+1;
  const writes=[env.DB.prepare(`INSERT INTO notification_preferences(user_id,push_enabled,payment_updates,group_updates,revision,updated_at) VALUES(?,?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET push_enabled=excluded.push_enabled,payment_updates=excluded.payment_updates,group_updates=excluded.group_updates,revision=excluded.revision,updated_at=excluded.updated_at WHERE notification_preferences.revision=?`).bind(actor.userId,+p.push_enabled,+p.payment_updates,+p.group_updates,revision,now(),expected)];
  return {handled:true,value:await mutation(env,actor,operation,uuid(body.p_request_id??id(),'request_id'),body,{contract_version:1,user_id:actor.userId,revision},writes,{expectedPreferenceRevision:expected})};
 }
 case 'mark_notification_event_read': {
  const event=await first(env,'SELECT * FROM notification_events WHERE id=? AND user_id=?',uuid(body.p_event_id,'event_id'),actor.userId);if(!event)throw new ApiError(404,'notification_unavailable','Notification is unavailable.');
  await mutation(env,actor,operation,id(),body,null,[env.DB.prepare(`UPDATE notification_events SET status='read',read_at=? WHERE id=? AND user_id=?`).bind(now(),event.id,actor.userId)]);return {handled:true,value:null};
 }
 case 'register_notification_device': {
  return {handled:true,value:await registerDevice(body,env,actor)};
 }
 case 'unregister_notification_device': {
  const hash=await digest(text(body.p_token,'token',4096));
  await mutation(env,actor,operation,id(),body,null,[env.DB.prepare(`UPDATE notification_devices SET active=0,updated_at=? WHERE user_id=? AND owner_session_id=? AND token_hash=?`).bind(now(),actor.userId,actor.sessionId,hash)]);return {handled:true,value:null};
 }
 case 'create_mobile_support_request': {
  if(body.p_kind==='payment_review'){
   const requestId=uuid(body.p_request_id,'request_id'),collectionId=uuid(body.p_collection_id,'collection_id'),intentId=uuid(body.p_intent_id,'intent_id');
   const optional=(value,field,max)=>value==null||value===''?null:text(value,field,max);
   const reference=optional(body.p_provider_reference,'provider_reference',160),note=optional(body.p_note,'note',2000);
   const intent=await first(env,'SELECT id FROM payment_intents WHERE id=? AND member_id=? AND collection_id=?',intentId,actor.userId,collectionId);
   if(!intent)throw new ApiError(404,'payment_intent_unavailable','This transfer request is unavailable.');
   const response={id:requestId,status:'received',collection_id:collectionId,intent_id:intentId,financial_effects:0};
   const context={contract_version:1,intent_id:intentId,collection_id:collectionId,provider_reference:reference,evidence_note:note};
   const [check,remove]=momoGuard(env,'EXISTS(SELECT 1 FROM payment_intents WHERE id=? AND member_id=? AND collection_id=?)',[intentId,actor.userId,collectionId]);
   return {handled:true,value:await mutation(env,actor,operation,requestId,body,response,[check,env.DB.prepare(`INSERT INTO support_requests(id,user_id,collection_id,kind,message,created_at) VALUES(?,?,?,'payment_review',?,?)`).bind(requestId,actor.userId,collectionId,JSON.stringify(context),now()),remove],{entityType:'support_request',entityId:requestId})};
  }
  const requestId=uuid(body.p_request_id??id(),'request_id');const message=text(body.p_message??body.message,'message',4000);
  await mutation(env,actor,operation,requestId,body,{id:requestId,status:'received'},[env.DB.prepare(`INSERT INTO support_requests(id,user_id,collection_id,kind,message,created_at) VALUES(?,?,?,?,?,?)`).bind(requestId,actor.userId,body.p_collection_id??null,body.p_kind??'support',message,now())]);return {handled:true,value:{id:requestId,status:'received'}};
 }
 default:return {handled:false};
 }
}
export async function notificationEvents(env,actor) {
 const [check,remove]=registrationGuard(env,actor);let result;
 try {result=await env.DB.batch([check,env.DB.prepare('SELECT * FROM notification_events WHERE user_id=? ORDER BY created_at DESC,id LIMIT 100').bind(actor.userId),remove]);}
 catch(error){if(/session_changed/.test(String(error?.message??error)))throw new ApiError(403,'notification_access_changed','Sign in again to read your notifications.');throw error;}
 // The app model consumes `type`; keep the stored event_type/data fields for
 // existing consumers instead of silently classifying every event as a group update.
 return result[1].results.map(({data_json,...r})=>({...r,type:r.event_type,data:JSON.parse(data_json)}));
}
