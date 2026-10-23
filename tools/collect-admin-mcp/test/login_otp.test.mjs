import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, realpath, rm, readFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ADMIN_ORIGIN, configuration, loadCredential, saveCredential } from '../src/config.mjs';
import { requestEmailCode, verifyEmailCode } from '../src/login_otp.mjs';
import { loginWithCredentials } from '../src/login.mjs';
import { requestJson } from '../src/api.mjs';

const ACCOUNT = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';
const PRINCIPAL = '33333333-3333-4333-8333-333333333333';
const CHALLENGE = '44444444-4444-4444-8444-444444444444';
const COOKIE = `__Host-collect_admin=${'b'.repeat(64)}`;
const EMAIL = 'staff@example.test', CODE = '123456';
const expiry = () => new Date(Date.now() + 3_600_000).toISOString();
const session = (changes = {}) => ({ user: { id: ACCOUNT, email: EMAIL, role: 'staff', sessionId: SESSION,
  principalId: PRINCIPAL, financialModel: 'canonical_evidence_ledger', permissions: ['users.read'],
  assuranceLevel: 1, mfaAt: null, ...changes }, expiresAt: expiry() });
const challenge = () => ({ accepted: true, challenge_id: CHALLENGE, expires_in: 300, retry_after: 60, emailStatus: 'accepted' });
const response = (value, status = 200, cookie) => new Response(JSON.stringify(value), { status,
  headers: { 'content-type': 'application/json', ...(cookie ? { 'set-cookie': cookie } : {}) } });
const secure = `${COOKIE}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=3600`;
async function harness(t, handler) {
  const dir = await mkdtemp(join(await realpath(tmpdir()), 'collect-mcp-otp-test-'));
  const config = configuration({ COLLECT_ADMIN_MCP_SESSION_FILE: join(dir, 'session.json') });
  const requests = [], original = globalThis.fetch;
  globalThis.fetch = async (input, options = {}) => {
    const url = new URL(input); assert.equal(url.origin, ADMIN_ORIGIN);
    assert.equal(options.redirect, 'error');
    const request = { url: url.href, path: url.pathname, method: options.method ?? 'GET', headers: options.headers,
      body: options.body ? JSON.parse(options.body) : undefined };
    if (request.method === 'POST') {
      assert.equal(request.headers.Origin, ADMIN_ORIGIN);
      assert.equal(request.headers['Content-Type'], 'application/json');
      assert.equal(request.headers['X-Collect-Requested-With'], 'collect-admin');
    }
    requests.push(request); return handler(request);
  };
  t.after(async () => { globalThis.fetch = original; await rm(dir, { recursive: true, force: true }); });
  return { config, requests, dir };
}
async function unchangedCredential(f) {
  await saveCredential(f.config, { version: 1, origin: ADMIN_ORIGIN, cookie: `__Host-collect_admin=${'a'.repeat(64)}`,
    accountId: ACCOUNT, principalId: PRINCIPAL, sessionId: SESSION, expiresAt: expiry() });
  return readFile(f.config.credentialFile);
}

test('OTP-only Staff creates one independent verified AAL1 private MCP session with no password', async t => {
  const payload = session();
  const f = await harness(t, r => r.path.endsWith('/otp') ? response(challenge(), 202)
    : r.path.endsWith('/verify') ? response(payload, 200, secure) : response(payload));
  const original = await requestEmailCode(f.config, ' STAFF@example.test ');
  const result = await verifyEmailCode(f.config, original, CODE);
  assert.equal(result.role, 'staff'); assert.equal((await loadCredential(f.config)).accountId, ACCOUNT);
  assert.equal((await stat(f.config.credentialFile)).mode & 0o777, 0o600);
  assert.equal((await stat(f.dir)).mode & 0o777, 0o700);
  assert.deepEqual(f.requests.map(r => [r.method, r.path]), [['POST', '/api/admin/auth/otp'], ['POST', '/api/admin/auth/verify'], ['GET', '/api/admin/auth/session']]);
  assert.deepEqual(f.requests[0].body, { email: EMAIL });
  assert.deepEqual(f.requests[1].body, { email: EMAIL, challenge_id: CHALLENGE, code: CODE });
  assert.equal(f.requests[0].headers.Cookie, undefined); assert.equal(f.requests[1].headers.Cookie, undefined);
  assert.equal(f.requests[2].headers.Cookie, COOKIE);
  assert.equal(JSON.stringify(result).includes(COOKIE), false); assert.equal(JSON.stringify(result).includes(CODE), false);
  await assert.rejects(verifyEmailCode(f.config, original, CODE), { code: 'invalid_login' });
  assert.equal(f.requests.length, 3);
});

