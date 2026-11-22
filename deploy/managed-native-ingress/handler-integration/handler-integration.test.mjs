// Cloud-only integration qualification using synthetic I/O; preserved historical preimages are unchanged.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {registerHooks} from 'node:module';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../../../supabase/functions/_shared/deployment-profile.js';
import {verifyNativeIngress,claimNativeIngress,createNativeIngressSigner} from '../../../supabase/functions/_shared/native-ingress.js';
import {consumeNativeIngressNonce} from '../../../supabase/functions/_shared/native-ingress-nonce.js';
import {createManagedNativeFrontdoor} from '../worker.js';
import {jobDispatchFixture} from '../../../supabase/functions/_shared/tests/helpers/job-dispatch-fixture.js';

// Synthetic adapters log ordering and model a committed, unique nonce. They do
// not establish production PostgreSQL, Cloudflare or provider behavior.
const state={events:[],nonces:new Set(),mode:'normal',bucket:null,signal:null};
globalThis.__nativeHandlerIntegration=state;
const mock={
 './deployment-database.js':`export const assertRuntimeDeployment=async()=>{globalThis.__nativeHandlerIntegration.events.push('schema')};`,
 './auth-cleanup.js':`export const cleanupExpiredGoogleFlows=()=>{};`,
 './member-realtime-publisher.js':`export const publishMemberRealtime=()=>{};`,
 './postgres.js':`const s=()=>globalThis.__nativeHandlerIntegration;export const connection=()=>{s().events.push('connection');return {}};export const fenceConnection=()=>({});export class PostgresDatabase{constructor(){s().events.push('database');this.sql={}}setApplicationWork(work){this.work=work;s().events.push('bind')}prepare(text){s().events.push('prepare');if(text!=='SELECT private.collect_native_ingress_consume(?::uuid,?::text,?::text,?::bigint) AS claimed')throw Error('unexpected SQL');return {bind:(nonce)=>({first:async column=>{if(column!=='claimed')throw Error('unexpected column');const h=s();h.events.push('claim');if(h.mode==='error')throw Error('synthetic private error');if(h.mode==='invalid')return 1;if(h.nonces.has(nonce))return false;h.nonces.add(nonce);if(h.mode==='hang')return new Promise(()=>{});if(h.mode==='lost')throw Error('synthetic lost commit acknowledgement');return true}})}}}`,
 './application-fence.js':`const s=()=>globalThis.__nativeHandlerIntegration;export const sqlFenceBackend=()=>({});export const openApplicationWork=async options=>{const h=s();h.events.push('fence');h.signal=options.signal;if(h.abortOnFence)h.abortOnFence();return {abandon(){h.events.push('abandon')},finish:async()=>{h.events.push('finish')},waitUntil:p=>p}};`,
 './adapters.js':`export class SupabaseObjectBucket{constructor(){globalThis.__nativeHandlerIntegration.events.push('storage')}}export const providerAdapters=()=>{globalThis.__nativeHandlerIntegration.events.push('provider');return {}};`,
 './domain/index.js':`export default {fetch:async(request,env)=>{const h=globalThis.__nativeHandlerIntegration;h.events.push('dispatch');if(new URL(request.url).pathname.startsWith('/v1/burimunsi')){if(!env.BURIMUNSI_NATIVE_ROUTE)return Response.json({code:'native_service_unconfigured'},{status:503});h.bucket=await env.__testNetwork(request);h.bodyBytes=(await request.arrayBuffer()).byteLength;h.idempotency=request.headers.get('idempotency-key');h.ingressPresent=request.headers.has('x-collect-native-ingress')}return Response.json({ok:true})}};`,
 './domain/momo_pipeline.js':`export const drainMomoJobs=()=>{};`,
 './scheduled-processing.js':`export const parseScheduledDispatch=()=>{};export const scheduledProcessingAdmission=()=>({allowed:globalThis.__nativeHandlerIntegration.admissionAllowed??true,processing:null,notifications:null});export const scheduledProcessingResult=()=>{};export const scheduledNotificationResult=()=>{};`,
 './domain/notification_delivery.js':`export const drainNotificationDeliveries=()=>{};`,
 './domain/core.js':`export const json=(value,status=200,headers={})=>Response.json(value,{status,headers});export const readJson=()=>{};`,
 './domain/observability.js':`export const recordPlatformHealth=()=>{};export const runtimeFailureEvent=()=>{};`,
 './domain/client_diagnostics.js':`export const cleanupClientDiagnostics=()=>{};`,
 './gateway-upload-hold.js':`export const gatewayUploadHeld=()=>{};export const isGatewayIngest=()=>false;export const nativeGatewayUploadsEnabled=()=>false;`,
 './domain/burimunsi/collect-runtime.js':`export const createCollectNativeRuntime=async(env,options)=>{const h=globalThis.__nativeHandlerIntegration;h.events.push('native');if(env.BURIMUNSI_NATIVE_ENABLED!=='true')return null;env.__testNetwork=options.trustedNetworkBucket;return ()=>{}};export const runCollectNativeScheduledCycle=()=>{};`,
 './domain/burimunsi/postgres-native-auto-worker.js':`export const drainNativeAutoTransactions=()=>{};`,
 './domain/burimunsi/postgres-native-sms-ledger.js':`export const drainNativeSmsLedger=()=>{};`,
 './scheduled-native-auto.js':`export const nativeAutoProcessingResult=()=>{};`,
 './scheduled-canonical.js':`export const scheduledCanonicalDrain=()=>{};`,
};
const shared=new URL('../../../supabase/functions/_shared/',import.meta.url);
const runtimeServe=new URL('serve.js',shared).href;
const runtimeBoundaries=new Set([
 'serve.js','edge-runtime.js','edge-http-handler.js','edge-http-transport.js','edge-jobs-handler.js','edge-job-cycle.js',
].map(file=>new URL(file,shared).href));
const runtimeIndex=new URL('../../../supabase/functions/collect-api/index.ts',import.meta.url).href;
const hooks=registerHooks({resolve(specifier,context,next){
 if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){throw Error("unexpected real database")}',shortCircuit:true};
 if(specifier==='npm:nodemailer@10.1.7')return {url:'data:text/javascript,export function createTransport(){throw Error("unexpected real SMTP")}',shortCircuit:true};
 const mockSpecifier=specifier==='./postgres-connections.js'?'./postgres.js':specifier;
 if(runtimeBoundaries.has(context.parentURL)&&Object.hasOwn(mock,mockSpecifier))
  return {url:'data:text/javascript,'+encodeURIComponent(mock[mockSpecifier]),shortCircuit:true};
 return next(specifier,context);
}});
const {createHandler,createScheduledHandler}=await import(runtimeServe);
test.after(()=>{hooks.deregister();delete globalThis.__nativeHandlerIntegration;});

