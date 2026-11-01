import {ApiError,uuid,integer,digest,stableJson} from './core.js';
import {contributionIntentJson,normalizeContributionSender,boundCreationReceipt} from './payments.js';
import {compileSql} from '../postgres.js';
import {applicationWork,reserveDatabaseConnection} from '../application-fence.js';

const CREATE='create_contribution_intent';
const MAX_BODY_BYTES=8192;
const statuses=new Set(['pending','expired','cancelled','matched','ambiguous']);
const lookupFields=['p_contract_version','p_original_request_id','p_original_session_id','p_collection_id','p_original_body'];
const bodyFields=['collection','p_expected_amount_rwf','p_sender_phone_hash','p_request_id'];
const reviewFields=['p_contract_version','p_intent_id','p_collection_id'];
const sessionFields=['p_contract_version'];
const queryError=review=>new ApiError(400,review?'invalid_contribution_review_query':'invalid_contribution_command_query','Use the original contribution request identities.');
const accessError=()=>new ApiError(403,'contribution_access_changed','Sign in again to check this contribution request.');
const unavailable=()=>new ApiError(404,'contribution_intent_unavailable','This contribution request is unavailable for payment review.');
const readError=()=>new ApiError(503,'contribution_status_unavailable','This contribution request could not be checked.');

function exactObject(value,fields){
 if(!value||typeof value!=='object'||Array.isArray(value))return false;
 const keys=Reflect.ownKeys(value);
 return keys.length===fields.length&&fields.every(key=>keys.includes(key)&&Object.getOwnPropertyDescriptor(value,key)?.enumerable===true&&Object.hasOwn(Object.getOwnPropertyDescriptor(value,key),'value'));
}
function exactUuid(value){const result=uuid(value);if(result!==value)throw queryError(false);return result;}
function parseLookup(body){
 try{
  if(!exactObject(body,lookupFields)||body.p_contract_version!==1||!exactObject(body.p_original_body,bodyFields))throw 0;
  const request=exactUuid(body.p_original_request_id),session=exactUuid(body.p_original_session_id),collection=exactUuid(body.p_collection_id),original=body.p_original_body;
  if(exactUuid(original.p_request_id)!==request||exactUuid(original.collection)!==collection||typeof original.p_sender_phone_hash!=='string'||!/[a-f0-9]{64}/.test(original.p_sender_phone_hash)||original.p_sender_phone_hash.length!==64)throw 0;
  const amount=integer(original.p_expected_amount_rwf,'amount',1),canonical=stableJson(original);
  if(new TextEncoder().encode(canonical).length>MAX_BODY_BYTES)throw 0;
  return {request,session,collection,amount,canonical,senderHash:original.p_sender_phone_hash};
 }catch{throw queryError(false);}
}
function parseReview(body){
 try{if(!exactObject(body,reviewFields)||body.p_contract_version!==1)throw 0;return {intent:exactUuid(body.p_intent_id),collection:exactUuid(body.p_collection_id)};}
 catch{throw queryError(true);}
}

// The real router has already verified GoTrue and projected this actor. Local
// identity equality binds this invocation; SQL below remains authoritative.
function actorBinding(env,actor){
 const verified=env?.AUTH_VERIFIED,claims=verified?.claims;
 const binding={actor,verified,claims,token:verified?.token,user:actor?.userId,session:actor?.sessionId,surface:actor?.surface,auth:verified?.user?.id,expiry:claims?.exp,issuer:claims?.iss,audience:claims?.aud};
 if(!sameActor(env,actor,binding))throw accessError();
 try{if(uuid(binding.user)!==binding.user||uuid(binding.session)!==binding.session||uuid(binding.auth)!==binding.auth)throw 0;}catch{throw accessError();}
 return binding;
}
function sameActor(env,actor,b){
 return env?.AUTH_ACTOR===actor&&actor===b.actor&&actor?.userId===b.user&&actor?.sessionId===b.session&&actor?.surface===b.surface&&['member','admin'].includes(b.surface)&&actor?.user?.auth_user_id===b.auth&&
  env?.AUTH_VERIFIED===b.verified&&env?.AUTH_VERIFIED?.token===b.token&&typeof b.token==='string'&&b.token.length>0&&env?.AUTH_VERIFIED?.user?.id===b.auth&&env?.AUTH_VERIFIED?.claims===b.claims&&env?.DB?.claims===b.claims&&
  b.claims?.sub===b.auth&&b.claims?.session_id===b.session&&b.claims?.role==='authenticated'&&b.claims?.iss===b.issuer&&b.issuer===env.SUPABASE_URL+'/auth/v1'&&b.claims?.aud===b.audience&&
  (b.audience==='authenticated'||Array.isArray(b.audience)&&b.audience.includes('authenticated'))&&b.claims?.exp===b.expiry&&Number.isSafeInteger(b.expiry)&&b.expiry>Math.floor(Date.now()/1000);
}

