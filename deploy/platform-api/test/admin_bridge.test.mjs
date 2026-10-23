import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {exportDtos} from './support/dto_export.mjs';
import {fixture,hash} from './admin_support/fixture.mjs';

async function operator(f,options={}){const account=await f.seedAccount(options),login=await f.login(account),verified=await f.stepUp(login);return {...verified,account};}
async function createGroup(f,operator,member,key=randomUUID(),extra={}){
 const data={title:'Controlled collection',slug:'controlled-'+randomUUID().slice(0,8),collection_type:'ikimina',description:'Retained fixture group',
  owner_user_id:member.id,receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Recorded group creation',...extra};
 const result=await f.operation('groups',operator.cookie,data,key);assert.equal(result.status,200,JSON.stringify(result));return {id:result.body.resource_id,data,key,receipt:result.body};
}
async function record(f,operator,group,amount=1000,key=randomUUID()){
 const data={group_id:group.id,payee_id:group.id,amount_rwf:amount,provider_reference:'fixture-'+randomUUID(),observed_at:new Date().toISOString(),evidence:'Exact retained operator receipt fixture; no provider settlement assertion.',reason:'Record retained evidence'};
 const result=await f.operation('transactions',operator.cookie,data,key);assert.equal(result.status,200,JSON.stringify(result));return {id:result.body.resource_id,data,key,receipt:result.body};
}
async function proposal(f,operator,payment,member,extra={}){
 const u=await f.db.prepare('SELECT * FROM users WHERE id=?').bind(member.id).first(),m=await f.db.prepare('SELECT * FROM memberships WHERE user_id=? AND collection_id=(SELECT collection_id FROM payments WHERE id=?)').bind(member.id,payment.id).first(),p=await f.db.prepare('SELECT * FROM payments WHERE id=?').bind(payment.id).first();
 const data={member_user_id:member.id,amount_rwf:p.amount_minor,expected_transaction_version:p.revision,expected_member_version:u.revision,expected_membership_version:m.revision,
  expected_payment_identity:{display_name:u.full_name,momo_provider:u.momo_provider,momo_number:u.momo_number,momo_pay_code:u.momo_pay_code},reason:'Independent attribution proposal',...extra};
 const key=randomUUID(),result=await f.call(`/api/admin/reconciliations/${payment.id}/proposals`,{cookie:operator.cookie,data,headers:{'Idempotency-Key':key}});return {result,data,key};
}
async function approval(f,operator,proposal,{version=1,key=randomUUID(),headers={}}={}){
 const data={outcome:'approved',expected_proposal_version:1,expected_transaction_version:version,reason:'Independent retained evidence review'};
 return {result:await f.call(`/api/admin/reconciliations/proposals/${proposal.result.body.resource_id}/reviews`,{cookie:operator.cookie,data,headers:{'Idempotency-Key':key,...headers}}),data,key};
}

test('mobile and cookie Admin read the same canonical people/groups without a second operating store',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),group=await createGroup(f,admin,member),native=await f.nativeLogin(member.phone);
 assert.equal(native.user.id,member.id);
 const app=await f.call('/v1/rpc/list_current_user_collections',{origin:'https://collect.example',data:{},headers:{Authorization:`Bearer ${native.access_token}`}});assert.equal(app.status,200);assert.ok(app.body.some(r=>r.id===group.id));
 const groups=await f.call('/api/admin/core/groups',{method:'GET',cookie:admin.cookie});assert.equal(groups.status,200,JSON.stringify(groups));assert.equal(groups.body.model,'canonical_evidence_ledger');assert.equal(groups.body.rows[0].id,group.id);
 const people=await f.call('/api/admin/core/users',{method:'GET',cookie:admin.cookie});assert.equal(people.status,200);assert.ok(people.body.rows.some(r=>r.id===member.id));
 for(const row of people.body.rows)assert.ok(!['password_hash','token_hash','secret_ciphertext','auth_version'].some(k=>k in row));
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type='table' AND name GLOB 'collect_*'").first()).n,0);
 const injected=await f.call("/api/admin/core/users?search="+encodeURIComponent("%_' OR 1=1 --"),{method:'GET',cookie:admin.cookie});assert.equal(injected.status,200);assert.equal(injected.body.total,0);
});

test('staff, stale versions, unsupported journals and forged capabilities are denied truthfully',async t=>{
 const f=await fixture(t),owner=await operator(f),staffAccount=await f.seedAccount({email:'staff@example.com',role:'staff'}),staff=await f.login(staffAccount),member=await f.seedMember(),group=await createGroup(f,owner,member);
 assert.equal((await f.operation('users',staff.cookie,{display_name:'Other member',phone_e164:'+250788123459',reason:'Unauthorized creation'})).status,403);
 assert.equal((await f.operation('groups',staff.cookie,{...group.data,slug:'staff-group',permissions:['collections.manage']})).status,400);
 const patch=await f.call(`/api/admin/operations/groups/${group.id}`,{method:'PATCH',cookie:owner.cookie,data:{title:'Changed group',expected_version:1,reason:'Recorded update'},headers:{'Idempotency-Key':randomUUID()}});assert.equal(patch.status,200,JSON.stringify(patch));
 const stale=await f.call(`/api/admin/operations/groups/${group.id}`,{method:'PATCH',cookie:owner.cookie,data:{title:'Stale update',expected_version:1,reason:'Stale attempt'},headers:{'Idempotency-Key':randomUUID()}});assert.equal(stale.status,409);
 assert.equal((await f.operation('journals',owner.cookie,{reason:'Unsupported journal'})).status,501);
 assert.equal((await f.operation(`transactions/${randomUUID()}/verification`,owner.cookie,{verification_status:'confirmation_recorded',reason:'Cannot manufacture confirmation'})).status,501);
});

