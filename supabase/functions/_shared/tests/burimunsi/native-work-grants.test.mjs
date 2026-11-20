import test from 'node:test';
import assert from 'node:assert/strict';
import {PostgresNativeWorkGrants} from '../../domain/burimunsi/postgres-native-work-grants.js';

const id='11111111-1111-4111-8111-111111111111',requestId='22222222-2222-4222-8222-222222222222';
const args=['synthetic-admin','a'.repeat(64),'https://admin.synthetic.invalid','33333333-3333-4333-8333-333333333333'];
const input=()=>({requestId,grantId:id,owner:'synthetic-worker',version:1,policyVersion:'policy-1',expiresAt:1900000000000});
const receipt=()=>({grantId:id,groupId:'synthetic-group',owner:'synthetic-worker',version:1,enabled:false,expiresAt:1900000000000});
const client=sql=>new PostgresNativeWorkGrants({authority:{groupId:'synthetic-group',write:fn=>fn(sql)},actorArgs:args});

test('issuance passes exact actor/request tuple and defaults to disabled',async()=>{
 const sql={async unsafe(q,p){assert.match(q,/native_grant_issue/);assert.deepEqual(p,[...args,'synthetic-group',requestId,id,'synthetic-worker',1,'policy-1',1900000000000,false]);return [{result:receipt()}];}};
 const out=await client(sql).issue(input());assert.equal(out.enabled,false);assert.ok(Object.isFrozen(out));
});
test('a returned grant from a different group or with changed values is refused',async()=>{
 for(const change of [{groupId:'different-group'},{enabled:true},{owner:'other-worker'}]){
  const sql={async unsafe(){return [{result:{...receipt(),...change}}];}};await assert.rejects(client(sql).issue(input()));
 }
});
test('revocation binds original request and verifies durable result',async()=>{
 const sql={async unsafe(q,p){assert.match(q,/native_grant_revoke/);assert.deepEqual(p,[...args,'synthetic-group',requestId,id]);
  return [{result:{grantId:id,groupId:'synthetic-group',revoked:true,applied:true}}];}};
 assert.equal((await client(sql).revoke({requestId,grantId:id})).revoked,true);
});
test('lost mutation response is not retried; same request is reconciled by lookup',async()=>{
 let count=0;const sql={async unsafe(q){count++;if(q.includes('grant_issue'))throw Error('synthetic response lost');
  assert.match(q,/native_grant_command/);return [{result:{found:true,operation:'issue',receipt:receipt()}}];}};
 const api=client(sql);await assert.rejects(api.issue(input()));assert.equal(count,1);
 const out=await api.lookup(requestId);assert.equal(count,2);assert.equal(out.receipt.enabled,false);assert.ok(Object.isFrozen(out.receipt));
});
test('getters and malformed authority results fail before returning a receipt',async()=>{
 let count=0;const sql={async unsafe(){count++;return [{result:{found:true,operation:'issue',receipt:{...receipt(),groupId:'other'}}}];}};
 const api=client(sql),v=input();Object.defineProperty(v,'owner',{enumerable:true,get(){throw Error('must not execute');}});
 await assert.rejects(api.issue(v));assert.equal(count,0);await assert.rejects(api.lookup(requestId));assert.equal(count,1);
});
