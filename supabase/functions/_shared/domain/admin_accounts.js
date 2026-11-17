import {ApiError,json,readJson,first,rows,id,digest,uuid,now} from './core.js';
import {loadAdminEmailAccount,handleAdminEmail,isAdminEmailDenialError} from './admin_email_auth.js';
import {changeAdminPassword} from './admin_password.js';
import {bindAdminEmailActor,requireFreshAdminEmail,hasFreshAdminEmail} from './admin_email_policy.js';
import {authRequest,verifyToken,claimsOf} from '../auth-http.js';
import {projectSession,startOtp,verifyOtp,responseSession,handleAuth} from './auth.js';
import {encrypt,decrypt} from './encryption.js';
import {adminAccountSession as legacySession,adminPublicUser,accountGuard,accountDatabase,adminCookie,guardedOwnerSessionIdentity} from './admin_accounts_legacy.js';
import {handleAdminGoogle} from './admin-google.js';
import {validateAdminOrigin} from '../admin-security.js';
import {handleAdminInvitation} from './admin_invitation.js';
import {handleAdminInvitationV2} from './admin_invitation_v2.js';
import {preliminaryCurrentOwner} from './admin_owner_precheck.js';
import {adminManagedMfa} from './admin_managed_mfa.js';
import {adminMfaPorts,resolveAdminMfaCandidate,logoutAdminMfaCandidate,recoverAdminMfaIntent,logoutAdminMfaIntent} from './admin_mfa_bff.js';
export {adminPublicUser,accountGuard,accountDatabase,adminCookie,validateAdminOrigin};
const unix=()=>Math.floor(Date.now()/1000);
// Browser storage is renewed on each session check; Chrome caps a persistent
// cookie at 400 days. Server/provider revocation remains authoritative.
const ADMIN_COOKIE_SECONDS=400*24*60*60;
const adminMfaEnabled=env=>env.COLLECT_ADMIN_TOTP_ENABLED==='true';
const adminMfaRecovery=env=>adminMfaEnabled(env)||env.COLLECT_ADMIN_TOTP_RECOVERY_ENABLED==='true';
const TERMINAL_REFRESH_ERRORS=new Set(['refresh_token_not_found','refresh_token_already_used','session_not_found','session_expired','user_not_found','user_banned']);
const fail=(code,status=403)=>{throw new ApiError(status,code,code==='admin_access_not_approved'?'This email does not have Admin access. Contact the super admin to be added.':'This Admin action is unavailable.');};
const random=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),v=>v.toString(16).padStart(2,'0')).join('');
const custodyEnv=env=>({...env,DATA_KEY_ID:env.SESSION_KEY_ID??'bff-v1',DATA_ENCRYPTION_KEY:env.SESSION_ENCRYPTION_KEY,DATA_DECRYPTION_KEYS_JSON:env.SESSION_DECRYPTION_KEYS_JSON});
const context=row=>`bff:${row.auth_session_id}:${row.auth_user_id}`;
async function decode(env,row){return JSON.parse(new TextDecoder().decode(await decrypt(custodyEnv(env),row.token_ciphertext,context(row))));}
async function encode(env,row,tokens){return encrypt(custodyEnv(env),new TextEncoder().encode(JSON.stringify({access_token:tokens.access_token,refresh_token:tokens.refresh_token})),context(row));}
const cookieToken=request=>{
 const values=(request.headers.get('Cookie')??'').split(';').map(x=>x.trim()).filter(x=>x.startsWith('__Host-collect_admin='));
 return values.length===1&&/^__Host-collect_admin=[a-f0-9]{64}$/.test(values[0])?values[0].split('=')[1]:null;
};
async function revokeFailedRefresh(env,hash,version,lease){
 // Lock both rows before deciding: a reclaimed lease or concurrent logout must
 // never be deleted because of an older provider response.
 return env.DB.transaction(async sql=>{
  await env.DB.context(sql);
  await sql.unsafe('SELECT pg_advisory_xact_lock(734636924058501::bigint)');
  const rows=await sql.unsafe(`SELECT s.token_hash FROM app.admin_sessions s
    JOIN private.bff_sessions b ON b.token_hash=s.token_hash
    WHERE s.token_hash=$1 AND b.version=$2 AND b.refresh_lease=$3 FOR UPDATE OF s,b`,[hash,version,lease]);
  if(rows.length!==1)return false;
  await sql.unsafe('DELETE FROM app.admin_sessions WHERE token_hash=$1',[hash]);return true;
 });
}
async function logoutAdminSession(request,env){
 const origin=validateAdminOrigin(request,env),token=cookieToken(request);
 if(!token)return json({ok:true},200,{'Set-Cookie':adminCookie()});
 if(request.headers.get('X-Collect-CSRF')!==await digest('collect-admin-csrf:'+token))fail('csrf_rejected');
 const hash=await digest(token);
 // Commit the exact browser session's local revocation first. Provider outages
 // must not leave a restorable cookie behind after a confirmed local sign-out.
 const retained=await env.DB.transaction(async sql=>{
  await env.DB.context(sql);
  await sql.unsafe('SELECT pg_advisory_xact_lock(734636924058501::bigint)');
  const sessions=await sql.unsafe('SELECT token_hash FROM app.admin_sessions WHERE token_hash=$1 AND origin=$2 FOR UPDATE',[hash,origin]);
  if(sessions.length!==1)return null;
  const rows=await sql.unsafe('SELECT auth_user_id,auth_session_id,token_ciphertext FROM private.bff_sessions WHERE token_hash=$1',[hash]);
  await sql.unsafe('DELETE FROM app.admin_sessions WHERE token_hash=$1 AND origin=$2',[hash,origin]);
  return rows[0]??null;
 });
 let providerLogout='unconfirmed';
 if(retained){
  try{const tokens=await decode(env,retained);await authRequest(env,'/logout?scope=local',{token:tokens.access_token});providerLogout='confirmed';}
  catch{/* The local session is already revoked; do not retry an unknown provider effect. */}
 }
 return json({ok:true,providerLogout},200,{'Set-Cookie':adminCookie()});
}
export async function adminAccountSession(request,env,required=true) {
 const origin=validateAdminOrigin(request,env);const token=cookieToken(request);if(!token){if(required)fail('unauthenticated',401);return null;}
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
  const original=await decode(env,row),proof=await verifyToken(env,original.access_token);
  if(proof.user.id!==row.auth_user_id||proof.claims.session_id!==row.auth_session_id||![1,2].includes(row.issued_assurance_level)||
   proof.claims.aal!==`aal${row.issued_assurance_level}`||proof.user.email?.toLowerCase()!==row.admin_email)fail('session_changed',401);
  env.DB.setClaims(proof.claims);
  const ack=await env.DB.batch([env.DB.prepare('SELECT private.collect_admin_mfa_intent_ack_restore_v1(?,?,?,?) AS result').bind(row.admin_id,hash,origin,row.public_id)]);
  if(ack?.[0]?.results?.[0]?.result!==true)throw new ApiError(409,'mfa_recovery_pending','The authenticator result is still being recovered.');
  row={...row,mfa_intent_hash:null,mfa_pending_state:null};
 }
 let tokens=await decode(env,row),claims=claimsOf(tokens.access_token);
 if(claims.exp<unix()+30){
  const lease=id();let claimed=await env.DB.prepare('UPDATE private.bff_sessions SET refresh_lease=?,refresh_lease_until=? WHERE token_hash=? AND version=? AND refresh_lease IS NULL RETURNING token_hash').bind(lease,unix()+30,hash,row.version).first();
  if(!claimed){
   const current=await first(env,'SELECT * FROM private.bff_sessions WHERE token_hash=?',hash);
   if(current?.token_hash===hash&&current.auth_user_id===row.auth_user_id&&current.auth_session_id===row.auth_session_id&&current.version===row.version+1&&current.refresh_lease===null&&current.refresh_lease_until===null&&typeof current.token_ciphertext==='string'&&current.token_ciphertext&&current.token_ciphertext!==row.token_ciphertext){
    const winner=await decode(env,current),proof=await verifyToken(env,winner.access_token);
    if(proof.user.id!==row.auth_user_id||proof.claims.session_id!==row.auth_session_id)fail('session_changed',401);
    tokens=winner; // Exact committed winner, never a second refresh dispatch.
   }else if(current?.token_hash===hash&&current.auth_user_id===row.auth_user_id&&current.auth_session_id===row.auth_session_id&&
      current.version===row.version&&current.token_ciphertext===row.token_ciphertext&&typeof current.refresh_lease==='string'&&
      Number.isSafeInteger(current.refresh_lease_until)&&current.refresh_lease_until<=unix()){
    // GoTrue accepts the current refresh token or its immediate parent after a
    // lost response. Reclaim only this exact expired lease and ciphertext; a
    // concurrent winner or a different session is never replayed.
    claimed=await env.DB.prepare(`UPDATE private.bff_sessions SET refresh_lease=?,refresh_lease_until=?
      WHERE token_hash=? AND version=? AND refresh_lease=? AND refresh_lease_until=? AND token_ciphertext=? RETURNING token_hash`)
      .bind(lease,unix()+30,hash,row.version,current.refresh_lease,current.refresh_lease_until,row.token_ciphertext).first();
    if(!claimed)fail('session_refresh_pending',409);
   }else{
    fail('session_refresh_pending',409);
   }
  }
  if(claimed){
  let refreshed,cipher;
  try {
   refreshed=await authRequest(env,'/token?grant_type=refresh_token',{body:{refresh_token:tokens.refresh_token}});
   const proof=await verifyToken(env,refreshed.access_token);if(proof.user.id!==row.auth_user_id||proof.claims.session_id!==row.auth_session_id)fail('session_changed',401);
   if(proof.claims.aal==='aal2'&&row.issued_assurance_level!==2)throw new ApiError(409,'mfa_recovery_required','Recheck the authenticator result before continuing.');
   cipher=await encode(env,row,refreshed);const updated=await env.DB.prepare('UPDATE private.bff_sessions SET token_ciphertext=?,version=version+1,refresh_lease=NULL,refresh_lease_until=NULL WHERE token_hash=? AND refresh_lease=? AND version=? RETURNING version').bind(cipher,hash,lease,row.version).first();if(!updated)fail('session_changed',401);tokens=refreshed;
  }catch(error){
   // A lost COMMIT reply is recoverable from the exact retained ciphertext;
   // a concurrent committed winner is separately verified under the same SID.
   let retained;try{retained=await first(env,'SELECT * FROM private.bff_sessions WHERE token_hash=?',hash);}
   catch{throw new ApiError(503,'session_refresh_pending','The session is temporarily unavailable.');}
   if(!retained)fail('unauthenticated',401);
   if(refreshed&&cipher&&retained.version===row.version+1&&retained.token_ciphertext===cipher&&retained.refresh_lease===null)tokens=refreshed;
   else if(retained.token_hash===hash&&retained.auth_user_id===row.auth_user_id&&retained.auth_session_id===row.auth_session_id&&
     retained.version===row.version+1&&retained.refresh_lease===null&&retained.refresh_lease_until===null&&
     typeof retained.token_ciphertext==='string'&&retained.token_ciphertext&&retained.token_ciphertext!==row.token_ciphertext){
    const winner=await decode(env,retained),proof=await verifyToken(env,winner.access_token);
    if(proof.user.id!==row.auth_user_id||proof.claims.session_id!==row.auth_session_id)fail('session_changed',401);
    tokens=winner;
   }else if(!refreshed&&[400,401,403,422].includes(error?.status)&&TERMINAL_REFRESH_ERRORS.has(error?.code)&&
     retained.version===row.version&&retained.refresh_lease===lease){
    // A definite provider rejection ends only this still-owned original session.
    if(!await revokeFailedRefresh(env,hash,row.version,lease))fail('session_refresh_pending',409);
    fail('session_refresh_recovery_required',401);
   }else if(error?.code==='mfa_recovery_required'){
    await env.DB.prepare('UPDATE private.bff_sessions SET refresh_lease=NULL,refresh_lease_until=NULL WHERE token_hash=? AND version=? AND refresh_lease=?').bind(hash,row.version,lease).first();
    throw error;
   }else throw new ApiError(503,'session_refresh_pending','The session is temporarily unavailable.');
  }
  }
 }

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
 env.ADMIN_AUTH_EXCHANGE=true;try{await projectSession(env,verified,{surface:'admin'});}finally{env.ADMIN_AUTH_EXCHANGE=false;}
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
 return json({user:adminPublicUser(authenticated),expiresAt:new Date(authenticated.expires_at*1000).toISOString(),csrfToken:authenticated.csrfToken},200,{'Set-Cookie':adminCookie(token,ADMIN_COOKIE_SECONDS)});
}

