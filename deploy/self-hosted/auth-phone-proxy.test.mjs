import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createAuthPhoneProxy} from './auth-phone-proxy.mjs';

const profile={admin_origin:'https://admin.collect.example',environment:'qualification',format:'collect.deployment.v1',google_callback_origin:'https://admin.collect.example',id:'collect-test',member_api_origin:'https://api.collect.example',mode:'self_hosted',public_origin:'https://collect.example',supabase_origin:'https://supabase.collect.example'};
const raw=JSON.stringify(profile),env={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(raw).digest('hex'),SUPABASE_URL:profile.supabase_origin,SUPABASE_INTERNAL_URL:'http://api-gw:8000',APP_ENVIRONMENT:'qualification',AUTH_PHONE_DELIVERY_MODE:'opensms_hook',AUTH_SMS_ENABLED:'true',AUTH_WHATSAPP_ENABLED:'false'};
const request=(path,body,options={})=>new Request(profile.supabase_origin+'/auth/v1'+path,{method:body===undefined?'GET':'POST',headers:{apikey:'sb_publishable_synthetic',...(body===undefined?{}:{'Content-Type':'application/json'})},...(body===undefined?{}:{body:typeof body==='string'?body:JSON.stringify(body)}),...options});
function fixture(overrides={},reply=()=>Response.json({ok:true})){
 const calls=[];return {calls,handle:createAuthPhoneProxy({...env,...overrides},{fetchImpl:async(url,options)=>{calls.push({url,options});return reply(url,options);}})};
}
for(const [path,body] of [
 ['/otp',{phone:'+250788123456',channel:'whatsapp'}],['/signup',{Phone:'+250788123456'}],
 ['/user',{PHONE:null}],['/verify',{TYPE:'phone_change'}],['/resend',{type:'sms',phone:'+250788123456'}],
 ['/otp','{"phone":null,"PHONE":"+250788123456"}'],['/factors',{factor_type:'phone',phone:'+250788123456'}],
 ['/verify?type=phone_change',undefined],['/otp?PHONE=%2B250788123456',{email:'member@example.test'}],
])test('OpenSMS refuses public phone mutation '+path+' '+JSON.stringify(body),async()=>{
 const f=fixture(),result=await f.handle(request(path,body));assert.equal(result.status,403);assert.equal(f.calls.length,0);
 assert.equal((await result.json()).code,'phone_requires_collect');
});

test('email flows, anonymous signup, user read, token and OAuth redirects stay GoTrue-owned',async()=>{
 for(const [path,body] of [['/otp',{email:'member@example.test'}],['/signup',{gotrue_meta_security:{captcha_token:'synthetic'}}],['/user',undefined],['/verify?type=email&token=synthetic',undefined],['/token?grant_type=refresh_token',{refresh_token:'synthetic'}],['/authorize?provider=google',undefined],['/recover',{email:'member@example.test'}],['/resend',{type:'signup',email:'member@example.test'}]]){
  const f=fixture({},()=>new Response(null,{status:303,headers:{Location:'https://accounts.google.com/o/oauth2/auth','Set-Cookie':'synthetic=test; Secure; HttpOnly'}}));
  const result=await f.handle(request(path,body));assert.equal(result.status,303);assert.equal(f.calls.length,1);assert.equal(f.calls[0].url,'http://api-gw:8000/auth/v1'+path);
  assert.equal(f.calls[0].options.redirect,'manual');assert.equal(result.headers.get('Location'),'https://accounts.google.com/o/oauth2/auth');assert.match(result.headers.get('Set-Cookie'),/^synthetic=/);
 }
});

test('email reauthentication is preserved and implicit SMS reauthentication is denied',async()=>{
 for(const email of ['member@example.test',null]){
  const f=fixture({},url=>url.endsWith('/user')?Response.json({id:'synthetic-user',email,phone:'250788123456'}):Response.json({ok:true}));
  const result=await f.handle(request('/reauthenticate',undefined,{headers:{Authorization:'Bearer synthetic',apikey:'sb_publishable_synthetic'}}));
  assert.equal(result.status,email?200:403);assert.equal(f.calls.length,email?2:1);assert.equal(f.calls[0].options.method,'GET');
 }
});

