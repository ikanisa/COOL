const test=require('node:test'),assert=require('node:assert/strict'),path=require('node:path');
const now=Math.floor(Date.now()/1000),secret=Buffer.alloc(32,7).toString('base64');
const env={SEND_SMS_HOOK_SECRET:'v1,whsec_'+secret,WHATSAPP_GRAPH_API_VERSION:'v25.0',WHATSAPP_PHONE_NUMBER_ID:'1234',WHATSAPP_CLOUD_OTP_AUTH_BUTTON:'true',WHATSAPP_CLOUD_API_TOKEN:'test-only-token',WHATSAPP_AUTH_TEMPLATE_NAME:'unit_template',WHATSAPP_AUTH_TEMPLATE_LANGUAGE:'en_US',SUPABASE_URL:'https://backend.test',SUPABASE_SERVICE_ROLE_KEY:'test-only-service',INTERNAL_FUNCTION_SECRET:'test-only-internal'};
let handler;global.Deno={env:{get:name=>env[name]},serve:fn=>handler=fn};
const moduleSuffix=process.env.COLLECT_EDGE_MODULE_SUFFIX||'.js';
require(path.join(process.env.COLLECT_EDGE_BUILD,'auth-send-whatsapp-otp/index'+moduleSuffix));const otpHandler=handler;
require(path.join(process.env.COLLECT_EDGE_BUILD,'ingest-payment-sms/index'+moduleSuffix));const receiptHandler=handler;
require(path.join(process.env.COLLECT_EDGE_BUILD,'parse-payment-sms/index'+moduleSuffix));const parserHandler=handler;
require(path.join(process.env.COLLECT_EDGE_BUILD,'verify-play-integrity/index'+moduleSuffix));const integrityHandler=handler;
require(path.join(process.env.COLLECT_EDGE_BUILD,'send-notification/index'+moduleSuffix));const notificationHandler=handler;
require(path.join(process.env.COLLECT_EDGE_BUILD,'dispatch-notifications/index'+moduleSuffix));const dispatchHandler=handler;
require(path.join(process.env.COLLECT_EDGE_BUILD,'collect-notification-operator/index'+moduleSuffix));const operatorHandler=handler;
const owner='11111111-1111-4111-8111-111111111111',envelope='22222222-2222-4222-8222-222222222222',cap='33333333-3333-4333-8333-333333333333',raw='44444444-4444-4444-8444-444444444444';
global.__user={user:{id:owner}};
const operatorSession='11111111-1111-4111-8111-111111111199';
const operatorAuthorization='Bearer e30.'+Buffer.from(JSON.stringify({sub:owner,session_id:operatorSession,role:'authenticated'})).toString('base64url')+'.synthetic';
async function otpRequest(){const body=JSON.stringify({user:{phone:'+250788123456'},sms:{otp:'123456'}}),id='hook_test';const key=await crypto.subtle.importKey('raw',Buffer.from(secret,'base64'),{name:'HMAC',hash:'SHA-256'},false,['sign']);const sig=Buffer.from(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(`${id}.${now}.${body}`))).toString('base64');return new Request('https://edge.test',{method:'POST',headers:{'webhook-id':id,'webhook-timestamp':String(now),'webhook-signature':'v1,'+sig},body});}
function receiptRequest(auth=true){return new Request('https://edge.test',{method:'POST',headers:{'content-type':'application/json',...(auth?{authorization:'Bearer test'}:{})},body:JSON.stringify({raw_sender:'M-Money',raw_body:'receipt',native_capability:cap,client_envelope_id:envelope,receiver_momo_number:'+250788123456',received_at_device:'2026-09-27T10:00:00Z'})});}
function setup(reservation='reserved'){const calls=[];global.__service={rpc:async(name,p)=>{calls.push(name);if(name==='reserve_signed_otp_v3')return{data:reservation==='throttled'?'throttled':{contract_version:3,hook_id:p.p_hook_id,payload_hash:p.p_payload_hash,attempt_id:cap,state:({reserved:'reserved',already_sent:'accepted',unresolved:'ambiguous'})[reservation]||reservation,revision:1,can_send:reservation==='reserved'},error:null};if(name==='begin_signed_otp_v3')return{data:{contract_version:3,hook_id:p.p_hook_id,payload_hash:p.p_payload_hash,attempt_id:p.p_attempt_id,state:'sending',revision:p.p_revision+1,can_send:false,started:true},error:null};if(name==='record_signed_otp_v3')return{data:{contract_version:3,hook_id:p.p_hook_id,payload_hash:p.p_payload_hash,attempt_id:p.p_attempt_id,state:p.p_outcome,revision:p.p_revision+1,can_send:false},error:null};if(name==='attested_sms_contract_version')return{data:2,error:null};if(name==='accept_attested_receipt_v2')return{data:{stored:true,contract_version:2,raw_sms_id:raw,owner_user_id:owner,client_envelope_id:envelope,body_sha256:p.p_body_hash},error:null};throw new Error('unexpected RPC')}};return calls;}
async function fetchMock(fn,body){const original=global.fetch;let count=0;global.fetch=async(...args)=>{count++;return fn(...args)};try{return await body(()=>count)}finally{global.fetch=original}}
test('OTP GET rejected without provider or DB',async()=>{const c=setup();assert.equal((await otpHandler(new Request('https://edge.test'))).status,405);assert.equal(c.length,0)});
test('OTP static header rejected',async()=>{const c=setup();const r=await otpHandler(new Request('https://edge.test',{method:'POST',headers:{'x-hook-secret':secret},body:'{}'}));assert.equal(r.status,401);assert.equal(c.length,0)});
test('OTP signed send once then complete',async()=>{const c=setup();await fetchMock(async(url,options)=>{assert.equal(options.redirect,'error');assert.ok(options.signal);assert.equal(JSON.parse(options.body).template.components[0].parameters[0].text,'123456');return new Response('{"messages":[{"id":"unit-id"}]}',{status:200})},async count=>{assert.equal((await otpHandler(await otpRequest())).status,200);assert.equal(count(),1)});assert.deepEqual(c,['reserve_signed_otp_v3','begin_signed_otp_v3','record_signed_otp_v3'])});
for(const [state,status] of [['already_sent',200],['throttled',429],['unresolved',503],['unexpected',503]])test('OTP reservation '+state,async()=>{setup(state);await fetchMock(async()=>{throw new Error('must not send')},async count=>{assert.equal((await otpHandler(await otpRequest())).status,status);assert.equal(count(),0)})});
test('OTP dry-run cannot claim delivered',async()=>{setup();env.WHATSAPP_CLOUD_DRY_RUN='true';try{assert.equal((await otpHandler(await otpRequest())).status,503)}finally{delete env.WHATSAPP_CLOUD_DRY_RUN}});
test('OTP missing template does not consume quota',async()=>{const c=setup(),saved=env.WHATSAPP_AUTH_TEMPLATE_NAME;delete env.WHATSAPP_AUTH_TEMPLATE_NAME;try{assert.equal((await otpHandler(await otpRequest())).status,503);assert.equal(c.length,0)}finally{env.WHATSAPP_AUTH_TEMPLATE_NAME=saved}});
test('OTP provider body never leaks or triggers fallback resend',async()=>{setup();await fetchMock(async()=>new Response('{"private":"SECRET"}',{status:400}),async count=>{const r=await otpHandler(await otpRequest());assert.equal(r.status,503);assert.ok(!(await r.text()).includes('SECRET'));assert.equal(count(),1)})});
test('OTP missing provider id cannot become success',async()=>{setup();await fetchMock(async()=>new Response('{}'),async()=>assert.equal((await otpHandler(await otpRequest())).status,503))});
test('Receipt auth failure does not store',async()=>{const c=setup();assert.equal((await receiptHandler(receiptRequest(false))).status,401);assert.equal(c.length,0)});
test('Receipt owner-bound v2 ACK returned',async()=>{setup();await fetchMock(async()=>new Response('{"ok":true}'),async()=>{const r=await receiptHandler(receiptRequest());assert.equal(r.status,200);const p=await r.json();assert.equal(p.receipt.owner_user_id,owner);assert.equal(p.evidence_level,'sms_observed');assert.equal(p.payment_confirmed,undefined);assert.equal(r.headers.get('cache-control'),'no-store')})});
test('Receipt parsing failure retains retry state',async()=>{setup();await fetchMock(async()=>new Response('{"error":"private exception"}',{status:503}),async()=>{const r=await receiptHandler(receiptRequest());assert.equal(r.status,503);const body=await r.json();assert.equal(body.receipt,undefined);assert.equal(body.error,'receipt_stored_processing_retry')})});
test('Receipt legacy version is not a fallback',async()=>{const names=[];global.__service={rpc:async name=>{names.push(name);return{data:1,error:null}}};assert.equal((await receiptHandler(receiptRequest())).status,503);assert.deepEqual(names,['attested_sms_contract_version'])});

