import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {AdminHttp} from '../src/http_client.mjs';
import {acquireEmailProof} from '../src/human_login.mjs';
import {ORIGINS,sha} from '../src/contract.mjs';
import {fixture} from './http_fixture.mjs';
import {syntheticEmailProof,loopback} from './human_fixture.mjs';
const EMAIL='synthetic@example.invalid',ROOT='/api/admin/auth';
async function setup(t,{origin=ORIGINS[0],mutateFetch}={}) {
  const server=await fixture({origin});t.after(()=>server.close());
  const http=new AdminHttp({origin,clock:()=>server.now,fetchImpl:mutateFetch?((url,options)=>mutateFetch(server,url,options)):server.fetch});
  const login=()=>server.login(http),request=async()=>http.requestEmailVerification(await server.emailProof('sensitive'));
  return {server,http,login,request,verify:()=>server.reverify(http)};
}
test('email OTP login and sensitive verification keep original cookie, CSRF, public user and truthful AAL',async t=>{
  const c=await setup(t),first=await c.login(),old=c.server.authChecks.find(r=>r.path===ROOT+'/session');
  assert.equal(old.csrf,null);assert.equal(c.server.sessions.size,1);assert.equal(first.user.assuranceLevel,1);assert.equal(first.user.mfaAt,null);
  const next=await c.verify();assert.deepEqual(next.user,first.user);assert.notEqual(next.emailVerifiedAt,first.emailVerifiedAt);assert.notEqual(next.authority,first.authority);assert.ok(next.epoch>first.epoch);
  for(const r of c.server.authChecks.filter(r=>[ROOT+'/email/request',ROOT+'/email/verify'].includes(r.path))){assert.equal(r.cookie,old.cookie);assert.equal(r.csrf,sha('collect-admin-csrf:'+old.cookie));assert.equal(r.requestedWith,'collect-admin');}
  assert.equal(c.http.metadata().authentication_state,'verified_email_session');assert.equal(Object.keys(c.server.counts).some(k=>/mfa|factor/.test(k)),false);
  await c.http.logout();const logout=c.server.authChecks.at(-1);assert.equal(logout.cookie,old.cookie);assert.equal(logout.csrf,sha('collect-admin-csrf:'+old.cookie));assert.equal(c.server.sessions.size,0);assert.equal(c.http.snapshot(),null);
  assert.equal(JSON.stringify(c.http.metadata()).includes(logout.csrf),false);
});
test('missing, plain, foreign, cancelled, expired and reused opaque CAPTCHA proofs never send another code',async t=>{
  const c=await setup(t),send=proof=>c.http.requestEmailSignIn(EMAIL,proof);
  for(const proof of [undefined,'token',{token:'token'}])await assert.rejects(send(proof),/fresh_bound_human_captcha/);
  const foreign=await syntheticEmailProof({origin:ORIGINS[1]});await assert.rejects(send(foreign),/fresh_bound_human_captcha/);
  const abort=new AbortController(),cancelled=await c.server.emailProof('sign_in',{signal:abort.signal});abort.abort();await assert.rejects(send(cancelled),/fresh_bound_human_captcha/);
  const expired=await c.server.emailProof();const actual=Date.now;t.mock.method(Date,'now',()=>actual()+120001);await assert.rejects(send(expired),/fresh_bound_human_captcha/);t.mock.restoreAll();
  assert.equal(c.server.counts[ROOT+'/otp'],undefined);
  const proof=await c.server.emailProof();assert.deepEqual(proof,{});assert.equal(Object.isFrozen(proof),true);await send(proof);await assert.rejects(send(proof),/fresh_bound_human_captcha/);assert.equal(c.server.counts[ROOT+'/otp'],1);
});
test('CAPTCHA capabilities are purpose-specific and password proof cannot substitute',async t=>{
  const c=await setup(t);await c.login();
  const signIn=await c.server.emailProof();await assert.rejects(c.http.requestEmailVerification(signIn),/fresh_bound_human_captcha/);
  const password=await c.server.passwordProof();await assert.rejects(c.http.requestEmailVerification(password),/fresh_bound_human_captcha/);
  assert.equal(c.server.counts[ROOT+'/email/request'],undefined);
  const sensitive=await c.server.emailProof('sensitive');await assert.rejects(c.http.requestEmailSignIn(EMAIL,sensitive),/fresh_bound_human_captcha/);assert.equal(c.server.counts[ROOT+'/otp'],1);
});
test('human cancellation closes the pairing listener without any Auth send',async t=>{
  const c=await setup(t),abort=new AbortController();let pairing;
  await assert.rejects(acquireEmailProof({origin:ORIGINS[0]},{signal:abort.signal,onPairing:info=>{pairing=info;abort.abort();}}),{code:'challenge_cancelled'});
  await assert.rejects(loopback(pairing,'GET','/v1/collect-admin/human-challenge/offer'));assert.equal(c.server.counts[ROOT+'/otp'],undefined);
});
for(const kind of ['missing','foreign'])test(`${kind} initial login CSRF never admits cookie authority`,async t=>{
  const c=await setup(t);c.server.authTransform=(path,value)=>{if(path===ROOT+'/verify'){if(kind==='missing')delete value.csrfToken;else value.csrfToken='0'.repeat(64);}return value;};
  await assert.rejects(c.login(),e=>e.outcomeUnknown===true);assert.equal(c.http.snapshot(),null);assert.equal(c.server.counts[ROOT+'/verify'],1);assert.equal(c.server.sessions.size,1);
});
for(const kind of ['missing','foreign'])test(`${kind} current session CSRF fences before an operating action`,async t=>{
  const c=await setup(t);await c.login();c.server.authTransform=(path,value)=>{if(path===ROOT+'/session'){if(kind==='missing')delete value.csrfToken;else value.csrfToken='f'.repeat(64);}return value;};
  await assert.rejects(c.http.ensure(c.http.snapshot().user.sessionId,'assisted_sms.read'));assert.equal(c.http.snapshot(),null);assert.equal(c.server.counts.list_pending,undefined);
});
for(const kind of ['missing','foreign','old-cookie'])test(`${kind} outgoing CSRF is refused before notification dispatch`,async t=>{
  let corrupt=false,old;
  const c=await setup(t,{mutateFetch:(server,url,options)=>{
    if(url.endsWith('/email/request')&&!old)old=options.headers['X-Collect-CSRF'];
    if(corrupt&&url.endsWith('/notification-operator')){options={...options,headers:{...options.headers}};if(kind==='missing')delete options.headers['X-Collect-CSRF'];else options.headers['X-Collect-CSRF']=kind==='old-cookie'?old:'0'.repeat(64);}
    return server.fetch(url,options);
  }});await c.login();await c.request();if(kind==='old-cookie')await c.login();corrupt=true;
  const before=await c.http.ensure(c.http.snapshot().user.sessionId,'assisted_sms.read');await assert.rejects(c.http.operator('list_pending',{},before),{code:'csrf_rejected'});assert.equal(c.server.counts.list_pending,undefined);
});
test('server CAPTCHA and requested-with refusals never become successful sends',async t=>{
  const c=await setup(t,{mutateFetch:(server,url,options)=>{if(url.endsWith('/auth/otp')){const body=JSON.parse(options.body);body.captcha_token='unissued_synthetic';options={...options,body:JSON.stringify(body)};}return server.fetch(url,options);}});
  await assert.rejects(c.login(),e=>e.code==='captcha_verification_failed'&&!e.outcomeUnknown);assert.equal(c.server.sessions.size,0);
  const d=await setup(t,{mutateFetch:(server,url,options)=>{const headers={...options.headers};if(url.endsWith('/auth/otp'))delete headers['X-Collect-Requested-With'];return server.fetch(url,{...options,headers});}});
  await assert.rejects(d.login(),{code:'requested_with_required'});assert.equal(d.server.sessions.size,0);
});
for(const kind of ['missing','wrong-sid','extra-field','future','not-iso'])test(`${kind} sidecar is unavailable, never fabricated null or a replacement user`,async t=>{
  const c=await setup(t),before=await c.login();
  c.server.authTransform=(path,value)=>{if(path!==ROOT+'/email-verification')return value;if(kind==='missing')delete value.emailVerifiedAt;if(kind==='wrong-sid')value.sessionId=randomUUID();if(kind==='extra-field')value.csrfToken='forbidden';if(kind==='future')value.emailVerifiedAt=new Date(c.server.now+1).toISOString();if(kind==='not-iso')value.emailVerifiedAt='2026-01-01';return value;};
  await assert.rejects(c.http.refresh());const after=c.http.snapshot();assert.deepEqual(after.user,before.user);assert.equal(after.emailVerifiedAt,before.emailVerifiedAt);assert.equal(after.proofState,'unavailable');assert.equal(c.http.metadata().authentication_state,'email_verification_unavailable');
  c.server.authTransform=null;await c.http.ensure(before.user.sessionId,'assisted_sms.read');assert.equal(c.server.sessions.size,1);
});
for(const kind of ['null','stale'])test(`${kind} authoritative proof cannot authorize sensitive work`,async t=>{
  const c=await setup(t),before=await c.login();c.server.current.emailVerifiedAt=kind==='null'?null:c.server.now-300001;
  const next=await c.http.refresh();assert.equal(next.proofState,'available');assert.equal(c.http.metadata().authentication_state,'email_verification_required');
  await assert.rejects(c.http.ensure(before.user.sessionId,'assisted_sms.manage'),{code:'recent_email_sign_in_required'});assert.equal(c.server.counts.claim,undefined);
});
test('strict six-digit strings include leading zero; wrong400 code keeps original session and permits explicit corrected input',async t=>{
  const c=await setup(t),before=await c.login(),challenge=await c.request();
  for(const code of [123456,'12345','1234567','１２３４５６',' 123456'])await assert.rejects(c.http.verifyEmail(challenge.challenge_id,code),/invalid_email_code/);
  assert.equal(c.server.counts[ROOT+'/email/verify'],undefined);
  await assert.rejects(c.http.verifyEmail(challenge.challenge_id,'000000'),e=>e.code==='invalid_credentials'&&!e.outcomeUnknown);
  assert.deepEqual(c.http.snapshot().user,before.user);assert.equal(c.server.counts[ROOT+'/logout'],undefined);
  const verified=await c.http.verifyEmail(challenge.challenge_id,c.server.code);assert.deepEqual(verified.user,before.user);assert.equal(c.server.counts[ROOT+'/email/verify'],2);assert.equal(c.server.code[0],'0');
});
for(const failure of ['lost-reply','verify','cleanup'])test(`protected ${failure} remains unknown without code replay or original-session replacement`,async t=>{
  const c=await setup(t),before=await c.login(),challenge=await c.request();
  if(failure==='lost-reply')c.server.authFault=ROOT+'/email/verify';else c.server.emailVerifyFault=failure;
  await assert.rejects(c.http.verifyEmail(challenge.challenge_id,c.server.code),e=>e.outcomeUnknown===true&&(failure==='lost-reply'||e.code==='admin_email_operation_unknown'));
  assert.deepEqual(c.http.snapshot().user,before.user);assert.equal(c.http.snapshot().proofState,'unavailable');assert.equal(c.server.sessions.size,1);assert.equal(c.server.counts[ROOT+'/email/verify'],1);
  await assert.rejects(c.http.verifyEmail(challenge.challenge_id,c.server.code),/current_bound_email_challenge/);assert.equal(c.server.counts[ROOT+'/email/verify'],1);assert.equal(c.server.counts[ROOT+'/logout'],undefined);
});
test('unknown verify with old freshA cannot authorize work; only same-session newerB reconciles',async t=>{
  const c=await setup(t),a=await c.login(),challenge=await c.request();c.server.emailVerifyFault='verify';
  await assert.rejects(c.http.verifyEmail(challenge.challenge_id,c.server.code),{code:'admin_email_operation_unknown'});
  const held=await c.http.refresh();assert.equal(held.emailVerifiedAt,a.emailVerifiedAt);assert.equal(held.proofState,'unavailable');
  await assert.rejects(c.http.ensure(a.user.sessionId,'assisted_sms.manage'),{code:'recent_email_sign_in_required'});
  await assert.rejects(c.http.requestEmailVerification(await c.server.emailProof('sensitive')),{code:'admin_email_operation_unknown'});
  assert.equal(c.server.counts[ROOT+'/email/request'],1);assert.equal(c.server.counts[ROOT+'/email/verify'],1);assert.equal(c.server.counts.claim,undefined);
  c.server.now+=1000;c.server.current.emailVerifiedAt=c.server.now;const b=await c.http.ensure(a.user.sessionId,'assisted_sms.manage');
  assert.deepEqual(b.user,a.user);assert.equal(b.proofState,'available');assert.notEqual(b.authority,a.authority);assert.ok(b.epoch>held.epoch);assert.equal(c.server.counts[ROOT+'/logout'],undefined);
});
test('unknown sidecar read preserves last value and same-proof read recovery does not add a second epoch',async t=>{
  const c=await setup(t),before=await c.login();c.server.sidecarFault=503;await assert.rejects(c.http.refresh());
  const held=c.http.snapshot();assert.equal(held.proofState,'unavailable');assert.equal(held.emailVerifiedAt,before.emailVerifiedAt);assert.ok(held.epoch>before.epoch);
  const recovered=await c.http.refresh();assert.equal(recovered.epoch,held.epoch);assert.equal(recovered.proofState,'available');assert.equal(recovered.authority,before.authority);
});
test('real401 clears custody; a refresh409 retries only the dedicated GET once',async t=>{
  const c=await setup(t),before=await c.login();const count=c.server.counts[ROOT+'/session'];c.server.sessionFault=409;
  const next=await c.http.refresh();assert.equal(next.user.sessionId,before.user.sessionId);assert.equal(c.server.counts[ROOT+'/session'],count+2);assert.equal(c.server.counts[ROOT+'/verify'],1);
  c.server.sidecarFault=401;await assert.rejects(c.http.refresh(),{code:'authentication_required'});assert.equal(c.http.snapshot(),null);
});
test('lost initial verify reply never replays the consumed login challenge',async t=>{
  const c=await setup(t),challenge=await c.http.requestEmailSignIn(EMAIL,await c.server.emailProof());c.server.authFault=ROOT+'/verify';
  await assert.rejects(c.http.verifyEmailSignIn(challenge.challenge_id,c.server.code),e=>e.outcomeUnknown===true);assert.equal(c.http.snapshot(),null);assert.equal(c.server.sessions.size,1);
  await assert.rejects(c.http.verifyEmailSignIn(challenge.challenge_id,c.server.code),/current_bound_email_challenge/);assert.equal(c.server.counts[ROOT+'/verify'],1);
});
test('protected sidecar cannot rotate cookie or mutate CSRF',async t=>{
  const c=await setup(t),before=await c.login(),challenge=await c.request();
  c.server.authTransform=(path,value,headers)=>{if(path===ROOT+'/email/verify')headers['Set-Cookie']=`__Host-collect_admin=${'a'.repeat(64)}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=3600`;return value;};
  await assert.rejects(c.http.verifyEmail(challenge.challenge_id,c.server.code),e=>e.code==='unexpected_auth_rotation'&&e.outcomeUnknown);assert.deepEqual(c.http.snapshot().user,before.user);
  c.server.authTransform=null;await c.http.refresh();const last=c.server.authChecks.at(-1);assert.notEqual(last.cookie,'a'.repeat(64));assert.equal(c.server.sessions.size,1);
});
test('a late successful protected verification cannot resurrect cleared custody',async t=>{
  let entered,release;const reached=new Promise(resolve=>entered=resolve),gate=new Promise(resolve=>release=resolve);
  const c=await setup(t,{mutateFetch:async(server,url,options)=>{const response=await server.fetch(url,options);if(url.endsWith('/auth/email/verify')){entered();await gate;}return response;}});
  await c.login();const challenge=await c.request(),pending=c.http.verifyEmail(challenge.challenge_id,c.server.code);const rejected=assert.rejects(pending,e=>e.outcomeUnknown===true);await reached;c.http.clear();release();await rejected;assert.equal(c.http.snapshot(),null);
});