test('native guest identity changes cannot bypass the same-identity Collect upgrade journal',async()=>{
 for(const mode of ['opensms_hook','twilio'])for(const anonymous of [true,false])for(const path of ['/user','/user/identities/authorize?provider=google']){
  const f=fixture({AUTH_PHONE_DELIVERY_MODE:mode},(url,options)=>url.endsWith('/user')&&options.method==='GET'?Response.json({id:'synthetic-user',is_anonymous:anonymous}):Response.json({ok:true}));
  const result=await f.handle(request(path,path==='/user'?{email:'member@example.test'}:undefined,{method:path==='/user'?'PUT':'GET',headers:{Authorization:'Bearer synthetic',apikey:'sb_publishable_synthetic','Content-Type':'application/json'}}));
  assert.equal(result.status,anonymous?403:200);assert.equal(f.calls.length,anonymous?1:2);
 }
});

test('MFA challenge and verify consult the trusted native factor, never caller claims',async()=>{
 for(const method of ['challenge','verify'])for(const type of ['phone','totp',null]){
  const f=fixture({},url=>url.endsWith('/user')?Response.json({id:'synthetic-user',factors:type?[{id:'factor-1',factor_type:type}]:[]}):Response.json({ok:true}));
  const result=await f.handle(request('/factors/factor-1/'+method,{code:'123456'},{headers:{Authorization:'Bearer synthetic',apikey:'sb_publishable_synthetic','Content-Type':'application/json','X-Forwarded-User':'trusted-totp'}}));
  assert.equal(result.status,type==='totp'?200:403);assert.equal(f.calls.length,type==='totp'?2:1);
 }
});

test('native provider modes preserve phone channels without an OpenSMS fallback',async()=>{
 for(const mode of ['twilio','twilio_verify']){
  const f=fixture({AUTH_PHONE_DELIVERY_MODE:mode,AUTH_WHATSAPP_ENABLED:'true'}),result=await f.handle(request('/otp',{phone:'+250788123456',channel:'whatsapp'}));
  assert.equal(result.status,200);assert.equal(f.calls.length,1);assert.equal(JSON.parse(new TextDecoder().decode(f.calls[0].options.body)).channel,'whatsapp');
 }
});

test('profile identity, environment, fixed internal destination and mutually exclusive modes fail closed',async()=>{
 for(const override of [{COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)},{SUPABASE_URL:'https://other.collect.example'},{SUPABASE_INTERNAL_URL:'http://attacker:8000'},{APP_ENVIRONMENT:'production'},{AUTH_PHONE_DELIVERY_MODE:'unknown'},{AUTH_WHATSAPP_ENABLED:'true'}]){
  const f=fixture(override);assert.equal((await f.handle(request('/user'))).status,503);assert.equal(f.calls.length,0);
 }
});

test('public origin is exact and untrusted forwarding headers never reach the private gateway',async()=>{
 const f=fixture(),headers={Authorization:'Bearer synthetic',apikey:'sb_publishable_synthetic',Origin:profile.admin_origin,'X-Forwarded-Host':'attacker.example','X-Forwarded-For':'1.2.3.4',Forwarded:'host=attacker.example','X-Real-IP':'1.2.3.4',Host:'attacker.example'};
 const response=await f.handle(request('/user',undefined,{headers}));assert.equal(response.status,200);
 const sent=f.calls[0].options.headers;for(const key of ['Host','X-Forwarded-Host','X-Forwarded-For','X-Real-IP','Forwarded'])assert.equal(sent.has(key),false);
 assert.equal(sent.get('Authorization'),'Bearer synthetic');assert.equal(response.headers.get('Access-Control-Allow-Origin'),profile.admin_origin);
 assert.equal((await f.handle(new Request('https://evil.example/auth/v1/user'))).status,421);
 assert.equal((await f.handle(request('/user',undefined,{headers:{Origin:'https://evil.example'}}))).status,403);assert.equal(f.calls.length,1);
});

test('bounded, object-only JSON and encoded-path aliases are rejected before mutation',async()=>{
 const f=fixture();
 for(const req of [request('/otp','{'),request('/otp',[]),request('/otp','null'),request('/otp',{email:'x'.repeat(17000)}),request('/otp','phone=x',{headers:{'Content-Type':'application/x-www-form-urlencoded'}}),request('/%6ftp',{email:'member@example.test'}),request('/factors%2ffactor-1/challenge',{})]){
  assert([400,413,415].includes((await f.handle(req)).status));
 }
 assert.equal(f.calls.length,0);
});

