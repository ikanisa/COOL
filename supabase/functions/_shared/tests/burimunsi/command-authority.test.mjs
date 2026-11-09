import test from 'node:test';import assert from 'node:assert/strict';
import {revalidateCommandActor} from '../../domain/burimunsi/command-authority.js';
import {MemberService} from '../../domain/burimunsi/member-service.js';
import {ContributionService} from '../../domain/burimunsi/contribution-service.js';
import {actor,member} from './fixtures.mjs';
const req='33333333-3333-4333-8333-333333333333';
for(const changed of [{id:'other'},{sessionId:'replacement'},{groupId:'other'},{expiresAt:50},{active:false},{revoked:true},{capabilities:['records.read']}])test('command actor must still own exact current scope '+JSON.stringify(changed),async()=>{
 await assert.rejects(revalidateCommandActor({reloadActor:async()=>({...actor,...changed})},actor,'group-1','members.enroll',1000));
});
test('current actor succeeds unchanged',async()=>assert.equal((await revalidateCommandActor({reloadActor:async()=>actor},actor,'group-1','members.enroll',1000)).id,actor.id));
function store(afterCommand){
 const f={committed:false,retained:null,actor:structuredClone(actor),checks:0};
 f.inCanonicalTransaction=async fn=>{
  const tx={reloadActor:async()=>{f.checks++;return f.actor},retainedCommand:async()=>null,
   createDirectMember:async()=>{afterCommand?.(f);return {id:'member-1',groupId:'group-1',phone:'+250780000816'}},
   setMembershipActive:async()=>{afterCommand?.(f);return {applied:true}},enqueueEligibleRematch:async()=>{},
   lockReceipt:async()=>({id:'tx-1',groupId:'group-1',version:1,state:'unallocated',hasConflict:false,amountRwf:10000}),lockMember:async()=>member,
   postCanonicalContribution:async()=>{afterCommand?.(f);return {transactionId:'tx-1',memberId:'member-1',amountRwf:10000,currency:'RWF',ledgerEntryId:'l-1',memberBalanceRwf:10000,groupBalanceRwf:10000}},
   retainCommand:async c=>{f.retained=c}};
  const result=await fn(tx);f.committed=true;return result;
 };return f;
}
for(const op of ['enroll','membership','allocate']){
 const execute=f=>{
  // Lifecycle tests now exercise an admitted Admin; separate negatives protect Staff denial.
  if(op==='membership')f.actor.role='admin';
  if(op==='allocate')return new ContributionService({store:f,groupId:'group-1',clock:()=>1000}).allocate(actor,{transactionId:'tx-1',memberId:'member-1',expectedVersion:1,note:'Independent identity proof',requestId:req});
  const service=new MemberService({store:f,groupId:'group-1',clock:()=>1000});
  return op==='enroll'?service.enroll(actor,{name:'Example',phone:'+250780000816',requestId:req}):service.setActive(actor,{memberId:'member-1',active:false,expectedVersion:1,requestId:req});
 };
 test(op+' retains explicit operation identity',async()=>{const f=store();await execute(f);assert.equal(f.retained.operation,'burimunsi.'+op);assert.ok(f.checks>=2)});
 test(op+' cannot acknowledge expired session after command completes',async()=>{const f=store(f=>f.actor.expiresAt=999);await assert.rejects(execute(f),/session_unavailable/);assert.equal(f.committed,false);assert.equal(f.retained,null)});
 test(op+' cannot acknowledge session replacement after command completes',async()=>{const f=store(f=>f.actor.sessionId='replacement');await assert.rejects(execute(f),/session_unavailable/);assert.equal(f.committed,false)});
}
