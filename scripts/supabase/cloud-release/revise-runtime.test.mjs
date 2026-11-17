import test from 'node:test';
import assert from 'node:assert/strict';
import {reconcileResumeFunctions,reconcileResumeHistory,requireRevisionFunctions,requireRevisionPreimage,requireRevisionSchedulerReady,requireSecretPreimages,reviseRuntime,verifyFencedRevisionPreimage} from './revise-runtime.mjs';
import {createHash} from 'node:crypto';
import {identity} from './migrations.mjs';

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

test('the fenced preimage detects management drift before migration',async()=>{
 const before=['admin-api','collect-api','collect-jobs'].map((slug,i)=>({slug,status:'ACTIVE',verify_jwt:false,
  version:i+1,id:`00000000-0000-4000-8000-00000000000${i}`,ezbr_sha256:source}));
 const expected={mode:'open',epoch:25,source_sha256:source};
 const digest=createHash('sha256').update(source).digest('hex');
 const api=(functions,secret)=>async path=>({json:()=>path==='functions'?functions:[{name:'BUILD_SOURCE_ID',value:secret}]});
 assert.equal((await verifyFencedRevisionPreimage(expected,before,api(before,digest))).length,3);
 await assert.rejects(verifyFencedRevisionPreimage(expected,before,api(before,next)),/runtime_revision_source_secret_changed/);
 await assert.rejects(verifyFencedRevisionPreimage(expected,before,api(before.map((x,i)=>i?x:{...x,version:99}),digest)),
  /runtime_revision_functions_changed/);
});

const migration=identity('20261117180000_observation_status.sql','SELECT 1;');
const baseHistory=[{version:'20261117000000',name:'earlier',sha256:source,entries:1}];
const appliedHistory=[...baseHistory,{version:migration.version,name:migration.name,sha256:migration.sha256,entries:1}];
const functions=['collect-api','admin-api','collect-jobs'].map((slug,i)=>({slug,status:'ACTIVE',verify_jwt:false,
 version:10+i,id:`00000000-0000-4000-8000-00000000000${i}`,ezbr_sha256:source}));
const resumePrior={before:{mode:'open',epoch:'25',source_sha256:source},fenceId:'00000000-0000-4000-8000-000000000099',
 snapshot:{sourceSha256:next},testEvidence:{passed:true,sourceSha256:next},functions,
 migrations:[{file:migration.file,sha256:migration.sha256}],migrationHistory:baseHistory};
function resumeRecords(){
 const records=new Map([['revision-old-release-intent.json',resumePrior],
  ['revision-old-release-migration-'+migration.version+'-intent.json',{file:migration.file,sha256:migration.sha256,before:baseHistory}]]);
 return {records,readRecord:name=>records.get(name)??null};
}
function completedSecret(records,label='old-release'){
 records.set('revision-'+label+'-source-secret-attempt.json',{previousSourceSha256:source,sourceSha256:next});
 records.set('revision-'+label+'-source-secret-complete.json',{sourceSha256:next,secretSha256:createHash('sha256').update(next).digest('hex')});
}

test('resume accepts a committed exact migration after a lost acknowledgement',()=>{
 const {readRecord}=resumeRecords();
 assert.equal(reconcileResumeHistory(resumePrior,[migration],appliedHistory,readRecord,['old-release']).applied,1);
 for(const actual of [baseHistory.concat({...appliedHistory[1],sha256:next}),
  appliedHistory.concat({version:'20261117190000',name:'foreign',sha256:source,entries:1})])
  assert.throws(()=>reconcileResumeHistory(resumePrior,[migration],actual,readRecord,['old-release']),/fenced_revision_history_changed/);
 assert.throws(()=>reconcileResumeHistory(resumePrior,[migration],appliedHistory,()=>null,['old-release']),/fenced_revision_history_changed/);
 assert.throws(()=>reconcileResumeHistory({...resumePrior,migrations:[{file:'20261117180000_other.sql',sha256:migration.sha256}]},
  [migration],appliedHistory,readRecord,['old-release']),/fenced_revision_migrations_changed/);
});

