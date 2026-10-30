import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {RetentionApi,parseEmailProof} from '../src/retention_api.mjs';
import {verifyCurrentEmail,verificationArguments} from '../src/verify_email.mjs';
import {ADMIN_ORIGIN,saveCredential,SafeError} from '../src/config.mjs';

const id=n=>`${String(n).padStart(8,'0')}-1111-4111-8111-111111111111`;
const cookie='__Host-collect_admin='+'a'.repeat(64),csrf='b'.repeat(64);
function session(){return {user:{id:id(1),principalId:id(2),sessionId:id(3),email:'operator@example.test',role:'owner',financialModel:'canonical_evidence_ledger',permissions:['privacy.review'],assuranceLevel:1,mfaAt:null},expiresAt:new Date(Date.now()+3600000).toISOString(),csrfToken:csrf};}
const proof=()=>({contractVersion:1,sessionId:id(3),emailVerifiedAt:new Date(Math.floor(Date.now()/1000)*1000).toISOString()});
async function fixture(t,{onSession,onProof,onPrivacy,onEmail}={}){
 const dir=await mkdtemp(join(tmpdir(),'retention-api-')),config={origin:ADMIN_ORIGIN,credentialFile:join(dir,'session.json')};
 await saveCredential(config,{version:1,origin:ADMIN_ORIGIN,cookie,accountId:id(1),principalId:id(2),sessionId:id(3),expiresAt:new Date(Date.now()+3600000).toISOString()});
 const original=globalThis.fetch,requests=[];let sessions=0,proofs=0;
 globalThis.fetch=async(input,options)=>{
  const url=new URL(input);assert.equal(url.origin,ADMIN_ORIGIN);assert.equal(options.redirect,'error');assert.equal(options.headers.Cookie,cookie);assert.equal(options.headers.Origin,ADMIN_ORIGIN);assert.equal(Object.hasOwn(options.headers,'Authorization'),false);
  const path=url.pathname,body=options.body?JSON.parse(options.body):null;requests.push({path,method:options.method,body,headers:options.headers});let value;
  if(path==='/api/admin/auth/session')value=onSession?.(++sessions)??session();
  else if(path==='/api/admin/auth/email-verification')value=onProof?.(++proofs)??proof();
  else {assert.equal(options.method,'POST');assert.equal(options.headers['X-Collect-CSRF'],csrf);
   if(path.startsWith('/api/admin/privacy/'))value=await onPrivacy?.(path,body)??{ok:true};
   else value=await onEmail?.(path,body)??proof();}
  return new Response(JSON.stringify(value),{status:200,headers:{'Content-Type':'application/json'}});
 };
 t.after(async()=>{globalThis.fetch=original;await rm(dir,{recursive:true,force:true});});
 return {api:new RetentionApi(config),requests};
}

test('retention uses same-origin cookie, current session email proof, CSRF and exact RPC paths with final fences',async t=>{
 const f=await fixture(t);const result=await f.api.withSession(async scope=>{
  assert.equal(Object.hasOwn(scope,'cookie'),false);assert.equal(Object.hasOwn(scope,'csrfToken'),false);
  await scope.read('status',{p_plan_id:id(4)});return scope.write('claim',{p_operation_id:id(5),p_plan_id:id(4),p_task_id:id(6),p_expected_task_revision:0,p_lease_seconds:120});
 });assert.deepEqual(result,{ok:true});assert.equal(f.requests.filter(r=>r.path.endsWith('/auth/session')).length,2);assert.equal(f.requests.filter(r=>r.path.endsWith('/auth/email-verification')).length,2);
 const writes=f.requests.filter(r=>r.path.startsWith('/api/admin/privacy/'));assert.deepEqual(writes.map(r=>r.path),['/api/admin/privacy/admin_get_account_retention_status_v1','/api/admin/privacy/admin_claim_account_retention_task_v1']);
 assert.equal(JSON.stringify(result).includes(cookie),false);
});

