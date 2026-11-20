/** Synthetic transaction adapter; encryption is the actual Collect AES-GCM code. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {PostgresSmartOnboardingJournal} from '../../domain/burimunsi/smart-onboarding-journal.js';

const groupId='group-1',actorId='11111111-1111-4111-8111-111111111111',sessionId='22222222-2222-4222-8222-222222222222';
const requestId='33333333-3333-4333-8333-333333333333',reservationId='44444444-4444-4444-8444-444444444444';
const sourceSha256='a'.repeat(64),policySha256='b'.repeat(64),decoderBuildSha256='c'.repeat(64);
const preview={sourceKind:'image',rows:[{row:1,momoName:'Synthetic Alice',momoNumber:'+250780000001',status:'ready',issue:null,selected:true}]};
const input={groupId,actorId,sessionId,proposedRequestId:requestId,proposedReservationId:reservationId,
 sourceSha256,mimeType:'image/png',policySha256,decoderBuildSha256};
function fixture(){
 const state={rows:[],audit:[],allowed:true,inTx:false};
 const actor={id:actorId,sessionId,groupId,principalUserId:'principal-1',role:'staff',active:true,revoked:false,
  capabilities:['members.enroll'],expiresAt:9999999999999};
 const sql={unsafe:async(query,v)=>{
  assert.equal(state.inTx,true);
  if(query.startsWith('INSERT INTO private.burimunsi_command_receipts')){
   const [collection_id,actor_id,request_id,session_id,operation,fingerprint,raw,created_at]=v;
   if(state.rows.some(x=>x.collection_id===collection_id&&x.actor_id===actor_id&&
     (x.request_id===request_id||x.operation===operation&&x.fingerprint===fingerprint)))return [];
   state.rows.push({collection_id,actor_id,request_id,session_id,operation,fingerprint,response:structuredClone(raw),created_at});
   return [{request_id}];
  }
  if(query.includes('WHERE collection_id=$1 AND actor_id=$2::uuid AND operation=$3 AND fingerprint=$4'))
   return structuredClone(state.rows.filter(x=>x.collection_id===v[0]&&x.actor_id===v[1]&&x.operation===v[2]&&x.fingerprint===v[3]));
  if(query.includes('WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid')&&query.trimStart().startsWith('SELECT'))
   return structuredClone(state.rows.filter(x=>x.collection_id===v[0]&&x.actor_id===v[1]&&x.request_id===v[2]&&x.operation===v[3]));
  if(query.startsWith('UPDATE private.burimunsi_command_receipts')){
   const row=state.rows.find(x=>x.collection_id===v[0]&&x.actor_id===v[1]&&x.request_id===v[2]&&x.operation===v[3]&&x.response.state===v[5]);
   if(!row)return [];row.response=structuredClone(v[4]);return [structuredClone(row)];
  }
  throw new Error('unexpected synthetic query');
 }};
 const authority={groupId,db:{},async write(fn){assert.equal(state.inTx,false);const saved=structuredClone(state.rows),audit=structuredClone(state.audit);state.inTx=true;
  try{return await fn(sql);}catch(error){state.rows=saved;state.audit=audit;throw error;}finally{state.inTx=false;}},
  async session(_sql,{id}){assert.equal(state.inTx,true);return state.allowed&&id===sessionId?actor:null;},
  async audit(_sql,id,action,entity,request){state.audit.push({id,action,entity,request});}};
 const env={DATA_KEY_ID:'synthetic-key',DATA_ENCRYPTION_KEY:btoa(String.fromCharCode(...new Uint8Array(32).fill(7)))};
 return {state,journal:new PostgresSmartOnboardingJournal({authority,env,clock:()=>1000000})};
}

test('journal encrypts previews, recovers original rows and never stores source bytes or plaintext',async()=>{
 const f=fixture(),receipt=await f.journal.reserve(input);
 assert.equal(receipt.state,'reserved');await f.journal.advance({receipt,sessionId,phase:'decode'});
 await f.journal.advance({receipt,sessionId,phase:'extract'});
 const done=await f.journal.complete({receipt,sessionId,phase:'extract',preview});assert.equal(done.state,'completed');
 const stored=JSON.stringify(f.state.rows);assert.equal(stored.includes('Synthetic Alice'),false);
 assert.equal(stored.includes('+250780000001'),false);assert.equal(stored.includes('fileBytes'),false);
 const recovered=await f.journal.reserve({...input,proposedRequestId:'55555555-5555-4555-8555-555555555555',
  proposedReservationId:'66666666-6666-4666-8666-666666666666'});
 assert.deepEqual(recovered.preview,preview);assert.equal(recovered.requestId,requestId);assert.equal(f.state.rows.length,1);
 assert.deepEqual(f.state.audit.map(x=>x.action),['burimunsi.smart_import.reserved','burimunsi.smart_import.completed']);
});

test('a repeated unfinished upload remains pending and cannot advance twice',async()=>{
 const f=fixture(),receipt=await f.journal.reserve(input);await f.journal.advance({receipt,sessionId,phase:'decode'});
 const repeated=await f.journal.reserve({...input,proposedRequestId:'55555555-5555-4555-8555-555555555555'});
 assert.equal(repeated.state,'pending');assert.equal(f.state.rows.length,1);
 await assert.rejects(f.journal.advance({receipt,sessionId,phase:'decode'}),/smart_import_pending/);
 assert.equal(f.state.rows[0].response.state,'decode');
});

test('a revoked actor cannot reserve, advance or publish',async()=>{
 const f=fixture(),receipt=await f.journal.reserve(input);f.state.allowed=false;
 await assert.rejects(f.journal.advance({receipt,sessionId,phase:'decode'}),/session_unavailable/);
 await assert.rejects(f.journal.reserve(input),/session_unavailable/);
 assert.equal(f.state.rows[0].response.state,'reserved');assert.equal(f.state.audit.length,1);
});

test('a source, actor, policy or group mismatch cannot use a prior receipt',async()=>{
 const f=fixture(),receipt=await f.journal.reserve(input);
 for(const changed of [{sourceSha256:'d'.repeat(64)},{policySha256:'d'.repeat(64)},
  {actorId:'55555555-5555-4555-8555-555555555555'},{groupId:'other'}]){
  await assert.rejects(f.journal.advance({receipt:{...receipt,...changed},sessionId,phase:'decode'}));
 }
 assert.equal(f.state.rows[0].response.state,'reserved');
});

test('tampering with the encrypted preview or its policy binding cannot recover it',async()=>{
 const f=fixture(),receipt=await f.journal.reserve(input);await f.journal.advance({receipt,sessionId,phase:'decode'});
 await f.journal.advance({receipt,sessionId,phase:'extract'});await f.journal.complete({receipt,sessionId,phase:'extract',preview});
 const sealed=JSON.parse(f.state.rows[0].response.ciphertext);
 sealed.data=(sealed.data[0]==='A'?'B':'A')+sealed.data.slice(1);f.state.rows[0].response.ciphertext=JSON.stringify(sealed);
 await assert.rejects(f.journal.reserve(input));
});

test('corrupt preview shape cannot be written as an acknowledged outcome',async()=>{
 const f=fixture(),receipt=await f.journal.reserve(input);await f.journal.advance({receipt,sessionId,phase:'decode'});
 await f.journal.advance({receipt,sessionId,phase:'extract'});
 await assert.rejects(f.journal.complete({receipt,sessionId,phase:'extract',preview:{...preview,privateData:'no'}}),/smart_import_recovery_invalid/);
 assert.equal(f.state.rows[0].response.state,'extract');
});
