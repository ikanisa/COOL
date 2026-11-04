import test,{before} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {generateKeyPairSync,verify} from 'node:crypto';
import {createFcmSender,androidNotificationMessage,fcmRetryAfter,validPushAdmission} from '../fcm-notifications.js';

const at=1793232000,project='synthetic-collect',androidPackage='app.cool.mobile';
let pair,credential;
before(()=>{pair=generateKeyPairSync('rsa',{modulusLength:2048});credential={type:'service_account',project_id:project,private_key_id:'synthetic-key',client_email:'synthetic@'+project+'.iam.gserviceaccount.com',
 private_key:pair.privateKey.export({type:'pkcs8',format:'pem'}),token_uri:'https://oauth2.googleapis.com/token',universe_domain:'googleapis.com'};});
const environment=()=>({FCM_PROJECT_ID:project,FCM_ANDROID_PACKAGE:androidPackage,FCM_SERVICE_ACCOUNT_JSON:JSON.stringify(credential)});
const payload=()=>androidNotificationMessage({eventId:'00000000-0000-4000-8000-000000000001',recipientId:'00000000-0000-4000-8000-000000000002',token:'synthetic-registration-token',androidPackage});
const oauth=()=>Response.json({access_token:'synthetic-oauth-token',token_type:'Bearer',expires_in:3600});
const error=(status,code,fcmCode,headers={})=>Response.json({error:{code:status,status:code,...(fcmCode?{details:[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:fcmCode}]}:{})}},{status,headers});

