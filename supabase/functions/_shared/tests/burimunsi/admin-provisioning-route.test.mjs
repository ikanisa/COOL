// Real composite route/BFF/CSRF/provider verification + production crypto over
// reduced SQLite. The PG provisioning helper is explicitly substituted.
import test from 'node:test';import assert from 'node:assert/strict';
import {provisioningAdminFixture as fixture,provisioningOwner as owner,I,PRINCIPAL} from './provisioning-admin-fixture.mjs';
const BASE='/api/admin/burimunsi/provisioning',R='34000000-0000-4000-8000-000000000001';
const command=()=>({operation:'set_pin',requestId:R,collectionId:I.group,scopeVersion:1,principalId:PRINCIPAL,
 approvalVersion:2,expectedAccountVersion:0,reason:'Owner approved native setup',pin:'8492'});
const directory=()=>({contractVersion:1,collectionId:I.group,configured:true,scopeEnabled:false,scopeVersion:1,
 accounts:[{principalId:PRINCIPAL,accountId:null,phone:'+250780000002',name:'QA approved operator',role:'staff',capabilities:['records.read'],
  approvalVersion:2,approved:true,version:0,credentialVersion:0,active:false,removed:false}],grants:[]});
const empty=()=>({contractVersion:1,collectionId:I.group,requestId:R,found:false});