test('resume only accepts confirmed deployments or unchanged original bundles',()=>{
 const {records,readRecord}=resumeRecords();
 const changed=functions.map((f,i)=>i?{...f,version:f.version+1}:{...f,version:f.version+2,ezbr_sha256:next});
 records.set('revision-old-release-collect-api-attempt.json',{sourceSha256:next});
 assert.throws(()=>reconcileResumeFunctions(resumePrior,changed,next,readRecord,['old-release']),/fenced_revision_function_outcome_unknown/);
 records.set('revision-old-release-collect-api-complete.json',changed[0]);
 assert.deepEqual(reconcileResumeFunctions(resumePrior,changed,next,readRecord,['old-release']).confirmed,['collect-api']);
 assert.throws(()=>reconcileResumeFunctions(resumePrior,changed,next,()=>null,['old-release']),/fenced_revision_function_outcome_unknown/);
});

test('changed-bundle qualification rejects a confirmed unchanged digest',()=>{
 const {records,readRecord}=resumeRecords();
 const unchanged=functions.map((x,i)=>i?x:{...x,version:x.version+1});
 records.set('revision-old-release-collect-api-attempt.json',{sourceSha256:next});
 records.set('revision-old-release-collect-api-complete.json',unchanged[0]);
 assert.equal(reconcileResumeFunctions(resumePrior,unchanged,next,readRecord,['old-release']).confirmed.length,1);
 assert.throws(()=>reconcileResumeFunctions(resumePrior,unchanged,next,readRecord,['old-release'],true),/revision_bundle_unchanged/);
});

test('repeated resumes can use earlier recorded evidence without replay',()=>{
 const {records,readRecord}=resumeRecords();
 const changed=functions.map((f,i)=>i?{...f,version:f.version+1}:{...f,version:f.version+2,ezbr_sha256:next});
 records.set('revision-old-release-collect-api-attempt.json',{sourceSha256:next});
 records.set('revision-old-release-collect-api-complete.json',changed[0]);
 assert.equal(reconcileResumeHistory(resumePrior,[migration],appliedHistory,readRecord,['old-release','retry-release']).applied,1);
 assert.deepEqual(reconcileResumeFunctions(resumePrior,changed,next,readRecord,['old-release','retry-release']).confirmed,['collect-api']);
});

test('an unacknowledged deploy attempt blocks even when the old bundle remains visible',async()=>{
 const {records,readRecord}=resumeRecords();
 records.set('revision-old-release-collect-api-attempt.json',{sourceSha256:next});
 assert.throws(()=>reconcileResumeFunctions(resumePrior,functions,next,readRecord,['old-release']),/fenced_revision_function_outcome_unknown/);
 let deployed=false;
 const db={async query(sql){
  if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256'))return {rows:[{mode:'fenced',epoch:'25',operation_id:resumePrior.fenceId,source_sha256:source}]};
  if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))return {rows:[{n:0}]};
  if(sql==='SELECT private._collect_fence_scheduler_status() AS status')return {rows:[{status:ready}]};
  throw Error('unexpected_database_operation');},async end(){}};
 await assert.rejects(reviseRuntime({label:'pending-retry',resumeFencedRevision:'old-release',
  testEvidence:{passed:true,sourceSha256:next},migrations:[migration]},
 {captureSnapshot:()=>({sourceSha:next,summary:()=>({sourceSha256:next})}),check:()=>({status:'passed'}),open:async()=>db,
  api:async(path,options)=>{if(options)deployed=true;return {json:()=>functions};},readHistory:async()=>appliedHistory,
  save:()=>{throw Error('unexpected_save')},readRecord}),/fenced_revision_function_outcome_unknown/);
 assert.equal(deployed,false);
});

