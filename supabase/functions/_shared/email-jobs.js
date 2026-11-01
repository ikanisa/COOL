import {verifyDeploymentProfile} from './deployment-profile.js';
import {assertRuntimeDeployment} from './deployment-database.js';
import {normalizeRuntimeEnv} from './runtime-env.js';
import {connection,fenceConnection,PostgresDatabase} from './postgres.js';
import {openApplicationWork,sqlFenceBackend} from './application-fence.js';
import {providerAdapters} from './adapters.js';
import {drainContributionEmailDispatch,validContributionEmailAdmission} from './domain/contribution_email_delivery.js';
import {parseEmailJobDispatch,emailJobResult} from './email-job-contract.js';
import {json,readJson} from './domain/core.js';

export function createContributionEmailJobsHandler(envReader=()=>Deno.env.toObject(),{openWork=openApplicationWork,processEmails=drainContributionEmailDispatch,databaseFactory=env=>new PostgresDatabase(connection(env.COLLECT_DATABASE_URL,env))}={}){
 return async request=>{
  let work;
  try{
   let env=envReader();
   if(typeof env.COLLECT_EMAIL_JOB_TOKEN!=='string'||env.COLLECT_EMAIL_JOB_TOKEN.length<32||request.headers.get('Authorization')!=='Bearer '+env.COLLECT_EMAIL_JOB_TOKEN)return json({code:'unauthorized'},401);
   if(request.method!=='POST')return json({code:'method_not_allowed'},405);
   if(!/^\/(?:functions\/v1\/)?collect-email-jobs\/?$/.test(new URL(request.url).pathname))return json({code:'not_found'},404);
   let dispatch;try{dispatch=parseEmailJobDispatch(await readJson(request,2048));}catch{return json({code:'invalid_email_dispatch'},400);}
   if(env.COLLECT_CONTRIBUTION_EMAIL_ENABLED!=='true'||!validContributionEmailAdmission(env,dispatch.admission))return json({code:'email_admission_unavailable'},503);
   await verifyDeploymentProfile(env);env=normalizeRuntimeEnv(env);
   env.DB=databaseFactory(env);await assertRuntimeDeployment(env.DB.sql,env);
   work=await openWork({backend:sqlFenceBackend(env.DB.sql,fenceConnection(env.COLLECT_DATABASE_URL,env)),sourceSha256:env.BUILD_SOURCE_ID,kind:'jobs'});
   env.COLLECT_FENCE_WORK=work;env.DB.setApplicationWork(work);Object.assign(env,providerAdapters(env));
   const emails=emailJobResult(await processEmails(env,{dispatchId:dispatch.dispatchId,admission:dispatch.admission}));
   return json({dispatch_id:dispatch.dispatchId,email_admission:dispatch.admission,emails},emails.status==='complete'?200:503);
  }catch{return json({code:'email_jobs_unconfirmed'},503);}
  finally{if(work){const close=work.finish().catch(()=>console.error(JSON.stringify({service:'collect_email_jobs',event:'work_close_unconfirmed'})));if(typeof EdgeRuntime!=='undefined')EdgeRuntime.waitUntil(close);else await close;}}
 };
}
