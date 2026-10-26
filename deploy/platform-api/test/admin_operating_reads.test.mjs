import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {exportDtos} from './support/dto_export.mjs';
import {fixture} from './admin_support/fixture.mjs';

async function owner(f){const account=await f.seedAccount(),login=await f.login(account);return {...await f.stepUp(login),account};}
async function group(f,admin,member){
 const response=await f.operation('groups',admin.cookie,{title:'Scoped collection',slug:'scope-'+randomUUID().slice(0,8),
  collection_type:'ikimina',owner_user_id:member.id,description:'Retained group description',
  receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Controlled scoped group'});
 assert.equal(response.status,200,JSON.stringify(response));return response.body.resource_id;
}
const read=(f,admin,path)=>f.call('/api/admin/operations/'+path,{method:'GET',cookie:admin.cookie});

test('canonical operating details retain scoped, complete pagination and recorded identities',async t=>{
 const f=await fixture(t),admin=await owner(f),member=await f.seedMember(),groupId=await group(f,admin,member);
 const date=new Date().toISOString();
 for(let i=0;i<27;i++){
  const userId=randomUUID();await f.db.prepare("INSERT INTO users(id,public_id,member_type,full_name,momo_number,created_at,updated_at) VALUES(?,?,'direct',?,'0788123456',?,?)")
   .bind(userId,String(i+20).padStart(6,'0'),'Direct member '+i,date,date).run();
  await f.db.prepare("INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,'member',1,?)").bind(randomUUID(),groupId,userId,date).run();
 }
 const detail=await read(f,admin,'groups/'+groupId);assert.equal(detail.status,200,JSON.stringify(detail));
 assert.equal(detail.body.contract_version,2);assert.equal(detail.body.model,'canonical_evidence_ledger');
 assert.equal(detail.body.resource.description,'Retained group description');assert.equal(detail.body.resource.owner_user_id,member.id);
 assert.equal(detail.body.current_actor_id,admin.account.adminId);assert.equal(detail.body.can_manage,true);
 assert.ok(detail.body.allowed_operations.includes('updateGroup'));assert.ok(!detail.body.allowed_operations.includes('createJournal'));
 assert.equal(detail.body.related.memberships.length,25);assert.deepEqual(detail.body.related_pages.memberships,{total:28,limit:25,offset:0,next_offset:25});
 assert.equal(detail.body.related.payees.length,1);assert.equal(detail.body.related.payees[0].id,groupId);
 const next=await read(f,admin,`groups/${groupId}?relation=memberships&offset=25&limit=25`);
 assert.equal(next.status,200,JSON.stringify(next));assert.equal(next.body.related.memberships.length,3);assert.equal(next.body.related_pages.memberships.next_offset,null);
 assert.equal(new Set([...detail.body.related.memberships,...next.body.related.memberships].map(r=>r.id)).size,28);
 assert.equal((await read(f,admin,`groups/${groupId}?relation=accounts`)).status,400);
 assert.equal((await read(f,admin,`groups/${groupId}?relation=memberships&offset=1&offset=2`)).status,400);
 assert.equal((await read(f,admin,`groups/${groupId}?offset=25`)).status,400);
 const user=await read(f,admin,'users/'+member.id),payee=await read(f,admin,'payees/'+groupId);
 assert.equal(user.status,200);assert.equal(user.body.related.memberships[0].group_id,groupId);
 assert.equal(payee.status,200);assert.equal(payee.body.resource.label,'Recorded receiver');
 const captured={scope:'Isolated actual workerd/D1 fixtures; no hosted or provider acceptance.',group:detail.body,group_next:next.body,user:user.body,payee:payee.body};
 captured.session=(await f.call('/api/admin/auth/session',{method:'GET',cookie:admin.cookie})).body;
 for(const kind of ['groups','users','members','payees']){
  const lookup=await read(f,admin,`lookups?kind=${kind}&limit=100${['members','payees'].includes(kind)?'&group_id='+groupId:''}`);assert.equal(lookup.status,200,JSON.stringify(lookup));captured['lookup_'+kind]=lookup.body;
 }
 const alias=await f.db.prepare('SELECT idempotency_key FROM admin_bridge_requests LIMIT 1').first();
 captured.history=(await read(f,admin,'requests?limit=25&offset=0')).body;
 captured.lookup=(await read(f,admin,'requests/'+alias.idempotency_key)).body;
 captured.lookup_key=alias.idempotency_key;
 await exportDtos('admin-operating-dto-examples.json',captured);
});

test('group lookups exclude unrelated members, receivers and authentication-only operators',async t=>{
 const f=await fixture(t),admin=await owner(f),member=await f.seedMember(),other=await f.seedMember({phone:'+250788123459'}),first=await group(f,admin,member),second=await group(f,admin,other);
 const members=await read(f,admin,`lookups?kind=members&group_id=${first}&limit=100`);
 assert.equal(members.status,200,JSON.stringify(members));assert.deepEqual(members.body.rows.map(r=>r.id),[member.id]);
 const payees=await read(f,admin,`lookups?kind=payees&group_id=${first}&limit=100`);
 assert.equal(payees.status,200,JSON.stringify(payees));assert.deepEqual(payees.body.rows.map(r=>r.group_id),[first]);assert.ok(!payees.body.rows.some(r=>r.id===second));
 assert.equal((await read(f,admin,'lookups?kind=members')).status,400);
 assert.equal((await read(f,admin,'lookups?kind=payees')).status,400);
 const users=await read(f,admin,'lookups?kind=users&limit=100');assert.equal(users.status,200);assert.equal(users.body.rows.length,2);assert.ok(users.body.rows.every(r=>r.member_type!=='operator'));
});

test('detail relations and operating capabilities remain permission bound',async t=>{
 const f=await fixture(t),admin=await owner(f),member=await f.seedMember(),groupId=await group(f,admin,member);
 const staffAccount=await f.seedAccount({email:'reader@example.test',role:'staff'}),staff=await f.login(staffAccount);
 const detail=await read(f,staff,'groups/'+groupId);assert.equal(detail.status,200,JSON.stringify(detail));assert.equal(detail.body.can_manage,false);assert.deepEqual(detail.body.allowed_operations,[]);
 await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='users.read'").bind(staffAccount.userId).run();
 const withoutPeople=await read(f,staff,'groups/'+groupId);assert.equal(withoutPeople.status,200);assert.ok(!Object.hasOwn(withoutPeople.body.related,'memberships'));
 assert.equal((await read(f,staff,`groups/${groupId}?relation=memberships`)).status,400);
 assert.equal((await read(f,staff,'lookups?kind=users')).status,403);
 const operator=await read(f,admin,'users/'+admin.account.userId);assert.equal(operator.status,200);assert.equal(operator.body.can_manage,false);assert.deepEqual(operator.body.allowed_operations,[]);
});
