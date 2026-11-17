// Wrap only the two admitted native SMS lanes. A durable reservation commits
// immediately before each provider invocation; uncertainty never refunds it.
import {nativeSmsAdmission} from './managed-jobs-dispatch-auth.mjs';
const unavailable=()=>Object.assign(new Error('Native provider budget unavailable.'),{code:'native_provider_budget_unavailable',status:503});
export function withNativeProviderBudget(env,payload){
 const provider=env.AI,admission=nativeSmsAdmission(env,payload);
 if(!admission.allowed||!admission.enabled)throw unavailable();
 const source=env.BUILD_SOURCE_ID,model=env.MOMO_AI_MODEL,approval=env.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256;
 return {...env,AI:{async run(legacy,options){
  const work=env.DB?.applicationWork;
  if(env.COLLECT_JOB_AUTH_MODE!=='supabase_dispatch_hmac_v1'||work?.kind!=='jobs'||work!==env.COLLECT_FENCE_WORK||
   typeof work.assert!=='function'||env.BUILD_SOURCE_ID!==source||env.MOMO_AI_MODEL!==model||
   env.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256!==approval||typeof model!=='string'||!/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/.test(model)||
   !Number.isSafeInteger(options?.max_tokens)||options.max_tokens<1||options.max_tokens>1400||
   options.response_format?.json_schema?.properties?.schema_version?.enum?.[0]!=='momo-native-extraction.v2')throw unavailable();
  await work.assert();
  const row=await env.DB.prepare('SELECT private.collect_native_provider_reserve(?::uuid,?::text,?::text,?::text) AS accepted')
   .bind(payload.dispatch_id,source,model,approval).first();
  if(row?.accepted!==true)throw unavailable();
  await work.assert();
  // The actual provider adapter contains one guarded fetch and no retry loop.
  return await provider.run(legacy,options);
 }}};
}
