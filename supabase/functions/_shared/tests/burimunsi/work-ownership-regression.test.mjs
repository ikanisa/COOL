import test from 'node:test';import assert from 'node:assert/strict';import {pathToFileURL,fileURLToPath} from 'node:url';import path from 'node:path';
// Same probes can execute the delivered baseline source as an explicit control.
const runtime=process.env.BURIMUNSI_REGRESSION_ROOT??fileURLToPath(new URL('../../domain/burimunsi/',import.meta.url));
const {ContributionService}=await import(pathToFileURL(path.join(runtime,'contribution-service.js')));
const {PostgresReceiptJobStore}=await import(pathToFileURL(path.join(runtime,'postgres-receipt-job-store.js')));
const ID='df9a9625-2e23-4c5a-afb3-c0f0eb7c6d03',NOW=1794000000000;
test('automatic work generation does not change during an awaited command',async()=>{
 const work={kind:'receipt',jobId:ID,owner:'worker-1',leaseVersion:1},seen=[];
 const tx={assertAutomaticAdmission:async cmd=>{seen.push(cmd.work.leaseVersion);work.leaseVersion=99;},
  lockReceipt:async()=>({id:'tx-1',groupId:'group-1',version:1,state:'unallocated',hasConflict:false,amountRwf:1000}),
  loadApprovedPolicy:async()=>null,listEligibleMembers:async()=>[],listVerifiedIdentities:async()=>[],
  postCanonicalContribution:async()=>{throw Error('must not post')},readCanonicalResult:async()=>null};
 const svc=new ContributionService({store:{inCanonicalTransaction:fn=>fn(tx)},groupId:'group-1'});
 assert.equal((await svc.automaticallyAllocate('tx-1',crypto.randomUUID(),work)).state,'unallocated');assert.deepEqual(seen,[1,1]);
});
function fixture({expireInAdmission=false}={}) {
 let clock=NOW;const queries=[];
 const row={id:ID,collection_id:'group-1',source_id:'source-1',source_sha256:'a'.repeat(64),binding_id:'binding-1',binding_version:1,
  receiving_account_id:'wallet-1',profile_version:'p1',lease_owner:'worker-1',lease_version:1,lease_expires_at:NOW+30000,
  attempt:1,max_attempts:4,transaction_id:'tx-1',state:'running'};
 const sql={unsafe:async q=>{queries.push(q);if(q.startsWith('SELECT floor'))return [{now_ms:String(clock)}];
  if(q.startsWith('SELECT *')){if(!expireInAdmission)clock=NOW+30001;return [row];}
  if(q.includes('RETURNING state'))return [{state:'retry'}];return [];}};
 const store=new PostgresReceiptJobStore({authority:{groupId:'group-1',write:fn=>fn(sql)},
  admission:{assertInTransaction:async()=>{if(expireInAdmission)clock=NOW+30001;return {processingEnabled:true,profile:{version:'p1'}};}},
  sources:{assertLineage:async()=>true,load:async()=>null},canonical:{ingest:async()=>null,outcome:async()=>null}});
 return {store,queries,sql};
}
test('receipt failure cleanup checks expiry after acquiring row ownership',async()=>{const f=fixture();const r=await f.store.failJob({jobId:ID,owner:'worker-1',leaseVersion:1});assert.deepEqual(r,{applied:false,state:'lease_lost'});assert(!f.queries.some(q=>q.startsWith('UPDATE')));});
test('receipt posting lease is rechecked after awaited admission',async()=>{const f=fixture({expireInAdmission:true});await assert.rejects(f.store.assertPostingLease(f.sql,{groupId:'group-1',transactionId:'tx-1',work:{kind:'receipt',jobId:ID,owner:'worker-1',leaseVersion:1}}),/lease_unavailable/);});
