import {adminEmailArguments,requireFreshAdminEmail} from './admin_email_policy.js';
import {ApiError,json,readJson,uuid} from './core.js';
import {digest} from './core.js';
const OWNER_EMAIL='info@ikanisa.com';

const PREFIX='/api/admin', SESSION_SECONDS=28800, unix=()=>Math.floor(Date.now()/1000);
const iso=v=>v==null?null:new Date(v*1000).toISOString();
const sql=(env,query,...args)=>env.DB.prepare(query).bind(...args);
const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const expired=()=>fail(401,'unauthenticated','Your session has ended. Sign in again.');
const notApproved=()=>fail(403,'admin_access_not_approved','This email does not have Admin access. Contact the super admin to be added.');
const invalidOtp=()=>fail(401,'invalid_credentials','The sign-in code is invalid or expired. Request a new code.');
const OTP_SECONDS=300,OTP_COOLDOWN=60;
const encoder=new TextEncoder();

import {validateAdminOrigin} from '../admin-security.js';
export {validateAdminOrigin};
export function adminCookie(token='',age=0){return `__Host-collect_admin=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${age}; Secure`;}
async function body(request,allowed,max=4096){const value=await readJson(request,max);if(Object.keys(value).some(k=>!allowed.includes(k)))fail(400,'invalid_request','Request has unsupported fields.');return value;}
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
 AND s.issued_mfa_factor_id=ss.mfa_factor_id AND EXISTS(SELECT 1 FROM auth_mfa_factors f WHERE f.id=ss.mfa_factor_id AND f.user_id=u.id AND f.status='verified')))`,hash,validateAdminOrigin(request,env),unix(),unix()).first();
 if(!result){if(required)expired();return null;}
 const grants=await sql(env,`SELECT c.permission FROM admin_account_role_capabilities c JOIN admin_grants g ON g.permission=c.permission
 WHERE c.role=? AND g.user_id=? AND c.permission<>'auth.mfa.enroll' ORDER BY c.permission`,result.role,result.principal_id).all();
 result.permissions=grants.results.map(v=>v.permission);return result;
}
export const adminPublicUser=user=>user?{id:user.id,email:user.email,role:user.role,sessionId:user.public_id,
 expiresAt:iso(user.expires_at),permissions:user.permissions,assuranceLevel:user.issued_assurance_level,
 mfaAt:iso(user.issued_mfa_at),principalId:user.principal_id,financialModel:'canonical_evidence_ledger',
 ...(user.mfaAvailable===true?{mfaAvailable:true}:{}),...(user.mfaRequired===true?{mfaRequired:true}:{})}:null;

// The original cookie proof is checked in the SAME D1 batch as all delegated
// writes. An intervening account/password/role/session change cannot authorize a
// canonical-domain mutation through a previously resolved actor.
export function accountGuard(env,account,permission=null,{owner=false,mfa=false,fresh=false}={}){
 if(mfa||fresh)requireFreshAdminEmail(account);
 const guardId=crypto.randomUUID();
 // The separately gated protected singleton is part of this same guarded
 // mutation transaction. The legacy predicate remains exact until the new
 // database migration and every owner mutation path are qualified together.
 const dynamicOwner=env.COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED==='true';
 const ownerPredicate=dynamicOwner?"(a.role='owner' AND private.collect_owner_is(a.id,l.user_id,a.email))":"(a.role='owner' AND a.email=?)";
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
 WHERE g.user_id=u.id AND g.permission=? AND g.permission<>'auth.mfa.enroll' AND c.role=a.role))
 AND (?=0 OR ${ownerPredicate})
 AND (?=0 OR (private.assert_admin_email_context(300)).id IS NOT NULL)
 ) THEN 1 ELSE 0 END)`,guardId,account.token_hash,account.origin,account.public_id,account.id,account.auth_version,account.role,account.principal_id,
 account.auth_session_id,account.issued_assurance_level,account.issued_mfa_at,account.issued_mfa_factor_id,permission,permission,
 Number(owner),...(dynamicOwner?[]:[OWNER_EMAIL]),Number(mfa||fresh));
 return {statement,remove:sql(env,'DELETE FROM admin_account_guards WHERE id=?',guardId)};
}
export function accountDatabase(env,account,permission=null,options={}){
 const wrap=db=>new Proxy(db,{get(target,key){
  if(key==='batch')return async statements=>{const gate=accountGuard({...env,DB:target},account,permission,options);
   try{const context=target.prepare('SELECT private.set_admin_email_context(?::text,?::text,?::text,?::text) AS result').bind(...adminEmailArguments(account));return(await target.batch([context,gate.statement,...statements,gate.remove])).slice(2,-1);}
   catch(error){if(error?.code==='42501'&&/\bmfa_required\b/.test(String(error?.message??error)))fail(403,'mfa_required','Verify your authenticator before continuing.');if(/recent_email_(?:verification|sign_in)_required/.test(String(error?.message??error)))fail(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');if(String(error).match(/admin_account_guards|admin_account_authority|admin_email_denied/))fail(403,'admin_access_changed','Your account access changed. Sign in and verify again.');throw error;}};
  // D1DatabaseSession has no withSession method. Preserve that capability
  // boundary so nested auth reads keep the selected, guarded session.
  if(key==='withSession')return typeof target.withSession==='function'?(...args)=>wrap(target.withSession(...args)):undefined;
  const value=Reflect.get(target,key);return typeof value==='function'?value.bind(target):value;
 }});return {...env,ADMIN_ACCOUNT:account,DB:wrap(env.DB)};
}

// Optional session metadata only. This never grants an Admin permission; the
// protected binding and the current actor are checked again by each mutation.
// Opaque legacy IDs remain valid without inventing a UUID-only requirement.
const validOwnerId=value=>typeof value==='string'&&value.length>0&&value.length<=200&&value===value.trim()&&!/[\u0000-\u001f\u007f-\u009f]/.test(value);
function validOwnerEmail(value){
 if(typeof value!=='string'||value.length>254||value!==value.trim().toLowerCase()||/[\s\u0000-\u001f\u007f]/.test(value))return false;
 const parts=value.split('@');if(parts.length!==2||!parts[0]||parts[0].length>64||parts[0].startsWith('.')||parts[0].endsWith('.')||parts[0].includes('..')||!/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$/.test(parts[0]))return false;
 const labels=parts[1].split('.');return labels.length>=2&&labels.every(label=>label.length>0&&label.length<=63&&/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(label));
}
function checkedOwnerIdentity(value){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==4||
  !['schemaVersion','adminId','principalId','email'].every(key=>Object.hasOwn(value,key))||value.schemaVersion!==1||
  !validOwnerId(value.adminId)||!validOwnerId(value.principalId)||!validOwnerEmail(value.email))return null;
 return {schemaVersion:1,adminId:value.adminId,principalId:value.principalId,email:value.email};
}
export async function guardedOwnerSessionIdentity(env,account){
 try{
  // accountDatabase places the existing cookie-bound actor guard and email
  // context in the same fenced, serialized transaction as these reads. The
  // email context holds SHARE locks on the viewer's session and identity.
  const queryOwner=env.DB.prepare('SELECT private.collect_owner_attestation() AS result');
  const queryViewer=env.DB.prepare(`SELECT a.id,a.email,a.role,a.auth_version,l.user_id AS principal_id
   FROM admin_users a JOIN admin_principal_links l ON l.admin_user_id=a.id WHERE a.id=? AND l.user_id=?`).bind(account.id,account.principal_id);
  const queryGrants=env.DB.prepare(`SELECT c.permission FROM admin_account_role_capabilities c JOIN admin_grants g ON g.permission=c.permission
   WHERE c.role=? AND g.user_id=? AND c.permission<>'auth.mfa.enroll' ORDER BY c.permission FOR SHARE OF c,g`).bind(account.role,account.principal_id);
  const result=await accountDatabase(env,account).DB.batch([queryOwner,queryViewer,queryGrants]);
  const owner=result?.[0]?.results,viewers=result?.[1]?.results,grants=result?.[2]?.results;
  if(!Array.isArray(owner)||owner.length!==1||!Array.isArray(viewers)||viewers.length!==1||!Array.isArray(grants)||!Array.isArray(account.permissions))return null;
  const viewer=viewers[0],permissions=grants.map(row=>row?.permission);
  if(viewer?.id!==account.id||viewer.email!==account.email||viewer.role!==account.role||viewer.auth_version!==account.auth_version||viewer.principal_id!==account.principal_id||
   permissions.some(value=>typeof value!=='string')||new Set(permissions).size!==permissions.length||
   new Set(account.permissions).size!==account.permissions.length||
   JSON.stringify([...permissions].sort())!==JSON.stringify([...account.permissions].sort()))return null;
  return checkedOwnerIdentity(owner[0]?.result);
 }catch(error){
  // An unavailable optional proof must not break ordinary sign-in. A failed
  // application fence still aborts the entire request under the usual policy.
  if(['application_fenced','application_fence_unavailable'].includes(error?.code))throw error;
  return null;
 }
}
function base64(bytes){let raw='';for(const value of new Uint8Array(bytes))raw+=String.fromCharCode(value);return btoa(raw).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');}
