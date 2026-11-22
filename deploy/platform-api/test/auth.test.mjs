import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {fixture,using,authorization,claims,signed,admin,totp,setupMfa} from './support/auth_fixture.mjs';

test('OTP registration is single-use and concurrent verification creates one session; no secrets in response/audit',async t=>{
  const f=await using(t),otp=await f.otp();assert.equal(otp.status,202,JSON.stringify({body:otp.body,trace:f.trace}));assert.equal(f.messages.length,1);
  const results=await Promise.all([f.verify(otp),f.verify(otp)]);assert.deepEqual(results.map(r=>r.status).sort(),[200,401]);
  const session=results.find(r=>r.status===200).body;assert.match(session.user.user_metadata.public_id,/^\d{6}$/);
  assert.equal((await f.actor(session)).status,200);assert.equal((await f.verify(otp)).status,401);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_sessions').first()).n,1);
  const challenge=await f.db.prepare('SELECT * FROM auth_otp_challenges').first();assert.notEqual(challenge.code_hash,f.messages[0].code);assert.equal(challenge.status,'consumed');
  const audit=JSON.stringify((await f.db.prepare('SELECT * FROM audit_log').all()).results);assert.ok(!audit.includes(session.access_token));assert.ok(!audit.includes(session.refresh_token));
  assert.equal(otp.headers.get('cache-control'),'no-store');assert.equal(otp.headers.get('set-cookie'),null);
});

test('OTP retries are idempotent, concurrent duplicate requests send once and conflicts reject',async t=>{
  const f=await using(t),id=randomUUID();
  const responses=await Promise.all([f.otp(undefined,{request_id:id}),f.otp(undefined,{request_id:id})]);
  assert.deepEqual(responses.map(r=>r.status),[202,202]);assert.equal(f.messages.length,1);
  assert.equal((await f.otp(undefined,{request_id:id})).status,202);assert.equal(f.messages.length,1);
  assert.equal((await f.otp({phone:'+250788123457'},{request_id:id})).status,409);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_rate_claims').first()).n,1);
});

test('wrong codes consume at most five attempts under concurrency; expired and wrong-identity codes fail',async t=>{
  const f=await using(t),otp=await f.otp();
  const wrong=f.messages[0].code==='000000'?'111111':'000000';
  const failures=await Promise.all(Array.from({length:8},()=>f.verify(otp,undefined,{code:wrong})));assert.ok(failures.every(r=>r.status===401));
  assert.equal((await f.db.prepare('SELECT attempts FROM auth_otp_challenges').first()).attempts,5);
  assert.equal((await f.verify(otp)).status,401);
  await f.db.prepare('UPDATE auth_otp_throttles SET last_requested_at=last_requested_at-61').run();
  const next=await f.otp();assert.equal(next.status,202);
  assert.equal((await f.verify(next,{phone:'+250788123459'})).status,401);
  await f.db.prepare('UPDATE auth_otp_challenges SET created_at=created_at-301,expires_at=expires_at-301 WHERE id=?').bind(next.body.challenge_id).run();
  assert.equal((await f.verify(next)).status,401);
});

test('OTP identity, source and global spend budgets are transactionally refused under concurrent callers',async t=>{
  const f=await using(t,{AUTH_OTP_IP_PER_HOUR:'2',AUTH_OTP_GLOBAL_PER_DAY:'2'});
  const requests=await Promise.all(Array.from({length:6},(_,i)=>f.otp({phone:`+25078812345${i}`})));
  assert.deepEqual(requests.map(r=>r.status).sort(),[202,202,429,429,429,429]);assert.equal(f.messages.length,2);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_rate_claims').first()).n,2);
  assert.equal((await f.db.prepare('SELECT max(used) n FROM auth_rate_buckets').first()).n,2);
  assert.equal((await f.otp({phone:'+250788123450'})).status,429);
});

