import {verifyDeploymentProfile,resolveDeploymentProfile} from './deployment-profile.js';
import {isManagedAdminBrowserOrigin,managedAdminChallengeParent} from './admin-security.js';
import {normalizeRuntimeEnv,configurePublicRuntimeEnv,isGoogleProviderNavigation,COLLECT_SUPABASE_ORIGIN} from './runtime-env.js';
import {assertRuntimeDeployment} from './deployment-database.js';
import {cleanupExpiredGoogleFlows} from './auth-cleanup.js';
import {publishMemberRealtime} from './member-realtime-publisher.js';
import {connection,fenceConnection,PostgresDatabase} from './postgres.js';
import {openApplicationWork,sqlFenceBackend} from './application-fence.js';
import {SupabaseObjectBucket,providerAdapters} from './adapters.js';
import worker from './domain/index.js';
import {drainMomoJobs} from './domain/momo_pipeline.js';
import {parseScheduledDispatch,scheduledProcessingAdmission,scheduledProcessingResult,scheduledNotificationResult} from './scheduled-processing.js';
import {verifyManagedJobSignature,claimManagedJobDispatch,completeManagedJobDispatch,nativeSmsAdmission} from './managed-jobs-dispatch-auth.mjs';
import {withNativeProviderBudget} from './native-provider-budget.mjs';
import {drainNotificationDeliveries} from './domain/notification_delivery.js';
import {json,readJson} from './domain/core.js';
import {recordPlatformHealth} from './domain/observability.js';
import {cleanupClientDiagnostics} from './domain/client_diagnostics.js';
import {gatewayUploadHeld,isGatewayIngest,nativeGatewayUploadsEnabled} from './gateway-upload-hold.js';
import {createCollectNativeRuntime,runCollectNativeScheduledCycle} from './domain/burimunsi/collect-runtime.js';
import {drainNativeAutoTransactions} from './domain/burimunsi/postgres-native-auto-worker.js';
import {nativeAutoProcessingResult} from './scheduled-native-auto.js';
import {drainNativeSmsLedger} from './domain/burimunsi/postgres-native-sms-ledger.js';
import {drainBuriMunsiPaymentSms} from './domain/burimunsi/payment-sms-delivery.mjs';
import {nativeSmsLedgerResult} from './scheduled-native-sms-ledger.js';
import {scheduledCanonicalDrain} from './scheduled-canonical.js';
import {scheduledNativeFinancialWork} from './scheduled-native-financial-work.js';
import {isCollectNativeRoute} from './domain/burimunsi/collect-route.js';
export {runtimeFailureEvent} from './domain/observability.js';
// Health observations never change an admitted response or application work.
function observeFailure(report,value){try{report(value);}catch{}}
export function requestTransportProfile(request){
 const url=new URL(request.url),site=request.headers.get('Sec-Fetch-Site');
 return {protocol:['http:','https:'].includes(url.protocol)?url.protocol:'other',host:url.origin===COLLECT_SUPABASE_ORIGIN||url.hostname===new URL(COLLECT_SUPABASE_ORIGIN).hostname?'project':['localhost','127.0.0.1','[::1]'].includes(url.hostname)?'loopback':'other',port:['','80','443','9000','9999'].includes(url.port)?url.port:'other',sec_fetch_site:['same-origin','same-site','cross-site','none'].includes(site)?site:'other',origin_present:request.headers.has('Origin')};
}
export function logicalRequest(request,functionName,env={}) {
 const url=new URL(request.url),prefix='/functions/v1/'+functionName;
 // Hosted Supabase terminates HTTPS before invoking Edge with an internal
 // http URL for this exact project host. Restore only that fixed public
 // scheme; never infer it from caller-supplied forwarding headers or hosts.
 const profile=resolveDeploymentProfile(env),publicUrl=new URL(profile.supabase_origin);
 if(url.protocol==='http:'&&url.hostname===publicUrl.hostname&&!url.port)url.protocol='https:';
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
 * @param {object} [options]
 * @param {typeof openApplicationWork} [options.openWork]
 * @param {typeof recordPlatformHealth} [options.reportHealth]
 * @param {(request:Request)=>Promise<string>|string} [options.trustedNativeNetworkBucket]
 * @param {(request:Request,env:Record<string,unknown>)=>Promise<{request:Request,networkBucket:(request:Request)=>Promise<string>|string}>} [options.admitDirectSupabaseNativeIngress]
 * @param {(request:Request,env:Record<string,unknown>)=>Promise<object>} [options.verifyNativeIngress]
 * @param {(token:object,consume:Function)=>Promise<{request:Request,networkBucket:Function}>} [options.claimNativeIngress]
 * @param {(db:object,work:object,values:object)=>Promise<boolean>} [options.consumeNativeIngressNonce]
 */
export function createHandler(functionName,envReader=()=>Deno.env.toObject(),{openWork=openApplicationWork,reportHealth=recordPlatformHealth,trustedNativeNetworkBucket,admitDirectSupabaseNativeIngress,verifyNativeIngress,claimNativeIngress,consumeNativeIngressNonce}={}) {
 return async request=>{
  const started=performance.now();let env,work,cors={},stage='environment';try {env=configurePublicRuntimeEnv(envReader());await verifyDeploymentProfile(env);env.ALLOWED_ORIGINS=[...new Set([...(env.ALLOWED_ORIGINS??'').split(','),...(env.ADMIN_ORIGINS??env.ADMIN_ORIGIN??'').split(',')].map(v=>v.trim()).filter(Boolean))].join(',');let logical=logicalRequest(request,functionName,env);const path=new URL(logical.url).pathname;
   const admin=functionName==='admin-api',origin=request.headers.get('Origin');
   const challengeParent=functionName==='collect-api'?managedAdminChallengeParent(logical,env):null;
   if(admin&&!path.startsWith('/api/admin/'))return json({code:'not_found'},404);
   if(!admin&&path.startsWith('/api/admin'))return json({code:'not_found'},404);
   const allowed=(env.ALLOWED_ORIGINS??'').split(',').map(v=>v.trim()).filter(Boolean);
   if(origin&&!allowed.includes(origin)&&origin!==challengeParent&&!(admin&&isManagedAdminBrowserOrigin(env,origin))&&!isGoogleProviderNavigation(logical,env))return json({code:'origin_denied'},403);
   cors=origin?{'Access-Control-Allow-Origin':origin,Vary:'Origin','Access-Control-Allow-Methods':'GET,HEAD,POST,PATCH,DELETE,OPTIONS','Access-Control-Allow-Headers':'Authorization,Content-Type,apikey,Idempotency-Key,X-Request-ID,X-Collect-Admin,X-Collect-CSRF,X-Collect-Requested-With,X-Collect-Review-Reason'+(admin?',X-Collect-Owner-Identity-Version':''),...(admin?{'Access-Control-Allow-Credentials':'true','Access-Control-Expose-Headers':'X-Collect-Evidence-Sensitivity'}:{}),'Access-Control-Max-Age':'600'}:{};
   if(request.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
   if(functionName==='collect-api'&&isGatewayIngest(request.method,path)&&!nativeGatewayUploadsEnabled(env)){
    const held=gatewayUploadHeld();return json({code:held.code,message:held.message},held.status,cors);
   }
   let nativeNetworkBucket=trustedNativeNetworkBucket,pendingNativeIngress;
   if(functionName!=='collect-api'&&isCollectNativeRoute(logical))return json({code:'not_found'},404,cors);
   if(functionName==='collect-api'&&isCollectNativeRoute(logical)){
    if(env.BURIMUNSI_NATIVE_ENABLED!=='true'){
     // A disabled native route must not reach database or provider setup.
     stage='native_ingress';throw new Error('native_ingress_unconfigured');
    }else if(env.COLLECT_NATIVE_INGRESS_MODE==='supabase_direct_v1'){
     stage='native_ingress';
     if(typeof admitDirectSupabaseNativeIngress!=='function')throw new Error('native_ingress_unconfigured');
     const admitted=await admitDirectSupabaseNativeIngress(logical,env);
     if(!(admitted?.request instanceof Request)||typeof admitted.networkBucket!=='function')throw new Error('native_ingress_unconfigured');
     logical=admitted.request;nativeNetworkBucket=admitted.networkBucket;
    }else{
     stage='native_ingress';
     if(env.COLLECT_NATIVE_INGRESS_MODE!==undefined&&env.COLLECT_NATIVE_INGRESS_MODE!==''&&env.COLLECT_NATIVE_INGRESS_MODE!=='signed_frontdoor_v1')throw new Error('native_ingress_unconfigured');
     if(typeof verifyNativeIngress!=='function'||typeof claimNativeIngress!=='function'||typeof consumeNativeIngressNonce!=='function')throw new Error('native_ingress_unconfigured');
     pendingNativeIngress=await verifyNativeIngress(logical,env);
     if(!pendingNativeIngress||typeof pendingNativeIngress!=='object')throw new Error('native_ingress_unconfigured');
    }
   }
   stage='normalization';env=normalizeRuntimeEnv(env);env.MOMO_PROCESSING_PAUSED=env.MOMO_PROCESSING_PAUSED??'true';env.AUTH_MEMBER_REGISTRATION_ENABLED=env.AUTH_MEMBER_REGISTRATION_ENABLED??'false';
   stage='database_initialization';env.DB=new PostgresDatabase(connection(env.COLLECT_DATABASE_URL,env));await assertRuntimeDeployment(env.DB.sql,env);
   stage='fence_admission';work=await openWork({backend:sqlFenceBackend(env.DB.sql,fenceConnection(env.COLLECT_DATABASE_URL,env)),sourceSha256:env.BUILD_SOURCE_ID,kind:admin?'http_admin':'http_collect',signal:request.signal});env.COLLECT_FENCE_WORK=work;env.DB.setApplicationWork(work);
   if(request.signal.aborted)throw new Error('request_cancelled_before_dispatch');
   if(pendingNativeIngress){
    stage='native_nonce_claim';
    const admitted=await claimNativeIngress(pendingNativeIngress,values=>consumeNativeIngressNonce(env.DB,work,values));
    if(!(admitted?.request instanceof Request)||typeof admitted.networkBucket!=='function'||request.signal.aborted)throw new Error('native_ingress_unconfigured');
    logical=admitted.request;nativeNetworkBucket=admitted.networkBucket;
   }
   stage='storage_initialization';env.PRIVATE_MEDIA=new SupabaseObjectBucket(env);stage='provider_initialization';Object.assign(env,providerAdapters(env));
   if(functionName==='collect-api'&&isCollectNativeRoute(logical)){
    stage='native_initialization';
    const native=await createCollectNativeRuntime(env,{trustedNetworkBucket:nativeNetworkBucket});
    if(native)env.BURIMUNSI_NATIVE_ROUTE=native;
   }
   const ctx={waitUntil:promise=>{work.waitUntil(promise);if(typeof EdgeRuntime!=='undefined')EdgeRuntime.waitUntil(Promise.resolve(promise).catch(()=>{}));}};
   stage='dispatch';if(request.signal.aborted)throw new Error('request_cancelled_before_dispatch');const documentEnv=challengeParent?{...env,ALLOWED_ORIGINS:challengeParent}:env;const response=await worker.fetch(logical,documentEnv,ctx);if(admin&&response.status===403){const failure=await response.clone().json().catch(()=>null);if(failure?.error?.code==='origin_rejected')console.error(JSON.stringify({service:'collect_platform_api',event:'admin_transport_rejected',profile:requestTransportProfile(logical)}));}let content=response.body;if(path.startsWith('/privacy/account-deletion')&&response.ok&&/text\/(?:html|javascript)|application\/javascript/.test(response.headers.get('Content-Type')??'')){const prefix='/functions/v1/'+functionName;content=(await response.text()).replaceAll('/v1/',prefix+'/v1/').replaceAll('/privacy/account-deletion',prefix+'/privacy/account-deletion');}const copy=new Response(content,response);if(response.ok&&/text\/html/i.test(copy.headers.get('Content-Type')??'')){if(path==='/v1/security/challenge')copy.headers.set('X-Collect-Document','collect.turnstile.v1');if(/^\/privacy\/account-deletion\/?$/.test(path))copy.headers.set('X-Collect-Document','collect.privacy.portal.v1');}for(const[k,v]of Object.entries(cors))copy.headers.set(k,v);return copy;
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
export function createScheduledHandler(envReader=()=>Deno.env.toObject(),cleanup=cleanupExpiredGoogleFlows,processReceipts=drainMomoJobs,{openWork=openApplicationWork,reportHealth=recordPlatformHealth,cleanupDiagnostics=cleanupClientDiagnostics,processNotifications=drainNotificationDeliveries,processNativeAuto=drainNativeAutoTransactions,processNativeSmsLedger=drainNativeSmsLedger,processPaymentSms=drainBuriMunsiPaymentSms,processCanonical=runCollectNativeScheduledCycle,processNativeFinancialWork=scheduledNativeFinancialWork}={}){
 return async request=>{
  const started=performance.now();let work,env,dispatchId=null,dispatch={dispatchId:null,processing:null,notifications:null},stage='environment';try{env=envReader();const input=env,token=request.headers.get('Authorization');
   const managed=input.COLLECT_JOB_AUTH_MODE==='supabase_dispatch_hmac_v1';
   if(!managed&&(input.SUPABASE_URL==='https://rrlduytparvsjfmegalh.supabase.co'||(input.COLLECT_JOB_AUTH_MODE!==undefined&&input.COLLECT_JOB_AUTH_MODE!=='')||!input.COLLECT_JOB_TOKEN||token!=='Bearer '+input.COLLECT_JOB_TOKEN))return json({code:'unauthorized'},401);
   if(request.method!=='POST')return json({code:'method_not_allowed'},405);
   if(!/^\/(?:functions\/v1\/)?collect-jobs\/?$/.test(new URL(request.url).pathname))return json({code:'not_found'},404);
   let payload=null;
   if(request.body!==null){
    try{payload=await readJson(request,2048);dispatch=parseScheduledDispatch(payload);dispatchId=dispatch.dispatchId;
    }catch(error){return json({code:'invalid_job_dispatch'},[400,413,415].includes(error.status)?error.status:400);}
   }
   if(managed&&!(await verifyManagedJobSignature(input,payload,token)))return json({code:'unauthorized'},401);
   stage='normalization';await verifyDeploymentProfile(input);env=normalizeRuntimeEnv(input);env.MOMO_PROCESSING_PAUSED=env.MOMO_PROCESSING_PAUSED??'true';stage='database_initialization';env.DB=new PostgresDatabase(connection(env.COLLECT_DATABASE_URL,env));await assertRuntimeDeployment(env.DB.sql,env);stage='fence_admission';work=await openWork({backend:sqlFenceBackend(env.DB.sql,fenceConnection(env.COLLECT_DATABASE_URL,env)),sourceSha256:env.BUILD_SOURCE_ID,kind:'jobs'});env.COLLECT_FENCE_WORK=work;env.DB.setApplicationWork(work);if(managed&&!(await claimManagedJobDispatch(env.DB,input,payload,token)))return json({code:'unauthorized'},401);stage='storage_initialization';env.PRIVATE_MEDIA=new SupabaseObjectBucket(env);stage='provider_initialization';Object.assign(env,providerAdapters(env));const nativeGate=managed?nativeSmsAdmission(env,payload):{allowed:true,enabled:false};if(!nativeGate.allowed)return json({code:'native_sms_admission_changed'},503);stage='dispatch';
   // Expired credential custody has its own budget and executes even while
   // receipt extraction is paused. One failure never becomes a success count.
   let maintenance,processing;try{maintenance=await cleanup(env,{limit:100});}catch{maintenance={status:'unconfirmed',code:'auth_cleanup_unconfirmed'};}
   // An optional hint failure never rolls back authoritative cleanup/payment work.
   const realtime=await publishMemberRealtime(env);
   // Maintenance remains the default. Processing additionally binds the exact
   // reviewed source/model/approval and immutable original dispatch contract;
   // flipping the pause flag alone never authorizes provider work.
   const admission=scheduledProcessingAdmission(env,dispatch);
   if(!admission.allowed)processing={status:'unconfirmed',code:admission.code,processed:0,results:[],paused:env.MOMO_PROCESSING_PAUSED==='true'};
   else try{const result=await processReceipts(env,admission.processing?{limit:admission.processing.batch_limit}:undefined);
    processing=admission.processing?scheduledProcessingResult(result):result;
   }catch{processing={status:'unconfirmed',code:'receipt_processing_unconfirmed'};}
   let notifications={status:'disabled',paused:true,processed:0,results:[],recovered_unknown:0};
   if(admission.allowed&&admission.notifications){
    try{notifications=scheduledNotificationResult(await processNotifications(env,{limit:admission.notifications.batch_limit,admission:admission.notifications}));}
    catch{notifications={status:'unconfirmed',code:'notification_delivery_unconfirmed',processed:0,results:[]};}
   }
   // Native messages use an independent, server-selected jobs scope. The
   // feature is default-off and does not unpause the managed gateway lane.
   // A failed provider call never changes the result of another lane.
   const nativeEnv=nativeGate.enabled?withNativeProviderBudget(env,payload):env;
   let nativeAuto=null;
   if(env.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED==='true'){
    if(!admission.allowed)nativeAuto={status:'unconfirmed',code:'native_auto_admission_unavailable'};
    else try{nativeAuto=nativeAutoProcessingResult(await processNativeAuto(nativeEnv,{limit:1}));}
     catch{nativeAuto={status:'unconfirmed',code:'native_auto_processing_unconfirmed'};}
   }
   // The same admitted native SMS cycle posts matching receipts into the
   // existing Collect ledger. Unmatched payers remain recorded and retry
   // automatically; no additional gateway/provider confirmation is required.
   let nativeLedger=null;
   if(env.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED==='true'){
    if(!admission.allowed)nativeLedger={status:'unconfirmed',code:'native_sms_ledger_admission_unavailable'};
    else try{nativeLedger=nativeSmsLedgerResult(await processNativeSmsLedger(nativeEnv,{limit:1}));}
     catch{nativeLedger={status:'unconfirmed',code:'native_sms_ledger_unconfirmed'};}
   }
   let paymentSms=null;
   if(env.BURIMUNSI_PAYMENT_SMS_ENABLED==='true'){
    if(!nativeGate.enabled||!admission.allowed)paymentSms={status:'held',processed:0};
    else try{paymentSms=await processPaymentSms(env);}
     catch{paymentSms={status:'unconfirmed',processed:0};}
   }
   // Canonical scheduling is an independently configured, default-off lane.
   // It does not promote native SMS or bypass any posting authority/evidence.
   const canonical=await scheduledCanonicalDrain(env,admission,{runCycle:processCanonical});
   // This default-off lane can only defer native work; no provider or writer is composed.
   const nativeFinancial=await processNativeFinancialWork(env,admission);
   // Telemetry maintenance is bounded and reports its own outcome. It cannot
   // turn an acknowledged business drain into an ambiguous financial failure.
   let diagnostics;try{diagnostics=await cleanupDiagnostics(env,{limit:1000});
    if(diagnostics?.status!=='complete'||!Number.isSafeInteger(diagnostics.removed)||diagnostics.removed<0||diagnostics.removed>1000)throw new Error('diagnostics_cleanup_unconfirmed');
   }catch{diagnostics={status:'unconfirmed'};try{console.error(JSON.stringify({service:'collect_platform_api',event:'diagnostics_cleanup_unconfirmed'}));}catch{}}
   const status=maintenance.status==='complete'&&processing.status!=='unconfirmed'&&notifications.status!=='unconfirmed'&&nativeAuto?.status!=='unconfirmed'&&nativeLedger?.status!=='unconfirmed'&&canonical?.status!=='unconfirmed'&&nativeFinancial?.status!=='unconfirmed'?200:503;
   if(status===503)observeFailure(reportHealth,{status,component:'operations',requestId:null,dispatchId,sourceId:env.BUILD_SOURCE_ID,elapsedMs:performance.now()-started});
   const response=json({...(dispatchId?{dispatch_id:dispatchId}:{}),...(nativeGate.enabled?{native_sms_admission:nativeGate.admission}:{}),...(admission.processing?{processing_admission:admission.processing}:{}),...(admission.notifications?{notification_admission:admission.notifications}:{}),maintenance,processing,notifications,...(nativeAuto?{native_auto_processing:nativeAuto}:{}),...(nativeLedger?{native_sms_ledger:nativeLedger}:{}),...(paymentSms?{payment_receipt_sms:paymentSms}:{}),...(canonical?{canonical_processing:canonical}:{}),...(nativeFinancial?{native_financial_work:nativeFinancial}:{}),realtime,diagnostics},status);if(managed&&status===200&&!(await completeManagedJobDispatch(env.DB,input,dispatchId,response)))return json({code:'job_completion_unconfirmed'},503);return response;
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
