import test from 'node:test';
import assert from 'node:assert/strict';
import {PostgresNativeAuthStore} from '../../domain/burimunsi/postgres-auth-store.js';
import {readRecoveryProof} from '../../domain/burimunsi/postgres-operation-recovery.js';
import {projectRecoveredOutcome} from '../../domain/burimunsi/operation-recovery.js';
import {NativeAuthService} from '../../domain/burimunsi/auth-service.js';
import {createNativeHandler} from '../../domain/burimunsi/http.js';

const uuid=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const groupId='group-1',requestId=uuid(8),originId=uuid(2),currentId=uuid(3),digest='a'.repeat(64),now=1794132000000;
const actor={id:uuid(1),sessionId:currentId,principalUserId:'principal-1',installationId:uuid(4),groupId,
 role:'admin',active:true,revoked:false,expiresAt:now+60000,capabilities:['records.read','staff.manage']};
const input={groupId,actorId:actor.id,sessionId:currentId,requestId,originDigest:digest,operation:'burimunsi.staff.create'};
function fixture() {
 const state={receipt:null,accounts:0,audits:0,sql:[],changes:{}};
 const row={
   origin_session_id:originId,origin_group_id:groupId,origin_actor_id:actor.id,origin_principal_id:actor.principalUserId,
   origin_installation_id:actor.installationId,origin_grant_id:uuid(5),origin_grant_version:1,origin_token_hash:digest,origin_created_at:now-60000,
   current_session_id:currentId,current_group_id:groupId,current_actor_id:actor.id,current_principal_id:actor.principalUserId,
   current_installation_id:actor.installationId,current_grant_id:uuid(5),current_grant_version:1,
 };
 const sql={unsafe:async(q,p=[])=>{
   state.sql.push(q);
   if(q.includes('FROM private.burimunsi_sessions c'))return state.changes.missingOrigin?[]:[{...row,...state.changes}];
   if(q.includes('SELECT collection_id,actor_id,request_id,session_id,operation,created_at'))return state.receipt?[state.receipt]:[];
   if(q.includes('SELECT session_id,operation,fingerprint,response'))return state.receipt?[state.receipt]:[];
   if(q.startsWith('INSERT INTO private.burimunsi_command_receipts')){
     assert.equal(state.receipt,null);
     const [collection_id,actor_id,request_id,session_id,operation,fingerprint]=p;
     const tombstone=operation.startsWith('burimunsi.staff.cancelled.');
     const response=tombstone?{}:p[6],created_at=tombstone?p[6]:p[7];
     if(tombstone)assert.match(q,/'{}'::jsonb/);
     state.receipt={collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at,cancellation_marker_valid:tombstone};
     return [];
   }
   if(q.includes('INSERT INTO private.burimunsi_accounts')){state.accounts++;return [];}
   if(q.includes('INSERT INTO private.burimunsi_audit')){state.audits++;return [];}
   throw Error('Unexpected synthetic SQL: '+q.slice(0,90));
 }};
 const db={transaction:async()=>{},context:async()=>{},readContext:async()=>{},applicationWork:{assert:async()=>{}}};
 const store=new PostgresNativeAuthStore({db,groupId,createOperatorPrincipal:async()=>({id:'principal-2'}),clock:()=>now});
 let queue=Promise.resolve();
 store.write=fn=>{const next=queue.then(()=>fn(sql));queue=next.catch(()=>{});return next;};
 store.read=fn=>fn(sql);
 let current=actor;
 store.session=async(_sql,{id})=>({...current,sessionId:id});
 const setActor=value=>{current=value};
 const command={groupId,actorId:actor.id,actorSessionId:originId,requestId,action:'create',
   fingerprint:'b'.repeat(64),name:'Synthetic',phone:'synthetic',pinHash:{synthetic:true},capabilities:['records.read']};
 const read=async()=>{
   const proof=await readRecoveryProof(sql,{groupId,actorId:actor.id,currentSessionId:currentId,requestId,originDigest:digest});
   return projectRecoveredOutcome({proof,actor:current,groupId,requestId,originDigest:digest,now});
 };
 return {state,store,command,read,setActor};
}
test('missing receipt alone stays pending until a locked cancellation is committed',async()=>{
 const f=fixture();assert.equal((await f.read()).state,'pending');
 const out=await f.store.resolveStaffCommand(input);
 assert.equal(out.state,'cancelled');assert.equal(out.operation,input.operation);
 assert.equal((await f.read()).state,'cancelled');assert.equal(f.state.accounts,0);assert.equal(f.state.audits,1);
 assert.equal(f.state.receipt.session_id,originId);assert.equal(f.state.receipt.operation,'burimunsi.staff.cancelled.create');
 assert.deepEqual(f.state.receipt.response,{});assert.match(f.state.receipt.fingerprint,/^[a-f0-9]{64}$/);
});
test('preflight then cancellation prevents late apply of the original staff command',async()=>{
 const f=fixture();
 assert.equal(await f.store.retainedStaffCommand({groupId,actorId:actor.id,sessionId:originId,requestId,now}),null);
 await f.store.resolveStaffCommand(input);
 await assert.rejects(f.store.mutateStaff(f.command),/staff_command_cancelled/);
 assert.equal(f.state.accounts,0);assert.equal(f.state.receipt.operation,'burimunsi.staff.cancelled.create');
});
test('writer wins the lock: cancellation returns original committed outcome without replacing it',async()=>{
 const f=fixture();const [applied,resolution]=await Promise.all([f.store.mutateStaff(f.command),f.store.resolveStaffCommand(input)]);
 assert.equal(applied.applied,true);assert.equal(resolution.state,'committed');
 assert.equal(f.state.accounts,1);assert.equal(f.state.receipt.operation,input.operation);assert.equal(f.state.audits,1);
});
test('cancellation wins the lock: a concurrent writer cannot create staff',async()=>{
 const f=fixture();const [resolution,applied]=await Promise.allSettled([f.store.resolveStaffCommand(input),f.store.mutateStaff(f.command)]);
 assert.equal(resolution.value.state,'cancelled');assert.equal(applied.status,'rejected');assert.match(String(applied.reason),/staff_command_cancelled/);
 assert.equal(f.state.accounts,0);assert.equal(f.state.audits,1);
});
test('lost acknowledgement is recoverable by a read; repeated resolution is idempotent',async()=>{
 const f=fixture();await f.store.resolveStaffCommand(input);const retained=structuredClone(f.state.receipt);
 assert.equal((await f.read()).state,'cancelled');
 assert.equal((await f.store.resolveStaffCommand(input)).state,'cancelled');
 assert.deepEqual(f.state.receipt,retained);assert.equal(f.state.audits,1);assert.equal(f.state.accounts,0);
});
for(const [name,patch] of [
 ['old principal',{origin_principal_id:'other'}],['old installation',{origin_installation_id:uuid(88)}],
 ['old grant',{origin_grant_id:uuid(88)}],['old grant version',{origin_grant_version:2}],
 ['old session absent',{missingOrigin:true}],['old token',{origin_token_hash:'b'.repeat(64)}]
])test(name+' mismatch denies tombstone',async()=>{const f=fixture();Object.assign(f.state.changes,patch);await assert.rejects(f.store.resolveStaffCommand(input));assert.equal(f.state.receipt,null);assert.equal(f.state.audits,0)});
for(const [name,patch] of [
 ['staff role',{role:'staff'}],['missing capability',{capabilities:['records.read']}],['revoked session',{revoked:true}],
 ['expired session',{expiresAt:now}],['different actor',{id:uuid(90)}],['different group',{groupId:'other'}]
])test(name+' denies cancellation',async()=>{const f=fixture();f.setActor({...actor,...patch});await assert.rejects(f.store.resolveStaffCommand(input));assert.equal(f.state.receipt,null)});
test('a different operation or malformed cancellation marker is never a valid outcome',async()=>{
 const f=fixture();await f.store.resolveStaffCommand(input);
 await assert.rejects(f.store.resolveStaffCommand({...input,operation:'burimunsi.staff.reset'}),/idempotency_conflict/);
 f.state.receipt.cancellation_marker_valid=false;
 await assert.rejects(f.read(),/invalid_recovery_receipt/);
 await assert.rejects(f.store.resolveStaffCommand(input),/invalid_recovery_receipt/);
});
test('preflight returns no fabricated committed result for a cancelled command',async()=>{
 const f=fixture();await f.store.resolveStaffCommand(input);
 const hasher={hash:async()=>({}),verify:async()=>true,commandFingerprint:async()=> 'b'.repeat(64)};
 const service=new NativeAuthService({store:f.store,hasher,groupId,clock:()=>now});
 await assert.rejects(service.manageStaff({...actor,sessionId:originId},{action:'create',name:'Synthetic',phone:'0780000001',pin:'1234',capabilities:['records.read'],requestId}),/staff_command_cancelled/);
 assert.equal(f.state.accounts,0);
});
test('staff create maps only exact PostgreSQL freshness failure after transaction rejection',async()=>{
 const f=fixture();let rolledBack=false;
 f.store.write=async()=>{rolledBack=true;throw Object.assign(Error('fresh_auth_required'),{code:'42501'});};
 await assert.rejects(f.store.mutateStaff(f.command),error=>rolledBack&&error.code==='fresh_auth_required'&&error.status===403);
 for(const original of [Object.assign(Error('permission_denied'),{code:'42501'}),
   Object.assign(Error('fresh_auth_required'),{code:'XX000'})]){
  f.store.write=async()=>{throw original};
  await assert.rejects(f.store.mutateStaff(f.command),error=>error===original);
 }
 const original=Object.assign(Error('fresh_auth_required'),{code:'42501'});
 f.store.write=async()=>{throw original};
 await assert.rejects(f.store.mutateStaff({...f.command,action:'edit'}),error=>error===original);
});
test('strict HTTP route is authenticated, no-store, scoped and rejects nonstaff operations',async()=>{
 const f=fixture(),unused=async()=>{};
 const service=new NativeAuthService({store:f.store,hasher:{hash:unused,verify:unused,commandFingerprint:unused},groupId,clock:()=>now});
 const handler=createNativeHandler({auth:{login:unused,authenticate:async()=>actor,logout:unused,changePasscode:unused,manageStaff:unused,
   resolveStaffCommand:(...args)=>service.resolveStaffCommand(...args)},records:{home:unused,page:unused,detail:unused,exportLedger:unused,commandStatus:unused},
   contributions:{allocate:unused},members:{enroll:unused,setActive:unused},gateway:{status:unused,replace:unused},
   origin:'https://example.test',networkBucket:async()=>'',strictContract:true,groupId});
 const call=(body,extra='')=>handler(new Request('https://example.test/v1/burimunsi/operations/'+requestId+'/staff-resolution'+extra,{
   method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+'c'.repeat(64),'x-burimunsi-installation':actor.installationId,
    'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':uuid(10),'x-burimunsi-generation':'1','x-burimunsi-operation-origin':digest},body:JSON.stringify(body)}));
 const invalid=await call({operation:'burimunsi.allocate'});assert.equal(invalid.status,400);assert.equal(f.state.receipt,null);
 const badQuery=await call({operation:input.operation},'?x=1');assert.equal(badQuery.status,400);assert.equal(f.state.receipt,null);
 const ok=await call({operation:input.operation});assert.equal(ok.status,200);assert.equal(ok.headers.get('cache-control'),'no-store');
 const data=(await ok.json()).data;assert.equal(data.state,'cancelled');assert.equal(data.operation,input.operation);
});