test('an unacknowledged source-secret update is never retried from either readback',async()=>{
 for(const observed of [source,next]){
  const {records,readRecord}=resumeRecords();records.set('revision-old-release-source-secret-attempt.json',{
   previousSourceSha256:source,sourceSha256:next});let mutations=0;
  const db={async query(sql){
   if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256'))return {rows:[{mode:'fenced',epoch:'25',operation_id:resumePrior.fenceId,source_sha256:source}]};
   if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))return {rows:[{n:0}]};
   if(sql==='SELECT private._collect_fence_scheduler_status() AS status')return {rows:[{status:ready}]};
   throw Error('unexpected_database_operation');},async end(){}};
  await assert.rejects(reviseRuntime({label:'secret-retry',resumeFencedRevision:'old-release',
   testEvidence:{passed:true,sourceSha256:next},migrations:[migration]},
  {captureSnapshot:()=>({sourceSha:next,summary:()=>({sourceSha256:next})}),check:()=>({status:'passed'}),open:async()=>db,
   api:async(path,options)=>{if(options)mutations++;return {json:()=>path==='functions'?functions:[{
    name:'BUILD_SOURCE_ID',value:createHash('sha256').update(observed).digest('hex')}]};},readHistory:async()=>appliedHistory,
   save:()=>{throw Error('unexpected_save')},readRecord}),/fenced_revision_secret_outcome_unknown/);
  assert.equal(mutations,0);
 }
});

test('a completed secret cannot precede a missing reviewed migration',async()=>{
 const {records,readRecord}=resumeRecords();completedSecret(records);let mutations=0;
 const db={async query(sql){
  if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256'))return {rows:[{mode:'fenced',epoch:'25',operation_id:resumePrior.fenceId,source_sha256:source}]};
  if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))return {rows:[{n:0}]};
  if(sql==='SELECT private._collect_fence_scheduler_status() AS status')return {rows:[{status:ready}]};
  throw Error('unexpected_database_operation');},async end(){}};
 await assert.rejects(reviseRuntime({label:'missing-migration',resumeFencedRevision:'old-release',
  testEvidence:{passed:true,sourceSha256:next},migrations:[migration]},
 {captureSnapshot:()=>({sourceSha:next,summary:()=>({sourceSha256:next})}),check:()=>({status:'passed'}),open:async()=>db,
  api:async(path,options)=>{if(options)mutations++;return {json:()=>path==='functions'?functions:[{
   name:'BUILD_SOURCE_ID',value:createHash('sha256').update(next).digest('hex')}]};},readHistory:async()=>baseHistory,
  save:()=>{throw Error('unexpected_save')},readRecord}),/fenced_revision_history_changed/);
 assert.equal(mutations,0);
});

