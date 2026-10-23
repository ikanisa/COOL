import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createContext,SourceTextModule,SyntheticModule} from 'node:vm';

const FRONT='https://source-fixture.example';
const EPOCH='a1'.repeat(32);
const PROPOSED=new URL('../src/index.js',import.meta.url);
const BEFORE=new URL('./support/source_freeze_preimage.fixture.txt',import.meta.url);
const BEFORE_SHA256='cce6e539a9f103b2528f7dc9724c19e5301f4953b2826ac5706dbb18d0c54ec4';
const SOURCE=process.env.COLLECT_SOURCE_FREEZE_TEST_SOURCE
  ?new URL(process.env.COLLECT_SOURCE_FREEZE_TEST_SOURCE,'file://'):PROPOSED;
const OPEN=[['absent',{}],['explicit false',{COLLECT_SOURCE_FROZEN:'false'}]];
const FROZEN={COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:EPOCH};

class FixtureApiError extends Error {
  constructor(status,code,message){super(message);this.status=status;this.code=code;}
}

// Evaluate the actual entrypoint bytes. Only its existing imported dependencies
// are replaced; no handler text, imports or branch conditions are rewritten.
async function harness(source=SOURCE){
  const calls=[],invocations=new Map(),waited=[];
  const spy=(name,implementation=()=>null)=>(...args)=>{
    calls.push(name);
    if(!invocations.has(name))invocations.set(name,[]);
    invocations.get(name).push(args);
    return implementation(...args);
  };
  const actor={userId:'synthetic-member',sessionId:'synthetic-session'};
  const json=(body,status=200,headers={})=>Response.json(body,{status,headers:{
    'Cache-Control':'no-store','X-Content-Type-Options':'nosniff',
    'Referrer-Policy':'no-referrer',...headers,
  }});
  const dependencies={
    './core.js':{
      ApiError:FixtureApiError,json,
      readJson:spy('readJson',request=>request.json()),
      first:spy('first',()=>({ready:1})),
      now:spy('now',()=> '2026-10-20T00:00:00.000Z'),
    },
    './sync.js':{syncEvents:spy('syncEvents',()=>({events:[]}))},
    './auth.js':{handleAuth:spy('handleAuth'),requireSession:spy('requireSession',()=>actor)},
    './admin_bridge.js':{handleAdmin:spy('handleAdmin')},
    './groups.js':{publicGroups:spy('publicGroups',()=>[])},
    './notifications.js':{notificationEvents:spy('notificationEvents',()=>[])},
    './evidence.js':{evidenceRoute:spy('evidenceRoute')},
    './challenge.js':{challengeRoute:spy('challengeRoute')},
    './receipts.js':{receiptRoute:spy('receiptRoute')},
    './privacy_portal.js':{privacyPortalRoute:spy('privacyPortalRoute')},
    './operations.js':{
      publicRpcNames:[],
      dispatchOperation:spy('dispatchOperation',(kind,operation,body,_env,member)=>
        ({kind,operation,body,user_id:member.userId})),
    },
    './observability.js':{
      recordPlatformHealth:spy('recordPlatformHealth'),
      platformHealthComponent:spy('platformHealthComponent',()=> 'synthetic-component'),
    },
    './momo_pipeline.js':{drainMomoJobs:spy('drainMomoJobs',()=>Promise.resolve({synthetic:true}))},
    './momo_gateway.js':{momoGatewayRoute:spy('momoGatewayRoute')},
  };
  const context=createContext({
    Request,Response,Headers,URL,Error,Set,console,
    crypto:{randomUUID:spy('randomUUID',()=> '00000000-0000-4000-8000-000000000001')},
    performance:{now:spy('performance.now',()=>1)},
    fetch:spy('unexpected.fetch',()=>{throw Error('No network is permitted in this fixture');}),
  });
  const sourceBytes=await readFile(source);
  if(source.href===BEFORE.href)assert.equal(createHash('sha256').update(sourceBytes).digest('hex'),BEFORE_SHA256,
    'The immutable pre-freeze entrypoint fixture must retain its reviewed bytes');
  const module=new SourceTextModule(sourceBytes.toString('utf8'),{context,identifier:source.href});
  await module.link(specifier=>{
    const exports=dependencies[specifier];
    assert.ok(exports,'Unexpected entrypoint dependency: '+specifier);
    return new SyntheticModule(Object.keys(exports),function(){
      for(const [name,value]of Object.entries(exports))this.setExport(name,value);
    },{context,identifier:'synthetic:'+specifier});
  });
  await module.evaluate();
  const ctx={waitUntil:spy('ctx.waitUntil',promise=>waited.push(promise))};
  const environment=fields=>{
    const env={BUILD_SOURCE_ID:'synthetic-reviewed-source',...fields};
    Object.defineProperty(env,'ALLOWED_ORIGINS',{get:spy('env.ALLOWED_ORIGINS',()=>FRONT)});
    for(const name of ['DB','PRIVATE_MEDIA','AI','PLATFORM_API']){
      Object.defineProperty(env,name,{get:spy('binding.'+name,()=>{throw Error('Unexpected binding access');})});
    }
    return env;
  };
  return {worker:module.namespace.default,calls,invocations,ctx,waited,environment};
}

