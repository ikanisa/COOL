import test from 'node:test';import assert from 'node:assert/strict';
import {ContributionService} from '../../domain/burimunsi/contribution-service.js';
import {parseReceipt} from '../../domain/burimunsi/receipt.js';
import {actor,member,identity,policy,profile,fullSource,source} from './fixtures.mjs';
// Deliberately TEST ONLY: no in-memory financial store exists in runtime modules.
class CanonicalFixture {
 constructor(){this.state={actor:structuredClone(actor),receipt:{...parseReceipt(fullSource,profile),id:'tx-1',groupId:'group-1',version:1,state:'unallocated',hasConflict:false},member:structuredClone(member),identity:structuredClone(identity),entries:[],commands:{}};this.tail=Promise.resolve();this.fail=false;}
 async inCanonicalTransaction(fn){let release;const prev=this.tail;this.tail=new Promise(r=>release=r);await prev;const s=structuredClone(this.state);
  try{const tx={assertAutomaticAdmission:async()=>{if(this.hold)throw Error("processing_on_hold")},reloadActor:async()=>s.actor,retainedCommand:async(g,a,k)=>s.commands[g+':'+a+':'+k],lockReceipt:async(id,g)=>s.receipt.id===id&&s.receipt.groupId===g?s.receipt:null,
  lockMember:async(id,g)=>s.member.id===id&&s.member.groupId===g?s.member:null,loadApprovedPolicy:async()=>policy,listEligibleMembers:async()=>[s.member],listVerifiedIdentities:async()=>[s.identity],
  postCanonicalContribution:async cmd=>{assert.equal(cmd.receiptId,s.receipt.id);assert.equal(cmd.memberId,s.member.id);assert.equal(s.entries.length,0);const result={transactionId:s.receipt.id,memberId:cmd.memberId,amountRwf:s.receipt.amountRwf,currency:'RWF',ledgerEntryId:'ledger-1',memberBalanceRwf:s.receipt.amountRwf,groupBalanceRwf:s.receipt.amountRwf};s.entries.push(result);s.receipt.state='posted';s.receipt.memberId=cmd.memberId;s.receipt.version++;if(this.fail)throw Error('injected commit failure');return result;},
  retainCommand:async cmd=>{s.commands[cmd.groupId+':'+cmd.actorId+':'+cmd.requestId]={fingerprint:cmd.fingerprint,sessionId:cmd.sessionId,response:cmd.response};},readCanonicalResult:async()=>s.entries[0]};
  const result=await fn(tx);this.state=s;return result;}finally{release();}}
}
const work={kind:'receipt',jobId:'df9a9625-2e23-4c5a-afb3-c0f0eb7c6d03',owner:'worker-1',leaseVersion:1};
const command={transactionId:'tx-1',memberId:'member-1',expectedVersion:1,note:'Independent identity confirmed',requestId:'b7d39761-135b-5423-acd1-59eb0348174f'};
test('exception allocation calls canonical writer once and returns server snapshots',async()=>{const db=new CanonicalFixture();const svc=new ContributionService({store:db,groupId:'group-1'});const r=await svc.allocate(actor,command);assert.equal(r.amountRwf,10000);assert.equal(r.memberBalanceRwf,10000);assert.equal(db.state.entries.length,1);});
test('same idempotency request returns original committed result',async()=>{const db=new CanonicalFixture(),s=new ContributionService({store:db,groupId:'group-1'});assert.deepEqual(await s.allocate(actor,command),await s.allocate(actor,command));assert.equal(db.state.entries.length,1);});
test('different body with same request key is rejected',async()=>{const db=new CanonicalFixture(),s=new ContributionService({store:db,groupId:'group-1'});await s.allocate(actor,command);await assert.rejects(s.allocate(actor,{...command,note:'Different attribution'}),/idempotency_conflict/);});
test('racing operators create one economic effect',async()=>{const db=new CanonicalFixture(),s=new ContributionService({store:db,groupId:'group-1'});const outcomes=await Promise.allSettled(Array.from({length:20},(_,i)=>s.allocate(actor,{...command,requestId:crypto.randomUUID()})));assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);assert.equal(db.state.entries.length,1);});
test('canonical transaction failure rolls back allocation and command receipt',async()=>{const db=new CanonicalFixture();db.fail=true;const s=new ContributionService({store:db,groupId:'group-1'});await assert.rejects(s.allocate(actor,command));assert.equal(db.state.entries.length,0);assert.equal(db.state.receipt.version,1);db.fail=false;await s.allocate(actor,command);assert.equal(db.state.entries.length,1);});
test('revoked session is checked inside writer transaction',async()=>{const db=new CanonicalFixture();db.state.actor.revoked=true;await assert.rejects(new ContributionService({store:db,groupId:'group-1'}).allocate(actor,command),/session/);assert.equal(db.state.entries.length,0);});
for(const [key,value] of [['hasConflict',true],['version',2],['state','processing']])test('latest receipt '+key+' prevents stale credit',async()=>{const db=new CanonicalFixture();db.state.receipt[key]=value;await assert.rejects(new ContributionService({store:db,groupId:'group-1'}).allocate(actor,command));assert.equal(db.state.entries.length,0);});
test('automatic matching and repeat work use existing canonical result',async()=>{const db=new CanonicalFixture(),s=new ContributionService({store:db,groupId:'group-1'});assert.deepEqual(await s.automaticallyAllocate('tx-1','30e41b92-f611-575c-9813-0746ddc90748',work),await s.automaticallyAllocate('tx-1','4d923261-a5c6-5024-94e4-af118f899452',work));assert.equal(db.state.entries.length,1);});
test('wallet balance is never used as member balance',async()=>{const db=new CanonicalFixture();db.state.receipt.walletBalanceRwf=800000000;const r=await new ContributionService({store:db,groupId:'group-1'}).automaticallyAllocate('tx-1','30e41b92-f611-575c-9813-0746ddc90748',work);assert.equal(r.memberBalanceRwf,10000);});
test('masked source cannot be auto-posted',async()=>{const db=new CanonicalFixture();db.state.receipt={...db.state.receipt,...parseReceipt(source,profile)};const r=await new ContributionService({store:db,groupId:'group-1'}).automaticallyAllocate('tx-1','30e41b92-f611-575c-9813-0746ddc90748',work);assert.equal(r.state,'unallocated');assert.equal(db.state.entries.length,0);});
test('missing canonical adapter fails closed at startup',()=>assert.throws(()=>new ContributionService({store:{},groupId:'g'}),/collect_adapter_required/));