test('resume skips the exact committed migration and confirmed function',async()=>{
 const {records,readRecord}=resumeRecords();const current=functions.map((f,i)=>i?{...f}:{...f,version:f.version+1,ezbr_sha256:next});
 completedSecret(records);
 records.set('revision-old-release-collect-api-attempt.json',{sourceSha256:next});
 records.set('revision-old-release-collect-api-complete.json',current[0]);
 let control={mode:'fenced',epoch:'25',source_sha256:source,operation_id:resumePrior.fenceId};
 const calls=[],saved=[];let secret=createHash('sha256').update(next).digest('hex');
 const db={async query(sql,args){calls.push(sql);
  if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256'))return {rows:[control]};
  if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))return {rows:[{n:0}]};
  if(sql==='SELECT private._collect_fence_scheduler_status() AS status')return {rows:[{status:ready}]};
  if(sql.startsWith('SELECT private.collect_fence_drain_v3'))return {rows:[{v:{mode:'fenced'}}]};
  if(sql.startsWith('SELECT private.collect_fence_upgrade_source_v3')){control={mode:'fenced',epoch:'26',source_sha256:next,operation_id:args[0]};return {rows:[]};}
  if(sql.startsWith('SELECT private.collect_fence_release_v3')){control={mode:'open',epoch:'27',source_sha256:next,operation_id:args[0]};return {rows:[]};}
  throw Error('unexpected_database_operation');},async end(){}};
 const api=async(path,options)=>{
  if(path==='functions')return {json:()=>structuredClone(current)};
  if(path==='secrets'&&!options)return {json:()=>[{name:'BUILD_SOURCE_ID',value:secret}]};
  if(path==='secrets')throw Error('already-bound secret must not be rewritten');
  if(path.startsWith('functions/deploy?slug=')){const slug=path.split('=')[1];calls.push('deploy:'+slug);
   const row=current.find(x=>x.slug===slug);row.version++;row.ezbr_sha256=next;return {json:()=>({version:row.version})};}
  throw Error('unexpected_api');
 };
 const result=await reviseRuntime({label:'new-release',resumeFencedRevision:'old-release',
  testEvidence:{passed:true,sourceSha256:next},migrations:[migration],
  expectedBefore:{mode:'fenced',epoch:25,source_sha256:source},expectedFunctions:structuredClone(current)},
 {captureSnapshot:()=>({sourceSha:next,summary:()=>({sourceSha256:next}),makeForm:()=>({})}),
  check:()=>({status:'passed',sourceSha256:next}),open:async()=>db,api,save:(n,v)=>saved.push({n,v}),
  readHistory:async()=>appliedHistory,applyMigration:async()=>{throw Error('migration replayed')},readRecord});
 assert.equal(result.status,'revision_deployed_live');
 assert.deepEqual(calls.filter(x=>x.startsWith('deploy:')),['deploy:admin-api','deploy:collect-jobs']);
 assert.equal(saved.some(x=>x.n.includes('migration-')),false);
});

function upgradedFixture({released=false,corruptReceipt=false,secretOld=false}={}){
 const digest=x=>createHash('sha256').update(typeof x==='string'?x:JSON.stringify(x)).digest('hex');
 const prior={...resumePrior,upgradeId:'00000000-0000-4000-8000-000000000097',
  releaseId:'00000000-0000-4000-8000-000000000098',checked:{status:'passed',sourceSha256:next}};
 const current=functions.map(x=>({...x,version:x.version+1,ezbr_sha256:next}));
 const records=new Map([['revision-old-release-intent.json',prior],
  ['revision-old-release-migration-'+migration.version+'-intent.json',{file:migration.file,sha256:migration.sha256,before:baseHistory}],
  ['revision-old-release-deployment-readback.json',{sourceSha256:next,functions:current,sha256:digest(current)}]]);
 completedSecret(records);
 for(const item of current){records.set('revision-old-release-'+item.slug+'-attempt.json',{sourceSha256:next});
  records.set('revision-old-release-'+item.slug+'-complete.json',item);}
 let control={mode:released?'open':'fenced',epoch:released?'27':'26',source_sha256:next,
  operation_id:released?prior.releaseId:prior.upgradeId};
 const queries=[],saved=[];
 const db={async query(sql,args){queries.push({sql,args});
  if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256'))return {rows:[control]};
  if(sql==='BEGIN ISOLATION LEVEL READ COMMITTED'||sql==='COMMIT'||sql==='ROLLBACK'||sql.startsWith('SELECT pg_advisory_xact_lock'))return {rows:[]};
  if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))return {rows:[{n:released?1:0}]};
  if(sql==='SELECT private._collect_fence_scheduler_status() AS status')return {rows:[{status:ready}]};
  if(sql.includes('FROM private.collect_fence_source_upgrades'))return {rows:[{
   prior_fence_operation_id:prior.fenceId,old_source_sha256:source,old_epoch:'25',new_source_sha256:next,new_epoch:'26',
   plan_sha256:corruptReceipt?source:digest(prior),qualification_sha256:digest({testEvidence:prior.testEvidence,checked:prior.checked}),
   deployment_readback_sha256:digest(current)}]};
  if(sql.startsWith('SELECT action,epoch,source_sha256'))return {rows:[{action:'release',epoch:'27',source_sha256:next}]};
  if(sql.startsWith('SELECT private.collect_fence_release_v3')){
   assert.equal(args[0],prior.releaseId);control={mode:'open',epoch:'27',source_sha256:next,operation_id:prior.releaseId};return {rows:[]};}
  throw Error('unexpected_database_operation');},async end(){}};
 const deps={captureSnapshot:()=>({sourceSha:next,summary:()=>({sourceSha256:next})}),
  check:()=>({status:'passed',sourceSha256:next}),open:async()=>db,
  api:async(path,options)=>{if(options)throw Error('unexpected_mutation');
   if(path==='functions')return {json:()=>current};
   if(path==='secrets')return {json:()=>[{name:'BUILD_SOURCE_ID',value:digest(secretOld?source:next)}]};throw Error('unexpected_api');},
  save:(n,v)=>saved.push({n,v}),readHistory:async()=>appliedHistory,
  applyMigration:async()=>{throw Error('migration replayed')},readRecord:name=>records.get(name)??null};
 return {deps,queries,saved,prior,current};
}

