import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_support/fixture.mjs';
import {fixture as bearerFixture,admin,authorization} from './support/auth_fixture.mjs';

async function setup(t){
 const f=await fixture(t),a=await f.seedAccount({role:'staff',email:'notes-staff@example.test'}),login=await f.login(a),member=await f.seedMember();
 const date=new Date().toISOString(),group=randomUUID();
 await f.db.prepare(`INSERT INTO collections(id,slug,creator_user_id,title,description,collection_type,created_at,updated_at)
 VALUES(?,?,?,'Notes group','','ikimina',?,?)`).bind(group,'notes-'+group,member.id,date,date).run();
 return {f,a,login,member,group};
}
const note=(f,cookie,type,target,body,key=randomUUID(),headers={})=>f.operation(`${type}/${target}/notes`,cookie,{body},key,headers);
const read=(f,cookie,type,target,query='')=>f.call(`/api/admin/operations/${type}/${target}/notes${query}`,{method:'GET',cookie});

test('staff support notes persist encrypted, scoped and audited without leaking text into receipts or audit',async t=>{
 const {f,a,login,member,group}=await setup(t),body='Private synthetic member follow-up π';
 const saved=await note(f,login.cookie,'users',member.id,body);assert.equal(saved.status,200,JSON.stringify(saved));assert.equal(saved.body.resource_type,'operator_notes');
 const row=await f.db.prepare('SELECT * FROM admin_operator_notes').first();assert.equal(row.created_by,a.userId);assert.ok(!row.body_ciphertext.includes(body));
 const receipts=await f.db.prepare('SELECT * FROM request_receipts').all(),audit=await f.db.prepare('SELECT * FROM audit_log').all();
 assert.ok(!JSON.stringify(receipts.results).includes(body));assert.ok(!JSON.stringify(audit.results).includes(body));
 const page=await read(f,login.cookie,'users',member.id);assert.equal(page.status,200,JSON.stringify(page));assert.equal(page.body.rows[0].body,body);assert.equal(page.body.rows[0].id,saved.body.resource_id);
 assert.deepEqual(Object.keys(page.body.rows[0]).sort(),['author_name','body','created_at','created_by','id']);
 assert.equal((await read(f,login.cookie,'groups',group)).body.total,0);
 assert.equal((await note(f,login.cookie,'groups',group,'Group support note')).status,200);
 assert.equal((await read(f,login.cookie,'groups',group)).body.total,1);
});

test('lost reply and original-key retry retain exactly one note and expose a typed history receipt',async t=>{
 const {f,login,member}=await setup(t),key=randomUUID(),body='Recorded original synthetic note';
 const first=await note(f,login.cookie,'users',member.id,body,key,{'X-Test-Pause':'lost_reply'});assert.equal(first.status,200,JSON.stringify(first));
 const again=await note(f,login.cookie,'users',member.id,body,key);assert.equal(again.status,200);assert.deepEqual(again.body,first.body);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_operator_notes').first()).n,1);
 assert.equal((await note(f,login.cookie,'users',member.id,'Changed body',key)).status,409);
 const history=await f.call('/api/admin/operations/requests?limit=25&offset=0',{method:'GET',cookie:login.cookie});assert.equal(history.status,200,JSON.stringify(history));
 assert.equal(history.body.rows[0].scope,'operator_notes.post');assert.deepEqual(history.body.rows[0].receipt,first.body);
 const lookup=await f.call('/api/admin/operations/requests/'+key,{method:'GET',cookie:login.cookie});assert.equal(lookup.status,200);assert.deepEqual(lookup.body.receipt,first.body);
});

