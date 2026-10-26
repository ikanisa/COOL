import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {privacyPortalScript} from '../../../supabase/functions/_shared/domain/privacy_portal_assets.js';
import {privacyPortalRoute} from '../../../supabase/functions/_shared/domain/privacy_portal.js';
import {withMountedPrivacyPortal} from './fixtures/privacy_portal_dom.mjs';

// Import the exact served browser implementation. No provider, DB or network is
// used: request/challenge/fetch are intercepted with explicit synthetic replies.
const client=await import('data:text/javascript;base64,'+Buffer.from(privacyPortalScript).toString('base64'));
const issuer='https://rrlduytparvsjfmegalh.supabase.co/auth/v1';
const jwt=claims=>Buffer.from('{"alg":"ES256"}').toString('base64url')+'.'+Buffer.from(JSON.stringify(claims)).toString('base64url')+'.synthetic';
const envelope=b=>({...Object.fromEntries(['contract_version','purpose','mode','challenge_id','challenge_context'].map(k=>[k,b[k]])),identity_type:'email',channel:'email'});
const stamp=now=>new Date(now).toISOString().replace(/\.(\d{3})Z$/,'.$1000Z');
function intake(id,now,submission){return {contract_version:1,request_id:id,scope:'own_account_eligible_data',state:'pending_review',reason_code:'account_deletion_requested',reason_supplied:false,accepted_at:stamp(now),policy_review_pending:true,subject_scope_review_pending:true,erasure_completed:false,account_access_restricted:false,auth_removed:false,retention_approval_granted:false,processor_operation_started:false,...(submission?{submission_id:submission,replay:false,equivalent_active_request:false}:{})};}
function review(id,now){return {contract_version:1,scope:'own_account_privacy_review',request_id:id,checked_at:stamp(now),revision:0,review_state:'not_started',outcome_code:null,outcome_recorded_at:null,completion:'blocked',blocking_reason:'policy_authority_unavailable',policy_acceptance_granted:false,subject_scope_review_pending:true,legal_hold_review_pending:true,copy_dispositions_verified:false,destructive_execution_available:false,erasure_completed:false,account_access_restricted:false,auth_removed:false,processor_operation_started:false};}
function harness(){
 let clock=Date.now();const h={calls:[],writes:[],securityChecks:0,principal:randomUUID(),managed:randomUUID(),sid:randomUUID(),email:'member@example.test',storage:null,accepted:null,hook:null,emailHook:null};
 h.now=()=>clock;h.advance=seconds=>{clock+=seconds*1000;};
 h.descriptor=(body,{state='not_started',cancelled=false,cleanup='not_required'}={})=>({...envelope(body),destination_hint:'m***@example.test',retry_after:60,created_at:h.created??Math.floor(clock/1000),expires_at:(h.created??Math.floor(clock/1000))+300,delivery_status:'not_disclosed',verification_state:state,operation_id:body.operation_id??null,cancelled,candidate_cleanup:cleanup});
 h.candidate=body=>{
  const at=h.created??Math.floor(clock/1000),claims={iss:issuer,sub:h.managed,session_id:h.sid,aud:'authenticated',role:'authenticated',iat:at,exp:at+3600,amr:[{method:'otp',timestamp:at}]};
  return {...envelope(body),operation_id:body.operation_id,access_token:jwt(claims),refresh_token:'synthetic-refresh-memory-only',token_type:'bearer',expires_at:claims.exp,expires_in:3600,user:{id:h.principal,auth_user_id:h.managed,email:h.email,email_confirmed_at:stamp(clock-1000),is_anonymous:false},auth_event:{method:'otp',timestamp:at},purpose_proof:{purpose:'account_deletion_request',challenge_id:body.challenge_id,user_id:h.principal,auth_user_id:h.managed,initiating_session_id:null,session_id:h.sid,method:'otp',authenticated_at:at,expires_at:at+300}};
 };
 const request=async(path,body,token)=>{
  h.calls.push({path,body:structuredClone(body),token});if(h.hook){const value=await h.hook(path,body,token);if(value!==undefined)return value;}
  if(path.endsWith('/get_current_account_deletion_request_status_v1'))return h.accepted;
  if(path.endsWith('/get_account_deletion_request_status_v1')){if(!h.accepted)throw Object.assign(new Error('not found'),{status:404,code:'privacy_request_unavailable'});return h.accepted;}
  if(path.endsWith('/request_account_deletion_v1')){assert.equal(Object.keys(h.storage).sort().join(','),'subject_id,submission_id,version');h.accepted=intake(body.p_request_id,clock);return intake(body.p_request_id,clock,body.p_request_id);}
  if(path.endsWith('/get_account_deletion_review_status_v1'))return review(body.p_request_id,clock);
  if(path==='/v1/auth/logout')return {ok:true};
  assert.fail('Unexpected ordinary endpoint '+path);
 };
 const emailRequest=async(path,body,token)=>{
  h.calls.push({path,body:structuredClone(body),token});assert.equal(token,null);
  if(h.emailHook){const value=await h.emailHook(path,body,token);if(value!==undefined)return value;}
  if(path.endsWith('/challenge')){h.created=Math.floor(clock/1000);return {status:202,body:h.descriptor(body)};}
  if(path.endsWith('/verify'))return {status:200,body:h.candidate(body)};
  if(path.endsWith('/status'))return {status:200,body:h.descriptor(body,{state:'verified',cleanup:'unconfirmed'})};
  if(path.endsWith('/cancel'))return {status:200,body:h.descriptor(body,{state:body.operation_id?'verified':'not_started',cancelled:true,cleanup:body.candidate_access_token?'confirmed':body.operation_id?'unconfirmed':'not_required'})};
  assert.fail('Unexpected email endpoint '+path);
 };
 h.controller=client.createPrivacyPortalController({request,emailRequest,emailAvailable:true,challenge:async()=>{h.securityChecks++;return 'synthetic-captcha';},now:h.now,randomUUID,emailRandomContext:()=>randomBytes(32).toString('base64url'),checkpoint:{read:()=>h.storage,write:value=>{h.storage=structuredClone(value);h.writes.push(structuredClone(value));},clear:()=>{h.storage=null;}}});
 h.signIn=async()=>{h.controller.chooseEmail();await h.controller.requestEmailCode(h.email);await h.controller.verifyEmailCode('1234567890');};
 return h;
}

