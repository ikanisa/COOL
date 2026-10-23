import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {privacyPortalScript} from '../../../supabase/functions/_shared/domain/privacy_portal_assets.js';
import {startOtp} from '../../../supabase/functions/_shared/domain/auth.js';

// Import the exact served browser module and execute current startOtp. Only its
// DB interface and HTTP provider are synthetic; no PostgreSQL/provider proof.
const client = await import('data:text/javascript;base64,' + Buffer.from(privacyPortalScript).toString('base64'));
const phone = '+250788000001';
const origin = 'https://privacy-auth.invalid';
const jwt = claims => Buffer.from('{"alg":"ES256","typ":"JWT"}').toString('base64url') + '.' +
  Buffer.from(JSON.stringify(claims)).toString('base64url') + '.synthetic-not-a-signature';
const error = (code, status) => Object.assign(new Error(code), {code, status});
const stamp = now => new Date(now).toISOString().replace(/\.(\d{3})Z$/, '.$1000Z');

function intake(id, now, submission = null) {
  return {contract_version: 1, request_id: id, scope: 'own_account_eligible_data', state: 'pending_review',
    reason_code: 'account_deletion_requested', reason_supplied: false, accepted_at: stamp(now),
    policy_review_pending: true, subject_scope_review_pending: true, erasure_completed: false,
    account_access_restricted: false, auth_removed: false, retention_approval_granted: false,
    processor_operation_started: false,
    ...(submission ? {submission_id: submission, replay: false, equivalent_active_request: false} : {})};
}
function review(id, now) {
  return {contract_version: 1, scope: 'own_account_privacy_review', request_id: id, checked_at: stamp(now),
    revision: 0, review_state: 'not_started', outcome_code: null, outcome_recorded_at: null,
    completion: 'blocked', blocking_reason: 'policy_authority_unavailable', policy_acceptance_granted: false,
    subject_scope_review_pending: true, legal_hold_review_pending: true, copy_dispositions_verified: false,
    destructive_execution_available: false, erasure_completed: false, account_access_restricted: false,
    auth_removed: false, processor_operation_started: false};
}
class Statement {
  constructor(db, sql) { this.db = db; this.sql = sql; this.values = []; }
  bind(...values) { this.values = values; return this; }
  async first() {
    assert.match(this.sql, /^SELECT id FROM users WHERE phone=/);
    return this.db.eligible ? {id: this.db.principal} : null;
  }
  async run() {
    assert.match(this.sql, /^UPDATE private\.supabase_otp_challenges SET delivery_status=/);
    const challenge = this.db.reservations.find(row => row.id === this.values[1]);
    assert.ok(challenge); challenge.delivery = this.values[0];
    return {meta: {changes: 1}};
  }
}
function harness(t, {eligible = true, providerUnknown = false, storage = {value: null}} = {}) {
  let clock = Date.now();
  const h = {principal: randomUUID(), managed: randomUUID(), session: randomUUID(), calls: [],
    provider: [], accepted: null, hook: null, storage, securityChecks: 0};
  h.db = {eligible, principal: h.principal, reservations: [], prepare: sql => new Statement(h.db, sql),
    async batch(statements) {
      const insert = statements.find(s => s.sql.startsWith('INSERT INTO private.supabase_otp_challenges('));
      assert.ok(insert); const [id, , , identity, surface, registrationAllowed] = insert.values;
      h.db.reservations.push({id, identity, surface, registrationAllowed, delivery: 'reserved'});
      return statements.map(() => ({meta: {changes: 1}}));
    }};
  const env = {DB: h.db, AUTH_MEMBER_REGISTRATION_ENABLED: 'true', SUPABASE_URL: origin,
    SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_synthetic_privacy_only'};
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    h.provider.push({url, init, body: JSON.parse(init.body)});
    if (providerUnknown) throw new TypeError('synthetic provider acknowledgement lost');
    return Response.json({message_id: 'synthetic-only'});
  };
  t.after(() => {
    globalThis.fetch = previousFetch;
    // These postconditions cannot be swallowed as an unknown provider outcome.
    for (const call of h.provider) {
      assert.equal(call.url, origin + '/auth/v1/otp');
      assert.equal(call.init.method, 'POST'); assert.equal(call.init.redirect, 'error');
      assert.equal(call.init.headers.apikey, env.SUPABASE_PUBLISHABLE_KEY);
      assert.equal(call.body.create_user, false); assert.equal(call.body.channel, 'whatsapp');
      assert.equal(call.body.phone, phone);
      assert.equal(Object.hasOwn(call.init.headers, 'Authorization'), false);
    }
  });
  h.dto = () => {
    const at = Math.floor(clock / 1000), claims = {sub: h.managed, session_id: h.session,
      aud: 'authenticated', role: 'authenticated', iat: at, exp: at + 900,
      amr: [{method: 'otp', timestamp: at}]};
    return {claims, value: {access_token: jwt(claims), token_type: 'bearer', expires_in: 900,
      refresh_token: 'synthetic-never-persist', user: {id: h.principal, auth_user_id: h.managed,
        phone: phone.slice(1), phone_confirmed_at: new Date(clock - 1000).toISOString(), is_anonymous: false}}};
  };
  h.request = async (path, body, token) => {
    h.calls.push({path, body: structuredClone(body), token});
    if (h.hook) { const reply = await h.hook(path, body, token); if (reply !== undefined) return reply; }
    if (path === '/v1/auth/otp') return startOtp(env, body);
    if (path === '/v1/auth/verify') {
      assert.equal(body.challenge_id, h.db.reservations.at(-1).id);
      assert.equal(body.phone, phone); assert.equal(body.surface, 'member');
      return h.dto().value;
    }
    if (path.endsWith('/get_current_account_deletion_request_status_v1')) return h.accepted;
    if (path.endsWith('/get_account_deletion_request_status_v1')) {
      if (!h.accepted) throw error('privacy_request_unavailable', 404);
      return h.accepted;
    }
    if (path.endsWith('/request_account_deletion_v1')) {
      h.accepted = intake(body.p_request_id, clock);
      return intake(body.p_request_id, clock, body.p_request_id);
    }
    if (path.endsWith('/get_account_deletion_review_status_v1')) return review(body.p_request_id, clock);
    if (path === '/v1/auth/logout') return {ok: true};
    assert.fail('Unexpected local request: ' + path);
  };
  h.create = () => client.createPrivacyPortalController({request: h.request, now: () => clock,
    randomUUID, challenge: async () => 'synthetic-captcha-' + (++h.securityChecks),
    checkpoint: {read: () => storage.value, write: value => {storage.value = structuredClone(value);},
      clear: () => {storage.value = null;}}});
  h.controller = h.create();
  h.advance = ms => {clock += ms;};
  h.signIn = async () => {await h.controller.requestCode(phone); await h.controller.verifyCode('123456');};
  return h;
}