test('unknown delivery receipt is not an automatic resend and permits only explicit code entry',async t=>{
  const c=await setup(t);c.server.deliveryStatus='unknown';const challenge=await c.http.requestEmailSignIn(EMAIL,await c.server.emailProof());
  assert.equal(challenge.delivery_status,'unknown');assert.equal(c.server.counts[ROOT+'/otp'],1);await c.http.verifyEmailSignIn(challenge.challenge_id,c.server.code);assert.equal(c.server.counts[ROOT+'/otp'],1);
});
test('malformed successful send receipts remain unknown without a usable local challenge',async t=>{
  for(const protectedSend of [false,true]){
    const c=await setup(t);if(protectedSend)await c.login();const path=ROOT+(protectedSend?'/email/request':'/otp');
    c.server.authTransform=(route,value)=>route===path?{...value,challenge_id:'not-a-uuid'}:value;
    await assert.rejects(protectedSend?c.request():c.http.requestEmailSignIn(EMAIL,await c.server.emailProof()),e=>e.outcomeUnknown===true);
    assert.equal(c.server.counts[path],1);assert.equal(c.server.counts[ROOT+'/email/verify'],undefined);
  }
});
test('a superseded send reply cannot replace the current bound challenge',async t=>{
  let entered,release,held=true;const reached=new Promise(resolve=>entered=resolve),gate=new Promise(resolve=>release=resolve);
  const c=await setup(t,{mutateFetch:async(server,url,options)=>{const response=await server.fetch(url,options);if(held&&url.endsWith('/auth/email/request')){held=false;entered();await gate;}return response;}});
  await c.login();const old=c.request(),rejected=assert.rejects(old,e=>e.code==='email_attempt_changed'&&e.outcomeUnknown);await reached;
  const current=await c.request();release();await rejected;await c.http.verifyEmail(current.challenge_id,c.server.code);assert.equal(c.server.counts[ROOT+'/email/verify'],1);
});
