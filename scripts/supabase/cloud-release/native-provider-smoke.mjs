// Exactly one authorized non-personal provider request. Never write its raw
// response, input, authorization header or key to stdout or evidence. An
// uncertain outcome is reconciled manually; there is no automatic retry.
import {existsSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {management,record,ROOT,sha} from './access.mjs';
import {prepareNativeAutoExtraction,validateNativeAutoExtraction} from '../../../supabase/functions/_shared/domain/burimunsi/native-auto-parser.js';

if(process.argv.length!==3||process.argv[2]!=='--one-authorized-synthetic')throw Error('explicit_single_synthetic_request_required');
if(existsSync(ROOT+'/managed-jobs-provider-smoke-intent.json'))throw Error('prior_attempt_requires_reconciliation');
const env=process.env,model=env.MOMO_AI_MODEL;
if(model!=='gpt-5.4-mini-2026-03-17'||typeof env.OPENAI_API_KEY!=='string'||!env.OPENAI_API_KEY)throw Error('provider_source_config_changed');
const remote=(await management('secrets')).json(),key=remote.filter(x=>x.name==='OPENAI_API_KEY');
if(key.length!==1||key[0].value!==sha(env.OPENAI_API_KEY))throw Error('provider_cloud_key_changed');
const account={provider:'mtn_momo',status:'active',profile_status:'approved',profile_version:'synthetic-1',currency:'RWF',timezone:'Africa/Kigali',
 profile_json:JSON.stringify({sender_allowlist:['Example Money'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],transaction_id_prefixes:['FT Id:'],outgoing_markers:['You have sent'],date_format:'YMD_HMS',utc_offset_minutes:120})};
// A generic payment reference is not an unambiguous provider transaction ID.
const source={raw_sender:'Example Money',raw_body:'You have received 1,250 RWF from Example Person. FT Id: ABC123. Fee 10 RWF. Balance 9,000 RWF.',source_mode:'catch_up'};
const prepared=prepareNativeAutoExtraction(source,account);if(prepared.kind!=='provider')throw Error('synthetic_contract_invalid');
const p=prepared.request,id=randomUUID(),started=Date.now();
record('managed-jobs-provider-smoke-intent.json',{format:'collect.jobs.provider-smoke.v1',id,model,source:'synthetic_nonpersonal',maxCompletionTokens:p.max_tokens,providerTimeoutMs:8000,at:new Date().toISOString()});
let status=null,code=null,usage=null,parsed=null;
try{
 const response=await fetch('https://api.openai.com/v1/chat/completions',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+env.OPENAI_API_KEY},redirect:'error',signal:AbortSignal.timeout(8000),
  body:JSON.stringify({model,messages:p.messages,temperature:0,max_completion_tokens:p.max_tokens,store:false,response_format:{type:'json_schema',json_schema:{name:'collect_momo_extraction',strict:true,schema:p.response_format.json_schema}}})});
 status=response.status;const raw=await response.arrayBuffer();if(raw.byteLength>65536)throw Error('response_too_large');
 const body=JSON.parse(new TextDecoder().decode(raw));
 if(!response.ok){const allowed=new Set(['insufficient_quota','credit_balance_exhausted','organization_usage_limit_exceeded','organization_spend_limit_exceeded','project_spend_limit_exceeded','rate_limit_exceeded','invalid_api_key','model_not_found']);code=allowed.has(body?.error?.code)?body.error.code:'provider_rejected';}
 else{
  const value=JSON.parse(body.choices?.[0]?.message?.content),v=validateNativeAutoExtraction(source,account,value);
  parsed={schemaValid:v.kind==='parsed',incoming:v.direction==='incoming',successful:v.facts?.payment_outcome==='successful',
   principalMatches:v.facts?.amount_minor===1250,currencyMatches:v.facts?.currency==='RWF',referenceMatches:v.facts?.provider_transaction_id==='ABC123'};
  const u=body.usage;if(u&&[u.prompt_tokens,u.completion_tokens,u.total_tokens].every(Number.isSafeInteger))usage={inputTokens:u.prompt_tokens,outputTokens:u.completion_tokens,totalTokens:u.total_tokens};
 }
}catch(error){code=error?.name==='TimeoutError'?'timeout_unconfirmed':'response_unconfirmed';}
const result={format:'collect.jobs.provider-smoke.v1',id,model,httpStatus:status,errorCode:code,parsed,usage,
 costUpperBoundUsd:usage?(usage.inputTokens*0.75+usage.outputTokens*4.5)/1_000_000:null,
 outcome:status===200&&parsed&&Object.values(parsed).every(Boolean)?'validated':'unconfirmed',elapsedMs:Date.now()-started,
 syntheticOnly:true,financialWrites:0,at:new Date().toISOString()};
record('managed-jobs-provider-smoke-result.json',result);
console.log(JSON.stringify(result));
