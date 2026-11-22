import {ApiError,digest,id} from './core.js';
import {authRequest,verifyToken} from '../auth-http.js';
import {decrypt} from './encryption.js';
import {accountDatabase,adminCookie} from './admin_accounts_legacy.js';
import {validateAdminOrigin,adminCookieToken} from '../admin-security.js';
import {lockCollectMutation} from '../postgres-mutation-lock.js';
import {adminMfaDenied as denied,adminMfaPending as pending} from './admin_account_support/errors.js';
import {adminTokenCustody,decryptAdminTokens,adminMfaIntentHash as intentHash,finishAdminProviderLogout,
 adminMfaOldCookieContext as oldCookieContext,adminMfaCandidateContext as candidateContext,ADMIN_COOKIE_SECONDS} from './admin_bff_tokens.js';
import {adminMfaPorts} from './admin_mfa_stage.js';
export {adminMfaPorts};

const unix=()=>Math.floor(Date.now()/1000);
const validUuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

function validIntent(body) {
 return body&&typeof body==='object'&&!Array.isArray(body)&&
   Object.keys(body).sort().join(',')==='challenge_id,factor_id,verification_id'&&
   validUuid(body.factor_id)&&validUuid(body.challenge_id)&&/^[a-f0-9]{64}$/.test(body.verification_id??'');
}

async function revokeMfaSession(env,origin,query,args) {
 return env.DB.transaction(async sql => {
  await env.DB.context(sql);
  await lockCollectMutation(sql);
  const found=await sql.unsafe(query,args);
  if(found.length!==1)return null;
  await sql.unsafe('DELETE FROM app.admin_sessions WHERE token_hash=$1 AND origin=$2',[found[0].token_hash,origin]);
  return found[0];
 });
}

// Used only after a candidate hash and its original live session are proven.
// The decrypted value must be hashed and compared to the original row before
// being returned as a fallback cookie; the caller must not log either value.
export async function decryptAdminMfaOldCookie(env,account,ciphertext){
 const bytes=await decrypt(adminTokenCustody(env),ciphertext,oldCookieContext(account));
 const token=new TextDecoder().decode(bytes);
 if(!/^[a-f0-9]{64}$/.test(token)||await digest(token)!==account.token_hash)throw pending();
 return token;
}

// Called before ordinary session resolution, never as a public token-exchange
// route. Possession of the provisional HttpOnly cookie selects the candidate;
// the current provider session and database authority are then revalidated.
export async function resolveAdminMfaCandidate(env,request,{enabled=false,verify=verifyToken}={}){
 const origin=validateAdminOrigin(request,env),token=adminCookieToken(request);if(!token)return null;
 const candidateHash=await digest(token);
 const query=`SELECT b.*,s.user_id AS id,s.public_id,s.origin,s.auth_version,s.issued_assurance_level,
  s.issued_mfa_at,s.issued_mfa_factor_id,s.expires_at,a.role,a.email,l.user_id AS principal_id
  FROM private.bff_sessions b JOIN app.admin_sessions s ON s.token_hash=b.token_hash
  JOIN app.admin_users a ON a.id=s.user_id JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  WHERE b.mfa_pending_hash=? AND s.origin=?`;
 const account=await env.DB.prepare(query).bind(candidateHash,origin).first();if(!account)return null;
 let tokens;
 try{tokens=await decryptAdminTokens(env,account);}
 catch{throw pending();}
 const verified=await verify(env,tokens.access_token);
 if(verified.user.id!==account.auth_user_id||verified.claims.session_id!==account.auth_session_id||
    !verified.user.email_confirmed_at||typeof verified.user.email!=='string'||verified.user.email.toLowerCase()!==account.email)throw denied();
 env.DB.setClaims(verified.claims);
 const committed=async()=>{
  const row=await env.DB.prepare(`SELECT b.*,s.user_id AS id,s.public_id,s.origin,s.auth_version,s.issued_assurance_level,
   s.issued_mfa_at,s.issued_mfa_factor_id,s.expires_at,a.role,a.email,l.user_id AS principal_id
   FROM private.bff_sessions b JOIN app.admin_sessions s ON s.token_hash=b.token_hash
   JOIN app.admin_users a ON a.id=s.user_id JOIN app.admin_principal_links l ON l.admin_user_id=a.id
   WHERE b.token_hash=? AND s.origin=?`).bind(candidateHash,origin).first();
  if(!row||row.id!==account.id||row.public_id!==account.public_id||row.auth_user_id!==account.auth_user_id||
     row.auth_session_id!==account.auth_session_id||row.issued_assurance_level!==2||
     row.issued_mfa_factor_id!==account.mfa_pending_factor||row.issued_mfa_at!==account.mfa_pending_at||
     row.mfa_pending_hash!==null)return false;
  await accountDatabase(env,row).DB.batch([env.DB.prepare('SELECT 1 AS ok')]);
  return true;
 };
 if(enabled===true&&account.mfa_pending_state==='staged'){
  try{
   const result=await env.DB.batch([env.DB.prepare('SELECT private.collect_admin_mfa_intent_complete_v1(?,?) AS result').bind(candidateHash,origin)]);
   const value=result?.[0]?.results?.[0]?.result;
   if(value?.version!==1||value.state!=='complete'||value.public_session_id!==account.public_id)throw pending();
   return {state:'complete'};
  }catch{
   try{if(await committed())return {state:'complete'};}catch{/* Try the guarded fallback below. */}
  }
 }
 try{
  const result=await env.DB.batch([env.DB.prepare('SELECT private.collect_admin_mfa_intent_restore_v1(?,?) AS result').bind(candidateHash,origin)]);
  const value=result?.[0]?.results?.[0]?.result;
  if(value?.version!==1||value.state!=='restore'||value.original_hash!==account.token_hash||
     value.auth_user_id!==account.auth_user_id||value.auth_session_id!==account.auth_session_id||
     value.public_session_id!==account.public_id)throw pending();
  const original=await decryptAdminMfaOldCookie(env,account,value.old_cookie_ciphertext);
  return {state:'restore',token:original,cookie:adminCookie(original,ADMIN_COOKIE_SECONDS)};
 }catch{
  try{if(await committed())return {state:'complete'};}catch{/* A failed readback never grants authority. */}
  throw pending();
 }
}