test('preflight is bounded to configured browser origins and reviewed headers',async()=>{
 const f=fixture(),headers={Origin:profile.public_origin,'Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'apikey,content-type,authorization'};
 assert.equal((await f.handle(request('/otp',undefined,{method:'OPTIONS',headers}))).status,204);
 assert.equal((await f.handle(request('/otp',undefined,{method:'OPTIONS',headers:{...headers,'Access-Control-Request-Headers':'x-forwarded-for'}}))).status,403);
 assert.equal(f.calls.length,0);
});

test('network failures and oversized provider replies never expose credentials or partial bodies',async()=>{
 for(const reply of [()=>{throw new TypeError('Bearer secret must not appear');},()=>new Response('secret'.repeat(15000))]){
  const f=fixture({},reply),response=await f.handle(request('/user'));assert.equal(response.status,503);assert(!((await response.text()).includes('secret')));
 }
});

function fragmented(bytes,emptyPerByte=1){
 let position=0,empty=0;
 return new ReadableStream({pull(controller){
  if(position===bytes.length){controller.close();return;}
  if(empty++<emptyPerByte){controller.enqueue(new Uint8Array());return;}
  empty=0;controller.enqueue(bytes.subarray(position,++position));
 }});
}

test('fragmented request and upstream bodies respect byte limits and preserve bytes',async()=>{
 const encoder=new TextEncoder(),requestText='{"email":"'+'x'.repeat(16372)+'"}';
 const requestBytes=encoder.encode(requestText);assert.equal(requestBytes.length,16384);
 for(const extra of [0,1]){
  const bytes=extra?encoder.encode(requestText+' '):requestBytes,f=fixture();
  const input=new Request(profile.supabase_origin+'/auth/v1/recover',{method:'POST',duplex:'half',headers:{'Content-Type':'application/json'},body:fragmented(bytes)});
  const result=await f.handle(input);assert.equal(result.status,extra?413:200);assert.equal(f.calls.length,extra?0:1);
  if(!extra)assert.deepEqual(f.calls[0].options.body,requestBytes);
 }
 for(const extra of [0,1]){
  const bytes=new Uint8Array(65536+extra).fill(97),f=fixture({},()=>new Response(fragmented(bytes,0)));
  const response=await f.handle(request('/user'));assert.equal(response.status,extra?503:200);
  if(!extra)assert.deepEqual(new Uint8Array(await response.arrayBuffer()),bytes);
 }
});

test('abort cancels a stalled incoming stream without invoking the provider',async()=>{
 const aborter=new AbortController();let started,cancelled=false;
 const pending=new Promise(resolve=>{started=resolve;});
 const body=new ReadableStream({pull(){started();return new Promise(()=>{});},cancel(){cancelled=true;}});
 const f=fixture(),input=new Request(profile.supabase_origin+'/auth/v1/recover',{method:'POST',duplex:'half',headers:{'Content-Type':'application/json'},body,signal:aborter.signal});
 const operation=f.handle(input);await pending;aborter.abort();
 const response=await operation;assert.equal(response.status,503);assert.equal(f.calls.length,0);assert.equal(cancelled,true);
});

test('upstream abort returns promptly even when cancellation rejects or never settles',async()=>{
 for(const cancellation of ['reject','pending']){
  const aborter=new AbortController();let started,rejectRead,cancelled=0;
  const pending=new Promise(resolve=>{started=resolve;});
  const body={getReader(){return {
   read(){started();return new Promise((_,reject)=>{rejectRead=reject;});},
   cancel(){cancelled++;return cancellation==='reject'?Promise.reject(Error('synthetic cancel')):new Promise(()=>{});},
  };}};
  const f=fixture({},()=>({status:200,body,headers:new Headers()}));
  const operation=f.handle(request('/user',undefined,{signal:aborter.signal}));
  await pending;aborter.abort();let timer;
  const response=await Promise.race([operation,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('abort did not settle')),1000);})]).finally(()=>clearTimeout(timer));
  assert.equal(response.status,503);assert.equal(cancelled,1);assert.equal(f.calls.length,1);
  rejectRead(Error('synthetic late read'));await new Promise(resolve=>setImmediate(resolve));
 }
});

