import {createHash} from 'node:crypto';

export const CONTRACT_SHA = '9c88f77dacb0f5757f09b8a246b115462b2e25c135de6807c68df33d6ece534e';
export const MARKER = Object.freeze({contract_version:1,scope:'assisted_sms_internal_record',delivery_confirmed:false,provider_confirmation:false,settlement_status:'not_asserted'});
export const ACTIONS = Object.freeze(['list_pending','claim','get_claimed','confirm','record_send_start','record_outcome','release_claim','get_operation']);
export const WRITES = new Set(['claim','confirm','record_send_start','record_outcome','release_claim']);
export const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
export const HASH = /^[a-f0-9]{64}$/;
export const ORIGINS = Object.freeze(['https://platform-admin.collect.ikanisa.com','https://admin-supabase-qa.collect.ikanisa.com']);
export class OperatorError extends Error {
  constructor(code, {unknown=false}={}) { super(code); this.name='OperatorError'; this.code=code; this.outcomeUnknown=unknown; }
}
export const need=(value,code='invalid_contract')=>{if(!value)throw new OperatorError(code);};
export const plain=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&Object.getPrototypeOf(value)===Object.prototype;
export const sha=value=>createHash('sha256').update(value).digest('hex');
export function canonical(value) {
  if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
  if(plain(value))return '{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}';
  need(value===null||typeof value==='string'||typeof value==='boolean'||typeof value==='number'&&Number.isFinite(value),'invalid_canonical_value');
  return JSON.stringify(value);
}
export const same=(a,b)=>canonical(a)===canonical(b);
export function keys(value,required,optional=[]) {
  need(plain(value),'invalid_object');
  need(required.every(key=>Object.hasOwn(value,key))&&Object.keys(value).every(key=>required.includes(key)||optional.includes(key)),'unsupported_or_missing_fields');
  return value;
}
export const uuid=value=>{need(typeof value==='string'&&UUID.test(value),'invalid_uuid');return value;};
export const hash=value=>{need(typeof value==='string'&&HASH.test(value),'invalid_digest');return value;};
export const integer=(value,min=1,max=999999998)=>{need(Number.isSafeInteger(value)&&value>=min&&value<=max,'invalid_integer');return value;};
export function timestamp(value) {
  need(typeof value==='string'&&/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)&&Number.isFinite(Date.parse(value))&&new Date(value).toISOString()===value,'invalid_timestamp');
  return value;
}
export const REQUESTS = Object.freeze({
  list_pending:{required:[],optional:['limit','after_created_at','after_job_id']},
  claim:{required:['job_id','request_id','worker_id','expected_fence'],optional:[]},
  get_claimed:{required:['job_id','claim_token','fence_version'],optional:[]},
  confirm:{required:['job_id','claim_token','fence_version','request_id','confirmation_id','body_sha256','destination_sha256','destination_revision','user_confirmation'],optional:[]},
  record_send_start:{required:['job_id','claim_token','fence_version','request_id','confirmation_id'],optional:[]},
  record_outcome:{required:['attempt_id','request_id','observation','evidence_reference_sha256'],optional:[]},
  release_claim:{required:['job_id','claim_token','fence_version','request_id'],optional:[]},
  get_operation:{required:['request_id'],optional:[]},
});
export function request(action,input) {
  need(ACTIONS.includes(action),'unsupported_action');
  const spec=REQUESTS[action];keys(input,spec.required,spec.optional);
  for(const [key,value]of Object.entries(input)) {
    if(['job_id','request_id','claim_token','confirmation_id','attempt_id','after_job_id'].includes(key))uuid(value);
    else if(key==='expected_fence')integer(value,0,999999997);
    else if(key==='fence_version'||key==='destination_revision')integer(value);
    else if(key==='limit')integer(value,1,50);
    else if(key.endsWith('_sha256'))hash(value);
    else if(key==='worker_id')need(typeof value==='string'&&/^[A-Za-z0-9._:-]{3,80}$/.test(value),'invalid_worker');
    else if(key==='after_created_at')timestamp(value);
    else if(key==='user_confirmation')need(value===true,'explicit_confirmation_required');
    else if(key==='observation')need(['observed_sent','failed_no_send','uncertain'].includes(value),'invalid_observation');
  }
  need(Object.hasOwn(input,'after_created_at')===Object.hasOwn(input,'after_job_id'),'incomplete_cursor');
  need(Buffer.byteLength(JSON.stringify({action,...input}))<=4096,'request_too_large');
  return structuredClone(input);
}
function marker(value) { for(const [key,expected]of Object.entries(MARKER))need(value[key]===expected,'wrong_semantic_marker'); }
export function receipt(action,value,{stored=false}={}) {
  need(plain(value),'invalid_receipt'); marker(value);
  const base=Object.keys(MARKER), common=['job_id','claim_token','fence_version'];
  const fields={
    list_pending:['items','next_cursor'],
    claim:[...common,'worker_id','claim_expires_at','originating_session_id','public_session_id'],
    get_claimed:[...common,'destination_e164','destination_sha256','destination_revision','message_body','body_sha256','payment_id','template_key','claim_expires_at'],
    confirm:[...common,'confirmation_id','body_sha256','destination_sha256','destination_revision','expires_at','originating_session_id','public_session_id'],
    record_send_start:[...common,'attempt_id','confirmation_id','state','originating_session_id','public_session_id',...stored?[]:['replay','may_send','acknowledgement']],
    record_outcome:['attempt_id','observation','evidence_reference_sha256','may_send'],
    release_claim:['job_id','state','fence_version'],
    get_operation:['request_id','observed','receipt','may_send'],
  };
  keys(value,[...base,...fields[action]],['replay']);
  for(const key of ['job_id','claim_token','confirmation_id','attempt_id','payment_id','originating_session_id','public_session_id','request_id'])if(Object.hasOwn(value,key))uuid(value[key]);
  for(const key of ['body_sha256','destination_sha256','evidence_reference_sha256'])if(Object.hasOwn(value,key))hash(value[key]);
  for(const key of ['fence_version','destination_revision'])if(Object.hasOwn(value,key))integer(value[key]);
  for(const key of ['claim_expires_at','expires_at'])if(Object.hasOwn(value,key))timestamp(value[key]);
  if(Object.hasOwn(value,'replay'))need(typeof value.replay==='boolean','invalid_replay');
  if(action==='list_pending') {
    need(Array.isArray(value.items)&&value.items.length<=50,'invalid_pending');
    for(const item of value.items) {
      keys(item,['id','payment_id','state','created_at','fence','attempt_id']);
      uuid(item.id);uuid(item.payment_id);timestamp(item.created_at);integer(item.fence,0);
      need(['queued','claimed','send_started','uncertain'].includes(item.state),'invalid_pending_state');
      if(item.attempt_id!==null)uuid(item.attempt_id);
    }
    need(new Set(value.items.map(item=>item.id)).size===value.items.length,'duplicate_pending_job');
    if(value.next_cursor!==null){keys(value.next_cursor,['after_created_at','after_job_id']);timestamp(value.next_cursor.after_created_at);uuid(value.next_cursor.after_job_id);}
  }
  if(action==='claim')need(/^[A-Za-z0-9._:-]{3,80}$/.test(value.worker_id),'invalid_worker');
  if(action==='get_claimed') {
    need(/^\+2507[2389][0-9]{7}$/.test(value.destination_e164),'invalid_destination');
    need(typeof value.message_body==='string'&&value.message_body.length>0&&Buffer.byteLength(value.message_body)<=4096&&!/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value.message_body),'invalid_message');
    need(sha(value.message_body)===value.body_sha256&&sha(value.destination_e164)===value.destination_sha256,'content_digest_mismatch');
    need(typeof value.template_key==='string'&&/^[A-Za-z0-9._:-]{1,100}$/.test(value.template_key),'invalid_template');
  }
  if(action==='record_send_start') {
    need(value.state==='send_started','invalid_start_state');
    if(!stored) {
      need(typeof value.may_send==='boolean'&&typeof value.acknowledgement==='string'&&/^[a-z_]{1,100}$/.test(value.acknowledgement),'invalid_start_ack');
      need(!value.may_send||value.replay===false&&value.acknowledgement==='first_committed_response_only','reissued_permit_refused');
    }
  }
  if(action==='release_claim')need(value.state==='queued','invalid_release_state');
  if(action==='record_outcome')need(value.may_send===false&&['observed_sent','failed_no_send','uncertain'].includes(value.observation),'invalid_outcome');
  if(action==='get_operation')need(typeof value.observed==='boolean'&&value.may_send===false&&(value.observed?plain(value.receipt):value.receipt===null),'invalid_operation_receipt');
  return structuredClone(value);
}
export function sanitized(value) {
  if(Array.isArray(value))return value.map(sanitized);
  if(plain(value))return Object.fromEntries(Object.entries(value).filter(([key])=>!['destination_e164','message_body','manual_handoff'].includes(key)).map(([key,item])=>[key,key==='may_send'?false:sanitized(item)]));
  return value;
}
export function publicSession(value,now=Date.now()) {
  keys(value,['id','email','role','sessionId','expiresAt','permissions','assuranceLevel','mfaAt','principalId','financialModel']);
  for(const key of ['id','sessionId','principalId'])uuid(value[key]);
  timestamp(value.expiresAt);need(Date.parse(value.expiresAt)>now,'session_expired');
  need(typeof value.email==='string'&&value.email.length<=254&&['owner','admin','staff'].includes(value.role),'invalid_session_user');
  need(value.financialModel==='canonical_evidence_ledger'&&[1,2].includes(value.assuranceLevel),'invalid_session_assurance');
  need(Array.isArray(value.permissions)&&value.permissions.length<=256&&new Set(value.permissions).size===value.permissions.length&&value.permissions.every(item=>typeof item==='string'&&/^[a-z][a-z0-9_.]{1,100}$/.test(item)),'invalid_permissions');
  if(value.assuranceLevel===2)timestamp(value.mfaAt);else need(value.mfaAt===null,'invalid_session_assurance');
  return structuredClone(value);
}
export const authorityKey=user=>canonical({id:user.id,principalId:user.principalId,sessionId:user.sessionId,role:user.role,permissions:[...user.permissions].sort(),expiresAt:user.expiresAt,assuranceLevel:user.assuranceLevel,mfaAt:user.mfaAt});


