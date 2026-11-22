// Synthetic loopback fixtures only. No browser, provider, Auth or credentials.
import test from 'node:test';
import assert from 'node:assert/strict';
import { request } from 'node:http';
import { createPublicKey, verify } from 'node:crypto';
import { ADMIN_ORIGIN, SafeError } from '../src/config.mjs';
import { acquireHumanChallenge } from '../src/human_challenge.mjs';

const CONFIG = Object.freeze({ origin: ADMIN_ORIGIN });
const OFFER = '/v1/collect-admin/human-challenge/offer', COMPLETE = '/v1/collect-admin/human-challenge/complete';
const SYNTHETIC = 'SYNTHETIC_CHALLENGE_CANDIDATE_NOT_PROVIDER_VERIFIED';
function pairingOrStopped(pairing, pending) {
  return Promise.race([pairing, pending.then(() => { throw Error('Synthetic challenge finished before pairing.'); })]);
}
async function fixture(t, operation = 'admin.email_otp.send', origin = ADMIN_ORIGIN) {
  const controller = new AbortController(); let deliver;
  const pairing = new Promise(resolve => { deliver = resolve; });
  const pending = acquireHumanChallenge({origin}, { operation, signal: controller.signal, onPairing: deliver });
  pending.catch(() => {});
  t.after(async () => { controller.abort(); await pending.catch(() => {}); });
  const received = await pairingOrStopped(pairing, pending);
  return { ...received, controller, pending };
}
function call(f, method, path, { headers = {}, value, raw } = {}) {
  const bytes = raw === undefined ? value === undefined ? undefined : Buffer.from(JSON.stringify(value)) : Buffer.from(raw);
  return new Promise((resolve, reject) => {
    const actualHeaders = { Origin: f.descriptor.admin_origin, 'X-Collect-Handoff-Version': '1',
      'X-Collect-Handoff-Attempt': f.descriptor.attempt_id,
      ...(bytes ? { 'Content-Type': 'application/json', 'Content-Length': bytes.length } : {}), ...headers };
    for (const key of Object.keys(actualHeaders)) if (actualHeaders[key] === undefined) delete actualHeaders[key];
    const req = request({ hostname: '127.0.0.1', port: f.descriptor.loopback_port, method, path,
      headers: actualHeaders }, res => {
      const chunks = []; res.on('data', c => chunks.push(c));
      res.on('end', () => {
        try {
          const text = Buffer.concat(chunks).toString('utf8');
          resolve({ status: res.statusCode, headers: res.headers, text, value: text ? JSON.parse(text) : null });
        } catch (error) { reject(error); }
      });
      res.on('error', reject);
    });
    req.on('error', reject); req.setTimeout(2000, () => req.destroy(Error('synthetic loopback timeout')));
    req.end(bytes);
  });
}
async function offer(f) {
  const r = await call(f, 'GET', OFFER);
  assert.equal(r.status, 200); cors(r, f.descriptor.admin_origin);
  assert.equal(r.value.type, 'collect.admin.human_challenge.signed_offer.v1');
  const bytes = Buffer.from(r.value.payload_base64url, 'base64url');
  const key = createPublicKey({ key: { kty: 'OKP', crv: 'Ed25519', x: f.descriptor.listener_public_key_ed25519 }, format: 'jwk' });
  assert.equal(verify(null, bytes, key, Buffer.from(r.value.signature_ed25519_base64url, 'base64url')), true);
  const value = JSON.parse(bytes);
  assert.equal(bytes.toString(), JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(k => [k, value[k]]))));
  assert.equal(value.attempt_id, f.descriptor.attempt_id); assert.equal(value.operation, f.descriptor.operation);
  assert.equal(value.admin_origin, f.descriptor.admin_origin); assert.equal(value.loopback_port, f.descriptor.loopback_port);
  assert.equal(value.expires_at_ms, f.descriptor.expires_at_ms); assert.match(value.nonce, /^[A-Za-z0-9_-]{43}$/);
  return value;
}
function complete(f, o, changes = {}) {
  return { type: 'collect.admin.human_challenge.complete.v1', attempt_id: f.descriptor.attempt_id,
    operation: f.descriptor.operation, nonce: o.nonce, widget_attempt_id: f.descriptor.attempt_id,
    token: SYNTHETIC, ...changes };
}
function cors(r, origin = ADMIN_ORIGIN) {
  assert.equal(r.headers['access-control-allow-origin'], origin);
  assert.equal(r.headers.vary, 'Origin');
  assert.equal(r.headers['access-control-allow-credentials'], undefined);
}

