import {MANAGED_SUPABASE_ORIGIN,verifyDeploymentProfile} from './deployment-profile.js';
import {nativeRequestBodyLimit,readNativeBody,requireActiveNativeRequest} from './domain/burimunsi/wire/request-boundary.mjs';

export const DIRECT_SUPABASE_INGRESS_MODE='supabase_direct_v1';
const NATIVE_INGRESS_HEADER='X-Collect-Native-Ingress';
const encoder=new TextEncoder();
const hex=bytes=>Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
const deny=(code='native_ingress_denied',status=401)=>{
 const error=new Error(code);error.name='NativeIngressError';error.code=code;error.status=status;throw error;
};

/** Direct Supabase requests do not provide a verified client network identity.
 * All of them share one project-stable abuse bucket. Existing database-backed
 * account/installation budgets and authentication are still mandatory. The
 * bucket is a public label, not a credential, IP witness or proof of origin. */
export async function admitDirectSupabaseNativeIngress(request,env){
 const profile=await verifyDeploymentProfile(env);
 if(env.COLLECT_NATIVE_INGRESS_MODE!==DIRECT_SUPABASE_INGRESS_MODE||
   env.COLLECT_DEPLOYMENT_PROFILE===undefined||profile.mode!=='managed'||
   profile.supabase_origin!==MANAGED_SUPABASE_ORIGIN||env.SUPABASE_URL!==profile.supabase_origin||
   env.APP_ENVIRONMENT!==profile.environment||env.BURIMUNSI_NATIVE_ENABLED!=='true')
  deny('native_ingress_unconfigured',503);
 requireActiveNativeRequest(request);
 const url=new URL(request.url),path=url.pathname;
 if(url.origin!==profile.supabase_origin||url.username||url.password||url.hash||url.href.length>8192||
   !['GET','POST','PATCH'].includes(request.method)||/%|\\|\/\//.test(path)||
   path.split('/').some(part=>part==='.'||part==='..')||
   !(path==='/v1/burimunsi'||path.startsWith('/v1/burimunsi/')))deny();
 // Preserve exact logical target and body limits before opening the database.
 // Forwarded IP/Worker headers and a forged old ingress token provide no
 // network authority and are stripped from the downstream request.
 const limit=nativeRequestBodyLimit(request.method,url.href.slice(url.origin.length));
 const bytes=request.method==='GET'?undefined:await readNativeBody(request,{maxBytes:limit});
 requireActiveNativeRequest(request);
 const headers=new Headers(request.headers);
 for(const name of [NATIVE_INGRESS_HEADER,'cf-connecting-ip','cf-worker','x-forwarded-for','x-real-ip','true-client-ip'])headers.delete(name);
 const admitted=new Request(request.url,{method:request.method,headers,body:bytes,signal:request.signal});
 const globalBucket=hex(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(
  'collect.native.supabase-direct.global-budget.v1|'+MANAGED_SUPABASE_ORIGIN))));
 requireActiveNativeRequest(admitted);
 return Object.freeze({request:admitted,networkBucket:async candidate=>{
  requireActiveNativeRequest(candidate);
  if(candidate!==admitted)deny();
  return globalBucket;
 }});
}
