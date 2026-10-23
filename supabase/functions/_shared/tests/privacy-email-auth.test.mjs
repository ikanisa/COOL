import {wrapFixtureModule} from './helpers/fenced-module.js';
import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {isAbsolute, join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Root supplies a coherent actual _shared graph. No copied controller, helper
// imports, real HTTP, JWT signature verification or PostgreSQL authority proof.
// The helper fixture models receipts/CAS only; actual SQL remains independently
// qualified. Global fetch/clock replacements are restored before final checks.
const sourceRoot = process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof sourceRoot === 'string' && isAbsolute(sourceRoot),
  'COLLECT_AUTH_SOURCE_ROOT must name the absolute actual _shared source graph.');
const actual = async name => {if(name==='postgres.js')return import('./helpers/fenced-postgres.js');return wrapFixtureModule(name,await import(pathToFileURL(join(sourceRoot, name)).href));};
const {handlePrivacyEmailAuth} = await actual('domain/privacy_email_auth.js');
const {ApiError} = await actual('domain/core.js');
const {default: privacyApi} = await actual('domain/index.js');

const NOW = 1_792_497_600;
const PROJECT = 'https://privacy-email.synthetic.invalid';
const EMAIL = 'synthetic.member@example.invalid';
const AUTH = '11111111-1111-4111-8111-111111111111';
const PRINCIPAL = '22222222-2222-4222-8222-222222222222';
const ORIGINAL = '33333333-3333-4333-8333-333333333333';
const CANDIDATE = '44444444-4444-4444-8444-444444444444';
const REPLACEMENT = '55555555-5555-4555-8555-555555555555';
const OTHER_AUTH = '66666666-6666-4666-8666-666666666666';
const OTHER_PRINCIPAL = '77777777-7777-4777-8777-777777777777';
const CHALLENGE = '88888888-8888-4888-8888-888888888888';
const OPERATION = '99999999-9999-4999-8999-999999999999';
const CONTEXT = Buffer.alloc(32, 7).toString('base64url');
const CONTEXT_HASH = createHash('sha256').update(CONTEXT).digest('hex');
const CODE = '184275';
const REFRESH = 'synthetic-private-refresh-token';
const PRIVATE = 'synthetic-private-provider-detail';
const KEY = 'sb_publishable_synthetic_privacy_only';
const PURPOSE = 'account_deletion_request';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const clone = value => structuredClone(value);
const base = (mode = 'current_session') => ({contract_version: 1, purpose: PURPOSE,
  mode, challenge_id: CHALLENGE, challenge_context: CONTEXT});
const claims = (session, extra = {}) => ({sub: AUTH, session_id: session,
  role: 'authenticated', aud: 'authenticated', aal: 'aal1',
  iss: PROJECT + '/auth/v1', exp: NOW + 3600, iat: NOW,
  amr: [{method: 'otp', timestamp: NOW}], ...extra});
const jwt = value => [Buffer.from('{"alg":"synthetic-stub-only"}').toString('base64url'),
  Buffer.from(JSON.stringify(value)).toString('base64url'), 'synthetic-signature'].join('.');
const managedUser = (extra = {}) => ({id: AUTH, email: EMAIL,
  email_confirmed_at: '2026-10-20T12:00:00Z', app_metadata: {provider: 'email'}, ...extra});
const projected = (session, extra = {}) => ({id: session, user_id: PRINCIPAL,
  surface: 'member', auth_at: NOW - 600, created_at: NOW - 600,
  expires_at: NOW + 3600, revoked_at: null, assurance_level: 1,
  mfa_at: null, mfa_factor_id: null, ...extra});
const helperSignatures = {
  prepare: '?::text,?::text,?::text,?::text', send_claim: '?::text,?::text,?::uuid',
  send_finish: '?::text,?::text,?::uuid,?::text', verify_claim: '?::text,?::text,?::uuid',
  verify_finish: '?::text,?::text,?::uuid,?::text', consume: '?::text,?::text,?::uuid',
  status: '?::text,?::text', cancel: '?::text,?::text,?::uuid',
  cleanup_claim: '?::text,?::text,?::uuid,?::uuid',
  cleanup_finish: '?::text,?::text,?::uuid,?::uuid,?::text',
};