for (const operation of ['admin.email_otp.send', 'admin.email_otp.verify', 'admin.password.sign_in']) {
  test(`one signed synthetic ${operation} candidate is returned only after listener closure`, async t => {
    const f = await fixture(t, operation);
    assert.equal(f.parentUrl, `${ADMIN_ORIGIN}/admin/auth/local-challenge`);
    assert.deepEqual(Object.keys(f.descriptor).sort(), ['type', 'attempt_id', 'operation', 'admin_origin', 'loopback_port', 'expires_at_ms', 'listener_public_key_ed25519'].sort());
    assert.equal(Object.isFrozen(f.descriptor), true);
    assert.equal(JSON.stringify(f.descriptor).includes(SYNTHETIC), false);
    const o = await offer(f), r = await call(f, 'POST', COMPLETE, { value: complete(f, o) });
    assert.equal(r.status, 202); cors(r);
    assert.equal(r.value.status, 'accepted_for_one_cli_operation'); assert.equal(r.value.session_confirmed, false);
    assert.equal(r.text.includes(SYNTHETIC), false); assert.equal(r.text.includes(o.nonce), false);
    assert.equal(await f.pending, SYNTHETIC);
    await assert.rejects(call(f, 'GET', OFFER));
  });
}

test('both strict preflights and actual response CORS coexist without consuming the offer or nonce', async t => {
  const f = await fixture(t);
  for (const [path, method] of [[OFFER, 'GET'], [COMPLETE, 'POST']]) {
    const r = await call(f, 'OPTIONS', path, { headers: { 'Access-Control-Request-Method': method,
      'Access-Control-Request-Headers': 'content-type,x-collect-handoff-version,x-collect-handoff-attempt' } });
    assert.equal(r.status, 204); assert.equal(r.headers['access-control-allow-origin'], ADMIN_ORIGIN);
    assert.equal(r.headers.vary, 'Origin, Access-Control-Request-Method, Access-Control-Request-Headers');
    assert.equal(r.headers['access-control-allow-credentials'], undefined);
  }
  const o = await offer(f), r = await call(f, 'POST', COMPLETE, { value: complete(f, o) });
  assert.equal(r.status, 202); cors(r); assert.equal(await f.pending, SYNTHETIC);
});

for (const origin of ['https://unapproved.example', 'null', '', undefined]) test(`unapproved Origin ${origin === undefined ? '(missing)' : origin || '(empty)'} gets no ACAO or offer`, async t => {
  const f = await fixture(t), r = await call(f, 'GET', OFFER, { headers: { Origin: origin } });
  assert.equal(r.status, 403); assert.equal(r.headers['access-control-allow-origin'], undefined);
  assert.equal(r.headers['access-control-allow-credentials'], undefined); assert.equal(r.text.includes('nonce'), false);
});

for (const [name, headers, path, status] of [
  ['wrong Host', { Host: 'localhost' }, OFFER, 403],
  ['cookie import', { Cookie: '__Host-collect_admin=SYNTHETIC' }, OFFER, 403],
  ['bearer import', { Authorization: 'Bearer SYNTHETIC' }, OFFER, 403],
  ['wrong version', { 'X-Collect-Handoff-Version': '2' }, OFFER, 403],
  ['query route', {}, OFFER + '?callback=https://unapproved.example', 404],
  ['arbitrary redirect route', {}, '/redirect', 404],
]) test(`${name} is refused with readable exact-origin CORS`, async t => {
  const f = await fixture(t), r = await call(f, 'GET', path, { headers });
  assert.equal(r.status, status); cors(r); assert.equal(r.text.includes('SYNTHETIC'), false);
});

