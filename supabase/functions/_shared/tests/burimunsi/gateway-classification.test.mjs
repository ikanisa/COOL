import test from 'node:test';
import assert from 'node:assert/strict';
import {classifyGatewayPair,GATEWAY_CLASSIFICATION_SQL,NON_BURIMUNSI_PAIR_CONDITION} from '../../domain/burimunsi/postgres-gateway-classification.js';
const hash='a'.repeat(64),group='qualification-group';
function fixture(classification={kind:'burimunsi',collectionId:group}){
 const state={checks:0,batches:0,statements:[],classification,afterBatch:null,error:null};
 const work={assert:async()=>{state.checks++;if(state.revoked)throw Error('PRIVATE failure detail');}};
 const db={applicationWork:work,prepare:sql=>({bind:(...values)=>({sql,values})}),batch:async statements=>{
  state.batches++;state.statements.push(...statements);if(state.error)throw state.error;
  await state.afterBatch?.();return state.result??[{success:true,results:[{classification:state.classification}]}];
 }};
 const env={DB:db,BURIMUNSI_NATIVE_ENABLED:'true',BURIMUNSI_COLLECTION_ID:group};
 return {state,db,env,run:()=>classifyGatewayPair({env,codeHash:hash})};
}
test('exact Buri target uses the same admitted DB.batch and projects no secret or hash',async()=>{
 const f=fixture();assert.deepEqual(await f.run(),{kind:'burimunsi',collectionId:group});
 assert.deepEqual(f.state.statements,[{sql:GATEWAY_CLASSIFICATION_SQL,values:[hash]}]);assert.equal(f.state.batches,1);assert.equal(f.state.checks,2);
});
test('only authoritative non-Buri classification can select legacy, without native configuration',async()=>{
 const f=fixture({kind:'non_burimunsi'});delete f.env.BURIMUNSI_COLLECTION_ID;delete f.env.BURIMUNSI_NATIVE_ENABLED;
 assert.deepEqual(await f.run(),{kind:'non_burimunsi'});
});
test('blocked scoped-wallet ambiguity never becomes legacy',async()=>{
 const f=fixture({kind:'blocked'});await assert.rejects(f.run(),e=>e.code==='pairing_unavailable'&&e.status===401);
});
for(const config of [{BURIMUNSI_COLLECTION_ID:'wrong-group'},
 {BURIMUNSI_NATIVE_ENABLED:undefined},{BURIMUNSI_NATIVE_ENABLED:'false'},{BURIMUNSI_NATIVE_ENABLED:true}])
 test('Buri target denies missing/wrong/disabled server configuration '+JSON.stringify(config),async()=>{
  const f=fixture();Object.assign(f.env,config);await assert.rejects(f.run(),/native_gateway_unconfigured/);assert.equal(f.state.batches,1);
 });
for(const filter of [undefined,''])test('authoritative Buri target does not require a business group in deployment: '+String(filter),async()=>{
 const f=fixture();f.env.BURIMUNSI_COLLECTION_ID=filter;assert.deepEqual(await f.run(),{kind:'burimunsi',collectionId:group});
});
for(const value of [null,{},[],{kind:'other'},{kind:'burimunsi'},{kind:'burimunsi',collectionId:'wrong group'},
 {kind:'burimunsi',collectionId:group+'\n'},{kind:'burimunsi',collectionId:group,gateway_token:'PRIVATE'},{kind:'non_burimunsi',pairing_code:'PRIVATE'},
 {kind:'blocked',collectionId:group},'{"kind":"non_burimunsi"}'])
 test('unproven or secret-bearing classifier projection is refused '+JSON.stringify(value),async()=>{
  const f=fixture(value);await assert.rejects(f.run(),/gateway_classification_unavailable/);
 });
for(const result of [[],[{success:false,results:[]}],[{success:true,results:[]}],
 [{success:true,results:[{classification:{kind:'non_burimunsi'}},{classification:{kind:'non_burimunsi'}}]}],
 [{success:true,results:[{classification:{kind:'non_burimunsi'},gateway_token:'PRIVATE'}]}]])
 test('malformed batch cannot produce legacy success '+JSON.stringify(result),async()=>{
  const f=fixture();f.state.result=result;await assert.rejects(f.run(),/gateway_classification_unavailable/);
 });
test('missing SQL/helper or DB failure is fixed-code closed failure, without private details',async()=>{
 const f=fixture();f.state.error=Error('PRIVATE connection or token');await assert.rejects(f.run(),e=>e.code==='gateway_classification_unavailable'&&!e.message.includes('PRIVATE'));
});
for(const change of ['work','db','config','feature','revoked'])test('changed admitted context cannot publish '+change,async()=>{
 const f=fixture();f.state.afterBatch=()=>{if(change==='work')f.db.applicationWork={assert:async()=>{}};
  if(change==='db')f.env.DB={};if(change==='config')f.env.BURIMUNSI_COLLECTION_ID='other';
  if(change==='feature')f.env.BURIMUNSI_NATIVE_ENABLED='false';if(change==='revoked')f.state.revoked=true;};
 await assert.rejects(f.run(),e=>e.code==='request_not_admitted'&&!e.message.includes('PRIVATE'));
});
for(const codeHash of [null,'','A'.repeat(64),'a'.repeat(63),'a'.repeat(65),'a'.repeat(63)+'\n','a'.repeat(64)+'\n','a'.repeat(64)+'\r\n'])
 test('strict digest fails before any DB batch '+JSON.stringify(codeHash),async()=>{
  const f=fixture();await assert.rejects(classifyGatewayPair({env:f.env,codeHash}),/invalid_pairing_code/);assert.equal(f.state.batches,0);
 });
test('same-lock legacy condition requires an exact minimal non-Buri result',()=>{
 assert.equal(NON_BURIMUNSI_PAIR_CONDITION,`private.burimunsi_gateway_pair_classify(?) = '{"kind":"non_burimunsi"}'::jsonb`);
});
test('revoked admission fails before any classifier batch',async()=>{
 const f=fixture();f.state.revoked=true;await assert.rejects(f.run(),e=>e.code==='request_not_admitted'&&!e.message.includes('PRIVATE'));
 assert.equal(f.state.batches,0);
});
