import {ApiError,digest,id} from './core.js';
import {authRequest,verifyToken} from '../auth-http.js';
import {encrypt,decrypt,adminMfaReplayHashes} from './encryption.js';
import {accountDatabase,adminCookie} from './admin_accounts_legacy.js';
import {validateAdminOrigin} from '../admin-security.js';

// Unregistered staging ports. The caller must not expose Admin MFA until the
// corresponding candidate-cookie completion and recovery routes are qualified.
const unix=()=>Math.floor(Date.now()/1000);
const denied=()=>new ApiError(403,'mfa_admin_denied','This authenticator action is unavailable.');
const pending=()=>new ApiError(503,'mfa_operation_unknown','The authenticator result could not be confirmed. Recheck your setup or sign-in before trying again.');
const custody=env=>({...env,DATA_KEY_ID:env.SESSION_KEY_ID??'bff-v1',DATA_ENCRYPTION_KEY:env.SESSION_ENCRYPTION_KEY,DATA_DECRYPTION_KEYS_JSON:env.SESSION_DECRYPTION_KEYS_JSON});
const tokensContext=account=>`bff:${account.auth_session_id}:${account.auth_user_id}`;
const oldCookieContext=account=>`bff-mfa-old:${account.auth_session_id}:${account.auth_user_id}`;
const candidateContext=account=>`bff-mfa-candidate:${account.auth_session_id}:${account.auth_user_id}`;
const intentHash=value=>digest('collect-admin-mfa-intent-v1:'+value);
const validUuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const random=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),v=>v.toString(16).padStart(2,'0')).join('');
function cookieToken(request){
 const values=(request.headers.get('Cookie')??'').split(';').map(x=>x.trim()).filter(x=>x.startsWith('__Host-collect_admin='));
 return values.length===1&&/^__Host-collect_admin=[a-f0-9]{64}$/.test(values[0])?values[0].split('=')[1]:null;
}
function authority(env,account,operation,factor=null){
 return env.DB.prepare('SELECT private.collect_admin_mfa_authorize_v1(?,?,?,?,?,?::uuid) AS result')
  .bind(account.id,account.token_hash,account.origin,account.public_id,operation,factor);
}
function requireResult(value,action){
 if(value?.version!==1||value.authorized!==true||value.action!==action)throw denied();
}
async function authorityResult(work){
 try{return await work();}
 catch(error){if(error?.code==='42501'&&/admin_mfa_denied/.test(String(error?.message??'')))throw denied();throw error;}
}

