import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,readFileSync,rmSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {JournalError,dispatchManagedBackup,prepareSyntheticAttempt,readSyntheticAttempt,recordSyntheticDispatchIntent,recordSyntheticOutcome} from './synthetic-journal.mjs';
const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',other='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',code=x=>e=>e instanceof JournalError&&e.code===x;
const fixture=async fn=>{const root=mkdtempSync('/private/tmp/collect-journal-fixture-');try{return await fn(root);}finally{rmSync(root,{recursive:true,force:true});}};
const opts=(root,operationId=id)=>({mode:'synthetic',root,operationId});
function race(root){return new Promise(resolve=>{const c=spawn(process.execPath,[fileURLToPath(new URL('./journal-race-worker.mjs',import.meta.url))],{stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});let out='';c.stdout.on('data',b=>out+=b);c.on('close',(status)=>resolve({status,out:out.trim()}));c.stdin.end(JSON.stringify({root,id}));});}
test('synthetic durable one-use journal and trusted-root gate',{timeout:30000},async t=>{
 await t.test('managed execution refuses before accessing root',async()=>{let reads=0;const o={mode:'managed'};Object.defineProperty(o,'root',{get(){reads++;throw Error();}});assert.throws(()=>prepareSyntheticAttempt(o),code('managed_execution_closed'));assert.throws(()=>dispatchManagedBackup(o),code('managed_execution_closed'));assert.equal(reads,0);});
 await t.test('intent is durable before a missing acknowledgement and prevents redispatch',()=>fixture(async root=>{
  assert.deepEqual(prepareSyntheticAttempt(opts(root)),{status:'prepared'});assert.deepEqual(recordSyntheticDispatchIntent(opts(root)),{status:'dispatch_intent_recorded'});
  assert.deepEqual(readSyntheticAttempt(opts(root)),{status:'dispatch_intent',dispatchAllowed:false,artifactSha256:null});
  assert.throws(()=>recordSyntheticDispatchIntent(opts(root)),code('dispatch_refused'));assert.throws(()=>prepareSyntheticAttempt(opts(root,other)),code('existing_record_refused'));
  assert.deepEqual(recordSyntheticOutcome({...opts(root),outcome:'outcome_unknown',artifactSha256:null}),{status:'outcome_unknown'});
  assert.equal(readSyntheticAttempt(opts(root)).status,'outcome_unknown');assert.throws(()=>prepareSyntheticAttempt(opts(root,other)),code('existing_record_refused'));
 }));
 await t.test('a completed receipt can be reconciled without authorizing a new attempt',()=>fixture(async root=>{
  prepareSyntheticAttempt(opts(root));recordSyntheticDispatchIntent(opts(root));const digest='c'.repeat(64);
  recordSyntheticOutcome({...opts(root),outcome:'completed',artifactSha256:digest});
  assert.deepEqual(readSyntheticAttempt(opts(root)),{status:'completed',dispatchAllowed:false,artifactSha256:digest});
  assert.throws(()=>recordSyntheticOutcome({...opts(root),outcome:'completed',artifactSha256:digest}),code('outcome_refused'));
  assert.throws(()=>prepareSyntheticAttempt(opts(root)),code('existing_record_refused'));assert.throws(()=>prepareSyntheticAttempt(opts(root,other)),code('existing_record_refused'));
 }));
 await t.test('concurrent processes obtain at most one dispatch permit',()=>fixture(async root=>{
  prepareSyntheticAttempt(opts(root));const results=await Promise.all([race(root),race(root)]);
  assert.equal(results.filter(x=>x.status===0&&x.out==='dispatch_intent_recorded').length,1);assert.equal(results.filter(x=>x.status!==0).length,1);
  assert.equal(readSyntheticAttempt(opts(root)).status,'dispatch_intent');
 }));
 await t.test('truncated or altered journal fails closed',()=>fixture(async root=>{
  prepareSyntheticAttempt(opts(root));recordSyntheticDispatchIntent(opts(root));const p=join(root,`attempt-${id}.journal`),original=readFileSync(p,'utf8');
  writeFileSync(p,original.replace('dispatch_intent','completed'));assert.throws(()=>readSyntheticAttempt(opts(root)),code('journal_refused'));
 }));
});
