import {verifyDeploymentProfile,canonicalProfile} from '../../deployment-profile.js';
import {applicationWork,applicationWorkTuple} from '../../application-fence.js';
import {validateProviderProfile} from '../momo_pipeline.js';
import {encrypt,decrypt} from '../encryption.js';
import {nativePinHasher} from './native-secrets.js';
import {createCollectNativeRoute} from './collect-route.js';
import {composePostgresNativeWorkers} from './compose-postgres.js';
import {requireId} from './values.js';
import {requireThat} from './errors.js';
import {parseWire} from './wire/runtime.mjs';
import {resolveNativeCollection} from './postgres-scope-discovery.js';
import {verifyToken} from '../../auth-http.js';
import {projectSession} from '../auth.js';
import {createManagedRequestGate} from './managed-request-gate.js';

const need=(value,code='native_service_unconfigured')=>requireThat(value,code,503);
const managedWorkerGate=createManagedRequestGate({verifyToken,projectSession,applicationWorkTuple});
export const nativeObservationsEnabled=env=>env?.BURIMUNSI_SMS_OBSERVATIONS_ENABLED==='true';
const sameBytes=(a,b)=>a.length===b.length&&a.every((value,index)=>value===b[index]);
function base64(value,min=32,max=32){
 need(typeof value==='string'&&value.length>=44&&value.length<=344&&value.length%4===0&&/^[A-Za-z0-9+/]+={0,2}$/.test(value),'authentication_unconfigured');
 let bytes;try{bytes=Uint8Array.from(atob(value),c=>c.charCodeAt(0));}catch{need(false,'authentication_unconfigured');}
 need(bytes.length>=min&&bytes.length<=max&&btoa(String.fromCharCode(...bytes))===value,'authentication_unconfigured');return bytes;
}
function secretsFor(env,{staffDefault=false}={}){
 // Reuse the same protected native hasher as owner provisioning. No new key,
 // weak PIN derivation, fallback pepper or auth universe is introduced here.
 const hasher=nativePinHasher(env),pepper=hasher.pepper.slice();
 const cursor=base64(env.BURIMUNSI_CURSOR_KEY_BASE64);
 const domains=[[base64(env.DATA_ENCRYPTION_KEY)],[base64(env.SESSION_ENCRYPTION_KEY)]];
 for(const [index,name] of ['DATA_DECRYPTION_KEYS_JSON','SESSION_DECRYPTION_KEYS_JSON'].entries()){
  if(env[name]===undefined||env[name]==='')continue;
  let ring;try{ring=parseWire(env[name],4096);}catch{need(false,'authentication_unconfigured');}
  // The duplicate-key-aware wire parser deliberately produces null-prototype
  // records. Accept its record shape while retaining all key/domain checks.
  need(ring&&Object.getPrototypeOf(ring)===null&&Object.keys(ring).every(id=>/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(id)),
   'authentication_unconfigured');
  const values=Object.values(ring);need(values.length<=8,'authentication_unconfigured');
  domains[index].push(...values.map(value=>base64(value)));
 }
 need(!sameBytes(pepper,cursor)&&domains[0].every(data=>domains[1].every(bff=>!sameBytes(data,bff)))&&
  domains.flat().every(value=>!sameBytes(value,pepper)&&!sameBytes(value,cursor)),
  'authentication_unconfigured');
 const defaultStaffPin=staffDefault?(env.BURIMUNSI_DEFAULT_STAFF_PIN||undefined):undefined;
 need(defaultStaffPin===undefined||typeof defaultStaffPin==='string'&&/^[0-9]{4}$/.test(defaultStaffPin),'authentication_unconfigured');
 return Object.freeze({pinPepper:pepper,pinPepperId:hasher.pepperId,cursorKey:cursor,...(defaultStaffPin===undefined?{}:{defaultStaffPin})});
}
function configuration(profile,groupId,observationEnabled=false,preserveStaffPinOnPhoneChange=false,smartOnboardingAdvancedEnabled=false){
 if(groupId!==undefined)requireId(groupId);
 // These select implemented closed adapters. They do not enable processing,
 // approve a worker/policy, resume SMS upload, or install a schedule/provider.
 return Object.freeze({enabled:true,...(groupId===undefined?{}:{groupId}),origin:profile.supabase_origin,canonicalIntegrationEnabled:true,
  nativeObservationEnabled:observationEnabled,preserveStaffPinOnPhoneChange,smartOnboardingAdvancedEnabled,
  nativePostingAuthorityEnabled:true,sharedPostingEnabled:true,journalEvidenceEnabled:true,
  journalAllocationEnabled:true,postingPreparationEnabled:true,rematchEnabled:true});
}
async function assembled(env,kind){
 need(env&&typeof env==='object'&&typeof env.COLLECT_DEPLOYMENT_PROFILE==='string'&&
  typeof env.COLLECT_DEPLOYMENT_PROFILE_SHA256==='string','native_profile_mismatch');
 const profile=await verifyDeploymentProfile(env);
 need(env.SUPABASE_URL===profile.supabase_origin&&(env.APP_ENVIRONMENT===profile.environment||
  env.APP_ENVIRONMENT==='test'&&profile.environment==='qualification'),'native_profile_mismatch');
 const work=applicationWork(env),tuple=applicationWorkTuple(work),db=env.DB,media=env.PRIVATE_MEDIA;
 need(db?.applicationWork===work&&work.kind===kind&&tuple[2]===env.BUILD_SOURCE_ID,'request_not_admitted');
 for(const name of ['transaction','context','readContext','prepare','statement','setClaims'])need(typeof db?.[name]==='function','collect_adapter_required');
 need(media&&typeof media.get==='function'&&typeof media.put==='function'&&
  media.namespace?.origin===profile.supabase_origin&&
  media.namespace.bucket===(env.COLLECT_PRIVATE_BUCKET??'collect-evidence'),'collect_adapter_required');
 need(typeof env.DATA_KEY_ID==='string'&&/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(env.DATA_KEY_ID),'authentication_unconfigured');
 return Object.freeze({profile,profileIdentity:canonicalProfile(profile),db,work,tuple:JSON.stringify(tuple),media,keyId:env.DATA_KEY_ID});
}
function bridgesFor(local,bound){
 // Only this module constructs bridges from the already assembled server
 // context. No env string, request JSON, client principal or caller bridge map
 // can replace source readers, SQL writers, storage, crypto or gateway ports.
 need(local.DB===bound.db&&local.DB.applicationWork===bound.work&&local.PRIVATE_MEDIA===bound.media&&
  JSON.stringify(applicationWorkTuple(bound.work))===bound.tuple&&local.DATA_KEY_ID===bound.keyId,'request_not_admitted');
 return Object.freeze({commands:Object.freeze({}),
  canonical:Object.freeze({env:local,validateProviderProfile,applicationWorkTuple}),
  posting:Object.freeze({
   custody:Object.freeze({namespace:bound.media.namespace,decrypt:(sealed,aad)=>decrypt(local,sealed,aad)}),
   preparation:Object.freeze({media:bound.media,keyId:bound.keyId,encrypt:(bytes,aad)=>encrypt(local,bytes,aad)})})});
}