class Statement {
  constructor(db, sql) {this.db = db; this.sql = sql; this.values = [];}
  bind(...values) {this.values = values; return this;}
  first() {return this.db.first(this.sql, this.values);}
  all() {return this.db.unexpected('Unexpected all(): ' + this.sql);}
  run() {
    const db = this.db;
    db.writes.push({sql: this.sql, values: clone(this.values)});
    if (this.sql === 'INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at,assurance_level,mfa_at,mfa_factor_id) VALUES(?,?,?,?,?,?,1,NULL,NULL) ON CONFLICT(id) DO NOTHING') {
      const [session, user, surface, authAt, createdAt, expiresAt] = this.values;
      db.check(user === PRINCIPAL && surface === 'member', 'Projection must preserve the existing member');
      db.events.push('projection-insert');
      if (!db.sessions.has(session)) db.sessions.set(session, projected(session,
        {user_id: user, surface, auth_at: authAt, created_at: createdAt, expires_at: expiresAt}));
      db.options.afterProjection?.(db);
      return {meta: {changes: 1}};
    }
    return db.unexpected('Unapproved write, including principal/link creation: ' + this.sql);
  }
}
class Database {
  constructor(options = {}) {
    this.options = options; this.claims = {}; this.reads = []; this.writes = [];
    this.helpers = []; this.events = []; this.violations = []; this.prepared = false;
    this.members = new Map([[AUTH, {user_id: PRINCIPAL, access_status: 'active', revision: 7}]]);
    this.sessions = new Map([[ORIGINAL, projected(ORIGINAL)]]);
    this.managed = new Set([ORIGINAL, CANDIDATE, REPLACEMENT]);
    this.c = {id: CHALLENGE, mode: options.mode ?? 'current_session', identity_value: EMAIL,
      created_at: NOW - 10, expires_at: NOW + 290, delivery_status: 'accepted',
      verification_state: 'not_started', verification_operation_id: null,
      expected_auth_user_id: AUTH, expected_user_id: PRINCIPAL,
      initiating_session_id: ORIGINAL, initiating_user_revision: 7,
      verified_session_id: null, verified_amr_at: null, cancelled: false,
      cleanup_state: 'not_started'};
    if (this.c.mode === 'portal_bootstrap') Object.assign(this.c,
      {expected_auth_user_id: null, expected_user_id: null, initiating_session_id: null, initiating_user_revision: null});
  }
  prepare(sql) {return new Statement(this, sql);}
  batch() {return this.unexpected('No batch/principal creation is allowed in this fixture');}
  setClaims(value) {this.claims = clone(value);}
  check(condition, message) {if (!condition) this.unexpected(message);}
  equal(actualValue, expected, message) {
    try {assert.deepEqual(actualValue, expected);} catch {this.unexpected(message);}
  }
  unexpected(message) {this.violations.push(message); throw new Error(message);}
  result(extra = {}) {return {result: {challenge: clone(this.c), ...extra}};}
  async first(sql, values) {
    this.reads.push({sql, values: clone(values), claims: clone(this.claims)});
    for (const [name, signature] of Object.entries(helperSignatures)) {
      if (sql === `SELECT private.privacy_email_${name}(${signature}) AS result`) return this.helper(name, values);
    }
    if (sql === 'SELECT private.is_managed_session(?::uuid,?::uuid) AS allowed') {
      this.check(values[0] === this.claims.sub && values[1] === this.claims.session_id, 'Managed check must use actual installed claims');
      return {allowed: this.managed.has(values[1])};
    }
    if (sql === 'SELECT l.user_id,u.access_status,u.revision FROM private.auth_principal_links l JOIN users u ON u.id=l.user_id WHERE l.auth_user_id=?')
      return clone(this.members.get(values[0]) ?? null);
    if (sql === 'SELECT * FROM auth_sessions WHERE id=?') return clone(this.sessions.get(values[0]) ?? null);
    if (sql === 'SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?')
      return this.members.has(values[0]) ? {user_id: this.members.get(values[0]).user_id} : null;
    if (sql === 'SELECT * FROM users WHERE id=?') {
      this.equal(values, [PRINCIPAL], 'Projection cannot select a different principal');
      return {id: PRINCIPAL, access_status: 'active', revision: 7, full_name: 'Synthetic member', public_id: '100001'};
    }
    if (sql.startsWith('SELECT a.id FROM admin_sessions s JOIN admin_users a ')) return null;
    if (sql === 'SELECT private.session_expiry(?) AS expires_at') return {expires_at: values[0]};
    return this.unexpected('Unexpected query: ' + sql);
  }
  helper(name, values) {
    this.helpers.push({name, values: clone(values), claims: clone(this.claims)});
    this.events.push('helper:' + name);
    this.check(values[0] === CHALLENGE, 'Helper challenge ID must stay captured');
    this.check(values[name === 'prepare' ? 3 : 1] === CONTEXT_HASH, 'Helper receives the context hash, not its raw secret');
    if (this.options.denyHelper === name) throw new Error('privacy_email_denied');
    if (this.options.faultHelper === name) throw new Error(PRIVATE);
    switch (name) {
      case 'prepare': {
        this.equal(values.slice(0, 3), [CHALLENGE, this.c.mode, this.c.mode === 'current_session' ? null : EMAIL], 'Prepare identity/mode is server-owned');
        const created = !this.prepared; this.prepared = true;
        if (created) this.c.delivery_status = 'reserved';
        return this.result({created});
      }
      case 'send_claim':
        this.check(UUID.test(values[2]), 'Send claim requires a server nonce');
        if (this.sendClaim) return this.result({claimed: false});
        this.sendClaim = values[2]; return this.result({claimed: true});
      case 'send_finish':
        this.check(values[2] === this.sendClaim, 'Send finish must retain its exact nonce');
        this.check(['accepted', 'rejected', 'unknown'].includes(values[3]), 'Closed send outcome');
        this.c.delivery_status = values[3]; return this.result();
      case 'verify_claim':
        this.check(UUID.test(values[2]), 'Verification operation must be a UUID');
        this.check(['accepted', 'unknown'].includes(this.c.delivery_status) ||
          this.c.mode === 'portal_bootstrap' && this.c.delivery_status === 'rejected', 'Verify fixture must have an admissible dispatch history');
        if (this.c.verification_operation_id === values[2] || ['verifying', 'unconfirmed', 'verified'].includes(this.c.verification_state)) return this.result({claimed: false});
        this.c.verification_operation_id = values[2]; this.c.verification_state = 'verifying';
        return this.result({claimed: true});
      case 'verify_finish':
        this.check(values[2] === this.c.verification_operation_id, 'Verify finish stays with the admitted operation');
        this.check(['rejected', 'unconfirmed'].includes(values[3]), 'Verify finish cannot manufacture success');
        if (this.c.verification_state !== 'verified') this.c.verification_state = values[3];
        return this.result();
      case 'consume': {
        this.check(values[2] === this.c.verification_operation_id, 'Consume operation remains captured');
        this.check(this.claims.sub === AUTH && this.claims.session_id === CANDIDATE, 'Consume installs the online candidate claims');
        this.c.verification_state = 'verified'; this.c.verified_session_id = CANDIDATE;
        this.c.verified_amr_at = this.options.expectedEvent ?? NOW;
        return this.result({proof: {purpose: PURPOSE, challenge_id: CHALLENGE,
          user_id: PRINCIPAL, auth_user_id: AUTH, initiating_session_id: this.c.initiating_session_id,
          session_id: CANDIDATE, method: 'otp', authenticated_at: this.c.verified_amr_at,
          expires_at: this.c.expires_at, ...this.options.proofOverride}});
      }
      case 'status': return this.result();
      case 'cancel': this.c.cancelled = true; return this.result();
      case 'cleanup_claim':
        this.check(values[2] === OPERATION && UUID.test(values[3]), 'Cleanup binds operation and a fresh nonce');
        if (this.cleanupClaim) return this.result({claimed: false});
        // Return a deliberately permissive claimed row: controller identity
        // rejection tests must exercise actual code, not a fixture SQL policy.
        this.cleanupClaim = values[3]; this.c.cleanup_state = 'claimed'; return this.result({claimed: true});
      case 'cleanup_finish':
        this.check(values[2] === OPERATION && values[3] === this.cleanupClaim, 'Cleanup finish binds the exact claim nonce');
        this.check(['confirmed', 'unconfirmed'].includes(values[4]), 'Closed cleanup outcome');
        this.c.cleanup_state = values[4];
        if (values[4] === 'confirmed') {
          this.check(this.claims.session_id === CANDIDATE, 'Only the recorded candidate can be retired');
          this.sessions.get(CANDIDATE).revoked_at = NOW; this.events.push('exact-local-revocation');
        }
        return this.result();
      default: return this.unexpected('Unapproved helper: ' + name);
    }
  }
  recorded() {
    this.c.verification_state = 'verified'; this.c.verification_operation_id = OPERATION;
    this.c.verified_session_id = CANDIDATE; this.c.verified_amr_at = NOW;
    this.sessions.set(CANDIDATE, projected(CANDIDATE, {auth_at: NOW}));
  }
}

