// Pure renderer only: it never writes the currently qualified Edge sources.
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const sha=x=>createHash('sha256').update(x).digest('hex');
const pins={serve:'0c1305540340c19a058ce5f5510c67a586b82eeacb98e45f226ebe4b1499b1da',
 processing:'08571899e08aa0e9b01b2cf8aa8807e099061de29725e54f8719c37ed5fd8270'};
const integrated={serve:'45862b8c5442041157bc2274dfd5c7aa19fa31c25570da0e146ab02a5f1f2ac1',
 processing:'64a161f7aef2d4e113d3a88c0f2063cbaf70219416ed6d031b873c8aec4f8d2b',
 auth:'5cac35234d8fce99056705a7e002c078970366a007e4a572b00485a9502ad463',
 budget:'8c212ad319d820374a33abcaeb405ee643010cc86b0e107790d39b7020fe9962'};
function once(text,from,to){const i=text.indexOf(from);if(i<0||text.indexOf(from,i+from.length)>=0)throw Error('jobs_handler_base_changed');return text.slice(0,i)+to+text.slice(i+from.length);}
export async function renderManagedJobsHandler(){
 let serve=await readFile(new URL('../../../supabase/functions/_shared/serve.js',import.meta.url),'utf8');
 let processing=await readFile(new URL('../../../supabase/functions/_shared/scheduled-processing.js',import.meta.url),'utf8');
 const auth=await readFile(new URL('./managed-jobs-dispatch-auth.mjs',import.meta.url),'utf8');
 const budget=await readFile(new URL('./native-provider-budget.mjs',import.meta.url),'utf8');
 if(sha(budget)!==integrated.budget)throw Error('jobs_budget_module_changed');
 if(sha(serve)===integrated.serve&&sha(processing)===integrated.processing&&sha(auth)===integrated.auth){
  const installed=await readFile(new URL('../../../supabase/functions/_shared/managed-jobs-dispatch-auth.mjs',import.meta.url),'utf8');
  if(sha(installed)!==integrated.auth)throw Error('jobs_handler_module_changed');
  if(sha(await readFile(new URL('../../../supabase/functions/_shared/native-provider-budget.mjs',import.meta.url),'utf8'))!==integrated.budget)throw Error('jobs_budget_module_changed');
  return {serve,processing,auth,budget,hashes:integrated,basePins:pins};
 }
 if(sha(serve)!==pins.serve||sha(processing)!==pins.processing)throw Error('jobs_handler_base_changed');
 serve=once(serve,"import {parseScheduledDispatch,scheduledProcessingAdmission,scheduledProcessingResult,scheduledNotificationResult} from './scheduled-processing.js';",
  "import {parseScheduledDispatch,scheduledProcessingAdmission,scheduledProcessingResult,scheduledNotificationResult} from './scheduled-processing.js';\nimport {verifyManagedJobSignature,claimManagedJobDispatch,completeManagedJobDispatch,nativeSmsAdmission} from './managed-jobs-dispatch-auth.mjs';");
 serve=once(serve,"  const started=performance.now();let work,env,dispatchId=null,dispatch={dispatchId:null,processing:null,notifications:null},stage='environment';try{env=envReader();const input=env,token=request.headers.get('Authorization');if(!input.COLLECT_JOB_TOKEN||token!=='Bearer '+input.COLLECT_JOB_TOKEN)return json({code:'unauthorized'},401);",
 `  const started=performance.now();let work,env,dispatchId=null,dispatch={dispatchId:null,processing:null,notifications:null},stage='environment';try{env=envReader();const input=env,token=request.headers.get('Authorization');
   const managed=input.COLLECT_JOB_AUTH_MODE==='supabase_dispatch_hmac_v1';
   if(!managed&&(input.SUPABASE_URL==='https://rrlduytparvsjfmegalh.supabase.co'||(input.COLLECT_JOB_AUTH_MODE!==undefined&&input.COLLECT_JOB_AUTH_MODE!=='')||!input.COLLECT_JOB_TOKEN||token!=='Bearer '+input.COLLECT_JOB_TOKEN))return json({code:'unauthorized'},401);`);
 serve=once(serve,"   if(request.body!==null){\n    try{dispatch=parseScheduledDispatch(await readJson(request,2048));dispatchId=dispatch.dispatchId;",
  "   let payload=null;\n   if(request.body!==null){\n    try{payload=await readJson(request,2048);dispatch=parseScheduledDispatch(payload);dispatchId=dispatch.dispatchId;");
 serve=once(serve,"   stage='normalization';await verifyDeploymentProfile(input);",
  "   if(managed&&!(await verifyManagedJobSignature(input,payload,token)))return json({code:'unauthorized'},401);\n   stage='normalization';await verifyDeploymentProfile(input);");
 serve=once(serve,"env.COLLECT_FENCE_WORK=work;env.DB.setApplicationWork(work);stage='storage_initialization';",
  "env.COLLECT_FENCE_WORK=work;env.DB.setApplicationWork(work);if(managed&&!(await claimManagedJobDispatch(env.DB,input,payload,token)))return json({code:'unauthorized'},401);stage='storage_initialization';");
 serve=once(serve,"Object.assign(env,providerAdapters(env));stage='dispatch';",
  "Object.assign(env,providerAdapters(env));const nativeGate=managed?nativeSmsAdmission(env,payload):{allowed:true,enabled:false};if(!nativeGate.allowed)return json({code:'native_sms_admission_changed'},503);stage='dispatch';");
 serve=once(serve,"return json({...(dispatchId?{dispatch_id:dispatchId}:{}),...(admission.processing?{processing_admission:admission.processing}:{}),",
  "const response=json({...(dispatchId?{dispatch_id:dispatchId}:{}),...(nativeGate.enabled?{native_sms_admission:nativeGate.admission}:{}),...(admission.processing?{processing_admission:admission.processing}:{}),");
 serve=once(serve,"realtime,diagnostics},status);",
  "realtime,diagnostics},status);if(managed&&status===200&&!(await completeManagedJobDispatch(env.DB,input,dispatchId,response)))return json({code:'job_completion_unconfirmed'},503);return response;");
 processing=once(processing,"!['dispatch_id','processing_admission','notification_admission'].includes(key)",
  "!['dispatch_id','dispatch_expires_at','native_sms_admission','processing_admission','notification_admission'].includes(key)");
 serve=once(serve,"import {verifyManagedJobSignature,claimManagedJobDispatch,completeManagedJobDispatch,nativeSmsAdmission} from './managed-jobs-dispatch-auth.mjs';",
  "import {verifyManagedJobSignature,claimManagedJobDispatch,completeManagedJobDispatch,nativeSmsAdmission} from './managed-jobs-dispatch-auth.mjs';\nimport {withNativeProviderBudget} from './native-provider-budget.mjs';");
 serve=once(serve,'   let nativeAuto=null;','   const nativeEnv=nativeGate.enabled?withNativeProviderBudget(env,payload):env;\n   let nativeAuto=null;');
 serve=once(serve,'processNativeAuto(env,{limit:1})','processNativeAuto(nativeEnv,{limit:1})');
 serve=once(serve,'processNativeSmsLedger(env,{limit:1})','processNativeSmsLedger(nativeEnv,{limit:1})');
 return {serve,processing,auth,budget,hashes:{serve:sha(serve),processing:sha(processing),auth:sha(auth),budget:sha(budget)},basePins:pins};
}
