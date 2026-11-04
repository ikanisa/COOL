import {registerHooks} from 'node:module';
import assert from 'node:assert/strict';
import {test} from './helpers/fenced-node-test.js';

// Exercise the real Admin bridge and receiving-account route against synthetic
// authority and storage boundaries. No statements are executed or committed.
const doubles={
 './admin_accounts.js': `export async function handleAdminAccounts(){return null;}
 export function validateAdminOrigin(){}
 export async function adminAccountSession(){return globalThis.__receiverFixture.account;}
 export async function adminCanonicalActor(){return globalThis.__receiverFixture.actor;}
 export function accountDatabase(env){return env;}
 export async function adminInternalRequest(){throw Error('unrelated internal request');}`,
 './mutations.js': `export async function retainedResponse(){return globalThis.__receiverFixture.retained??{found:false};}
 export async function mutation(env,actor,operation,id,body,value,writes,options){
  globalThis.__receiverFixture.mutations.push({operation,body,value,writes,options});return value;}`,
 './encryption.js': `export async function encrypt(){return 'synthetic-cipher';}
 export async function decrypt(){throw Error('unrelated decrypt');}`,
 './notification_operator.js': `export async function notificationOperatorRoute(){return null;}`,
 './notification_operator_management.js': `export async function notificationOperatorManagementRoute(){return null;}`,
};
registerHooks({resolve(specifier,context,next){
 if((context.parentURL?.endsWith('/domain/admin_bridge.js')||context.parentURL?.endsWith('/domain/admin_momo.js'))&&Object.hasOwn(doubles,specifier))
  return {url:'data:text/javascript,'+encodeURIComponent(doubles[specifier]),shortCircuit:true};
 return next(specifier,context);
}});
const {handleAdmin}=await import('../domain/admin_bridge.js');
const {digest}=await import('../domain/core.js');
const ids={admin:'30000000-0000-4000-8000-000000000001',principal:'30000000-0000-4000-8000-000000000002',session:'30000000-0000-4000-8000-000000000003',group:'30000000-0000-4000-8000-000000000004',owner:'30000000-0000-4000-8000-000000000005'};
const reason='Synthetic destination format test';
const perms=['collections.create','collections.manage','receivers.read','receivers.manage'];
let sequence=0;
function fixture(row=null){
 const f={row,mutations:[],account:{id:ids.admin,principal_id:ids.principal,auth_session_id:ids.session,role:'owner',permissions:perms},actor:{userId:ids.principal,sessionId:ids.session,permissions:new Set(perms),assuranceLevel:2}};
 f.DB={
  prepare(sql){return {sql,bind(...args){return {sql,args,async first(){
   if(sql==='SELECT * FROM collections WHERE id=?'&&args[0]===ids.group)return f.row;
   throw Error(`Unexpected synthetic read: ${sql}`);
  }};}};},
  async batch(){throw Error('synthetic statements must not execute');},
 };
 globalThis.__receiverFixture=f;return f;
}
function group(route,visibility='public_approved',sponsored=true){return {
 title:'Synthetic group',slug:'synthetic-group',collection_type:'ikimina',owner_user_id:ids.owner,
 receiver:{label:'Synthetic receiver',network:'mtn_momo',momo_number_or_code:route},visibility,is_platform_sponsored:sponsored,reason,
};}
function existing(visibility,route,sponsored=0){return {id:ids.group,revision:3,status:'active',visibility_status:visibility,is_platform_sponsored:sponsored,
 receiver_display_label:'Synthetic receiver',receiver_network:'mtn_momo',receiver_momo_number:route,title:'Existing synthetic group',
 description:'',collection_type:'ikimina',data_json:'{}'};}
async function call(f,path,method,body){
 const request=new Request('https://admin.example.invalid/api/admin/'+path,{method,headers:{'Content-Type':'application/json','Idempotency-Key':`synthetic-${++sequence}`},body:JSON.stringify(body)});
 const response=await handleAdmin(request,{DB:f.DB},{});return {status:response.status,body:await response.json()};
}
const written=(f,table)=>{
 assert.equal(f.mutations.length,1);
 const writes=f.mutations[0].writes.filter(statement=>statement.sql.startsWith(`INSERT INTO ${table}(`));
 assert.equal(writes.length,1);return writes[0].args;
};

test('new public destinations match the existing receiving-account format',async()=>{
 const cases=[
  {input:'0001',stored:'0001',canonical:'0001'},
  {input:'123456789',stored:'123456789',canonical:'123456789'},
  {input:'0788123456',stored:'250788123456',canonical:'+250788123456'},
  {input:'250788123456',stored:'250788123456',canonical:'+250788123456'},
  {input:'+250788123456',stored:'250788123456',canonical:'+250788123456'},
 ];
 for(const {input,stored,canonical} of cases){
  const g=fixture(),created=await call(g,'operations/groups','POST',group(input));
  assert.equal(created.status,200,input);const groupArgs=written(g,'collections');
  assert.equal(groupArgs[6],stored);assert.equal(groupArgs[7],'mtn_momo');assert.equal(groupArgs[9],'public_approved');assert.equal(groupArgs[10],1);
  const a=fixture(),account=await call(a,'momo/accounts','POST',{provider:'mtn_momo',public_code:input,recipient_name:'Synthetic receiver',reason});
  assert.equal(account.status,200,input);const accountArgs=written(a,'momo_receiving_accounts');
  assert.equal(accountArgs[1],'mtn_momo');assert.equal(accountArgs[2],input);assert.equal(accountArgs[4],await digest(canonical));
 }
});