test('receipt-bound upgraded fence releases once with the original release ID',async()=>{
 const f=upgradedFixture();
 const result=await reviseRuntime({label:'recovery-one',resumeFencedRevision:'old-release',
  testEvidence:{passed:true,sourceSha256:next},migrations:[migration]},f.deps);
 assert.equal(result.status,'revision_deployed_live');
 assert.equal(f.queries.filter(x=>x.sql.startsWith('SELECT private.collect_fence_release_v3')).length,1);
 assert.equal(f.saved.some(x=>x.n==='revision-recovery-one-release-resume-complete.json'),true);
});

test('an already released receipt is read back without any replay',async()=>{
 const f=upgradedFixture({released:true});
 const result=await reviseRuntime({label:'recovery-two',resumeFencedRevision:'old-release',
  testEvidence:{passed:true,sourceSha256:next},migrations:[migration]},f.deps);
 assert.equal(result.status,'revision_already_deployed_live');
 assert.equal(f.queries.some(x=>/collect_fence_release_v3|collect_fence_drain_v3|collect_fence_upgrade_source_v3/.test(x.sql)),false);
 assert.equal(f.saved.length,0);
});

test('a changed upgrade receipt prevents release',async()=>{
 const f=upgradedFixture({corruptReceipt:true});
 await assert.rejects(reviseRuntime({label:'recovery-three',resumeFencedRevision:'old-release',
  testEvidence:{passed:true,sourceSha256:next},migrations:[migration]},f.deps),/fenced_revision_upgrade_evidence_changed/);
 assert.equal(f.queries.some(x=>x.sql.startsWith('SELECT private.collect_fence_release_v3')),false);
 assert.equal(f.saved.length,0);
});

test('a deployed function with an old source secret cannot be released',async()=>{
 const f=upgradedFixture({secretOld:true});
 await assert.rejects(reviseRuntime({label:'recovery-four',resumeFencedRevision:'old-release',
  testEvidence:{passed:true,sourceSha256:next},migrations:[migration]},f.deps),/fenced_revision_source_secret_changed/);
 assert.equal(f.queries.some(x=>x.sql.startsWith('SELECT private.collect_fence_release_v3')),false);
});