test('delivery acknowledgement loss remains unknown on retries, never resends, but received code can verify',async t=>{
  const f=await using(t);f.setDelivery('unacknowledged');const requestId=randomUUID();
  const first=await f.otp(undefined,{request_id:requestId});assert.equal(first.status,503);assert.equal(first.body.error.code,'otp_delivery_unknown');
  const retry=await f.otp(undefined,{request_id:requestId});assert.equal(retry.status,503);assert.equal(retry.body.error.code,'otp_delivery_unknown');assert.equal(f.messages.length,1);
  assert.equal((await f.verify(first)).status,200);
});

test('unconfigured/insecure delivery, missing CAPTCHA configuration and provider outage fail closed',async t=>{
  for(const overrides of [{OTP_DELIVERY_TOKEN:''},{OTP_DELIVERY_URL:'http://trusted-relay.example/otp'},
    {OTP_DELIVERY_URL:'https://127.0.0.1/otp'},{TURNSTILE_SECRET:''},{TURNSTILE_HOSTNAME:''}]) {
    const f=await fixture(overrides);try{assert.equal((await f.otp()).status,503);assert.equal(f.messages.length,0);}finally{await f.close();}
  }
  const f=await using(t);f.setCaptcha('outage');assert.equal((await f.otp()).status,503);assert.equal(f.messages.length,0);
});

test('CAPTCHA missing, unsuccessful, wrong hostname and replay are denied before delivery',async t=>{
  const f=await using(t);assert.equal((await f.otp(undefined,{captcha_token:''})).status,400);f.setCaptcha('wrong_host');assert.equal((await f.otp()).status,400);
  f.setCaptcha('valid');const captchaToken=randomUUID();assert.equal((await f.otp(undefined,{captcha_token:captchaToken})).status,202);
  assert.equal((await f.otp({phone:'+250788123457'},{captcha_token:captchaToken})).status,400);assert.equal(f.messages.length,1);
});

test('Admin unknown and ungranted email never registers or sends; member session cannot inherit operator grants',async t=>{
  const f=await using(t);const unknown=await f.otp({email:'unknown@example.com',surface:'admin'});assert.equal(unknown.status,202);assert.equal(f.messages.length,0);
  const a=await admin(f,{grant:false,enrollment:false});assert.equal((await f.otp(a.identity)).status,202);assert.equal(f.messages.length,0);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM users').first()).n,1);
  await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(a.id,'payments.reconcile',new Date().toISOString()).run();
  await f.db.prepare('UPDATE auth_otp_throttles SET last_requested_at=last_requested_at-61').run();
  const member=await f.login({email:a.identity.email});assert.equal((await f.actor(member)).body.permissions.length,0);
  assert.equal((await f.call('/v1/auth/mfa/enroll',{},authorization(member))).status,403);
});

test('member registration disabled does not create unknown accounts',async t=>{
  const f=await using(t,{AUTH_MEMBER_REGISTRATION_ENABLED:'false'}),request=await f.otp();assert.equal(request.status,202);assert.equal(f.messages.length,0);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM users').first()).n,0);
});

test('refresh rotates once, replay revokes its session and repeated replay emits only one audit',async t=>{
  const f=await using(t),original=await f.login();
  const fresh=await f.call('/v1/auth/refresh',{refresh_token:original.refresh_token});assert.equal(fresh.status,200);assert.notEqual(fresh.body.refresh_token,original.refresh_token);
  assert.equal(claims(fresh.body.access_token).session_id,claims(original.access_token).session_id);
  assert.equal((await f.call('/v1/auth/refresh',{refresh_token:original.refresh_token})).status,401);
  assert.equal((await f.actor(fresh.body)).status,401);assert.equal((await f.call('/v1/auth/refresh',{refresh_token:fresh.body.refresh_token})).status,401);
  assert.equal((await f.call('/v1/auth/refresh',{refresh_token:original.refresh_token})).status,401);
  assert.equal((await f.db.prepare("SELECT count(*) n FROM audit_log WHERE action='auth.refresh.replay'").first()).n,1);
});

