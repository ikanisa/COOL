import {test} from './helpers/fenced-node-test.js';
import {fixtureEnvironment} from './helpers/fenced-unit.js';
import assert from 'node:assert/strict';
import {isAbsolute,join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Real exported handler, email attestation, account wrapper, authRequest and
// application-fence code. SQL/provider responses below are local mocks only:
// this is not managed AMR/password eligibility, GoTrue current-password policy,
// signed-token, hosted recovery/logout or native PostgreSQL acceptance.
const root=process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof root==='string'&&isAbsolute(root),'Provide the coherent actual _shared source graph.');
const actual=name=>import(pathToFileURL(join(root,name)).href);
const {changeAdminPassword}=await actual('domain/admin_password.js');
const {attestAdminEmailAccount}=await actual('domain/admin_email_policy.js');
const {ApiError}=await actual('domain/core.js');
const NOW=1792497600,ORIGIN='https://admin-supabase-qa.collect.ikanisa.com';
const PROJECT='https://admin-password.synthetic.invalid',PUBLISHABLE='sb_publishable_synthetic_password';
const TOKEN='synthetic-current-session-access-token';
const CURRENT='synthetic-current-password',NEXT='synthetic-new-password-123';
const ADMIN='11111111-1111-4111-8111-111111111111',PRINCIPAL='22222222-2222-4222-8222-222222222222';
const AUTH='33333333-3333-4333-8333-333333333333',SID='44444444-4444-4444-8444-444444444444';
const PUBLIC='55555555-5555-4555-8555-555555555555',PROOF='66666666-6666-4666-8666-666666666666';
const COOKIE_HASH='a'.repeat(64);
const CONTEXT_SQL='SELECT private.set_admin_email_context(?::text,?::text,?::text,?::text) AS result';
const PASSWORD_GUARD_SQL='SELECT private.assert_admin_password_change_context() AS allowed';
const DELETE_SQL='DELETE FROM admin_sessions WHERE token_hash=?';
const validBody=()=>({currentPassword:CURRENT,newPassword:NEXT});
const failure=(status,code)=>error=>{
 assert.ok(error instanceof ApiError);assert.equal(error.status,status);assert.equal(error.code,code);
 for(const secret of [CURRENT,NEXT,TOKEN,PUBLISHABLE])assert.equal(error.message.includes(secret),false);
 return true;
};

async function fixture(options,run){
 const previousNow=Date.now,previousFetch=globalThis.fetch;
 Date.now=()=>NOW*1000;
 const prepared=[],batches=[],deletes=[],calls=[],events=[];
 const state={currentBffPresent:true};
 const account={id:ADMIN,principal_id:PRINCIPAL,auth_user_id:AUTH,auth_session_id:SID,
  token_hash:COOKIE_HASH,public_id:PUBLIC,origin:ORIGIN,auth_version:1,role:'owner',
  issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null,
  supabaseTokens:{access_token:TOKEN,refresh_token:'synthetic-refresh-never-dispatched'}};
 if(options.proof!=='missing')attestAdminEmailAccount(account,{contract_version:1,public_session_id:PUBLIC,
  email_verified_at:options.proof==='none'?null:options.proof==='stale'?NOW-301:NOW,
  proof_id:options.proof==='none'?null:PROOF});
 if(options.changedBinding)account.public_id=PROOF;
 const db={prepare(sql){
  const statement={sql,values:[],bind(...values){this.values=values;return this;},async run(){
   assert.equal(sql,DELETE_SQL,'Only the exact old BFF delete is an allowed direct write');
   assert.deepEqual(this.values,[COOKIE_HASH]);events.push('delete_old_bff');deletes.push({sql,values:[...this.values]});state.currentBffPresent=false;
   return {meta:{changes:1}};
  }};prepared.push(statement);return statement;
 },async batch(statements){
  batches.push(statements);events.push('sql_current_context_and_password_guard');
  assert.equal(statements.length,4);assert.equal(statements[0].sql,CONTEXT_SQL);
  assert.deepEqual(statements[0].values,[ADMIN,COOKIE_HASH,ORIGIN,PUBLIC]);
  assert.ok(statements[1].sql.startsWith('INSERT INTO admin_account_guards'));
  assert.equal(statements[1].values.at(-1),1,'The original fresh email policy remains requested');
  assert.equal(statements[2].sql,PASSWORD_GUARD_SQL);assert.deepEqual(statements[2].values,[]);
  assert.equal(statements[3].sql,'DELETE FROM admin_account_guards WHERE id=?');
  if(options.guardError)throw options.guardError;
  const guard=Object.hasOwn(options,'guard')?options.guard:{results:[{allowed:true}]};
  return [{results:[{result:{}}]},{results:[]},guard,{results:[]}];
 }};
 const env=fixtureEnvironment({DB:db,SUPABASE_URL:PROJECT,SUPABASE_PUBLISHABLE_KEY:PUBLISHABLE});
 globalThis.fetch=async(input,init)=>{
  const request=new Request(input,init),call={url:request.url,method:request.method,
   body:init?.body===undefined?null:JSON.parse(init.body),authorization:request.headers.get('Authorization'),
   apikey:request.headers.get('apikey'),redirect:request.redirect,signal:init?.signal};
  calls.push(call);
  assert.equal(call.authorization,'Bearer '+TOKEN);assert.equal(call.apikey,PUBLISHABLE);
  assert.equal(call.redirect,'error');assert.ok(call.signal instanceof AbortSignal);
  if(call.url===PROJECT+'/auth/v1/user'&&call.method==='PUT'){
   events.push('provider_password_put');
   assert.deepEqual(call.body,{password:NEXT,current_password:CURRENT});
   return options.put?options.put(call):Response.json({id:AUTH});
  }
  assert.equal(call.url,PROJECT+'/auth/v1/logout?scope=global');assert.equal(call.method,'POST');
  assert.equal(call.body,null);events.push('provider_explicit_global_logout');
  return options.logout?options.logout(call):new Response(null,{status:204});
 };
 const invoke=(value=validBody(),{raw=false,headers={}}={})=>changeAdminPassword(new Request(ORIGIN+'/api/admin/password',{
  method:'POST',headers:{'Content-Type':'application/json',...headers},body:raw?value:JSON.stringify(value),
 }),env,account);
 try{await run({account,env,prepared,batches,deletes,calls,events,state,invoke});}
 finally{globalThis.fetch=previousFetch;Date.now=previousNow;}
}
const noBusinessEffect=f=>{assert.deepEqual(f.calls,[]);assert.deepEqual(f.deletes,[]);assert.equal(f.state.currentBffPresent,true);};
const oldBffPreserved=f=>{assert.deepEqual(f.deletes,[]);assert.equal(f.state.currentBffPresent,true);};

