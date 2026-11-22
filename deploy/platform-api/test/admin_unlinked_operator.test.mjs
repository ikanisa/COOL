import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_support/fixture.mjs';
import {lists} from '../src/admin_records.js';

const timestamp='2026-10-16T12:00:00.000Z';
const errorCode=response=>response.body.error?.code;
const get=(f,cookie,path)=>f.call(path,{method:'GET',cookie});
const detail=(f,cookie,id)=>get(f,cookie,'/api/admin/operations/users/'+id);
async function seedPerson(f,{memberType='operator',name='Synthetic unlinked operator',id=randomUUID(),publicId}={}){
 publicId??=String((await f.db.prepare('SELECT count(*) AS n FROM users').first()).n).padStart(6,'0');
 await f.db.prepare('INSERT INTO users(id,public_id,member_type,full_name,created_at,updated_at) VALUES(?,?,?,?,?,?)').bind(id,publicId,memberType,name,timestamp,timestamp).run();
 return {id,publicId,memberType};
}
async function snapshot(f,ids){
 const users=[];for(const id of ids)users.push(await f.db.prepare('SELECT id,access_status,revision FROM users WHERE id=?').bind(id).first());
 return {users,grants:(await f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all()).results,
  roles:(await f.db.prepare('SELECT * FROM admin_role_assignments ORDER BY user_id,role').all()).results,
  receipts:(await f.db.prepare('SELECT count(*) AS n FROM request_receipts').first()).n,
  memberships:(await f.db.prepare('SELECT count(*) AS n FROM memberships').first()).n};
}