test('a fresh revision records its exact deployment readback before upgrade',async()=>{
 const digest=x=>createHash('sha256').update(typeof x==='string'?x:JSON.stringify(x)).digest('hex');
 let control={mode:'open',epoch:'25',source_sha256:source,operation_id:'00000000-0000-4000-8000-000000000099'};
 const current=functions.map(x=>({...x})),saved=[],queries=[];let secret=digest(source),history=baseHistory;
 const db={async query(sql,args){queries.push(sql);
  if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256'))return {rows:[control]};
  if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))return {rows:[{n:0}]};
  if(sql==='SELECT private._collect_fence_scheduler_status() AS status')return {rows:[{status:ready}]};
  if(sql.startsWith('SELECT private.collect_fence_begin_quiesce')){control={...control,mode:'quiescing',operation_id:args[0]};return {rows:[{v:control}]};}
  if(sql.startsWith('SELECT private.collect_fence_drain_v3')){control={...control,mode:'fenced'};return {rows:[{v:control}]};}
  if(sql.startsWith('SELECT private.collect_fence_upgrade_source_v3')){
   assert.equal(saved.at(-1).n,'revision-fresh-release-deployment-readback.json');
   assert.equal(args[7],saved.at(-1).v.sha256);control={mode:'fenced',epoch:'26',source_sha256:next,operation_id:args[0]};return {rows:[]};}
  if(sql.startsWith('SELECT private.collect_fence_release_v3')){control={mode:'open',epoch:'27',source_sha256:next,operation_id:args[0]};return {rows:[]};}
  throw Error('unexpected_database_operation');},async end(){}};
 const api=async(path,options)=>{
  if(path==='functions')return {json:()=>structuredClone(current)};
  if(path==='secrets'&&!options)return {json:()=>[{name:'BUILD_SOURCE_ID',value:secret}]};
  if(path==='secrets'){secret=digest(next);current.forEach(x=>x.version++);return {json:()=>({})};}
  if(path.startsWith('functions/deploy?slug=')){const row=current.find(x=>x.slug===path.split('=')[1]);
   row.version++;row.ezbr_sha256=next;return {json:()=>({version:row.version})};}
  throw Error('unexpected_api');
 };
 const result=await reviseRuntime({label:'fresh-release',testEvidence:{passed:true,sourceSha256:next},migrations:[migration],requireChangedBundles:true,
  expectedBefore:{mode:'open',epoch:25,source_sha256:source},expectedFunctions:structuredClone(current)},
 {captureSnapshot:()=>({sourceSha:next,summary:()=>({sourceSha256:next}),makeForm:()=>({})}),
  check:()=>({status:'passed',sourceSha256:next}),open:async()=>db,api,save:(n,v)=>saved.push({n,v}),
  readHistory:async()=>history,applyMigration:async()=>{history=appliedHistory;return history}});
 assert.equal(result.status,'revision_deployed_live');
 assert.equal(saved.find(x=>x.n==='revision-fresh-release-intent.json').v.requireChangedBundles,true);
 assert.equal(saved.at(-1).n,'revision-fresh-release-complete.json');
 assert.equal(queries.filter(x=>x.startsWith('SELECT private.collect_fence_upgrade_source_v3')).length,1);
});

test('a fresh qualified revision stops before upgrade when a bundle is unchanged',async()=>{
 const digest=x=>createHash('sha256').update(x).digest('hex');
 let control={mode:'open',epoch:'25',source_sha256:source,operation_id:'00000000-0000-4000-8000-000000000099'},secret=digest(source);
 const current=functions.map(x=>({...x})),saved=[],queries=[];
 const db={async query(sql,args){queries.push(sql);
  if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256'))return {rows:[control]};
  if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))return {rows:[{n:0}]};
  if(sql==='SELECT private._collect_fence_scheduler_status() AS status')return {rows:[{status:ready}]};
  if(sql.startsWith('SELECT private.collect_fence_begin_quiesce')){control={...control,mode:'quiescing',operation_id:args[0]};return {rows:[{v:control}]};}
  if(sql.startsWith('SELECT private.collect_fence_drain_v3')){control={...control,mode:'fenced'};return {rows:[{v:control}]};}
  throw Error('unexpected_database_operation');},async end(){}};
 const api=async(path,options)=>{
  if(path==='functions')return {json:()=>structuredClone(current)};
  if(path==='secrets'&&!options)return {json:()=>[{name:'BUILD_SOURCE_ID',value:secret}]};
  if(path==='secrets'){secret=digest(next);return {json:()=>({})};}
  if(path.startsWith('functions/deploy?slug=')){const row=current.find(x=>x.slug===path.split('=')[1]);
   row.version++;return {json:()=>({version:row.version})};}
  throw Error('unexpected_api');
 };
 await assert.rejects(reviseRuntime({label:'unchanged-release',testEvidence:{passed:true,sourceSha256:next},migrations:[],requireChangedBundles:true,
  expectedBefore:{mode:'open',epoch:25,source_sha256:source},expectedFunctions:structuredClone(current)},
 {captureSnapshot:()=>({sourceSha:next,summary:()=>({sourceSha256:next}),makeForm:()=>({})}),
  check:()=>({status:'passed'}),open:async()=>db,api,save:(n,v)=>saved.push({n,v}),readHistory:async()=>[]}),/revision_bundle_unchanged/);
 assert.equal(queries.some(x=>x.startsWith('SELECT private.collect_fence_upgrade_source_v3')),false);
 assert.equal(saved.some(x=>x.n==='revision-unchanged-release-collect-api-complete.json'),false);
 assert.equal(control.mode,'fenced');
});