test('actual Supabase OTP and mapped managed response reach deletion intake with registration disabled', async t => {
  const h = harness(t); await h.signIn();
  assert.equal(h.controller.state.step, 'request'); assert.equal(h.securityChecks, 2);
  const otp = h.calls.find(c => c.path === '/v1/auth/otp');
  assert.equal(otp.body.allow_registration, false); assert.equal(otp.body.should_create_user, false);
  assert.equal(Object.hasOwn(otp.body, 'create_account'), false);
  assert.equal(h.db.reservations[0].registrationAllowed, 0);
  assert.notEqual(h.principal, h.managed);
  await h.controller.reviewRequest(); await h.controller.submit();
  assert.equal(h.controller.state.step, 'received');
  assert.match(h.controller.state.message, /have not been erased/);
  assert.equal(h.storage.value, null);
});

test('an unregistered phone cannot create an account even when member registration is enabled', async t => {
  const h = harness(t, {eligible: false});
  await assert.rejects(h.controller.requestCode(phone), e => e.code === 'registration_unavailable');
  assert.equal(h.provider.length, 0); assert.equal(h.db.reservations.length, 0);
  assert.equal(h.controller.state.signedIn, false);
});

test('a retained unknown delivery receipt can verify using its actual server challenge', async t => {
  const h = harness(t, {providerUnknown: true}); await h.signIn();
  assert.equal(h.db.reservations[0].delivery, 'unknown');
  assert.equal(h.controller.state.step, 'request');
});

test('a lost OTP HTTP reply never guesses a challenge; explicit resend after cooldown can recover', async t => {
  const h = harness(t);
  h.hook = async path => {if (path === '/v1/auth/otp') throw new TypeError('synthetic reply lost');};
  await h.controller.requestCode(phone);
  assert.equal(h.controller.state.step, 'phone');
  await assert.rejects(h.controller.verifyCode('123456'), e => e.code === 'invalid_code');
  assert.equal(h.calls.filter(c => c.path === '/v1/auth/verify').length, 0);
  await assert.rejects(h.controller.requestCode(phone), e => e.code === 'rate_limited');
  h.advance(60001); h.hook = null; await h.signIn();
  assert.equal(h.controller.state.step, 'request');
});