export function adminMfaPorts(env,account,request){
 const provider={identity:token=>verifyToken(env,token),request:(path,options)=>authRequest(env,path,options)};
 async function guard({fresh,operation,factorId=null}){
  const result=await authorityResult(()=>accountDatabase(env,account,null,{fresh}).DB.batch([authority(env,account,operation,factorId)]));
  requireResult(result?.[0]?.results?.[0]?.result,operation);
 }
 async function claim({factorId,challengeId,verificationId,code}){
  const token=cookieToken(request);if(!token||await digest(token)!==account.token_hash)throw denied();
  const at=unix(),lease=id(),expires=at+25,window=Math.floor(at/60),key=await digest('collect-admin-mfa-verify:'+account.id),intent=await intentHash(verificationId);
  const replayHashes=await adminMfaReplayHashes(custody(env),account.auth_user_id,factorId,code);
  if(!replayHashes.length)throw pending();
  const replayList=replayHashes.map(()=>'?').join(',');
  // GoTrue sees the local BFF's network address. Bound attempts by Admin
  // account in the existing rate table as well, before dispatching a code.
  const budget=env.DB.prepare(`INSERT INTO admin_rate_limits(key_hash,bucket,count,expires_at)
   SELECT ?,?,1,? WHERE EXISTS(SELECT 1 FROM private.bff_sessions
    WHERE token_hash=? AND auth_user_id=?::uuid AND auth_session_id=?::uuid AND refresh_lease IS NULL AND mfa_pending_hash IS NULL)
   ON CONFLICT(key_hash,bucket) DO UPDATE SET count=admin_rate_limits.count+1 RETURNING count`)
   .bind(key,window,(window+6)*60,account.token_hash,account.auth_user_id,account.auth_session_id);
  const statement=env.DB.prepare(`WITH replay AS (
   INSERT INTO admin_rate_limits(key_hash,bucket,count,expires_at)
   SELECT ?,?,1,? WHERE EXISTS(SELECT 1 FROM private.bff_sessions
    WHERE token_hash=? AND auth_user_id=?::uuid AND auth_session_id=?::uuid AND refresh_lease IS NULL AND mfa_pending_hash IS NULL)
    AND NOT EXISTS(SELECT 1 FROM admin_rate_limits WHERE key_hash IN (${replayList}) AND expires_at>?)
    AND coalesce((SELECT sum(count) FROM admin_rate_limits WHERE key_hash=? AND bucket BETWEEN ? AND ?),0)<=5
   ON CONFLICT(key_hash,bucket) DO NOTHING RETURNING key_hash)
   SELECT CASE WHEN EXISTS(SELECT 1 FROM replay) THEN private.collect_admin_mfa_intent_begin_v1(?,?,?,?,?::uuid,?::uuid,?,?,?,?) ELSE NULL END AS result`)
   .bind(replayHashes[0],window,at+120,account.token_hash,account.auth_user_id,account.auth_session_id,
    ...replayHashes,at,key,window-5,window,account.id,account.token_hash,account.origin,account.public_id,factorId,challengeId,intent,lease,expires,account.bff_version);
  const total=env.DB.prepare('SELECT coalesce(sum(count),0) AS total FROM admin_rate_limits WHERE key_hash=? AND bucket BETWEEN ? AND ?')
   .bind(key,window-5,window);
  const replay=env.DB.prepare(`SELECT count(*) AS total FROM admin_rate_limits WHERE key_hash IN (${replayList}) AND expires_at>?`)
   .bind(...replayHashes,at);
  const result=await authorityResult(()=>accountDatabase(env,account).DB.batch([authority(env,account,'verify',factorId),budget,statement,total,replay]));
  requireResult(result?.[0]?.results?.[0]?.result,'verify');
  if(Number(result?.[3]?.results?.[0]?.total)>5)throw new ApiError(429,'rate_limited','Too many attempts. Please try again later.');
  const row=result?.[2]?.results?.[0]?.result;
  if(!row&&Number(result?.[4]?.results?.[0]?.total)>0)throw new ApiError(429,'mfa_code_already_used','Wait for a new authenticator code.');
  if(row?.state!=='claimed'||!Number.isSafeInteger(row?.version)||row.version<1)throw new ApiError(409,'session_refresh_pending','The session is temporarily busy. Try again.');
  return {id:lease,version:row.version};
 }
 async function release({lease,factorId,challengeId,verificationId}){
  // Only a definite provider rejection reaches this port. A stale verifier
  // cannot release a later refresh or another verification's lease.
  const statement=env.DB.prepare('SELECT private.collect_admin_mfa_intent_release_v1(?,?,?,?,?::uuid,?::uuid,?,?,?) AS result')
   .bind(account.id,account.token_hash,account.origin,account.public_id,factorId,challengeId,await intentHash(verificationId),lease.id,lease.version);
  await env.DB.batch([statement]);
 }
 async function stage({verified,tokens,factorId,challengeId,verificationId,lease}){
  const original=cookieToken(request);if(!original||await digest(original)!==account.token_hash)throw denied();
  const candidate=random(),candidateHash=await digest(candidate),encoder=new TextEncoder();
  const tokenCipher=await encrypt(custody(env),encoder.encode(JSON.stringify({access_token:tokens.access_token,refresh_token:tokens.refresh_token})),tokensContext(account));
  const oldCipher=await encrypt(custody(env),encoder.encode(original),oldCookieContext(account));
  const candidateCipher=await encrypt(custody(env),encoder.encode(candidate),candidateContext(account));
  const intent=await intentHash(verificationId);
  env.DB.setClaims(verified.claims);
  try{
   const statement=env.DB.prepare('SELECT private.collect_admin_mfa_intent_prepare_v1(?,?,?,?,?,?,?::uuid,?::uuid,?,?,?,?,?) AS result')
    .bind(account.id,account.token_hash,account.origin,account.public_id,lease.version,lease.id,factorId,challengeId,intent,candidateHash,tokenCipher,oldCipher,candidateCipher);
   const result=await env.DB.batch([statement]);
   if(result?.[0]?.results?.[0]?.result?.state!=='pending')throw pending();
  }catch(error){
   // A lost commit reply may be adopted only from the exact candidate, token
   // ciphertext, factor and version, after the original actor revalidates.
   try{
    const select=env.DB.prepare(`SELECT b.version,b.token_ciphertext,b.mfa_pending_hash,b.mfa_pending_old_cookie_ciphertext,b.mfa_pending_factor,b.refresh_lease,b.mfa_intent_hash,b.mfa_intent_challenge,b.mfa_intent_candidate_ciphertext
     FROM private.bff_sessions b WHERE b.token_hash=? AND b.auth_user_id=?::uuid AND b.auth_session_id=?::uuid`)
     .bind(account.token_hash,account.auth_user_id,account.auth_session_id);
    const result=await accountDatabase(env,account).DB.batch([authority(env,account,'verify',factorId),select]);
    requireResult(result?.[0]?.results?.[0]?.result,'verify');const row=result?.[1]?.results?.[0];
    if(row?.version!==lease.version+1||row.token_ciphertext!==tokenCipher||row.mfa_pending_hash!==candidateHash||
       row.mfa_pending_old_cookie_ciphertext!==oldCipher||row.mfa_pending_factor!==factorId||row.refresh_lease!==null||row.mfa_intent_hash!==intent||
       row.mfa_intent_challenge!==challengeId||row.mfa_intent_candidate_ciphertext!==candidateCipher)throw pending();
   }catch{throw pending();}
  }
  return {ok:true,cookie:adminCookie(candidate,400*24*60*60)};
 }
 return {provider,guard,claim,release,stage};
}