test('one no-create email code reaches existing review/intake; only three checkpoint fields persist',async()=>{
 const h=harness();await h.signIn();assert.equal(h.controller.state.step,'request');assert.equal(h.controller.state.signedIn,true);
 assert.equal(h.calls.filter(c=>c.path==='/v1/privacy/email/challenge').length,1);assert.equal(h.calls.filter(c=>c.path==='/v1/privacy/email/verify').length,1);
 assert.equal(h.calls.filter(c=>c.path==='/v1/auth/otp'||c.path==='/v1/auth/verify').length,0);assert.equal(h.securityChecks,2);
 const challenge=h.calls.find(c=>c.path.endsWith('/challenge'));assert.equal(challenge.body.mode,'portal_bootstrap');assert.equal(challenge.body.allow_registration,false);assert.equal(challenge.body.should_create_user,false);assert.match(challenge.body.challenge_context,/^[A-Za-z0-9_-]{43}$/);assert.equal(Buffer.from(challenge.body.challenge_context,'base64url').length,32);assert.equal(Object.hasOwn(challenge.body,'user_id'),false);
 await h.controller.reviewRequest();await h.controller.submit();assert.equal(h.controller.state.step,'received');assert.match(h.controller.state.message,/have not been erased/);
 assert.equal(h.storage,null);assert.equal(h.writes.length,1);assert.deepEqual(Object.keys(h.writes[0]).sort(),['subject_id','submission_id','version']);
 assert.equal(JSON.stringify(h.writes).includes(challenge.body.challenge_context),false);assert.equal(JSON.stringify(h.controller.state).includes('synthetic-refresh'),false);
});