function protectedRequest(path,method='GET',headers={}){
  const request=new Request(FRONT+path,{method,headers:{'Content-Type':'application/json',...headers},
    ...(['GET','HEAD'].includes(method)?{}:{body:'{"synthetic":"must-not-be-read"}'}),
  });
  let reads=0;
  for(const name of ['arrayBuffer','blob','bytes','formData','json','text']){
    Object.defineProperty(request,name,{value:()=>{reads++;throw Error('Request body read before source gate');}});
  }
  return {request,assertUnread(){assert.equal(reads,0);assert.equal(request.bodyUsed,false);}};
}

async function assertFenced(response,{code,state,epoch}){
  assert.equal(response.status,503);
  assert.match(response.headers.get('Content-Type'),/^application\/json/);
  assert.equal(response.headers.get('Cache-Control'),'no-store');
  assert.equal(response.headers.get('Set-Cookie'),null);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'),null);
  const body=await response.json();
  assert.deepEqual(body,{
    code,message:state==='frozen'?'Source access is paused. The request was not processed.':
      'Source access is unavailable. The request was not processed.',
    request_processed:false,source_freeze:{state,epoch},
  });
  return body;
}

test('entrypoint keeps the existing fetch/scheduled surface and introduces no queue consumer',async()=>{
  assert.equal(createHash('sha256').update(await readFile(BEFORE)).digest('hex'),BEFORE_SHA256);
  const {worker}=await harness();
  assert.equal(typeof worker.fetch,'function');assert.equal(typeof worker.scheduled,'function');
  assert.equal(Object.hasOwn(worker,'queue'),false);assert.equal(worker.queue,undefined);
  assert.deepEqual(Object.keys(worker).sort(),['fetch','scheduled']);
});

test('open status is metadata only for absent and exact false configurations',async t=>{
  for(const [name,fields]of OPEN)await t.test(name,async()=>{
    const h=await harness(),input=protectedRequest('/source-freeze-status');
    const response=await h.worker.fetch(input.request,h.environment(fields),h.ctx);
    assert.equal(response.status,200);assert.equal(response.headers.get('Cache-Control'),'no-store');
    assert.equal(response.headers.get('Set-Cookie'),null);
    assert.deepEqual(await response.json(),{service:'collect-platform-api',database:'not_checked',
      source_freeze:{state:'open',epoch:null},request_processed:false});
    input.assertUnread();assert.deepEqual(h.calls,[]);
  });
});

test('frozen GET health and status return only metadata before UUID, clock, CORS or dispatch',async t=>{
  for(const path of ['/health','/source-freeze-status'])await t.test(path,async()=>{
    const h=await harness(),input=protectedRequest(path,'GET',{Origin:'https://forged-origin.example'});
    const response=await h.worker.fetch(input.request,h.environment(FROZEN),h.ctx);
    assert.equal(response.status,200);assert.equal(response.headers.get('Cache-Control'),'no-store');
    assert.equal(response.headers.get('Set-Cookie'),null);assert.equal(response.headers.get('Access-Control-Allow-Origin'),null);
    assert.deepEqual(await response.json(),{service:'collect-platform-api',database:'not_checked',
      source_freeze:{state:'frozen',epoch:EPOCH},request_processed:false});
    input.assertUnread();assert.deepEqual(h.calls,[]);
  });
});

