import {ApiError,first,id,json,readJson,uuid} from './core.js';
import {authRequest,verifyToken} from '../auth-http.js';
import {attestAdminEmailAccount,adminEmailArguments,adminEmailState} from './admin_email_policy.js';

const epoch=()=>Math.floor(Date.now()/1000);
const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const sessionId=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const invalid=()=>new ApiError(400,'admin_email_invalid','Check the email verification details.');
const denied=()=>new ApiError(403,'admin_email_denied','This email verification is unavailable.');
const unknown=()=>new ApiError(503,'admin_email_operation_unknown','The email verification result is unconfirmed. Check the current verification before continuing.');
const adminEmailDenialCodes=new Set(['admin_email_candidate_denied','admin_email_denied','admin_email_authority','admin_email_binding','admin_email_binding_changed','admin_email_session_changed']);
export function isAdminEmailDenialError(error){return String(error?.message??'').split(/[^A-Za-z0-9_]+/).some(token=>adminEmailDenialCodes.has(token));}
const prefix='?::text,?::text,?::text,?::text';
const signatures={status:'',prepare:',?::text',send_claim:',?::text,?::uuid',send_finish:',?::text,?::uuid,?::text',
 verify_claim:',?::text,?::uuid',record:',?::text,?::uuid',verify_finish:',?::text,?::uuid,?::text',
 cleanup_claim:',?::text,?::uuid,?::uuid',cleanup_finish:',?::text,?::uuid,?::uuid,?::text',record_initial:',?::text'};