test('10–12 digit non-phones are refused before either synthetic mutation',async()=>{
 for(const input of ['0718123456','00012345678','251788123456']){
  const g=fixture(),created=await call(g,'operations/groups','POST',group(input));
  assert.equal(created.status,400,input);assert.equal(created.body.error.code,'invalid_receiver');assert.equal(g.mutations.length,0);
  const a=fixture(),account=await call(a,'momo/accounts','POST',{provider:'mtn_momo',public_code:input,recipient_name:'Synthetic receiver',reason});
  assert.equal(account.status,400,input);assert.equal(account.body.error.code,'invalid_account');assert.equal(a.mutations.length,0);
 }
 const f=fixture(),reply=await call(f,'operations/groups','POST',group('0001\n'));
 assert.equal(reply.status,400);assert.equal(reply.body.error.code,'invalid_receiver');assert.equal(f.mutations.length,0);
});

test('first publication checks the receiver irrespective of old sponsorship state',async()=>{
 for(const visibility of ['private','public_pending'])for(const sponsored of [0,1]){
  const f=fixture(existing(visibility,'0718123456',sponsored));
  const reply=await call(f,`operations/groups/${ids.group}`,'PATCH',{visibility:'public_approved',is_platform_sponsored:true,expected_version:3,reason});
  assert.equal(reply.status,400,`${visibility}/${sponsored}`);assert.equal(reply.body.error.code,'invalid_receiver');assert.equal(f.mutations.length,0);
 }
 for(const route of ['0001','123456789','250788123456']){
  const f=fixture(existing('private',route));
  const reply=await call(f,`operations/groups/${ids.group}`,'PATCH',{visibility:'public_approved',is_platform_sponsored:true,expected_version:3,reason});
  assert.equal(reply.status,200,route);assert.equal(f.mutations.length,1);
  const update=f.mutations[0].writes.find(statement=>statement.sql.startsWith('UPDATE collections SET'));
  assert.ok(update);assert.equal(update.sql.includes('receiver_momo_number='),false);
 }
});

test('already-public legacy receivers remain locked and ordinary edits remain possible',async()=>{
 for(const sponsored of [0,1]){
  const f=fixture(existing('public_approved','123456789012',sponsored));
  const reply=await call(f,`operations/groups/${ids.group}`,'PATCH',{title:'Updated synthetic group',expected_version:3,reason});
  assert.equal(reply.status,200);assert.equal(f.mutations.length,1);
  const update=f.mutations[0].writes.find(statement=>statement.sql.startsWith('UPDATE collections SET'));
  assert.ok(update);assert.equal(update.sql.includes('receiver_momo_number='),false);
  const locked=fixture(existing('public_approved','123456789012',sponsored));
  const refused=await call(locked,`operations/groups/${ids.group}`,'PATCH',{receiver:{label:'Other',network:'mtn_momo',momo_number_or_code:'0001'},expected_version:3,reason});
  assert.equal(refused.status,409);assert.equal(refused.body.error.code,'receiver_locked');assert.equal(locked.mutations.length,0);
 }
});

test('private phone-only rules, public sponsorship and replay order are unchanged',async()=>{
 let f=fixture(),reply=await call(f,'operations/groups','POST',group('0001','private',false));
 assert.equal(reply.status,400);assert.equal(reply.body.error.code,'invalid_phone');assert.equal(f.mutations.length,0);
 f=fixture();reply=await call(f,'operations/groups','POST',group('0788123456','private',false));
 assert.equal(reply.status,200);assert.equal(written(f,'collections')[6],'250788123456');
 f=fixture();reply=await call(f,'operations/groups','POST',group('0001','public_approved',false));
 assert.equal(reply.status,400);assert.equal(reply.body.error.code,'invalid_publication');assert.equal(f.mutations.length,0);
 f=fixture();f.actor.permissions.delete('receivers.manage');reply=await call(f,'operations/groups','POST',group('0001'));
 assert.equal(reply.status,403);assert.equal(reply.body.error.code,'permission_required');assert.equal(f.mutations.length,0);
 f=fixture();f.retained={found:true,value:{status:'succeeded',resource_id:ids.group}};
 reply=await call(f,'operations/groups','POST',group('123456789012'));
 assert.equal(reply.status,200);assert.equal(reply.body.resource_id,ids.group);assert.equal(f.mutations.length,0);
});

test('new groups use the exact canonical owner ID and retain prior replay',async()=>{
 const owner='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 for(const [visibility,sponsored,route] of [['public_approved',true,'0001'],['private',false,'0788123456']]){
  const body={...group(route,visibility,sponsored),owner_user_id:owner};
  const f=fixture(),reply=await call(f,'operations/groups','POST',body);
  assert.equal(reply.status,200);assert.equal(written(f,'collections')[2],owner);
  assert.equal(written(f,'memberships')[2],owner);
  const guard=f.mutations[0].writes.find(statement=>statement.sql.startsWith('INSERT INTO admin_bridge_guards'));
  assert.equal(guard.args[1],owner);
  for(const [changed,errorCode] of [[owner.toUpperCase(),'invalid_owner'],[owner.replace('a','A'),'invalid_owner'],[` ${owner} `,'invalid_parameter']]){
   const rejected=fixture(),result=await call(rejected,'operations/groups','POST',{...body,owner_user_id:changed});
   assert.equal(result.status,400);assert.equal(result.body.error.code,errorCode);assert.equal(rejected.mutations.length,0);
  }
 }
 const retained=fixture();retained.retained={found:true,value:{status:'succeeded',resource_id:ids.group}};
 const replay=await call(retained,'operations/groups','POST',{...group('0001'),owner_user_id:owner.toUpperCase()});
 assert.equal(replay.status,200);assert.equal(replay.body.resource_id,ids.group);assert.equal(retained.mutations.length,0);
});
