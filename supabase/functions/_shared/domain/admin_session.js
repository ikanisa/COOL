import {ApiError,json,first,id,digest} from './core.js';
import {loadAdminEmailAccount,isAdminEmailDenialError} from './admin_email_auth.js';
import {bindAdminEmailActor} from './admin_email_policy.js';
import {verifyToken,claimsOf} from '../auth-http.js';
import {projectSession} from './auth.js';
import {adminAccountSession as legacySession,adminPublicUser,adminCookie} from './admin_accounts_legacy.js';
import {validateAdminOrigin,adminCookieToken} from '../admin-security.js';
import {lockAdminSessionMutation} from '../postgres-mutation-lock.js';
import {decryptAdminTokens,encryptAdminTokens,newAdminCookieToken,finishAdminProviderLogout,ADMIN_COOKIE_SECONDS} from './admin_bff_tokens.js';
import {failAdminAccount as fail} from './admin_account_support/errors.js';
import {refreshAdminSession} from './admin_session_refresh.js';

const unix=()=>Math.floor(Date.now()/1000);
export const adminMfaEnabled=env=>env.COLLECT_ADMIN_TOTP_ENABLED==='true';

async function projectAdminExchange(env, verified) {
 env.ADMIN_AUTH_EXCHANGE=true;
 try { await projectSession(env, verified, {surface:'admin'}); }
 finally { env.ADMIN_AUTH_EXCHANGE=false; }
}

