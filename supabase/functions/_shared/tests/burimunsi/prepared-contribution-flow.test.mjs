import test from 'node:test';
import assert from 'node:assert/strict';
import {preparedFlow,ids,count} from './prepared-contribution-fixture.mjs';
import {ContributionService} from '../../domain/burimunsi/contribution-service.js';
import {BuriError} from '../../domain/burimunsi/errors.js';

const call=(f,mode)=>mode==='exception'?f.allocate():f.auto();
for(const mode of ['exception','automatic']) {
  test(mode+' entrypoint prepares and posts without a manual preparation call',async()=>{
    const f=await preparedFlow(mode);try{
      const value=await call(f,mode);
      assert.equal(value.amountRwf,12500);assert.equal(value.memberId,ids.member);
      assert.equal(f.state.puts,1);assert.equal(f.state.plans.length,1);
      for(const t of ['payments','payment_evidence','momo_financial_links','ledger_entries','contribution_posting_snapshots'])assert.equal(count(f,'app.'+t),1,t);
      assert.equal(count(f,'private.burimunsi_command_receipts'),mode==='exception'?1:0);
      assert.equal(f.sqlite.prepare('SELECT amount_minor FROM app.ledger_entries').get().amount_minor,12500);
      assert.equal(f.state.inTransaction,false);
    }finally{f.close();}
  });
  test(mode+' completed replay never prepares or uploads again',async()=>{
    const f=await preparedFlow(mode);try{
      const first=await call(f,mode);f.preparation.prepare=()=>{throw Error('MUST NOT PREPARE');};
      assert.deepEqual(await call(f,mode),first);assert.equal(f.state.puts,1);assert.equal(count(f,'app.ledger_entries'),1);
    }finally{f.close();}
  });
  test(mode+' storage failure cannot become a financial write',async()=>{
    const f=await preparedFlow(mode);try{
      f.media.put=async()=>{throw Error('SECRET provider details');};
      await assert.rejects(call(f,mode),/posting_preparation_unavailable/);
      assert.equal(count(f,'app.payments'),0);assert.equal(count(f,'app.ledger_entries'),0);assert.equal(count(f,'private.burimunsi_command_receipts'),0);
    }finally{f.close();}
  });
  test(mode+' lost provider reply retries with unchanged request and ciphertext',async()=>{
    const f=await preparedFlow(mode);try{
      f.state.afterPut=()=>{throw Error('provider reply lost');};await assert.rejects(call(f,mode),/posting_preparation_unavailable/);
      const before=f.sqlite.prepare("SELECT object_key,sealed_body FROM private.storage_payload_reservations WHERE object_key LIKE 'evidence/%'").get();
      assert.equal(count(f,'app.ledger_entries'),0);f.state.afterPut=null;
      const value=await call(f,mode);assert.equal(value.amountRwf,12500);
      assert.deepEqual(f.sqlite.prepare("SELECT object_key,sealed_body FROM private.storage_payload_reservations WHERE object_key LIKE 'evidence/%'").get(),before);
      assert.equal(f.state.plans[0].requestId,f.state.plans[1].requestId);assert.equal(count(f,'app.ledger_entries'),1);
    }finally{f.close();}
  });
  test(mode+' lost final COMMIT reply is resolved by authorized durable readback',async()=>{
    const f=await preparedFlow(mode);try{
      f.state.beforeFinancial=()=>{f.state.commitLost=true;};
      const result=await call(f,mode);assert.equal(result.amountRwf,12500);assert.equal(f.state.puts,1);
      assert.equal(f.state.plans.length,1);assert.equal(count(f,'app.ledger_entries'),1);
    }finally{f.close();}
  });
  test(mode+' authorization change after evidence storage cannot post',async()=>{
    const f=await preparedFlow(mode);try{
      f.state.afterPreparation=()=>{if(mode==='exception')f.actor.revoked=true;else f.state.leaseLost=true;};
      await assert.rejects(call(f,mode));assert.equal(f.state.puts,1);assert.equal(count(f,'app.ledger_entries'),0);
      assert.equal(count(f,'private.storage_payload_reservations'),2,'stored evidence is not deleted on error');
    }finally{f.close();}
  });
  for(const [name,sql]of [
    ['receipt version',"UPDATE app.momo_transactions SET version=4"],
    ['receipt amount',"UPDATE app.momo_transactions SET amount_minor=25000"],
    ['source binding version',"UPDATE private.burimunsi_transaction_scopes SET source_binding_version=3"],
    ['member revision',"UPDATE app.memberships SET revision=2"],
    ['deactivated member',"UPDATE app.memberships SET active=0"],
    ['conflicting receipt',"UPDATE app.momo_transactions SET has_conflict=1"],
  ])test(mode+' rederivation refuses changed '+name+' after preparation',async()=>{
    const f=await preparedFlow(mode);try{
      f.state.afterPreparation=()=>f.sqlite.exec(sql);await assert.rejects(call(f,mode));
      assert.equal(count(f,'app.ledger_entries'),0);assert.equal(count(f,'app.payments'),0);
    }finally{f.close();}
  });
  for(const at of [0,1,2,3])test(mode+' rollback after allocation write '+at+' keeps evidence but no financial effect',async()=>{
    const f=await preparedFlow(mode);try{
      f.state.failAllocationAt=at;await assert.rejects(call(f,mode));
      for(const t of ['payments','payment_evidence','momo_financial_links','ledger_entries'])assert.equal(count(f,'app.'+t),0);
      assert.equal(count(f,'private.storage_payload_reservations'),2);
      f.state.failAllocationAt=-1;await call(f,mode);assert.equal(count(f,'app.ledger_entries'),1);
    }finally{f.close();}
  });
  for(const phase of ['afterPreparation','afterPut'])test(mode+' coordinated race winner at '+phase+' resolves one ledger effect',async()=>{
    const f=await preparedFlow(mode);try{
      let winner;
      f.state[phase]=async()=>{
        f.state[phase]=null;
        winner=mode==='exception'?await f.withoutPreparation.allocate(f.actor,{
          transactionId:f.command.receiptId,memberId:ids.member,expectedVersion:3,
          note:'Verified original source and identity',requestId:ids.request}):
          await f.withoutPreparation.automaticallyAllocate(f.command.receiptId,ids.request,f.command.work);
      };
      const value=await call(f,mode);assert.deepEqual(value,winner);assert.equal(count(f,'app.ledger_entries'),1);
      assert.equal(count(f,'private.burimunsi_command_receipts'),mode==='exception'?1:0);
    }finally{f.close();}
  });
}
test('exception command planning ignores caller-injected source, actor and object key',async()=>{
  const f=await preparedFlow('exception');try{
    await f.service.allocate({...f.actor,principalUserId:'forged'}, {transactionId:f.command.receiptId,memberId:ids.member,
      expectedVersion:3,note:'Verified original source and identity',requestId:ids.request,
      receipt:{amountRwf:1},actor:{principalUserId:'forged'},objectKey:'attacker/object',mode:'automatic'});
    const c=f.state.plans[0];assert.equal(c.receipt.amountRwf,12500);assert.equal(c.actor.principalUserId,ids.otherActor);
    assert.equal(c.mode,'exception');assert.equal(Object.hasOwn(c,'objectKey'),false);
  }finally{f.close();}
});
test('plan is deeply frozen before asynchronous preparation',async()=>{
 const f=await preparedFlow();try{
  f.state.beforePreparation=c=>{assert(Object.isFrozen(c)&&Object.isFrozen(c.receipt)&&Object.isFrozen(c.member)&&Object.isFrozen(c.work));
    assert.throws(()=>{c.receipt.amountRwf=1;},TypeError);};
  await f.auto();assert.equal(count(f,'app.ledger_entries'),1);
 }finally{f.close();}
});
test('exception request key reused with different input refuses before another upload',async()=>{
 const f=await preparedFlow('exception');try{await f.allocate();
  await assert.rejects(f.service.allocate(f.actor,{transactionId:f.command.receiptId,memberId:ids.member,expectedVersion:3,
    note:'Different identity justification',requestId:ids.request}),/idempotency_conflict/);assert.equal(f.state.puts,1);
 }finally{f.close();}
});
test('new native session cannot adopt prior committed result',async()=>{
 const f=await preparedFlow('exception');try{await f.allocate();f.actor.sessionId=crypto.randomUUID();
  await assert.rejects(f.allocate(),/idempotency_conflict/);assert.equal(f.state.puts,1);
 }finally{f.close();}
});
test('failed native command receipt retention rolls back the payment and retry succeeds',async()=>{
 const f=await preparedFlow('exception');try{f.state.failCommandReceipt=true;await assert.rejects(f.allocate());
  assert.equal(count(f,'app.ledger_entries'),0);assert.equal(count(f,'private.burimunsi_command_receipts'),0);
  f.state.failCommandReceipt=false;await f.allocate();assert.equal(count(f,'app.ledger_entries'),1);
 }finally{f.close();}
});
test('unknown member does not cause evidence preparation',async()=>{
 const f=await preparedFlow();try{f.identities.length=0;const value=await f.auto();assert.equal(value.state,'unallocated');
  assert.equal(f.state.puts,0);assert.equal(f.state.plans.length,0);assert.equal(count(f,'app.ledger_entries'),0);
 }finally{f.close();}
});
test('identity change after preparation cannot reuse prepared financial target',async()=>{
 const f=await preparedFlow();try{f.state.afterPreparation=()=>{f.identities[0].id='different-identity';};
  await assert.rejects(f.auto(),/posting_plan_changed/);assert.equal(count(f,'app.ledger_entries'),0);
 }finally{f.close();}
});
test('worker lease is copied before asynchronous planning',async()=>{
 const f=await preparedFlow();try{const work={...f.command.work};f.state.beforePreparation=()=>{work.owner='attacker';work.leaseVersion=999;};
  await f.service.automaticallyAllocate(f.command.receiptId,ids.request,work);
  assert.equal(f.state.plans[0].work.owner,f.command.work.owner);assert.equal(count(f,'app.ledger_entries'),1);
 }finally{f.close();}
});
for(const prepared of [null,{}, {prepared:false,contractVersion:1},{prepared:true,contractVersion:2}])test('invalid preparation acknowledgement cannot trigger posting: '+JSON.stringify(prepared),async()=>{
 const f=await preparedFlow();try{f.preparation.prepare=async()=>prepared;await assert.rejects(f.auto(),/posting_preparation_unavailable/);
  assert.equal(count(f,'app.ledger_entries'),0);assert.equal(count(f,'app.payments'),0);
 }finally{f.close();}
});
test('preparation error reconciles only durable result, never invokes another preparation/post attempt',async()=>{
 const f=await preparedFlow();try{let calls=0;f.preparation.prepare=async()=>{calls++;throw new BuriError('posting_preparation_unavailable',503);};
  await assert.rejects(f.auto(),/posting_preparation_unavailable/);assert.equal(calls,1);assert.equal(count(f,'app.ledger_entries'),0);
 }finally{f.close();}
});
test('generic preparation dependency must implement prepare',()=>assert.throws(()=>new ContributionService({store:{inCanonicalTransaction(){}},groupId:'group',preparation:{}}),/collect_adapter_required/));
