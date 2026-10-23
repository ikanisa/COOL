// Fixed application-health fields only. Requests, errors, credentials, bodies,
// query strings and actor/provider identities never enter this boundary.
const components=new Set(['platform','health','auth','privacy','challenge','admin',
 'reconciliation','native_integrity','operations','receipt','evidence','sync',
 'notifications','public_collections']);
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const SHA=/^[a-f0-9]{64}$/;

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
   let {status,component,requestId,sourceId,elapsedMs,unexpected=false}=value;
   if(!Number.isInteger(status)||(status!==429&&(status<500||status>599))||!components.has(component))return false;
   const observed=clock();if(!Number.isFinite(observed)||observed<0)return false;
   const minute=Math.floor(observed/60000);
   if(window===null||minute>window){window=minute;count=0;suppressed=false;}
   const source=typeof sourceId==='string'&&SHA.test(sourceId)?sourceId:'unknown';
   let event,level;
   if(count>=64){
    if(suppressed)return false;
    suppressed=true;event='events_suppressed';level='warn';
    status=null;component='platform';requestId=null;elapsedMs=null;
   }else{
    count++;
    event=unexpected===true?'unexpected_failure':status===429?'capacity_limited':'service_degraded';
    level=status===429?'warn':'error';
    requestId=typeof requestId==='string'&&UUID.test(requestId)?requestId:null;
    elapsedMs=Number.isFinite(elapsedMs)?Math.min(3600000,Math.max(0,Math.round(elapsedMs))):0;
   }
   emit(level,JSON.stringify({service:'collect_platform_api',schema_version:1,event,
    component,status,request_id:requestId,source_id:source,elapsed_ms:elapsedMs}));
   return true;
  }catch{return false;}
 };
}
export const recordPlatformHealth=createPlatformHealthReporter();
