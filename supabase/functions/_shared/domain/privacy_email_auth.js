import {ApiError,json,readJson,first,digest,id,uuid} from './core.js';
import {authRequest,verifyToken} from '../auth-http.js';
import {projectSession} from './auth.js';

const purpose='account_deletion_request';
const epoch=()=>Math.floor(Date.now()/1000);
const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const modes=['current_session','portal_bootstrap'];
const verificationStates=['not_started','verifying','rejected','unconfirmed','verified'];
const cleanupStates=['not_started','claimed','confirmed','unconfirmed'];
const denied=()=>new ApiError(403,'privacy_email_denied','This verification is unavailable.');
const invalid=()=>new ApiError(400,'privacy_email_invalid','Check the verification details.');
const unknown=()=>new ApiError(503,'privacy_email_operation_unknown','The verification result is unconfirmed. Check its status before continuing.');
const helperSql={
 prepare:'SELECT private.privacy_email_prepare(?::text,?::text,?::text,?::text) AS result',
 send_claim:'SELECT private.privacy_email_send_claim(?::text,?::text,?::uuid) AS result',
 send_finish:'SELECT private.privacy_email_send_finish(?::text,?::text,?::uuid,?::text) AS result',
 verify_claim:'SELECT private.privacy_email_verify_claim(?::text,?::text,?::uuid) AS result',
 verify_finish:'SELECT private.privacy_email_verify_finish(?::text,?::text,?::uuid,?::text) AS result',
 consume:'SELECT private.privacy_email_consume(?::text,?::text,?::uuid) AS result',
 status:'SELECT private.privacy_email_status(?::text,?::text) AS result',
 cancel:'SELECT private.privacy_email_cancel(?::text,?::text,?::uuid) AS result',
 cleanup_claim:'SELECT private.privacy_email_cleanup_claim(?::text,?::text,?::uuid,?::uuid) AS result',
 cleanup_finish:'SELECT private.privacy_email_cleanup_finish(?::text,?::text,?::uuid,?::uuid,?::text) AS result',
};
function dbError(error) {
 const message=String(error?.message??'');
 if(message.includes('privacy_email_denied'))return denied();
 if(message.includes('privacy_email_invalid'))return invalid();
 if(message.includes('otp_cooldown'))return new ApiError(429,'auth_rate_limited','Wait before requesting another code.');
 return unknown();
}
function challengeResult(result,input) {
 const c=result?.challenge;
 if(!object(result)||!object(c)||c.id!==input.challenge_id||c.mode!==input.mode||
  typeof c.identity_value!=='string'||c.identity_value.length>254||
  !Number.isSafeInteger(c.created_at)||!Number.isSafeInteger(c.expires_at)||c.created_at<=0||
  c.expires_at<=c.created_at||c.expires_at>c.created_at+300||
  !['reserved','accepted','rejected','unknown'].includes(c.delivery_status)||
  !verificationStates.includes(c.verification_state)||!cleanupStates.includes(c.cleanup_state)||
  typeof c.cancelled!=='boolean')throw unknown();
 if(c.verification_operation_id!==null&&c.verification_operation_id!==undefined)
  uuid(c.verification_operation_id,'operation_id');
 return result;
}
async function helper(env,name,input,...args) {
 let row;try{row=await first(env,helperSql[name],...args);}catch(error){throw dbError(error);}
 return challengeResult(row?.result,input);
}
function email(value) {
 if(typeof value!=='string'||value.length>254||/[\u0000-\u001f\u007f-\u009f]/.test(value)||!/^\S+@[^\s@]+\.[^\s@]+$/.test(value.trim()))throw invalid();
 return value.trim().toLowerCase();
}
function confirmedEmail(user) {
 if(typeof user?.email_confirmed_at!=='string'||!Number.isFinite(Date.parse(user.email_confirmed_at)))throw denied();
 try{return email(user.email);}catch{throw denied();}
}
function context(value) {
 if(typeof value!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(value))throw invalid();
 try {
  const bytes=atob(value.replace(/-/g,'+').replace(/_/g,'/')+'=');
  if(bytes.length!==32||btoa(bytes).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')!==value)throw 0;
 }catch{throw invalid();}
 return value;
}
function parse(body,operation) {
 const allowed=['contract_version','purpose','mode','challenge_id','challenge_context'];
 if(operation==='challenge')allowed.push('email','captcha_token','allow_registration','should_create_user');
 if(operation==='verify')allowed.push('operation_id','code','captcha_token');
 if(operation==='status')allowed.push('operation_id');
 if(operation==='cancel')allowed.push('operation_id','candidate_access_token');
 if(Object.keys(body).some(key=>!allowed.includes(key))||body.contract_version!==1||body.purpose!==purpose||!modes.includes(body.mode))throw invalid();
 const input={...body,challenge_id:uuid(body.challenge_id,'challenge_id'),challenge_context:context(body.challenge_context)};
 if(body.operation_id!==undefined&&body.operation_id!==null)input.operation_id=uuid(body.operation_id,'operation_id');
 else input.operation_id=null;
 if(operation==='verify'&&(!input.operation_id||typeof body.code!=='string'||!/^\d{6,10}$/.test(body.code)))throw invalid();
 if(body.captcha_token!==undefined&&(typeof body.captcha_token!=='string'||!body.captcha_token||body.captcha_token.length>8192))throw invalid();
 if(operation==='challenge') {
  if(body.allow_registration!==undefined&&body.allow_registration!==false||body.should_create_user!==undefined&&body.should_create_user!==false)throw invalid();
  if(body.mode==='current_session'&&Object.hasOwn(body,'email'))throw invalid();
  input.email=body.mode==='portal_bootstrap'?email(body.email):null;
 }
 if(body.candidate_access_token!==undefined&&(typeof body.candidate_access_token!=='string'||!body.candidate_access_token||body.candidate_access_token.length>16384||/\s/.test(body.candidate_access_token)))throw invalid();
 return input;
}
function bearer(request) {
 const value=request.headers.get('Authorization')?.match(/^Bearer (\S+)$/)?.[1];
 if(!value||value.length>16384)throw denied();return value;
}
async function existingMember(env,verified,{cleanup=false}={}) {
 env.DB.setClaims(verified.claims);
 const managed=await first(env,'SELECT private.is_managed_session(?::uuid,?::uuid) AS allowed',verified.user.id,verified.claims.session_id);
 if(managed?.allowed!==true)throw denied();
 if(cleanup) {
  const link=await first(env,'SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?',verified.user.id);
  if(!link||typeof link.user_id!=='string'||!link.user_id)throw denied();return link;
 }
 const member=await first(env,'SELECT l.user_id,u.access_status,u.revision FROM private.auth_principal_links l JOIN users u ON u.id=l.user_id WHERE l.auth_user_id=?',verified.user.id);
 if(!member||member.access_status!=='active'||!Number.isSafeInteger(member.revision)||member.revision<1)throw denied();
 return member;
}
function assertNative(original,c) {
 if(c.mode!=='current_session'||c.expected_auth_user_id!==original.verified.user.id||c.expected_user_id!==original.member.user_id||
  c.initiating_session_id!==original.verified.claims.session_id||c.initiating_user_revision!==original.member.revision||
  c.identity_value!==original.email)throw denied();
}
async function nativeAuthority(request,env,c=null) {
 const verified=await verifyToken(env,bearer(request));
 const member=await existingMember(env,verified),session=await first(env,'SELECT * FROM auth_sessions WHERE id=?',verified.claims.session_id);
 if(!session||session.user_id!==member.user_id||session.surface!=='member'||session.revoked_at!==null||
  !Number.isSafeInteger(session.expires_at)||session.expires_at<=epoch())throw denied();
 const original={verified,member,email:confirmedEmail(verified.user)};
 if(c)assertNative(original,c);return original;
}
async function authority(request,env,input) {
 if(input.mode==='current_session')return nativeAuthority(request,env);
 if(request.headers.has('Authorization'))throw denied();
 env.DB.setClaims({});return null;
}
function install(env,original) {env.DB.setClaims(original?.verified.claims??{});}
function envelope(input) {
 return {contract_version:1,purpose,mode:input.mode,identity_type:'email',channel:'email',
  challenge_id:input.challenge_id,challenge_context:input.challenge_context};
}
function destination(value) {
 const split=value.lastIndexOf('@');return split>0?value[0]+'***@'+value.slice(split+1):'***';
}
function receipt(input,result) {
 const c=result.challenge;
 return {...envelope(input),destination_hint:destination(c.identity_value),retry_after:60,created_at:c.created_at,expires_at:c.expires_at,
  delivery_status:input.mode==='portal_bootstrap'?'not_disclosed':c.delivery_status,
  verification_state:c.verification_state,operation_id:c.verification_operation_id??null,cancelled:c.cancelled,
  candidate_cleanup:c.cleanup_state==='confirmed'?'confirmed':c.verification_state==='not_started'&&c.cleanup_state==='not_started'?'not_required':'unconfirmed'};
}
function unresolved(input,{cleanup='unconfirmed'}={}) {
 return json({...envelope(input),code:'privacy_email_operation_unknown',message:'The verification result is unconfirmed. Check its status before continuing.',
  operation_id:input.operation_id,outcome:'unconfirmed',candidate_cleanup:cleanup},503);
}
function assertLive(c) {
 const at=epoch();if(c.cancelled||c.created_at>at||c.expires_at<at)throw denied();
}
function otpEvent(verified,c) {
 const at=epoch();assertLive(c);let found=null;
 for(const entry of Array.isArray(verified.claims.amr)?verified.claims.amr:[]) {
  if(object(entry)&&entry.method==='otp'&&Number.isSafeInteger(entry.timestamp)&&entry.timestamp>0&&entry.timestamp>=c.created_at&&entry.timestamp<=at&&entry.timestamp>=at-300)
   found=found===null?entry.timestamp:Math.min(found,entry.timestamp);
 }
 if(found===null)throw denied();return found;
}
function tokens(data,verified) {
 if(!object(data)||typeof data.access_token!=='string'||!data.access_token||data.access_token.length>16384||/\s/.test(data.access_token)||
  typeof data.refresh_token!=='string'||!data.refresh_token||data.refresh_token.length>4096||/\s/.test(data.refresh_token)||
  verified.token!==data.access_token)throw unknown();
 return {access_token:data.access_token,refresh_token:data.refresh_token,token_type:'bearer',expires_at:verified.claims.exp,expires_in:Math.max(1,verified.claims.exp-epoch())};
}
async function candidate(env,verified,c,original,{cleanup=false}={}) {
 const member=await existingMember(env,verified,{cleanup});
 if(!cleanup&&confirmedEmail(verified.user)!==c.identity_value)throw denied();
 if(c.mode==='current_session') {
  if(original)assertNative(original,c);
  if(verified.user.id!==c.expected_auth_user_id||member.user_id!==c.expected_user_id||verified.claims.session_id===c.initiating_session_id)throw denied();
 }
 // Cleanup uses immutable recorded proof even after local cancellation/expiry.
 const event=cleanup?c.verified_amr_at:otpEvent(verified,c);
 if(cleanup) {
  if(c.verified_session_id!==verified.claims.session_id||!Number.isSafeInteger(event)||event<=0||
   !Array.isArray(verified.claims.amr)||!verified.claims.amr.some(entry=>object(entry)&&entry.method==='otp'&&entry.timestamp===event))throw denied();
 } else if(c.mode==='current_session'&&member.revision!==c.initiating_user_revision)throw denied();
 return {member,event};
}
async function markVerify(env,input,original,outcome) {
 install(env,original);
 try{return await helper(env,'verify_finish',input,input.challenge_id,input.hash,input.operation_id,outcome);}
 catch{throw unknown();}
}
async function challenge(request,env,input,original) {
 install(env,original);
 const prepared=await helper(env,'prepare',input,input.challenge_id,input.mode,input.email,input.hash);
 if(original)assertNative(original,prepared.challenge);
 if(prepared.created!==true)return json(receipt(input,prepared),202);
 const claim=id(),claimed=await helper(env,'send_claim',input,input.challenge_id,input.hash,claim);
 if(claimed.claimed!==true)return json(receipt(input,claimed),202);
 assertLive(claimed.challenge);
 let outcome='accepted';
 try{await authRequest(env,'/otp',{body:{email:claimed.challenge.identity_value,create_user:false,gotrue_meta_security:{captcha_token:input.captcha_token}}});}
 catch(error){outcome=error instanceof ApiError&&[400,401,403,422,429].includes(error.status)?'rejected':'unknown';}
 let finished;
 try{finished=await helper(env,'send_finish',input,input.challenge_id,input.hash,claim,outcome);}catch{throw unknown();}
 // Eligibility and a broken mailer must have the same anonymous receipt.
 // Keep the actual outcome server-side; it must not become an existence oracle.
 if(outcome==='unknown'&&input.mode!=='portal_bootstrap')return unresolved(input);
 return json(receipt(input,finished),202);
}
function proof(result,input,verified,member,event) {
 const p=result.proof,c=result.challenge;
 if(!object(p)||p.purpose!==purpose||p.challenge_id!==input.challenge_id||p.user_id!==member.user_id||p.auth_user_id!==verified.user.id||
  p.session_id!==verified.claims.session_id||p.initiating_session_id!==(input.mode==='current_session'?c.initiating_session_id:null)||
  p.method!=='otp'||p.authenticated_at!==event||p.expires_at!==c.expires_at||c.verified_session_id!==verified.claims.session_id||c.verified_amr_at!==event||
  c.verification_state!=='verified'||c.verification_operation_id!==input.operation_id||c.cancelled)throw unknown();
 return {purpose,challenge_id:p.challenge_id,user_id:p.user_id,auth_user_id:p.auth_user_id,initiating_session_id:p.initiating_session_id,
  session_id:p.session_id,method:'otp',authenticated_at:p.authenticated_at,expires_at:p.expires_at};
}
async function verify(request,env,input,original) {
 install(env,original);
 const claimed=await helper(env,'verify_claim',input,input.challenge_id,input.hash,input.operation_id);
 if(claimed.claimed!==true)return json(receipt(input,claimed),claimed.challenge.verification_state==='verifying'||claimed.challenge.verification_state==='unconfirmed'?503:200);
 const c=claimed.challenge;if(original)assertNative(original,c);assertLive(c);
 let data;
 try{data=await authRequest(env,'/verify',{body:{email:c.identity_value,token:input.code,type:'email',gotrue_meta_security:{captcha_token:input.captcha_token}}});}
 catch(error) {
  const rejected=error instanceof ApiError&&[400,401,403,422,429].includes(error.status);
  const result=await markVerify(env,input,original,rejected?'rejected':'unconfirmed');
  if(!rejected)return unresolved(input);
  return json({...receipt(input,result),code:'privacy_email_code_rejected',message:'The code could not be verified.'},error.status===429?429:401);
 }
 let safeCandidate=false,verified;
 try {
  if(!object(data)||typeof data.access_token!=='string')throw unknown();
  verified=await verifyToken(env,data.access_token);
  const session=tokens(data,verified),checked=await candidate(env,verified,c,original);
  safeCandidate=true;
  // Revalidate the captured initiating bearer after provider I/O, before projection.
  if(original)original=await nativeAuthority(request,env,c);
  const actor=await projectSession(env,verified,{existingLinkOnly:true,expectedAuthUserId:verified.user.id,expectedUserId:checked.member.user_id});
  const at=epoch();if(actor.surface!=='member'||!Number.isSafeInteger(actor.authAt)||actor.authAt<at-300||actor.authAt>at||actor.authAt!==checked.event)throw denied();
  if(original)original=await nativeAuthority(request,env,c);
  env.DB.setClaims(verified.claims);
  const consumed=await helper(env,'consume',input,input.challenge_id,input.hash,input.operation_id);
  const purposeProof=proof(consumed,input,verified,checked.member,checked.event);
  return json({...session,user:actor.user,...envelope(input),operation_id:input.operation_id,
   auth_event:{method:'otp',timestamp:checked.event},purpose_proof:purposeProof});
 }catch {
  // The token is still server-local and unadopted. Never guess or use another
  // token when identity/event validation did not establish this exact candidate.
  if(safeCandidate)await authRequest(env,'/logout?scope=local',{token:verified.token}).catch(()=>{});
  await markVerify(env,input,original,'unconfirmed').catch(()=>{});
  return unresolved(input);
 }
}
async function cleanup(request,env,input) {
 // Candidate cleanup grants no sign-in access. Its exact recorded proof remains
 // usable for irreversible retirement after the initiating session is revoked.
 const verified=await verifyToken(env,input.candidate_access_token);
 env.DB.setClaims(verified.claims);
 if(!input.operation_id)throw denied();
 const claim=id();
 const claimed=await helper(env,'cleanup_claim',input,input.challenge_id,input.hash,input.operation_id,claim);
 if(claimed.claimed!==true)return json(receipt(input,claimed),claimed.challenge.cleanup_state==='confirmed'?200:503);
 try {
  if(claimed.challenge.verification_operation_id!==input.operation_id)throw denied();
  await candidate(env,verified,claimed.challenge,null,{cleanup:true});
 }catch {
  env.DB.setClaims(verified.claims);
  await helper(env,'cleanup_finish',input,input.challenge_id,input.hash,input.operation_id,claim,'unconfirmed').catch(()=>{});
  return unresolved(input);
 }
 let outcome='confirmed';
 try{await authRequest(env,'/logout?scope=local',{token:input.candidate_access_token});}catch{outcome='unconfirmed';}
 env.DB.setClaims(verified.claims);
 let finished;
 try{finished=await helper(env,'cleanup_finish',input,input.challenge_id,input.hash,input.operation_id,claim,outcome);}catch{throw unknown();}
 if(outcome!=='confirmed'||finished.challenge.cleanup_state!=='confirmed')return unresolved(input);
 return json(receipt(input,finished));
}
/** Four POST-only, no-cookie routes. index.js must dispatch before requireSession. */
export async function handlePrivacyEmailAuth(request,env) {
 const path=new URL(request.url).pathname;
 if(!path.startsWith('/v1/privacy/email/'))return null;
 const operation=path.slice('/v1/privacy/email/'.length);
 if(!['challenge','verify','status','cancel'].includes(operation))throw new ApiError(404,'not_found','This verification route is unavailable.');
 if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','Use POST.');
 if(request.headers.get('Sec-Fetch-Site')==='cross-site')throw denied();
 const input=parse(await readJson(request,32768),operation);input.hash=await digest(input.challenge_context);
 try {
  if(operation==='cancel'&&input.candidate_access_token)return await cleanup(request,env,input);
  const original=await authority(request,env,input);install(env,original);
  if(operation==='challenge')return await challenge(request,env,input,original);
  if(operation==='verify')return await verify(request,env,input,original);
  const result=await helper(env,operation,input,input.challenge_id,input.hash,...(operation==='cancel'?[input.operation_id]:[]));
  if(original)assertNative(original,result.challenge);
  return json(receipt(input,result));
 }catch(error) {
  if(error instanceof ApiError&&error.code==='privacy_email_operation_unknown')return unresolved(input);
  throw error;
 }
}