test('a second successful-offer read is refused without revealing another nonce', async t => {
  const f = await fixture(t), o = await offer(f), duplicate = await call(f, 'GET', OFFER);
  assert.equal(duplicate.status, 409); cors(duplicate); assert.equal(duplicate.text.includes(o.nonce), false);
  await call(f, 'POST', COMPLETE, { value: complete(f, o) }); assert.equal(await f.pending, SYNTHETIC);
});

for (const [name, changes, status] of [
  ['wrong operation', { operation: 'admin.password.sign_in' }, 409],
  ['wrong widget attempt', { widget_attempt_id: '11111111-1111-4111-8111-111111111111' }, 409],
  ['wrong nonce', { nonce: 'A'.repeat(43) }, 403],
  ['unknown field', { callback: 'https://unapproved.example' }, 400],
  ['token and error', { error: 'cancelled' }, 400],
  ['oversized token', { token: 'X'.repeat(2049) }, 400],
  ['whitespace token', { token: 'SYNTHETIC SECRET' }, 400],
]) test(`${name} cannot return a candidate or echo private input`, async t => {
  const f = await fixture(t), o = await offer(f), r = await call(f, 'POST', COMPLETE, { value: complete(f, o, changes) });
  assert.equal(r.status, status); cors(r); assert.equal(r.text.includes(o.nonce), false); assert.equal(r.text.includes('SYNTHETIC'), false);
  await assert.rejects(f.pending, error => error instanceof SafeError && !error.message.includes(o.nonce));
});

test('duplicate decoded JSON keys are rejected rather than last-value-wins', async t => {
  const f = await fixture(t), o = await offer(f);
  const raw = JSON.stringify(complete(f, o)).replace('"token":', '"token":"FIRST_SYNTHETIC","to\\u006ben":');
  const r = await call(f, 'POST', COMPLETE, { raw });
  assert.equal(r.status, 400); cors(r); await assert.rejects(f.pending, { code: 'invalid_challenge' });
});

test('body byte bound and JSON media type are enforced before accepting a token', async t => {
  const f = await fixture(t); await offer(f);
  const r = await call(f, 'POST', COMPLETE, { raw: 'X'.repeat(16_385) });
  assert.equal(r.status, 413); cors(r); await assert.rejects(f.pending, { code: 'invalid_challenge' });
});

test('a non-JSON completion is refused with readable CORS and never returns a candidate', async t => {
  const f = await fixture(t), o = await offer(f);
  const r = await call(f, 'POST', COMPLETE, { value: complete(f, o), headers: { 'Content-Type': 'text/plain' } });
  assert.equal(r.status, 415); cors(r); await assert.rejects(f.pending, { code: 'invalid_challenge' });
});

test('the total request budget closes the listener without a candidate or automatic restart', async t => {
  const f = await fixture(t);
  for (let i = 0; i < 4; i++) { const r = await call(f, 'GET', '/not-a-handoff-path'); assert.equal(r.status, 404); cors(r); }
  const r = await call(f, 'GET', OFFER);
  assert.equal(r.status, 429); cors(r); await assert.rejects(f.pending, { code: 'invalid_challenge' });
  await assert.rejects(call(f, 'GET', OFFER));
});

test('a third preflight cannot extend the two-preflight job budget', async t => {
  const f = await fixture(t), headers = { 'Access-Control-Request-Method': 'GET',
    'Access-Control-Request-Headers': 'x-collect-handoff-version,x-collect-handoff-attempt' };
  for (let i = 0; i < 2; i++) assert.equal((await call(f, 'OPTIONS', OFFER, { headers })).status, 204);
  const r = await call(f, 'OPTIONS', OFFER, { headers });
  assert.equal(r.status, 429); cors(r); await assert.rejects(f.pending, { code: 'invalid_challenge' });
});