test('unknown email delivery preserves the original challenge/cooldown and accepts its arriving code without resend', async t => {
  const payload = session();
  const f = await harness(t, r => r.path.endsWith('/otp')
    ? response({ error: { code: 'email_delivery_unknown', message: 'PRIVATE_PROVIDER_DETAIL' }, challenge_id: CHALLENGE, expires_in: 300, retry_after: 60 }, 503)
    : r.path.endsWith('/verify') ? response(payload, 200, secure) : response(payload));
  const original = await requestEmailCode(f.config, EMAIL);
  assert.equal(original.delivery, 'unknown'); assert.equal(original.challengeId, CHALLENGE); assert.equal(original.retryAfter, 60);
  assert.equal(JSON.stringify(original).includes('PRIVATE_PROVIDER_DETAIL'), false);
  assert.equal((await verifyEmailCode(f.config, original, CODE)).role, 'staff');
  assert.equal(f.requests.filter(r => r.path.endsWith('/otp')).length, 1);
});

for (const digits of [6, 8, 10]) test(`Supabase email challenge accepts its ${digits}-digit code once with origin headers and cookie verification`, async t => {
  const payload = session();
  const f = await harness(t, r => r.path.endsWith('/otp')
    ? response({ challenge_id: CHALLENGE, retry_after: 60, expires_in: 300, channel: 'email', delivery_status: 'accepted' })
    : r.path.endsWith('/verify') ? response(payload, 200, secure) : response(payload));
  const original = await requestEmailCode(f.config, EMAIL);
  const code = '1'.repeat(digits);
  assert.equal(original.delivery, 'accepted');
  assert.equal((await verifyEmailCode(f.config, original, code)).role, 'staff');
  assert.equal(f.requests[1].body.code, code);
  assert.equal((await loadCredential(f.config)).cookie, COOKIE);
  await assert.rejects(verifyEmailCode(f.config, original, code), { code: 'invalid_login' });
  assert.equal(f.requests.length, 3);
});

test('Supabase unknown delivery retains one challenge and rejects invalid code lengths without sending another code', async t => {
  const payload = session();
  const f = await harness(t, r => r.path.endsWith('/otp')
    ? response({ challenge_id: CHALLENGE, retry_after: 60, expires_in: 300, channel: 'email', delivery_status: 'unknown' })
    : r.path.endsWith('/verify') ? response(payload, 200, secure) : response(payload));
  const original = await requestEmailCode(f.config, EMAIL);
  assert.equal(original.delivery, 'unknown'); assert.equal(original.retryAfter, 60);
  for (const code of ['12345', '12345678901', 'abcdefgh']) {
    await assert.rejects(verifyEmailCode(f.config, original, code), { code: 'invalid_login' });
  }
  assert.equal(f.requests.length, 1);
  assert.equal((await verifyEmailCode(f.config, original, CODE)).role, 'staff');
  assert.equal(f.requests.filter(r => r.path.endsWith('/otp')).length, 1);
});

test('Supabase challenge projection refuses other channels and unknown delivery states without replacing credentials', async t => {
  const variants = [
    { channel: 'whatsapp', delivery_status: 'accepted' },
    { channel: 'email', delivery_status: 'reserved' },
    { channel: 'email', delivery_status: 'rejected' },
  ];
  const f = await harness(t, () => response({ challenge_id: CHALLENGE, retry_after: 60, expires_in: 300,
    ...variants.shift() }));
  const before = await unchangedCredential(f);
  for (let i = 0; i < 3; i++) {
    await assert.rejects(requestEmailCode(f.config, EMAIL), { code: 'login_response_unknown' });
    assert.deepEqual(await readFile(f.config.credentialFile), before);
  }
  assert.equal(f.requests.length, 3);
});

test('shared password transport includes the Supabase origin header without adopting cookie or CSRF state', async t => {
  const f = await harness(t, () => response({ ok: true }));
  await requestJson(f.config, '/api/admin/auth/login', { method: 'POST', body: { email: EMAIL, password: 'synthetic-password-only' } });
  assert.equal(f.requests.length, 1);
  assert.equal(f.requests[0].headers.Cookie, undefined);
  assert.equal(f.requests[0].headers.Authorization, undefined);
  assert.equal(f.requests[0].headers['X-Collect-CSRF'], undefined);
});

