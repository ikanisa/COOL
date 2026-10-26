import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_support/fixture.mjs';

async function setup(t){const f=await fixture(t),a=await f.seedAccount({role:'staff',email:'sync-staff@example.test'}),login=await f.login(a);return {f,a,login};}
async function event(f,a,type='payment',details='private synthetic audit payload'){
 return f.db.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,details_json,created_at)
 VALUES(?,(SELECT auth_session_id FROM admin_sessions WHERE user_id=? LIMIT 1),'test.change',?,?,?,?) RETURNING id`)
 .bind(a.userId,a.adminId,type,randomUUID(),JSON.stringify({private:details}),new Date().toISOString()).first();
}
const read=(f,cookie,query='',headers={})=>f.call('/api/admin/sync'+query,{method:'GET',cookie,headers});

test('cookie updates return only capability-scoped IDs and never private audit fields',async t=>{
 const {f,a,login}=await setup(t);await event(f,a);const result=await read(f,login.cookie,'?areas=payments,ledger,reconciliations');
 assert.equal(result.status,200,JSON.stringify(result));assert.equal(result.body.contract_version,1);
 assert.deepEqual(result.body.events.map(e=>e.area),['payments','ledger','reconciliations']);
 assert.ok(result.body.events.every(e=>Object.keys(e).sort().join(',')==='area,id'));
 assert.ok(!JSON.stringify(result.body).includes('private synthetic'));assert.ok(!JSON.stringify(result.body).includes(a.userId));
 assert.equal(result.headers.get('Cache-Control'),'no-store');
 const end=await read(f,login.cookie,'?areas=payments,ledger,reconciliations&cursor='+result.body.cursor);assert.equal(end.body.events.length,0);assert.equal(end.body.cursor,result.body.cursor);
});

test('complete expanded rows survive bounded pagination without lost notifications',async t=>{
 const {f,a,login}=await setup(t);for(let n=0;n<9;n++)await event(f,a);
 let cursor='0';const ids=new Set();
 for(let n=0;n<9;n++){
  const r=await read(f,login.cookie,'?areas=payments,ledger,reconciliations&limit=4&cursor='+cursor);
  assert.equal(r.status,200,JSON.stringify(r));assert.equal(r.body.events.length,3);assert.ok(BigInt(r.body.cursor)>BigInt(cursor));cursor=r.body.cursor;
  for(const e of r.body.events){assert.ok(!ids.has(e.id));ids.add(e.id);}
 }
 assert.equal(ids.size,27);assert.equal((await read(f,login.cookie,'?areas=payments&cursor='+cursor)).body.events.length,0);
});

test('request invalidation is personal while unrelated domain and unknown entity changes stay filtered',async t=>{
 const {f,a,login}=await setup(t),other=await f.seedAccount({role:'admin',email:'other-sync@example.test'});await f.login(other);
 await event(f,other,'request');await event(f,other,'privacy_review');
 const mine=await event(f,a,'request');
 const r=await read(f,login.cookie,'?areas=requests');assert.equal(r.status,200);assert.deepEqual(r.body.events,[{id:mine.id+':requests',area:'requests'}]);
 const privateArea=await read(f,login.cookie,'?areas=profiles');assert.equal(privateArea.status,200);assert.equal(privateArea.body.events.length,0);assert.equal(privateArea.body.cursor,'0');
});

test('cookie sync refuses missing auth, wrong origin, unsupported methods and malformed filters',async t=>{
 const {f,login}=await setup(t);assert.equal((await read(f,null)).status,401);
 assert.equal((await read(f,login.cookie,'',{'Sec-Fetch-Site':'cross-site'})).status,403);
 assert.equal((await f.call('/api/admin/sync',{cookie:login.cookie,data:{}})).status,405);
 assert.equal((await f.call('/api/admin/sync/extra',{method:'GET',cookie:login.cookie})).status,404);
 for(const q of ['?areas=audit','?areas=payments,payments','?areas=','?cursor=-1','?cursor=1e3','?cursor=9007199254740992','?cursor=0&cursor=1','?limit=101','?limit=2&areas=payments,ledger,reconciliations','?fields=details_json']){
  assert.equal((await read(f,login.cookie,q)).status,400,q);
 }
});

test('lost grants and changed roles cannot authorize a stale read snapshot',async t=>{
 for(const change of ['grant','role','revoked']){
  const {f,a,login}=await setup(t);await event(f,a);
  f.setGate(async()=>change==='grant'?f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='payments.read'").bind(a.userId).run():change==='role'?f.db.prepare("UPDATE admin_users SET role='admin' WHERE id=?").bind(a.adminId).run():f.db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='test' WHERE user_id=?").bind(a.userId).run());
  const r=await read(f,login.cookie,'?areas=payments',{'X-Test-Pause':'sync_read'});assert.equal(r.status,403,JSON.stringify({change,...r}));assert.ok(!r.body.events);
 }
});

test('the current granted area cap is enforced before scanning any private events',async t=>{
 const {f,a,login}=await setup(t);await event(f,a);await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='payments.read'").bind(a.userId).run();
 assert.equal((await read(f,login.cookie,'?areas=payments')).status,403);
 const r=await read(f,login.cookie);assert.equal(r.status,200);assert.ok(r.body.events.every(e=>e.area!=='payments'&&e.area!=='payment_intents'));
 await f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(a.adminId).run();assert.equal((await read(f,login.cookie)).status,401);
});
