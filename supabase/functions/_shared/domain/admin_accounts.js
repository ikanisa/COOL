import {ApiError,json,readJson,first,uuid} from './core.js';
import {handleAdminEmail} from './admin_email_auth.js';
import {changeAdminPassword} from './admin_password.js';
import {authRequest,verifyToken} from '../auth-http.js';
import {startOtp,verifyOtp,handleAuth} from './auth.js';
import {adminPublicUser,accountDatabase,adminCookie,guardedOwnerSessionIdentity} from './admin_accounts_legacy.js';
import {handleAdminGoogle} from './admin-google.js';
import {validateAdminOrigin,adminCookieToken,LEGACY_ADMIN_OWNER_EMAIL} from '../admin-security.js';
import {adminManagedMfa} from './admin_managed_mfa.js';
import {adminMfaPorts,resolveAdminMfaCandidate,logoutAdminMfaCandidate,recoverAdminMfaIntent,logoutAdminMfaIntent} from './admin_mfa_bff.js';
import {adminAccountSession,adminInternalRequest,issueAdminSession,logoutAdminSession,adminMfaEnabled} from './admin_session.js';
import {ADMIN_COOKIE_SECONDS} from './admin_bff_tokens.js';
import {readAdminTeam,manageAdminTeam} from './admin_team.js';
import {failAdminAccount as fail} from './admin_account_support/errors.js';

export {adminPublicUser,accountGuard,accountDatabase,accountReadDatabase,adminCookie} from './admin_accounts_legacy.js';
export {adminAccountSession,adminInternalRequest,adminCanonicalActor,issueAdminSession} from './admin_session.js';
export {validateAdminOrigin};

const unix=()=>Math.floor(Date.now()/1000);
const adminMfaRecovery=env=>adminMfaEnabled(env)||env.COLLECT_ADMIN_TOTP_RECOVERY_ENABLED==='true';

