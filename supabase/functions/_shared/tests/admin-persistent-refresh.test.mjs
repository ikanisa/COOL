import {test} from './helpers/fenced-node-test.js';
import {fixtureEnvironment} from './helpers/fenced-unit.js';
import assert from 'node:assert/strict';
import {isAbsolute,join} from 'node:path';
import {pathToFileURL} from 'node:url';

const root=process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof root==='string'&&isAbsolute(root));
const actual=name=>import(pathToFileURL(join(root,name)).href);
const {adminAccountSession,handleAdminAccounts}=await actual('domain/admin_accounts.js');
const {encrypt}=await actual('domain/encryption.js');
const {digest}=await actual('domain/core.js');
const BASE=1792497600,ORIGIN='https://admin-test.example.invalid',PROJECT='https://auth-test.example.invalid';
const AUTH='11111111-1111-4111-8111-111111111111',SID='22222222-2222-4222-8222-222222222222';
const PRINCIPAL='33333333-3333-4333-8333-333333333333',ADMIN='44444444-4444-4444-8444-444444444444';
const PUBLIC='55555555-5555-4555-8555-555555555555',COOKIE='b'.repeat(64),KEY=Buffer.alloc(32,7).toString('base64');
const jwt=(exp,aal='aal1')=>[Buffer.from('{}').toString('base64url'),Buffer.from(JSON.stringify({sub:AUTH,session_id:SID,role:'authenticated',aud:'authenticated',iss:PROJECT+'/auth/v1',aal,exp,iat:BASE,amr:[{method:'password',timestamp:BASE-600}]})).toString('base64url'),'signature'].join('.');

