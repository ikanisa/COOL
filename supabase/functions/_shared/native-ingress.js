import {verifyDeploymentProfile} from './deployment-profile.js';
import {readNativeBody,requireActiveNativeRequest,nativeRequestBodyLimit} from './domain/burimunsi/wire/request-boundary.mjs';
import {parseWire} from './domain/burimunsi/wire/runtime.mjs';

export const NATIVE_INGRESS_HEADER='X-Collect-Native-Ingress';
const FORMAT='collect.native-ingress.v1',PROOF='collect.native-ingress.edge-proof.v2',LEGACY_PROOF='collect.native-ingress.edge-proof.v1';
export const MANAGED_PROOF='collect.native-ingress.managed-edge-proof.v1';
export const MANAGED_WORKER_GUARD='cloudflare_worker_presence_reject';
export const NATIVE_WORKER_GUARD='origin_cf_worker_presence_reject';
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

export function nativeWorkerGuardExpression(origin){
 const host=new URL(origin).hostname;
 return '(http.host eq "'+host+'" and starts_with(http.request.uri.path, "/functions/v1/collect-api/v1/burimunsi") and cf.worker.upstream_zone ne "")';
}
/** Protected operational review provenance, not a cryptographic Cloudflare
 * attestation. The deployment owner records actual Tunnel/socket readback;
 * a CF header alone cannot commission a zone. Runtime socket admission and the
 * independently protected short-lived request HMAC remain required. */
async function configuration(env,clock){
 const profile=await verifyDeploymentProfile(env),now=clock();
 need(env.COLLECT_DEPLOYMENT_PROFILE!==undefined&&
  env.SUPABASE_URL===profile.supabase_origin&&env.APP_ENVIRONMENT===profile.environment&&Number.isSafeInteger(now),
  'native_ingress_unconfigured',503);
 const raw=env.COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON,hash=env.COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256;
 let proof;try{if(typeof raw==='string'&&raw.length<=8192)proof=JSON.parse(raw);}catch{}
 const legacy=proof?.format===LEGACY_PROOF;
 const fields=profile.mode==='managed'?['evidenceSha256','format','frontdoorOrigin','networkSource','profileSha256','pseudoIpv4',
  'reviewedAt','status','supabaseOrigin','workerGuard']:(legacy?['directTunnelOnly','evidenceSha256','expiresAt','format','nativeWorkerGuardExpression','nativeWorkerGuardRuleId',
  'profileSha256','protectedUnixSocket','pseudoIpv4','reviewedAt','status','supabaseOrigin','tunnelId']:
  ['directTunnelOnly','evidenceSha256','format','nativeWorkerGuard','profileSha256','protectedUnixSocket','pseudoIpv4',
   'reviewedAt','status','supabaseOrigin','tunnelId']);
 need(proof&&typeof proof==='object'&&!Array.isArray(proof)&&Object.keys(proof).sort().join('|')===fields.join('|')&&
  canonical(proof)===raw&&digest(hash)&&await sha(encoder.encode(raw))===hash&&proof.status==='reviewed'&&
  proof.profileSha256===env.COLLECT_DEPLOYMENT_PROFILE_SHA256&&proof.supabaseOrigin===profile.supabase_origin&&
  digest(proof.evidenceSha256)&&Number.isSafeInteger(proof.reviewedAt)&&proof.reviewedAt>0&&proof.reviewedAt<=now,
  'native_ingress_edge_unqualified',503);
 if(profile.mode==='managed'){
  // The record binds a reviewed deployment identity; it is not provider
  // attestation. The frontdoor must verify the actual Cloudflare route and
  // request provenance before signing a network identity.
  need(proof.format===MANAGED_PROOF&&proof.frontdoorOrigin===profile.member_api_origin&&
   proof.frontdoorOrigin!==profile.supabase_origin&&proof.networkSource==='cf-connecting-ip'&&
   proof.workerGuard===MANAGED_WORKER_GUARD&&proof.pseudoIpv4==='off',
   'native_ingress_edge_unqualified',503);
 }else{
  need([PROOF,LEGACY_PROOF].includes(proof.format)&&
  /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(proof.tunnelId)&&
  (legacy?typeof proof.nativeWorkerGuardRuleId==='string'&&/^[a-f0-9]{32}$/.test(proof.nativeWorkerGuardRuleId)&&
   proof.nativeWorkerGuardExpression===nativeWorkerGuardExpression(profile.supabase_origin)&&
   Number.isSafeInteger(proof.expiresAt)&&proof.expiresAt>proof.reviewedAt&&proof.expiresAt-proof.reviewedAt<=7*86400000:
   proof.nativeWorkerGuard===NATIVE_WORKER_GUARD)&&
  proof.directTunnelOnly===true&&proof.protectedUnixSocket===true&&proof.pseudoIpv4==='off',
  'native_ingress_edge_unqualified',503);
 }
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
 // Review provenance is not an expiring authorization credential. Retain the
 // old v1 expiry field as historical metadata only. Each request still has its
 // own independently checked, short HMAC lifetime below.
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
async function authorityDigest(request,mode){
 const fields=[];
 for(const [name,value]of request.headers)if(name.startsWith('x-burimunsi-')||
  ['authorization','cookie','apikey','origin','content-type','x-collect-csrf','x-collect-requested-with','x-collect-review-reason'].includes(name)||
  mode==='managed'&&['idempotency-key','x-request-id','x-collect-admin'].includes(name))fields.push([name,value]);
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
/** Trusted frontdoor only. For self-hosting clientAddress comes from the
 * protected direct-Tunnel socket; for managed hosting it must come from the
 * separately qualified Cloudflare frontdoor. Both reject Worker subrequests.
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
   await sha(bytes),await authorityDigest(clean,config.profile.mode)];
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
 need(await authorityDigest(request,config.profile.mode)===headersHash);
 const bytes=await bodyBytes(request,route);need(await sha(bytes)===bodyHash);requireActiveNativeRequest(request);
 const after=clock();need(Number.isSafeInteger(after)&&at<=after+2000&&after-at<=MAX_AGE,'native_ingress_denied');
 const headers=new Headers(request.headers);headers.delete(NATIVE_INGRESS_HEADER);
 const token=Object.freeze({});pendingIngress.set(token,{request:replacement(request,bytes,headers),network,profile,policy,nonce,at,clock,mode:config.profile.mode});return token;
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

/** Legacy self-hosted entrypoint. Managed admission stays closed until its
 * real handler verifies first and claims through the fence-bound store. */
export async function admitNativeIngress(request,env,options={}){
 const token=await verifyNativeIngress(request,env,options),state=pendingIngress.get(token);
 pendingIngress.delete(token);
 need(state?.mode==='self_hosted','native_ingress_replay_unconfigured',503);
 return releaseNativeIngress(state);
}
