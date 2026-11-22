import {test} from 'node:test';
import assert from 'node:assert/strict';
import process from 'node:process';
import {runInNewContext} from 'node:vm';
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
  test(`${name}: aborted stalled body returns without waiting for cancellation`,async()=>{
    for (const cancel of [()=>new Promise(()=>{}),()=>Promise.reject(new Error('synthetic cancel rejection'))]) {
      let cancellations=0;const controller=new AbortController();
      const body=new ReadableStream({start(c){c.enqueue(bytes('{"partial":'));},cancel(){cancellations++;return cancel();}});
      const request=new Request('https://collect.invalid/test',{method:'POST',headers:{'content-type':'application/json'},body,signal:controller.signal,duplex:'half'});
      const unhandled=[];const observe=reason=>unhandled.push(reason);process.on('unhandledRejection',observe);
      try {
        const result=bounded(readJson(request,32));await nextTurn();controller.abort();const outcome=await result;
        assert.equal(outcome.kind,'rejected');assert.ok(outcome.error instanceof ErrorClass);
        assert.equal(outcome.error.status,400);assert.equal(outcome.error.code,'request_aborted');
        assert.equal(cancellations,1);assert.equal(request.body.locked,false);
        await nextTurn();await nextTurn();assert.deepEqual(unhandled,[]);
      } finally {process.removeListener('unhandledRejection',observe);}
    }
  });
  test(`${name}: already-aborted body never starts a read`,async()=>{
    const controller=new AbortController();controller.abort();let reads=0,cancellations=0,releases=0;
    const request={signal:controller.signal,headers:new Headers({'content-type':'application/json'}),body:{getReader(){return {
      read(){reads++;return new Promise(()=>{});},cancel(){cancellations++;return new Promise(()=>{});},releaseLock(){releases++;},
    };}}};
    const result=await bounded(readJson(request,32));assert.equal(result.kind,'rejected');assert.equal(result.error.code,'request_aborted');
    assert.equal(reads,0);assert.equal(cancellations,1);assert.equal(releases,1);
  });
  test(`${name}: abort observes late read failure and synchronous cancel failure`,async()=>{
    const controller=new AbortController();let rejectRead,cancellations=0,releases=0,added=0,removed=0;
    const signal=controller.signal,add=signal.addEventListener.bind(signal),remove=signal.removeEventListener.bind(signal);
    signal.addEventListener=(...args)=>{added++;return add(...args);};signal.removeEventListener=(...args)=>{removed++;return remove(...args);};
    const request={signal,headers:new Headers({'content-type':'application/json'}),body:{getReader(){return {
      read(){return new Promise((_,reject)=>{rejectRead=reject;});},cancel(){cancellations++;throw new Error('synthetic sync cancel');},releaseLock(){releases++;},
    };}}};
    const unhandled=[];const observe=reason=>unhandled.push(reason);process.on('unhandledRejection',observe);
    try {
      const pending=bounded(readJson(request,32));controller.abort();const outcome=await pending;
      assert.equal(outcome.kind,'rejected');assert.equal(outcome.error.code,'request_aborted');
      rejectRead(new Error('synthetic late read failure'));await nextTurn();await nextTurn();
      assert.deepEqual(unhandled,[]);assert.equal(cancellations,1);assert.equal(releases,1);assert.equal(added,1);assert.equal(removed,1);
    } finally {process.removeListener('unhandledRejection',observe);}
  });
  test(`${name}: completed body removes the abort listener`,async()=>{
    const controller=new AbortController();let cancellations=0,added=0,removed=0;
    const signal=controller.signal,add=signal.addEventListener.bind(signal),remove=signal.removeEventListener.bind(signal);
    signal.addEventListener=(...args)=>{added++;return add(...args);};signal.removeEventListener=(...args)=>{removed++;return remove(...args);};
    let count=0;const request={signal,headers:new Headers({'content-type':'application/json'}),body:{getReader(){return {
      async read(){return count++?{done:true}:{done:false,value:bytes('{}')};},cancel(){cancellations++;},releaseLock(){},
    };}}};
    assert.deepEqual(await readJson(request,32),{});controller.abort();assert.equal(cancellations,0);assert.equal(added,1);assert.equal(removed,1);
  });
  test(`${name}: empty and tiny chunks use capped geometric allocations`,async()=>{
    const controller=new AbortController();let reads=0,added=0,removed=0,cancellations=0;
    const signal=controller.signal,add=signal.addEventListener.bind(signal),remove=signal.removeEventListener.bind(signal);
    signal.addEventListener=(...args)=>{added++;return add(...args);};signal.removeEventListener=(...args)=>{removed++;return remove(...args);};
    const space=bytes(' '),empty=bytes(''),json=bytes('{}');const request={signal,headers:new Headers({'content-type':'application/json'}),body:{getReader(){return {
      async read(){reads++;return reads<=16384?{done:false,value:reads%2?empty:space}:reads===16385?{done:false,value:json}:{done:true};},
      cancel(){cancellations++;},releaseLock(){},
    };}}};
    const original=globalThis.Uint8Array,allocations=[];
    globalThis.Uint8Array=new Proxy(original,{construct(target,args,newTarget){if(typeof args[0]==='number')allocations.push({size:args[0],afterRead:reads});return Reflect.construct(target,args,newTarget);}});
    try{assert.deepEqual(await readJson(request,8194),{});}finally{globalThis.Uint8Array=original;}
    controller.abort();assert.equal(allocations[0].size,0);assert.equal(allocations.at(-1).size,8194);
    assert.ok(allocations.length<=16);
    assert.ok(allocations.every((a,i)=>a.size<=8194&&(i===0||a.size>allocations[i-1].size)));
    assert.ok(allocations.slice(1).every(a=>a.afterRead===16385||a.afterRead<=16384&&a.afterRead%2===0));
    assert.equal(reads,16386);assert.equal(added,1);assert.equal(removed,1);assert.equal(cancellations,0);
  });
  test(`${name}: rejects non-byte chunks and observes cancellation`,async()=>{
    for(const invalid of [null,{},'{}',new Int8Array([123,125]),new DataView(new ArrayBuffer(2))]){
      let cancellations=0,releases=0,reads=0;
      const request={headers:new Headers({'content-type':'application/json'}),body:{getReader(){return {
        async read(){reads++;return {done:false,value:invalid};},cancel(){cancellations++;return Promise.reject(new Error('synthetic cancellation'));},releaseLock(){releases++;},
      };}}};
      const outcome=await bounded(readJson(request,32));assert.equal(outcome.kind,'rejected');
      assert.ok(outcome.error instanceof ErrorClass);assert.equal(outcome.error.status,400);assert.equal(outcome.error.code,'invalid_request');
      assert.equal(reads,1);assert.equal(cancellations,1);assert.equal(releases,1);
    }
    await nextTurn();
  });
  test(`${name}: accepts sliced, Buffer and cross-realm byte views`,async()=>{
    const source=bytes('x{}x'),values=[new Uint8Array(source.buffer,source.byteOffset+1,2),Buffer.from('{}'),runInNewContext('new Uint8Array([123,125])')];
    for(const value of values){const request={headers:new Headers({'content-type':'application/json'}),body:{getReader(){let sent=false;return {
      async read(){if(sent)return {done:true};sent=true;return {done:false,value};},releaseLock(){},
    };}}};assert.deepEqual(await readJson(request,2),{});}
  });
  test(`${name}: zero and small byte limits remain exact`,async()=>{
    for(const [input,limit,expected] of [['',0,'invalid_json'],['{',1,'invalid_json'],['{}',1,'request_too_large'],['{}',2,null],['{} ',2,'request_too_large']]){
      const x=fixture([bytes(input)],{close:true});const outcome=await bounded(readJson(x.request,limit));
      if(expected===null){assert.equal(outcome.kind,'resolved');assert.deepEqual(outcome.value,{});}
      else{assert.equal(outcome.kind,'rejected');assert.equal(outcome.error.code,expected);}
    }
  });
}
