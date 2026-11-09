import assert from 'node:assert/strict';
import {PostgresRematchJobStore,rematchRequestId} from '../../domain/burimunsi/postgres-rematch-job-store.js';
export const ID='df9a9625-2e23-4c5a-afb3-c0f0eb7c6d03',REQUEST='b7d39761-135b-5423-acd1-59eb0348174f',NOW=1794000000000;
/** SQL recorder, not a SQL interpreter. It verifies adapter statements and
 * supplied arguments; it cannot establish actual RLS, lock or trigger behavior. */
export function sqlFixture() {
 const calls=[];
 const row={id:ID,collection_id:'group-1',receiving_account_id:'wallet-1',member_id:'member-1',request_id:REQUEST,cause:'enrollment',
  cutoff_at:String(NOW-1000),after_transaction_id:'',target_transaction_id:'tx-1',target_outcome:null,target_reason:null,
  policy_version:'identity-v1',lease_owner:'worker-1',lease_version:'2',lease_expires_at:String(NOW+180000),attempt:1,max_attempts:4,
  processed_count:'0',lease_start_count:'0',state:'running'};
 const state={now:NOW,hold:false,policy:'identity-v1',enabled:true,wallet:'wallet-1',member:'member-1',memberActive:1,
   access:'active',affected:true,candidates:[{id:'tx-1'}],failState:'retry',lineage:true,
   outcome:{groupId:'group-1',transactionId:'tx-1',state:'unallocated',hasConflict:false},row};
 const sql={unsafe:async(text,values=[])=>{
  calls.push({text,values});
  if(text.startsWith('SELECT floor'))return [{now_ms:String(state.now)}];
  if(text.startsWith('SELECT collection_id'))return [{collection_id:'group-1',receiving_account_id:state.wallet,enabled:state.enabled}];
  if(text.startsWith('SELECT m.user_id'))return [{user_id:state.member,active:state.memberActive,access_status:state.access}];
  if(text.startsWith('SELECT *')){if(state.expireOnLock)state.now=NOW+180001;return state.missing?[]:[row];}
  if(text.startsWith('WITH candidate'))return state.missing?[]:[row];
  if(text.startsWith('SELECT t.id'))return state.candidates;
  if(text.includes('RETURNING state'))return state.affected?[{state:state.failState}]:[];
  if(text.includes('RETURNING id'))return state.affected?[{id:ID}]:[];
  return [];
 }};
 const authority={groupId:'group-1',write:async fn=>{calls.push({event:'begin'});try{const r=await fn(sql);calls.push({event:'commit'});return r;}catch(e){calls.push({event:'rollback'});throw e;}}};
 const admission={assertInTransaction:async(tx,cmd)=>{assert.equal(tx,sql);assert.equal(cmd.kind,'rematch');calls.push({event:'admission'});if(state.expireOnAdmission)state.now=NOW+180001;return {processingEnabled:!state.hold,policyVersion:state.policy};}};
 const canonical={outcome:async(tx,cmd)=>{assert.equal(tx,sql);assert.equal(cmd.groupId,'group-1');calls.push({event:'outcome'});return state.outcome;}};
 const store=new PostgresRematchJobStore({authority,admission,canonical});
 const witness={jobId:ID,owner:'worker-1',leaseVersion:2};
 const work={kind:'rematch',...witness,memberId:'member-1',policyVersion:'identity-v1'};
 return {store,row,state,calls,sql,authority,admission,canonical,witness,work};
}
export const event={groupId:'group-1',memberId:'member-1',requestId:REQUEST,cause:'enrollment'};
export async function command(f,result={state:'unallocated',transactionId:'tx-1',reason:'no_verified_identity'}) {
 return {groupId:'group-1',transactionId:'tx-1',requestId:await rematchRequestId('group-1',ID,'tx-1'),work:f.work,result};
}
