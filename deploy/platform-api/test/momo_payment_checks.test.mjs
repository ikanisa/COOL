import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_sms_support/fixture.mjs';

async function setup(t){
 const f=await fixture(t,{MOMO_PROCESSING_PAUSED:'true'},{migrationsThrough:15}),account=await f.seedAccount(),owner=await f.stepUp(await f.login(account)),member=await f.seedMember();
 const group=await f.operation('groups',owner.cookie,{title:'Member check queue',slug:'member-check-queue',collection_type:'ikimina',owner_user_id:member.id,
  receiver:{label:'Controlled check receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Create controlled operator payment-check destination'});assert.equal(group.status,200,JSON.stringify(group));
 const native=await f.nativeLogin(member.phone),groupId=group.body.resource_id;
 const intent=await f.call('/v1/rpc/create_contribution_intent',{origin:'https://collect.example',headers:{Authorization:'Bearer '+native.access_token},data:{collection:groupId,p_expected_amount_rwf:5000,p_request_id:randomUUID()}});assert.equal(intent.status,200);
 const read=(suffix='',cookie=owner.cookie)=>f.call('/api/admin/momo/transactions/payment-checks'+suffix,{method:'GET',cookie});
 const request=async(extra={})=>{const id=randomUUID(),body={p_kind:'payment_review',p_collection_id:groupId,p_intent_id:intent.body.id,p_request_id:id,
  p_provider_reference:'MEMBER-UNVERIFIED-0007',p_note:'Member asks for a check; this does not prove a payment.',...extra};
  const result=await f.call('/v1/rpc/create_mobile_support_request',{origin:'https://collect.example',headers:{Authorization:'Bearer '+native.access_token},data:body});assert.equal(result.status,200,JSON.stringify(result));return {id,body,result};};
 return {f,account,owner,member,groupId,native,intent:intent.body,read,request};
}

test('operator payment-check queue exposes the actual typed member request as unverified context and receives ID-only payment invalidation',async t=>{
 const s=await setup(t),before=await s.f.call('/api/admin/sync?areas=payments&limit=100',{method:'GET',cookie:s.owner.cookie});assert.equal(before.status,200);
 const requested=await s.request(),page=await s.read();assert.equal(page.status,200,JSON.stringify(page));assert.equal(page.body.total,1);assert.equal(page.body.rows.length,1);assert.equal(page.body.next_offset,null);
 const row=page.body.rows[0];assert.equal(row.id,requested.id);assert.equal(row.member_id,s.member.id);assert.equal(row.member_public_id,s.member.public_id);assert.equal(row.member_name,'Recorded Member');
 assert.equal(row.group_id,s.groupId);assert.equal(row.group_name,'Member check queue');assert.equal(row.intent_id,s.intent.id);assert.equal(row.expected_amount_minor,5000);assert.equal(row.currency,'RWF');
 assert.equal(row.provider_reference,requested.body.p_provider_reference);assert.equal(row.evidence_note,requested.body.p_note);assert.equal(row.provider_reference_verified,false);assert.equal(row.source,'member_request');assert.equal(row.request_status,'received');assert.equal(row.financial_effects,0);assert.ok(Number.isFinite(Date.parse(row.requested_at)));
 const updates=await s.f.call(`/api/admin/sync?areas=payments&limit=100&cursor=${before.body.cursor}`,{method:'GET',cookie:s.owner.cookie});assert.equal(updates.status,200,JSON.stringify(updates));assert.ok(updates.body.events.some(event=>event.area==='payments'));
 assert.ok(updates.body.events.every(event=>Object.keys(event).sort().join(',')==='area,id'));assert.ok(!JSON.stringify(updates.body).includes(requested.body.p_provider_reference));assert.ok(!JSON.stringify(updates.body).includes(requested.body.p_note));
 for(const table of ['payments','ledger_entries','notification_events'])assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n,0);
});

test('member check queue requires all three live capabilities and rejects unsupported or unbounded read filters',async t=>{
 const s=await setup(t);await s.request();
 assert.equal((await s.read('',null)).status,401);
 for(const permission of ['payments.read','users.read','collections.read']){
  await s.f.db.prepare('DELETE FROM admin_grants WHERE user_id=? AND permission=?').bind(s.account.userId,permission).run();assert.equal((await s.read()).status,403,permission);
  await s.f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_by,granted_at) VALUES(?,?,?,?)').bind(s.account.userId,permission,'controlled-test-reinstatement',new Date().toISOString()).run();
 }
 for(const suffix of ['?limit=0','?limit=101','?offset=-1','?offset=2147483648','?limit=1&limit=2','?search=unreviewed','?status=credited'])assert.equal((await s.read(suffix)).status,400,suffix);
 assert.equal((await s.read('?limit=1&offset=0')).status,200);
});

test('bounded payment-check pages include only exact valid typed owner/group/intent context and safely exclude malformed legacy records',async t=>{
 const s=await setup(t),first=await s.request(),second=await s.request({p_provider_reference:null,p_note:null});
 const context={contract_version:1,intent_id:s.intent.id,collection_id:s.groupId,provider_reference:null,evidence_note:null};
 const variants=['{not valid JSON',JSON.stringify({...context,contract_version:2}),JSON.stringify({...context,intent_id:randomUUID()}),JSON.stringify({...context,collection_id:randomUUID()}),
  JSON.stringify({...context,provider_reference:7}),JSON.stringify({...context,evidence_note:'x'.repeat(2001)}),JSON.stringify({...context,extra:'not part of the typed contract'}),JSON.stringify(Object.fromEntries(Object.entries(context).filter(([key])=>key!=='provider_reference')))];
 for(const message of variants)await s.f.db.prepare("INSERT INTO support_requests(id,user_id,collection_id,kind,message,created_at) VALUES(?,?,?,'payment_review',?,?)").bind(randomUUID(),s.member.id,s.groupId,message,new Date().toISOString()).run();
 const other=await s.f.seedMember({phone:'+250788654321'});
 await s.f.db.prepare("INSERT INTO support_requests(id,user_id,collection_id,kind,message,created_at) VALUES(?,?,?,'payment_review',?,?)").bind(randomUUID(),other.id,s.groupId,JSON.stringify(context),new Date().toISOString()).run();
 await s.f.db.prepare("INSERT INTO support_requests(id,user_id,collection_id,kind,message,created_at) VALUES(?,?,?,'support',?,?)").bind(randomUUID(),s.member.id,s.groupId,JSON.stringify(context),new Date().toISOString()).run();
 const a=await s.read('?limit=1&offset=0'),b=await s.read('?limit=1&offset=1'),empty=await s.read('?limit=1&offset=2');
 for(const page of [a,b,empty])assert.equal(page.status,200,JSON.stringify(page));assert.equal(a.body.total,2);assert.equal(a.body.next_offset,1);assert.equal(b.body.next_offset,null);assert.equal(empty.body.rows.length,0);
 assert.deepEqual([a.body.rows[0].id,b.body.rows[0].id].sort(),[first.id,second.id].sort());
});