for(const method of ['GET','POST'])test('actual shared staff cannot provision native credentials '+method,()=>fixture(async({state,call})=>{
 state.ownerCommand=()=>{throw Error('Must not reach credential SQL');};
 const {response,body}=await call({path:BASE,method,body:command()});
 assert.equal(response.status,403);assert.equal(body.error.code,'owner_required');
}));
for(const [name,change,options,status] of [
 ['stale email',(f,s)=>s.emailVerifiedAt=null,{},403],
 ['CSRF',(f,s)=>{}, {headers:{'X-Collect-CSRF':''}},403],
 ['origin',(f,s)=>{}, {headers:{Origin:'https://evil.example.invalid'}},403],
 ['cross-site',(f,s)=>{}, {headers:{'Sec-Fetch-Site':'cross-site'}},403],
 ['provider revocation',(f,s)=>s.provider=false,{},401],
 ['managed admission revocation',(f,s)=>s.managed=false,{},401],
])test('credential provisioning retains '+name+' denial before command SQL',()=>fixture(async({f,state,at,call})=>{
 owner(f,state,at);change(f,state);let invoked=false;state.ownerCommand=()=>{invoked=true;throw Error('Must not reach SQL');};
 const {response,body}=await call({path:BASE,body:command(),...options});
 assert.equal(response.status,status,JSON.stringify(body));assert.equal(invoked,false);
}));
test('missing reviewed schema fails closed and does not fall through to member/other Admin writers',()=>fixture(async({f,state,at,call})=>{
 owner(f,state,at);state.ownerCommand=()=>{throw Object.assign(Error('function missing'),{code:'42883'});};
 const {response,body}=await call({path:BASE,body:command()});
 assert.equal(response.status,503);assert.equal(body.error.code,'burimunsi_provisioning_unavailable');
 assert(!state.queries.some(q=>q.includes('INSERT INTO users')||q.includes('INSERT INTO app.users')));
}));
test('actual owner route hashes PIN and shares existing fenced DB; receipt never contains credential material',()=>fixture(async({f,env,state,at,call,hash})=>{
 owner(f,state,at);let count=0;
 state.ownerCommand=(q,args)=>{
  assert.equal(args[1],hash);assert.equal(args[4],I.group);
  if(q.includes('_lookup('))return empty();if(q.includes('_directory('))return directory();
  assert(q.includes('_apply('));const c=JSON.parse(args[5]);count++;
  assert.equal(c.pin,undefined);assert.equal(c.pinHash.algorithm,'pbkdf2-sha256+hmac-v1');assert.match(args[6],/^[a-f0-9]{64}$/);
  assert.equal(c.pin,undefined);assert.equal(Object.hasOwn(c,'pin'),false);assert.equal(c.reason.includes('8492'),false);
  return {contractVersion:1,collectionId:I.group,requestId:R,operation:'set_pin',principalId:PRINCIPAL,
   accountId:c.accountId,accountVersion:1,credentialVersion:1,scopeVersion:1,approvalVersion:2,applied:true};
 };
 const {response,body}=await call({path:BASE,body:command()});
 assert.equal(response.status,200,JSON.stringify(body));assert.equal(count,1);assert.equal(body.applied,true);
 assert.equal(body.pin,undefined);assert.equal(body.pinHash,undefined);assert.equal(body.installationToken,undefined);
 assert.equal(response.headers.get('Cache-Control'),'no-store, private');
 assert.equal(env.DB,f.db);assert(state.queries.some(q=>q.includes('pg_advisory_xact_lock(734636924058501')));
}));
test('changed source and configured scope cannot retarget a provisioning command',()=>fixture(async({f,env,state,at,call})=>{
 owner(f,state,at);state.ownerCommand=()=>{throw Error('No command SQL allowed');};
 env.BUILD_SOURCE_ID='d'.repeat(64);assert.equal((await call({path:BASE,body:command()})).response.status,503);
 env.BUILD_SOURCE_ID='a'.repeat(64);env.BURIMUNSI_COLLECTION_ID='other-group';
 assert.equal((await call({path:BASE,body:command()})).response.status,409);
}));
test('versioned PIN setup and cancellation send their catalog precondition to the fenced writer',()=>fixture(async({f,state,at,call})=>{
 owner(f,state,at);
 const version='?provisioningContract=2';
 let mutations=0;
 state.ownerCommand=(query,args)=>{
  if(query.startsWith('SELECT private.burimunsi_provisioning_lookup('))return empty();
  if(query.startsWith('SELECT private.burimunsi_provisioning_directory('))return directory();
  assert(query.includes(' WHERE (SELECT count(*)=3 AS available'));
  mutations++;
  if(query.startsWith('SELECT private.burimunsi_provisioning_cancel('))return {contractVersion:1,collectionId:I.group,requestId:R,operation:'cancelled',applied:false};
  assert(query.startsWith('SELECT private.burimunsi_provisioning_apply('));
  const prepared=JSON.parse(args[5]);
  assert.equal(prepared.pin,undefined);
  return {contractVersion:1,collectionId:I.group,requestId:R,operation:'set_pin',principalId:PRINCIPAL,accountId:prepared.accountId,
   accountVersion:1,credentialVersion:1,scopeVersion:1,approvalVersion:2,applied:true};
 };
 assert.equal((await call({path:BASE+version,body:command()})).response.status,200);
 assert.equal((await call({path:BASE+'/requests/'+R+'/cancel'+version,body:{collectionId:I.group}})).response.status,200);
 assert.equal(mutations,2);
 assert.equal((await call({path:BASE+'?provisioningContract=1',body:command()})).response.status,400);
 assert.equal((await call({path:BASE+'/requests/'+R+'/delivery'+version,body:{collectionId:I.group}})).response.status,400);
 assert.equal(mutations,2);
}));
test('lost mutation COMMIT returns original request only; no internal error/PIN/token diagnostic leaks',()=>fixture(async({f,state,at,call})=>{
 owner(f,state,at);let applied=0;
 state.ownerCommand=q=>{if(q.includes('_lookup('))return empty();if(q.includes('_directory('))return directory();
  applied++;throw Error('Internal fixture failure including 8492 and secret-do-not-release');};
 const {response,body}=await call({path:BASE,body:command()});assert.equal(response.status,503);assert.equal(body.requestId,R);
 assert.equal(body.outcome,'operation_unknown');assert.equal(applied,1);
 assert(!JSON.stringify(body).includes('8492'));assert(!JSON.stringify(body).includes('secret-do-not-release'));
}));
test('delivery is explicit POST and keeps BFF CSRF and current-email admission',()=>fixture(async({f,state,at,call})=>{
 owner(f,state,at);let invoked=false;state.ownerCommand=()=>{invoked=true;throw Error('No delivery SQL');};
 const path=BASE+'/requests/'+R+'/delivery',body={collectionId:I.group,installationId:I.installation,profile:'staff',grantVersion:1};
 assert.equal((await call({path,method:'GET'})).response.status,405);
 assert.equal((await call({path,body,headers:{'X-Collect-CSRF':''}})).response.status,403);
 assert.equal(invoked,false);
}));
