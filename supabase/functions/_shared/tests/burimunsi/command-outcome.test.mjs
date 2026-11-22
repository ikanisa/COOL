import test from 'node:test';
import assert from 'node:assert/strict';
import {COMMAND_OUTCOME_SQL,readCommandOutcome} from '../../domain/burimunsi/postgres-command-outcome.js';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';
import {RecordsService} from '../../domain/burimunsi/records-service.js';
const actorId='10000000-0000-4000-8000-000000000001',requestId='30000000-0000-4000-8000-000000000001';
const query={groupId:'qa-group',actorId,requestId,principalUserId:'qa-principal'};
const row={collection_id:query.groupId,actor_id:actorId,request_id:requestId,operation:'burimunsi.allocate',financial_state:'posted'};
for(const state of ['posted','reversed','corrected'])test('command outcome separates historical commit from '+state,async()=>{
 const got=await readCommandOutcome({unsafe:async()=>[{...row,financial_state:state}]},query);
 assert.equal(got.state,'committed');assert.equal(got.financialState,state);
 assert.deepEqual(Object.keys(got).sort(),['actorId','financialState','groupId','operation','requestId','state']);
});
test('nonfinancial commit is not a financial posting',async()=>{
 const got=await readCommandOutcome({unsafe:async()=>[{...row,operation:'burimunsi.enroll',financial_state:'not_applicable'}]},query);
 assert.equal(got.financialState,'not_applicable');
});
test('absent retained command is not rejected',async()=>assert.equal(await readCommandOutcome({unsafe:async()=>[]},query),null));
test('SQL parameters carry original request and fresh immutable principal',async()=>{
 await readCommandOutcome({unsafe:async(sql,params)=>{assert.equal(sql,COMMAND_OUTCOME_SQL);assert.deepEqual(params,['qa-group',actorId,requestId,'qa-principal']);return [];}},query);
});
for(const [key,value] of Object.entries({collection_id:'other',actor_id:'other',request_id:'other',operation:'unrecognized',financial_state:'inconsistent'}))
 test('reader rejects corrupt '+key,async()=>assert.rejects(readCommandOutcome({unsafe:async()=>[{...row,[key]:value}]},query),/command_outcome_inconsistent/));
for(const combination of [{operation:'burimunsi.enroll',financial_state:'posted'},{operation:'burimunsi.allocate',financial_state:'not_applicable'}])
 test('reader rejects operation/effect mismatch '+combination.operation,async()=>assert.rejects(readCommandOutcome({unsafe:async()=>[{...row,...combination}]},query),/command_outcome_inconsistent/));
test('multiple canonical links cannot be accepted as one success',async()=>assert.rejects(readCommandOutcome({unsafe:async()=>[row,row]},query),/command_outcome_inconsistent/));
test('missing principal cannot broaden SQL authority',async()=>assert.rejects(readCommandOutcome({unsafe:async()=>{assert.fail('must not query');}}, {...query,principalUserId:null})));
for(const replica of [true,null,undefined])test('status refuses replica or unproven connection '+replica,async()=>{
 const store=new PostgresRecordsStore({authority:{groupId:'qa-group',session:async()=>null,read:fn=>fn({unsafe:async()=>[{replica}]})},sourceReader:{revision(){},page(){},detail(){}}});
 await assert.rejects(store.withCommandSnapshot(()=>assert.fail('must not read a command')),/command_primary_required/);
});
test('primary-only status uses exactly one admitted read snapshot',async()=>{
 let reads=0,queries=[];
 const store=new PostgresRecordsStore({authority:{groupId:'qa-group',session:async()=>null,read:fn=>{reads++;return fn({unsafe:async(sql)=>{queries.push(sql);return sql.includes('pg_is_in_recovery')?[{replica:false}]:[row];}});}},sourceReader:{revision(){},page(){},detail(){}}});
 assert.equal((await store.withCommandSnapshot(tx=>tx.readCommandOutcome(query))).state,'committed');
 assert.equal(reads,1);assert.equal(queries.length,2);
});
function service(){
 const actor={id:actorId,sessionId:'20000000-0000-4000-8000-000000000002',principalUserId:'qa-principal',groupId:'qa-group',active:true,revoked:false,role:'staff',capabilities:['records.read'],expiresAt:10000};
 const state={actor,result:{...query,operation:'burimunsi.allocate',state:'committed',financialState:'posted'},reads:0,writes:0};
 const tx={reloadActor:async()=>state.actor,loadBinding:async()=>null,readCommandOutcome:async q=>{assert.equal(q.principalUserId,'qa-principal');return state.result;}};
 const svc=new RecordsService({groupId:'qa-group',clock:()=>2000,cursor:{create(){},read(){}},store:{withReadSnapshot:()=>assert.fail('must use command snapshot'),withCommandSnapshot:fn=>{state.reads++;return fn(tx);}}});
 return {svc,state,actor};
}
test('new session may read old principal-scoped commit without write capability',async()=>{
 const {svc,state,actor}=service();const got=await svc.commandStatus(actor,requestId);
 assert.deepEqual(got,{contractVersion:2,requestId,groupId:'qa-group',actorId,state:'committed',operation:'burimunsi.allocate',financialState:'posted'});
 assert.equal(state.reads,1);
});
for(const change of [{revoked:true},{active:false},{expiresAt:1},{capabilities:[]},{groupId:'other'}])test('current authority blocks status '+JSON.stringify(change),async()=>{
 const {svc,state,actor}=service();state.actor={...actor,...change};await assert.rejects(svc.commandStatus(actor,requestId));
});
test('missing receipt returns a scoped unresolved v2 envelope',async()=>{
 const {svc,state,actor}=service();state.result=null;
 assert.deepEqual(await svc.commandStatus(actor,requestId),{contractVersion:2,requestId,groupId:'qa-group',actorId,state:'pending',financialState:'unresolved'});
});
for(const change of [{requestId:'other'},{state:'rejected'},{financialState:'unknown'},{operation:'other'},{actorId:'other'},{groupId:'other'}])test('service refuses fabricated outcome '+JSON.stringify(change),async()=>{
 const {svc,state,actor}=service();state.result={...state.result,...change};await assert.rejects(svc.commandStatus(actor,requestId),/command_scope_violation/);
});
test('SQL is read-only and never projects historical balance as current',()=>{
 assert.doesNotMatch(COMMAND_OUTCOME_SQL,/\b(?:INSERT|UPDATE|DELETE|TRUNCATE)\b/);
 assert.doesNotMatch(COMMAND_OUTCOME_SQL,/balance_after|BalanceRwf/);
 assert.match(COMMAND_OUTCOME_SQL,/origin\.principal_user_id=\$4/);
});
