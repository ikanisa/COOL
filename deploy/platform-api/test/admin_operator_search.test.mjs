import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_support/fixture.mjs';

const timestamp='2026-10-16T12:00:00.000Z';
const sorted=values=>[...values].sort();
async function person(f,name,memberType='operator',status='active'){
 const id=randomUUID(),publicId=String((await f.db.prepare('SELECT count(*) AS n FROM users').first()).n).padStart(6,'0');
 await f.db.prepare('INSERT INTO users(id,public_id,full_name,member_type,access_status,created_at,updated_at) VALUES(?,?,?,?,?,?,?)').bind(id,publicId,name,memberType,status,timestamp,timestamp).run();
 return id;
}

test('operator search is the unlinked Operator type while role, member and quoted text searches keep their semantics through router and D1',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),cookie=(await f.login(owner)).cookie;
 const admin=await f.seedAccount({email:'search-admin@collect-auth.invalid',role:'admin'}),staff=await f.seedAccount({email:'search-staff@collect-auth.invalid',role:'staff'}),linkedApp=await f.seedAccount({email:'search-linked-app@collect-auth.invalid',role:'admin'}),linkedDirect=await f.seedAccount({email:'search-linked-direct@collect-auth.invalid',role:'staff'});
 for(const [account,name,memberType] of [[owner,'Linked Owner Controls','operator'],[admin,'Linked Admin Controls','operator'],[staff,'Linked Staff Controls','operator'],[linkedApp,'Overlapping App Controls','app'],[linkedDirect,'Overlapping Direct Controls','direct']])await f.db.prepare('UPDATE users SET full_name=?,member_type=? WHERE id=?').bind(name,memberType,account.userId).run();
 const first=await person(f,'Read Only First'),second=await person(f,'Read Only Second','operator','suspended'),literal=await person(f,'Literal Operator Person','app'),app=await person(f,'Unrelated App Person','app'),direct=await person(f,'Ordinary Direct Person','direct');
 const search=async(query,{kind='users',lookup=false}={})=>{
  const path=lookup?'/api/admin/operations/lookups?kind='+kind+'&':'/api/admin/core/'+kind+'?';
  const response=await f.call(path+'limit=100&search='+encodeURIComponent(query),{method:'GET',cookie});
  assert.equal(response.status,200,JSON.stringify(response.body));assert.equal(response.body.total,response.body.rows.length);return response.body.rows;
 };
 const expect=async(query,ids,options)=>assert.deepEqual(sorted((await search(query,options)).map(row=>row.id)),sorted(ids),query);
 await t.test('explicit type and bare Operator token select only unlinked operators independent of literal name',async()=>{
  for(const query of ['type:operator','Operator','OPERATOR','TYPE:OPERATOR']){
   const rows=await search(query);assert.deepEqual(sorted(rows.map(row=>row.id)),sorted([first,second]));
   for(const row of rows){assert.deepEqual(row.user_types,['Operator']);assert.equal(row.member_type,'operator');assert.equal(row.operator_admin_id,null);}
  }
 });
 await t.test('existing status and text intersections remain conjunctive and cannot include linked or App identities',async()=>{
  await expect('type:operator status:active',[first]);await expect('Operator suspended',[second]);await expect('Operator First',[first]);
  for(const query of ['type:operator type:app','type:operator type:staff','Operator "Literal"','type:operator type:owner'])await expect(query,[]);
 });
 await t.test('existing explicit and bare linked-role searches retain linked and overlapping identities',async()=>{
  for(const query of ['type:owner','Owner'])await expect(query,[owner.userId]);
  for(const query of ['type:admin','Admin'])await expect(query,[admin.userId,linkedApp.userId]);
  for(const query of ['type:staff','Staff'])await expect(query,[staff.userId,linkedDirect.userId]);
 });
 await t.test('existing App and Direct filters preserve both unlinked and linked member-type overlaps',async()=>{
  for(const query of ['type:app','App'])await expect(query,[literal,app,linkedApp.userId]);
  for(const query of ['type:direct','Direct'])await expect(query,[direct,linkedDirect.userId]);
 });
 await t.test('quoted Operator and ordinary partial words retain literal text matching',async()=>{
  await expect('"Operator"',[literal]);await expect('"type:operator"',[]);await expect('Operat',[literal]);await expect('"Read Only"',[first,second]);
 });
 await t.test('member list and eligible user lookup keep existing operator exclusion even with the new filter',async()=>{
  await expect('type:operator',[],{kind:'members'});await expect('Operator',[],{kind:'members'});
  await expect('type:operator',[],{lookup:true});await expect('Operator',[],{lookup:true});
  await expect('type:app',[literal,app,linkedApp.userId],{lookup:true});
 });
 await t.test('unknown explicit types still fail closed and non-person records retain literal Operator search',async()=>{
  const invalid=await f.call('/api/admin/core/users?search=type%3Aunknown',{method:'GET',cookie});assert.equal(invalid.status,400);assert.equal(invalid.body.error?.code,'invalid_filter');
  const id=randomUUID();await f.db.prepare('INSERT INTO collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES(?,?,?,?,?,?,?)').bind(id,'search-'+id,literal,'Literal Operator Group','ikimina',timestamp,timestamp).run();
  await expect('Operator',[id],{kind:'groups'});
 });
 await t.test('separate legacy RPC search preserves public-ID text behavior and does not acquire semantic filters',async()=>{
  await f.db.prepare('UPDATE users SET email=? WHERE id=?').bind(owner.email,owner.userId).run();
  const origin='https://collect.example',challenge=await f.call('/v1/auth/otp',{origin,data:{email:owner.email,surface:'admin',create_account:false,captcha_token:randomUUID()}});assert.equal(challenge.status,202);
  const message=f.mail.findLast(m=>m.to===owner.email&&m.subject==='Your Collect sign-in code');assert.ok(message,'Native email binding observed the approved owner code delivery');
  const code=/^Your Collect sign-in code is ([0-9]{6})\. /.exec(message.text)?.[1];assert.ok(code,'Native email carries the sign-in code');
  const verified=await f.call('/v1/auth/verify',{origin,data:{email:owner.email,surface:'admin',challenge_id:challenge.body.challenge_id,code,captcha_token:randomUUID()}});assert.equal(verified.status,200);
  const headers={Authorization:'Bearer '+verified.body.access_token},publicId=(await f.db.prepare('SELECT public_id FROM users WHERE id=?').bind(owner.userId).first()).public_id;
  const rpc=async query=>{const response=await f.call('/v1/rpc/admin_list_users',{origin,headers,data:{p_search:query,p_limit:100}});assert.equal(response.status,200);return response.body;};
  const match=await rpc(publicId);assert.equal(match.total,1);assert.deepEqual(match.rows.map(row=>row.id),[owner.userId]);
  for(const query of ['Operator','type:operator']){const miss=await rpc(query);assert.equal(miss.total,0);assert.deepEqual(miss.rows,[]);}
 });
});
