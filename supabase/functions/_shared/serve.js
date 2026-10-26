import {normalizeRuntimeEnv,isGoogleProviderNavigation,COLLECT_SUPABASE_ORIGIN} from './runtime-env.js';
import {cleanupExpiredGoogleFlows} from './auth-cleanup.js';
import {publishMemberRealtime} from './member-realtime-publisher.js';
import {connection,fenceConnection,PostgresDatabase} from './postgres.js';
import {openApplicationWork,sqlFenceBackend} from './application-fence.js';
import {SupabaseObjectBucket,providerAdapters} from './adapters.js';
import worker from './domain/index.js';
import {drainMomoJobs} from './domain/momo_pipeline.js';
import {json,readJson,uuid} from './domain/core.js';
import {recordPlatformHealth} from './domain/observability.js';
export {runtimeFailureEvent} from './domain/observability.js';
// Health observations never change an admitted response or application work.
function observeFailure(report,value){try{report(value);}catch{}}
export function requestTransportProfile(request){
 const url=new URL(request.url),site=request.headers.get('Sec-Fetch-Site');
 return {protocol:['http:','https:'].includes(url.protocol)?url.protocol:'other',host:url.origin===COLLECT_SUPABASE_ORIGIN||url.hostname===new URL(COLLECT_SUPABASE_ORIGIN).hostname?'project':['localhost','127.0.0.1','[::1]'].includes(url.hostname)?'loopback':'other',port:['','80','443','9000','9999'].includes(url.port)?url.port:'other',sec_fetch_site:['same-origin','same-site','cross-site','none'].includes(site)?site:'other',origin_present:request.headers.has('Origin')};
}
export function logicalRequest(request,functionName) {
 const url=new URL(request.url),prefix='/functions/v1/'+functionName;
 // Hosted Supabase terminates HTTPS before invoking Edge with an internal
 // http URL for this exact project host. Restore only that fixed public
 // scheme; never infer it from caller-supplied forwarding headers or hosts.
 if(url.protocol==='http:'&&url.hostname===new URL(COLLECT_SUPABASE_ORIGIN).hostname&&!url.port)url.protocol='https:';
 if(url.pathname===prefix)url.pathname='/';else if(url.pathname.startsWith(prefix+'/'))url.pathname=url.pathname.slice(prefix.length);
 else if(url.pathname==='/'+functionName)url.pathname='/';else if(url.pathname.startsWith('/'+functionName+'/'))url.pathname=url.pathname.slice(functionName.length+1);
 else throw new Error('Wrong function prefix.');
 // Original method/path are the canonical identity on all transports. Client
 // supplied forwarding headers never override this value.
 const headers=new Headers(request.headers);headers.delete('X-Collect-Original-Path');headers.delete('X-Collect-Actor');
 return new Request(url,{method:request.method,headers,body:['GET','HEAD'].includes(request.method)?undefined:request.body,duplex:'half',signal:request.signal});
}
/**
 * @param {string} functionName
 * @param {()=>Record<string, unknown>} [envReader]
 */
