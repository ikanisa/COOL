// Compile the ORIGINAL canonical producer batch. No SQL, AI/provider, storage
// upload, account or application admission is created by this compiler.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {registerHooks} from 'node:module';
import {MOMO_SCHEMA_VERSION,validateProviderProfile,validateMomoExtraction,finishStatements} from '../../functions/_shared/domain/momo_pipeline.js';
import {canonicalJson} from '../../functions/_shared/domain/burimunsi/values.js';
registerHooks({resolve(specifier,context,next){
 if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){throw Error("SQL compilation only")}',shortCircuit:true};
 return next(specifier,context);
}});
const {compileSql}=await import('../../functions/_shared/postgres.js');
const hash=value=>createHash('sha256').update(value).digest('hex');
const literal=value=>value===null?'NULL':typeof value==='number'?String(value):"'"+String(value).replaceAll("'","''")+"'";
const profile={sender_allowlist:['M-Money'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],
 transaction_id_prefixes:['FT Id:'],date_format:'YMD_HMS',utc_offset_minutes:120};
const body='You have received 1,000 RWF from QUALIFICATION PAYER (*****001) at 2026-11-10 12:00:00. Balance: 25,000 RWF. FT Id: 1234567890.';
const account={id:'buri-qualification-wallet',provider:'mtn_momo',status:'active',profile_status:'approved',
 profile_version:'adoption-profile.v1',profile_json:JSON.stringify(profile),currency:'RWF',timezone:'Africa/Kigali'};
const output={schema_version:MOMO_SCHEMA_VERSION,event_kind:'incoming_receipt',payment_outcome:'successful',
 transaction_id_raw:'1234567890',original_transaction_id_raw:null,transaction_datetime_raw:'2026-11-10 12:00:00',
 principal_amount_raw:'1,000',currency_raw:'RWF',payer_name_raw:'QUALIFICATION PAYER',payer_identifier_raw:'*****001',
 payment_reference_raw:null,fee_amount_raw:null,wallet_balance_after_raw:'25,000',issues:[],evidence:{
 incoming_success:'You have received 1,000 RWF',principal:'1,000 RWF',transaction_id:'FT Id: 1234567890',
 transaction_datetime:'2026-11-10 12:00:00',payer:'QUALIFICATION PAYER (*****001)',fee:null,wallet_balance_after:'Balance: 25,000 RWF'}};
const hashBody=hash(body);
const payload=canonicalJson({raw_sender:'M-Money',normalized_sender:'M-Money',raw_body:body,
 receiver_momo_number:'00000',gateway_binding_id:'adoption-binding',gateway_binding_version:1,
 subscription_id:7,completeness:'complete',source_mode:'live',captured_at:'2026-11-10T10:00:00.000Z',
 inbox_received_at:'2026-11-10T10:00:00.000Z',service_centre_at:null,received_at_device:null});
