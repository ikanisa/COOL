import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_support/fixture.mjs';

async function operator(f,options={}){const account=await f.seedAccount(options);return {...await f.stepUp(await f.login(account)),account};}
const cancel=(f,admin,target,{key=randomUUID(),reason='Cancel the original unconfirmed reference',headers={},origin}={})=>
 f.call(`/api/admin/operations/requests/${target}/cancel`,{cookie:admin.cookie,data:{reason},headers:{'Idempotency-Key':key,...headers},...(origin?{origin}:{})});
async function groupBody(f){const member=await f.seedMember();return {title:'Cancellation boundary',slug:'cancel-group',collection_type:'ikimina',
 owner_user_id:member.id,receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Create a retained fixture group'};}

test('cancelling while a write waits atomically blocks the original and every delayed retry',async t=>{
 const f=await fixture(t),admin=await operator(f),data=await groupBody(f),key=randomUUID(),cancelKey=randomUUID();let cancellation;
 f.setGate(async()=>{cancellation=await cancel(f,admin,key,{key:cancelKey});assert.equal(cancellation.status,200,JSON.stringify(cancellation));});
 const first=await f.operation('groups',admin.cookie,data,key,{'X-Test-Pause':'before_commit'});
 assert.equal(first.status,409,JSON.stringify(first));assert.equal(cancellation.body.status,'cancelled');
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,0);
 assert.equal((await f.operation('groups',admin.cookie,data,key)).status,409);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,0);
 const lookup=await f.call('/api/admin/operations/requests/'+key,{method:'GET',cookie:admin.cookie});assert.equal(lookup.body.status,'cancelled');assert.equal(lookup.body.receipt,null);
 const replay=await cancel(f,admin,key,{key:cancelKey});assert.deepEqual(replay.body,cancellation.body);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='admin.request.cancel'").first()).n,1);
 const history=await f.call('/api/admin/operations/requests',{method:'GET',cookie:admin.cookie});assert.equal(history.status,200);assert.equal(history.body.rows[0].scope,'requests.cancel');assert.equal(history.body.rows[0].status,'cancelled');
 assert.equal((await cancel(f,admin,randomUUID(),{key:cancelKey})).status,409,'a cancellation key cannot be reused against another original reference');
});

test('a committed write is returned as recorded and is never represented as cancelled',async t=>{
 const f=await fixture(t),admin=await operator(f),body=await groupBody(f),key=randomUUID();
 const created=await f.operation('groups',admin.cookie,body,key);assert.equal(created.status,200);
 const result=await cancel(f,admin,key);assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.body.status,'succeeded');assert.deepEqual(result.body.receipt,created.body);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,1);
 const lookup=await f.call('/api/admin/operations/requests/'+key,{method:'GET',cookie:admin.cookie});assert.equal(lookup.body.status,'succeeded');
});

test('password-only, wrong-origin and malformed cancellation requests create no blocking alias',async t=>{
 const f=await fixture(t),account=await f.seedAccount(),login=await f.login(account),key=randomUUID();
 assert.equal((await cancel(f,login,key)).status,403);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_bridge_requests').first()).n,0);
 const admin={...await f.stepUp(login),account};
 assert.equal((await cancel(f,admin,key,{origin:'https://untrusted.example'})).status,403);
 assert.equal((await cancel(f,admin,key,{reason:'short'})).status,400);
 assert.equal((await cancel(f,admin,key,{key})).status,400);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_bridge_requests').first()).n,0);
});

test('a request reference from another account cannot cancel that account effect',async t=>{
 const f=await fixture(t),first=await operator(f),second=await operator(f,{email:'other@example.test',role:'admin'}),body=await groupBody(f),key=randomUUID();
 const created=await f.operation('groups',first.cookie,body,key);assert.equal(created.status,200);
 const result=await cancel(f,second,key);assert.equal(result.status,200);assert.equal(result.body.status,'cancelled');assert.notEqual(result.body.request_id,created.body.request_id);
 const original=await f.call('/api/admin/operations/requests/'+key,{method:'GET',cookie:first.cookie});assert.equal(original.body.status,'succeeded');assert.deepEqual(original.body.receipt,created.body);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM collections').first()).n,1);
});

test('revoking cancellation authority during commit retains neither alias nor cancellation receipt',async t=>{
 const f=await fixture(t),admin=await operator(f),key=randomUUID();
 f.setGate(async()=>f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='account.manage'").bind(admin.account.userId).run());
 const result=await cancel(f,admin,key,{headers:{'X-Test-Pause':'before_commit'}});
 assert.ok([401,403].includes(result.status),JSON.stringify(result));assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_bridge_requests').first()).n,0);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM request_receipts').first()).n,0);
});