for (const [name, mutate] of [
  ['invalid challenge', value => ({...value, challenge_id: 'unbound'})],
  ['rejected delivery', value => ({...value, delivery_status: 'rejected'})],
  ['wrong channel', value => ({...value, channel: 'sms'})],
  ['invalid lifetime', value => ({...value, expires_in: 0})],
]) {
  test('malformed managed OTP receipt fails closed: ' + name, async t => {
    const h = harness(t);
    h.hook = path => path === '/v1/auth/otp' ? mutate({challenge_id: randomUUID(),
      retry_after: 60, expires_in: 300, channel: 'whatsapp', delivery_status: 'accepted'}) : undefined;
    await assert.rejects(h.controller.requestCode(phone), e => e.code === 'protocol_unavailable');
    await assert.rejects(h.controller.verifyCode('123456'), e => e.code === 'invalid_code');
    assert.equal(h.controller.state.signedIn, false);
  });
}

for (const [name, mutate] of [
  ['foreign managed subject', (claims, value) => {claims.sub = randomUUID();}],
  ['missing principal link', (claims, value) => {delete value.user.auth_user_id;}],
  ['different phone', (claims, value) => {value.user.phone = '250789000001';}],
  ['unconfirmed phone', (claims, value) => {delete value.user.phone_confirmed_at;}],
  ['stale authentication in a new token', claims => {claims.amr[0].timestamp -= 301;}],
  ['future authentication', claims => {claims.iat += 60; claims.amr[0].timestamp += 60;}],
  ['expired session', claims => {claims.exp = claims.iat - 1;}],
]) {
  test('managed identity/freshness checks refuse ' + name, async t => {
    const h = harness(t); await h.controller.requestCode(phone);
    h.hook = path => {
      if (path !== '/v1/auth/verify') return;
      const {claims, value} = h.dto(); mutate(claims, value); value.access_token = jwt(claims); return value;
    };
    await assert.rejects(h.controller.verifyCode('123456'), e => e.code === 'protocol_unavailable');
    assert.equal(h.controller.state.signedIn, false);
    assert.equal(h.calls.filter(c => c.path.includes('/v1/rpc/')).length, 0);
  });
}

test('a lost deletion acknowledgement is recovered after restart under the same legacy principal', async t => {
  const h = harness(t); await h.signIn(); await h.controller.reviewRequest();
  h.hook = (path, body) => {
    if (path.endsWith('/request_account_deletion_v1')) {
      h.accepted = intake(body.p_request_id, Date.now()); throw new TypeError('synthetic acknowledgement lost');
    }
  };
  await assert.rejects(h.controller.submit(), /acknowledgement lost/);
  assert.equal(h.controller.state.unknown, true);
  assert.equal(h.storage.value.subject_id, h.principal);
  assert.equal(Object.keys(h.storage.value).sort().join(','), 'subject_id,submission_id,version');
  const reference = h.storage.value.submission_id;
  h.controller.destroy(); h.hook = null; h.controller = h.create(); await h.signIn();
  assert.equal(h.controller.state.step, 'received'); assert.equal(h.controller.state.receipt.requestId, reference);
  assert.equal(h.calls.filter(c => c.path.endsWith('/request_account_deletion_v1')).length, 1);
  assert.equal(h.storage.value, null);
});

test('clearing during verification fences the late response and starts no deletion/status operation', async t => {
  const h = harness(t); await h.controller.requestCode(phone);
  let resolveReply, entered;
  const waiting = new Promise(resolve => {entered = resolve;});
  h.hook = path => path === '/v1/auth/verify' ? new Promise(resolve => {resolveReply = resolve; entered();}) : undefined;
  const verifying = h.controller.verifyCode('123456'); await waiting;
  await h.controller.clear(); resolveReply(h.dto().value);
  await assert.rejects(verifying, e => e.code === 'cancelled');
  assert.equal(h.controller.state.signedIn, false); assert.equal(h.storage.value, null);
  assert.equal(h.calls.filter(c => c.path.includes('/v1/rpc/')).length, 0);
});