test('lost reply and exact retry preserve one canonical group and retained receipt',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),key=randomUUID(),data={title:'Retry group',slug:'retry-group',collection_type:'ikimina',owner_user_id:member.id,
 receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Recorded retry creation'};
 const initial=await f.operation('groups',admin.cookie,data,key,{'X-Test-Pause':'lost_reply'});assert.equal(initial.status,200,JSON.stringify(initial));
 const retry=await f.operation('groups',admin.cookie,data,key);assert.equal(retry.status,200,JSON.stringify(retry));assert.deepEqual(retry.body,initial.body);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,1);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_bridge_requests').first()).n,1);
 assert.equal((await f.operation('groups',admin.cookie,{...data,title:'Different content'},key)).status,409);
 const saved=await f.call(`/api/admin/operations/requests/${key}`,{method:'GET',cookie:admin.cookie});assert.equal(saved.status,200);assert.equal(saved.body.status,'succeeded');assert.deepEqual(saved.body.receipt,initial.body);
});

test('account revocation during an awaited group mutation rolls back every domain write and alias',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember();
 f.setGate(async()=>f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(admin.account.adminId).run());
 const result=await f.operation('groups',admin.cookie,{title:'Blocked group',slug:'blocked-group',collection_type:'ikimina',owner_user_id:member.id,receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Revocation boundary'},randomUUID(),{'X-Test-Pause':'before_commit'});
 assert.ok([401,403].includes(result.status),JSON.stringify(result));assert.equal((await f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,0);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_bridge_requests').first()).n,0);
});

test('a capability revoked after commit cannot obtain a lost-reply success through stale authority',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember();f.setGate(async()=>f.db.prepare('DELETE FROM admin_grants WHERE user_id=? AND permission=?').bind(admin.account.userId,'collections.create').run());
 const result=await f.operation('groups',admin.cookie,{title:'Committed group',slug:'committed-group',collection_type:'ikimina',owner_user_id:member.id,receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Lost reply authority fence'},randomUUID(),{'X-Test-Pause':'lost_reply'});
 assert.equal(result.status,403,JSON.stringify(result));assert.equal((await f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,1,'effect is retained, but response authority is revoked');
});

test('retained evidence is encrypted in real R2 and cookie revocation during read releases no plaintext',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),group=await createGroup(f,admin,member),payment=await record(f,admin,group);
 const evidence=await f.db.prepare('SELECT e.* FROM payment_evidence e JOIN payments p ON p.evidence_id=e.id WHERE p.id=?').bind(payment.id).first();
 const bucket=await f.mf.getR2Bucket('PRIVATE_MEDIA'),object=await bucket.get(evidence.object_key);assert.ok(object);assert.ok(!(await object.text()).includes(payment.data.evidence));
 const duplicate=await f.operation('transactions',admin.cookie,payment.data,payment.key);assert.equal(duplicate.status,200);assert.deepEqual(duplicate.body,payment.receipt);assert.equal((await bucket.list()).objects.length,1);
 const read=await f.call(`/api/admin/evidence/${evidence.id}`,{method:'GET',cookie:admin.cookie});assert.equal(read.status,200);assert.equal(read.body,payment.data.evidence);
 f.setGate(async()=>f.db.prepare('DELETE FROM admin_sessions WHERE token_hash=?').bind(hash(admin.cookie.split('=')[1])).run());
 const denied=await f.call(`/api/admin/evidence/${evidence.id}`,{method:'GET',cookie:admin.cookie,headers:{'X-Test-Pause':'evidence_read'}});assert.ok([401,403].includes(denied.status),JSON.stringify(denied));assert.ok(!JSON.stringify(denied.body).includes(payment.data.evidence));
});

test('reconciliation guards the selected member identity and versions through approval',async t=>{
 const f=await fixture(t),proposer=await operator(f),reviewer=await operator(f,{email:'reviewer@example.com',role:'admin'}),member=await f.seedMember(),group=await createGroup(f,proposer,member),payment=await record(f,proposer,group),p=await proposal(f,proposer,payment,member);
 assert.equal(p.result.status,200,JSON.stringify(p.result));assert.equal((await approval(f,proposer,p)).result.status,403,'self-review cannot credit the member');
 await f.db.prepare('UPDATE users SET momo_number=? WHERE id=?').bind('0788123459',member.id).run();
 const changed=await approval(f,reviewer,p);assert.equal(changed.result.status,409,JSON.stringify(changed.result));assert.equal((await f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,0);
 const retry=await f.call(`/api/admin/reconciliations/${payment.id}/proposals`,{cookie:proposer.cookie,data:p.data,headers:{'Idempotency-Key':p.key}});assert.equal(retry.status,200);assert.deepEqual(retry.body,p.result.body);
});

test('member identity changed during proposal commit cannot retain an eligible proposal snapshot',async t=>{
 const f=await fixture(t),proposer=await operator(f),member=await f.seedMember(),group=await createGroup(f,proposer,member),payment=await record(f,proposer,group),u=await f.db.prepare('SELECT * FROM users WHERE id=?').bind(member.id).first();
 f.setGate(async()=>f.db.prepare('UPDATE users SET full_name=? WHERE id=?').bind('Changed member identity',member.id).run());
 const result=await f.call(`/api/admin/reconciliations/${payment.id}/proposals`,{cookie:proposer.cookie,data:{member_user_id:member.id,amount_rwf:1000,expected_transaction_version:1,expected_member_version:u.revision,expected_membership_version:1,expected_payment_identity:{display_name:u.full_name,momo_provider:u.momo_provider,momo_number:u.momo_number,momo_pay_code:u.momo_pay_code},reason:'Concurrent identity boundary'},headers:{'Idempotency-Key':randomUUID(),'X-Test-Pause':'before_commit'}});
 assert.equal(result.status,409,JSON.stringify(result));assert.equal((await f.db.prepare('SELECT count(*) AS n FROM reconciliations').first()).n,0);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_bridge_reconciliation_snapshots').first()).n,0);
});

test('independent reconciliation, exact retries and reversal expose factual signed ledgers and mobile balances',async t=>{
 const f=await fixture(t),proposer=await operator(f),reviewer=await operator(f,{email:'reviewer@example.com',role:'admin'}),member=await f.seedMember(),group=await createGroup(f,proposer,member),payment=await record(f,proposer,group),p=await proposal(f,proposer,payment,member);
 assert.equal(p.result.status,200,JSON.stringify(p.result));const approved=await approval(f,reviewer,p);assert.equal(approved.result.status,200,JSON.stringify(approved.result));
 const retry=await f.call(`/api/admin/reconciliations/proposals/${p.result.body.resource_id}/reviews`,{cookie:reviewer.cookie,data:approved.data,headers:{'Idempotency-Key':approved.key}});assert.equal(retry.status,200);assert.deepEqual(retry.body,approved.result.body);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,1);
 const native=await f.nativeLogin(member.phone),balance=await f.call('/v1/rpc/list_current_member_collection_balances',{origin:'https://collect.example',headers:{Authorization:`Bearer ${native.access_token}`}});assert.equal(balance.status,200);assert.equal(balance.body[0].balances[0].amount_raised_minor,1000);
 const captures={scope:'isolated actual workerd/D1/R2 fixtures, no provider settlement or deployment claim',bundle_sha256:f.bundleSha256};
 for(const area of ['overview','groups','users','members','payees','transactions','ledgers']){const read=await f.call('/api/admin/core/'+area,{method:'GET',cookie:proposer.cookie});assert.equal(read.status,200,JSON.stringify(read));captures[area]=read.body;}
 assert.equal(captures.ledgers.rows[0].kind,'contribution');assert.equal(captures.ledgers.rows[0].signed_amount_rwf,1000);assert.ok(!('balanced' in captures.ledgers.rows[0]));
 assert.equal(captures.transactions.rows[0].evidence_level,'operator_recorded');assert.equal(captures.transactions.rows[0].provider_confirmation,false);assert.equal(captures.transactions.rows[0].settlement_status,'not_asserted');
 const reverseKey=randomUUID(),reverseData={expected_version:2,reason:'Recorded reversal of prior contribution'},reverse=await f.operation(`transactions/${payment.id}/reverse`,reviewer.cookie,reverseData,reverseKey);assert.equal(reverse.status,200,JSON.stringify(reverse));
 assert.deepEqual((await f.operation(`transactions/${payment.id}/reverse`,reviewer.cookie,reverseData,reverseKey)).body,reverse.body);
 const ledger=await f.call('/api/admin/core/ledgers?status=reversal',{method:'GET',cookie:proposer.cookie});assert.equal(ledger.status,200,JSON.stringify(ledger));assert.equal(ledger.body.rows[0].signed_amount_rwf,-1000);captures.reversal_ledger=ledger.body;
 const after=await f.call('/api/admin/core/overview',{method:'GET',cookie:proposer.cookie});assert.equal(after.status,200);assert.equal(after.body.amounts.total_net_contributions_rwf,'0');captures.after_reversal=after.body;
 captures.request_identities=(await f.db.prepare(`SELECT l.user_id AS principal_id,a.idempotency_key,a.request_id FROM admin_bridge_requests a JOIN admin_principal_links l ON l.admin_user_id=a.admin_user_id ORDER BY a.created_at,a.request_id`).all()).results;
 await exportDtos('admin-dto-examples.json',captures);
});