test('opaque send descriptor does not claim delivery and permits one explicit code attempt',async()=>{
 const h=harness();h.controller.chooseEmail();await h.controller.requestEmailCode(h.email);
 assert.equal(h.controller.state.step,'email-code');assert.match(h.controller.state.message,/Delivery is not disclosed/);
 assert.equal(h.controller.state.signedIn,false);await h.controller.verifyEmailCode('123456');
 assert.equal(h.controller.state.step,'request');
});

for(const [label,change] of [
 ['missing mapping',v=>{delete v.user.auth_user_id;}],
 ['same email wrong managed subject',v=>{v.user.auth_user_id=randomUUID();}],
 ['wrong canonical proof',v=>{v.purpose_proof.user_id=randomUUID();}],
 ['unconfirmed email',v=>{delete v.user.email_confirmed_at;}],
 ['different email',v=>{v.user.email='other@example.test';}],
 ['bootstrap initiating session',v=>{v.purpose_proof.initiating_session_id=randomUUID();}],
 ['foreign issuer',v=>{const c=JSON.parse(Buffer.from(v.access_token.split('.')[1],'base64url'));c.iss='https://foreign.invalid/auth/v1';v.access_token=jwt(c);}],
 ['fresh iat stale OTP',v=>{const c=JSON.parse(Buffer.from(v.access_token.split('.')[1],'base64url'));c.amr[0].timestamp-=601;v.access_token=jwt(c);}],
 ['string event',v=>{v.auth_event.timestamp=String(v.auth_event.timestamp);}],
 ['future event',v=>{v.auth_event.timestamp++;v.purpose_proof.authenticated_at++;}],
 ['different context',v=>{v.challenge_context=randomBytes(32).toString('base64url');}],
]){
 test('qualified bootstrap candidate refuses '+label,async()=>{
  const h=harness();h.emailHook=(path,body)=>{if(path.endsWith('/verify')){const value=h.candidate(body);change(value);return {status:200,body:value};}};
  h.controller.chooseEmail();await h.controller.requestEmailCode(h.email);
  await assert.rejects(h.controller.verifyEmailCode('123456'));assert.equal(h.controller.state.signedIn,false);assert.equal(h.controller.state.step,'email-unknown');
  assert.equal(h.calls.filter(c=>c.path.includes('/v1/rpc/')).length,0);assert.equal(h.calls.filter(c=>c.path.endsWith('/cancel')).length,0);
 });
}

test('lost verify and verified status metadata cannot install tokens or retry the provider operation',async()=>{
 const h=harness();h.emailHook=path=>{if(path.endsWith('/verify'))throw new TypeError('RAW_NATIVE_OR_PROVIDER_DETAILS');};
 h.controller.chooseEmail();await h.controller.requestEmailCode(h.email);await assert.rejects(h.controller.verifyEmailCode('123456'));
 await h.controller.checkEmailVerification();assert.equal(h.controller.state.signedIn,false);assert.equal(h.controller.state.step,'email-unknown');
 await assert.rejects(h.controller.verifyEmailCode('123456'));assert.equal(h.calls.filter(c=>c.path.endsWith('/verify')).length,1);
 assert.equal(h.controller.state.error.includes('RAW_NATIVE'),false);assert.equal(h.calls.filter(c=>c.path.includes('/v1/rpc/')).length,0);
 await h.controller.clear();assert.match(h.controller.state.message,/Candidate sign-out could not be confirmed/);
 assert.equal(h.calls.some(c=>Object.hasOwn(c.body,'candidate_access_token')),false);
});

test('definite rejection permits explicit new operation UUID, never automatic verification replay',async()=>{
 const h=harness();let calls=0;h.emailHook=(path,body)=>{if(path.endsWith('/verify')&&++calls===1)return {status:401,body:{...h.descriptor(body,{state:'rejected',cleanup:'unconfirmed'}),code:'privacy_email_code_rejected',message:'do not render'}};};
 h.controller.chooseEmail();await h.controller.requestEmailCode(h.email);await assert.rejects(h.controller.verifyEmailCode('111111'));
 assert.equal(calls,1);assert.equal(h.controller.state.step,'email-code');await h.controller.verifyEmailCode('222222');
 const attempts=h.calls.filter(c=>c.path.endsWith('/verify'));assert.notEqual(attempts[0].body.operation_id,attempts[1].body.operation_id);assert.equal(attempts[0].body.challenge_id,attempts[1].body.challenge_id);assert.equal(attempts[0].body.challenge_context,attempts[1].body.challenge_context);assert.equal(h.controller.state.signedIn,true);
});