for(const [label,result] of [
  ['missing RPC',{data:null,error:{code:'PGRST202',message:'missing synthetic RPC'}}],
  ['null version',{data:null,error:null}],
  ['undefined version',{data:undefined,error:null}],
  ['future version',{data:3,error:null}],
  ['text version',{data:'2',error:null}],
])test('Receipt and parser fail closed on '+label,async()=>{
  const calls=[];
  global.__service={rpc:async name=>{calls.push(name);assert.equal(name,'attested_sms_contract_version');return result},
    from:()=>{throw new Error('must not read or mutate SMS evidence')}};
  await fetchMock(async()=>{throw new Error('must not invoke the parser or provider')},async count=>{
    const receipt=await receiptHandler(receiptRequest());
    assert.equal(receipt.status,503);
    assert.deepEqual(await receipt.json(),{error:'receipt_contract_unavailable'});
    assert.equal(count(),0);
  });
  const parser=await parserHandler(parserRequest());
  assert.equal(parser.status,503);
  assert.deepEqual(await parser.json(),{error:'receipt_contract_unavailable'});
  assert.deepEqual(calls,['attested_sms_contract_version','attested_sms_contract_version']);
});

function parserRequest(internal=true){return new Request('https://edge.test',{method:'POST',headers:{'content-type':'application/json',...(internal?{'x-collect-signature':'test-only-internal'}:{})},body:JSON.stringify({raw_sms_id:raw})});}
function parserService(leaseCompleted,{existingEvent=false}={}){
  const calls=[];const eventId='55555555-5555-4555-8555-555555555555';
  const claimed={raw_sender:'M-Money',raw_body:'You have received RWF 1,234 from 0788123456. Transaction ID ABCD1234.',receiver_user_id:owner,collection_id:null,receiver_momo_number_hash:'a'.repeat(64),received_at_device:'2026-09-27T10:00:00Z',ingested_at:'2026-09-27T10:01:00Z'};
  const service={
    rpc:async name=>{calls.push(name);if(name==='attested_sms_contract_version')return{data:2,error:null};if(name==='claim_raw_payment_sms_for_parse')return{data:claimed,error:null};if(name==='allocate_parsed_payment_event')return{data:'needs_review',error:null};throw new Error('unexpected RPC: '+name)},
    from:table=>{
      let operation='';const query={
        select(){if(!operation)operation='select';return this},
        insert(){operation='insert';return this},
        update(){operation='update';return this},
        eq(){return this},
        async single(){assert.equal(table,'parsed_payment_events');assert.equal(operation,'insert');calls.push('insert_event');return{data:{id:eventId},error:null}},
        async maybeSingle(){if(table==='parsed_payment_events'){assert.equal(operation,'select');return{data:existingEvent?{id:eventId,allocation_status:'unallocated',parser_model:'collect-deterministic-momo-v2'}:null,error:null}}assert.equal(table,'raw_payment_sms');assert.equal(operation,'update');calls.push('complete_lease');return{data:leaseCompleted?{id:raw}:null,error:null}},
        then(resolve,reject){calls.push('release_lease');return Promise.resolve({error:null}).then(resolve,reject)},
      };return query;
    },
  };
  return{service,calls};
}
test('Parser rejects missing internal authorization before any database call',async()=>{const d=parserService(true);global.__service=d.service;assert.equal((await parserHandler(parserRequest(false))).status,401);assert.equal(d.calls.length,0)});
test('Parser stale lease never reports accepted processing or allocates money',async()=>{const d=parserService(false);global.__service=d.service;const response=await parserHandler(parserRequest());assert.equal(response.status,503);assert.equal((await response.json()).error,'receipt_parse_lease_lost');assert.ok(d.calls.includes('complete_lease'));assert.ok(!d.calls.includes('allocate_parsed_payment_event'))});
test('Parser exact lease completion proceeds to review without finalizing payment',async()=>{const d=parserService(true);global.__service=d.service;const response=await parserHandler(parserRequest());assert.equal(response.status,200);const result=await response.json();assert.equal(result.finality.status,'awaiting_reconciliation');assert.equal(result.allocation_status,'needs_review');assert.ok(d.calls.includes('allocate_parsed_payment_event'))});
test('Parser retry repairs raw status from a stored event before review',async()=>{const d=parserService(true,{existingEvent:true});global.__service=d.service;const response=await parserHandler(parserRequest());assert.equal(response.status,200);const result=await response.json();assert.equal(result.replay,true);assert.equal(result.finality.status,'awaiting_reconciliation');assert.ok(d.calls.includes('complete_lease'));assert.ok(d.calls.includes('allocate_parsed_payment_event'));assert.ok(!d.calls.includes('claim_raw_payment_sms_for_parse'))});
test('Parser retry refuses ACK if stored event raw status cannot be repaired',async()=>{const d=parserService(false,{existingEvent:true});global.__service=d.service;const response=await parserHandler(parserRequest());assert.equal(response.status,503);assert.equal((await response.json()).error,'receipt_parse_state_unavailable');assert.ok(!d.calls.includes('allocate_parsed_payment_event'))});