test('every frozen non-metadata route and method refuses before body, handlers, bindings and ctx',async t=>{
  const routes=[
    ['/health','HEAD'],['/health','POST'],['/health','OPTIONS'],
    ['/source-freeze-status','HEAD'],['/source-freeze-status','POST'],['/source-freeze-status','OPTIONS'],
    ['/health/','GET'],['/source-freeze-status/','GET'],
    ['/api/admin/auth/session','GET'],['/api/admin/team/invite','POST'],
    ['/v1/auth/otp','POST'],['/v1/auth/verify','POST'],
    ['/v1/auth/google/start','POST'],['/v1/auth/google/callback?code=synthetic&state=synthetic','GET'],
    ['/hooks/momo/ingest','POST'],['/v1/gateway/momo/ingest','POST'],
    ['/v1/rpc/create_contribution_intent','POST'],['/v1/functions/roster-import-upload','POST'],
    ['/privacy/account-deletion','GET'],['/privacy/account-deletion/portal.js','GET'],
    ['/v1/query/public-collections','GET'],['/v1/sync','GET'],['/unknown','OPTIONS'],
  ];
  for(const [path,method]of routes)await t.test(method+' '+path,async()=>{
    const h=await harness(),input=protectedRequest(path,method,{Origin:'https://forged-origin.example',
      Cookie:'__Host-collect_admin=synthetic','X-Collect-Admin':'1',Authorization:'Bearer synthetic'});
    await assertFenced(await h.worker.fetch(input.request,h.environment(FROZEN),h.ctx),
      {code:'source_frozen',state:'frozen',epoch:EPOCH});
    input.assertUnread();assert.deepEqual(h.calls,[]);assert.equal(h.waited.length,0);
  });
});

test('headers and query strings cannot override the operator source gate',async t=>{
  for(const path of [
    '/api/admin/auth/session?COLLECT_SOURCE_FROZEN=false&COLLECT_SOURCE_FREEZE_EPOCH=',
    '/v1/auth/google/callback?source_frozen=false&source_freeze_epoch='+EPOCH,
    '/v1/rpc/create_contribution_intent?source_freeze_status=open',
  ])await t.test(path,async()=>{
    const h=await harness(),input=protectedRequest(path,'POST',{
      Origin:FRONT,'COLLECT_SOURCE_FROZEN':'false','COLLECT_SOURCE_FREEZE_EPOCH':EPOCH,
      'X-Collect-Source-Frozen':'false','X-Collect-Source-Freeze-Epoch':EPOCH,
      'X-Collect-Original-Path':'/health','X-HTTP-Method-Override':'GET',
    });
    await assertFenced(await h.worker.fetch(input.request,h.environment(FROZEN),h.ctx),
      {code:'source_frozen',state:'frozen',epoch:EPOCH});
    input.assertUnread();assert.deepEqual(h.calls,[]);
  });
});

const INVALID=[
  ['missing epoch',{COLLECT_SOURCE_FROZEN:'true'}],
  ['empty epoch',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:''}],
  ['short epoch',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:'a'.repeat(63)}],
  ['long epoch',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:'a'.repeat(65)}],
  ['uppercase epoch',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:'A'.repeat(64)}],
  ['nonhex epoch',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:'z'.repeat(64)}],
  ['padded epoch',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:' '+EPOCH}],
  ['epoch plus LF',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:EPOCH+'\n'}],
  ['epoch plus CR',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:EPOCH+'\r'}],
  ['epoch plus Unicode line separator',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:EPOCH+'\u2028'}],
  ['epoch plus Unicode paragraph separator',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:EPOCH+'\u2029'}],
  ['numeric epoch',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:123}],
  ['null epoch',{COLLECT_SOURCE_FROZEN:'true',COLLECT_SOURCE_FREEZE_EPOCH:null}],
  ['orphan epoch',{COLLECT_SOURCE_FREEZE_EPOCH:EPOCH}],
  ['false plus epoch',{COLLECT_SOURCE_FROZEN:'false',COLLECT_SOURCE_FREEZE_EPOCH:EPOCH}],
  ['false plus empty epoch',{COLLECT_SOURCE_FROZEN:'false',COLLECT_SOURCE_FREEZE_EPOCH:''}],
  ['absent flag plus empty epoch',{COLLECT_SOURCE_FREEZE_EPOCH:''}],
  ['empty flag',{COLLECT_SOURCE_FROZEN:''}],
  ['uppercase flag',{COLLECT_SOURCE_FROZEN:'TRUE',COLLECT_SOURCE_FREEZE_EPOCH:EPOCH}],
  ['padded flag',{COLLECT_SOURCE_FROZEN:'true ',COLLECT_SOURCE_FREEZE_EPOCH:EPOCH}],
  ['boolean true',{COLLECT_SOURCE_FROZEN:true,COLLECT_SOURCE_FREEZE_EPOCH:EPOCH}],
  ['boolean false',{COLLECT_SOURCE_FROZEN:false}],
  ['null flag',{COLLECT_SOURCE_FROZEN:null}],
];
test('malformed or inconsistent configuration fails closed even for health and status, without epoch echo',async t=>{
  for(const [name,fields]of INVALID)await t.test(name,async()=>{
    for(const [path,method]of [['/health','GET'],['/source-freeze-status','GET'],['/api/admin/auth/session','GET'],['/v1/auth/otp','POST']]){
      const h=await harness(),input=protectedRequest(path,method,{Origin:FRONT,
        'X-Collect-Source-Frozen':'false','X-Collect-Source-Freeze-Epoch':EPOCH});
      const body=await assertFenced(await h.worker.fetch(input.request,h.environment(fields),h.ctx),
        {code:'source_freeze_configuration_invalid',state:'invalid',epoch:null});
      assert.equal(JSON.stringify(body).includes(EPOCH),false);
      input.assertUnread();assert.deepEqual(h.calls,[]);
    }
  });
});

