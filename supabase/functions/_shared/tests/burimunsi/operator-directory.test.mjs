// Adapter orchestration with explicit SQL/managed-session doubles. The actual
// PostgreSQL function, RLS and approval guard run in retained SQL qualification.
import test from 'node:test';import assert from 'node:assert/strict';
import {PostgresOperatorDirectory} from '../../domain/burimunsi/postgres-operator-directory.js';
const principal='approved-shared-user',phone='+250780000002';
function fixture(){
 const state={allowed:true,rows:[{principal_user_id:principal}],role:'admin',calls:[],revoked:false};
 const work={assert:async()=>{if(state.revoked)throw Error('work_revoked');}};
 const db={applicationWork:work},managedSessions={current:async(sql,actor)=>{
  state.parent={sql,actor};return {sharedRole:state.role};}};
 const sql={unsafe:async(q,args)=>{state.calls.push({q,args});if(q.startsWith('SELECT private.'))return [{allowed:state.allowed}];return state.rows;}};
 const directory=new PostgresOperatorDirectory({db,groupId:'group-1',managedSessions});
 const account={groupId:'group-1',principalUserId:principal,phone,role:'staff',capabilities:['records.read']};
 const input={groupId:'group-1',phone,actorId:'current-admin'};
 return {directory,db,sql,state,account,input,resolve:()=>directory.resolveStaff(sql,input),check:()=>directory.assertInTransaction(sql,account)};
}
test('staff resolves only the exact pre-approved phone inside the caller transaction',async()=>{
 const f=fixture();assert.deepEqual(await f.resolve(),{id:principal});assert.equal(f.state.parent.sql,f.sql);
 assert.equal(f.state.parent.actor,'current-admin');assert.deepEqual(f.state.calls[0].args,['group-1',phone]);
 assert(!f.state.calls.some(c=>/INSERT|UPDATE|DELETE/.test(c.q)));
});
for(const role of ['staff','operator',undefined])test('shared '+role+' cannot resolve a new native staff principal',async()=>{
 const f=fixture();f.state.role=role;await assert.rejects(f.resolve(),/access_denied/);assert.equal(f.state.calls.length,0);
});
for(const rows of [[],[{principal_user_id:principal},{principal_user_id:'another'}]])test('missing/ambiguous operator approval never chooses an identity '+rows.length,async()=>{
 const f=fixture();f.state.rows=rows;await assert.rejects(f.resolve(),/access_denied/);
});
test('revoked owner approval denies current native authority',async()=>{
 const f=fixture();await f.check();f.state.allowed=false;await assert.rejects(f.check(),/access_denied/);
});
test('approval predicate receives the current phone, principal, role and capability ceiling',async()=>{
 const f=fixture();await f.check();assert.deepEqual(f.state.calls[0].args,['group-1',principal,phone,'staff',['records.read']]);
});
for(const mutate of [f=>{f.account.groupId='other';},f=>{f.input.groupId='other';},f=>{f.input.phone='0780000002';},f=>{f.state.revoked=true;}])
 test('foreign scope, noncanonical identity or revoked work stays closed',async()=>{
  const f=fixture();mutate(f);await assert.rejects(f.account.groupId==='other'?f.check():f.resolve());
 });
test('replaced request work cannot read an operator approval',async()=>{
 const f=fixture();f.db.applicationWork={assert:async()=>{}};await assert.rejects(f.check(),/request_not_admitted/);
 assert.equal(f.state.calls.length,0);
});