const env={DB:{prepare:sql=>({bind:(...values)=>({sql,values})})}};
function producer(name,sourceBody,extraction,sourceAccount,{terminalNonpayment=false}={}){
 const validation=validateMomoExtraction(extraction,{raw_body:sourceBody,raw_sender:'M-Money'},sourceAccount,validateProviderProfile(sourceAccount));
 assert.equal(validation.accepted,true,JSON.stringify(validation.errors));
 const job={raw_sms_id:'__adoption_source__',lease_token:'__adoption_lease__',attempt_count:'__adoption_attempt__',
  receiving_account_id:sourceAccount.id,body_sha256:hash(sourceBody),mode:'live'};
 // The no-fact branch exercises terminal-job plumbing only; it cannot
 // reclassify/delete the immutable historical fact or authorize a posting.
 const built=finishStatements(env,job,sourceAccount,terminalNonpayment?
  {output:null,validation:[{code:'not_successful_incoming'}],outcome:'non_payment',state:'completed',facts:null}:
  {output:extraction,validation:[],outcome:'accepted',state:'completed',facts:validation.facts});
 const guard=built.writes.find(x=>x.sql.startsWith('INSERT INTO momo_processing_guards')).values[0];
 const candidate=built.writes.find(x=>x.sql.startsWith('INSERT INTO momo_transactions'))?.values[0];
 const special=new Map([[job.raw_sms_id,'p_source'],[job.lease_token,'p_lease'],[job.attempt_count,'p_attempt'],[built.attemptId,'v_attempt'],
  [guard,'v_guard'],[guard+':profile',"v_guard||':profile'"],[guard+':finish',"v_guard||':finish'"],[candidate,'v_candidate']]);
 const statements=built.writes.map(statement=>{
  const {text,values}=compileSql(statement.sql,statement.values);
  const sql=text.replace(/\$(\d+)\b/g,(_,n)=>special.get(values[Number(n)-1])??literal(values[Number(n)-1]));
  return sql+'; GET DIAGNOSTICS v_changes=ROW_COUNT; PERFORM set_config(\'collect.last_changes\',v_changes::text,true);';
 });
 return `CREATE FUNCTION pg_temp.${name}(p_source text,p_lease text,p_attempt bigint DEFAULT 1) RETURNS void
 LANGUAGE plpgsql SECURITY INVOKER SET search_path=app,pg_catalog AS $adoption$
 DECLARE v_attempt text:=gen_random_uuid()::text;v_guard text:=gen_random_uuid()::text;
 v_candidate text:=gen_random_uuid()::text;v_changes bigint;
 BEGIN PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 ${statements.join('\n')}
 END;$adoption$;`;
}
const conflictBody=body.replaceAll('1,000','2,000');
const conflictOutput={...output,principal_amount_raw:'2,000',evidence:{...output.evidence,
 incoming_success:'You have received 2,000 RWF',principal:'2,000 RWF'}};
const otherWallet={...account,id:'adoption-other-wallet'};
const functions=[producer('adoption_finish',body,output,account),
 producer('adoption_finish_conflict',conflictBody,conflictOutput,account),
 producer('adoption_finish_other_wallet',body,output,otherWallet),
 producer('adoption_finish_nonreceipt',body,output,account,{terminalNonpayment:true}),
 `SELECT set_config('burimunsi.adoption.fixture.body',${literal(body)},true),
 set_config('burimunsi.adoption.fixture.profile',${literal(account.profile_json)},true),
 set_config('burimunsi.adoption.fixture.payload',${literal(payload)},true),
 set_config('burimunsi.adoption.fixture.conflict_body',${literal(conflictBody)},true);`];
const sources={};
const root=new URL('../../../',import.meta.url);
async function pin(name){
 if(sources[name])return;
 const url=new URL(name,root),bytes=await readFile(url);sources[name]=hash(bytes);
 if(!/\.(?:mjs|js)$/.test(name))return;
 const text=bytes.toString();
 for(const pattern of [/\bfrom\s*['"]([^'"]+)['"]/g,/\bimport\s*['"]([^'"]+)['"]/g,/\bimport\(\s*['"]([^'"]+)['"]/g])
  for(const match of text.matchAll(pattern))if(match[1].startsWith('.')){
   const dependency=new URL(match[1],url);assert(dependency.pathname.startsWith(root.pathname),'Source dependency escaped checkout');
   await pin(dependency.pathname.slice(root.pathname.length));
  }
}
for(const name of ['supabase/functions/_shared/domain/momo_pipeline.js','supabase/functions/_shared/domain/core.js',
 'supabase/functions/_shared/domain/encryption.js','supabase/functions/_shared/domain/burimunsi/values.js','supabase/functions/_shared/postgres.js',
 'supabase/migrations/20261110193000_burimunsi_canonical_receipt_adoption.sql',
 'supabase/tests/burimunsi/compile-canonical-adoption-fixture.mjs','supabase/tests/burimunsi/canonical-adoption-contract.sql',
 'supabase/tests/burimunsi/run-canonical-allocation-fixture.mjs'])await pin(name);
process.stdout.write(JSON.stringify({format:'collect.burimunsi.canonical-adoption-sql-fixture.v1',production_acceptance:false,
 scope:'Original validated canonical producer SQL and additive routing trigger on synthetic retained-schema rows; no second parser or poster',
 adoption_inputs:functions.join('\n'),payload,body,body_sha256:hash(body),profile_version:account.profile_version,sources})+'\n');