function freshDriftFixture({afterSecret=null,functionRead=null,secretRead=null}={}){
 const digest=x=>createHash('sha256').update(x).digest('hex');
 const secretMap={BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:digest('false'),COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256:digest('old-approval')};
 let control={mode:'open',epoch:'25',source_sha256:source,operation_id:'00000000-0000-4000-8000-000000000099'},secret=digest(source),functionReads=0,secretReads=0;
 const current=functions.map(x=>({...x})),saved=[],queries=[],deploys=[];
 const db={async query(sql,args){queries.push(sql);
  if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256'))return {rows:[control]};
  if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))return {rows:[{n:0}]};
  if(sql==='SELECT private._collect_fence_scheduler_status() AS status')return {rows:[{status:ready}]};
  if(sql.startsWith('SELECT private.collect_fence_begin_quiesce')){control={...control,mode:'quiescing',operation_id:args[0]};return {rows:[{v:control}]};}
  if(sql.startsWith('SELECT private.collect_fence_drain_v3')){control={...control,mode:'fenced'};return {rows:[{v:control}]};}
  if(sql.startsWith('SELECT private.collect_fence_upgrade_source_v3')){control={mode:'fenced',epoch:'26',source_sha256:next,operation_id:args[0]};return {rows:[]};}
  if(sql.startsWith('SELECT private.collect_fence_release_v3')){control={mode:'open',epoch:'27',source_sha256:next,operation_id:args[0]};return {rows:[]};}
  throw Error('unexpected_database_operation');},async end(){}};
 const api=async(path,options)=>{
  if(path==='functions'){functionReads++;const result=structuredClone(current);functionRead?.(functionReads,result);return {json:()=>result};}
  if(path==='secrets'&&!options){secretReads++;const result=[{name:'BUILD_SOURCE_ID',value:secret},...Object.entries(secretMap).map(([name,value])=>({name,value}))];
   secretRead?.(secretReads,result);return {json:()=>result};}
  if(path==='secrets'){secret=digest(next);current.forEach(x=>x.version++);afterSecret?.(current);return {json:()=>({})};}
  if(path.startsWith('functions/deploy?slug=')){const slug=path.split('=')[1];deploys.push(slug);
   const row=current.find(x=>x.slug===slug);row.version++;row.ezbr_sha256=next;return {json:()=>({version:row.version})};}
  throw Error('unexpected_api');
 };
 const args={label:'drift-release',testEvidence:{passed:true,sourceSha256:next},migrations:[],requireChangedBundles:true,
  expectedBefore:{mode:'open',epoch:25,source_sha256:source},expectedFunctions:structuredClone(current),expectedSecretPreimages:secretMap};
 const deps={captureSnapshot:()=>({sourceSha:next,summary:()=>({sourceSha256:next}),makeForm:()=>({})}),
  check:()=>({status:'passed'}),open:async()=>db,api,save:(n,v)=>saved.push({n,v}),readHistory:async()=>[]};
 return {args,deps,queries,saved,deploys,secretMap};
}