test('unknown original code request stops without resend or local credential changes', async t => {
  const f = await harness(t, () => { throw Error('PRIVATE_TRANSPORT_DETAIL'); });
  const before = await unchangedCredential(f);
  await assert.rejects(requestEmailCode(f.config, EMAIL), { code: 'otp_request_unconfirmed' });
  assert.equal(f.requests.length, 1); assert.deepEqual(await readFile(f.config.credentialFile), before);
});

test('unapproved address is rejected without verify, account creation or credential replacement', async t => {
  const f = await harness(t, () => response({ error: { code: 'admin_access_not_approved', message: 'PRIVATE_DETAIL' } }, 403));
  const before = await unchangedCredential(f);
  await assert.rejects(requestEmailCode(f.config, EMAIL), { code: 'admin_access_not_approved' });
  assert.equal(f.requests.length, 1); assert.deepEqual(await readFile(f.config.credentialFile), before);
});

test('an expired original challenge is not verified or automatically replaced', async t => {
  const f = await harness(t, () => response(challenge(), 202));
  const original = await requestEmailCode(f.config, EMAIL), now = Date.now;
  Date.now = () => Date.parse(original.expiresAt) + 1;
  try { await assert.rejects(verifyEmailCode(f.config, original, CODE), { code: 'invalid_login' }); }
  finally { Date.now = now; }
  assert.equal(f.requests.length, 1);
});

test('malformed code makes no verification request; a confirmed denial never auto-replays', async t => {
  const f = await harness(t, r => r.path.endsWith('/otp') ? response(challenge(), 202) : response({ error: { code: 'invalid_credentials' } }, 401));
  const original = await requestEmailCode(f.config, EMAIL);
  for (const code of ['', '12345', '1234567', 'abcdef']) await assert.rejects(verifyEmailCode(f.config, original, code), { code: 'invalid_login' });
  assert.equal(f.requests.length, 1);
  await assert.rejects(verifyEmailCode(f.config, original, CODE), { code: 'invalid_login' });
  await assert.rejects(verifyEmailCode(f.config, original, CODE), { code: 'invalid_login' });
  assert.equal(f.requests.length, 2);
});

test('fully lost verification acknowledgement performs one session lookup and never invents or saves a cookie', async t => {
  const f = await harness(t, r => {
    if (r.path.endsWith('/otp')) return response(challenge(), 202);
    if (r.path.endsWith('/verify')) throw Error('PRIVATE_LOST_ACK');
    assert.equal(r.headers.Cookie, undefined); return response({ user: null });
  });
  const before = await unchangedCredential(f), original = await requestEmailCode(f.config, EMAIL);
  await assert.rejects(verifyEmailCode(f.config, original, CODE), { code: 'verification_unconfirmed' });
  assert.deepEqual(f.requests.map(r => r.path), ['/api/admin/auth/otp', '/api/admin/auth/verify', '/api/admin/auth/session']);
  assert.deepEqual(await readFile(f.config.credentialFile), before);
  await assert.rejects(verifyEmailCode(f.config, original, CODE), { code: 'invalid_login' });
  assert.equal(f.requests.length, 3);
});

test('lost verification body with a validated returned cookie reconciles once against the matching live email', async t => {
  const payload = session();
  const f = await harness(t, r => {
    if (r.path.endsWith('/otp')) return response(challenge(), 202);
    if (r.path.endsWith('/verify')) return new Response(new ReadableStream({ start(controller) { controller.error(Error('PRIVATE_TRUNCATED_BODY')); } }), {
      status: 200, headers: { 'content-type': 'application/json', 'set-cookie': secure },
    });
    assert.equal(r.headers.Cookie, COOKIE); return response(payload);
  });
  const original = await requestEmailCode(f.config, EMAIL);
  assert.equal((await verifyEmailCode(f.config, original, CODE)).role, 'staff');
  assert.equal(f.requests.length, 3); assert.equal((await loadCredential(f.config)).cookie, COOKIE);
});