const authoritySql=`WITH authority AS (
 SELECT s.id AS authority_session_id,s.user_id AS authority_user_id,s.surface,s.expires_at AS authority_expires_at,
  u.momo_number AS profile_momo_number,u.country_code AS profile_country_code,
  CASE WHEN private.is_managed_session(?::uuid,?::uuid)=true THEN private.session_expiry(unixepoch()+2591999) ELSE NULL END AS managed_expires_at,
  (SELECT a.expires_at FROM admin_sessions a JOIN admin_users u ON u.id=a.user_id JOIN admin_principal_links l ON l.admin_user_id=u.id
   WHERE a.auth_session_id=s.id AND l.user_id=s.user_id AND u.status='active' AND a.auth_version=u.auth_version LIMIT 1) AS admin_expires_at
 FROM auth_sessions s JOIN users u ON u.id=s.user_id
 JOIN private.auth_principal_links l ON l.user_id=s.user_id AND l.auth_user_id=?::uuid
 WHERE s.id=? AND s.user_id=? AND s.surface=? AND s.revoked_at IS NULL AND s.expires_at>unixepoch() AND u.access_status='active'
  AND private.is_managed_session(?::uuid,?::uuid)=true
)
`;
const authorityProjection=`a.authority_session_id,a.authority_user_id,a.surface,a.authority_expires_at,a.managed_expires_at,a.admin_expires_at,clock_timestamp() AS observed_at`;
const admissionSql=`(a.surface='member' OR (a.surface='admin' AND a.admin_expires_at>unixepoch()))`;
const lookupSql=authoritySql+`SELECT ${authorityProjection},r.response_json,r.request_id AS receipt_request_id,p.*
 FROM authority a LEFT JOIN request_receipts r ON r.user_id=a.authority_user_id AND r.request_id=? AND r.operation=? AND r.session_id=? AND r.body_sha256=?
 LEFT JOIN payment_intents p ON p.id=(CASE WHEN json_valid(r.response_json) THEN r.response_json::jsonb->>'id' ELSE NULL END)
  AND p.member_id=a.authority_user_id AND p.collection_id=? AND p.originating_session_id=? AND p.amount_minor=?
 WHERE ${admissionSql}`;
const reviewSql=authoritySql+`SELECT ${authorityProjection},a.profile_momo_number,a.profile_country_code,p.*,
 c.status AS group_status,c.revision AS collection_revision,c.receiver_momo_number AS current_receiver_number,
 c.receiver_network AS current_receiver_network,c.receiver_display_label AS current_receiver_label,m.active AS membership_active,
 r.response_json AS creation_response_json
 FROM authority a LEFT JOIN payment_intents p ON p.id=? AND p.collection_id=? AND p.member_id=a.authority_user_id AND p.originating_session_id=a.authority_session_id
 LEFT JOIN collections c ON c.id=p.collection_id LEFT JOIN memberships m ON m.collection_id=c.id AND m.user_id=a.authority_user_id
 LEFT JOIN request_receipts r ON r.user_id=p.member_id AND r.request_id=p.request_id AND r.operation='create_contribution_intent' AND r.session_id=p.originating_session_id AND r.body_sha256=p.request_sha256
 WHERE ${admissionSql}`;
const sessionSql=authoritySql+`SELECT ${authorityProjection} FROM authority a WHERE ${admissionSql}`;
const authorityValues=b=>[b.auth,b.session,b.auth,b.session,b.user,b.surface,b.auth,b.session];