test('migration history drift prevents both source upgrade and release',async()=>{
 for(const driftRead of [2,3]){
  const f=freshDriftFixture();let reads=0;
  f.deps.readHistory=async()=>++reads===driftRead?baseHistory:[];
  await assert.rejects(reviseRuntime(f.args,f.deps),/runtime_revision_history_changed/);
  assert.equal(f.queries.some(x=>x.startsWith('SELECT private.collect_fence_upgrade_source_v3')),driftRead===3);
  assert.equal(f.queries.some(x=>x.startsWith('SELECT private.collect_fence_release_v3')),false);
 }
});

test('secret preimages require one exact metadata hash and never expose values',()=>{
 const expected={BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'d'.repeat(64)};
 requireSecretPreimages(expected,[{name:'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED',value:'d'.repeat(64)}]);
 for(const metadata of [[],[{name:'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED',value:source}],
  [{name:'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED',value:'d'.repeat(64)},{name:'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED',value:'d'.repeat(64)}]])
  assert.throws(()=>requireSecretPreimages(expected,metadata),/runtime_revision_secret_preimage_changed/);
 assert.throws(()=>requireSecretPreimages({BUILD_SOURCE_ID:source},[]),/runtime_revision_secret_preimage_invalid/);
});

test('post-secret provider drift stops before dispatching any function',async()=>{
 for(const change of [{id:'11111111-1111-4111-8111-111111111111'},{status:'INACTIVE'},{verify_jwt:true},{ezbr_sha256:next}]){
  const f=freshDriftFixture({afterSecret:rows=>Object.assign(rows[0],change)});
  await assert.rejects(reviseRuntime(f.args,f.deps),/functions_changed/);
  assert.deepEqual(f.deploys,[]);assert.equal(f.queries.some(x=>x.startsWith('SELECT private.collect_fence_upgrade_source_v3')),false);
 }
});

test('a changed function ID after its deploy is not recorded complete',async()=>{
 const f=freshDriftFixture({functionRead:(count,rows)=>{if(count===5)rows[0].id='11111111-1111-4111-8111-111111111111';}});
 await assert.rejects(reviseRuntime(f.args,f.deps),/revision_deploy_unconfirmed/);
 assert.equal(f.saved.some(x=>x.n==='revision-drift-release-collect-api-complete.json'),false);
 assert.equal(f.queries.some(x=>x.startsWith('SELECT private.collect_fence_upgrade_source_v3')),false);
});

test('final function ID, status and JWT drift each prevent source upgrade',async()=>{
 for(const change of [{id:'11111111-1111-4111-8111-111111111111'},{status:'INACTIVE'},{verify_jwt:true}]){
  const f=freshDriftFixture({functionRead:(count,rows)=>{if(count===10)Object.assign(rows[0],change);}});
  await assert.rejects(reviseRuntime(f.args,f.deps),/runtime_revision_functions_changed/);
  assert.deepEqual(f.deploys,['collect-api','admin-api','collect-jobs']);
  assert.equal(f.queries.some(x=>x.startsWith('SELECT private.collect_fence_upgrade_source_v3')),false);
  assert.equal(f.queries.some(x=>x.startsWith('SELECT private.collect_fence_release_v3')),false);
 }
});

test('native secret drift stops both pre-upgrade and pre-release',async()=>{
 for(const readNumber of [4,5]){
  const f=freshDriftFixture({secretRead:(count,rows)=>{if(count===readNumber)rows.find(x=>x.name==='BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED').value=next;}});
  await assert.rejects(reviseRuntime(f.args,f.deps),/runtime_revision_secret_preimage_changed/);
  assert.equal(f.queries.some(x=>x.startsWith('SELECT private.collect_fence_upgrade_source_v3')),readNumber===5);
  assert.equal(f.queries.some(x=>x.startsWith('SELECT private.collect_fence_release_v3')),false);
 }
});
