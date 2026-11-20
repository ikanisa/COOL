import test from 'node:test';import assert from 'node:assert/strict';
import {postingFixture,ids} from './posting-executor-fixture.mjs';
import {PostgresSharedPosting} from '../../domain/burimunsi/postgres-shared-posting.js';
for(const mode of ['automatic','exception'])test('shared posting executor writes canonical ledger/snapshot/notice/audit without review: '+mode,async()=>{
 const f=postingFixture(mode);try{
  assert.equal(await f.run(),undefined); // caller still owns verified final result
  assert.deepEqual(f.state.phases,['before_allocation','after_allocation','before_posting','after_posting']);
  const p=f.sqlite.prepare('SELECT * FROM app.payments').get();assert.equal(p.member_id,ids.member);assert.equal(p.status,'reconciled');assert.equal(p.revision,8);
  const l=f.sqlite.prepare('SELECT * FROM app.ledger_entries').get();assert.equal(l.amount_minor,12500);assert.equal(l.actor_user_id,ids.otherActor);assert.equal(l.request_id,ids.request);
  const s=f.sqlite.prepare('SELECT * FROM app.contribution_posting_snapshots').get();assert.equal(s.member_balance_after_minor,12500);assert.equal(s.group_balance_after_minor,12500);
  assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.reconciliations').get().n,0);
  assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.notification_events').get().n,1);
  assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.audit_log').get().n,1);
  assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.admin_bridge_guards').get().n,0);
  assert.equal(f.sqlite.prepare('SELECT status FROM app.payment_intents').get().status,'matched');
 }finally{f.close();}
});
const invalid=[
 ['wrong source wallet',"UPDATE app.momo_transactions SET receiving_account_id='other'"],
 ['wrong evidence group',"UPDATE app.payment_evidence SET collection_id='other'"],
 ['source conflict','UPDATE app.momo_transactions SET has_conflict=1'],
 ['historical source',"UPDATE app.momo_transactions SET mode='historical'"],
 ['historical adoption','UPDATE app.momo_financial_links SET historical_existing=1'],
 ['wrong beneficiary',"UPDATE app.momo_financial_links SET beneficiary_member_id='other'"],
 ['previous member',"UPDATE app.payments SET member_id='other'"],
 ['corrected payment',"UPDATE app.payments SET status='corrected'"],
 ['reversed payment',"UPDATE app.payments SET status='reversed'"],
 ['wrong rail',"UPDATE app.payments SET rail='cash'"],
 ['wrong evidence amount','UPDATE app.payment_evidence SET amount_minor=10'],
 ['wrong source amount','UPDATE app.momo_transactions SET amount_minor=10'],
 ['wrong payment amount','UPDATE app.payments SET amount_minor=10'],
 ['wrong currency',"UPDATE app.payment_evidence SET currency='USD'"],
 ['wrong source kind',"UPDATE app.momo_transactions SET event_kind='outgoing'"],
 ['scope disabled','UPDATE private.burimunsi_scopes SET enabled=false'],
 ['unapproved profile',"UPDATE app.momo_receiving_accounts SET profile_status='unverified'"],
 ['inactive wallet',"UPDATE app.momo_receiving_accounts SET status='inactive'"],
 ['wrong provider',"UPDATE app.momo_receiving_accounts SET provider='airtel_money'"],
 ['inactive group',"UPDATE app.collections SET status='inactive'"],
 ['inactive member','UPDATE app.memberships SET active=0'],
 ['suspended person',"UPDATE app.users SET access_status='suspended'"],
 ['different route',"UPDATE app.payment_evidence SET receiver_momo_number='0780000002'"],
 ['malformed route',"UPDATE app.payment_evidence SET receiver_momo_number='please pay 0780000001'"],
 ['different FT id',"UPDATE app.payment_evidence SET external_reference='FT999'"],
 ['empty reference',"UPDATE app.momo_transactions SET provider_transaction_id=''"],
 ['evidence hash missing',"UPDATE app.payment_evidence SET object_sha256=''"],
 ['evidence size missing','UPDATE app.payment_evidence SET size_bytes=NULL'],
 ['different binding',"UPDATE private.burimunsi_transaction_scopes SET source_binding_id='other'"],
 ['different binding version','UPDATE private.burimunsi_transaction_scopes SET source_binding_version=8'],
 ['different identity policy',"UPDATE private.burimunsi_transaction_scopes SET policy_version='new-policy'"],
 ['changed version','UPDATE app.momo_transactions SET version=50'],
 ['existing ledger',`INSERT INTO app.ledger_entries(id,payment_id,kind) VALUES('existing','${ids.payment}','correction')`],
 ['existing snapshot',`INSERT INTO app.contribution_posting_snapshots(ledger_entry_id,payment_id) VALUES('existing','${ids.payment}')`]
];
for(const[label,change]of invalid)test('executor rejects '+label+' and rolls back allocation',async()=>{
 const f=postingFixture();try{const before=f.snapshot();f.state.afterAllocation=()=>f.sqlite.exec(change);await assert.rejects(f.run());assert.deepEqual(f.snapshot(),before);assert.equal(f.state.statements.length,0);}finally{f.close();}
});
for(const stage of ['before_allocation','after_allocation','before_posting','after_posting'])test('authority failure rolls back at '+stage,async()=>{
 const f=postingFixture();try{const before=f.snapshot();f.state.onAuthority=(phase)=>{if(phase===stage)throw Error('authority revoked')};await assert.rejects(f.run(),/authority revoked/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
for(const field of ['actorId','sessionId','principalUserId','principalSessionId','mode','requestId','groupId','receiptId','kind','policyVersion'])test('authority binding change rejected: '+field,async()=>{
 const f=postingFixture();try{const before=f.snapshot();f.state.onAuthority=(phase,a)=>{if(phase==='after_allocation')a[field]=field.endsWith('Id')?ids.evidence:'different';};await assert.rejects(f.run());assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
for(const proof of [null,false,{}, {verified:false}, {verified:'true'}])test('no missing evidence proof fallback '+JSON.stringify(proof),async()=>{
 const f=postingFixture();try{const before=f.snapshot();f.evidence.assertInTransaction=async()=>proof;await assert.rejects(f.run(),/posting_evidence_required/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
test('evidence-await record mutation cannot retain the old proof',async()=>{
 const f=postingFixture();try{const before=f.snapshot();f.state.onProof=()=>{f.sqlite.exec("UPDATE app.payment_evidence SET object_key='evidence/replaced'");return {verified:true};};await assert.rejects(f.run(),/posting_record_changed/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
test('replacement admission while its assertion awaits aborts before allocation',async()=>{
 const f=postingFixture();try{f.db.applicationWork.assert=async()=>{await Promise.resolve();f.db.applicationWork={assert:async()=>{}}};await assert.rejects(f.run(),/request_not_admitted/);assert.equal(f.state.allocationCalls,0);}finally{f.close();}
});
test('caller mutation after the first await cannot reassign a posting',async()=>{
 const f=postingFixture();try{f.state.onAuthority=phase=>{if(phase==='before_allocation'){f.command.memberId='other';f.command.receipt.amountRwf=2;f.command.work.leaseVersion=99;}};await f.run();assert.equal(f.sqlite.prepare('SELECT member_id FROM app.payments').get().member_id,ids.member);}finally{f.close();}
});
let length;{const f=postingFixture();try{await f.run();length=f.state.statements.length;}finally{f.close();}}
for(let i=0;i<length;i++)test('statement failure '+i+' rolls back posting AND allocation',async()=>{
 const f=postingFixture();try{const before=f.snapshot();f.state.failAt=i;await assert.rejects(f.run(),/injected statement failure/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
test('new executor does not run an independent transaction or return an acknowledgement',async()=>{
 const f=postingFixture();try{await f.run();assert(f.state.queries.every(q=>!/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(q.text)));assert(f.state.statements.every(q=>!/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(q.sql)));}finally{f.close();}
});
for(const missing of ['runtime','allocation','evidence','prepare','statement'])test('missing mandatory writer integration: '+missing,()=>{
 const f=postingFixture();try{const o={db:f.db,groupId:ids.group,runtime:f.runtime,allocation:f.allocation,evidence:f.evidence};if(['prepare','statement'].includes(missing))delete o.db[missing];else delete o[missing];assert.throws(()=>new PostgresSharedPosting(o),/collect_adapter_required/);}finally{f.close();}
});
test('replaying the completed command does not add a second contribution',async()=>{
 const f=postingFixture();try{await f.run();const before=f.snapshot();await assert.rejects(f.run());assert.deepEqual(f.snapshot(),before);assert.equal(f.sqlite.prepare('SELECT count(*) AS n FROM app.ledger_entries').get().n,1);}finally{f.close();}
});

for(const ref of ['FT100','wallet-1:FT100'])for(const status of ['recorded','reconciled','reversed'])test('other economic reference is refused even if reversed: '+ref+' '+status,async()=>{
 const f=postingFixture();try{
  f.sqlite.prepare('INSERT INTO app.payment_evidence(id,external_reference,receiver_network,receiver_momo_number,currency) VALUES(?,?,?,?,?)').run('prior-evidence',ref,'mtn_momo','250780000001','RWF');
  f.sqlite.prepare('INSERT INTO app.payments(id,evidence_id,status) VALUES(?,?,?)').run('prior-payment','prior-evidence',status);
  const before=f.snapshot();await assert.rejects(f.run(),/posting_record_invalid/);assert.deepEqual(f.snapshot(),before);
 }finally{f.close();}
});
test('native operator identity cannot masquerade as the canonical principal',async()=>{
 const f=postingFixture('exception');try{const before=f.snapshot();f.state.onAuthority=(_phase,a)=>{a.principalUserId=ids.actor;};await assert.rejects(f.run(),/session_unavailable/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