async function integritySetup(license='LICENSED') {
 const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
 const pem='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('pkcs8',keys.privateKey)).toString('base64')+'\n-----END PRIVATE KEY-----';
 env.PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON=JSON.stringify({client_email:'unit@example.invalid',private_key:pem,token_uri:'https://untrusted.invalid'});
 env.PLAY_INTEGRITY_MIN_VERSION_CODE='23';env.PLAY_INTEGRITY_CERTIFICATE_SHA256='CERT';
 const {smsIntegrityRequestHash}=require(path.join(process.env.COLLECT_EDGE_BUILD,'_shared/play_integrity_binding'+moduleSuffix));
 const sms={subjectId:owner,nonce:cap,receiverMomoNumberHash:'a'.repeat(64),clientEnvelopeId:envelope,rawSender:'M-Money',rawBodySha256:'b'.repeat(64),receivedAtDevice:'2026-09-27T10:00:00Z'};
 const hash=await smsIntegrityRequestHash(sms);
 const payload={action:'sms.ingest',subject_id:owner,nonce:cap,sms_permission_granted:true,sms_access_enabled:true,request_hash:hash,receiver_momo_number_hash:sms.receiverMomoNumberHash,integrity_token:'unit-test-only',sms_request:{client_envelope_id:envelope,raw_sender:sms.rawSender,raw_body_sha256:sms.rawBodySha256,received_at_device:sms.receivedAtDevice}};
 const decoded={requestDetails:{requestPackageName:'app.cool.mobile',requestHash:hash,timestampMillis:String(Date.now())},appIntegrity:{packageName:'app.cool.mobile',appRecognitionVerdict:'PLAY_RECOGNIZED',versionCode:'23',certificateSha256Digest:['CERT']},accountDetails:{appLicensingVerdict:license},deviceIntegrity:{deviceRecognitionVerdict:['MEETS_DEVICE_INTEGRITY']}};
 const request=new Request('https://edge.test',{method:'POST',headers:{authorization:'Bearer test','content-type':'application/json'},body:JSON.stringify(payload)});
 const urls=[];let minted=0;global.__service={rpc:async name=>{assert.equal(name,'mint_native_action_capability');minted++;return{data:cap,error:null}}};
 const fetcher=async(url,options)=>{
   urls.push(url);assert.equal(options.redirect,'error');assert.ok(options.signal);
   if(url==='https://oauth2.googleapis.com/token'){
      assert.equal(new URLSearchParams(options.body).get('grant_type'),'urn:ietf:params:oauth:grant-type:jwt-bearer');
      return new Response('{"access_token":"unit-test-access-token"}');
   }
   assert.equal(url,'https://playintegrity.googleapis.com/v1/app.cool.mobile:decodeIntegrityToken');
   return new Response(JSON.stringify({tokenPayloadExternal:decoded}));
 };
 return {request,fetcher,urls,minted:()=>minted};
}
test('Integrity uses documented OAuth grant and fixed endpoint',async()=>{const d=await integritySetup();await fetchMock(d.fetcher,async()=>{const r=await integrityHandler(d.request);assert.equal(r.status,200);assert.equal((await r.json()).status,'pass');assert.equal(d.minted(),1);assert.equal(d.urls.length,2)})});
test('Integrity unlicensed app cannot mint capability',async()=>{const d=await integritySetup('UNLICENSED');await fetchMock(d.fetcher,async()=>{assert.equal((await integrityHandler(d.request)).status,403);assert.equal(d.minted(),0)})});