// The unchanged sealed harness bundles the actual router and uses real local D1
// migrations. Only initial records and provider acknowledgements are fixtures.
test('canonical users expose unlinked Operator and preserve linked and member identities through the actual router',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),login=await f.login(owner),session=await f.stepUp(login),cookie=session.cookie;
 const unlinked=await seedPerson(f),admin=await f.seedAccount({email:'representation-admin@collect-auth.invalid',role:'admin'}),staff=await f.seedAccount({email:'representation-staff@collect-auth.invalid',role:'staff'});
 const app=await f.seedMember({phone:'+250788120001'}),direct=await f.seedMember({phone:'+250788120002'});
 await f.db.prepare("UPDATE users SET member_type='direct' WHERE id=?").bind(direct.id).run();
 const linkedApp=await f.seedAccount({email:'representation-linked-app@collect-auth.invalid',role:'admin'}),linkedDirect=await f.seedAccount({email:'representation-linked-direct@collect-auth.invalid',role:'staff'});
 await f.db.prepare("UPDATE users SET member_type='app' WHERE id=?").bind(linkedApp.userId).run();
 await f.db.prepare("UPDATE users SET member_type='direct' WHERE id=?").bind(linkedDirect.userId).run();

 await t.test('list includes the unlinked operator with exact Collect identifiers and null Admin tuple',async()=>{
  const response=await get(f,cookie,'/api/admin/core/users?limit=100');assert.equal(response.status,200);
  assert.equal(response.body.total,8);assert.equal(response.body.rows.length,8);
  const row=response.body.rows.find(v=>v.id===unlinked.id);assert.ok(row);
  assert.deepEqual(row.user_types,['Operator']);assert.equal(row.member_type,'operator');
  assert.equal(row.person_id,unlinked.id);assert.equal(row.collect_user_id,unlinked.id);assert.equal(row.public_id,unlinked.publicId);
  for(const key of ['operator_admin_id','operator_role','operator_status','operator_public_id'])assert.equal(row[key],null,key);
  assert.equal(row.whatsapp_number,null);
  assert.equal(Object.hasOwn(row,'joined_operator_admin_id'),false,'join validation is internal only');
 });
 await t.test('unlinked operator detail is read-only and member selectors exclude it',async()=>{
  const response=await detail(f,cookie,unlinked.id);assert.equal(response.status,200);
  assert.deepEqual(response.body.resource.user_types,['Operator']);assert.equal(response.body.can_manage,false);assert.deepEqual(response.body.allowed_operations,[]);
  const lookup=await get(f,cookie,'/api/admin/operations/lookups?kind=users&limit=100');assert.equal(lookup.status,200);
  assert.equal(lookup.body.rows.some(v=>v.id===unlinked.id),false);
  assert.equal(lookup.body.rows.some(v=>v.member_type==='operator'),false);
 });
 await t.test('linked Owner, Admin and Staff retain exact roles and source identifiers',async()=>{
  for(const account of [owner,admin,staff]){
   const response=await detail(f,cookie,account.userId);assert.equal(response.status,200);
   const row=response.body.resource;assert.deepEqual(row.user_types,[account.role==='staff'?'Staff':'Admin']);
   assert.equal(row.operator_admin_id,account.adminId);assert.equal(row.operator_role,account.role);assert.equal(row.operator_status,'active');
   assert.equal(row.operator_public_id,row.public_id);assert.equal(row.collect_user_id,account.userId);
   assert.equal(response.body.can_manage,false);assert.deepEqual(response.body.allowed_operations,[]);
  }
 });
 await t.test('ordinary App/Direct and intentionally overlapping linked App/Direct preserve exact type order',async()=>{
  for(const [id,types,memberType] of [[app.id,['App'],'app'],[direct.id,['Direct'],'direct'],[linkedApp.userId,['Admin','App'],'app'],[linkedDirect.userId,['Staff','Direct'],'direct']]){
   const response=await detail(f,cookie,id);assert.equal(response.status,200);
   assert.deepEqual(response.body.resource.user_types,types);assert.equal(response.body.resource.member_type,memberType);
   if(types.length===1)for(const key of ['operator_admin_id','operator_role','operator_status','operator_public_id'])assert.equal(response.body.resource[key],null,key);
  }
  assert.equal((await detail(f,cookie,app.id)).body.resource.whatsapp_number,app.phone);
  assert.equal((await detail(f,cookie,direct.id)).body.resource.whatsapp_number,null);
 });
 const groupId=randomUUID();
 await f.db.prepare('INSERT INTO collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES(?,?,?,?,?,?,?)').bind(groupId,'representation-'+groupId,app.id,'Synthetic representation group','ikimina',timestamp,timestamp).run();
 await t.test('unlinked and linked operator user updates and membership creation remain denied without resource, grant or receipt writes',async()=>{
  const targets=[unlinked.id,owner.userId,admin.userId,staff.userId],before=await snapshot(f,targets);
  for(const id of targets){
   const changed=await f.call('/api/admin/operations/users/'+id,{method:'PATCH',cookie,headers:{'Idempotency-Key':randomUUID()},data:{status:'suspended',expected_version:1,reason:'Synthetic protected operator regression'}});
   assert.equal(changed.status,501);assert.equal(errorCode(changed),'operation_unavailable');
   const membership=await f.operation('memberships',cookie,{group_id:groupId,user_id:id,role:'member',status:'active',reason:'Synthetic protected operator regression'});
   assert.equal(membership.status,409);assert.equal(errorCode(membership),'stale_state');
  }
  assert.deepEqual(await snapshot(f,targets),before);
 });
 await t.test('linked App/Direct generic user update protection remains intact',async()=>{
  const targets=[linkedApp.userId,linkedDirect.userId],before=await snapshot(f,targets);
  for(const id of targets){
   const response=await f.call('/api/admin/operations/users/'+id,{method:'PATCH',cookie,headers:{'Idempotency-Key':randomUUID()},data:{status:'suspended',expected_version:1,reason:'Synthetic linked principal regression'}});
   assert.equal(response.status,501);assert.equal(errorCode(response),'operation_unavailable');
  }
  assert.deepEqual(await snapshot(f,targets),before);
 });
 await t.test('existing mixed identity membership policy remains supported and does not change grants',async()=>{
  const grants=await f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all();
  for(const id of [linkedApp.userId,linkedDirect.userId]){
   const response=await f.operation('memberships',cookie,{group_id:groupId,user_id:id,role:'member',status:'active',reason:'Synthetic existing mixed identity membership policy'});
   assert.equal(response.status,200);assert.equal(response.body.status,'succeeded');
   assert.equal((await f.db.prepare('SELECT active FROM memberships WHERE collection_id=? AND user_id=?').bind(groupId,id).first()).active,1);
  }
  assert.deepEqual((await f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all()).results,grants.results);
 });
 await t.test('real D1 malformed public and Admin identifiers fail closed at the actual read route',async()=>{
  await f.db.prepare('UPDATE users SET public_id=? WHERE id=?').bind('bad-id',unlinked.id).run();
  const invalidPublic=await detail(f,cookie,unlinked.id);assert.equal(invalidPublic.status,503);assert.equal(errorCode(invalidPublic),'invalid_source_data');
  await f.db.prepare('UPDATE users SET public_id=? WHERE id=?').bind(unlinked.publicId,unlinked.id).run();
  const bad=await seedPerson(f,{name:'Synthetic malformed linked principal'});
  await f.db.prepare("INSERT INTO admin_users(id,email,role,status,created_at,updated_at) VALUES(?,?,'staff','invited',?,?)").bind('not-an-admin-uuid','malformed-link@collect-auth.invalid',1,1).run();
  await f.db.prepare('INSERT INTO admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(?,?,?,?)').bind('not-an-admin-uuid',bad.id,'controlled-negative-fixture',timestamp).run();
  const invalidAdmin=await detail(f,cookie,bad.id);assert.equal(invalidAdmin.status,503);assert.equal(errorCode(invalidAdmin),'invalid_source_data');
  const invalidPerson=await seedPerson(f,{id:'not-a-collect-uuid',name:'Unique malformed Collect identifier'});
  const invalidCollect=await get(f,cookie,'/api/admin/core/users?search='+encodeURIComponent('Unique malformed Collect identifier'));
  assert.equal(invalidCollect.status,503);assert.equal(errorCode(invalidCollect),'invalid_source_data');assert.equal(invalidPerson.id,'not-a-collect-uuid');
 });
});

