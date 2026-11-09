import test from 'node:test';import assert from 'node:assert/strict';
import {allocationFixture,connectAllocationFlow,ids} from './posting-allocation-fixture.mjs';
import {postingPreparationIdentity,postingEvidenceDescriptor} from '../../domain/burimunsi/posting-preparation.js';
import {PostgresPostingAllocation} from '../../domain/burimunsi/postgres-posting-allocation.js';
const denied=e=>e.code==='posting_allocation_unavailable'&&e.status===503&&!e.cause;
for(const mode of ['automatic','exception']){
 test('actual allocation + custody + shared posting execute in one fixture transaction: '+mode,async()=>{
  const f=await allocationFixture(mode);try{await f.run();const p=f.sqlite.prepare('SELECT * FROM app.payments').get();
   assert.equal(p.id,f.identity.paymentId);assert.equal(p.evidence_id,f.identity.evidenceId);assert.equal(p.member_id,ids.member);
   assert.equal(p.amount_minor,12500);assert.equal(p.payer_display_name,'EXAMPLE PAYER');assert.equal(p.status,'reconciled');assert.equal(p.intent_id,null);
   assert.equal(f.sqlite.prepare('SELECT count(*) n FROM app.ledger_entries').get().n,1);
   assert.equal(f.sqlite.prepare('SELECT count(*) n FROM app.contribution_posting_snapshots').get().n,1);
   assert.equal(f.sqlite.prepare('SELECT count(*) n FROM app.notification_events').get().n,1);
   assert.equal(f.sqlite.prepare('SELECT linked_by FROM app.momo_financial_links').get().linked_by,ids.otherActor);
   assert.equal(f.state.allocationCalls,0,'old simulated allocator must not be called');assert.equal(f.state.allocationWrites,4);
  }finally{f.close();}
 });
 test('actual canonical service flow returns durable result: '+mode,async()=>{
  const f=connectAllocationFlow(await allocationFixture(mode));try{const call=mode==='automatic'?f.auto:f.allocate;
   const result=await call();assert.equal(result.memberId,ids.member);assert.equal(result.groupBalanceRwf,12500);const before=f.snapshot();
   assert.deepEqual(await call(),result);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationWrites,4);
  }finally{f.close();}
 });
 test('lost COMMIT reply reconciles without repeating allocation: '+mode,async()=>{
  const f=connectAllocationFlow(await allocationFixture(mode));try{const call=mode==='automatic'?f.auto:f.allocate;f.state.commitReplyLost=true;
   await assert.rejects(call(),/lost commit reply/);const before=f.snapshot();assert.equal((await call()).amountRwf,12500);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationWrites,4);
  }finally{f.close();}
 });
}
test('allocator prepares existing record types, but does not itself write a ledger or commit for its caller',async()=>{
 const f=await allocationFixture();try{await f.runAllocation();assert.equal(f.sqlite.prepare('SELECT count(*) n FROM app.ledger_entries').get().n,0);
  assert.equal(f.sqlite.prepare('SELECT allocation_state FROM app.momo_transactions').get().allocation_state,'linked');
  assert.equal(f.state.queries.some(q=>/^(?:BEGIN|COMMIT|ROLLBACK|SET ROLE|CREATE)/i.test(q.text)),false);
 }finally{f.close();}
});
for(const boundary of [0,1,2,3])test('allocation failure at write '+boundary+' rolls back all financial rows',async()=>{
 const f=await allocationFixture();try{f.state.failAllocationAt=boundary;const before=f.snapshot();await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
for(const boundary of [0,1,2,3,4,5,6])test('shared-posting failure at statement '+boundary+' rolls back the real allocator',async()=>{
 const f=await allocationFixture();try{f.state.failAt=boundary;const before=f.snapshot();await assert.rejects(f.run(),/injected/);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
const sourceFailures=[
 ['missing source','DELETE FROM app.sms_receipts'],['ambiguous source',"INSERT INTO app.momo_transaction_sources SELECT * FROM app.momo_transaction_sources"],
 ['inactive scope','UPDATE private.burimunsi_scopes SET enabled=0'],['wrong scope wallet',"UPDATE private.burimunsi_scopes SET receiving_account_id='other'"],
 ['scope version','UPDATE private.burimunsi_scopes SET version=0'],['source version','UPDATE app.momo_transactions SET version=4'],
 ['wrong source wallet',"UPDATE app.momo_transactions SET receiving_account_id='other'"],['wrong source binding',"UPDATE private.burimunsi_transaction_scopes SET source_binding_id='other'"],
 ['binding version','UPDATE private.burimunsi_transaction_scopes SET source_binding_version=3'],['conflict','UPDATE app.momo_transactions SET has_conflict=1'],
 ['observation conflict',"INSERT INTO app.momo_transaction_sources VALUES('transaction-1','x','x','conflict')"],
 ['not incoming',"UPDATE app.momo_transactions SET event_kind='outgoing'"],['historical',"UPDATE app.momo_transactions SET mode='historical'"],
 ['not unallocated',"UPDATE app.momo_transactions SET allocation_state='needs_review'"],['amount','UPDATE app.momo_transactions SET amount_minor=1'],
 ['currency',"UPDATE app.momo_transactions SET currency='USD'"],['provider',"UPDATE app.momo_transactions SET provider='airtel_money'"],
 ['reference',"UPDATE app.momo_transactions SET provider_transaction_id='FT999'"],['inactive wallet',"UPDATE app.momo_receiving_accounts SET status='disabled'"],
 ['unapproved profile',"UPDATE app.momo_receiving_accounts SET profile_status='unverified'"],['empty profile version',"UPDATE app.momo_receiving_accounts SET profile_version=''"],
 ['inactive group',"UPDATE app.collections SET status='closed'"],['group revision','UPDATE app.collections SET revision=0'],
 ['route mismatch',"UPDATE app.collections SET receiver_momo_number='+250780000002'"],['invalid wallet route',"UPDATE app.momo_receiving_accounts SET public_code='garbage'"],
 ['network mismatch',"UPDATE app.collections SET receiver_network='airtel_money'"],['inactive member','UPDATE app.memberships SET active=0'],
 ['changed member revision','UPDATE app.memberships SET revision=2'],['disabled user',"UPDATE app.users SET access_status='disabled'"],
 ['operator beneficiary',"UPDATE app.users SET member_type='operator'"],['missing member type','UPDATE app.users SET member_type=NULL'],
 ['user revision','UPDATE app.users SET revision=0'],['policy version',"UPDATE private.burimunsi_transaction_scopes SET policy_version='changed'"],
 ['parse digest',"UPDATE app.momo_parse_attempts SET source_body_sha256='bad'"],['parse failed',"UPDATE app.momo_parse_attempts SET outcome='needs_review'"],
 ['wrong original parse',"UPDATE app.momo_transactions SET parse_attempt_id='wrong'"],['missing provider and capture times','UPDATE app.momo_transactions SET transaction_at=NULL,created_at=NULL'],
 ['bad payer type',"UPDATE app.momo_transactions SET payer_name=X'FF'"]
];
for(const [name,sql] of sourceFailures)test('allocation refuses source condition: '+name,async()=>{
 const f=await allocationFixture();try{f.sqlite.exec(sql);const before=f.snapshot();await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationWrites,0);}finally{f.close();}
});
for(const ref of ['FT100','wallet-1:FT100'])for(const status of ['recorded','reversed','orphan'])test('existing wallet reference prevents another allocation: '+ref+'/'+status,async()=>{
 const f=await allocationFixture();try{
  f.sqlite.prepare('INSERT INTO app.payment_evidence(id,external_reference,receiver_network,receiver_momo_number,currency) VALUES(?,?,?,?,?)').run('prior-evidence',ref,'mtn_momo','0780000001','RWF');
  if(status!=='orphan')f.sqlite.prepare('INSERT INTO app.payments(id,evidence_id,status) VALUES(?,?,?)').run('prior-payment','prior-evidence',status);
  const before=f.snapshot();await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);
 }finally{f.close();}
});
for(const other of ['wallet','provider'])test('different '+other+' does not collide with a reference',async()=>{
 const f=await allocationFixture();try{
  f.sqlite.prepare('INSERT INTO app.payment_evidence(id,external_reference,receiver_network,receiver_momo_number,currency) VALUES(?,?,?,?,?)').run('other-evidence','FT100',other==='provider'?'airtel_money':'mtn_momo',other==='wallet'?'0780000002':'0780000001','RWF');
  await f.run();assert.equal(f.sqlite.prepare('SELECT count(*) n FROM app.ledger_entries').get().n,1);
 }finally{f.close();}
});
const journalFailures=[
 ['missing evidence',"DELETE FROM private.storage_payload_reservations WHERE object_key LIKE 'evidence/%'"],
 ['scrubbed body',"UPDATE private.storage_payload_reservations SET sealed_body=NULL WHERE object_key LIKE 'evidence/%'"],
 ['pending put',"UPDATE private.storage_put_intents SET state='pending' WHERE object_key LIKE 'evidence/%'"],
 ['uncertain put',"UPDATE private.storage_put_intents SET upload_unresolved=1 WHERE object_key LIKE 'evidence/%'"],
 ['active put',"UPDATE private.storage_put_intents SET active_attempt='inflight' WHERE object_key LIKE 'evidence/%'"],
 ['tombstone',"UPDATE private.storage_put_intents SET delete_tombstone=1 WHERE object_key LIKE 'evidence/%'"],
 ['delete intent',"INSERT INTO private.storage_delete_intents SELECT object_key,'delete' FROM private.storage_objects WHERE object_key LIKE 'evidence/%'"],
 ['wrong namespace',"UPDATE private.storage_namespace SET origin='https://other.test'"],
 ['wrong digest',"UPDATE private.storage_payload_reservations SET plaintext_sha256='bad' WHERE object_key LIKE 'evidence/%'"],
 ['wrong command binding',"UPDATE private.storage_payload_reservations SET source_fingerprint='bad' WHERE object_key LIKE 'evidence/%'"],
 ['changed ciphertext',"UPDATE private.storage_payload_reservations SET sealed_body='bad' WHERE object_key LIKE 'evidence/%'"],
 ['wrong scope',"UPDATE private.storage_objects SET scope='{}' WHERE object_key LIKE 'evidence/%'"],
 ['wrong authenticated context',"UPDATE private.storage_payload_reservations SET aad='wrong' WHERE object_key LIKE 'evidence/%'"],
 ['mismatched cipher size',"UPDATE private.storage_objects SET size=1 WHERE object_key LIKE 'evidence/%'"],
 ['missing namespace','DELETE FROM private.storage_namespace']
];
for(const [name,sql]of journalFailures)test('allocation refuses prepared evidence: '+name,async()=>{
 const f=await allocationFixture();try{f.sqlite.exec(sql);const before=f.snapshot();await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationWrites,0);}finally{f.close();}
});
test('prepared evidence owner retention barrier refuses allocation',async()=>{
 const f=await allocationFixture();try{f.sqlite.prepare('INSERT INTO app.privacy_retention_barriers VALUES(?)').run(ids.otherActor);const before=f.snapshot();await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
for(const change of ['request','member','principal','session','reason','amount','policy'])test('prepared object cannot transfer to changed '+change,async()=>{
 const f=await allocationFixture(change==='reason'?'exception':'automatic');try{
  if(change==='request')f.command.requestId='22222222-2222-4222-8222-222222222222';
  if(change==='member')f.command.memberId='other-member';
  if(change==='principal')f.state.onAuthority=(_phase,p)=>p.principalUserId='other-principal';
  if(change==='session')f.state.onAuthority=(_phase,p)=>p.principalSessionId='22222222-2222-4222-8222-222222222222';
  if(change==='reason')f.command.reason='A different verified reason';
  if(change==='amount')f.command.receipt.amountRwf=500;
  if(change==='policy')f.command.policyVersion='changed';
  const before=f.snapshot();await assert.rejects(f.run());assert.deepEqual(f.snapshot(),before);
 }finally{f.close();}
});
test('after-await source mutation is rechecked and rolls back',async()=>{
 const f=await allocationFixture();try{const before=f.snapshot(),decrypt=f.custody.decrypt;
  f.custody.decrypt=async(...args)=>{const value=await decrypt(...args);f.sqlite.exec('UPDATE app.memberships SET revision=2');return value;};
  await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationWrites,0);
 }finally{f.close();}
});
test('replacement admission after an allocation write causes rollback',async()=>{
 const f=await allocationFixture();try{const before=f.snapshot();f.state.afterQuery=text=>{if(text.startsWith('INSERT INTO app.payments'))f.db.applicationWork={assert:async()=>{}};};
  await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);
 }finally{f.close();}
});
test('full custody failure rolls back all four real allocation writes',async()=>{
 const f=await allocationFixture();try{f.sqlite.exec("UPDATE app.momo_gateway_credentials SET revoked_at='revoked'");const before=f.snapshot();
  await assert.rejects(f.run(),e=>e.code==='posting_evidence_unavailable');assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationWrites,4);
 }finally{f.close();}
});
for(const kind of ['receipt','lease','principal'])test('late '+kind+' failure rolls back allocation and ledger',async()=>{
 const f=connectAllocationFlow(await allocationFixture(kind==='receipt'?'exception':'automatic'));try{const before=f.snapshot();
  if(kind==='receipt')f.state.failCommandReceipt=true;
  else f.state.onAuthority=(phase,p)=>{if(phase==='after_posting'){if(kind==='lease')f.state.leaseLost=true;else p.principalUserId='replacement';}};
  await assert.rejects(kind==='receipt'?f.allocate():f.auto());assert.deepEqual(f.snapshot(),before);
 }finally{f.close();}
});
test('stable preparation identity excludes only worker lease churn, not target or authority',async()=>{
 const f=await allocationFixture();try{const a=await postingPreparationIdentity(f.command,f.principal),c=structuredClone(f.command);
  c.work.owner='new-worker';c.work.leaseVersion=200;assert.deepEqual(await postingPreparationIdentity(c,f.principal),a);
  assert(Object.isFrozen(a)&&Object.isFrozen(a.target)&&Object.isFrozen(a.target.identityIds));assert.notEqual(a.paymentId,a.evidenceId);
  assert.match(a.paymentId,/^[a-f0-9]{8}-[a-f0-9]{4}-8[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
  const d=postingEvidenceDescriptor(a,'a'.repeat(64),'key-2');assert.equal(d.requestDigest,a.requestDigest);assert(Object.isFrozen(d.scope));
 }finally{f.close();}
});
test('preparation snapshots caller values before awaiting hashes',async()=>{
 const f=await allocationFixture();try{const c=structuredClone(f.command),p=structuredClone(f.principal);const promise=postingPreparationIdentity(c,p);
  c.memberId='replaced';p.principalUserId='replaced';assert.deepEqual(await promise,f.identity);
 }finally{f.close();}
});
test('allocator requires the concrete custody instance for the same request',async()=>{
 const f=await allocationFixture();try{assert.throws(()=>new PostgresPostingAllocation({db:f.db,groupId:ids.group,custody:{journal:async()=>({})}}));
  assert.throws(()=>new PostgresPostingAllocation({db:f.db,groupId:'another',custody:f.custody}));
 }finally{f.close();}
});

test('internally consistent journal cannot replace the expected command fingerprint',async()=>{
 const f=await allocationFixture();try{const fingerprint='f'.repeat(64),key=f.identity.objectKey;
  f.sqlite.prepare('UPDATE private.storage_payload_reservations SET source_fingerprint=? WHERE object_key=?').run(fingerprint,key);
  for(const table of ['storage_put_intents','storage_objects']){
   const metadata=JSON.parse(f.sqlite.prepare(`SELECT custom_metadata FROM private.${table} WHERE object_key=?`).get(key).custom_metadata);
   metadata.source_fingerprint=fingerprint;f.sqlite.prepare(`UPDATE private.${table} SET custom_metadata=? WHERE object_key=?`).run(JSON.stringify(metadata),key);
  }
  const before=f.snapshot();await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.allocationWrites,0);
 }finally{f.close();}
});
for(const field of ['evidence','payment','link','version'])test('incorrect RETURNING '+field+' result causes rollback',async()=>{
 const f=await allocationFixture();try{const before=f.snapshot();f.state.afterQuery=(text,_values,rows)=>{
  const hit=field==='evidence'&&text.startsWith('INSERT INTO app.payment_evidence')||field==='payment'&&text.startsWith('INSERT INTO app.payments')||field==='link'&&text.startsWith('INSERT INTO app.momo_financial_links')||field==='version'&&text.startsWith('UPDATE app.momo_transactions');
  if(hit)rows.splice(0);
 };await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
test('allocation never reveals protected data through its public error',async()=>{
 const f=await allocationFixture();try{f.custody.decrypt=async()=>{throw Error('DO_NOT_EXPOSE_KEY_OR_MESSAGE');};
  await assert.rejects(f.run(),e=>denied(e)&&!JSON.stringify(e).includes('DO_NOT_EXPOSE')&&!e.stack.includes('DO_NOT_EXPOSE'));
 }finally{f.close();}
});
test('known source creation time is used when provider time is absent, without inventing a provider timestamp',async()=>{
 const f=await allocationFixture();try{f.sqlite.exec('UPDATE app.momo_transactions SET transaction_at=NULL');await f.run();
  assert.equal(f.sqlite.prepare('SELECT observed_at FROM app.payment_evidence').get().observed_at,'2026-11-07T08:00:01.000Z');
  assert.equal(f.sqlite.prepare('SELECT transaction_at FROM app.momo_transactions').get().transaction_at,null);
 }finally{f.close();}
});
test('unrequested payment intent linking is refused',async()=>{const f=await allocationFixture();try{f.command.intentId=ids.intent;const before=f.snapshot();await assert.rejects(f.run(),denied);assert.deepEqual(f.snapshot(),before);}finally{f.close();}});
