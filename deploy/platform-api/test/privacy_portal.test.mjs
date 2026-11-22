import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {privacyPortalRoute} from '../src/privacy_portal.js';
import {privacyPortalScript} from '../src/privacy_portal_assets.js';

// Import the exact served module. Outbound calls are controlled here; actual
// Worker/D1 authority and no-registration admission are covered by server tests.
const client = await import('data:text/javascript;base64,' + Buffer.from(privacyPortalScript).toString('base64'));
const number = '+250788123456';
const start = Date.parse('2026-10-16T12:00:00.000Z');
const stamp = '2026-10-16T12:00:00.000000Z';
function problem(code, status) {return Object.assign(new Error(code), {code, status});}
function intake(id, {submission = null, reason = false} = {}) {
  return {
    contract_version: 1, request_id: id, scope: 'own_account_eligible_data', state: 'pending_review',
    reason_code: 'account_deletion_requested', reason_supplied: reason, accepted_at: stamp,
    policy_review_pending: true, subject_scope_review_pending: true, erasure_completed: false,
    account_access_restricted: false, auth_removed: false, retention_approval_granted: false,
    processor_operation_started: false,
    ...(submission ? {submission_id: submission, replay: false, equivalent_active_request: false} : {}),
  };
}
function review(id) {
  return {
    contract_version: 1, scope: 'own_account_privacy_review', request_id: id, checked_at: stamp,
    revision: 0, review_state: 'not_started', outcome_code: null, outcome_recorded_at: null,
    completion: 'blocked', blocking_reason: 'policy_authority_unavailable', policy_acceptance_granted: false,
    subject_scope_review_pending: true, legal_hold_review_pending: true, copy_dispositions_verified: false,
    destructive_execution_available: false, erasure_completed: false, account_access_restricted: false,
    auth_removed: false, processor_operation_started: false,
  };
}
function harness({storage = {value: null}, user = randomUUID()} = {}) {
  let clock = start;
  const h = {calls: [], challenges: 0, changes: [], accepted: null, user, session: randomUUID(), hook: null, storage};
  const request = async (path, body, token) => {
    h.calls.push({path, body: structuredClone(body), token});
    if (h.hook) {const result = await h.hook(path, body, token);if (result !== undefined) return result;}
    if (path === '/v1/auth/otp') return {accepted: true, challenge_id: body.request_id, request_id: body.request_id, channel: 'whatsapp', retry_after: 60};
    if (path === '/v1/auth/verify') {
      const claims = {sub: h.user, session_id: h.session, role: 'authenticated', exp: Math.floor(clock / 1000) + 900, auth_time: Math.floor(clock / 1000)};
      const token = Buffer.from('{"alg":"HS256","typ":"JWT"}').toString('base64url') + '.' + Buffer.from(JSON.stringify(claims)).toString('base64url') + '.isolated-test-signature';
      return {access_token: token, expires_at: claims.exp, token_type: 'bearer', refresh_token: 'private-refresh-token-never-persist', user: {id: h.user, phone: number, is_anonymous: false}};
    }
    if (path.endsWith('/get_current_account_deletion_request_status_v1')) return h.accepted;
    if (path.endsWith('/get_account_deletion_request_status_v1')) {
      if (!h.accepted) throw problem('privacy_request_unavailable', 404);
      return h.accepted;
    }
    if (path.endsWith('/request_account_deletion_v1')) {
      h.accepted = intake(body.p_request_id);
      return intake(body.p_request_id, {submission: body.p_request_id});
    }
    if (path.endsWith('/get_account_deletion_review_status_v1')) return review(body.p_request_id);
    if (path === '/v1/auth/logout') return {ok: true};
    assert.fail('Unexpected portal request: ' + path);
  };
  h.create = () => client.createPrivacyPortalController({request, challenge: async () => 'fresh-challenge-' + (++h.challenges), randomUUID, now: () => clock,
    checkpoint: {read: () => storage.value, write: value => {storage.value = structuredClone(value);}, clear: () => {storage.value = null;}},
    changed: state => h.changes.push(state),
  });
  h.controller = h.create();
  h.advance = milliseconds => {clock += milliseconds;};
  h.signIn = async () => {await h.controller.requestCode(number);await h.controller.verifyCode('123456');};
  h.confirm = async () => {await h.controller.reviewRequest();await h.controller.submit();};
  return h;
}