// Used only after a candidate hash and its original live session are proven.
// The decrypted value must be hashed and compared to the original row before
// being returned as a fallback cookie; the caller must not log either value.
export async function decryptAdminMfaOldCookie(env,account,ciphertext){
 const bytes=await decrypt(custody(env),ciphertext,oldCookieContext(account));
 const token=new TextDecoder().decode(bytes);
 if(!/^[a-f0-9]{64}$/.test(token)||await digest(token)!==account.token_hash)throw pending();
 return token;
}

// Called before ordinary session resolution, never as a public token-exchange
// route. Possession of the provisional HttpOnly cookie selects the candidate;
// the current provider session and database authority are then revalidated.
export async function resolveAdminMfaCandidate(env,request,{enabled=false,verify=verifyToken}={}){
 const origin=validateAdminOrigin(request,env),token=cookieToken(request);if(!token)return null;
 const candidateHash=await digest(token);
 const query=`SELECT b.*,s.user_id AS id,s.public_id,s.origin,s.auth_version,s.issued_assurance_level,
  s.issued_mfa_at,s.issued_mfa_factor_id,s.expires_at,a.role,a.email,l.user_id AS principal_id
  FROM private.bff_sessions b JOIN app.admin_sessions s ON s.token_hash=b.token_hash
  JOIN app.admin_users a ON a.id=s.user_id JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  WHERE b.mfa_pending_hash=? AND s.origin=?`;
 const account=await env.DB.prepare(query).bind(candidateHash,origin).first();if(!account)return null;
 let tokens;
 try{tokens=JSON.parse(new TextDecoder().decode(await decrypt(custody(env),account.token_ciphertext,tokensContext(account))));}
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
  return {state:'restore',token:original,cookie:adminCookie(original,400*24*60*60)};
 }catch{
  try{if(await committed())return {state:'complete'};}catch{/* A failed readback never grants authority. */}
  throw pending();
 }
}