test('permission loss at commit rolls back the note, audit, receipt and request alias',async t=>{
 const {f,a,login,member}=await setup(t);
 f.setGate(async()=>f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='users.read'").bind(a.userId).run());
 const denied=await note(f,login.cookie,'users',member.id,'Private synthetic denied note',randomUUID(),{'X-Test-Pause':'before_commit'});
 assert.equal(denied.status,403,JSON.stringify(denied));
 for(const table of ['admin_operator_notes','request_receipts','admin_bridge_requests'])assert.equal((await f.db.prepare(`SELECT count(*) AS n FROM ${table}`).first()).n,0,table);
 assert.equal((await read(f,login.cookie,'users',member.id)).status,403);
});

test('new sign-ins cannot replay a retained note, and revoked cookie sessions cannot read private notes',async t=>{
 const {f,a,login,member}=await setup(t),key=randomUUID(),body='Original-session synthetic note';
 assert.equal((await note(f,login.cookie,'users',member.id,body,key)).status,200);
 const next=await f.login(a);assert.equal((await note(f,next.cookie,'users',member.id,body,key)).status,409);
 await f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(a.adminId).run();
 const denied=await read(f,login.cookie,'users',member.id);assert.equal(denied.status,401);assert.ok(!JSON.stringify(denied.body).includes(body));
});

test('note paging and filters are complete and bounded; ciphertext cannot be transplanted across entities',async t=>{
 const {f,login,member,group}=await setup(t);
 for(let i=0;i<27;i++)assert.equal((await note(f,login.cookie,'users',member.id,'Synthetic note '+i)).status,200);
 const first=await read(f,login.cookie,'users',member.id,'?limit=25&offset=0'),next=await read(f,login.cookie,'users',member.id,'?limit=25&offset=25');
 assert.equal(first.status,200);assert.equal(next.status,200);assert.equal(first.body.total,27);assert.equal(first.body.rows.length,25);assert.equal(next.body.rows.length,2);
 assert.equal(new Set([...first.body.rows,...next.body.rows].map(r=>r.id)).size,27);
 assert.equal((await read(f,login.cookie,'users',member.id,'?limit=101')).status,400);
 assert.equal((await read(f,login.cookie,'users',member.id,'?offset=0&offset=25')).status,400);
 assert.equal((await read(f,login.cookie,'groups',group)).body.rows.length,0);
 await f.db.prepare("UPDATE admin_operator_notes SET entity_type='collection',entity_id=? WHERE id=?").bind(group,first.body.rows[0].id).run();
 const bad=await read(f,login.cookie,'groups',group);assert.equal(bad.status,503);assert.equal(bad.body.error.code,'note_unavailable');assert.ok(!JSON.stringify(bad.body).includes('Synthetic note'));
});

test('note writes reject missing targets, unsupported entities, invalid content and method/field smuggling',async t=>{
 const {f,login,member}=await setup(t);
 assert.equal((await note(f,login.cookie,'users',randomUUID(),'Missing target note')).status,404);
 for(const body of ['', 'x'.repeat(2001),'bad\u0001note'])assert.equal((await note(f,login.cookie,'users',member.id,body)).status,400);
 const extra=await f.operation(`users/${member.id}/notes`,login.cookie,{body:'A valid note',permission:'users.manage'});assert.equal(extra.status,400);
 const patch=await f.call(`/api/admin/operations/users/${member.id}/notes`,{method:'PATCH',cookie:login.cookie,data:{body:'Unexpected patch'},headers:{'Idempotency-Key':randomUUID()}});assert.equal(patch.status,405);
 assert.equal((await note(f,null,'users',member.id,'No authenticated session')).status,401);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_operator_notes').first()).n,0);
});

test('the registered bearer RPC requires explicit request identity and current Admin authority',async t=>{
 const {f,member}=await setup(t),native=await f.nativeLogin(member.phone),path='/v1/rpc/admin_record_operator_note';
 const denied=await f.call(path,{origin:'https://collect.example',headers:{Authorization:`Bearer ${native.access_token}`},data:{p_entity_type:'profile',p_entity_id:member.id,p_body:'Member cannot create operator notes',p_request_id:randomUUID()}});
 assert.equal(denied.status,403,JSON.stringify(denied));assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_operator_notes').first()).n,0);
});

test('the actual bearer RPC retains a note once and refuses missing request IDs and revoked sessions',async t=>{
 const f=await bearerFixture({}, {entrypoint:'index.js'});t.after(()=>f.close());
 const operator=await admin(f),date=new Date().toISOString();
 await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(operator.id,'users.read',date).run();
 const session=await f.login(operator.identity),path='/v1/rpc/admin_record_operator_note',
  body={p_entity_type:'profile',p_entity_id:operator.id,p_body:'Private recorded bearer fixture',p_request_id:randomUUID()};
 const first=await f.call(path,body,authorization(session));assert.equal(first.status,200,JSON.stringify(first));assert.equal(first.body.ok,true);
 assert.deepEqual((await f.call(path,body,authorization(session))).body,first.body);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_operator_notes').first()).n,1);
 const {p_request_id,...withoutId}=body;assert.equal((await f.call(path,withoutId,authorization(session))).status,400);
 await f.db.prepare("UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='test' WHERE user_id=?").bind(operator.id).run();
 assert.equal((await f.call(path,body,authorization(session))).status,401);
});
