// Managed-cloud native frontdoor candidate. No route is installed by import.
// The deployed Cloudflare route must establish request provenance and block
// Worker subrequests before this module may sign a network identity.
import {verifyDeploymentProfile} from '../../supabase/functions/_shared/deployment-profile.js';
import {createNativeIngressSigner,NATIVE_INGRESS_HEADER} from '../../supabase/functions/_shared/native-ingress.js';
import {CONTRACT_VERSION} from '../../supabase/functions/_shared/domain/burimunsi/wire/native-contract.mjs';
import {admitUpstreamResponse, RESPONSE_SAFETY_HEADERS} from './upstream-response.js';

const PREFIX='/functions/v1/collect-api',NATIVE='/v1/burimunsi';
const allowed=new Set(['accept','accept-language','accept-encoding','authorization','apikey','cookie','origin',
 'content-type','content-length','idempotency-key','x-request-id','x-collect-admin','x-collect-csrf',
 'x-collect-requested-with','x-collect-review-reason']);
const fail=(status,code)=>Response.json({contractVersion:CONTRACT_VERSION,ok:false,error:{code}},
 {status,headers:{...RESPONSE_SAFETY_HEADERS,'x-burimunsi-contract':CONTRACT_VERSION}});
// For a host that cannot construct the handler: no proxy fallback or upstream
// work has occurred, and the native client still receives its exact contract.
export const managedNativeFrontdoorUnavailable=()=>fail(503,'native_service_unconfigured');

export function canonicalManagedClientAddress(value){
 if(typeof value!=='string'||!value||value.length>64||/[\s%,\[\]]/.test(value))throw Error('invalid_client_address');
 if(!value.includes(':')){
  const parts=value.split('.');
  if(parts.length!==4||parts.some(x=>!/^(0|[1-9][0-9]{0,2})$/.test(x)||Number(x)>255))throw Error('invalid_client_address');
  return parts.join('.');
 }
 if(!/^[0-9a-f:.]+$/i.test(value))throw Error('invalid_client_address');
 let host;try{host=new URL('http://['+value+']/').hostname;}catch{throw Error('invalid_client_address');}
 if(!host.startsWith('[')||!host.endsWith(']'))throw Error('invalid_client_address');
 const normalized=host.slice(1,-1);
 const mapped=/^::ffff:([a-f0-9]{1,4}):([a-f0-9]{1,4})$/.exec(normalized);
 if(mapped){const a=parseInt(mapped[1],16),b=parseInt(mapped[2],16);return [a>>8,a&255,b>>8,b&255].join('.');}
 // Cloudflare uses this address for cross-zone Worker subrequests; it must
 // never become a distinct trusted client network bucket.
 if(normalized==='2a06:98c0:3600::103')throw Error('invalid_client_address');
 return normalized;
}

function selectedPath(url){
 const path=url.pathname;
 if(/%|\\|\/\//.test(path)||path.split('/').some(part=>part==='.'||part==='..'))return null;
 const logical=path.startsWith(PREFIX+'/')?path.slice(PREFIX.length):path;
 return logical===NATIVE||logical.startsWith(NATIVE+'/')?logical+url.search:null;
}
function cleanHeaders(input){
 const output=new Headers();let total=0;
 for(const [name,value]of input){
  if(!allowed.has(name)&&!name.startsWith('x-burimunsi-'))continue;
  if(name.length>128||value.length>8192||(total+=name.length+value.length)>32768)throw Error('header_limit');
  output.set(name,value);
 }
 output.delete(NATIVE_INGRESS_HEADER);output.set('accept-encoding','identity');
 return output;
}
export async function createManagedNativeFrontdoor(env,{fetchImpl=fetch,clock=()=>Date.now()}={}){
 const profile=await verifyDeploymentProfile(env);
 if(env.COLLECT_DEPLOYMENT_PROFILE===undefined||profile.mode!=='managed'||
  env.SUPABASE_URL!==profile.supabase_origin||env.APP_ENVIRONMENT!==profile.environment||
  env.BURIMUNSI_NATIVE_ENABLED!=='true'||typeof fetchImpl!=='function')throw Error('managed_native_frontdoor_unconfigured');
 const sign=await createNativeIngressSigner(env,{clock});
 return async request=>{
  let dispatched=false;
  try{
   const url=new URL(request.url),path=selectedPath(url);
   if(url.origin!==profile.member_api_origin)return fail(403,'origin_denied');
   if(!path)return fail(404,'not_found');
   if(!['GET','POST','PATCH'].includes(request.method))return fail(405,'method_not_allowed');
   // Cloudflare documents CF-Worker on Worker fetch subrequests. Reject it
   // before accepting CF-Connecting-IP, dropping headers or reading a body.
   if(request.headers.has('cf-worker'))return fail(403,'native_ingress_network_denied');
   let address;try{address=canonicalManagedClientAddress(request.headers.get('cf-connecting-ip'));}catch{return fail(403,'native_ingress_network_denied');}
   const headers=cleanHeaders(request.headers),signal=AbortSignal.any([request.signal,AbortSignal.timeout(25000)]);
   if(request.method==='GET')headers.delete('content-length');
   const upstream=new Request(profile.supabase_origin+PREFIX+path,{method:request.method,headers,
    body:request.method==='GET'?undefined:request.body,duplex:'half',signal});
   const signed=await sign(upstream,address);
   // A failed or uncertain upstream mutation is never retried here.
   dispatched=true;
   const response=await fetchImpl(new Request(signed,{redirect:'manual'}));
   return await admitUpstreamResponse(response,signal) ?? fail(503,'backend_unavailable');
  }catch(error){
   // The size violation is known before any upstream dispatch. Once a fetch
   // was attempted, even malformed/oversized responses leave the mutation
   // outcome unknown and must not be converted into a definitive rejection.
   if(!dispatched&&error?.code==='CONTRACT_REQUEST_SIZE')return fail(413,'contract_request_size');
   return fail(503,'backend_unavailable');
  }
 };
}
