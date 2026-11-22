import {verifyDeploymentProfile} from './deployment-profile.js';
import {readNativeBody,requireActiveNativeRequest,nativeRequestBodyLimit} from './domain/burimunsi/wire/request-boundary.mjs';
import {parseWire} from './domain/burimunsi/wire/runtime.mjs';

export const NATIVE_INGRESS_HEADER='X-Collect-Native-Ingress';
const FORMAT='collect.native-ingress.v1';
export const MANAGED_PROOF='collect.native-ingress.managed-edge-proof.v1';
export const MANAGED_WORKER_GUARD='cloudflare_worker_presence_reject';
const PREFIX='/functions/v1/collect-api',MAX_AGE=30000;
const pendingIngress=new WeakMap();
const encoder=new TextEncoder(),hex=bytes=>Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
const canonical=value=>JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(key=>[key,value[key]])));
const identifier=value=>typeof value==='string'&&/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value);
const digest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
export class NativeIngressError extends Error {
 constructor(code='native_ingress_denied',status=401){super(code);this.name='NativeIngressError';this.code=code;this.status=status;}
}
const need=(ok,code='native_ingress_denied',status=401)=>{if(!ok)throw new NativeIngressError(code,status);};
function keyBytes(value){
 let bytes;try{if(typeof value==='string'&&value.length===44)bytes=Uint8Array.from(atob(value),c=>c.charCodeAt(0));}catch{}
 need(bytes?.length===32&&btoa(String.fromCharCode(...bytes))===value,'native_ingress_unconfigured',503);return bytes;
}
async function sha(value){return hex(new Uint8Array(await crypto.subtle.digest('SHA-256',value)));}
async function hmac(key,value){return new Uint8Array(await crypto.subtle.sign('HMAC',key,encoder.encode(value)));}
const importKey=bytes=>crypto.subtle.importKey('raw',bytes,{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);

/** The deployment owner records reviewed Cloudflare route configuration.
 * Provider provenance and a short-lived request HMAC remain independently required. */
async function configuration(env,clock){
 const profile=await verifyDeploymentProfile(env),now=clock();
 need(env.COLLECT_DEPLOYMENT_PROFILE!==undefined&&
  env.SUPABASE_URL===profile.supabase_origin&&env.APP_ENVIRONMENT===profile.environment&&Number.isSafeInteger(now),
  'native_ingress_unconfigured',503);
 const raw=env.COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON,hash=env.COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256;
 let proof;try{if(typeof raw==='string'&&raw.length<=8192)proof=JSON.parse(raw);}catch{}
 const fields=['evidenceSha256','format','frontdoorOrigin','networkSource','profileSha256','pseudoIpv4',
  'reviewedAt','status','supabaseOrigin','workerGuard'];
 need(proof&&typeof proof==='object'&&!Array.isArray(proof)&&Object.keys(proof).sort().join('|')===fields.join('|')&&
  canonical(proof)===raw&&digest(hash)&&await sha(encoder.encode(raw))===hash&&proof.status==='reviewed'&&
  proof.profileSha256===env.COLLECT_DEPLOYMENT_PROFILE_SHA256&&proof.supabaseOrigin===profile.supabase_origin&&
  digest(proof.evidenceSha256)&&Number.isSafeInteger(proof.reviewedAt)&&proof.reviewedAt>0&&proof.reviewedAt<=now,
  'native_ingress_edge_unqualified',503);
 need(proof.format===MANAGED_PROOF&&proof.frontdoorOrigin===profile.member_api_origin&&
  proof.frontdoorOrigin!==profile.supabase_origin&&proof.networkSource==='cf-connecting-ip'&&
  proof.workerGuard===MANAGED_WORKER_GUARD&&proof.pseudoIpv4==='off',
  'native_ingress_edge_unqualified',503);
 const id=env.COLLECT_NATIVE_INGRESS_KEY_ID,rawKey=env.COLLECT_NATIVE_INGRESS_KEY_BASE64,bytes=keyBytes(rawKey);
 need(identifier(id),'native_ingress_unconfigured',503);
 // Retained current and prior payload/session/native secrets must keep their
 // independent purposes. This code receives env values; it opens no key file.
 for(const name of ['DATA_ENCRYPTION_KEY','SESSION_ENCRYPTION_KEY','BURIMUNSI_PIN_PEPPER_BASE64','BURIMUNSI_CURSOR_KEY_BASE64'])
  need(!env[name]||env[name]!==rawKey,'native_ingress_unconfigured',503);
 for(const name of ['DATA_DECRYPTION_KEYS_JSON','SESSION_DECRYPTION_KEYS_JSON'])if(env[name]){
  let ring;try{ring=parseWire(env[name],4096);}catch{}
  need(ring&&typeof ring==='object'&&!Array.isArray(ring)&&Object.keys(ring).length<=8&&
   !Object.values(ring).includes(rawKey),'native_ingress_unconfigured',503);
 }
 const root=await importKey(bytes);
 const signing=await importKey(await hmac(root,'collect.native-ingress.signing-key.v1'));
 const network=await importKey(await hmac(root,'collect.native-ingress.network-key.v1'));
 return {profile,id,hash,signing,network,clock};
}
function target(request,physical){
 const url=new URL(request.url),path=url.pathname;
 need(request.method==='GET'||request.method==='POST'||request.method==='PATCH');
 need(!url.username&&!url.password&&!url.hash&&url.href.length<=8192&&!/%|\\|\/\//.test(path)&&
  !path.split('/').some(part=>part==='.'||part==='..'));
 const logical=physical&&path.startsWith(PREFIX+'/')?path.slice(PREFIX.length):physical?null:path;
 need(logical==='/v1/burimunsi'||logical?.startsWith('/v1/burimunsi/'));
 // Use the serialized target only for the cap so even a bare '?' stays at 8 KiB.
 // Keep the original signed path and all authority/HMAC checks unchanged.
 const bodyLimit=nativeRequestBodyLimit(request.method,url.href.slice(url.origin.length+(physical?PREFIX.length:0)));
 return {origin:url.origin,path:logical+url.search,bodyLimit};
}
async function authorityDigest(request){
 const fields=[];
 for(const [name,value]of request.headers)if(name.startsWith('x-burimunsi-')||
  ['authorization','cookie','apikey','origin','content-type','x-collect-csrf','x-collect-requested-with','x-collect-review-reason',
   'idempotency-key','x-request-id','x-collect-admin'].includes(name))fields.push([name,value]);
 fields.sort(([a],[b])=>a.localeCompare(b));return sha(encoder.encode(JSON.stringify(fields)));
}
async function bodyBytes(request,route){return request.method==='GET'?new Uint8Array():readNativeBody(request,{maxBytes:route.bodyLimit});}
function replacement(request,bytes,headers){
 return new Request(request.url,{method:request.method,headers,body:request.method==='GET'?undefined:bytes,signal:request.signal});
}
const message=(parts,request,path)=>JSON.stringify([FORMAT,...parts,request.method,'collect-api',path]);
function packed(parts){return btoa(String.fromCharCode(...encoder.encode(JSON.stringify(parts)))).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');}
function unpacked(value){
 let raw,parts;try{
  if(typeof value==='string'&&value.length<=2048&&/^[A-Za-z0-9_-]+$/.test(value)){
   raw=new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(atob(value.replaceAll('-','+').replaceAll('_','/')+'='.repeat((4-value.length%4)%4)),c=>c.charCodeAt(0)));
   parts=JSON.parse(raw);
  }
 }catch{}
 need(Array.isArray(parts)&&parts.length===10&&packed(parts)===value);return parts;
}
/** Trusted frontdoor only. clientAddress comes from the independently
 * qualified Cloudflare frontdoor. Reject Worker subrequests.
 * Cloudflare adds that marker to all Worker fetch subrequests after WAF evaluation:
 * https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-worker */
export async function createNativeIngressSigner(env,{clock=()=>Date.now()}={}){
 const config=await configuration(env,clock);
 return async(request,clientAddress)=>{
  need(!request.headers.has('cf-worker'),'native_ingress_network_denied',403);
  requireActiveNativeRequest(request);const route=target(request,true),now=clock();
  need(route.origin===config.profile.supabase_origin,'native_ingress_edge_unqualified',503);
  need(typeof clientAddress==='string'&&clientAddress.length<=64&&/^[0-9a-f:.]+$/.test(clientAddress));
  const headers=new Headers(request.headers);headers.delete(NATIVE_INGRESS_HEADER);
  const clean=new Request(request,{headers}),bytes=await bodyBytes(clean,route);
  const network=hex(await hmac(config.network,'collect.native-ingress.network.v1|'+clientAddress));
  const parts=[1,config.id,env.COLLECT_DEPLOYMENT_PROFILE_SHA256,config.hash,now,crypto.randomUUID(),network,
   await sha(bytes),await authorityDigest(clean)];
  parts.push(hex(await hmac(config.signing,message(parts,clean,route.path))));
  headers.set(NATIVE_INGRESS_HEADER,packed(parts));return replacement(clean,bytes,headers);
 };
}
/** Verify before database work. The opaque token carries no dispatchable
 * request or network witness; only a committed single-use claim releases it. */
export async function verifyNativeIngress(request,env,{clock=()=>Date.now()}={}){
 const config=await configuration(env,clock),route=target(request,false);
 need(route.origin===config.profile.supabase_origin);
 const parts=unpacked(request.headers.get(NATIVE_INGRESS_HEADER)),signature=parts.pop();
 const [version,id,profile,policy,at,nonce,network,bodyHash,headersHash]=parts,now=clock();
 need(version===1&&id===config.id&&profile===env.COLLECT_DEPLOYMENT_PROFILE_SHA256&&policy===config.hash&&
  Number.isSafeInteger(at)&&at<=now+2000&&now-at<=MAX_AGE&&
  typeof nonce==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(nonce)&&digest(network)&&digest(bodyHash)&&digest(headersHash)&&digest(signature));
 const signatureBytes=Uint8Array.from(signature.match(/../g),value=>parseInt(value,16));
 need(await crypto.subtle.verify('HMAC',config.signing,signatureBytes,encoder.encode(message(parts,request,route.path))));
 need(await authorityDigest(request)===headersHash);
 const bytes=await bodyBytes(request,route);need(await sha(bytes)===bodyHash);requireActiveNativeRequest(request);
 const after=clock();need(Number.isSafeInteger(after)&&at<=after+2000&&after-at<=MAX_AGE,'native_ingress_denied');
 const headers=new Headers(request.headers);headers.delete(NATIVE_INGRESS_HEADER);
 const token=Object.freeze({});pendingIngress.set(token,{request:replacement(request,bytes,headers),network,profile,policy,nonce,at,clock});return token;
}
function releaseNativeIngress(state){
 const admitted=state.request,witnesses=new WeakMap([[admitted,state.network]]);
 return Object.freeze({request:admitted,networkBucket:async candidate=>{
  requireActiveNativeRequest(candidate);const now=state.clock();need(witnesses.has(candidate)&&Number.isSafeInteger(now)&&state.at<=now+2000&&now-state.at<=MAX_AGE);
  return witnesses.get(candidate);
 }});
}

/** Consume must resolve true only after an atomic, fence-bound claim commits.
 * It must bound its own wait, abandon unconfirmed work and never retry. */
export async function claimNativeIngress(token,consume){
 const state=pendingIngress.get(token);need(state,'native_ingress_unconfigured',503);
 pendingIngress.delete(token);need(typeof consume==='function','native_ingress_unconfigured',503);
 const now=state.clock();need(Number.isSafeInteger(now)&&state.at<=now+2000&&now-state.at<=MAX_AGE);
 requireActiveNativeRequest(state.request);
 let claimed;try{claimed=await consume({nonce:state.nonce,profile:state.profile,policy:state.policy,issuedAtMs:state.at});}
 catch{throw new NativeIngressError('native_ingress_store_unavailable',503);}
 need(claimed===true);requireActiveNativeRequest(state.request);
 const after=state.clock();need(Number.isSafeInteger(after)&&state.at<=after+2000&&after-state.at<=MAX_AGE);
 return releaseNativeIngress(state);
}
