import test from 'node:test';import assert from 'node:assert/strict';import {pathToFileURL} from 'node:url';
import {createPhonePinRequestGate,PIN_CONTEXT_SQL,PIN_SET_CONTEXT_SQL,PIN_RENEW_SQL} from '../../domain/burimunsi/phone-pin-request.js';
import {CONTRACT_VERSION} from '../../domain/burimunsi/wire/native-contract.mjs';
const path=process.env.BURI_AUTH_SOURCE;
const {PostgresNativeAuthStore}=await import(path?pathToFileURL(path).href:'../../domain/burimunsi/postgres-auth-store.js');
const id='11111111-1111-4111-8111-111111111111',sid='22222222-2222-4222-8222-222222222222',rid='33333333-3333-4333-8333-333333333333';
function fixture(){
 const calls=[];const actor={id,session_id:sid,expires_at:9999999999999,installation_id:'44444444-4444-4444-8444-444444444444',principal_user_id:'principal-1',collection_id:'g',role:'admin',capabilities:['records.read','staff.manage'],installation_profile:'internal_receiver'};
 const sql={unsafe:async(q,v=[])=>{calls.push({q,v});
  if(q===PIN_CONTEXT_SQL||q===PIN_RENEW_SQL)return [{collection_id:'g',account_id:id,principal_user_id:'principal-1',native_session_id:sid,
   grant_id:rid,installation_id:actor.installation_id,profile:'internal_receiver',role:'admin',capabilities:['records.read'],created_at:1,expires_at:9999999999999}];
  if(q===PIN_SET_CONTEXT_SQL)return [{result:{collection_id:'g'}}];
  if(q.startsWith('SELECT private.burimunsi_pin_rotate_passcode'))return [{result:{rotated:true,expiresAt:1801000}}];
  if(q.startsWith('SELECT s.id'))return [actor];if(q.startsWith('SELECT * FROM private.burimunsi_accounts'))return [{id,role:'staff',removed:false,version:1,name:'Example',phone:'+250780000001',capabilities:['records.read'],pin_hash:{algorithm:'test'},active:true}];return []}};
 const db={applicationWork:{assert:async()=>{}},transaction:fn=>fn(sql),context:async()=>{},readContext:async()=>{},setClaims:()=>{}};
 return {calls,sql,db,actor,store:new PostgresNativeAuthStore({db,groupId:'g',createOperatorPrincipal:async()=>({id:'existing-principal'}),clock:()=>1000})};
}
const hash={algorithm:'pbkdf2-sha256',iterations:600000,salt:'synthetic',hash:'synthetic',pepperId:'test-key'};
async function changeWithBoundProof(f){
 const gate=createPhonePinRequestGate({secrets:{},networkBucket:async()=>'',clock:()=>1000});
 const request=new Request('https://supabase.example.test/v1/burimunsi/session/passcode',{method:'POST',headers:{
  'X-BuriMunsi-Auth':'phone_pin','X-BuriMunsi-Profile':'internal_receiver','X-BuriMunsi-Installation':f.actor.installation_id,
  'X-BuriMunsi-Device':'d'.repeat(64),'X-BuriMunsi-Group':'g',Authorization:'Bearer '+'e'.repeat(64),
  'X-BuriMunsi-Contract':CONTRACT_VERSION,'X-BuriMunsi-Request':rid,'X-BuriMunsi-Generation':'1'}});
 return gate({request,env:{DB:f.db}},()=>f.store.changePinIfCurrent({groupId:'g',sessionId:sid,actorId:id,accountId:id,
  expectedCredentialVersion:1,expectedAccountVersion:1,pinHash:hash,replacementTokenHash:'f'.repeat(64),temporaryToken:'c'.repeat(64),sessionTtlMs:1800000}));
}
test('passcode change supplies a JSONB object, not pre-stringified JSON',async()=>{
 const f=fixture();await changeWithBoundProof(f);
 const q=f.calls.find(c=>c.q.startsWith('SELECT private.burimunsi_pin_rotate_passcode'));assert.deepEqual(q.v[4],hash);
});
for(const [sqlstate,code,status] of [['42501','session_unavailable',401],['23505','invalid_session_candidate',400]])
 test('passcode transaction maps definitive database rejection '+sqlstate,async()=>{
  const f=fixture(),unsafe=f.sql.unsafe;f.sql.unsafe=async(q,v)=>{
   if(q.startsWith('SELECT private.burimunsi_pin_rotate_passcode'))throw Object.assign(Error('Synthetic rollback'),{code:sqlstate});return unsafe(q,v);
  };
  await assert.rejects(changeWithBoundProof(f),e=>e.code===code&&e.status===status);
  assert.equal(f.calls.some(c=>c.q.startsWith('INSERT INTO private.burimunsi_audit')),false);
 });
