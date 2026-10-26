import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_support/fixture.mjs';
import {coreOrdering,coreSearch} from '../src/admin_search.js';

async function operator(f){const login=await f.login(await f.seedAccount());return f.stepUp(login);}
async function group(f,admin,member,title){
 const result=await f.operation('groups',admin.cookie,{title,slug:'search-'+randomUUID().slice(0,8),collection_type:'ikimina',owner_user_id:member.id,
  receiver:{label:'Receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Controlled search fixture'});
 assert.equal(result.status,200,JSON.stringify(result));return result.body.resource_id;
}

test('actual D1 sorts whole money values numerically across server windows',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),id=await group(f,admin,member,'Search group');
 for(const amount of [10,2,100]){const r=await f.operation('transactions',admin.cookie,{group_id:id,payee_id:id,amount_rwf:amount,provider_reference:randomUUID(),observed_at:new Date().toISOString(),evidence:'Retained search fixture',reason:'Record controlled receipt'});assert.equal(r.status,200,JSON.stringify(r));}
 const pages=[];
 for(const offset of [0,1,2]){
  const r=await f.call(`/api/admin/core/transactions?sort=amount_minor_desc&limit=1&offset=${offset}`,{method:'GET',cookie:admin.cookie});
  assert.equal(r.status,200,JSON.stringify(r));assert.equal(r.body.total,3);pages.push(r.body.rows[0].amount_rwf);
 }
 assert.deepEqual(pages,[100,10,2]);
 const filtered=await f.call('/api/admin/core/transactions?search=unallocated%20transactions&sort=amount_minor_asc',{method:'GET',cookie:admin.cookie});
 assert.equal(filtered.status,200,JSON.stringify(filtered));assert.deepEqual(filtered.body.rows.map(r=>r.amount_rwf),[2,10,100]);
 assert.ok(filtered.body.rows.every(r=>r.provider_confirmation===false&&r.settlement_status==='not_asserted'));
});

test('natural person and group terms filter actual authorized records',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember({name:'Zebra Member'}),other=await f.seedMember({phone:'+250788123459',name:'Alpha Member'});
 await group(f,admin,member,'Zulu group');await group(f,admin,member,'Alpha group');
 await f.seedAccount({email:'staff@example.com',role:'staff'});
 const groups=await f.call('/api/admin/core/groups?search=active%20private%20groups&sort=title_asc&limit=1',{method:'GET',cookie:admin.cookie});
 assert.equal(groups.status,200,JSON.stringify(groups));assert.equal(groups.body.total,2);assert.equal(groups.body.rows[0].title,'Alpha group');
 const staff=await f.call('/api/admin/core/users?search=staff%20users',{method:'GET',cookie:admin.cookie});
 assert.equal(staff.status,200,JSON.stringify(staff));assert.equal(staff.body.total,1);assert.equal(staff.body.rows[0].operator_role,'staff');
 const ungrouped=await f.call('/api/admin/core/users?search=type%3Aapp%20users%20without%20groups&sort=full_name_asc',{method:'GET',cookie:admin.cookie});
 assert.equal(ungrouped.status,200,JSON.stringify(ungrouped));assert.deepEqual(ungrouped.body.rows.map(r=>r.id),[other.id]);
 const quoted=await f.call('/api/admin/core/users?search='+encodeURIComponent('"Zebra Member"'),{method:'GET',cookie:admin.cookie});
 assert.equal(quoted.status,200);assert.deepEqual(quoted.body.rows.map(r=>r.id),[member.id]);
});

test('ordering and filter injection are refused without widening read authority',async t=>{
 const f=await fixture(t),admin=await operator(f);await f.seedMember();
 for(const query of ['sort=amount_minor_desc','sort=created_at_desc%3BDROP%20TABLE%20users','sort=created_at_desc&sort=created_at_asc','status=made_up','search=type%3Amade_up']){
  const r=await f.call('/api/admin/core/users?'+query,{method:'GET',cookie:admin.cookie});assert.equal(r.status,400,JSON.stringify({query,r}));
 }
 const injection=await f.call('/api/admin/core/users?search='+encodeURIComponent("%_' OR 1=1 --"),{method:'GET',cookie:admin.cookie});
 assert.equal(injection.status,200);assert.equal(injection.body.total,0);
 assert.equal((await f.call('/api/admin/core/users?sort=full_name_asc',{method:'GET',origin:'https://hostile.example',cookie:admin.cookie})).status,403);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM users').first()).n,2);
});

test('every admitted ordering is bounded and search values remain SQL bindings',()=>{
 assert.equal(coreOrdering('ledgers','created_at_desc'),'posted_at DESC,id DESC');
 assert.throws(()=>coreOrdering('ledgers','debit_rwf_desc'),/unavailable/);
 const result=coreSearch('users','type:direct "a\'b"',['full_name','email']);
 assert.deepEqual(result.args,['direct',"a'b","a'b"]);assert.ok(!result.predicates.join().includes("a'b"));
 assert.throws(()=>coreSearch('users',Array.from({length:25},()=> 'x').join(' '),['full_name']),/24/);
});
