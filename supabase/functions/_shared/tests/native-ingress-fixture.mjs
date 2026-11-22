// Synthetic Cloud ingress policy, key and HTTP fixture.
import {createHash} from 'node:crypto';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../deployment-profile.js';
import {claimNativeIngress,createNativeIngressSigner,MANAGED_PROOF,MANAGED_WORKER_GUARD,verifyNativeIngress} from '../native-ingress.js';
export const now=1900000000000;
export const profile={format:'collect.deployment.v1',id:'ingress-fixture',mode:'managed',environment:'qualification',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.collect.example',
 admin_origin:'https://admin.collect.example',public_origin:'https://collect.example',google_callback_origin:'https://admin.collect.example'};
export const key=byte=>Buffer.alloc(32,byte).toString('base64');
export const canonical=value=>JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(name=>[name,value[name]])));
export const sha=value=>createHash('sha256').update(value).digest('hex');
export function environment(overrides={},proofChanges={}){
 const raw=canonicalProfile(profile),profileSha256=sha(raw);
 const proof=canonical({format:MANAGED_PROOF,status:'reviewed',profileSha256,supabaseOrigin:profile.supabase_origin,
  frontdoorOrigin:profile.member_api_origin,networkSource:'cf-connecting-ip',workerGuard:MANAGED_WORKER_GUARD,
  pseudoIpv4:'off',reviewedAt:now-10000,evidenceSha256:'c'.repeat(64),...proofChanges});
 return {COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:profileSha256,APP_ENVIRONMENT:'qualification',
  SUPABASE_URL:profile.supabase_origin,BURIMUNSI_NATIVE_ENABLED:'true',
  AUTH_PHONE_DELIVERY_MODE:'opensms_hook',AUTH_SMS_ENABLED:'false',AUTH_WHATSAPP_ENABLED:'false',
  COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON:proof,COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256:sha(proof),
  COLLECT_NATIVE_INGRESS_KEY_ID:'synthetic-ingress-v1',COLLECT_NATIVE_INGRESS_KEY_BASE64:key(5),
  DATA_ENCRYPTION_KEY:key(1),SESSION_ENCRYPTION_KEY:key(2),BURIMUNSI_PIN_PEPPER_BASE64:key(3),BURIMUNSI_CURSOR_KEY_BASE64:key(4),...overrides};
}
export function request({path='/functions/v1/collect-api/v1/burimunsi/session/login',body='{"phone":"+250788123456","pin":"0123"}',headers={},method='POST',signal}={}){
 return new Request(profile.supabase_origin+path,{method,headers:{'content-type':'application/json','x-burimunsi-installation':'fixture-installation',
  'x-burimunsi-collect-session':'synthetic-managed-session',...headers},body:method==='GET'?undefined:body,signal});
}
export async function signed(env=environment(),options={}){
 const signer=await createNativeIngressSigner(env,{clock:()=>now}),output=await signer(request(options),'192.0.2.1');
 const url=new URL(output.url);url.pathname=url.pathname.slice('/functions/v1/collect-api'.length);
 return new Request(url,{method:output.method,headers:output.headers,body:output.method==='GET'?undefined:await output.arrayBuffer(),signal:output.signal});
}

// In-process stand-in for the atomic claim; production always uses its database store.
export async function admitNativeIngress(request,env,options){
 return claimNativeIngress(await verifyNativeIngress(request,env,options),async()=>true);
}
