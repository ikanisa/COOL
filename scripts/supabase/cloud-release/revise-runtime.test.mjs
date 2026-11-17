import test from 'node:test';
import assert from 'node:assert/strict';
import {requireRevisionFunctions,requireRevisionPreimage,requireRevisionSchedulerReady,reviseRuntime} from './revise-runtime.mjs';

const source='a'.repeat(64),next='b'.repeat(64);
const ready={checked:true,coverageVerified:true,blocking:false,namedActiveJobs:0,
 pendingNativeRequests:0,lifecycleUnproven:0,reviewedUnknownDispatches:1};

function fixture(scheduler){
 const calls=[],saved=[];
 const db={
  async query(sql){
   calls.push(sql);
   if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256'))
    return {rows:[{mode:'open',epoch:'25',operation_id:'prior',source_sha256:source}]};
   if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))
    return {rows:[{n:0}]};
   if(sql==='SELECT private._collect_fence_scheduler_status() AS status')
    return {rows:[{status:scheduler}]};
   throw Error('unexpected_database_operation');
  },
  async end(){calls.push('connection_closed');}
 };
 const deps={
  captureSnapshot:()=>({sourceSha:next,summary:()=>({sourceSha256:next})}),
  check:()=>({status:'passed',sourceSha256:next}),
  open:async()=>db,
  api:async(path)=>{calls.push('api:'+path);return {json:()=>[{}, {}, {}]};},
  readHistory:async()=>[],
  save:(name,plan)=>{saved.push({name,plan});throw Error('test_stops_before_intent_write');}
 };
 return {calls,saved,deps};
}

test('scheduler readiness fails closed for unavailable or unverified status',()=>{
 for(const value of [null,undefined,{},[],{...ready,checked:false},
  {...ready,coverageVerified:false},{...ready,blocking:true},
  {...ready,checked:'true'},{...ready,blocking:0}]){
  assert.throws(()=>requireRevisionSchedulerReady(value),/runtime_revision_scheduler_not_drained/);
 }
 assert.equal(requireRevisionSchedulerReady(ready),ready);
});

test('active cron and unproven dispatch stop before an intent or quiesce',async()=>{
 for(const status of [
  {...ready,blocking:true,namedActiveJobs:1},
  {...ready,blocking:true,lifecycleUnproven:1}
 ]){
  const f=fixture(status);
  await assert.rejects(reviseRuntime({label:'scheduler-test',testEvidence:{passed:true}},f.deps),
   /runtime_revision_scheduler_not_drained/);
  assert.equal(f.saved.length,0);
  assert.equal(f.calls.some(x=>x.startsWith('api:')),false);
  assert.equal(f.calls.some(x=>/begin_quiesce|drain_v3|UPDATE|INSERT|DELETE/.test(x)),false);
  assert.equal(f.calls.at(-1),'connection_closed');
 }
});

test('an observed ready scheduler is retained in the revision intent',async()=>{
 const f=fixture(ready);
 await assert.rejects(reviseRuntime({label:'scheduler-test',testEvidence:{passed:true}},f.deps),
  /test_stops_before_intent_write/);
 assert.equal(f.saved.length,1);
 assert.equal(f.saved[0].name,'revision-scheduler-test-intent.json');
 assert.deepEqual(f.saved[0].plan.schedulerPreflight,ready);
 assert.equal(f.calls.some(x=>/begin_quiesce|drain_v3/.test(x)),false);
 assert.equal(f.calls.at(-1),'connection_closed');
});

test('qualified source and epoch are checked before any revision action',async()=>{
 const good={mode:'open',epoch:25,source_sha256:source};
 for(const bad of [null,{}, {...good,epoch:26},{...good,source_sha256:'c'.repeat(64)},
  {...good,mode:'fenced'}, {...good,epoch:'25'}]){
  assert.throws(()=>requireRevisionPreimage(bad,{...good,epoch:'25'}),/runtime_revision_preimage_changed/);
 }
 assert.equal(requireRevisionPreimage(good,{...good,epoch:'25'}).source_sha256,source);
 const f=fixture(ready);
 await assert.rejects(reviseRuntime({label:'preimage-test',testEvidence:{passed:true,sourceSha256:next},
  expectedBefore:{...good,epoch:26}},f.deps),/runtime_revision_preimage_changed/);
 assert.equal(f.saved.length,0);
 assert.equal(f.calls.some(x=>x.startsWith('api:')||/begin_quiesce|drain_v3/.test(x)),false);
 assert.equal(f.calls.at(-1),'connection_closed');
});

test('a source-bound revision rejects test evidence for another snapshot',async()=>{
 const f=fixture(ready);
 await assert.rejects(reviseRuntime({label:'preimage-test',testEvidence:{passed:true,sourceSha256:source},
  expectedBefore:{mode:'open',epoch:25,source_sha256:source}},f.deps),/runtime_revision_evidence_changed/);
 assert.equal(f.saved.length,0);
 assert.equal(f.calls.some(x=>x.startsWith('api:')||/begin_quiesce|drain_v3/.test(x)),false);
});

test('a revision rejects changed deployed functions before fencing',()=>{
 const before=['admin-api','collect-api','collect-jobs'].map((slug,i)=>({slug,status:'ACTIVE',verify_jwt:false,
  version:i+1,id:`00000000-0000-4000-8000-00000000000${i}`,ezbr_sha256:source}));
 assert.equal(requireRevisionFunctions(before,[...before].reverse()).length,3);
 for(const changed of [before.slice(0,2),[before[0],before[1],before[1]],
  before.map((x,i)=>i===0?{...x,version:x.version+1}:x),
  before.map((x,i)=>i===1?{...x,ezbr_sha256:next}:x),
  before.map((x,i)=>i===2?{...x,verify_jwt:true}:x)])
  assert.throws(()=>requireRevisionFunctions(before,changed),/runtime_revision_functions_changed/);
});