for (const [name, cookies] of [
  ['no HttpOnly', `${COOKIE}; Path=/; Secure; SameSite=Strict`],
  ['no Secure', `${COOKIE}; Path=/; HttpOnly; SameSite=Strict`],
  ['Domain attribute', `${COOKIE}; Path=/; HttpOnly; Secure; SameSite=Strict; Domain=collect.ikanisa.com`],
  ['weaker SameSite', `${COOKIE}; Path=/; HttpOnly; Secure; SameSite=Lax`],
]) test(`OTP login refuses ${name} without saving or replaying`, async t => {
  const payload = session();
  const f = await harness(t, r => r.path.endsWith('/otp') ? response(challenge(), 202) : response(payload, 200, cookies));
  const before = await unchangedCredential(f), original = await requestEmailCode(f.config, EMAIL);
  await assert.rejects(verifyEmailCode(f.config, original, CODE), { code: 'invalid_login_response' });
  assert.equal(f.requests.length, 2); assert.deepEqual(await readFile(f.config.credentialFile), before);
});

for (const [name, changes] of [ ['email', { email: 'another@example.test' }], ['session', { sessionId: '55555555-5555-4555-8555-555555555555' }], ['permission', { permissions: [] }] ])
 test(`OTP login refuses changed live ${name} and preserves the prior credential`, async t => {
  const payload = session();
  const f = await harness(t, r => r.path.endsWith('/otp') ? response(challenge(), 202) : r.path.endsWith('/verify') ? response(payload, 200, secure) : response(session(changes)));
  const before = await unchangedCredential(f), original = await requestEmailCode(f.config, EMAIL);
  await assert.rejects(verifyEmailCode(f.config, original, CODE), { code: 'session_changed' });
  assert.equal(f.requests.filter(r => r.path.endsWith('/verify')).length, 1);
  assert.deepEqual(await readFile(f.config.credentialFile), before);
 });

test('OTP setup never accepts a different origin or forged challenge', async t => {
  const f = await harness(t, () => assert.fail('network not expected'));
  await assert.rejects(requestEmailCode({ ...f.config, origin: 'https://untrusted.example' }, EMAIL), { code: 'invalid_configuration' });
  await assert.rejects(verifyEmailCode(f.config, { challengeId: CHALLENGE }, CODE), { code: 'invalid_login' });
  assert.equal(f.requests.length, 0);
});

function assertNoCaptcha(value, ...tokens) {
  const rendered = value instanceof Error
    ? [value.name, value.message, value.stack, JSON.stringify(value)].join('\n')
    : JSON.stringify(value);
  for (const token of tokens) assert.equal(rendered.includes(token), false, 'Human verification tokens must stay private.');
}
function assertCaptchaBody(request, path, body, token) {
  assert.equal(request.url, ADMIN_ORIGIN + path);
  assert.equal(request.method, 'POST');
  assert.deepEqual(request.body, { ...body, captcha_token: token });
  assert.equal(JSON.stringify(request.headers).includes(token), false);
}
function invalidChallenge(error) {
  assert.equal(error.code, 'invalid_challenge');
  assert.equal(error.message, 'Complete the current human verification before continuing.');
  return true;
}

test('optional distinct human tokens are forwarded once in OTP bodies and excluded from retained state', async t => {
  const sendToken = 'synthetic-otp-send-captcha-only', verifyToken = 'synthetic-otp-verify-captcha-only';
  const payload = session();
  const f = await harness(t, r => r.path.endsWith('/otp') ? response(challenge(), 202)
    : r.path.endsWith('/verify') ? response(payload, 200, secure) : response(payload));
  const original = await requestEmailCode(f.config, EMAIL, { captchaToken: sendToken });
  const result = await verifyEmailCode(f.config, original, CODE, { captchaToken: verifyToken });
  assert.deepEqual(f.requests.map(r => r.path), ['/api/admin/auth/otp', '/api/admin/auth/verify', '/api/admin/auth/session']);
  assertCaptchaBody(f.requests[0], '/api/admin/auth/otp', { email: EMAIL }, sendToken);
  assertCaptchaBody(f.requests[1], '/api/admin/auth/verify', { email: EMAIL, challenge_id: CHALLENGE, code: CODE }, verifyToken);
  assert.equal(f.requests[2].body, undefined);
  assert.equal(f.requests[2].headers.Cookie, COOKIE);
  assertNoCaptcha(f.requests[2], sendToken, verifyToken);
  assert.deepEqual(Object.keys(original).sort(), ['challengeId', 'delivery', 'expiresAt', 'retryAfter']);
  assertNoCaptcha(original, sendToken, verifyToken);
  assertNoCaptcha(result, sendToken, verifyToken);
  assertNoCaptcha(await readFile(f.config.credentialFile, 'utf8'), sendToken, verifyToken);
  await assert.rejects(verifyEmailCode(f.config, original, CODE, { captchaToken: verifyToken }), { code: 'invalid_login' });
  assert.equal(f.requests.length, 3);
});

