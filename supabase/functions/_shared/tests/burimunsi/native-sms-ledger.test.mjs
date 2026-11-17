import test from 'node:test';
import assert from 'node:assert/strict';
import {PostgresNativeSmsLedger,drainNativeSmsLedger} from '../../domain/burimunsi/postgres-native-sms-ledger.js';
import {MOMO_SCHEMA_VERSION} from '../../domain/momo_pipeline.js';
import {digest} from '../../domain/core.js';
import {sha256} from '../../domain/burimunsi/values.js';
import {BuriError} from '../../domain/burimunsi/errors.js';
import {NATIVE_AUTO_SCHEMA_VERSION,prepareNativeAutoExtraction,validateNativeAutoExtraction} from '../../domain/burimunsi/native-auto-parser.js';
import {storageEntity} from '../../storage-identity.js';

const group='11111111-1111-4111-8111-111111111111',sourceId='22222222-2222-4222-8222-222222222222';
const body='You have received 1,250 RWF from Example Person *********456. Balance 9,000 RWF.';
const output={schema_version:MOMO_SCHEMA_VERSION,event_kind:'incoming_receipt',payment_outcome:'successful',
 transaction_id_raw:null,original_transaction_id_raw:null,transaction_datetime_raw:null,principal_amount_raw:'1,250',currency_raw:'RWF',
 payer_name_raw:'Example Person',payer_identifier_raw:'*********456',payment_reference_raw:null,fee_amount_raw:null,wallet_balance_after_raw:'9,000 RWF',
 evidence:{incoming_success:'You have received',principal:'You have received 1,250 RWF',transaction_id:null,
  transaction_datetime:null,payer:'from Example Person *********456',fee:null,wallet_balance_after:'Balance 9,000 RWF'},issues:[]};
const profile={provider:'mtn_momo',status:'active',profile_status:'approved',profile_version:'test',currency:'RWF',timezone:'Africa/Kigali',
 profile_json:JSON.stringify({sender_allowlist:['Example Money'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],
  transaction_id_prefixes:['Reference:'],date_format:'YMD_HMS',utc_offset_minutes:120})};
const member={id:'member-1',full_name:'Example Person',momo_number:'0788123456',member_type:'direct',access_status:'active',collection_id:group,active:1};

