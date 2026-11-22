import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,realpath,readFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {beginAttempt,attachBackend,finishAttempt,beginReconciliation,finishReconciliation} from './journal.mjs';
const plan={preimageSha256:'a'.repeat(64),admissions:{count:2,sha:'b'.repeat(64)},reviewedPlanSha256:'c'.repeat(64),exclusionEvidenceSha256:'d'.repeat(64)};
const code=x=>e=>e?.archiveCode===x;

test('durable fixture journal binds the preimage, permits one dispatch and never turns missing acknowledgement into retry',async()=>{
 const root=await mkdtemp(join(await realpath(tmpdir()),'collect-archive-journal-'));
 try{
  const job=await beginAttempt(root,plan);await attachBackend(job,123456);
  await assert.rejects(beginAttempt(root,plan),code('APPLY_ALREADY_ATTEMPTED'));
  await assert.rejects(beginReconciliation(root,{...plan,reviewedPlanSha256:'d'.repeat(64)}),code('JOURNAL_MISMATCH'));
  const r=await beginReconciliation(root,plan);assert.equal(r.priorBackendPid,123456);
  await finishReconciliation(r,'not_recorded_do_not_retry');
  const status=JSON.parse(await readFile(join(r.dir,`reconcile-${r.attempt}.outcome.json`),'utf8'));
  assert.equal(status.state,'not_recorded_do_not_retry');
  await assert.rejects(beginAttempt(root,plan),code('APPLY_ALREADY_ATTEMPTED'));
  // Missing outcome remains missing until a valid one-use writer records it.
  await finishAttempt(job,'unconfirmed','COMMIT_UNKNOWN');
  await assert.rejects(finishAttempt(job,'committed'),code('JOURNAL_UNAVAILABLE'));
 }finally{await rm(root,{recursive:true,force:true});}
});

test('an intent without a verified backend cannot be reconciled or retried automatically',async()=>{
 const root=await mkdtemp(join(await realpath(tmpdir()),'collect-archive-journal-'));
 try{await beginAttempt(root,plan);await assert.rejects(beginReconciliation(root,plan),code('JOURNAL_UNAVAILABLE'));
  await assert.rejects(beginAttempt(root,plan),code('APPLY_ALREADY_ATTEMPTED'));
 }finally{await rm(root,{recursive:true,force:true});}
});

test('two concurrent dispatch intents cannot both claim the same version and trusted root',async()=>{
 const root=await mkdtemp(join(await realpath(tmpdir()),'collect-archive-journal-'));
 try{
  const result=await Promise.allSettled([beginAttempt(root,plan),beginAttempt(root,plan)]);
  assert.equal(result.filter(x=>x.status==='fulfilled').length,1);
  assert.equal(result.filter(x=>x.status==='rejected'&&x.reason?.archiveCode==='APPLY_ALREADY_ATTEMPTED').length,1);
 }finally{await rm(root,{recursive:true,force:true});}
});