function request(operation, body, {token, method = 'POST', path} = {}) {
  return new Request('https://collect-api.synthetic.invalid' + (path ?? '/v1/privacy/email/' + operation),
    {method, headers: {'Content-Type': 'application/json', ...(token ? {Authorization: 'Bearer ' + token} : {})},
      ...(method === 'GET' ? {} : {body: JSON.stringify(body)})});
}
async function fixture(options, check) {
  const db = new Database(options), calls = [], violations = [];
  const originalClaims = claims(ORIGINAL, {amr: [{method: 'password', timestamp: NOW - 600}]});
  const candidateClaims = claims(CANDIDATE, options.candidateClaims ?? {});
  const originalToken = jwt(originalClaims), candidateToken = jwt(candidateClaims);
  const replacementToken = jwt(claims(REPLACEMENT));
  const identities = new Map([[originalToken, managedUser()], [candidateToken, managedUser(options.candidateUser)], [replacementToken, managedUser()]]);
  const env = {SUPABASE_URL: PROJECT, SUPABASE_PUBLISHABLE_KEY: KEY, DB: db,
    AUTH_MEMBER_REGISTRATION_ENABLED: 'true'};
  const previousFetch = globalThis.fetch, previousNow = Date.now;
  const count = path => calls.filter(call => call.path === path).length;
  const invoke = (operation, body = base(options.mode), settings = {}) => handlePrivacyEmailAuth(
    request(operation, body, {token: body.mode === 'current_session' ? originalToken : undefined, ...settings}), env);
  Date.now = () => NOW * 1000;
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init), url = new URL(req.url);
    const call = {url: req.url, path: url.pathname.replace('/auth/v1', '') + url.search,
      method: req.method, headers: req.headers, init,
      body: init?.body === undefined ? undefined : JSON.parse(init.body)};
    calls.push(call); db.events.push('http:' + call.path);
    if (url.origin !== PROJECT || !url.pathname.startsWith('/auth/v1/')) {
      violations.push('HTTP escaped the fixed synthetic provider'); throw new Error(PRIVATE);
    }
    if (call.path === '/user' && req.method === 'GET') {
      const token = req.headers.get('Authorization')?.slice(7);
      if (options.onUser) {const result = await options.onUser({token, db, originalToken, candidateToken, calls}); if (result) return result;}
      const user = identities.get(token);
      return user ? Response.json(user) : Response.json({error_code: 'invalid_token', msg: PRIVATE}, {status: 401});
    }
    if (call.path === '/otp' && req.method === 'POST') {
      if (options.otpReply) return options.otpReply({db, call});
      return Response.json({});
    }
    if (call.path === '/verify' && req.method === 'POST') {
      if (options.verifyReply) return options.verifyReply({db, call, candidateToken});
      return Response.json({access_token: candidateToken, refresh_token: REFRESH});
    }
    if (call.path === '/logout?scope=local' && req.method === 'POST') {
      if (options.logoutReply) return options.logoutReply({db, call});
      db.managed.delete(CANDIDATE); // Simulate GoTrue row removal before SQL finish.
      return new Response(null, {status: 204});
    }
    violations.push('Unexpected provider request: ' + call.path); throw new Error(PRIVATE);
  };
  try {await check({db, env, calls, count, invoke, originalToken, candidateToken, replacementToken, identities});}
  finally {
    globalThis.fetch = previousFetch; Date.now = previousNow;
    assert.deepEqual(violations, []); assert.deepEqual(db.violations, []);
    for (const call of calls) {
      assert.equal(call.init.redirect, 'error'); assert.ok(call.init.signal instanceof AbortSignal);
      assert.equal(call.headers.get('apikey'), KEY);
      assert.equal(call.headers.get('Content-Type'), 'application/json');
    }
  }
}
const apiError = (status, code) => error => {
  assert.ok(error instanceof ApiError); assert.equal(error.status, status); assert.equal(error.code, code);
  assert.equal(JSON.stringify({message: error.message, code: error.code}).includes(PRIVATE), false); return true;
};
function privateFree(value, tokens = []) {
  const serialized = JSON.stringify(value);
  for (const forbidden of [EMAIL, AUTH, PRINCIPAL, ORIGINAL, CANDIDATE, CODE, REFRESH, PRIVATE, ...tokens])
    assert.equal(serialized.includes(forbidden), false, 'Public metadata leaked a private field');
}
async function unconfirmed(response, tokens = []) {
  assert.equal(response.status, 503); const body = await response.json();
  assert.equal(body.code, 'privacy_email_operation_unknown'); assert.equal(body.outcome, 'unconfirmed');
  assert.equal(body.challenge_id, CHALLENGE); assert.equal(body.challenge_context, CONTEXT);
  assert.equal(body.candidate_cleanup, 'unconfirmed'); privateFree(body, tokens); return body;
}
const verifyBody = (mode = 'current_session') => ({...base(mode), operation_id: OPERATION, code: CODE, captcha_token: 'synthetic-captcha'});

