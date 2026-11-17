// Actual admission/OTP/verification/route source with explicit SQL and HTTP
// models. Real PostgreSQL/RLS is covered separately by managed-email-contract.sql.
import {test} from '../helpers/fenced-node-test.js';
import {ownFixtureWork,syntheticFenceBackend} from '../helpers/fenced-unit.js';
import {openApplicationWork} from '../../application-fence.js';
import assert from 'node:assert/strict';
import {admitManagedEmailOtp,MANAGED_EMAIL_OTP_PATH} from '../../domain/burimunsi/managed-email-otp.js';
import {startOtp,verifyOtp} from '../../domain/auth.js';
import {collectNativeRoute,createCollectNativeRoute} from '../../domain/burimunsi/collect-route.js';
import {canonicalProfile} from '../../deployment-profile.js';
import {digest} from '../../domain/core.js';

const ORIGIN='https://native-preauth.example.invalid',EMAIL='operator@example.invalid';
const INSTALL='b1000000-0000-4000-8000-000000000001',AUTH='b2000000-0000-4000-8000-000000000001';
const SESSION='b3000000-0000-4000-8000-000000000001',DEVICE='a'.repeat(64),NETWORK='b'.repeat(64);
const profile={format:'collect.deployment.v1',id:'native-preauth-fixture',mode:'self_hosted',environment:'qualification',
 supabase_origin:ORIGIN,member_api_origin:'https://api.example.invalid',admin_origin:'https://admin.example.invalid',
 public_origin:'https://public.example.invalid',google_callback_origin:'https://admin.example.invalid'};
const request=(body={email:EMAIL,profile:'staff'},headers={},path=MANAGED_EMAIL_OTP_PATH)=>new Request(ORIGIN+path,
 {method:'POST',headers:{'Content-Type':'application/json','X-BuriMunsi-Installation':INSTALL,'X-BuriMunsi-Device':DEVICE,
  Origin:ORIGIN,...headers},body:JSON.stringify(body)});
