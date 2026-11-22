/** Actual composite Admin route, encrypted BFF custody, managed projection and
 * native SQL read over a reduced SQLite schema. GoTrue responses, PG managed
 * session function, locks/RLS and email status are explicit test substitutes.
 * No live account, production credential, PG migration or provider is exercised.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {principalFixture,I} from './native-principal-fixture.mjs';
import {openApplicationWork} from '../../application-fence.js';
import {syntheticFenceBackend} from '../helpers/fenced-unit.js';
import {canonicalProfile} from '../../deployment-profile.js';
import {digest} from '../../domain/core.js';
import {encrypt} from '../../domain/encryption.js';
import {handleAdmin} from '../../domain/admin_bridge.js';
import {createAdminWorker} from '../../../../../deploy/platform-admin/src/index.js';
await import('../helpers/node-postgres-import.mjs');
const {logicalRequest}=await import('../../serve.js');

const ORIGIN='https://admin.native-access.example.invalid',PROJECT='https://rrlduytparvsjfmegalh.supabase.co';
const AUTH='20000000-0000-4000-8000-000000000001',SID='20000000-0000-4000-8000-000000000002';
const ADMIN='20000000-0000-4000-8000-000000000003',PUBLIC='20000000-0000-4000-8000-000000000004';
const PRINCIPAL='20000000-0000-4000-8000-000000000005';
const COOKIE='b'.repeat(64),DEVICE='c'.repeat(64),SOURCE='a'.repeat(64),KEY=Buffer.alloc(32,11).toString('base64');
const PROFILE={format:'collect.deployment.v1',id:'native-access-fixture',mode:'managed',environment:'qualification',
 supabase_origin:PROJECT,admin_origin:ORIGIN,member_api_origin:'https://api.native-access.example.invalid',
 public_origin:'https://collect.native-access.example.invalid',google_callback_origin:ORIGIN};

async function fixture(run){
 const f=principalFixture(),at=Math.floor(Date.now()/1000),hash=await digest(COOKIE),csrf=await digest('collect-admin-csrf:'+COOKIE);
 const state={managed:true,approved:true,provider:true,authCalls:0,queries:[],nativeReads:0,emailVerifiedAt:null,ownerCommand:null};
 const claims={sub:AUTH,session_id:SID,role:'authenticated',aud:'authenticated',aal:'aal1',exp:at+3600,iat:at-10,
  iss:PROJECT+'/auth/v1',amr:[{method:'password',timestamp:at-10}]};
 const token=Buffer.from('{}').toString('base64url')+'.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.synthetic-signature';
 const cipher=await encrypt({DATA_KEY_ID:'fixture-bff',DATA_ENCRYPTION_KEY:KEY},
  new TextEncoder().encode(JSON.stringify({access_token:token,refresh_token:'fixture-only-never-released'})),`bff:${SID}:${AUTH}`);
 f.sqlite.exec(`ALTER TABLE private.burimunsi_scopes ADD COLUMN version INTEGER DEFAULT 1;
  ALTER TABLE private.burimunsi_device_grants ADD COLUMN custodian_account_id TEXT;
  CREATE TABLE app.collections(id TEXT PRIMARY KEY,status TEXT);
  CREATE TABLE private.auth_principal_links(auth_user_id TEXT PRIMARY KEY,user_id TEXT);
  CREATE TABLE private.bff_sessions(token_hash TEXT PRIMARY KEY,auth_user_id TEXT,auth_session_id TEXT,token_ciphertext TEXT,version INTEGER,refresh_lease TEXT,refresh_lease_until INTEGER);
  CREATE TABLE app.admin_users(id TEXT PRIMARY KEY,email TEXT,role TEXT,status TEXT,auth_version INTEGER);
  CREATE TABLE app.admin_principal_links(admin_user_id TEXT,user_id TEXT);
  CREATE TABLE app.admin_sessions(token_hash TEXT,public_id TEXT,user_id TEXT,auth_version INTEGER,auth_session_id TEXT,origin TEXT,created_at INTEGER,expires_at INTEGER,issued_assurance_level INTEGER,issued_mfa_at INTEGER,issued_mfa_factor_id TEXT);
  CREATE TABLE app.auth_sessions(id TEXT PRIMARY KEY,user_id TEXT,surface TEXT,auth_at INTEGER,created_at INTEGER,expires_at INTEGER,revoked_at INTEGER,assurance_level INTEGER,mfa_at INTEGER,mfa_factor_id TEXT);
  CREATE TABLE app.auth_mfa_factors(id TEXT,user_id TEXT,status TEXT);
  CREATE TABLE app.admin_grants(user_id TEXT,permission TEXT);
  CREATE TABLE app.admin_account_role_capabilities(role TEXT,permission TEXT);`);
 f.sqlite.prepare('UPDATE app.users SET id=?').run(PRINCIPAL);
 f.sqlite.prepare('UPDATE private.burimunsi_accounts SET principal_user_id=?').run(PRINCIPAL);
 f.sqlite.prepare('INSERT INTO app.collections VALUES(?,?)').run(I.group,'active');
 f.sqlite.prepare('INSERT INTO private.auth_principal_links VALUES(?,?)').run(AUTH,PRINCIPAL);
 f.sqlite.prepare('INSERT INTO private.bff_sessions VALUES(?,?,?,?,1,NULL,NULL)').run(hash,AUTH,SID,cipher);
 f.sqlite.prepare('INSERT INTO app.admin_users VALUES(?,?,?,?,?)').run(ADMIN,'operator@example.invalid','staff','active',1);
 f.sqlite.prepare('INSERT INTO app.admin_principal_links VALUES(?,?)').run(ADMIN,PRINCIPAL);
 f.sqlite.prepare('INSERT INTO app.admin_sessions VALUES(?,?,?,?,?,?,?,?,?,NULL,NULL)').run(hash,PUBLIC,ADMIN,1,SID,ORIGIN,at-10,at+3000,1);
 f.sqlite.prepare('INSERT INTO app.auth_sessions VALUES(?,?,?,?,?,?,NULL,1,NULL,NULL)').run(SID,PRINCIPAL,'admin',at-10,at-10,at+3500);
 f.sqlite.prepare('INSERT INTO app.admin_grants VALUES(?,?)').run(PRINCIPAL,'collections.view');
 f.sqlite.prepare('INSERT INTO app.admin_account_role_capabilities VALUES(?,?)').run('staff','collections.view');
 f.sqlite.prepare('UPDATE private.burimunsi_device_grants SET token_hash=?').run(await digest(DEVICE));
 f.sqlite.function('fixture_managed_session',(auth,sid)=>Number(state.managed&&auth===AUTH&&sid===SID));
 f.sqlite.function('fixture_operator_approved',(_group,_principal,_phone,_role,_capabilities)=>Number(state.approved));
 const work=await openApplicationWork({backend:syntheticFenceBackend(),sourceSha256:SOURCE,kind:'http_admin'});
 f.db.applicationWork=work;f.db.setClaims=()=>{};
 const nativeUnsafe=f.sql.unsafe.bind(f.sql);
 f.sql.unsafe=async(q,args)=>{
  state.queries.push(q);if(q.startsWith('SELECT a.id AS operator_id'))state.nativeReads++;
  if(q.startsWith('SELECT private.burimunsi_operator_')||q.startsWith('SELECT private.burimunsi_native_grant_')){
   if(!state.ownerCommand)throw Error('No owner command substitute configured');
   return [{result:await state.ownerCommand(q,args),guarded_approval:state.approvalGuard===true}];
  }
  return nativeUnsafe(q.replaceAll('private.is_managed_session(','fixture_managed_session(')
   .replaceAll('private.burimunsi_operator_is_current(','fixture_operator_approved('),args);
 };
 f.db.prepare=q=>({bind(...args){return {async first(){
  state.queries.push(q);
  if(q.startsWith('SELECT private.is_managed_session('))return {allowed:state.managed};
  if(q.startsWith('SELECT private.admin_email_status('))return {result:{contract_version:1,public_session_id:PUBLIC,
   email_verified_at:state.emailVerifiedAt,proof_id:state.emailVerifiedAt===null?null:PUBLIC}};
  return f.sqlite.prepare(q.replaceAll('::uuid','')).get(...args)??null;
 },async all(){state.queries.push(q);return {results:f.sqlite.prepare(q).all(...args)};},async run(){throw Error('Fixture does not allow projection or other writes');}};}});
 f.db.batch=async statements=>{
  assert.equal(statements.length,1);const statement=statements[0];
  // The reduced SQLite fixture substitutes this owner-only PG resolver; the
  // actual function/RLS/fence is separately qualified by scope-setup-contract.
  assert.equal(statement.sql,'SELECT private.burimunsi_resolve_installation_scope(?::uuid,?::text) AS scope');
  const rows=f.sqlite.prepare(`SELECT DISTINCT d.collection_id FROM private.burimunsi_device_grants d
   JOIN private.burimunsi_scopes s ON s.collection_id=d.collection_id AND s.enabled
   JOIN app.collections c ON c.id=s.collection_id AND c.status='active'
   JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.collection_id=d.collection_id
   JOIN private.burimunsi_accounts a ON a.id=da.account_id AND a.collection_id=d.collection_id
   WHERE d.installation_id=? AND d.token_hash=? AND d.active AND a.active AND NOT a.removed AND a.principal_user_id=?
    AND (d.profile='staff' OR(d.profile='internal_receiver' AND a.role='admin' AND d.custodian_account_id=a.id))`).all(...statement.values,PRINCIPAL);
  if(!state.approved||rows.length!==1)throw Error('managed_scope_required');
  return [{success:true,results:[{scope:{collectionId:rows[0].collection_id}}]}];
 };
 const prepared=f.db.prepare;f.db.prepare=q=>{const wrapped=prepared(q);return {bind(...values){
  if(q.startsWith('SELECT private.burimunsi_resolve_installation_scope('))return {sql:q,values};
  return wrapped.bind(...values);
 }};};
 const raw=canonicalProfile(PROFILE),env={DB:f.db,COLLECT_FENCE_WORK:work,BUILD_SOURCE_ID:SOURCE,
  COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:await digest(raw),SUPABASE_URL:PROJECT,
  SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fixture',ADMIN_ORIGIN:ORIGIN,BURIMUNSI_COLLECTION_ID:I.group,
  SESSION_KEY_ID:'fixture-bff',SESSION_ENCRYPTION_KEY:KEY};
 const fetch=globalThis.fetch;
 globalThis.fetch=async(input,options)=>{
  state.authCalls++;assert.equal(String(input),PROJECT+'/auth/v1/user');assert.equal(options.method,'GET');
  assert.equal(options.headers.Authorization,'Bearer '+token);
  return state.provider?Response.json({id:AUTH,email:f.sqlite.prepare('SELECT email FROM app.admin_users WHERE id=?').get(ADMIN).email,email_confirmed_at:'2026-01-01T00:00:00Z'}):Response.json({error_code:'invalid_session'},{status:401});
 };
 const request=({method='POST',headers={},body={installationId:I.installation},path='/api/admin/burimunsi/access'}={})=>new Request(ORIGIN+path,{method,
  headers:{Origin:ORIGIN,Cookie:'__Host-collect_admin='+COOKIE,'X-Collect-Requested-With':'collect-admin','Content-Type':'application/json',
   'X-Collect-CSRF':csrf,'X-BuriMunsi-Device':DEVICE,...headers},...(['GET','HEAD'].includes(method)?{}:{body:JSON.stringify(body)})});
 const call=async options=>{const response=await handleAdmin(request(options),env,{});return {response,body:response?await response.json():null};};
 try{await run({f,env,state,claims,token,call,request,at,hash});}
 finally{globalThis.fetch=fetch;await work.finish();f.close();}
}

test('native access uses genuine encrypted BFF credentials and an exact current device binding',()=>fixture(async({call,token,state,at})=>{
 const {response,body}=await call();assert.equal(response.status,200,JSON.stringify(body));
 assert.deepEqual(body,{contractVersion:'burimunsi.collect-session.v1',accessToken:token,expiresAt:(at+3000)*1000,
  authUserId:AUTH,principalUserId:PRINCIPAL,principalSessionId:SID,operatorId:I.account,collectionId:I.group,
  installationId:I.installation,profile:'staff',accountVersion:1,credentialVersion:1,grantVersion:1,scopeVersion:1});
 assert.equal(response.headers.get('Cache-Control'),'no-store, private');assert.equal(response.headers.get('Pragma'),'no-cache');
 assert.equal(JSON.stringify(body).includes('refresh'),false);assert.equal(JSON.stringify(body).includes(DEVICE),false);
 assert.equal(state.nativeReads,1);assert.equal(state.authCalls,2);
}));

for(const [name,change] of [
 ['revoked device',f=>f.execute('UPDATE private.burimunsi_device_grants SET active=0')],
 ['different device secret',f=>f.execute('UPDATE private.burimunsi_device_grants SET token_hash=?','a'.repeat(64))],
 ['different installation',f=>f.execute('UPDATE private.burimunsi_device_grants SET installation_id=?',PUBLIC)],
 ['removed operator',f=>f.execute('UPDATE private.burimunsi_accounts SET removed=1,active=0')],
 ['disabled scope',f=>f.execute('UPDATE private.burimunsi_scopes SET enabled=0')],
 ['suspended collection',f=>f.execute("UPDATE app.collections SET status='suspended'")],
 ['operator belongs to another principal',f=>f.execute('UPDATE private.burimunsi_accounts SET principal_user_id=?','somebody-else')],
 ['account no longer linked to device',f=>f.execute('DELETE FROM private.burimunsi_device_accounts')],
 ['staff cannot elevate native role',f=>f.execute("UPDATE private.burimunsi_accounts SET role='admin'")],
 ['staff cannot use receiver profile',f=>f.execute("UPDATE private.burimunsi_device_grants SET profile='internal_receiver'")]
])test('native access denies '+name,()=>fixture(async({f,call})=>{change(f);const {response,body}=await call();assert.equal(response.status,403,JSON.stringify(body));assert.equal(body.error.code,'burimunsi_access_denied');assert.equal(body.accessToken,undefined);}));

for(const [name,options,status] of [
 ['wrong origin',{headers:{Origin:'https://elsewhere.example.invalid'}},403],
 ['cross-site request',{headers:{'Sec-Fetch-Site':'cross-site'}},403],
 ['missing CSRF',{headers:{'X-Collect-CSRF':''}},403],
 ['missing device proof',{headers:{'X-BuriMunsi-Device':''}},403],
 ['PIN cannot replace device proof',{headers:{'X-BuriMunsi-Device':'1234'}},403],
 ['unexpected body field',{body:{installationId:I.installation,principalUserId:PRINCIPAL}},400],
 ['noncanonical installation',{body:{installationId:' '+I.installation}},400],
 ['wrong method',{method:'GET'},405]
])test('native access preserves '+name,()=>fixture(async({call})=>{const {response,body}=await call(options);assert.equal(response.status,status,JSON.stringify(body));assert.equal(body.accessToken,undefined);}));

test('provider revocation cannot be hidden by a valid PIN/device',()=>fixture(async({state,call})=>{state.provider=false;const {response}=await call();assert.equal(response.status,401);assert.equal(state.nativeReads,0);}));
test('revoked owner approval cannot release a shared token to the native device',()=>fixture(async({state,call})=>{
 state.approved=false;const {response,body}=await call();assert.equal(response.status,403);assert.equal(body.accessToken,undefined);
}));
test('changed deployment source is not an admitted token exchange',()=>fixture(async({env,call})=>{env.BUILD_SOURCE_ID='c'.repeat(64);const {response}=await call();assert.equal(response.status,503);}));
test('managed session denial cannot create a new projection',()=>fixture(async({state,call})=>{state.managed=false;const {response}=await call();assert.equal(response.status,401);assert.equal(state.nativeReads,0);}));
test('existing unrelated Admin routes keep their dispatcher',()=>fixture(async({call})=>{const {response}=await call({path:'/api/other'});assert.equal(response,null);}));

test('native BFF access survives the real Admin proxy and shared function URL projection',()=>fixture(async({env,request,token})=>{
 let dispatches=0;
 const proxy=createAdminWorker({fetchImpl:async upstream=>{
  dispatches++;assert.equal(upstream.url,PROJECT+'/functions/v1/admin-api/api/admin/burimunsi/access');
  assert.equal(upstream.headers.get('X-BuriMunsi-Device'),DEVICE);
  const logical=logicalRequest(upstream,'admin-api',env);
  assert.equal(new URL(logical.url).origin,PROJECT);
  return handleAdmin(logical,env,{});
 }});
 const response=await proxy.fetch(request(),{...env,COLLECT_BACKEND:'supabase',ASSETS:{fetch(){throw Error('No static fallback');}}});
 assert.equal(response.status,200,await response.clone().text());assert.equal((await response.json()).accessToken,token);
 assert.equal(dispatches,1);assert.equal(response.headers.get('Pragma'),'no-cache');
}));

test('native admin on its assigned receiving installation can use the managed bridge',()=>fixture(async({f,call})=>{
 f.execute("UPDATE app.admin_users SET role='admin'");
 f.execute("UPDATE private.burimunsi_accounts SET role='admin'");
 f.execute("UPDATE private.burimunsi_device_grants SET profile='internal_receiver',custodian_account_id=?",I.account);
 const {response,body}=await call();assert.equal(response.status,200,JSON.stringify(body));assert.equal(body.profile,'internal_receiver');
}));

const OPERATORS='/api/admin/burimunsi/operators';
const OWNER_REQUEST='30000000-0000-4000-8000-000000000001';
const approval=()=>({requestId:OWNER_REQUEST,collectionId:I.group,adminId:ADMIN,principalId:PRINCIPAL,phone:'0780 000 002',role:'staff',
 capabilities:['records.read','members.enroll'],active:true,expectedVersion:0});
function ownerFixture(f,state,at){
 // Explicit owner/email SQL substitutes for route tests; real SQL owner proof
 // and retained outcome/revocation checks belong to native PG qualification.
 f.execute("UPDATE app.admin_users SET role='owner',email='info@ikanisa.com'");state.emailVerifiedAt=at;
 f.execute('INSERT INTO app.admin_grants VALUES(?,?)',PRINCIPAL,'admin_users.manage');
 f.execute('INSERT INTO app.admin_account_role_capabilities VALUES(?,?)','owner','admin_users.manage');
}
test('owner directory negotiates approval only with the guarded runtime command',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);state.ownerCommand=async(q,args)=>{
  assert(q.startsWith('SELECT private.burimunsi_operator_directory('));
  assert.deepEqual(args,[ADMIN,await digest(COOKIE),ORIGIN,PUBLIC,I.group,null]);
  if(q.includes('AS guarded_approval')){
   assert.match(q,/has_function_privilege\([\s\S]+burimunsi_operator_approve_v2\(/);
   assert.match(q,/AND NOT COALESCE[\s\S]+burimunsi_operator_approve\(/);
  }
  return {contractVersion:1,collectionId:I.group,configured:true,team:[],approvals:[]};
 };
 const path=OPERATORS+'?collectionId='+I.group;
 let r=await call({path:path+'&approvalContract=2',method:'GET'});
 assert.equal(r.response.status,200,JSON.stringify(r.body));assert.equal(Object.hasOwn(r.body,'approvalContract'),false);
 state.approvalGuard=true;
 r=await call({path,method:'GET'});
 assert.equal(r.response.status,200,JSON.stringify(r.body));assert.equal(Object.hasOwn(r.body,'approvalContract'),false);
 r=await call({path:path+'&approvalContract=2',method:'GET'});
 assert.equal(r.response.status,200,JSON.stringify(r.body));assert.equal(r.body.approvalContract,2);
}));
test('directory negotiation rejects malformed and misplaced contract requests before SQL',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);let calls=0;state.ownerCommand=()=>{calls++;};
 for(const path of [OPERATORS+'?approvalContract=1',OPERATORS+'?approvalContract=2&approvalContract=2',
  OPERATORS+'/requests/'+OWNER_REQUEST+'?approvalContract=2']){
  const {response,body}=await call({path,method:'GET'});
  assert.equal(response.status,400);assert.equal(body.error.code,'invalid_request');
 }
 const {response}=await call({path:OPERATORS,body:approval(),headers:{'Idempotency-Key':'30000000-0000-4000-8000-000000000002'}});
 assert.equal(response.status,400);assert.equal(calls,0);
}));
test('ordinary shared staff cannot approve BuriMunsi identities',()=>fixture(async({state,call})=>{
 state.ownerCommand=()=>{throw Error('Must not reach owner SQL');};
 const {response,body}=await call({path:OPERATORS,body:approval()});
 assert.equal(response.status,403);assert.equal(body.error.code,'owner_required');
}));
test('owner approval retains the existing fresh-email requirement',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);state.emailVerifiedAt=null;
 const {response,body}=await call({path:OPERATORS,body:approval()});
 assert.equal(response.status,403);assert.equal(body.error.code,'recent_email_sign_in_required');
}));
test('owner approval binds server scope/cookie and normalizes the explicit login phone',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);let calls=0;
 state.ownerCommand=async(q,args)=>{
  calls++;assert(q.includes('burimunsi_operator_approve_v2('));
  assert.deepEqual(args,[ADMIN,await digest(COOKIE),ORIGIN,PUBLIC,I.group,OWNER_REQUEST,ADMIN,
   '+250780000002','staff',['members.enroll','records.read'],true,0,PRINCIPAL]);
  return {contractVersion:1,requestId:OWNER_REQUEST,principalId:PRINCIPAL,version:1,active:true,applied:true};
 };
 const {response,body}=await call({path:OPERATORS,body:approval(),headers:{'Idempotency-Key':OWNER_REQUEST}});assert.equal(response.status,200,JSON.stringify(body));
 assert.equal(body.requestId,OWNER_REQUEST);assert.equal(calls,1);assert.equal(body.accessToken,undefined);
}));
test('a changed principal is reported as a conflict and is not retried',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);let calls=0;state.ownerCommand=()=>{calls++;throw Error('burimunsi_approval_changed');};
 const {response,body}=await call({path:OPERATORS,body:approval()});
 assert.equal(response.status,409);assert.equal(body.error.code,'burimunsi_approval_changed');assert.equal(calls,1);
}));
test('a mismatched approval receipt is never reported as success',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);state.ownerCommand=()=>({contractVersion:1,requestId:OWNER_REQUEST,
  principalId:'20000000-0000-4000-8000-000000000006',version:1,active:true,applied:true});
 const {response,body}=await call({path:OPERATORS,body:approval()});
 assert.equal(response.status,503);assert.equal(body.outcome,'operation_unknown');assert.equal(body.requestId,OWNER_REQUEST);
}));
for(const [name,mutate] of [
 ['missing principal',b=>{delete b.principalId;}],['malformed principal',b=>{b.principalId='not-a-principal';}],
 ['staff escalation',b=>{b.capabilities.push('staff.manage');}],['fractional revision',b=>{b.expectedVersion=0.5;}],
 ['duplicate capability',b=>{b.capabilities.push('records.read');}],['credential body',b=>{b.pin='1234';}]
])test('owner approval rejects '+name+' before command SQL',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);let calls=0;state.ownerCommand=()=>{calls++;};const body=approval();mutate(body);
 const {response}=await call({path:OPERATORS,body});assert.equal(response.status,400);assert.equal(calls,0);
}));
test('a retained owner request cannot be retargeted by a configured group change',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);let calls=0;state.ownerCommand=()=>{calls++;};
 const {response,body}=await call({path:OPERATORS,body:{...approval(),collectionId:'other'}});
 assert.equal(response.status,409);assert.equal(body.error.code,'burimunsi_scope_changed');assert.equal(calls,0);
}));
test('unknown approval commit returns the original request without retry or secret text',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);let calls=0;state.ownerCommand=()=>{calls++;throw Error('sensitive-test-credential');};
 const {response,body}=await call({path:OPERATORS,body:approval()});assert.equal(response.status,503);
 assert.equal(body.outcome,'operation_unknown');assert.equal(body.requestId,OWNER_REQUEST);assert.equal(calls,1);
 assert(!JSON.stringify(body).includes('sensitive-test-credential'));
}));
test('owner can read the retained original approval outcome',()=>fixture(async({f,state,at,call})=>{
 ownerFixture(f,state,at);state.ownerCommand=(q,args)=>{
  assert(q.includes('burimunsi_operator_directory('));assert.equal(args.at(-1),OWNER_REQUEST);
  return {contractVersion:1,found:true,receipt:{contractVersion:1,requestId:OWNER_REQUEST,principalId:PRINCIPAL,version:1,active:true,applied:true}};
 };
 const {response,body}=await call({path:OPERATORS+'/requests/'+OWNER_REQUEST,method:'GET'});
 assert.equal(response.status,200);assert.equal(body.receipt.requestId,OWNER_REQUEST);
}));

const NATIVE_WORK='/api/admin/burimunsi/native-work-grants';
const WORK_ID='30000000-0000-4000-8000-000000000002';
const workIssue=()=>({operation:'issue',collectionId:I.group,requestId:OWNER_REQUEST,grantId:WORK_ID,
 owner:'synthetic-worker',version:1,policyVersion:'policy-v1',expiresAt:1900000000000});
function workOwner(f,state,at,financial=true){
 ownerFixture(f,state,at);
 for(const permission of ['receivers.manage',...(financial?['payments.reconcile']:[])]){
  f.execute('INSERT INTO app.admin_grants VALUES(?,?)',PRINCIPAL,permission);
  f.execute('INSERT INTO app.admin_account_role_capabilities VALUES(?,?)','owner',permission);
 }
}
test('native worker route refuses non-owner and requires owner financial permission for issue',()=>fixture(async({f,state,at,call})=>{
 state.ownerCommand=()=>{throw Error('must not reach SQL');};
 let r=await call({path:NATIVE_WORK,body:workIssue(),headers:{'Idempotency-Key':OWNER_REQUEST}});assert.equal(r.response.status,403);
 workOwner(f,state,at,false);r=await call({path:NATIVE_WORK,body:workIssue(),headers:{'Idempotency-Key':OWNER_REQUEST}});
 assert.equal(r.response.status,403);assert.equal(r.body.error.code,'financial_permission_required');
}));
test('native worker issue uses existing owner BFF and defaults to disabled',()=>fixture(async({f,state,at,call})=>{
 workOwner(f,state,at);let calls=0;state.ownerCommand=async(q,args)=>{
  calls++;assert(q.includes('burimunsi_native_grant_issue('));
  assert.deepEqual(args,[ADMIN,await digest(COOKIE),ORIGIN,PUBLIC,I.group,OWNER_REQUEST,WORK_ID,'synthetic-worker',1,'policy-v1',1900000000000,false]);
  return {grantId:WORK_ID,groupId:I.group,owner:'synthetic-worker',version:1,enabled:false,expiresAt:1900000000000};};
 const r=await call({path:NATIVE_WORK,body:workIssue(),headers:{'Idempotency-Key':OWNER_REQUEST}});
 assert.equal(r.response.status,200,JSON.stringify(r.body));assert.equal(r.body.enabled,false);assert.equal(calls,1);
}));
test('native worker route refuses stale email, absent CSRF, scope change and absent idempotency key',()=>fixture(async({f,state,at,call})=>{
 workOwner(f,state,at);let calls=0;state.ownerCommand=()=>{calls++;};state.emailVerifiedAt=null;
 let r=await call({path:NATIVE_WORK,body:workIssue(),headers:{'Idempotency-Key':OWNER_REQUEST}});assert.equal(r.response.status,403);
 state.emailVerifiedAt=at;r=await call({path:NATIVE_WORK,body:workIssue(),headers:{'X-Collect-CSRF':'','Idempotency-Key':OWNER_REQUEST}});assert.equal(r.response.status,403);
 r=await call({path:NATIVE_WORK,body:{...workIssue(),collectionId:'other'},headers:{'Idempotency-Key':OWNER_REQUEST}});assert.equal(r.response.status,409);
 r=await call({path:NATIVE_WORK,body:workIssue()});assert.equal(r.response.status,400);assert.equal(calls,0);
}));
test('native worker route rejects cross-origin and malformed grant data before SQL',()=>fixture(async({f,state,at,call})=>{
 workOwner(f,state,at);let calls=0;state.ownerCommand=()=>{calls++;};
 let r=await call({path:NATIVE_WORK,body:workIssue(),headers:{Origin:'https://elsewhere.example.invalid','Idempotency-Key':OWNER_REQUEST}});
 assert.equal(r.response.status,403);
 r=await call({path:NATIVE_WORK,body:{...workIssue(),owner:42},headers:{'Idempotency-Key':OWNER_REQUEST}});
 assert.equal(r.response.status,400);assert.equal(calls,0);
}));
test('owner can revoke a worker after losing financial permission',()=>fixture(async({f,state,at,call})=>{
 workOwner(f,state,at,false);state.ownerCommand=(q,args)=>{assert(q.includes('burimunsi_native_grant_revoke('));assert.equal(args.at(-1),WORK_ID);
  return {grantId:WORK_ID,groupId:I.group,revoked:true,applied:true};};
 const r=await call({path:NATIVE_WORK,body:{operation:'revoke',collectionId:I.group,requestId:OWNER_REQUEST,grantId:WORK_ID},headers:{'Idempotency-Key':OWNER_REQUEST}});
 assert.equal(r.response.status,200,JSON.stringify(r.body));assert.equal(r.body.revoked,true);
}));
test('native worker route reports an idempotency payload conflict without retry',()=>fixture(async({f,state,at,call})=>{
 workOwner(f,state,at);let calls=0;state.ownerCommand=()=>{calls++;const e=new Error('private detail');e.code='23505';throw e;};
 const r=await call({path:NATIVE_WORK,body:workIssue(),headers:{'Idempotency-Key':OWNER_REQUEST}});
 assert.equal(r.response.status,409);assert.equal(r.body.error.code,'native_work_request_conflict');assert.equal(calls,1);
 assert(!JSON.stringify(r.body).includes('private detail'));
}));
test('unknown native worker commit is not retried and original request can be recovered',()=>fixture(async({f,state,at,call})=>{
 workOwner(f,state,at);let calls=0;state.ownerCommand=q=>{calls++;if(q.includes('grant_issue'))throw Error('private synthetic error');
  assert(q.includes('grant_command'));return {found:true,operation:'issue',receipt:{grantId:WORK_ID,groupId:I.group,
   owner:'synthetic-worker',version:1,enabled:false,expiresAt:1900000000000}};};
 let r=await call({path:NATIVE_WORK,body:workIssue(),headers:{'Idempotency-Key':OWNER_REQUEST}});
 assert.equal(r.response.status,503);assert.equal(r.body.outcome,'operation_unknown');assert.equal(calls,1);assert(!JSON.stringify(r.body).includes('private'));
 r=await call({path:NATIVE_WORK+'/requests/'+OWNER_REQUEST+'?collectionId='+I.group,method:'GET'});
 assert.equal(r.response.status,200,JSON.stringify(r.body));assert.equal(r.body.receipt.grantId,WORK_ID);assert.equal(calls,2);
}));
