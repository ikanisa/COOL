import test from 'node:test';
import assert from 'node:assert/strict';
import {consumeNativeIngressNonce,NATIVE_INGRESS_CLAIM_TIMEOUT_MS} from '../native-ingress-nonce.js';

const values=()=>({nonce:'4c84dbb9-113c-4c4c-8b64-7f495789a172',profile:'a'.repeat(64),policy:'b'.repeat(64),issuedAtMs:1700000000000});
function fixture(fn){
 const calls=[],abandoned=[];
 return {calls,abandoned,work:{abandon(reason){abandoned.push(reason);}},db:{prepare(sql){calls.push({sql});return {bind(...args){calls.at(-1).args=args;return {first(column){calls.at(-1).column=column;return fn();}};}};}}};
}
const unavailable=error=>error?.message==='native_ingress_store_unavailable';

test('one acknowledged fenced claim is parameterized and returned',async()=>{
 const f=fixture(async()=>true),input=values();
 assert.equal(await consumeNativeIngressNonce(f.db,f.work,input),true);
 assert.deepEqual(f.calls,[{sql:'SELECT private.collect_native_ingress_consume(?::uuid,?::text,?::text,?::bigint) AS claimed',args:[input.nonce,input.profile,input.policy,input.issuedAtMs],column:'claimed'}]);
 assert.deepEqual(f.abandoned,[]);
});
test('an acknowledged duplicate remains a denial and is not retried',async()=>{
 const f=fixture(async()=>false);
 assert.equal(await consumeNativeIngressNonce(f.db,f.work,values()),false);
 assert.equal(f.calls.length,1);assert.deepEqual(f.abandoned,[]);
});
test('invalid or unverified-shaped input never reaches the store',async()=>{
 for(const update of [{nonce:'not-a-uuid'},{nonce:{toString:()=>values().nonce}},{profile:'X'.repeat(64)},{policy:'b'.repeat(63)},{issuedAtMs:0},{issuedAtMs:1.5},{extra:true}]){
  const f=fixture(async()=>true);await assert.rejects(consumeNativeIngressNonce(f.db,f.work,{...values(),...update}),unavailable);
  assert.equal(f.calls.length,0);assert.deepEqual(f.abandoned,[]);
 }
});
test('failure, lost acknowledgement and non-boolean results abandon work without retry',async()=>{
 for(const fn of [async()=>{throw Error('private database detail');},async()=>null,async()=>'true']){
  const f=fixture(fn);await assert.rejects(consumeNativeIngressNonce(f.db,f.work,values()),unavailable);
  assert.equal(f.calls.length,1);assert.deepEqual(f.abandoned,['work_lost']);
 }
});
test('a hung acknowledgement times out, abandons work and ignores a later result',async t=>{
 t.mock.timers.enable({apis:['setTimeout']});let finish;
 const f=fixture(()=>new Promise(resolve=>{finish=resolve;}));
 const pending=consumeNativeIngressNonce(f.db,f.work,values());await Promise.resolve();
 t.mock.timers.tick(NATIVE_INGRESS_CLAIM_TIMEOUT_MS);
 await assert.rejects(pending,unavailable);finish(true);await Promise.resolve();
 assert.equal(f.calls.length,1);assert.deepEqual(f.abandoned,['work_lost']);
});
