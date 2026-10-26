import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import worker from '../src/index.js';
import {handleAdmin} from '../src/admin_bridge.js';
import {createPlatformHealthReporter,platformHealthComponent} from '../src/observability.js';

const source='a'.repeat(64),secret='private-phone-250788123456-token@example.com';
const base=()=>({status:503,component:'auth',requestId:randomUUID(),sourceId:source,elapsedMs:12.4});
const expectedFields=['component','elapsed_ms','event','request_id','schema_version','service','source_id','status'].sort();
function capture(t){
 const records=[],old={error:console.error,warn:console.warn};
 console.error=text=>records.push({level:'error',value:JSON.parse(text)});
 console.warn=text=>records.push({level:'warn',value:JSON.parse(text)});
 t.after(()=>{console.error=old.error;console.warn=old.warn;});return records;
}

test('operational records reject identifiers, payloads and error-controlled labels',()=>{
 const records=[],report=createPlatformHealthReporter({emit:(level,text)=>records.push({level,value:JSON.parse(text)})});
 const request=base();assert.equal(report({...request,body:secret,error:new Error(secret),url:secret,actor:secret}),true);
 assert.equal(records.length,1);assert.deepEqual(Object.keys(records[0].value).sort(),expectedFields);
 assert.deepEqual(records[0].value,{service:'collect_platform_api',schema_version:1,event:'service_degraded',component:'auth',status:503,request_id:request.requestId,source_id:source,elapsed_ms:12});
 assert.equal(report({...base(),component:secret}),false);
 assert.equal(report({...base(),status:401}),false);
 assert.equal(report({...base(),status:'503'}),false);
 assert.equal(report({...base(),requestId:secret,sourceId:secret,elapsedMs:Infinity}),true);
 assert.equal(records.at(-1).value.request_id,null);assert.equal(records.at(-1).value.source_id,'unknown');
 assert.ok(!JSON.stringify(records).includes(secret));
});

test('component projections contain no raw dynamic route, RPC, phone or query value',()=>{
 const cases=[['/v1/receipts/'+secret,'receipt'],['/v1/evidence/'+secret,'evidence'],
  ['/v1/rpc/'+secret,'operations'],['/api/admin/reconciliations/'+secret,'reconciliation'],
  ['/v1/functions/verify-play-integrity','native_integrity'],['/v1/auth/'+secret,'auth'],
  ['/privacy/account-deletion/'+secret,'privacy'],['/privacy/account-deletion','privacy'],['/'+secret,'platform']];
 for(const [path,component]of cases)assert.equal(platformHealthComponent(path),component);
 assert.equal(platformHealthComponent({toString(){throw new Error(secret);}}),'platform');
});

test('a burst is bounded, suppression remains observable and clock rollback cannot reopen the budget',()=>{
 let now=60000;const records=[],report=createPlatformHealthReporter({clock:()=>now,emit:(level,text)=>records.push({level,value:JSON.parse(text)})});
 for(let i=0;i<10000;i++)report(base());
 assert.equal(records.length,65);assert.equal(records.filter(r=>r.value.event==='events_suppressed').length,1);
 assert.deepEqual(records.at(-1).value,{service:'collect_platform_api',schema_version:1,event:'events_suppressed',component:'platform',status:null,request_id:null,source_id:source,elapsed_ms:null});
 now=0;assert.equal(report(base()),false);assert.equal(records.length,65);
 now=120000;assert.equal(report(base()),true);assert.equal(records.length,66);
});

test('failed logging and invalid clocks never escape the observation boundary',()=>{
 const report=createPlatformHealthReporter({emit(){throw new Error(secret);}});
 assert.equal(report(base()),false);
 assert.equal(createPlatformHealthReporter({clock:()=>NaN})(base()),false);
 const hostile={get status(){throw new Error(secret);}};
 assert.equal(report(hostile),false);assert.equal(report(null),false);
});

test('actual failed health request keeps the public error contract and emits only fixed labels',async t=>{
 const records=capture(t),error=new Error(secret);error.name=secret;
 const env={BUILD_SOURCE_ID:source,DB:{prepare(){throw error;}}};
 const response=await worker.fetch(new Request('https://api.collect.example/health?private='+secret,{headers:{'X-Request-ID':secret}}),env,{});
 assert.equal(response.status,500);const body=await response.json();
 assert.equal(body.code,'internal_error');assert.equal(body.message,'The request could not be completed.');
 assert.equal(records.length,1);const event=records[0].value;
 assert.equal(event.component,'health');assert.equal(event.event,'unexpected_failure');assert.equal(event.status,500);
 assert.equal(event.request_id,body.request_id);assert.equal(event.source_id,source);
 assert.deepEqual(Object.keys(event).sort(),expectedFields);assert.ok(!JSON.stringify({records,body}).includes(secret));
});

test('actual known service failure is observable without logging an arbitrary error message or code',async t=>{
 const records=capture(t),env={BUILD_SOURCE_ID:source,DB:{prepare(){return {bind(){return this;},async first(){return null;}};}}};
 const response=await worker.fetch(new Request('https://api.collect.example/v1/rpc/get_active_policy_document',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({p_document_key:secret})}),env,{});
 assert.equal(response.status,503);assert.equal((await response.json()).code,'configuration_unavailable');
 assert.equal(records.length,1);assert.equal(records[0].value.event,'service_degraded');
 assert.equal(records[0].value.component,'operations');assert.ok(!JSON.stringify(records).includes(secret));
});

test('an internally handled Admin failure is observed once without changing its response or inventing a request correlation',async t=>{
 const records=capture(t),request=new Request('https://api.collect.example/api/admin/auth/session'),env={BUILD_SOURCE_ID:source};
 const baseline=await handleAdmin(request.clone(),env,{}),response=await worker.fetch(request,env,{});
 assert.equal(response.status,503);assert.equal(response.status,baseline.status);
 assert.deepEqual([...response.headers],[...baseline.headers]);assert.deepEqual(await response.json(),await baseline.json());
 assert.equal(records.length,1);assert.equal(records[0].value.component,'auth');assert.equal(records[0].value.event,'service_degraded');
 assert.equal(records[0].value.request_id,null);
});

test('actual healthy and ordinary denied requests do not fill the failure log',async t=>{
 const records=capture(t),env={BUILD_SOURCE_ID:source,AUTH_JWT_SECRET:'synthetic-jwt-key-'.repeat(3),
  AUTH_TOKEN_HASH_SECRET:'synthetic-hash-key-'.repeat(3),AUTH_ISSUER:'collect-fixture',
  DB:{async batch(){throw new Error('An unsigned request must not mutate the DB.');},prepare(){return {bind(){return this;},async first(){return {ready:1};}};}}};
 const healthy=await worker.fetch(new Request('https://api.collect.example/health'),env,{});
 assert.equal(healthy.status,200);assert.equal((await healthy.json()).database,'available');
 const denied=await worker.fetch(new Request('https://api.collect.example/'+secret),env,{});
 assert.equal(denied.status,401);assert.equal(records.length,0);
});

test('actual unavailable request still responds when the console transport fails',async t=>{
 const old=console.error;console.error=()=>{throw new Error(secret);};t.after(()=>{console.error=old;});
 const response=await worker.fetch(new Request('https://api.collect.example/health'),{BUILD_SOURCE_ID:source,DB:{prepare(){throw new Error(secret);}}},{});
 assert.equal(response.status,500);assert.equal((await response.json()).code,'internal_error');
});
