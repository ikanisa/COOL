// Real adapters; SQL filtering/locking/provider helpers simulated. Not PG qualification.
import test from 'node:test';import assert from 'node:assert/strict';
import {authorityFixture,I} from './posting-authority-fixture.mjs';
import {PostgresWorkerAuthority} from '../../domain/burimunsi/postgres-worker-authority.js';
import {PostgresIdentityDirectory} from '../../domain/burimunsi/postgres-identity-directory.js';
import {PostgresProcessingAdmission} from '../../domain/burimunsi/postgres-processing-admission.js';
import {matchExistingMember} from '../../domain/burimunsi/policy.js';
import {PARSER_VERSION} from '../../domain/burimunsi/receipt.js';
import {sha256} from '../../domain/burimunsi/values.js';
function workerFixture(){const f=authorityFixture(),work=f.db.applicationWork;work.kind='jobs';
 const tuple=[I.request,1,'a'.repeat(64)],state={leaseCalls:0,denyLeaseAt:0,grantPresent:true};
 const grant={id:I.grant,version:1,principal_user_id:I.principal,principal_session_id:I.canonical,
 source_sha256:tuple[2],policy_version:'policy-1',revoked_at:null,approved_at:I.now-1000,expires_at:I.now+60000,now_ms:String(I.now),work_kinds:['receipt','rematch']};
 const original=f.sql.unsafe;f.sql.unsafe=async(q,v)=>q.includes('FROM private.burimunsi_worker_grants')?
  state.grantPresent?[structuredClone(grant)]:[]:original(q,v);
 const jobs={assertPostingLease:async(sql,c)=>{assert.equal(sql,f.sql);assert.equal(c.groupId,I.group);assert.equal(c.transactionId,'transaction-1');
  state.leaseCalls++;if(state.denyLeaseAt===state.leaseCalls)throw Error('lease unavailable');}};
 const runtime=new PostgresWorkerAuthority({authority:f.store,jobs,applicationWorkTuple:()=>tuple});
 const command={mode:'automatic',groupId:I.group,receiptId:'transaction-1',memberId:'member-1',requestId:I.request,policyVersion:'policy-1',
  work:{kind:'receipt',jobId:I.issued,owner:'worker-1',leaseVersion:1}};
 return {...f,tuple,grant,state,jobs,runtime,command,run:()=>f.store.write(sql=>runtime.assertInTransaction(sql,{command,phase:'before_posting'}))};
}
test('worker retains unchanged financial guard and rechecks durable lease',async()=>{const f=workerFixture();try{
 const p=await f.run();assert.equal(p.kind,'admitted_worker');assert.equal(p.principalSessionId,I.canonical);
 assert.equal(f.state.leaseCalls,2);assert.equal(f.h.guards.length,2);assert.equal(f.h.guards[0].values[6],2);assert.equal(f.h.guards[0].values[8],300);
}finally{f.close();}});
for(const [field,value]of [['principal_user_id','other'],['principal_session_id',I.issued],['source_sha256','b'.repeat(64)],
 ['policy_version','wrong'],['revoked_at',1],['expires_at',I.now],['approved_at',I.now+1],['work_kinds',[]]])
 test('worker grant rejects '+field,async()=>{const f=workerFixture();try{f.grant[field]=value;await assert.rejects(f.run());}finally{f.close();}});
