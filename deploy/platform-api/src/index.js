import {ApiError,json,readJson,first,now} from './core.js';
import {syncEvents} from './sync.js';
import {handleAuth,requireSession} from './auth.js';
import {handleAdmin} from './admin_bridge.js';
import {publicGroups} from './groups.js';
import {notificationEvents} from './notifications.js';
import {evidenceRoute} from './evidence.js';
import {challengeRoute} from './challenge.js';
import {receiptRoute} from './receipts.js';
import {privacyPortalRoute} from './privacy_portal.js';
import {dispatchOperation,publicRpcNames} from './operations.js';
import {recordPlatformHealth,platformHealthComponent} from './observability.js';
import {drainMomoJobs} from './momo_pipeline.js';
import {momoGatewayRoute} from './momo_gateway.js';
const PUBLIC_OPERATIONS=new Set(publicRpcNames);
function cors(request,env) {
 const origin=request.headers.get('Origin');
 const allowed=(env.ALLOWED_ORIGINS??'').split(',').map(s=>s.trim()).filter(Boolean);
 if(origin&&!allowed.includes(origin))throw new ApiError(403,'origin_denied','This origin is not allowed.');
 return origin?{'Access-Control-Allow-Origin':origin,'Vary':'Origin','Access-Control-Allow-Methods':'GET,POST,OPTIONS','Access-Control-Allow-Headers':'Authorization,Content-Type,X-Request-ID','Access-Control-Max-Age':'600'}:{};
}
async function publicRpc(operation,body,env) {
 const row=await first(env,'SELECT value_json FROM runtime_config WHERE key=?',operation==='get_active_policy_document'?`policy:${body.p_document_key??body.p_slug??body.p_kind??body.slug}`:operation);
 if(!row)throw new ApiError(503,'configuration_unavailable','This information is unavailable. Please contact support.');
 return JSON.parse(row.value_json);
}
// Operator-only source admission fence. This does not cancel already-running
// requests, fence direct storage writers, or prove a final migration freeze.
function sourceFreezeState(env) {
 try {
  const flag=env.COLLECT_SOURCE_FROZEN,epoch=env.COLLECT_SOURCE_FREEZE_EPOCH;
  if((flag===undefined||flag==='false')&&epoch===undefined)return {state:'open',epoch:null};
  if(flag==='true'&&typeof epoch==='string'&&epoch.length===64&&/^[a-f0-9]{64}$/.test(epoch))return {state:'frozen',epoch};
 }catch{}
 return {state:'invalid',epoch:null};
}
function sourceFreezeCode(freeze) {
 return freeze.state==='frozen'?'source_frozen':'source_freeze_configuration_invalid';
}
function sourceFreezeResponse(request,freeze) {
 if(freeze.state==='invalid')return json({code:sourceFreezeCode(freeze),
  message:'Source access is unavailable. The request was not processed.',
  request_processed:false,source_freeze:freeze},503);
 const metadata=request.method==='GET'&&new URL(request.url).pathname==='/source-freeze-status';
 if(freeze.state==='open')return metadata?json({service:'collect-platform-api',
  database:'not_checked',source_freeze:freeze,request_processed:false}):null;
 if(metadata||(request.method==='GET'&&new URL(request.url).pathname==='/health'))
  return json({service:'collect-platform-api',database:'not_checked',
   source_freeze:freeze,request_processed:false});
 return json({code:sourceFreezeCode(freeze),
  message:'Source access is paused. The request was not processed.',
  request_processed:false,source_freeze:freeze},503);
}
export default {
 async scheduled(_event,env,ctx){
  const freeze=sourceFreezeState(env);
  if(freeze.state!=='open')throw new Error(sourceFreezeCode(freeze));
  ctx.waitUntil(drainMomoJobs(env));
 },
 async fetch(request,env,ctx){
  const freeze=sourceFreezeState(env),fenced=sourceFreezeResponse(request,freeze);
  if(fenced)return fenced;
  const requestId=crypto.randomUUID(),started=performance.now();let headers={};
  const observeResponse=response=>{
   if(response.status===429||response.status>=500)recordPlatformHealth({status:response.status,
    component:platformHealthComponent(new URL(request.url).pathname),requestId:null,
    sourceId:env.BUILD_SOURCE_ID,elapsedMs:performance.now()-started});
   return response;
  };
  try{
   const portal=await privacyPortalRoute(request,env);if(portal)return observeResponse(portal);
   const admin=await handleAdmin(request,env,ctx);if(admin)return observeResponse(admin);
   headers=cors(request,env);const url=new URL(request.url);
   if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
   const gateway=await momoGatewayRoute(request,env);
   if(gateway){if(gateway.ok&&request.method==='POST'&&url.pathname.endsWith('/ingest'))ctx.waitUntil(drainMomoJobs(env));return observeResponse(withHeaders(gateway,headers));}
   if(url.pathname==='/health'&&request.method==='GET'){
    await first(env,'SELECT 1 AS ready');return json({service:'collect-platform-api',database:'available',release:env.BUILD_SOURCE_ID??null,checked_at:now()},200,headers);
   }
   const challenge=await challengeRoute(request,env);if(challenge)return observeResponse(withHeaders(challenge,headers));
   const auth=await handleAuth(request,env);if(auth)return observeResponse(withHeaders(auth,headers));
   if(request.method==='GET'&&url.pathname==='/v1/query/public-collections')return json(await publicGroups(env),200,headers);
   const match=/^\/v1\/rpc\/([a-z][a-z0-9_]{0,100})$/.exec(url.pathname);
   if(match&&request.method==='POST'&&PUBLIC_OPERATIONS.has(match[1]))return json(await publicRpc(match[1],await readJson(request),env),200,headers);
   const actor=await requireSession(request,env);
   if(request.method==='GET'&&url.pathname==='/v1/query/notification-events')return json(await notificationEvents(env,actor),200,headers);
   if(request.method==='GET'&&url.pathname==='/v1/sync')return json(await syncEvents(request,env,actor),200,headers);
   const receipt=await receiptRoute(request,env,actor);if(receipt)return observeResponse(withHeaders(receipt,headers));
   const evidence=await evidenceRoute(request,env,actor);if(evidence)return observeResponse(withHeaders(evidence,headers));
   if(match&&request.method==='POST'){
    const body=await readJson(request);
    return json(await dispatchOperation('rpc',match[1],body,env,actor),200,headers);
   }
   const functionMatch=/^\/v1\/functions\/([a-z][a-z0-9_-]{0,100})$/.exec(url.pathname);
   if(functionMatch&&request.method==='POST'){
    const upload=['prepare-roster-import','roster-import-upload','roster-import-extract'].includes(functionMatch[1]);
    const body=await readJson(request,upload?7100000:32768);
    return json(await dispatchOperation('function',functionMatch[1],body,env,actor),200,headers);
   }
   throw new ApiError(404,'not_found','This route is unavailable.');
  }catch(error){
   const known=error instanceof ApiError;
   recordPlatformHealth({status:known?error.status:500,component:platformHealthComponent(new URL(request.url).pathname),
    requestId,sourceId:env.BUILD_SOURCE_ID,elapsedMs:performance.now()-started,unexpected:!known});
   return json({code:known?error.code:'internal_error',message:known?error.message:'The request could not be completed.',request_id:requestId},known?error.status:500,headers);
  }
 }
};
function withHeaders(response,headers){const copy=new Response(response.body,response);for(const [k,v]of Object.entries(headers))copy.headers.set(k,v);return copy;}