async function fixture(options,run){
 const oldNow=Date.now,oldFetch=globalThis.fetch;let now=BASE;Date.now=()=>now*1000;
 const hash=await digest(COOKIE),crypt={DATA_KEY_ID:'synthetic-bff',DATA_ENCRYPTION_KEY:KEY};
 const cipher=await encrypt(crypt,new TextEncoder().encode(JSON.stringify({access_token:jwt(BASE-1),refresh_token:'synthetic-parent'})),`bff:${SID}:${AUTH}`);
 let started,release;const refreshStarted=new Promise(resolve=>{started=resolve;}),refreshGate=new Promise(resolve=>{release=resolve;});
 const state={row:{token_hash:hash,auth_user_id:AUTH,auth_session_id:SID,admin_email:'synthetic@example.invalid',token_ciphertext:cipher,version:1,refresh_lease:null,refresh_lease_until:null,expires_at:BASE+3600},deleted:false,posts:0,refreshInputs:[],commits:0,providerLogouts:0,
  ownerBatches:0,ownerIdentity:{schemaVersion:1,adminId:'owner-opaque-id',principalId:'principal-opaque-id',email:'configured.owner@example.invalid'},ownerGuardFailure:false,ownerFailure:null,ownerViewerPatch:{},ownerGrants:['admin_users.manage']};
 state.row.issued_assurance_level=1;
 const account={id:ADMIN,email:'synthetic@example.invalid',role:'owner',status:'active',auth_version:1,principal_id:PRINCIPAL,public_id:PUBLIC,token_hash:hash,auth_session_id:SID,origin:ORIGIN,expires_at:BASE+3600,issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null,auth_at:BASE-600};
 const db={claims:{},setClaims(value){this.claims=value;},async context(){},async batch(statements){
   state.ownerBatches++;
   assert.equal(statements.length,6);
   assert.match(statements[0].sql,/^SELECT private\.set_admin_email_context\(/);
   assert.match(statements[1].sql,/^INSERT INTO admin_account_guards/);
   assert.equal(statements[2].sql,'SELECT private.collect_owner_attestation() AS result');
   assert.match(statements[3].sql,/^SELECT a\.id,a\.email,a\.role,a\.auth_version/);
   assert.match(statements[4].sql,/FOR SHARE OF c,g/);
   assert.match(statements[5].sql,/^DELETE FROM admin_account_guards/);
   if(state.ownerGuardFailure)throw Error('admin_account_authority');
   if(state.ownerFailure)throw state.ownerFailure;
   return [{results:[]},{results:[]},{results:[{result:state.ownerIdentity}]},
    {results:[{id:account.id,email:account.email,role:account.role,auth_version:account.auth_version,principal_id:account.principal_id,...state.ownerViewerPatch}]},
    {results:state.ownerGrants.map(permission=>({permission}))},{results:[]}];
  },async transaction(fn){
   return fn({unsafe:async(sql,args)=>{
    if(sql.startsWith('SELECT pg_advisory_xact_lock'))return [];
    if(sql.startsWith('SELECT s.token_hash'))return !state.deleted&&state.row.version===args[1]&&state.row.refresh_lease===args[2]?[{token_hash:hash}]:[];
    if(sql.startsWith('SELECT token_hash FROM app.admin_sessions'))return !state.deleted&&args[0]===hash&&args[1]===ORIGIN?[{token_hash:hash}]:[];
    if(sql.startsWith('SELECT auth_user_id,auth_session_id,token_ciphertext'))return state.deleted?[]:[{...state.row}];
    if(sql.startsWith('DELETE FROM app.admin_sessions')){state.deleted=true;return [];}
    throw Error('unexpected transaction SQL');
   }});
  },prepare(sql){return {sql,args:[],bind(...args){this.args=args;return this;},async first(){
   const a=this.args;
   if(sql.startsWith('SELECT b.*,s.expires_at'))return state.deleted?null:{...state.row};
   if(sql.startsWith('SELECT * FROM private.bff_sessions'))return state.deleted?null:{...state.row};
   if(sql.startsWith('UPDATE private.bff_sessions SET refresh_lease=NULL')){
    if(state.row.token_hash!==a[0]||state.row.version!==a[1]||state.row.refresh_lease!==a[2])return null;
    state.row.refresh_lease=null;state.row.refresh_lease_until=null;return {token_hash:hash};
   }
   if(sql.startsWith('UPDATE private.bff_sessions SET refresh_lease=')){
    if(sql.includes('AND refresh_lease IS NULL')){
     if(state.deleted||state.row.version!==a[3]||state.row.refresh_lease!==null)return null;
    }else{
     if(options.reclaimRace){state.row.refresh_lease='another-owner';return null;}
     if(state.deleted||state.row.version!==a[3]||state.row.refresh_lease!==a[4]||state.row.refresh_lease_until!==a[5]||state.row.token_ciphertext!==a[6])return null;
    }
    state.row.refresh_lease=a[0];state.row.refresh_lease_until=a[1];return{token_hash:hash};
   }
   if(sql.startsWith('UPDATE private.bff_sessions SET token_ciphertext=')){
    if(state.deleted||state.row.refresh_lease!==a[2]||state.row.version!==a[3])return null;
    state.row.token_ciphertext=a[0];state.row.version++;state.row.refresh_lease=null;state.row.refresh_lease_until=null;state.commits++;
    if(options.lostCommit&&state.commits===1)throw Error('synthetic lost commit response');
    return{version:state.row.version};
   }
   if(sql.startsWith('SELECT private.is_managed_session('))return{allowed:true};
   if(sql==='SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?')return{user_id:PRINCIPAL};
   if(sql==='SELECT * FROM users WHERE id=?')return{id:PRINCIPAL,access_status:'active',full_name:'Synthetic',public_id:'100001'};
   if(sql==='SELECT * FROM auth_sessions WHERE id=?')return{id:SID,user_id:PRINCIPAL,surface:'admin',auth_at:BASE-600,created_at:BASE-600,expires_at:BASE+3600,revoked_at:null,assurance_level:1,mfa_at:null,mfa_factor_id:null};
   if(sql.startsWith('SELECT a.id FROM admin_sessions s JOIN admin_users a'))return{id:ADMIN};
   if(sql.startsWith('SELECT a.*,s.public_id'))return{...account};
   if(sql.startsWith('SELECT private.admin_email_status('))return{result:{contract_version:1,public_session_id:PUBLIC,email_verified_at:null,proof_id:null}};
   throw Error('unexpected fixture query');
  },async all(){if(sql.startsWith('SELECT g.permission FROM admin_grants')||sql.startsWith('SELECT c.permission FROM admin_account_role_capabilities'))return{results:[{permission:'admin_users.manage'}]};throw Error('unexpected fixture all');}};}};
 globalThis.fetch=async(input,init)=>{
  const request=new Request(input,init);
  if(request.url===PROJECT+'/auth/v1/token?grant_type=refresh_token'){
   const body=await request.json();state.refreshInputs.push(body.refresh_token);state.posts++;
   if(options.pauseRefresh){started();await refreshGate;}
   if(options.invalid)return Response.json({error_code:'refresh_token_not_found'},{status:400});
   if(options.nonterminal&&state.posts===1)return Response.json({error_code:'validation_failed'}, {status:options.nonterminal});
   if(options.misleadingTerminal&&state.posts===1)return Response.json({error_code:'refresh_token_not_found'}, {status:503});
   if(options.transient&&state.posts===1)return Response.json({error_code:'temporary'}, {status:503});
   return Response.json({access_token:jwt(now+3600,options.refreshAal2?'aal2':'aal1'),refresh_token:'synthetic-child'});
  }
  if(request.url===PROJECT+'/auth/v1/logout?scope=local'){
   state.providerLogouts++;assert.equal(state.deleted,true,'local revocation commits before the provider request');
   return options.logoutUnavailable?Response.json({error_code:'temporary'}, {status:503}):
    options.logoutExpired?Response.json({error_code:'bad_jwt'}, {status:401}):new Response(null,{status:204});
  }
  assert.equal(request.url,PROJECT+'/auth/v1/user');
  return Response.json({id:AUTH,email:'synthetic@example.invalid',email_confirmed_at:'2026-10-20T12:00:00Z',app_metadata:{provider:'email'}});
 };
 const request=(extra={})=>new Request(ORIGIN+'/api/admin/auth/session',{headers:{Cookie:'__Host-collect_admin='+COOKIE,Origin:ORIGIN,'X-Collect-Requested-With':'collect-admin',...extra}});
 const logoutRequest=async({csrf=true,cookie=true}={})=>new Request(ORIGIN+'/api/admin/auth/logout',{method:'POST',headers:{...(cookie?{Cookie:'__Host-collect_admin='+COOKIE}:{}),Origin:ORIGIN,'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json',...(csrf?{'X-Collect-CSRF':await digest('collect-admin-csrf:'+COOKIE)}:{})},body:'{}'});
 const environment=()=>fixtureEnvironment({DB:db,SUPABASE_URL:PROJECT,SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_bff',ADMIN_ORIGIN:ORIGIN,SESSION_KEY_ID:'synthetic-bff',SESSION_ENCRYPTION_KEY:KEY});
 try{await run({state,request,logoutRequest,environment,refreshStarted,releaseRefresh:release,advance:seconds=>{now+=seconds;}});}finally{release();Date.now=oldNow;globalThis.fetch=oldFetch;}
}

test('owner identity requires both explicit server flag and versioned authenticated session opt-in', {concurrency:false},async()=>fixture({},async f=>{
 const version={'X-Collect-Owner-Identity-Version':'1'};
 for(const [flag,headers] of [[undefined,version],['false',version],['true',{}],['true',{'X-Collect-Owner-Identity-Version':'2'}]]){
  const env=f.environment();if(flag!==undefined)env.COLLECT_ADMIN_OWNER_IDENTITY_ENABLED=flag;
  const response=await handleAdminAccounts(f.request(headers),env,{}),body=await response.json();
  assert.deepEqual(Object.keys(body).sort(),['csrfToken','expiresAt','ownerEmail','user']);assert.equal(body.ownerEmail,'info@ikanisa.com');
  assert.match(response.headers.get('cache-control'),/no-store/);
 }
 assert.equal(f.state.ownerBatches,0);
 const env=f.environment();env.COLLECT_ADMIN_OWNER_IDENTITY_ENABLED='true';
 const response=await handleAdminAccounts(f.request(version),env,{}),body=await response.json();
 assert.deepEqual(body.ownerIdentity,f.state.ownerIdentity);assert.equal(body.ownerEmail,'configured.owner@example.invalid');
 assert.equal(body.user.id,ADMIN);assert.equal(f.state.ownerBatches,1);assert.match(response.headers.get('cache-control'),/no-store/);
}));

test('owner identity signed-out response remains legacy-shaped and performs no proof query', {concurrency:false},async()=>fixture({},async f=>{
 const env=f.environment();env.COLLECT_ADMIN_OWNER_IDENTITY_ENABLED='true';
 const request=new Request(ORIGIN+'/api/admin/auth/session',{headers:{Origin:ORIGIN,'X-Collect-Owner-Identity-Version':'1'}});
 const response=await handleAdminAccounts(request,env,{}),body=await response.json();
 assert.deepEqual(body,{user:null,expiresAt:null,ownerEmail:'info@ikanisa.com',csrfToken:null});assert.equal(f.state.ownerBatches,0);
}));

test('missing, malformed or unavailable owner proof preserves ordinary session without owner authority', {concurrency:false},async()=>fixture({},async f=>{
 const env=f.environment();env.COLLECT_ADMIN_OWNER_IDENTITY_ENABLED='true';const req=()=>f.request({'X-Collect-Owner-Identity-Version':'1'});
 for(const value of [null,{}, {schemaVersion:2,adminId:'a',principalId:'b',email:'owner@example.invalid'},
  {schemaVersion:1,adminId:'invalid\nowner',principalId:'b',email:'owner@example.invalid'},
  {schemaVersion:1,adminId:'a',principalId:'b',email:'INVALID'},
  {schemaVersion:1,adminId:'a',principalId:'b',email:'owner@example.invalid',extra:true}]){
  f.state.ownerIdentity=value;const body=await (await handleAdminAccounts(req(),env,{})).json();
  assert.equal(body.ownerIdentity,null);assert.equal(body.ownerEmail,null);assert.equal(body.user.id,ADMIN);
 }
 f.state.ownerFailure=Error('synthetic owner store unavailable');
 const body=await (await handleAdminAccounts(req(),env,{})).json();assert.equal(body.ownerIdentity,null);assert.equal(body.ownerEmail,null);assert.equal(body.user.id,ADMIN);
}));

test('revoked or changed viewer and changed grant set never receive owner identity', {concurrency:false},async()=>fixture({},async f=>{
 const env=f.environment();env.COLLECT_ADMIN_OWNER_IDENTITY_ENABLED='true';const req=()=>f.request({'X-Collect-Owner-Identity-Version':'1'});
 for(const patch of [{id:'other'},{email:'other@example.invalid'},{role:'staff'},{auth_version:2},{principal_id:'other'}]){
  f.state.ownerViewerPatch=patch;const body=await (await handleAdminAccounts(req(),env,{})).json();assert.equal(body.ownerIdentity,null);
 }
 f.state.ownerViewerPatch={};f.state.ownerGrants=[];
 assert.equal((await (await handleAdminAccounts(req(),env,{})).json()).ownerIdentity,null);
 f.state.ownerGrants=['admin_users.manage'];f.state.ownerGuardFailure=true;
 assert.equal((await (await handleAdminAccounts(req(),env,{})).json()).ownerIdentity,null);
}));

test('application fence failure is never hidden by optional owner metadata', {concurrency:false},async()=>fixture({},async f=>{
 const env=f.environment();env.COLLECT_ADMIN_OWNER_IDENTITY_ENABLED='true';f.state.ownerFailure=Object.assign(Error('fenced'),{code:'application_fence_unavailable'});
 await assert.rejects(handleAdminAccounts(f.request({'X-Collect-Owner-Identity-Version':'1'}),env,{}),e=>e.code==='application_fence_unavailable');
}));

test('Admin refresh survives a temporary unknown provider outcome', {concurrency:false},async()=>fixture({transient:true},async f=>{
 await assert.rejects(adminAccountSession(f.request(),f.environment()),e=>e.status===503&&e.code==='session_refresh_pending');
 assert.equal(f.state.deleted,false);assert.equal(f.state.row.version,1);assert.ok(f.state.row.refresh_lease);
 f.advance(31);
 const account=await adminAccountSession(f.request(),f.environment());
 assert.equal(account.auth_session_id,SID);assert.equal(account.auth_at,BASE-600);assert.equal(account.issued_mfa_at,null);
 assert.deepEqual(f.state.refreshInputs,['synthetic-parent','synthetic-parent']);assert.equal(f.state.row.version,2);assert.equal(f.state.deleted,false);
}));

test('an old AAL1 cookie cannot inherit AAL2 through an ordinary provider refresh', {concurrency:false},async()=>fixture({refreshAal2:true},async f=>{
 await assert.rejects(adminAccountSession(f.request(),f.environment()),e=>e.status===409&&e.code==='mfa_recovery_required');
 assert.equal(f.state.posts,1);assert.equal(f.state.commits,0);assert.equal(f.state.row.version,1);
 assert.equal(f.state.row.refresh_lease,null);assert.equal(f.state.deleted,false);
}));

test('an in-flight MFA intent blocks generic session promotion without deleting its saved cookie', {concurrency:false},async()=>fixture({},async f=>{
 f.state.row.mfa_intent_hash='e'.repeat(64);
 await assert.rejects(adminAccountSession(f.request(),f.environment()),e=>e.status===409&&e.code==='mfa_recovery_pending');
 assert.equal(f.state.posts,0);assert.equal(f.state.deleted,false);assert.equal(f.state.row.version,1);
}));

test('a lost database commit reply uses the exact retained winner without a second refresh', {concurrency:false},async()=>fixture({lostCommit:true},async f=>{
 const account=await adminAccountSession(f.request(),f.environment());
 assert.equal(account.auth_session_id,SID);assert.equal(f.state.posts,1);assert.equal(f.state.row.version,2);assert.equal(f.state.deleted,false);
}));

test('a definite invalid refresh revokes only the still-owned cookie session', {concurrency:false},async()=>fixture({invalid:true},async f=>{
 await assert.rejects(adminAccountSession(f.request(),f.environment()),e=>e.status===401&&e.code==='session_refresh_recovery_required');
 assert.equal(f.state.deleted,true);assert.equal(f.state.posts,1);
}));

test('a changed recovery lease never retries or deletes another owner session', {concurrency:false},async()=>fixture({transient:true,reclaimRace:true},async f=>{
 await assert.rejects(adminAccountSession(f.request(),f.environment()),e=>e.status===503);
 f.advance(31);await assert.rejects(adminAccountSession(f.request(),f.environment()),e=>e.status===409&&e.code==='session_refresh_pending');
 assert.equal(f.state.posts,1);assert.equal(f.state.deleted,false);
}));

for(const status of [400,403])test('unrelated provider '+status+' leaves the saved session recoverable', {concurrency:false},async()=>fixture({nonterminal:status},async f=>{
 await assert.rejects(adminAccountSession(f.request(),f.environment()),e=>e.status===503&&e.code==='session_refresh_pending');
 assert.equal(f.state.deleted,false);f.advance(31);
 assert.ok(await adminAccountSession(f.request(),f.environment()));assert.equal(f.state.deleted,false);
}));

test('a provider 503 cannot be treated as a definitive token revocation even with a terminal-looking code', {concurrency:false},async()=>fixture({misleadingTerminal:true},async f=>{
 await assert.rejects(adminAccountSession(f.request(),f.environment()),e=>e.status===503&&e.code==='session_refresh_pending');
 assert.equal(f.state.deleted,false);f.advance(31);assert.ok(await adminAccountSession(f.request(),f.environment()));
}));

test('manual logout revokes the local session even when the provider is unavailable', {concurrency:false},async()=>fixture({logoutUnavailable:true},async f=>{
 const result=await handleAdminAccounts(await f.logoutRequest(),f.environment(),{}),body=await result.json();
 assert.equal(body.ok,true);assert.equal(body.providerLogout,'unconfirmed');assert.equal(f.state.deleted,true);assert.equal(f.state.providerLogouts,1);
 assert.match(result.headers.get('Set-Cookie'),/Max-Age=0/);
 assert.equal(await adminAccountSession(f.request(),f.environment(),false),null);
}));

test('manual logout still revokes local access if the retained provider token is expired', {concurrency:false},async()=>fixture({logoutExpired:true},async f=>{
 const result=await handleAdminAccounts(await f.logoutRequest(),f.environment(),{}),body=await result.json();
 assert.equal(body.ok,true);assert.equal(body.providerLogout,'unconfirmed');assert.equal(f.state.deleted,true);
 assert.equal(await adminAccountSession(f.request(),f.environment(),false),null);
}));

test('a refresh already in flight cannot restore a manually logged-out session', {concurrency:false},async()=>fixture({pauseRefresh:true,logoutExpired:true},async f=>{
 const pending=adminAccountSession(f.request(),f.environment());await f.refreshStarted;
 const result=await handleAdminAccounts(await f.logoutRequest(),f.environment(),{});assert.equal((await result.json()).ok,true);
 f.releaseRefresh();await assert.rejects(pending,e=>e.status===401);assert.equal(f.state.deleted,true);
}));

test('manual logout requires the cookie-bound CSRF proof and is idempotent without a cookie', {concurrency:false},async()=>fixture({},async f=>{
 await assert.rejects(handleAdminAccounts(await f.logoutRequest({csrf:false}),f.environment(),{}),e=>e.status===403&&e.code==='csrf_rejected');
 assert.equal(f.state.deleted,false);assert.equal(f.state.providerLogouts,0);
 const result=await handleAdminAccounts(await f.logoutRequest({cookie:false}),f.environment(),{});
 assert.equal((await result.json()).ok,true);assert.match(result.headers.get('Set-Cookie'),/Max-Age=0/);assert.equal(f.state.deleted,false);
}));

test('password recovery uses the shared batch lock and never reactivates changed authority', {concurrency:false},async()=>{
 const previousFetch=globalThis.fetch,calls=[],batches=[];let eligible=true;
 const access=jwt(Math.floor(Date.now()/1000)+3600);
 const db={prepare(sql){return {sql,args:[],bind(...args){this.args=args;return this;},async first(){
  assert.match(sql,/SELECT id,auth_version FROM admin_users/);return{id:ADMIN,auth_version:5};
 },async run(){throw Error('Admin authority change must use a batch');}};},async batch(statements){
  batches.push(statements);assert.equal(statements.length,1);assert.match(statements[0].sql,/auth_version=auth_version\+1/);
  assert.match(statements[0].sql,/status IN\('active','invited'\) AND auth_version=\?/);assert.deepEqual(statements[0].args.slice(-2),[ADMIN,5]);
  return[{results:[],meta:{changes:eligible?1:0}}];
 }};
 globalThis.fetch=async(input,init)=>{const r=new Request(input,init);calls.push([r.method,new URL(r.url).pathname]);
  if(r.url===PROJECT+'/auth/v1/verify')return Response.json({access_token:access,refresh_token:'synthetic-refresh'});
  if(r.url===PROJECT+'/auth/v1/user'&&r.method==='GET')return Response.json({id:AUTH,email:'synthetic@example.invalid',email_confirmed_at:'2026-10-20T12:00:00Z'});
  if(r.url===PROJECT+'/auth/v1/user'&&r.method==='PUT')return Response.json({id:AUTH});
  if(r.url===PROJECT+'/auth/v1/logout')return new Response(null,{status:204});
  throw Error('unexpected provider request');
 };
 try{
  const env=fixtureEnvironment({DB:db,SUPABASE_URL:PROJECT,SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_bff',ADMIN_ORIGIN:ORIGIN});
  const request=()=>new Request(ORIGIN+'/api/admin/auth/complete-password',{method:'POST',headers:{Origin:ORIGIN,'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json'},
   body:JSON.stringify({token:'t'.repeat(32),password:'synthetic-new-password',invite:false})});
  const response=await handleAdminAccounts(request(),env,{});assert.equal((await response.json()).ok,true);
  assert.equal(batches.length,1);assert.deepEqual(calls.map(v=>v[0]),['POST','GET','PUT','POST']);
  eligible=false;calls.length=0;
  await assert.rejects(handleAdminAccounts(request(),env,{}),e=>e.status===503&&e.code==='password_recovery_unconfirmed');
  assert.deepEqual(calls.map(v=>v[0]),['POST','GET','PUT','POST'],'changed authority closes the recovery provider session without reactivating the account');
 }finally{globalThis.fetch=previousFetch;}
});
