import test from 'node:test';import assert from 'node:assert/strict';
import {automaticWork} from '../../domain/burimunsi/automatic-work.js';
import {automaticJobRouter} from '../../domain/burimunsi/automatic-job-router.js';
const work={kind:'receipt',jobId:'df9a9625-2e23-4c5a-afb3-c0f0eb7c6d03',owner:'worker-1',leaseVersion:1};
test('work snapshot is frozen and independent of later mutation',()=>{const input={...work},copy=automaticWork(input);input.owner='other';assert.equal(copy.owner,'worker-1');assert(Object.isFrozen(copy));});
for(const [field,value] of [['kind','unknown'],['jobId','bad'],['owner',''],['leaseVersion',0],['leaseVersion',1.5],['leaseVersion','1']])
 test('work schema rejects invalid '+field,()=>assert.throws(()=>automaticWork({...work,[field]:value})));
test('work getters are never invoked',()=>{let calls=0;const input={...work};Object.defineProperty(input,'owner',{get(){calls++;return 'worker-1'},enumerable:true});assert.throws(()=>automaticWork(input));assert.equal(calls,0);});
test('unexpected member injection into a receipt work is rejected',()=>assert.throws(()=>automaticWork({...work,memberId:'member-2'})));
test('rematch requires bound member and policy',()=>{assert.throws(()=>automaticWork({...work,kind:'rematch'}));const checked=automaticWork({...work,kind:'rematch',memberId:'member-1',policyVersion:'identity-v1'});assert.equal(checked.memberId,'member-1');});
test('closed job routing never falls back between receipt and rematch authority',async()=>{const seen=[],sql={};const router=automaticJobRouter({assertPostingLease:(tx)=>{assert.equal(tx,sql);seen.push('receipt')}},{assertPostingLease:(tx)=>{assert.equal(tx,sql);seen.push('rematch')},retainAutomaticOutcome:(tx)=>{assert.equal(tx,sql);seen.push('checkpoint')}});await router.assertPostingLease(sql,{work});await router.assertPostingLease(sql,{work:{...work,kind:'rematch',memberId:'member-1',policyVersion:'v1'}});assert.deepEqual(seen,['receipt','rematch']);assert.throws(()=>router.retainAutomaticOutcome(sql,{work}));assert.deepEqual(seen,['receipt','rematch']);});