const now=Date.now(),hash=x=>createHash('sha256').update(x).digest('hex');
const canonical=value=>JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(name=>[name,value[name]])));
const key=n=>Buffer.alloc(32,n).toString('base64');
const profile={format:'collect.deployment.v1',id:'managed-handler-fixture',mode:'managed',environment:'qualification',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.collect.example',admin_origin:'https://admin.collect.example',
 public_origin:'https://collect.example',google_callback_origin:'https://admin.collect.example'};
function managedEnvironment(overrides={}){
 const raw=canonicalProfile(profile),digest=hash(raw),proof=canonical({format:'collect.native-ingress.managed-edge-proof.v1',status:'reviewed',
  frontdoorOrigin:profile.member_api_origin,networkSource:'cf-connecting-ip',workerGuard:'cloudflare_worker_presence_reject',pseudoIpv4:'off',
  profileSha256:digest,supabaseOrigin:profile.supabase_origin,reviewedAt:now-1000,evidenceSha256:'c'.repeat(64)});
 return {COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:digest,APP_ENVIRONMENT:'qualification',
  SUPABASE_URL:profile.supabase_origin,BURIMUNSI_NATIVE_ENABLED:'true',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@db.rrlduytparvsjfmegalh.supabase.co:5432/postgres',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic',SUPABASE_SECRET_KEY:'sb_secret_synthetic',BUILD_SOURCE_ID:'a'.repeat(64),
  COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON:proof,COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256:hash(proof),
  COLLECT_NATIVE_INGRESS_KEY_ID:'managed-handler-fixture',COLLECT_NATIVE_INGRESS_KEY_BASE64:key(5),
  DATA_ENCRYPTION_KEY:key(1),SESSION_ENCRYPTION_KEY:key(2),BURIMUNSI_PIN_PEPPER_BASE64:key(3),BURIMUNSI_CURSOR_KEY_BASE64:key(4),...overrides};
}
function reset(mode='normal'){state.events=[];state.nonces=new Set();state.mode=mode;state.bucket=null;state.signal=null;state.bodyBytes=null;state.idempotency=null;state.ingressPresent=null;delete state.abortOnFence;delete state.admissionAllowed;}
const opts=(overrides={})=>({verifyNativeIngress,claimNativeIngress,consumeNativeIngressNonce,reportHealth:()=>{},...overrides});
async function managedSigned(env=managedEnvironment(),{body='{}',path='/v1/burimunsi/session/login',headers={},signal}={}){
 const signer=await createNativeIngressSigner(env),input=new Request(profile.supabase_origin+'/functions/v1/collect-api'+path,
  {method:'POST',headers:{'content-type':'application/json',...headers},body,signal});
 return signer(input,'192.0.2.1');
}
const indexOf=event=>state.events.indexOf(event);
const noneAfterFence=()=>{for(const event of ['storage','provider','native','dispatch'])assert.equal(state.events.includes(event),false,event);};

