import test from 'node:test';
import assert from 'node:assert/strict';
import {PostgresNativeFinancialJobs} from '../../domain/burimunsi/postgres-native-financial-jobs.js';

const ids={jobId:'11111111-1111-4111-8111-111111111111',leaseToken:'22222222-2222-4222-8222-222222222222',
 grant:'33333333-3333-4333-8333-333333333333',admission:'44444444-4444-4444-8444-444444444444'};
const source=(x={})=>({contractVersion:1,kind:'native_receipt',groupId:'synthetic-group',sourceId:'synthetic-source',transactionId:'synthetic-transaction',
 jobId:ids.jobId,workerGrantId:ids.grant,workerGrantVersion:1,owner:'synthetic-worker',leaseToken:ids.leaseToken,leaseVersion:1,
 leaseExpiresAt:1900000000000,admissionId:ids.admission,admissionEpoch:1,sourceCodeSha256:'a'.repeat(64),
 sourceKey:'b'.repeat(64),sourceKeyContentSha256:'c'.repeat(64),sourceKeyBodySha256:'d'.repeat(64),bodySha256:'d'.repeat(64),
 objectSha256:'e'.repeat(64),sourceFingerprint:'f'.repeat(64),ownerUserId:'synthetic-owner',objectSizeBytes:100,transactionMode:'historical',...x});
const work=()=>({jobId:ids.jobId,leaseToken:ids.leaseToken,leaseVersion:1});
function fixture(sql){return new PostgresNativeFinancialJobs({authority:{groupId:'synthetic-group',write:fn=>fn(sql)}});}

test('enqueue binds the authorized grant and source in the same SQL call',async()=>{
 let calls=0;const sql={async unsafe(q,args){calls++;assert.match(q,/native_work_enqueue\(\$1::uuid,\$2\)/);assert.deepEqual(args,[ids.grant,'synthetic-source']);return [{result:{jobId:ids.jobId,state:'queued',durable:true}}];}};
 assert.equal((await fixture(sql).enqueue(ids.grant,'synthetic-source')).durable,true);
 await assert.rejects(fixture(sql).enqueue('not-a-grant','synthetic-source'));assert.equal(calls,1);
});
test('assertNativeLease uses the caller transaction and returns frozen server-derived historical identity',async()=>{
 let calls=0;const sql={async unsafe(query,args){calls++;assert.match(query,/native_work_assert/);assert.deepEqual(args,[ids.jobId,ids.leaseToken,1]);return [{result:source()}];}};
 const r=await fixture(sql).assertNativeLease(sql,work());
 assert.equal(calls,1);assert.equal(r.transactionMode,'historical');assert.equal(r.ownerUserId,'synthetic-owner');assert.ok(Object.isFrozen(r));
});
test('assertion refuses another group, missing key or inconsistent body hash',async()=>{
 for(const replacement of [{groupId:'other-group'},{sourceKey:null},{sourceKeyBodySha256:'0'.repeat(64)}]){
  const sql={async unsafe(){return [{result:source(replacement)}];}};
  await assert.rejects(fixture(sql).assertNativeLease(sql,work()));
 }
});
test('lease arguments are snapshotted before awaiting SQL',async()=>{
 const w=work();const sql={async unsafe(query,args){w.leaseVersion=7;assert.equal(args[2],1);return [{result:source()}];}};
 const r=await fixture(sql).assertNativeLease(sql,w);assert.equal(r.leaseVersion,1);assert.equal(w.leaseVersion,7);
});
test('getter-based lease data and invalid delays are refused before SQL',async()=>{
 let calls=0;const sql={async unsafe(){calls++;return [{result:source()}];}};const jobs=fixture(sql);const w=work();
 Object.defineProperty(w,'leaseToken',{enumerable:true,get(){throw Error('must not invoke');}});
 await assert.rejects(jobs.assertNativeLease(sql,w));await assert.rejects(jobs.defer(work(),'identity_unavailable',29999));assert.equal(calls,0);
});
test('defer uses the exact lease and bounded evidence retry rather than accepting arbitrary states',async()=>{
 const sql={async unsafe(q,args){assert.match(q,/native_work_defer/);assert.deepEqual(args,[ids.jobId,ids.leaseToken,1,'identity_unavailable',30000]);return [{result:{jobId:ids.jobId,state:'waiting',nextAttemptAt:1900000030000}}];}};
 const r=await fixture(sql).defer(work(),'identity_unavailable',30000);assert.equal(r.state,'waiting');
 await assert.rejects(fixture(sql).defer(work(),'posted',30000));
});
test('completion uses the same SQL transaction and refuses an unconfirmed acknowledgement',async()=>{
 const sql={async unsafe(q,args){assert.match(q,/native_work_complete/);assert.deepEqual(args,[ids.jobId,ids.leaseToken,1]);
  return [{result:{jobId:ids.jobId,state:'completed',transactionId:'synthetic-transaction'}}];}};
 const r=await fixture(sql).completeInTransaction(sql,work());assert.equal(r.state,'completed');assert.ok(Object.isFrozen(r));
 const bad={async unsafe(){return [{result:{jobId:ids.jobId,state:'waiting',transactionId:'synthetic-transaction'}}];}};
 await assert.rejects(fixture(bad).completeInTransaction(bad,work()));
});