test('an unreadable operator configuration fails closed without leaking its thrown details',async()=>{
  const h=await harness(),env=h.environment({});
  Object.defineProperty(env,'COLLECT_SOURCE_FROZEN',{get(){throw Error('synthetic-private-configuration-detail');}});
  const input=protectedRequest('/health');
  const body=await assertFenced(await h.worker.fetch(input.request,env,h.ctx),
    {code:'source_freeze_configuration_invalid',state:'invalid',epoch:null});
  assert.equal(JSON.stringify(body).includes('synthetic-private-configuration-detail'),false);
  input.assertUnread();assert.deepEqual(h.calls,[]);
});

test('open health and mutation preserve the exact original dispatch order and body handling',async t=>{
  for(const [name,fields]of OPEN)await t.test(name,async()=>{
    for(const [path,method]of [['/health','GET'],['/v1/rpc/synthetic_operation','POST']]){
      const before=await harness(BEFORE),after=await harness();
      const request=()=>new Request(FRONT+path,{method,headers:{Origin:FRONT,'Content-Type':'application/json'},
        ...(method==='POST'?{body:'{"synthetic":"original-body"}'}:{})});
      const oldResponse=await before.worker.fetch(request(),before.environment(fields),before.ctx);
      const newResponse=await after.worker.fetch(request(),after.environment(fields),after.ctx);
      assert.equal(newResponse.status,200);assert.equal(newResponse.status,oldResponse.status);
      assert.deepEqual([...newResponse.headers],[...oldResponse.headers]);
      assert.deepEqual(await newResponse.json(),await oldResponse.json());
      assert.deepEqual(after.calls,before.calls);
      assert.equal(after.invocations.get('first')?.length??0,method==='GET'?1:0);
      assert.equal(after.invocations.get('readJson')?.length??0,method==='POST'?1:0);
      assert.equal(after.invocations.get('dispatchOperation')?.length??0,method==='POST'?1:0);
      if(method==='GET')assert.equal(after.invocations.get('first')[0][1],'SELECT 1 AS ready');
      else assert.deepEqual(after.invocations.get('dispatchOperation')[0].slice(0,3),
        ['rpc','synthetic_operation',{synthetic:'original-body'}]);
      assert.equal(after.waited.length,0);
    }
  });
});

test('open scheduled dispatch remains one drain and one waitUntil, matching the original entrypoint',async t=>{
  for(const [name,fields]of OPEN)await t.test(name,async()=>{
    const before=await harness(BEFORE),after=await harness();
    for(const h of [before,after]){
      assert.equal(await h.worker.scheduled({},h.environment(fields),h.ctx),undefined);
      assert.equal(h.waited.length,1);await h.waited[0];
    }
    assert.deepEqual(after.calls,before.calls);assert.deepEqual(after.calls,['drainMomoJobs','ctx.waitUntil']);
    assert.equal(after.invocations.get('drainMomoJobs').length,1);
  });
});

test('frozen and invalid scheduled events reject before draining, bindings or waitUntil',async t=>{
  for(const [name,fields]of [['frozen',FROZEN],...INVALID])await t.test(name,async()=>{
    const h=await harness();
    await assert.rejects(()=>h.worker.scheduled({},h.environment(fields),h.ctx),error=>
      error.message===(name==='frozen'?'source_frozen':'source_freeze_configuration_invalid'));
    assert.deepEqual(h.calls,[]);assert.equal(h.waited.length,0);
  });
});