export function createHandler(functionName,envReader=()=>Deno.env.toObject(),{openWork=openApplicationWork,reportHealth=recordPlatformHealth}={}) {
 return async request=>{
  const started=performance.now();let env,work,cors={},stage='environment';try {env=envReader();env.ALLOWED_ORIGINS=[...new Set([...(env.ALLOWED_ORIGINS??'').split(','),...(env.ADMIN_ORIGINS??env.ADMIN_ORIGIN??'').split(',')].map(v=>v.trim()).filter(Boolean))].join(',');const logical=logicalRequest(request,functionName),path=new URL(logical.url).pathname;
   const admin=functionName==='admin-api',origin=request.headers.get('Origin');
   if(admin&&!path.startsWith('/api/admin/'))return json({code:'not_found'},404);
   if(!admin&&path.startsWith('/api/admin'))return json({code:'not_found'},404);
   const allowed=(admin?env.ADMIN_ORIGINS??env.ADMIN_ORIGIN:env.ALLOWED_ORIGINS??'').split(',').map(v=>v.trim()).filter(Boolean);
   if(origin&&!allowed.includes(origin)&&!isGoogleProviderNavigation(logical))return json({code:'origin_denied'},403);
   cors=origin?{'Access-Control-Allow-Origin':origin,Vary:'Origin','Access-Control-Allow-Methods':'GET,HEAD,POST,PATCH,DELETE,OPTIONS','Access-Control-Allow-Headers':'Authorization,Content-Type,apikey,Idempotency-Key,X-Request-ID,X-Collect-Admin,X-Collect-CSRF,X-Collect-Requested-With,X-Collect-Review-Reason',...(admin?{'Access-Control-Allow-Credentials':'true'}:{}),'Access-Control-Max-Age':'600'}:{};
   if(request.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
   stage='normalization';env=normalizeRuntimeEnv(env);env.MOMO_PROCESSING_PAUSED=env.MOMO_PROCESSING_PAUSED??'true';env.AUTH_MEMBER_REGISTRATION_ENABLED=env.AUTH_MEMBER_REGISTRATION_ENABLED??'false';
   stage='database_initialization';env.DB=new PostgresDatabase(connection(env.COLLECT_DATABASE_URL));
   stage='fence_admission';work=await openWork({backend:sqlFenceBackend(env.DB.sql,fenceConnection(env.COLLECT_DATABASE_URL)),sourceSha256:env.BUILD_SOURCE_ID,kind:admin?'http_admin':'http_collect'});env.COLLECT_FENCE_WORK=work;env.DB.setApplicationWork(work);
   stage='storage_initialization';env.PRIVATE_MEDIA=new SupabaseObjectBucket(env);stage='provider_initialization';Object.assign(env,providerAdapters(env));
   const ctx={waitUntil:promise=>{work.waitUntil(promise);if(typeof EdgeRuntime!=='undefined')EdgeRuntime.waitUntil(Promise.resolve(promise).catch(()=>{}));}};
   stage='dispatch';const response=await worker.fetch(logical,env,ctx);if(admin&&response.status===403){const failure=await response.clone().json().catch(()=>null);if(failure?.error?.code==='origin_rejected')console.error(JSON.stringify({service:'collect_platform_api',event:'admin_transport_rejected',profile:requestTransportProfile(logical)}));}let content=response.body;if(path.startsWith('/privacy/account-deletion')&&response.ok&&/text\/(?:html|javascript)|application\/javascript/.test(response.headers.get('Content-Type')??'')){const prefix='/functions/v1/'+functionName;content=(await response.text()).replaceAll('/v1/',prefix+'/v1/').replaceAll('/privacy/account-deletion',prefix+'/privacy/account-deletion');}const copy=new Response(content,response);if(response.ok&&/text\/html/i.test(copy.headers.get('Content-Type')??'')){if(path==='/v1/security/challenge')copy.headers.set('X-Collect-Document','collect.turnstile.v1');if(/^\/privacy\/account-deletion\/?$/.test(path))copy.headers.set('X-Collect-Document','collect.privacy.portal.v1');}for(const[k,v]of Object.entries(cors))copy.headers.set(k,v);return copy;
  }catch(error){
   if(error?.code==='application_fenced'||error?.code==='application_fence_unavailable'){
    observeFailure(reportHealth,{status:503,component:'platform',requestId:null,sourceId:env?.BUILD_SOURCE_ID,elapsedMs:performance.now()-started});
    return json({code:error.code,message:error.message},503,cors);
   }
   const requestId=crypto.randomUUID();
   observeFailure(reportHealth,{status:503,component:'platform',requestId,sourceId:env?.BUILD_SOURCE_ID,elapsedMs:performance.now()-started,runtimeFailure:{error,stage,env}});
   return json({code:'backend_unavailable',message:'The backend is unavailable.',request_id:requestId},503);
  }
  finally{if(work)finishApplicationWork(work);}
 };
}
/** @param {()=>Record<string, unknown>} [envReader] */
export function createScheduledHandler(envReader=()=>Deno.env.toObject(),cleanup=cleanupExpiredGoogleFlows,processReceipts=drainMomoJobs,{openWork=openApplicationWork,reportHealth=recordPlatformHealth}={}){
 return async request=>{
  const started=performance.now();let work,env,dispatchId=null,stage='environment';try{env=envReader();const input=env,token=request.headers.get('Authorization');if(!input.COLLECT_JOB_TOKEN||token!=='Bearer '+input.COLLECT_JOB_TOKEN)return json({code:'unauthorized'},401);
   if(request.method!=='POST')return json({code:'method_not_allowed'},405);
   if(!/^\/(?:functions\/v1\/)?collect-jobs\/?$/.test(new URL(request.url).pathname))return json({code:'not_found'},404);
   if(request.body!==null){
    try{const payload=await readJson(request,128),keys=Object.keys(payload);
     if(keys.length===1&&keys[0]==='dispatch_id')dispatchId=uuid(payload.dispatch_id,'dispatch_id');
     else if(keys.length)throw new Error('Unexpected dispatch payload');
    }catch(error){return json({code:'invalid_job_dispatch'},[400,413,415].includes(error.status)?error.status:400);}
   }
   stage='normalization';env=normalizeRuntimeEnv(input);env.MOMO_PROCESSING_PAUSED=env.MOMO_PROCESSING_PAUSED??'true';stage='database_initialization';env.DB=new PostgresDatabase(connection(env.COLLECT_DATABASE_URL));stage='fence_admission';work=await openWork({backend:sqlFenceBackend(env.DB.sql,fenceConnection(env.COLLECT_DATABASE_URL)),sourceSha256:env.BUILD_SOURCE_ID,kind:'jobs'});env.COLLECT_FENCE_WORK=work;env.DB.setApplicationWork(work);stage='storage_initialization';env.PRIVATE_MEDIA=new SupabaseObjectBucket(env);stage='provider_initialization';Object.assign(env,providerAdapters(env));stage='dispatch';
   // Expired credential custody has its own budget and executes even while
   // receipt extraction is paused. One failure never becomes a success count.
   let maintenance,processing;try{maintenance=await cleanup(env,{limit:100});}catch{maintenance={status:'unconfirmed',code:'auth_cleanup_unconfirmed'};}
   // An optional hint failure never rolls back authoritative cleanup/payment work.
   const realtime=await publishMemberRealtime(env);
   // This scheduler is admitted for maintenance only. Detect configuration
   // drift BEFORE touching the receipt queue or an external AI/provider.
   if(env.MOMO_PROCESSING_PAUSED!=='true')processing={status:'unconfirmed',code:'maintenance_gate_changed',processed:0,results:[],paused:false};
   else try{processing=await processReceipts(env);}catch{processing={status:'unconfirmed',code:'receipt_processing_unconfirmed'};}
   const status=maintenance.status==='complete'&&processing.status!=='unconfirmed'?200:503;
   if(status===503)observeFailure(reportHealth,{status,component:'operations',requestId:null,dispatchId,sourceId:env.BUILD_SOURCE_ID,elapsedMs:performance.now()-started});
   return json({...(dispatchId?{dispatch_id:dispatchId}:{}),maintenance,processing,realtime},status);
  }catch(error){
   const fenced=error?.code==='application_fenced'||error?.code==='application_fence_unavailable';
   observeFailure(reportHealth,{status:503,component:'operations',requestId:null,dispatchId,sourceId:env?.BUILD_SOURCE_ID,elapsedMs:performance.now()-started,...(fenced?{}:{runtimeFailure:{error,stage,env}})});
   if(fenced)return json({code:error.code,message:error.message},503);
   return json({code:'backend_unavailable',message:'The backend is unavailable.'},503);
  }
  finally{if(work)finishApplicationWork(work);}
 };
}
export const scheduledHandler=createScheduledHandler();

function finishApplicationWork(work){const done=work.finish().catch(()=>{console.error(JSON.stringify({service:'collect_platform_api',event:'application_work_close_unconfirmed',scope:'application_only'}));});if(typeof EdgeRuntime!=='undefined')EdgeRuntime.waitUntil(done);}
