import {ApiError,digest,id} from './core.js';
import {authRequest,verifyToken} from '../auth-http.js';
import {encrypt,adminMfaReplayHashes} from './encryption.js';
import {accountDatabase,adminCookie} from './admin_accounts_legacy.js';
import {adminCookieToken} from '../admin-security.js';
import {adminMfaDenied as denied,adminMfaPending as pending} from './admin_account_support/errors.js';
import {adminTokenCustody,encryptAdminTokens,newAdminCookieToken,adminMfaIntentHash as intentHash,
 adminMfaOldCookieContext as oldCookieContext,adminMfaCandidateContext as candidateContext,ADMIN_COOKIE_SECONDS} from './admin_bff_tokens.js';

const unix=()=>Math.floor(Date.now()/1000);

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
  const token=adminCookieToken(request);if(!token||await digest(token)!==account.token_hash)throw denied();
  const at=unix(),lease=id(),expires=at+25,window=Math.floor(at/60),key=await digest('collect-admin-mfa-verify:'+account.id),intent=await intentHash(verificationId);
  const replayHashes=await adminMfaReplayHashes(adminTokenCustody(env),account.auth_user_id,factorId,code);
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
  const original=adminCookieToken(request);if(!original||await digest(original)!==account.token_hash)throw denied();
  const candidate=newAdminCookieToken(),candidateHash=await digest(candidate),encoder=new TextEncoder();
  const tokenCipher=await encryptAdminTokens(env,account,tokens);
  const oldCipher=await encrypt(adminTokenCustody(env),encoder.encode(original),oldCookieContext(account));
  const candidateCipher=await encrypt(adminTokenCustody(env),encoder.encode(candidate),candidateContext(account));
  const intent=await intentHash(verificationId);
  env.DB.setClaims(verified.claims);
  try{
   const statement=env.DB.prepare('SELECT private.collect_admin_mfa_intent_prepare_v1(?,?,?,?,?,?,?::uuid,?::uuid,?,?,?,?,?) AS result')
    .bind(account.id,account.token_hash,account.origin,account.public_id,lease.version,lease.id,factorId,challengeId,intent,candidateHash,tokenCipher,oldCipher,candidateCipher);
   const result=await env.DB.batch([statement]);
   if(result?.[0]?.results?.[0]?.result?.state!=='pending')throw pending();
  }catch{
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
  return {ok:true,cookie:adminCookie(candidate,ADMIN_COOKIE_SECONDS)};
 }
 return {provider,guard,claim,release,stage};
}