test('Android payload exactly matches the shared consumer fixture and contains no financial facts',async()=>{
 const fixture=JSON.parse(await readFile(new URL('./fixtures/android-contribution-push.fixture.json',import.meta.url),'utf8'));
 assert.deepEqual(payload(),fixture);assert.deepEqual(Object.keys(payload().data).sort(),['collect_event_id','collect_push_version','deep_link','recipient_id','type']);
 for(const bad of [{token:'bad token'},{eventId:'not-an-id'},{recipientId:'not-an-id'},{androidPackage:'different.app'}])assert.throws(()=>androidNotificationMessage({eventId:payload().data.collect_event_id,recipientId:payload().data.recipient_id,token:payload().token,androidPackage,...bad}));
});
test('FCM OAuth uses verified RS256, fixed audience/scope and explicit bounded v1 Android send',async()=>{
 const calls=[],sender=createFcmSender(environment(),{now:()=>at,fetchImpl:async(url,options)=>{
  calls.push({url,options});assert.equal(options.redirect,'error');assert(options.signal instanceof AbortSignal);
  if(calls.length===1){
   assert.equal(url,'https://oauth2.googleapis.com/token');const form=new URLSearchParams(options.body);assert.equal(form.get('grant_type'),'urn:ietf:params:oauth:grant-type:jwt-bearer');
   const [header,claims,signature]=form.get('assertion').split('.');
   assert.deepEqual(JSON.parse(Buffer.from(header,'base64url')),{alg:'RS256',typ:'JWT',kid:credential.private_key_id});
   assert.deepEqual(JSON.parse(Buffer.from(claims,'base64url')),{iss:credential.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:url,iat:at,exp:at+300});
   assert.equal(verify('RSA-SHA256',Buffer.from(header+'.'+claims),pair.publicKey,Buffer.from(signature,'base64url')),true);
   return oauth();
  }
  assert.equal(url,'https://fcm.googleapis.com/v1/projects/'+project+'/messages:send');assert.equal(options.headers.Authorization,'Bearer synthetic-oauth-token');
  assert.deepEqual(JSON.parse(options.body),{validate_only:false,message:payload()});return Response.json({name:'projects/'+project+'/messages/0:synthetic%accepted'});
 }});
 const prepared=await sender.prepare();assert.equal(prepared.kind,'ready');const outcome=await prepared.send(payload());
 assert.deepEqual(outcome,{kind:'accepted',messageId:'projects/'+project+'/messages/0:synthetic%accepted',httpStatus:200});
 assert.equal((await sender.prepare()).kind,'ready');assert.equal(calls.length,2,'A still-current token is reused only in this adapter instance');
 assert.equal(JSON.stringify(outcome).includes('synthetic-oauth-token'),false);assert.equal(JSON.stringify(outcome).includes('registration-token'),false);
});
test('configuration cannot redirect OAuth, impersonate a user or target a different project/package',()=>{
 for(const patch of [{FCM_PROJECT_ID:'different-project'},{FCM_ANDROID_PACKAGE:'unreviewed.app'},
  {FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({...credential,token_uri:'https://evil.example/token'})},
  {FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({...credential,client_email:'other@different-project.iam.gserviceaccount.com'})},
  {FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({...credential,universe_domain:'evil.example'})}])assert.throws(()=>createFcmSender({...environment(),...patch}));
});
test('only confirmed UNREGISTERED disables a device, while invalid payload errors leave registration intact',async()=>{
 for(const [response,expected]of [[error(404,'NOT_FOUND','UNREGISTERED'),{kind:'rejected',code:'invalid_registration',httpStatus:404,disableDevice:true}],
  [error(400,'INVALID_ARGUMENT','INVALID_ARGUMENT'),{kind:'rejected',code:'provider_request_rejected',httpStatus:400}],
  [error(403,'PERMISSION_DENIED','SENDER_ID_MISMATCH'),{kind:'rejected',code:'provider_auth_rejected',httpStatus:403}]]){
  let calls=0;const sender=createFcmSender(environment(),{now:()=>at,fetchImpl:async()=>++calls===1?oauth():response});
  assert.deepEqual(await(await sender.prepare()).send(payload()),expected);assert.equal(calls,2);
 }
});
test('explicit throttling/unavailability honors Retry-After without an inline resend',async()=>{
 for(const [response,delay,kind]of [[error(429,'RESOURCE_EXHAUSTED','QUOTA_EXCEEDED',{'Retry-After':'120'}),120,'retry'],
  [error(503,'UNAVAILABLE',null,{'Retry-After':new Date((at+180)*1000).toUTCString()}),180,'retry'],
  [error(500,'INTERNAL'),0,'retry'],[error(503,'UNAVAILABLE',null,{'Retry-After':'999999999'}),undefined,'rejected']]){
  let calls=0;const sender=createFcmSender(environment(),{now:()=>at,fetchImpl:async()=>++calls===1?oauth():response}),outcome=await(await sender.prepare()).send(payload());
  assert.equal(outcome.kind,kind);assert.equal(outcome.retryAfterSeconds,delay);assert.equal(calls,2);
 }
 assert.equal(fcmRetryAfter('not-a-date',at),null);
});
test('send timeout, malformed/oversized success, unknown error and mismatched project remain terminal uncertainty candidates',async()=>{
 const responses=[()=>{throw Error('timeout containing token must not escape');},()=>new Response('{'),
  ()=>new Response('x'.repeat(16385)),()=>Response.json({name:'projects/other-project/messages/accepted'}),
  ()=>Response.json({error:{status:'unrecognized'}},{status:503}),()=>new Response('forbidden',{status:403})];
 for(const response of responses){let calls=0;const observed=[];const sender=createFcmSender(environment(),{now:()=>at,onUncertain:label=>observed.push(label),fetchImpl:async()=>++calls===1?oauth():response()}),outcome=await(await sender.prepare()).send(payload());
  assert.equal(outcome.kind,'unknown');assert.equal(outcome.code,'delivery_unconfirmed');assert.equal(calls,2);assert.equal(JSON.stringify(outcome).includes('token'),false);
  assert.deepEqual(observed,['push'],'Semantic uncertainty must also reach the source-fence observation');
 }
});
test('OAuth uncertainty sends no notification and arbitrary provider payload expansion is refused before network dispatch',async()=>{
 let calls=0;const unavailable=createFcmSender(environment(),{fetchImpl:async()=>{calls++;throw Error('synthetic OAuth timeout');}});
 const outcome=await unavailable.prepare();assert.equal(outcome.kind,'retry');assert.equal(outcome.code,'provider_auth_unavailable');assert.equal(calls,1);
 const sender=createFcmSender(environment(),{fetchImpl:async()=>{calls++;return oauth();}}),prepared=await sender.prepare(),before=calls;
 for(const changed of [{...payload(),data:{...payload().data,amount:'999'}},{...payload(),notification:{title:'Private financial balance',body:'sensitive'}},{...payload(),topic:'unapproved'}])assert.equal((await prepared.send(changed)).code,'invalid_push_payload');
 assert.equal(calls,before);
});
test('OAuth throttling preserves Retry-After even with an unreadable body and refuses unreviewed delays',async()=>{
 for(const [response,kind,delay,code]of [
  [Response.json({error:'temporarily_unavailable'},{status:429,headers:{'Retry-After':'180'}}),'retry',180,'provider_auth_unavailable'],
  [new Response('{',{status:503,headers:{'Retry-After':new Date((at+240)*1000).toUTCString()}}),'retry',240,'provider_auth_unavailable'],
  [Response.json({error:'temporarily_unavailable'},{status:503,headers:{'Retry-After':'999999999'}}),'rejected',undefined,'retry_after_unreviewed'],
 ]){
  let calls=0;const sender=createFcmSender(environment(),{now:()=>at,fetchImpl:async()=>{calls++;return response;}});
  const result=await sender.prepare();assert.equal(result.kind,kind);assert.equal(result.retryAfterSeconds,delay);assert.equal(result.code,code);assert.equal(calls,1);
 }
});
test('push admission is exact, bounded and binds reviewed source/project/package/start-time/approval',()=>{
 const input={contract:'collect.android-push.v1',source_sha256:'a'.repeat(64),approval_sha256:'b'.repeat(64),project_id:project,android_package:androidPackage,admitted_from:at,batch_limit:1};
 assert.equal(validPushAdmission(input),true);for(const patch of [{batch_limit:2},{admitted_from:String(at)},{source_sha256:'invalid'},{android_package:'app.cool.mobile.gateway'},{extra:true}])assert.equal(validPushAdmission({...input,...patch}),false);
});