async function fixture({members=[member],failOnStatement=0,wrongGroup=false,sourceBody=body,extractionOutput=output,canonicalAmount=1250,canonicalId=null,failBackoff=false}={}){
 const source={provenance:'native_observation_unverified',source_mode:'catch_up',complete:false,raw_sender:'Example Money',raw_body:sourceBody};
 const bytes=new TextEncoder().encode(JSON.stringify(source)),bodySha=await sha256(sourceBody),objectSha=await digest(bytes);
 const proof={id:sourceId,sourceId,principalUserId:'owner-1',object_key:'sms/'+sourceId,object_sha256:objectSha,
  bodySha256:bodySha,size_bytes:bytes.length,fingerprint:'a'.repeat(64)};
 const row={collection_id:wrongGroup?'other-group':group,source_id:sourceId,source_fingerprint:proof.fingerprint,
  principal_user_id:'owner-1',capture_session_id:'33333333-3333-4333-8333-333333333333',body_sha256:bodySha,
  object_sha256:objectSha,object_key:proof.object_key,size_bytes:bytes.length,transaction_id:sourceId,
  receiving_account_id:'account-1',provider:'mtn_momo',provider_transaction_id:canonicalId,event_kind:'incoming_receipt',
  amount_minor:canonicalAmount,currency:'RWF',payer_name:'Example Person',payer_identifier:'*********456',wallet_balance_after_minor:null,
  mode:'historical',allocation_state:'not_applicable',has_conflict:0,version:1,transaction_at:null,created_at:'2026-01-01T00:00:00.000Z',
  output_json:JSON.stringify(extractionOutput),posting_facts:null,posting_output:null,public_code:'12345',receiver_display_label:'Example',has_link:false,link_posted:false};
 let backoffCalls=0,state={row,members,writes:[],stored:[],deferred:0,statements:0,failureDeferred:0,failureCount:0,nextAttemptAt:0,lastError:null};
 const tx={async unsafe(query,values){
  if(query.includes('native_sms_post_snapshot'))return [{result:structuredClone(state.row)}];
  if(query.includes('native_sms_post_facts')){state.row.posting_output=structuredClone(values[2]);state.row.posting_facts=structuredClone(values[3]);return [{result:true}];}
  if(query.includes('native_sms_post_defer')){state.deferred++;state.deferDelay=values[1];state.failureCount=0;state.lastError=null;return [{result:true}];}
  if(query.includes('native_sms_post_retry')){
   backoffCalls++;if(failBackoff)throw Error('synthetic metadata failure');
   if(wrongGroup||state.row.has_link)return [{result:{deferred:false,state:'not_eligible'}}];
   state.failureDeferred++;state.nextAttemptAt=Date.now()+Math.min(900000,60000*2**Math.min(state.failureCount,4));
   state.failureCount=Math.min(16,state.failureCount+1);state.lastError=values[1];
   return [{result:{deferred:true,failureCount:state.failureCount,nextAttemptAt:state.nextAttemptAt}}];
  }
  if(query.includes('FROM app.memberships'))return structuredClone(state.members);
  if(query.includes('INSERT INTO app.payment_evidence')){state.writes.push('evidence');return [{id:values[0]}];}
  if(query.includes('INSERT INTO app.payments')){state.writes.push('payment');return [{id:values[0]}];}
  if(query.includes('INSERT INTO app.momo_financial_links')){state.writes.push('link');state.row.has_link=true;return [{transaction_id:values[0]}];}
  if(query.includes('UPDATE app.momo_transactions')){state.row.allocation_state='linked';state.row.version++;return [{id:values[1]}];}
  if(query.includes('FROM app.payments p JOIN app.ledger_entries')){state.row.link_posted=true;return [{member_id:'member-1',status:'reconciled',currency:'RWF',
   ledger_currency:'RWF',evidence_id:state.evidenceId,amount_minor:state.row.amount_minor,ledger_amount:state.row.amount_minor}];}
  throw Error('unexpected synthetic SQL');
 }};
 const authority={async write(fn){const before=structuredClone(state);try{return await fn(tx);}catch(e){state=before;throw e;}}};
 const plan={snapshot:{actor:{collectionId:group},proof,profile:{profileSha256:'b'.repeat(64),profile}},journal:{}};
 const worker={authority,async plan(){return plan;},async verify(){},witnesses:{async stage(){return {};},async prefetch(){},
  async sealed(){return 'sealed';},forget(){}},custody:{async decrypt(){return new Uint8Array(bytes);}}};
 const ledger=Object.create(PostgresNativeSmsLedger.prototype);ledger.groupId=group;ledger.worker=worker;ledger.authority=authority;
 ledger.env={DATA_KEY_ID:'fixture',DATA_ENCRYPTION_KEY:Buffer.alloc(32,7).toString('base64'),
  PRIVATE_MEDIA:{async put(key,_cipher,options){state.stored.push({key,scope:options.scope});state.evidenceId=options.scope.entityId;
   return {stored:true,metadataCommitted:true,key};}}};
 ledger.db={prepare(text){return {bind(...values){return {text,values};}};},async statement(_tx,statement){
  state.statements++;if(failOnStatement&&state.statements===failOnStatement)throw Error('synthetic failure');state.writes.push(statement.text);
 }};
 return {ledger,get state(){return state;},get backoffCalls(){return backoffCalls;}};
}