test('concurrent refresh cannot produce two usable successors',async t=>{
  const f=await using(t),original=await f.login();
  const results=await Promise.all([f.call('/v1/auth/refresh',{refresh_token:original.refresh_token}),f.call('/v1/auth/refresh',{refresh_token:original.refresh_token})]);
  assert.deepEqual(results.map(r=>r.status).sort(),[200,401]);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_refresh_tokens').first()).n,2);
  assert.equal((await f.actor(results.find(r=>r.status===200).body)).status,401);
});

test('logout revokes only the captured session; suspension and revoked Admin grants immediately deny existing tokens',async t=>{
  const f=await using(t),one=await f.login();await f.db.prepare('UPDATE auth_otp_throttles SET last_requested_at=last_requested_at-61').run();const two=await f.login();
  assert.equal((await f.call('/v1/auth/logout',{},authorization(one))).status,200);assert.equal((await f.actor(one)).status,401);assert.equal((await f.actor(two)).status,200);
  await f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(two.user.id).run();assert.equal((await f.actor(two)).status,401);
  const a=await admin(f),adminSession=await f.login(a.identity);await f.db.prepare('DELETE FROM admin_grants WHERE user_id=?').bind(a.id).run();assert.equal((await f.actor(adminSession)).status,401);
});

test('JWT rejects wrong issuer/audience/algorithm, expiry, fabricated assurance and swapped subject',async t=>{
  const f=await using(t),session=await f.login(),base=claims(session.access_token);
  for(const value of [{...base,iss:'evil'},{...base,aud:'evil'},{...base,sub:randomUUID()},
    {...base,iat:base.iat-1000,exp:base.exp-1000,auth_time:base.auth_time-1000},
    {...base,aal:'aal2',mfa_at:base.iat,mfa_factor_id:randomUUID()}])assert.equal((await f.actor({access_token:signed(value)})).status,401);
  assert.equal((await f.actor({access_token:signed(base,{alg:'none',typ:'JWT'})})).status,401);
});

test('browser origin, cookie auth, and unsupported methods fail before creating sign-in state',async t=>{
  const f=await using(t);
  for(const headers of [{Origin:'https://evil.example'},{Origin:'null'},{Cookie:'auth=pretend'},{'Sec-Fetch-Site':'cross-site'}])
    assert.ok([400,403].includes((await f.call('/v1/auth/otp',{phone:'+250788123456',captcha_token:randomUUID()},headers)).status));
  assert.equal(f.messages.length,0);assert.equal((await f.call('/v1/auth/otp',{phone:'+250788123456',captcha_token:randomUUID()},{Origin:'https://collect.example'})).status,202);
  assert.equal((await f.mf.dispatchFetch('https://api.collect.example/v1/auth/otp',{method:'GET'})).status,405);
});

test('MFA enrollment requires fresh approved Admin and stores encrypted secret; verified factor is listed without secret',async t=>{
  const f=await using(t),a=await admin(f),session=await f.login(a.identity);
  const {factor,challenge}=await setupMfa(f,session);const stored=await f.db.prepare('SELECT * FROM auth_mfa_factors WHERE id=?').bind(factor.id).first();
  assert.ok(!stored.secret_ciphertext.includes(factor.totp.secret));assert.match(factor.totp.uri,/^otpauth:\/\/totp\/Collect/);
  const result=await f.call('/v1/auth/mfa/verify',{factor_id:factor.id,challenge_id:challenge.id,code:totp(factor.totp.secret)},authorization(session));
  assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(claims(result.body.access_token).aal,'aal2');assert.equal((await f.actor(result.body)).body.assuranceLevel,2);
  assert.equal((await f.actor(session)).body.assuranceLevel,1,'old OTP JWT must not acquire AAL2 from upgraded database session');
  const user=await f.call('/v1/auth/user',{},authorization(result.body));assert.equal(user.status,200);assert.equal(user.body.factors[0].status,'verified');assert.ok(!JSON.stringify(user.body).includes(factor.totp.secret));
  assert.equal((await f.call('/v1/auth/mfa/unenroll',{factor_id:factor.id},authorization(result.body))).status,409,'last verified factor cannot be removed through email recovery');
  assert.equal((await f.call('/v1/auth/refresh',{refresh_token:result.body.refresh_token})).status,200);
});

