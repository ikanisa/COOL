import {ApiError,first,uuid,text,now,id,digest,stableJson,requirePermission} from './core.js';
import {mutation,retainedResponse,assertMutationAdmission} from './mutations.js';
import {consumeNativeCapability,canonicalRwandaPhone,clientSmsCaptureScope} from './native_integrity.js';
import {encrypt,decrypt} from './encryption.js';
import {requireSession} from './auth.js';
import {storageEntity,verifyRetainedObject} from '../storage-identity.js';
import {processingInsert} from './momo_pipeline.js';
// Capture consent belongs to a signed-in installation, independently of an
// optional wallet attestation. A later explicit disable from any session wins;
// another enabled group-attestation record does not erase capture opt-in.
const captureConsent=`EXISTS(SELECT 1 FROM native_consents c JOIN auth_sessions s ON s.id=c.session_id JOIN users u ON u.id=c.user_id
 WHERE c.user_id=? AND c.session_id=? AND c.id=(SELECT max(id) FROM native_consents WHERE user_id=c.user_id AND session_id=c.session_id)
 AND c.enabled=1 AND c.build_channel GLOB 'android_*' AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>unixepoch() AND u.access_status='active'
 AND NOT EXISTS(SELECT 1 FROM native_consents disabled WHERE disabled.user_id=c.user_id AND disabled.id>c.id AND disabled.enabled=0))`;
const captureBudget=`(SELECT count(*) FROM sms_receipts WHERE owner_user_id=? AND created_at>=strftime('%Y-%m-%dT%H:%M:%fZ','now','-60 seconds'))<60
 AND (SELECT count(*) FROM sms_receipts WHERE owner_user_id=? AND created_at>=strftime('%Y-%m-%dT%H:%M:%fZ','now','-1 day'))<1000`;
