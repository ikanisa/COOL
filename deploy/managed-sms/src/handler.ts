import {app} from '../../collect-sms/src/index.ts';
import {sha256} from '../../collect-sms/src/util.ts';
import {receiptReadPrincipal,checkedReceiptResponse} from './receipt-read.ts';
import {verifyDeploymentProfile,normalizeHttpsOrigin} from '../../../supabase/functions/_shared/deployment-profile.js';
import {openApplicationWork} from '../../../supabase/functions/_shared/application-fence.js';
import {ManagedGatewayDatabase,isConfirmedAccessDenied} from './database.ts';
import {managedSmsFence} from './fence.ts';
import {bound,type Pool} from './transactions.ts';

const PREFIX='/functions/v1/collect-sms';
const MAX_BODY=262144;
const unavailable=()=>Response.json({error:{code:'gateway_unavailable',message:'The SMS gateway is unavailable. Retain the original operation for reconciliation.'}},{status:503,headers:{'cache-control':'no-store','x-content-type-options':'nosniff'}});
const denial=(status:number)=>new Response(null,{status,headers:{'cache-control':'no-store','x-content-type-options':'nosniff'}});
type Settings=Record<string,any>;
type Dependencies={poolFactory:(binding:any)=>Pool;databaseFactory?:(pool:Pool)=>any;fenceFactory?:(pool:Pool,profile:string)=>any;application?:typeof app;finishObservationMs?:number;backgroundGraceMs?:number};
async function bodyBytes(request:Request){
 const length=request.headers.get('content-length');if(length!==null&&(!/^(0|[1-9][0-9]*)$/.test(length)||Number(length)>MAX_BODY)){
  if(request.body)void request.body.cancel().catch(()=>{});throw Error('body_invalid');}
 const reader=request.body?.getReader();if(!reader)throw Error('body_invalid');const chunks:Uint8Array[]=[];let size=0,done=false,bytes:Uint8Array|undefined;
 let stop!:()=>void;const stopped=new Promise<never>((_,reject)=>{stop=()=>reject(Error('body_unconfirmed'));});
 const timer=setTimeout(stop,5000),onAbort=()=>stop();request.signal.addEventListener('abort',onAbort,{once:true});if(request.signal.aborted)stop();
 try{while(true){const part=await Promise.race([reader.read(),stopped]);if(part.done){done=true;break;}size+=part.value.byteLength;if(size>MAX_BODY)throw Error('body_invalid');chunks.push(part.value);}
  if(length!==null&&size!==Number(length))throw Error('body_invalid');bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
  const body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));if(!body||Array.isArray(body)||typeof body!=='object'||body.kind!=='receipt')throw Error('body_invalid');return bytes;
 }catch{bytes?.fill(0);throw Error('body_invalid');}finally{clearTimeout(timer);request.signal.removeEventListener('abort',onAbort);if(!done)void reader.cancel().catch(()=>{});try{reader.releaseLock();}catch{}for(const c of chunks)c.fill(0);}
}
/** Dependency injection is for synthetic fixtures; the exported Worker is closed. */
export function createManagedSmsHandler(deps:Dependencies){
 return async(request:Request,env:Settings,ctx:{waitUntil:(p:Promise<unknown>)=>void})=>{
  let corsOrigin:string|null=null;
  const handle=async()=>{
  let bytes:Uint8Array|undefined,pool:Pool|undefined,work:any;let response:Response|undefined;
  try{
   if(env.COLLECT_SMS_MANAGED_ENABLED!=='true'||!/^[a-f0-9]{64}$/.test(env.BUILD_SOURCE_ID??'')||
      !/^[a-f0-9]{64}$/.test(env.COLLECT_SMS_UNVERIFIED_APPROVAL_CLAIM_SHA256??'')||!env.COLLECT_DEPLOYMENT_PROFILE)throw Error('disabled');
   const profile=await verifyDeploymentProfile(env);if(profile.mode!=='managed'||profile.environment!=='production')throw Error('profile_invalid');
   const origin=normalizeHttpsOrigin(env.SMS_PUBLIC_ORIGIN);if(origin!==env.SMS_PUBLIC_ORIGIN||origin===profile.supabase_origin)throw Error('origin_invalid');
   const url=new URL(request.url);if(url.origin!==origin||url.search||url.hash)return denial(403);
   const browserOrigin=request.headers.get('origin');if(browserOrigin&&browserOrigin!==profile.admin_origin&&browserOrigin!==origin)return denial(403);
   corsOrigin=browserOrigin;
   if(!url.pathname.startsWith(PREFIX+'/'))return denial(404);const path=url.pathname.slice(PREFIX.length);
   if(request.method==='OPTIONS'){
    const method=request.headers.get('access-control-request-method');
    const getRoute=/^\/v1\/messages\/[^/]{1,600}$/.test(path),postRoute=path==='/v1/messages';
    if(!browserOrigin||!((getRoute&&method==='GET')||(postRoute&&method==='POST')))return denial(403);
    const requested=request.headers.get('access-control-request-headers');
    const names=requested===null?[]:requested.toLowerCase().split(',').map(v=>v.trim());
    const allowed=method==='GET'?new Set(['authorization','content-type']):new Set(['authorization','content-type','idempotency-key']);
    if((requested?.length??0)>1024||names.some(n=>!allowed.has(n))||new Set(names).size!==names.length)return denial(403);
    const h=new Headers({'cache-control':'no-store','x-content-type-options':'nosniff','access-control-allow-methods':method,
     vary:'Origin, Access-Control-Request-Method, Access-Control-Request-Headers'});
    if(names.length)h.set('access-control-allow-headers',names.join(', '));return new Response(null,{status:204,headers:h});
   }
   const messageGet=request.method==='GET'&&/^\/v1\/messages\/[^/]{1,600}$/.test(path);
   const messagePost=request.method==='POST'&&path==='/v1/messages';if(!messageGet&&!messagePost)return denial(404);
   const authorization=request.headers.get('authorization');if(!authorization||!/^Bearer app_[a-f0-9]{64}$/.test(authorization))return denial(401);
   const headers=new Headers({authorization});if(browserOrigin)headers.set('origin',browserOrigin);
   if(messagePost){
    const id=request.headers.get('idempotency-key');if(!id||id.length>128||!/^[\x21-\x7e]+$/.test(id)||id.includes(','))return denial(400);
    if(!/^application\/json(?:\s*;[^\r\n]*)?$/i.test(request.headers.get('content-type')??''))return denial(400);
    headers.set('idempotency-key',id);headers.set('content-type','application/json');
    try{bytes=await bodyBytes(request);}catch{return denial(400);}
   }
   if(request.signal.aborted)throw Error('aborted');
   pool=deps.poolFactory(env.SMS_HYPERDRIVE);const db=(deps.databaseFactory??(p=>new ManagedGatewayDatabase(p)))(pool);
   const backend=(deps.fenceFactory??managedSmsFence)(pool,env.COLLECT_DEPLOYMENT_PROFILE_SHA256);
   work=await (openApplicationWork as any)({backend,sourceSha256:env.BUILD_SOURCE_ID,kind:'http_collect',signal:request.signal});
   const tokenHash=await sha256(authorization.slice(7));
   const scopedDb=db.withApplicationWork(work,{tokenHash,scope:messageGet?'messages:read':'messages:write'});
   const bindings={DB:scopedDb,COLLECT_FENCE_WORK:work,ROOT_ADMIN_TOKEN:'',OTP_HMAC_KEY:'',
    ENVIRONMENT:'production',ALLOW_INSECURE_LOCALHOST:'false',ADMIN_ORIGIN:profile.admin_origin,
    FCM_ENABLED:'false',DISPATCH_PAUSED:'true',RETENTION_AUTO_PURGE:'false',FETCH:async()=>{throw Error('provider_disabled');}};
   let identity:{applicationId:string;messageId:string}|null=null;
   if(messageGet){try{
    const messageId=decodeURIComponent(path.slice('/v1/messages/'.length));
    if(!messageId||messageId.length>200||/[\0\r\n]/.test(messageId))throw Error('message_id_invalid');
    identity=await receiptReadPrincipal(scopedDb,tokenHash,messageId);if(!identity)response=denial(404);
   }catch(error){response=isConfirmedAccessDenied(error)?denial(404):unavailable();}}
   const target=new URL(path,origin);const forwarded=new Request(target,{method:request.method,headers,...(bytes?{body:bytes as unknown as BodyInit}:{}),signal:request.signal});
   const execution={props:{},waitUntil(p:Promise<unknown>){ctx.waitUntil(work.waitUntil(p));},passThroughOnException(){}};
   if(!response)try{response=await (deps.application??app).fetch(forwarded,bindings as any,execution as any);
    if(messageGet&&identity)response=await checkedReceiptResponse(response,identity,browserOrigin);
   }catch{response=undefined;}
   if(response?.status===404){if(response.body)void response.body.cancel().catch(()=>{});response=denial(404);}
   const finished=work.finish({failed:!response||response.status>=500});
   let result:any;try{result=await bound(finished,Math.min(10000,deps.finishObservationMs??10000));}catch{
    // The original work owns the pool until it finishes. Do not terminate an
    // in-flight close/commit just because its response deadline elapsed.
    const owned=pool;pool=undefined;
    const background=(async()=>{try{await bound(Promise.resolve(finished),Math.min(20000,deps.backgroundGraceMs??20000));}
     catch{return;}try{await bound(Promise.resolve(owned.end({timeout:0})),3000);}catch{/* quarantine on unknown cleanup */}})();
    try{ctx.waitUntil(background);}catch{/* isolate lifetime/cleanup remains unconfirmed */}return unavailable();
   }
   if(result?.state!=='settled'||!result.applicationWorkFinished||!response||response.status>=500)return unavailable();
   const output=new Response(response.body,response);output.headers.set('cache-control','no-store');output.headers.set('x-content-type-options','nosniff');return output;
  }catch{return unavailable();}
  finally{bytes?.fill(0);if(pool){try{await bound(Promise.resolve(pool.end({timeout:0})),3000);}catch{return unavailable();}}}
  };
  const result=await handle();
  if(!corsOrigin)return result;
  const headers=new Headers(result.headers),vary=headers.get('vary');
  headers.set('access-control-allow-origin',corsOrigin);
  if(!vary?.split(',').some(v=>v.trim().toLowerCase()==='origin'))headers.set('vary',vary?`${vary}, Origin`:'Origin');
  return new Response(result.body,{status:result.status,statusText:result.statusText,headers});
 };
}