// Unknown roles/types and dangling links cannot be inserted through the enforced
// D1 schema. These direct adapter negatives supplement, rather than replace, the
// actual router/D1 cases above without weakening database constraints.
test('person read adapter rejects inconsistent tuples instead of emitting a misleading successful row',async t=>{
 const adminId=randomUUID(),base={id:randomUUID(),public_id:'000123',member_type:'operator',operator_admin_id:null,joined_operator_admin_id:null,operator_role:null,operator_status:null,
  full_name:'Synthetic source row',phone:null,email:null,momo_provider:'',momo_number:'',momo_pay_code:'',status:'active',revision:1,active_groups:0,net_contributed_rwf:0,created_at:timestamp,updated_at:timestamp};
 const linked={...base,operator_admin_id:adminId,joined_operator_admin_id:adminId,operator_role:'staff',operator_status:'active'};
 const cases=[['unknown member type',{...base,member_type:'other'}],['role without link',{...base,operator_role:'staff'}],['status without link',{...base,operator_status:'active'}],
  ['joined Admin without link',{...base,joined_operator_admin_id:adminId}],['dangling Admin link',{...linked,joined_operator_admin_id:null}],['different joined Admin',{...linked,joined_operator_admin_id:randomUUID()}],
  ['unknown linked role',{...linked,operator_role:'auditor'}],['missing linked role',{...linked,operator_role:null}],['unknown linked status',{...linked,operator_status:'disabled'}],
  ['missing linked status',{...linked,operator_status:null}],['malformed Admin id',{...linked,operator_admin_id:'not-a-uuid',joined_operator_admin_id:'not-a-uuid'}],
  ['malformed Collect id',{...base,id:'not-a-uuid'}],['malformed public id',{...base,public_id:'12345'}],['numeric public id',{...base,public_id:123456}]];
 for(const [name,row] of cases)await t.test(name,()=>assert.throws(()=>lists.users.row(row),error=>error.status===503&&error.code==='invalid_source_data'));
 await t.test('invited and revoked linked roles remain accurately represented',()=>{
  for(const role of ['owner','admin','staff'])for(const status of ['invited','active','revoked']){
   const row=lists.users.row({...linked,operator_role:role,operator_status:status});
   assert.deepEqual(row.user_types,[role==='staff'?'Staff':'Admin']);assert.equal(row.operator_role,role);assert.equal(row.operator_status,status);
  }
 });
});