const rejected=code=>error=>error.code===code;
async function fixture(options={}){
 const state={sql:[],http:[],challenge:null,current:true};
 const db={setClaims(value){state.claims=value;},prepare(sql){return {bind(...args){return {
  async first(){
   state.sql.push({sql,args});
   if(sql.includes('burimunsi_managed_email_reserve')){
    if(options.reserveFailure)throw Error('synthetic lost reservation ACK');
    if(options.denied)return {result:{allowed:false,code:options.denied}};
    const [id,installation,hash,email,deviceProfile,network,ttl]=args;
    assert.equal(installation,INSTALL);assert.equal(email,EMAIL);assert.equal(network,NETWORK);
    assert.equal(args.length,7);assert.ok(Number.isSafeInteger(ttl)&&ttl>=60&&ttl<=1800);
    assert.ok(['staff','internal_receiver'].includes(deviceProfile));
    const createdAt=Math.floor(Date.now()/1000);
    state.challenge={id,identity_type:'email',identity_value:EMAIL,surface:'admin',native_preauth:true,
     created_at:createdAt,expires_at:createdAt+ttl,delivery_status:'reserved',attempts:0};
    options.onReserve?.(state);
    return {result:{allowed:true,challengeId:id,collectionId:'fixture-group',createdAt,expiresAt:state.challenge.expires_at,...options.reservation}};
   }
   if(sql.includes('burimunsi_managed_email_assert')){
    options.onAssert?.(state);
    const [id,subject,consume]=args;assert.equal(id,state.challenge.id);
    if(subject!==null&&subject!==AUTH)return {allowed:false};
    if(consume&&state.current)state.challenge.consumed_at=Math.floor(Date.now()/1000);
    return {allowed:state.current};
   }
   if(sql.startsWith('UPDATE private.supabase_otp_challenges pending SET attempts')){
    state.challenge.attempts++;return {...state.challenge};
   }
   if(sql.startsWith('SELECT a.id FROM admin_users'))return {id:'existing-admin'};
   throw Error('Unexpected SQL '+sql);
  },async run(){state.sql.push({sql,args});
   assert.ok(sql.startsWith('UPDATE private.supabase_otp_challenges SET delivery_status='));
   state.challenge.delivery_status=args[0];return {success:true};
  }};}};},async batch(statements){state.sql.push({batch:statements});return [];}};
 const work=ownFixtureWork(await openApplicationWork({backend:syntheticFenceBackend(),sourceSha256:'a'.repeat(64),kind:'http_collect'}));
 const env={DB:db,COLLECT_FENCE_WORK:work,BURIMUNSI_NATIVE_ENABLED:'true',SUPABASE_URL:ORIGIN,
  SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_only',SUPABASE_SERVICE_ROLE_KEY:'sb_secret_synthetic_only',
  COLLECT_DEPLOYMENT_PROFILE:canonicalProfile(profile),COLLECT_DEPLOYMENT_PROFILE_SHA256:await digest(canonicalProfile(profile)),
  ...(Object.hasOwn(options,'adminTtl')?{COLLECT_ADMIN_EMAIL_OTP_TTL_SECONDS:options.adminTtl}:{})};
 db.applicationWork=work;env.BUILD_SOURCE_ID='a'.repeat(64);
 const oldFetch=globalThis.fetch;
 globalThis.fetch=async(url,init)=>{
  const call={url:String(url),...init,body:init.body===undefined?null:JSON.parse(init.body)};state.http.push(call);
  if(new URL(call.url).pathname==='/auth/v1/otp'){
   assert.equal(call.url,ORIGIN+'/auth/v1/otp?redirect_to='+encodeURIComponent(profile.admin_origin));
   if(options.dispatch)options.dispatch(state);
   if(options.unknown)throw Error('synthetic uncertain send');
   return Response.json({});
  }
  if(call.url.endsWith('/verify')){
   if(options.verify)options.verify(state);
   const claims={sub:options.subject??AUTH,session_id:SESSION,role:'authenticated',aud:'authenticated',
    iss:ORIGIN+'/auth/v1',exp:Math.floor(Date.now()/1000)+3600};
   const access_token=[Buffer.from('{}').toString('base64url'),Buffer.from(JSON.stringify(claims)).toString('base64url'),'synthetic'].join('.');
   return Response.json({access_token});
  }
  if(call.url.endsWith('/user'))return Response.json({id:options.subject??AUTH,email:EMAIL,email_confirmed_at:'2026-11-10T00:00:00Z',is_anonymous:false});
  if(call.url.endsWith('/logout?scope=local'))return new Response(null,{status:204});
  throw Error('Unexpected Auth request');
 };
 return {env,state,close(){globalThis.fetch=oldFetch;}};
}
async function send(f,overrides={}){
 const admitted=await admitManagedEmailOtp(request(),f.env,{profile,networkBucket:async()=>NETWORK});
 return startOtp(f.env,{email:admitted.email,surface:'admin',...overrides},{nativeAdmission:admitted.admission});
}