async function captureAccess(env,actor,{budget=false}={}) {
 if(actor.surface!=='member'||!(await first(env,'SELECT '+captureConsent+' AS allowed',actor.userId,actor.sessionId))?.allowed)
  throw new ApiError(403,'sms_access_required','Enable Android SMS access for this sign-in before uploading.');
 if(budget&&!(await first(env,'SELECT '+captureBudget+' AS allowed',actor.userId,actor.userId))?.allowed)
  throw new ApiError(429,'sms_capture_limited','SMS uploads are temporarily limited. Keep the capture pending and retry later.');
}
function captureGuard(env,actor,{budget=false}={}) {
 const guard=id(),condition=captureConsent+(budget?' AND '+captureBudget:''),params=[actor.userId,actor.sessionId,...(budget?[actor.userId,actor.userId]:[])];
 return [env.DB.prepare('INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN '+condition+' THEN 1 ELSE 0 END').bind(guard,...params),
  env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guard)];
}
export async function receiptFunction(name,body,env,actor) {
 if(!['ingest-payment-sms','ingest-client-sms'].includes(name))return {handled:false};
 const envelope=uuid(body.client_envelope_id,'client_envelope_id');
 if(typeof body.raw_body!=='string'||!body.raw_body||new TextEncoder().encode(body.raw_body).length>16384||body.raw_body.includes('\0'))throw new ApiError(400,'invalid_sms_request','Invalid receipt text.');
 const sender=text(body.raw_sender,'raw_sender',96),bodySha=await digest(body.raw_body),general=body.receiver_momo_number==null&&body.native_capability==null;
 const phone=general?null:canonicalRwandaPhone(body.receiver_momo_number);
 const received=body.received_at_device??null;
 if(received!==null&&(typeof received!=='string'||!Number.isFinite(Date.parse(received))||received.length>64))throw new ApiError(400,'invalid_sms_request','Invalid receipt time.');
 const bindingId=body.gateway_binding_id==null?null:uuid(body.gateway_binding_id,'gateway_binding_id');
 const bindingVersion=body.gateway_binding_version??null;
 if((bindingId===null)!==(bindingVersion===null)||bindingId!==null&&(!Number.isSafeInteger(bindingVersion)||bindingVersion<1))throw new ApiError(400,'invalid_gateway_binding','Select the enrolled receiving source.');
 if(general&&bindingId!==null)throw new ApiError(400,'invalid_gateway_binding','An unverified device capture cannot claim a receiving binding.');
 const completeness=body.completeness??'complete';
 if(!['complete','incomplete','inconsistent'].includes(completeness))throw new ApiError(400,'invalid_sms_request','Record the source completeness.');
 const receiverHash=general?await clientSmsCaptureScope(actor):await digest(phone),identity={client_envelope_id:envelope,raw_sender:body.raw_sender,body_sha256:bodySha,receiver_hash:receiverHash,received_at_device:received,
  ...(bindingId===null?{}:{gateway_binding_id:bindingId,gateway_binding_version:bindingVersion}),...(body.completeness===undefined?{}:{completeness})};
 if(general)await captureAccess(env,actor);
 // A new managed-Auth session can resolve its own durable pre-cutover capture.
 // This is an ACK lookup, never a rewritten financial receipt or fresh upload.
 if(general){const historical=await first(env,'SELECT r.*,q.body_sha256 AS request_sha256,q.response_json FROM sms_receipts r JOIN request_receipts q ON q.user_id=r.owner_user_id AND q.request_id=r.client_envelope_id AND q.operation=\'sms.capture\' WHERE r.owner_user_id=? AND r.client_envelope_id=?',actor.userId,envelope);
  if(historical&&historical.originating_session_id!==actor.sessionId){
   if(historical.request_sha256!==await digest(stableJson(identity)))throw new ApiError(409,'request_conflict','The retained capture has a different identity.');
   await verifyRetainedObject(env,historical);await assertMutationAdmission(env,actor,captureGuard(env,actor));
   const key=await digest('capture-ack:'+actor.sessionId+':'+envelope),rid=`${key.slice(0,8)}-${key.slice(8,12)}-4${key.slice(13,16)}-8${key.slice(17,20)}-${key.slice(20,32)}`;
   const value=JSON.parse(historical.response_json),guards=captureGuard(env,actor);
   return {handled:true,value:await mutation(env,actor,'sms.capture.resolve',rid,identity,value,guards,{entityType:'sms_receipt',entityId:historical.id})};
  }
 }
 const previous=await retainedResponse(env,actor,'sms.capture',envelope,identity);
 if(previous.found){const row=await first(env,'SELECT * FROM sms_receipts WHERE id=? AND owner_user_id=? AND client_envelope_id=?',previous.value.receipt.raw_sms_id,actor.userId,envelope);if(!row)throw new ApiError(503,'receipt_unavailable','Retained receipt storage is unavailable.');await verifyRetainedObject(env,row);await assertMutationAdmission(env,actor,general?captureGuard(env,actor):[]);return {handled:true,value:previous.value};}
 if(general)await captureAccess(env,actor,{budget:true});
 const claim=general?null:await consumeNativeCapability(env,actor,body.native_capability,'sms.ingest',body);
 if(!env.PRIVATE_MEDIA)throw new ApiError(503,'receipt_storage_unavailable','Receipt storage is unavailable.');
 const receiptId=await storageEntity('sms.capture',actor.userId,envelope),objectKey='sms/'+receiptId;
 const payload=new TextEncoder().encode(JSON.stringify({raw_sender:body.raw_sender,normalized_sender:sender,raw_body:body.raw_body,receiver_momo_number:phone,received_at_device:received,completeness,
  ...(general?{source_provenance:'member_device_unverified',receiving_source_known:false}:{})}));
 const objectSha=await digest(payload),cipher=await encrypt(env,payload,`sms:${receiptId}:${objectSha}`);
 await env.PRIVATE_MEDIA.put(objectKey,cipher,{scope:{ownerId:actor.userId,purpose:'sms_receipt',entityId:receiptId},aad:`sms:${receiptId}:${objectSha}`,sourceDigest:await digest(stableJson(identity)),httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:objectSha,key_id:env.DATA_KEY_ID}});
 const response={ok:true,receipt:{contract_version:2,stored:true,raw_sms_id:receiptId,owner_user_id:actor.userId,client_envelope_id:envelope,body_sha256:bodySha,
  ...(general?{source_provenance:'member_device_unverified',receiving_source_known:false,financial_effects:0}:{})}};
 const write=env.DB.prepare(`INSERT INTO sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,received_at_device,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)`).bind(receiptId,actor.userId,actor.sessionId,envelope,bodySha,receiverHash,objectKey,objectSha,payload.length,received,now());
 try {
  // Raw evidence retention and Admin metadata predate the optional extraction
  // schema. An absent pipeline must not make ordinary opted-in capture fail.
  const pipeline=await first(env,"SELECT 1 AS available FROM sqlite_schema WHERE type='table' AND name='momo_processing_jobs'");
  const access=general?captureGuard(env,actor,{budget:true}):null;
  const writes=[...(access?[access[0]]:[claim]),write,...(pipeline?[processingInsert(env,receiptId,{bindingId,bindingVersion})]:[]),...(access?[access[1]]:[])];
  const committed=await mutation(env,actor,'sms.capture',envelope,identity,response,writes,{entityType:'sms_receipt',entityId:receiptId});
  return {handled:true,value:committed};
 }catch(error){
  if(general){await captureAccess(env,actor,{budget:true});}
  if(/gateway_binding_changed|momo_processing_jobs/.test(String(error)))throw new ApiError(409,'gateway_binding_changed','The receiving source changed. Refresh its enrollment before uploading.');throw error;}
}
export async function receiptRoute(request,env,actor) {
 const match=/^\/v1\/receipts\/([0-9a-f-]{36})$/.exec(new URL(request.url).pathname);
 if(!match||request.method!=='GET')return null;
 requirePermission(actor,'sms.raw.reveal');
 const row=await first(env,'SELECT * FROM sms_receipts WHERE id=?',uuid(match[1],'receipt_id'));if(!row)throw new ApiError(404,'receipt_unavailable','Receipt evidence is unavailable.');
 const object=await env.PRIVATE_MEDIA.get(row.object_key);if(!object)throw new ApiError(503,'receipt_unavailable','Retained receipt evidence is unavailable.');
 const bytes=await decrypt(env,await object.text(),`sms:${row.id}:${row.object_sha256}`);
 if(bytes.length!==row.size_bytes||await digest(bytes)!==row.object_sha256)throw new ApiError(503,'receipt_integrity_failed','Retained receipt verification failed.');
 const current=await requireSession(request,env);requirePermission(current,'sms.raw.reveal');
 return new Response(bytes,{headers:{'Content-Type':'application/json','Content-Disposition':'attachment','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
}