test('Internal notification endpoints return a stable 401 code without exposing auth internals',async()=>{
  const request=()=>new Request('https://edge.test',{method:'POST',headers:{'content-type':'application/json'},body:'{}'});
  for(const endpoint of [notificationHandler,dispatchHandler]){
    const response=await endpoint(request());
    assert.equal(response.status,401);
    assert.deepEqual(await response.json(),{error:'authentication_required'});
  }
});

test('Notification endpoints suppress SQL and provider exception text',async()=>{
  const privateError=new Error('SQL column and provider token SECRET');
  global.__service={rpc:()=>({abortSignal:async()=>({data:null,error:privateError})})};
  const headers={'content-type':'application/json','x-collect-signature':'test-only-internal'};
  const notification=await notificationHandler(new Request('https://edge.test',{method:'POST',headers,
    body:JSON.stringify({user_id:owner,type:'notice',title:'Test',body:'Test'})}));
  assert.equal(notification.status,503);
  assert.deepEqual(await notification.json(),{error:'service_unavailable'});
  const dispatch=await dispatchHandler(new Request('https://edge.test',{method:'POST',headers,body:'{}'}));
  assert.equal(dispatch.status,500);
  assert.deepEqual(await dispatch.json(),{error:'service_unavailable'});
});

test('Operator error response suppresses internal SQL text',async()=>{
  global.__service={rpc:async()=>({data:null,error:new Error('SQL SECRET from admin_current_user')})};
  const response=await operatorHandler(new Request('https://edge.test',{method:'POST',
    headers:{authorization:operatorAuthorization,'content-type':'application/json'},
    body:JSON.stringify({action:'health'})}));
  assert.equal(response.status,503);
  assert.deepEqual(await response.json(),{error:'service_unavailable'});
});

