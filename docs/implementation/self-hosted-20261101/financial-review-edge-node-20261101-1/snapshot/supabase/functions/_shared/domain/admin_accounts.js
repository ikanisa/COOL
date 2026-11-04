import {ApiError,json,readJson,first,rows,id,digest,uuid,now} from './core.js';
import {loadAdminEmailAccount,handleAdminEmail,isAdminEmailDenialError} from './admin_email_auth.js';
import {changeAdminPassword} from './admin_password.js';
import {bindAdminEmailActor,requireFreshAdminEmail,hasFreshAdminEmail} from './admin_email_policy.js';
import {authRequest,verifyToken,claimsOf} from '../auth-http.js';
import {projectSession,startOtp,verifyOtp,responseSession,handleAuth} from './auth.js';
import {encrypt,decrypt} from './encryption.js';
import {adminAccountSession as legacySession,adminPublicUser,accountGuard,accountDatabase,adminCookie} from './admin_accounts_legacy.js';
import {handleAdminGoogle} from './admin-google.js';
import {validateAdminOrigin} from '../admin-security.js';
import {handleAdminInvitation} from './admin_invitation.js';
import {handleAdminInvitationV2} from './admin_invitation_v2.js';
export {adminPublicUser,accountGuard,accountDatabase,adminCookie,validateAdminOrigin};
const unix=()=>Math.floor(Date.now()/1000);
const fail=(code,status=403)=>{throw new ApiError(status,code,code==='admin_access_not_approved'?'This email does not have Admin access. Contact the super admin to be added.':'This Admin action is unavailable.');};
const random=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),v=>v.toString(16).padStart(2,'0')).join('');
const custodyEnv=env=>({...env,DATA_KEY_ID:env.SESSION_KEY_ID??'bff-v1',DATA_ENCRYPTION_KEY:env.SESSION_ENCRYPTION_KEY,DATA_DECRYPTION_KEYS_JSON:env.SESSION_DECRYPTION_KEYS_JSON});
const context=row=>`bff:${row.auth_session_id}:${row.auth_user_id}`;
async function decode(env,row){return JSON.parse(new TextDecoder().decode(await decrypt(custodyEnv(env),row.token_ciphertext,context(row))));}
async function encode(env,row,tokens){return encrypt(custodyEnv(env),new TextEncoder().encode(JSON.stringify({access_token:tokens.access_token,refresh_token:tokens.refresh_token})),context(row));}
const cookieToken=request=>(request.headers.get('Cookie')??'').split(';').map(x=>x.trim()).find(x=>/^__Host-collect_admin=[a-f0-9]{64}$/.test(x))?.split('=')[1];
export async function adminAccountSession(request,env,required=true) {
 validateAdminOrigin(request,env);const token=cookieToken(request);if(!token){if(required)fail('unauthenticated',401);return null;}
 const hash=await digest(token);let row=await first(env,`SELECT b.*,s.expires_at FROM private.bff_sessions b JOIN admin_sessions s ON s.token_hash=b.token_hash WHERE b.token_hash=? AND s.expires_at>?`,hash,unix());
 if(!row){if(required)fail('unauthenticated',401);return null;}
 let tokens=await decode(env,row),claims=claimsOf(tokens.access_token);
 if(claims.exp<unix()+30){
  const lease=id(),claimed=await env.DB.prepare('UPDATE private.bff_sessions SET refresh_lease=?,refresh_lease_until=? WHERE token_hash=? AND version=? AND refresh_lease IS NULL RETURNING token_hash').bind(lease,unix()+30,hash,row.version).first();
  if(!claimed){
   const current=await first(env,'SELECT * FROM private.bff_sessions WHERE token_hash=?',hash);
   if(current?.token_hash===hash&&current.auth_user_id===row.auth_user_id&&current.auth_session_id===row.auth_session_id&&current.version===row.version+1&&current.refresh_lease===null&&current.refresh_lease_until===null&&typeof current.token_ciphertext==='string'&&current.token_ciphertext&&current.token_ciphertext!==row.token_ciphertext){
    const winner=await decode(env,current),proof=await verifyToken(env,winner.access_token);
    if(proof.user.id!==row.auth_user_id||proof.claims.session_id!==row.auth_session_id)fail('session_changed',401);
    tokens=winner; // Exact committed winner, never a second refresh dispatch.
   }else{
    if(current?.refresh_lease&&current.refresh_lease_until<=unix()){await env.DB.prepare('DELETE FROM admin_sessions WHERE token_hash=?').bind(hash).run();fail('session_refresh_recovery_required',401);}
    fail('session_refresh_pending',409);
   }
  }else{
  let refreshed,cipher;
  try {
   refreshed=await authRequest(env,'/token?grant_type=refresh_token',{body:{refresh_token:tokens.refresh_token}});
   const proof=await verifyToken(env,refreshed.access_token);if(proof.user.id!==row.auth_user_id||proof.claims.session_id!==row.auth_session_id)fail('session_changed',401);
   cipher=await encode(env,row,refreshed);const updated=await env.DB.prepare('UPDATE private.bff_sessions SET token_ciphertext=?,version=version+1,refresh_lease=NULL,refresh_lease_until=NULL WHERE token_hash=? AND refresh_lease=? AND version=? RETURNING version').bind(cipher,hash,lease,row.version).first();if(!updated)fail('session_changed',401);tokens=refreshed;
  }catch(error){
   // A lost COMMIT reply is recoverable only from this exact durable ciphertext.
   const retained=await first(env,'SELECT * FROM private.bff_sessions WHERE token_hash=?',hash).catch(()=>null);
   if(refreshed&&cipher&&retained?.version===row.version+1&&retained.token_ciphertext===cipher&&retained.refresh_lease===null)tokens=refreshed;
   else{await env.DB.prepare('DELETE FROM admin_sessions WHERE token_hash=?').bind(hash).run().catch(()=>{});fail('session_refresh_recovery_required',401);}
  }
  }
 }

 const verified=await verifyToken(env,tokens.access_token);if(verified.user.id!==row.auth_user_id||verified.claims.session_id!==row.auth_session_id)fail('session_changed',401);
 env.ADMIN_AUTH_EXCHANGE=true;await projectSession(env,verified,{surface:'admin'});env.ADMIN_AUTH_EXCHANGE=false;
 const account=await legacySession(request,env,required);if(!account)return null;
 const csrf=await digest('collect-admin-csrf:'+token);
 if(!['GET','HEAD','OPTIONS'].includes(request.method)&&request.headers.get('X-Collect-CSRF')!==csrf)fail('csrf_rejected');
 account.supabaseTokens=tokens;account.auth_user_id=row.auth_user_id;account.csrfToken=csrf;await loadAdminEmailAccount(env,account);env.ADMIN_ACCOUNT=account;return account;
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
 await env.DB.prepare("UPDATE admin_users SET status='active',password_hash='supabase-managed',accepted_at=COALESCE(accepted_at,?),updated_at=? WHERE id=? AND status IN('active','invited')").bind(unix(),unix(),account.id).run();
 env.ADMIN_AUTH_EXCHANGE=true;try{await projectSession(env,verified,{surface:'admin'});}finally{env.ADMIN_AUTH_EXCHANGE=false;}
 const sid=verified.claims.session_id,projected=await first(env,'SELECT * FROM auth_sessions WHERE id=? AND user_id=? AND revoked_at IS NULL',sid,account.principal_id);if(!projected||projected.surface!=='admin')fail('session_changed',401);
 const token=random(),hash=await digest(token),publicId=id(),at=projected.auth_at,expiry=projected.expires_at,row={auth_user_id:verified.user.id,auth_session_id:sid},cipher=await encode(env,row,data);
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
 return json({user:adminPublicUser(authenticated),expiresAt:new Date(expiry*1000).toISOString(),csrfToken:authenticated.csrfToken},200,{'Set-Cookie':adminCookie(token,Math.max(0,expiry-unix()))});
}

