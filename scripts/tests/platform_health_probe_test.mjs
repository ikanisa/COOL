import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {probePlatformHealth} from '../cloudflare/platform_health_probe.mjs';

const source='a'.repeat(64),other='b'.repeat(64),clock=Date.parse('2026-10-16T05:00:00.000Z');
const secret='private-phone-250788123456-token@example.com';
const healthy=(extra={})=>({service:'collect-platform-api',database:'available',release:source,checked_at:new Date(clock).toISOString(),...extra});
const run=(fetchImpl,extra={})=>probePlatformHealth({expectedSourceId:source,now:()=>clock,fetchImpl,...extra});

test('one exact source-bound health read uses the fixed HTTPS destination without credentials or retries',async()=>{
 const calls=[],result=await run(async(url,options)=>{calls.push({url,options});return Response.json(healthy());});
 assert.equal(result.source_bound_health_available,true);assert.equal(result.outcome,'available');
 assert.equal(result.expected_source_id,source);assert.equal(result.observed_source_id,source);assert.equal(result.SLO_or_alert_delivery_accepted,false);
 assert.equal(calls.length,1);assert.equal(calls[0].url,'https://api.collect.ikanisa.com/health');
 assert.equal(calls[0].options.method,'GET');assert.equal(calls[0].options.redirect,'manual');
 assert.equal(Object.keys(calls[0].options.headers).includes('Authorization'),false);
});

test('a valid different deployed source is reported as a mismatch rather than accepted as healthy',async()=>{
 const result=await run(async()=>Response.json(healthy({release:other})));
 assert.equal(result.outcome,'source_mismatch');assert.equal(result.source_bound_health_available,false);assert.equal(result.observed_source_id,other);
});

test('stale, future and noncanonical timestamps fail without echoing response fields',async()=>{
 for(const checked_at of [new Date(clock-60001).toISOString(),new Date(clock+5001).toISOString(),'2026-10-16T05:00:00Z',secret]){
  const result=await run(async()=>Response.json(healthy({checked_at})));
  assert.equal(result.outcome,'invalid_response');assert.equal(result.observed_source_id,null);assert.ok(!JSON.stringify(result).includes(secret));
 }
});

test('unexpected response fields, types and private text cannot cross the observation boundary',async()=>{
 for(const body of [healthy({private:secret}),healthy({release:secret}),healthy({database:secret}),[healthy()],{service:secret},null]){
  const result=await run(async()=>Response.json(body));assert.equal(result.outcome,'invalid_response');assert.ok(!JSON.stringify(result).includes(secret));
 }
});

test('duplicate and escaped response field aliases cannot be accepted after JSON normalization',async()=>{
 const normal=JSON.stringify(healthy()),duplicate=normal.replace('{','{"service":"'+secret+'",');
 const escaped=normal.replace('"service"','"\\u0073ervice"');
 for(const body of [duplicate,escaped]){
  const result=await run(async()=>new Response(body,{headers:{'Content-Type':'application/json'}}));
  assert.equal(result.outcome,'invalid_response');assert.equal(result.observed_source_id,null);assert.ok(!JSON.stringify(result).includes(secret));
 }
});

test('redirects and unavailable statuses are refused without a follow-up request',async()=>{
 for(const status of [302,401,429,500,503]){
  let calls=0;const result=await run(async()=>{calls++;return new Response(secret,{status,headers:{Location:'https://private.example/'+secret}});});
  assert.equal(result.outcome,'unavailable');assert.equal(calls,1);assert.equal(result.http_status,status);assert.ok(!JSON.stringify(result).includes(secret));
 }
});

test('oversized body streams are cancelled and cannot leak their bytes',async()=>{
 let cancelled=false;const stream=new ReadableStream({pull(c){c.enqueue(new TextEncoder().encode(secret.repeat(100)));},cancel(){cancelled=true;}});
 const result=await run(async()=>new Response(stream,{headers:{'Content-Type':'application/json'}}));
 assert.equal(result.outcome,'invalid_response');assert.equal(cancelled,true);assert.ok(!JSON.stringify(result).includes(secret));
});

test('content type, declared length, malformed JSON and UTF-8 are rejected',async()=>{
 const responses=[new Response(secret,{headers:{'Content-Type':'text/html'}}),
  new Response(secret,{headers:{'Content-Type':'application/json','Content-Length':'99999'}}),
  new Response(secret,{headers:{'Content-Type':'application/json','Content-Length':'invalid'}}),
  new Response(secret,{headers:{'Content-Type':'application/json'}}),
  new Response(new Uint8Array([255]),{headers:{'Content-Type':'application/json'}})];
 for(const response of responses){const result=await run(async()=>response);assert.equal(result.outcome,'invalid_response');assert.ok(!JSON.stringify(result).includes(secret));}
});

test('a hung response has a bounded deadline and a redacted timeout without retry',async()=>{
 let calls=0,signal;const result=await run(async(_,options)=>{calls++;signal=options.signal;return new Promise(()=>{});},{timeoutMs:20});
 assert.equal(result.outcome,'timeout');assert.equal(result.source_bound_health_available,false);assert.equal(signal.aborted,true);assert.equal(calls,1);
});

test('provider and local exception text is replaced by a closed failure code',async()=>{
 const result=await run(async()=>{throw new Error(secret);});assert.equal(result.outcome,'network_failure');assert.ok(!JSON.stringify(result).includes(secret));
});

test('invalid source/deadline configuration and CLI destination overrides are refused before network access',async()=>{
 let calls=0;const fetchImpl=async()=>{calls++;throw new Error('must not run');};
 await assert.rejects(probePlatformHealth({expectedSourceId:secret,fetchImpl}));
 await assert.rejects(probePlatformHealth({expectedSourceId:source,fetchImpl,timeoutMs:5001}));assert.equal(calls,0);
 const cli=fileURLToPath(new URL('../cloudflare/platform_health_probe.mjs',import.meta.url));
 const result=spawnSync(process.execPath,[cli,'--url','https://private.example/'+secret],{encoding:'utf8'});
 assert.equal(result.status,2);assert.equal(result.stdout,'');assert.ok(!result.stderr.includes(secret));
});
