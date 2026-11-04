// Fixed application-health fields only. Requests, errors, credentials, bodies,
// query strings and actor/provider identities never enter this boundary.
const components=new Set(['platform','health','auth','privacy','challenge','admin',
 'reconciliation','native_integrity','operations','receipt','evidence','sync',
 'notifications','public_collections']);
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const SHA=/^[a-f0-9]{64}$/;
// Scheduled dispatches use the existing core.uuid1–8 contract; request IDs
// retain their original generated-v4-only contract.
const DISPATCH_UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;

export function platformHealthComponent(path){
 if(typeof path!=='string')return 'platform';
 if(path==='/health')return 'health';
 if(path==='/privacy/account-deletion'||path.startsWith('/privacy/account-deletion/')||path.startsWith('/api/admin/privacy/'))return 'privacy';
 if(path.startsWith('/v1/auth/')||path.startsWith('/api/admin/auth/'))return 'auth';
 if(path==='/v1/security/challenge')return 'challenge';
 if(path.startsWith('/api/admin/reconciliations'))return 'reconciliation';
 if(path.startsWith('/api/admin/'))return 'admin';
 if(path==='/v1/functions/verify-play-integrity')return 'native_integrity';
 if(path.startsWith('/v1/functions/')||path.startsWith('/v1/rpc/'))return 'operations';
 if(path.startsWith('/v1/receipts/'))return 'receipt';
 if(path.startsWith('/v1/evidence/'))return 'evidence';
 if(path==='/v1/sync')return 'sync';
 if(path==='/v1/query/notification-events')return 'notifications';
 if(path==='/v1/query/public-collections')return 'public_collections';
 return 'platform';
}

// An isolate may emit at most64 failure records plus one suppression notice per
// minute. This is a logging bound, not a cross-isolate quota or an accepted SLO.
export function createPlatformHealthReporter({emit=(level,text)=>console[level](text),clock=()=>Date.now()}={}){
 let window=null,count=0,suppressed=false;
 return function report(value){
  try{
   let {status,component,requestId,sourceId,elapsedMs,unexpected=false,runtimeFailure=null,dispatchId=null}=value;
   const hasDispatch=Object.hasOwn(value,'dispatchId');
   if(!Number.isInteger(status)||(status!==429&&(status<500||status>599))||!components.has(component))return false;
   const observed=clock();if(!Number.isFinite(observed)||observed<0)return false;
   const minute=Math.floor(observed/60000);
   if(window===null||minute>window){window=minute;count=0;suppressed=false;}
   const source=typeof sourceId==='string'&&SHA.test(sourceId)?sourceId:'unknown';
   let event,level,diagnostic=null,dispatchCorrelation=null;
   if(count>=64){
    if(suppressed)return false;
    suppressed=true;event='events_suppressed';level='warn';
    status=null;component='platform';requestId=null;elapsedMs=null;
   }else{
    count++;
    if(runtimeFailure!==null)diagnostic=runtimeFailureEvent(runtimeFailure.error,runtimeFailure.stage,runtimeFailure.env);
    event=diagnostic?'runtime_unavailable':unexpected===true?'unexpected_failure':status===429?'capacity_limited':'service_degraded';
    level=status===429?'warn':'error';
    requestId=typeof requestId==='string'&&UUID.test(requestId)?requestId:null;
    if(component==='operations'&&hasDispatch&&typeof dispatchId==='string'&&DISPATCH_UUID.test(dispatchId))dispatchCorrelation=dispatchId.toLowerCase();
    elapsedMs=Number.isFinite(elapsedMs)?Math.min(3600000,Math.max(0,Math.round(elapsedMs))):0;
   }
   emit(level,JSON.stringify({service:'collect_platform_api',schema_version:1,event,
    component,status,request_id:requestId,source_id:source,elapsed_ms:elapsedMs,
    ...(component==='operations'&&hasDispatch?{dispatch_id:dispatchCorrelation}:{}),
    ...(diagnostic?{stage:diagnostic.stage,reason:diagnostic.reason,configured:diagnostic.configured,
     ...(diagnostic.database_profile?{database_profile:diagnostic.database_profile}:{})}:{})}));
   return true;
  }catch{return false;}
 };
}
export const recordPlatformHealth=createPlatformHealthReporter();

// Runtime diagnostics use the same reporter/budget as domain failures. Raw
// errors and environment values are reduced here to the original fixed fields.
export function runtimeFailureEvent(error,stage,env){
 const reasons={'Supabase origin and database must be configured':'origin_or_database_missing','Invalid Supabase origin':'origin_invalid','Invalid database configuration':'database_invalid','Database connection overrides are not permitted':'database_overrides_rejected','Unexpected Supabase project':'project_mismatch','Database project identity mismatch':'database_target_mismatch','Invalid SUPABASE_PUBLISHABLE_KEYS':'publishable_dictionary_invalid','Invalid SUPABASE_SECRET_KEYS':'secret_dictionary_invalid','Missing configured publishable key':'publishable_key_missing','Invalid configured publishable key':'publishable_key_invalid','Missing configured secret key':'secret_key_missing','Invalid configured secret key':'secret_key_invalid'};
 const event={service:'collect_platform_api',event:'runtime_unavailable',stage:['environment','normalization','database_initialization','storage_initialization','provider_initialization','dispatch'].includes(stage)?stage:'unknown',reason:error instanceof Error&&Object.hasOwn(reasons,error.message)?reasons[error.message]:'unclassified',configured:{supabase_origin:typeof env?.SUPABASE_URL==='string'&&!!env.SUPABASE_URL,injected_database:typeof env?.SUPABASE_DB_URL==='string'&&!!env.SUPABASE_DB_URL,custom_database:typeof env?.COLLECT_DATABASE_URL==='string'&&!!env.COLLECT_DATABASE_URL,publishable_dictionary:typeof env?.SUPABASE_PUBLISHABLE_KEYS==='string'&&!!env.SUPABASE_PUBLISHABLE_KEYS,secret_dictionary:typeof env?.SUPABASE_SECRET_KEYS==='string'&&!!env.SUPABASE_SECRET_KEYS}};
 let profile;
 if(event.reason==='database_overrides_rejected'){
  // Inspect only closed enums and bounded counts. Never log URL strings,
  // credentials, arbitrary query names or arbitrary option values.
  try{const target=new URL(env.COLLECT_DATABASE_URL??env.SUPABASE_DB_URL),entries=[...target.searchParams],names=['sslmode','application_name','connect_timeout','sslrootcert','options','pgbouncer','connection_limit','pool_mode'],modes=['disable','allow','prefer','require','verify-ca','verify-full'];profile={parameter_count:Math.min(entries.length,16),parameters:[...new Set(entries.map(([name])=>names.includes(name)?name:'other'))].sort(),ssl_modes:[...new Set(target.searchParams.getAll('sslmode').map(value=>modes.includes(value)?value:'other'))].sort(),host:target.hostname==='db.rrlduytparvsjfmegalh.supabase.co'?'direct':target.hostname.endsWith('.pooler.supabase.com')?'pooler':'other',port:['5432','6543'].includes(target.port)?target.port:'other'};}catch{profile={invalid:true};}
 }
 return {...event,...(profile?{database_profile:profile}:{})};
}