test('retained source facts are recovered without AI while an unmatched receipt stays recorded',async()=>{
 const f=await fixture({members:[]});assert.deepEqual(await f.ledger.process(sourceId),{state:'unmatched'});
 assert.equal(f.state.row.posting_facts.wallet_balance_after_minor,9000);
 assert.equal(f.state.row.posting_facts.counterparty_identifier,'*********456');
 assert.equal(f.state.deferred,1);assert.equal(f.state.writes.length,0);assert.equal(f.state.stored.length,0);
});
test('matched native catch-up uses the existing payment/link/contribution path once',async()=>{
 const f=await fixture();assert.deepEqual(await f.ledger.process(sourceId),{state:'posted'});
 assert.equal(f.state.row.mode,'historical');assert.deepEqual(f.state.writes.slice(0,3),['evidence','payment','link']);
 assert.equal(f.state.writes.filter(x=>x.includes('INSERT INTO ledger_entries')).length,1);
 assert.equal(f.state.writes.filter(x=>x.includes('INSERT INTO contribution_posting_snapshots')).length,1);
 assert.equal(f.state.stored.length,1);
 const count=f.state.writes.length;assert.deepEqual(await f.ledger.process(sourceId),{state:'already_posted'});assert.equal(f.state.writes.length,count);
});
test('a matched source-grounded receipt with a canonical provider ID may post once without a balance',async()=>{
 const noBalanceBody='You have received 1,250 RWF from Example Person *********456. FT Id: TX-123.';
 const result={...output,schema_version:NATIVE_AUTO_SCHEMA_VERSION,wallet_effect:'credit',transaction_id_raw:'TX-123',wallet_balance_after_raw:null,
  evidence:{...output.evidence,incoming_success:'You have received 1,250 RWF from Example Person *********456',
   principal:'You have received 1,250 RWF from Example Person *********456',transaction_id:'FT Id: TX-123',wallet_balance_after:null}};
 const f=await fixture({sourceBody:noBalanceBody,extractionOutput:result,canonicalId:'TX-123'});
 assert.equal((await f.ledger.process(sourceId)).state,'posted');
 assert.equal(f.state.row.posting_facts.wallet_balance_after_minor,null);assert.equal(f.state.row.posting_facts.provider_transaction_id,'TX-123');
 assert.deepEqual(f.state.writes.slice(0,3),['evidence','payment','link']);
 const count=f.state.writes.length;assert.deepEqual(await f.ledger.process(sourceId),{state:'already_posted'});assert.equal(f.state.writes.length,count);
});
test('an absent, mismatched or unsupported provider ID without a balance never credits a member',async()=>{
 const principal='You have received 1,250 RWF from Example Person *********456';
 const cases=[
  {sourceBody:principal+'.',raw:null,canonicalId:null,quote:null},
  {sourceBody:principal+'. FT Id: TX-123.',raw:'TX-123',canonicalId:'TX-999',quote:'FT Id: TX-123'},
  {sourceBody:principal+'. FT Id: TX-123.',raw:'FAKE-888',canonicalId:'FAKE-888',quote:'FT Id: TX-123'},
  {sourceBody:principal+'. Payer phone 0780000123.',raw:'0780000123',canonicalId:'0780000123',quote:'Payer phone 0780000123'},
  {sourceBody:principal+'. Numéro ABC-77.',raw:'ABC-77',canonicalId:'ABC-77',quote:'Numéro ABC-77'},
  {sourceBody:principal+'. Agent ID AGT-42.',raw:'AGT-42',canonicalId:'AGT-42',quote:'Agent ID AGT-42'},
 ];
 for(const c of cases){
  const value={...output,schema_version:NATIVE_AUTO_SCHEMA_VERSION,wallet_effect:'credit',transaction_id_raw:c.raw,wallet_balance_after_raw:null,
   evidence:{...output.evidence,incoming_success:principal,principal,transaction_id:c.quote,wallet_balance_after:null}};
  const f=await fixture({sourceBody:c.sourceBody,extractionOutput:value,canonicalId:c.canonicalId});
  f.ledger.env.MOMO_AI_ENABLED='true';f.ledger.env.AI={run:async()=>({response:JSON.stringify(value)})};
  assert.equal((await f.ledger.process(sourceId)).state,'unmatched');assert.deepEqual(f.state.writes,[]);assert.equal(f.state.stored.length,0);
 }
});
test('repeated deterministic incomplete extraction is deferred for a day without any financial writes',async()=>{
 const principal='You have received 1,250 RWF from Example Person *********456';
 const value={...output,schema_version:NATIVE_AUTO_SCHEMA_VERSION,wallet_effect:'credit',transaction_id_raw:null,wallet_balance_after_raw:null,
  evidence:{...output.evidence,incoming_success:principal,principal,transaction_id:null,wallet_balance_after:null}};
 const f=await fixture({sourceBody:principal+'.',extractionOutput:value});
 let calls=0;f.ledger.env.MOMO_AI_ENABLED='true';f.ledger.env.AI={run:async()=>{calls++;return {response:JSON.stringify(value)};}};
 assert.equal((await f.ledger.process(sourceId)).state,'unmatched');assert.equal(calls,1);
 assert.equal(f.state.deferred,1);assert.equal(f.state.deferDelay,86400000);assert.equal(f.state.failureDeferred,0);
 assert.deepEqual(f.state.writes,[]);assert.equal(f.state.stored.length,0);
});
test('a completed but malformed AI response is deferred for a day without financial writes',async()=>{
 const principal='You have received 1,250 RWF from Example Person *********456';
 const value={...output,schema_version:NATIVE_AUTO_SCHEMA_VERSION,wallet_effect:'credit',transaction_id_raw:null,wallet_balance_after_raw:null,
  evidence:{...output.evidence,incoming_success:principal,principal,transaction_id:null,wallet_balance_after:null}};
 const f=await fixture({sourceBody:principal+'.',extractionOutput:value});
 f.ledger.env.MOMO_AI_ENABLED='true';f.ledger.env.AI={run:async()=>({response:'{malformed synthetic json'})};
 assert.equal((await f.ledger.process(sourceId)).state,'unmatched');assert.equal(f.state.deferred,1);
 assert.equal(f.state.deferDelay,86400000);assert.deepEqual(f.state.writes,[]);assert.equal(f.state.stored.length,0);
});
test('temporary AI provider failures retain normal retry backoff and never write financial rows',async()=>{
 const principal='You have received 1,250 RWF from Example Person *********456';
 const value={...output,schema_version:NATIVE_AUTO_SCHEMA_VERSION,wallet_effect:'credit',transaction_id_raw:null,wallet_balance_after_raw:null,
  evidence:{...output.evidence,incoming_success:principal,principal,transaction_id:null,wallet_balance_after:null}};
 const f=await fixture({sourceBody:principal+'.',extractionOutput:value});
 f.ledger.env.MOMO_AI_ENABLED='true';f.ledger.env.AI={run:async()=>{throw Error('synthetic provider unavailable');}};
 await assert.rejects(f.ledger.process(sourceId));assert.equal(f.state.deferred,0);assert.equal(f.state.failureDeferred,1);
 assert.equal(f.state.lastError,'source_unavailable');assert.deepEqual(f.state.writes,[]);assert.equal(f.state.stored.length,0);
});
test('canonical provider ID changes during a no-balance posting never reach financial writes',async()=>{
 const sourceBody='You have received 1,250 RWF from Example Person *********456. FT Id: TX-123.';
 const value={...output,schema_version:NATIVE_AUTO_SCHEMA_VERSION,wallet_effect:'credit',transaction_id_raw:'TX-123',wallet_balance_after_raw:null,
  evidence:{...output.evidence,incoming_success:'You have received 1,250 RWF from Example Person *********456',
   principal:'You have received 1,250 RWF from Example Person *********456',transaction_id:'FT Id: TX-123',wallet_balance_after:null}};
 const f=await fixture({sourceBody,extractionOutput:value,canonicalId:'TX-123'});let checks=0;
 f.ledger.worker.verify=async()=>{if(++checks===2)f.state.row.provider_transaction_id='TX-999';};
 await assert.rejects(f.ledger.process(sourceId));assert.deepEqual(f.state.writes,[]);assert.equal(f.state.row.has_link,false);
});
test('a coherently mapped replay with an existing complete financial link performs no second write',async()=>{
 const f=await fixture();assert.deepEqual(await f.ledger.process(sourceId),{state:'posted'});
 const beforeWrites=f.state.writes.length,beforeStored=f.state.stored.length,originalEvidence=f.state.evidenceId;
 const cloudOwner='cloud-owner-1',differentEvidence=await storageEntity('burimunsi.native.sms.evidence',cloudOwner,sourceId);
 assert.notEqual(differentEvidence,originalEvidence);
 const plan=await f.ledger.worker.plan();plan.snapshot.proof.principalUserId=cloudOwner;f.state.row.principal_user_id=cloudOwner;
 f.ledger.worker.witnesses.prefetch=async()=>{throw Error('unexpected object read');};
 f.ledger.env.PRIVATE_MEDIA.put=async()=>{throw Error('unexpected object write');};
 assert.deepEqual(await f.ledger.process(sourceId),{state:'already_posted'});
 assert.equal(f.state.writes.length,beforeWrites);assert.equal(f.state.stored.length,beforeStored);
 f.state.row.link_posted=false;
 await assert.rejects(f.ledger.process(sourceId));
 assert.equal(f.state.writes.length,beforeWrites);assert.equal(f.state.stored.length,beforeStored);
});
test('ambiguous or cross-collection candidates do not credit a member',async()=>{
 const a=await fixture({members:[member,{...member,id:'member-2'}]});assert.equal((await a.ledger.process(sourceId)).state,'unmatched');
 assert.equal(a.state.writes.length,0);
 const b=await fixture({wrongGroup:true});await assert.rejects(b.ledger.process(sourceId));assert.equal(b.state.writes.length,0);
});
test('a failure inside the financial transaction rolls back all payment, link and ledger writes',async()=>{
 const f=await fixture({failOnStatement:3});await assert.rejects(f.ledger.process(sourceId));
 assert.deepEqual(f.state.writes,[]);assert.equal(f.state.row.has_link,false);assert.equal(f.state.row.allocation_state,'not_applicable');
 assert.equal(f.state.failureDeferred,1);assert.equal(f.state.lastError,'posting_failed');assert.ok(f.state.nextAttemptAt>Date.now());
});
test('a revoked source persists scoped backoff without retrying its money transaction',async()=>{
 const f=await fixture(),original=f.ledger.worker.plan;
 f.ledger.worker.plan=async()=>{throw new BuriError('access_denied',403)};
 await assert.rejects(f.ledger.process(sourceId),/access_denied/);
 assert.equal(f.state.lastError,'access_denied');assert.equal(f.state.failureCount,1);assert.equal(f.state.writes.length,0);
 f.ledger.worker.plan=original;f.state.members=[];
 assert.equal((await f.ledger.process(sourceId)).state,'unmatched');
 assert.equal(f.state.failureCount,0);assert.equal(f.state.lastError,null);
});
test('loss of the admission never attempts a separate retry write',async()=>{
 const f=await fixture();f.ledger.worker.plan=async()=>{throw new BuriError('request_not_admitted',503)};
 await assert.rejects(f.ledger.process(sourceId),/request_not_admitted/);assert.equal(f.backoffCalls,0);assert.equal(f.state.writes.length,0);
});
test('an uncertain retry metadata result is not automatically replayed',async()=>{
 const f=await fixture({failOnStatement:3,failBackoff:true});
 await assert.rejects(f.ledger.process(sourceId),/native_sms_posting_retry_unavailable/);
 assert.equal(f.backoffCalls,1);assert.equal(f.state.row.has_link,false);assert.deepEqual(f.state.writes,[]);
});
test('misclassified incoming status and balance-only principal cannot reach the financial writer',async()=>{
 for(const tail of ['This transfer failed.','This transfer is pending.','This transfer has been reversed.','balance-only']){
  let sourceBody=body+' '+tail,value=structuredClone(output);
  if(tail==='balance-only'){
   sourceBody='You have received a transfer from Example Person *********456. Balance 9,000 RWF.';
   value.principal_amount_raw='9,000';value.evidence.principal=sourceBody;
  }
  const source={raw_sender:'Example Money',raw_body:sourceBody,source_mode:'catch_up'};
  assert.equal(prepareNativeAutoExtraction(source,profile).kind,'provider');
  const parsed=validateNativeAutoExtraction(source,profile,value);
  const f=await fixture({sourceBody,extractionOutput:value,canonicalAmount:parsed.facts.amount_minor});
  f.state.row.event_kind=parsed.facts.event_kind;f.state.row.currency=parsed.facts.currency;
  f.ledger.env.MOMO_AI_ENABLED='true';f.ledger.env.AI={run:async()=>({response:JSON.stringify(value)})};
  assert.equal((await f.ledger.process(sourceId)).state,'unmatched',tail);
  assert.equal(f.state.writes.length,0,tail);assert.equal(f.state.stored.length,0,tail);assert.equal(f.state.deferred,1,tail);assert.equal(f.state.deferDelay,86400000,tail);
 }
 const valid=await fixture({sourceBody:body+' A different, earlier transfer failed.'});
 assert.equal((await valid.ledger.process(sourceId)).state,'posted');
});
test('a link without a matching posted contribution is not reported as posted',async()=>{
 const f=await fixture();f.state.row.has_link=true;f.state.row.link_posted=false;
 await assert.rejects(f.ledger.process(sourceId));assert.equal(f.state.writes.length,0);
});
test('an older unknown transaction is enriched but not credited using missing canonical facts',async()=>{
 const f=await fixture();f.state.row.event_kind='unknown';f.state.row.amount_minor=null;f.state.row.currency=null;
 assert.deepEqual(await f.ledger.process(sourceId),{state:'unmatched'});
 assert.equal(f.state.row.posting_facts.event_kind,'incoming_receipt');assert.equal(f.state.row.posting_facts.amount_minor,1250);
 assert.equal(f.state.writes.length,0);
});
test('scheduler remains bounded and uses the existing enable switch',async()=>{
 assert.deepEqual(await drainNativeSmsLedger({}),{status:'disabled',processed:0,results:[]});
 await assert.rejects(drainNativeSmsLedger({BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true'},{limit:2}));
});