/** Called only AFTER serve.js has assembled this request's ordinary shared
 * PostgresDatabase, branded application work, protected Storage and providers.
 * Returns a branded route for the caller to install; it mutates no env and does
 * no DB/provider I/O, provisioning, financial work or operational activation.
 *
 * trustedNetworkBucket is a SERVER FUNCTION from an authenticated ingress/socket
 * boundary, returning a protected 64-hex bucket. No trusted Edge resolver exists
 * in the current shared hosting adapter. Enabled-without-resolver fails closed;
 * the factory supplies no raw-header, env-string, installation-ID or constant
 * bucket fallback. The hosting adapter must establish this trusted provenance;
 * validating the returned digest alone is not ingress authentication.
 */
export async function createCollectNativeRuntime(env,{trustedNetworkBucket,clock=()=>Date.now()}={}){
 if(env?.BURIMUNSI_NATIVE_ENABLED!=='true')return null;
 need(typeof clock==='function','collect_adapter_required');
 const bound=await assembled(env,'http_collect');
 need(typeof trustedNetworkBucket==='function','trusted_network_resolver_required');
 if(env.BURIMUNSI_COLLECTION_ID!==undefined&&env.BURIMUNSI_COLLECTION_ID!=='')requireId(env.BURIMUNSI_COLLECTION_ID);
 need(env.BURIMUNSI_SMS_OBSERVATIONS_ENABLED===undefined||env.BURIMUNSI_SMS_OBSERVATIONS_ENABLED===''||
  ['true','false'].includes(env.BURIMUNSI_SMS_OBSERVATIONS_ENABLED),'native_service_unconfigured');
 need(env.BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED===undefined||env.BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED===''||
  ['true','false'].includes(env.BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED),'native_service_unconfigured');
 need(env.BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED===undefined||env.BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED===''||
  ['true','false'].includes(env.BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED),'native_service_unconfigured');
 const config=configuration(bound.profile,undefined,nativeObservationsEnabled(env),env.BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED==='true',
  env.BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED==='true'),secrets=secretsFor(env,{staffDefault:true});
 const networkBucket=async request=>{
  let value;try{value=await trustedNetworkBucket(request);}catch{need(false,'trusted_network_resolver_required');}
  need(typeof value==='string'&&/^[a-f0-9]{64}$/.test(value),'trusted_network_resolver_required');return value;
 };
 return createCollectNativeRoute({profile:bound.profile,config,secrets,networkBucket,clock,
  resolveGroup:({request,env:local})=>resolveNativeCollection({env:local,
   installationId:request.headers.get('X-BuriMunsi-Installation'),deviceToken:request.headers.get('X-BuriMunsi-Device')}),
  bridgeFactory:({env:local,db,work,profile,groupId})=>{
   need(db===bound.db&&work===bound.work&&canonicalProfile(profile)===bound.profileIdentity,'request_not_admitted');requireId(groupId);
   return bridgesFor(local,bound);
  }});
}

