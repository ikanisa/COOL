import {ApiError,json,readJson,first,rows,digest,id,now,uuid} from './core.js';
import {authRequest,verifyToken,claimsOf} from '../auth-http.js';
import {handleGoogleAuth} from './google_auth.js';
const unix=()=>Math.floor(Date.now()/1000);
function originalAuthenticationAt(claims,at) {
 // Token iat renews on refresh; only a validated first-factor AMR event is fresh.
 let authAt=0;
 for(const entry of Array.isArray(claims.amr)?claims.amr:[]){
  if(entry!==null&&typeof entry==='object'&&!Array.isArray(entry)&&['otp','password','oauth'].includes(entry.method)&&Number.isSafeInteger(entry.timestamp)&&entry.timestamp>0&&entry.timestamp<=at)authAt=authAt===0?entry.timestamp:Math.min(authAt,entry.timestamp);
 }
 return authAt; // Missing event evidence preserves ordinary access without freshness.
}
const fail=(code='invalid_session',status=401)=>{throw new ApiError(status,code,code==='admin_access_not_approved'?'This email does not have Admin access. Contact the super admin to be added.':'Sign in again or request a new code.');};
const mfaUnknown=()=>new ApiError(503,'mfa_operation_unknown','The authenticator result could not be confirmed. Recheck your setup or sign-in before trying again.');
const mfaId=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const mfaObject=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
function userWithFactors(user) {
 // The authenticated GET /user endpoint omits an empty enrolled-factor list.
 // Normalize only this outward user DTO; retain the raw verified provider user.
 const factors=Object.hasOwn(user,'factors')?user.factors:[];
 if(!Array.isArray(factors)||factors.length>128||factors.some(factor=>!mfaObject(factor)||!mfaId(factor.id)||typeof factor.factor_type!=='string'||!/^[a-z][a-z0-9_]{0,63}$/.test(factor.factor_type)||!['unverified','verified'].includes(factor.status)))
  throw new ApiError(503,'auth_user_unavailable','Account details could not be confirmed. Try again.');
 return {...user,factors};
}
async function mfaRequest(env,path,options) {
 try{return await authRequest(env,path,options);}
 catch(error){if(error instanceof ApiError&&error.status<500)throw error;throw mfaUnknown();}
}
function mfaOwnedFactor(env,factor) {
 const factors=env.AUTH_VERIFIED.user.factors;
 if(!Array.isArray(factors)||factors.length>128)fail('factor_unavailable',403);
 const matches=factors.filter(value=>value?.id===factor);
 if(matches.length!==1||matches[0].factor_type!=='totp'||!['unverified','verified'].includes(matches[0].status))fail('factor_unavailable',403);
 return matches[0];
}
function mfaFresh(actor) {
 const at=unix();if(!Number.isSafeInteger(actor.authAt)||actor.authAt<at-300||actor.authAt>at)fail('fresh_auth_required',403);
}
function mfaEnrollment(result,email,name) {
 // Supabase enroll confirms a NEW unverified factor. Its REST DTO uses `type`
 // and does not include status; this is never a proof of successful MFA.
 if(!mfaObject(result)||!mfaId(result.id)||result.type!=='totp'||
  result.status!==undefined&&result.status!=='unverified'||result.friendly_name!==name||
  !mfaObject(result.totp)||typeof result.totp.secret!=='string'||!/^[A-Z2-7]{32}$/.test(result.totp.secret)||
  typeof result.totp.uri!=='string'||result.totp.uri.length>2048||typeof email!=='string')throw mfaUnknown();
 let supplied;
 try{supplied=new URL(result.totp.uri);}catch{throw mfaUnknown();}
 const expected={secret:result.totp.secret,issuer:'Collect',algorithm:'SHA1',digits:'6',period:'30'};
 let label;try{label=decodeURIComponent(supplied.pathname.slice(1));}catch{throw mfaUnknown();}
 if(supplied.protocol!=='otpauth:'||supplied.hostname!=='totp'||supplied.username||supplied.password||supplied.port||supplied.hash||
  supplied.pathname.split('/').length!==2||label!=='Collect:'+email||
  [...supplied.searchParams.keys()].some(key=>!Object.hasOwn(expected,key))||
  Object.entries(expected).some(([key,value])=>{
   const values=supplied.searchParams.getAll(key);
   return values.length>1||values.length===1&&values[0]!==value||['secret','issuer'].includes(key)&&values.length!==1;
  }))throw mfaUnknown();
 // RFC TOTP defaults are filled only when absent; a wrong explicit algorithm,
 // period, digit count, secret, issuer or account is never changed/accepted.
 const uri=new URL('otpauth://totp/'+encodeURIComponent('Collect:'+email));
 for(const [key,value]of Object.entries(expected))uri.searchParams.set(key,value);
 // The active client consumes secret/URI, not provider SVG markup or tokens.
 return {id:result.id,factor_type:'totp',status:'unverified',friendly_name:name,totp:{secret:result.totp.secret,uri:uri.href}};
}
function mfaChallenge(result,factor) {
 const at=unix();
 if(!mfaObject(result)||!mfaId(result.id)||result.type!=='totp'||result.challenge_id!==undefined&&result.challenge_id!==result.id||result.factor_id!==undefined&&result.factor_id!==factor||!Number.isSafeInteger(result.expires_at)||result.expires_at<=at||result.expires_at>at+600)throw mfaUnknown();
 return {id:result.id,challenge_id:result.id,factor_id:factor,expires_at:result.expires_at};
}
function mfaDeleted(result,factor) {
 if(!mfaObject(result)||result.id!==factor||result.factor_type!==undefined&&result.factor_type!=='totp'||result.type!==undefined&&result.type!=='totp'||result.status!==undefined&&result.status!=='revoked')throw mfaUnknown();
 return {id:factor,factor_type:'totp',status:'revoked'};
}
async function mfaVerifiedSession(env,data,factor) {
 try{
  if(!mfaObject(data)||typeof data.access_token!=='string'||typeof data.refresh_token!=='string'||!data.refresh_token||data.refresh_token.length>4096)throw mfaUnknown();
  const verified=await verifyToken(env,data.access_token);
  const own=verified.user.factors?.filter(value=>value.id===factor&&value.factor_type==='totp'&&value.status==='verified');
  if(verified.claims.aal!=='aal2'||own?.length!==1)throw mfaUnknown();
  // Actual managed session, factor and AMR evidence remain enforced by the
  // projection helper. No shape/status alias can manufacture an AAL upgrade.
  const actor=await projectSession(env,verified,{surface:'admin',factorId:factor,mfaVerified:true});
  return {...data,user:actor.user};
 }catch{throw mfaUnknown();}
}
function identity(body) {
 const surface=body.surface??'member';if(!['member','admin'].includes(surface)||(body.phone==null)===(body.email==null))fail('invalid_request',400);
 if(body.phone!=null){if(surface==='admin'||typeof body.phone!=='string'||!/^\+2507[2389][0-9]{7}$/.test(body.phone))fail('invalid_phone',400);return {type:'phone',value:body.phone,surface,channel:body.channel??'whatsapp'};}
 if(typeof body.email!=='string'||body.email.length>254||!/^\S+@[^\s@]+\.[^\s@]+$/.test(body.email.trim()))fail('invalid_email',400);
 return {type:'email',value:body.email.trim().toLowerCase(),surface,channel:'email'};
}
export async function projectSession(env,verified,{surface='member',factorId=null,mfaVerified=false,existingLinkOnly=false,expectedAuthUserId=null,expectedUserId=null}={}) {
 if(mfaVerified)throw new ApiError(410,'mfa_not_available','Verify your email to confirm sensitive changes.');
 const {user,claims}=verified;
 if(expectedAuthUserId!==null&&user.id!==expectedAuthUserId)fail('verified_identity_mismatch',403);
 env.DB.setClaims(claims);
 const managed=await first(env,'SELECT private.is_managed_session(?::uuid,?::uuid) AS allowed',user.id,claims.session_id);if(!managed?.allowed)fail('access_revoked');
 let link=await first(env,'SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?',user.id);
 if(existingLinkOnly&&!link||expectedUserId!==null&&link?.user_id!==expectedUserId)fail('verified_identity_mismatch',403);
 if(!link){
  const email=user.email_confirmed_at?user.email?.toLowerCase():null,phone=user.phone_confirmed_at?(user.phone?.startsWith('+')?user.phone:'+'+user.phone):null;
  let principal;
  if(surface==='admin')principal=await first(env,"SELECT l.user_id AS id FROM admin_users a JOIN admin_principal_links l ON l.admin_user_id=a.id WHERE a.email=? AND a.status IN('active','invited')",email);
  else {const found=await rows(env,`SELECT id FROM users WHERE (? IS NOT NULL AND lower(email)=?) OR (? IS NOT NULL AND phone=?) UNION SELECT l.user_id AS id FROM admin_principal_links l JOIN admin_users a ON a.id=l.admin_user_id JOIN users u ON u.id=l.user_id WHERE ? IS NOT NULL AND a.email=? AND a.status IN('active','invited')`,email,email,phone,phone,email,email);if(found.length>1)fail('identity_link_conflict',409);principal=found[0];}
  if(!principal){if(!email&&!phone)fail('verified_identity_required',403);if(surface!=='member'||env.AUTH_MEMBER_REGISTRATION_ENABLED!=='true')fail('registration_unavailable',403);
   const newId=id(),stamp=now();await env.DB.batch([env.DB.prepare(`INSERT INTO users(id,public_id,phone,email,full_name,created_at,updated_at) VALUES(?,(SELECT printf('%06d',min(candidate)) FROM (SELECT 0 AS candidate UNION ALL SELECT CAST(public_id AS INTEGER)+1 FROM users WHERE public_id!='999999') c WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM users WHERE public_id=printf('%06d',candidate))),?,?,'',?,?)`).bind(newId,phone,email,stamp,stamp)]);principal={id:newId};
  }
  await env.DB.prepare('INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES(?,?,?) ON CONFLICT(auth_user_id) DO NOTHING').bind(user.id,principal.id,'supabase-auth-getuser:'+claims.session_id).run();
  link=await first(env,'SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?',user.id);if(link?.user_id!==principal.id)fail('identity_link_conflict',409);
 }
 const principal=await first(env,'SELECT * FROM users WHERE id=?',link.user_id);if(principal?.access_status!=='active')fail('access_revoked',403);
 const previous=await first(env,'SELECT * FROM auth_sessions WHERE id=?',claims.session_id);
 const admission=await first(env,'SELECT a.id FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id JOIN admin_principal_links l ON l.admin_user_id=a.id WHERE s.auth_session_id=? AND a.status=\'active\' AND s.auth_version=a.auth_version AND l.user_id=? AND s.expires_at>?',claims.session_id,principal.id,unix());
 const actualSurface=admission?'admin':surface;
 if(actualSurface==='admin'&&!env.ADMIN_AUTH_EXCHANGE&&!admission)fail('admin_admission_required',403);
 const authAt=previous?.auth_at??originalAuthenticationAt(claims,unix());
 const mfaAt=previous?.mfa_at??null;
 const currentFactor=previous?.mfa_factor_id??null;
 const aal=claims.aal==='aal2'&&mfaAt&&currentFactor?2:1;
 if(!previous){const lifetime=actualSurface==='admin'?28800:2592000;const expiry=(await first(env,'SELECT private.session_expiry(?) AS expires_at',unix()+lifetime)).expires_at;
 await env.DB.prepare(`INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at,assurance_level,mfa_at,mfa_factor_id) VALUES(?,?,?,?,?,?,1,NULL,NULL) ON CONFLICT(id) DO NOTHING`).bind(claims.session_id,principal.id,actualSurface,authAt,unix(),expiry).run();}
 const session=await first(env,'SELECT * FROM auth_sessions WHERE id=?',claims.session_id);if(session?.revoked_at||session?.surface!==actualSurface||existingLinkOnly&&session?.user_id!==principal.id)fail('access_revoked');
 const effectiveAal=Number(session.assurance_level)===2&&claims.aal==='aal2'?2:1;
 const permissions=actualSurface==='admin'?new Set((await rows(env,`SELECT g.permission FROM admin_grants g JOIN admin_sessions s ON s.auth_session_id=? JOIN admin_users a ON a.id=s.user_id JOIN admin_account_role_capabilities c ON c.role=a.role AND c.permission=g.permission WHERE g.user_id=? AND g.permission<>'auth.mfa.enroll' AND a.status='active' AND s.auth_version=a.auth_version`,claims.session_id,principal.id)).map(r=>r.permission)):new Set();
 const actor={userId:principal.id,sessionId:claims.session_id,surface:actualSurface,assuranceLevel:effectiveAal,aal:effectiveAal===2?'aal2':'aal1',authAt:effectiveAal===2?session.mfa_at:session.auth_at,mfaAt:effectiveAal===2?session.mfa_at:null,mfaFactorId:effectiveAal===2?session.mfa_factor_id:null,permissions,user:{...user,id:principal.id,auth_user_id:user.id,user_metadata:{full_name:principal.full_name,public_id:principal.public_id,country_code:principal.country_code,currency_code:principal.currency_code,momo_provider:principal.momo_provider,momo_number:principal.momo_number},app_metadata:{provider:user.app_metadata?.provider,roles:permissions.size?['admin']:['member'],permissions:[...permissions]}}};
 env.AUTH_ACTOR=actor;env.AUTH_VERIFIED=verified;return actor;
}
export async function requireSession(request,env) {
 const token=request.headers.get('Authorization')?.match(/^Bearer (\S+)$/)?.[1];if(!token)fail();
 const verified=env.AUTH_VERIFIED?.token===token?env.AUTH_VERIFIED:await verifyToken(env,token);
 return projectSession(env,verified);
}
export async function responseSession(env,data,options={}) {
 const verified=await verifyToken(env,data.access_token);const actor=await projectSession(env,verified,options);
 return {...data,user:actor.user};
}
export async function startOtp(env,body) {
 const target=identity(body);if(target.type==='phone'&&!['sms','whatsapp'].includes(target.channel))fail('invalid_channel',400);
 const existing=target.surface==='admin'?await first(env,"SELECT a.id FROM admin_users a JOIN admin_principal_links l ON l.admin_user_id=a.id JOIN users u ON u.id=l.user_id WHERE a.email=? AND a.status IN('active','invited') AND u.access_status='active'",target.value):target.type==='email'?await first(env,`SELECT id FROM users WHERE lower(email)=? AND access_status='active' UNION SELECT l.user_id AS id FROM admin_principal_links l JOIN admin_users a ON a.id=l.admin_user_id JOIN users u ON u.id=l.user_id WHERE a.email=? AND a.status IN('active','invited') AND u.access_status='active'`,target.value,target.value):await first(env,`SELECT id FROM users WHERE phone=? AND access_status='active'`,target.value);
 const registration=target.surface==='member'&&env.AUTH_MEMBER_REGISTRATION_ENABLED==='true'&&body.allow_registration!==false&&body.should_create_user!==false;
 if(!existing&&!registration)fail(target.surface==='admin'?'admin_access_not_approved':'registration_unavailable',403);
 const key=await digest(target.type+':'+target.value),at=unix();
 const challenge=id(),guard=id();
 try{await env.DB.batch([
  env.DB.prepare('INSERT INTO admin_bridge_guards(id,passed) SELECT ?,CASE WHEN NOT EXISTS(SELECT 1 FROM private.supabase_otp_challenges WHERE identity_hash=? AND created_at>?) THEN 1 ELSE 0 END').bind(guard,key,at-60),
  env.DB.prepare('INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status) VALUES(?,?,?,?,?,?,?,?,\'reserved\')').bind(challenge,key,target.type,target.value,target.surface,Number(registration),at,at+300),
  env.DB.prepare('DELETE FROM admin_bridge_guards WHERE id=?').bind(guard)
 ]);}catch(error){if(/admin_bridge_guards|check constraint|otp_cooldown/.test(String(error)))fail('auth_rate_limited',429);throw error;}
 let outcome='accepted';
 try{await authRequest(env,'/otp',{body:{[target.type]:target.value,create_user:registration||target.surface==='admin'||Boolean(existing)&&body.allow_registration!==false&&body.should_create_user!==false,...(target.type==='phone'?{channel:target.channel}:{}),gotrue_meta_security:{captcha_token:body.captcha_token}}});}
 catch(error){outcome=error instanceof ApiError&&[400,401,403,422,429].includes(error.status)?'rejected':'unknown';await env.DB.prepare('UPDATE private.supabase_otp_challenges SET delivery_status=? WHERE id=?').bind(outcome,challenge).run();if(outcome==='rejected')throw error;}
 if(outcome==='accepted')await env.DB.prepare('UPDATE private.supabase_otp_challenges SET delivery_status=? WHERE id=?').bind(outcome,challenge).run();
 return {challenge_id:challenge,retry_after:60,expires_in:300,channel:target.channel,delivery_status:outcome};
}
export async function verifyOtp(env,body,{project=true}={}) {
 const challenge=await env.DB.prepare(`UPDATE private.supabase_otp_challenges pending SET attempts=pending.attempts+1 WHERE pending.id=? AND pending.consumed_at IS NULL AND pending.expires_at>? AND pending.attempts<5 AND pending.delivery_status IN('accepted','unknown') AND pending.surface=?
  AND NOT EXISTS(SELECT 1 FROM private.supabase_otp_challenges newer WHERE newer.identity_hash=pending.identity_hash AND newer.surface=pending.surface AND newer.created_at>pending.created_at) RETURNING pending.*`).bind(uuid(body.challenge_id,'challenge_id'),unix(),body.surface??'member').first();
 if(!challenge||typeof body.code!=='string'||!/^\d{6,10}$/.test(body.code))fail('invalid_credentials');
 const data=await authRequest(env,'/verify',{body:{[challenge.identity_type]:challenge.identity_value,token:body.code,type:challenge.identity_type==='email'?'email':'sms',gotrue_meta_security:{captcha_token:body.captcha_token}}});
 // The provider's verify response is not a phone/email assertion. Re-read
 // the actual managed user and bind its confirmed identity to this challenge
 // before consuming the local one-shot admission.
 const verified=await verifyToken(env,data.access_token);
 const actual=challenge.identity_type==='phone'?(verified.user.phone_confirmed_at?(verified.user.phone?.startsWith('+')?verified.user.phone:'+'+verified.user.phone):null):(verified.user.email_confirmed_at?verified.user.email?.toLowerCase():null);
 if(actual!==challenge.identity_value){await authRequest(env,'/logout?scope=local',{token:data.access_token}).catch(()=>{});fail('verified_identity_mismatch',403);}
 const consumed=await env.DB.prepare(`UPDATE private.supabase_otp_challenges pending SET consumed_at=? WHERE pending.id=? AND pending.consumed_at IS NULL
  AND NOT EXISTS(SELECT 1 FROM private.supabase_otp_challenges newer WHERE newer.identity_hash=pending.identity_hash AND newer.surface=pending.surface AND newer.created_at>pending.created_at) RETURNING pending.id`).bind(unix(),challenge.id).first();
 if(!consumed){await authRequest(env,'/logout?scope=local',{token:data.access_token}).catch(()=>{});fail('challenge_consumed');}
 if(!project)return data;
 const actor=await projectSession(env,verified,{surface:challenge.surface});
 if(challenge.identity_type==='phone'&&challenge.surface==='member'){const proof=await first(env,'SELECT private.record_managed_phone_verification(?) AS challenge_id',challenge.id);if(proof?.challenge_id!==challenge.id)fail('phone_proof_unconfirmed',503);}
 return {...data,user:actor.user};
}
export async function handleAuth(request,env) {
 const path=new URL(request.url).pathname;if(!path.startsWith('/v1/auth/'))return null;
 if(path==='/v1/auth/mfa'||path.startsWith('/v1/auth/mfa/'))throw new ApiError(410,'mfa_not_available','Verify your email to confirm sensitive changes.');
 if(path.startsWith('/v1/auth/google/'))return handleGoogleAuth(request,env);
 if(request.method==='GET'&&path==='/v1/auth/user'){const actor=await requireSession(request,env);return json(userWithFactors(actor.user));}
 if(request.method!=='POST')throw new ApiError(405,'method_not_allowed','Use POST.');
 const body=await readJson(request,16384);
 if(path==='/v1/auth/otp')return json(await startOtp(env,body));
 if(path==='/v1/auth/verify'){if(body.surface==='admin')fail('admin_cookie_required',403);return json(await verifyOtp(env,body));}
 if(path==='/v1/auth/refresh'){const data=await authRequest(env,'/token?grant_type=refresh_token',{body:{refresh_token:body.refresh_token}});return json(await responseSession(env,data));}
 if(path==='/v1/auth/logout'){const actor=await requireSession(request,env);await authRequest(env,'/logout?scope=local',{token:env.AUTH_VERIFIED.token});await env.DB.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='signed_out' WHERE id=? AND user_id=?").bind(unix(),actor.sessionId,actor.userId).run();return json({ok:true});}
 throw new ApiError(404,'not_found','This identity operation does not exist.');
}

export const otpDeliveryAvailable=env=>env.AUTH_PHONE_ENABLED==='true'&&Boolean(env.SUPABASE_URL&&env.SUPABASE_PUBLISHABLE_KEY);