// One fresh domain SELECT in a real read-only read-committed transaction. A
// repeatable-read snapshot could be acquired by earlier role/claims setup and
// hide a route commit that precedes the domain SELECT. No intent, receipt, ledger or
// domain guard write occurs here. Auth projection/work admission surround it.
async function snapshot(env,query,values){
 let work;try{work=applicationWork(env);}catch{throw readError();}
 try{return await work.local(async()=>{
  let tx,idle=false,result,failure;
  try{
   await work.assert();tx=await reserveDatabaseConnection(env.DB.sql);
   await tx.unsafe('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');
   await env.DB.readContext(tx,{isolation:'read committed'});const q=compileSql(query,values),rows=await tx.unsafe(q.text,q.values);
   if(!Array.isArray(rows)||rows.length>1)throw readError();result=rows[0]??null;
   await work.assert();await tx.unsafe('COMMIT');idle=true;
  }catch(error){
   failure=error;
   if(tx){try{await tx.unsafe('ROLLBACK');idle=true;}catch{try{work.abandon('work_lost');}catch{}}}
  }finally{
   if(tx&&idle){try{tx.release();}catch{failure=readError();try{work.abandon('work_lost');}catch{}}}
   else if(tx){try{work.abandon('work_lost');}catch{}}
  }
  if(failure)throw readError();return result;
 });}catch{throw readError();}
}
function observation(row,binding,env,actor){
 if(!row||!sameActor(env,actor,binding))throw accessError();
 const at=Math.floor(Date.now()/1000);
 if(row.authority_user_id!==binding.user||row.authority_session_id!==binding.session||row.surface!==binding.surface||!Number.isSafeInteger(row.authority_expires_at)||row.authority_expires_at<=at||!Number.isSafeInteger(row.managed_expires_at)||row.managed_expires_at<=at||binding.surface==='admin'&&(!Number.isSafeInteger(row.admin_expires_at)||row.admin_expires_at<=at))throw accessError();
 const value=row.observed_at;
 if(!(value instanceof Date)&&(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)))throw readError();
 const stamp=value instanceof Date?value:new Date(value);
 if(!Number.isFinite(stamp.getTime())||typeof value==='string'&&stamp.toISOString()!==value)throw readError();return stamp.toISOString();
}
function retainedIntent(row,input){
 if(row.receipt_request_id!==input.request||typeof row.response_json!=='string'||new TextEncoder().encode(row.response_json).length>MAX_BODY_BYTES||!statuses.has(row.status))return null;
 try{
  const saved=JSON.parse(row.response_json);
  if(JSON.stringify(saved)!==row.response_json||stableJson(saved)!==stableJson(contributionIntentJson({...row,status:'pending',sender_phone_hash:input.senderHash})))return null;
  if(uuid(row.id)!==row.id||row.collection_id!==input.collection||row.originating_session_id!==input.session||row.amount_minor!==input.amount||row.currency!=='RWF'||row.rail!=='rwanda_momo')return null;
  return {id:row.id,status:row.status};
 }catch{return null;}
}
export async function contributionCommandRpc(operation,body,env,actor){
 if(operation==='get_current_member_contribution_session_v1'){
  if(!exactObject(body,sessionFields)||body.p_contract_version!==1)throw new ApiError(400,'invalid_contribution_session_query','Use the supported contribution session query.');
  const binding=actorBinding(env,actor),row=await snapshot(env,sessionSql,authorityValues(binding)),observedAt=observation(row,binding,env,actor);
  const expires=Math.min(binding.expiry,row.authority_expires_at,row.managed_expires_at,...(binding.surface==='admin'?[row.admin_expires_at]:[]));
  return {handled:true,value:{contract_version:1,binding_kind:'current_contribution_session',issuer:binding.issuer,owner_id:binding.user,auth_subject:binding.auth,session_id:binding.session,
   expires_at:expires,observed_at:observedAt,retry_authorized:false,launch_authorized:false}};
 }
 if(operation==='get_current_member_contribution_command_v1'){
  const input=parseLookup(body),binding=actorBinding(env,actor),sha=await digest(input.canonical);
  if(!sameActor(env,actor,binding))throw accessError();
  const row=await snapshot(env,lookupSql,[...authorityValues(binding),input.request,CREATE,input.session,sha,input.collection,input.session,input.amount]);
  const observedAt=observation(row,binding,env,actor),intent=retainedIntent(row,input);
  return {handled:true,value:{contract_version:1,request_id:input.request,original_session_id:input.session,collection_id:input.collection,body_sha256:sha,
   command_status:intent?'receipt_retained':'unknown',observed_at:observedAt,external_payment:'unknown',retry_authorized:false,launch_authorized:false,observed_intent:intent}};
 }
 if(operation==='review_current_member_contribution_intent_v1'){
  const input=parseReview(body),binding=actorBinding(env,actor);
  const row=await snapshot(env,reviewSql,[...authorityValues(binding),input.intent,input.collection]);
  const observedAt=observation(row,binding,env,actor),expires=Date.parse(row.expires_at),created=Date.parse(row.created_at);
  const sender=normalizeContributionSender(row.profile_momo_number),senderHash=sender?await digest(sender):null;
  if(row.id!==input.intent||row.collection_id!==input.collection||row.member_id!==binding.user||row.originating_session_id!==binding.session||row.status!=='pending'||row.currency!=='RWF'||row.rail!=='rwanda_momo'||
   !Number.isSafeInteger(row.amount_minor)||row.amount_minor<=0||!Number.isFinite(expires)||expires<=Date.now()||!Number.isFinite(created)||row.membership_active!==1||row.group_status!=='active'||
   !Number.isSafeInteger(row.collection_revision)||row.collection_revision<1||row.profile_country_code!=='RW'||!senderHash||!boundCreationReceipt(row,senderHash)||
   !['mtn_momo','airtel_money'].includes(row.receiver_network)||typeof row.receiver_momo_number!=='string'||!/^\+?[0-9]{4,12}$/.test(row.receiver_momo_number)||row.receiver_momo_number!==row.current_receiver_number||row.receiver_network!==row.current_receiver_network||(row.receiver_label??'')!==(row.current_receiver_label??''))throw unavailable();
  if(!sameActor(env,actor,binding))throw accessError();
  return {handled:true,value:{contract_version:1,review_status:'current',collection_id:input.collection,intent_id:input.intent,reviewed_session_id:binding.session,collection_revision:row.collection_revision,
   observed_at:observedAt,external_payment:'unknown',retry_authorized:false,launch_authorized:true,intent:contributionIntentJson({...row,sender_phone_hash:senderHash})}};
 }
 return {handled:false};
}