// A separate sidecar supplies sensitive-operation email proof. It never changes
// the provider's public user/AAL DTO or the underlying BFF identity.
export function emailVerification(value,sessionId,now=Date.now()) {
  keys(value,['contractVersion','sessionId','emailVerifiedAt']);
  uuid(sessionId);uuid(value.sessionId);
  need(sessionId!=='00000000-0000-0000-0000-000000000000','email_verification_session_mismatch');
  need(value.contractVersion===1&&value.sessionId===sessionId,'email_verification_session_mismatch');
  if(value.emailVerifiedAt!==null) {
    timestamp(value.emailVerifiedAt);
    need(Date.parse(value.emailVerifiedAt)<=now,'future_email_verification_refused');
  }
  return structuredClone(value);
}
export const sensitiveAuthorityKey=(user,emailVerifiedAt)=>canonical({
  actor:authorityKey(user),verification_method:'email',email_verified_at:emailVerifiedAt,
});
export function hasFreshEmailVerification(snapshot,now=Date.now(),maxAgeMs=300000) {
  const proof=Date.parse(snapshot?.emailVerifiedAt??'');
  return Number.isSafeInteger(maxAgeMs)&&maxAgeMs>=0&&maxAgeMs<=300000&&snapshot?.proofState==='available'&&Number.isFinite(proof)&&proof<=now&&proof>=now-maxAgeMs&&Date.parse(snapshot.user.expiresAt)>now;
}
