/** Synthetic SQLite/lease/storage HTTP fixture. Real source and job-store code,
 * Storage GET implementation/transport/protocol and AES-GCM are executed.
 * PostgreSQL RLS, row locks and a real worker credential are NOT qualified. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {storageWitnessFixture} from './storage-witness-fixture.mjs';
import {PostgresRetainedSources} from '../../domain/burimunsi/postgres-retained-sources.js';
import {PostgresReceiptJobStore} from '../../domain/burimunsi/postgres-receipt-job-store.js';
import {receiptFingerprint,transactionKey,parseReceipt} from '../../domain/burimunsi/receipt.js';
const body='You have received 12,500 RWF from EXAMPLE PAYER (0780000001) at 2026-11-07 10:00:00. Balance: 30,000 RWF. FT Id: 123456.';
async function fixture(){
  const f=await storageWitnessFixture('automatic',body),s=f.sqlite;
  s.exec(`ALTER TABLE private.burimunsi_scopes ADD COLUMN active_binding_id TEXT DEFAULT 'binding-1';
    ALTER TABLE private.burimunsi_scopes ADD COLUMN binding_version INTEGER DEFAULT 2;
    CREATE TABLE private.burimunsi_receipt_jobs(id TEXT PRIMARY KEY,collection_id TEXT,state TEXT,lease_owner TEXT,
      lease_version INTEGER,lease_expires_at INTEGER,transaction_id TEXT,updated_at INTEGER);`);
  const sources=new PostgresRetainedSources({db:f.db,groupId:f.command.groupId,namespace:f.media.namespace,
    decrypt:f.custody.decrypt,storageWitnesses:f.storageWitnesses});
  const descriptor=await f.authority.write(sql=>sources.sourceForEnqueue(sql,'raw-1'));
  const job={...descriptor,id:'33333333-3333-4333-8333-333333333333',owner:'worker-1',leaseVersion:1,
    state:'running',transactionId:null,leaseExpiresAt:f.state.now+180000};
  s.prepare('INSERT INTO private.burimunsi_receipt_jobs VALUES(?,?,?,?,?,?,?,?)').run(job.id,job.groupId,'running',job.owner,1,job.leaseExpiresAt,null,f.state.now);
  const profile={version:descriptor.profileVersion,offsetMinutes:120,senders:['M-Money']};
  let ingests=0,leases=0;
  const canonical={ingest:async(sql,input)=>{
    assert.equal(f.state.inTransaction,true);assert.equal((await sources.load(sql,input.job)).body,body);ingests++;
    return {durable:true,transactionId:'transaction-1',groupId:job.groupId,receivingAccountId:job.receivingAccountId};
  },outcome:async()=>{throw Error('not used');}};
  const store=new PostgresReceiptJobStore({authority:f.authority,sources,canonical,
    admission:{assertInTransaction:async()=>({processingEnabled:true,profile})}});
  // This fixture isolates the real preflight/load/commit boundaries. Existing
  // receipt-job-store tests exercise actual SQL lease parsing and predicates.
  store.lease=async(sql,expected)=>{
    assert.equal(f.state.inTransaction,true);leases++;
    assert.equal(expected.jobId,job.id);assert.equal(expected.owner,job.owner);assert.equal(expected.leaseVersion,job.leaseVersion);
    assert.equal(job.state,'running');assert(job.leaseExpiresAt>f.state.now);
    return {job:structuredClone(job),admission:{processingEnabled:true,profile},now:f.state.now};
  };
  store.time=async()=>f.state.now;
  const args={job:structuredClone(job),owner:job.owner,leaseVersion:job.leaseVersion};
  return {...f,sources,job,store,args,profile,ingests:()=>ingests,leases:()=>leases,
    load:()=>store.loadSource(args)};
}
test('worker source is prefetched outside SQL, then revalidated under the same lease',async()=>{
  const f=await fixture();try{
    const source=await f.load();assert.equal(source.body,body);assert.equal(f.leases(),2);
    assert(f.state.storageCalls.some(c=>c.method==='GET'&&c.path.includes('/sms/raw-1')));
    const receipt=parseReceipt(source,f.profile),calls=f.state.storageCalls.length;
    await f.store.commitCanonicalReceipt({...f.args,key:transactionKey(f.job.receivingAccountId,receipt),fingerprint:await receiptFingerprint(receipt)});
    assert.equal(f.ingests(),1);assert.equal(f.state.storageCalls.length,calls,'commit and canonical re-read perform no Storage I/O');
    await assert.rejects(f.sources.load(f.sql,f.job),/source_unavailable/,'completed source step releases its private witness');
  }finally{f.close();}
});
test('raw SQL metadata and a valid digest cannot replace the preflight witness',async()=>{
  const f=await fixture();try{await assert.rejects(f.authority.write(sql=>f.sources.load(sql,f.job)),/source_unavailable/);assert.equal(f.state.storageCalls.length,0);}finally{f.close();}
});
for(const [name,change]of [
  ['lease owner',f=>f.job.owner='replacement'],
  ['lease version',f=>f.job.leaseVersion++],
  ['lease expiry',f=>f.job.leaseExpiresAt=f.state.now],
  ['source group',f=>f.sqlite.exec("UPDATE private.burimunsi_sms_source_scopes SET collection_id='foreign'")],
  ['source proof',f=>f.sqlite.exec("UPDATE private.burimunsi_sms_source_scopes SET proof_sha256='"+'d'.repeat(64)+"'")],
  ['original installation',f=>f.sqlite.exec("UPDATE app.momo_gateway_credentials SET installation_id='another'")],
  ['original custodian',f=>f.sqlite.exec("UPDATE private.burimunsi_accounts SET principal_user_id='another'")],
])test('delayed prefetch cannot inherit changed '+name,async()=>{
  const f=await fixture();try{let fired=false;f.state.onStorage=async()=>{if(!fired){fired=true;await Promise.resolve();change(f);}};
    await assert.rejects(f.load());assert.equal(f.ingests(),0);assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.ledger_entries').get().n,0);
  }finally{f.close();}
});
test('posting cannot use an unassociated source merely because today\'s wallet matches',async()=>{
  const f=await fixture();try{f.sqlite.exec('DELETE FROM private.burimunsi_sms_source_scopes');await assert.rejects(f.prepare());assert.equal(f.state.storageCalls.length,0);}finally{f.close();}
});
