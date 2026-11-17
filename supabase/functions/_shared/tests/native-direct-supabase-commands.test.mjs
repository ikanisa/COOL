// Actual direct ingress, native wire handler and command services over a
// serial synthetic transaction store. No production database or provider.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../deployment-profile.js';
import {admitDirectSupabaseNativeIngress} from '../native-direct-supabase-ingress.js';
import {createNativeHandler} from '../domain/burimunsi/http.js';
import {MemberService} from '../domain/burimunsi/member-service.js';
import {ContributionService} from '../domain/burimunsi/contribution-service.js';
import {BuriError} from '../domain/burimunsi/errors.js';

const profile={format:'collect.deployment.v1',id:'direct-command-fixture',mode:'managed',environment:'qualification',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.fixture.invalid',admin_origin:'https://admin.fixture.invalid',
 public_origin:'https://collect.fixture.invalid',google_callback_origin:'https://admin.fixture.invalid'};
const raw=canonicalProfile(profile),env={COLLECT_DEPLOYMENT_PROFILE:raw,
 COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(raw).digest('hex'),APP_ENVIRONMENT:'qualification',
 SUPABASE_URL:MANAGED_SUPABASE_ORIGIN,BURIMUNSI_NATIVE_ENABLED:'true',COLLECT_NATIVE_INGRESS_MODE:'supabase_direct_v1'};
const install='22222222-2222-4222-8222-222222222222',actorId='11111111-1111-4111-8111-111111111111',
 session='33333333-3333-4333-8333-333333333333',correlation='44444444-4444-4444-8444-444444444444',
 enrollId='55555555-5555-4555-8555-555555555555',allocationId='66666666-6666-4666-8666-666666666666',
 membershipId='77777777-7777-4777-8777-777777777777',validToken='a'.repeat(64),group='group-1';

function fixture(){
 let state={actor:{id:actorId,sessionId:session,groupId:group,role:'staff',active:true,revoked:false,
  expiresAt:9999999999999,capabilities:['records.read','members.enroll','payments.allocate']},
  receipts:new Map(),members:0,posts:0,membershipWrites:0,rematches:0,receiptState:'unallocated'};
 let tail=Promise.resolve();
 const transact=fn=>{
  const task=tail.then(async()=>{
   const copy=structuredClone(state),tx={
    reloadActor:async()=>copy.actor,
    retainedCommand:async(_group,_actor,id)=>copy.receipts.get(id)??null,
    retainCommand:async c=>{if(copy.receipts.has(c.requestId))throw Error('duplicate fixture receipt');copy.receipts.set(c.requestId,c);},
    createDirectMember:async c=>{copy.members++;return {id:'member-1',groupId:group,phone:c.phone,name:c.name};},
    enqueueEligibleRematch:async()=>{copy.rematches++;},
    setMembershipActive:async c=>{copy.membershipWrites++;return {applied:true,groupId:group,memberId:c.memberId,active:c.active,version:c.expectedVersion+1};},
    lockReceipt:async()=>({id:'transaction-1',groupId:group,version:1,state:copy.receiptState,hasConflict:false,amountRwf:10000}),
    lockMember:async()=>({id:'member-1',groupId:group,active:true,eligible:true}),
    postCanonicalContribution:async()=>{copy.posts++;copy.receiptState='posted';return {transactionId:'transaction-1',memberId:'member-1',amountRwf:10000,currency:'RWF',ledgerEntryId:'ledger-1',memberBalanceRwf:10000,groupBalanceRwf:10000};},
   };
   const result=await fn(tx);state=copy;return result;
  });tail=task.catch(()=>{});return task;
 };
 const store={inMemberTransaction:transact,inCanonicalTransaction:transact},members=new MemberService({store,groupId:group}),
  contributions=new ContributionService({store,groupId:group}),noop=async()=>({});
 async function invoke(path,method,body,{token=validToken,forward='192.0.2.1'}={}){
  const request=new Request(MANAGED_SUPABASE_ORIGIN+'/v1/burimunsi'+path,{method,headers:{
   'content-type':'application/json','authorization':'Bearer '+token,'x-burimunsi-installation':install,
   'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':correlation,'x-burimunsi-generation':'1',
   'x-forwarded-for':forward,'cf-connecting-ip':forward},body:JSON.stringify(body)});
  const admitted=await admitDirectSupabaseNativeIngress(request,env);
  const handler=createNativeHandler({auth:{login:noop,authenticate:async(candidate,installation)=>{
    if(candidate!==validToken||installation!==install)throw new BuriError('session_unavailable',401);return state.actor;},
    logout:noop,changePasscode:noop,manageStaff:noop},
   records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},
   members:{enroll:(...args)=>members.enroll(...args),setActive:(...args)=>members.setActive(...args)},
   contributions:{allocate:(...args)=>contributions.allocate(...args)},gateway:{status:noop,replace:noop},
   origin:MANAGED_SUPABASE_ORIGIN,groupId:group,strictContract:true,networkBucket:admitted.networkBucket});
  const response=await handler(admitted.request);return {status:response.status,body:await response.json()};
 }
 return {invoke,get state(){return state;},setRole(role){state.actor.role=role;}};
}

test('direct duplicate enrollment is retained once; altered retry and bad auth cannot write',async()=>{
 const f=fixture(),body={name:'Example Member',phone:'+250780000002',requestId:enrollId};
 const [a,b]=await Promise.all([f.invoke('/members','POST',body),f.invoke('/members','POST',body,{forward:'198.51.100.8'})]);
 assert.equal(a.status,200);assert.equal(b.status,200);assert.deepEqual(a.body.data,b.body.data);
 assert.equal(f.state.members,1);assert.equal(f.state.rematches,1);assert.equal(f.state.receipts.size,1);
 assert.equal((await f.invoke('/members','POST',{...body,name:'Changed Name'})).status,409);
 assert.equal((await f.invoke('/members','POST',body,{token:'b'.repeat(64)})).status,401);assert.equal(f.state.members,1);
});

test('direct lost-reply allocation retry preserves one financial command and conflicts on changed intent',async()=>{
 const f=fixture(),body={memberId:'member-1',expectedVersion:1,note:'Reviewed source and payer',requestId:allocationId};
 const first=await f.invoke('/payments/transaction-1/allocate','POST',body);assert.equal(first.status,200);
 const retry=await f.invoke('/payments/transaction-1/allocate','POST',body);assert.equal(retry.status,200);
 assert.deepEqual(retry.body.data,first.body.data);assert.equal(f.state.posts,1);
 assert.equal((await f.invoke('/payments/transaction-1/allocate','POST',{...body,note:'Changed reviewed decision'})).status,409);
 assert.equal(f.state.posts,1);
});

test('direct membership change requires Admin authority and retains the original result',async()=>{
 const f=fixture(),body={active:false,expectedVersion:1,requestId:membershipId};
 assert.equal((await f.invoke('/members/member-1','PATCH',body)).status,403);assert.equal(f.state.membershipWrites,0);
 f.setRole('admin');const first=await f.invoke('/members/member-1','PATCH',body),retry=await f.invoke('/members/member-1','PATCH',body);
 assert.equal(first.status,200);assert.equal(retry.status,200);assert.deepEqual(first.body.data,{applied:true});
 assert.deepEqual(retry.body.data,first.body.data);assert.equal(f.state.membershipWrites,1);
 assert.equal((await f.invoke('/members/member-1','PATCH',{...body,active:true})).status,409);
 assert.equal(f.state.membershipWrites,1);
});