test('passcode transaction leaves an unknown commit outcome unknown',async()=>{
 const f=fixture(),unsafe=f.sql.unsafe,unknown=Object.assign(Error('Synthetic connection loss'),{code:'ECONNRESET'});
 f.sql.unsafe=async(q,v)=>{if(q.startsWith('SELECT private.burimunsi_pin_rotate_passcode'))throw unknown;return unsafe(q,v);};
 await assert.rejects(changeWithBoundProof(f),e=>e===unknown);
});
test('staff creation supplies a JSONB passcode object',async()=>{
 const f=fixture();await f.store.mutateStaff({groupId:'g',actorSessionId:sid,actorId:id,requestId:rid,fingerprint:'f'.repeat(64),action:'create',name:'Example',phone:'+250780000001',capabilities:['records.read'],pinHash:hash});
 const q=f.calls.find(c=>c.q.startsWith('INSERT INTO private.burimunsi_accounts'));assert.deepEqual(q.v[6],hash);
});
test('staff command receipt supplies a JSONB response object',async()=>{
 const f=fixture();await f.store.mutateStaff({groupId:'g',actorSessionId:sid,actorId:id,requestId:rid,fingerprint:'f'.repeat(64),action:'create',name:'Example',phone:'+250780000001',capabilities:['records.read'],pinHash:hash});
 const q=f.calls.find(c=>c.q.startsWith('INSERT INTO private.burimunsi_command_receipts'));assert.equal(typeof q.v[6],'object');assert.equal(q.v[6].applied,true);
});
test('staff reset supplies a JSONB passcode object',async()=>{
 const f=fixture();await f.store.mutateStaff({groupId:'g',actorSessionId:sid,actorId:id,requestId:rid,fingerprint:'f'.repeat(64),action:'reset',id,expectedVersion:1,pinHash:hash});
 const q=f.calls.find(c=>c.q.startsWith('UPDATE private.burimunsi_accounts SET name'));assert.deepEqual(q.v[3],hash);
});
// The principal resolver below is an explicit trusted-port double, not GoTrue
// or PostgreSQL qualification. The real adapter must carry the login identity
// needed to select an already approved shared Collect operator.
test('staff creation can resolve the existing shared principal by its exact phone',async()=>{
 const f=fixture(),phone='+250780000002',principal='approved-shared-operator';let resolutions=0;
 f.store.createOperatorPrincipal=async(tx,input)=>{
  assert.equal(tx,f.sql);resolutions++;
  return input.groupId==='g'&&input.phone===phone&&input.actorId==='principal-1'?{id:principal}:null;
 };
 await f.store.mutateStaff({groupId:'g',actorSessionId:sid,actorId:id,requestId:rid,fingerprint:'f'.repeat(64),action:'create',name:'Example',phone,capabilities:['records.read'],pinHash:hash});
 const q=f.calls.find(c=>c.q.startsWith('INSERT INTO private.burimunsi_accounts'));
 assert.equal(q.v[2],principal);assert.equal(q.v[3],phone);assert.equal(resolutions,1);
 assert.equal(f.calls.some(c=>/INSERT INTO (?:app\.)?users\b/.test(c.q)),false);
});
test('unapproved shared identity cannot create a native staff account or receipt',async()=>{
 const f=fixture();f.store.createOperatorPrincipal=async()=>null;
 await assert.rejects(f.store.mutateStaff({groupId:'g',actorSessionId:sid,actorId:id,requestId:rid,fingerprint:'f'.repeat(64),action:'create',name:'Example',phone:'+250780000002',capabilities:['records.read'],pinHash:hash}),/principal_unavailable/);
 assert.equal(f.calls.some(c=>c.q.startsWith('INSERT INTO private.burimunsi_accounts')||c.q.startsWith('INSERT INTO private.burimunsi_command_receipts')),false);
});