test('AAL2 without independent current-session email proof cannot read or mutate retention',async t=>{
 const f=await fixture(t,{onSession:()=>({...session(),user:{...session().user,assuranceLevel:2,mfaAt:new Date().toISOString()}}),onProof:()=>({...proof(),emailVerifiedAt:null})});
 await assert.rejects(()=>f.api.withSession(scope=>scope.write('plan',{})),{code:'recent_email_sign_in_required'});assert.equal(f.requests.some(r=>r.path.startsWith('/api/admin/privacy/')),false);
});

test('wrong session, stale proof, future proof and missing CSRF are rejected before data operations',async t=>{
 const user=session().user;
 for(const emailVerifiedAt of [new Date(Date.now()-301000).toISOString(),null])assert.throws(()=>parseEmailProof({...proof(),emailVerifiedAt},user),{code:'recent_email_sign_in_required'});
 assert.throws(()=>parseEmailProof({...proof(),sessionId:id(20)},user));assert.throws(()=>parseEmailProof({...proof(),emailVerifiedAt:new Date(Date.now()+60000).toISOString()},user));
 const f=await fixture(t,{onSession:()=>({...session(),csrfToken:undefined})});await assert.rejects(()=>f.api.withSession(scope=>scope.read('context')));assert.equal(f.requests.length,1);
});

test('capability changes at final fence prevent returning data; missing privacy grant prevents all privacy calls',async t=>{
 const f=await fixture(t,{onSession:n=>n===1?session():({...session(),user:{...session().user,permissions:[]}})});
 await assert.rejects(()=>f.api.withSession(scope=>scope.read('context')),{code:'retention_session_changed'});
 const before=f.requests.filter(r=>r.path.startsWith('/api/admin/privacy/')).length;
 await assert.rejects(()=>f.api.withSession(scope=>scope.read('context')),{code:'permission_denied'});assert.equal(f.requests.filter(r=>r.path.startsWith('/api/admin/privacy/')).length,before);
});

test('email verification scope cannot invoke privacy or arbitrary endpoints and keeps the original public session',async t=>{
 const f=await fixture(t,{onEmail:(path,body)=>{
  if(path.endsWith('/request')){assert.deepEqual(body,{captcha_token:'synthetic-token'});return {challenge_id:id(10),delivery_status:'unknown',expires_in:300,retry_after:60};}
  assert.equal(path,'/api/admin/auth/email/verify');assert.deepEqual(body,{challenge_id:id(10),code:'123456'});return proof();
 }});
 await assert.rejects(()=>f.api.withSession(scope=>scope.read('context'),{fresh:false,privacy:false}));
 await assert.rejects(()=>f.api.withSession(scope=>scope.write('execute',{}),{fresh:false,privacy:false}));
 await assert.rejects(()=>f.api.withSession(scope=>scope.read('https://elsewhere.example',{})));
 const challenge=await f.api.requestVerification('synthetic-token');assert.equal(challenge.delivery_status,'unknown');const verified=await f.api.verifyEmail(challenge.challenge_id,'123456');assert.equal(verified.sessionId,id(3));
 assert.equal(f.requests.some(r=>r.path.includes('/login')||r.path.includes('/auth/otp')),false);
});

test('uncertain verification reads proof once without replaying a code; no stdin or argument secrets accepted',async()=>{
 let calls=0,reads=0;const api={async verifyEmail(){calls++;throw new SafeError('service_unavailable','unconfirmed');},async verificationStatus(){reads++;return proof();}};
 assert.equal((await verifyCurrentEmail(api,id(9),'123456')).sessionId,id(3));assert.equal(calls,1);assert.equal(reads,1);
 assert.throws(()=>verificationArguments([],false),{code:'interactive_verification_required'});assert.throws(()=>verificationArguments(['123456'],true),{code:'interactive_verification_required'});assert.throws(()=>verificationArguments(['resume',id(9),'123456'],true));assert.equal(verificationArguments(['resume',id(9)],true),id(9));
});