test('Operator rejects invalid input with a fixed 400 code',async()=>{
  global.__service={rpc:async name=>{
    assert.equal(name,'admin_current_user');
    return {data:{permissions:['notifications.read']},error:null};
  }};
  for(const payload of [{action:'execute_sql',sql:'select secret'}, {action:'list_pending',limit:0}]){
    const response=await operatorHandler(new Request('https://edge.test',{method:'POST',
      headers:{authorization:operatorAuthorization,'content-type':'application/json'},
      body:JSON.stringify(payload)}));
    assert.equal(response.status,400);
    assert.deepEqual(await response.json(),{error:'invalid_request'});
  }
});

test('Operator permission denial does not disclose internal ACL names',async()=>{
  global.__service={rpc:async name=>{
    assert.equal(name,'admin_current_user');
    return {data:{permissions:[]},error:null};
  }};
  const response=await operatorHandler(new Request('https://edge.test',{method:'POST',
    headers:{authorization:operatorAuthorization,'content-type':'application/json'},
    body:JSON.stringify({action:'health'})}));
  assert.equal(response.status,403);
  assert.deepEqual(await response.json(),{error:'forbidden'});
});

test('Operator rejects oversized input before permission or service RPCs',async()=>{
  const calls=[];
  global.__service={rpc:async name=>{calls.push(name);throw new Error('unexpected RPC')}};
  const response=await operatorHandler(new Request('https://edge.test',{method:'POST',
    headers:{authorization:operatorAuthorization,'content-type':'application/json'},
    body:JSON.stringify({action:'health',padding:'x'.repeat(17000)})}));
  assert.equal(response.status,413);
  assert.deepEqual(await response.json(),{error:'payload_too_large'});
  assert.deepEqual(calls,[]);
});

