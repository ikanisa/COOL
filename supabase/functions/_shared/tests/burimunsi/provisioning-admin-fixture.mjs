// TEST ONLY: reduced SQLite BFF fixture shared in shape with admin-access.test.
// Actual managed-provider/PG owner procedures/RLS/fence are explicit substitutes.
import assert from 'node:assert/strict';
import {principalFixture,I} from './native-principal-fixture.mjs';
import {openApplicationWork} from '../../application-fence.js';
import {syntheticFenceBackend} from '../helpers/fenced-unit.js';
import {canonicalProfile} from '../../deployment-profile.js';
import {digest} from '../../domain/core.js';
import {encrypt} from '../../domain/encryption.js';
import {handleAdmin} from '../../domain/admin_bridge.js';
const ORIGIN='https://admin.native-access.example.invalid',PROJECT='https://supabase.native-access.example.invalid';
const AUTH='20000000-0000-4000-8000-000000000001',SID='20000000-0000-4000-8000-000000000002';
const ADMIN='20000000-0000-4000-8000-000000000003',PUBLIC='20000000-0000-4000-8000-000000000004';
const PRINCIPAL='20000000-0000-4000-8000-000000000005';
const COOKIE='b'.repeat(64),DEVICE='c'.repeat(64),SOURCE='a'.repeat(64),KEY=Buffer.alloc(32,11).toString('base64');
const PROFILE={format:'collect.deployment.v1',id:'native-access-fixture',mode:'self_hosted',environment:'qualification',
 supabase_origin:PROJECT,admin_origin:ORIGIN,member_api_origin:'https://api.native-access.example.invalid',
 public_origin:'https://collect.native-access.example.invalid',google_callback_origin:ORIGIN};

export async function provisioningAdminFixture(run){
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
  if(q.startsWith('SELECT private.burimunsi_provisioning_')){
   if(!state.ownerCommand)throw Error('No owner command substitute configured');
   return [{result:await state.ownerCommand(q,args)}];
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
 const raw=canonicalProfile(PROFILE),env={DB:f.db,COLLECT_FENCE_WORK:work,BUILD_SOURCE_ID:SOURCE,
  COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:await digest(raw),SUPABASE_URL:PROJECT,
  SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fixture',ADMIN_ORIGIN:ORIGIN,BURIMUNSI_COLLECTION_ID:I.group,
  SESSION_KEY_ID:'fixture-bff',SESSION_ENCRYPTION_KEY:KEY};
 Object.assign(env,{BURIMUNSI_PIN_PEPPER_BASE64:Buffer.alloc(32,91).toString('base64'),BURIMUNSI_PIN_PEPPER_ID:'provisioning-fixture',DATA_KEY_ID:'provisioning-fixture',DATA_ENCRYPTION_KEY:KEY});
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

export function provisioningOwner(f,state,at){
 // Explicit owner/email SQL substitutes for route tests; real SQL owner proof
 // and retained outcome/revocation checks belong to native PG qualification.
 f.execute("UPDATE app.admin_users SET role='owner',email='info@ikanisa.com'");state.emailVerifiedAt=at;
 f.execute('INSERT INTO app.admin_grants VALUES(?,?)',PRINCIPAL,'admin_users.manage');
 f.execute('INSERT INTO app.admin_account_role_capabilities VALUES(?,?)','owner','admin_users.manage');
}

export {I,PRINCIPAL,ADMIN,PUBLIC};
