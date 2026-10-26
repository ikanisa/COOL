import {requestedAdminEmail} from './admin_email_policy.js';
import {ApiError,digest,stableJson,first,now,id,auditStatement} from './core.js';
function mapped(error) {
  if(error instanceof ApiError)return error;
  const message=String(error.message??error);
  if(/recent_email_(?:verification|sign_in)_required|admin_email_(denied|authority|binding|session_changed)/.test(message))return new ApiError(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');
  if(/session_changed|fresh_auth_required/.test(message))return new ApiError(403,'session_changed','Verify your sign-in before continuing.');
  if(/mfa_required/.test(message))return new ApiError(403,'mfa_required','Complete two-step verification before continuing.');
  if(/native_capability_denied|native_claim_expired|native_consent_required|native_session_changed/.test(message))return new ApiError(403,'native_capability_denied','Android verification is no longer available for this action.');
  if(/permission_denied|group_access_denied/.test(message))return new ApiError(403,'42501','You do not have access to this action.');
  if(/stale_collection|stale_payment|stale_preferences|invitation_changed|recipient_changed|admin_bridge_state|momo_processing_state|UNIQUE constraint/.test(message))return new ApiError(409,'stale_state','This record changed. Refresh before continuing.');
  return error;
}
function guard(env,actor,options={},replay=false) {
  const adminEmail=requestedAdminEmail(actor,options.minimumAssurance);
  if(!adminEmail&&options.minimumAssurance&&(!Number.isInteger(actor.assuranceLevel)||actor.assuranceLevel<options.minimumAssurance))throw new ApiError(403,'mfa_required','Complete two-step verification before continuing.');
  const guardId=id();
  const stmt=env.DB.prepare(`INSERT INTO mutation_guards(id,user_id,session_id,now_seconds,collection_id,required_group_role,permission,fresh_seconds,expected_collection_revision,payment_id,expected_payment_revision,minimum_assurance,expected_mfa_at,expected_preference_revision,invite_collection_id,expected_share_hash,expected_share_version,recipient_user_id,recipient_collection_id,target_collection_id,expected_target_collection_revision) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
    .bind(guardId,actor.userId,actor.sessionId,Math.floor(Date.now()/1000),options.collectionId??null,options.role??null,options.permission??null,options.freshSeconds??null,replay?null:(options.expectedCollectionRevision??null),options.paymentId??null,replay?null:(options.expectedPaymentRevision??null),options.minimumAssurance??null,options.minimumAssurance&&!adminEmail?(actor.mfaAt??null):null,replay?null:(options.expectedPreferenceRevision??null),replay?null:(options.inviteCollectionId??null),replay?null:(options.expectedShareHash??null),replay?null:(options.expectedShareVersion??null),replay?null:(options.recipientUserId??null),replay?null:(options.recipientCollectionId??null),replay?null:(options.targetCollectionId??null),replay?null:(options.expectedTargetCollectionRevision??null));
  return [stmt,env.DB.prepare('DELETE FROM mutation_guards WHERE id=?').bind(guardId)];
}
async function retained(env,actor,operation,requestId,sha,row,options) {
  const [check,remove]=guard(env,actor,options,true);
  try {await env.DB.batch([check,remove]);}catch(error){throw mapped(error);}
  if(row.operation!==operation||row.body_sha256!==sha||row.session_id!==actor.sessionId)throw new ApiError(409,'request_conflict','This request belongs to a different operation or sign-in.');
  return JSON.parse(row.response_json);
}
export async function retainedResponse(env,actor,operation,requestId,body,options={}) {
  const row=await first(env,'SELECT * FROM request_receipts WHERE user_id=? AND request_id=?',actor.userId,requestId);
  if(!row)return {found:false};
  return {found:true,value:await retained(env,actor,operation,requestId,await digest(stableJson(body)),row,options)};
}
export async function mutation(env,actor,operation,requestId,body,response,writes,options={}) {
  const sha=await digest(stableJson(body));
  const previous=await first(env,'SELECT * FROM request_receipts WHERE user_id=? AND request_id=?',actor.userId,requestId);
  if(previous)return retained(env,actor,operation,requestId,sha,previous,options);
  const [check,remove]=guard(env,actor,options);
  const receipt=env.DB.prepare('INSERT INTO request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at) VALUES(?,?,?,?,?,?,?)')
    .bind(actor.userId,requestId,operation,actor.sessionId,sha,JSON.stringify(response),now());
  try {
    await env.DB.batch([check,receipt,...writes,auditStatement(env,actor,operation,options.entityType??'request',options.entityId??requestId,{...options.auditDetails,request_sha256:sha},requestId),remove]);
    return response;
  }catch(error) {
    const committed=await first(env,'SELECT * FROM request_receipts WHERE user_id=? AND request_id=?',actor.userId,requestId);
    if(committed)return retained(env,actor,operation,requestId,sha,committed,options);
    throw mapped(error);
  }
}

export async function assertMutationAdmission(env,actor,writes=[],options={}){const[check,remove]=guard(env,actor,options,true);try{await env.DB.batch([check,...writes,remove]);}catch(error){throw mapped(error);}}