test('optional password human token is body-only and one private cookie is verified before adoption', async t => {
  const token = 'synthetic-password-captcha-only', password = 'synthetic-password-only', payload = session();
  const f = await harness(t, r => response(payload, 200, r.path.endsWith('/login') ? secure : undefined));
  const result = await loginWithCredentials(f.config, EMAIL, password, { captchaToken: token });
  assert.deepEqual(f.requests.map(r => r.path), ['/api/admin/auth/login', '/api/admin/auth/session']);
  assertCaptchaBody(f.requests[0], '/api/admin/auth/login', { email: EMAIL, password }, token);
  assert.equal(f.requests[0].headers.Cookie, undefined);
  assert.equal(f.requests[1].headers.Cookie, COOKIE);
  assert.equal(f.requests[1].body, undefined);
  assertNoCaptcha(f.requests[1], token);
  assertNoCaptcha(result, token);
  assertNoCaptcha(await readFile(f.config.credentialFile, 'utf8'), token);
  assert.equal((await loadCredential(f.config)).cookie, COOKIE);
});

test('undefined optional human tokens remain omitted for OTP request, OTP verification and password login', async t => {
  const payload = session(), password = 'synthetic-password-only';
  const f = await harness(t, r => r.path.endsWith('/otp') ? response(challenge(), 202)
    : response(payload, 200, r.path.endsWith('/verify') || r.path.endsWith('/login') ? secure : undefined));
  for (const options of [undefined, {}, { captchaToken: undefined }]) {
    const start = f.requests.length;
    const original = await requestEmailCode(f.config, EMAIL, options);
    await verifyEmailCode(f.config, original, CODE, options);
    await loginWithCredentials(f.config, EMAIL, password, options);
    const requests = f.requests.slice(start);
    assert.deepEqual(requests.map(r => r.path), ['/api/admin/auth/otp', '/api/admin/auth/verify',
      '/api/admin/auth/session', '/api/admin/auth/login', '/api/admin/auth/session']);
    assert.deepEqual(requests[0].body, { email: EMAIL });
    assert.deepEqual(requests[1].body, { email: EMAIL, challenge_id: CHALLENGE, code: CODE });
    assert.deepEqual(requests[3].body, { email: EMAIL, password });
    for (const request of requests.filter(r => r.method === 'POST')) assert.equal(Object.hasOwn(request.body, 'captcha_token'), false);
  }
});

test('optional human token length boundaries survive unchanged in all three auth POST bodies', async t => {
  const payload = session(), password = 'synthetic-password-only';
  const f = await harness(t, r => r.path.endsWith('/otp') ? response(challenge(), 202)
    : response(payload, 200, r.path.endsWith('/verify') || r.path.endsWith('/login') ? secure : undefined));
  for (const [sendToken, verifyToken, passwordToken] of [
    ['~', '!', '?'], ['s'.repeat(2048), 'v'.repeat(2048), 'p'.repeat(2048)],
  ]) {
    const start = f.requests.length;
    const original = await requestEmailCode(f.config, EMAIL, { captchaToken: sendToken });
    await verifyEmailCode(f.config, original, CODE, { captchaToken: verifyToken });
    await loginWithCredentials(f.config, EMAIL, password, { captchaToken: passwordToken });
    const requests = f.requests.slice(start);
    assertCaptchaBody(requests[0], '/api/admin/auth/otp', { email: EMAIL }, sendToken);
    assertCaptchaBody(requests[1], '/api/admin/auth/verify', { email: EMAIL, challenge_id: CHALLENGE, code: CODE }, verifyToken);
    assertCaptchaBody(requests[3], '/api/admin/auth/login', { email: EMAIL, password }, passwordToken);
    assert.equal(requests.length, 5);
  }
});