test('registered-phone request reserves exact device/network identity before privileged existing-user OTP',async()=>{
 const f=await fixture();try{
  const result=await send(f,{admin:false,should_create_user:true,captcha_token:'client-cannot-select-admin',redirect_to:'https://foreign.invalid'});
  assert.equal(result.delivery_status,'accepted');assert.equal(f.state.http.length,1);
  const call=f.state.http[0];assert.equal(call.url,ORIGIN+'/auth/v1/otp?redirect_to='+encodeURIComponent(profile.admin_origin));
  assert.equal(call.headers.apikey,f.env.SUPABASE_SERVICE_ROLE_KEY);assert.equal(call.body.create_user,false);
  assert.equal(call.body.email,EMAIL);assert.equal(call.headers.Authorization,undefined,'Opaque secret is translated only by the real Kong boundary');
  const reserved=f.state.sql.find(x=>x.sql?.includes('managed_email_reserve'));
  assert.equal(reserved.args[6],1800);assert.equal(f.state.challenge.expires_at-f.state.challenge.created_at,1800);
  assert.ok(result.expires_in>0&&result.expires_in<=1800);
  assert.equal(reserved.args[2],await digest(DEVICE));assert.notEqual(reserved.args[2],DEVICE);
  assert.ok(f.state.sql.some(x=>x.sql?.includes('managed_email_assert')));
 }finally{f.close();}
});
for(const ttl of ['60','300','1800'])test('managed Admin reservation uses only server TTL '+ttl,async()=>{
 const f=await fixture({adminTtl:ttl});try{
  const result=await send(f,{ttl_seconds:999999,expires_in:999999});
  const reserved=f.state.sql.find(x=>x.sql?.includes('managed_email_reserve'));assert.equal(reserved.args[6],Number(ttl));
  assert.equal(f.state.challenge.expires_at-f.state.challenge.created_at,Number(ttl));assert.ok(result.expires_in>0&&result.expires_in<=Number(ttl));
 }finally{f.close();}
});
for(const reservation of [{createdAt:null},{expiresAt:null},{createdAt:1,expiresAt:1801}])test('unconfirmed SQL reservation deadline cannot dispatch Auth',async()=>{
 const f=await fixture({reservation});try{await assert.rejects(send(f),rejected('native_email_reservation_unconfirmed'));assert.equal(f.state.http.length,0);assert.ok(f.state.challenge);}finally{f.close();}
});
for(const code of ['native_email_admission_denied','auth_rate_limited'])test('SQL '+code+' prevents any Auth request',async()=>{
 const f=await fixture({denied:code});try{await assert.rejects(send(f),rejected(code));assert.equal(f.state.http.length,0);}finally{f.close();}
});
test('lost reserve commit cannot dispatch email or retry through another path',async()=>{
 const f=await fixture({reserveFailure:true});try{await assert.rejects(send(f));assert.equal(f.state.http.length,0);}finally{f.close();}
});
test('uncertain provider result retains original challenge and shared cooldown',async()=>{
 const f=await fixture({unknown:true});try{const r=await send(f);assert.equal(r.delivery_status,'unknown');
  assert.equal(r.challenge_id,f.state.challenge.id);assert.equal(f.state.http.length,1);assert.equal(r.retry_after,60);
 }finally{f.close();}
});
test('forged server admission and body flag never select privileged OTP',async()=>{
 const f=await fixture();try{
  await assert.rejects(startOtp(f.env,{email:EMAIL,surface:'admin'},{nativeAdmission:{}}),rejected('native_email_admission_denied'));
  assert.equal(f.state.http.length,0);
  f.state.challenge={id:AUTH,delivery_status:'reserved'};
  await startOtp(f.env,{email:EMAIL,surface:'admin',admin:true,nativeAdmission:{},captcha_token:'public-fixture-token'});
  assert.equal(f.state.http[0].headers.apikey,f.env.SUPABASE_PUBLISHABLE_KEY);
  assert.equal(f.state.http[0].body.gotrue_meta_security.captcha_token,'public-fixture-token');
 }finally{f.close();}
});
test('attestation failure precedes body parsing and all DB/Auth I/O',async()=>{
 const f=await fixture();try{
  await assert.rejects(admitManagedEmailOtp(request(),f.env,{profile,networkBucket:async()=>{throw Error('not attested');}}));
  assert.deepEqual(f.state.sql,[]);assert.deepEqual(f.state.http,[]);
 }finally{f.close();}
});
for(const phase of ['onReserve','onAssert'])test('caller abort during '+phase+' retains reservation without sending email',async()=>{
 const controller=new AbortController(),f=await fixture({[phase]:()=>controller.abort()});try{
  const admitted=await admitManagedEmailOtp(new Request(request(),{signal:controller.signal}),f.env,{profile,networkBucket:async()=>NETWORK});
  await assert.rejects(startOtp(f.env,{email:admitted.email,surface:'admin'},{nativeAdmission:admitted.admission}));
  assert.ok(f.state.challenge,'Committed reservation/cooldown is retained');assert.equal(f.state.http.length,0);
 }finally{f.close();}
});
for(const email of ['a\u0000@example.invalid','a\u001f@example.invalid','a\u007f@example.invalid','a@@example.invalid'])
 test('native preauth rejects invalid email before SQL/provider',async()=>{
  const f=await fixture();try{
   await assert.rejects(admitManagedEmailOtp(request({email,profile:'staff'}),f.env,{profile,networkBucket:async()=>NETWORK}),rejected('invalid_request'));
   assert.deepEqual(f.state.sql,[]);assert.deepEqual(f.state.http,[]);
  }finally{f.close();}
 });
