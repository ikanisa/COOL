import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_sms_support/fixture.mjs';

async function setup(t){
 const f=await fixture(t,{MOMO_PROCESSING_PAUSED:'true'},{migrationsThrough:15}),account=await f.seedAccount(),owner=await f.stepUp(await f.login(account)),member=await f.seedMember();
 const group=await f.operation('groups',owner.cookie,{title:'Payment support',slug:'payment-support',collection_type:'ikimina',owner_user_id:member.id,receiver:{label:'Controlled support receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Create controlled payment-support destination'});assert.equal(group.status,200,JSON.stringify(group));
 const session=await f.nativeLogin(member.phone),collectionId=group.body.resource_id;
 const intent=await f.call('/v1/rpc/create_contribution_intent',{origin:'https://collect.example',headers:{Authorization:'Bearer '+session.access_token},data:{collection:collectionId,p_expected_amount_rwf:5000,p_request_id:randomUUID()}});assert.equal(intent.status,200,JSON.stringify(intent));
 const data={p_kind:'payment_review',p_collection_id:collectionId,p_intent_id:intent.body.id,p_request_id:randomUUID(),p_provider_reference:'001234(ABC)',p_note:'Member supplied note; provider settlement remains unverified.'};
 const call=(body=data,current=session,headers={})=>f.call('/v1/rpc/create_mobile_support_request',{origin:'https://collect.example',headers:{Authorization:'Bearer '+current.access_token,...headers},data:body});
 return {f,member,session,collectionId,intent: intent.body,data,call};
}

test('member payment check retains exact context and exact retries without financial effects',async t=>{
 const s=await setup(t),received=await s.call();assert.equal(received.status,200,JSON.stringify(received));
 assert.deepEqual(received.body,{id:s.data.p_request_id,status:'received',collection_id:s.collectionId,intent_id:s.intent.id,financial_effects:0});
 assert.deepEqual((await s.call()).body,received.body);
 assert.equal((await s.call({...s.data,p_note:'A changed payload must use a new request.'})).status,409);
 const rows=(await s.f.db.prepare('SELECT * FROM support_requests').all()).results;assert.equal(rows.length,1);assert.equal(rows[0].user_id,s.member.id);assert.equal(rows[0].kind,'payment_review');
 assert.deepEqual(JSON.parse(rows[0].message),{contract_version:1,intent_id:s.intent.id,collection_id:s.collectionId,provider_reference:'001234(ABC)',evidence_note:s.data.p_note});
 for(const table of ['payments','ledger_entries','notification_events'])assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n,0,table);
 assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='create_mobile_support_request'").first()).n,1);
 const optional=await s.call({...s.data,p_request_id:randomUUID(),p_provider_reference:null,p_note:null});assert.equal(optional.status,200,JSON.stringify(optional));
});

test('member payment check rejects foreign or mismatched intent and stale sign-in at commit',async t=>{
 const s=await setup(t),other=await s.f.nativeLogin('+250788654321');
 assert.equal((await s.call(s.data,other)).status,404);
 assert.equal((await s.call({...s.data,p_collection_id:randomUUID()})).status,404);
 assert.equal((await s.call({...s.data,p_intent_id:randomUUID()})).status,404);
 assert.equal((await s.call({...s.data,p_provider_reference:'x'.repeat(161)})).status,400);
 const claims=JSON.parse(Buffer.from(s.session.access_token.split('.')[1],'base64url'));
 s.f.setGate(async event=>{assert.equal(event.phase,'before_commit');await s.f.db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='controlled_payment_review_logout' WHERE id=?").bind(claims.session_id).run();});
 const denied=await s.call(s.data,s.session,{'X-Test-Pause':'before_commit'});assert.equal(denied.status,403,JSON.stringify(denied));
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM support_requests').first()).n,0);
 assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM request_receipts WHERE operation='create_mobile_support_request'").first()).n,0);
});

test('member payment check rechecks exact intent ownership in the committing batch',async t=>{
 const s=await setup(t),other=await s.f.seedMember({phone:'+250788654321'});
 s.f.setGate(async()=>{await s.f.db.prepare('UPDATE payment_intents SET member_id=? WHERE id=?').bind(other.id,s.intent.id).run();});
 const denied=await s.call(s.data,s.session,{'X-Test-Pause':'before_commit'});assert.equal(denied.status,409,JSON.stringify(denied));
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM support_requests').first()).n,0);
 assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM request_receipts WHERE operation='create_mobile_support_request'").first()).n,0);
});