test('public presentation reports unavailable verification truthfully without exposing provider configuration', async () => {
  const url = 'https://api.collect.example/privacy/account-deletion';
  for (const env of [{}, {OTP_DELIVERY_TOKEN: 'private-provider-token'},
    {OTP_DELIVERY_TOKEN: 'private-provider-token', OTP_DELIVERY_URL: 'http://relay.example/otp'},
    {OTP_DELIVERY_TOKEN: 'private-provider-token', OTP_DELIVERY_URL: 'https://relay.example/otp?private=secret'}]) {
    const body = await privacyPortalRoute(new Request(url), env).text();
    assert.match(body, /data-verification-available="false"/);
    assert.match(body, /Phone verification is currently unavailable/);
    assert.match(body, /id="step-phone" hidden/);
    assert.match(body, /request a review by email/);
    assert.ok(!body.includes('private-provider-token') && !body.includes('relay.example'));
  }
  const body = await privacyPortalRoute(new Request(url), {
    OTP_DELIVERY_TOKEN: 'private-provider-token', OTP_DELIVERY_URL: 'https://relay.example/otp',
  }).text();
  assert.match(body, /data-verification-available="true"/);
  assert.ok(!body.includes('id="verification-unavailable"') && !body.includes('id="step-phone" hidden'));
  assert.ok(!body.includes('private-provider-token') && !body.includes('relay.example'));
});

test('public route serves only exact portal/asset GET or HEAD with no private configuration or cache', async () => {
  const env = {AUTH_JWT_SECRET: 'do-not-render-secret', OTP_DELIVERY_TOKEN: 'private-provider-token'};
  for (const path of ['/privacy/account-deletion', '/privacy/account-deletion/', '/privacy/account-deletion/assets/client.js', '/privacy/account-deletion/assets/style.css']) {
    const response = privacyPortalRoute(new Request('https://api.collect.example' + path + '?phone=private-number'), env);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
    assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(response.headers.get('x-frame-options'), 'DENY');
    const csp = response.headers.get('content-security-policy');
    for (const rule of ["default-src 'none'", "script-src 'self'", "connect-src 'self'", "frame-src 'self'", "frame-ancestors 'none'", "form-action 'none'"]) assert.ok(csp.includes(rule));
    assert.ok(!csp.includes('unsafe-inline'));
    const body = await response.text();
    for (const secret of ['do-not-render-secret', 'private-provider-token', 'private-number']) assert.ok(!body.includes(secret));
    const head = privacyPortalRoute(new Request('https://api.collect.example' + path, {method: 'HEAD'}), env);
    assert.equal(head.status, 200);assert.equal(await head.text(), '');
    assert.equal(privacyPortalRoute(new Request('https://api.collect.example' + path, {method: 'POST'}), env).status, 405);
  }
  assert.equal(privacyPortalRoute(new Request('https://api.collect.example/privacy/account-deletion/assets/unknown.js'), env), null);
  assert.equal(privacyPortalRoute(new Request('https://api.collect.example/v1/rpc/request_account_deletion_v1'), env), null);
});

test('portal is usable semantic HTML without an app and contains truthful support and fallback', async () => {
  const response = privacyPortalRoute(new Request('https://api.collect.example/privacy/account-deletion'), {});
  const html = await response.text();
  for (const content of ['<html lang="en">', '<main', '<label for="phone">', '<label for="code">', 'autocomplete="one-time-code"', 'role="status"', 'role="alert"', '<noscript>', 'mailto:info@ikanisa.com', 'Records have not been erased', 'type="module"']) assert.ok(html.includes(content), content);
  assert.ok(!html.includes('type="file"'));assert.ok(!html.includes('localStorage'));assert.ok(!html.includes('serviceWorker'));
});

test('actual client binds fresh security checks to no-registration OTP and existing authenticated request/status', async () => {
  const h = harness();await h.signIn();
  assert.equal(h.controller.state.step, 'request');assert.equal(h.challenges, 2);
  const otp = h.calls.find(c => c.path === '/v1/auth/otp');
  assert.equal(otp.body.create_account, false);assert.equal(otp.body.surface, 'member');
  const verify = h.calls.find(c => c.path === '/v1/auth/verify');
  assert.ok(!Object.hasOwn(verify.body, 'create_account'));assert.notEqual(verify.body.captcha_token, otp.body.captcha_token);
  assert.ok(!h.calls.some(c => c.path.endsWith('/request_account_deletion_v1')));
  await h.confirm();
  assert.equal(h.controller.state.step, 'received');assert.equal(h.controller.state.review.state, 'not_started');
  assert.match(h.controller.state.message, /not been erased/);
  const submit = h.calls.find(c => c.path.endsWith('/request_account_deletion_v1'));
  assert.deepEqual(Object.keys(submit.body).sort(), ['p_reason', 'p_request_id']);assert.equal(submit.body.p_reason, null);assert.ok(submit.token);
  assert.equal(h.storage.value, null);assert.ok(!JSON.stringify(h.changes).includes('private-refresh-token'));
});