test('privacy email actual controller boundaries and lifecycle', {concurrency: false}, async t => {
  await t.test('actual API dispatches the anonymous namespace before generic session admission', async () => fixture({}, async f => {
    const response = await privacyApi.fetch(request('status', {}), {DB: f.db},
      {waitUntil() {throw new Error('No background task belongs to an invalid request');}});
    assert.equal(response.status, 400); assert.equal((await response.json()).code, 'privacy_email_invalid');
    assert.deepEqual(f.calls, []); assert.deepEqual(f.db.reads, []);
  }));
  await t.test('phone verification and unrelated routes are not intercepted', async () => fixture({}, async f => {
    assert.equal(await f.invoke('verify', {}, {path: '/v1/privacy/phone/verify'}), null);
    assert.equal(await f.invoke('verify', {}, {path: '/v1/auth/verify'}), null);
    assert.deepEqual(f.calls, []); assert.deepEqual(f.db.reads, []);
  }));
  for (const [name, setup] of [
    ['missing original bearer', f => ({token: undefined})],
    ['Admin projected surface', f => {f.db.sessions.get(ORIGINAL).surface = 'admin'; return {};}],
    ['missing immutable member link', f => {f.db.members.delete(AUTH); return {};}],
    ['revoked original managed session', f => {f.db.managed.delete(ORIGINAL); return {};}],
  ]) await t.test(name + ' blocks before reservation or projection', async () => fixture({}, async f => {
    const settings = setup(f);
    await assert.rejects(f.invoke('challenge', base(), settings), apiError(403, 'privacy_email_denied'));
    assert.deepEqual(f.db.helpers, []); assert.deepEqual(f.db.writes, []); assert.equal(f.count('/otp'), 0);
  }));
  await t.test('native derives its confirmed email, preserves CAPTCHA/no-create and never resends a replay', async () => fixture({}, async f => {
    const body = {...base(), captcha_token: 'synthetic-captcha', allow_registration: false, should_create_user: false};
    const response = await f.invoke('challenge', body); assert.equal(response.status, 202);
    const descriptor = await response.json(); assert.equal(descriptor.destination_hint, 's***@example.invalid');
    assert.equal(descriptor.delivery_status, 'accepted'); assert.equal(descriptor.challenge_context, CONTEXT);
    const call = f.calls.find(call => call.path === '/otp');
    assert.deepEqual(call.body, {email: EMAIL, create_user: false, gotrue_meta_security: {captcha_token: 'synthetic-captcha'}});
    assert.equal(call.headers.has('Authorization'), false); assert.equal(Object.hasOwn(call.body, 'channel'), false);
    assert.ok(f.db.events.indexOf('helper:send_claim') < f.db.events.indexOf('http:/otp'));
    assert.equal((await f.invoke('challenge', body)).status, 202); assert.equal(f.count('/otp'), 1);
    assert.deepEqual(f.db.writes, []);
  }));
  await t.test('a lost send-claim race does not dispatch even when prepare created the descriptor', async () => fixture({}, async f => {
    f.db.sendClaim = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    assert.equal((await f.invoke('challenge')).status, 202);
    assert.deepEqual(f.db.helpers.map(call => call.name), ['prepare', 'send_claim']);
    assert.equal(f.count('/otp'), 0);
  }));
  for (const override of [{email: 'other@example.invalid'}, {should_create_user: true}, {allow_registration: true}])
    await t.test('native destination/registration override is refused: ' + Object.keys(override)[0], async () => fixture({}, async f => {
      await assert.rejects(f.invoke('challenge', {...base(), ...override}), apiError(400, 'privacy_email_invalid'));
      assert.deepEqual(f.calls, []); assert.deepEqual(f.db.helpers, []);
    }));
  for (const control of ['\u0000', '\u0085'])
    await t.test('dedicated email locator rejects control ' + control.charCodeAt(0) + ' before DB or provider', async () => fixture({mode: 'portal_bootstrap'}, async f => {
      await assert.rejects(f.invoke('challenge', {...base('portal_bootstrap'), email: 'synthetic' + control + '@example.invalid'}), apiError(400, 'privacy_email_invalid'));
      assert.deepEqual(f.calls, []); assert.deepEqual(f.db.reads, []);
    }));
  await t.test('bootstrap accepted, ineligible, broken-mailer and lost dispatch have identical public challenge/status metadata', async () => {
    const descriptors = [], statuses = [];
    for (const reply of [() => Response.json({}),
      () => Response.json({error_code: 'signup_disabled', msg: PRIVATE}, {status: 422}),
      () => Response.json({error_code: 'unexpected_failure', msg: PRIVATE}, {status: 503}),
      () => {throw new Error(PRIVATE);},
    ]) await fixture({mode: 'portal_bootstrap', otpReply: reply}, async f => {
      const response = await f.invoke('challenge', {...base('portal_bootstrap'), email: '  SYNTHETIC.MEMBER@example.invalid  '});
      assert.equal(response.status, 202); const body = await response.json(); descriptors.push(body);
      assert.equal(body.delivery_status, 'not_disclosed'); privateFree(body);
      assert.equal(f.calls[0].body.create_user, false); assert.equal(f.calls[0].body.email, EMAIL);
      const status = await f.invoke('status', base('portal_bootstrap'));
      statuses.push({status: status.status, body: await status.json()});
      assert.equal(statuses.at(-1).body.delivery_status, 'not_disclosed'); privateFree(statuses.at(-1).body);
      const replay = await f.invoke('challenge', {...base('portal_bootstrap'), email: EMAIL});
      assert.equal(replay.status, 202); assert.deepEqual(await replay.json(), body);
      assert.equal(f.count('/otp'), 1);
      assert.deepEqual(f.db.writes, []);
    });
    for (const descriptor of descriptors) assert.deepEqual(descriptor, descriptors[0]);
    for (const status of statuses) assert.deepEqual(status, statuses[0]);
  });
  await t.test('unknown dispatch retains original IDs and duplicate challenge performs no second send', async () => fixture({
    otpReply: () => {throw new Error(PRIVATE);}}, async f => {
    const body = base();
    await unconfirmed(await f.invoke('challenge', body));
    assert.equal((await f.invoke('challenge', body)).status, 202); assert.equal(f.count('/otp'), 1);
  }));
  await t.test('lost send-claim acknowledgment is unknown and does not call the provider', async () => fixture({faultHelper: 'send_claim'}, async f => {
    await unconfirmed(await f.invoke('challenge')); assert.equal(f.count('/otp'), 0);
  }));
  await t.test('native verification uses retained identity and actual online candidate before projection and consume', async () => fixture({}, async f => {
    const response = await f.invoke('verify', verifyBody()); assert.equal(response.status, 200);
    const body = await response.json(); assert.equal(body.access_token, f.candidateToken); assert.equal(body.refresh_token, REFRESH);
    assert.equal(body.user.id, PRINCIPAL); assert.equal(body.user.auth_user_id, AUTH);
    assert.deepEqual(body.auth_event, {method: 'otp', timestamp: NOW});
    assert.deepEqual(body.purpose_proof, {purpose: PURPOSE, challenge_id: CHALLENGE, user_id: PRINCIPAL,
      auth_user_id: AUTH, initiating_session_id: ORIGINAL, session_id: CANDIDATE, method: 'otp', authenticated_at: NOW, expires_at: NOW + 290});
    const call = f.calls.find(call => call.path === '/verify');
    assert.deepEqual(call.body, {email: EMAIL, token: CODE, type: 'email', gotrue_meta_security: {captcha_token: 'synthetic-captcha'}});
    assert.equal(call.headers.has('Authorization'), false);
    assert.ok(f.db.events.indexOf('helper:verify_claim') < f.db.events.indexOf('http:/verify'));
    assert.ok(f.db.events.indexOf('projection-insert') < f.db.events.indexOf('helper:consume'));
    assert.equal(f.count('/logout?scope=local'), 0);
    const replay = await f.invoke('verify', verifyBody()); assert.equal(replay.status, 200);
    privateFree(await replay.json(), [f.candidateToken]); assert.equal(f.count('/verify'), 1);
  }));
  await t.test('portal candidate succeeds with an existing mapping and no initiating bearer or second code', async () => fixture({mode: 'portal_bootstrap'}, async f => {
    const response = await f.invoke('verify', verifyBody('portal_bootstrap')); assert.equal(response.status, 200);
    const body = await response.json(); assert.equal(body.purpose_proof.initiating_session_id, null);
    assert.equal(body.user.id, PRINCIPAL); assert.equal(f.count('/verify'), 1);
    assert.equal(f.calls.some(call => call.headers.get('Authorization') === 'Bearer ' + f.originalToken), false);
    assert.deepEqual(f.db.writes.map(write => write.sql.startsWith('INSERT INTO auth_sessions')), [true]);
  }));
  await t.test('bootstrap rejected dispatch does not expose a local-only verify shortcut', async () => {
    const outcomes = [];
    for (const rejected of [false, true]) await fixture({mode: 'portal_bootstrap',
      otpReply: () => rejected ? Response.json({error_code: 'signup_disabled', msg: PRIVATE}, {status: 422}) : Response.json({}),
      verifyReply: () => Response.json({error_code: 'otp_expired', msg: PRIVATE}, {status: 400})}, async f => {
      assert.equal((await f.invoke('challenge', {...base('portal_bootstrap'), email: EMAIL})).status, 202);
      const response = await f.invoke('verify', verifyBody('portal_bootstrap'));
      const body = await response.json(); outcomes.push({status: response.status, body});
      assert.equal(f.count('/verify'), 1, 'Both dispatch histories reach the same provider verification contract');
      assert.equal(response.status, 401); privateFree(body); assert.deepEqual(f.db.writes, []);
    });
    assert.deepEqual(outcomes[0], outcomes[1]);
  });
  for (const [name, options, setup] of [
    ['same email, different managed subject', {candidateClaims: {sub: OTHER_AUTH}, candidateUser: {id: OTHER_AUTH}}, f => f.db.members.set(OTHER_AUTH, {user_id: PRINCIPAL, access_status: 'active', revision: 7})],
    ['same managed subject, conflicting canonical mapping', {}, f => {f.db.options.conflict = true;}],
    ['portal has no preexisting immutable mapping', {mode: 'portal_bootstrap'}, f => f.db.members.delete(AUTH)],
    ['candidate confirmed email differs', {candidateUser: {email: 'other@example.invalid'}}, () => {}],
    ['candidate reuses the initiating session', {candidateClaims: {session_id: ORIGINAL}}, () => {}],
  ]) await t.test(name + ' never reaches projection, linking or consume', async () => fixture({...options,
    verifyReply: ({db, candidateToken}) => {
      if (db.options.conflict) db.members.get(AUTH).user_id = OTHER_PRINCIPAL;
      return Response.json({access_token: candidateToken, refresh_token: REFRESH});
    }}, async f => {
      setup(f); await unconfirmed(await f.invoke('verify', verifyBody(options.mode)), [f.candidateToken]);
      assert.deepEqual(f.db.writes, []); assert.equal(f.db.helpers.some(call => call.name === 'consume'), false);
      assert.equal(f.db.reads.some(read => read.sql === 'SELECT user_id FROM private.auth_principal_links WHERE auth_user_id=?'), false);
    }));
  for (const [name, amr] of [
    ['absent', undefined], ['method strings', ['otp']], ['string timestamp', [{method: 'otp', timestamp: String(NOW)}]],
    ['before challenge', [{method: 'otp', timestamp: NOW - 11}]], ['future', [{method: 'otp', timestamp: NOW + 1}]],
    ['OAuth instead of OTP', [{method: 'oauth', timestamp: NOW}]],
    ['MFA instead of OTP', [{method: 'totp', timestamp: NOW}]],
  ]) await t.test('fresh iat cannot replace valid OTP evidence: ' + name, async () => fixture({candidateClaims: {amr, iat: NOW}}, async f => {
    await unconfirmed(await f.invoke('verify', verifyBody()), [f.candidateToken]);
    assert.deepEqual(f.db.writes, []); assert.equal(f.db.helpers.some(call => call.name === 'consume'), false);
    assert.equal(f.count('/logout?scope=local'), 0, 'Unvalidated candidate cannot authorize a guessed cleanup');
  }));
  await t.test('earliest usable OTP event wins despite malformed/MFA entries', async () => fixture({expectedEvent: NOW - 5,
    candidateClaims: {amr: [null, 'otp', {method: 'totp', timestamp: NOW - 7}, {method: 'otp', timestamp: NOW}, {method: 'otp', timestamp: NOW - 5}]}}, async f => {
    const response = await f.invoke('verify', verifyBody()); assert.equal(response.status, 200);
    assert.deepEqual((await response.json()).auth_event, {method: 'otp', timestamp: NOW - 5});
  }));
  for (const [name, fault] of [['changed account revision', 'revision'], ['revoked initiating session during verification', 'revoked']])
    await t.test(name + ' rechecks the captured original before projection', async () => fixture({
      verifyReply: ({db, candidateToken}) => {
        if (fault === 'revision') db.members.get(AUTH).revision++;
        else db.sessions.get(ORIGINAL).revoked_at = NOW;
        return Response.json({access_token: candidateToken, refresh_token: REFRESH});
      }}, async f => {
      await unconfirmed(await f.invoke('verify', verifyBody()), [f.candidateToken]);
      assert.deepEqual(f.db.writes, []); assert.equal(f.db.helpers.some(call => call.name === 'consume'), false);
    }));
  await t.test('final SQL consume denial returns unknown and only retires the captured unadopted candidate', async () => fixture({denyHelper: 'consume'}, async f => {
    await unconfirmed(await f.invoke('verify', verifyBody()), [f.candidateToken]);
    const logout = f.calls.filter(call => call.path === '/logout?scope=local'); assert.equal(logout.length, 1);
    assert.equal(logout[0].headers.get('Authorization'), 'Bearer ' + f.candidateToken);
    assert.equal(f.db.sessions.get(ORIGINAL).revoked_at, null);
  }));
  await t.test('original revocation after projection still blocks final consume and return of candidate tokens', async () => fixture({
    afterProjection: db => {db.sessions.get(ORIGINAL).revoked_at = NOW;}}, async f => {
    await unconfirmed(await f.invoke('verify', verifyBody()), [f.candidateToken]);
    assert.equal(f.db.writes.length, 1); assert.equal(f.db.helpers.some(call => call.name === 'consume'), false);
    const logout = f.calls.find(call => call.path === '/logout?scope=local');
    assert.equal(logout.headers.get('Authorization'), 'Bearer ' + f.candidateToken);
  }));
  await t.test('malformed session DTO cannot reach candidate projection or disclose a partial token', async () => fixture({
    verifyReply: ({candidateToken}) => Response.json({access_token: candidateToken, refresh_token: ' '})}, async f => {
    await unconfirmed(await f.invoke('verify', verifyBody()), [f.candidateToken]);
    assert.deepEqual(f.db.writes, []); assert.equal(f.db.helpers.some(call => call.name === 'consume'), false);
  }));
  for (const [name, reply, status] of [
    ['definite wrong code', () => Response.json({error_code: 'otp_expired', msg: PRIVATE}, {status: 400}), 401],
    ['rate limit', () => Response.json({error_code: 'over_request_rate_limit', msg: PRIVATE}, {status: 429}), 429],
    ['lost verify response', () => {throw new Error(PRIVATE);}, 503],
  ]) await t.test(name + ' has a durable receipt and no automatic repeated verify', async () => fixture({verifyReply: reply}, async f => {
    const response = await f.invoke('verify', verifyBody()); assert.equal(response.status, status);
    const body = await response.json(); privateFree(body, [f.candidateToken]); assert.equal(body.operation_id, OPERATION);
    if (status === 503) {
      assert.equal(body.outcome, 'unconfirmed'); assert.equal(body.candidate_cleanup, 'unconfirmed');
      assert.equal(f.count('/logout?scope=local'), 0, 'A lost verify body gives no exact cleanup token');
    }
    await f.invoke('verify', verifyBody()); assert.equal(f.count('/verify'), 1); assert.deepEqual(f.db.writes, []);
  }));
  await t.test('anonymous status is read-only metadata, even for recorded verification with lost tokens', async () => fixture({mode: 'portal_bootstrap'}, async f => {
    f.db.recorded();
    const response = await f.invoke('status', {...base('portal_bootstrap'), operation_id: OPERATION}); assert.equal(response.status, 200);
    const body = await response.json(); assert.equal(body.verification_state, 'verified'); privateFree(body, [f.candidateToken]);
    assert.deepEqual(f.db.helpers.map(call => call.name), ['status']); assert.deepEqual(f.calls, []); assert.deepEqual(f.db.writes, []);
  }));
  await t.test('cancel without a received candidate never guesses a provider session or reports cleanup', async () => fixture({}, async f => {
    f.db.c.verification_state = 'unconfirmed'; f.db.c.verification_operation_id = OPERATION;
    const response = await f.invoke('cancel', {...base(), operation_id: OPERATION});
    const body = await response.json(); assert.equal(body.cancelled, true); assert.equal(body.candidate_cleanup, 'unconfirmed');
    assert.equal(f.count('/logout?scope=local'), 0); assert.deepEqual(f.db.writes, []);
  }));
  await t.test('ordinary native status/cancel retain original authority when no exact candidate is supplied', async () => fixture({}, async f => {
    f.db.managed.delete(ORIGINAL);
    for (const operation of ['status', 'cancel'])
      await assert.rejects(f.invoke(operation, {...base(), operation_id: OPERATION}), apiError(403, 'privacy_email_denied'));
    assert.deepEqual(f.db.helpers, []); assert.equal(f.count('/logout?scope=local'), 0);
  }));
  await t.test('exact recorded candidate can be cleaned after original revocation; 204 precedes exact local confirmation', async () => fixture({
    candidateClaims: {amr: [{method: 'otp', timestamp: NOW - 400}]}}, async f => {
    f.db.recorded(); f.db.sessions.get(ORIGINAL).revoked_at = NOW; f.db.managed.delete(ORIGINAL);
    f.db.members.get(AUTH).revision++; f.db.members.get(AUTH).access_status = 'blocked';
    f.identities.set(f.candidateToken, managedUser({email: 'changed-contact@example.invalid', email_confirmed_at: null}));
    f.db.c.cancelled = true; f.db.c.created_at = NOW - 410; f.db.c.expires_at = NOW - 110;
    f.db.c.verified_amr_at = NOW - 400; f.db.sessions.get(CANDIDATE).auth_at = NOW - 400;
    const response = await f.invoke('cancel', {...base(), operation_id: OPERATION, candidate_access_token: f.candidateToken});
    assert.equal(response.status, 200); const body = await response.json(); assert.equal(body.candidate_cleanup, 'confirmed'); privateFree(body, [f.candidateToken]);
    assert.equal(f.calls.filter(call => call.path === '/user').length, 1);
    assert.equal(f.calls[0].headers.get('Authorization'), 'Bearer ' + f.candidateToken);
    assert.equal(f.calls.find(call => call.path === '/logout?scope=local').headers.get('Authorization'), 'Bearer ' + f.candidateToken);
    assert.equal(f.db.managed.has(CANDIDATE), false); assert.equal(f.db.sessions.get(CANDIDATE).revoked_at, NOW);
    assert.ok(f.db.events.indexOf('http:/logout?scope=local') < f.db.events.indexOf('helper:cleanup_finish'));
    assert.ok(f.db.events.indexOf('helper:cleanup_finish') < f.db.events.indexOf('exact-local-revocation'));
  }));
  for (const tokenKind of ['originalToken', 'replacementToken'])
    await t.test('cleanup refuses substitution of ' + tokenKind + ' even with a permissive claimed helper row', async () => fixture({}, async f => {
      f.db.recorded();
      await unconfirmed(await f.invoke('cancel', {...base(), operation_id: OPERATION, candidate_access_token: f[tokenKind]}), [f.candidateToken]);
      assert.equal(f.count('/logout?scope=local'), 0); assert.equal(f.db.sessions.get(ORIGINAL).revoked_at, null);
      assert.equal(f.db.sessions.get(CANDIDATE).revoked_at, null);
      assert.equal(f.db.helpers.find(call => call.name === 'cleanup_finish').values.at(-1), 'unconfirmed');
    }));
  for (const [name, reply, faultHelper] of [
    ['provider refuses logout', () => Response.json({error_code: 'denied', msg: PRIVATE}, {status: 401}), undefined],
    ['logout response is lost', () => {throw new Error(PRIVATE);}, undefined],
    ['cleanup finish acknowledgement is lost', undefined, 'cleanup_finish'],
  ]) await t.test(name + ' never claims confirmed cleanup or retries logout', async () => fixture({logoutReply: reply, faultHelper}, async f => {
    f.db.recorded(); const body = {...base(), operation_id: OPERATION, candidate_access_token: f.candidateToken};
    await unconfirmed(await f.invoke('cancel', body), [f.candidateToken]);
    await f.invoke('cancel', body); assert.equal(f.count('/logout?scope=local'), 1);
    assert.equal(f.db.sessions.get(CANDIDATE).revoked_at, null);
  }));
});
