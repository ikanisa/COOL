// FCM HTTP v1 only. No legacy server key, alternate endpoint or provider text
// enters this adapter. The caller owns durable send-start/unknown-outcome state.
export const PUSH_CONTRACT='collect.android-push.v1';
export const PUSH_BATCH_LIMIT=1;
export const PUSH_PACKAGES=Object.freeze(['app.cool.mobile','app.cool.mobile.dev']);
export const isFcmProject=value=>typeof value==='string'&&/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(value);
const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(value);
const sha=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const fields=['contract','source_sha256','approval_sha256','project_id','android_package','admitted_from','batch_limit'];
export function validPushAdmission(value){return object(value)&&Object.keys(value).length===fields.length&&fields.every(key=>Object.hasOwn(value,key))&&
 value.contract===PUSH_CONTRACT&&sha(value.source_sha256)&&sha(value.approval_sha256)&&isFcmProject(value.project_id)&&PUSH_PACKAGES.includes(value.android_package)&&
 Number.isSafeInteger(value.admitted_from)&&value.admitted_from>0&&value.admitted_from<4102444800&&value.batch_limit===PUSH_BATCH_LIMIT;}

export function androidNotificationMessage({eventId,recipientId,token,androidPackage}){
 if(!uuid(eventId)||!uuid(recipientId)||typeof token!=='string'||!/^[-A-Za-z0-9_:]{1,3072}$/.test(token)||!PUSH_PACKAGES.includes(androidPackage))throw Error('invalid_push_payload');
 const message={token,notification:{title:'Collect',body:'Open Collect to view your updates.'},
  data:{collect_push_version:'2',collect_event_id:eventId,recipient_id:recipientId,deep_link:'/activity',type:'contribution'},
  android:{priority:'NORMAL',ttl:'300s',restricted_package_name:androidPackage,
   notification:{channel_id:'collect_contributions',tag:'collect:'+eventId,visibility:'PRIVATE'}}};
 if(new TextEncoder().encode(JSON.stringify(message)).length>4096)throw Error('invalid_push_payload');
 return message;
}

const TOKEN_URL='https://oauth2.googleapis.com/token',SCOPE='https://www.googleapis.com/auth/firebase.messaging';
const encoder=new TextEncoder(),limit=16384;
const base64url=bytes=>btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
const encode=value=>base64url(encoder.encode(JSON.stringify(value)));
function credentials(env){
 if(!isFcmProject(env.FCM_PROJECT_ID)||!PUSH_PACKAGES.includes(env.FCM_ANDROID_PACKAGE)||typeof env.FCM_SERVICE_ACCOUNT_JSON!=='string'||encoder.encode(env.FCM_SERVICE_ACCOUNT_JSON).length>16384)throw Error('fcm_configuration_unavailable');
 const value=JSON.parse(env.FCM_SERVICE_ACCOUNT_JSON);
 if(!object(value)||value.type!=='service_account'||value.project_id!==env.FCM_PROJECT_ID||
  typeof value.client_email!=='string'||!new RegExp('^[A-Za-z0-9._-]+@'+env.FCM_PROJECT_ID+'\\.iam\\.gserviceaccount\\.com$').test(value.client_email)||
  typeof value.private_key_id!=='string'||!/^[-A-Za-z0-9_]{1,128}$/.test(value.private_key_id)||
  typeof value.private_key!=='string'||value.private_key.length>8192||!/^-----BEGIN PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]+-----END PRIVATE KEY-----\r?\n?$/.test(value.private_key)||
  value.token_uri!==TOKEN_URL||(value.universe_domain!==undefined&&value.universe_domain!=='googleapis.com'))throw Error('fcm_configuration_unavailable');
 return value;
}
async function boundedJson(response,track,onUncertain){
 const declared=response.headers.get('content-length');if(declared!==null&&(!/^\d+$/.test(declared)||Number(declared)>limit)){
  if(response.body)track(response.body.cancel().catch(onUncertain));throw Error('provider_response_unconfirmed');
 }
 const chunks=[];let bytes=0,reader,complete=false;
 try{
  if(response.body){reader=response.body.getReader();while(true){const next=await reader.read();if(next.done){complete=true;break;}
   if(!(next.value instanceof Uint8Array)||next.value.byteLength>limit-bytes)throw Error('provider_response_unconfirmed');
   chunks.push(next.value);bytes+=next.value.byteLength;
  }}
  const result=new Uint8Array(bytes);let offset=0;for(const chunk of chunks){result.set(chunk,offset);offset+=chunk.byteLength;}
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(result));
 }finally{if(reader&&!complete)track(reader.cancel().catch(onUncertain));reader?.releaseLock();}
}
export function fcmRetryAfter(value,nowSeconds){
 if(value===null)return 0;
 const seconds=/^\d{1,9}$/.test(value)?Number(value):Math.ceil((Date.parse(value)-nowSeconds*1000)/1000);
 // Never shorten a provider-mandated delay. Out-of-contract delays stop work.
 return Number.isSafeInteger(seconds)&&seconds>=0&&seconds<=604800?seconds:null;
}
function rejection(response,body,nowSeconds){
 const status=response.status,code=body?.error?.status;
 const fcmCodes=Array.isArray(body?.error?.details)?body.error.details.filter(value=>value?.['@type']==='type.googleapis.com/google.firebase.fcm.v1.FcmError').map(value=>value.errorCode):[];
 if(status===404&&code==='NOT_FOUND'&&fcmCodes.length===1&&fcmCodes[0]==='UNREGISTERED')return {kind:'rejected',code:'invalid_registration',httpStatus:status,disableDevice:true};
 if((status===429&&code==='RESOURCE_EXHAUSTED')||(status===503&&code==='UNAVAILABLE')||(status===500&&code==='INTERNAL')){
  const delay=fcmRetryAfter(response.headers.get('retry-after'),nowSeconds);
  return delay===null?{kind:'rejected',code:'retry_after_unreviewed',httpStatus:status}:
   {kind:'retry',code:status===429?'provider_throttled':'provider_unavailable',httpStatus:status,retryAfterSeconds:delay};
 }
 if(status>=400&&status<500&&object(body?.error)&&typeof code==='string')return {kind:'rejected',code:status===401||status===403?'provider_auth_rejected':'provider_request_rejected',httpStatus:status};
 return {kind:'unknown',code:'delivery_unconfirmed',httpStatus:status>=100&&status<=599?status:null};
}

