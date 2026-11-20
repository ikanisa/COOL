import test from 'node:test';import assert from 'node:assert/strict';
// BASELINE_AUTHORITY_MODULE is used only for explicit old/new regression control.
const {PostgresNativeAuthority}=await import(process.env.BASELINE_AUTHORITY_MODULE??'../../domain/burimunsi/postgres-authority.js');
for(const readOnly of [false,true])test('admission replacement during final await must roll back '+(readOnly?'read':'write'),async()=>{
 let final=false,committed=false,rolledBack=false;const tx={unsafe:async()=>[]};
 const work={assert:async()=>{await Promise.resolve();if(final)db.applicationWork={assert:async()=>{}};}};
 const db={applicationWork:work,context:async()=>{},readContext:async()=>{},transaction:async cb=>{try{const v=await cb(tx);committed=true;return v;}catch(e){rolledBack=true;throw e;}}};
 const authority=new PostgresNativeAuthority({db,groupId:'group-1'});
 await assert.rejects(authority[readOnly?'read':'write'](()=>{final=true;return 'sensitive result';}),/request_not_admitted/);
 assert.equal(committed,false);assert.equal(rolledBack,true);
});