for(const race of ['clear then replacement','expiry']){
 test('late '+race+' cleans only exact received candidate without current/refresh token substitution',async()=>{
  const h=harness();let enter,resolve;const entered=new Promise(r=>{enter=r;});let oldCandidate,originalBody;
  h.emailHook=(path,body)=>{if(path.endsWith('/verify')&&!oldCandidate){originalBody=structuredClone(body);oldCandidate=h.candidate(body);return new Promise(r=>{resolve=r;enter();});}};
  h.controller.chooseEmail();await h.controller.requestEmailCode(h.email);
  const verifying=h.controller.verifyEmailCode('123456');const rejected=assert.rejects(verifying);await entered;
  if(race==='clear then replacement'){
   await h.controller.clear();h.email='other@example.test';h.principal=randomUUID();h.managed=randomUUID();h.sid=randomUUID();
   h.controller.chooseEmail();await h.controller.requestEmailCode(h.email);await h.controller.verifyEmailCode('654321');assert.equal(h.controller.state.signedIn,true);
  }else h.advance(601);
  resolve({status:200,body:oldCandidate});await rejected;
  const cleanup=h.calls.filter(c=>c.path.endsWith('/cancel')&&c.body.candidate_access_token);assert.equal(cleanup.length,1);
  assert.equal(cleanup[0].body.candidate_access_token,oldCandidate.access_token);assert.equal(cleanup[0].body.challenge_id,originalBody.challenge_id);assert.equal(cleanup[0].body.challenge_context,originalBody.challenge_context);assert.equal(cleanup[0].body.operation_id,originalBody.operation_id);assert.equal(cleanup[0].token,null);
  assert.deepEqual(Object.keys(cleanup[0].body).sort(),['candidate_access_token','challenge_context','challenge_id','contract_version','mode','operation_id','purpose']);
  if(race==='clear then replacement'){await h.controller.reviewRequest();await h.controller.submit();assert.equal(h.writes.at(-1).subject_id,h.principal);}
  else assert.equal(h.controller.state.signedIn,false);
 });
}

test('after synchronous email adoption clear uses explicit ordinary captured-session signout, never candidate cancel',async()=>{
 const h=harness();await h.signIn();await h.controller.clear();assert.equal(h.calls.filter(c=>c.path.endsWith('/privacy/email/cancel')).length,0);
 const logout=h.calls.find(c=>c.path==='/v1/auth/logout');assert.ok(logout?.token);assert.equal(h.controller.state.signedIn,false);
});