async function manageTeam(request,env,path){
 const account=await adminAccountSession(request,env);if(account.role!=='owner'||account.email!=='info@ikanisa.com'||!account.permissions.includes('admin_users.manage'))fail('owner_required');requireFreshAdminEmail(account);
 const body=request.method==='GET'?{}:await readJson(request);
 const invitationV2=await handleAdminInvitationV2(request,env,account,body,path);if(invitationV2)return invitationV2;
 const invitation=await handleAdminInvitation(request,env,account,body,path);if(invitation)return invitation;
 const match=/^\/team\/([0-9a-f-]{36})\/revoke$/.exec(path);if(!match)fail('not_found',404);
 const subject=await first(env,'SELECT * FROM admin_users WHERE id=?',uuid(match[1]));if(!subject||subject.role==='owner')fail('owner_protected');
 await accountDatabase(env,account,'admin_users.manage',{owner:true,mfa:true,fresh:true}).DB.batch([env.DB.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1,challenge_version=challenge_version+1,updated_at=? WHERE id=?").bind(unix(),subject.id)]);return json({ok:true});
}
export async function handleAdminAccounts(request,env,ctx) {
 const full=new URL(request.url).pathname;if(!full.startsWith('/api/admin/'))return null;const path=full.slice('/api/admin'.length);
 if(!path.startsWith('/auth/')&&path!=='/team'&&!path.startsWith('/team/'))return null;
 validateAdminOrigin(request,env);
 if(path==='/auth/mfa'||path.startsWith('/auth/mfa/'))throw new ApiError(410,'mfa_not_available','Verify your email to confirm sensitive changes.');
 const readOnly=(path==='/auth/session'||path==='/auth/user'||path==='/auth/email-verification'||path==='/team'||path==='/team/invitation-status'||path==='/team/v2'||path==='/team/v2/invitation-status')&&request.method==='GET';if(!readOnly&&request.method!=='POST')fail('method_not_allowed',405);const google=await handleAdminGoogle(request,env);if(google)return google;
 if(path==='/auth/session'&&request.method==='GET'){const account=await adminAccountSession(request,env,false);return json({user:adminPublicUser(account),expiresAt:account?new Date(account.expires_at*1000).toISOString():null,ownerEmail:'info@ikanisa.com',csrfToken:account?.csrfToken??null});}
 if(path==='/team'&&request.method==='GET'){await adminAccountSession(request,env);const account=env.ADMIN_ACCOUNT;if(!account.permissions.includes('admin_users.read'))fail('permission_required');const members=await rows(env,`SELECT a.id,a.email,a.role,a.status,a.display_name,a.created_at,a.invited_at,a.accepted_at,(SELECT CASE WHEN i.state IN('reserved','dispatching') THEN 'unknown' ELSE i.state END FROM private.admin_invitation_attempts i WHERE i.subject_id=a.id AND i.contract_version=1 AND i.replayed_request_id IS NULL ORDER BY i.attempt_sequence DESC LIMIT 1) AS invitation_email_status,(SELECT i.request_id::text FROM private.admin_invitation_attempts i WHERE i.subject_id=a.id AND i.contract_version=1 AND i.replayed_request_id IS NULL ORDER BY i.attempt_sequence DESC LIMIT 1) AS invitation_request_id,(SELECT i.kind FROM private.admin_invitation_attempts i WHERE i.subject_id=a.id AND i.contract_version=1 AND i.replayed_request_id IS NULL ORDER BY i.attempt_sequence DESC LIMIT 1) AS invitation_operation FROM admin_users a ORDER BY a.email`);const capabilities=await rows(env,"SELECT role,permission FROM admin_account_role_capabilities WHERE permission<>'auth.mfa.enroll'");const permissionsByRole={owner:[],admin:[],staff:[]};for(const c of capabilities)permissionsByRole[c.role].push(c.permission);return json({currentEmail:account.email,canManage:account.role==='owner'&&account.email==='info@ikanisa.com'&&account.permissions.includes('admin_users.manage')&&hasFreshAdminEmail(account),permissionsByRole,members:members.map(v=>({...v,displayName:v.display_name,createdAt:new Date(v.created_at*1000).toISOString(),invitedAt:v.invited_at?new Date(v.invited_at*1000).toISOString():null,acceptedAt:v.accepted_at?new Date(v.accepted_at*1000).toISOString():null,emailStatus:v.invitation_email_status??null,invitationRequestId:v.invitation_request_id??null,invitationOperation:v.invitation_operation??null}))});}
 if(path.startsWith('/team/'))return manageTeam(request,env,path);
 if(path==='/auth/otp'){return json(await startOtp(env,{...await readJson(request),surface:'admin'}));}
 if(path==='/auth/verify'){const body=await readJson(request);const result=await verifyOtp(env,{...body,surface:'admin'},{project:false});return issueAdminSession(request,env,result,{emailChallengeId:uuid(body.challenge_id,'challenge_id')});}
 if(path==='/auth/login'){const body=await readJson(request);const account=await first(env,"SELECT id FROM admin_users WHERE email=? AND status='active'",String(body.email??'').trim().toLowerCase());if(!account)fail('invalid_credentials',401);return issueAdminSession(request,env,await authRequest(env,'/token?grant_type=password',{body:{email:body.email,password:body.password,gotrue_meta_security:{captcha_token:body.captcha_token}}}));}
 if(path==='/auth/logout'){const account=await adminAccountSession(request,env);await authRequest(env,'/logout?scope=local',{token:account.supabaseTokens.access_token});await env.DB.batch([env.DB.prepare('DELETE FROM admin_sessions WHERE token_hash=?').bind(account.token_hash)]);return json({ok:true},200,{'Set-Cookie':adminCookie()});}
 if(path==='/auth/forgot-password'){const body=await readJson(request);const account=await first(env,"SELECT id FROM admin_users WHERE email=? AND status='active'",String(body.email??'').trim().toLowerCase());if(account)await authRequest(env,'/recover',{body:{email:body.email,gotrue_meta_security:{captcha_token:body.captcha_token}}});return json({ok:true,message:'Request received. If eligible, check your inbox.'},202);}
 if(path==='/auth/complete-password'){
  const body=await readJson(request);if(typeof body.token!=='string'||!/^\S{32,512}$/.test(body.token)||typeof body.password!=='string'||body.password.length<12||body.password.length>128||typeof body.invite!=='boolean')fail('invalid_link',400);
  const data=await authRequest(env,'/verify',{body:{token_hash:body.token,type:body.invite?'invite':'recovery'}}),verified=await verifyToken(env,data.access_token);
  const approved=await first(env,"SELECT id FROM admin_users WHERE email=? AND status IN('active','invited')",verified.user.email?.toLowerCase());if(!approved){await authRequest(env,'/logout',{token:data.access_token}).catch(()=>{});fail('admin_access_not_approved');}
  await authRequest(env,'/user',{method:'PUT',token:data.access_token,body:{password:body.password}});
  await env.DB.prepare("UPDATE admin_users SET status='active',password_hash='supabase-managed',auth_version=auth_version+1,accepted_at=COALESCE(accepted_at,?),updated_at=? WHERE id=?").bind(unix(),unix(),approved.id).run();await authRequest(env,'/logout',{token:data.access_token});return json({ok:true},200,{'Set-Cookie':adminCookie()});
 }
 const account=await adminAccountSession(request,env);
 const emailVerification=await handleAdminEmail(request,env,account,path);if(emailVerification)return emailVerification;
 if(path==='/auth/user'){
  const body=request.method==='GET'?null:await readJson(request);
  return handleAuth(await adminInternalRequest(request,env,account,'/v1/auth/user',request.method,body),env);
 }
 if(path==='/auth/change-password')return changeAdminPassword(request,env,account);
 fail('not_found',404);
}
