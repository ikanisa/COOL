import {ApiError,json,readJson,uuid} from './core.js';
import {handleAuth,requireSession} from './auth.js';
import {OWNER_EMAIL,digest,normalizeEmail,passwordHash,passwordMatches,randomToken,validPassword} from './admin_account_support/security.js';
import {buildAccountEmail,buildAdminInvitationEmail,buildAdminOtpEmail} from './admin_account_support/emails.js';
import {sendTransactionalEmail} from './email_delivery.js';

const PREFIX='/api/admin', SESSION_SECONDS=28800, unix=()=>Math.floor(Date.now()/1000);
const iso=v=>v==null?null:new Date(v*1000).toISOString();
const sql=(env,query,...args)=>env.DB.prepare(query).bind(...args);
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const expired=()=>fail(401,'unauthenticated','Your session has ended. Sign in again.');
const notApproved=()=>fail(403,'admin_access_not_approved','This email does not have Admin access. Contact the super admin to be added.');
const invalidOtp=()=>fail(401,'invalid_credentials','The sign-in code is invalid or expired. Request a new code.');
const OTP_SECONDS=300,OTP_COOLDOWN=60;
const encoder=new TextEncoder();

export function validateAdminOrigin(request,env) {
 if(!env.DB?.prepare||!env.ADMIN_ORIGIN)fail(503,'service_unavailable','Account service is not configured.');
 let expected;try{expected=new URL(env.ADMIN_ORIGIN);}catch{fail(503,'service_unavailable','Account service is not configured.');}
 if(expected.origin!==env.ADMIN_ORIGIN||expected.protocol!=='https:'||expected.username||expected.password)
  fail(503,'service_unavailable','Account service is not configured.');
 const allowed=env.ADMIN_ORIGINS===undefined?[expected.origin]:env.ADMIN_ORIGINS.split(',').map(v=>v.trim());
 if(!allowed.length||allowed.some(v=>{try{const url=new URL(v);return url.origin!==v||url.protocol!=='https:'||url.username||url.password;}catch{return true;}}))
  fail(503,'service_unavailable','Account service is not configured.');
 const url=new URL(request.url),origin=request.headers.get('Origin');
 if(!allowed.includes(url.origin)||url.protocol!=='https:'||request.headers.get('Sec-Fetch-Site')==='cross-site'
   ||(origin&&origin!==url.origin)||(request.method!=='GET'&&origin!==url.origin))
  fail(403,'origin_rejected','Open the configured admin website to continue.');
 return url.origin;
}
export function adminCookie(token='',age=0){return `__Host-collect_admin=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${age}; Secure`;}
async function body(request,allowed,max=4096){const value=await readJson(request,max);if(Object.keys(value).some(k=>!allowed.includes(k)))fail(400,'invalid_request','Request has unsupported fields.');return value;}
const email=value=>{const result=normalizeEmail(value);if(!result)fail(400,'invalid_email','Enter a valid email address.');return result;};
const password=value=>{if(!validPassword(value))fail(400,'invalid_password','Use a password of 12 to 128 characters.');return value;};
const name=value=>{if(typeof value!=='string'||value.trim().length>120||/[\u0000-\u001f\u007f]/.test(value)||(value.trim()&&value.trim().length<2))fail(400,'invalid_name','Enter a recorded full name.');return value.trim();};

async function limited(env,key,max,window){const timestamp=unix();const row=await sql(env,`INSERT INTO admin_rate_limits(key_hash,bucket,count,expires_at) VALUES(?,?,1,?)
 ON CONFLICT(key_hash,bucket) DO UPDATE SET count=count+1 RETURNING count`,await digest(key),Math.floor(timestamp/window),timestamp+window*2).first();return row.count>max;}
async function rate(request,env,action,max=20,window=900){if(await limited(env,`${action}:ip:${request.headers.get('CF-Connecting-IP')||'unknown'}`,max,window))fail(429,'rate_limited','Too many attempts. Please try again later.');}

export async function adminAccountSession(request,env,required=true){
 const tokens=(request.headers.get('Cookie')||'').split(';').map(v=>v.trim()).filter(v=>v.startsWith('__Host-collect_admin='));
 if(tokens.length!==1||!/^__Host-collect_admin=[a-f0-9]{64}$/.test(tokens[0])){if(required)expired();return null;}
 const hash=await digest(tokens[0].slice('__Host-collect_admin='.length));
 const result=await sql(env,`SELECT a.*,s.public_id,s.token_hash,s.expires_at,s.auth_session_id,s.origin,
 s.issued_assurance_level,s.issued_mfa_at,s.issued_mfa_factor_id,l.user_id AS principal_id,
 ss.auth_at,ss.assurance_level,ss.mfa_at,ss.mfa_factor_id FROM admin_sessions s
 JOIN admin_users a ON a.id=s.user_id JOIN admin_principal_links l ON l.admin_user_id=a.id
 JOIN users u ON u.id=l.user_id JOIN auth_sessions ss ON ss.id=s.auth_session_id AND ss.user_id=u.id
 WHERE s.token_hash=? AND s.origin=? AND s.expires_at>? AND s.auth_version=a.auth_version AND a.status='active'
 AND u.access_status='active' AND ss.surface='admin' AND ss.revoked_at IS NULL AND ss.expires_at>?
 AND (s.issued_assurance_level=1 OR (s.issued_assurance_level=ss.assurance_level AND s.issued_mfa_at=ss.mfa_at
 AND s.issued_mfa_factor_id=ss.mfa_factor_id AND EXISTS(SELECT 1 FROM auth_mfa_factors f WHERE f.id=ss.mfa_factor_id AND f.user_id=u.id AND f.status='verified')))`,hash,new URL(request.url).origin,unix(),unix()).first();
 if(!result){if(required)expired();return null;}
 const grants=await sql(env,`SELECT c.permission FROM admin_account_role_capabilities c JOIN admin_grants g ON g.permission=c.permission
 WHERE c.role=? AND g.user_id=? ORDER BY c.permission`,result.role,result.principal_id).all();
 result.permissions=grants.results.map(v=>v.permission);return result;
}
export const adminPublicUser=user=>user?{id:user.id,email:user.email,role:user.role,sessionId:user.public_id,
 expiresAt:iso(user.expires_at),permissions:user.permissions,assuranceLevel:user.issued_assurance_level,
 mfaAt:iso(user.issued_mfa_at),principalId:user.principal_id,financialModel:'canonical_evidence_ledger'}:null;