async function manageTeam(request,env,path){
 const account=await adminAccountSession(request,env);if(!account.permissions.includes('admin_users.manage')||!await preliminaryCurrentOwner(env,account))fail('owner_required');requireFreshAdminEmail(account);
 const body=request.method==='GET'?{}:await readJson(request);
 const invitationV2=await handleAdminInvitationV2(request,env,account,body,path);if(invitationV2)return invitationV2;
 const invitation=await handleAdminInvitation(request,env,account,body,path);if(invitation)return invitation;
 const match=/^\/team\/([0-9a-f-]{36})\/revoke$/.exec(path);if(!match)fail('not_found',404);
 const subject=await first(env,'SELECT * FROM admin_users WHERE id=?',uuid(match[1]));if(!subject||subject.role==='owner')fail('owner_protected');
 const dynamic=env.COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED==='true';
 const update=env.DB.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1,challenge_version=challenge_version+1,updated_at=? WHERE id=?"+
  (dynamic?" AND id <> (private.collect_owner_attestation()->>'adminId')":'' )).bind(unix(),subject.id);
 const changed=await accountDatabase(env,account,'admin_users.manage',{owner:true,mfa:true,fresh:true}).DB.batch([update]);
 if(dynamic&&changed?.[0]?.meta?.changes!==1)throw new ApiError(409,'admin_access_changed','The account changed. Refresh before trying again.');
 return json({ok:true});
}
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
   ownerEmail:wantsOwner?ownerIdentity?.email??null:'info@ikanisa.com',csrfToken:account?.csrfToken??null,
   ...(wantsOwner?{ownerIdentity}:{})},200,transition?.state==='restore'?{'Set-Cookie':transition.cookie}:
    account&&!adminMfaEnabled(env)?{'Set-Cookie':adminCookie(cookieToken(resolvedRequest),ADMIN_COOKIE_SECONDS)}:{});
 }
 if(path==='/team'&&request.method==='GET'){await adminAccountSession(request,env);const account=env.ADMIN_ACCOUNT;if(!account.permissions.includes('admin_users.read'))fail('permission_required');const members=await rows(env,`SELECT a.id,a.email,a.role,a.status,a.display_name,a.created_at,a.invited_at,a.accepted_at,(SELECT CASE WHEN i.state IN('reserved','dispatching') THEN 'unknown' ELSE i.state END FROM private.admin_invitation_attempts i WHERE i.subject_id=a.id AND i.contract_version=1 AND i.replayed_request_id IS NULL ORDER BY i.attempt_sequence DESC LIMIT 1) AS invitation_email_status,(SELECT i.request_id::text FROM private.admin_invitation_attempts i WHERE i.subject_id=a.id AND i.contract_version=1 AND i.replayed_request_id IS NULL ORDER BY i.attempt_sequence DESC LIMIT 1) AS invitation_request_id,(SELECT i.kind FROM private.admin_invitation_attempts i WHERE i.subject_id=a.id AND i.contract_version=1 AND i.replayed_request_id IS NULL ORDER BY i.attempt_sequence DESC LIMIT 1) AS invitation_operation FROM admin_users a ORDER BY a.email`);const capabilities=await rows(env,"SELECT role,permission FROM admin_account_role_capabilities WHERE permission<>'auth.mfa.enroll'");const permissionsByRole={owner:[],admin:[],staff:[]};for(const c of capabilities)permissionsByRole[c.role].push(c.permission);return json({currentEmail:account.email,canManage:account.permissions.includes('admin_users.manage')&&hasFreshAdminEmail(account)&&await preliminaryCurrentOwner(env,account),permissionsByRole,members:members.map(v=>({...v,displayName:v.display_name,createdAt:new Date(v.created_at*1000).toISOString(),invitedAt:v.invited_at?new Date(v.invited_at*1000).toISOString():null,acceptedAt:v.accepted_at?new Date(v.accepted_at*1000).toISOString():null,emailStatus:v.invitation_email_status??null,invitationRequestId:v.invitation_request_id??null,invitationOperation:v.invitation_operation??null}))});}
 if(path.startsWith('/team/'))return manageTeam(request,env,path);
 if(path==='/auth/otp'){return json(await startOtp(env,{...await readJson(request),surface:'admin'}));}
 if(path==='/auth/verify'){const body=await readJson(request);const result=await verifyOtp(env,{...body,surface:'admin'},{project:false});return issueAdminSession(request,env,result,{emailChallengeId:uuid(body.challenge_id,'challenge_id')});}
 if(path==='/auth/login'){const body=await readJson(request);const account=await first(env,"SELECT id FROM admin_users WHERE email=? AND status='active'",String(body.email??'').trim().toLowerCase());if(!account)fail('invalid_credentials',401);return issueAdminSession(request,env,await authRequest(env,'/token?grant_type=password',{body:{email:body.email,password:body.password,gotrue_meta_security:{captcha_token:body.captcha_token}}}));}
 if(path==='/auth/logout'){
  if(adminMfaRecovery(env)&&!request.headers.has('X-Collect-CSRF')&&cookieToken(request)){
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