export function createFcmSender(env,{fetchImpl=fetch,now=()=>Math.floor(Date.now()/1000),track=promise=>{void promise.catch(()=>{});},onUncertain=(_label)=>{}}={}){
 const config=credentials(env),projectId=config.project_id,androidPackage=env.FCM_ANDROID_PACKAGE;
 let cached=null,keyPromise=null;
 const key=()=>keyPromise??=(async()=>{
  const raw=config.private_key.replace(/-----[^-]+-----|\s+/g,''),bytes=Uint8Array.from(atob(raw),character=>character.charCodeAt(0));
  const result=await crypto.subtle.importKey('pkcs8',bytes,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  if(result.algorithm.modulusLength<2048||result.algorithm.modulusLength>4096)throw Error('fcm_configuration_unavailable');return result;
 })();
 async function prepare(){
  const at=now();let token,authDelay=60;
  if(cached&&cached.expiresAt>at+60)token=cached.token;
  else try{
   const header=encode({alg:'RS256',typ:'JWT',kid:config.private_key_id}),claims=encode({iss:config.client_email,scope:SCOPE,aud:TOKEN_URL,iat:at,exp:at+300}),input=header+'.'+claims;
   const signature=base64url(new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',await key(),encoder.encode(input))));
   const reply=await fetchImpl(TOKEN_URL,{method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:input+'.'+signature}).toString()});
   const requestedDelay=fcmRetryAfter(reply.headers.get('retry-after'),at);
   if(requestedDelay===null){if(reply.body)track(reply.body.cancel().catch(()=>onUncertain('push_oauth')));return {kind:'rejected',code:'retry_after_unreviewed',httpStatus:reply.status};}
   authDelay=Math.max(authDelay,requestedDelay);
   const body=await boundedJson(reply,track,()=>onUncertain('push_oauth'));
   if(reply.status!==200)return {kind:reply.status>=400&&reply.status<500&&reply.status!==429?'rejected':'retry',code:'provider_auth_unavailable',httpStatus:reply.status,retryAfterSeconds:authDelay};
   if(typeof body?.access_token!=='string'||!/^[\x21-\x7e]{1,8192}$/.test(body.access_token)||body.token_type!=='Bearer'||!Number.isSafeInteger(body.expires_in)||body.expires_in<60||body.expires_in>3600){
    onUncertain('push_oauth');return {kind:'retry',code:'provider_auth_unavailable',httpStatus:200,retryAfterSeconds:authDelay};
   }
   token=body.access_token;cached={token,expiresAt:at+body.expires_in};
  }catch{onUncertain('push_oauth');return {kind:'retry',code:'provider_auth_unavailable',httpStatus:null,retryAfterSeconds:authDelay};}
  // A token acquisition failure has sent no notification. The caller must
  // recheck current authority and commit send-start before invoking this closure.
  return {kind:'ready',async send(message){
   try{const expected=androidNotificationMessage({eventId:message?.data?.collect_event_id,recipientId:message?.data?.recipient_id,token:message?.token,androidPackage});
    if(JSON.stringify(message)!==JSON.stringify(expected))throw Error('invalid_push_payload');
   }catch{return {kind:'rejected',code:'invalid_push_payload',httpStatus:null};}
   try{
    const reply=await fetchImpl('https://fcm.googleapis.com/v1/projects/'+projectId+'/messages:send',{
     method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({validate_only:false,message})});
    const body=await boundedJson(reply,track,()=>onUncertain('push'));
    if(reply.status===200&&typeof body?.name==='string'&&new RegExp('^projects/'+projectId+'/messages/[-A-Za-z0-9_:%.~]{1,250}$').test(body.name))return {kind:'accepted',messageId:body.name,httpStatus:200};
    const outcome=rejection(reply,body,now());if(outcome.kind==='unknown')onUncertain('push');return outcome;
   }catch{onUncertain('push');return {kind:'unknown',code:'delivery_unconfirmed',httpStatus:null};}
  }};
 }
 return Object.freeze({available:true,projectId,androidPackage,prepare});
}