export async function logoutAdminSession(request,env){
 const origin=validateAdminOrigin(request,env),token=adminCookieToken(request);
 if(!token)return json({ok:true},200,{'Set-Cookie':adminCookie()});
 if(request.headers.get('X-Collect-CSRF')!==await digest('collect-admin-csrf:'+token))fail('csrf_rejected');
 const hash=await digest(token);
 // Commit the exact browser session's local revocation first. Provider outages
 // must not leave a restorable cookie behind after a confirmed local sign-out.
 const retained=await env.DB.transaction(async sql=>{
  await env.DB.context(sql);
  await lockAdminSessionMutation(sql,hash);
  const sessions=await sql.unsafe('SELECT token_hash FROM app.admin_sessions WHERE token_hash=$1 AND origin=$2 FOR UPDATE',[hash,origin]);
  if(sessions.length!==1)return null;
  const rows=await sql.unsafe('SELECT auth_user_id,auth_session_id,token_ciphertext FROM private.bff_sessions WHERE token_hash=$1',[hash]);
  await sql.unsafe('DELETE FROM app.admin_sessions WHERE token_hash=$1 AND origin=$2',[hash,origin]);
  return rows[0]??null;
 });
 const providerLogout=await finishAdminProviderLogout(env,retained);
 return json({ok:true,providerLogout},200,{'Set-Cookie':adminCookie()});
}
export async function adminAccountSession(request,env,required=true) {
 const origin=validateAdminOrigin(request,env);const token=adminCookieToken(request);if(!token){if(required)fail('unauthenticated',401);return null;}
 // An expired projection can only be renewed by the original cookie and the
 // real provider session. A revoked account/session is rejected before any
 // provider refresh is attempted.
 const hash=await digest(token);let row=await first(env,`SELECT b.*,s.expires_at,s.user_id AS admin_id,s.public_id,s.issued_assurance_level,a.email AS admin_email FROM private.bff_sessions b
  JOIN admin_sessions s ON s.token_hash=b.token_hash
  JOIN admin_users a ON a.id=s.user_id AND a.status='active' AND a.auth_version=s.auth_version
  JOIN admin_principal_links l ON l.admin_user_id=a.id JOIN users u ON u.id=l.user_id AND u.access_status='active'
  JOIN auth_sessions p ON p.id=s.auth_session_id AND p.user_id=u.id AND p.surface='admin' AND p.revoked_at IS NULL
  WHERE b.token_hash=? AND s.origin=?`,hash,origin);
 if(!row){if(required)fail('unauthenticated',401);return null;}
 if(row.mfa_intent_hash){
  if(row.mfa_pending_state!=='restoring')throw new ApiError(409,'mfa_recovery_pending','The authenticator check is still finishing. Recheck its result.');
  const original=await decryptAdminTokens(env,row),proof=await verifyToken(env,original.access_token);
  if(proof.user.id!==row.auth_user_id||proof.claims.session_id!==row.auth_session_id||![1,2].includes(row.issued_assurance_level)||
   proof.claims.aal!==`aal${row.issued_assurance_level}`||proof.user.email?.toLowerCase()!==row.admin_email)fail('session_changed',401);
  env.DB.setClaims(proof.claims);
  const ack=await env.DB.batch([env.DB.prepare('SELECT private.collect_admin_mfa_intent_ack_restore_v1(?,?,?,?) AS result').bind(row.admin_id,hash,origin,row.public_id)]);
  if(ack?.[0]?.results?.[0]?.result!==true)throw new ApiError(409,'mfa_recovery_pending','The authenticator result is still being recovered.');
  row={...row,mfa_intent_hash:null,mfa_pending_state:null};
 }
 let tokens=await decryptAdminTokens(env,row);
 if(claimsOf(tokens.access_token).exp<unix()+30)tokens=await refreshAdminSession(env,row,tokens,hash);

 const verified=await verifyToken(env,tokens.access_token);
 if(verified.user.id!==row.auth_user_id||verified.claims.session_id!==row.auth_session_id||
  !verified.user.email_confirmed_at||typeof verified.user.email!=='string'||
  verified.user.email.toLowerCase()!==row.admin_email)fail('session_changed',401);
 if(verified.claims.aal==='aal2'&&row.issued_assurance_level!==2)throw new ApiError(409,'mfa_recovery_required','Recheck the authenticator result before continuing.');
 env.DB.setClaims(verified.claims);
 if(Number(row.expires_at)<=unix()+300){
  let result;try{result=(await first(env,'SELECT private.collect_admin_renew_session(?,?) AS result',token,origin))?.result;}
  catch(error){if(error?.code==='42501')fail('unauthenticated',401);throw error;}
  if(!Number.isSafeInteger(result?.expiresAt)||result.expiresAt<=unix())fail('session_changed',401);
 }
 await projectAdminExchange(env,verified);
 const account=await legacySession(request,env,required);if(!account)return null;
 const csrf=await digest('collect-admin-csrf:'+token);
 if(!['GET','HEAD','OPTIONS'].includes(request.method)&&request.headers.get('X-Collect-CSRF')!==csrf)fail('csrf_rejected');
 account.supabaseTokens=tokens;account.auth_user_id=row.auth_user_id;account.csrfToken=csrf;
 if(adminMfaEnabled(env)){const current=await first(env,'SELECT version FROM private.bff_sessions WHERE token_hash=? AND auth_user_id=?::uuid AND auth_session_id=?::uuid',hash,row.auth_user_id,row.auth_session_id);if(!Number.isSafeInteger(current?.version))fail('session_changed',401);account.bff_version=current.version;}
 await loadAdminEmailAccount(env,account);env.ADMIN_ACCOUNT=account;return account;
}
export async function adminInternalRequest(request,env,account,path,method=request.method,value=null) {
 const headers=new Headers(request.headers);headers.delete('Cookie');headers.set('Authorization','Bearer '+account.supabaseTokens.access_token);headers.set('Content-Type','application/json');headers.delete('Content-Length');
 return new Request(new URL(path,request.url),{method,headers,...(['GET','HEAD'].includes(method)?{}:{body:JSON.stringify(value??{})})});
}
export async function adminCanonicalActor(request,env,account,permission=null) {
 if(permission&&!account.permissions.includes(permission))fail('permission_required');
 const verified=await verifyToken(env,account.supabaseTokens.access_token);const actor=await projectSession(env,verified,{surface:'admin'});actor.permissions=new Set([...actor.permissions].filter(v=>account.permissions.includes(v)));return bindAdminEmailActor(actor,account);
}
export async function issueAdminSession(request,env,data,{emailChallengeId=null}={}) {
 const verified=await verifyToken(env,data.access_token),email=verified.user.email_confirmed_at?verified.user.email?.toLowerCase():null,origin=validateAdminOrigin(request,env);if(!origin)fail('origin_rejected');
 const account=await first(env,"SELECT a.*,l.user_id AS principal_id FROM admin_users a JOIN admin_principal_links l ON l.admin_user_id=a.id WHERE a.email=? AND a.status IN('active','invited')",email);if(!account)fail('admin_access_not_approved');
 env.DB.setClaims(verified.claims);if(!(await first(env,'SELECT private.is_managed_session(?::uuid,?::uuid) AS allowed',verified.user.id,verified.claims.session_id))?.allowed)fail('session_changed',401);
 // Activation revokes prior Admin projections. It must precede the new one.
 await env.DB.batch([env.DB.prepare("UPDATE admin_users SET status='active',password_hash='supabase-managed',accepted_at=COALESCE(accepted_at,?),updated_at=? WHERE id=? AND status IN('active','invited')").bind(unix(),unix(),account.id)]);
 await projectAdminExchange(env,verified);
 const sid=verified.claims.session_id,projected=await first(env,'SELECT * FROM auth_sessions WHERE id=? AND user_id=? AND revoked_at IS NULL',sid,account.principal_id);if(!projected||projected.surface!=='admin')fail('session_changed',401);
 const token=newAdminCookieToken(),hash=await digest(token),publicId=id(),at=projected.auth_at,expiry=projected.expires_at,row={auth_user_id:verified.user.id,auth_session_id:sid},cipher=await encryptAdminTokens(env,row,data);
 env.DB.setClaims(verified.claims);
 try{await env.DB.batch([
  env.DB.prepare('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at) SELECT ?,?,id,auth_version,?,?,?,? FROM admin_users WHERE id=? AND status=\'active\'').bind(hash,publicId,sid,origin,at,expiry,account.id),
  env.DB.prepare('INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext) VALUES(?,?,?,?)').bind(hash,verified.user.id,sid,cipher),
  env.DB.prepare("INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) VALUES(?,?,?,'supabase_signed_in',?)").bind(id(),account.id,account.id,unix()),
  ...(emailChallengeId===null?[]:[env.DB.prepare('SELECT private.admin_email_record_initial(?,?,?,?,?) AS result').bind(account.id,hash,origin,publicId,emailChallengeId)])
 ]);}catch(error){
  const retained=await first(env,emailChallengeId===null
   ?'SELECT b.auth_user_id,b.auth_session_id FROM private.bff_sessions b JOIN admin_sessions s ON s.token_hash=b.token_hash WHERE b.token_hash=? AND s.public_id=? AND s.origin=?'
   :`SELECT b.auth_user_id,b.auth_session_id,EXISTS(SELECT 1 FROM private.admin_sensitive_email_proofs p
      WHERE p.challenge_id=? AND p.admin_id=s.user_id AND p.auth_user_id=b.auth_user_id
       AND p.original_session_id=b.auth_session_id AND p.verified_session_id=b.auth_session_id
       AND p.cookie_hash=b.token_hash AND p.public_session_id=s.public_id
       AND p.auth_version=s.auth_version AND p.origin=s.origin) AS initial_proof
     FROM private.bff_sessions b JOIN admin_sessions s ON s.token_hash=b.token_hash
     WHERE b.token_hash=? AND s.public_id=? AND s.origin=?`,
   ...(emailChallengeId===null?[hash,publicId,origin]:[emailChallengeId,hash,publicId,origin])).catch(()=>null);
  const exactCommit=retained?.auth_user_id===verified.user.id&&retained?.auth_session_id===sid&&
   (emailChallengeId===null||retained?.initial_proof===true);
  if(!exactCommit){
   if(emailChallengeId!==null){
    if(isAdminEmailDenialError(error))throw new ApiError(403,'admin_email_denied','This email verification is unavailable.');
    throw new ApiError(503,'admin_email_operation_unknown','The email verification result is unconfirmed. Check the current verification before continuing.');
   }
   throw error;
  }
 }
 const authenticated=await adminAccountSession(new Request(request.url,{headers:{Cookie:`__Host-collect_admin=${token}`,Origin:origin}}),env);
 return json({user:adminPublicUser(authenticated),expiresAt:new Date(authenticated.expires_at*1000).toISOString(),csrfToken:authenticated.csrfToken},200,{'Set-Cookie':adminCookie(token,ADMIN_COOKIE_SECONDS)});
}
