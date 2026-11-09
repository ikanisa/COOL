import test from 'node:test';import assert from 'node:assert/strict';
import {PostgresReceiptJobStore,safeProcessingCode} from '../../domain/burimunsi/postgres-receipt-job-store.js';
import {sha256} from '../../domain/burimunsi/values.js';
import {parseReceipt,receiptFingerprint,transactionKey} from '../../domain/burimunsi/receipt.js';
import {profile,fullSource} from './fixtures.mjs';
// SQL recorder only: these tests exercise actual adapter code, parameters and
// callback boundaries. They do NOT simulate PostgreSQL locking, RLS or commits.
const ID='df9a9625-2e23-4c5a-afb3-c0f0eb7c6d03';const NOW=1794000000000;
const hash=await sha256(fullSource.body);
function fixture(){
 const calls=[];
 const row={id:ID,collection_id:'group-1',source_id:'source-1',source_sha256:hash,binding_id:'binding-1',binding_version:'1',receiving_account_id:'wallet-1',profile_version:profile.version,
  lease_owner:'worker-1',lease_version:'2',lease_expires_at:String(NOW+180000),attempt:1,max_attempts:4,transaction_id:'tx-1',state:'running'};
 const state={hold:false,clock:NOW,source:{...fullSource,id:'source-1',groupId:'group-1',receivingAccountId:'wallet-1',bindingId:'binding-1',bindingVersion:1},lineage:true,
  canonical:{durable:true,transactionId:'tx-1',groupId:'group-1',receivingAccountId:'wallet-1'},outcome:{transactionId:'tx-1',groupId:'group-1',state:'posted',hasConflict:false,ledgerEntryId:'ledger-1'},rowsAffected:true,failState:'retry'};
 const tx={unsafe:async(sql,values=[])=>{
  calls.push({type:'sql',sql,values});
  if(sql.startsWith('SELECT floor'))return [{now_ms:String(state.clock)}];
  if(sql.startsWith('SELECT *'))return [row];
  if(sql.startsWith('WITH candidate'))return [row];
  if(sql.includes('RETURNING lease_expires_at'))return state.rowsAffected?[{lease_expires_at:NOW+180000}]:[];
  if(sql.includes('RETURNING state'))return state.rowsAffected?[{state:state.failState}]:[];
  if(sql.includes('RETURNING id'))return state.rowsAffected?[{id:ID}]:[];
  return [];
 }};
 const authority={groupId:'group-1',write:async fn=>{calls.push({type:'begin'});try{const value=await fn(tx);calls.push({type:'commit'});return value}catch(e){calls.push({type:'rollback'});throw e}}};
 const admission={assertInTransaction:async sql=>{assert.equal(sql,tx);calls.push({type:'admission'});return {processingEnabled:!state.hold,profile}}};
 const sources={assertLineage:async sql=>{assert.equal(sql,tx);return state.lineage},load:async sql=>{assert.equal(sql,tx);calls.push({type:'source'});return state.source}};
 const canonical={ingest:async sql=>{assert.equal(sql,tx);calls.push({type:'ingest'});if(state.expireDuringIngest){state.clock=NOW+200000;state.rowsAffected=false}return state.canonical},outcome:async sql=>{assert.equal(sql,tx);return state.outcome}};
 const store=new PostgresReceiptJobStore({authority,admission,sources,canonical});
 const job={id:ID,groupId:'group-1'};const witness={jobId:ID,owner:'worker-1',leaseVersion:2};
 return {store,state,row,calls,tx,job,witness};
}
const capture={groupId:'group-1',sourceId:'source-1',sourceSha256:hash,bindingId:'binding-1',bindingVersion:1,receivingAccountId:'wallet-1',profileVersion:profile.version};
test('constructor rejects an unadmitted transaction port',()=>assert.throws(()=>new PostgresReceiptJobStore({authority:{}})));
test('current hold prevents claiming and source access',async()=>{const f=fixture();f.state.hold=true;await assert.rejects(f.store.claimNext({groupId:'group-1',owner:'worker-1',profileVersion:profile.version,leaseMs:180000}),/processing_on_hold/);assert.equal(f.calls.some(c=>c.sql?.startsWith('WITH candidate')),false)});
test('claim uses database clock and conditional skip-locked lease generation',async()=>{const f=fixture();const j=await f.store.claimNext({groupId:'group-1',owner:'worker-1',profileVersion:profile.version,leaseMs:180000,now:1});assert.equal(j.leaseVersion,2);const c=f.calls.find(c=>c.sql?.startsWith('WITH candidate'));assert(c.sql.includes('SKIP LOCKED'));assert(c.sql.includes('lease_version=j.lease_version+1'));assert.equal(c.values[1],NOW)});
test('expired last-attempt work has a durable dead-letter path',async()=>{const f=fixture();await f.store.claimNext({groupId:'group-1',owner:'worker-1',profileVersion:profile.version,leaseMs:180000});assert(f.calls.some(c=>c.sql?.includes("state='dead_letter'")&&c.sql.includes('attempt>=max_attempts')))});
test('ingress enqueue is in supplied transaction, not a second commit',async()=>{const f=fixture();const r=await f.store.enqueueInTransaction(f.tx,capture);assert.equal(r.jobId,ID);assert(!f.calls.some(c=>c.type==='begin'));assert(f.calls.some(c=>c.sql?.includes('ON CONFLICT(collection_id,source_id) DO NOTHING')))});
test('replayed source cannot be relabelled after receiver replacement',async()=>{const f=fixture();await assert.rejects(f.store.enqueueInTransaction(f.tx,{...capture,bindingVersion:2}),/source_changed/)});
test('unverified ingress lineage cannot enqueue work',async()=>{const f=fixture();f.state.lineage=false;await assert.rejects(f.store.enqueueInTransaction(f.tx,capture),/source_scope_changed/);assert(!f.calls.some(c=>c.sql?.startsWith('INSERT')))});
for(const [key,value] of [['lease_owner','other'],['lease_version','3'],['lease_expires_at',String(NOW)],['state','completed']])test('stale lease blocks source read '+key,async()=>{const f=fixture();f.row[key]=value;await assert.rejects(f.store.loadSource({job:f.job,owner:'worker-1',leaseVersion:2}),/lease_unavailable/);assert(!f.calls.some(c=>c.type==='source'))});
test('source bytes are hash-checked before use',async()=>{const f=fixture();f.state.source.body+=' changed';await assert.rejects(f.store.loadSource({job:f.job,owner:'worker-1',leaseVersion:2}),/source_hash_changed/)});
test('original binding lineage is checked on retained source',async()=>{const f=fixture();f.state.source.bindingVersion=2;await assert.rejects(f.store.loadSource({job:f.job,owner:'worker-1',leaseVersion:2}),/source_scope_changed/)});
async function ingest(f){const receipt=parseReceipt(fullSource,profile);return f.store.commitCanonicalReceipt({job:f.job,owner:'worker-1',leaseVersion:2,key:transactionKey('wallet-1',receipt),fingerprint:await receiptFingerprint(receipt),receipt:{amountRwf:999999}})}
test('canonical ingest reparses retained body and never trusts caller receipt',async()=>{const f=fixture();const r=await ingest(f);assert.equal(r.transactionId,'tx-1');assert(f.calls.some(c=>c.type==='source'));assert(f.calls.findIndex(c=>c.type==='ingest')<f.calls.findIndex(c=>c.type==='commit'))});
test('cross-group canonical outcome rolls back job checkpoint',async()=>{const f=fixture();f.state.canonical.groupId='other';await assert.rejects(ingest(f),/canonical_ack_missing/);assert.equal(f.calls.at(-1).type,'rollback')});
test('expired lease during ingestion rejects the enclosing transaction',async()=>{const f=fixture();f.state.expireDuringIngest=true;await assert.rejects(ingest(f),/lease_unavailable/);assert.equal(f.calls.at(-1).type,'rollback')});
test('posting fence uses writer SQL transaction without opening another',async()=>{const f=fixture();await f.store.assertPostingLease(f.tx,{groupId:'group-1',transactionId:'tx-1',work:{kind:'receipt',...f.witness}});assert(!f.calls.some(c=>c.type==='begin'));assert(f.calls.some(c=>c.sql?.includes('FOR UPDATE')))});
test('posting fence rejects wrong canonical transaction',async()=>{const f=fixture();await assert.rejects(f.store.assertPostingLease(f.tx,{groupId:'group-1',transactionId:'another',work:{kind:'receipt',...f.witness}}),/transaction_conflict/)});
test('finish requires observed canonical outcome',async()=>{const f=fixture();f.state.outcome={...f.state.outcome,state:'processing'};await assert.rejects(f.store.finishJob({...f.witness,transactionId:'tx-1'}),/canonical_posting_outcome_missing/)});
test('finish refuses a newly conflicted canonical record',async()=>{const f=fixture();f.state.outcome.hasConflict=true;await assert.rejects(f.store.finishJob({...f.witness,transactionId:'tx-1'}),/canonical_posting_outcome_missing/)});
test('successful finish clears lease only through owner/version CAS',async()=>{const f=fixture();assert.deepEqual(await f.store.finishJob({...f.witness,transactionId:'tx-1'}),{applied:true});const c=f.calls.find(c=>c.sql?.includes("SET state='completed'"));assert(c.sql.includes('lease_version=$5'));assert(c.sql.includes('lease_expires_at>$4'))});
test('lost finish acknowledgement can be retried without rewriting evidence',async()=>{const f=fixture();f.state.rowsAffected=false;await assert.rejects(f.store.finishJob({...f.witness,transactionId:'tx-1'}),/lease_unavailable/)});
test('failure checkpoint cannot overwrite a newer lease',async()=>{const f=fixture();f.state.rowsAffected=false;assert.deepEqual(await f.store.failJob({...f.witness,code:'transaction_conflict'}),{applied:false,state:'lease_lost'})});
test('failure metadata strips arbitrary private exception content',async()=>{const f=fixture();await f.store.failJob({...f.witness,code:'Customer EXAMPLE received 10000; secret=xyz'});const c=f.calls.find(c=>c.sql?.includes('RETURNING state'));assert.equal(c.values.at(-1),'processing_unavailable')});
test('pausing processing does not prevent safe retry checkpoint',async()=>{const f=fixture();f.state.hold=true;const r=await f.store.failJob({...f.witness,code:'processing_on_hold'});assert(r.applied);assert(!f.calls.some(c=>c.type==='admission'))});
test('lease extension cannot resurrect expired authority',async()=>{const f=fixture();f.row.lease_expires_at=String(NOW);await assert.rejects(f.store.extendLease({...f.witness}),/lease_unavailable/)});
test('lease duration is bounded',async()=>{const f=fixture();await assert.rejects(f.store.extendLease({...f.witness,leaseMs:999999999}),/invalid_worker_config/)});
test('redaction preserves only known operational codes',()=>{assert.equal(safeProcessingCode('transaction_conflict'),'transaction_conflict');assert.equal(safeProcessingCode('provider raw phone'),'processing_unavailable')});