test('a non-byte upstream chunk fails closed',async()=>{
 const f=fixture({},()=>new Response(new ReadableStream({start(controller){controller.enqueue('not bytes');controller.close();}})));
 assert.equal((await f.handle(request('/user'))).status,503);
});

test('OpenSMS token grants inspect JSON bytes independently of Content-Type',async()=>{
 const phoneBodies=[
  '{"phone":"+250700000000","password":"synthetic"}',
  '{"PHONE":"+250700000000","password":"synthetic"}',
  '{"\\u0070hone":"+250700000000","password":"synthetic"}',
  '{"phone":"+250700000000","phone":null}',
  '{"phone":null,"phone":"+250700000000"}',
  '{"Phone":"+250700000000","PHONE":null}',
  '{"PHONE":null,"Phone":"+250700000000"}',
 ];
 for(const contentType of ['application/json','text/plain','application/octet-stream','']){
  for(const body of phoneBodies){
   const f=fixture(),headers={apikey:'synthetic','Content-Type':contentType};
   const response=await f.handle(request('/token?grant_type=password',body,{headers}));
   assert.equal(response.status,403);assert.equal(f.calls.length,0);
  }
 }
 const missing=fixture(),headers=new Headers({apikey:'synthetic'});
 const input=new Request(profile.supabase_origin+'/auth/v1/token?grant_type=password',{method:'POST',headers,body:new TextEncoder().encode(phoneBodies[0])});
 assert.equal((await missing.handle(input)).status,403);assert.equal(missing.calls.length,0);
 for(const path of ['/token/?grant_type=password','/token?grant_type=password&PHONE=synthetic']){
  const f=fixture();const response=await f.handle(request(path,phoneBodies[0],{headers:{'Content-Type':'text/plain'}}));
  assert.equal(response.status,403);assert.equal(f.calls.length,0);
 }
 const queryOnly=fixture();
 assert.equal((await queryOnly.handle(request('/token?grant_type=password&PHONE=synthetic','{"email":"member@example.invalid","password":"synthetic"}',{headers:{'Content-Type':'text/plain'}}))).status,403);
 assert.equal(queryOnly.calls.length,0);
 const slashAllowed=fixture();
 assert.equal((await slashAllowed.handle(request('/token/?grant_type=refresh_token','{"refresh_token":"synthetic"}',{headers:{'Content-Type':'text/plain'}}))).status,200);
 assert.equal(slashAllowed.calls.length,1);
 for(const body of ['{','[]','null','"value"']){
  const f=fixture();const response=await f.handle(request('/token?grant_type=password',body,{headers:{'Content-Type':'text/plain'}}));
  assert.equal(response.status,400);assert.equal(f.calls.length,0);
 }
 const invalid=fixture();const bad=new Request(profile.supabase_origin+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'Content-Type':'text/plain'},body:new Uint8Array([0xff])});
 assert.equal((await invalid.handle(bad)).status,400);assert.equal(invalid.calls.length,0);
});

test('OpenSMS retains email and refresh grants; native modes retain phone grants',async()=>{
 for(const [grant,body] of [['password','{"email":"member@example.invalid","password":"synthetic"}'],['refresh_token','{"refresh_token":"synthetic"}']]){
  for(const contentType of ['application/json','text/plain','']){
   const f=fixture();const response=await f.handle(request('/token?grant_type='+grant,body,{headers:{'Content-Type':contentType}}));
   assert.equal(response.status,200);assert.equal(f.calls.length,1);
   assert.equal(new TextDecoder().decode(f.calls[0].options.body),body);
   assert.equal(f.calls[0].options.headers.get('Content-Type'),contentType);
  }
 }
 for(const mode of ['twilio','twilio_verify'])for(const contentType of ['application/json','text/plain']){
  const body='{"phone":"+250700000000","password":"synthetic"}',f=fixture({AUTH_PHONE_DELIVERY_MODE:mode});
  const response=await f.handle(request('/token?grant_type=password',body,{headers:{'Content-Type':contentType}}));
  assert.equal(response.status,200);assert.equal(f.calls.length,1);assert.equal(new TextDecoder().decode(f.calls[0].options.body),body);
 }
});