export async function handleAdminAccounts(request,env,ctx) {
 const full=new URL(request.url).pathname;if(!full.startsWith('/api/admin/'))return null;const path=full.slice('/api/admin'.length);
 if(!path.startsWith('/auth/')&&path!=='/team'&&!path.startsWith('/team/'))return null;
 validateAdminOrigin(request,env);
 const mfaPath=path==='/auth/mfa'||path.startsWith('/auth/mfa/');
 if(mfaPath&&!adminMfaEnabled(env))throw new ApiError(410,'mfa_not_available','Verify your email to confirm sensitive changes.');
 const readOnly=(path==='/auth/session'||path==='/auth/user'||path==='/auth/email-verification'||path==='/auth/mfa/factors'||path==='/team'||path==='/team/invitation-status'||path==='/team/v2'||path==='/team/v2/invitation-status')&&request.method==='GET';if(!readOnly&&request.method!=='POST')fail('method_not_allowed',405);const google=await handleAdminGoogle(request,env);if(google)return google;
 if(mfaPath){
  if(path==='/auth/mfa/recover'&&request.method==='POST'){
   const result=await recoverAdminMfaIntent(env,request,await readJson(request));return json({ok:true},200,{'Set-Cookie':result.cookie});
  }
  const operations={'/auth/mfa/factors':'list','/auth/mfa/enroll':'enroll','/auth/mfa/challenge':'challenge','/auth/mfa/verify':'verify','/auth/mfa/cancel-enrollment':'cancel'};
  const operation=operations[path];if(!operation)fail('not_found',404);
  if((operation==='list'&&request.method!=='GET')||(operation!=='list'&&request.method!=='POST'))fail('method_not_allowed',405);
  const account=await adminAccountSession(request,env),ports=adminMfaPorts(env,account,request);
  const result=await adminManagedMfa({enabled:true,account,operation,body:operation==='list'?{}:await readJson(request),...ports});
  return operation==='verify'?json({ok:true},200,{'Set-Cookie':result.cookie}):json(result);
 }
 if(path==='/auth/session'&&request.method==='GET'){
  const transition=adminMfaRecovery(env)?await resolveAdminMfaCandidate(env,request,{enabled:adminMfaEnabled(env)}):null;
  let resolvedRequest=request;
  if(transition?.state==='restore'){const headers=new Headers(request.headers);headers.set('Cookie',`__Host-collect_admin=${transition.token}`);resolvedRequest=new Request(request,{headers});}
  const account=await adminAccountSession(resolvedRequest,env,false);
  if(account&&adminMfaEnabled(env)&&['owner','admin','staff'].includes(account.role)){
   const policy=await accountDatabase(env,account).DB.batch([env.DB.prepare('SELECT private.collect_admin_mfa_policy_enabled_v1() AS required')]);
   const required=policy?.[0]?.results?.[0]?.required;
   if(typeof required!=='boolean')throw new ApiError(503,'mfa_policy_unavailable','Authenticator policy is temporarily unavailable.');
   account.mfaRequired=required;
   try{await adminMfaPorts(env,account,resolvedRequest).guard({fresh:false,operation:'list'});account.mfaAvailable=true;}
   catch(error){if(!(error instanceof ApiError&&error.status===403))throw error;}
  }
  // The server and the authenticated caller must opt in independently. Signed
  // out and all legacy responses keep their existing exact envelope shape.
  const wantsOwner=account&&env.COLLECT_ADMIN_OWNER_IDENTITY_ENABLED==='true'&&request.headers.get('X-Collect-Owner-Identity-Version')==='1';
  const ownerIdentity=wantsOwner?await guardedOwnerSessionIdentity(env,account):null;
  return json({user:adminPublicUser(account),expiresAt:account?new Date(account.expires_at*1000).toISOString():null,
   ownerEmail:wantsOwner?ownerIdentity?.email??null:LEGACY_ADMIN_OWNER_EMAIL,csrfToken:account?.csrfToken??null,
   ...(wantsOwner?{ownerIdentity}:{})},200,transition?.state==='restore'?{'Set-Cookie':transition.cookie}:
    account&&!adminMfaEnabled(env)?{'Set-Cookie':adminCookie(adminCookieToken(resolvedRequest),ADMIN_COOKIE_SECONDS)}:{});
 }
 if(path==='/team'&&request.method==='GET')return readAdminTeam(request,env);
 if(path.startsWith('/team/'))return manageAdminTeam(request,env,path);
 if(path==='/auth/otp'){return json(await startOtp(env,{...await readJson(request),surface:'admin'}));}
 if(path==='/auth/verify'){const body=await readJson(request);const result=await verifyOtp(env,{...body,surface:'admin'},{project:false});return issueAdminSession(request,env,result,{emailChallengeId:uuid(body.challenge_id,'challenge_id')});}
 if(path==='/auth/login'){const body=await readJson(request);const account=await first(env,"SELECT id FROM admin_users WHERE email=? AND status='active'",String(body.email??'').trim().toLowerCase());if(!account)fail('invalid_credentials',401);return issueAdminSession(request,env,await authRequest(env,'/token?grant_type=password',{body:{email:body.email,password:body.password,gotrue_meta_security:{captcha_token:body.captcha_token}}}));}
 if(path==='/auth/logout'){
  if(adminMfaRecovery(env)&&!request.headers.has('X-Collect-CSRF')&&adminCookieToken(request)){
   const body=await readJson(request);
   if(body&&Object.hasOwn(body,'verification_id')){
    const transition=await logoutAdminMfaIntent(env,request,body);
    return json({ok:true,providerLogout:transition.providerLogout},200,{'Set-Cookie':transition.cookie});
   }
  }
  const transition=adminMfaRecovery(env)?await logoutAdminMfaCandidate(env,request):null;
  if(transition?.state==='revoked')return json({ok:true,providerLogout:transition.providerLogout},200,{'Set-Cookie':transition.cookie});
  return logoutAdminSession(request,env);
 }
 if(path==='/auth/forgot-password'){const body=await readJson(request);const account=await first(env,"SELECT id FROM admin_users WHERE email=? AND status='active'",String(body.email??'').trim().toLowerCase());if(account)await authRequest(env,'/recover',{body:{email:body.email,gotrue_meta_security:{captcha_token:body.captcha_token}}});return json({ok:true,message:'Request received. If eligible, check your inbox.'},202);}
 if(path==='/auth/complete-password'){
  const body=await readJson(request);if(typeof body.token!=='string'||!/^\S{32,512}$/.test(body.token)||typeof body.password!=='string'||body.password.length<12||body.password.length>128||typeof body.invite!=='boolean')fail('invalid_link',400);
  const data=await authRequest(env,'/verify',{body:{token_hash:body.token,type:body.invite?'invite':'recovery'}}),verified=await verifyToken(env,data.access_token);
  const approved=await first(env,"SELECT id,auth_version FROM admin_users WHERE email=? AND status IN('active','invited')",verified.user.email?.toLowerCase());if(!approved||!Number.isSafeInteger(approved.auth_version)){await authRequest(env,'/logout',{token:data.access_token}).catch(()=>{});fail('admin_access_not_approved');}
  await authRequest(env,'/user',{method:'PUT',token:data.access_token,body:{password:body.password}});
  // The provider update happened outside our database. Do not revive an
  // account revoked or changed while that request was in flight.
  let changed;try{changed=await env.DB.batch([env.DB.prepare("UPDATE admin_users SET status='active',password_hash='supabase-managed',auth_version=auth_version+1,accepted_at=COALESCE(accepted_at,?),updated_at=? WHERE id=? AND status IN('active','invited') AND auth_version=?").bind(unix(),unix(),approved.id,approved.auth_version)]);}
  catch(error){await authRequest(env,'/logout',{token:data.access_token}).catch(()=>{});throw error;}
  if(changed?.[0]?.meta?.changes!==1){await authRequest(env,'/logout',{token:data.access_token}).catch(()=>{});throw new ApiError(503,'password_recovery_unconfirmed','The password change could not be confirmed. Contact the administrator.');}
  await authRequest(env,'/logout',{token:data.access_token});return json({ok:true},200,{'Set-Cookie':adminCookie()});
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
