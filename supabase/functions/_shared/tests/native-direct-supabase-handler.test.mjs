// The actual serve boundary with synthetic database/provider/dispatch ports.
// It establishes routing and ordering, not hosted auth or database behavior.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {registerHooks} from 'node:module';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../deployment-profile.js';
import {admitDirectSupabaseNativeIngress} from '../native-direct-supabase-ingress.js';

const state={events:[],buckets:[],authority:[]};globalThis.__directIngressTest=state;
const mock={
 './runtime-env.js':`export const COLLECT_SUPABASE_ORIGIN='${MANAGED_SUPABASE_ORIGIN}';export const configurePublicRuntimeEnv=e=>({...e});export const normalizeRuntimeEnv=e=>({...e});export const isGoogleProviderNavigation=()=>false;`,
 './deployment-database.js':`export const assertRuntimeDeployment=async()=>{globalThis.__directIngressTest.events.push('schema')};`,
 './auth-cleanup.js':`export const cleanupExpiredGoogleFlows=()=>{};`,
 './member-realtime-publisher.js':`export const publishMemberRealtime=()=>{};`,
 './postgres.js':`export const connection=()=>{globalThis.__directIngressTest.events.push('database');return {}};export const fenceConnection=()=>({});export class PostgresDatabase{constructor(){this.sql={}}setApplicationWork(work){this.applicationWork=work}}`,
 './application-fence.js':`export const sqlFenceBackend=()=>({});export const openApplicationWork=async()=>{globalThis.__directIngressTest.events.push('fence');return {finish:async()=>{},waitUntil:p=>p}};`,
 './adapters.js':`export class SupabaseObjectBucket{constructor(){}}export const providerAdapters=()=>({});`,
 './domain/index.js':`export default {fetch:async(request,env)=>{const s=globalThis.__directIngressTest;s.events.push('dispatch');s.buckets.push(await env.__network(request));s.authority.push([request.headers.get('authorization'),request.headers.get('cookie'),request.headers.get('x-forwarded-for')]);return Response.json({fixture:true})}};`,
 './domain/momo_pipeline.js':`export const drainMomoJobs=()=>{};`,
 './scheduled-processing.js':`export const parseScheduledDispatch=()=>{};export const scheduledProcessingAdmission=()=>{};export const scheduledProcessingResult=()=>{};export const scheduledNotificationResult=()=>{};`,
 './domain/notification_delivery.js':`export const drainNotificationDeliveries=()=>{};`,
 './domain/core.js':`export const json=(v,status=200,headers={})=>Response.json(v,{status,headers});export const readJson=()=>{};`,
 './domain/observability.js':`export const recordPlatformHealth=()=>{};export const runtimeFailureEvent=()=>{};`,
 './domain/client_diagnostics.js':`export const cleanupClientDiagnostics=()=>{};`,
 './gateway-upload-hold.js':`export const gatewayUploadHeld=()=>{};export const isGatewayIngest=()=>false;export const nativeGatewayUploadsEnabled=()=>false;`,
 './domain/burimunsi/collect-runtime.js':`export const createCollectNativeRuntime=async(env,options)=>{globalThis.__directIngressTest.events.push('native');env.__network=options.trustedNetworkBucket;return ()=>{}};export const runCollectNativeScheduledCycle=()=>{};`,
 './domain/burimunsi/postgres-native-auto-worker.js':`export const drainNativeAutoTransactions=()=>{};`,
 './domain/burimunsi/postgres-native-sms-ledger.js':`export const drainNativeSmsLedger=()=>{};`,
 './scheduled-native-auto.js':`export const nativeAutoProcessingResult=()=>{};`,
 './scheduled-native-sms-ledger.js':`export const nativeSmsLedgerResult=()=>{};`,
 './scheduled-canonical.js':`export const scheduledCanonicalDrain=()=>{};`,
 './scheduled-native-financial-work.js':`export const scheduledNativeFinancialWork=()=>{};`,
 './domain/burimunsi/collect-route.js':`export const isCollectNativeRoute=r=>new URL(r.url).pathname.startsWith('/v1/burimunsi');`,
};
const serve=new URL('../serve.js',import.meta.url).href;
const hooks=registerHooks({resolve(specifier,context,next){
 if(context.parentURL===serve&&Object.hasOwn(mock,specifier))return {url:'data:text/javascript,'+encodeURIComponent(mock[specifier]),shortCircuit:true};
 return next(specifier,context);
}});
const {createHandler}=await import(serve);
test.after(()=>{hooks.deregister();delete globalThis.__directIngressTest;});
const profile={format:'collect.deployment.v1',id:'direct-handler-fixture',mode:'managed',environment:'qualification',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.fixture.invalid',admin_origin:'https://admin.fixture.invalid',
 public_origin:'https://collect.fixture.invalid',google_callback_origin:'https://admin.fixture.invalid'};
const raw=canonicalProfile(profile),env=()=>({COLLECT_DEPLOYMENT_PROFILE:raw,
 COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(raw).digest('hex'),APP_ENVIRONMENT:'qualification',
 SUPABASE_URL:MANAGED_SUPABASE_ORIGIN,BURIMUNSI_NATIVE_ENABLED:'true',COLLECT_NATIVE_INGRESS_MODE:'supabase_direct_v1',
 COLLECT_DATABASE_URL:'postgres://synthetic.invalid/fixture',BUILD_SOURCE_ID:'a'.repeat(64)});
const req=(headers={},origin=MANAGED_SUPABASE_ORIGIN)=>new Request(origin+'/functions/v1/collect-api/v1/burimunsi/session/login',
 {method:'POST',headers:{'content-type':'application/json',...headers},body:'{}'});
function reset(){state.events=[];state.buckets=[];state.authority=[];}

test('opted-in direct mode reaches dispatch through the bounded global bucket without signed-frontdoor fallback',async()=>{
 reset();let signed=0,claim=0;
 const handler=createHandler('collect-api',env,{admitDirectSupabaseNativeIngress,
  verifyNativeIngress:()=>{signed++;throw Error('must not use signed frontdoor');},
  claimNativeIngress:()=>{claim++;throw Error('must not claim a frontdoor nonce');},reportHealth:()=>{}});
 for(const headers of [{'Authorization':'Bearer one','Cookie':'a=1','X-Forwarded-For':'192.0.2.1'},
  {'Authorization':'Bearer two','Cookie':'b=2','CF-Connecting-IP':'198.51.100.2'}])
  assert.equal((await handler(req(headers))).status,200);
 assert.equal(signed,0);assert.equal(claim,0);assert.equal(state.buckets[0],state.buckets[1]);
 assert.deepEqual(state.authority,[['Bearer one','a=1',null],['Bearer two','b=2',null]]);
 assert.equal(state.events.filter(x=>x==='fence').length,2);assert.equal(state.events.filter(x=>x==='dispatch').length,2);
});

test('missing direct adapter, disabled native, unsupported mode and wrong origin fail before DB',async()=>{
 for(const [options,change,input] of [[{}, {},req()],
  [{admitDirectSupabaseNativeIngress},{BURIMUNSI_NATIVE_ENABLED:'false'},req()],
  [{admitDirectSupabaseNativeIngress},{COLLECT_NATIVE_INGRESS_MODE:'unexpected'},req()],
  [{admitDirectSupabaseNativeIngress},{},req({},'https://wrong.fixture.invalid')]]){
  reset();const handler=createHandler('collect-api',()=>({...env(),...change}),{...options,reportHealth:()=>{}});
  assert.equal((await handler(input)).status,503);assert.equal(state.events.includes('database'),false);
 }
});
