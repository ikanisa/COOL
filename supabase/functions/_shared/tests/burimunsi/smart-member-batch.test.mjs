import test from 'node:test';
import assert from 'node:assert/strict';
import {MemberService} from '../../domain/burimunsi/member-service.js';
import {actor} from './fixtures.mjs';

const requestId='91919191-9191-4191-8191-919191919191';
const row=(n,phone='0780000816')=>({row:n,name:'Synthetic Member '+n,phone,verifiedOwnership:true,acceptedTerms:true,consentRecorded:true});
function fixture(){
 const f={state:{members:[],events:[],receipts:[],attestations:[]},actor:structuredClone(actor),fail:false};
 f.store={inMemberTransaction:async fn=>{
  const next=structuredClone(f.state), tx={
   reloadActor:async()=>f.actor,
   retainedCommand:async(_g,_a,r)=>next.receipts.find(x=>x.requestId===r),
   retainCommand:async x=>{if(f.fail)throw Error('synthetic failure');next.receipts.push(x)},
   createDirectMember:async c=>{const old=next.members.find(x=>x.phone===c.phone);if(old)return {...old,existing:true};
    const value={id:'member-'+(next.members.length+1),groupId:c.groupId,phone:c.phone};next.members.push(value);return value;},
   recordMemberImportAttestation:async x=>{next.attestations.push(x)},
   enqueueEligibleRematch:async x=>{next.events.push(x)},
   onboardingCandidate:async x=>x.candidateId==='candidate-valid'&&x.phone==='+250780000816'?{last3:'816'}:null,
  };
  const out=await fn(tx);f.state=next;return out;
 }};
 f.service=new MemberService({store:f.store,groupId:'group-1',clock:()=>1000});return f;
}
test('one atomic batch is replayed exactly and records separate rematch identities',async()=>{
 const f=fixture(),body={requestId,rows:[row(1),row(2,'0780000817')]};const first=await f.service.importMembers(actor,body);
 assert.equal(first.created,2);assert.deepEqual(await f.service.importMembers(actor,body),first);
 assert.equal(f.state.members.length,2);assert.equal(f.state.attestations.length,2);assert.equal(f.state.events.length,2);
 assert.notEqual(f.state.events[0].requestId,f.state.events[1].requestId);assert.notEqual(f.state.events[0].requestId,requestId);
 await assert.rejects(f.service.importMembers(actor,{requestId,rows:[...body.rows,row(3,'0780000818')]}),/idempotency_conflict/);
 assert.equal(f.state.members.length,2);
});
test('invalid, unverified, duplicate and mismatched suggestion rows create no member',async()=>{
 const f=fixture();const body={requestId,rows:[{...row(1),verifiedOwnership:false},{...row(2,'bad')},
  {...row(3,'0780000817'),candidateId:'candidate-valid'},row(4,'0780000816')]};
 const result=await f.service.importMembers(actor,body);
 assert.deepEqual(result.results.map(x=>x.status),['needs_verification','invalid','candidate_changed','duplicate_in_batch']);
 assert.equal(f.state.members.length,0);assert.equal(f.state.attestations.length,0);
});
test('valid suggestion remains a hint and an existing member is not rematched',async()=>{
 const f=fixture();f.state.members.push({id:'member-1',groupId:'group-1',phone:'+250780000816'});
 const out=await f.service.importMembers(actor,{requestId,rows:[{...row(1),candidateId:'candidate-valid'}]});
 assert.equal(out.results[0].status,'already_registered');assert.equal(f.state.events.length,0);assert.equal(f.state.attestations.length,1);
});
test('same last three digits cannot retarget a suggested payer to another full number',async()=>{
 const f=fixture(),out=await f.service.importMembers(actor,{requestId,rows:[{...row(1,'0781000816'),candidateId:'candidate-valid'}]});
 assert.equal(out.results[0].status,'candidate_changed');assert.equal(f.state.members.length,0);
});
test('receipt failure rolls back member, attestation and rematch',async()=>{
 const f=fixture();f.fail=true;await assert.rejects(f.service.importMembers(actor,{requestId,rows:[row(1)]}),/synthetic failure/);
 assert.deepEqual(f.state,{members:[],events:[],receipts:[],attestations:[]});
});
