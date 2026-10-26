import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture,hash} from './admin_support/fixture.mjs';

const history='/api/admin/operations/requests';
async function operator(f,options={}){
 const account=await f.seedAccount(options),login=await f.login(account);
 return {...await f.stepUp(login),account};
}
const groupBody=member=>({title:'Staff boundary group',slug:'staff-boundary-'+randomUUID(),collection_type:'ikimina',
 owner_user_id:member.id,receiver:{label:'Recorded member receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Reviewed private group creation'});
const get=(f,path,cookie)=>f.call(path,{method:'GET',cookie});
const grants=async(f,account)=>(await f.db.prepare('SELECT permission FROM admin_grants WHERE user_id=? ORDER BY permission').bind(account.userId).all()).results.map(r=>r.permission);
async function counts(f){return f.db.prepare(`SELECT (SELECT count(*) FROM collections) AS groups,
 (SELECT count(*) FROM admin_bridge_requests) AS aliases,(SELECT count(*) FROM request_receipts) AS receipts,
 (SELECT count(*) FROM audit_log) AS audits`).first();}

test('Staff reads and private creation preserve least privilege and canonical member ownership',async t=>{
 const f=await fixture(t),account=await f.seedAccount({email:'staff-boundary@example.test',role:'staff'}),password=await f.login(account),member=await f.seedMember();
 for(const area of ['overview','groups','users','members','payees','transactions','ledgers'])assert.equal((await get(f,'/api/admin/core/'+area,password.cookie)).status,200,area);
 assert.equal((await get(f,history,password.cookie)).status,200);
 const body=groupBody(member),before=await grants(f,account);
 assert.ok(before.includes('collections.create'));
 for(const forbidden of ['collections.manage','users.manage','admin_users.manage','reconciliations.review','payments.write'])assert.ok(!before.includes(forbidden));
 assert.equal((await f.operation('groups',password.cookie,body)).status,403,'password-only writes require MFA');
 assert.equal((await counts(f)).groups,0);
 const staff=await f.stepUp(password),created=await f.operation('groups',staff.cookie,body);
 assert.equal(created.status,200,JSON.stringify(created));
 const row=await f.db.prepare('SELECT creator_user_id,visibility_status,is_platform_sponsored FROM collections WHERE id=?').bind(created.body.resource_id).first();
 assert.deepEqual(row,{creator_user_id:member.id,visibility_status:'private',is_platform_sponsored:0});
 const membership=(await f.db.prepare('SELECT user_id,role FROM memberships WHERE collection_id=?').bind(created.body.resource_id).all()).results;
 assert.deepEqual(membership,[{user_id:member.id,role:'owner'}]);
 assert.deepEqual(await grants(f,account),before,'private creation never grants operator or group authority');
 assert.equal((await f.db.prepare('SELECT role FROM admin_users WHERE id=?').bind(account.adminId).first()).role,'staff');
 const checkpoint=await counts(f);
 assert.equal((await f.operation('users',staff.cookie,{display_name:'Forged admin',phone_e164:'+250788123459',reason:'Forbidden member creation'})).status,403);
 assert.equal((await f.call(`/api/admin/operations/groups/${created.body.resource_id}`,{method:'PATCH',cookie:staff.cookie,data:{title:'Forbidden edit',expected_version:1,reason:'Forbidden group change'},headers:{'Idempotency-Key':randomUUID()}})).status,403);
 assert.equal((await f.call('/api/admin/team/invite',{cookie:staff.cookie,data:{email:'forged-admin@example.test',role:'admin'}})).status,403);
 assert.equal((await f.operation('groups',staff.cookie,{...groupBody(member),role:'owner',permissions:['admin_users.manage']})).status,400);
 assert.deepEqual(await counts(f),checkpoint,'denied changes retain no domain, request or audit effect');
 assert.deepEqual(await grants(f,account),before);
});

test('request history pages and exact lookups are account-scoped and reject scope injection',async t=>{
 const f=await fixture(t),first=await operator(f),other=await operator(f,{email:'other-history@example.test',role:'admin'}),member=await f.seedMember(),keys=[];
 for(let i=0;i<3;i++){const key=randomUUID();keys.push(key);assert.equal((await f.operation('groups',first.cookie,groupBody(member),key)).status,200);}
 const foreignKey=randomUUID(),foreign=await f.operation('groups',other.cookie,groupBody(member),foreignKey);assert.equal(foreign.status,200);
 const page=await get(f,history+'?limit=2&offset=0',first.cookie),tail=await get(f,history+'?limit=2&offset=2',first.cookie);
 assert.equal(page.status,200);assert.equal(tail.status,200);assert.equal(page.body.total,3);assert.equal(tail.body.total,3);
 assert.equal(page.body.rows.length,2);assert.equal(tail.body.rows.length,1);
 const combined=[...page.body.rows,...tail.body.rows];assert.equal(new Set(combined.map(r=>r.id)).size,3);
 assert.deepEqual(new Set(combined.map(r=>r.idempotency_key)),new Set(keys));
 for(const row of combined){assert.equal(row.scope,'groups.post');assert.equal(row.status,'succeeded');assert.equal(row.id,row.receipt.request_id);assert.equal(row.receipt.resource_type,'groups');}
 assert.deepEqual((await get(f,history+'?limit=2&offset=0',first.cookie)).body,page.body,'stable page ordering');
 const foreignLookup=await get(f,history+'/'+foreignKey,first.cookie);assert.equal(foreignLookup.status,200);assert.equal(foreignLookup.body.status,'not_found');
 assert.ok(!('request_id' in foreignLookup.body));assert.ok(!JSON.stringify(foreignLookup.body).includes(foreign.body.resource_id));
 assert.equal((await get(f,history,other.cookie)).body.total,1);
 assert.deepEqual((await get(f,history+'?offset=3',first.cookie)).body.rows,[]);
 for(const query of ['?limit=0','?limit=101','?offset=-1','?offset=2147483648','?limit=1&limit=2','?admin_user_id='+other.account.adminId])assert.equal((await get(f,history+query,first.cookie)).status,400,query);
 assert.equal((await get(f,history+'/'+keys[0]+'?admin_user_id='+other.account.adminId,first.cookie)).status,400);
 await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='account.manage'").bind(first.account.userId).run();
 assert.equal((await get(f,history,first.cookie)).status,403);assert.equal((await get(f,history+'/'+keys[0],first.cookie)).status,403);
});

test('discarded post-commit response is recovered by exact read without replay or payload substitution',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),key=randomUUID(),body=groupBody(member);let postCommitFaults=0;
 f.setGate(async event=>{assert.equal(event.phase,'lost_reply');postCommitFaults++;});
 // Deliberately discard the client reply after the fixture injects a D1 post-commit fault.
 // This proves retained outcome recovery, not a hosted browser/network disconnect.
 await f.operation('groups',admin.cookie,body,key,{'X-Test-Pause':'lost_reply'});
 assert.equal(postCommitFaults,1);
 const state=await counts(f);assert.equal(state.groups,1);assert.equal(state.aliases,1);assert.equal(state.receipts,1);
 const retained=await f.db.prepare('SELECT r.response_json FROM admin_bridge_requests a JOIN request_receipts r ON r.request_id=a.request_id WHERE a.admin_user_id=? AND a.idempotency_key=?').bind(admin.account.adminId,key).first();
 const outcome=await get(f,history+'/'+key,admin.cookie);assert.equal(outcome.status,200);assert.equal(outcome.body.status,'succeeded');assert.deepEqual(outcome.body.receipt,JSON.parse(retained.response_json));
 assert.deepEqual(await counts(f),state,'GET recovery never resends or mutates the original');
 const mismatch=await f.operation('groups',admin.cookie,{...body,title:'Substituted payload'},key);assert.equal(mismatch.status,409);assert.equal(mismatch.body.error.code,'request_conflict');
 assert.deepEqual(await counts(f),state);
 const password=await f.login(admin.account),afterSignIn=await get(f,history+'/'+key,password.cookie);
 assert.equal(afterSignIn.status,200);assert.deepEqual(afterSignIn.body,outcome.body,'same account can read its original after a new sign-in');
 const replay=await f.operation('groups',password.cookie,body,key);assert.equal(replay.status,403,'password-only sign-in can read status but cannot replay the original');
 assert.deepEqual(await counts(f),state);
});

