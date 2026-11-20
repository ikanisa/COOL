import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,readFileSync,rmSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {JournalError,prepareAttempt,readAttempt,recordDispatchIntent,recordOutcome} from './journal.mjs';
const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',other='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',planSha256='d'.repeat(64),code=x=>e=>e instanceof JournalError&&e.code===x;
const fixture=async fn=>{const root=mkdtempSync('/private/tmp/collect-journal-fixture-');try{return await fn(root);}finally{rmSync(root,{recursive:true,force:true});}};
const opts=(root,operationId=id)=>({mode:'synthetic',root,operationId,planSha256});
function race(root){return new Promise(resolve=>{const c=spawn(process.execPath,[fileURLToPath(new URL('./journal-race-worker.mjs',import.meta.url))],{stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});let out='';c.stdout.on('data',b=>out+=b);c.on('close',(status)=>resolve({status,out:out.trim()}));c.stdin.end(JSON.stringify({root,id,planSha256}));});}
test('synthetic durable one-use journal and trusted-root gate',{timeout:30000},async t=>{
 await t.test('managed journal is bound to its declared scope and plan',()=>fixture(async root=>{prepareAttempt({...opts(root),mode:'managed'});assert.throws(()=>readAttempt(opts(root)),code('active_attempt_mismatch'));assert.throws(()=>readAttempt({...opts(root),mode:'managed',planSha256:'e'.repeat(64)}),code('active_attempt_mismatch'));}));
 await t.test('intent is durable before a missing acknowledgement and prevents redispatch',()=>fixture(async root=>{
  assert.deepEqual(prepareAttempt(opts(root)),{status:'prepared'});assert.deepEqual(recordDispatchIntent(opts(root)),{status:'dispatch_intent_recorded'});
  assert.deepEqual(readAttempt(opts(root)),{status:'dispatch_intent',dispatchAllowed:false,artifactSha256:null,planSha256});
  assert.throws(()=>recordDispatchIntent(opts(root)),code('dispatch_refused'));assert.throws(()=>prepareAttempt(opts(root,other)),code('existing_record_refused'));
  assert.deepEqual(recordOutcome({...opts(root),outcome:'outcome_unknown',artifactSha256:null}),{status:'outcome_unknown'});
  assert.equal(readAttempt(opts(root)).status,'outcome_unknown');assert.throws(()=>prepareAttempt(opts(root,other)),code('existing_record_refused'));
 }));
 await t.test('a completed receipt can be reconciled without authorizing a new attempt',()=>fixture(async root=>{
  prepareAttempt(opts(root));recordDispatchIntent(opts(root));const digest='c'.repeat(64);
  recordOutcome({...opts(root),outcome:'completed',artifactSha256:digest});
  assert.deepEqual(readAttempt(opts(root)),{status:'completed',dispatchAllowed:false,artifactSha256:digest,planSha256});
  assert.throws(()=>recordOutcome({...opts(root),outcome:'completed',artifactSha256:digest}),code('outcome_refused'));
  assert.throws(()=>prepareAttempt(opts(root)),code('existing_record_refused'));assert.throws(()=>prepareAttempt(opts(root,other)),code('existing_record_refused'));
 }));
 await t.test('concurrent processes obtain at most one dispatch permit',()=>fixture(async root=>{
  prepareAttempt(opts(root));const results=await Promise.all([race(root),race(root)]);
  assert.equal(results.filter(x=>x.status===0&&x.out==='dispatch_intent_recorded').length,1);assert.equal(results.filter(x=>x.status!==0).length,1);
  assert.equal(readAttempt(opts(root)).status,'dispatch_intent');
 }));
 await t.test('truncated or altered journal fails closed',()=>fixture(async root=>{
  prepareAttempt(opts(root));recordDispatchIntent(opts(root));const p=join(root,`attempt-${id}.journal`),original=readFileSync(p,'utf8');
  writeFileSync(p,original.replace('dispatch_intent','completed'));assert.throws(()=>readAttempt(opts(root)),code('journal_refused'));
 }));
});
