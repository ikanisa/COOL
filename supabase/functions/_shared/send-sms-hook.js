import {createHandler as createSignedHandler} from '../send-sms-hook/handler.mjs';
import {verifyDeploymentProfile} from './deployment-profile.js';
import {assertRuntimeDeployment} from './deployment-database.js';
import {connection,fenceConnection} from './postgres.js';
import {openApplicationWork,sqlFenceBackend,guardedFetch,noteUnknownEffect} from './application-fence.js';

const unavailable=()=>new Response(JSON.stringify({error:{http_code:503,message:'SMS service unavailable.'}}),
 {status:503,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
async function beginWork(env){
 const sql=connection(env.COLLECT_DATABASE_URL,env);
 await assertRuntimeDeployment(sql,env);
 return openApplicationWork({backend:sqlFenceBackend(sql,fenceConnection(env.COLLECT_DATABASE_URL,env)),sourceSha256:env.BUILD_SOURCE_ID,kind:'http_collect'});
}

/** Signature/body validation precedes every DB admission and provider operation.
 * The signed handler owns one four-second response deadline. Admission and late
 * transport cleanup remain owned even when that response deadline expires.
 */
export function createCollectSendSmsHandler(envReader=()=>Deno.env.toObject(),{admit=beginWork,handlerOptions={}}={}){
 return async request=>{
  let env;try{env={...envReader()};}catch{return unavailable();}
  // GoTrue v2.197.0's signed payload has no requested channel. The custom
  // OpenSMS hook and native WhatsApp delivery are mutually exclusive modes.
  if(env.AUTH_SMS_ENABLED!=='true'||env.AUTH_PHONE_DELIVERY_MODE!=='opensms_hook'||env.AUTH_WHATSAPP_ENABLED==='true')return unavailable();
  let workPromise,work;
  const transport=async(url,options)=>{
   if(options.signal.aborted)throw Error('sms_hook_deadline');
   workPromise??=(async()=>{
    const profile=await verifyDeploymentProfile(env);
    if(env.COLLECT_DEPLOYMENT_PROFILE===undefined||env.AUTH_PROJECT_ID!==profile.id||
     env.APP_ENVIRONMENT!==profile.environment||env.SUPABASE_URL!==profile.supabase_origin||
     !/^[a-f0-9]{64}$/.test(env.BUILD_SOURCE_ID??'')||
     // An Auth application token can never double as the receipt credential.
     env.OPENSMS_APPLICATION_TOKEN===env.OPENSMS_RECEIPT_APPLICATION_TOKEN||
     env.OPENSMS_APPLICATION_ID===env.OPENSMS_RECEIPT_APPLICATION_ID)throw Error('sms_hook_configuration');
    if(options.signal.aborted)throw Error('sms_hook_deadline');
    work=await admit(env);env.COLLECT_FENCE_WORK=work;return work;
   })();
   await workPromise;
   if(options.signal.aborted)throw Error('sms_hook_deadline');
   return guardedFetch(env,'sms_otp',url,options);
  };
  try{
   const result=await createSignedHandler({...env,OPENSMS_SENDER_LABEL:env.OPENSMS_SENDER_LABEL??'Collect'},
    {...handlerOptions,transport})(request);
   if(result.status>=500&&work)noteUnknownEffect(env,'sms_otp');
   return result;
  }catch{return unavailable();}
  finally{
   if(workPromise){
    const completion=workPromise.then(owned=>owned.finish()).catch(()=>{});
    if(typeof EdgeRuntime!=='undefined')EdgeRuntime.waitUntil(completion);
   }
  }
 };
}
