import {test} from 'node:test';
import assert from 'node:assert/strict';
import process from 'node:process';
import {setImmediate as nextTurn} from 'node:timers/promises';
import {readJson as readSupabase, ApiError as SupabaseError} from '../domain/core.js';

// Synthetic, no socket or provider. This exercises the selected Supabase
// implementation. The original dual-backend test remains in the snapshot.
const targets=[['Supabase',readSupabase,SupabaseError]];
const bytes=value=>new TextEncoder().encode(value);
function fixture(chunks,{cancel=()=>{},close=false,headers={'content-type':'application/json'}}={}) {
  let cancelled=0;
  const stream=new ReadableStream({
    start(controller){for(const chunk of chunks)controller.enqueue(chunk);if(close)controller.close();},
    cancel(){cancelled++;return cancel();},
  });
  const request=new Request('https://collect.invalid/test',{method:'POST',headers,body:stream,duplex:'half'});
  return {request,cancellations:()=>cancelled};
}
async function bounded(promise) {
  let timer;
  try { return await Promise.race([
    promise.then(value=>({kind:'resolved',value}),error=>({kind:'rejected',error})),
    new Promise(resolve=>{timer=setTimeout(()=>resolve({kind:'timeout'}),1500);}),
  ]); } finally {clearTimeout(timer);}
}
function is413(result,ErrorClass) {
  return result.kind==='rejected' && result.error instanceof ErrorClass &&
    result.error.status===413 && result.error.code==='request_too_large' && result.error.message==='The request is too large.';
}
for(const [name,readJson,ErrorClass] of targets) {
  test(`${name}: oversized stream starts cancellation and returns 413`,async()=>{
    const x=fixture([bytes('1234'),bytes('56789')]);
    assert.ok(is413(await bounded(readJson(x.request,8)),ErrorClass));
    assert.equal(x.cancellations(),1);assert.equal(x.request.body.locked,false);
  });
  test(`${name}: rejected cancellation preserves 413 and is handled`,async()=>{
    const x=fixture([bytes('123456789')],{cancel:()=>Promise.reject(new Error('private synthetic marker'))});
    const unhandled=[];const observe=reason=>unhandled.push(reason);process.on('unhandledRejection',observe);
    try {
      const outcome=await bounded(readJson(x.request,8));await nextTurn();await nextTurn();
      assert.ok(is413(outcome,ErrorClass));assert.equal(x.cancellations(),1);
      assert.equal(x.request.body.locked,false);assert.deepEqual(unhandled,[]);
      assert.equal(outcome.error.message.includes('private synthetic marker'),false);
    } finally {process.removeListener('unhandledRejection',observe);}
  });
  test(`${name}: never-settling cancellation cannot delay 413`,async()=>{
    const x=fixture([bytes('123456789')],{cancel:()=>new Promise(()=>{})});
    assert.ok(is413(await bounded(readJson(x.request,8)),ErrorClass));
    assert.equal(x.cancellations(),1);assert.equal(x.request.body.locked,false);
  });
  test(`${name}: synchronous reader cancellation failure still returns 413`,async()=>{
    let cancelled=0,released=0;
    const request={headers:new Headers({'content-type':'application/json'}),body:{getReader(){return {
      async read(){return {done:false,value:bytes('123456789')};},
      cancel(){cancelled++;throw new Error('synthetic synchronous failure');},
      releaseLock(){released++;},
    };}}};
    assert.ok(is413(await bounded(readJson(request,8)),ErrorClass));
    assert.equal(cancelled,1);assert.equal(released,1);
  });
  test(`${name}: exact-limit JSON with split UTF-8 remains valid`,async()=>{
    const input=bytes('{"text":"é"}');const split=input.indexOf(0xc3)+1;
    const x=fixture([input.subarray(0,split),input.subarray(split)],{close:true});
    assert.deepEqual(await readJson(x.request,input.length),{text:'é'});assert.equal(x.cancellations(),0);
  });
  test(`${name}: content length and media type controls remain unchanged`,async()=>{
    let x=fixture([bytes('{}')],{close:true,headers:{'content-type':'application/json','content-length':'9'}});
    assert.ok(is413(await bounded(readJson(x.request,8)),ErrorClass));assert.equal(x.cancellations(),0);
    x=fixture([bytes('{}')],{close:true,headers:{'content-type':'text/plain'}});
    const result=await bounded(readJson(x.request,8));assert.equal(result.kind,'rejected');
    assert.ok(result.error instanceof ErrorClass);assert.equal(result.error.status,415);assert.equal(result.error.code,'unsupported_media_type');
  });
  test(`${name}: malformed UTF-8, JSON and nonobject errors remain unchanged`,async()=>{
    for(const [input,code] of [[new Uint8Array([0xff]),'invalid_json'],[bytes('{'),'invalid_json'],[bytes('[]'),'invalid_request'],[bytes('null'),'invalid_request']]) {
      const x=fixture([input],{close:true});const result=await bounded(readJson(x.request,32));
      assert.equal(result.kind,'rejected');assert.ok(result.error instanceof ErrorClass);
      assert.equal(result.error.status,400);assert.equal(result.error.code,code);
    }
  });
}