// The caller must present the same per-tab intent that initiated this exact
// challenge. The stored provider tokens remain encrypted and never leave BFF.
export async function recoverAdminMfaIntent(env,request,body,{verify=verifyToken,requestAuth=authRequest}={}){
 const origin=validateAdminOrigin(request,env),token=cookieToken(request);
 if(!token||!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).sort().join(',')!=='challenge_id,factor_id,verification_id'||
  !validUuid(body.factor_id)||!validUuid(body.challenge_id)||!/^[a-f0-9]{64}$/.test(body.verification_id??''))throw denied();
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
 let old;try{old=JSON.parse(new TextDecoder().decode(await decrypt(custody(env),account.mfa_intent_old_tokens,tokensContext(account))));}catch{throw pending();}
 let current=old;if(account.mfa_pending_state==='staged'){
  try{current=JSON.parse(new TextDecoder().decode(await decrypt(custody(env),account.token_ciphertext,tokensContext(account))));}catch{throw pending();}
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
  let candidate;try{candidate=new TextDecoder().decode(await decrypt(custody(env),plan.candidate_ciphertext,candidateContext(account)));}catch{throw pending();}
  if(!/^[a-f0-9]{64}$/.test(candidate)||await digest(candidate)!==plan.candidate_hash)throw pending();
  return {ok:true,cookie:adminCookie(candidate,400*24*60*60)};
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
 const origin=validateAdminOrigin(request,env),token=cookieToken(request);
 if(!token||request.headers.has('X-Collect-CSRF')||!body||typeof body!=='object'||Array.isArray(body)||
  Object.keys(body).sort().join(',')!=='challenge_id,factor_id,verification_id'||
  !validUuid(body.factor_id)||!validUuid(body.challenge_id)||!/^[a-f0-9]{64}$/.test(body.verification_id??''))throw denied();
 const hash=await digest(token),intent=await intentHash(body.verification_id);
 const retained=await env.DB.transaction(async sql=>{
  await env.DB.context(sql);await sql.unsafe('SELECT pg_advisory_xact_lock(734636924058501::bigint)');
  const found=await sql.unsafe(`SELECT b.token_hash,b.auth_user_id,b.auth_session_id,b.token_ciphertext FROM private.bff_sessions b
   JOIN app.admin_sessions s ON s.token_hash=b.token_hash WHERE s.origin=$1 AND b.mfa_intent_hash=$2
    AND b.mfa_intent_factor=$3::uuid AND b.mfa_intent_challenge=$4::uuid
    AND (b.token_hash=$5 OR (b.mfa_pending_hash=$5 AND b.mfa_pending_state='staged')) FOR UPDATE OF b,s`,
   [origin,intent,body.factor_id,body.challenge_id,hash]);
  if(found.length!==1)return null;
  await sql.unsafe('DELETE FROM app.admin_sessions WHERE token_hash=$1 AND origin=$2',[found[0].token_hash,origin]);
  return found[0];
 });
 if(!retained)throw new ApiError(409,'mfa_recovery_unavailable','The pending session could not be signed out. Recheck your session.');
 let providerLogout='unconfirmed';
 try{
  const tokens=JSON.parse(new TextDecoder().decode(await decrypt(custody(env),retained.token_ciphertext,tokensContext(retained))));
  await authRequest(env,'/logout?scope=local',{token:tokens.access_token});providerLogout='confirmed';
 }catch{/* The exact local session has already been revoked. */}
 return {state:'revoked',providerLogout,cookie:adminCookie()};
}

// A user can press Sign out before the provisional cookie has been resolved.
// Revoke the exact local session first, including when completion won the
// race. The old CSRF proof is still held by the browser until refresh.
export async function logoutAdminMfaCandidate(env,request){
 const origin=validateAdminOrigin(request,env),token=cookieToken(request);if(!token)return null;
 const candidateHash=await digest(token);
 const account=await env.DB.prepare(`SELECT b.*,s.user_id AS id,s.public_id,s.origin,s.auth_version
  FROM private.bff_sessions b JOIN app.admin_sessions s ON s.token_hash=b.token_hash
  WHERE b.mfa_pending_hash=? AND s.origin=?`).bind(candidateHash,origin).first();
 if(!account)return null;
 const original=await decryptAdminMfaOldCookie(env,account,account.mfa_pending_old_cookie_ciphertext);
 const supplied=request.headers.get('X-Collect-CSRF');
 if(supplied!==await digest('collect-admin-csrf:'+original)&&supplied!==await digest('collect-admin-csrf:'+token))throw denied();
 const retained=await env.DB.transaction(async sql=>{
  await env.DB.context(sql);await sql.unsafe('SELECT pg_advisory_xact_lock(734636924058501::bigint)');
  const found=await sql.unsafe(`SELECT b.token_hash,b.auth_user_id,b.auth_session_id,b.token_ciphertext FROM private.bff_sessions b
   JOIN app.admin_sessions s ON s.token_hash=b.token_hash WHERE s.origin=$1 AND s.public_id=$2
    AND b.auth_user_id=$3::uuid AND b.auth_session_id=$4::uuid
    AND ((b.token_hash=$5 AND b.mfa_pending_hash=$6) OR (b.token_hash=$6 AND b.mfa_pending_hash IS NULL))
   FOR UPDATE OF b,s`,[origin,account.public_id,account.auth_user_id,account.auth_session_id,account.token_hash,candidateHash]);
  if(found.length!==1)return null;
  await sql.unsafe('DELETE FROM app.admin_sessions WHERE token_hash=$1 AND origin=$2',[found[0].token_hash,origin]);
  return found[0];
 });
 if(!retained)return null;
 let providerLogout='unconfirmed';
 try{
  const tokens=JSON.parse(new TextDecoder().decode(await decrypt(custody(env),retained.token_ciphertext,tokensContext(retained))));
  await authRequest(env,'/logout?scope=local',{token:tokens.access_token});providerLogout='confirmed';
 }catch{/* Local logout already committed. */}
 return {state:'revoked',providerLogout,cookie:adminCookie()};
}
