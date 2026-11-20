import test from 'node:test';
import assert from 'node:assert/strict';
import {PostgresNativeObservations} from '../../domain/burimunsi/postgres-observations.js';
import {PostgresNativeCanonicalIntake} from '../../domain/burimunsi/postgres-native-canonical-intake.js';
import {nativeExtractionApproval,PostgresNativeUnassignedExtraction} from '../../domain/burimunsi/postgres-native-unassigned-extraction.js';
import {canonicalJson,sha256} from '../../domain/burimunsi/values.js';
import {digest} from '../../domain/core.js';

const uuid=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const actor={id:uuid(1),sessionId:uuid(2),installationId:uuid(3),principalUserId:'synthetic-person',groupId:'synthetic-group'};
const sourceId=uuid(4),enc=new TextEncoder();
const body='You have received RWF 1,500 from +250788111222 at 2026-11-10 08:10:20. Fee: 0 RWF. Balance: 9,000 RWF. TxId: TX-556677.';
const output={schema_version:'momo-extraction.v1',event_kind:'incoming_receipt',payment_outcome:'successful',
 transaction_id_raw:'TX-556677',original_transaction_id_raw:null,transaction_datetime_raw:'2026-11-10 08:10:20',
 principal_amount_raw:'1,500',currency_raw:'RWF',payer_name_raw:null,payer_identifier_raw:'+250788111222',
 payment_reference_raw:null,fee_amount_raw:'0',wallet_balance_after_raw:'9,000',
 evidence:{incoming_success:'You have received RWF 1,500',principal:'RWF 1,500',transaction_id:'TxId: TX-556677',
  transaction_datetime:'at 2026-11-10 08:10:20',payer:'from +250788111222',fee:'Fee: 0 RWF',wallet_balance_after:'Balance: 9,000 RWF'},issues:[]};
const tuple={provider:'synthetic_provider',status:'active',profile_status:'approved',profile_version:'synthetic-v1',
 profile_json:JSON.stringify({sender_allowlist:['SYNTHETIC-MOMO'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],
  transaction_id_prefixes:['TxId:'],date_format:'YMD_HMS',utc_offset_minutes:120}),currency:'RWF',timezone:'Africa/Kigali'};
const fail=code=>Object.assign(new Error('synthetic failure'),{code});

async function fixture(){
 const payload={raw_sender:'SYNTHETIC-MOMO',raw_body:body,source_mode:'catch_up',complete:false,
  captured_at:'2026-11-10T08:10:20Z',service_centre_at:null,inbox_received_at:'2026-11-10T08:10:20Z',
  subscription_id:null,provenance:'native_observation_unverified'};
 const plain=enc.encode(JSON.stringify(payload));
 const record={id:sourceId,sourceId,principalUserId:actor.principalUserId,object_key:`sms/${sourceId}`,
  object_sha256:await digest(plain),bodySha256:await sha256(body),fingerprint:'c'.repeat(64),
  size_bytes:plain.length,consentGeneration:1,sessionId:actor.sessionId};
 const s={record,plain,profile:{profileSha256:await sha256(tuple.profile_json),profile:tuple},journal:{stable:true},
  consent:true,state:'source_unresolved',checkpoint:null,providerCalls:0,stages:0,finished:null,
  onProvider:null,onDispatch:null,lostDispatch:false,providerError:false,output:structuredClone(output)};
 const o=Object.create(PostgresNativeObservations.prototype);o.groupId=actor.groupId;
 o.env={BURIMUNSI_NATIVE_CANONICAL_INTAKE_ENABLED:'true',BURIMUNSI_NATIVE_UNASSIGNED_EXTRACTION_ENABLED:'true',
  MOMO_PROCESSING_PAUSED:'false',MOMO_AI_ENABLED:'true',BUILD_SOURCE_ID:'a'.repeat(64),MOMO_AI_MODEL:'synthetic-model',
  OPENAI_API_KEY:'synthetic',AI:{run:async(_model,request)=>{s.providerCalls++;assert.equal(request.provider_timeout_ms,8000);
   await s.onProvider?.();if(s.providerError)throw fail('synthetic_provider_unknown');return {response:JSON.stringify(s.output)};}}};
 o.env.BURIMUNSI_NATIVE_EXTRACTION_APPROVAL_SHA256=await sha256(canonicalJson({contract:'burimunsi.native-unassigned-extraction.v1',
  sourceSha256:o.env.BUILD_SOURCE_ID,modelId:o.env.MOMO_AI_MODEL}));
 o.current=async()=>{if(!s.consent)throw fail('42501');return {...actor};};o.identity=a=>({...a});
 o.own=async()=>{if(!s.consent)throw fail('42501');return structuredClone(s.record);};
 o.namespace=async()=>({origin:'https://example.invalid',bucket:'synthetic'});
 o.custody={journal:async()=>structuredClone(s.journal),sameJournal:(a,b)=>canonicalJson(a)===canonicalJson(b),
  decrypt:async()=>new Uint8Array(s.plain)};
 o.checkJournal=async(_r,j)=>{if(!j.stable)throw fail('40001');};
 o.storageWitnesses={stage:async()=>({}),prefetch:async()=>{},sealed:async()=>'{"v":1}',forget:()=>{}};
 const tx={unsafe:async(sql,args)=>{
  if(sql.includes('burimunsi_observation_hint_profile'))return [{result:structuredClone(s.profile)}];
  if(sql.includes('burimunsi_native_parse_begin')){
   const started=s.state==='source_unresolved';if(started){s.state='processing';s.checkpoint='preflight';}
   return [{result:{sourceId,started,state:s.state,financialEffects:0}}];
  }
  if(sql.includes('burimunsi_native_parse_dispatch')){
   assert.equal(s.checkpoint,'preflight');s.checkpoint='dispatch';await s.onDispatch?.();
   if(s.lostDispatch)throw fail('08006');return [{result:true}];
  }
  if(sql.includes('burimunsi_native_parse_finish')){
   assert.equal(s.checkpoint,'dispatch');s.state='needs_review';s.finished={output:args[5]===null?null:JSON.parse(args[5]),
    validation:JSON.parse(args[6]),unknown:args[7]};return [{result:{sourceId,state:'needs_review',financialEffects:0}}];
  }
  throw new Error('unexpected synthetic SQL');
 }};
 o.authority={assertOwned:async()=>{},write:async fn=>fn(tx)};
 const intake=Object.create(PostgresNativeCanonicalIntake.prototype);intake.observations=o;intake.stage=async()=>{s.stages++;};
 return {s,o,adapter:new PostgresNativeUnassignedExtraction({observations:o,intake})};
}