test('outside-app status reads an existing in-app request without exposing its optional reason', async () => {
  const h = harness();h.accepted = intake(randomUUID(), {reason: true});await h.signIn();
  assert.equal(h.controller.state.step, 'received');assert.equal(h.controller.state.receipt.requestId, h.accepted.request_id);
  assert.ok(!h.calls.some(c => c.path.endsWith('/request_account_deletion_v1')));
});

test('lost response after commit resolves from status without another write', async () => {
  const h = harness();await h.signIn();
  h.hook = async (path, body) => {if (path.endsWith('/request_account_deletion_v1')) {h.accepted = intake(body.p_request_id);throw new Error('network lost');}};
  await h.controller.reviewRequest();await assert.rejects(h.controller.submit());
  assert.equal(h.controller.state.unknown, true);assert.equal(h.controller.state.canRetry, false);
  await assert.rejects(h.controller.submit({retry: true}));
  await h.controller.checkStatus();assert.equal(h.controller.state.step, 'received');
  assert.equal(h.calls.filter(c => c.path.endsWith('/request_account_deletion_v1')).length, 1);
});

test('lost request requires a successful status read then explicit exact-UUID replay', async () => {
  const h = harness();await h.signIn();let first = true;
  h.hook = async path => {if (first && path.endsWith('/request_account_deletion_v1')) {first = false;throw new Error('network lost');}};
  await h.controller.reviewRequest();await assert.rejects(h.controller.submit());
  assert.deepEqual(Object.keys(h.storage.value).sort(), ['subject_id', 'submission_id', 'version']);
  assert.ok(!JSON.stringify(h.storage.value).includes(number));assert.ok(!JSON.stringify(h.storage.value).includes('token'));
  await h.controller.checkStatus();assert.equal(h.controller.state.canRetry, true);
  await h.controller.submit({retry: true});
  const writes = h.calls.filter(c => c.path.endsWith('/request_account_deletion_v1'));
  assert.equal(writes.length, 2);assert.deepEqual(writes[0].body, writes[1].body);
  assert.equal(h.controller.state.step, 'received');
});

test('reload re-verifies identity and recovers only the minimal checkpoint before replay', async () => {
  const h = harness();await h.signIn();let first = true;
  h.hook = async path => {if (first && path.endsWith('/request_account_deletion_v1')) {first = false;throw new Error('lost');}};
  await h.controller.reviewRequest();await assert.rejects(h.controller.submit());const submission = h.storage.value.submission_id;
  h.controller.destroy();h.controller = h.create();h.session = randomUUID();
  assert.equal(h.controller.state.signedIn, false);await h.signIn();assert.equal(h.controller.state.step, 'unknown');
  await h.controller.submit({retry: true});assert.equal(h.controller.state.receipt.requestId, submission);
});

test('a new account cannot recover or replay the previous account checkpoint', async () => {
  const storage = {value: {version: 1, subject_id: randomUUID(), submission_id: randomUUID()}};
  const previous = structuredClone(storage.value);const h = harness({storage});await h.signIn();
  assert.equal(h.controller.state.step, 'request');assert.equal(storage.value, null);
  assert.ok(!h.calls.some(c => c.body.p_request_id === previous.submission_id));
});

test('failed status does not authorize an uncertain replay and raw errors never become copy', async () => {
  const h = harness();await h.signIn();h.hook = async path => {if (path.endsWith('/request_account_deletion_v1')) throw new Error('lost');};
  await h.controller.reviewRequest();await assert.rejects(h.controller.submit());
  h.hook = async path => {if (path.includes('status')) throw problem('private-provider-body-PIN1234', 503);};
  await assert.rejects(h.controller.checkStatus());assert.equal(h.controller.state.canRetry, false);
  assert.ok(!h.controller.state.error.includes('PIN1234'));await assert.rejects(h.controller.submit({retry: true}));
});