// The original cookie proof is checked in the SAME D1 batch as all delegated
// writes. An intervening account/password/role/session change cannot authorize a
// canonical-domain mutation through a previously resolved actor.
export function accountGuard(env,account,permission=null,{owner=false,mfa=false,fresh=false}={}){
 const guardId=crypto.randomUUID();
 const statement=sql(env,`INSERT INTO admin_account_guards(id,passed) SELECT ?,(CASE WHEN EXISTS(
 SELECT 1 FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id JOIN admin_principal_links l ON l.admin_user_id=a.id
 JOIN users u ON u.id=l.user_id JOIN auth_sessions ss ON ss.id=s.auth_session_id AND ss.user_id=u.id
 WHERE s.token_hash=? AND s.origin=? AND s.public_id=? AND a.id=? AND a.auth_version=? AND s.auth_version=a.auth_version
 AND a.status='active' AND a.role=? AND l.user_id=? AND ss.id=? AND u.access_status='active'
 AND s.expires_at>unixepoch() AND ss.expires_at>unixepoch() AND ss.revoked_at IS NULL AND ss.surface='admin'
 AND s.issued_assurance_level=? AND s.issued_mfa_at IS ? AND s.issued_mfa_factor_id IS ?
 AND (s.issued_assurance_level=1 OR (ss.assurance_level=2 AND ss.mfa_at=s.issued_mfa_at AND ss.mfa_factor_id=s.issued_mfa_factor_id
 AND EXISTS(SELECT 1 FROM auth_mfa_factors f WHERE f.id=ss.mfa_factor_id AND f.user_id=u.id AND f.status='verified')))
 AND (? IS NULL OR EXISTS(SELECT 1 FROM admin_grants g JOIN admin_account_role_capabilities c ON c.permission=g.permission
 WHERE g.user_id=u.id AND g.permission=? AND c.role=a.role))
 AND (?=0 OR (a.role='owner' AND a.email=?))
 AND (?=0 OR s.issued_assurance_level=2)
 AND (?=0 OR COALESCE(s.issued_mfa_at,ss.auth_at)>=unixepoch()-300)
 ) THEN 1 ELSE 0 END)`,guardId,account.token_hash,account.origin,account.public_id,account.id,account.auth_version,account.role,account.principal_id,
 account.auth_session_id,account.issued_assurance_level,account.issued_mfa_at,account.issued_mfa_factor_id,permission,permission,
 Number(owner),OWNER_EMAIL,Number(mfa),Number(fresh));
 return {statement,remove:sql(env,'DELETE FROM admin_account_guards WHERE id=?',guardId)};
}
export function accountDatabase(env,account,permission=null,options={}){
 const wrap=db=>new Proxy(db,{get(target,key){
  if(key==='batch')return async statements=>{const gate=accountGuard({...env,DB:target},account,permission,options);
   try{return(await target.batch([gate.statement,...statements,gate.remove])).slice(1,-1);}
   catch(error){if(String(error).match(/admin_account_guards|admin_account_authority/))fail(403,'admin_access_changed','Your account access changed. Sign in and verify again.');throw error;}};
  // D1DatabaseSession has no withSession method. Preserve that capability
  // boundary so nested auth reads keep the selected, guarded session.
  if(key==='withSession')return typeof target.withSession==='function'?(...args)=>wrap(target.withSession(...args)):undefined;
  const value=Reflect.get(target,key);return typeof value==='function'?value.bind(target):value;
 }});return {...env,DB:wrap(env.DB)};
}
function base64(bytes){let raw='';for(const value of new Uint8Array(bytes))raw+=String.fromCharCode(value);return btoa(raw).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');}
export async function adminInternalRequest(request,env,account,path,method=request.method,value=null){
 if(typeof env.AUTH_JWT_SECRET!=='string'||env.AUTH_JWT_SECRET.length<32||typeof env.AUTH_ISSUER!=='string')fail(503,'auth_configuration_missing','Account authorization is unavailable.');
 const current=unix(),claims={iss:env.AUTH_ISSUER,aud:env.AUTH_AUDIENCE??'authenticated',sub:account.principal_id,session_id:account.auth_session_id,
 iat:current,exp:Math.min(current+900,account.expires_at),auth_time:account.auth_at,role:'authenticated',
 aal:account.issued_assurance_level===2?'aal2':'aal1',...(account.issued_assurance_level===2?{mfa_at:account.issued_mfa_at,mfa_factor_id:account.issued_mfa_factor_id}:{})};
 const encoder=new TextEncoder(),header=base64(encoder.encode(JSON.stringify({alg:'HS256',typ:'JWT'}))),payload=base64(encoder.encode(JSON.stringify(claims)));
 const key=await crypto.subtle.importKey('raw',encoder.encode(env.AUTH_JWT_SECRET),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 const token=`${header}.${payload}.${base64(await crypto.subtle.sign('HMAC',key,encoder.encode(`${header}.${payload}`)))}`;
 const headers=new Headers(request.headers);headers.delete('Cookie');headers.set('Authorization',`Bearer ${token}`);
 headers.delete('Content-Length');headers.set('Content-Type','application/json');
 return new Request(new URL(path,request.url),{method,headers,...(['GET','HEAD'].includes(method)?{}:{body:JSON.stringify(value??{})})});
}
export async function adminCanonicalActor(request,env,account,permission=null){
 if(permission&&!account.permissions.includes(permission))fail(403,'permission_required','This action is unavailable for this account.');
 const actor=await requireSession(await adminInternalRequest(request,env,account,'/v1/auth/user','GET'),env);
 // Account roles cap authority even when the principal has other manual grants.
 actor.permissions=new Set([...actor.permissions].filter(p=>account.permissions.includes(p)));return actor;
}
async function ownerBatch(env,user,queries){
 if(user.role!=='owner'||user.email!==OWNER_EMAIL)fail(403,'owner_required','Only the main administrator can manage team access.');
 if(user.issued_assurance_level!==2)fail(403,'mfa_required','Complete two-step verification before managing team access.');
 return accountDatabase(env,user,'admin_users.manage',{owner:true,mfa:true,fresh:true}).DB.batch(queries);
}

async function sendChallenge(env,user,kind,actor=null,auditAction=null){
 const timestamp=unix(),token=randomToken(),tokenHash=await digest(token),eventId=crypto.randomUUID();
 const queries=[sql(env,`UPDATE admin_users SET challenge_version=challenge_version+1,updated_at=? WHERE id=? AND status=? AND auth_version=? RETURNING challenge_version`,timestamp,user.id,user.status,user.auth_version),
 sql(env,`INSERT INTO admin_challenges(token_hash,user_id,kind,auth_version,challenge_version,created_at,expires_at)
 SELECT ?,id,?,auth_version,challenge_version,?,? FROM admin_users WHERE id=? AND status=? AND auth_version=?`,tokenHash,kind,timestamp,timestamp+(kind==='invite'?86400:1800),user.id,user.status,user.auth_version),
 sql(env,`INSERT INTO admin_email_events(id,user_id,kind,status,created_at,updated_at) SELECT ?,user_id,kind,'pending',?,? FROM admin_challenges WHERE token_hash=?`,eventId,timestamp,timestamp,tokenHash)];
 if(actor&&auditAction)queries.push(sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) SELECT ?,?,user_id,?,? FROM admin_challenges WHERE token_hash=?`,crypto.randomUUID(),actor.id,auditAction,timestamp,tokenHash));
 const result=actor?await ownerBatch(env,actor,queries):await env.DB.batch(queries);
 if(!result[0].meta.changes)fail(409,'account_changed','The account changed. Refresh and try again.');
 const link=`${env.ADMIN_ORIGIN}/#/admin/setup?token=${token}&invite=${kind==='invite'}`;
 try{
  const accepted=await sendTransactionalEmail(env,{to:user.email,...buildAccountEmail({kind,link})});
  await env.DB.batch([sql(env,`UPDATE admin_challenges SET delivery_status='accepted' WHERE token_hash=?`,tokenHash),sql(env,`UPDATE admin_email_events SET status='accepted',provider_message_id=?,updated_at=? WHERE id=?`,accepted.messageId.slice(0,256),unix(),eventId)]);
  return {emailStatus:'accepted'};
 }catch{
  await env.DB.batch([sql(env,`UPDATE admin_challenges SET delivery_status='failed',used_at=? WHERE token_hash=?`,unix(),tokenHash),sql(env,`UPDATE admin_email_events SET status='failed',updated_at=? WHERE id=?`,unix(),eventId)]);
  fail(503,'email_unavailable','Email delivery could not be confirmed. The account remains pending; try resending the invitation.');
 }
}

async function sendInvitation(env,user,actor,auditAction=null){
 const timestamp=unix(),eventId=crypto.randomUUID();
 const queries=[sql(env,`INSERT INTO admin_email_events(id,user_id,kind,status,created_at,updated_at)
  SELECT ?,a.id,'invite','pending',?,? FROM admin_users a JOIN admin_principal_links l ON l.admin_user_id=a.id
  JOIN users u ON u.id=l.user_id WHERE a.id=? AND a.status='invited' AND a.auth_version=? AND u.access_status='active'`,
  eventId,timestamp,timestamp,user.id,user.auth_version)];
 if(auditAction)queries.push(sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at)
  SELECT ?,?,user_id,?,? FROM admin_email_events WHERE id=?`,crypto.randomUUID(),actor.id,auditAction,timestamp,eventId));
 const result=await ownerBatch(env,actor,queries);
 if(result[0].meta.changes!==1)fail(409,'account_changed','The account changed. Refresh and try again.');
 try{
  const accepted=await sendTransactionalEmail(env,{to:user.email,...buildAdminInvitationEmail({link:`${env.ADMIN_ORIGIN}/#/admin/login`})});
  await sql(env,`UPDATE admin_email_events SET status='accepted',provider_message_id=?,updated_at=? WHERE id=?`,accepted.messageId,unix(),eventId).run();
  return {emailStatus:'accepted'};
 }catch{
  await sql(env,`UPDATE admin_email_events SET status='failed',updated_at=? WHERE id=?`,unix(),eventId).run();
  fail(503,'email_unavailable','Email delivery could not be confirmed. The account remains pending; try resending the invitation.');
 }
}

// Codes are keyed to the recipient and exact approved account/principal/origin/version.
// The six-digit space is never protected by an offline-guessable plain digest.
function otpCode(){const values=new Uint32Array(1);do{crypto.getRandomValues(values);}while(values[0]>=4294000000);return (values[0]%1000000).toString().padStart(6,'0');}
async function otpKey(env,usage){
 if(typeof env.AUTH_TOKEN_HASH_SECRET!=='string'||encoder.encode(env.AUTH_TOKEN_HASH_SECRET).length<32||env.AUTH_TOKEN_HASH_SECRET.length>4096)
  fail(503,'auth_configuration_missing','Account sign-in is unavailable.');
 return crypto.subtle.importKey('raw',encoder.encode(env.AUTH_TOKEN_HASH_SECRET),{name:'HMAC',hash:'SHA-256'},false,[usage]);
}
const otpMessage=(challenge,code,recipient)=>`collect-admin-email-otp-v2:${challenge.id}:${challenge.user_id}:${challenge.principal_user_id}:${challenge.origin}:${challenge.role}:${challenge.auth_version}:${challenge.challenge_version}:${challenge.account_status}:${recipient}:${code}`;
const otpHex=bytes=>[...new Uint8Array(bytes)].map(value=>value.toString(16).padStart(2,'0')).join('');
async function otpHash(env,challenge,code,recipient){return otpHex(await crypto.subtle.sign('HMAC',await otpKey(env,'sign'),encoder.encode(otpMessage(challenge,code,recipient))));}
async function otpMatches(env,challenge,code,recipient){return crypto.subtle.verify('HMAC',await otpKey(env,'verify'),Uint8Array.from(challenge.code_hash.match(/../g),value=>parseInt(value,16)),encoder.encode(otpMessage(challenge,code,recipient)));}
const approvedAccount=`SELECT a.*,l.user_id AS principal_user_id FROM admin_users a
 JOIN admin_principal_links l ON l.admin_user_id=a.id JOIN users u ON u.id=l.user_id
 WHERE a.email=? AND a.status IN ('invited','active') AND u.access_status='active'
 AND (a.status='invited' OR EXISTS(SELECT 1 FROM admin_grants g JOIN admin_account_role_capabilities c ON c.permission=g.permission
 WHERE g.user_id=l.user_id AND c.role=a.role))`;

async function requestAdminOtp(request,env){
 await rate(request,env,'email-otp',30,900);const data=await body(request,['email']),target=email(data.email);
 if(await limited(env,`email-otp:email:${target}`,5,900))fail(429,'rate_limited','Too many attempts. Please try again later.');
 const user=await sql(env,approvedAccount,target).first();if(!user)notApproved();
 const timestamp=unix(),challenge={id:crypto.randomUUID(),user_id:user.id,principal_user_id:user.principal_user_id,
  origin:new URL(request.url).origin,role:user.role,auth_version:user.auth_version,challenge_version:user.challenge_version,account_status:user.status};
 const code=otpCode(),hash=await otpHash(env,challenge,code,target),eventId=crypto.randomUUID(),guardId=crypto.randomUUID();
 try{await env.DB.batch([
  sql(env,`INSERT INTO admin_account_guards(id,passed) SELECT ?,(CASE WHEN EXISTS(
   SELECT 1 FROM (${approvedAccount}) WHERE id=? AND principal_user_id=? AND role=? AND auth_version=? AND challenge_version=? AND status=?
   ) THEN 1 ELSE 0 END)`,guardId,target,user.id,user.principal_user_id,user.role,user.auth_version,user.challenge_version,user.status),
  sql(env,`UPDATE admin_email_otp_challenges SET delivery_status='superseded' WHERE user_id=? AND used_at IS NULL
   AND delivery_status IN ('pending','accepted','unknown')`,user.id),
  sql(env,`INSERT INTO admin_email_otp_challenges(id,user_id,principal_user_id,origin,role,auth_version,challenge_version,account_status,code_hash,created_at,expires_at)
   VALUES(?,?,?,?,?,?,?,?,?,?,?)`,challenge.id,user.id,user.principal_user_id,challenge.origin,user.role,user.auth_version,user.challenge_version,user.status,hash,timestamp,timestamp+OTP_SECONDS),
  sql(env,`INSERT INTO admin_email_events(id,user_id,kind,status,created_at,updated_at) VALUES(?,?,'sign_in','pending',?,?)`,eventId,user.id,timestamp,timestamp),
  sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) VALUES(?,NULL,?,'email_otp_requested',?)`,crypto.randomUUID(),user.id,timestamp),
  sql(env,'DELETE FROM admin_account_guards WHERE id=?',guardId)]);
 }catch(error){
  if(String(error).includes('admin_email_otp_cooldown'))fail(429,'rate_limited','Wait 60 seconds before requesting another code.');
  if(String(error).match(/admin_account_guards|admin_account_authority/))notApproved();throw error;
 }
 try{
  const accepted=await sendTransactionalEmail(env,{to:user.email,...buildAdminOtpEmail({code})});
  await env.DB.batch([
   sql(env,`UPDATE admin_email_otp_challenges SET delivery_status='accepted' WHERE id=? AND delivery_status='pending'`,challenge.id),
   sql(env,`UPDATE admin_email_events SET status='accepted',provider_message_id=?,updated_at=? WHERE id=?`,accepted.messageId,unix(),eventId)]);
  return json({accepted:true,challenge_id:challenge.id,expires_in:OTP_SECONDS,retry_after:OTP_COOLDOWN,emailStatus:'accepted'},202);
 }catch{
  // A lost provider acknowledgement can still have delivered the original code.
  await env.DB.batch([
   sql(env,`UPDATE admin_email_otp_challenges SET delivery_status='unknown' WHERE id=? AND delivery_status='pending'`,challenge.id),
   sql(env,`UPDATE admin_email_events SET status='failed',updated_at=? WHERE id=?`,unix(),eventId)]);
  return json({error:{code:'email_delivery_unknown',message:'Email delivery could not be confirmed. If a code arrives, enter it before requesting another.'},
   challenge_id:challenge.id,expires_in:OTP_SECONDS,retry_after:OTP_COOLDOWN},503);
 }
}

async function verifyAdminOtp(request,env){
 await rate(request,env,'email-verify',60,900);const data=await body(request,['email','challenge_id','code']),target=email(data.email);
 if(await limited(env,`email-verify:email:${target}`,20,900))fail(429,'rate_limited','Too many attempts. Please try again later.');
 const id=uuid(data.challenge_id,'challenge_id');if(typeof data.code!=='string'||!/^[0-9]{6}$/.test(data.code))invalidOtp();
 const origin=new URL(request.url).origin,challenge=await sql(env,`UPDATE admin_email_otp_challenges SET attempts=attempts+1
  WHERE id=? AND origin=? AND used_at IS NULL AND attempts<5 AND expires_at>?
  AND delivery_status IN ('accepted','unknown') AND EXISTS(SELECT 1 FROM admin_users a WHERE a.id=user_id AND a.email=?) RETURNING *`,id,origin,unix(),target).first();
 if(!challenge||!await otpMatches(env,challenge,data.code,target))invalidOtp();
 const timestamp=unix(),token=randomToken(),hash=await digest(token),publicId=crypto.randomUUID(),sessionId=crypto.randomUUID(),guardId=crypto.randomUUID();
 try{await env.DB.batch([
  sql(env,`INSERT INTO admin_account_guards(id,passed) SELECT ?,(CASE WHEN EXISTS(
   SELECT 1 FROM admin_email_otp_challenges c JOIN admin_users a ON a.id=c.user_id
   JOIN admin_principal_links l ON l.admin_user_id=a.id JOIN users u ON u.id=l.user_id
   WHERE c.id=? AND c.code_hash=? AND c.origin=? AND c.used_at IS NULL AND c.attempts<=5 AND c.expires_at>unixepoch()
   AND c.delivery_status IN ('accepted','unknown') AND a.email=? AND a.status=c.account_status AND a.role=c.role
   AND a.auth_version=c.auth_version AND a.challenge_version=c.challenge_version AND l.user_id=c.principal_user_id
   AND u.access_status='active' AND (a.status='invited' OR EXISTS(SELECT 1 FROM admin_grants g
    JOIN admin_account_role_capabilities cap ON cap.permission=g.permission WHERE g.user_id=u.id AND cap.role=a.role))
  ) THEN 1 ELSE 0 END)`,guardId,id,challenge.code_hash,origin,target),
  sql(env,`UPDATE admin_email_otp_challenges SET used_at=?,consumed_session_id=? WHERE id=? AND used_at IS NULL`,timestamp,sessionId,id),
  // The existing authority trigger activates role grants and revokes old sessions
  // before this batch creates the new AAL1 session. This sentinel is deliberately
  // rejected by passwordMatches; no password is generated or sent to the person.
  sql(env,`UPDATE admin_users SET status='active',password_hash=COALESCE(password_hash,'email-otp-only'),
   auth_version=auth_version+1,accepted_at=COALESCE(accepted_at,?),updated_at=?
   WHERE id=? AND status='invited'`,timestamp,timestamp,challenge.user_id),
  sql(env,`INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
   SELECT ?,principal_user_id,'admin',?,?,? FROM admin_email_otp_challenges WHERE id=? AND consumed_session_id=?`,sessionId,timestamp,timestamp,timestamp+SESSION_SECONDS,id,sessionId),
  sql(env,`INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
   SELECT ?,?,a.id,a.auth_version,?,?,?,? FROM admin_users a WHERE a.id=?`,hash,publicId,sessionId,origin,timestamp,timestamp+SESSION_SECONDS,challenge.user_id),
  sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) VALUES(?,?,?,'email_otp_signed_in',?)`,crypto.randomUUID(),challenge.user_id,challenge.user_id,timestamp),
  sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at)
   SELECT ?,user_id,user_id,'invitation_accepted',? FROM admin_email_otp_challenges WHERE id=? AND account_status='invited'`,crypto.randomUUID(),timestamp,id),
  sql(env,'DELETE FROM admin_account_guards WHERE id=?',guardId)]);
 }catch(error){if(String(error).match(/admin_account_guards|admin_account_authority|admin_email_otp_already_consumed/))invalidOtp();throw error;}
 const account=await adminAccountSession(new Request(request.url,{headers:{Cookie:`__Host-collect_admin=${token}`}}),env);
 return json({user:adminPublicUser(account),expiresAt:iso(timestamp+SESSION_SECONDS)},200,{'Set-Cookie':adminCookie(token,SESSION_SECONDS)});
}

async function accountRoute(request,env,ctx,path){
 if(request.method==='GET'&&path==='/auth/session'){const account=await adminAccountSession(request,env,false);return json({user:adminPublicUser(account),expiresAt:iso(account?.expires_at),ownerEmail:OWNER_EMAIL});}
 if(request.method==='GET'&&path==='/team'){
  const user=await adminAccountSession(request,env);if(!user.permissions.includes('admin_users.read'))fail(403,'permission_required','Team access is unavailable.');
  const [result,roles,authority]=await accountDatabase(env,user,'admin_users.read').DB.batch([sql(env,`SELECT a.id,a.email,a.role,a.status,a.display_name,a.created_at,a.invited_at,a.accepted_at,
  (SELECT e.status FROM admin_email_events e WHERE e.user_id=a.id ORDER BY e.created_at DESC,e.id DESC LIMIT 1) AS email_status FROM admin_users a ORDER BY CASE WHEN role='owner' THEN 0 ELSE 1 END,email`),
  sql(env,'SELECT role,permission FROM admin_account_role_capabilities ORDER BY role,permission'),
  sql(env,`SELECT (CASE WHEN a.role='owner' AND a.email=? AND s.issued_assurance_level=2
   AND s.issued_mfa_at<=unixepoch() AND s.issued_mfa_at>=unixepoch()-300
   AND EXISTS(SELECT 1 FROM admin_grants WHERE user_id=l.user_id AND permission='admin_users.manage')
   THEN 1 ELSE 0 END) AS can_manage FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id
   JOIN admin_principal_links l ON l.admin_user_id=a.id WHERE s.token_hash=?`,OWNER_EMAIL,user.token_hash)]);
  const permissionsByRole={owner:[],admin:[],staff:[]};for(const row of roles.results)permissionsByRole[row.role].push(row.permission);
  return json({currentEmail:user.email,canManage:authority.results[0]?.can_manage===1,permissionsByRole,
   members:result.results.map(v=>({id:v.id,email:v.email,role:v.role,status:v.status,displayName:v.display_name,
   createdAt:iso(v.created_at),invitedAt:iso(v.invited_at),acceptedAt:iso(v.accepted_at),emailStatus:v.email_status}))});
 }
 if(path.startsWith('/auth/mfa/')||path==='/auth/user'){
  const account=await adminAccountSession(request,env),subpath=path==='/auth/user'?'/v1/auth/user':`/v1${path}`;
  const data=request.method==='GET'?null:await readJson(request,8192);
  const scoped=accountDatabase(env,account);const response=await handleAuth(await adminInternalRequest(request,env,account,subpath,request.method,data),scoped);
  if(!response)fail(404,'not_found','This verification endpoint does not exist.');
  if(path==='/auth/mfa/enroll'&&response.status===200){
   // Cookie accounts have their own approved email; canonical operator
   // principals deliberately need no member email/phone. Adapt only the
   // authenticator's display label using this authenticated account, retaining
   // the generated secret, issuer, algorithm and strict client URI contract.
   const enrolled=await response.json(),uri=new URL(enrolled.totp.uri);
   uri.pathname=`/${encodeURIComponent(`Collect:${account.email}`)}`;
   return json({...enrolled,totp:{...enrolled.totp,uri:uri.href}});
  }
  if(path!=='/auth/mfa/verify'||response.status!==200)return response;
  // The existing cookie is an AAL snapshot. Rotate its secret after REAL TOTP
  // verification; possession of the pre-verification cookie never becomes AAL2.
  const verified=await response.json(),token=randomToken(),hash=await digest(token);
  const [rotated]=await scoped.DB.batch([sql(env,`UPDATE admin_sessions SET token_hash=?,issued_assurance_level=2,
   issued_mfa_at=(SELECT mfa_at FROM auth_sessions WHERE id=auth_session_id),issued_mfa_factor_id=(SELECT mfa_factor_id FROM auth_sessions WHERE id=auth_session_id)
   WHERE token_hash=? AND auth_session_id=? RETURNING token_hash`,hash,account.token_hash,account.auth_session_id)]);
  if(rotated.meta.changes!==1)expired();
  // JWT/refresh material is internal server transport and is never returned to
  // the cookie frontend or recorded in Admin receipts/logs.
  void verified;const current=await adminAccountSession(new Request(request.url,{headers:{Cookie:`__Host-collect_admin=${token}`}}),env);
  return json({ok:true,user:adminPublicUser(current)},200,{'Set-Cookie':adminCookie(token,Math.max(0,current.expires_at-unix()))});
 }
 if(request.method!=='POST')fail(405,'method_not_allowed','This request method is not supported.');
 if(path==='/auth/otp')return requestAdminOtp(request,env);
 if(path==='/auth/verify')return verifyAdminOtp(request,env);
 if(path==='/auth/login'){
  await rate(request,env,'login',30);const data=await body(request,['email','password']);const target=email(data.email);
  if(typeof data.password!=='string'||data.password.length>512)fail(401,'invalid_credentials','Email or password is incorrect.');
  if(await limited(env,`login:email:${target}`,10,900))fail(429,'rate_limited','Too many attempts. Please try again later.');
  const user=await sql(env,'SELECT * FROM admin_users WHERE email=?',target).first();
  const matches=await passwordMatches(data.password,user?.status==='active'?user.password_hash:null);
  if(!user||!matches||user.status!=='active')fail(401,'invalid_credentials','Email or password is incorrect.');
  const timestamp=unix(),token=randomToken(),hash=await digest(token),publicId=crypto.randomUUID(),sessionId=crypto.randomUUID(),guardId=crypto.randomUUID();
  try{await env.DB.batch([
   sql(env,`INSERT INTO admin_account_guards(id,passed) SELECT ?,(CASE WHEN EXISTS(SELECT 1 FROM admin_users a JOIN admin_principal_links l ON l.admin_user_id=a.id
    JOIN users u ON u.id=l.user_id WHERE a.id=? AND a.status='active' AND a.auth_version=? AND a.password_hash=? AND u.access_status='active'
    AND EXISTS(SELECT 1 FROM admin_grants WHERE user_id=u.id)) THEN 1 ELSE 0 END)`,guardId,user.id,user.auth_version,user.password_hash),
   sql(env,`INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) SELECT ?,l.user_id,'admin',?,?,? FROM admin_principal_links l WHERE l.admin_user_id=?`,sessionId,timestamp,timestamp,timestamp+SESSION_SECONDS,user.id),
   sql(env,`INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)`,hash,publicId,user.id,user.auth_version,sessionId,new URL(request.url).origin,timestamp,timestamp+SESSION_SECONDS),
   sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) VALUES(?,?,?,'signed_in',?)`,crypto.randomUUID(),user.id,user.id,timestamp),
   sql(env,'DELETE FROM admin_account_guards WHERE id=?',guardId)]);
  }catch(error){if(String(error).match(/admin_account_guards|admin_account_authority/))fail(401,'invalid_credentials','Email or password is incorrect.');throw error;}
  const account=await adminAccountSession(new Request(request.url,{headers:{Cookie:`__Host-collect_admin=${token}`}}),env);
  return json({user:adminPublicUser(account),expiresAt:iso(timestamp+SESSION_SECONDS)},200,{'Set-Cookie':adminCookie(token,SESSION_SECONDS)});
 }
 if(path==='/auth/logout'){await body(request,[]);const user=await adminAccountSession(request,env,false);if(user)await sql(env,'DELETE FROM admin_sessions WHERE token_hash=?',user.token_hash).run();return json({ok:true},200,{'Set-Cookie':adminCookie()});}
 if(path==='/auth/forgot-password'){
  await rate(request,env,'forgot',10,3600);const data=await body(request,['email']),target=email(data.email),throttled=await limited(env,`forgot:email:${target}`,3,3600);
  if(!throttled){const work=(async()=>{const user=await sql(env,'SELECT * FROM admin_users WHERE email=?',target).first();if(user?.status==='active'||(user?.status==='invited'&&user.role==='owner'))try{await sendChallenge(env,user,user.status==='invited'?'invite':'reset');}catch{/* Failure metadata retained; no secret logs. */}})();if(ctx?.waitUntil)ctx.waitUntil(work);else await work;}
  return json({ok:true,message:'Request received. If this account is eligible, check its inbox for a password link.'},202);
 }
 if(path==='/auth/complete-password'){
  await rate(request,env,'complete',10);const data=await body(request,['token','password','invite']);password(data.password);
  if(typeof data.token!=='string'||!/^[a-f0-9]{64}$/.test(data.token)||typeof data.invite!=='boolean')fail(400,'invalid_link','This password link is invalid or expired.');
  const hash=await digest(data.token),kind=data.invite?'invite':'reset',timestamp=unix();
  const challenge=await sql(env,`SELECT c.*,a.status FROM admin_challenges c JOIN admin_users a ON a.id=c.user_id JOIN admin_principal_links l ON l.admin_user_id=a.id
   WHERE c.token_hash=? AND c.kind=? AND c.delivery_status='accepted' AND c.used_at IS NULL AND c.expires_at>?
   AND c.auth_version=a.auth_version AND c.challenge_version=a.challenge_version AND a.status=?`,hash,kind,timestamp,kind==='invite'?'invited':'active').first();
  if(!challenge)fail(400,'invalid_link','This password link is invalid or expired.');
  const hashed=await passwordHash(data.password),time=unix();
  const [changed]=await env.DB.batch([
   sql(env,`UPDATE admin_users SET password_hash=?,status='active',auth_version=auth_version+1,updated_at=?,accepted_at=COALESCE(accepted_at,?)
   WHERE id=? AND auth_version=? AND challenge_version=? AND status=? AND EXISTS(SELECT 1 FROM admin_challenges WHERE token_hash=? AND used_at IS NULL AND delivery_status='accepted' AND expires_at>?) RETURNING id`,hashed,time,time,challenge.user_id,challenge.auth_version,challenge.challenge_version,challenge.status,hash,time),
   sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) SELECT ?,?,?,?,? WHERE changes()=1`,crypto.randomUUID(),challenge.user_id,challenge.user_id,kind==='invite'?'invitation_accepted':'password_reset',time),
   sql(env,`UPDATE admin_challenges SET used_at=? WHERE user_id=? AND used_at IS NULL AND EXISTS(SELECT 1 FROM admin_users WHERE id=? AND password_hash=?)`,time,challenge.user_id,challenge.user_id,hashed)]);
  if(changed.results.length!==1)fail(400,'invalid_link','This password link is invalid or expired.');
  return json({ok:true},200,{'Set-Cookie':adminCookie()});
 }
 if(path==='/auth/change-password'){
  const user=await adminAccountSession(request,env);await rate(request,env,'change',10);const data=await body(request,['currentPassword','newPassword']);password(data.newPassword);
  if(typeof data.currentPassword!=='string'||data.currentPassword.length>512||!await passwordMatches(data.currentPassword,user.password_hash))fail(400,'invalid_password','Your current password is incorrect.');
  const hashed=await passwordHash(data.newPassword),timestamp=unix(),gate=accountGuard(env,user,'account.manage');
  await env.DB.batch([gate.statement,sql(env,`UPDATE admin_users SET password_hash=?,auth_version=auth_version+1,updated_at=? WHERE id=? AND auth_version=? AND status='active'`,hashed,timestamp,user.id,user.auth_version),
   sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) VALUES(?,?,?,'password_changed',?)`,crypto.randomUUID(),user.id,user.id,timestamp),
   sql(env,'UPDATE admin_challenges SET used_at=? WHERE user_id=? AND used_at IS NULL',timestamp,user.id),gate.remove]);
  return json({ok:true},200,{'Set-Cookie':adminCookie()});
 }
 if(path==='/team/invite'){
  const user=await adminAccountSession(request,env);const data=await body(request,['email','role','displayName']);const target=email(data.email),display=name(data.displayName??'');
  if(!['admin','staff'].includes(data.role))fail(400,'invalid_role','Choose administrator or staff.');if(target===OWNER_EMAIL)fail(409,'owner_protected','The main administrator already owns this account.');
  await rate(request,env,'invite',30,3600);const timestamp=unix(),adminId=crypto.randomUUID(),principalId=crypto.randomUUID();
  const inviteGuardId=crypto.randomUUID();
  const result=await ownerBatch(env,user,[
   sql(env,`INSERT INTO admin_users(id,email,role,display_name,status,created_at,invited_at,updated_at) VALUES(?,?,?,?,'invited',?,?,?)
    ON CONFLICT(email) DO UPDATE SET role=excluded.role,display_name=excluded.display_name,status='invited',password_hash=NULL,
    auth_version=admin_users.auth_version+1,challenge_version=admin_users.challenge_version+1,accepted_at=NULL,invited_at=excluded.invited_at,updated_at=excluded.updated_at
    WHERE admin_users.status='revoked' RETURNING *`,adminId,target,data.role,display,timestamp,timestamp,timestamp),
   sql(env,`INSERT INTO admin_bridge_guards(id,passed) SELECT ?,(CASE WHEN changes()=1 THEN 1 ELSE 0 END)`,inviteGuardId),
   sql(env,`INSERT INTO users(id,public_id,full_name,member_type,created_at,updated_at) SELECT ?,
    (SELECT printf('%06d',min(candidate)) FROM (SELECT 0 AS candidate UNION ALL SELECT CAST(public_id AS INTEGER)+1 FROM users WHERE public_id!='999999') c WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM users WHERE public_id=printf('%06d',candidate))),
    ?,'operator',?,? WHERE EXISTS(SELECT 1 FROM admin_users a WHERE a.email=? AND NOT EXISTS(SELECT 1 FROM admin_principal_links WHERE admin_user_id=a.id))`,principalId,display,new Date().toISOString(),new Date().toISOString(),target),
   sql(env,`INSERT INTO admin_principal_links(admin_user_id,user_id,approved_by,approved_at) SELECT a.id,?,?,? FROM admin_users a WHERE a.email=? AND NOT EXISTS(SELECT 1 FROM admin_principal_links WHERE admin_user_id=a.id)`,principalId,user.id,new Date().toISOString(),target),
   sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) SELECT ?,?,id,'invitation_created',? FROM admin_users WHERE email=?`,crypto.randomUUID(),user.id,timestamp,target),
   sql(env,'DELETE FROM admin_bridge_guards WHERE id=?',inviteGuardId)]);
  const invited=result[0].results[0];if(!invited)fail(409,'member_exists','This person already has access or a pending invitation.');
  return json({ok:true,...await sendInvitation(env,invited,user)},201);
 }
 const match=/^\/team\/([a-f0-9-]{36})\/(resend|revoke)$/.exec(path);
 if(match){const user=await adminAccountSession(request,env);await body(request,[]);await rate(request,env,'team-action',30,3600);
  const member=await sql(env,'SELECT * FROM admin_users WHERE id=?',uuid(match[1])).first();if(!member)fail(404,'member_not_found','The team member was not found.');
  if(member.role==='owner'||member.email===OWNER_EMAIL)fail(409,'owner_protected','The main administrator cannot be changed here.');
  if(match[2]==='resend'){if(member.status!=='invited')fail(409,'not_pending','Only pending invitations can be resent.');if(await limited(env,`resend:${member.id}`,3,3600))fail(429,'rate_limited','Too many attempts. Please try again later.');return json({ok:true,...await sendInvitation(env,member,user,'invitation_resent')});}
  await ownerBatch(env,user,[sql(env,`UPDATE admin_users SET status='revoked',password_hash=NULL,auth_version=auth_version+1,challenge_version=challenge_version+1,updated_at=? WHERE id=? AND role!='owner'`,unix(),member.id),
   sql(env,'UPDATE admin_challenges SET used_at=? WHERE user_id=? AND used_at IS NULL',unix(),member.id),sql(env,`INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) VALUES(?,?,?,'access_revoked',?)`,crypto.randomUUID(),user.id,member.id,unix())]);return json({ok:true});
 }
 fail(404,'not_found','This account action does not exist.');
}

export async function handleAdminAccounts(request,env,ctx){
 const path=new URL(request.url).pathname;if(!path.startsWith(`${PREFIX}/`))return null;
 const relative=path.slice(PREFIX.length);if(!relative.startsWith('/auth/')&&relative!=='/team'&&!relative.startsWith('/team/'))return null;
 try{const origin=validateAdminOrigin(request,env);return await accountRoute(request,{...env,ADMIN_ORIGIN:origin},ctx,relative);}
 catch(error){const known=error instanceof ApiError,conflict=/admin_bridge_state/.test(String(error));return json({error:{code:known?error.code:conflict?'account_changed':'service_unavailable',message:known?error.message:conflict?'This account already has access or its invitation changed. Refresh before continuing.':'The account request could not be completed.'}},known?error.status:conflict?409:503);}
}
