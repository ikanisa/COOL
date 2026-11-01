import {verifyDeploymentProfile} from '../../supabase/functions/_shared/deployment-profile.js';

const UPSTREAM='http://api-gw:8000';
const REQUEST_LIMIT=16384,RESPONSE_LIMIT=65536;
const safeHeaders={'Cache-Control':'no-store, no-transform','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
const requestHeaders=new Set(['authorization','apikey','content-type','accept','accept-language','x-client-info','x-supabase-api-version','origin','cookie']);
const hopHeaders=new Set(['connection','keep-alive','proxy-authenticate','proxy-authorization','te','trailer','transfer-encoding','upgrade','content-length','content-encoding']);
const phoneTypes=new Set(['sms','phone_change','phone']);
const modes=new Set(['opensms_hook','twilio','twilio_verify']);

function failure(status,code,cors={}){
 return Response.json({code,message:code==='phone_requires_collect'?'Use the Collect account flow for phone verification.':'The identity request could not be completed.'},
  {status,headers:{...safeHeaders,...cors}});
}
async function limitedBytes(stream,limit,signal){
 if(!stream)return new Uint8Array();
 const reader=stream.getReader(),parts=[];let size=0,listener;
 const interrupted=new Promise((_,reject)=>{
  listener=()=>reject(Error('deadline'));
  if(signal.aborted)listener();else signal.addEventListener('abort',listener,{once:true});
 });
 try{
  while(true){
   const chunk=await Promise.race([reader.read(),interrupted]);
   if(chunk.done)break;
   size+=chunk.value.length;if(size>limit)throw Error('body_limit');parts.push(chunk.value);
  }
  const bytes=new Uint8Array(size);let at=0;for(const part of parts){bytes.set(part,at);at+=part.length;}return bytes;
 }finally{
  signal.removeEventListener('abort',listener);
  // Do not leave a slow or oversized upstream/body stream running after denial.
  void reader.cancel().catch(()=>{});
 }
}
function parseObject(bytes){
 const object=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
 if(!object||typeof object!=='object'||Array.isArray(object))throw Error('invalid_json');
 return object;
}
function phoneFields(entries){
 // encoding/json matches exported Go fields case-insensitively. Checking only
 // lowercase keys would permit {Phone:...} or {TYPE:phone_change} bypasses.
 return [...entries].some(([key,value])=>{
  key=key.toLowerCase();
  return key==='phone'||key==='channel'||key==='factor_type'&&String(value).toLowerCase()==='phone'||
   key==='type'&&phoneTypes.has(String(value).toLowerCase());
 });
}
function forwardedHeaders(source){
 const result=new Headers();
 for(const [key,value] of source)if(requestHeaders.has(key.toLowerCase()))result.set(key,value);
 return result;
}
function canonicalAuthPath(path){
 // GoTrue routes use literal segments. Reject encoded separators, dot segments,
 // Unicode and alternate spellings instead of relying on two decoders agreeing.
 return /^\/auth\/v1(?:\/[A-Za-z0-9_-]+)*\/?$/.test(path);
}

/** Route *every* public /auth/v1 path through this handler. The HTTP ingress must
 * reject raw encoded/dot/backslash aliases before constructing its Request.
 * Collect's trusted API uses the private api-gw directly; no client header can
 * authorize a bypass here. Token/OAuth/email semantics remain GoTrue-owned.
 */
export function createAuthPhoneProxy(env,{fetchImpl=fetch}={}){
 let validated;
 async function configuration(){
  validated??=(async()=>{
   const profile=await verifyDeploymentProfile(env);
   if(env.COLLECT_DEPLOYMENT_PROFILE===undefined||profile.mode!=='self_hosted'||
    env.SUPABASE_URL!==profile.supabase_origin||env.APP_ENVIRONMENT!==profile.environment||
    env.SUPABASE_INTERNAL_URL!==UPSTREAM||!modes.has(env.AUTH_PHONE_DELIVERY_MODE))throw Error('configuration');
   if(env.AUTH_PHONE_DELIVERY_MODE==='opensms_hook'&&env.AUTH_WHATSAPP_ENABLED==='true')throw Error('configuration');
   return profile;
  })();
  return validated;
 }
 return async request=>{
  let profile;try{profile=await configuration();}catch{return failure(503,'auth_unavailable');}
  const url=new URL(request.url),allowedOrigins=new Set([profile.supabase_origin,profile.member_api_origin,profile.admin_origin,profile.public_origin]);
  if(url.origin!==profile.supabase_origin)return failure(421,'origin_unavailable');
  const origin=request.headers.get('Origin');
  if(origin&&!allowedOrigins.has(origin))return failure(403,'origin_unavailable');
  const cors=origin?{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Credentials':'true','Vary':'Origin'}:{};
  if(!canonicalAuthPath(url.pathname)||url.href.length>8192||url.hash)return failure(400,'invalid_request',cors);
  if(request.method==='OPTIONS'){
   const method=request.headers.get('Access-Control-Request-Method');
   const headers=(request.headers.get('Access-Control-Request-Headers')??'').split(',').map(v=>v.trim().toLowerCase()).filter(Boolean);
   if(!origin||!['GET','HEAD','POST','PUT','PATCH','DELETE'].includes(method)||headers.some(value=>!requestHeaders.has(value)))return failure(403,'origin_unavailable',cors);
   return new Response(null,{status:204,headers:{...safeHeaders,...cors,'Access-Control-Allow-Methods':method,'Access-Control-Allow-Headers':headers.join(', '),'Access-Control-Max-Age':'600'}});
  }
  if(!['GET','HEAD','POST','PUT','PATCH','DELETE'].includes(request.method))return failure(405,'method_not_allowed',cors);
  const path=url.pathname.replace(/\/$/,'').slice('/auth/v1'.length)||'/';
  const smsOnly=env.AUTH_PHONE_DELIVERY_MODE==='opensms_hook';
  const headers=forwardedHeaders(request.headers);
  const signal=AbortSignal.any([request.signal,AbortSignal.timeout(15000)]);
  const fetchUpstream=(path,options={})=>fetchImpl(UPSTREAM+'/auth/v1'+path,{method:request.method,headers,signal,redirect:'manual',...options});
  let bytes,upstreamStarted=false;
  try{
   const length=request.headers.get('Content-Length');
   if(length!==null&&(!/^\d+$/.test(length)||Number(length)>REQUEST_LIMIT))return failure(413,'request_too_large',cors);
   bytes=await limitedBytes(request.body,REQUEST_LIMIT,signal);
   const phoneRoute=['/otp','/verify','/signup','/user','/resend'].includes(path)||/^\/factors(?:\/[^/]+\/(?:challenge|verify))?$/.test(path);
   const jsonType=/^application\/json(?:\s*;|$)/i.test(request.headers.get('Content-Type')??'');
   let body={};
   if(bytes.length){
    if(phoneRoute&&!jsonType)return failure(415,'json_required',cors);
    if(jsonType){try{body=parseObject(bytes);}catch{return failure(400,'invalid_request',cors);}}
   }else if(phoneRoute&&!['GET','HEAD'].includes(request.method))return failure(400,'invalid_request',cors);
   if(smsOnly&&(phoneFields(url.searchParams)||phoneFields(Object.entries(body))))return failure(403,'phone_requires_collect',cors);
   const guestIdentityChange=path==='/user'&&request.method==='PUT'&&Object.keys(body).some(key=>['email','phone'].includes(key.toLowerCase()))||path==='/user/identities/authorize';
   if(guestIdentityChange||smsOnly&&(path==='/reauthenticate'||/^\/factors\/[^/]+\/(?:challenge|verify)$/.test(path))){
    // These routes can invoke phone delivery without a phone in the request.
    // Read the real current user/factor through GoTrue; no decoded bearer,
    // caller metadata, or forwarded header chooses the delivery capability.
    if(!headers.get('Authorization'))return failure(401,'invalid_session',cors);
    upstreamStarted=true;
    const userResponse=await fetchUpstream('/user',{method:'GET'});
    if(userResponse.status!==200)return failure(userResponse.status===401?401:503,'invalid_session',cors);
    const user=parseObject(await limitedBytes(userResponse.body,RESPONSE_LIMIT,signal));
    if(guestIdentityChange){
     if(typeof user.is_anonymous!=='boolean')return failure(503,'auth_unavailable',cors);
     if(user.is_anonymous)return failure(403,'guest_requires_collect',cors);
    }else if(path==='/reauthenticate'){
     // Pinned GoTrue prefers a nonempty email; without one it falls back to SMS.
     if(typeof user.email!=='string'||!user.email)return failure(403,'phone_requires_collect',cors);
    }else{
     const factorId=path.split('/')[2],factor=Array.isArray(user.factors)?user.factors.find(f=>f?.id===factorId):null;
     if(!factor||!['totp','webauthn'].includes(factor.factor_type))return failure(403,'phone_requires_collect',cors);
    }
   }
   upstreamStarted=true;
   const response=await fetchUpstream(path+url.search,{...(bytes.length?{body:bytes}:{})});
   const responseBytes=await limitedBytes(response.body,RESPONSE_LIMIT,signal),output=new Headers();
   for(const [key,value] of response.headers)if(!hopHeaders.has(key.toLowerCase())&&!key.toLowerCase().startsWith('access-control-'))output.append(key,value);
   // Preserve separate OAuth cookies when the runtime exposes getSetCookie.
   if(response.headers.getSetCookie){output.delete('Set-Cookie');for(const value of response.headers.getSetCookie())output.append('Set-Cookie',value);}
   for(const [key,value] of Object.entries({...safeHeaders,...cors}))output.set(key,value);
   return new Response(request.method==='HEAD'||[204,205,304].includes(response.status)?null:responseBytes,{status:response.status,headers:output});
  }catch(error){return failure(error?.message==='body_limit'&&!upstreamStarted?413:503,'auth_unavailable',cors);}
 };
}