test('Operator authorized health action still returns its result',async()=>{
  const calls=[];
  global.__service={rpc:async (name,params)=>{
    calls.push(name);
    if(name==='admin_current_user')return {data:{permissions:['notifications.read']},error:null};
    assert.equal(name,'collect_notification_health_v2');
    assert.deepEqual(params,{p_operator_user_id:owner,p_operator_session_id:operatorSession});
    return {data:{pending:0},error:null};
  }};
  const response=await operatorHandler(new Request('https://edge.test',{method:'POST',
    headers:{authorization:operatorAuthorization,'content-type':'application/json'},
    body:JSON.stringify({action:'health'})}));
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{ok:true,action:'health',result:{pending:0}});
  assert.deepEqual(calls,['admin_current_user','collect_notification_health_v2']);
});

test('Operator keeps state conflicts distinct from outages without exposing SQL text',async()=>{
  global.__service={rpc:async name=>name==='admin_current_user'
    ? {data:{permissions:['notifications.manage']},error:null}
    : {data:null,error:{code:'P0001',message:'stale claim with private SQL details'}}};
  const response=await operatorHandler(new Request('https://edge.test',{method:'POST',
    headers:{authorization:operatorAuthorization,'content-type':'application/json'},
    body:JSON.stringify({action:'claim',job_id:raw,worker_id:'worker-1',request_id:cap})}));
  assert.equal(response.status,409);
  assert.deepEqual(await response.json(),{error:'conflict'});
});

test('Integrity authentication and missing configuration use stable codes only',async()=>{
  const d=await integritySetup();
  const anonymous=await integrityHandler(new Request('https://edge.test',{method:'POST',
    headers:{'content-type':'application/json'},body:await d.request.clone().text()}));
  assert.equal(anonymous.status,401);
  assert.deepEqual(await anonymous.json(),{error:'authentication_required'});
  const account=env.PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON;
  delete env.PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON;
  try{
    const unavailable=await integrityHandler(d.request);
    assert.equal(unavailable.status,503);
    assert.deepEqual(await unavailable.json(),{error:'play_integrity_unavailable'});
  }finally{env.PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON=account;}
});

test('Integrity invalid private policy does not disclose configuration state',async()=>{
  const d=await integritySetup();
  const original=env.PLAY_INTEGRITY_MIN_VERSION_CODE;
  env.PLAY_INTEGRITY_MIN_VERSION_CODE='invalid-private-policy';
  try{
    await fetchMock(d.fetcher,async()=>{
      const response=await integrityHandler(d.request);
      assert.equal(response.status,503);
      assert.deepEqual(await response.json(),{error:'play_integrity_unavailable'});
      assert.equal(d.minted(),0);
    });
  }finally{env.PLAY_INTEGRITY_MIN_VERSION_CODE=original;}
});

