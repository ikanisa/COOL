import {registerHooks} from 'node:module';
import assert from 'node:assert/strict';
import {test} from './helpers/fenced-node-test.js';

// Synthetic Admin identity and storage. The real bridge and mutation/replay
// code construct statements, but the fixture never executes database SQL.
const doubles={
 './admin_accounts.js': `export async function handleAdminAccounts(){return null;}
 export function validateAdminOrigin(){}
 export async function adminAccountSession(){return globalThis.__membershipFixture.account;}
 export async function adminCanonicalActor(){return globalThis.__membershipFixture.actor;}
 export function accountDatabase(env){return env;}
 export async function adminInternalRequest(){throw Error('unrelated request');}`,
 './encryption.js': `export async function encrypt(){return 'synthetic-cipher';}
 export async function decrypt(){throw Error('unrelated decrypt');}`,
 './notification_operator.js': `export async function notificationOperatorRoute(){return null;}`,
 './notification_operator_management.js': `export async function notificationOperatorManagementRoute(){return null;}`,
};
registerHooks({resolve(specifier,context,next){
 if(context.parentURL?.endsWith('/domain/admin_bridge.js')&&Object.hasOwn(doubles,specifier))
  return {url:'data:text/javascript,'+encodeURIComponent(doubles[specifier]),shortCircuit:true};
 return next(specifier,context);
}});
const {handleAdmin}=await import('../domain/admin_bridge.js');
const {digest,stableJson}=await import('../domain/core.js');
const ids={admin:'30000000-0000-4000-8000-000000000001',principal:'30000000-0000-4000-8000-000000000002',session:'30000000-0000-4000-8000-000000000003',group:'30000000-0000-4000-8000-000000000004',user:'30000000-0000-4000-8000-000000000005'};
const reason='Synthetic membership change';
const path=`/api/admin/operations/memberships/${ids.group}/${ids.user}`;
let sequence=0;

function fixture(existing={role:'admin',active:0,revision:3}){
 const f={existing,receipt:null,batches:[],reads:[],account:{id:ids.admin,principal_id:ids.principal,auth_session_id:ids.session,role:'owner',permissions:['collections.manage']},
  actor:{userId:ids.principal,sessionId:ids.session,permissions:new Set(['collections.manage']),assuranceLevel:2}};
 f.DB={
  prepare(sql){return {sql,bind(...args){return {sql,args,async first(){
   f.reads.push({sql,args});
   if(sql==='SELECT * FROM request_receipts WHERE user_id=? AND request_id=?')
    return f.receipt?.user_id===args[0]&&f.receipt?.request_id===args[1]?f.receipt:null;
   if(sql==='SELECT * FROM memberships WHERE collection_id=? AND user_id=?')
    return args[0]===ids.group&&args[1]===ids.user?f.existing:null;
   throw Error(`Unexpected synthetic read: ${sql}`);
  }};}};},
  async batch(statements){
   f.batches.push(statements);
   for(const statement of statements){
    if(statement.sql.startsWith('INSERT INTO request_receipts(')){
     const [user_id,request_id,operation,session_id,body_sha256,response_json]=statement.args;
     f.receipt={user_id,request_id,operation,session_id,body_sha256,response_json};
    }
   }
   return statements.map(()=>({meta:{changes:1}}));
  },
 };
 globalThis.__membershipFixture=f;return f;
}
async function call(f,method,body,{key=`synthetic-${++sequence}`,url=path}={}){
 const request=new Request('https://admin.example.invalid'+url,{method,headers:{'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify(body)});
 const response=await handleAdmin(request,{DB:f.DB},{});return {status:response.status,body:await response.json()};
}
function writes(f,verb){return f.batches.flat().filter(statement=>statement.sql.startsWith(verb+' memberships(')||statement.sql.startsWith(verb+' memberships SET'));}
function noMutation(f){assert.equal(writes(f,'INSERT').length,0);assert.equal(writes(f,'UPDATE').length,0);assert.equal(f.receipt,null);}

test('new partial or null membership PATCH cannot demote or reactivate a person',async()=>{
 for(const change of [{status:'active'},{role:'admin'},{},{role:null,status:'removed'},{role:'member',status:null}]){
  const f=fixture(),reply=await call(f,'PATCH',{...change,expected_version:3,reason});
  assert.equal(reply.status,400,JSON.stringify(change));assert.equal(reply.body.error.code,'invalid_request');noMutation(f);
 }
});

test('a complete PATCH still supplies the explicitly selected role and status',async()=>{
 for(const [role,status,active] of [['admin','removed',0],['member','active',1],['member','left',0]]){
  const f=fixture(),reply=await call(f,'PATCH',{role,status,expected_version:3,reason});
  assert.equal(reply.status,200,JSON.stringify({role,status}));assert.equal(reply.body.version,4);
  const updates=writes(f,'UPDATE');assert.equal(updates.length,1);
  assert.deepEqual(updates[0].args,[role,active,ids.group,ids.user]);
 }
});

test('create retains its existing member and active defaults',async()=>{
 const f=fixture(null),reply=await call(f,'POST',{group_id:ids.group,user_id:ids.user,reason},{url:'/api/admin/operations/memberships'});
 assert.equal(reply.status,200);assert.equal(reply.body.version,1);
 const inserts=writes(f,'INSERT');assert.equal(inserts.length,1);
 assert.deepEqual(inserts[0].args.slice(1,5),[ids.group,ids.user,'member',1]);
});

test('a stale full PATCH is refused without constructing a membership write',async()=>{
 const f=fixture(),reply=await call(f,'PATCH',{role:'admin',status:'removed',expected_version:2,reason});
 assert.equal(reply.status,409);assert.equal(reply.body.error.code,'stale_state');noMutation(f);
});

test('an exact earlier partial receipt remains replayable; altered input conflicts',async()=>{
 const f=fixture(),key='synthetic-retained-request',body={status:'active',expected_version:3,reason};
 const raw=await digest(`collect-admin:${ids.principal}:${key}`);
 const requestId=`${raw.slice(0,8)}-${raw.slice(8,12)}-4${raw.slice(13,16)}-8${raw.slice(17,20)}-${raw.slice(20,32)}`;
 const result={status:'succeeded',request_id:requestId,resource_type:'memberships',resource_id:`${ids.group}/${ids.user}`,version:4};
 f.receipt={user_id:ids.principal,request_id:requestId,operation:`admin.bridge.memberships.patch.${ids.group}.${ids.user}`,
  session_id:ids.session,body_sha256:await digest(stableJson({method:'PATCH',path,body})),response_json:JSON.stringify(result)};
 let reply=await call(f,'PATCH',body,{key});assert.equal(reply.status,200);assert.deepEqual(reply.body,result);
 assert.equal(writes(f,'UPDATE').length,0);assert.equal(writes(f,'INSERT').length,0);
 reply=await call(f,'PATCH',{...body,status:'removed'},{key});assert.equal(reply.status,409);assert.equal(reply.body.error.code,'request_conflict');
 assert.equal(writes(f,'UPDATE').length,0);assert.equal(writes(f,'INSERT').length,0);
});
