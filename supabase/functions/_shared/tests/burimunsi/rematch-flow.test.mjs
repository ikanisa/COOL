import test from 'node:test';import assert from 'node:assert/strict';
import {ContributionService} from '../../domain/burimunsi/contribution-service.js';
import {processRematchBatch} from '../../domain/burimunsi/rematch-worker.js';
import {BuriError} from '../../domain/burimunsi/errors.js';
import {parseReceipt} from '../../domain/burimunsi/receipt.js';
import {member,identity,policy,profile,fullSource} from './fixtures.mjs';
const ID='df9a9625-2e23-4c5a-afb3-c0f0eb7c6d03';
/** Test-only durable-state model. The actual ContributionService and worker
 * execute; SQL commits/locks/RLS, process death and the real ledger do NOT. */
class Flow {
 constructor(){
  this.state={job:{id:ID,groupId:'group-1',memberId:'member-1',policyVersion:policy.approvedVersion,state:'queued',owner:null,leaseVersion:0,attempt:0,maxAttempts:4},
   target:null,targetOutcome:null,after:false,entries:[],members:[structuredClone(member)],identities:[structuredClone(identity)],
   receipt:{...parseReceipt(fullSource,profile),id:'tx-1',groupId:'group-1',version:1,state:'unallocated',hasConflict:false}};
  this.requests=[];this.calls=[];this.policy=structuredClone(policy);this.hold=false;this.failCheckpoint=false;this.loseCommitReply=false;this.loseAdvanceReply=false;this.failFailure=false;
  this.service=new ContributionService({store:this,groupId:'group-1'});
 }
 async inCanonicalTransaction(fn){
  const s=structuredClone(this.state);
  const tx={assertAutomaticAdmission:async c=>{this.calls.push('admission');if(this.hold)throw new BuriError('processing_on_hold',503);assert.equal(c.work.jobId,ID);assert.equal(c.work.memberId,s.job.memberId);assert.equal(c.work.leaseVersion,s.job.leaseVersion);},
   lockReceipt:async()=>s.receipt,loadApprovedPolicy:async()=>this.policy,listEligibleMembers:async()=>s.members,listVerifiedIdentities:async()=>s.identities,
   postCanonicalContribution:async cmd=>{
    this.calls.push('post');assert.equal(cmd.memberId,s.job.memberId);assert.equal(s.entries.length,0);this.requests.push(cmd.requestId);
    const result={transactionId:'tx-1',memberId:cmd.memberId,amountRwf:s.receipt.amountRwf,currency:'RWF',ledgerEntryId:'ledger-1',memberBalanceRwf:s.receipt.amountRwf,groupBalanceRwf:s.receipt.amountRwf};
    s.entries.push(result);s.receipt.state='posted';s.receipt.memberId=cmd.memberId;return result;
   },readCanonicalResult:async()=>s.entries[0],
   retainAutomaticOutcome:async cmd=>{this.calls.push('outcome');s.targetOutcome=cmd.result.ledgerEntryId?'posted':cmd.result.state;if(this.failCheckpoint)throw new BuriError('checkpoint_failed',503);}
  };
  const result=await fn(tx);this.state=s;this.calls.push('commit');
  if(this.loseCommitReply){this.loseCommitReply=false;throw Error('simulated lost commit reply');}
  return result;
 }
 async claimNext({owner}){
  if(this.hold)throw new BuriError('processing_on_hold',503);
  const j=this.state.job;if(['completed','running','dead_letter'].includes(j.state))return null;
  j.state='running';j.owner=owner;j.leaseVersion++;j.attempt++;return {...j};
 }
 async nextTarget(){if(this.state.after){this.state.job.state='completed';return null;}this.state.target='tx-1';return {transactionId:'tx-1',outcome:this.state.targetOutcome};}
 async advanceTarget(){
  assert.notEqual(this.state.targetOutcome,null);const outcome=this.state.targetOutcome;
  this.state.after=true;this.state.target=null;this.state.targetOutcome=null;this.calls.push('advance');
  if(this.loseAdvanceReply){this.loseAdvanceReply=false;throw Error('simulated lost cursor reply');}
  return {applied:true,replayed:false,outcome};
 }
 async yieldJob(){this.state.job.state='queued';this.state.job.attempt=0;return {applied:true};}
 async failJob(){if(this.failFailure)throw Error('checkpoint unavailable');this.state.job.state=this.state.job.attempt>=4?'dead_letter':'retry';return {applied:true,state:this.state.job.state};}
 run(options={}){return processRematchBatch({store:this,contributions:this.service,groupId:'group-1',owner:'worker-1',...options});}
}
test('enrollment rematch uses existing verified full identity and canonical writer',async()=>{const f=new Flow(),r=await f.run();assert.equal(r.postedObservations,1);assert.equal(r.completed,1);assert.equal(f.state.entries.length,1);assert.deepEqual(f.calls.slice(-4),['admission','outcome','commit','advance']);});
test('outcome checkpoint failure rolls back the synthetic financial transaction',async()=>{const f=new Flow();f.failCheckpoint=true;const r=await f.run({limit:1});assert.equal(r.retry,1);assert.equal(f.state.entries.length,0);assert.equal(f.state.targetOutcome,null);assert.equal(f.state.after,false);});
test('lost canonical commit reply resumes retained outcome without a second post',async()=>{const f=new Flow();f.loseCommitReply=true;const first=await f.run({limit:1});assert.equal(first.retry,1);assert.equal(f.state.entries.length,1);assert.equal(f.state.targetOutcome,'posted');const next=await f.run();assert.equal(next.resumedOutcomes,1);assert.equal(f.requests.length,1);assert.equal(f.state.job.state,'completed');});
test('lost cursor acknowledgement does not reprocess target',async()=>{const f=new Flow();f.loseAdvanceReply=true;await f.run({limit:1});assert.equal(f.state.after,true);await f.run();assert.equal(f.requests.length,1);assert.equal(f.state.entries.length,1);});
test('bounded slice yields durable progress instead of consuming retry budget',async()=>{const f=new Flow();const r=await f.run({limit:1,targetsPerJob:1});assert.equal(r.yielded,1);assert.equal(f.state.job.attempt,0);const r2=await f.run();assert.equal(r2.completed,1);assert.equal(f.requests.length,1);});
test('member enrollment alone cannot credit a matching display name or number',async()=>{const f=new Flow();f.state.identities=[];const r=await f.run();assert.equal(r.unallocated,1);assert.equal(f.state.entries.length,0);});
test('masked payer suffix cannot authorize historical rematch',async()=>{const f=new Flow();f.state.receipt.fullPayerPhone=null;assert.equal((await f.run()).unallocated,1);assert.equal(f.state.entries.length,0);});
test('ownership starting after the receipt time cannot claim historical savings',async()=>{const f=new Flow();f.state.identities[0].validFrom='2099-01-01T00:00:00Z';assert.equal((await f.run()).unallocated,1);assert.equal(f.state.entries.length,0);});
test('inactive competing owner does not resolve overlapping identity ambiguity',async()=>{const f=new Flow();f.state.identities.push({...f.state.identities[0],id:'identity-2',memberId:'member-2'});f.state.members.push({...member,id:'member-2',active:false});assert.equal((await f.run()).unallocated,1);assert.equal(f.state.entries.length,0);});
test('valid identity for another member is not assigned to the newly enrolled member',async()=>{const f=new Flow();f.state.job.memberId='member-2';assert.equal((await f.run()).unallocated,1);assert.equal(f.state.entries.length,0);});
test('member deactivation before processing prevents automatic credit',async()=>{const f=new Flow();f.state.members[0].active=false;assert.equal((await f.run()).unallocated,1);assert.equal(f.state.entries.length,0);});
test('policy drift stops work without advancing an unprocessed target',async()=>{const f=new Flow();f.policy.approvedVersion='changed';const r=await f.run();assert.equal(r.stopped,true);assert.equal(f.state.after,false);assert.equal(f.state.entries.length,0);});
for(const [key,value] of [['hasConflict',true],['state','reversed']])test('unsupported/conflicted record is skipped without compensation: '+key,async()=>{const f=new Flow();f.state.receipt[key]=value;assert.equal((await f.run()).skipped,1);assert.equal(f.state.entries.length,0);});
test('processing state is retried, never assumed unallocated',async()=>{const f=new Flow();f.state.receipt.state='processing';const r=await f.run({limit:1});assert.equal(r.retry,1);assert.equal(f.state.after,false);assert.equal(f.state.entries.length,0);});
test('failure checkpoint outage stops batch and leaves target retained',async()=>{const f=new Flow();f.failCheckpoint=true;f.failFailure=true;const r=await f.run();assert.equal(r.checkpointFailed,1);assert(r.stopped);assert.equal(f.state.target,'tx-1');assert.equal(f.state.entries.length,0);});
test('worker cannot count a fabricated response without retained canonical outcome',async()=>{const f=new Flow();f.service={automaticallyAllocate:async()=>({ledgerEntryId:'invented'})};const r=await f.run({limit:1});assert.equal(r.retry,1);assert.equal(r.postedObservations,0);assert.equal(f.state.after,false);});
for(const options of [{limit:0},{limit:21},{targetsPerJob:101},{targetsPerJob:0},{leaseMs:1000}])test('batch rejects unbounded or invalid options '+JSON.stringify(options),async()=>{const f=new Flow();await assert.rejects(f.run(options),/invalid_worker_config/);assert.equal(f.state.job.state,'queued');});
