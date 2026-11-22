import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {exportDtos} from './support/dto_export.mjs';
import {fixture} from './admin_support/fixture.mjs';

async function operator(f,options={}){const account=await f.seedAccount(options);return {...await f.stepUp(await f.login(account)),account};}
async function setup(f){
 const owner=await operator(f),staff=await operator(f,{role:'staff',email:'proposer@example.test'}),member=await f.seedMember();
 const group=await f.operation('groups',owner.cookie,{title:'Retained review group',slug:'review-group',collection_type:'ikimina',
  owner_user_id:member.id,receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Create retained review group'});
 assert.equal(group.status,200,JSON.stringify(group));const groupId=group.body.resource_id;
 const payment=await f.operation('transactions',owner.cookie,{group_id:groupId,payee_id:groupId,amount_rwf:1500,provider_reference:'controlled-evidence-reference',
  observed_at:new Date().toISOString(),evidence:'Exact controlled retained receiver evidence. No provider confirmation claim.',reason:'Record exact retained payment evidence'});
 assert.equal(payment.status,200,JSON.stringify(payment));return {owner,staff,member,groupId,paymentId:payment.body.resource_id};
}
async function propose(f,s,extra={}){
 const user=await f.db.prepare('SELECT * FROM users WHERE id=?').bind(s.member.id).first();
 const body={member_user_id:s.member.id,amount_rwf:1500,expected_transaction_version:1,expected_member_version:user.revision,expected_membership_version:1,
  expected_payment_identity:{display_name:user.full_name,momo_provider:user.momo_provider,momo_number:user.momo_number,momo_pay_code:user.momo_pay_code},reason:'Attribute this retained evidence to the reviewed member',...extra};
 return f.call(`/api/admin/reconciliations/${s.paymentId}/proposals`,{cookie:s.staff.cookie,data:body,headers:{'Idempotency-Key':randomUUID()}});
}
const review=(f,cookie,id,outcome,headers={},reason='Independent review of retained evidence')=>f.call(`/api/admin/reconciliations/proposals/${id}/reviews`,
 {cookie,data:{outcome,expected_proposal_version:1,expected_transaction_version:1,reason},headers:{'Idempotency-Key':randomUUID(),...headers}});
const read=(f,cookie,path)=>f.call('/api/admin/reconciliations'+path,{method:'GET',cookie});

test('staff can propose without acquiring review authority; independent approval retains both reasons',async t=>{
 const f=await fixture(t),s=await setup(f);
 const session=await f.call('/api/admin/auth/session',{method:'GET',cookie:s.staff.cookie});assert.equal(session.body.user.financialModel,'canonical_evidence_ledger');
 assert.ok(!session.body.user.permissions.includes('payments.reconcile'));assert.ok(!session.body.user.permissions.includes('reconciliations.review'));
 const proposal=await propose(f,s);assert.equal(proposal.status,200,JSON.stringify(proposal));assert.equal(proposal.body.proposal_status,'proposed');
 assert.equal((await review(f,s.staff.cookie,proposal.body.resource_id,'approved')).status,403);
 const queue=await read(f,s.owner.cookie,'?status=recorded&limit=25&offset=0'),detail=await read(f,s.owner.cookie,'/'+s.paymentId),members=await read(f,s.owner.cookie,'/members?transaction_id='+s.paymentId);
 assert.equal(queue.status,200,JSON.stringify(queue));assert.equal(queue.body.rows.length,1);assert.equal(queue.body.limit,25);assert.equal(queue.body.next_offset,null);
 assert.equal(detail.status,200,JSON.stringify(detail));assert.equal(detail.body.current_principal_id,s.owner.account.userId);
 const retained=detail.body.related.proposals.rows[0];assert.equal(retained.proposed_by_principal_id,s.staff.account.userId);assert.equal(retained.reason,'Attribute this retained evidence to the reviewed member');
 assert.equal(retained.snapshot_available,true);assert.equal(retained.payment_identity.display_name,'Recorded Member');assert.equal(detail.body.resource.provider_confirmation,false);
 assert.equal(members.status,200);assert.equal(members.body.transaction_id,s.paymentId);assert.equal(members.body.rows.length,1);
 const approved=await review(f,s.owner.cookie,proposal.body.resource_id,'approved');assert.equal(approved.status,200,JSON.stringify(approved));
 const after=await read(f,s.owner.cookie,'/'+s.paymentId);assert.equal(after.status,200);assert.equal(after.body.related.ledger_entries.rows.length,1);
 assert.equal(after.body.related.proposals.rows[0].review_reason,'Independent review of retained evidence');assert.equal(after.body.resource.status,'reconciled');
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM ledger_entries WHERE payment_id=?').bind(s.paymentId).first()).n,1);
 await exportDtos('admin-canonical-reconciliation-dto-examples.json',{scope:'Isolated actual workerd/D1/R2 execution; no hosted or provider claim.',queue:queue.body,detail:detail.body,members:members.body,proposal_receipt:proposal.body,review_receipt:approved.body,after:after.body});
});

test('independent rejection changes no money and remains discoverable by its exact request key',async t=>{
 const f=await fixture(t),s=await setup(f),p=await propose(f,s);assert.equal(p.status,200,JSON.stringify(p));
 const key=randomUUID(),headers={'Idempotency-Key':key},first=await review(f,s.owner.cookie,p.body.resource_id,'rejected',headers);
 assert.equal(first.status,200,JSON.stringify(first));assert.equal(first.body.proposal_status,'rejected');assert.equal(first.body.transaction_version,1);
 const retry=await review(f,s.owner.cookie,p.body.resource_id,'rejected',headers);assert.deepEqual(retry.body,first.body);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);
 const lookup=await f.call('/api/admin/operations/requests/'+key,{method:'GET',cookie:s.owner.cookie});assert.equal(lookup.status,200);assert.deepEqual(lookup.body.receipt,first.body);
 const history=await f.call('/api/admin/operations/requests?limit=25&offset=0',{method:'GET',cookie:s.owner.cookie});assert.equal(history.status,200,JSON.stringify(history));
 assert.ok(history.body.rows.some(r=>r.scope==='reconciliations.review'&&r.idempotency_key===key));
 assert.ok(!JSON.stringify(history.body).includes('Exact controlled retained receiver evidence'));
});

test('a concurrent rejection makes a paused approval roll back its receipt and credit atomically',async t=>{
 const f=await fixture(t),s=await setup(f),other=await operator(f,{email:'independent@example.test',role:'admin'}),p=await propose(f,s);assert.equal(p.status,200);
 f.setGate(async()=>{const reject=await review(f,other.cookie,p.body.resource_id,'rejected');assert.equal(reject.status,200,JSON.stringify(reject));});
 const rejected=await review(f,s.owner.cookie,p.body.resource_id,'approved',{'X-Test-Pause':'before_commit'});
 assert.equal(rejected.status,409,JSON.stringify(rejected));assert.equal((await f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);
 assert.equal((await f.db.prepare('SELECT status FROM reconciliations WHERE id=?').bind(p.body.resource_id).first()).status,'rejected');
});

test('financial reasons and scoped member authority cannot be omitted',async t=>{
 const f=await fixture(t),s=await setup(f);
 assert.equal((await propose(f,s,{reason:''})).status,400);
 await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='users.read'").bind(s.staff.account.userId).run();
 const members=await read(f,s.staff.cookie,'/members?transaction_id='+s.paymentId);assert.equal(members.status,403);
 const detail=await read(f,s.staff.cookie,'/'+s.paymentId);assert.equal(detail.status,403);
});