for(const options of [{proof:'missing'},{proof:'none'},{proof:'stale'},{changedBinding:true}])test('fresh email proof is required before empty-body credentials: '+Object.keys(options)[0]+'/'+String(Object.values(options)[0]),{concurrency:false},()=>fixture(options,async f=>{
 await assert.rejects(f.invoke({}),failure(403,'recent_email_sign_in_required'));
 assert.deepEqual(f.prepared,[]);assert.deepEqual(f.batches,[]);noBusinessEffect(f);
 assert.equal(f.account.issued_assurance_level,1);assert.equal(f.account.issued_mfa_at,null);
}));

const invalidCredentials=[
 ['empty object',{}],['missing currentPassword',{newPassword:NEXT}],['missing newPassword',{currentPassword:CURRENT}],
 ['extra field',{...validBody(),nonce:'not-supported'}],['currentPassword wrong type',{...validBody(),currentPassword:42}],
 ['newPassword wrong type',{...validBody(),newPassword:null}],['empty currentPassword',{...validBody(),currentPassword:''}],
 ['oversized currentPassword',{...validBody(),currentPassword:'c'.repeat(513)}],
 ['short newPassword',{...validBody(),newPassword:'n'.repeat(11)}],
 ['oversized newPassword',{...validBody(),newPassword:'n'.repeat(129)}],
];
for(const [name,body]of invalidCredentials)test('credential shape is refused before any SQL/provider: '+name,{concurrency:false},()=>fixture({},async f=>{
 await assert.rejects(f.invoke(body),failure(400,'invalid_password_change'));
 assert.deepEqual(f.prepared,[]);assert.deepEqual(f.batches,[]);noBusinessEffect(f);
}));
for(const [name,raw,status,code]of [
 ['malformed JSON','{',400,'invalid_json'],['array','[]',400,'invalid_request'],['null','null',400,'invalid_request'],
 ['actual oversized streamed JSON',JSON.stringify({currentPassword:'x'.repeat(5000),newPassword:NEXT}),413,'request_too_large'],
])test('bounded body parsing refuses before SQL/provider: '+name,{concurrency:false},()=>fixture({},async f=>{
 await assert.rejects(f.invoke(raw,{raw:true}),failure(status,code));
 assert.deepEqual(f.prepared,[]);assert.deepEqual(f.batches,[]);noBusinessEffect(f);
}));

test('SQL recovery-only guard result becomes403 without PUT/logout/old BFF deletion',{concurrency:false},()=>fixture({guardError:new Error('password_recovery_required')},async f=>{
 await assert.rejects(f.invoke(),failure(403,'password_recovery_required'));
 assert.equal(f.batches.length,1);noBusinessEffect(f);
 assert.deepEqual(f.events,['sql_current_context_and_password_guard']);
 // SQL, not this mock, must distinguish actual signed AMR/managed OTP,
 // magiclink/recovery and absent encrypted_password. No such proof is forged.
}));
test('proof expiry inside the SQL batch preserves the dedicated email recovery code',{concurrency:false},()=>fixture({guardError:new Error('recent_email_sign_in_required')},async f=>{
 await assert.rejects(f.invoke(),failure(403,'recent_email_sign_in_required'));noBusinessEffect(f);
}));
for(const [name,guard]of [
 ['false',{results:[{allowed:false}]}],['null row',{results:[null]}],['missing allowed',{results:[{}]}],
 ['string true',{results:[{allowed:'true'}]}],['numeric true',{results:[{allowed:1}]}],
 ['zero rows',{results:[]}],['multiple rows',{results:[{allowed:true},{allowed:true}]}],
 ['missing result field',{}],['null result',null],['malformed results array',{results:{allowed:true}}],
])test('inexact SQL authority fails closed without provider/local effect: '+name,{concurrency:false},()=>fixture({guard},async f=>{
 await assert.rejects(f.invoke(),failure(503,'password_change_unavailable'));
 assert.equal(f.batches.length,1);noBusinessEffect(f);
}));

