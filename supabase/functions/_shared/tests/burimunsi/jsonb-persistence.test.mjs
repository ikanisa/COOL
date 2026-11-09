import test from 'node:test';import assert from 'node:assert/strict';import {pathToFileURL} from 'node:url';
const path=process.env.BURI_AUTH_SOURCE;
const {PostgresNativeAuthStore}=await import(path?pathToFileURL(path).href:'../../domain/burimunsi/postgres-auth-store.js');
const id='11111111-1111-4111-8111-111111111111',sid='22222222-2222-4222-8222-222222222222',rid='33333333-3333-4333-8333-333333333333';
function fixture(){
 const calls=[];const actor={id,session_id:sid,expires_at:9999999999999,installation_id:'44444444-4444-4444-8444-444444444444',principal_user_id:'principal-1',collection_id:'g',role:'admin',capabilities:['records.read','staff.manage'],installation_profile:'internal_receiver'};
 const sql={unsafe:async(q,v=[])=>{calls.push({q,v});if(q.startsWith('SELECT s.id'))return [actor];if(q.startsWith('UPDATE private.burimunsi_accounts SET pin_hash'))return [{id}];if(q.startsWith('SELECT * FROM private.burimunsi_accounts'))return [{id,role:'staff',removed:false,version:1,name:'Example',phone:'+250780000001',capabilities:['records.read'],pin_hash:{algorithm:'test'},active:true}];return []}};
 const db={applicationWork:{assert:async()=>{}},transaction:fn=>fn(sql),context:async()=>{},readContext:async()=>{}};
 return {calls,sql,store:new PostgresNativeAuthStore({db,groupId:'g',createOperatorPrincipal:async()=>({id:'existing-principal'}),clock:()=>1000})};
}
const hash={algorithm:'pbkdf2-sha256',iterations:600000,salt:'synthetic',hash:'synthetic',pepperId:'test-key'};
test('passcode change supplies a JSONB object, not pre-stringified JSON',async()=>{
 const f=fixture();await f.store.changePinIfCurrent({groupId:'g',sessionId:sid,actorId:id,accountId:id,expectedCredentialVersion:1,pinHash:hash});
 const q=f.calls.find(c=>c.q.startsWith('UPDATE private.burimunsi_accounts SET pin_hash'));assert.deepEqual(q.v[0],hash);
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
