import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readdirSync,rmSync} from 'node:fs';
import {dispatchManagedBackup,GovernorError,readSyntheticGovernedAttempt,runSyntheticGovernedAttempt} from './synthetic-governor.mjs';
const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',other='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',code=x=>e=>e instanceof GovernorError&&e.code===x;
const fixture=async fn=>{const root=mkdtempSync('/private/tmp/collect-governor-fixture-');let retain=false;try{return await fn(root,()=>{retain=true;});}finally{if(retain)process.stderr.write(`[synthetic-governor] retained unconfirmed fixture ${root}\n`);else rmSync(root,{recursive:true,force:true});}};
const opts=(root,action,operationId=id,deadlineMs=3000)=>({mode:'synthetic',root,operationId,deadlineMs,action});
test('outer synthetic supervisor retains uncertain attempts',{timeout:30000},async t=>{
 await t.test('production refuses before touching root or spawning',async()=>{let reads=0;const o={mode:'managed'};Object.defineProperty(o,'root',{get(){reads++;throw Error();}});await assert.rejects(runSyntheticGovernedAttempt(o),code('managed_execution_closed'));await assert.rejects(dispatchManagedBackup(o),code('managed_execution_closed'));assert.equal(reads,0);});
 await t.test('overlapping journal and artifact roots are refused before intent',()=>fixture(async root=>{
  const r=await runSyntheticGovernedAttempt({...opts(root,'synthetic_backup'),config:{scratchPath:root}});assert.equal(r.status,'worker_outcome_unconfirmed');assert.deepEqual(readdirSync(root),[]);
 }));
 await t.test('normal result is journalled and duplicate dispatch is blocked',()=>fixture(async root=>{
  assert.deepEqual(await runSyntheticGovernedAttempt(opts(root,'fixture_complete')),{status:'completed',dispatchAllowed:false,artifactSha256:'f'.repeat(64)});
  assert.deepEqual(await readSyntheticGovernedAttempt(opts(root,'read')),{status:'completed',dispatchAllowed:false,artifactSha256:'f'.repeat(64)});
  assert.equal((await runSyntheticGovernedAttempt(opts(root,'fixture_complete',other))).status,'worker_outcome_unconfirmed');
 }));
 await t.test('missing acknowledgement requires independent journal read, never redispatch',()=>fixture(async root=>{
  assert.deepEqual(await runSyntheticGovernedAttempt(opts(root,'fixture_missing_ack')),{status:'acknowledgement_missing_do_not_retry',dispatchAllowed:false});
  assert.equal((await readSyntheticGovernedAttempt(opts(root,'read'))).status,'completed');assert.equal((await runSyntheticGovernedAttempt(opts(root,'fixture_complete'))).status,'worker_outcome_unconfirmed');
 }));
 await t.test('deadline stops a blocked event loop without claiming dispatch status',()=>fixture(async (root,retain)=>{
  const start=Date.now(),r=await runSyntheticGovernedAttempt(opts(root,'blocked_before_prepare',id,300));if(r.status==='group_stop_unconfirmed')retain();assert(Date.now()-start<4000);
  assert(['deadline_terminated_outcome_unknown','group_stop_unconfirmed'].includes(r.status));assert.equal(r.dispatchAllowed,false);
  assert.equal((await readSyntheticGovernedAttempt(opts(root,'read'))).status,'worker_outcome_unconfirmed');
 }));
 await t.test('deadline after dispatch leaves the trusted-root gate and unknown outcome',()=>fixture(async (root,retain)=>{
  const r=await runSyntheticGovernedAttempt(opts(root,'hang_after_dispatch',id,300));if(r.status==='group_stop_unconfirmed')retain();assert(['deadline_terminated_outcome_unknown','group_stop_unconfirmed'].includes(r.status));
  assert.equal((await readSyntheticGovernedAttempt(opts(root,'read'))).status,'dispatch_intent');assert.equal((await runSyntheticGovernedAttempt(opts(root,'fixture_complete',other))).status,'worker_outcome_unconfirmed');
 }));
 await t.test('descendant process timeout remains unconfirmed unless the group is gone',()=>fixture(async (root,retain)=>{
  const r=await runSyntheticGovernedAttempt(opts(root,'hang_with_child',id,300));if(r.status==='group_stop_unconfirmed')retain();assert(['deadline_terminated_outcome_unknown','group_stop_unconfirmed'].includes(r.status));assert.equal(r.dispatchAllowed,false);
  assert.equal((await readSyntheticGovernedAttempt(opts(root,'read'))).status,'dispatch_intent');
 }));
});
