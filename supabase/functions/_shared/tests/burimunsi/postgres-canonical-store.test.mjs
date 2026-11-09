import test from 'node:test';import assert from 'node:assert/strict';
import {PostgresCanonicalStore} from '../../domain/burimunsi/postgres-canonical-store.js';
import {ContributionService} from '../../domain/burimunsi/contribution-service.js';
import {policy,identity,member} from './fixtures.mjs';
const aid='11111111-1111-4111-8111-111111111111',sid='22222222-2222-4222-8222-222222222222',rid='33333333-3333-4333-8333-333333333333';
const actor={id:aid,sessionId:sid,principalUserId:'principal-1',groupId:'group-1',role:'staff',active:true,expiresAt:9999999999999,capabilities:['records.read','payments.allocate','members.enroll']};
const command={transactionId:'tx-1',memberId:'member-1',expectedVersion:1,note:'Independent identity checked',requestId:rid};
const work={kind:'receipt',jobId:'44444444-4444-4444-8444-444444444444',owner:'worker-1',leaseVersion:1};
/** SQL recorder and transaction fixture, NOT PostgreSQL execution. */
function fixture(){
 const f={queries:[],claims:0,writes:0,commits:0,rollbacks:0,receipts:[],result:null,session:structuredClone(actor),enabled:true,
 row:{id:'tx-1',collection_id:'group-1',receiving_account_id:'wallet-1',currency:'RWF',event_kind:'incoming_receipt',has_conflict:0,version:1,amount_minor:10000,
 allocation_state:'unallocated',transaction_at:'2026-10-08T13:15:20.000Z',payer_identifier:'+250780000816',payer_name:'EXAMPLE PERSON',provider_transaction_id:'90000000001',source_binding_id:'binding-1',source_binding_version:1}};
 const sql={unsafe:async(q,v=[])=>{
  f.queries.push({q,v});
  if(q.includes('SELECT collection_id,receiving_account_id,enabled,version'))return [{collection_id:'group-1',receiving_account_id:'wallet-1',enabled:f.enabled,version:1}];
  if(q.includes('SELECT t.*,x.collection_id'))return f.duplicateReceipt?[f.row,f.row]:[f.row];
  if(q.includes('SELECT u.id,m.collection_id'))return [{id:'member-1',collection_id:'group-1',active:1,revision:1,access_status:f.memberStatus??'active'}];
  if(q.includes('SELECT session_id,operation,fingerprint,response'))return f.receipts;
  if(q.includes('INSERT INTO private.burimunsi_command_receipts')){
   if(f.failReceipt)throw Error('receipt failure');f.receipts=[{session_id:v[3],operation:v[4],fingerprint:v[5],response:v[6]}];return [];
  }
  if(q.includes('SELECT t.id AS transaction_id'))return f.result?(f.duplicateResult?[f.result,f.result]:[f.result]):[];
  throw Error('Unexpected SQL '+q);
 }};
 const authority={groupId:'group-1',session:async tx=>{assert.equal(tx,sql);return f.session},write:async fn=>{
  const old=structuredClone({row:f.row,receipts:f.receipts,result:f.result,writes:f.writes});
  try{const r=await fn(sql);f.commits++;return r}catch(e){Object.assign(f,old);f.rollbacks++;throw e}
 }};
 const commands={postContribution:async(tx,cmd)=>{
  assert.equal(tx,sql);assert.equal(cmd.receipt.id,'tx-1');assert.equal(cmd.member.id,'member-1');f.writes++;
  f.result={transaction_id:'tx-1',source_amount:10000,source_currency:'RWF',has_conflict:0,event_kind:'incoming_receipt',allocation_state:'linked',payment_evidence_id:'evidence-1',entry_evidence_id:'evidence-1',has_compensation:false,payment_id:'p-1',member_id:cmd.memberId,link_member_id:cmd.memberId,rail:'rwanda_momo',amount_minor:10000,currency:'RWF',status:'reconciled',ledger_entry_id:'ledger-1',entry_amount:10000,entry_currency:'RWF',member_balance_after_minor:10000,group_balance_after_minor:10000};
  if(f.corruptResult)Object.assign(f.result,f.corruptResult);
  if(f.revokeAfterWrite)f.session={...f.session,active:false};
  if(f.expireLeaseAfterWrite)f.hold=true;
  f.row={...f.row,allocation_state:'linked',payment_status:'reconciled',member_id:cmd.memberId,version:2};
  return {ledgerEntryId:'untrusted-claim-ignored'};
 },createDirectMember:async(tx,cmd)=>{assert.equal(tx,sql);return cmd},setMembershipActive:async(tx,cmd)=>{assert.equal(tx,sql);return cmd},enqueueEligibleRematch:async(tx,cmd)=>{assert.equal(tx,sql);return cmd}};
 const identities={policy:async tx=>{assert.equal(tx,sql);return policy},members:async tx=>{assert.equal(tx,sql);return [member]},verified:async tx=>{assert.equal(tx,sql);return f.identities??[identity]}};
 const jobs={assertPostingLease:async(tx,cmd)=>{assert.equal(tx,sql);assert.equal(cmd.groupId,'group-1');f.claims++;if(f.hold)throw Error('lease lost')}};
 f.options={authority,commands,identities,jobs,clock:()=>1000};f.store=new PostgresCanonicalStore(f.options);f.service=new ContributionService({store:f.store,groupId:'group-1',clock:()=>1000});return f;
}
test('exception posting uses same SQL transaction and authoritative snapshot, not claimed return',async()=>{
 const f=fixture(),r=await f.service.allocate(actor,command);assert.equal(r.ledgerEntryId,'ledger-1');assert.equal(f.writes,1);assert.equal(f.commits,1);assert.equal(f.receipts[0].operation,'burimunsi.allocate');assert.equal(typeof f.receipts[0].response,'object');
});
test('replay returns retained result without another financial command',async()=>{
 const f=fixture();const a=await f.service.allocate(actor,command),b=await f.service.allocate(actor,command);assert.deepEqual(a,b);assert.equal(f.writes,1);
});
test('changed replay body is rejected',async()=>{
 const f=fixture();await f.service.allocate(actor,command);await assert.rejects(f.service.allocate(actor,{...command,note:'Different identity proof'}),/idempotency_conflict/);assert.equal(f.writes,1);
});
test('receipt insertion failure rolls back financial result and allocation',async()=>{
 const f=fixture();f.failReceipt=true;await assert.rejects(f.service.allocate(actor,command),/receipt failure/);assert.equal(f.writes,0);assert.equal(f.result,null);assert.equal(f.row.allocation_state,'unallocated');assert.equal(f.rollbacks,1);
});
test('session revoked after shared writer cannot commit',async()=>{
 const f=fixture();f.revokeAfterWrite=true;await assert.rejects(f.service.allocate(actor,command),/session_unavailable/);assert.equal(f.writes,0);
});
test('automatic posting repeats verified identity and current lease checks',async()=>{
 const f=fixture();const r=await f.service.automaticallyAllocate('tx-1',rid,work);assert.equal(r.memberId,'member-1');assert.ok(f.claims>=4);assert.equal(f.writes,1);
});
test('automatic repeated job reads original canonical result',async()=>{
 const f=fixture();const first=await f.service.automaticallyAllocate('tx-1',rid,work);assert.deepEqual(await f.service.automaticallyAllocate('tx-1',rid,work),first);assert.equal(f.writes,1);
});
test('lease loss after writer rolls back',async()=>{
 const f=fixture();f.expireLeaseAfterWrite=true;await assert.rejects(f.service.automaticallyAllocate('tx-1',rid,work),/lease lost/);assert.equal(f.writes,0);
});
test('masked phone remains unallocated',async()=>{
 const f=fixture();f.row.payer_identifier='*********816';assert.equal((await f.service.automaticallyAllocate('tx-1',rid,work)).state,'unallocated');assert.equal(f.writes,0);assert.equal(f.claims,2);
});
test('deactivated competing owner still prevents automatic credit',async()=>{
 const f=fixture();f.identities=[identity,{...identity,id:'other-proof',memberId:'inactive-member'}];assert.equal((await f.service.automaticallyAllocate('tx-1',rid,work)).reason,'ambiguous_identity');assert.equal(f.writes,0);
});
for(const patch of [{member_id:'wrong-member'},{link_member_id:'wrong-member'},{link_member_id:null},{rail:'cash'},{entry_amount:9999},{entry_currency:'USD'},{source_currency:'USD'},{has_conflict:1},{status:'reversed'},
 {member_balance_after_minor:'9007199254740992'},{group_balance_after_minor:null},{group_balance_after_minor:''},{group_balance_after_minor:-1}]){
 test('invalid canonical readback rolls back '+JSON.stringify(patch),async()=>{
  const f=fixture();f.corruptResult=patch;await assert.rejects(f.service.allocate(actor,command));assert.equal(f.writes,0);assert.equal(f.receipts.length,0);
 });
}
for(const patch of [{has_conflict:1},{version:2},{currency:'USD'},{event_kind:'outgoing_payment'},{receiving_account_id:'other-wallet'},{collection_id:'other-group'},{amount_minor:0},{amount_minor:null},{amount_minor:'9007199254740992'}]){
 test('receipt guard prevents command '+JSON.stringify(patch),async()=>{const f=fixture();Object.assign(f.row,patch);await assert.rejects(f.service.allocate(actor,command));assert.equal(f.writes,0)});
}
test('duplicate canonical rows are not arbitrarily collapsed',async()=>{
 const f=fixture();f.duplicateReceipt=true;await assert.rejects(f.service.allocate(actor,command),/canonical_record_invalid/);assert.equal(f.writes,0);
});
test('duplicate ledger results are not acknowledged',async()=>{
 const f=fixture();f.duplicateResult=true;await assert.rejects(f.service.allocate(actor,command),/canonical_writer_contract_violation/);assert.equal(f.writes,0);
});
test('disabled scope stops before financial work',async()=>{
 const f=fixture();f.enabled=false;await assert.rejects(f.service.allocate(actor,command),/scope_unavailable/);assert.equal(f.writes,0);
});
test('suspended member cannot receive a credit',async()=>{
 const f=fixture();f.memberStatus='suspended';await assert.rejects(f.service.allocate(actor,command),/member_unavailable/);assert.equal(f.writes,0);
});
test('escaped transaction interface cannot be reused after callback closes',async()=>{
 const f=fixture();let escaped;await f.store.inCanonicalTransaction(tx=>{escaped=tx});const n=f.queries.length;await assert.rejects(escaped.lockReceipt('tx-1','group-1'),/transaction_closed/);assert.equal(f.queries.length,n);
});
test('cross-group direct adapter use fails closed',async()=>{
 const f=fixture();await assert.rejects(f.store.inCanonicalTransaction(tx=>tx.lockReceipt('tx-1','other-group')),/access_denied/);
});
test('direct automatic writer call without lease witness fails closed',async()=>{
 const f=fixture();await assert.rejects(f.store.inCanonicalTransaction(tx=>tx.postCanonicalContribution({groupId:'group-1',receiptId:'tx-1',memberId:'member-1',expectedVersion:1,requestId:rid,mode:'automatic',work,policyVersion:'test-policy-1',identityIds:['identity-1']})),/automatic_work_required/);assert.equal(f.writes,0);
});
test('trusted identity changes between match and writer are re-evaluated',async()=>{
 const f=fixture();let calls=0;f.options.identities.verified=async()=>++calls===1?[identity]:[];
 await assert.rejects(f.service.automaticallyAllocate('tx-1',rid,work),/identity_changed/);assert.equal(f.writes,0);
});
for(const key of ['authority','commands','identities','jobs'])test('missing required bridge '+key+' fails at construction',()=>{
 const f=fixture();assert.throws(()=>new PostgresCanonicalStore({...f.options,[key]:{}}));
});
const rematchWork={...work,kind:'rematch',memberId:'member-1',policyVersion:policy.approvedVersion};
test('rematch checkpoint receives exact financial SQL transaction and canonical readback',async()=>{
 const f=fixture();let captured;let originalSql;
 const original=f.options.commands.postContribution;
 f.options.commands.postContribution=async(sql,cmd)=>{originalSql=sql;return original(sql,cmd)};
 f.options.jobs.retainAutomaticOutcome=async(sql,cmd)=>{assert.equal(sql,originalSql);captured=cmd;return {durable:true}};
 const result=await f.service.automaticallyAllocate('tx-1',rid,rematchWork);
 assert.deepEqual(captured.result,result);assert.deepEqual(captured.work,rematchWork);assert.equal(f.writes,1);assert.equal(f.commits,1);
});
test('rematch checkpoint refusal rolls back canonical adapter transaction',async()=>{
 const f=fixture();f.options.jobs.retainAutomaticOutcome=async()=>{throw Error('checkpoint refused')};
 await assert.rejects(f.service.automaticallyAllocate('tx-1',rid,rematchWork),/checkpoint refused/);
 assert.equal(f.writes,0);assert.equal(f.result,null);assert.equal(f.rollbacks,1);
});
test('outcome checkpoint cannot be called without matching automatic admission',async()=>{
 const f=fixture();f.options.jobs.retainAutomaticOutcome=async()=>{throw Error('must not call')};
 await assert.rejects(f.store.inCanonicalTransaction(tx=>tx.retainAutomaticOutcome({groupId:'group-1',transactionId:'tx-1',requestId:rid,work:rematchWork,result:{}})),/automatic_work_required/);
});
test('rematch member cannot be swapped between admission and writer',async()=>{
 const f=fixture();await assert.rejects(f.store.inCanonicalTransaction(async tx=>{
  await tx.assertAutomaticAdmission({groupId:'group-1',transactionId:'tx-1',requestId:rid,work:{...rematchWork,memberId:'different-member'}});
  return tx.postCanonicalContribution({groupId:'group-1',receiptId:'tx-1',memberId:'member-1',expectedVersion:1,requestId:rid,mode:'automatic',
   work:{...rematchWork,memberId:'different-member'},policyVersion:policy.approvedVersion,identityIds:[identity.id]});
 }),/identity_changed/);assert.equal(f.writes,0);
});
test('closed transaction cannot retain a rematch outcome',async()=>{
 const f=fixture();let escaped;await f.store.inCanonicalTransaction(async tx=>{escaped=tx});
 await assert.rejects(escaped.retainAutomaticOutcome({groupId:'group-1',transactionId:'tx-1',requestId:rid,work:rematchWork,result:{}}),/transaction_closed/);
});

// Replayed original snapshots must not acknowledge unsupported compensation or
// disconnected source/evidence. Controls also run against the exact v0.5.0 module.
for(const patch of [{status:'corrected'},{event_kind:'outgoing'},{allocation_state:'unallocated'},
 {has_compensation:true},{has_compensation:null},{has_compensation:0},
 {entry_evidence_id:'other-evidence'},{payment_evidence_id:null,entry_evidence_id:null},{payment_id:''}]){
 test('v0.6 rejects disconnected or compensated readback '+JSON.stringify(patch),async()=>{
  const f=fixture();f.corruptResult=patch;await assert.rejects(f.service.allocate(actor,command));
  assert.equal(f.writes,0);assert.equal(f.receipts.length,0);assert.equal(f.rollbacks,1);
 });
}