test('invalid optional human tokens reject before HTTP without consuming a challenge or changing prior credentials', async t => {
  const payload = session();
  const f = await harness(t, r => r.path.endsWith('/otp') ? response(challenge(), 202)
    : r.path.endsWith('/verify') ? response(payload, 200, secure) : response(payload));
  const before = await unchangedCredential(f), original = await requestEmailCode(f.config, EMAIL);
  const invalid = [null, false, 0, {}, [], '', 'x'.repeat(2049),
    ...Array.from({ length: 33 }, (_, ordinal) => 'synthetic-' + String.fromCharCode(ordinal) + '-private'),
    'synthetic-' + String.fromCharCode(127) + '-private'];
  for (const captchaToken of invalid) {
    await assert.rejects(requestEmailCode(f.config, EMAIL, { captchaToken }), invalidChallenge);
    await assert.rejects(verifyEmailCode(f.config, original, CODE, { captchaToken }), invalidChallenge);
    await assert.rejects(loginWithCredentials(f.config, EMAIL, 'synthetic-password-only', { captchaToken }), invalidChallenge);
    assert.equal(f.requests.length, 1);
  }
  assert.deepEqual(await readFile(f.config.credentialFile), before);
  assert.equal((await verifyEmailCode(f.config, original, CODE, { captchaToken: 'synthetic-corrected-token-only' })).role, 'staff');
  assert.equal(f.requests.length, 3);
});

test('unknown token-bearing OTP request hides echoed transport details and never resends or replaces credentials', async t => {
  const token = 'synthetic-unknown-send-token-only';
  const f = await harness(t, () => { throw Error(token + ':PRIVATE_TRANSPORT_DETAIL'); });
  const before = await unchangedCredential(f);
  await assert.rejects(requestEmailCode(f.config, EMAIL, { captchaToken: token }), error => {
    assert.equal(error.code, 'otp_request_unconfirmed'); assertNoCaptcha(error, token); return true;
  });
  assert.equal(f.requests.length, 1);
  assertCaptchaBody(f.requests[0], '/api/admin/auth/otp', { email: EMAIL }, token);
  assert.deepEqual(await readFile(f.config.credentialFile), before);
});

test('unknown token-bearing verification keeps one cookie-free lookup and rejects replay without leaking tokens', async t => {
  const sendToken = 'synthetic-lost-send-token-only', verifyToken = 'synthetic-lost-verify-token-only';
  const f = await harness(t, r => {
    if (r.path.endsWith('/otp')) return response(challenge(), 202);
    if (r.path.endsWith('/verify')) throw Error(verifyToken + ':PRIVATE_LOST_ACK');
    assert.equal(r.headers.Cookie, undefined); return response({ user: null });
  });
  const before = await unchangedCredential(f);
  const original = await requestEmailCode(f.config, EMAIL, { captchaToken: sendToken });
  await assert.rejects(verifyEmailCode(f.config, original, CODE, { captchaToken: verifyToken }), error => {
    assert.equal(error.code, 'verification_unconfirmed'); assertNoCaptcha(error, sendToken, verifyToken); return true;
  });
  assert.deepEqual(f.requests.map(r => r.path), ['/api/admin/auth/otp', '/api/admin/auth/verify', '/api/admin/auth/session']);
  assertCaptchaBody(f.requests[1], '/api/admin/auth/verify', { email: EMAIL, challenge_id: CHALLENGE, code: CODE }, verifyToken);
  assertNoCaptcha(original, sendToken, verifyToken);
  assertNoCaptcha(f.requests[2], sendToken, verifyToken);
  assert.deepEqual(await readFile(f.config.credentialFile), before);
  await assert.rejects(verifyEmailCode(f.config, original, CODE, { captchaToken: verifyToken }), error => {
    assert.equal(error.code, 'invalid_login'); assertNoCaptcha(error, sendToken, verifyToken); return true;
  });
  assert.equal(f.requests.length, 3);
});

test('token-bearing password denial and lost response hide provider details without replay or credential replacement', async t => {
  const token = 'synthetic-password-error-token-only';
  const replies = [
    () => response({ message: token + ':PRIVATE_PROVIDER_DETAIL' }, 401),
    () => { throw Error(token + ':PRIVATE_TRANSPORT_DETAIL'); },
  ];
  const f = await harness(t, () => replies.shift()());
  const before = await unchangedCredential(f);
  for (let attempt = 0; attempt < 2; attempt++) {
    await assert.rejects(loginWithCredentials(f.config, EMAIL, 'synthetic-password-only', { captchaToken: token }), error => {
      assertNoCaptcha(error, token); return true;
    });
    assert.equal(f.requests.length, attempt + 1);
    assertCaptchaBody(f.requests[attempt], '/api/admin/auth/login', { email: EMAIL, password: 'synthetic-password-only' }, token);
    assert.deepEqual(await readFile(f.config.credentialFile), before);
  }
});