function mapped(error){
 if(isAdminEmailDenialError(error))return denied();
 if(/otp_cooldown|admin_email_cooldown/.test(String(error?.message??'')))return new ApiError(429,'auth_rate_limited','Wait before requesting another code.');
 return unknown();
}
async function helper(env,account,name,...args){
 let row;try{row=await first(env,`SELECT private.admin_email_${name}(${prefix}${signatures[name]}) AS result`,...adminEmailArguments(account),...args);}
 catch(error){throw mapped(error);}
 if(!object(row?.result))throw unknown();return row.result;
}
export async function loadAdminEmailAccount(env,account){
 const result=await helper(env,account,'status');attestAdminEmailAccount(account,result);return account;
}
function challenge(result,account,challengeId){
 const c=result?.challenge,now=epoch();
 if(!object(c)||c.id!==challengeId||typeof c.identity_value!=='string'||c.identity_value!==account.email||
  c.original_auth_user_id!==account.auth_user_id||c.original_session_id!==account.auth_session_id||c.principal_id!==account.principal_id||
  !Number.isSafeInteger(c.created_at)||c.created_at<=0||c.created_at>now||!Number.isSafeInteger(c.expires_at)||c.expires_at<=c.created_at||c.expires_at>c.created_at+300||
  !['reserved','accepted','rejected','unknown'].includes(c.delivery_status)||
  !['not_started','verifying','rejected','unconfirmed','verified'].includes(c.verification_state)||
  !['not_started','claimed','confirmed','unconfirmed','not_required'].includes(c.cleanup_state))throw unknown();
 return c;
}
function parse(body,verify=false){
 const allowed=verify?['challenge_id','code','captcha_token']:['captcha_token'];
 if(!object(body)||Object.keys(body).some(key=>!allowed.includes(key)))throw invalid();
 if(body.captcha_token!==undefined&&(typeof body.captcha_token!=='string'||!body.captcha_token||body.captcha_token.length>8192||/[\u0000-\u001f\u007f]/.test(body.captcha_token)))throw invalid();
 if(!verify)return body;
 if(typeof body.code!=='string'||!/^\d{6}$/.test(body.code))throw invalid();
 return {...body,challenge_id:uuid(body.challenge_id,'challenge_id')};
}
async function original(env,account){
 const verified=await verifyToken(env,account.supabaseTokens?.access_token);
 if(verified.user.id!==account.auth_user_id||verified.claims.session_id!==account.auth_session_id||
  typeof verified.user.email_confirmed_at!=='string'||!Number.isFinite(Date.parse(verified.user.email_confirmed_at))||
  verified.user.email?.toLowerCase()!==account.email)throw denied();
 env.DB.setClaims(verified.claims);return verified;
}
function otpEvents(verified,c){
 const now=epoch(),events=[];
 if(c.expires_at<now)throw denied();
 // SQL derives the authoritative managed AMR event. Its explicit one-second
 // JWT comparison tolerance must not be narrowed to an arbitrary oldest event.
 for(const entry of Array.isArray(verified.claims.amr)?verified.claims.amr:[]){
  if(object(entry)&&entry.method==='otp'&&Number.isSafeInteger(entry.timestamp)&&entry.timestamp>=c.created_at-1&&entry.timestamp>0&&entry.timestamp<=now+1&&now-entry.timestamp<=301)
   events.push(entry.timestamp);
 }
 if(!events.length)throw denied();return events;
}
function validCandidate(verified,account,c){
 if(verified.user.id!==account.auth_user_id||!sessionId(verified.claims.session_id)||verified.claims.session_id===account.auth_session_id||
  typeof verified.user.email_confirmed_at!=='string'||!Number.isFinite(Date.parse(verified.user.email_confirmed_at))||
  verified.user.email?.toLowerCase()!==c.identity_value)throw denied();
 return otpEvents(verified,c);
}
const rejected=error=>error instanceof ApiError&&[400,401,403,422,429].includes(error.status);
async function finishVerify(env,account,challengeId,operation,outcome){
 try{challenge(await helper(env,account,'verify_finish',challengeId,operation,outcome),account,challengeId);}
 catch{throw unknown();}
}
export async function requestAdminEmail(env,account,input){
 const body=parse(input),verified=await original(env,account),challengeId=id();
 const prepared=await helper(env,account,'prepare',challengeId),c=challenge(prepared,account,challengeId);
 if(prepared.created!==true)throw unknown();
 const claim=id(),admission=await helper(env,account,'send_claim',challengeId,claim);challenge(admission,account,challengeId);
 if(admission.claimed!==true)throw unknown();
 let outcome='accepted';
 try{await authRequest(env,'/otp',{body:{email:c.identity_value,create_user:false,gotrue_meta_security:{captcha_token:body.captcha_token}}});}
 catch(error){outcome=rejected(error)?'rejected':'unknown';}
 env.DB.setClaims(verified.claims);
 const completed=challenge(await helper(env,account,'send_finish',challengeId,claim,outcome),account,challengeId);
 await loadAdminEmailAccount(env,account);
 if(outcome==='rejected')throw new ApiError(400,'admin_email_send_rejected','The email code request was not accepted. Check the verification details.');
 return json({challenge_id:challengeId,retry_after:60,expires_in:Math.max(0,completed.expires_at-epoch()),delivery_status:outcome},202);
}
export async function verifyAdminEmail(env,account,input){
 const body=parse(input,true),verifiedOriginal=await original(env,account),operation=id();
 const admission=await helper(env,account,'verify_claim',body.challenge_id,operation),c=challenge(admission,account,body.challenge_id);
 if(c.expires_at<epoch())throw new ApiError(400,'invalid_credentials','The email code is invalid or expired.');
 if(admission.claimed!==true)throw unknown();
 let data,verifiedCandidate,event,providerAccepted=false;
 try{
  data=await authRequest(env,'/verify',{body:{email:c.identity_value,token:body.code,type:'email',gotrue_meta_security:{captcha_token:body.captcha_token}}});
  providerAccepted=true;
  if(!object(data)||typeof data.access_token!=='string'||!data.access_token||data.access_token.length>16384||/\s/.test(data.access_token))throw unknown();
  verifiedCandidate=await verifyToken(env,data.access_token);event=validCandidate(verifiedCandidate,account,c);
 }catch(error){
  env.DB.setClaims(verifiedOriginal.claims);
  const definitiveRejection=!providerAccepted&&rejected(error);
  await finishVerify(env,account,body.challenge_id,operation,definitiveRejection?'rejected':'unconfirmed');
  // Do not log, persist or return a candidate bearer. No repeat /verify, no
  // projection and no risk of logging out the original BFF-managed session.
  throw definitiveRejection?new ApiError(400,'invalid_credentials','The email code is invalid or expired.'):unknown();
 }
 let recorded;
 try{
  env.DB.setClaims(verifiedCandidate.claims);
  recorded=challenge(await helper(env,account,'record',body.challenge_id,operation),account,body.challenge_id);
  if(recorded.verification_state!=='verified'||recorded.verified_session_id!==verifiedCandidate.claims.session_id||!Number.isSafeInteger(recorded.verified_amr_at)||recorded.verified_amr_at<c.created_at||recorded.verified_amr_at>c.expires_at||!event.some(timestamp=>Math.abs(timestamp-recorded.verified_amr_at)<=1))throw unknown();
 }finally{env.DB.setClaims(verifiedOriginal.claims);}
 const cleanupClaim=id(),cleanup=await helper(env,account,'cleanup_claim',body.challenge_id,operation,cleanupClaim);
 challenge(cleanup,account,body.challenge_id);if(cleanup.claimed!==true)throw unknown();
 let outcome='confirmed';
 try{await authRequest(env,'/logout?scope=local',{token:data.access_token});}catch{outcome='unconfirmed';}
 env.DB.setClaims(verifiedOriginal.claims);
 const completed=challenge(await helper(env,account,'cleanup_finish',body.challenge_id,operation,cleanupClaim,outcome),account,body.challenge_id);
 if(outcome!=='confirmed'||completed.cleanup_state!=='confirmed')throw unknown();
 await loadAdminEmailAccount(env,account);
 return json(adminEmailState(account));
}
export async function recordInitialAdminEmail(env,account,challengeId){
 // Only the caller that completed the existing email/admin OTP challenge uses
 // this path. SQL derives OTP AMR and the consumed challenge itself; password,
 // Google, refresh and privacy proof cannot create this authorization.
 uuid(challengeId,'challenge_id');
 const verified=await verifyToken(env,account.supabaseTokens?.access_token);
 if(verified.user.id!==account.auth_user_id||verified.claims.session_id!==account.auth_session_id||
  typeof verified.user.email_confirmed_at!=='string'||!Number.isFinite(Date.parse(verified.user.email_confirmed_at))||
  verified.user.email?.toLowerCase()!==account.email)throw denied();
 env.DB.setClaims(verified.claims);
 try{await helper(env,account,'record_initial',challengeId);}catch(error){
  // One dispatch only. An acknowledgement loss is reconciled by current proof
  // state, never by repeating record or the provider OTP exchange.
  await loadAdminEmailAccount(env,account);if(adminEmailState(account).emailVerifiedAt===null)throw error;return;
 }
 await loadAdminEmailAccount(env,account);
}
export async function handleAdminEmail(request,env,account,path){
 if(path==='/auth/email-verification'){
  if(request.method!=='GET')throw new ApiError(405,'method_not_allowed','Use GET.');
  if(new URL(request.url).search||new URL(request.url).hash)throw invalid();
  return json(adminEmailState(account));
 }
 if(path!=='/auth/email/request'&&path!=='/auth/email/verify')return null;
 if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','Use POST.');
 if(new URL(request.url).search||new URL(request.url).hash)throw invalid();
 const body=await readJson(request,12288);
 return path==='/auth/email/request'?requestAdminEmail(env,account,body):verifyAdminEmail(env,account,body);
}
