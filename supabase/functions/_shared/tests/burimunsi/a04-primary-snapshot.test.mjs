import test from 'node:test';import assert from 'node:assert/strict';
import {PostgresRecordsStore} from '../../domain/burimunsi/postgres-records-store.js';
import {RecordsService} from '../../domain/burimunsi/records-service.js';
const groupId='group-1',actorId='00000000-0000-4000-8000-000000000001',requestId='00000000-0000-4000-8000-000000000002';
for(const replica of [true,null,undefined,'false',0])test(`A04 command snapshot rejects non-primary attestation ${replica}`,async()=>{
 let called=false;const sql={unsafe:async()=>[{replica}]};const store=new PostgresRecordsStore({authority:{groupId,read:fn=>fn(sql),session:async()=>({})},sourceReader:{revision:async()=>'',page:async()=>{},detail:async()=>{}}});
 await assert.rejects(store.withCommandSnapshot(async()=>{called=true}),/command_primary_required/);assert.equal(called,false);
});
test('A04 literal false primary attestation permits command snapshot',async()=>{
 const queries=[];const sql={unsafe:async q=>{queries.push(q);return[{replica:false}];}};
 const store=new PostgresRecordsStore({authority:{groupId,read:fn=>fn(sql),session:async()=>({})},sourceReader:{revision:async()=>'',page:async()=>{},detail:async()=>{}}});
 assert.equal(await store.withCommandSnapshot(async()=>42),42);assert.deepEqual(queries,['SELECT pg_is_in_recovery() AS replica']);
});
for(const method of ['recoverCommandStatus','commandStatus'])test(`A04 ${method} cannot downgrade to ordinary reader`,async()=>{
 let ordinary=0;const service=new RecordsService({store:{withReadSnapshot:async()=>{ordinary++;throw Error('fallback')}},groupId,cursor:{create:async()=>'',read:async()=>{}}});
 await assert.rejects(service[method]({id:actorId},requestId,'a'.repeat(64)));assert.equal(ordinary,0);
});