for(const mode of ['1','yes','TRUE',' true ','on','0'])test('OTP ambiguous/dry-run mode blocks: '+mode,async()=>{const c=setup();env.WHATSAPP_CLOUD_DRY_RUN=mode;try{assert.equal((await otpHandler(await otpRequest())).status,503);assert.equal(c.length,0)}finally{delete env.WHATSAPP_CLOUD_DRY_RUN}});

// Dispatch orchestration uses the real handler and isolated provider/SQL adapters.
// Lost persistence acknowledgements must never overwrite an accepted provider send.
test('Dispatch claims one, bounds RPCs and preserves an accepted result when completion fails',async()=>{
  const calls=[];let sends=0;
  env.FCM_SERVICE_ACCOUNT_JSON='{}';
  global.__pushSend=async()=>{sends++;return{ok:true,retryable:false,messageId:'accepted-push',errorCode:null,latencyMs:12}};
  global.__service={rpc:(name,params)=>({abortSignal(signal){
    assert.ok(signal instanceof AbortSignal);assert.equal(signal.aborted,false);
    calls.push({name,params});
    if(name==='claim_notification_deliveries'){
      assert.deepEqual(params,{p_contract_version:2,p_limit:1});
      return Promise.resolve({data:[{delivery_id:raw,event_id:envelope,device_id:cap,user_id:owner,token:'private-token',provider:'fcm',environment:'production',title:'Private',body:'Private body',deep_link:null,event_type:'notice',attempt_number:1,claim_token:cap}],error:null});
    }
    if(name==='notification_delivery_is_current'){assert.equal(params.p_claim_token,cap);return Promise.resolve({data:true,error:null});}
    assert.equal(name,'complete_notification_delivery');
    assert.equal(params.p_success,true);
    assert.equal(params.p_provider_message_id,'accepted-push');
    assert.equal(params.p_attempt_number,1);assert.equal(params.p_claim_token,cap);
    return Promise.resolve({data:null,error:new Error('private SQL persistence failure')});
  }})};
  try{
    const response=await dispatchHandler(new Request('https://edge.test',{method:'POST',headers:{'content-type':'application/json','x-collect-signature':'test-only-internal'},body:'{"limit":100}'}));
    assert.equal(response.status,503);
    const result=await response.json();
    assert.equal(result.ok,false);assert.equal(result.completion_pending,1);
    assert.equal(result.sent,0);assert.equal(result.retrying,0);
    assert.equal(sends,1);assert.equal(calls.length,3);
    assert.ok(!JSON.stringify(result).includes('private'));
  }finally{delete global.__pushSend;delete env.FCM_SERVICE_ACCOUNT_JSON;}
});

test('Dispatch terminal attempt is reported failed after one transport exception',async()=>{
  const completions=[];
  env.FCM_SERVICE_ACCOUNT_JSON='{}';
  global.__pushSend=async()=>{throw new Error('private provider exception')};
  global.__service={rpc:(name,params)=>({abortSignal(signal){
    assert.ok(signal instanceof AbortSignal);
    if(name==='claim_notification_deliveries')return Promise.resolve({data:[{delivery_id:raw,user_id:owner,provider:'fcm',attempt_number:5,claim_token:cap}],error:null});
    if(name==='notification_delivery_is_current')return Promise.resolve({data:true,error:null});
    completions.push(params);return Promise.resolve({data:null,error:null});
  }})};
  try{
    const response=await dispatchHandler(new Request('https://edge.test',{method:'POST',headers:{'content-type':'application/json','x-collect-signature':'test-only-internal'},body:'{"limit":1}'}));
    assert.equal(response.status,200);
    const result=await response.json();
    assert.equal(result.failed,1);assert.equal(result.retrying,0);
    assert.equal(completions.length,1);
    assert.equal(completions[0].p_error_code,'transport_exception');
  }finally{delete global.__pushSend;delete env.FCM_SERVICE_ACCOUNT_JSON;}
});