test('expiry and clear discard delayed submission receipts without claiming the request failed', async () => {
  for (const action of ['expiry', 'clear']) {
    const h = harness();await h.signIn();let resolve;
    h.hook = async (path, body) => {if (path.endsWith('/request_account_deletion_v1')) return new Promise(done => {resolve = () => done(intake(body.p_request_id, {submission: body.p_request_id}));});};
    await h.controller.reviewRequest();const waiting = h.controller.submit();await new Promise(done => setImmediate(done));
    if (action === 'expiry') {h.advance(901000);h.controller.tick();assert.ok(h.storage.value);} else {await h.controller.clear();assert.equal(h.storage.value, null);}
    resolve();await assert.rejects(waiting);assert.equal(h.controller.state.receipt, null);assert.equal(h.controller.state.signedIn, false);
  }
});

test('a five-minute-old verification cannot submit and no-registration OTP uncertainty is not blind resent', async () => {
  const h = harness();await h.signIn();h.advance(301000);
  await assert.rejects(h.controller.reviewRequest());assert.equal(h.controller.state.signedIn, false);
  assert.ok(!h.calls.some(c => c.path.endsWith('/request_account_deletion_v1')));
  const g = harness();g.hook = async path => {if (path === '/v1/auth/otp') throw problem('otp_delivery_unknown', 503);};
  await g.controller.requestCode(number);assert.equal(g.controller.state.step, 'code');
  await assert.rejects(g.controller.requestCode(number, {newAttempt: true}));assert.equal(g.calls.length, 1);
  g.advance(61000);await g.controller.requestCode(number);
  assert.equal(g.calls[0].body.request_id, g.calls[1].body.request_id);
});

test('malformed completion or foreign review receipt cannot become deletion success', async () => {
  const h = harness();await h.signIn();h.hook = async (path, body) => {
    if (path.endsWith('/request_account_deletion_v1')) return {...intake(body.p_request_id, {submission: body.p_request_id}), erasure_completed: true};
  };
  await h.controller.reviewRequest();await assert.rejects(h.controller.submit());assert.equal(h.controller.state.receipt, null);assert.equal(h.controller.state.unknown, true);
  const g = harness();g.accepted = intake(randomUUID());g.hook = async path => {if (path.endsWith('/get_account_deletion_review_status_v1')) return review(randomUUID());};
  await g.signIn();assert.equal(g.controller.state.step, 'received');assert.equal(g.controller.state.review, null);assert.match(g.controller.state.error, /could not be confirmed/);
});

test('CAPTCHA messages bind origin, source, attempt, strict envelope and bounded token', () => {
  const source = {}, origin = 'https://api.collect.example', attempt = randomUUID(), config = {origin, source, attempt};
  const event = {origin, source, data: {type: 'collect.turnstile.v1', attempt_id: attempt, token: 'fresh-token'}};
  assert.equal(client.captchaEnvelope(event, config), 'fresh-token');
  for (const changed of [{origin: 'https://evil.example'}, {source: {}}, {data: {...event.data, attempt_id: randomUUID()}}]) assert.equal(client.captchaEnvelope({...event, ...changed}, config), null);
  for (const data of [{...event.data, secret: 'unexpected'}, {...event.data, token: 'bad token'}, {...event.data, token: 'x'.repeat(2049)}, {type: event.data.type, attempt_id: attempt, error: 'expired'}]) assert.throws(() => client.captchaEnvelope({...event, data}, config));
});

test('actual fetch adapter omits ambient credentials and uses only maintained own-account endpoints', async () => {
  const previous = globalThis.fetch;let seen;
  globalThis.fetch = async (path, options) => {seen = {path, options};return Response.json(null);};
  try {
    await client.portalRequest('/v1/rpc/get_current_account_deletion_request_status_v1', {}, 'controlled-session-token');
    assert.equal(seen.options.credentials, 'omit');assert.equal(seen.options.cache, 'no-store');assert.equal(seen.options.redirect, 'error');assert.equal(seen.options.referrerPolicy, 'no-referrer');
    assert.equal(seen.options.headers.Authorization, 'Bearer controlled-session-token');assert.deepEqual(JSON.parse(seen.options.body), {});
    await assert.rejects(client.portalRequest('https://evil.example/steal', {}, 'controlled-session-token'));
  } finally {globalThis.fetch = previous;}
});