test('email portal is independent of phone flag and fail-closed without existing CAPTCHA binding',async()=>{
 const request=new Request('https://collect.example/privacy/account-deletion');
 const env={SUPABASE_URL:'https://rrlduytparvsjfmegalh.supabase.co',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fixture_only',AUTH_PHONE_ENABLED:'false'};
 const unavailable=await privacyPortalRoute(request,env).text();assert.match(unavailable,/data-email-verification-available="false"/);
 const configured=await privacyPortalRoute(request,{...env,TURNSTILE_SITE_KEY:'synthetic-site-key'}).text();assert.match(configured,/data-verification-available="false" data-email-verification-available="true"/);assert.match(configured,/id="email-form"/);assert.match(configured,/minlength="6" maxlength="10"/);
 assert.equal(privacyPortalRoute(request,env).headers.get('X-Frame-Options'),'DENY');assert.match(privacyPortalRoute(request,env).headers.get('Content-Security-Policy'),/connect-src 'self'/);
});

test('actual email fetch adapter preserves no-cookie same-origin POST and bounded raw statuses',async t=>{
 const old=globalThis.fetch,calls=[];t.after(()=>{globalThis.fetch=old;});
 globalThis.fetch=async(path,init)=>{calls.push({path,init});return new Response(JSON.stringify({synthetic:true}),{status:202,headers:{'Content-Type':'application/json'}});};
 const reply=await client.portalEmailRequest('/v1/privacy/email/challenge',{synthetic:true},null);assert.equal(reply.status,202);
 const c=calls[0];assert.equal(c.init.method,'POST');assert.equal(c.init.credentials,'omit');assert.equal(c.init.cache,'no-store');assert.equal(c.init.redirect,'error');assert.equal(c.init.referrerPolicy,'no-referrer');assert.equal(Object.hasOwn(c.init.headers,'Authorization'),false);
 await assert.rejects(client.portalEmailRequest('/v1/auth/verify',{},null));await assert.rejects(client.portalEmailRequest('/v1/privacy/email/status',{},'replacement-token'));assert.equal(calls.length,1);
 globalThis.fetch=async()=>new Response('x'.repeat(32769),{status:200});await assert.rejects(client.portalEmailRequest('/v1/privacy/email/status',{},null),e=>e.code==='privacy_email_unconfirmed');
});

test('mounted email-only unknown cancellation returns to a reachable email form without phone fallback',async()=>{
 await withMountedPrivacyPortal({client,route:privacyPortalRoute,failFirstChallenge:true},async h=>{
  assert.ok(h.visible('email-form'));assert.equal(h.visible('phone-form'),false);assert.equal(h.visible('use-phone'),false);
  h.node('email').value=h.email;await h.submit('email-form');assert.ok(h.visible('step-email-unknown'));
  await h.click('email-cancel');assert.ok(h.visible('email-form'));assert.equal(h.visible('phone-form'),false);assert.equal(h.visible('use-phone'),false);
  h.node('email').value=h.email;await h.submit('email-form');assert.ok(h.visible('email-code-form'));
  assert.equal(h.calls.filter(c=>c.path.endsWith('/challenge')).length,2);assert.equal(h.calls.filter(c=>c.path==='/v1/auth/otp').length,0);
 });
});

test('mounted adopted email clear preserves email recovery and truthful uncertain ordinary signout',async()=>{
 await withMountedPrivacyPortal({client,route:privacyPortalRoute,failLogout:true},async h=>{
  await h.signIn();await h.click('clear');assert.ok(h.visible('email-form'));assert.equal(h.visible('phone-form'),false);
  assert.match(h.node('status').textContent,/Server sign-out could not be confirmed/);
  assert.equal(h.calls.filter(c=>c.path==='/v1/auth/logout').length,1);assert.equal(h.calls.filter(c=>c.path.endsWith('/privacy/email/cancel')).length,0);
  h.node('email').value=h.email;await h.submit('email-form');assert.ok(h.visible('email-code-form'));
 });
});

test('mounted email-only session expiry keeps verification reachable through actual timer and form handlers',async()=>{
 await withMountedPrivacyPortal({client,route:privacyPortalRoute},async h=>{
  await h.signIn();await h.expire();assert.ok(h.visible('email-form'));assert.equal(h.visible('phone-form'),false);
  assert.match(h.node('error').textContent,/Verify your identity again/);
  h.node('email').value=h.email;await h.submit('email-form');assert.ok(h.visible('email-code-form'));
  assert.equal(h.calls.filter(c=>Object.hasOwn(c.body,'candidate_access_token')).length,0);
 });
});

test('mounted dual-mode clear restores phone and the actual email switch remains reachable',async()=>{
 await withMountedPrivacyPortal({client,route:privacyPortalRoute,phoneAvailable:true},async h=>{
  assert.ok(h.visible('phone-form'));await h.click('use-email');h.node('email').value=h.email;await h.submit('email-form');assert.ok(h.visible('email-code-form'));
  await h.click('clear');assert.ok(h.visible('phone-form'));assert.ok(h.visible('use-email'));
  await h.click('use-email');assert.ok(h.visible('email-form'));assert.equal(h.visible('phone-form'),false);
 });
});
