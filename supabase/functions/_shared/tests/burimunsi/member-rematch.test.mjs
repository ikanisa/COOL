import test from 'node:test';import assert from 'node:assert/strict';
import {MemberService} from '../../domain/burimunsi/member-service.js';
import {actor} from './fixtures.mjs';
const requestId='91919191-9191-4191-8191-919191919191';
/** Transaction-state fixture, not a PostgreSQL or real person-command test. */
function fixture(){
 const f={state:{members:[],events:[],receipts:[]},actor:{...structuredClone(actor),role:"admin"},failEnqueue:false,failReceipt:false,afterEnqueue:null,commits:0,rollbacks:0};
 f.store={inCanonicalTransaction:async fn=>{
  const next=structuredClone(f.state);
  const tx={reloadActor:async()=>f.actor,retainedCommand:async(_g,_a,r)=>next.receipts.find(c=>c.requestId===r),
   retainCommand:async c=>{if(f.failReceipt)throw Error('receipt write failed');next.receipts.push(c)},
   createDirectMember:async c=>{next.members.push({id:'member-1',groupId:c.groupId,phone:c.phone,active:true});return next.members.at(-1)},
   setMembershipActive:async c=>{next.members.push({id:c.memberId,active:c.active});return {applied:true}},
   enqueueEligibleRematch:async c=>{if(f.failEnqueue)throw Error('rematch enqueue failed');next.events.push(c);f.afterEnqueue?.();return {durable:true}}};
  try{const out=await fn(tx);f.state=next;f.commits++;return out}catch(e){f.rollbacks++;throw e}
 }};
 f.service=new MemberService({store:f.store,groupId:'group-1',clock:()=>1000});
 f.enroll=()=>f.service.enroll(actor,{name:'Synthetic Member',phone:'0780000816',requestId});
 f.setActive=active=>f.service.setActive(actor,{memberId:'member-1',active,expectedVersion:1,requestId});return f;
}
for(const operation of ['enroll','reactivate']){
 const run=f=>operation==='enroll'?f.enroll():f.setActive(true);
 test(operation+' retains event in same transactional unit',async()=>{
  const f=fixture();await run(f);assert.equal(f.state.members.length,1);assert.equal(f.state.events.length,1);assert.equal(f.state.receipts.length,1);
  assert.deepEqual(f.state.events[0],{groupId:'group-1',memberId:'member-1',requestId,cause:operation==='enroll'?'enrollment':'reactivation'});
  assert.ok(!JSON.stringify(f.state.events).includes('0780000816'));
 });
 test(operation+' replay never extends cutoff or queues a replacement event',async()=>{const f=fixture();const a=await run(f),b=await run(f);assert.deepEqual(a,b);assert.equal(f.state.events.length,1);assert.equal(f.state.members.length,1)});
 test(operation+' enqueue failure rolls back membership command',async()=>{const f=fixture();f.failEnqueue=true;await assert.rejects(run(f),/rematch enqueue failed/);assert.deepEqual(f.state,{members:[],events:[],receipts:[]});assert.equal(f.rollbacks,1)});
 test(operation+' receipt failure rolls back membership and rematch event',async()=>{const f=fixture();f.failReceipt=true;await assert.rejects(run(f),/receipt write failed/);assert.deepEqual(f.state,{members:[],events:[],receipts:[]})});
 test(operation+' revocation during enqueue rolls back the event',async()=>{const f=fixture();f.afterEnqueue=()=>{f.actor.revoked=true};await assert.rejects(run(f),/session_unavailable/);assert.equal(f.state.events.length,0)});
}
test('deactivation never queues a rematch',async()=>{const f=fixture();await f.setActive(false);assert.equal(f.state.members[0].active,false);assert.equal(f.state.events.length,0)});
test('different lifecycle body cannot reuse a retained request',async()=>{const f=fixture();await f.setActive(true);await assert.rejects(f.setActive(false),/idempotency_conflict/);assert.equal(f.state.events.length,1)});

// Membership lifecycle is Admin-only under the frozen UI policy. Enrollment remains delegated.
for(const active of [true,false])test('staff with enrollment capability cannot change membership '+active,async()=>{const f=fixture();f.actor.role='staff';await assert.rejects(f.setActive(active),/access_denied/);assert.deepEqual(f.state,{members:[],events:[],receipts:[]})});
test('staff enrollment remains allowed without lifecycle permission',async()=>{const f=fixture();f.actor.role='staff';await f.enroll();assert.equal(f.state.members.length,1)});
test('Admin role loss during reactivation rolls back the command',async()=>{const f=fixture();f.afterEnqueue=()=>f.actor.role='staff';await assert.rejects(f.setActive(true),/access_denied/);assert.deepEqual(f.state,{members:[],events:[],receipts:[]})});
test('staff cannot replay an Admin lifecycle command',async()=>{const f=fixture();await f.setActive(false);f.actor.role='staff';await assert.rejects(f.setActive(false),/access_denied/);assert.equal(f.state.receipts.length,1)});