test('an alias without a retained receipt remains unconfirmed and read-only rather than not-found or success',async t=>{
 const f=await fixture(t),admin=await operator(f),key=randomUUID(),requestId=randomUUID(),timestamp=new Date().toISOString();
 const session=await f.db.prepare('SELECT auth_session_id FROM admin_sessions WHERE token_hash=?').bind(hash(admin.cookie.split('=')[1])).first();
 // Explicit inconsistent-state fixture: normal mutation admission commits alias+receipt atomically.
 await f.db.prepare('INSERT INTO admin_bridge_requests(admin_user_id,idempotency_key,request_id,session_id,operation,body_sha256,created_at) VALUES(?,?,?,?,?,?,?)')
  .bind(admin.account.adminId,key,requestId,session.auth_session_id,'operations.groups.POST',hash('declared unresolved fixture'),timestamp).run();
 const state=await counts(f),lookup=await get(f,history+'/'+key,admin.cookie);
 assert.equal(lookup.status,200);assert.equal(lookup.body.status,'unconfirmed');assert.equal(lookup.body.request_id,requestId);assert.equal(lookup.body.receipt,null);
 const list=await get(f,history,admin.cookie);assert.equal(list.status,200);assert.equal(list.body.total,1);assert.equal(list.body.rows[0].status,'unconfirmed');assert.equal(list.body.rows[0].receipt,null);
 assert.equal((await get(f,history+'/'+randomUUID(),admin.cookie)).body.status,'not_found');
 assert.deepEqual(await counts(f),state,'status reads do not invent a receipt, clear an original, or execute an effect');
});
