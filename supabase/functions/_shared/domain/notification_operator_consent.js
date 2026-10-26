import {ApiError,uuid,integer,id,now,digest,stableJson} from './core.js';
import {encrypt} from './encryption.js';
import {mutation,retainedResponse} from './mutations.js';
import {assistedSmsDestinationContext} from './notification_operator.js';

const encoder=new TextEncoder();
const marker={contract_version:1,scope:'own_receipt_sms_consent',delivery_confirmed:false,provider_confirmation:false};
const purpose='contribution_receipt_sms';
// Every choice, including a no-op withdrawal, has an immutable receipt. Never
// reset this head by deleting/restoring a partial receipt history.
const decisionCount=`(SELECT count(*) FROM request_receipts WHERE user_id=? AND operation='assisted_sms.consent.set'
 AND json_extract(response_json,'$.collection_id')=? AND json_extract(response_json,'$.purpose')='contribution_receipt_sms')`;
const live=`EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id
 WHERE s.id=? AND s.user_id=? AND s.surface='member' AND s.revoked_at IS NULL
 AND s.expires_at>unixepoch() AND u.access_status='active')`;
function fields(body,allowed){if(!body||Array.isArray(body)||Object.keys(body).some(k=>!allowed.includes(k)))throw new ApiError(400,'invalid_request','The request contains unsupported fields.');}
const changed=()=>new ApiError(409,'sms_consent_changed','Your group, phone verification or consent changed. Refresh before continuing.');
function gate(env,condition,args){const key=id();return [env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN ${condition} THEN 1 ELSE 0 END)`).bind(key,...args),env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(key)];}
async function state(env,actor,collection){
 const row=await env.DB.prepare(`SELECT ${decisionCount} AS decision_revision,u.phone,u.updated_at AS profile_updated_at,u.member_type,c.status AS collection_status,
  m.active AS membership_active,a.enabled,a.consent_revision,a.destination_revision,a.destination_sha256,a.destination_ciphertext,a.authorization_receipt_sha256,a.phone_verification_challenge_id,
  CASE WHEN private.managed_phone_binding(u.id,a.phone_verification_challenge_id,u.phone,NULL) THEN 1 ELSE 0 END AS authorized_phone_binding,
  (SELECT proof.challenge_id FROM private.managed_phone_verifications proof
   WHERE proof.user_id=u.id AND proof.session_id=s.id::uuid AND private.managed_phone_binding(u.id,proof.challenge_id,u.phone,s.id)
   ORDER BY proof.verified_at DESC,proof.challenge_id DESC LIMIT 1) AS verified_challenge_id
 FROM auth_sessions s JOIN users u ON u.id=s.user_id CROSS JOIN collections c
 LEFT JOIN memberships m ON m.collection_id=c.id AND m.user_id=u.id
 LEFT JOIN assisted_sms_authorizations a ON a.collection_id=c.id AND a.recipient_user_id=u.id
 WHERE s.id=? AND s.user_id=? AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>unixepoch()
 AND u.access_status='active' AND c.id=? AND (m.id IS NOT NULL OR a.recipient_user_id IS NOT NULL)`)
 .bind(actor.userId,collection,actor.sessionId,actor.userId,collection).first();
 if(!row)throw new ApiError(403,'sms_consent_unavailable','Your current sign-in cannot access receipt SMS for this group.');
 if(!Number.isSafeInteger(row.decision_revision)||row.decision_revision<0)throw new ApiError(503,'sms_decision_history_unavailable','The recorded choice history could not be verified.');
 return row;
}
function summary(collection,row){
 const proof=row.member_type==='app'&&/^\+2507[2389][0-9]{7}$/.test(row.phone??'')&&row.verified_challenge_id!==null;
 const authorizationStatus=row.enabled!==1?'disabled':row.member_type!=='app'?'direct_verification_pending':row.authorized_phone_binding!==1?'blocked_phone_binding':row.collection_status!=='active'||row.membership_active!==1?'blocked_membership':'active';
 return {...marker,purpose,collection_id:collection,opt_in:row.enabled===1,revision:row.consent_revision??0,decision_revision:row.decision_revision,
  authorization_status:authorizationStatus,consent_effective:authorizationStatus==='active',
  destination_revision:row.destination_revision??null,current_verified_phone_binding:row.authorized_phone_binding===1,phone_verification_available:proof,
  opt_in_available:proof&&row.collection_status==='active'&&row.membership_active===1,
  unavailable_reason:row.member_type==='direct'?'direct_recipient_verification_required':!proof?'current_phone_verification_required':row.collection_status!=='active'||row.membership_active!==1?'active_membership_required':null};
}
function mapped(error){
 if(error instanceof ApiError)return error;
 if(/session_changed|permission_denied/.test(String(error?.message??error)))return new ApiError(403,'sms_authority_changed','Your sign-in changed. Sign in again before continuing.');
 if(/admin_bridge_state|sms_authorization_revision|UNIQUE constraint/.test(String(error?.message??error)))return changed();
 return new ApiError(503,'sms_consent_unknown','The result could not be confirmed. Check the same request before repeating it.');
}
async function setConsent(body,env,actor,collection){
 fields(body,['p_collection_id','p_expected_revision','p_expected_decision_revision','p_opt_in','p_request_id']);
 const expected=integer(body.p_expected_revision,'p_expected_revision',0,999999998),expectedDecision=integer(body.p_expected_decision_revision,'p_expected_decision_revision',0,Number.MAX_SAFE_INTEGER-1),requestId=uuid(body.p_request_id,'p_request_id');
 if(typeof body.p_opt_in!=='boolean')throw new ApiError(400,'explicit_consent_required','Choose whether to receive contribution receipt SMS.');
 const operation='assisted_sms.consent.set',old=await state(env,actor,collection),previous=await retainedResponse(env,actor,operation,requestId,body);
 if(previous.found){await state(env,actor,collection);return {...previous.value,replay:true};}
 if((old.consent_revision??0)!==expected||old.decision_revision!==expectedDecision)throw changed();
 const active=body.p_opt_in;
 if(active&&(old.member_type!=='app'||old.collection_status!=='active'||old.membership_active!==1||!old.verified_challenge_id||!/^\+2507[2389][0-9]{7}$/.test(old.phone??'')))
  throw new ApiError(403,'receipt_sms_phone_proof_required','Use your current verified phone sign-in and active group membership to opt in.');
 const destinationSha=active?await digest(old.phone):old.destination_sha256??null;
 const destinationChanged=active&&destinationSha!==old.destination_sha256,exists=old.consent_revision!==null;
 const update=exists?(old.enabled===1)!==active||destinationChanged||active&&old.authorized_phone_binding!==1:active;
 const revision=update?expected+1:expected,destinationRevision=destinationChanged?(old.destination_revision??0)+1:old.destination_revision??null;
 const timestamp=now(),decision={kind:'authenticated_member_receipt_sms_consent',purpose,request_id:requestId,collection_id:collection,
  recipient_user_id:actor.userId,originating_session_id:actor.sessionId,opt_in:active,consent_revision:revision,decision_revision:expectedDecision+1,
  destination_revision:destinationRevision,destination_sha256:destinationSha,phone_verification_challenge_id:active?old.verified_challenge_id:null,recorded_at:timestamp};
 const decisionSha=await digest(stableJson(decision));
 const cipher=destinationChanged?await encrypt(env,encoder.encode(old.phone),assistedSmsDestinationContext(collection,actor.userId,destinationRevision)):old.destination_ciphertext;
 let condition=live+` AND EXISTS(SELECT 1 FROM collections c LEFT JOIN memberships m ON m.collection_id=c.id AND m.user_id=?
  LEFT JOIN assisted_sms_authorizations a ON a.collection_id=c.id AND a.recipient_user_id=? WHERE c.id=?
  AND (m.id IS NOT NULL OR a.recipient_user_id IS NOT NULL) AND coalesce(a.consent_revision,0)=?)`;
 condition+=` AND ${decisionCount}=?`;
 // mutation() has inserted this request's receipt inside the same batch. A
 // later no-op decision must fence an older request before any state write.
 const args=[actor.sessionId,actor.userId,actor.userId,actor.userId,collection,expected,actor.userId,collection,expectedDecision+1];
 if(active){condition+=` AND EXISTS(SELECT 1 FROM users u JOIN memberships m ON m.user_id=u.id JOIN collections c ON c.id=m.collection_id
  WHERE u.id=? AND u.member_type='app' AND u.phone=? AND u.updated_at=? AND u.access_status='active'
  AND m.collection_id=? AND m.active=1 AND c.status='active' AND private.managed_phone_binding(u.id,?,u.phone,?))`;
  args.push(actor.userId,old.phone,old.profile_updated_at,collection,old.verified_challenge_id,actor.sessionId);
 }
 const check=gate(env,condition,args),writes=[check[0]];
 if(update){
  if(exists)writes.push(env.DB.prepare(`UPDATE assisted_sms_authorizations SET enabled=?,consent_revision=?,destination_revision=?,destination_ciphertext=?,destination_sha256=?,phone_verification_challenge_id=?,authorization_receipt_sha256=?,updated_at=? WHERE collection_id=? AND recipient_user_id=?`)
   .bind(Number(active),revision,destinationRevision,cipher,destinationSha,active?old.verified_challenge_id:old.phone_verification_challenge_id,decisionSha,timestamp,collection,actor.userId));
  else writes.push(env.DB.prepare(`INSERT INTO assisted_sms_authorizations(collection_id,recipient_user_id,enabled,consent_revision,destination_revision,destination_ciphertext,destination_sha256,phone_verification_challenge_id,authorization_receipt_sha256,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)`)
   .bind(collection,actor.userId,1,revision,destinationRevision,cipher,destinationSha,old.verified_challenge_id,decisionSha,timestamp));
 }
 writes.push(check[1]);
 const response={...marker,...decision,decision_sha256:decisionSha,authorization_receipt_sha256:update?decisionSha:old.authorization_receipt_sha256??null,
  recorded_state_only:true,replay:false};
 try{return await mutation(env,actor,operation,requestId,body,response,writes,{entityType:'assisted_sms_consent',entityId:collection,
  auditDetails:{purpose,opt_in:active,consent_revision:revision,decision_revision:expectedDecision+1,decision_sha256:decisionSha}});}
 catch(error){throw mapped(error);}
}
// Existing authenticated RPC dispatch supplies the verified actor. No caller
// can select a recipient, phone, session, proof or arbitrary consent receipt.
export async function assistedSmsConsentRpc(operation,body,base,actor){
 if(!['get_assisted_sms_consent_v1','set_assisted_sms_consent_v1'].includes(operation))return {handled:false};
 if(actor?.surface!=='member')throw new ApiError(403,'member_required','Use your member sign-in to manage receipt SMS.');
 const env={...base,DB:base.DB.withSession?base.DB.withSession('first-primary'):base.DB},collection=uuid(body.p_collection_id,'p_collection_id');
 if(operation==='set_assisted_sms_consent_v1')return {handled:true,value:await setConsent(body,env,actor,collection)};
 fields(body,['p_collection_id']);return {handled:true,value:summary(collection,await state(env,actor,collection))};
}