test('MFA challenge is session-bound, single-use, and counter replay is rejected across new challenges',async t=>{
  const f=await using(t),a=await admin(f),session=await f.login(a.identity),{factor,challenge}=await setupMfa(f,session);
  await f.db.prepare('UPDATE auth_otp_throttles SET last_requested_at=last_requested_at-61').run();const other=await f.login(a.identity);
  const body={factor_id:factor.id,challenge_id:challenge.id,code:totp(factor.totp.secret)};
  assert.equal((await f.call('/v1/auth/mfa/verify',body,authorization(other))).status,401);
  const results=await Promise.all([f.call('/v1/auth/mfa/verify',body,authorization(session)),f.call('/v1/auth/mfa/verify',body,authorization(session))]);
  assert.deepEqual(results.map(r=>r.status).sort(),[200,401]);
  const upgraded=results.find(r=>r.status===200).body;
  assert.equal((await f.call('/v1/auth/mfa/verify',body,authorization(upgraded))).status,401);
  const next=await f.call('/v1/auth/mfa/challenge',{factor_id:factor.id},authorization(upgraded));assert.equal(next.status,200);
  assert.equal((await f.call('/v1/auth/mfa/verify',{...body,challenge_id:next.body.id},authorization(upgraded))).status,401);
  assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_mfa_claims').first()).n,1);
});

test('MFA failed code attempts and global verification budget stay bounded even with new challenges',async t=>{
  const f=await using(t),a=await admin(f),session=await f.login(a.identity),{factor,challenge}=await setupMfa(f,session);
  const real=totp(factor.totp.secret),wrong=real==='000000'?'111111':'000000';
  const body={factor_id:factor.id,challenge_id:challenge.id,code:wrong};
  const results=await Promise.all(Array.from({length:12},()=>f.call('/v1/auth/mfa/verify',body,authorization(session))));
  assert.equal(results.filter(r=>r.status===429).length,2);assert.ok(results.every(r=>r.status===401||r.status===429));
  assert.equal((await f.db.prepare('SELECT attempts FROM auth_mfa_challenges WHERE id=?').bind(challenge.id).first()).attempts,5);
  assert.equal((await f.db.prepare("SELECT used FROM auth_mfa_budgets WHERE kind='verification'").first()).used,10);
  const next=await f.call('/v1/auth/mfa/challenge',{factor_id:factor.id},authorization(session));assert.equal(next.status,200);
  assert.equal((await f.call('/v1/auth/mfa/verify',{...body,challenge_id:next.body.id,code:real},authorization(session))).status,429);
});

test('OTP source budget is separate from global budget and identity cooldown applies across surfaces',async t=>{
  const f=await using(t,{AUTH_OTP_IP_PER_HOUR:'1',AUTH_OTP_GLOBAL_PER_DAY:'10'});
  assert.equal((await f.otp()).status,202);assert.equal((await f.otp({phone:'+250788123457'})).status,429);
  const other=await f.call('/v1/auth/otp',{phone:'+250788123457',captcha_token:randomUUID()},{'CF-Connecting-IP':'192.0.2.2'});assert.equal(other.status,202);
  assert.equal(f.messages.length,2);assert.equal((await f.db.prepare('SELECT count(*) n FROM auth_rate_claims').first()).n,2);
});

