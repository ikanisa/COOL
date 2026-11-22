import test from 'node:test';
import assert from 'node:assert/strict';
import {probePlatformHealth} from '../supabase/platform_health_probe.mjs';
const source='a'.repeat(64),target='https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-api/health';
test('Supabase adapter makes one exact anonymous GET with redirects refused and unchanged source-bound contract',async()=>{
 const calls=[];const result=await probePlatformHealth({expectedSourceId:source,now:()=>Date.parse('2026-10-23T00:00:00.000Z'),fetchImpl:async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify({checked_at:'2026-10-23T00:00:00.000Z',database:'available',release:source,service:'collect-platform-api'}),{headers:{'Content-Type':'application/json'}});}});
 assert.equal(calls.length,1);assert.equal(calls[0].url,target);assert.equal(calls[0].options.method,'GET');assert.equal(calls[0].options.redirect,'manual');assert.deepEqual(calls[0].options.headers,{Accept:'application/json','Cache-Control':'no-cache'});assert.equal(result.source_bound_health_available,true);assert.equal(result.SLO_or_alert_delivery_accepted,false);
});
test('Supabase adapter preserves source mismatch and unavailable outcomes without retries or accepting an unrelated deployment',async()=>{
 for(const status of [200,503]){let count=0;const result=await probePlatformHealth({expectedSourceId:source,now:()=>Date.parse('2026-10-23T00:00:00.000Z'),fetchImpl:async()=>{count++;return new Response(JSON.stringify({checked_at:'2026-10-23T00:00:00.000Z',database:'available',release:'b'.repeat(64),service:'collect-platform-api'}),{status,headers:{'Content-Type':'application/json'}});}});assert.equal(count,1);assert.equal(result.source_bound_health_available,false);assert.equal(result.outcome,status===200?'source_mismatch':'unavailable');}
});
