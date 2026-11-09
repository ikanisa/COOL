import test from 'node:test';import assert from 'node:assert/strict';
import {PostgresNativeAuthority} from '../../domain/burimunsi/postgres-authority.js';
function fixture(){
 const events=[];let fail=false;const tx={unsafe:async(q,v=[])=>{events.push([q,v]);return []}};
 const work={assert:async()=>{if(fail)throw Error('work revoked')}};
 const db={applicationWork:work,transaction:async fn=>{events.push(['BEGIN']);try{const r=await fn(tx);events.push(['COMMIT']);return r}catch(e){events.push(['ROLLBACK']);throw e}},
 context:async t=>{assert.equal(t,tx);events.push(['CONTEXT'])},readContext:async(t,o)=>{assert.equal(t,tx);assert.equal(o.isolation,'repeatable read');events.push(['READ_CONTEXT'])}};
 return {events,db,tx,deny:()=>fail=true};
}
test('write uses the existing Collect transaction, fence, lock and parameterized scope',async()=>{
 const f=fixture(),a=new PostgresNativeAuthority({db:f.db,groupId:'group-1'});const result=await a.write(tx=>{assert.equal(tx,f.tx);f.events.push(['BODY']);return 17});
 assert.equal(result,17);assert.deepEqual(f.events.map(e=>e[0]),['BEGIN','CONTEXT','SELECT pg_advisory_xact_lock(734636924058501::bigint)',"SELECT set_config('burimunsi.collection_id',$1,true)",'BODY','COMMIT']);assert.deepEqual(f.events[3][1],['group-1']);
});
test('read selects real read-only repeatable-read before installing context',async()=>{
 const f=fixture(),a=new PostgresNativeAuthority({db:f.db,groupId:'group-1'});await a.read(()=>42);
 assert.deepEqual(f.events.map(e=>e[0]),['BEGIN','SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY','READ_CONTEXT',"SELECT set_config('burimunsi.collection_id',$1,true)",'COMMIT']);
});
test('admission revoked during callback rolls back instead of acknowledging',async()=>{
 const f=fixture(),a=new PostgresNativeAuthority({db:f.db,groupId:'group-1'});await assert.rejects(a.write(()=>{f.deny();return 42}),/work revoked/);assert.equal(f.events.at(-1)[0],'ROLLBACK');
});
test('admission object replacement invalidates an already constructed adapter',async()=>{
 const f=fixture(),a=new PostgresNativeAuthority({db:f.db,groupId:'group-1'});f.db.applicationWork={assert:async()=>{}};await assert.rejects(a.write(()=>42),/request_not_admitted/);assert.equal(f.events.length,0);
});
test('callback exceptions reach existing rollback owner',async()=>{
 const f=fixture(),a=new PostgresNativeAuthority({db:f.db,groupId:'group-1'});await assert.rejects(a.write(()=>{throw Error('failed')}),/failed/);assert.equal(f.events.at(-1)[0],'ROLLBACK');
});
for(const invalid of [undefined,null,{},'group with spaces',"g';DROP TABLE x--"]){test('reject absent authority or invalid group '+String(invalid),()=>{
 const f=fixture();assert.throws(()=>new PostgresNativeAuthority({db:invalid===undefined?{}:f.db,groupId:invalid}));
});}
test('an application work fence is mandatory; no no-op default is installed',()=>{
 const f=fixture();delete f.db.applicationWork;assert.throws(()=>new PostgresNativeAuthority({db:f.db,groupId:'g'}),/collect_adapter_required/);
});
