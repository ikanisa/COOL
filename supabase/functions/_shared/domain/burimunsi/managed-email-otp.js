import {ApiError,digest,uuid} from '../core.js';
import {ADMIN_EMAIL_CODE_MIN_SECONDS,ADMIN_EMAIL_CODE_MAX_SECONDS} from '../admin_email_code_policy.js';
import {applicationWork,applicationWorkTuple} from '../../application-fence.js';
import {readNativeBody,requireActiveNativeRequest} from './wire/request-boundary.mjs';
import {parseWire} from './wire/runtime.mjs';

export const MANAGED_EMAIL_OTP_PATH='/v1/burimunsi/managed/email-otp';
export const MANAGED_EMAIL_RESERVE_SQL='SELECT private.burimunsi_managed_email_reserve(?::text,?::uuid,?::text,?::text,?::text,?::text,?::integer) AS result';
const admissions=new WeakMap();
const fail=(code='native_email_admission_denied',status=403)=>{throw new ApiError(status,code,'This approved phone cannot request this Collect email code.');};
async function owned(env,state){
 requireActiveNativeRequest(state.request);
 const work=applicationWork(env);
 if(env.DB!==state.db||work!==state.work||work.kind!=='http_collect'||env.DB.applicationWork!==work||
  JSON.stringify(applicationWorkTuple(work))!==state.tuple||env.BURIMUNSI_NATIVE_ENABLED!=='true')fail('request_not_admitted',503);
 await work.assert();
 requireActiveNativeRequest(state.request);
 if(env.DB!==state.db||env.DB.applicationWork!==work||JSON.stringify(applicationWorkTuple(work))!==state.tuple)fail('request_not_admitted',503);
}

/** Only the already attested native ingress supplies networkBucket. This opaque
 * admission never comes from request JSON, an Admin Worker or a caller flag. */
export async function admitManagedEmailOtp(request,env,{profile,networkBucket}){
 if(request.method!=='POST')fail('method_not_allowed',405);
 const url=new URL(request.url),origin=request.headers.get('Origin');
 if(url.origin!==profile.supabase_origin||url.pathname!==MANAGED_EMAIL_OTP_PATH||url.search||
  origin&&origin!==profile.supabase_origin||request.headers.has('X-BuriMunsi-Collect-Session')||request.headers.has('Cookie'))fail();
 const work=applicationWork(env);await work.assert();
 const state={db:env.DB,work,request,tuple:JSON.stringify(applicationWorkTuple(work))};
 await owned(env,state);requireActiveNativeRequest(request);
 const network=await networkBucket(request);
 if(typeof network!=='string'||!/^[a-f0-9]{64}$/.test(network))fail('trusted_network_resolver_required',503);
 const installation=uuid(request.headers.get('X-BuriMunsi-Installation'),'installationId');
 if(installation!==request.headers.get('X-BuriMunsi-Installation'))fail();
 const token=request.headers.get('X-BuriMunsi-Device');
 if(typeof token!=='string'||!/^[a-f0-9]{64}$/.test(token))fail();
 if((request.headers.get('Content-Type')??'').split(';')[0].trim()!=='application/json')fail('json_required',415);
 let body;const bytes=await readNativeBody(request);
 try{body=parseWire(bytes,8192);}finally{bytes.fill(0);}
 if(!body||(Object.getPrototypeOf(body)!==null&&Object.getPrototypeOf(body)!==Object.prototype)||Object.keys(body).sort().join(',')!=='email,profile'||
  typeof body.email!=='string'||body.email.length>254||body.email!==body.email.trim().toLowerCase()||
  /[\u0000-\u001f\u007f]/.test(body.email)||! /^[^@\s]+@[^\s@]+\.[^\s@]+$/.test(body.email)||
  !['staff','internal_receiver'].includes(body.profile))fail('invalid_request',400);
 Object.assign(state,{installation,tokenHash:await digest(token),network,email:body.email,profile:body.profile});
 await owned(env,state);requireActiveNativeRequest(request);
 const admission=Object.freeze({});admissions.set(admission,state);
 return {admission,email:state.email};
}

/** Reserve the shared one-shot challenge and all durable abuse budgets in one
 * fenced transaction. Denials return normally so charged attempts commit. */
export async function reserveManagedEmailOtp(env,admission,email,challenge,ttlSeconds){
 const state=admissions.get(admission);if(!state||state.email!==email||state.reserved)fail();
 if(!Number.isSafeInteger(ttlSeconds)||ttlSeconds<ADMIN_EMAIL_CODE_MIN_SECONDS||ttlSeconds>ADMIN_EMAIL_CODE_MAX_SECONDS)fail('native_email_ttl_unconfigured',503);
 await owned(env,state);
 const result=await env.DB.prepare(MANAGED_EMAIL_RESERVE_SQL)
  .bind(challenge,state.installation,state.tokenHash,email,state.profile,state.network,ttlSeconds).first();
 await owned(env,state);
 const value=result?.result;
 if(value?.allowed!==true){if(value?.code==='auth_rate_limited')fail('auth_rate_limited',429);fail();}
 if(value.challengeId!==challenge||typeof value.collectionId!=='string'||
  env.BURIMUNSI_COLLECTION_ID&&env.BURIMUNSI_COLLECTION_ID!==value.collectionId)fail();
 const now=Math.floor(Date.now()/1000);
 if(!Number.isSafeInteger(value.createdAt)||!Number.isSafeInteger(value.expiresAt)||value.createdAt<=0||
  value.createdAt>now+5||value.expiresAt<=now||value.expiresAt-value.createdAt!==ttlSeconds)fail('native_email_reservation_unconfirmed',503);
 state.reserved=challenge;
 await assertManagedEmailOtp(env,challenge);
 return value;
}

/** No await separates this last request/ownership check from Auth dispatch.
 * A reservation may have committed during cancellation; it must retain its
 * cooldown without turning that cancellation into a privileged provider send. */
export function assertManagedEmailOtpDispatch(env,admission,challenge){
 const state=admissions.get(admission);if(!state||state.reserved!==challenge||state.dispatched)fail();
 requireActiveNativeRequest(state.request);
 const work=applicationWork(env);
 if(env.DB!==state.db||work!==state.work||env.DB.applicationWork!==work||env.BURIMUNSI_NATIVE_ENABLED!=='true'||
  JSON.stringify(applicationWorkTuple(work))!==state.tuple)fail('request_not_admitted',503);
 work.assertLocal();state.dispatched=true;
}

/** Native challenges fail closed even if native rollout is disabled later.
 * Ordinary Admin/member challenges never call this helper. A verified Auth
 * subject is passed only by the existing real GoTrue verification consumer. */
export async function assertManagedEmailOtp(env,challenge,authUserId=null,{consume=false}={}){
 if(env.BURIMUNSI_NATIVE_ENABLED!=='true')fail();
 const work=applicationWork(env);await work.assert();
 const db=env.DB,tuple=JSON.stringify(applicationWorkTuple(work));
 if(!['http_admin','http_collect'].includes(work.kind)||db?.applicationWork!==work)fail('request_not_admitted',503);
 await work.assert();
 const result=await db.prepare('SELECT private.burimunsi_managed_email_assert(?::text,?::uuid,?::boolean) AS allowed')
  .bind(challenge,authUserId,consume).first();
 await work.assert();
 if(env.DB!==db||db.applicationWork!==work||JSON.stringify(applicationWorkTuple(work))!==tuple)fail('request_not_admitted',503);
 if(result?.allowed!==true)fail();
}