for(const headers of [{'X-BuriMunsi-Device':'bad'},{Origin:'https://foreign.invalid'},
 {'Cookie':'session=untrusted'},{'X-BuriMunsi-Collect-Session':'untrusted'}])test('unexpected preauth credential/origin refuses before SQL/Auth',async()=>{
 const f=await fixture();try{await assert.rejects(admitManagedEmailOtp(request(undefined,headers),f.env,{profile,networkBucket:async()=>NETWORK}));
  assert.deepEqual(f.state.sql,[]);assert.deepEqual(f.state.http,[]);
 }finally{f.close();}
});
for(const body of [{email:EMAIL,profile:'staff',admin:true},{email:EMAIL,profile:'admin'},{email:EMAIL,profile:'staff',collectionId:'other'}])
 test('preauth rejects added authority selectors',async()=>{const f=await fixture();try{
  await assert.rejects(admitManagedEmailOtp(request(body),f.env,{profile,networkBucket:async()=>NETWORK}));assert.equal(f.state.http.length,0);
 }finally{f.close();}});
test('native verification rechecks versions and exact real Auth subject, then atomically consumes',async()=>{
 const f=await fixture();try{const r=await send(f);await verifyOtp(f.env,{challenge_id:r.challenge_id,code:'001234',surface:'admin'},{project:false});
  assert.ok(f.state.challenge.consumed_at);const calls=f.state.sql.filter(x=>x.sql?.includes('managed_email_assert'));
  assert.deepEqual(calls.at(-1).args,[r.challenge_id,AUTH,true]);
  assert.equal(f.state.http.filter(x=>x.url.endsWith('/verify')).length,1);
 }finally{f.close();}
});
for(const options of [{subject:INSTALL},{verify:state=>{state.current=false;}}])test('identity/version change during verification revokes provider session and cannot consume',async()=>{
 const f=await fixture(options);try{const r=await send(f);
  await assert.rejects(verifyOtp(f.env,{challenge_id:r.challenge_id,code:'001234',surface:'admin'},{project:false}),rejected('native_email_admission_denied'));
  assert.equal(f.state.challenge.consumed_at,undefined);assert.equal(f.state.http.at(-1).url,ORIGIN+'/auth/v1/logout?scope=local');
 }finally{f.close();}
});
test('revocation or rollout disable after send refuses before provider verification',async()=>{
 for(const disable of [false,true]){const f=await fixture();try{const r=await send(f);f.state.current=false;
  if(disable)f.env.BURIMUNSI_NATIVE_ENABLED='false';
  await assert.rejects(verifyOtp(f.env,{challenge_id:r.challenge_id,code:'001234',surface:'admin'},{project:false}));
  assert.equal(f.state.http.length,1);
 }finally{f.close();}}
});
test('actual mounted native route uses only exact preauth path without a managed-token fabrication',async()=>{
 const f=await fixture();try{
  const raw=canonicalProfile(profile);Object.assign(f.env,{COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:await digest(raw)});
  f.env.BURIMUNSI_NATIVE_ROUTE=createCollectNativeRoute({profile,config:{enabled:true,canonicalIntegrationEnabled:true,groupId:'fixture-group',origin:ORIGIN},
   secrets:{pinPepper:new Uint8Array(32),cursorKey:new Uint8Array(32)},networkBucket:async()=>NETWORK,
   bridgeFactory:()=>{throw Error('Preauth must not construct native/financial ports');}});
  const reply=await collectNativeRoute(request(),f.env);assert.equal(reply.status,200);
  assert.equal((await reply.json()).delivery_status,'accepted');
  const other=await collectNativeRoute(request(undefined,{},'/v1/burimunsi/managed/other'),f.env);
  assert.equal(other.status,401);assert.equal(f.state.http.length,1);
 }finally{f.close();}
});
