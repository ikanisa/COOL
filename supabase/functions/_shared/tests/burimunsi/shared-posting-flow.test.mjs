/** Actual service + canonical adapter + shared executor + SQL on TEST SQLite.
 * No production authority/custody bridge, PostgreSQL locks/RLS or carrier runs. */
import test from 'node:test';import assert from 'node:assert/strict';
import {postingFixture,ids} from './posting-executor-fixture.mjs';
import {PostgresCanonicalStore} from '../../domain/burimunsi/postgres-canonical-store.js';
import {ContributionService} from '../../domain/burimunsi/contribution-service.js';
function flow(){
 const f=postingFixture();f.sqlite.exec(`ALTER TABLE private.burimunsi_scopes ADD COLUMN version INTEGER DEFAULT 1;
 ALTER TABLE app.momo_transactions ADD COLUMN transaction_at TEXT DEFAULT '2026-11-07T00:00:00.000Z';
 ALTER TABLE app.momo_transactions ADD COLUMN payer_identifier TEXT DEFAULT '+250780000001';
 ALTER TABLE app.momo_transactions ADD COLUMN payer_name TEXT DEFAULT 'EXAMPLE PERSON';
 ALTER TABLE app.memberships ADD COLUMN revision INTEGER DEFAULT 1;
 CREATE TABLE app.momo_transaction_sources(transaction_id TEXT,relation TEXT);
 CREATE TABLE private.burimunsi_command_receipts(collection_id TEXT,actor_id TEXT,request_id TEXT,session_id TEXT,
  operation TEXT,fingerprint TEXT,response TEXT,created_at INTEGER,PRIMARY KEY(collection_id,actor_id,request_id));`);
 Object.assign(f.state,{failCommandReceipt:false,commitReplyLost:false,leaseLost:false});
 f.sql.unsafe=async(text,values=[])=>{
  if(f.state.failCommandReceipt&&text.includes('INSERT INTO private.burimunsi_command_receipts'))throw Error('command receipt failure');
  const params=[];const compiled=text.replace(/ FOR UPDATE(?: OF [a-z,]+)?\s*$/,'').replace(/\$(\d+)(?:::uuid|::jsonb)?/g,(_s,n)=>{const v=values[Number(n)-1];params.push(v&&typeof v==='object'?JSON.stringify(v):v);return '?';});
  return f.sqlite.prepare(compiled).all(...params).map(r=>{
   const row={...r};for(const k of ['has_entries','has_snapshot','has_other_reference','has_compensation','source_conflict','enabled'])if(k in row)row[k]=Boolean(row[k]);
   if('response'in row)row.response=JSON.parse(row.response);return row;
  });
 };
 f.actor={id:ids.actor,sessionId:ids.session,principalUserId:ids.otherActor,groupId:ids.group,role:'staff',active:true,
  expiresAt:9999999999999,capabilities:['records.read','payments.allocate','members.enroll']};
 const authority={groupId:ids.group,session:async()=>f.actor,write:async fn=>{
  f.sqlite.exec('BEGIN');let committed=false;
  try{const result=await fn(f.sql);f.sqlite.exec('COMMIT');committed=true;
   if(f.state.commitReplyLost){f.state.commitReplyLost=false;throw Error('lost commit reply');}return result;
  }catch(e){if(!committed)f.sqlite.exec('ROLLBACK');throw e;}
 }};
 f.identities=[{id:'identity-1',memberId:ids.member,groupId:ids.group,status:'verified',authority:'collect_verified',purpose:'own_contributions',
  phone:'+250780000001',validFrom:'2026-01-01T00:00:00.000Z',validUntil:null}];
 const identities={policy:async()=>({groupId:ids.group,approvedVersion:'verified-test-v1',fullIdentityEnabled:true}),
  members:async()=>[{id:ids.member,groupId:ids.group,active:true,eligible:true}],verified:async()=>f.identities};
 const commands={postContribution:(...args)=>f.writer.postContribution(...args),createDirectMember:async()=>{throw Error('not this fixture')},setMembershipActive:async()=>{throw Error('not this fixture')},enqueueEligibleRematch:async()=>{throw Error('not this fixture')}};
 const jobs={assertPostingLease:async()=>{if(f.state.leaseLost)throw Error('lease lost')}};
 f.store=new PostgresCanonicalStore({authority,commands,identities,jobs});f.service=new ContributionService({store:f.store,groupId:ids.group});
 f.allocate=()=>f.service.allocate(f.actor,{transactionId:f.command.receiptId,memberId:ids.member,expectedVersion:3,note:'Verified original source and identity',requestId:ids.request});
 f.auto=()=>f.service.automaticallyAllocate(f.command.receiptId,ids.request,f.command.work);
 return f;
}
test('automatic orchestration executes real shared SQL and returns canonical snapshot',async()=>{
 const f=flow();try{const r=await f.auto();assert.equal(r.memberId,ids.member);assert.equal(r.amountRwf,12500);assert.equal(r.memberBalanceRwf,12500);assert.equal(r.groupBalanceRwf,12500);assert.equal(f.state.allocationCalls,1);}finally{f.close();}
});
test('conflicting source prevents automatic posting without changing the ledger',async()=>{
 const f=flow();try{
  f.sqlite.prepare('INSERT INTO app.momo_transaction_sources(transaction_id,relation) VALUES(?,?)').run(f.command.receiptId,'conflict');
  await assert.rejects(f.auto(),/transaction_unavailable/);assert.equal(f.state.allocationCalls,0);
  assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.ledger_entries').get().n,0);
 }finally{f.close();}
});
test('a conflict arriving after posting prevents an automatic replay from reporting clean success',async()=>{
 const f=flow();try{
  await f.auto();const before=f.sqlite.prepare('SELECT count(*) AS n FROM app.ledger_entries').get().n;
  f.sqlite.prepare('INSERT INTO app.momo_transaction_sources(transaction_id,relation) VALUES(?,?)').run(f.command.receiptId,'conflict');
  await assert.rejects(f.auto(),/transaction_unavailable/);
  assert.equal(f.state.allocationCalls,1);assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.ledger_entries').get().n,before);
 }finally{f.close();}
});
test('automatic retry reads the original result without invoking allocation/posting twice',async()=>{
 const f=flow();try{const a=await f.auto(),before=f.snapshot(),b=await f.auto();assert.deepEqual(a,b);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationCalls,1);}finally{f.close();}
});
test('exception allocation, posting and durable response share one actual fixture transaction',async()=>{
 const f=flow();try{const a=await f.allocate(),before=f.snapshot(),b=await f.allocate();assert.deepEqual(a,b);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationCalls,1);assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM private.burimunsi_command_receipts').get().n,1);}finally{f.close();}
});
test('changed exception replay does not create a second effect',async()=>{
 const f=flow();try{await f.allocate();const before=f.snapshot();await assert.rejects(f.service.allocate(f.actor,{transactionId:f.command.receiptId,memberId:ids.member,expectedVersion:3,note:'A different identity statement',requestId:ids.request}),/idempotency_conflict/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
test('durable command receipt failure rolls back allocation, ledger, snapshot, audit and notification',async()=>{
 const f=flow();try{const before=f.snapshot();f.state.failCommandReceipt=true;await assert.rejects(f.allocate(),/command receipt failure/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
test('late worker lease loss rolls back the complete financial callback',async()=>{
 const f=flow();try{const before=f.snapshot();f.state.onAuthority=phase=>{if(phase==='after_posting')f.state.leaseLost=true;};await assert.rejects(f.auto(),/lease lost/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
test('session revocation after posting rolls back the exception callback',async()=>{
 const f=flow();try{const before=f.snapshot();f.state.onAuthority=phase=>{if(phase==='after_posting')f.actor={...f.actor,active:false};};await assert.rejects(f.allocate(),/session_unavailable/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
for(const kind of ['automatic','exception'])test('lost commit reply reconciles durable '+kind+' result instead of double posting',async()=>{
 const f=flow();try{f.state.commitReplyLost=true;const call=kind==='automatic'?f.auto:f.allocate;await assert.rejects(call(),/lost commit reply/);const before=f.snapshot(),r=await call();assert.equal(r.amountRwf,12500);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationCalls,1);}finally{f.close();}
});
test('ambiguous verified owners keep the actual stored receipt unallocated',async()=>{
 const f=flow();try{f.identities.push({...f.identities[0],id:'competing-proof',memberId:'other-member'});const before=f.snapshot();const r=await f.auto();assert.equal(r.reason,'ambiguous_identity');assert.equal(f.state.allocationCalls,0);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
test('canonical readback corruption rejects otherwise completed shared SQL',async()=>{
 const f=flow();try{const before=f.snapshot();f.state.onAuthority=phase=>{if(phase==='after_posting')f.sqlite.exec("UPDATE app.ledger_entries SET evidence_id='wrong-evidence'")};await assert.rejects(f.auto(),/canonical_writer_contract_violation/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