for (const error of ['cancelled', 'expired', 'unavailable', 'timeout', 'invalid_token']) test(`terminal widget ${error} closes without a token`, async t => {
  const f = await fixture(t), o = await offer(f), value = complete(f, o); delete value.token; value.error = error;
  const r = await call(f, 'POST', COMPLETE, { value });
  assert.equal(r.status, 202); cors(r); assert.notEqual(r.value.status, 'accepted_for_one_cli_operation');
  assert.equal(r.value.session_confirmed, false); await assert.rejects(f.pending, e => e instanceof SafeError);
});

test('cancellation before pairing creates no callback and no listener', async () => {
  const c = new AbortController(); c.abort(); let called = 0;
  await assert.rejects(acquireHumanChallenge(CONFIG, { operation: 'admin.email_otp.send', signal: c.signal,
    onPairing: () => called++ }), { code: 'challenge_cancelled' }); assert.equal(called, 0);
});

test('abort closes its own open listener before rejection', async t => {
  const f = await fixture(t); f.controller.abort();
  await assert.rejects(f.pending, { code: 'challenge_cancelled' }); await assert.rejects(call(f, 'GET', OFFER));
});

test('an unresolved pairing callback cannot extend the fixed deadline', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let paired; const ready = new Promise(resolve => { paired = resolve; });
  const pending = acquireHumanChallenge(CONFIG, { operation: 'admin.email_otp.send',
    onPairing: info => { paired(info); return new Promise(() => {}); } });
  pending.catch(() => {}); const info = await pairingOrStopped(ready, pending);
  t.mock.timers.tick(120_000);
  await assert.rejects(pending, { code: 'challenge_expired' });
  await assert.rejects(call(info, 'GET', OFFER));
});

test('only one acquisition may own a listener at a time', async t => {
  const f = await fixture(t);
  await assert.rejects(acquireHumanChallenge(CONFIG, { operation: 'admin.email_otp.verify', onPairing: () => {} }), { code: 'challenge_pending' });
  f.controller.abort(); await assert.rejects(f.pending, { code: 'challenge_cancelled' });
});

test('different origin, unknown operation and production callback overrides fail before pairing', async () => {
  for (const [config, options] of [
    [{ origin: 'https://unapproved.example' }, {}], [CONFIG, { operation: 'arbitrary.sql' }],
    [CONFIG, { operation: 'admin.email_otp.send', callback: 'http://127.0.0.1:1/' }],
  ]) await assert.rejects(acquireHumanChallenge(config, { operation: 'admin.email_otp.send', onPairing: () => assert.fail('pairing not expected'), ...options }), { code: 'invalid_challenge' });
});

const QA='https://admin-supabase-qa.collect.ikanisa.com';
for(const origin of [ADMIN_ORIGIN,QA]) test(`fixed approved origin ${origin} stays bound in parent, signed offer, completion and CORS`,async t=>{
  const f=await fixture(t,'admin.password.sign_in',origin);
  assert.equal(f.parentUrl,origin+'/admin/auth/local-challenge');assert.equal(f.descriptor.admin_origin,origin);
  const other=origin===QA?ADMIN_ORIGIN:QA;
  const foreign=await call(f,'GET',OFFER,{headers:{Origin:other}});
  assert.equal(foreign.status,403);assert.equal(foreign.headers['access-control-allow-origin'],undefined);
  const o=await offer(f);assert.equal(o.admin_origin,origin);
  const r=await call(f,'POST',COMPLETE,{value:complete(f,o)});assert.equal(r.status,202);cors(r,origin);
  assert.equal(await f.pending,SYNTHETIC);
});
for(const origin of [QA+'/',QA+':443',QA+'.evil.example',QA.replace('https:','http:'),'https://admin16-security-stage.collect.ikanisa.com']) test(`unapproved configured origin ${origin} never pairs`,async()=>{
  await assert.rejects(acquireHumanChallenge({origin},{operation:'admin.password.sign_in',onPairing:()=>assert.fail('must not pair')}),{code:'invalid_challenge'});
});