// The caller must present the same per-tab intent that initiated this exact
// challenge. The stored provider tokens remain encrypted and never leave BFF.
export async function recoverAdminMfaIntent(env,request,body,{verify=verifyToken,requestAuth=authRequest}={}){
 const origin=validateAdminOrigin(request,env),token=adminCookieToken(request);
 if(!token||!validIntent(body))throw denied();
 // After a tab reload the normal CSRF value is not yet available. The exact
 // unguessable tab intent is the recovery-only anti-CSRF capability; Origin,
 // JSON/custom-header checks and the original HttpOnly cookie remain required.
 const csrf=request.headers.get('X-Collect-CSRF');
 if(csrf!==null&&csrf!==await digest('collect-admin-csrf:'+token))throw denied();
 const hash=await digest(token),intent=await intentHash(body.verification_id);
 const account=await env.DB.prepare(`SELECT b.*,s.user_id AS id,s.public_id,s.origin,s.auth_version,s.issued_assurance_level,
  s.issued_mfa_at,s.issued_mfa_factor_id,s.expires_at,a.role,a.email,l.user_id AS principal_id
  FROM private.bff_sessions b JOIN app.admin_sessions s ON s.token_hash=b.token_hash
  JOIN app.admin_users a ON a.id=s.user_id JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  WHERE b.token_hash=? AND s.origin=? AND b.mfa_intent_hash=? AND b.mfa_intent_factor=?::uuid AND b.mfa_intent_challenge=?::uuid`)
  .bind(hash,origin,intent,body.factor_id,body.challenge_id).first();
 if(!account||![1,2].includes(account.issued_assurance_level)||typeof account.mfa_intent_old_tokens!=='string')throw denied();
 let old;try{old=await decryptAdminTokens(env,account,account.mfa_intent_old_tokens);}catch{throw pending();}
 let current=old;if(account.mfa_pending_state==='staged'){
  try{current=await decryptAdminTokens(env,account);}catch{throw pending();}
 }
 let prior;
 try{prior=await verify(env,current.access_token);}
 catch(error){
  if([401,403].includes(error?.status))throw new ApiError(409,'mfa_recovery_unavailable','This authenticator result cannot be recovered automatically. Sign in again.');
  throw pending();
 }
 if(prior.user.id!==account.auth_user_id||prior.claims.session_id!==account.auth_session_id||
  (account.mfa_pending_state==='staged'?prior.claims.aal!=='aal2':prior.claims.aal!==`aal${account.issued_assurance_level}`)||
  !prior.user.email_confirmed_at||typeof prior.user.email!=='string'||prior.user.email.toLowerCase()!==account.email)throw denied();
 env.DB.setClaims(prior.claims);
 const lease=id(),at=unix();let plan;
 try{const result=await env.DB.batch([env.DB.prepare('SELECT private.collect_admin_mfa_intent_recover_v1(?,?,?,?,?::uuid,?::uuid,?,?,?) AS result')
  .bind(account.id,hash,origin,account.public_id,body.factor_id,body.challenge_id,intent,lease,at+25)]);plan=result?.[0]?.results?.[0]?.result;}
 catch(error){if(error?.code==='55000')throw new ApiError(409,'mfa_recovery_pending','The authenticator check is still finishing. Try again shortly.');throw pending();}
 if(plan?.state==='staged'){
  let candidate;try{candidate=new TextDecoder().decode(await decrypt(adminTokenCustody(env),plan.candidate_ciphertext,candidateContext(account)));}catch{throw pending();}
  if(!/^[a-f0-9]{64}$/.test(candidate)||await digest(candidate)!==plan.candidate_hash)throw pending();
  return {ok:true,cookie:adminCookie(candidate,ADMIN_COOKIE_SECONDS)};
 }
 if(plan?.state!=='claimed'||!Number.isSafeInteger(plan.version)||plan.old_tokens!==account.mfa_intent_old_tokens)throw pending();
 if(typeof old.refresh_token!=='string'||!/^[a-z0-9]{12}$/.test(old.refresh_token))
  throw new ApiError(409,'mfa_recovery_unavailable','This authenticator result cannot be recovered automatically. Recheck your session.');
 let tokens,verified;
 try{tokens=await requestAuth(env,'/token?grant_type=refresh_token',{body:{refresh_token:old.refresh_token}});}
 catch(error){
  if([400,401,403,422].includes(error?.status))throw new ApiError(409,'mfa_recovery_unavailable','This authenticator result cannot be recovered automatically. Sign in again.');
  throw pending();
 }
 try{verified=await verify(env,tokens.access_token);}catch{throw pending();}
 if(verified.user.id!==account.auth_user_id||verified.claims.session_id!==account.auth_session_id||verified.claims.aal!=='aal2'||
  !Array.isArray(verified.user.factors)||!verified.user.factors.some(f=>f.id===body.factor_id&&f.status==='verified'&&f.factor_type==='totp'))throw pending();
 return adminMfaPorts(env,account,request).stage({verified,tokens,factorId:body.factor_id,challengeId:body.challenge_id,
  verificationId:body.verification_id,lease:{id:lease,version:plan.version}});
}

