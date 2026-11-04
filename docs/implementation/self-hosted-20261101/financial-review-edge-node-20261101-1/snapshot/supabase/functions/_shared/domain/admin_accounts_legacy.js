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
 mfaAt:iso(user.issued_mfa_at),principalId:user.principal_id,financialModel:'canonical_evidence_ledger'}:null;

// The original cookie proof is checked in the SAME D1 batch as all delegated
// writes. An intervening account/password/role/session change cannot authorize a
// canonical-domain mutation through a previously resolved actor.
export function accountGuard(env,account,permission=null,{owner=false,mfa=false,fresh=false}={}){
 if(mfa||fresh)requireFreshAdminEmail(account);
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
 WHERE g.user_id=u.id AND g.permission=? AND g.permission<>'auth.mfa.enroll' AND c.role=a.role))
 AND (?=0 OR (a.role='owner' AND a.email=?))
 AND (?=0 OR (private.assert_admin_email_context(300)).id IS NOT NULL)
 ) THEN 1 ELSE 0 END)`,guardId,account.token_hash,account.origin,account.public_id,account.id,account.auth_version,account.role,account.principal_id,
 account.auth_session_id,account.issued_assurance_level,account.issued_mfa_at,account.issued_mfa_factor_id,permission,permission,
 Number(owner),OWNER_EMAIL,Number(mfa||fresh));
 return {statement,remove:sql(env,'DELETE FROM admin_account_guards WHERE id=?',guardId)};
}
export function accountDatabase(env,account,permission=null,options={}){
 const wrap=db=>new Proxy(db,{get(target,key){
  if(key==='batch')return async statements=>{const gate=accountGuard({...env,DB:target},account,permission,options);
   try{const context=target.prepare('SELECT private.set_admin_email_context(?::text,?::text,?::text,?::text) AS result').bind(...adminEmailArguments(account));return(await target.batch([context,gate.statement,...statements,gate.remove])).slice(2,-1);}
   catch(error){if(/recent_email_(?:verification|sign_in)_required/.test(String(error?.message??error)))fail(403,'recent_email_sign_in_required','Verify your current Admin email before continuing.');if(String(error).match(/admin_account_guards|admin_account_authority|admin_email_denied/))fail(403,'admin_access_changed','Your account access changed. Sign in and verify again.');throw error;}};
  // D1DatabaseSession has no withSession method. Preserve that capability
  // boundary so nested auth reads keep the selected, guarded session.
  if(key==='withSession')return typeof target.withSession==='function'?(...args)=>wrap(target.withSession(...args)):undefined;
  const value=Reflect.get(target,key);return typeof value==='function'?value.bind(target):value;
 }});return {...env,ADMIN_ACCOUNT:account,DB:wrap(env.DB)};
}
function base64(bytes){let raw='';for(const value of new Uint8Array(bytes))raw+=String.fromCharCode(value);return btoa(raw).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');}
