import {registerHooks} from 'node:module';
import assert from 'node:assert/strict';
import {test} from './helpers/fenced-node-test.js';
import {OWNER_EMAIL} from '../domain/admin_account_support/security.js';

// Exercise the real route/dispatch code with explicit synthetic BFF, SQL and
// provider boundaries. These doubles do not certify PostgreSQL authority or a
// provider; they do let us prove the hold occurs after authorization and before
// creating or resuming any job or gateway dispatch.
const fixtures = {
 './admin_accounts.js': `export function validateAdminOrigin(r,e){if(!globalThis.__hold.origin)throw globalThis.__hold.error(403,'origin_rejected');}
 export async function adminAccountSession(r,e){if(!globalThis.__hold.account)throw globalThis.__hold.error(401,'unauthenticated');return globalThis.__hold.account;}
 export function accountDatabase(e){return e;}
 export async function adminCanonicalActor(){return globalThis.__hold.actor;}`,
 './admin_email_policy.js': `export function requireFreshAdminEmail(a){if(!globalThis.__hold.fresh)throw globalThis.__hold.error(403,'recent_email_sign_in_required');}
 export function adminEmailProofId(){return '50000000-0000-4000-8000-000000000001';}
 export function adminEmailVerifiedAt(){return 1792497600;}`,
 './mutations.js': `export async function retainedResponse(){globalThis.__hold.retainedReads++;return globalThis.__hold.retained??{found:false};}
 export async function mutation(e,a,o,id,b,v,w){globalThis.__hold.mutations.push({operation:o,body:b,writes:w});return v;}`,
 './assisted_sms_dispatch.js': `export async function dispatchAssistedSms(){globalThis.__hold.providerCalls++;throw Error('provider call prohibited');}
 export async function inspectAssistedSms(){globalThis.__hold.inspections++;return {may_send:false,gateway_state:'unknown'};}`,
};
registerHooks({resolve(specifier,context,next){
 if((context.parentURL?.endsWith('/domain/notification_operator_management.js')||context.parentURL?.endsWith('/domain/notification_operator.js'))&&Object.hasOwn(fixtures,specifier))
  return {url:'data:text/javascript,'+encodeURIComponent(fixtures[specifier]),shortCircuit:true};
 return next(specifier,context);
}});
const {ApiError,digest,stableJson}=await import('../domain/core.js');
const {notificationOperatorManagementRoute}=await import('../domain/notification_operator_management.js');
const {notificationOperatorRoute}=await import('../domain/notification_operator.js');
const ids={admin:'10000000-0000-4000-8000-000000000001',principal:'10000000-0000-4000-8000-000000000002',session:'10000000-0000-4000-8000-000000000003',public:'10000000-0000-4000-8000-000000000004',collection:'10000000-0000-4000-8000-000000000005',request:'10000000-0000-4000-8000-000000000006',attempt:'10000000-0000-4000-8000-000000000007'};
const url='https://admin.example.invalid';
function fixture(){
 const f={origin:true,fresh:true,retainedReads:0,mutations:[],providerCalls:0,inspections:0,reads:[],rows:new Map(),
  error:(status,code)=>new ApiError(status,code,'Synthetic authorization denial.'),
  account:{id:ids.admin,principal_id:ids.principal,auth_session_id:ids.session,public_id:ids.public,email:OWNER_EMAIL,role:'owner',permissions:['assisted_sms.manage','admin_users.manage']},
  actor:{userId:ids.principal,sessionId:ids.session,surface:'admin'}};
 f.db={prepare(sql){return {sql,bind(...args){return {sql,args};}};},async batch(statements){
  f.reads.push(...statements.map(s=>s.sql));
  return statements.map(s=>({results:s.sql.includes('FROM collections c LEFT JOIN assisted_sms_policies')?[{id:ids.collection,status:'active',enabled:1,revision:3,template_key:'collect.recorded_contribution.v1',approval_reference_sha256:'a'.repeat(64),updated_at:'2026-01-01T00:00:00.000Z'}]:
   s.sql.startsWith('SELECT * FROM request_receipts')?(f.rows.has(s.args[1])?[f.rows.get(s.args[1])]:[]):
   s.sql.includes('FROM assisted_sms_current_jobs j JOIN assisted_sms_claims')&&f.claim?[f.claim]:
   s.sql.startsWith('SELECT * FROM assisted_sms_confirmations')&&f.confirmation?[f.confirmation]:[]}));
 }};
 globalThis.__hold=f;return f;
}
function request(path,method='GET',body){return new Request(url+path,{method,headers:{Origin:url,'X-Collect-Admin':'1','Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});}
const denied=code=>e=>e instanceof ApiError&&e.code===code;
const policyPath='/api/admin/notification-operator/policies/'+ids.collection;
test('unauthenticated or unauthorized commands fail before the qualification response',async()=>{
 for(const mode of ['anonymous','nonowner','missing_permission','stale_email']){
  const f=fixture();if(mode==='anonymous')f.account=null;if(mode==='nonowner')f.account.role='staff';if(mode==='missing_permission')f.account.permissions=[];if(mode==='stale_email')f.fresh=false;
  await assert.rejects(()=>notificationOperatorManagementRoute(request(policyPath,'POST',{request_id:ids.request,expected_revision:3,enabled:true,owner_confirmation:true}),{DB:f.db}),denied({anonymous:'unauthenticated',nonowner:'owner_required',missing_permission:'permission_required',stale_email:'recent_email_sign_in_required'}[mode]));
  assert.equal(f.mutations.length,0);assert.equal(f.providerCalls,0);
 }
});
test('new and repeated enabling and materialization are held before receipts or mutation',async()=>{
 const f=fixture(),env={DB:f.db},plan={request_id:ids.request,collection_id:ids.collection,limit:5};
 for(let n=0;n<2;n++){
  await assert.rejects(()=>notificationOperatorManagementRoute(request(policyPath,'POST',{request_id:ids.request,expected_revision:3,enabled:true,owner_confirmation:true}),env),denied('receipt_sms_qualification_unavailable'));
  await assert.rejects(()=>notificationOperatorManagementRoute(request('/api/admin/notification-operator/materialize','POST',plan),env),denied('receipt_sms_qualification_unavailable'));
 }
 assert.equal(f.retainedReads,0);assert.equal(f.mutations.length,0);assert.deepEqual(f.reads,[]);assert.equal(f.providerCalls,0);
});
test('disable remains available while current policy and retained operation readback stay observable',async()=>{
 const f=fixture(),env={DB:f.db};
 const current=await notificationOperatorManagementRoute(request(policyPath),env);assert.equal((await current.json()).result.enabled,true);
 const disable=await notificationOperatorManagementRoute(request(policyPath,'POST',{request_id:ids.request,expected_revision:3,enabled:false,owner_confirmation:false}),env);
 assert.equal((await disable.json()).result.enabled,false);assert.equal(f.mutations.length,1);assert.equal(f.mutations[0].operation,'assisted_sms.policy.configure');
 const decision={request_id:ids.request,owner_user_id:ids.principal,originating_session_id:ids.session,public_session_id:ids.public,enabled:true};
 f.rows.set(ids.request,{operation:'assisted_sms.policy.configure',session_id:ids.session,response_json:JSON.stringify(decision)});
 const found=await notificationOperatorManagementRoute(request('/api/admin/notification-operator/policies/operations/'+ids.request),env);
 assert.equal((await found.json()).result.recorded_decision.enabled,true);assert.equal(f.mutations.length,1);
});
test('a retained materialization plan remains readable but its POST cannot resume work',async()=>{
 const f=fixture(),env={DB:f.db},input={request_id:ids.request,collection_id:ids.collection,limit:5};
 const plan={request_id:ids.request,input,collection_id:ids.collection,current_admin_id:ids.admin,current_principal_id:ids.principal,originating_session_id:ids.session,public_session_id:ids.public,sources:[],has_more_observed:false,recorded_at:'2026-01-01T00:00:00.000Z'};
 f.rows.set(ids.request,{operation:'assisted_sms.materialize.plan',session_id:ids.session,body_sha256:await digest(stableJson(input)),response_json:JSON.stringify(plan)});
 const status=await notificationOperatorManagementRoute(request('/api/admin/notification-operator/materialize/'+ids.request),env);
 assert.equal((await status.json()).result.observed,true);
 await assert.rejects(()=>notificationOperatorManagementRoute(request('/api/admin/notification-operator/materialize','POST',input),env),denied('receipt_sms_qualification_unavailable'));
 assert.equal(f.mutations.length,0);assert.equal(f.providerCalls,0);
});
test('gateway dispatch is held after authentication; existing gateway inspection remains available',async()=>{
 const f=fixture(),env={DB:f.db};
 await assert.rejects(()=>notificationOperatorRoute(request('/api/admin/notification-operator','POST',{action:'dispatch_gateway',attempt_id:ids.attempt,dispatch_token:'a'.repeat(64)}),env),denied('receipt_sms_qualification_unavailable'));
 assert.equal(f.providerCalls,0);assert.equal(f.mutations.length,0);
 const inspect=await notificationOperatorRoute(request('/api/admin/notification-operator','POST',{action:'inspect_gateway',attempt_id:ids.attempt}),env);
 assert.equal((await inspect.json()).result.may_send,false);assert.equal(f.inspections,1);
 f.account=null;
 await assert.rejects(()=>notificationOperatorRoute(request('/api/admin/notification-operator','POST',{action:'dispatch_gateway',attempt_id:ids.attempt,dispatch_token:'a'.repeat(64)}),env),denied('unauthenticated'));
 assert.equal(f.providerCalls,0);
});
test('manual send-start issues no automatic gateway grant and its replay issues no permit',async()=>{
 const f=fixture(),env={DB:f.db},claim='10000000-0000-4000-8000-000000000008',confirmation='10000000-0000-4000-8000-000000000009';
 f.claim={id:ids.collection,claim_id:claim,fence:1,body_sha256:'a'.repeat(64),destination_sha256:'b'.repeat(64),destination_revision:1};
 f.confirmation={id:confirmation,claim_id:claim,originating_session_id:ids.session,public_session_id:ids.public};
 const body={action:'record_send_start',job_id:ids.collection,claim_token:claim,fence_version:1,request_id:ids.request,confirmation_id:confirmation};
 const started=await notificationOperatorRoute(request('/api/admin/notification-operator','POST',body),env),result=(await started.json()).result;
 assert.equal(result.may_send,true);assert.equal(Object.hasOwn(result,'dispatch_token'),false);
 assert.equal(f.reads.some(sql=>sql.includes('INSERT INTO app.assisted_sms_dispatches')),false);assert.equal(f.providerCalls,0);
 f.retained={found:true,value:result};f.reads=[];
 const replay=await notificationOperatorRoute(request('/api/admin/notification-operator','POST',body),env);
 assert.equal((await replay.json()).result.may_send,false);assert.deepEqual(f.reads,[]);assert.equal(f.providerCalls,0);
});