test('MFA setup rejects missing encryption keys, missing owner permission, stale Admin and direct unverified session upgrade',async t=>{
  const f=await using(t),a=await admin(f,{enrollment:false}),session=await f.login(a.identity);
  assert.equal((await f.call('/v1/auth/mfa/enroll',{},authorization(session))).status,403);
  await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(a.id,'auth.mfa.enroll',new Date().toISOString()).run();
  const timestamp=Math.floor(Date.now()/1000),id=randomUUID();
  await f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'admin',?,?,?)")
    .bind(id,a.id,timestamp-301,timestamp-301,timestamp+3600).run();
  const old={access_token:signed({...claims(session.access_token),session_id:id,auth_time:timestamp-301})};
  assert.equal((await f.call('/v1/auth/mfa/enroll',{},authorization(old))).status,403);
  await assert.rejects(f.db.prepare('UPDATE auth_sessions SET assurance_level=2,mfa_at=?,mfa_factor_id=? WHERE id=?')
    .bind(timestamp,randomUUID(),id).run(),/verified_mfa_claim_required/);
  const unavailable=await fixture({DATA_ENCRYPTION_KEY:''});
  try {const operator=await admin(unavailable),current=await unavailable.login(operator.identity);
    assert.equal((await unavailable.call('/v1/auth/mfa/enroll',{},authorization(current))).status,503);
    assert.equal((await unavailable.db.prepare('SELECT count(*) n FROM auth_mfa_factors').first()).n,0);
  } finally {await unavailable.close();}
});

test('a verified replacement factor permits safe retirement and rejects superseded MFA tokens',async t=>{
  const f=await using(t),a=await admin(f),session=await f.login(a.identity),first=await setupMfa(f,session);
  const one=await f.call('/v1/auth/mfa/verify',{factor_id:first.factor.id,challenge_id:first.challenge.id,code:totp(first.factor.totp.secret)},authorization(session));assert.equal(one.status,200);
  const second=await setupMfa(f,one.body),two=await f.call('/v1/auth/mfa/verify',{factor_id:second.factor.id,challenge_id:second.challenge.id,code:totp(second.factor.totp.secret)},authorization(one.body));assert.equal(two.status,200);
  assert.equal((await f.actor(one.body)).status,401,'token from the preceding factor cannot assert the current assurance');
  assert.equal((await f.call('/v1/auth/mfa/unenroll',{factor_id:first.factor.id},authorization(two.body))).status,200);
  assert.equal((await f.actor(two.body)).status,200);
  const row=await f.db.prepare('SELECT status FROM auth_mfa_factors WHERE id=?').bind(first.factor.id).first();assert.equal(row.status,'revoked');
  await assert.rejects(f.db.prepare("UPDATE auth_mfa_factors SET status='verified',revoked_at=NULL WHERE id=?").bind(first.factor.id).run(),/mfa_revocation_is_final/);
});

test('a pending authenticator can be cancelled without granting assurance and expired MFA challenges fail',async t=>{
  const f=await using(t),a=await admin(f),session=await f.login(a.identity),{factor,challenge}=await setupMfa(f,session);
  await f.db.prepare('UPDATE auth_mfa_challenges SET created_at=created_at-301,expires_at=expires_at-301 WHERE id=?').bind(challenge.id).run();
  const expired=await f.call('/v1/auth/mfa/verify',{factor_id:factor.id,challenge_id:challenge.id,code:totp(factor.totp.secret)},authorization(session));assert.equal(expired.status,401);
  assert.equal((await f.call('/v1/auth/mfa/unenroll',{factor_id:factor.id},authorization(session))).status,200);
  assert.equal((await f.actor(session)).body.assuranceLevel,1);
});


test('access expiry is bounded by the actual session lifetime, even near refresh expiry',async t=>{
  const f=await using(t),one=await f.login(),current=Math.floor(Date.now()/1000),id=randomUUID();
  await f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)")
    .bind(id,one.user.id,current,current,current+5).run();
  const shortToken=signed({...claims(one.access_token),session_id:id,iat:current,exp:current+5,auth_time:current});
  assert.equal((await f.actor({access_token:shortToken})).status,200);
  const raw=Buffer.from(Array.from({length:32},(_,i)=>i+20)).toString('base64url');
  const hash=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw));
  await f.db.prepare('INSERT INTO auth_refresh_tokens(token_hash,session_id,created_at,expires_at) VALUES(?,?,?,?)')
    .bind(Buffer.from(hash).toString('hex'),id,current,current+5).run();
  const refresh=await f.call('/v1/auth/refresh',{refresh_token:raw});assert.equal(refresh.status,200);
  assert.ok(refresh.body.expires_in<=5);assert.equal(claims(refresh.body.access_token).exp,current+5);
});