test('eligible password change sends exact current_password once then explicit global logout then deletes old BFF/cookie',{concurrency:false},()=>fixture({},async f=>{
 const response=await f.invoke();assert.equal(response.status,200);assert.deepEqual(await response.json(),{ok:true});
 assert.equal(response.headers.get('Set-Cookie'),'__Host-collect_admin=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0; Secure');
 assert.equal(response.headers.get('Cache-Control'),'no-store');assert.equal(f.calls.length,2);
 assert.deepEqual(f.calls.map(c=>[c.method,c.url]),[['PUT',PROJECT+'/auth/v1/user'],['POST',PROJECT+'/auth/v1/logout?scope=global']]);
 assert.deepEqual(f.calls[0].body,{password:NEXT,current_password:CURRENT});assert.equal(f.calls[1].body,null);
 assert.deepEqual(f.events,['sql_current_context_and_password_guard','provider_password_put','provider_explicit_global_logout','delete_old_bff']);
 assert.equal(f.deletes.length,1);assert.deepEqual(f.deletes[0],{sql:DELETE_SQL,values:[COOKIE_HASH]});assert.equal(f.state.currentBffPresent,false);
 assert.equal(f.account.auth_session_id,SID);assert.equal(f.account.public_id,PUBLIC);assert.equal(f.account.issued_assurance_level,1);assert.equal(f.account.issued_mfa_at,null);
}));

for(const [name,put,status,code]of [
 ['current password rejected',()=>Response.json({error_code:'current_password_invalid'},{status:403}),403,'current_password_invalid'],
 ['new password rejected',()=>Response.json({error_code:'weak_password'},{status:422}),422,'weak_password'],
 ['provider unavailable/unknown',()=>Response.json({error_code:'synthetic_unavailable'},{status:503}),503,'synthetic_unavailable'],
 ['non-JSON accepted status remains unknown',()=>new Response('not JSON',{status:200}),503,'auth_unavailable'],
])test('PUT refusal/unknown has no subsequent logout/delete/replay: '+name,{concurrency:false},()=>fixture({put},async f=>{
 await assert.rejects(f.invoke(),failure(status,code));assert.equal(f.calls.length,1);assert.equal(f.calls[0].method,'PUT');oldBffPreserved(f);
 assert.deepEqual(f.events,['sql_current_context_and_password_guard','provider_password_put']);
}));
test('PUT transport ambiguity is not retried and never clears the current BFF',{concurrency:false},async()=>{
 const unknown=new Error('synthetic unconfirmed PUT transport');
 await fixture({put:()=>{throw unknown;}},async f=>{
  await assert.rejects(f.invoke(),error=>error===unknown);assert.equal(f.calls.length,1);oldBffPreserved(f);
  assert.deepEqual(f.events,['sql_current_context_and_password_guard','provider_password_put']);
 });
});
for(const [name,logout,status,code]of [
 ['unavailable/unknown',()=>Response.json({error_code:'synthetic_logout_unavailable'},{status:503}),503,'synthetic_logout_unavailable'],
 ['rejected',()=>Response.json({error_code:'synthetic_logout_rejected'},{status:401}),401,'synthetic_logout_rejected'],
 ['unconfirmed non-JSON success',()=>new Response('not JSON',{status:200}),503,'auth_unavailable'],
])test('post-PUT logout failure preserves local old BFF without another mutation: '+name,{concurrency:false},()=>fixture({logout},async f=>{
 await assert.rejects(f.invoke(),failure(status,code));assert.equal(f.calls.length,2);oldBffPreserved(f);
 assert.deepEqual(f.calls.map(c=>c.method),['PUT','POST']);
 assert.deepEqual(f.events,['sql_current_context_and_password_guard','provider_password_put','provider_explicit_global_logout']);
}));
test('post-PUT logout transport ambiguity does not retry PUT/logout or delete the current BFF',{concurrency:false},async()=>{
 const unknown=new Error('synthetic unconfirmed logout transport');
 await fixture({logout:()=>{throw unknown;}},async f=>{
  await assert.rejects(f.invoke(),error=>error===unknown);assert.equal(f.calls.length,2);oldBffPreserved(f);
  assert.deepEqual(f.events,['sql_current_context_and_password_guard','provider_password_put','provider_explicit_global_logout']);
 });
});
