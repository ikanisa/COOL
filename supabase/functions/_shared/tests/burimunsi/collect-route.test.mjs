/** Production route/gate/auth/SQL adapters over a reduced SQLite fixture.
 * GoTrue verification responses, PostgreSQL functions/locks/RLS and financial
 * bridge effects are simulated or forbidden. This is source integration proof,
 * never hosted identity, migration, provider or financial acceptance. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {collectNativeRoute,createCollectNativeRoute} from '../../domain/burimunsi/collect-route.js';
import {applicationWorkTuple,openApplicationWork} from '../../application-fence.js';
import {canonicalProfile} from '../../deployment-profile.js';
import {CONTRACT_VERSION} from '../../domain/burimunsi/wire/native-contract.mjs';
import {sha256} from '../../domain/burimunsi/values.js';
import {principalFixture,I} from './native-principal-fixture.mjs';
import {installCanonicalHarness} from './posting-authority-fixture.mjs';
// Existing Node-only shim denies real PostgreSQL/SMTP construction while the
// actual dispatcher imports its Deno npm: modules. No runtime source is replaced.
await import('../helpers/node-postgres-import.mjs');
const {default:collectWorker}=await import('../../domain/index.js');

const SOURCE='1'.repeat(64);
const PROFILE=Object.freeze({format:'collect.deployment.v1',id:'fixture-local',mode:'self_hosted',
  environment:'qualification',supabase_origin:'https://supabase.example.test',
  member_api_origin:'https://api.example.test',admin_origin:'https://admin.example.test',
  public_origin:'https://public.example.test',google_callback_origin:'https://admin.example.test'});
const NATIVE_TOKEN='a'.repeat(64);
const unused=()=>{throw Error('Unexercised bridge: this route test cannot write financial or account data');};
function settings(groupId=I.group){return {enabled:true,groupId,origin:PROFILE.supabase_origin,
  canonicalIntegrationEnabled:true,nativePostingAuthorityEnabled:true,sharedPostingEnabled:true,
  journalEvidenceEnabled:true,journalAllocationEnabled:true,postingPreparationEnabled:true};}

async function fixture(){
  const f=principalFixture(),h=installCanonicalHarness(f);
  const state={providerCalls:0,bridgeCalls:0,projectionQueries:[],writes:0,claims:null,asserts:0};
  const fenceRow={contractVersion:1,admissionId:I.request,sourceSha256:SOURCE,epoch:1,kind:'http_collect',mode:'open',state:'active'};
  const work=await openApplicationWork({sourceSha256:SOURCE,kind:'http_collect',id:I.request,backend:{
    register:async()=>fenceRow,lease:async()=>({row:fenceRow,assert:async()=>{state.asserts++;return fenceRow;},release:async()=>{}}),
    close:async(_id,_epoch,_source,outcome,reason,externalDispatches,uncertainDispatches)=>
      ({...fenceRow,state:outcome,reason,externalDispatches,uncertainDispatches}),status:unused}});
  f.db.applicationWork=work;f.db.setClaims=claims=>{state.claims=claims;};
  f.sqlite.exec(`CREATE TABLE private.auth_principal_links(auth_user_id TEXT PRIMARY KEY,user_id TEXT);
    CREATE TABLE private.burimunsi_session_links(native_session_id TEXT PRIMARY KEY,collection_id TEXT,account_id TEXT,
      principal_user_id TEXT,principal_session_id TEXT,created_at INTEGER,expires_at INTEGER);
    CREATE TABLE admin_users(id TEXT PRIMARY KEY,status TEXT,auth_version INTEGER,role TEXT);
    CREATE TABLE admin_sessions(user_id TEXT,auth_session_id TEXT,auth_version INTEGER,expires_at INTEGER);
    CREATE TABLE admin_principal_links(admin_user_id TEXT,user_id TEXT);
    CREATE TABLE admin_grants(user_id TEXT,permission TEXT);
    CREATE TABLE admin_account_role_capabilities(role TEXT,permission TEXT);`);
  f.sqlite.prepare('INSERT INTO private.auth_principal_links VALUES(?,?)').run(I.account,I.principal);
  f.sqlite.prepare('INSERT INTO private.burimunsi_session_links VALUES(?,?,?,?,?,?,?)').run(
    I.session,I.group,I.account,I.principal,I.canonical,I.now-1000,I.now+60000);
  f.sqlite.prepare('INSERT INTO admin_users VALUES(?,?,?,?)').run('fixture-admin','active',1,'staff');
  f.sqlite.prepare('INSERT INTO admin_sessions VALUES(?,?,?,?)').run('fixture-admin',I.canonical,1,Math.floor(Date.now()/1000)+3600);
  f.sqlite.prepare('INSERT INTO admin_principal_links VALUES(?,?)').run('fixture-admin',I.principal);
  f.sqlite.prepare('INSERT INTO admin_grants VALUES(?,?)').run(I.principal,'collections.view');
  f.sqlite.prepare('INSERT INTO admin_account_role_capabilities VALUES(?,?)').run('staff','collections.view');
  f.sqlite.prepare('UPDATE private.burimunsi_sessions SET token_hash=?').run(await sha256(NATIVE_TOKEN));
  // projectSession's actual read statements run against the same fixture DB.
  // Only the PostgreSQL managed-session function is a labeled test substitute.
  f.db.prepare=sql=>({bind:(...values)=>{
    const read=()=>{
      state.projectionQueries.push({sql,values});
      if(sql.startsWith('SELECT private.is_managed_session'))return [{allowed:values[0]===I.account&&values[1]===I.canonical&&h.managed}];
      const translated=sql.replaceAll('::uuid','').replace(/\bFROM users\b/g,'FROM app.users')
        .replace(/\bFROM auth_sessions\b/g,'FROM app.auth_sessions');
      return f.sqlite.prepare(translated).all(...values).map(row=>({...row}));
    };
    return {first:async()=>read()[0]??null,all:async()=>({results:read()}),run:async()=>{state.writes++;return unused();}};
  }});
  const raw=canonicalProfile(PROFILE);
  const env={DB:f.db,COLLECT_FENCE_WORK:work,BUILD_SOURCE_ID:SOURCE,COLLECT_DEPLOYMENT_PROFILE:raw,
    COLLECT_DEPLOYMENT_PROFILE_SHA256:await sha256(raw),SUPABASE_URL:PROFILE.supabase_origin,
    SUPABASE_PUBLISHABLE_KEY:'fixture-public-only'};
  const claims={sub:I.account,session_id:I.canonical,role:'authenticated',aud:'authenticated',
    iss:PROFILE.supabase_origin+'/auth/v1',exp:Math.floor(Date.now()/1000)+3600,
    amr:[{method:'otp',timestamp:Math.floor(I.now/1000)}]};
  const token=()=>Buffer.from('{"alg":"RS256","typ":"JWT"}').toString('base64url')+'.'+
    Buffer.from(JSON.stringify(claims)).toString('base64url')+'.fixture-signature';
  const originalFetch=globalThis.fetch;
  globalThis.fetch=async(input,options)=>{
    state.providerCalls++;
    assert.equal(String(input),PROFILE.supabase_origin+'/auth/v1/user');
    assert.equal(options.method,'GET');assert.equal(options.headers.Authorization,'Bearer '+token());
    return Response.json({id:I.account,is_anonymous:false});
  };
  const options={profile:PROFILE,config:settings(),clock:()=>I.now,
    secrets:{pinPepper:new Uint8Array(32).fill(1),pinPepperId:'fixture-only',cursorKey:new Uint8Array(32).fill(2)},
    networkBucket:unused,bridgeFactory:async inputs=>{
      state.bridgeCalls++;state.bridgeInputs=inputs;
      assert.equal(inputs.db,f.db);assert.equal(inputs.env.DB,f.db);assert.equal(inputs.work,work);
      assert.equal(inputs.admission.principalUserId,I.principal);assert.equal(inputs.admission.principalSessionId,I.canonical);
      assert.deepEqual(applicationWorkTuple(inputs.work),[I.request,1,SOURCE]);
      const namespace={origin:PROFILE.supabase_origin,bucket:'collect-evidence'};
      return {canonical:{env:inputs.env,validateProviderProfile:unused,applicationWorkTuple},
        commands:{enqueueEligibleRematch:unused},
        gateway:()=>({withAuthorityTransaction:unused,withReadSnapshot:unused}),
        sourceReader:{revision:unused,page:unused,detail:unused},
        posting:{custody:{namespace,decrypt:unused},preparation:{media:{namespace,put:unused},encrypt:unused,keyId:'fixture-key'}}};
    }};
  const request=(path='/session',overrides={})=>new Request(PROFILE.supabase_origin+'/v1/burimunsi'+path,{headers:{
    'X-BuriMunsi-Collect-Session':token(),'X-BuriMunsi-Contract':CONTRACT_VERSION,
    'X-BuriMunsi-Installation':I.installation,'X-BuriMunsi-Request':I.request,'X-BuriMunsi-Generation':'1',
    Authorization:'Bearer '+NATIVE_TOKEN,...overrides}});
  const mount=()=>{env.BURIMUNSI_NATIVE_ROUTE=createCollectNativeRoute(options);};
  return {...f,h,work,env,state,nativeState:f.state,options,claims,request,mount,close:async()=>{
    globalThis.fetch=originalFetch;await work.finish();f.close();}};
}

test('unconfigured namespace returns a versioned 503 before DB/provider/member auth',async()=>{
  let touched=0;const env={get DB(){touched++;throw Error('unexpected DB access');}};
  for(const path of ['/v1/burimunsi/session/login','/v1/burimunsi/home','/v1/burimunsi/operations/'+I.request]){
    const response=await collectNativeRoute(new Request(PROFILE.supabase_origin+path),env);
    assert.equal(response.status,503);assert.equal(response.headers.get('X-BuriMunsi-Contract'),CONTRACT_VERSION);
    assert.deepEqual(await response.json(),{contractVersion:CONTRACT_VERSION,ok:false,error:{code:'native_service_unconfigured'}});
  }
  assert.equal(touched,0);
});
test('existing Collect dispatcher mounts native namespace before ordinary member authentication',async()=>{
  let touched=0;const env={get DB(){touched++;throw Error('unexpected ordinary member/database dispatch');}};
  const response=await collectWorker.fetch(new Request(PROFILE.supabase_origin+'/v1/burimunsi/home'),env,{});
  assert.equal(response.status,503);assert.equal((await response.json()).error.code,'native_service_unconfigured');
  assert.equal(touched,0);
});
test('namespace hook leaves existing routes and the held ingest route untouched',async()=>{
  for(const path of ['/health','/api/admin/session','/v1/gateway/sms','/v1/burimunsix/home'])
    assert.equal(await collectNativeRoute(new Request(PROFILE.supabase_origin+path),{}),null);
});
test('an arbitrary env function cannot install a native composition',async()=>{
  const response=await collectNativeRoute(new Request(PROFILE.supabase_origin+'/v1/burimunsi/home'),
    {BURIMUNSI_NATIVE_ROUTE:()=>{throw Error('untrusted function executed');}});
  assert.equal(response.status,503);assert.equal((await response.json()).error.code,'native_service_unconfigured');
});
test('configured route invokes real managed auth and native SQL on the same admitted DB/fence',async()=>{
  const f=await fixture();try{
    f.mount();const response=await collectNativeRoute(f.request(),f.env);const value=await response.json();
    assert.equal(response.status,200,JSON.stringify(value));assert.equal(value.contractVersion,CONTRACT_VERSION);
    assert.equal(value.binding.groupId,I.group);assert.equal(value.binding.actorId,I.account);
    assert.equal(value.binding.installationId,I.installation);assert.equal(value.data.profile.id,I.account);
    assert.equal(f.state.providerCalls,1);assert.equal(f.state.bridgeCalls,1);assert.ok(f.state.asserts>0);
    assert.ok(f.nativeState.transactions>0);assert.ok(f.nativeState.queries.some(q=>q.text.includes('private.burimunsi_sessions')));
    assert.ok(f.state.projectionQueries.some(q=>q.sql.includes('private.auth_principal_links')));
    assert.equal(f.state.writes,0);assert.deepEqual(f.state.claims,{});
  }finally{await f.close();}
});
test('server-selected collection and profile cannot change through caller-owned config objects',async()=>{
  const f=await fixture();try{
    f.mount();f.options.config.groupId='other-group';f.options.config.origin='https://other.example.test';
    const response=await collectNativeRoute(f.request(),f.env);const value=await response.json();
    assert.equal(response.status,200);assert.equal(value.binding.groupId,I.group);
    assert.equal(f.state.bridgeInputs.groupId,I.group);assert.equal(f.state.writes,0);
  }finally{await f.close();}
});
test('missing managed token denies before bridge assembly or database projection',async()=>{
  const f=await fixture();try{
    f.mount();const request=f.request();request.headers.delete('X-BuriMunsi-Collect-Session');
    const response=await collectNativeRoute(request,f.env);
    assert.equal(response.status,401);assert.equal((await response.json()).error.code,'managed_session_required');
    assert.equal(f.state.providerCalls,0);assert.equal(f.state.bridgeCalls,0);assert.equal(f.state.projectionQueries.length,0);
  }finally{await f.close();}
});
test('expired provider claims deny through the actual shared verifier',async()=>{
  const f=await fixture();try{
    f.mount();f.claims.exp=0;const response=await collectNativeRoute(f.request(),f.env);
    assert.equal(response.status,401);assert.equal(f.state.providerCalls,1);assert.equal(f.state.bridgeCalls,0);
    assert.equal(f.state.projectionQueries.length,0);assert.deepEqual(f.state.claims,{});
  }finally{await f.close();}
});
test('a Supabase token cannot manufacture missing existing Admin admission',async()=>{
  const f=await fixture();try{
    f.mount();f.sqlite.exec('DELETE FROM admin_sessions');const response=await collectNativeRoute(f.request(),f.env);
    assert.equal(response.status,401);assert.equal(f.state.bridgeCalls,0);assert.equal(f.state.writes,0);
    assert.deepEqual(f.state.claims,{});
  }finally{await f.close();}
});
test('client group selectors fail closed rather than selecting another collection',async()=>{
  const f=await fixture();try{
    f.mount();const response=await collectNativeRoute(f.request('/session?groupId=other-group'),f.env);
    assert.equal(response.status,400);assert.equal((await response.json()).error.code,'contract_query');
    assert.equal(f.state.bridgeInputs.groupId,I.group);assert.equal(f.state.writes,0);
    assert.ok(f.nativeState.queries.every(q=>!q.values.includes('other-group')));
  }finally{await f.close();}
});
test('a configured different collection cannot authenticate this native account',async()=>{
  const f=await fixture();try{
    f.options.config=settings('different-group');f.mount();
    const response=await collectNativeRoute(f.request(),f.env);
    assert.equal(response.status,401);assert.equal(f.state.bridgeInputs.groupId,'different-group');
    assert.equal(f.state.writes,0);assert.deepEqual(f.state.claims,{});
  }finally{await f.close();}
});
test('wrong current deployment profile is denied before provider or DB work',async()=>{
  const f=await fixture();try{
    f.mount();const changed=canonicalProfile({...PROFILE,id:'different-deployment'});
    f.env.COLLECT_DEPLOYMENT_PROFILE=changed;f.env.COLLECT_DEPLOYMENT_PROFILE_SHA256=await sha256(changed);
    const response=await collectNativeRoute(f.request(),f.env);
    assert.equal(response.status,503);assert.equal((await response.json()).error.code,'native_profile_mismatch');
    assert.equal(f.state.providerCalls,0);assert.equal(f.state.bridgeCalls,0);assert.equal(f.state.projectionQueries.length,0);
  }finally{await f.close();}
});
test('unbranded/replaced fence cannot borrow the admitted DB or native composition',async()=>{
  const f=await fixture();try{
    f.mount();f.db.applicationWork={assert:async()=>{}};
    const response=await collectNativeRoute(f.request(),f.env);
    assert.equal(response.status,503);assert.equal(f.state.providerCalls,0);assert.equal(f.state.bridgeCalls,0);
  }finally{f.db.applicationWork=f.work;await f.close();}
});
test('replacement during asynchronous bridge assembly prevents native account/financial work',async()=>{
  const f=await fixture();try{
    const original=f.options.bridgeFactory;
    f.options.bridgeFactory=async inputs=>{const bridges=await original(inputs);f.db.applicationWork={assert:async()=>{}};return bridges;};
    f.mount();const response=await collectNativeRoute(f.request(),f.env);
    assert.equal(response.status,503);assert.equal((await response.json()).error.code,'request_not_admitted');
    assert.equal(f.nativeState.transactions,0);assert.equal(f.state.writes,0);assert.deepEqual(f.state.claims,{});
  }finally{f.db.applicationWork=f.work;await f.close();}
});
test('canonical integration must be explicitly selected by trusted server configuration',async()=>{
  const f=await fixture();try{
    f.options.config.canonicalIntegrationEnabled=false;
    assert.throws(()=>f.mount(),/native_service_unconfigured/);
    assert.equal(f.state.providerCalls,0);assert.equal(f.state.writes,0);
  }finally{await f.close();}
});
test('missing real bridge ports remain closed after managed authentication',async()=>{
  const f=await fixture();try{
    f.options.bridgeFactory=async()=>({});f.mount();const response=await collectNativeRoute(f.request(),f.env);
    assert.equal(response.status,503);assert.equal((await response.json()).error.code,'collect_adapter_required');
    assert.equal(f.state.writes,0);assert.deepEqual(f.state.claims,{});
    assert.equal(f.nativeState.queries.filter(q=>/^(INSERT|UPDATE|DELETE)/.test(q.text)).length,0);
  }finally{await f.close();}
});