test('no implicit worker authority without grant',async()=>{const f=workerFixture();try{f.state.grantPresent=false;await assert.rejects(f.run(),/worker_financial_authority_required/);}finally{f.close();}});
for(const at of [1,2])test('worker lease failure blocks phase '+at,async()=>{const f=workerFixture();try{f.state.denyLeaseAt=at;await assert.rejects(f.run());}finally{f.close();}});
test('canonical financial permission denial cannot be bypassed',async()=>{const f=workerFixture();try{f.h.allowed=false;await assert.rejects(f.run(),/posting_financial_authority_denied/);}finally{f.close();}});
test('grant rotation during guard invalidates proof',async()=>{const f=workerFixture();try{f.h.afterGuard=()=>{f.grant.version++;};await assert.rejects(f.run(),/posting_authority_changed/);}finally{f.close();}});
test('HTTP admission cannot become worker admission',async()=>{const f=workerFixture();try{f.db.applicationWork.kind='http_admin';await assert.rejects(f.run(),/worker_admission_required/);}finally{f.close();}});
test('changed fence epoch stops worker',async()=>{const f=workerFixture();try{f.tuple[1]++;await assert.rejects(f.run(),/worker_admission_required/);}finally{f.close();}});
test('rematch member bound to work claim',async()=>{const f=workerFixture();try{
 f.command.work={...f.command.work,kind:'rematch',memberId:'member-1',policyVersion:'policy-1'};assert.equal((await f.run()).kind,'admitted_worker');
 f.command.work.memberId='other-member';await assert.rejects(f.run(),/identity_changed/);
}finally{f.close();}});
const now=1794045600000;
function identityFixture(){const state={queries:[],policy:{collection_id:'group-1',identity_enabled:true,processing_enabled:true,scheduler_enabled:true,
 revoked_at:null,approved_version:'policy-1',approved_at:now-10000,expires_at:now+60000,now_ms:String(now),native_parser_version:PARSER_VERSION},
 members:[{id:'member-1',collection_id:'group-1',active:1,access_status:'active'}],proofs:[]};
 const db={applicationWork:{assert:async()=>{}}},sql={unsafe:async(q,v)=>{state.queries.push({q,v});return structuredClone(q.includes('burimunsi_integration_policies')?[state.policy]:q.includes('app.memberships')?state.members:state.proofs);}};
 const directory=new PostgresIdentityDirectory({db,groupId:'group-1'});
 const proof={id:'proof-1',member_id:'member-1',collection_id:'group-1',policy_version:'policy-1',state:'verified',revoked_at:null,
 phone:'+250780000001',approved_by:'owner-1',approved_at:now-2000,now_ms:String(now),purpose:'own_contributions',verification_method:'collect_owner_review',source_reference:'fixture-evidence-1',
 evidence_sha256:'a'.repeat(64),valid_from:now-10000,valid_until:null};state.proofs=[proof];
 return {state,db,sql,directory,proof};
}
test('effective-dated identity matches without display name inference',async()=>{const f=identityFixture();const policy=await f.directory.policy(f.sql,'group-1');
 const result=matchExistingMember({groupId:'group-1',at:new Date(now).toISOString(),fullPayerPhone:'+250780000001',name:'irrelevant'},
  await f.directory.members(f.sql,'group-1'),await f.directory.verified(f.sql,'group-1'),policy);
 assert.equal(result.kind,'matched');assert.equal(result.memberId,'member-1');
});
test('inactive competing owner remains ambiguous',async()=>{const f=identityFixture();f.state.proofs.push({...f.proof,id:'proof-2',member_id:'member-2'});
 f.state.members.push({id:'member-2',collection_id:'group-1',active:0,access_status:'active'});
 const result=matchExistingMember({groupId:'group-1',at:new Date(now).toISOString(),fullPayerPhone:'+250780000001'},
  await f.directory.members(f.sql,'group-1'),await f.directory.verified(f.sql,'group-1'),await f.directory.policy(f.sql,'group-1'));
 assert.equal(result.reason,'ambiguous_identity');assert(!f.state.queries.find(r=>r.q.includes('burimunsi_identity_proofs')).q.includes('JOIN app.memberships'));
});
for(const [field,value]of [['identity_enabled',false],['revoked_at',now],['expires_at',now],['approved_at',now+1]])test('disabled/stale identity policy '+field,async()=>{
 const f=identityFixture();f.state.policy[field]=value;assert.deepEqual(await f.directory.verified(f.sql,'group-1'),[]);
});
for(const [field,value]of [['phone','0780000001'],['verification_method','name_match'],['purpose','third_party'],
 ['evidence_sha256','invalid'],['source_reference',''],['valid_until',now-10001],['valid_from',8640000000000001],['approved_at',now+1],['member_id','invalid/member']])test('invalid identity proof rejects '+field,async()=>{
 const f=identityFixture();f.proof[field]=value;await assert.rejects(f.directory.verified(f.sql,'group-1'));
});
test('duplicate proof IDs are not a complete snapshot',async()=>{const f=identityFixture();f.state.proofs.push({...f.proof});await assert.rejects(f.directory.verified(f.sql,'group-1'));});
test('row limit does not silently drop competing owners',async()=>{const f=identityFixture();f.directory.maxRows=1;f.state.proofs.push({...f.proof,id:'other'});await assert.rejects(f.directory.verified(f.sql,'group-1'),/identity_snapshot_limit/);});
test('identity query cannot cross group',async()=>{const f=identityFixture();await assert.rejects(f.directory.members(f.sql,'other'),/access_denied/);assert.equal(f.state.queries.length,0);});
async function processingFixture(){const f=identityFixture();const profile={date_format:'YMD_HMS',utc_offset_minutes:120,sender_allowlist:['M-Money']};
 const wallet={provider:'mtn_momo',profile_version:'profile-1',profile_json:JSON.stringify(profile)};
 Object.assign(f.state.policy,{provider_profile_version:'profile-1',provider_profile_sha256:await sha256(wallet.profile_json)});
 const original=f.sql.unsafe;f.sql.unsafe=async(q,v)=>q.includes('SELECT w.*')?[structuredClone(wallet)]:original(q,v);
 const env={MOMO_PROCESSING_PAUSED:'false'},admission=new PostgresProcessingAdmission({db:f.db,groupId:'group-1',env,validateProviderProfile:()=>profile});
 return {...f,profile,wallet,env,admission,run:()=>admission.assertInTransaction(f.sql,{groupId:'group-1',profileVersion:'profile-1'})};
}
test('approved canonical profile maps sender/timezone to native parser',async()=>{const f=await processingFixture(),p=await f.run();assert.equal(p.profile.offsetMinutes,120);assert.deepEqual(p.profile.senders,['M-Money']);assert.equal(p.policyVersion,'policy-1');
 assert.deepEqual(f.state.queries[0].v,['group-1']);
});
for(const value of [undefined,null,true,false,'true','FALSE',''])test('processing pause is fail-closed '+String(value),async()=>{const f=await processingFixture();f.env.MOMO_PROCESSING_PAUSED=value;await assert.rejects(f.run(),/processing_on_hold/);});
test('same profile version with changed bytes is denied',async()=>{const f=await processingFixture();f.wallet.profile_json+=' ';await assert.rejects(f.run(),/profile_changed/);});
test('unsupported carrier cannot be enabled by approval alone',async()=>{const f=await processingFixture();f.wallet.provider='airtel_money';await assert.rejects(f.run(),/profile_changed/);});
test('unsupported date grammar is not guessed',async()=>{const f=await processingFixture();f.profile.date_format='DMY_HMS';await assert.rejects(f.run(),/profile_changed/);});
test('pause during profile read prevents admission',async()=>{const f=await processingFixture();const original=f.sql.unsafe;
 f.sql.unsafe=async(q,v)=>{const r=await original(q,v);if(q.includes('SELECT w.*'))f.env.MOMO_PROCESSING_PAUSED='true';return r;};await assert.rejects(f.run(),/processing_on_hold/);
});
