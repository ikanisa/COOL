import {app,maintenance} from './index.ts';
import {GatewayDatabase,gatewayConnection} from './postgres.ts';
import {verifyDeploymentProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {openApplicationWork,guardedFetch} from '../../../supabase/functions/_shared/application-fence.js';
import {smsFenceBackend} from './fence.ts';
import type {Env} from './types.ts';

type Settings=Record<string,string|undefined>;
const unavailable=()=>Response.json({error:{code:'gateway_unavailable',message:'The SMS gateway is not enabled.'}},{status:503,headers:{'cache-control':'no-store'}});
export function createSmsGatewayHandler(settings:Settings,options:{database?:GatewayDatabase;fenceBackend?:ReturnType<typeof smsFenceBackend>;waitUntil?:(promise:Promise<unknown>)=>void}={}){
 let ready:Promise<Env>|undefined;
 let publicOrigin:string|undefined;
 let backend:ReturnType<typeof smsFenceBackend>;
 async function environment(){
  if(settings.COLLECT_SMS_ENABLED!=='true')throw Error('gateway_disabled');
  const profile=await verifyDeploymentProfile(settings);
  if(!settings.COLLECT_DEPLOYMENT_PROFILE||profile.mode!=='self_hosted'||
   !/^[a-f0-9]{64}$/.test(settings.COLLECT_SMS_APPROVAL_SHA256??'')||
   !/^[a-f0-9]{64}$/.test(settings.BUILD_SOURCE_ID??'')||
   (settings.ROOT_ADMIN_TOKEN?.length??0)<32||(settings.OTP_HMAC_KEY?.length??0)<32)throw Error('gateway_configuration');
  const DB=options.database??new GatewayDatabase(gatewayConnection(settings.COLLECT_SMS_DATABASE_URL??'',settings));
  backend=options.fenceBackend??smsFenceBackend(DB.sql,gatewayConnection(settings.COLLECT_SMS_DATABASE_URL??'',settings),settings.COLLECT_DEPLOYMENT_PROFILE_SHA256!);
  publicOrigin=profile.supabase_origin;
  return {...settings,DB,ROOT_ADMIN_TOKEN:settings.ROOT_ADMIN_TOKEN!,OTP_HMAC_KEY:settings.OTP_HMAC_KEY!,
   ENVIRONMENT:'production',ALLOW_INSECURE_LOCALHOST:'false',
   ADMIN_ORIGIN:profile.admin_origin,
   DISPATCH_PAUSED:settings.DISPATCH_PAUSED==='false'?'false':'true',
   FCM_ENABLED:settings.FCM_ENABLED==='true'?'true':'false',
   RETENTION_AUTO_PURGE:settings.RETENTION_AUTO_PURGE==='true'?'true':'false'} as Env;
 }
 return async(request:Request):Promise<Response>=>{
  let base:Env;try{ready??=environment();base=await ready;}catch{return unavailable();}
  const url=new URL(request.url);
  const authority=new URL(publicOrigin!);
  // Reconstruct only the verified self-hosted ingress routes. Forwarded
  // headers never establish scheme, host or browser authority.
  if(url.protocol==='http:'&&(url.hostname===authority.hostname&&!url.port||
    ['http://api-gw:8000','http://functions:9000','http://127.0.0.1:9000'].includes(url.origin))){
   url.protocol='https:';url.hostname=authority.hostname;url.port='';
  }
  for(const prefix of ['/functions/v1/collect-sms','/collect-sms']){
   if(url.pathname===prefix){url.pathname='/';break;}
   if(url.pathname.startsWith(prefix+'/')){url.pathname=url.pathname.slice(prefix.length);break;}
  }
  if(url.origin!==publicOrigin)return new Response(null,{status:403,headers:{'cache-control':'no-store'}});
  // Scheduled maintenance is never exposed through an application/device token.
  if(url.pathname==='/internal/maintenance'){
   if(request.method!=='POST'||!settings.COLLECT_SMS_MAINTENANCE_TOKEN||settings.COLLECT_SMS_MAINTENANCE_TOKEN.length<32||
    request.headers.get('authorization')!=='Bearer '+settings.COLLECT_SMS_MAINTENANCE_TOKEN)return new Response(null,{status:404});
  }
  let work:Awaited<ReturnType<typeof openApplicationWork>>;
  try{work=await (openApplicationWork as any)({backend,sourceSha256:settings.BUILD_SOURCE_ID,kind:url.pathname==='/internal/maintenance'?'jobs':'http_collect'});}catch{return unavailable();}
  const env={...base,DB:(base.DB as GatewayDatabase).withApplicationWork(work),COLLECT_FENCE_WORK:work} as Env;
  env.FETCH=(input,init)=>guardedFetch(env,'gateway_http',input,init);
  const context={props:{},waitUntil(promise:Promise<unknown>){const owned=work.waitUntil(promise);options.waitUntil?.(owned);},passThroughOnException(){}};
  let failed=false;
  try{
   if(url.pathname==='/internal/maintenance'){await maintenance(env);return Response.json({ok:true},{headers:{'cache-control':'no-store'}});}
   const response=await app.fetch(new Request(url,request),env,context);failed=response.status>=500;return response;
  }catch{failed=true;return unavailable();}
  finally{
   // Even with Edge waitUntil, the original lease owns all pending database,
   // callback and FCM work. Unknown effects retain their original counters.
   try{await work.finish({failed});}catch{ /* Durable unresolved admission blocks drain. */ }
  }
 };
}