// A reloaded initiating tab may not yet have the cookie-bound CSRF value.
// It can still explicitly sign out using the same exact recovery capability;
// the retained local session is revoked before any provider request.
export async function logoutAdminMfaIntent(env,request,body){
 const origin=validateAdminOrigin(request,env),token=adminCookieToken(request);
 if(!token||request.headers.has('X-Collect-CSRF')||!validIntent(body))throw denied();
 const hash=await digest(token),intent=await intentHash(body.verification_id);
 const retained=await revokeMfaSession(env,origin,`SELECT b.token_hash,b.auth_user_id,b.auth_session_id,b.token_ciphertext FROM private.bff_sessions b
   JOIN app.admin_sessions s ON s.token_hash=b.token_hash WHERE s.origin=$1 AND b.mfa_intent_hash=$2
    AND b.mfa_intent_factor=$3::uuid AND b.mfa_intent_challenge=$4::uuid
    AND (b.token_hash=$5 OR (b.mfa_pending_hash=$5 AND b.mfa_pending_state='staged')) FOR UPDATE OF b,s`,
   [origin,intent,body.factor_id,body.challenge_id,hash]);
 if(!retained)throw new ApiError(409,'mfa_recovery_unavailable','The pending session could not be signed out. Recheck your session.');
 const providerLogout=await finishAdminProviderLogout(env,retained);
 return {state:'revoked',providerLogout,cookie:adminCookie()};
}

// A user can press Sign out before the provisional cookie has been resolved.
// Revoke the exact local session first, including when completion won the
// race. The old CSRF proof is still held by the browser until refresh.
export async function logoutAdminMfaCandidate(env,request){
 const origin=validateAdminOrigin(request,env),token=adminCookieToken(request);if(!token)return null;
 const candidateHash=await digest(token);
 const account=await env.DB.prepare(`SELECT b.*,s.user_id AS id,s.public_id,s.origin,s.auth_version
  FROM private.bff_sessions b JOIN app.admin_sessions s ON s.token_hash=b.token_hash
  WHERE b.mfa_pending_hash=? AND s.origin=?`).bind(candidateHash,origin).first();
 if(!account)return null;
 const original=await decryptAdminMfaOldCookie(env,account,account.mfa_pending_old_cookie_ciphertext);
 const supplied=request.headers.get('X-Collect-CSRF');
 if(supplied!==await digest('collect-admin-csrf:'+original)&&supplied!==await digest('collect-admin-csrf:'+token))throw denied();
 const retained=await revokeMfaSession(env,origin,`SELECT b.token_hash,b.auth_user_id,b.auth_session_id,b.token_ciphertext FROM private.bff_sessions b
   JOIN app.admin_sessions s ON s.token_hash=b.token_hash WHERE s.origin=$1 AND s.public_id=$2
    AND b.auth_user_id=$3::uuid AND b.auth_session_id=$4::uuid
    AND ((b.token_hash=$5 AND b.mfa_pending_hash=$6) OR (b.token_hash=$6 AND b.mfa_pending_hash IS NULL))
   FOR UPDATE OF b,s`,[origin,account.public_id,account.auth_user_id,account.auth_session_id,account.token_hash,candidateHash]);
 if(!retained)return null;
 const providerLogout=await finishAdminProviderLogout(env,retained);
 return {state:'revoked',providerLogout,cookie:adminCookie()};
}
