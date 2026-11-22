import test from 'node:test';
import assert from 'node:assert/strict';
import {processMomoJob} from '../domain/momo_pipeline.js';

test('direct MoMo processing does not touch storage, database or provider while paused or misconfigured',async()=>{
 for(const value of [undefined,null,'true','TRUE','FALSE','',false]){
  const env={MOMO_PROCESSING_PAUSED:value};
  for(const name of ['DB','PRIVATE_MEDIA','AI'])Object.defineProperty(env,name,{get(){throw Error(name+' was accessed');}});
  assert.deepEqual(await processMomoJob(env,'synthetic-id'),{state:'paused'});
 }
});

test('the explicit unpaused direct entry reaches the existing claim and does not send unclaimed work',async()=>{
 let claims=0,calls=0;
 const env={MOMO_PROCESSING_PAUSED:'false',DB:{prepare(sql){
  assert.match(sql,/^UPDATE momo_processing_jobs SET state='processing'/);
  return {bind(){return {async first(){claims++;return null;}};}};
 }},AI:{async run(){calls++;}}};
 assert.deepEqual(await processMomoJob(env,'synthetic-id'),{state:'not_claimed'});
 assert.equal(claims,1);assert.equal(calls,0);
});

test('an SMS stays unread unless the claim returns the exact processing lease',async()=>{
 for(const claimed of [{state:'source_unresolved',lease_token:null},{state:'needs_review',lease_token:null},
  {state:'processing',lease_token:'different-lease'}]){
  let claims=0;
  const env={MOMO_PROCESSING_PAUSED:'false',DB:{prepare(sql){
   assert.match(sql,/^UPDATE momo_processing_jobs SET state='processing'/);
   return {bind(){return {async first(){claims++;return claimed;}};}};
  }},PRIVATE_MEDIA:{async get(){assert.fail('Unexpected SMS read');}},
  AI:{async run(){assert.fail('Unexpected provider dispatch');}}};
  assert.deepEqual(await processMomoJob(env,'synthetic-id'),{state:'not_claimed'});
  assert.equal(claims,1);
 }
});