test('requires an explicit build/model approval and stays disabled without it',async()=>{
 const f=await fixture();delete f.o.env.BURIMUNSI_NATIVE_EXTRACTION_APPROVAL_SHA256;
 assert.equal(await nativeExtractionApproval(f.o.env),false);
 assert.deepEqual(await f.adapter.process(actor,sourceId),{state:'disabled',financialEffects:0});
 assert.equal(f.s.stages,0);assert.equal(f.s.providerCalls,0);
});

test('valid extracted data is retained only for review and an exact retry cannot dispatch again',async()=>{
 const f=await fixture();assert.deepEqual(await f.adapter.process(actor,sourceId),{sourceId,state:'needs_review',financialEffects:0});
 assert.equal(f.s.finished.output.principal_amount_raw,'1,500');assert.equal(f.s.finished.unknown,false);
 assert.ok(f.s.finished.validation.some(v=>v.code==='incomplete_source'));
 assert.ok(f.s.finished.validation.some(v=>v.code==='receiving_account_unverified'));
 assert.deepEqual(await f.adapter.process(actor,sourceId),{state:'needs_review',financialEffects:0});
 assert.equal(f.s.providerCalls,1);
});

test('provider timeout is persisted as uncertain and is not replayed',async()=>{
 const f=await fixture();f.s.providerError=true;await f.adapter.process(actor,sourceId);
 assert.equal(f.s.finished.unknown,true);assert.equal(f.s.finished.output,null);
 await f.adapter.process(actor,sourceId);assert.equal(f.s.providerCalls,1);
});

test('a lost dispatch commit acknowledgement never starts a provider request',async()=>{
 const f=await fixture();f.s.lostDispatch=true;
 await assert.rejects(f.adapter.process(actor,sourceId),e=>e.status===503);
 assert.equal(f.s.checkpoint,'dispatch');assert.equal(f.s.providerCalls,0);
 await f.adapter.process(actor,sourceId);assert.equal(f.s.providerCalls,0);
});

test('revoked consent after provider dispatch cannot finish or disclose the result',async()=>{
 const f=await fixture();f.s.onProvider=()=>{f.s.consent=false;};
 await assert.rejects(f.adapter.process(actor,sourceId),e=>e.status===403);
 assert.equal(f.s.checkpoint,'dispatch');assert.equal(f.s.finished,null);assert.equal(f.s.providerCalls,1);
});

test('profile changes or storage drift before dispatch stop external processing',async()=>{
 for(const change of ['profile','journal']){
  const f=await fixture();f.s.onDispatch=()=>{};
  const original=f.o.storageWitnesses.prefetch;f.o.storageWitnesses.prefetch=async(...args)=>{
   await original(...args);if(change==='profile')f.s.profile.profile.profile_version='changed';else f.s.journal.stable=false;
  };
  await assert.rejects(f.adapter.process(actor,sourceId),e=>[409,503].includes(e.status),change);
  assert.equal(f.s.providerCalls,0);
 }
});

test('unsupported model facts are never retained as extracted facts',async()=>{
 const f=await fixture();f.s.output.principal_amount_raw='999999';
 await f.adapter.process(actor,sourceId);assert.equal(f.s.finished.output,null);
 assert.ok(f.s.finished.validation.some(v=>v.code==='unsupported_fact'));
});
