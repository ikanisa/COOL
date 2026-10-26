import {requireFreshAdminEmail} from './admin_email_policy.js';
import {ApiError, auditStatement, digest, first, id, integer, now, requirePermission, stableJson, uuid} from './core.js';
import {mutation} from './mutations.js';
export {handlePrivacyEmailAuth} from './privacy_email_auth.js';
const epoch=()=>Math.floor(Date.now()/1000);
const utc=(value=now())=>new Date(value).toISOString().replace(/\.(\d{3})Z$/,'.$1000Z');
const inactive='policy_authority_unavailable';
const activeStatuses="('received','under_review','scheduled','erasing','on_hold','failed')";
const flags=()=>({policy_acceptance_granted:false,destructive_execution_available:false,erasure_completed:false,
  account_access_restricted:false,auth_removed:false,processor_operation_started:false});
const envelope=(time)=>({contract_version:1,scope:'account_privacy_review_only',checked_at:time,
  completion:'blocked',blocking_reason:inactive,...flags()});
function fields(body,allowed) {
  if(Object.keys(body).some(k=>!allowed.includes(k)))throw new ApiError(400,'invalid_request','The request contains an unsupported field.');
}
function reason(value) {
  if(value===undefined||value===null)return null;
  if(typeof value!=='string'||[...value].length>500||new TextEncoder().encode(value).length>2000||/[\u0000-\u001f\u007f-\u009f]/.test(value))
    throw new ApiError(400,'22023','privacy_request_reason_invalid');
  return value.trim()||null;
}
function conflict() {throw new ApiError(409,'privacy_request_conflict','This request has different details.');}
function unavailable() {throw new ApiError(404,'privacy_request_unavailable','The request is unavailable.');}
function adminActor(actor) {
  requirePermission(actor,'privacy.review');
  if(actor.surface!=='admin')throw new ApiError(403,'admin_required','Admin access is required.');
  requireFreshAdminEmail(actor);
}
async function authority(env,actor,{admin=false,fresh=false}={}) {
  if(admin)adminActor(actor);
  const guard=id();
  try {
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO mutation_guards(id,user_id,session_id,now_seconds,permission,fresh_seconds,minimum_assurance,expected_mfa_at)
        VALUES(?,?,?,?,?,?,?,?)`).bind(guard,actor.userId,actor.sessionId,epoch(),admin?'privacy.review':null,
          fresh&&!admin?300:null,admin?2:null,null),
      env.DB.prepare('DELETE FROM mutation_guards WHERE id=?').bind(guard),
    ]);
  } catch(error) {
    if(/recent_email_(?:verification|sign_in)_required/.test(String(error?.message)))throw new ApiError(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');
    if(/session_changed|fresh_auth_required|mfa_required|permission_denied/.test(String(error?.message)))
      throw new ApiError(403,'session_changed','Verify your sign-in before continuing.');
    throw error;
  }
}
function intake(row,extra={}) {
  return {contract_version:1,request_id:row.id,scope:'own_account_eligible_data',state:'pending_review',
    reason_code:'account_deletion_requested',reason_supplied:row.reason!==null,accepted_at:utc(row.created_at),
    policy_review_pending:true,subject_scope_review_pending:true,erasure_completed:false,account_access_restricted:false,
    auth_removed:false,retention_approval_granted:false,processor_operation_started:false,...extra};
}
async function ownRequest(env,actor,reference) {
  return first(env,`SELECT r.* FROM deletion_requests r WHERE r.user_id=?
    AND (r.id=? OR EXISTS(SELECT 1 FROM privacy_submissions s WHERE s.request_id=r.id AND s.user_id=r.user_id AND s.submission_id=?))`,
    actor.userId,reference,reference);
}
async function submit(operation,body,env,actor) {
  const legacy=operation==='request_account_deletion';
  fields(body,legacy?['request_reason']:['p_request_id','p_reason']);
  const submission=legacy?id():uuid(body.p_request_id,'request_id'), clean=reason(legacy?body.request_reason:body.p_reason);
  const fingerprint=await digest(stableJson({contract_version:1,scope:'own_account_eligible_data',subject_id:actor.userId,reason:clean}));
  await authority(env,actor,{fresh:true});
  for(let attempt=0;attempt<2;attempt++) {
    if(!legacy) {
      const previous=await first(env,'SELECT * FROM privacy_submissions WHERE submission_id=?',submission);
      if(previous) {
        if(previous.user_id!==actor.userId||previous.input_sha256!==fingerprint)conflict();
        const row=await ownRequest(env,actor,previous.request_id);if(!row)unavailable();
        await authority(env,actor,{fresh:true});
        return intake(row,{submission_id:submission,replay:true,equivalent_active_request:true});
      }
    }
    const active=await first(env,`SELECT * FROM deletion_requests WHERE user_id=? AND status IN ${activeStatuses} ORDER BY created_at,id LIMIT 1`,actor.userId);
    if(active&&active.reason!==clean)conflict();
    if(legacy&&active){await authority(env,actor,{fresh:true});return active.id;}
    const timestamp=utc(),requestId=active?.id??submission;
    const response=legacy?requestId:intake(active??{id:requestId,reason:clean,created_at:timestamp},
      {submission_id:submission,replay:false,equivalent_active_request:!!active});
    const writes=[];
    if(!active)writes.push(env.DB.prepare(`INSERT INTO deletion_requests(id,user_id,submission_id,reason,created_at,updated_at) VALUES(?,?,?,?,?,?)`)
      .bind(requestId,actor.userId,submission,clean,timestamp,timestamp));
    if(!legacy)writes.push(env.DB.prepare(`INSERT INTO privacy_submissions(submission_id,request_id,user_id,originating_session_id,input_sha256,created_at)
      VALUES(?,?,?,?,?,?)`).bind(submission,requestId,actor.userId,actor.sessionId,fingerprint,timestamp));
    try {
      return await mutation(env,actor,operation,submission,{reason:clean,submission_id:submission},response,writes,
        {freshSeconds:300,entityType:'privacy_request',entityId:requestId});
    } catch(error) {
      const message=String(error?.message??'');
      if(message.includes('privacy_request_submission_limit'))throw new ApiError(429,'54000','privacy_request_submission_limit');
      if(attempt===0&&(error instanceof ApiError&&error.status===409||/UNIQUE constraint/.test(message)))continue;
      throw error;
    }
  }
  conflict();
}
const joined=`SELECT r.*,h.revision AS review_revision,h.fence AS review_fence,h.state AS head_state,
 c.claim_id,c.claim_request_id,c.actor_id AS claim_actor,c.originating_session_id AS claim_session,
 c.expected_revision,c.revision AS claim_revision,c.fence AS claim_fence,c.lease_seconds,c.claimed_at,c.expires_at,
 o.outcome_request_id,o.actor_id AS outcome_actor,o.originating_session_id AS outcome_session,o.revision AS outcome_revision,o.fence AS outcome_fence,
 o.outcome_code,o.recorded_at FROM deletion_requests r
 LEFT JOIN privacy_review_heads h ON h.request_id=r.id LEFT JOIN privacy_review_claims c ON c.claim_id=h.latest_claim_id
 LEFT JOIN privacy_review_outcomes o ON o.outcome_request_id=h.last_outcome_id`;
function reviewState(row,time) {
  if(!row.head_state)return 'not_started';
  return row.head_state==='claim_active'&&row.expires_at<=time?'claim_expired':row.head_state;
}
function item(row,time) {
  return {request_id:row.id,accepted_at:utc(row.created_at),revision:row.review_revision??0,review_state:reviewState(row,time),
    claim_expires_at:row.expires_at?utc(row.expires_at):null,outcome_code:row.outcome_code??null,
    outcome_recorded_at:row.recorded_at?utc(row.recorded_at):null};
}
function claimReceipt(row) {
  return {contract_version:1,scope:'account_privacy_review_only',request_id:row.request_id??row.id,
    claim_request_id:row.claim_request_id,claim_id:row.claim_id,revision:row.claim_revision??row.revision,
    fence:row.claim_fence??row.fence,claimed_at:utc(row.claimed_at),expires_at:utc(row.expires_at),
    policy_acceptance_granted:false,destructive_execution_available:false,erasure_completed:false};
}
function outcomeReceipt(row) {
  return {contract_version:1,scope:'account_privacy_review_only',request_id:row.request_id??row.id,
    outcome_request_id:row.outcome_request_id,claim_id:row.claim_id,revision:row.outcome_revision??row.revision,
    fence:row.outcome_fence??row.fence,outcome_code:inactive,recorded_at:utc(row.recorded_at),completion:'blocked',...flags()};
}
function claimCurrent(row,actor,time) {
  return !!row&&row.claim_actor===actor.userId&&row.claim_session===actor.sessionId&&reviewState(row,time)==='claim_active'
    &&row.review_revision===row.claim_revision&&row.review_fence===row.claim_fence&&row.expires_at>time;
}
async function subjectReview(body,env,actor) {
  fields(body,['p_request_id']);const reference=uuid(body.p_request_id,'request_id'),request=await ownRequest(env,actor,reference);
  if(!request)unavailable();const row=await first(env,joined+' WHERE r.id=?',request.id);
  await authority(env,actor);const checked=utc();
  return {contract_version:1,scope:'own_account_privacy_review',request_id:row.id,checked_at:checked,revision:row.review_revision??0,
    review_state:reviewState(row,checked),outcome_code:row.outcome_code??null,outcome_recorded_at:row.recorded_at?utc(row.recorded_at):null,
    completion:'blocked',blocking_reason:inactive,subject_scope_review_pending:true,legal_hold_review_pending:true,
    copy_dispositions_verified:false,...flags()};
}
async function adminList(body,env,actor) {
  fields(body,['p_limit','p_before_accepted_at','p_before_request_id']);adminActor(actor);
  const limit=integer(body.p_limit??25,'limit',1,100),before=body.p_before_accepted_at??null,reference=body.p_before_request_id??null;
  if((before===null)!==(reference===null))throw new ApiError(400,'invalid_cursor','Supply a complete review cursor.');
  let date=null;if(before!==null){if(typeof before!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(before)||!Number.isFinite(Date.parse(before)))
    throw new ApiError(400,'invalid_cursor','Invalid review cursor.');date=utc(before);uuid(reference,'request_id');}
  const result=await env.DB.prepare(joined+' WHERE (? IS NULL OR r.created_at<? OR (r.created_at=? AND r.id<?)) ORDER BY r.created_at DESC,r.id DESC LIMIT ?')
    .bind(date,date,date,reference,limit+1).all();await authority(env,actor,{admin:true});const checked=utc(),items=result.results.slice(0,limit).map(r=>item(r,checked));
  return {...envelope(checked),items,limit,next_cursor:result.results.length>limit?{accepted_at:items.at(-1).accepted_at,request_id:items.at(-1).request_id}:null};
}
async function adminDetail(body,env,actor) {
  fields(body,['p_request_id']);adminActor(actor);const reference=uuid(body.p_request_id,'request_id');
  const row=await first(env,joined+' WHERE r.id=?',reference);await authority(env,actor,{admin:true});const checked=utc();
  return {...envelope(checked),item:row?item(row,checked):null,
    own_claim_receipt:row&&row.claim_actor===actor.userId&&row.claim_session===actor.sessionId?claimReceipt(row):null,
    own_outcome_receipt:row&&row.outcome_actor===actor.userId&&row.outcome_session===actor.sessionId?outcomeReceipt(row):null,
    own_claim_authority_current:claimCurrent(row,actor,checked)};
}
async function claimReview(body,env,actor) {
  fields(body,['p_request_id','p_claim_request_id','p_expected_revision','p_lease_seconds']);adminActor(actor);
  const requestId=uuid(body.p_request_id,'request_id'),operationId=uuid(body.p_claim_request_id,'claim_request_id');
  const revision=integer(body.p_expected_revision,'revision',0,999999998),lease=integer(body.p_lease_seconds??60,'lease_seconds',1,120);
  const prior=await first(env,'SELECT * FROM privacy_review_claims WHERE claim_request_id=?',operationId);
  if(prior) {
    if(prior.request_id!==requestId||prior.actor_id!==actor.userId||prior.originating_session_id!==actor.sessionId||prior.expected_revision!==revision||prior.lease_seconds!==lease)conflict();
    await authority(env,actor,{admin:true});return claimReceipt(prior);
  }
  const row=await first(env,joined+' WHERE r.id=?',requestId);if(!row)unavailable();
  const timestamp=utc();
  if((row.review_revision??0)!==revision)throw new ApiError(409,'privacy_review_source_changed','This review changed. Refresh before continuing.');
  if(row.head_state==='blocked')throw new ApiError(409,'privacy_review_policy_authority_unavailable','Approved retention policy is required before further processing.');
  if(row.head_state==='claim_active'&&row.expires_at>timestamp)throw new ApiError(409,'privacy_review_claim_busy','Another review claim is active.');
  const claimId=id(),fence=(row.review_fence??0)+1,expiry=utc(Date.parse(timestamp)+lease*1000);
  const response=claimReceipt({request_id:requestId,claim_request_id:operationId,claim_id:claimId,revision:revision+1,fence,claimed_at:timestamp,expires_at:expiry});
  try {
    return await mutation(env,actor,'admin_claim_account_deletion_review_v1',operationId,body,response,[
      env.DB.prepare(`INSERT INTO privacy_review_heads(request_id,created_at,updated_at) VALUES(?,?,?) ON CONFLICT(request_id) DO NOTHING`).bind(requestId,timestamp,timestamp),
      env.DB.prepare(`INSERT INTO privacy_review_claims(claim_id,claim_request_id,request_id,actor_id,originating_session_id,expected_revision,revision,fence,lease_seconds,claimed_at,expires_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)`).bind(claimId,operationId,requestId,actor.userId,actor.sessionId,revision,revision+1,fence,lease,timestamp,expiry),
      env.DB.prepare(`UPDATE privacy_review_heads SET revision=?,fence=?,state='claim_active',latest_claim_id=?,updated_at=? WHERE request_id=?`)
        .bind(revision+1,fence,claimId,timestamp,requestId),
    ],{permission:'privacy.review',minimumAssurance:2,entityType:'privacy_review',entityId:requestId});
  } catch(error) {
    if(/privacy_review_claim_limit/.test(String(error?.message)))throw new ApiError(429,'privacy_review_claim_limit','Wait before starting another review.');
    if(/privacy_review_source_changed|privacy_review_revision_invalid/.test(String(error?.message)))throw new ApiError(409,'privacy_review_source_changed','This review changed. Refresh before continuing.');
    throw error;
  }
}
async function recordReview(body,env,actor) {
  fields(body,['p_outcome_request_id','p_claim_id','p_fence','p_outcome_code']);adminActor(actor);
  const operationId=uuid(body.p_outcome_request_id,'outcome_request_id'),claimId=uuid(body.p_claim_id,'claim_id'),fence=integer(body.p_fence,'fence',1,1000000000);
  if(body.p_outcome_code!==inactive)throw new ApiError(409,'privacy_review_policy_authority_unavailable','Retention and erasure authority has not been established.');
  const prior=await first(env,'SELECT * FROM privacy_review_outcomes WHERE outcome_request_id=?',operationId);
  if(prior){if(prior.claim_id!==claimId||prior.fence!==fence||prior.actor_id!==actor.userId||prior.originating_session_id!==actor.sessionId)conflict();
    await authority(env,actor,{admin:true});return outcomeReceipt(prior);}
  const claim=await first(env,'SELECT * FROM privacy_review_claims WHERE claim_id=?',claimId);
  if(!claim||claim.actor_id!==actor.userId||claim.originating_session_id!==actor.sessionId)unavailable();
  const head=await first(env,'SELECT * FROM privacy_review_heads WHERE request_id=?',claim.request_id),timestamp=utc();
  if(head.state!=='claim_active'||head.latest_claim_id!==claimId||head.fence!==fence||claim.fence!==fence||claim.expires_at<=timestamp)
    throw new ApiError(409,'privacy_review_claim_stale','This review claim changed or expired.');
  const revision=head.revision+1,response=outcomeReceipt({request_id:claim.request_id,outcome_request_id:operationId,claim_id:claimId,revision,fence,recorded_at:timestamp});
  try {
    return await mutation(env,actor,'admin_record_account_deletion_review_v1',operationId,body,response,[
      env.DB.prepare(`INSERT INTO privacy_review_outcomes(outcome_request_id,request_id,claim_id,actor_id,originating_session_id,fence,revision,outcome_code,recorded_at)
        VALUES(?,?,?,?,?,?,?,?,?)`).bind(operationId,claim.request_id,claimId,actor.userId,actor.sessionId,fence,revision,inactive,timestamp),
      env.DB.prepare(`UPDATE privacy_review_heads SET revision=?,state='blocked',last_outcome_id=?,updated_at=? WHERE request_id=?`)
        .bind(revision,operationId,timestamp,claim.request_id),
    ],{permission:'privacy.review',minimumAssurance:2,entityType:'privacy_review',entityId:claim.request_id});
  }catch(error){if(/privacy_review_claim_stale|privacy_review_revision_invalid/.test(String(error?.message)))
    throw new ApiError(409,'privacy_review_claim_stale','This review claim changed or expired.');throw error;}
}
async function resolveReview(body,env,actor) {
  fields(body,['p_operation_kind','p_operation_id']);adminActor(actor);const kind=body.p_operation_kind;
  if(!['claim','outcome'].includes(kind))throw new ApiError(400,'invalid_request','Invalid review operation.');
  const operation=uuid(body.p_operation_id,'operation_id'),table=kind==='claim'?'privacy_review_claims':'privacy_review_outcomes',key=kind==='claim'?'claim_request_id':'outcome_request_id';
  const row=await first(env,`SELECT * FROM ${table} WHERE ${key}=? AND actor_id=? AND originating_session_id=?`,operation,actor.userId,actor.sessionId);
  const current=row&&kind==='claim'?await first(env,joined+' WHERE r.id=?',row.request_id):null;
  await authority(env,actor,{admin:true});const checked=utc();
  return {...envelope(checked),operation_kind:kind,operation_id:operation,observed:!!row,
    receipt:row?(kind==='claim'?claimReceipt(row):outcomeReceipt(row)):null,
    claim_authority_current:kind==='claim'&&claimCurrent(current,actor,checked)};
}
export async function privacyRpc(operation,body,env,actor) {
  const available=['request_account_deletion','request_account_deletion_v1','get_account_deletion_request_status_v1',
    'get_current_account_deletion_request_status_v1','get_account_deletion_review_status_v1','admin_list_account_deletion_reviews_v1',
    'admin_get_account_deletion_review_v1','admin_claim_account_deletion_review_v1','admin_record_account_deletion_review_v1','admin_get_account_deletion_review_operation_v1'];
  if(!available.includes(operation))return {handled:false};
  let value;
  if(operation==='request_account_deletion'||operation==='request_account_deletion_v1')value=await submit(operation,body,env,actor);
  else if(operation==='get_account_deletion_request_status_v1') {
    fields(body,['p_request_id']);const row=await ownRequest(env,actor,uuid(body.p_request_id,'request_id'));if(!row)unavailable();await authority(env,actor);value=intake(row);
  } else if(operation==='get_current_account_deletion_request_status_v1') {
    fields(body,[]);const row=await first(env,`SELECT * FROM deletion_requests WHERE user_id=? AND status IN ${activeStatuses} ORDER BY created_at,id LIMIT 1`,actor.userId);
    await authority(env,actor);value=row?intake(row):null;
  } else if(operation==='get_account_deletion_review_status_v1')value=await subjectReview(body,env,actor);
  else if(operation==='admin_list_account_deletion_reviews_v1')value=await adminList(body,env,actor);
  else if(operation==='admin_get_account_deletion_review_v1')value=await adminDetail(body,env,actor);
  else if(operation==='admin_claim_account_deletion_review_v1')value=await claimReview(body,env,actor);
  else if(operation==='admin_record_account_deletion_review_v1')value=await recordReview(body,env,actor);
  else value=await resolveReview(body,env,actor);
  return {handled:true,value};
}