test('the reviewed input manifest matches the synthetic integration source and fixtures',async()=>{
 const manifest=JSON.parse(await readFile(new URL('./current-inputs.json',import.meta.url),'utf8'));
 assert.equal(manifest.format,'collect.managed-native-handler-integration.successor.v1');
 assert.match(manifest.predecessor_manifest_sha256,/^[a-f0-9]{64}$/);
 const root=new URL('../../../',import.meta.url);
 for(const [name,expected] of Object.entries(manifest.source_inputs)){
  assert.equal(hash(await readFile(new URL(name,root))),expected,name);
 }
 for(const [name,expected] of Object.entries(manifest.fixture_inputs)){
  assert.equal(hash(await readFile(new URL(name,import.meta.url))),expected,name);
 }
});

test('the integrated scheduler preserves native ledger admission and reports unknown outcomes',async()=>{
 const env=managedEnvironment({COLLECT_JOB_AUTH_MODE:'supabase_dispatch_hmac_v1',FIXTURE_JOB_TOKEN:'synthetic',BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true'});
 const request=()=>new Request(profile.supabase_origin+'/functions/v1/collect-jobs',{method:'POST',headers:{Authorization:'Bearer synthetic'}});
 const options={reportHealth:()=>{},jobDispatch:jobDispatchFixture,cleanupDiagnostics:async()=>({status:'complete',removed:0}),processNativeAuto:async()=>({status:'complete',processed:0,results:[]})};
 let calls=0;const make=processNativeSmsLedger=>createScheduledHandler(()=>env,async()=>({status:'complete'}),async()=>({status:'complete'}),{...options,processNativeSmsLedger});
 reset();let response=await make(async(e,options)=>{calls++;assert.ok(e.COLLECT_FENCE_WORK);assert.deepEqual(options,{limit:1});return {status:'complete',processed:1,results:[{state:'unmatched',private:'excluded'}]};})(request());
 assert.equal(response.status,200);assert.deepEqual((await response.json()).native_sms_ledger,{status:'complete',processed:1,results:[{state:'unmatched'}]});assert.equal(calls,1);
 reset();state.admissionAllowed=false;response=await make(async()=>{calls++;})(request());assert.equal(response.status,503);assert.equal(calls,1);
 assert.deepEqual((await response.json()).native_sms_ledger,{status:'unconfirmed',code:'native_sms_ledger_admission_unavailable'});
 reset();response=await make(async()=>{throw Error('private failure');})(request());assert.equal(response.status,503);
 assert.deepEqual((await response.json()).native_sms_ledger,{status:'unconfirmed',code:'native_sms_ledger_unconfirmed'});
 reset();env.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED='false';response=await make(async()=>{calls++;})(request());assert.equal(response.status,200);
 assert.equal(Object.hasOwn(await response.json(),'native_sms_ledger'),false);assert.equal(calls,1);
});
test('the scheduler preserves the actual financial-work hold and unconfirmed status',async()=>{
 const env=managedEnvironment({COLLECT_JOB_AUTH_MODE:'supabase_dispatch_hmac_v1',FIXTURE_JOB_TOKEN:'synthetic',BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED:'true',MOMO_PROCESSING_PAUSED:'false'});
 const request=()=>new Request(profile.supabase_origin+'/functions/v1/collect-jobs',{method:'POST',headers:{Authorization:'Bearer synthetic'}});
 const options={reportHealth:()=>{},jobDispatch:jobDispatchFixture,cleanupDiagnostics:async()=>({status:'complete',removed:0})};
 const make=overrides=>createScheduledHandler(()=>env,async()=>({status:'complete'}),async()=>({status:'complete'}),{...options,...overrides});
 reset();let response=await make()(request());assert.equal(response.status,200);
 assert.deepEqual((await response.json()).native_financial_work,{status:'held',code:'retention_scope_unapproved'});
 env.MOMO_PROCESSING_PAUSED='true';response=await make()(request());assert.equal(response.status,200);
 assert.deepEqual((await response.json()).native_financial_work,{status:'paused'});
 env.BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED='false';response=await make()(request());assert.equal(response.status,200);
 assert.equal(Object.hasOwn(await response.json(),'native_financial_work'),false);
 reset();response=await make({processNativeFinancialWork:async(e,admission)=>{state.events.push('financial');assert.ok(e.COLLECT_FENCE_WORK);assert.equal(admission.allowed,true);return {status:'unconfirmed',code:'synthetic'};}})(request());
 assert.equal(response.status,503);assert.deepEqual((await response.json()).native_financial_work,{status:'unconfirmed',code:'synthetic'});
 assert(indexOf('financial')>indexOf('fence'));
});
test('managed verification precedes DB, committed claim precedes providers, and replay stops before dispatch',async()=>{
 reset();const env=managedEnvironment(),calls=[],handler=createHandler('collect-api',()=>env,opts({verifyNativeIngress:async(r,e)=>{calls.push('verify');state.events.push('verify');return verifyNativeIngress(r,e)}}));
 const input=await managedSigned(env),duplicate=input.clone();assert.equal((await handler(input)).status,200);assert.deepEqual(calls,['verify']);assert(indexOf('connection')>indexOf('verify'));
 assert(indexOf('claim')>indexOf('fence'));assert(indexOf('claim')>indexOf('bind'));assert(indexOf('storage')>indexOf('claim'));assert(indexOf('provider')>indexOf('claim'));
 assert(indexOf('native')>indexOf('claim'));assert(indexOf('dispatch')>indexOf('claim'));assert.match(state.bucket,/^[a-f0-9]{64}$/);
 state.events=[];assert.equal((await handler(duplicate)).status,503);assert.equal(state.events.filter(x=>x==='claim').length,1);noneAfterFence();
});
test('the actual managed frontdoor and Cloud handler preserve a large approved preview body',async()=>{
 reset();const env=managedEnvironment(),handler=createHandler('collect-api',()=>env,opts());
 const frontdoor=await createManagedNativeFrontdoor(env,{fetchImpl:request=>handler(request)}),body='x'.repeat(8193);
 const input=new Request(profile.member_api_origin+'/functions/v1/collect-api/v1/burimunsi/members/import/preview',
  {method:'POST',headers:{'content-type':'application/json','cf-connecting-ip':'192.0.2.1','idempotency-key':'synthetic'},body});
 assert.equal((await frontdoor(input)).status,200);assert.equal(state.bodyBytes,8193);assert.equal(state.idempotency,'synthetic');assert.equal(state.ingressPresent,false);
 assert(indexOf('claim')<indexOf('provider'));assert(indexOf('provider')<indexOf('dispatch'));
});
test('concurrent copies have one committed claim and one dispatch',async()=>{
 reset();const env=managedEnvironment(),handler=createHandler('collect-api',()=>env,opts()),input=await managedSigned(env),copy=input.clone();
 const responses=await Promise.all([handler(input),handler(copy)]);assert.deepEqual(responses.map(x=>x.status).sort(),[200,503]);
 assert.equal(state.events.filter(x=>x==='claim').length,2);assert.equal(state.events.filter(x=>x==='dispatch').length,1);
});
test('missing managed verifier, claim, or store never reaches database even through generic handler options',async()=>{
 const env=managedEnvironment();
 for(const options of [{},{verifyNativeIngress,claimNativeIngress},{verifyNativeIngress,consumeNativeIngressNonce},
  {claimNativeIngress,consumeNativeIngressNonce},{...opts(),claimNativeIngress:null},{...opts(),verifyNativeIngress:null},
  {...opts(),consumeNativeIngressNonce:null},{trustedNativeNetworkBucket:()=> 'forged'}]){
  reset();const handler=createHandler('collect-api',()=>env,{...options,reportHealth:()=>{}});
  assert.equal((await handler(await managedSigned(env))).status,503);assert.equal(state.events.length,0);
 }
});
test('unsigned and tampered managed requests are refused before database work',async()=>{
 const env=managedEnvironment();for(const change of ['missing','body','idempotency']){
  reset();let input;
  if(change==='missing')input=new Request(profile.supabase_origin+'/functions/v1/collect-api/v1/burimunsi/session/login',{method:'POST',body:'{}'});
  else{const original=await managedSigned(env),headers=new Headers(original.headers);if(change==='idempotency')headers.set('idempotency-key','changed');
   input=new Request(original.url,{method:'POST',headers,body:change==='body'?'{"changed":true}':await original.text()});}
  assert.equal((await createHandler('collect-api',()=>env,opts())(input)).status,503);assert.equal(state.events.length,0);
 }
});
test('lost claim acknowledgement consumes the nonce but never initializes providers or dispatches',async()=>{
 reset('lost');const env=managedEnvironment(),handler=createHandler('collect-api',()=>env,opts()),input=await managedSigned(env),retry=input.clone();
 assert.equal((await handler(input)).status,503);assert.equal(state.events.includes('abandon'),true);noneAfterFence();
 state.events=[];state.mode='normal';assert.equal((await handler(retry)).status,503);assert.equal(state.events.includes('claim'),true);noneAfterFence();
});
test('a timed-out claim abandons work, never dispatches and does not retry a consumed nonce',async()=>{
 reset('hang');const env=managedEnvironment(),handler=createHandler('collect-api',()=>env,opts()),input=await managedSigned(env),retry=input.clone();
 const timer=globalThis.setTimeout;globalThis.setTimeout=(fn,ms,...args)=>timer(fn,ms===8000?10:ms,...args);
 try{assert.equal((await handler(input)).status,503);assert.equal(state.events.includes('abandon'),true);noneAfterFence();}
 finally{globalThis.setTimeout=timer;}
 state.events=[];state.mode='normal';assert.equal((await handler(retry)).status,503);assert.equal(state.events.includes('claim'),true);noneAfterFence();
});
test('false, malformed and unavailable claims cannot start providers',async()=>{
 for(const mode of ['error','invalid']){reset(mode);const env=managedEnvironment();assert.equal((await createHandler('collect-api',()=>env,opts())(await managedSigned(env))).status,503);
  assert.equal(state.events.includes('abandon'),true);noneAfterFence();}
 reset();const env=managedEnvironment(),input=await managedSigned(env),handler=createHandler('collect-api',()=>env,opts({claimNativeIngress:async()=>({request:input})}));
 assert.equal((await handler(input)).status,503);noneAfterFence();
});
test('request cancellation after fence admission prevents nonce claim and provider setup',async()=>{
 reset();const env=managedEnvironment(),controller=new AbortController(),input=await managedSigned(env,{signal:controller.signal});state.abortOnFence=()=>controller.abort();
 assert.equal((await createHandler('collect-api',()=>env,opts())(input)).status,503);assert.equal(state.signal,input.signal);assert.equal(state.events.includes('claim'),false);noneAfterFence();
});
test('non-native and preflight routes preserve their existing paths without ingress options',async()=>{
 reset();const env=managedEnvironment(),handler=createHandler('collect-api',()=>env,{reportHealth:()=>{}});
 assert.equal((await handler(new Request(profile.supabase_origin+'/functions/v1/collect-api/health'))).status,200);
 assert.deepEqual(state.events.filter(x=>['storage','provider','native','dispatch'].includes(x)),['storage','provider','dispatch']);
 reset();assert.equal((await handler(new Request(profile.supabase_origin+'/functions/v1/collect-api/v1/burimunsi/session/login',{method:'OPTIONS'}))).status,204);assert.equal(state.events.length,0);
 reset();const other=createHandler('unrelated-api',()=>env,{reportHealth:()=>{}});
 assert.equal((await other(new Request(profile.supabase_origin+'/functions/v1/unrelated-api/v1/burimunsi/session/login',{method:'POST',body:'{}'}))).status,404);assert.equal(state.events.length,0);
});
test('disabled managed native requests fail before DB and provider setup',async()=>{
 reset();const managed=managedEnvironment({BURIMUNSI_NATIVE_ENABLED:'false'});
 assert.equal((await createHandler('collect-api',()=>managed,opts())(await managedSigned(managed))).status,503);
 assert.equal(state.events.length,0);
});
test('the Collect API entrypoint supplies the real verifier, claim and store to its handler',async()=>{
 reset();const env=managedEnvironment(),saved=globalThis.Deno;let handler;
 globalThis.Deno={env:{toObject:()=>env},serve:value=>{handler=value;}};
 try{await import(runtimeIndex+'?fixture=1');assert.equal(typeof handler,'function');const input=await managedSigned(env),retry=input.clone();
  assert.equal((await handler(input)).status,200);assert.equal(state.events.filter(x=>x==='claim').length,1);
  state.events=[];assert.equal((await handler(retry)).status,503);noneAfterFence();
 }finally{if(saved===undefined)delete globalThis.Deno;else globalThis.Deno=saved;}
});
