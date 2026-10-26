import {test} from './helpers/fenced-node-test.js';
import {fixtureEnvironment} from './helpers/fenced-unit.js';
import assert from 'node:assert/strict';
import {isAbsolute,join} from 'node:path';
import {pathToFileURL} from 'node:url';
const root=process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof root==='string'&&isAbsolute(root),'Provide the coherent actual _shared graph.');
const actual=name=>import(pathToFileURL(join(root,name)).href);
const {adminAccountSession,handleAdminAccounts}=await actual('domain/admin_accounts.js');
const {encrypt}=await actual('domain/encryption.js');
const {ApiError,digest}=await actual('domain/core.js');
const NOW=1792497600,ORIGIN='https://admin-supabase-qa.collect.ikanisa.com',PROJECT='https://admin-email-bff.synthetic.invalid';
const AUTH='11111111-1111-4111-8111-111111111111',SID='22222222-2222-4222-8222-222222222222';
const PRINCIPAL='33333333-3333-4333-8333-333333333333',ADMIN='44444444-4444-4444-8444-444444444444',PUBLIC='55555555-5555-4555-8555-555555555555';
const EMAIL='synthetic.admin@example.invalid',COOKIE='b'.repeat(64),KEY=Buffer.alloc(32,7).toString('base64');
const error=(status,code)=>value=>value instanceof ApiError&&value.status===status&&value.code===code;
const claims=(exp,patch={})=>({sub:AUTH,session_id:SID,role:'authenticated',aud:'authenticated',iss:PROJECT+'/auth/v1',aal:'aal1',exp,iat:NOW,amr:[{method:'password',timestamp:NOW-600}],...patch});
const jwt=value=>[Buffer.from('{}').toString('base64url'),Buffer.from(JSON.stringify(value)).toString('base64url'),'synthetic-signature'].join('.');
async function fixture(options,run){
 const oldNow=Date.now,oldFetch=globalThis.fetch;Date.now=()=>NOW*1000;
 const hash=await digest(COOKIE),currentClaims=claims(NOW+3600,options.claims??{}),oldToken=jwt(claims(NOW+20)),winnerToken=jwt(currentClaims);
 const cryptEnv={DATA_KEY_ID:'synthetic-bff',DATA_ENCRYPTION_KEY:KEY};
 const document=async token=>encrypt(cryptEnv,new TextEncoder().encode(JSON.stringify({access_token:token,refresh_token:'synthetic-refresh'})),`bff:${SID}:${AUTH}`);
 const old={token_hash:hash,auth_user_id:AUTH,auth_session_id:SID,version:7,refresh_lease:null,refresh_lease_until:null,token_ciphertext:await document(oldToken),expires_at:NOW+3600};
 const winner={...old,version:8,token_ciphertext:await document(winnerToken),...options.winner};
 const trace=[],calls=[],writes=[];
 const account={id:ADMIN,email:EMAIL,role:'owner',status:'active',auth_version:1,principal_id:PRINCIPAL,public_id:PUBLIC,token_hash:hash,auth_session_id:SID,origin:ORIGIN,expires_at:NOW+3600,issued_assurance_level:1,issued_mfa_at:null,issued_mfa_factor_id:null,auth_at:NOW-600};
 const db={claims:{},setClaims(value){this.claims=value;},prepare(sql){return{args:[],bind(...args){this.args=args;return this;},async first(){
  trace.push(sql);
  if(sql.startsWith('SELECT b.*,s.expires_at'))return old;
  if(sql.startsWith('UPDATE private.bff_sessions SET refresh_lease='))return null;
  if(sql==='SELECT * FROM private.bff_sessions WHERE token_hash=?')return winner;
  if(sql.startsWith('SELECT private.is_managed_session('))return{allowed:true};
  if(sql==='SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?')return{user_id:PRINCIPAL};
  if(sql==='SELECT * FROM users WHERE id=?')return{id:PRINCIPAL,access_status:'active',full_name:'Synthetic',public_id:'100001'};
  if(sql==='SELECT * FROM auth_sessions WHERE id=?')return{id:SID,user_id:PRINCIPAL,surface:'admin',auth_at:NOW-600,created_at:NOW-600,expires_at:NOW+3600,revoked_at:null,assurance_level:1,mfa_at:null,mfa_factor_id:null};
  if(sql.startsWith('SELECT a.id FROM admin_sessions s JOIN admin_users a'))return{id:ADMIN};
  if(sql.startsWith('SELECT a.*,s.public_id'))return{...account};
  if(sql.startsWith('SELECT private.admin_email_status('))return{result:{contract_version:1,public_session_id:PUBLIC,email_verified_at:null,proof_id:null}};
  throw new Error('Unexpected fixture query');
 },async all(){trace.push(sql);if(sql.startsWith('SELECT g.permission FROM admin_grants'))return{results:[{permission:'admin_users.manage'}]};if(sql.startsWith('SELECT c.permission FROM admin_account_role_capabilities'))return{results:[{permission:'admin_users.manage'}]};throw new Error('Unexpected fixture all');},async run(){writes.push(sql);throw new Error('No fixture write may be silently accepted');}};}};
 const env=fixtureEnvironment({DB:db,SUPABASE_URL:PROJECT,SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_bff',ADMIN_ORIGIN:ORIGIN,SESSION_KEY_ID:'synthetic-bff',SESSION_ENCRYPTION_KEY:KEY});
 globalThis.fetch=async(input,init)=>{const r=new Request(input,init);calls.push({url:r.url,method:r.method,token:r.headers.get('Authorization')});assert.equal(r.url,PROJECT+'/auth/v1/user');assert.equal(r.method,'GET');if(options.providerFailure)return Response.json({error_code:'synthetic_auth_failure'},{status:503});return Response.json({id:AUTH,email:EMAIL,email_confirmed_at:'2026-10-20T12:00:00Z',app_metadata:{provider:'email'}});};
 const request=(method='GET',extra={})=>new Request(ORIGIN+'/api/admin/auth/email-verification',{method,headers:{Cookie:'__Host-collect_admin='+COOKIE,Origin:ORIGIN,'X-Collect-Requested-With':'collect-admin',...(['GET','HEAD'].includes(method)?{}:{'Content-Type':'application/json'}),...extra},...(['GET','HEAD'].includes(method)?{}:{body:'{}'})});
 try{await run({env,db,trace,calls,writes,request,winnerToken});}
 finally{Date.now=oldNow;globalThis.fetch=oldFetch;assert.deepEqual(writes,[]);assert.equal(calls.filter(x=>x.method!=='GET').length,0,'A refresh loser never dispatches another refresh or logout');}
}
test('BFF refresh loser accepts only exact committed original-session winner', {concurrency:false},async t=>{
 await t.test('one retained version advance is reverified without refreshing, changing SID or manufacturing freshness',()=>fixture({},async f=>{
  const account=await adminAccountSession(f.request(),f.env);assert.equal(account.supabaseTokens.access_token,f.winnerToken);assert.equal(account.auth_session_id,SID);assert.equal(account.auth_at,NOW-600);assert.equal(account.issued_assurance_level,1);assert.equal(account.issued_mfa_at,null);assert.ok(f.calls.length>=2);assert.equal(f.db.claims.session_id,SID);
 }));
 for(const winner of [{version:7},{version:9},{refresh_lease:'still-owned',refresh_lease_until:NOW+30},{refresh_lease_until:NOW+30},{auth_user_id:ADMIN},{auth_session_id:PUBLIC},{token_hash:'a'.repeat(64)},{token_ciphertext:''}])await t.test('inexact winner remains pending: '+Object.keys(winner)[0],()=>fixture({winner},async f=>{
  await assert.rejects(adminAccountSession(f.request(),f.env),error(409,'session_refresh_pending'));assert.equal(f.calls.length,0);
 }));
 await t.test('wrong-SID winner is not adopted',()=>fixture({claims:{session_id:PUBLIC}},async f=>{await assert.rejects(adminAccountSession(f.request(),f.env),error(401,'session_changed'));}));
 await t.test('ordinary provider failure is not hidden as a successful winner',()=>fixture({providerFailure:true},async f=>{await assert.rejects(adminAccountSession(f.request(),f.env),error(503,'synthetic_auth_failure'));}));
 await t.test('email reauthentication keeps mutating CSRF enforcement',()=>fixture({},async f=>{
  const request=new Request(ORIGIN+'/api/admin/auth/email/request',{method:'POST',headers:f.request('POST').headers,body:'{}'});
  await assert.rejects(handleAdminAccounts(request,f.env,{}),error(403,'csrf_rejected'));assert.equal(f.calls.filter(x=>x.method==='POST').length,0);
 }));
 for(const headers of[{Origin:'https://foreign.invalid'},{'X-Collect-Requested-With':'other'},{'Sec-Fetch-Site':'cross-site'}])await t.test('email reauthentication preserves origin/requested-with before any identity access: '+Object.keys(headers)[0],()=>fixture({},async f=>{
  const request=new Request(ORIGIN+'/api/admin/auth/email/request',{method:'POST',headers:f.request('POST',headers).headers,body:'{}'});
  await assert.rejects(handleAdminAccounts(request,f.env,{}),error(403,'origin_rejected'));assert.deepEqual(f.trace,[]);assert.deepEqual(f.calls,[]);
 }));
});