/** Separate explicit worker construction. Merely installing the HTTP route or
 * invoking a constructor never creates a scheduler, changes MOMO pause/approval,
 * fabricates managed credentials, or dispatches a provider. Worker methods keep
 * the existing approved policy, live managed principal and worker-lease guards.
 */
export async function createCollectNativeWorkerRuntime(env,{clock=()=>Date.now(),collectionId}={}){
 if(env?.BURIMUNSI_NATIVE_ENABLED!=='true'||env.BURIMUNSI_NATIVE_WORKERS_ENABLED!=='true')return null;
 need(typeof clock==='function','collect_adapter_required');
 const bound=await assembled(env,'jobs');
 const selected=collectionId??env.BURIMUNSI_COLLECTION_ID;
 // A scheduler selects an existing DB-backed scope explicitly. Each composed
 // worker still proves its policy/grant/lease before work. No global business
 // group or eager all-scope schedule is created by constructing this facade.
 if(selected===undefined||selected==='')return Object.freeze({forCollection:groupId=>createCollectNativeWorkerRuntime(env,{clock,collectionId:groupId})});
 requireId(selected);
 need(env.BURIMUNSI_COLLECTION_ID===undefined||env.BURIMUNSI_COLLECTION_ID===''||env.BURIMUNSI_COLLECTION_ID===selected,'managed_scope_changed');
 const config=configuration(bound.profile,selected);
 const secrets=secretsFor(env);
 return composePostgresNativeWorkers({admission:Object.freeze({verified:true,groupId:config.groupId}),config,
  db:bound.db,bridges:bridgesFor(env,bound),secrets,clock});
}

/** One bounded cycle under the real managed principal. The caller supplies a
 * server-selected collection and credential; no HTTP payload chooses either.
 * Existing processing policy, financial guard, worker grant and job leases are
 * still checked by the worker in each transaction. This starts no scheduler.
 */
export async function runCollectNativeScheduledCycle(env,{collectionId,owner,managedAccessToken}={}){
 requireId(collectionId);requireId(owner);
 need(env?.BURIMUNSI_NATIVE_ENABLED==='true'&&env.BURIMUNSI_NATIVE_WORKERS_ENABLED==='true');
 const bound=await assembled(env,'jobs');
 const request=new Request(bound.profile.supabase_origin+'/internal/burimunsi-scheduler',{
  headers:{'X-BuriMunsi-Collect-Session':managedAccessToken??''}});
 return managedWorkerGate({request,env,groupId:collectionId},async(_principal,local)=>{
  const workers=await createCollectNativeWorkerRuntime(local,{collectionId});
  need(workers&&typeof workers.runScheduledCycle==='function');
  return workers.runScheduledCycle({owner,receiptLimit:1,rematchLimit:0,targetsPerJob:1,leaseMs:180000,budgetMs:30000});
 });
}