test('a new session cannot replay a prior session command',async()=>{const db=new CanonicalFixture(),s=new ContributionService({store:db,groupId:'group-1'});await s.allocate(actor,command);db.state.actor.sessionId='another-session';await assert.rejects(s.allocate({...actor,sessionId:'another-session'},command),/idempotency_conflict/);assert.equal(db.state.entries.length,1)});

test('automatic post rechecks work fence before its enclosing transaction can commit',async()=>{
 const db=new CanonicalFixture();const original=db.inCanonicalTransaction.bind(db);let checks=0;
 db.inCanonicalTransaction=fn=>original(async tx=>{
  tx.assertAutomaticAdmission=async()=>{checks++;if(checks===2)throw Error('lease expired before commit')};return fn(tx);
 });
 const s=new ContributionService({store:db,groupId:'group-1'});
 await assert.rejects(s.automaticallyAllocate('tx-1',crypto.randomUUID(),work),/lease expired/);
 assert.equal(checks,2);assert.equal(db.state.entries.length,0);
});
test('already posted result is validated rather than blindly acknowledged',async()=>{
 const db=new CanonicalFixture(),s=new ContributionService({store:db,groupId:'group-1'});
 await s.automaticallyAllocate('tx-1',crypto.randomUUID(),work);
 db.state.entries[0].memberId='different-member';
 await assert.rejects(s.automaticallyAllocate('tx-1',crypto.randomUUID(),work),/canonical_writer_contract_violation/);
});
