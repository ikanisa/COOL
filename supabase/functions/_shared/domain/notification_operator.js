import {requireFreshAdminEmail,adminEmailProofId,adminEmailVerifiedAt} from './admin_email_policy.js';
import {ApiError,json,readJson,uuid,integer,id,now,digest,stableJson,auditStatement} from './core.js';
import {adminAccountSession,adminCanonicalActor,accountDatabase,validateAdminOrigin} from './admin_accounts.js';
import {encrypt,decrypt} from './encryption.js';
import {mutation,retainedResponse} from './mutations.js';

const encoder=new TextEncoder(),decoder=new TextDecoder('utf-8',{fatal:true});
const marker={contract_version:1,scope:'assisted_sms_internal_record',delivery_confirmed:false,provider_confirmation:false,settlement_status:'not_asserted'};
const unavailable=()=>new ApiError(409,'sms_claim_unavailable','This claim changed or expired. Refresh its status.');
const options={permission:'assisted_sms.manage',minimumAssurance:2,freshSeconds:300,entityType:'assisted_sms'};
const bodyContext=row=>`assisted-sms-body:${row.id}:${row.payment_id}:${row.entry_id}`;
export const assistedSmsDestinationContext=(collection,user,revision)=>`assisted-sms-destination:${collection}:${user}:${revision}`;
export const assistedSmsLivePaymentSql=`NOT EXISTS(SELECT 1 FROM momo_financial_links momo_link JOIN momo_transactions momo_transaction ON momo_transaction.id=momo_link.transaction_id WHERE momo_link.payment_id=p.id AND momo_transaction.mode='historical')`;
export async function assistedSmsSourceCapabilities(env){
 const [result]=await env.DB.batch([env.DB.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name IN('contribution_posting_snapshots','momo_financial_links','momo_transactions')")]);
 const names=new Set(result.results.map(row=>row.name));
 return {snapshots:names.has('contribution_posting_snapshots'),momo:names.has('momo_financial_links')&&names.has('momo_transactions')};
}
function fields(body,allowed){if(!body||Array.isArray(body)||Object.keys(body).some(k=>!allowed.includes(k)))throw new ApiError(400,'invalid_request','The request contains unsupported fields.');}
function hash(value){if(typeof value!=='string'||!/^[a-f0-9]{64}$/.test(value))throw new ApiError(400,'invalid_request','Supply the exact content digest.');return value;}
function failure(error){
 if(error instanceof ApiError)return error;
 if(/recent_email_(?:verification|sign_in)_required/.test(String(error?.message??error)))return new ApiError(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');
 const value=String(error?.message??error);
 if(/sms_original_session_changed|admin_account_guards|admin_account_authority|session_changed|permission_denied|mfa_required/.test(value))return new ApiError(403,'sms_authority_changed','Your account access changed. Sign in and verify again.');
 if(/sms_.*changed|admin_bridge_state|UNIQUE constraint|CHECK constraint failed: passed=1/.test(value))return unavailable();
 return new ApiError(503,'sms_operation_unknown','The result could not be confirmed. Check the original operation before continuing.');
}
async function context(request,env,permission='assisted_sms.manage'){
 validateAdminOrigin(request,env);
 const account=await adminAccountSession(request,env);
 if(!account.permissions.includes(permission))throw new ApiError(403,'permission_required','Assisted SMS is unavailable for this account.');
 requireFreshAdminEmail(account);
 const scoped=accountDatabase(env,account,permission,{mfa:true,fresh:true});
 const actor=await adminCanonicalActor(request,scoped,account,permission);
 return {env:scoped,actor,account};
}
function stateGuard(env,condition,bindings=[]){
 const key=id();return [env.DB.prepare(`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN ${condition} THEN 1 ELSE 0 END)`).bind(key,...bindings),env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(key)];
}
async function authority(ctx){await ctx.env.DB.batch([ctx.env.DB.prepare('SELECT 1 AS current_authority')]);}
async function query(ctx,sql,...bindings){const [result]=await ctx.env.DB.batch([ctx.env.DB.prepare(sql).bind(...bindings)]);return result.results;}
function identity(ctx){const a=ctx.account;return [a.id,ctx.actor.userId,ctx.actor.sessionId,a.public_id];}
const claimSelect=`SELECT j.*,claim.id AS claim_id,claim.worker_id,claim.expires_seconds,claim.originating_session_id,claim.public_session_id
 FROM assisted_sms_current_jobs j JOIN assisted_sms_claims claim ON claim.id=j.active_claim_id
 WHERE j.id=? AND claim.id=? AND j.fence=? AND claim.fence=j.fence AND j.state='claimed'
 AND claim.actor_admin_id=? AND claim.actor_user_id=? AND claim.originating_session_id=? AND claim.public_session_id=?
 AND claim.expires_seconds>unixepoch()`;
function claimIdentity(body){return [uuid(body.job_id,'job_id'),uuid(body.claim_token,'claim_token'),integer(body.fence_version,'fence_version',1,999999998)];}
async function currentClaim(ctx,body){const rows=await query(ctx,claimSelect,...claimIdentity(body),...identity(ctx));if(rows.length!==1)throw unavailable();return rows[0];}
function claimReceipt(row){return {...marker,job_id:row.job_id,claim_token:row.id,fence_version:row.fence,worker_id:row.worker_id,claim_expires_at:new Date(row.expires_seconds*1000).toISOString(),originating_session_id:row.originating_session_id,public_session_id:row.public_session_id};}
const confirmationReceipt=row=>({...marker,job_id:row.job_id,confirmation_id:row.id,claim_token:row.claim_id,fence_version:row.fence,body_sha256:row.body_sha256,destination_sha256:row.destination_sha256,destination_revision:row.destination_revision,expires_at:new Date(row.expires_seconds*1000).toISOString(),originating_session_id:row.originating_session_id,public_session_id:row.public_session_id});
const startReceipt=row=>({...marker,attempt_id:row.id,job_id:row.job_id,confirmation_id:row.confirmation_id,claim_token:row.claim_id,fence_version:row.fence,state:'send_started',originating_session_id:row.originating_session_id,public_session_id:row.public_session_id});

// This is an internal producer boundary, not an exposed enqueue endpoint. A
// later approved producer must supply genuine policy/recipient authorization.
// Existing reviewed financial facts, consent/destination and policy are read
// again in the same inserting transaction by assisted_sms_job_current.
export async function enqueueAssistedSms(request,base,body){
 fields(body,['payment_id','request_id']);const ctx=await context(request,base),{env,actor}=ctx;
 const paymentId=uuid(body.payment_id,'payment_id'),requestId=uuid(body.request_id,'request_id'),operation='assisted_sms.enqueue';
 const replay=await retainedResponse(env,actor,operation,requestId,body,options);if(replay.found)return replay.value;
 const capabilities=await assistedSmsSourceCapabilities(env);
 const rows=await query(ctx,`SELECT p.*,e.id AS entry_id,e.amount_minor AS entry_amount,c.consent_revision AS consent_revision,c.authorization_receipt_sha256,c.destination_revision,c.destination_sha256,c.destination_ciphertext,
 policy.revision AS policy_revision,policy.approval_reference_sha256 AS policy_approval_sha256,policy.template_key,collection.title AS group_title,
 ${capabilities.snapshots?'snapshot.ledger_entry_id AS snapshot_entry_id,snapshot.member_balance_after_minor,snapshot.group_balance_after_minor':'NULL AS snapshot_entry_id,NULL AS member_balance_after_minor,NULL AS group_balance_after_minor'}
 FROM payments p JOIN ledger_entries e ON e.payment_id=p.id AND e.kind='contribution'
 JOIN collections collection ON collection.id=p.collection_id
 ${capabilities.snapshots?'LEFT JOIN contribution_posting_snapshots snapshot ON snapshot.ledger_entry_id=e.id AND snapshot.payment_id=p.id':''}
 JOIN assisted_sms_authorizations c ON c.collection_id=p.collection_id AND c.recipient_user_id=p.member_id AND c.enabled=1
 JOIN assisted_sms_policies policy ON policy.collection_id=p.collection_id AND policy.enabled=1
 WHERE p.id=? ${capabilities.momo?'AND '+assistedSmsLivePaymentSql:''}`,paymentId);
 if(rows.length!==1)throw new ApiError(409,'sms_eligibility_unavailable','An approved policy and recipient authorization are required.');
 const source=rows[0];if(!Number.isSafeInteger(source.amount_minor)||source.amount_minor<=0||source.entry_amount!==source.amount_minor)throw unavailable();
 if(typeof source.group_title!=='string'||!source.group_title.trim()||source.group_title.length>160||/[\u0000-\u001f\u007f]/.test(source.group_title))throw new ApiError(503,'sms_content_unavailable','The group receipt label could not be verified.');
 const hasSnapshot=source.snapshot_entry_id!==null;
 if(hasSnapshot&&(!Number.isSafeInteger(source.member_balance_after_minor)||source.member_balance_after_minor<=0||!Number.isSafeInteger(source.group_balance_after_minor)||source.group_balance_after_minor<=0))throw new ApiError(503,'sms_snapshot_unavailable','The recorded contribution positions could not be verified.');
 const raw=await decrypt(env,source.destination_ciphertext,assistedSmsDestinationContext(source.collection_id,source.member_id,source.destination_revision));
 const destination=decoder.decode(raw);if(!/^\+2507[2389][0-9]{7}$/.test(destination)||await digest(raw)!==source.destination_sha256)throw new ApiError(503,'sms_content_unavailable','The recipient could not be verified.');
 const jobId=id(),row={id:jobId,payment_id:paymentId,entry_id:source.entry_id};
 const positions=hasSnapshot?` After this contribution: your balance RWF ${source.member_balance_after_minor}; group balance RWF ${source.group_balance_after_minor}.`:'';
 const message=`Collect record: RWF ${source.amount_minor} credited to ${source.group_title.trim()}.${positions} Ref ${paymentId}. Provider confirmation not asserted.`;
 const ciphertext=await encrypt(env,encoder.encode(message),bodyContext(row)),bodySha=await digest(message);
 const response={...marker,job_id:jobId,payment_id:paymentId,state:'queued',body_sha256:bodySha};
 const conditions=['EXISTS(SELECT 1 FROM collections WHERE id=? AND title=?)'],guardArgs=[source.collection_id,source.group_title];
 if(capabilities.momo){conditions.push(`EXISTS(SELECT 1 FROM payments p WHERE p.id=? AND ${assistedSmsLivePaymentSql})`);guardArgs.push(paymentId);}
 if(capabilities.snapshots){conditions.push(hasSnapshot?'EXISTS(SELECT 1 FROM contribution_posting_snapshots WHERE ledger_entry_id=? AND payment_id=? AND member_balance_after_minor=? AND group_balance_after_minor=?)':'NOT EXISTS(SELECT 1 FROM contribution_posting_snapshots WHERE ledger_entry_id=? AND payment_id=?)');guardArgs.push(source.entry_id,paymentId,...(hasSnapshot?[source.member_balance_after_minor,source.group_balance_after_minor]:[]));}
 const sourceGuard=stateGuard(env,conditions.join(' AND '),guardArgs);
 try{return await mutation(env,actor,operation,requestId,body,response,[sourceGuard[0],env.DB.prepare(`INSERT INTO assisted_sms_jobs
 (id,payment_id,entry_id,collection_id,recipient_user_id,payment_revision,amount_minor,destination_revision,destination_sha256,destination_ciphertext,consent_revision,policy_revision,policy_approval_sha256,authorization_receipt_sha256,template_key,body_ciphertext,body_sha256,created_at)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(jobId,paymentId,source.entry_id,source.collection_id,source.member_id,source.revision,source.amount_minor,source.destination_revision,source.destination_sha256,source.destination_ciphertext,source.consent_revision,source.policy_revision,source.policy_approval_sha256,source.authorization_receipt_sha256,source.template_key,ciphertext,bodySha,now()),sourceGuard[1]],{...options,entityId:jobId});}
 catch(error){throw failure(error);}
}
async function pending(ctx,body){
 fields(body,['limit','after_created_at','after_job_id']);const limit=integer(body.limit??20,'limit',1,50),after=body.after_created_at??null,afterId=body.after_job_id??null;
 if((after===null)!==(afterId===null)||after!==null&&(typeof after!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(after)||!Number.isFinite(Date.parse(after))||new Date(after).toISOString()!==after))throw new ApiError(400,'invalid_cursor','Supply a complete valid cursor.');
 if(afterId!==null)uuid(afterId,'after_job_id');
 const rows=await query(ctx,`SELECT id,payment_id,state,created_at,fence,(SELECT a.id FROM assisted_sms_send_starts a WHERE a.job_id=assisted_sms_jobs.id) AS attempt_id FROM assisted_sms_jobs WHERE state IN ('queued','claimed','send_started','uncertain')
 AND (? IS NULL OR created_at>? OR (created_at=? AND id>?)) ORDER BY created_at,id LIMIT ?`,after,after,after,afterId,limit+1);
 const items=rows.slice(0,limit);return {...marker,items,next_cursor:rows.length>limit?{after_created_at:items.at(-1).created_at,after_job_id:items.at(-1).id}:null};
}
async function claim(ctx,body){
 fields(body,['job_id','request_id','worker_id','expected_fence']);const {env,actor,account}=ctx;
 const jobId=uuid(body.job_id,'job_id'),requestId=uuid(body.request_id,'request_id'),previous=integer(body.expected_fence,'expected_fence',0,999999997);
 if(typeof body.worker_id!=='string'||!/^[A-Za-z0-9._:-]{3,80}$/.test(body.worker_id))throw new ApiError(400,'invalid_worker','Supply a valid worker identifier.');
 const replay=await retainedResponse(env,actor,'assisted_sms.claim',requestId,body,options);if(replay.found)return {...replay.value,replay:true};
 const claimId=id(),[clock]=await query(ctx,'SELECT unixepoch() AS seconds'),expires=clock.seconds+120;
 const row={id:claimId,job_id:jobId,fence:previous+1,worker_id:body.worker_id,expires_seconds:expires,originating_session_id:actor.sessionId,public_session_id:account.public_id};
 try{return await mutation(env,actor,'assisted_sms.claim',requestId,body,claimReceipt(row),[env.DB.prepare(`INSERT INTO assisted_sms_claims
 (id,request_id,job_id,actor_admin_id,actor_user_id,originating_session_id,public_session_id,actor_role,actor_auth_version,actor_mfa_at,actor_email_proof_id,actor_email_verified_at,origin,worker_id,previous_fence,fence,created_seconds,expires_seconds)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,unixepoch(),?)`).bind(claimId,requestId,jobId,...identity(ctx),account.role,account.auth_version,null,adminEmailProofId(account),adminEmailVerifiedAt(account),account.origin,body.worker_id,previous,previous+1,expires)],{...options,entityId:jobId});}
 catch(error){throw failure(error);}
}
async function content(ctx,body){
 fields(body,['job_id','claim_token','fence_version']);const row=await currentClaim(ctx,body),{env}=ctx;
 const rawBody=await decrypt(env,row.body_ciphertext,bodyContext(row));
 const rawDestination=await decrypt(env,row.destination_ciphertext,assistedSmsDestinationContext(row.collection_id,row.recipient_user_id,row.destination_revision));
 if(await digest(rawBody)!==row.body_sha256||await digest(rawDestination)!==row.destination_sha256)throw new ApiError(503,'sms_content_unavailable','The claimed content could not be verified.');
 const message=decoder.decode(rawBody),destination=decoder.decode(rawDestination);
 if(!/^\+2507[2389][0-9]{7}$/.test(destination))throw new ApiError(503,'sms_content_unavailable','The recipient could not be verified.');
 // Decryption awaits cannot release plaintext after a winning revocation or
 // changed source/consent. Both the original cookie and claim are checked again.
 await currentClaim(ctx,body);
 return {...marker,job_id:row.id,claim_token:row.claim_id,fence_version:row.fence,destination_e164:destination,destination_sha256:row.destination_sha256,destination_revision:row.destination_revision,
 message_body:message,body_sha256:row.body_sha256,payment_id:row.payment_id,template_key:row.template_key,claim_expires_at:new Date(row.expires_seconds*1000).toISOString()};
}
async function confirm(ctx,body){
 fields(body,['job_id','claim_token','fence_version','request_id','confirmation_id','body_sha256','destination_sha256','destination_revision','user_confirmation']);
 if(body.user_confirmation!==true)throw new ApiError(400,'confirmation_required','Confirm this exact recipient and content before continuing.');
 const {env,actor}=ctx,requestId=uuid(body.request_id,'request_id'),confirmationId=uuid(body.confirmation_id,'confirmation_id');
 const bodySha=hash(body.body_sha256),destinationSha=hash(body.destination_sha256),revision=integer(body.destination_revision,'destination_revision',1);
 const replay=await retainedResponse(env,actor,'assisted_sms.confirm',requestId,body,options);if(replay.found)return {...replay.value,replay:true};
 const row=await currentClaim(ctx,body),[clock]=await query(ctx,'SELECT unixepoch() AS seconds');
 if(row.body_sha256!==bodySha||row.destination_sha256!==destinationSha||row.destination_revision!==revision)throw unavailable();
 const expires=Math.min(row.expires_seconds,clock.seconds+120),record={id:confirmationId,job_id:row.id,claim_id:row.claim_id,fence:row.fence,body_sha256:bodySha,destination_sha256:destinationSha,destination_revision:revision,expires_seconds:expires,originating_session_id:actor.sessionId,public_session_id:ctx.account.public_id};
 try{return await mutation(env,actor,'assisted_sms.confirm',requestId,body,confirmationReceipt(record),[env.DB.prepare(`INSERT INTO assisted_sms_confirmations
 (id,request_id,job_id,claim_id,fence,actor_admin_id,actor_user_id,originating_session_id,public_session_id,body_sha256,destination_sha256,destination_revision,confirmed_seconds,expires_seconds)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,unixepoch(),?)`).bind(confirmationId,requestId,row.id,row.claim_id,row.fence,...identity(ctx),bodySha,destinationSha,revision,expires)],{...options,entityId:row.id});}
 catch(error){throw failure(error);}
}
async function start(ctx,body){
 fields(body,['job_id','claim_token','fence_version','request_id','confirmation_id']);const {env,actor}=ctx;
 const requestId=uuid(body.request_id,'request_id'),confirmationId=uuid(body.confirmation_id,'confirmation_id'),operation='assisted_sms.send_start';
 const replay=await retainedResponse(env,actor,operation,requestId,body,options);
 if(replay.found)return {...replay.value,replay:true,may_send:false,acknowledgement:'recorded_start_permit_not_reissued'};
 let row;
 try{row=await currentClaim(ctx,body);}
 catch(error){
  // Another copy of this exact request can win after the first receipt read
  // but before this claim read. Resolve that committed identity rather than
  // reporting its now-consumed claim as a new operation failure.
  const raced=await retainedResponse(env,actor,operation,requestId,body,options);
  if(raced.found)return {...raced.value,replay:true,may_send:false,acknowledgement:'concurrent_start_observed_permit_not_reissued'};
  throw error;
 }
 const records=await query(ctx,'SELECT * FROM assisted_sms_confirmations WHERE id=?',confirmationId),confirmation=records[0];
 if(!confirmation||confirmation.claim_id!==row.claim_id||confirmation.originating_session_id!==actor.sessionId||confirmation.public_session_id!==ctx.account.public_id)throw unavailable();
 const attempt={id:id(),job_id:row.id,confirmation_id:confirmationId,claim_id:row.claim_id,fence:row.fence,originating_session_id:actor.sessionId,public_session_id:ctx.account.public_id},receipt=startReceipt(attempt),sha=await digest(stableJson(body));
 try{
  // Only a successful FIRST batch acknowledgement can issue the transient
  // response permit. The stored receipt deliberately contains no permit bit.
  await env.DB.batch([
   env.DB.prepare('INSERT INTO request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at) VALUES(?,?,?,?,?,?,?)').bind(actor.userId,requestId,operation,actor.sessionId,sha,JSON.stringify(receipt),now()),
   env.DB.prepare(`INSERT INTO assisted_sms_send_starts
   (id,request_id,job_id,confirmation_id,claim_id,fence,actor_admin_id,actor_user_id,originating_session_id,public_session_id,body_sha256,destination_sha256,destination_revision,started_seconds)
   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,unixepoch())`).bind(attempt.id,requestId,row.id,confirmationId,row.claim_id,row.fence,...identity(ctx),row.body_sha256,row.destination_sha256,row.destination_revision),
   auditStatement(env,actor,operation,'assisted_sms',row.id,{attempt_id:attempt.id,confirmation_id:confirmationId,request_sha256:sha,public_session_id:ctx.account.public_id},requestId),
  ]);
 }catch(error){
  // A lost reply may follow a committed start. Reconcile only this original
  // identity and operation; never issue a second permit, even when it exists.
  try{const retained=await retainedResponse(env,actor,operation,requestId,body,options);if(retained.found)return {...retained.value,replay:true,may_send:false,acknowledgement:'start_observed_after_unknown_reply_permit_not_reissued'};}
  catch(readError){throw failure(readError);}
  throw failure(error);
 }
 await authority(ctx);
 return {...receipt,replay:false,may_send:true,acknowledgement:'first_committed_response_only'};
}
async function release(ctx,body){
 fields(body,['job_id','claim_token','fence_version','request_id']);const {env,actor}=ctx,requestId=uuid(body.request_id,'request_id');
 const replay=await retainedResponse(env,actor,'assisted_sms.release',requestId,body,options);if(replay.found)return replay.value;
 const row=await currentClaim(ctx,body),gate=stateGuard(env,`EXISTS(SELECT 1 FROM assisted_sms_current_jobs WHERE id=? AND state='claimed' AND active_claim_id=? AND fence=?) AND NOT EXISTS(SELECT 1 FROM assisted_sms_send_starts WHERE job_id=?)`,[row.id,row.claim_id,row.fence,row.id]);
 try{return await mutation(env,actor,'assisted_sms.release',requestId,body,{...marker,job_id:row.id,state:'queued',fence_version:row.fence+1},[gate[0],env.DB.prepare("UPDATE assisted_sms_jobs SET state='queued',fence=fence+1,active_claim_id=NULL WHERE id=?").bind(row.id),gate[1]],{...options,entityId:row.id});}
 catch(error){throw failure(error);}
}
async function outcome(ctx,body){
 fields(body,['attempt_id','request_id','observation','evidence_reference_sha256']);const {env,actor}=ctx,requestId=uuid(body.request_id,'request_id'),attemptId=uuid(body.attempt_id,'attempt_id');
 if(!['observed_sent','failed_no_send','uncertain'].includes(body.observation))throw new ApiError(400,'invalid_observation','Record an observation without asserting delivery.');
 const evidence=hash(body.evidence_reference_sha256),receipt={...marker,attempt_id:attemptId,observation:body.observation,evidence_reference_sha256:evidence,may_send:false};
 try{return await mutation(env,actor,'assisted_sms.outcome',requestId,body,receipt,[env.DB.prepare(`INSERT INTO assisted_sms_outcomes
 (id,request_id,attempt_id,observer_admin_id,observer_user_id,observer_session_id,observer_public_session_id,observation,evidence_reference_sha256,observed_seconds)
 VALUES(?,?,?,?,?,?,?,?,?,unixepoch())`).bind(id(),requestId,attemptId,...identity(ctx),body.observation,evidence)],{...options,entityId:attemptId});}
 catch(error){throw failure(error);}
}
async function resolve(ctx,body){
 fields(body,['request_id']);const requestId=uuid(body.request_id,'request_id'),rows=await query(ctx,`SELECT operation,session_id,response_json FROM request_receipts WHERE user_id=? AND request_id=? AND substr(operation,1,13)='assisted_sms.'`,ctx.actor.userId,requestId),row=rows[0];
 if(row&&row.session_id!==ctx.actor.sessionId)throw new ApiError(409,'request_conflict','This operation belongs to another sign-in.');
 return {...marker,request_id:requestId,observed:!!row,receipt:row?JSON.parse(row.response_json):null,may_send:false};
}
export async function notificationOperatorRoute(request,env){
 if(new URL(request.url).pathname!=='/api/admin/notification-operator')return null;
 validateAdminOrigin(request,env);
 if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','Use the authenticated operator command.');
 if(request.headers.get('X-Collect-Admin')!=='1')throw new ApiError(403,'operator_origin_required','Open the configured Admin workspace.');
 const raw=await readJson(request,4096),{action,...body}=raw;
 const handlers={list_pending:pending,claim,get_claimed:content,confirm,record_send_start:start,record_outcome:outcome,release_claim:release,get_operation:resolve};
 if(!Object.hasOwn(handlers,action))throw new ApiError(400,'invalid_action','This operator action is unavailable.');
 const ctx=await context(request,env,action==='list_pending'?'assisted_sms.read':'assisted_sms.manage');
 try{return json({ok:true,result:await handlers[action](ctx,body)});}
 catch(error){throw failure(error);}
}
