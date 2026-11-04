import test from 'node:test';
import assert from 'node:assert/strict';
import {publishMemberRealtime} from '../member-realtime-publisher.js';
import {openApplicationWork} from '../application-fence.js';
const source='a'.repeat(64);
async function fixture(answer){
 let closed;const id=crypto.randomUUID(),proof={contractVersion:1,admissionId:id,sourceSha256:source,epoch:1,state:'active',mode:'open',kind:'jobs'};
 const backend={register:async()=>proof,lease:async()=>({row:proof,assert:async()=>proof,release:async()=>{}}),close:async(_id,_epoch,_source,state,reason,externalDispatches,uncertainDispatches)=>closed={...proof,state,reason,externalDispatches,uncertainDispatches},status:async()=>({found:false})};
 const work=await openApplicationWork({backend,sourceSha256:source,kind:'jobs',id});let calls=0;
 return{env:{COLLECT_FENCE_WORK:work,MEMBER_REALTIME_PUBLISHER_ENABLED:'true',DB:{prepare(text){calls++;assert.equal(text,'SELECT private.collect_member_realtime_publish() AS result');return{async first(key){assert.equal(key,'result');return typeof answer==='function'?answer():answer;}};}}},get calls(){return calls;},async finish(){await work.finish();return closed;}};
}
const valid=patch=>({status:'attempted_unconfirmed',scanned:1,attempted:2,failed:0,overflowed:0,delivery_confirmed:false,...patch});
test('default OFF makes no database or provider call',async()=>{const result=await publishMemberRealtime({});assert.equal(result.status,'disabled');assert.equal(result.attempted,0);assert.equal(result.delivery_confirmed,false);});
test('source-controlled disabled response remains disabled',async()=>{const f=await fixture(valid({status:'disabled',scanned:0,attempted:0}));const r=await publishMemberRealtime(f.env);assert.equal(r.status,'disabled');assert.equal(f.calls,1);assert.equal((await f.finish()).uncertainDispatches,0);});
test('database attempts never become delivery acknowledgements and retain unknown observation',async()=>{const f=await fixture(valid());const r=await publishMemberRealtime(f.env);assert.equal(r.delivery_confirmed,false);assert.equal(r.authoritative_polling,true);const closed=await f.finish();assert.equal(closed.state,'settled');assert.equal(closed.reason,'completed_with_unknown_obligation');assert.equal(closed.uncertainDispatches,1);});
test('unavailable Realtime returns explicit unconfirmed counts without replay',async()=>{const f=await fixture(()=>{throw Error('synthetic unavailable');});const r=await publishMemberRealtime(f.env);assert.equal(r.status,'unavailable');assert.equal(r.attempted,null);assert.equal(f.calls,1);assert.equal((await f.finish()).reason,'completed_with_unknown_obligation');});
test('forged success, extra identifiers and overflow are refused',async()=>{for(const bad of[valid({delivery_confirmed:true}),{...valid(),audit_cursor:1},valid({attempted:33}),valid({failed:3}),valid({scanned:5}),valid({overflowed:2})]){const f=await fixture(bad);assert.equal((await publishMemberRealtime(f.env)).status,'unavailable');assert.equal(f.calls,1);await f.finish();}});
test('raw publisher SQL promise remains tracked until completion',async()=>{let release;const pending=new Promise(r=>release=r),f=await fixture(()=>pending);const call=publishMemberRealtime(f.env);await new Promise(r=>setTimeout(r,0));let done=false;const close=f.finish().then(()=>done=true);await new Promise(r=>setTimeout(r,0));assert.equal(done,false);release(valid());await call;await close;assert.equal(done,true);});
